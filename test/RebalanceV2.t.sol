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
} from "../src/inerfaces/IRebalanceV2.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPOC} from "./mocks/MockPOC.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";

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
    address public profitWalletDao;

    function setUp() public {
        owner = address(this);

        // Deploy profit wallets
        profitWalletMeraFund = address(0x1);
        profitWalletPocRoyalty = address(0x2);
        profitWalletPocBuyback = address(0x3);
        profitWalletDao = address(0x4);

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
            dao: profitWalletDao
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

        // Execute rebalance
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, pocBuyParamsArray);

        // Check final balances
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalanceV2));

        // Verify launch token balance increased (profit)
        assertGt(finalLaunchToken, initialLaunchToken, "Launch token balance should increase");

        // Verify POC interactions
        assertEq(poc1.tokensReceivedOnBuy(), 1e24, "POC1 should receive correct amount");

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
        router.setSwapRate(address(collateral3), address(launchToken), 11e17); // 1.1:1
        router.setSwapRate(address(collateral4), address(launchToken), 11e17); // 1.1:1

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

        // Setup swap rates (1:1 for simplicity)
        router.setSwapRate(address(collateral3), address(collateral1), 1e18);
        router.setSwapRate(address(collateral4), address(collateral2), 1e18);

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
        assertEq(poc1.tokensReceivedOnBuy(), 1650e18, "POC1 should receive correct amount");
        assertEq(poc2.tokensReceivedOnBuy(), 1650e18, "POC2 should receive correct amount");
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

        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, pocBuyParamsArray);

        uint256 profit = launchToken.balanceOf(address(rebalanceV2)) - initialLaunchToken;
        assertGt(profit, 0, "Should have profit");

        // Record balances before withdrawal
        uint256 meraFundBalanceBefore = launchToken.balanceOf(profitWalletMeraFund);
        uint256 pocRoyaltyBalanceBefore = launchToken.balanceOf(profitWalletPocRoyalty);
        uint256 pocBuybackBalanceBefore = launchToken.balanceOf(profitWalletPocBuyback);
        uint256 daoBalanceBefore = launchToken.balanceOf(profitWalletDao);

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
        assertEq(launchToken.balanceOf(profitWalletDao), daoBalanceBefore + expectedDao, "DAO should receive profit");

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

    function test_withdraw_LaunchTokenLocked() public {
        // Set lock
        rebalanceV2.setWithdrawLaunchLock(block.timestamp + 1000);

        // Try to withdraw launch token (should fail)
        vm.expectRevert(IRebalanceV2.WithdrawLaunchLocked.selector);
        rebalanceV2.withdraw(address(launchToken), 1000e18);
    }

    function test_withdraw_LaunchTokenAfterLock() public {
        // Set lock
        uint256 lockUntil = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil);

        // Fast forward time
        vm.warp(lockUntil);

        // Mint some launch tokens
        launchToken.mint(address(rebalanceV2), 10000e18);

        uint256 ownerBalanceBefore = launchToken.balanceOf(owner);
        uint256 withdrawAmount = 5000e18;

        // Withdraw launch token (should succeed after lock expires)
        rebalanceV2.withdraw(address(launchToken), withdrawAmount);

        assertEq(
            launchToken.balanceOf(owner),
            ownerBalanceBefore + withdrawAmount,
            "Owner should receive withdrawn launch tokens"
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

        // Use very small amount that won't generate enough profit
        // Start: 1e24 launchToken
        // Swap: 1e24 launchToken -> 1e24 collateral (1:1)
        // Buy: 1e20 collateral -> 1.1e20 launchToken (MockPOC returns 1.1x)
        // Net: -1e24 + 1.1e20 = -9.89e23 (huge loss, so will revert)
        POCBuyParams[] memory pocBuyParamsArray = new POCBuyParams[](1);
        pocBuyParamsArray[0] = POCBuyParams({
            pocContract: address(poc1),
            collateral: address(collateral1),
            collateralAmount: 1e20 // Use very small amount, profit won't be enough
        });
        collateral1.mint(address(router), 2e24); // Mint enough collateral

        // Note: allowance for collateral1 is already set in setUp()

        // Should revert because launch token balance doesn't increase
        vm.expectRevert(IRebalanceV2.LaunchTokenBalanceNotIncreased.selector);
        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, pocBuyParamsArray);
    }

    function test_decreaseAllowanceForSpenders_Success() public {
        // Use a new token that doesn't have allowance set in setUp
        MockERC20 newToken = new MockERC20("New Token", "NEW");
        MockUniswapV2Router newRouter = new MockUniswapV2Router();

        // First set a specific allowance amount
        AllowanceParams[] memory setAllowances = new AllowanceParams[](1);
        setAllowances[0] = AllowanceParams({token: address(newToken), spender: address(newRouter), amount: 1000e18});
        rebalanceV2.increaseAllowanceForSpenders(setAllowances);

        // Check allowance before
        uint256 allowanceBefore = newToken.allowance(address(rebalanceV2), address(newRouter));
        assertEq(allowanceBefore, 1000e18, "Allowance should be set");

        // Decrease allowance
        AllowanceParams[] memory decreaseAllowances = new AllowanceParams[](1);
        decreaseAllowances[0] = AllowanceParams({token: address(newToken), spender: address(newRouter), amount: 500e18});
        rebalanceV2.decreaseAllowanceForSpenders(decreaseAllowances);

        // Check allowance after
        uint256 allowanceAfter = newToken.allowance(address(rebalanceV2), address(newRouter));
        assertEq(allowanceAfter, 500e18, "Allowance should be decreased");
    }

    function test_decreaseAllowanceForSpenders_RevertIfNotOwner() public {
        address nonOwner = address(0x123);
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 1000e18});

        vm.prank(nonOwner);
        vm.expectRevert();
        rebalanceV2.decreaseAllowanceForSpenders(allowances);
    }

    function test_increaseAllowanceForSpenders_RevertIfNotOwner() public {
        address nonOwner = address(0x123);
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 1000e18});

        vm.prank(nonOwner);
        vm.expectRevert();
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_increaseAllowanceForSpenders_RevertIfLockNotExpired() public {
        // Set lock
        uint256 lockUntil = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil);

        // Try to increase allowance while lock is active (should fail)
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(collateral1), spender: address(router), amount: 1000e18});

        vm.expectRevert(IRebalanceV2.WithdrawLockNotExpired.selector);
        rebalanceV2.increaseAllowanceForSpenders(allowances);
    }

    function test_increaseAllowanceForSpenders_SuccessAfterLockExpires() public {
        // Set lock
        uint256 lockUntil = block.timestamp + 1000;
        rebalanceV2.setWithdrawLaunchLock(lockUntil);

        // Fast forward time to after lock expires
        vm.warp(lockUntil);

        // Use a new token that doesn't have allowance set in setUp
        MockERC20 newToken = new MockERC20("New Token", "NEW");
        MockUniswapV2Router newRouter = new MockUniswapV2Router();

        // Increase allowance after lock expires (should succeed)
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] = AllowanceParams({token: address(newToken), spender: address(newRouter), amount: 1000e18});

        rebalanceV2.increaseAllowanceForSpenders(allowances);

        // Verify allowance was set
        uint256 allowance = newToken.allowance(address(rebalanceV2), address(newRouter));
        assertEq(allowance, 1000e18, "Allowance should be set after lock expires");
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

        rebalanceV2.rebalanceLPtoPOC(swapParamsArray, pocBuyParamsArray);

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
            collateralAmount: 1e20 // Buy very small amount - won't generate profit
        });

        router.setSwapRate(address(collateral3), address(collateral1), 1e18);
        collateral1.mint(address(router), 2e24);
        launchToken.mint(address(poc1), 2e24);

        // Should revert because launch token balance doesn't increase
        vm.expectRevert(IRebalanceV2.LaunchTokenBalanceNotIncreased.selector);
        rebalanceV2.rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);
    }
}

