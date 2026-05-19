// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVRFConsumer} from "./interfaces/IVRFConsumer.sol";
import {IRandomnessConsumer} from "./interfaces/IRandomnessConsumer.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

interface IReferral {
    function recordTicketPurchase(
        address buyer,
        uint256 ticketPrice,
        bytes32 referralCode
    ) external returns (uint256 commission);
}

contract Lottery is IRandomnessConsumer, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========== Enums ==========

    enum RoundStatus {
        OPEN,       // Accepting tickets
        DRAWING,    // VRF requested, awaiting callback
        COMPLETED,  // Winners selected, prizes ready to claim
        CANCELLED   // Round cancelled, refunds available
    }

    // ========== Structs ==========

    struct Round {
        uint256 id;
        address token;          // address(0) = ETH
        uint256 ticketPrice;    // Price per ticket (in token decimals or wei)
        uint256 maxTickets;     // 0 = unlimited
        uint256 startTime;
        uint256 endTime;
        uint256 totalTicketsSold;
        uint256 prizePool;      // totalTicketsSold * ticketPrice
        uint256 requestId;      // VRF request ID for this round
        uint32  numWinners;     // How many winners to select
        RoundStatus status;
        bool    prizesClaimable; // Set to true after winners determined
    }

    // ========== State Variables ==========

    IVRFConsumer public vrfConsumer;
    ITreasury   public treasury;
    IReferral   public referral;

    uint256 public currentRoundId;
    uint256 public vrfTimeout = 24 hours; // Max wait for VRF before retry

    // Round storage
    mapping(uint256 => Round) private _rounds;

    // Per-round ticket holders: roundId => ticketIndex => buyerAddress
    mapping(uint256 => mapping(uint256 => address)) private _ticketHolders;
    // Per-round ticket counts: roundId => buyer => count
    mapping(uint256 => mapping(address => uint256)) private _ticketCounts;
    // Refund tracking for cancelled rounds
    mapping(uint256 => mapping(address => bool)) public refunded;

    // Winners: roundId => address[]
    mapping(uint256 => address[]) private _winners;
    // Payouts: roundId => uint256[] (parallel to winners)
    mapping(uint256 => uint256[]) private _payouts;
    // Prize claimed: roundId => winner => bool
    mapping(uint256 => mapping(address => bool)) public prizeClaimed;

    // Reverse mapping: VRF requestId => roundId
    mapping(uint256 => uint256) private _requestToRound;

    // ========== Events ==========

    event RoundCreated(
        uint256 indexed roundId,
        address indexed token,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 startTime,
        uint256 endTime,
        uint32  numWinners
    );
    event TicketsPurchased(
        uint256 indexed roundId,
        address indexed buyer,
        uint256 numTickets,
        uint256 totalCost,
        bytes32 referralCode
    );
    event DrawRequested(uint256 indexed roundId, uint256 indexed requestId);
    event DrawCompleted(
        uint256 indexed roundId,
        uint256 indexed requestId,
        uint256[] randomWords,
        address[] winners,
        uint256[] payouts
    );
    event VRFTimeoutRetry(uint256 indexed roundId, uint256 oldRequestId, uint256 newRequestId);
    event RoundCancelled(uint256 indexed roundId);
    event RefundClaimed(uint256 indexed roundId, address indexed player, uint256 amount);
    event PrizeClaimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event TreasuryFeePaid(uint256 indexed roundId, uint256 houseEdgeAmount, uint256 referralCommission);

    // ========== Modifiers ==========

    modifier onlyValidRound(uint256 roundId) {
        require(roundId > 0 && roundId <= currentRoundId, "Invalid round");
        _;
    }

    // ========== Constructor ==========

    constructor(address _vrfConsumer, address _treasury) Ownable(msg.sender) {
        require(_vrfConsumer != address(0), "Zero VRFConsumer");
        require(_treasury != address(0), "Zero Treasury");
        vrfConsumer = IVRFConsumer(_vrfConsumer);
        treasury = ITreasury(_treasury);
    }

    // ========== Admin Functions ==========

    function setVRFConsumer(address _vrfConsumer) external onlyOwner {
        require(_vrfConsumer != address(0), "Zero address");
        vrfConsumer = IVRFConsumer(_vrfConsumer);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Zero address");
        treasury = ITreasury(_treasury);
    }

    function setReferral(address _referral) external onlyOwner {
        referral = IReferral(_referral);
    }

    function setVRFTimeout(uint256 _vrfTimeout) external onlyOwner {
        vrfTimeout = _vrfTimeout;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function createRound(
        address token,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 duration,
        uint32  numWinners
    ) external onlyOwner whenNotPaused returns (uint256 roundId) {
        require(ticketPrice > 0, "Ticket price zero");
        require(numWinners >= 1, "Need >= 1 winner");
        require(numWinners <= 100, "Too many winners");
        require(
            maxTickets == 0 || maxTickets >= numWinners,
            "Max tickets < winners"
        );
        require(duration >= 1 hours && duration <= 90 days, "Bad duration");

        (uint256 minBet, uint256 maxBet) = treasury.getBetLimits(token);
        require(ticketPrice >= minBet, "Below min bet");
        if (maxBet > 0) {
            require(ticketPrice <= maxBet, "Exceeds max bet");
        }

        currentRoundId++;
        roundId = currentRoundId;
        uint256 startTime_ = block.timestamp;
        uint256 endTime_ = startTime_ + duration;

        Round storage r = _rounds[roundId];
        r.id = roundId;
        r.token = token;
        r.ticketPrice = ticketPrice;
        r.maxTickets = maxTickets;
        r.startTime = startTime_;
        r.endTime = endTime_;
        r.numWinners = numWinners;
        r.status = RoundStatus.OPEN;

        emit RoundCreated(roundId, token, ticketPrice, maxTickets, startTime_, endTime_, numWinners);
    }

    function cancelRound(uint256 roundId) external onlyOwner onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.OPEN, "Not open");

        r.status = RoundStatus.CANCELLED;
        emit RoundCancelled(roundId);
    }

    // ========== Player Functions ==========

    function buyTicket(
        uint256 roundId,
        uint256 numTickets,
        bytes32 referralCode
    ) external payable nonReentrant whenNotPaused onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.OPEN, "Round not open");
        require(block.timestamp >= r.startTime, "Not started");
        require(block.timestamp < r.endTime, "Round ended");
        require(numTickets > 0, "Zero tickets");
        require(numTickets <= 100, "Too many tickets");
        if (r.maxTickets > 0) {
            require(r.totalTicketsSold + numTickets <= r.maxTickets, "Exceeds max tickets");
        }

        uint256 totalCost = r.ticketPrice * numTickets;

        if (r.token == address(0)) {
            require(msg.value == totalCost, "Wrong ETH amount");
        } else {
            require(msg.value == 0, "ETH not accepted");
            IERC20(r.token).safeTransferFrom(msg.sender, address(this), totalCost);
        }

        // Assign ticket indices to buyer
        uint256 startIdx = r.totalTicketsSold;
        for (uint256 i = 0; i < numTickets; i++) {
            _ticketHolders[roundId][startIdx + i] = msg.sender;
        }
        _ticketCounts[roundId][msg.sender] += numTickets;
        r.totalTicketsSold += numTickets;
        r.prizePool += totalCost;

        // Process referral
        bytes32 refCode = referralCode;
        if (refCode != bytes32(0) && address(referral) != address(0)) {
            referral.recordTicketPurchase(msg.sender, r.ticketPrice, refCode);
        }

        emit TicketsPurchased(roundId, msg.sender, numTickets, totalCost, refCode);
    }

    function triggerDraw(uint256 roundId) external onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.OPEN, "Not open");
        require(block.timestamp >= r.endTime, "Round not ended");

        if (r.totalTicketsSold == 0) {
            r.status = RoundStatus.CANCELLED;
            emit RoundCancelled(roundId);
            return;
        }

        r.status = RoundStatus.DRAWING;
        uint256 requestId = vrfConsumer.requestRandomness(1);
        r.requestId = requestId;
        _requestToRound[requestId] = roundId;

        emit DrawRequested(roundId, requestId);
    }

    function retryDraw(uint256 roundId) external onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.DRAWING, "Not in drawing");
        require(block.timestamp >= r.endTime + vrfTimeout, "VRF timeout not reached");

        uint256 oldRequestId = r.requestId;
        delete _requestToRound[oldRequestId];

        uint256 newRequestId = vrfConsumer.retryRequest(oldRequestId);
        r.requestId = newRequestId;
        _requestToRound[newRequestId] = roundId;

        emit VRFTimeoutRetry(roundId, oldRequestId, newRequestId);
    }

    // ========== VRF Callback (IRandomnessConsumer) ==========

    function onRandomnessFulfilled(uint256 requestId, uint256[] calldata randomWords) external override {
        require(msg.sender == address(vrfConsumer), "Not VRF consumer");

        uint256 roundId = _requestToRound[requestId];
        require(roundId > 0, "Unknown request");

        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.DRAWING, "Not in drawing");

        uint256 randomWord = randomWords[0];
        _completeDraw(roundId, randomWord, randomWords);
    }

    // ========== Internal: Draw Completion ==========

    function _selectWinners(
        uint256 randomWord,
        uint256 total,
        uint32 nWinners,
        uint256 roundId
    ) internal view returns (address[] memory selectedWinners) {
        selectedWinners = new address[](nWinners);
        uint256[] memory pickedIndices = new uint256[](nWinners);
        uint256 seed = randomWord;

        for (uint32 i = 0; i < nWinners; i++) {
            seed = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 candidateIdx = seed % total;

            uint256 attempts = 0;
            bool duplicate;
            do {
                duplicate = false;
                for (uint32 j = 0; j < i; j++) {
                    if (pickedIndices[j] == candidateIdx) {
                        duplicate = true;
                        break;
                    }
                }
                if (duplicate) {
                    seed = uint256(keccak256(abi.encodePacked(seed, attempts)));
                    candidateIdx = seed % total;
                    attempts++;
                }
            } while (duplicate && attempts < 100);

            pickedIndices[i] = candidateIdx;
            selectedWinners[i] = _ticketHolders[roundId][candidateIdx];
        }
    }

    function _completeDraw(uint256 roundId, uint256 randomWord, uint256[] memory allRandomWords) internal {
        Round storage r = _rounds[roundId];
        uint256 total = r.totalTicketsSold;
        uint32 nWinners = r.numWinners;
        if (nWinners > total) {
            nWinners = uint32(total);
        }

        address[] memory selectedWinners = _selectWinners(randomWord, total, nWinners, roundId);
        uint256[] memory selectedPayouts = new uint256[](nWinners);

        uint256 houseEdgeBps_ = treasury.houseEdgeBps();
        uint256 houseFee = (r.prizePool * houseEdgeBps_) / 10_000;
        uint256 winnerPool = r.prizePool - houseFee;
        uint256 payoutPerWinner = winnerPool / nWinners;

        for (uint32 i = 0; i < nWinners; i++) {
            selectedPayouts[i] = payoutPerWinner;
        }

        _winners[roundId] = selectedWinners;
        _payouts[roundId] = selectedPayouts;
        r.status = RoundStatus.COMPLETED;
        r.prizesClaimable = true;

        if (houseFee > 0) {
            if (r.token == address(0)) {
                treasury.depositLiquidity{value: houseFee}(address(0), houseFee);
            } else {
                IERC20(r.token).forceApprove(address(treasury), houseFee);
                treasury.depositLiquidity(r.token, houseFee);
            }
        }

        emit DrawCompleted(roundId, r.requestId, allRandomWords, selectedWinners, selectedPayouts);
        emit TreasuryFeePaid(roundId, houseFee, 0);
    }

    // ========== Prize & Refund Claims ==========

    function claimPrize(uint256 roundId) external nonReentrant onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.COMPLETED, "Not completed");
        require(r.prizesClaimable, "Prizes not claimable");

        // Find if msg.sender is a winner
        address[] storage roundWinners = _winners[roundId];
        uint256[] storage roundPayouts = _payouts[roundId];
        bool found = false;
        uint256 payout = 0;

        for (uint256 i = 0; i < roundWinners.length; i++) {
            if (roundWinners[i] == msg.sender && !prizeClaimed[roundId][msg.sender]) {
                found = true;
                payout = roundPayouts[i];
                break;
            }
        }

        require(found, "Not a winner or already claimed");
        prizeClaimed[roundId][msg.sender] = true;

        if (r.token == address(0)) {
            (bool sent,) = msg.sender.call{value: payout}("");
            require(sent, "ETH send failed");
        } else {
            IERC20(r.token).safeTransfer(msg.sender, payout);
        }

        emit PrizeClaimed(roundId, msg.sender, payout);
    }

    function claimRefund(uint256 roundId) external nonReentrant onlyValidRound(roundId) {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.CANCELLED, "Not cancelled");

        uint256 ticketCount = _ticketCounts[roundId][msg.sender];
        require(ticketCount > 0, "No tickets");
        require(!refunded[roundId][msg.sender], "Already refunded");

        refunded[roundId][msg.sender] = true;
        uint256 refundAmount = ticketCount * r.ticketPrice;

        if (r.token == address(0)) {
            (bool sent,) = msg.sender.call{value: refundAmount}("");
            require(sent, "ETH refund failed");
        } else {
            IERC20(r.token).safeTransfer(msg.sender, refundAmount);
        }

        emit RefundClaimed(roundId, msg.sender, refundAmount);
    }

    // ========== View Functions ==========

    function getRound(uint256 roundId) external view onlyValidRound(roundId)
        returns (Round memory)
    {
        return _rounds[roundId];
    }

    function getTicketHolder(uint256 roundId, uint256 index) external view
        returns (address)
    {
        return _ticketHolders[roundId][index];
    }

    function getTicketCount(uint256 roundId, address buyer) external view
        returns (uint256)
    {
        return _ticketCounts[roundId][buyer];
    }

    function getWinners(uint256 roundId) external view
        returns (address[] memory)
    {
        return _winners[roundId];
    }

    function getPayouts(uint256 roundId) external view
        returns (uint256[] memory)
    {
        return _payouts[roundId];
    }

    function getRoundStatus(uint256 roundId) external view
        returns (RoundStatus)
    {
        return _rounds[roundId].status;
    }

    function isWinner(uint256 roundId, address player) external view
        returns (bool)
    {
        address[] storage roundWinners = _winners[roundId];
        for (uint256 i = 0; i < roundWinners.length; i++) {
            if (roundWinners[i] == player) return true;
        }
        return false;
    }

    /// @notice Check if a round's prizes can be claimed
    function canClaimPrize(uint256 roundId, address player) external view
        returns (bool)
    {
        if (!_rounds[roundId].prizesClaimable) return false;
        if (prizeClaimed[roundId][player]) return false;
        address[] storage roundWinners = _winners[roundId];
        for (uint256 i = 0; i < roundWinners.length; i++) {
            if (roundWinners[i] == player) return true;
        }
        return false;
    }

    /// @notice Get total tickets an address owns in a round
    function getUserTicketCount(uint256 roundId, address user) external view
        returns (uint256)
    {
        return _ticketCounts[roundId][user];
    }

    // ========== Emergency ==========

    /// @notice Recover funds sent to contract outside normal flow (onlyOwner)
    function recoverStuckFunds(address token, address to) external onlyOwner {
        require(to != address(0), "Zero address");
        uint256 amount;
        if (token == address(0)) {
            amount = address(this).balance;
            (bool sent,) = to.call{value: amount}("");
            require(sent, "ETH recovery failed");
        } else {
            amount = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ========== Receive ==========

    receive() external payable {
        // Accept ETH only from treasury or trusted sources
    }
}
