// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {Referral} from "../src/Referral.sol";

/**
 * @title DeployLottery
 * @author SC6107 Group Project - Member 3 (Lottery + Referral)
 * @notice Deploys Lottery and Referral to Sepolia. VRFConsumer + Treasury are
 *         pre-deployed by Member 1 and their addresses are hard-coded below.
 *
 * @dev    Usage:
 *           # Sepolia (PRIVATE_KEY must be exported)
 *           forge script script/DeployLottery.s.sol \
 *             --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 *         After deployment, give the Lottery address to Member 1 so they can:
 *           vrfConsumer.setConsumerAuthorization(lottery, true)
 *           treasury.setGameAuthorization(lottery, true)
 */
contract DeployLottery is Script {
    // Person #1's pre-deployed infrastructure (Sepolia, chain 11155111)
    address constant VRF_CONSUMER = 0x64754668789Cc46F7d441c09D9293C97d6257E2C;
    address constant TREASURY     = 0x526BD277AF3efc291a98f5958b16783cc9821B75;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Referral referral = new Referral();
        Lottery lottery = new Lottery(VRF_CONSUMER, TREASURY);

        lottery.setReferral(address(referral));
        referral.setLottery(address(lottery));

        vm.stopBroadcast();

        console2.log("=== Lottery + Referral Deployed (Sepolia) ===");
        console2.log("Chain ID:  ", block.chainid);
        console2.log("Lottery:   ", address(lottery));
        console2.log("Referral:  ", address(referral));
        console2.log("VRF (ext):", VRF_CONSUMER);
        console2.log("Treasury:  ", TREASURY);
        console2.log("--- Post-deployment (Member 1) ---");
        console2.log("vrfConsumer.setConsumerAuthorization(lottery, true)");
        console2.log("treasury.setGameAuthorization(lottery, true)");
    }
}
