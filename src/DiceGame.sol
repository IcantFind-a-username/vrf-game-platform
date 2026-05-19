// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IAchievementNFT {
    function mintFirstWin(address player) external returns (uint256);
    function hasFirstWinAchievement(address player) external view returns (bool);
}

contract DiceGame is Ownable, ReentrancyGuard {
    struct Bet {
        address player;
        uint256 amount;
        uint8 guess;
        bool settled;
        bool won;
        uint8 result;
    }

    uint256 public nextRequestId;
    uint256 public minBet;
    uint256 public maxBet;
    uint256 public payoutMultiplier;

    IAchievementNFT public achievementNFT;

    mapping(uint256 => Bet) public bets;
    mapping(address => uint256[]) public playerRequests;

    event DiceRollRequested(
        uint256 indexed requestId,
        address indexed player,
        uint8 guess,
        uint256 amount
    );

    event DiceRollSettled(
        uint256 indexed requestId,
        address indexed player,
        uint8 guess,
        uint8 result,
        bool won,
        uint256 payout
    );

    constructor(
        address _achievementNFT,
        uint256 _minBet,
        uint256 _maxBet
    ) {
        require(_achievementNFT != address(0), "Invalid NFT contract");
        require(_minBet > 0, "Min bet must be positive");
        require(_maxBet >= _minBet, "Invalid max bet");

        achievementNFT = IAchievementNFT(_achievementNFT);
        minBet = _minBet;
        maxBet = _maxBet;
        payoutMultiplier = 5;
    }

    function rollDice(uint8 guess) external payable nonReentrant returns (uint256 requestId) {
        require(guess >= 1 && guess <= 6, "Guess must be between 1 and 6");
        require(msg.value >= minBet, "Bet is below minimum");
        require(msg.value <= maxBet, "Bet is above maximum");

        uint256 potentialPayout = msg.value * payoutMultiplier;
        require(address(this).balance >= potentialPayout, "Insufficient house liquidity");

        requestId = nextRequestId;
        nextRequestId++;

        bets[requestId] = Bet({
            player: msg.sender,
            amount: msg.value,
            guess: guess,
            settled: false,
            won: false,
            result: 0
        });

        playerRequests[msg.sender].push(requestId);

        emit DiceRollRequested(requestId, msg.sender, guess, msg.value);
    }

    function testFulfillRandomness(uint256 requestId, uint256 randomWord) external onlyOwner nonReentrant {
        Bet storage bet = bets[requestId];

        require(bet.player != address(0), "Bet does not exist");
        require(!bet.settled, "Bet already settled");

        uint8 result = uint8((randomWord % 6) + 1);
        bool won = result == bet.guess;

        bet.settled = true;
        bet.result = result;
        bet.won = won;

        uint256 payout = 0;

        if (won) {
            payout = bet.amount * payoutMultiplier;

            if (!achievementNFT.hasFirstWinAchievement(bet.player)) {
                achievementNFT.mintFirstWin(bet.player);
            }

            (bool success, ) = payable(bet.player).call{value: payout}("");
            require(success, "Payout failed");
        }

        emit DiceRollSettled(
            requestId,
            bet.player,
            bet.guess,
            result,
            won,
            payout
        );
    }

    function fundHouse() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
    }

    function withdrawHouseFunds(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }

    function setBetLimits(uint256 _minBet, uint256 _maxBet) external onlyOwner {
        require(_minBet > 0, "Min bet must be positive");
        require(_maxBet >= _minBet, "Invalid max bet");

        minBet = _minBet;
        maxBet = _maxBet;
    }

    function getPlayerRequests(address player) external view returns (uint256[] memory) {
        return playerRequests[player];
    }

    receive() external payable {}
}