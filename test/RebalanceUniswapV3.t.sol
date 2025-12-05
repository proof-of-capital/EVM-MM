// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Rebalance, RouterType, SwapParams, RebalanceParams, AllowanceParams} from "../src/Rebalance.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPOC} from "./mocks/MockPOC.sol";
import {MockUniswapV3Router} from "./mocks/MockUniswapV3Router.sol";

contract RebalanceUniswapV3Test is Test {
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
    MockUniswapV3Router public router;

    address public owner;
    address public admin;

    // Helper function to encode Uniswap V3 path: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
    function encodePath(address token0, uint24 fee, address token1) internal pure returns (bytes memory) {
        return abi.encodePacked(token0, fee, token1);
    }

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
        router = new MockUniswapV3Router();

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
        // Encode path for Uniswap V3: token0 + fee (3000 = 0.3%) + token1
        bytes memory path1 = encodePath(address(mainCollateralToken), 3000, address(fallenCollateral1));
        fallenParams[0] = RebalanceParams({
            pocContract: address(fallenPOC1),
            collateral: address(fallenCollateral1),
            amount: 1000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path1,
                amountOutMinimum: 900e18
            })
        });

        // Fallen param 2: mainCollateral -> fallenCollateral2 -> launchToken via fallenPOC2
        bytes memory path2 = encodePath(address(mainCollateralToken), 3000, address(fallenCollateral2));
        fallenParams[1] = RebalanceParams({
            pocContract: address(fallenPOC2),
            collateral: address(fallenCollateral2),
            amount: 2000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path2,
                amountOutMinimum: 1800e18
            })
        });

        // Prepare risen params (sell launch tokens)
        RebalanceParams[] memory risenParams = new RebalanceParams[](2);

        // Risen param 1: launchToken -> risenCollateral1 via risenPOC1 -> mainCollateral
        bytes memory path3 = encodePath(address(risenCollateral1), 3000, address(mainCollateralToken));
        risenParams[0] = RebalanceParams({
            pocContract: address(risenPOC1),
            collateral: address(risenCollateral1),
            amount: 1500e18, // Amount of launch tokens to sell
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path3,
                amountOutMinimum: 1350e18
            })
        });

        // Risen param 2: launchToken -> risenCollateral2 via risenPOC2 -> mainCollateral
        bytes memory path4 = encodePath(address(risenCollateral2), 3000, address(mainCollateralToken));
        risenParams[1] = RebalanceParams({
            pocContract: address(risenPOC2),
            collateral: address(risenCollateral2),
            amount: 1500e18, // Will be adjusted to remaining tokens in last iteration
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path4,
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
        bytes memory path1 = encodePath(address(mainCollateralToken), 3000, address(fallenCollateral1));
        rebalanceParams[0] = RebalanceParams({
            pocContract: address(fallenPOC1),
            collateral: address(fallenCollateral1),
            amount: 1000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path1,
                amountOutMinimum: 900e18
            })
        });

        // Rebalance param 2: mainCollateral -> fallenCollateral2 -> launchToken via fallenPOC2
        bytes memory path2 = encodePath(address(mainCollateralToken), 3000, address(fallenCollateral2));
        rebalanceParams[1] = RebalanceParams({
            pocContract: address(fallenPOC2),
            collateral: address(fallenCollateral2),
            amount: 2000e18,
            swapParams: SwapParams({
                routerType: RouterType.UniswapV3,
                routerAddress: address(router),
                path: new address[](0), // Not used for V3
                data: path2,
                amountOutMinimum: 1800e18
            })
        });

        // Setup swap rate for final swap (launchToken -> mainCollateralToken)
        // Use 1.1:1 ratio to ensure profit (launchToken worth more than mainCollateral)
        router.setSwapRate(address(launchToken), address(mainCollateralToken), 11e17); // 1.1:1

        // Prepare final swap params (launchToken -> mainCollateralToken)
        bytes memory finalPath = encodePath(address(launchToken), 3000, address(mainCollateralToken));
        SwapParams memory finalSwapParams = SwapParams({
            routerType: RouterType.UniswapV3,
            routerAddress: address(router),
            path: new address[](0), // Not used for V3
            data: finalPath,
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
}

