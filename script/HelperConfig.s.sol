// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockVRFCoordinator} from "../test/mocks/MockVRFCoordinator.sol";

/**
 * @title HelperConfig
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice Resolves the VRF v2.5 parameters for the active chain. On a local
 *         chain it deploys a {MockVRFCoordinator}; on Sepolia it uses the live
 *         Chainlink coordinator and gas lane.
 * @dev    Sepolia values from https://docs.chain.link/vrf/v2-5/supported-networks
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address vrfCoordinator; // VRF v2.5 coordinator
        bytes32 keyHash; // gas lane
        uint256 subscriptionId; // funded VRF v2.5 subscription
        uint32 callbackGasLimit; // gas budget for the fulfilment callback
        uint16 houseEdgeBps; // initial Treasury house edge
        address linkToken; // LINK token (informational)
    }

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    // --- Sepolia testnet constants ---
    address internal constant SEPOLIA_VRF_COORDINATOR =
        0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 internal constant SEPOLIA_KEY_HASH =
        0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    address internal constant SEPOLIA_LINK_TOKEN =
        0x779877A7B0D9E8603169DdbD7836e478b4624789;

    NetworkConfig public activeConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeConfig = _getSepoliaConfig();
        } else {
            activeConfig = _getOrCreateLocalConfig();
        }
    }

    function getConfig() external view returns (NetworkConfig memory) {
        return activeConfig;
    }

    function _getSepoliaConfig() internal view returns (NetworkConfig memory) {
        // SUBSCRIPTION_ID must be set in the environment before deploying.
        uint256 subId = vm.envUint("SUBSCRIPTION_ID");
        return NetworkConfig({
            vrfCoordinator: SEPOLIA_VRF_COORDINATOR,
            keyHash: SEPOLIA_KEY_HASH,
            subscriptionId: subId,
            callbackGasLimit: 200_000,
            houseEdgeBps: 250, // 2.5%
            linkToken: SEPOLIA_LINK_TOKEN
        });
    }

    function _getOrCreateLocalConfig() internal returns (NetworkConfig memory) {
        if (activeConfig.vrfCoordinator != address(0)) {
            return activeConfig;
        }
        vm.startBroadcast();
        MockVRFCoordinator mockCoordinator = new MockVRFCoordinator();
        vm.stopBroadcast();

        return NetworkConfig({
            vrfCoordinator: address(mockCoordinator),
            keyHash: bytes32(uint256(0x1234)),
            subscriptionId: 1,
            callbackGasLimit: 200_000,
            houseEdgeBps: 250,
            linkToken: address(0)
        });
    }
}
