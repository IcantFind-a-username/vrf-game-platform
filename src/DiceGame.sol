// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVRFConsumer} from "./interfaces/IVRFConsumer.sol";
import {IRandomnessConsumer} from "./interfaces/IRandomnessConsumer.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

interface IAchievementNFT {
    function mintFirstWin(address player) external returns (uint256);
    function hasFirstWinAchievement(address player) external view returns (bool);
}

/**
 * @title DiceGame
 * @notice Dice betting game integrated with VRFConsumer, Treasury, and optional commit-reveal.
 */
contract DiceGame is Ownable, ReentrancyGuard, IRandomnessConsumer {
    address public constant NATIVE = address(0);

    struct Bet {
        address player;
        address token;
        uint256 stake;
        uint8 guess;
        uint256 treasuryBetId;
        bool settled;
        bool won;
        uint8 result;

        // Commit-reveal fields
        bool isCommitReveal;
        bytes32 commitment;
        bool randomFulfilled;
        uint256 randomWord;
        uint256 revealDeadline;
    }

    IVRFConsumer public vrfConsumer;
    ITreasury public treasury;
    IAchievementNFT public achievementNFT;

    uint256 public revealTimeout = 1 hours;

    mapping(uint256 => Bet) public bets;
    mapping(address => uint256[]) public playerRequests;

    event DiceRollRequested(
        uint256 indexed requestId,
        uint256 indexed treasuryBetId,
        address indexed player,
        uint8 guess,
        uint256 stake
    );

    event DiceRollCommitted(
        uint256 indexed requestId,
        uint256 indexed treasuryBetId,
        address indexed player,
        bytes32 commitment,
        uint256 stake,
        uint256 revealDeadline
    );

    event DiceRandomnessReady(
        uint256 indexed requestId,
        address indexed player,
        uint256 revealDeadline
    );

    event DiceRollRevealed(
        uint256 indexed requestId,
        address indexed player,
        uint8 guess
    );

    event DiceRollForfeited(
        uint256 indexed requestId,
        address indexed player
    );

    event DiceRollSettled(
        uint256 indexed requestId,
        uint256 indexed treasuryBetId,
        address indexed player,
        uint8 guess,
        uint8 result,
        bool won,
        uint256 payout
    );

    constructor(
        address initialOwner,
        address _vrfConsumer,
        address _treasury,
        address _achievementNFT
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner");
        require(_vrfConsumer != address(0), "Invalid VRF consumer");
        require(_treasury != address(0), "Invalid treasury");
        require(_achievementNFT != address(0), "Invalid achievement NFT");

        vrfConsumer = IVRFConsumer(_vrfConsumer);
        treasury = ITreasury(_treasury);
        achievementNFT = IAchievementNFT(_achievementNFT);
    }

    /**
     * @notice Simple dice mode. Player directly reveals the guess when placing the bet.
     * @param guess Player's selected number from 1 to 6.
     */
    function rollDice(uint8 guess) external payable nonReentrant returns (uint256 requestId) {
        require(guess >= 1 && guess <= 6, "Guess must be between 1 and 6");
        require(msg.value > 0, "Stake must be greater than zero");

        uint256 stake = msg.value;
        uint256 maxPayout = treasury.quotePayout(stake * 6);

        uint256 treasuryBetId = treasury.openBet{value: stake}(
            msg.sender,
            NATIVE,
            stake,
            maxPayout
        );

        requestId = vrfConsumer.requestRandomness(1);

        bets[requestId] = Bet({
            player: msg.sender,
            token: NATIVE,
            stake: stake,
            guess: guess,
            treasuryBetId: treasuryBetId,
            settled: false,
            won: false,
            result: 0,
            isCommitReveal: false,
            commitment: bytes32(0),
            randomFulfilled: false,
            randomWord: 0,
            revealDeadline: 0
        });

        playerRequests[msg.sender].push(requestId);

        emit DiceRollRequested(
            requestId,
            treasuryBetId,
            msg.sender,
            guess,
            stake
        );
    }

    /**
     * @notice Commit-reveal mode step 1.
     * @dev commitment should be keccak256(abi.encodePacked(player, guess, salt)).
     *      The guess is hidden until revealRoll().
     */
    function commitRoll(bytes32 commitment)
        external
        payable
        nonReentrant
        returns (uint256 requestId)
    {
        require(commitment != bytes32(0), "Invalid commitment");
        require(msg.value > 0, "Stake must be greater than zero");

        uint256 stake = msg.value;
        uint256 maxPayout = treasury.quotePayout(stake * 6);

        uint256 treasuryBetId = treasury.openBet{value: stake}(
            msg.sender,
            NATIVE,
            stake,
            maxPayout
        );

        requestId = vrfConsumer.requestRandomness(1);

        uint256 revealDeadline = block.timestamp + revealTimeout;

        bets[requestId] = Bet({
            player: msg.sender,
            token: NATIVE,
            stake: stake,
            guess: 0,
            treasuryBetId: treasuryBetId,
            settled: false,
            won: false,
            result: 0,
            isCommitReveal: true,
            commitment: commitment,
            randomFulfilled: false,
            randomWord: 0,
            revealDeadline: revealDeadline
        });

        playerRequests[msg.sender].push(requestId);

        emit DiceRollCommitted(
            requestId,
            treasuryBetId,
            msg.sender,
            commitment,
            stake,
            revealDeadline
        );
    }

    /**
     * @notice Commit-reveal mode step 2.
     * @param requestId The VRF request id returned by commitRoll().
     * @param guess Player's original guess from 1 to 6.
     * @param salt Secret salt used to generate the original commitment.
     */
    function revealRoll(
        uint256 requestId,
        uint8 guess,
        bytes32 salt
    ) external nonReentrant {
        require(guess >= 1 && guess <= 6, "Guess must be between 1 and 6");

        Bet storage bet = bets[requestId];

        require(bet.player != address(0), "Bet does not exist");
        require(bet.isCommitReveal, "Not commit-reveal bet");
        require(msg.sender == bet.player, "Only player can reveal");
        require(!bet.settled, "Bet already settled");
        require(bet.randomFulfilled, "Randomness not ready");
        require(block.timestamp <= bet.revealDeadline, "Reveal deadline passed");

        bytes32 computedCommitment = keccak256(
            abi.encodePacked(msg.sender, guess, salt)
        );

        require(computedCommitment == bet.commitment, "Invalid reveal");

        bet.guess = guess;

        emit DiceRollRevealed(requestId, msg.sender, guess);

        uint8 result = uint8((bet.randomWord % 6) + 1);
        _settleBet(requestId, result);
    }

    /**
     * @notice If a commit-reveal player refuses to reveal after randomness is ready,
     *         anyone can forfeit the bet after the reveal deadline.
     */
    function forfeitExpiredRoll(uint256 requestId) external nonReentrant {
        Bet storage bet = bets[requestId];

        require(bet.player != address(0), "Bet does not exist");
        require(bet.isCommitReveal, "Not commit-reveal bet");
        require(!bet.settled, "Bet already settled");
        require(bet.randomFulfilled, "Randomness not ready");
        require(block.timestamp > bet.revealDeadline, "Reveal period not expired");

        bet.settled = true;
        bet.won = false;
        bet.result = 0;

        treasury.settleBet(bet.treasuryBetId, 0);

        emit DiceRollForfeited(requestId, bet.player);

        emit DiceRollSettled(
            requestId,
            bet.treasuryBetId,
            bet.player,
            bet.guess,
            0,
            false,
            0
        );
    }

    /**
     * @notice Called by VRFConsumer when Chainlink VRF returns random words.
     */
    function onRandomnessFulfilled(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external override nonReentrant {
        require(msg.sender == address(vrfConsumer), "Only VRFConsumer can fulfill");
        require(randomWords.length > 0, "No random words");

        Bet storage bet = bets[requestId];

        require(bet.player != address(0), "Bet does not exist");
        require(!bet.settled, "Bet already settled");

        if (bet.isCommitReveal) {
            bet.randomFulfilled = true;
            bet.randomWord = randomWords[0];

            emit DiceRandomnessReady(
                requestId,
                bet.player,
                bet.revealDeadline
            );
        } else {
            uint8 result = uint8((randomWords[0] % 6) + 1);
            _settleBet(requestId, result);
        }
    }

    function _settleBet(uint256 requestId, uint8 result) internal {
        Bet storage bet = bets[requestId];

        require(bet.player != address(0), "Bet does not exist");
        require(!bet.settled, "Bet already settled");

        bool won = result == bet.guess;

        bet.settled = true;
        bet.result = result;
        bet.won = won;

        uint256 payout = 0;

        if (won) {
            payout = treasury.quotePayout(bet.stake * 6);

            if (!achievementNFT.hasFirstWinAchievement(bet.player)) {
                achievementNFT.mintFirstWin(bet.player);
            }
        }

        treasury.settleBet(bet.treasuryBetId, payout);

        emit DiceRollSettled(
            requestId,
            bet.treasuryBetId,
            bet.player,
            bet.guess,
            result,
            won,
            payout
        );
    }

    function setVRFConsumer(address _vrfConsumer) external onlyOwner {
        require(_vrfConsumer != address(0), "Invalid VRF consumer");
        vrfConsumer = IVRFConsumer(_vrfConsumer);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = ITreasury(_treasury);
    }

    function setAchievementNFT(address _achievementNFT) external onlyOwner {
        require(_achievementNFT != address(0), "Invalid achievement NFT");
        achievementNFT = IAchievementNFT(_achievementNFT);
    }

    function setRevealTimeout(uint256 _revealTimeout) external onlyOwner {
        require(_revealTimeout > 0, "Invalid reveal timeout");
        revealTimeout = _revealTimeout;
    }

    function getPlayerRequests(address player) external view returns (uint256[] memory) {
        return playerRequests[player];
    }

    /**
     * @notice Helper for frontend commitment generation reference.
     */
    function getCommitmentHash(
        address player,
        uint8 guess,
        bytes32 salt
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, guess, salt));
    }
}