// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Referral is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== State ==========

    address public lottery;

    // referrer address => referral code
    mapping(address => bytes32) public referralCodes;
    // referral code => referrer address
    mapping(bytes32 => address) public codeToReferrer;
    // referrer => token => pending commission
    mapping(address => mapping(address => uint256)) public pendingCommissions;
    // referrer => token => total earned
    mapping(address => mapping(address => uint256)) public totalEarned;
    // referrer => token => total claimed
    mapping(address => mapping(address => uint256)) public totalClaimed;
    // user => referrer who referred them
    mapping(address => address) public referredBy;

    // Commission rate in basis points of ticket price
    // e.g., 100 = 1% of ticket price goes to referrer
    uint256 public commissionBps = 100; // 1%

    // ========== Events ==========

    event ReferralRegistered(address indexed referrer, bytes32 code);
    event CommissionEarned(
        address indexed referrer,
        address indexed buyer,
        address token,
        uint256 ticketPrice,
        uint256 commission
    );
    event CommissionClaimed(
        address indexed referrer,
        address indexed token,
        uint256 amount
    );
    event CommissionRateUpdated(uint256 oldRate, uint256 newRate);

    // ========== Modifiers ==========

    modifier onlyLottery() {
        require(msg.sender == lottery, "Only lottery");
        _;
    }

    // ========== Constructor ==========

    constructor() Ownable(msg.sender) {}

    // ========== Admin ==========

    function setLottery(address _lottery) external onlyOwner {
        require(_lottery != address(0), "Zero address");
        lottery = _lottery;
    }

    function setCommissionBps(uint256 _bps) external onlyOwner {
        require(_bps <= 2000, "Max 20%"); // sanity cap
        uint256 oldRate = commissionBps;
        commissionBps = _bps;
        emit CommissionRateUpdated(oldRate, _bps);
    }

    // ========== Referral Registration ==========

    function registerReferral(bytes32 code) external {
        require(code != bytes32(0), "Code cannot be empty");
        require(codeToReferrer[code] == address(0), "Code already taken");
        require(referralCodes[msg.sender] == bytes32(0), "Already registered");

        referralCodes[msg.sender] = code;
        codeToReferrer[code] = msg.sender;

        emit ReferralRegistered(msg.sender, code);
    }

    // ========== Lottery Callback ==========

    function recordTicketPurchase(
        address buyer,
        uint256 totalCost,
        bytes32 referralCode
    ) external onlyLottery returns (uint256 commission) {
        if (referralCode == bytes32(0)) return 0;

        address referrer = codeToReferrer[referralCode];
        if (referrer == address(0)) return 0;
        if (referrer == buyer) return 0; // no self-referral

        // Record who referred this buyer (first referrer wins)
        if (referredBy[buyer] == address(0)) {
            referredBy[buyer] = referrer;
        } else {
            referrer = referredBy[buyer];
        }

        commission = (totalCost * commissionBps) / 10_000;
        // Commission is tracked in ETH (address(0) token)
        pendingCommissions[referrer][address(0)] += commission;
        totalEarned[referrer][address(0)] += commission;

        emit CommissionEarned(referrer, buyer, address(0), totalCost, commission);
        return commission;
    }

    // ========== Claim ==========

    function claimCommission(address token) external nonReentrant {
        uint256 amount = pendingCommissions[msg.sender][token];
        require(amount > 0, "No pending commission");

        pendingCommissions[msg.sender][token] = 0;
        totalClaimed[msg.sender][token] += amount;

        // Commission is paid from this contract's balance
        // Treasury should fund this contract
        if (token == address(0)) {
            (bool sent,) = msg.sender.call{value: amount}("");
            require(sent, "ETH send failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit CommissionClaimed(msg.sender, token, amount);
    }

    // ========== View ==========

    function getReferralCode(address referrer) external view returns (bytes32) {
        return referralCodes[referrer];
    }

    function getReferrer(bytes32 code) external view returns (address) {
        return codeToReferrer[code];
    }

    function getPendingCommission(address referrer, address token)
        external
        view
        returns (uint256)
    {
        return pendingCommissions[referrer][token];
    }

    // ========== Emergency ==========

    receive() external payable {
        // Accept ETH to fund commissions
    }

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
}
