// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {AchievementNFT} from "../src/AchievementNFT.sol";
import {DiceGame} from "../src/DiceGame.sol";

contract DeployDice is Script {
    address constant VRF_CONSUMER = 0x64754668789Cc46F7d441c09D9293C97d6257E2C;
    address constant TREASURY = 0x526BD277AF3efc291a98f5958b16783cc9821B75;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying Dice contracts with deployer:", deployer);
        console2.log("VRFConsumer:", VRF_CONSUMER);
        console2.log("Treasury:", TREASURY);

        vm.startBroadcast(deployerPrivateKey);

        AchievementNFT achievementNFT = new AchievementNFT(deployer);

        DiceGame diceGame = new DiceGame(
            deployer,
            VRF_CONSUMER,
            TREASURY,
            address(achievementNFT)
        );

        achievementNFT.setGameContract(address(diceGame));

        vm.stopBroadcast();

        console2.log("AchievementNFT deployed to:", address(achievementNFT));
        console2.log("DiceGame deployed to:", address(diceGame));
        console2.log("AchievementNFT gameContract set to:", address(diceGame));
    }
}