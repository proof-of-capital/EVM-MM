// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {RebalanceV2} from "../src/RebalanceV2.sol";
import {ProfitWallets} from "../src/interfaces/IRebalanceV2.sol";

contract DeployRebalanceV2 is Script {
    function run() external returns (RebalanceV2) {
        // Get addresses from environment variables
        address launchToken = vm.envAddress("LAUNCH_TOKEN");
        address profitWalletMeraFund = vm.envAddress("PROFIT_WALLET_MERA_FUND");
        address profitWalletPocRoyalty = vm.envAddress("PROFIT_WALLET_POC_ROYALTY");
        address profitWalletPocBuyback = vm.envAddress("PROFIT_WALLET_POC_BUYBACK");
        address profitWalletDao = vm.envAddress("PROFIT_WALLET_DAO");

        console.log("Deploying RebalanceV2 contract...");
        console.log("Launch Token:", launchToken);
        console.log("Profit Wallet MeraFund:", profitWalletMeraFund);
        console.log("Profit Wallet POC Royalty:", profitWalletPocRoyalty);
        console.log("Profit Wallet POC Buyback:", profitWalletPocBuyback);
        console.log("Profit Wallet DAO:", profitWalletDao);

        // Prepare profit wallets structure
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: profitWalletMeraFund,
            pocRoyalty: profitWalletPocRoyalty,
            pocBuyback: profitWalletPocBuyback,
            dao: profitWalletDao
        });

        // Deploy contract
        vm.startBroadcast();
        RebalanceV2 rebalanceV2 = new RebalanceV2(launchToken, profitWallets);
        vm.stopBroadcast();

        console.log("RebalanceV2 contract deployed at:", address(rebalanceV2));
        console.log("Owner:", rebalanceV2.owner());
        console.log("Launch Token:", address(rebalanceV2.launchToken()));
        console.log("Profit Wallet MeraFund:", rebalanceV2.profitWalletMeraFund());
        console.log("Profit Wallet POC Royalty:", rebalanceV2.profitWalletPocRoyalty());
        console.log("Profit Wallet POC Buyback:", rebalanceV2.profitWalletPocBuyback());
        console.log("Profit Wallet DAO:", rebalanceV2.profitWalletDao());

        return rebalanceV2;
    }
}

