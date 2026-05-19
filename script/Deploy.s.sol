// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFConsumer} from "../src/VRFConsumer.sol";
import {Treasury} from "../src/Treasury.sol";

/**
 * @title DeployInfrastructure
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice Deploys the shared platform infrastructure: {VRFConsumer} and
 *         {Treasury}. Game contracts (Members 2 & 3) are deployed separately
 *         and then wired in by the owner via:
 *           - vrfConsumer.setConsumerAuthorization(game, true)
 *           - treasury.setGameAuthorization(game, true)
 *
 * @dev    Usage:
 *           # local (deploys a mock coordinator automatically)
 *           forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
 *
 *           # Sepolia (SUBSCRIPTION_ID must be exported first)
 *           forge script script/Deploy.s.sol \
 *             --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast
 *
 *         After deploying to Sepolia, add the VRFConsumer address as a consumer
 *         on your subscription at https://vrf.chain.link.
 */
contract DeployInfrastructure is Script {
    function run() external returns (VRFConsumer vrfConsumer, Treasury treasury) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        vm.startBroadcast();

        // 1. Randomness provider.
        vrfConsumer = new VRFConsumer(
            cfg.vrfCoordinator,
            cfg.keyHash,
            cfg.subscriptionId,
            cfg.callbackGasLimit
        );

        // 2. House treasury. The broadcasting account becomes the owner.
        treasury = new Treasury(msg.sender, cfg.houseEdgeBps);

        // 3. Enable native ETH betting with sane default limits
        //    (0.001 ETH .. 1 ETH). Adjust per game requirements.
        treasury.setTokenConfig(address(0), true, 0.001 ether, 1 ether);

        vm.stopBroadcast();

        console2.log("=== SC6107 Infrastructure Deployed ===");
        console2.log("Chain id:        ", block.chainid);
        console2.log("VRF coordinator: ", cfg.vrfCoordinator);
        console2.log("VRFConsumer:     ", address(vrfConsumer));
        console2.log("Treasury:        ", address(treasury));
        console2.log("House edge (bps):", treasury.houseEdgeBps());
        console2.log("--- Next steps ---");
        console2.log("1. Add VRFConsumer as a consumer on the VRF subscription.");
        console2.log("2. After game contracts deploy, authorize them on both.");
    }
}
