// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AchievementNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    address public gameContract;

    mapping(address => bool) public hasFirstWinAchievement;

    event GameContractUpdated(address indexed gameContract);
    event AchievementMinted(
        address indexed player,
        uint256 indexed tokenId,
        string achievementType
    );

    constructor() ERC721("Dice Achievement", "DICEACH") {}

    modifier onlyGameContract() {
        require(msg.sender == gameContract, "Only game contract can mint");
        _;
    }

    function setGameContract(address _gameContract) external onlyOwner {
        require(_gameContract != address(0), "Invalid game contract");

        gameContract = _gameContract;

        emit GameContractUpdated(_gameContract);
    }

    function mintFirstWin(address player) external onlyGameContract returns (uint256) {
        require(player != address(0), "Invalid player");
        require(!hasFirstWinAchievement[player], "Achievement already minted");

        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        hasFirstWinAchievement[player] = true;
        _safeMint(player, tokenId);

        emit AchievementMinted(player, tokenId, "FIRST_WIN");

        return tokenId;
    }
}