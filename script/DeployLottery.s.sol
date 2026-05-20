// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {Referral} from "../src/Referral.sol";

contract DeployLottery is Script {
    // ========== Sepolia Config ==========
    // Person #1's deployed contracts — update before running.
    // 1. Deploy VRFConsumer  (Member 1)
    // 2. Deploy Treasury     (Member 1)
    // 3. Fund the VRF v2.5 subscription on vrf.chain.link
    // 4. Register VRFConsumer as a consumer on the subscription
    // 5. Run this script → deploys Lottery + Referral
    // 6. Call vrfConsumer.setConsumerAuthorization(lottery, true)
    // 7. Call treasury.setGameAuthorization(lottery, true) if using bet system

    address constant VRF_CONSUMER = address(0); // TODO: Person #1 VRFConsumer address
    address constant TREASURY = address(0);     // TODO: Person #1 Treasury address

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Referral
        Referral referral = new Referral();

        // Deploy Lottery
        Lottery lottery = new Lottery(VRF_CONSUMER, TREASURY);

        // Wire up Lottery <-> Referral
        lottery.setReferral(address(referral));
        referral.setLottery(address(lottery));

        vm.stopBroadcast();

        console2.log("=== Sepolia Deployment ===");
        console2.log("Lottery:", address(lottery));
        console2.log("Referral:", address(referral));
        console2.log("=========================");
        console2.log("");
        console2.log("=== Post-Deployment Steps ===");
        console2.log("1. VRFConsumer.setConsumerAuthorization(lottery, true)");
        console2.log("   Authorizes Lottery to request randomness.");
        console2.log("2. Treasury.setGameAuthorization(lottery, true)");
        console2.log("   If using Treasury bet system for house edge settlement.");
    }
}
