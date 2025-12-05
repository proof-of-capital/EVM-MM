// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Rebalance, RouterType, SwapParams, RebalanceParams, AllowanceParams} from "../src/Rebalance.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPOC} from "./mocks/MockPOC.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";

contract RebalanceTest is Test {
    Rebalance public rebalance;
    MockERC20 public mainCollateralToken;
    MockERC20 public launchToken;
    MockERC20 public fallenCollateral1;
    MockERC20 public fallenCollateral2;
    MockERC20 public risenCollateral1;
    MockERC20 public risenCollateral2;
    MockPOC public fallenPOC1;
    MockPOC public fallenPOC2;
    MockPOC public risenPOC1;
    MockPOC public risenPOC2;
    MockUniswapV2Router public router;

    address public owner;
    address public admin;

    function setUp() public {
        owner = address(this);
        admin = address(this);

        // Deploy tokens
        mainCollateralToken = new MockERC20("Main Collateral", "MAIN");
        launchToken = new MockERC20("Launch Token", "LAUNCH");
        fallenCollateral1 = new MockERC20("Fallen Collateral 1", "FALL1");
        fallenCollateral2 = new MockERC20("Fallen Collateral 2", "FALL2");
        risenCollateral1 = new MockERC20("Risen Collateral 1", "RISE1");
        risenCollateral2 = new MockERC20("Risen Collateral 2", "RISE2");

        // Deploy POC contracts
        fallenPOC1 = new MockPOC(address(launchToken), address(fallenCollateral1));
        fallenPOC2 = new MockPOC(address(launchToken), address(fallenCollateral2));
        risenPOC1 = new MockPOC(address(launchToken), address(risenCollateral1));
        risenPOC2 = new MockPOC(address(launchToken), address(risenCollateral2));

        // Deploy router
        router = new MockUniswapV2Router();

        // Deploy Rebalance contract
        rebalance = new Rebalance(address(mainCollateralToken), address(launchToken));

        // Setup swap rates (1:1 for simplicity, can be adjusted)
        router.setSwapRate(address(mainCollateralToken), address(fallenCollateral1), 1e18);
        router.setSwapRate(address(mainCollateralToken), address(fallenCollateral2), 1e18);
        router.setSwapRate(address(risenCollateral1), address(mainCollateralToken), 1e18);
        router.setSwapRate(address(risenCollateral2), address(mainCollateralToken), 1e18);

        // Mint tokens to rebalance contract
        mainCollateralToken.mint(address(rebalance), 1000000e18);
        launchToken.mint(address(rebalance), 1000000e18);

        // Mint tokens to router for swaps
        fallenCollateral1.mint(address(router), 1000000e18);
        fallenCollateral2.mint(address(router), 1000000e18);
        mainCollateralToken.mint(address(router), 1000000e18);

        // Mint tokens to POC contracts for sell operations
        risenCollateral1.mint(address(risenPOC1), 1000000e18);
        risenCollateral2.mint(address(risenPOC2), 1000000e18);

        // Mint launch tokens to POC contracts for buy operations
        launchToken.mint(address(fallenPOC1), 1000000e18);
        launchToken.mint(address(fallenPOC2), 1000000e18);

        // Approve router to spend tokens from rebalance contract using increaseAllowanceForSpenders
        AllowanceParams[] memory allowances = new AllowanceParams[](11);
        allowances[0] =
            AllowanceParams({token: address(mainCollateralToken), spender: address(router), amount: type(uint256).max});
        allowances[1] =
            AllowanceParams({token: address(fallenCollateral1), spender: address(router), amount: type(uint256).max});
        allowances[2] =
            AllowanceParams({token: address(fallenCollateral2), spender: address(router), amount: type(uint256).max});
        allowances[3] =
            AllowanceParams({token: address(risenCollateral1), spender: address(router), amount: type(uint256).max});
        allowances[4] =
            AllowanceParams({token: address(risenCollateral2), spender: address(router), amount: type(uint256).max});
        allowances[5] =
            AllowanceParams({token: address(launchToken), spender: address(fallenPOC1), amount: type(uint256).max});
        allowances[6] =
            AllowanceParams({token: address(launchToken), spender: address(fallenPOC2), amount: type(uint256).max});
        allowances[7] =
            AllowanceParams({token: address(launchToken), spender: address(risenPOC1), amount: type(uint256).max});
        allowances[8] =
            AllowanceParams({token: address(launchToken), spender: address(risenPOC2), amount: type(uint256).max});
        allowances[9] = AllowanceParams({
            token: address(fallenCollateral1), spender: address(fallenPOC1), amount: type(uint256).max
        });
        allowances[10] = AllowanceParams({
            token: address(fallenCollateral2), spender: address(fallenPOC2), amount: type(uint256).max
        });
        rebalance.increaseAllowanceForSpenders(allowances);

        // Approve rebalance contract to spend tokens from POC contracts (for buy operations)
        fallenCollateral1.approve(address(rebalance), type(uint256).max);
        fallenCollateral2.approve(address(rebalance), type(uint256).max);
    }

    function test_rebalancePOCtoPOC_Success() public {
        // Record initial balances
        uint256 initialMainCollateral = mainCollateralToken.balanceOf(address(rebalance));
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalance));

        // Prepare fallen params (buy launch tokens)
        RebalanceParams[] memory fallenParams = new RebalanceParams[](2);

        // Fallen param 1: mainCollateral -> fallenCollateral1 -> launchToken via fallenPOC1
        address[] memory path1 = new address[](2);
        path1[0] = address(mainCollateralToken);
        path1[1] = address(fallenCollateral1);
        fallenParams[0] = RebalanceParams({
            pocContract: address(fallenPOC1),
            collateral: address(fallenCollateral1),
            amount: 1000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path1,
                data: "",
                amountOutMinimum: 900e18
            })
        });

        // Fallen param 2: mainCollateral -> fallenCollateral2 -> launchToken via fallenPOC2
        address[] memory path2 = new address[](2);
        path2[0] = address(mainCollateralToken);
        path2[1] = address(fallenCollateral2);
        fallenParams[1] = RebalanceParams({
            pocContract: address(fallenPOC2),
            collateral: address(fallenCollateral2),
            amount: 2000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path2,
                data: "",
                amountOutMinimum: 1800e18
            })
        });

        // Prepare risen params (sell launch tokens)
        RebalanceParams[] memory risenParams = new RebalanceParams[](2);

        // Risen param 1: launchToken -> risenCollateral1 via risenPOC1 -> mainCollateral
        address[] memory path3 = new address[](2);
        path3[0] = address(risenCollateral1);
        path3[1] = address(mainCollateralToken);
        risenParams[0] = RebalanceParams({
            pocContract: address(risenPOC1),
            collateral: address(risenCollateral1),
            amount: 1500e18, // Amount of launch tokens to sell
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path3,
                data: "",
                amountOutMinimum: 1350e18
            })
        });

        // Risen param 2: launchToken -> risenCollateral2 via risenPOC2 -> mainCollateral
        address[] memory path4 = new address[](2);
        path4[0] = address(risenCollateral2);
        path4[1] = address(mainCollateralToken);
        risenParams[1] = RebalanceParams({
            pocContract: address(risenPOC2),
            collateral: address(risenCollateral2),
            amount: 1500e18, // Will be adjusted to remaining tokens in last iteration
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path4,
                data: "",
                amountOutMinimum: 1350e18
            })
        });

        // Calculate expected launch tokens bought
        // For simplicity, we'll assume 1:1 ratio (fallenCollateral -> launchToken)
        // So 1000e18 + 2000e18 = 3000e18 launch tokens should be bought

        // Execute rebalance
        rebalance.rebalancePOCtoPOC(fallenParams, risenParams);

        // Check final balances
        uint256 finalMainCollateral = mainCollateralToken.balanceOf(address(rebalance));
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalance));

        // Verify balances according to modifier requirements:
        // 1. launchToken balance should not decrease (should be >= initial)
        assertGe(finalLaunchToken, initialLaunchToken, "Launch token balance should not decrease");

        // 2. mainCollateralToken balance should increase
        assertGt(finalMainCollateral, initialMainCollateral, "Main collateral balance should increase");

        // Verify POC interactions
        assertEq(fallenPOC1.tokensReceivedOnBuy(), 1000e18, "Fallen POC1 should receive correct amount");
        assertEq(fallenPOC2.tokensReceivedOnBuy(), 2000e18, "Fallen POC2 should receive correct amount");
        assertEq(risenPOC1.tokensSoldOnSell(), 1500e18, "Risen POC1 should sell correct amount");
        // Last risen param gets remaining tokens
        // Bought: 1000e18 + 2000e18 = 3000e18 collateral -> 3300e18 launch tokens (MockPOC returns 1.1x)
        // First risen sold: 1500e18
        // Second risen gets: 3300e18 - 1500e18 = 1800e18
        assertEq(risenPOC2.tokensSoldOnSell(), 1800e18, "Risen POC2 should sell remaining tokens");
    }

    function test_rebalanceLPtoPOC_Success() public {
        // Record initial balances
        uint256 initialMainCollateral = mainCollateralToken.balanceOf(address(rebalance));
        uint256 initialLaunchToken = launchToken.balanceOf(address(rebalance));

        // Prepare rebalance params (buy launch tokens from different POC contracts)
        RebalanceParams[] memory rebalanceParams = new RebalanceParams[](2);

        // Rebalance param 1: mainCollateral -> fallenCollateral1 -> launchToken via fallenPOC1
        address[] memory path1 = new address[](2);
        path1[0] = address(mainCollateralToken);
        path1[1] = address(fallenCollateral1);
        rebalanceParams[0] = RebalanceParams({
            pocContract: address(fallenPOC1),
            collateral: address(fallenCollateral1),
            amount: 1000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path1,
                data: "",
                amountOutMinimum: 900e18
            })
        });

        // Rebalance param 2: mainCollateral -> fallenCollateral2 -> launchToken via fallenPOC2
        address[] memory path2 = new address[](2);
        path2[0] = address(mainCollateralToken);
        path2[1] = address(fallenCollateral2);
        rebalanceParams[1] = RebalanceParams({
            pocContract: address(fallenPOC2),
            collateral: address(fallenCollateral2),
            amount: 2000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV2,
                routerAddress: address(router),
                path: path2,
                data: "",
                amountOutMinimum: 1800e18
            })
        });

        // Setup swap rate for final swap (launchToken -> mainCollateralToken)
        // Use 1.1:1 ratio to ensure profit (launchToken worth more than mainCollateral)
        router.setSwapRate(address(launchToken), address(mainCollateralToken), 11e17); // 1.1:1

        // Prepare final swap params (launchToken -> mainCollateralToken)
        address[] memory finalPath = new address[](2);
        finalPath[0] = address(launchToken);
        finalPath[1] = address(mainCollateralToken);
        SwapParams memory finalSwapParams = SwapParams({
            routerType: RouterType.UniswapV2,
            routerAddress: address(router),
            path: finalPath,
            data: "",
            amountOutMinimum: 2700e18 // Minimum expected from 3000e18 launch tokens
        });

        // Mint mainCollateralToken to router for final swap
        mainCollateralToken.mint(address(router), 1000000e18);

        // Approve launchToken for router in final swap using increaseAllowanceForSpenders
        AllowanceParams[] memory allowances = new AllowanceParams[](1);
        allowances[0] =
            AllowanceParams({token: address(launchToken), spender: address(router), amount: type(uint256).max});
        rebalance.increaseAllowanceForSpenders(allowances);

        // Execute rebalance
        rebalance.rebalanceLPtoPOC(rebalanceParams, finalSwapParams);

        // Check final balances
        uint256 finalMainCollateral = mainCollateralToken.balanceOf(address(rebalance));
        uint256 finalLaunchToken = launchToken.balanceOf(address(rebalance));

        // Verify balances according to modifier requirements:
        // 1. launchToken balance should not decrease (should be >= initial)
        assertGe(finalLaunchToken, initialLaunchToken, "Launch token balance should not decrease");

        // 2. mainCollateralToken balance should increase
        assertGt(finalMainCollateral, initialMainCollateral, "Main collateral balance should increase");

        // Verify POC interactions
        assertEq(fallenPOC1.tokensReceivedOnBuy(), 1000e18, "Fallen POC1 should receive correct amount");
        assertEq(fallenPOC2.tokensReceivedOnBuy(), 2000e18, "Fallen POC2 should receive correct amount");

        // Verify that all newly bought launch tokens were swapped back
        // We bought 3000e18 launch tokens, and they should all be swapped to mainCollateralToken
        // So final launch token balance should equal initial (all new tokens swapped)
        assertEq(finalLaunchToken, initialLaunchToken, "All newly bought launch tokens should be swapped back");
    }

    function test_emergencyWithdraw_Success() public {
        // Record initial balances
        uint256 rebalanceBalance = mainCollateralToken.balanceOf(address(rebalance));
        uint256 ownerBalance = mainCollateralToken.balanceOf(owner);
        uint256 withdrawAmount = 50000e18;

        // Ensure rebalance contract has enough tokens
        assertGe(rebalanceBalance, withdrawAmount, "Rebalance contract should have enough tokens");

        // Execute emergency withdraw
        rebalance.emergencyWithdraw(address(mainCollateralToken), withdrawAmount);

        // Check final balances
        uint256 finalRebalanceBalance = mainCollateralToken.balanceOf(address(rebalance));
        uint256 finalOwnerBalance = mainCollateralToken.balanceOf(owner);

        // Verify tokens were transferred
        assertEq(
            finalRebalanceBalance,
            rebalanceBalance - withdrawAmount,
            "Rebalance contract balance should decrease by withdraw amount"
        );
        assertEq(
            finalOwnerBalance,
            ownerBalance + withdrawAmount,
            "Owner balance should increase by withdraw amount"
        );
    }

 

    function test_emergencyWithdraw_RevertIfNotOwner() public {
        // Create a non-owner address
        address nonOwner = address(0x123);
        vm.prank(nonOwner);

        // Attempt to call emergency withdraw as non-owner
        vm.expectRevert();
        rebalance.emergencyWithdraw(address(mainCollateralToken), 1000e18);
    }

   

    function test_setAdmin_Success() public {
        // Create a new admin address
        address newAdmin = address(0x456);
        
        // Verify initial admin is owner
        assertEq(rebalance.admin(), owner, "Initial admin should be owner");

        // Execute setAdmin
        rebalance.setAdmin(newAdmin);

        // Verify admin was changed
        assertEq(rebalance.admin(), newAdmin, "Admin should be updated to new admin");
        assertTrue(rebalance.admin() != owner, "Admin should not be owner anymore");
    }

    function test_setAdmin_RevertIfNotOwner() public {
        // Create a non-owner address
        address nonOwner = address(0x789);
        address newAdmin = address(0x456);

        // Attempt to call setAdmin as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        rebalance.setAdmin(newAdmin);
    }

    function test_setAdmin_RevertIfZeroAddress() public {
        // Attempt to set admin to zero address
        vm.expectRevert(Rebalance.AdminCannotBeZeroAddress.selector);
        rebalance.setAdmin(address(0));
    }

}

