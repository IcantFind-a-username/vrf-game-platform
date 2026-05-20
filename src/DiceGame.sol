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
 * @notice Dice betting game integrated with the shared VRFConsumer and Treasury modules.
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
    }

    IVRFConsumer public vrfConsumer;
    ITreasury public treasury;
    IAchievementNFT public achievementNFT;

    mapping(uint256 => Bet) public bets;
    mapping(address => uint256[]) public playerRequests;

    event DiceRollRequested(
        uint256 indexed requestId,
        uint256 indexed treasuryBetId,
        address indexed player,
        uint8 guess,
        uint256 stake
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
     * @notice Place a dice bet using native ETH.
     * @param guess Player's selected number from 1 to 6.
     */
    function rollDice(uint8 guess) external payable nonReentrant returns (uint256 requestId) {
        require(guess >= 1 && guess <= 6, "Guess must be between 1 and 6");
        require(msg.value > 0, "Stake must be greater than zero");

        uint256 stake = msg.value;

        uint256 grossPayout = stake * 6;
        uint256 maxPayout = treasury.quotePayout(grossPayout);

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
            result: 0
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

        uint8 result = uint8((randomWords[0] % 6) + 1);
        bool won = result == bet.guess;

        bet.settled = true;
        bet.result = result;
        bet.won = won;

        uint256 payout = 0;

        if (won) {
            uint256 grossPayout = bet.stake * 6;
            payout = treasury.quotePayout(grossPayout);

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

    function getPlayerRequests(address player) external view returns (uint256[] memory) {
        return playerRequests[player];
    }
}