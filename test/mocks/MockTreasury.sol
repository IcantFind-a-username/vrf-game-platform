// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockTreasury {
    using SafeERC20 for IERC20;

    uint16 public houseEdgeBps = 250; // 2.5%

    struct TokenConfig {
        bool enabled;
        uint256 minBet;
        uint256 maxBet;
    }

    mapping(address => TokenConfig) private _tokenConfig;
    mapping(address => uint256) public lockedLiquidity;

    event LiquidityDeposited(address indexed token, address indexed from, uint256 amount);

    constructor() {
        // Pre-configure ETH with sensible defaults for testing
        _tokenConfig[address(0)] = TokenConfig(true, 0.001 ether, 0);
    }

    // ========== ITreasury-compatible functions ==========

    function depositLiquidity(address token, uint256 amount) external payable {
        if (token == address(0)) {
            require(msg.value == amount, "ETH value mismatch");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit LiquidityDeposited(token, msg.sender, amount);
    }

    function isTokenSupported(address token) external view returns (bool) {
        return _tokenConfig[token].enabled;
    }

    function getBetLimits(address token) external view returns (uint256 minBet, uint256 maxBet) {
        TokenConfig memory cfg = _tokenConfig[token];
        return (cfg.minBet, cfg.maxBet);
    }

    function quotePayout(uint256 grossPayout) external view returns (uint256) {
        return (grossPayout * (10_000 - houseEdgeBps)) / 10_000;
    }

    function availableLiquidity(address) external pure returns (uint256) {
        return type(uint256).max; // unlimited for mock
    }

    function totalLiquidity(address token) public view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }

    // ========== Test helpers ==========

    function setHouseEdge(uint16 _bps) external {
        houseEdgeBps = _bps;
    }

    function setMinBet(address token, uint256 _min) external {
        TokenConfig storage cfg = _tokenConfig[token];
        cfg.enabled = true;
        cfg.minBet = _min;
    }

    function setMaxBet(address token, uint256 _max) external {
        _tokenConfig[token].maxBet = _max;
    }

    function setBetLimits(address token, uint256 _min, uint256 _max) external {
        _tokenConfig[token] = TokenConfig(true, _min, _max);
    }

    // ========== Bet lifecycle (stubs for completeness) ==========

    function openBet(address, address, uint256, uint256) external payable returns (uint256) {
        revert("Mock: use depositLiquidity");
    }

    function settleBet(uint256, uint256) external pure {
        revert("Mock: not implemented");
    }

    receive() external payable {}
}
