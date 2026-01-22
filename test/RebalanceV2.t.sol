// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {RebalanceV2} from "../src/RebalanceV2.sol";
import {
    IRebalanceV2,
    RouterType,
    SwapParams,
    POCBuyParams,
    POCSellParams,
    AllowanceParams,
    ProfitWallets
} from "../src/interfaces/IRebalanceV2.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPOC} from "./mocks/MockPOC.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";
import {MockDAO} from "./mocks/MockDAO.sol";
import {DataTypes} from "../src/interfaces/DataTypes.sol";

contract RebalanceV2Test is Test {
    RebalanceV2 public rebalanceV2;
    MockERC20 public launchToken;
    MockERC20 public collateral1;
    MockERC20 public collateral2;
    MockERC20 public collateral3;
    MockERC20 public collateral4;
    MockPOC public poc1;
    MockPOC public poc2;
    MockPOC public poc3;
    MockPOC public poc4;
    MockUniswapV2Router public router;

    address public owner;
    address public profitWalletMeraFund;
    address public profitWalletPocRoyalty;
    address public profitWalletPocBuyback;
    MockDAO public mockDao;

    function setUp() public {
        owner = address(this);

        // Deploy profit wallets
        profitWalletMeraFund = address(0x1);
        profitWalletPocRoyalty = address(0x2);
        profitWalletPocBuyback = address(0x3);

        // Deploy MockDAO
        mockDao = new MockDAO();
        // Set DAO to Dissolved state by default to allow tests to work
        mockDao.setCurrentStage(DataTypes.Stage.Dissolved);

        // Deploy tokens
        launchToken = new MockERC20("Launch Token", "LAUNCH");
        collateral1 = new MockERC20("Collateral 1", "COL1");
        collateral2 = new MockERC20("Collateral 2", "COL2");
        collateral3 = new MockERC20("Collateral 3", "COL3");
        collateral4 = new MockERC20("Collateral 4", "COL4");

        // Deploy POC contracts
        poc1 = new MockPOC(address(launchToken), address(collateral1));
        poc2 = new MockPOC(address(launchToken), address(collateral2));
        poc3 = new MockPOC(address(launchToken), address(collateral3));
        poc4 = new MockPOC(address(launchToken), address(collateral4));

        // Deploy router
        router = new MockUniswapV2Router();

        // Deploy RebalanceV2 contract
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: profitWalletMeraFund,
            pocRoyalty: profitWalletPocRoyalty,
            pocBuyback: profitWalletPocBuyback,
            dao: address(mockDao)
        });
        rebalanceV2 = new RebalanceV2(address(launchToken), profitWallets);

        // Setup swap rates (1:1 for simplicity, can be adjusted)
        router.setSwapRate(address(launchToken), address(collateral1), 1e18);
        router.setSwapRate(address(launchToken), address(collateral2), 1e18);
        router.setSwapRate(address(collateral3), address(launchToken), 11e17); // 1.1:1 for profit
        router.setSwapRate(address(collateral4), address(launchToken), 11e17); // 1.1:1 for profit

        // Mint tokens to rebalance contract
        launchToken.mint(address(rebalanceV2), 1000000e18);

        // Mint tokens to router for swaps
        collateral1.mint(address(router), 1000000e18);
        collateral2.mint(address(router), 1000000e18);
        collateral3.mint(address(router), 1000000e18);
        collateral4.mint(address(router), 1000000e18);
        launchToken.mint(address(router), 1000000e18);

        // Mint tokens to POC contracts for sell operations
        collateral3.mint(address(poc3), 1000000e18);
        collateral4.mint(address(poc4), 1000000e18);

        // Mint launch tokens to POC contracts for buy operations
        launchToken.mint(address(poc1), 1000000e18);
        launchToken.mint(address(poc2), 1000000e18);

        // Approve router to spend tokens from rebalance contract using increaseAllowanceForSpenders
        AllowanceParams[] memory allowances = new AllowanceParams[](9);
        allowances[0] =
            AllowanceParams({token: address(launchToken), spender: address(router), amount: type(uint256).max});
        allowances[1] =
            AllowanceParams({token: address(collateral1), spender: address(router), amount: type(uint256).max});
        allowances[2] =
            AllowanceParams({token: address(collateral2), spender: address(router), amount: type(uint256).max});
        allowances[3] =
            AllowanceParams({token: address(collateral3), spender: address(router), amount: type(uint256).max});
        allowances[4] =
            AllowanceParams({token: address(collateral4), spender: address(router), amount: type(uint256).max});
        allowances[5] =
            AllowanceParams({token: address(collateral1), spender: address(poc1), amount: type(uint256).max});
        allowances[6] =
            AllowanceParams({token: address(collateral2), spender: address(poc2), amount: type(uint256).max});
        allowances[7] =
            AllowanceParams({token: address(launchToken), spender: address(poc3), amount: type(uint256).max});
        allowances[8] =
            AllowanceParams({token: address(launchToken), spender: address(poc4), amount: type(uint256).max});
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_rebalanceLPtoPOC_Success() public {
        // Record initial balances
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Note: rebalanceLPtoPOC uses entire launchToken balance for each swap
        // So we use single swap for simplicity
        SwapParams[] memory swapParamsArray = new SwapParams[](1);

        // Swap: launchToken -> collateral1
        address[] memory path1 = new address[](2);
        path1[0] = address(launchToken);
        path1[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 900e18
        });

        // Prepare POC buy params
        // Strategy: swap returns 1.1x collateral, then buy returns 1.1x launchToken
        // Start: 1e24 launchToken
        // Swap: 1e24 launchToken -> 1.1e24 collateral (1.1:1 rate)
        // Buy: 1e24 collateral -> 1.1e24 launchToken (MockPOC returns 1.1x)
        // Net: -1e24 + 1.1e24 = +1e23 profit
        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1e24 // Use all collateral received from swap
        });

        // Setup swap rate to return more collateral (1.1:1) - swap returns 1.1x collateral
        router.setSwapRate(address(launchToken), address(collateral1), 11e17); // 1.1:1

        // Mint launch tokens to router for swaps (need enough to return 1.1x)
        // Initial balance in rebalanceV2 is 1e24, so router needs at least 1.1e24 collateral
        collateral1.mint(address(router), 2e24); // Mint enough collateral for 1.1x return

        // Mint launch tokens to POC contract for buy operations
        // We buy with 1e24 collateral, MockPOC returns 1.1e24 launch tokens
        launchToken.mint(address(poc1), 2e24); // Mint enough launch tokens

        // Note: allowance for collateral1 is already set in setUp()

        // Prepare amountsIn array (use entire balance: 1e24)
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = initialLaunchToken; // Use entire balance

        // Execute rebalance
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);

        // Check final balances
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Verify launch token balance increased (profit)
        assertGt(finalLaunchToken, initialLaunchToken, "Launch token balance should increase");

        // Verify POC interactions
        // Swap returns 1.1e24 collateral, so POC receives 1.1e24
        assertEq(poc1.tokensReceivedOnBuy(), 11e23, "POC1 should receive correct amount");

        // Verify profit distribution
        uint256 profit = finalLaunchToken - initialLaunchToken;
        uint256 expectedMeraFund = (profit * 5) / 100;
        uint256 expectedPocRoyalty = (profit * 5) / 100;
        uint256 expectedPocBuyback = (profit * 45) / 100;
        uint256 expectedDao = profit - expectedMeraFund - expectedPocRoyalty - expectedPocBuyback;

        assertEq(rebalanceV2.accumulatedProfitMeraFund(), expectedMeraFund, "MeraFund profit should be correct");
        assertEq(rebalanceV2.accumulatedProfitPocRoyalty(), expectedPocRoyalty, "POC Royalty profit should be correct");
        assertEq(rebalanceV2.accumulatedProfitPocBuyback(), expectedPocBuyback, "POC Buyback profit should be correct");
        assertEq(rebalanceV2.accumulatedProfitDao(), expectedDao, "DAO profit should be correct");
    }

    function test_rebalancePOCtoLP_Success() public {
        // Record initial balances
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Mint some launch tokens to rebalance contract for selling
        launchToken.mint(address(rebalanceV2), 5000e18);

        // Prepare POC sell params
        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](2);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});
        pocSellParamsArray[1] = POCSellParams({pocContract: address(poc4), launchAmount: 1500e18});

        // Prepare swap params (collateral -> launchToken)
        SwapParams[] memory swapParamsArray = new SwapParams[](2);

        // Swap 1: collateral3 -> launchToken
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(launchToken);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Swap 2: collateral4 -> launchToken
        address[] memory path2 = new address[](2);
        path2[0] = address(collateral4);
        path2[1] = address(launchToken);
        swapParamsArray[1] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path2,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Setup swap rate for profit (collateral -> launchToken with profit)
        // Need to ensure profit >= 1% of initial balance
        // Initial: 1e24 (before mint), but initialLaunchBalance in modifier = 1.005e24 (after mint)
        // Sell: 3000e18 launchToken
        // Get: 1650e18 collateral3 + 1650e18 collateral4 = 3300e18 each
        // Each swap uses full balance, so:
        // Swap 1: 1650e18 collateral3 -> launchToken
        // Swap 2: 1650e18 collateral4 -> launchToken
        // Need: profit >= 1.005e24 * 100 / 10000 = 10050e18
        // Need back: 3000e18 + 10050e18 = 13050e18 total
        // From 1650e18 each: need 13050e18 / 2 = 6525e18 per swap
        // Rate: 6525e18 / 1650e18 = 3.954...
        // Use 4.0:1 to be safe
        router.setSwapRate(address(collateral3), address(launchToken), 40e17); // 4.0:1
        router.setSwapRate(address(collateral4), address(launchToken), 40e17); // 4.0:1

        // Mint launch tokens to router for swaps
        // After selling: 1.5e21 * 1.1 = 1.65e21 collateral each, total 3.3e21
        // After swap: 3.3e21 * 1.1 = 3.63e21 launchToken each
        launchToken.mint(address(router), 5e24); // Mint enough launch tokens

        // Note: allowances for collateral3 and collateral4 are already set in setUp()

        // Execute rebalance
        rebalanceV2.rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);

        // Check final balances
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Verify launch token balance increased (profit)
        assertGt(finalLaunchToken, initialLaunchToken, "Launch token balance should increase");

        // Verify POC interactions
        assertEq(poc3.tokensSoldOnSell(), 1500e18, "POC3 should sell correct amount");
        assertEq(poc4.tokensSoldOnSell(), 1500e18, "POC4 should sell correct amount");
    }

    function test_rebalancePOCtoLP_RevertIfNoProfit() public {
        // Mint some launch tokens to rebalance contract for selling
        launchToken.mint(address(rebalanceV2), 5000e18);

        // Prepare POC sell params - sell large amount
        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({
            pocContract: address(poc3),
            launchAmount: 3000e18 // Sell large amount
        });

        // Prepare swap params (collateral -> launchToken)
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(launchToken);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Setup swap rate that doesn't generate profit (1:1)
        // After selling: 3000e18 launch -> 3300e18 collateral (1.1x from MockPOC)
        // After swap: 3300e18 collateral -> 3300e18 launch (1:1 rate)
        // Net: -3000e18 + 3300e18 = +300e18 profit (should work)
        // But if we set rate to 0.9:1, we get: 3300e18 * 0.9 = 2970e18 launch
        // Net: -3000e18 + 2970e18 = -30e18 (loss, will revert)
        router.setSwapRate(address(collateral3), address(launchToken), 9e17); // 0.9:1 - loss

        // Mint launch tokens to router for swaps
        launchToken.mint(address(router), 5e24);

        // Note: allowances for collateral3 are already set in setUp()

        // Should revert because launch token balance doesn't increase
        vm.expectRevert(IRebalanceV2.LaunchTokenBalanceNotIncreased.selector);
        rebalanceV2.rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    function test_rebalancePOCtoPOC_Success() public {
        // Record initial balances
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Mint some launch tokens to rebalance contract for selling
        launchToken.mint(address(rebalanceV2), 5000e18);

        // Prepare POC sell params
        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](2);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});
        pocSellParamsArray[1] = POCSellParams({pocContract: address(poc4), launchAmount: 1500e18});

        // Prepare swap params (collateral -> collateral)
        SwapParams[] memory swapParamsArray = new SwapParams[](2);

        // Swap 1: collateral3 -> collateral1
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Swap 2: collateral4 -> collateral2
        address[] memory path2 = new address[](2);
        path2[0] = address(collateral4);
        path2[1] = address(collateral2);
        swapParamsArray[1] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path2,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Prepare POC buy params
        // After selling: we get 1.65e21 collateral from each POC (1.5e21 * 1.1)
        // Total: 3.3e21 collateral
        // After swaps: we get 3.3e21 of each target collateral (1:1 swap rate)
        // To ensure profit: we need to buy more launch tokens than we sold
        // We sold: 1.5e21 + 1.5e21 = 3e21 launch tokens
        // We need to buy: more than 3e21 to have profit
        // Buy with 1.65e21 collateral each -> get 1.815e21 launch tokens each = 3.63e21 total
        // Net: -3e21 + 3.63e21 = +0.63e21 profit
        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](2);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1650e18 // Use 1.65e21 collateral, will get 1.815e21 launchToken
        });
        pocBuyParamsArray[1] = POCBuyParams({
            pocContract: address(poc2),
            collateral: address(collateral2),
            collateralAmount: 1650e18 // Use 1.65e21 collateral, will get 1.815e21 launchToken
        });

        // Setup swap rates
        // Need to ensure profit >= 1% of initial balance
        // Initial: ~1.005e24, sell 3000e18, get 3300e18 collateral each = 6600e18 total
        // After swap 1:1: get 6600e18 target collateral
        // Buy: 6600e18 * 1.1 = 7260e18 launchToken
        // Profit: 7260e18 - 3000e18 = 4260e18
        // Percentage: 4260e18 / 1.005e24 = 0.424% < 1% (fails!)
        // Need higher swap rate: use 1.2:1 to get 6600e18 * 1.2 = 7920e18 collateral
        // Buy: 7920e18 * 1.1 = 8712e18 launchToken
        // Profit: 8712e18 - 3000e18 = 5712e18
        // Percentage: 5712e18 / 1.005e24 = 0.568% still < 1%
        // Use 1.5:1: 6600e18 * 1.5 = 9900e18 collateral
        // Buy: 9900e18 * 1.1 = 10890e18 launchToken
        // Profit: 10890e18 - 3000e18 = 7890e18
        // Percentage: 7890e18 / 1.005e24 = 0.785% still < 1%
        // Use 2.0:1: 6600e18 * 2.0 = 13200e18 collateral
        // Buy: 13200e18 * 1.1 = 14520e18 launchToken
        // Profit: 14520e18 - 3000e18 = 11520e18
        // Percentage: 11520e18 / 1.005e24 = 1.146% >= 1% (passes!)
        // Actually, each swap uses full balance separately, so need higher rate
        router.setSwapRate(address(collateral3), address(collateral1), 36e17); // 3.6:1
        router.setSwapRate(address(collateral4), address(collateral2), 36e17); // 3.6:1

        // Mint collateral tokens to router for swaps
        // After selling: 1.5e21 * 1.1 = 1.65e21 collateral each
        // After swap: 1.65e21 collateral -> 1.65e21 target collateral (1:1)
        collateral1.mint(address(router), 2e24);
        collateral2.mint(address(router), 2e24);

        // Mint launch tokens to POC contracts for buy operations
        launchToken.mint(address(poc1), 2e24);
        launchToken.mint(address(poc2), 2e24);

        // Note: allowances for collateral3 and collateral4 are already set in setUp()

        // Execute rebalance
        rebalanceV2.rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);

        // Check final balances
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Verify launch token balance increased (profit)
        assertGt(finalLaunchToken, initialLaunchToken, "Launch token balance should increase");

        // Verify POC interactions
        assertEq(poc3.tokensSoldOnSell(), 1500e18, "POC3 should sell correct amount");
        assertEq(poc4.tokensSoldOnSell(), 1500e18, "POC4 should sell correct amount");
        // After swap with 3.6:1 rate: 1650e18 * 3.6 = 5940e18 collateral
        assertEq(poc1.tokensReceivedOnBuy(), 5940e18, "POC1 should receive correct amount");
        assertEq(poc2.tokensReceivedOnBuy(), 5940e18, "POC2 should receive correct amount");
    }

    function test_withdrawProfits_Success() public {
        // First, generate some profit
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Setup a simple profitable swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path,
            data: "",
            amountOutMinimum: 900e18
        });

        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1e24 // Use all collateral received from swap
        });

        // Setup swap rate to return more collateral (1.1:1)
        router.setSwapRate(address(launchToken), address(collateral1), 11e17); // 1.1:1
        // Mint enough collateral to router for 1.1x return
        collateral1.mint(address(router), 2e24);
        // Mint launch tokens to POC contract for buy operations
        launchToken.mint(address(poc1), 2e24);

        // Note: allowance for collateral1 is already set in setUp()

        // Prepare amountsIn array (use entire balance)
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = initialLaunchToken; // Use entire balance

        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);

        uint256 profit = launchToken.balanceOf(address(rebalanceV2)) - initialLaunchToken;
        assertGt(profit, 0, "Should have profit");

        // Record balances before withdrawal
        uint256 meraFundBalanceBefore = launchToken.balanceOf(profitWalletMeraFund);
        uint256 pocRoyaltyBalanceBefore = launchToken.balanceOf(profitWalletPocRoyalty);
        uint256 pocBuybackBalanceBefore = launchToken.balanceOf(profitWalletPocBuyback);
        uint256 daoBalanceBefore = launchToken.balanceOf(address(mockDao));

        // Withdraw profits
        rebalanceV2.withdrawProfits();

        // Verify profits were transferred
        uint256 expectedMeraFund = (profit * 5) / 100;
        uint256 expectedPocRoyalty = (profit * 5) / 100;
        uint256 expectedPocBuyback = (profit * 45) / 100;
        uint256 expectedDao = profit - expectedMeraFund - expectedPocRoyalty - expectedPocBuyback;

        assertEq(
            launchToken.balanceOf(profitWalletMeraFund),
            meraFundBalanceBefore + expectedMeraFund,
            "MeraFund should receive profit"
        );
        assertEq(
            launchToken.balanceOf(profitWalletPocRoyalty),
            pocRoyaltyBalanceBefore + expectedPocRoyalty,
            "POC Royalty should receive profit"
        );
        assertEq(
            launchToken.balanceOf(profitWalletPocBuyback),
            pocBuybackBalanceBefore + expectedPocBuyback,
            "POC Buyback should receive profit"
        );
        assertEq(launchToken.balanceOf(address(mockDao)), daoBalanceBefore + expectedDao, "DAO should receive profit");

        // Verify accumulated profits are reset
        assertEq(rebalanceV2.accumulatedProfitMeraFund(), 0, "MeraFund accumulated profit should be reset");
        assertEq(rebalanceV2.accumulatedProfitPocRoyalty(), 0, "POC Royalty accumulated profit should be reset");
        assertEq(rebalanceV2.accumulatedProfitPocBuyback(), 0, "POC Buyback accumulated profit should be reset");
        assertEq(rebalanceV2.accumulatedProfitDao(), 0, "DAO accumulated profit should be reset");
    }

    function test_withdraw_Success() public {
        // Mint some collateral tokens to contract
        collateral1.mint(address(rebalanceV2), 10000e18);

        uint256 ownerBalanceBefore = collateral1.balanceOf(owner);
        uint256 withdrawAmount = 5000e18;

        // Withdraw collateral (not launch token, so no lock check)
        rebalanceV2.withdraw(address(collateral1), withdrawAmount);

        assertEq(
            collateral1.balanceOf(owner), ownerBalanceBefore + withdrawAmount, "Owner should receive withdrawn tokens"
        );
    }

    function test_withdraw_LaunchTokenBeforeDissolution() public {
        // Set DAO to Active state - withdrawal should be locked
        mockDao.setCurrentStage(DataTypes.Stage.Active);

        // Try to withdraw launch token (should fail)
        vm.expectRevert(IRebalanceV2.WithdrawLaunchLocked.selector);
        rebalanceV2.withdraw(address(launchToken), 1000e18);
    }

    function test_withdraw_LaunchTokenAfterDissolution() public {
        // Set DAO to Dissolved state
        mockDao.setCurrentStage(DataTypes.Stage.Dissolved);

        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 10000e18);

        uint256 ownerBalanceBefore = launchToken.balanceOf(owner);
        uint256 withdrawAmount = 5000e18;

        // Withdraw launch token (should succeed after dissolution)
        rebalanceV2.withdraw(address(launchToken), withdrawAmount);

        assertEq(
            launchToken.balanceOf(owner),
            ownerBalanceBefore + withdrawAmount,
            "Owner should receive withdrawn launch tokens after dissolution"
        );
    }

    function test_setWithdrawLaunchLock_Success() public {
        uint256 lockUntil = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil);
        assertEq(rebalanceV2.withdrawLaunchLockUntil(), lockUntil, "Lock should be set");
    }

    function test_setWithdrawLaunchLock_CannotDecrease() public {
        uint256 lockUntil1 = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil1);

        uint256 lockUntil2 = block.timestamp + 500; // Earlier than first lock
        vm.expectRevert(IRebalanceV2.LockCannotBeDecreased.selector);
        rebalanceV2.setWithdrawLaunchLock(lockUntil2);
    }

    function test_withdraw_RevertIfNotOwner() public {
        address nonOwner = address(0x123);
        vm.prank(nonOwner);

        vm.expectRevert();
        rebalanceV2.withdraw(address(collateral1), 1000e18);
    }

    function test_rebalanceLPtoPOC_RevertIfNoProfit() public {
        // Setup swap that doesn't generate profit
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path,
            data: "",
            amountOutMinimum: 900e18
        });

        // Setup swap rate that doesn't generate profit (1:1)
        router.setSwapRate(address(launchToken), address(collateral1), 1e18); // 1:1

        // Setup scenario that doesn't generate profit
        // Start: 1e24 launchToken
        // Swap: 1e24 launchToken -> 1e24 collateral (1:1)
        // Buy: 1e24 collateral -> 1e24 launchToken (MockPOC returns 1.1x, but we need to ensure no profit)
        // To ensure no profit: we need to buy less than we swapped
        // But code uses entire balance, so we need to ensure swap rate is low enough
        // Actually, with 1:1 swap and 1.1x buy, we should get profit
        // So we need to set swap rate to less than 1:1 to ensure loss
        router.setSwapRate(address(launchToken), address(collateral1), 9e17); // 0.9:1 - will get 0.9e24 collateral
        // After swap: 1e24 launchToken -> 0.9e24 collateral
        // After buy: 0.9e24 collateral -> 0.99e24 launchToken (0.9 * 1.1)
        // Net: -1e24 + 0.99e24 = -0.01e24 (loss, will revert)
        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1e24 // Not used, code uses balanceOf
        });
        collateral1.mint(address(router), 2e24); // Mint enough collateral
        // Mint launch tokens to POC contract for buy operations
        launchToken.mint(address(poc1), 2e24); // Mint enough launch tokens

        // Note: allowance for collateral1 is already set in setUp()

        // Prepare amountsIn array (use entire balance)
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = launchToken.balanceOf(address(rebalanceV2)); // Use entire balance

        // Should revert because launch token balance doesn't increase
        vm.expectRevert(IRebalanceV2.LaunchTokenBalanceNotIncreased.selector);
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);
    }

    function test_increaseAllowanceForSpenders_RevertIfNotOwner() public {
        address nonOwner = address(0x123);
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 1000e18});

        vm.prank(nonOwner);
        vm.expectRevert();
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_increaseAllowanceForSpenders_BeforeDissolution() public {
        // Set DAO to Active state - should be locked
        mockDao.setCurrentStage(DataTypes.Stage.Active);

        // Try to increase allowance while DAO is not dissolved (should fail)
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 1000e18});

        vm.expectRevert(IRebalanceV2.WithdrawLockNotExpired.selector);
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_increaseAllowanceForSpenders_AfterDissolution() public {
        // Set DAO to Dissolved state
        mockDao.setCurrentStage(DataTypes.Stage.Dissolved);

        // Use a new token that doesn't have allowance set in setUp
        MockERC20 newToken = new MockERC20("New Token", "NEW");
        MockUniswapV2Router newRouter = new MockUniswapV2Router();

        // Increase allowance after dissolution (should succeed)
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(newToken), spender: address(newRouter), amount: 1000e18});

        rebalanceV2.increaseAllowanceForSpenders(allowances);

        // Verify allowance was set
        uint256 allowance = newToken.allowance(address(rebalanceV2), address(newRouter));
        assertEq(allowance, 1000e18, "Allowance should be set after dissolution");
    }

    function test_increaseAllowanceForSpenders_AnyTokenToPOC_BeforeDissolution() public {
        // Set DAO to Active state
        mockDao.setCurrentStage(DataTypes.Stage.Active);

        // Create new POC contract that doesn't have allowance set in setUp
        MockPOC newPoc = new MockPOC(address(launchToken), address(collateral1));

        // Register new POC as POC contract in DAO
        mockDao.addPOCContract(address(newPoc), address(collateral1));

        // Increase allowance for any token to POC contract (should succeed even before dissolution)
        AllowanceParams[] memory allowances = new AllowanceParams[](2);
        allowances[0] = AllowanceParams({token: address(launchToken), spender: address(newPoc), amount: 1000e18});
        allowances[1] = AllowanceParams({token: address(collateral1), spender: address(newPoc), amount: 2000e18});

        rebalanceV2.increaseAllowanceForSpenders(allowances);

        // Verify allowances were set
        uint256 launchAllowance = launchToken.allowance(address(rebalanceV2), address(newPoc));
        uint256 collateralAllowance = collateral1.allowance(address(rebalanceV2), address(newPoc));
        assertEq(launchAllowance, 1000e18, "Allowance should be set for launch token to POC");
        assertEq(collateralAllowance, 2000e18, "Allowance should be set for collateral token to POC");
    }

    function test_increaseAllowanceForSpenders_AnyTokenToNonPOC_BeforeDissolution() public {
        // Set DAO to Active state
        mockDao.setCurrentStage(DataTypes.Stage.Active);

        // Try to increase allowance for any token to non-POC address (should fail)
        AllowanceParams[] memory allowances = new AllowanceParams[](2);
        allowances[0] = AllowanceParams({token: address(launchToken), spender: address(router), amount: 1000e18});
        allowances[1] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 2000e18});

        vm.expectRevert(IRebalanceV2.WithdrawLockNotExpired.selector);
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_withdrawProfits_PartialAccumulated() public {
        // Generate profit for only some wallets
        // Setup a simple profitable swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path,
            data: "",
            amountOutMinimum: 900e18
        });

        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] =
            POCBuyParams({pocContract: address(poc1), collateral: address(collateral1), collateralAmount: 1e24});

        router.setSwapRate(address(launchToken), address(collateral1), 11e17);
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        // Prepare amountsIn array (use entire balance)
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = launchToken.balanceOf(address(rebalanceV2)); // Use entire balance

        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);

        // Manually set some accumulated profits to 0 to test partial withdrawal
        // This simulates a scenario where some profits were already withdrawn
        // Note: We can't directly set accumulated profits, but we can test that
        // withdrawProfits handles zero amounts correctly by calling it multiple times
        rebalanceV2.withdrawProfits();

        // Call withdrawProfits again - should handle zero amounts gracefully
        rebalanceV2.withdrawProfits();

        // Verify all accumulated profits are still 0
        assertEq(rebalanceV2.accumulatedProfitMeraFund(), 0, "MeraFund should be 0");
        assertEq(rebalanceV2.accumulatedProfitPocRoyalty(), 0, "POC Royalty should be 0");
        assertEq(rebalanceV2.accumulatedProfitPocBuyback(), 0, "POC Buyback should be 0");
        assertEq(rebalanceV2.accumulatedProfitDao(), 0, "DAO should be 0");
    }

    function test_constructor_RevertIfInvalidProfitWallet_MeraFund() public {
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: address(0), // Invalid
            pocRoyalty: address(0x2),
            pocBuyback: address(0x3),
            dao: address(0x4)
        });

        vm.expectRevert(IRebalanceV2.InvalidProfitWalletAddress.selector);
        new RebalanceV2(address(launchToken), profitWallets);
    }

    function test_constructor_RevertIfInvalidProfitWallet_PocRoyalty() public {
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: address(0x1),
            pocRoyalty: address(0), // Invalid
            pocBuyback: address(0x3),
            dao: address(0x4)
        });

        vm.expectRevert(IRebalanceV2.InvalidProfitWalletAddress.selector);
        new RebalanceV2(address(launchToken), profitWallets);
    }

    function test_constructor_RevertIfInvalidProfitWallet_PocBuyback() public {
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: address(0x1),
            pocRoyalty: address(0x2),
            pocBuyback: address(0), // Invalid
            dao: address(0x4)
        });

        vm.expectRevert(IRebalanceV2.InvalidProfitWalletAddress.selector);
        new RebalanceV2(address(launchToken), profitWallets);
    }

    function test_constructor_RevertIfInvalidProfitWallet_Dao() public {
        ProfitWallets memory profitWallets = ProfitWallets({
            meraFund: address(0x1),
            pocRoyalty: address(0x2),
            pocBuyback: address(0x3),
            dao: address(0) // Invalid
        });

        vm.expectRevert(IRebalanceV2.InvalidProfitWalletAddress.selector);
        new RebalanceV2(address(launchToken), profitWallets);
    }

    function test_rebalancePOCtoLP_RevertIfInvalidPath_V2() public {
        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 5000e18);

        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        // Empty path should cause revert
        address[] memory emptyPath = new address[](0);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: emptyPath,
            data: "",
            amountOutMinimum: 1350e18
        });

        router.setSwapRate(address(collateral3), address(launchToken), 11e17);
        launchToken.mint(address(router), 5e24);

        // Should revert with InvalidPath error
        vm.expectRevert(IRebalanceV2.InvalidPath.selector);
        rebalanceV2.rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    function test_rebalancePOCtoLP_RevertIfInvalidPath_V3() public {
        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 5000e18);

        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        // Path with less than 20 bytes should cause revert
        bytes memory shortPath = new bytes(19);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV3,
            routerAddress: address(router),
            path: new address[](0),
            data: shortPath,
            amountOutMinimum: 1350e18
        });

        router.setSwapRate(address(collateral3), address(launchToken), 11e17);
        launchToken.mint(address(router), 5e24);

        // Should revert with InvalidV3Path error
        vm.expectRevert(IRebalanceV2.InvalidV3Path.selector);
        rebalanceV2.rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    function test_withdraw_LaunchTokenWhenDAOUnavailable() public {
        // Set DAO to revert (simulating unavailable DAO)
        mockDao.setShouldRevert(true);

        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 10000e18);

        // Try to withdraw launch token (should fail because DAO is unavailable)
        vm.expectRevert(IRebalanceV2.WithdrawLaunchLocked.selector);
        rebalanceV2.withdraw(address(launchToken), 1000e18);
    }

    function test_isWithdrawUnlocked_ViewFunction() public {
        // Before dissolution - should be locked
        mockDao.setCurrentStage(DataTypes.Stage.Active);
        assertFalse(rebalanceV2.isWithdrawUnlocked(), "Should be locked before dissolution");

        // After dissolution - should be unlocked
        mockDao.setCurrentStage(DataTypes.Stage.Dissolved);
        assertTrue(rebalanceV2.isWithdrawUnlocked(), "Should be unlocked after dissolution");
    }

    function test_setWithdrawLaunchLock_StillWorks() public {
        // Function setWithdrawLaunchLock should still work, but not affect unlock logic
        uint256 lockUntil = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil);
        assertEq(rebalanceV2.withdrawLaunchLockUntil(), lockUntil, "Lock timestamp should be set");

        // But lock is not removed even after time expires
        vm.warp(lockUntil + 1);

        // DAO is still in Dissolved state (from setUp), so withdrawal should work
        mockDao.setCurrentStage(DataTypes.Stage.Dissolved);

        launchToken.mint(address(rebalanceV2), 10000e18);
        uint256 ownerBalanceBefore = launchToken.balanceOf(owner);
        rebalanceV2.withdraw(address(launchToken), 1000e18);
        assertEq(launchToken.balanceOf(owner), ownerBalanceBefore + 1000e18, "Should withdraw when DAO is dissolved");

        // But if DAO is not dissolved, it should fail
        mockDao.setCurrentStage(DataTypes.Stage.Active);
        vm.expectRevert(IRebalanceV2.WithdrawLaunchLocked.selector);
        rebalanceV2.withdraw(address(launchToken), 1000e18);
    }

    function test_rebalancePOCtoPOC_RevertIfNoProfit() public {
        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 5000e18);

        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({
            pocContract: address(poc3),
            launchAmount: 3000e18 // Sell large amount
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1e20 // Not used in code, but kept for interface compliance
        });

        // Setup unprofitable swap rate
        // After selling: 3000e18 launch -> 3300e18 collateral3 (1.1x from MockPOC)
        // After swap with 0.82:1 rate: 3300e18 * 0.82 = 2706e18 collateral1
        // After buying: 2706e18 * 1.1 = 2976.6e18 launch (1.1x from MockPOC)
        // Net: -3000e18 + 2976.6e18 = -23.4e18 (loss, will revert)
        router.setSwapRate(address(collateral3), address(collateral1), 82e16); // 0.82:1 - unprofitable

        // Mint tokens to router and POC for operations
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        // Should revert because launch token balance doesn't increase
        vm.expectRevert(IRebalanceV2.LaunchTokenBalanceNotIncreased.selector);
        rebalanceV2.rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);
    }

    // ============ Tests for minProfitBps ============

    function test_minProfitBps_DefaultValue() public {
        // Check default value is 100 bps (1%)
        assertEq(rebalanceV2.minProfitBps(), 100, "Default minProfitBps should be 100 bps (1%)");
    }

    function test_setMinProfitBps_Success() public {
        // Set valid value (200 bps = 2%)
        rebalanceV2.setMinProfitBps(200);
        assertEq(rebalanceV2.minProfitBps(), 200, "minProfitBps should be updated to 200 bps");

        // Set minimum value (100 bps = 1%)
        rebalanceV2.setMinProfitBps(100);
        assertEq(rebalanceV2.minProfitBps(), 100, "minProfitBps should be updated to 100 bps");

        // Set maximum value (500 bps = 5%)
        rebalanceV2.setMinProfitBps(500);
        assertEq(rebalanceV2.minProfitBps(), 500, "minProfitBps should be updated to 500 bps");
    }

    function test_setMinProfitBps_RevertIfBelowMinimum() public {
        // Try to set value below 100 bps
        vm.expectRevert(IRebalanceV2.InvalidMinProfitBps.selector);
        rebalanceV2.setMinProfitBps(99);

        // Try to set value to 0
        vm.expectRevert(IRebalanceV2.InvalidMinProfitBps.selector);
        rebalanceV2.setMinProfitBps(0);
    }

    function test_setMinProfitBps_RevertIfAboveMaximum() public {
        // Try to set value above 500 bps
        vm.expectRevert(IRebalanceV2.InvalidMinProfitBps.selector);
        rebalanceV2.setMinProfitBps(501);

        // Try to set very large value
        vm.expectRevert(IRebalanceV2.InvalidMinProfitBps.selector);
        rebalanceV2.setMinProfitBps(1000);
    }

    function test_setMinProfitBps_RevertIfNotOwner() public {
        address nonOwner = address(0x123);
        vm.prank(nonOwner);

        vm.expectRevert();
        rebalanceV2.setMinProfitBps(200);
    }

    function test_rebalanceLPtoPOC_RevertIfProfitBelowMinimum() public {
        // Set minProfitBps to 300 bps (3%)
        rebalanceV2.setMinProfitBps(300);

        // Record initial balance
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Setup swap that generates profit but less than 3%
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path,
            data: "",
            amountOutMinimum: 900e18
        });

        // Setup swap rate to generate less than 3% profit
        // Initial: 1e24 launchToken
        // Required profit: 1e24 * 300 / 10000 = 3e22 (3%)
        // MockPOC gives 1.1x on buy, so total profit = (swapRate * 1.1 - 1) * initial
        // We need: (swapRate * 1.1 - 1) < 0.03
        // swapRate < 1.03 / 1.1 = 0.93636...
        // Use swapRate = 0.93e18 to get: 0.93 * 1.1 - 1 = 0.023 = 2.3% < 3%
        router.setSwapRate(address(launchToken), address(collateral1), 93e16); // 0.93:1 = 2.3% total profit
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] =
            POCBuyParams({pocContract: address(poc1), collateral: address(collateral1), collateralAmount: 1e24});

        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = initialLaunchToken;

        // Should revert because profit is less than 3% minimum
        vm.expectRevert(IRebalanceV2.MinProfitNotReached.selector);
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);
    }

    function test_rebalancePOCtoLP_RevertIfProfitBelowMinimum() public {
        // Set minProfitBps to 400 bps (4%)
        rebalanceV2.setMinProfitBps(400);

        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 5000e18);

        // Setup POC sell params
        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});

        // Setup swap params
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(launchToken);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Setup swap rate to generate only 3% profit (less than required 4%)
        // After sell: 1500e18 launch -> 1650e18 collateral (1.1x from MockPOC)
        // Required profit: initialLaunchToken * 400 / 10000 = 4% of initial
        // We need profit >= 4% of initial, but we'll generate only 3%
        // Initial: ~1e24, required: 4e22, but we'll get only 3e22
        router.setSwapRate(address(collateral3), address(launchToken), 103e16); // 1.03:1 = 3% profit
        launchToken.mint(address(router), 5e24);

        // Should revert because profit is less than 4% minimum
        vm.expectRevert(IRebalanceV2.MinProfitNotReached.selector);
        rebalanceV2.rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    function test_rebalancePOCtoPOC_RevertIfProfitBelowMinimum() public {
        // Set minProfitBps to 250 bps (2.5%)
        rebalanceV2.setMinProfitBps(250);

        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 5000e18);

        // Setup POC sell params
        POCSellParams[] memory pocSellParamsArray = new POCSellParams[](1);
        pocSellParamsArray[0] = POCSellParams({pocContract: address(poc3), launchAmount: 1500e18});

        // Setup swap params
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path1 = new address[](2);
        path1[0] = address(collateral3);
        path1[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 1350e18
        });

        // Setup POC buy params
        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] =
            POCBuyParams({pocContract: address(poc1), collateral: address(collateral1), collateralAmount: 1650e18});

        // Setup swap rate to generate only 2% profit (less than required 2.5%)
        router.setSwapRate(address(collateral3), address(collateral1), 102e16); // 1.02:1 = 2% profit
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        // Should revert because profit is less than 2.5% minimum
        vm.expectRevert(IRebalanceV2.MinProfitNotReached.selector);
        rebalanceV2.rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);
    }

    function test_rebalanceLPtoPOC_SuccessWithCustomMinProfit() public {
        // Set minProfitBps to 200 bps (2%)
        rebalanceV2.setMinProfitBps(200);

        // Record initial balances
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Setup swap params
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        address[] memory path1 = new address[](2);
        path1[0] = address(launchToken);
        path1[1] = address(collateral1);
        swapParamsArray[0] = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: path1,
            data: "",
            amountOutMinimum: 900e18
        });

        // Setup swap rate to generate 3% profit (more than required 2%)
        router.setSwapRate(address(launchToken), address(collateral1), 103e16); // 1.03:1 = 3% profit
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] =
            POCBuyParams({pocContract: address(poc1), collateral: address(collateral1), collateralAmount: 1e24});

        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = initialLaunchToken;

        // Execute rebalance - should succeed because profit is >= 2%
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);

        // Verify launch token balance increased
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalanceV2));
        assertGt(finalLaunchToken, initialLaunchToken, "Launch token balance should increase");

        // Verify profit is at least 2% of initial balance
        uint256 profit = finalLaunchToken - initialLaunchToken;
        uint256 minRequiredProfit = (initialLaunchToken * 200) / 10000; // 2%
        assertGe(profit, minRequiredProfit, "Profit should be at least 2% of initial balance");
    }
}

