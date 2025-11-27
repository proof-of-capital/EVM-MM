// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {Rebalance} from "../src/Rebalance.sol";


contract DeployRebalance is Script {
    function run() external returns (Rebalance) {
        // Get addresses from environment variables
        address mainCollateralToken = vm.envAddress("MAIN_COLLATERAL_TOKEN");
        address launchToken = vm.envAddress("LAUNCH_TOKEN");

        console.log("Deploying Rebalance contract...");
        console.log("Main Collateral Token:", mainCollateralToken);
        console.log("Launch Token:", launchToken);

        // Deploy contract
        vm.startBroadcast();
        Rebalance rebalance = new Rebalance(mainCollateralToken, launchToken);
        vm.stopBroadcast();

        console.log("Rebalance contract deployed at:", address(rebalance));
        console.log("Owner:", rebalance.owner());
        console.log("Admin:", rebalance.admin());

        return rebalance;
    }
}

