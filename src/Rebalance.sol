/// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM
// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetcollateral as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./inerfaces/IProofOfCapital.sol";
import "./inerfaces/IQuickswapV3Router.sol";
import "./inerfaces/IQuoterQuickswap.sol";
import "./inerfaces/IQuoterV2.sol";
import "./inerfaces/ISwapRouter.sol";
import "./inerfaces/ISwapRouterBase.sol";
import "./inerfaces/IUniswapV2Router01.sol";
import "./inerfaces/IUniswapV2Router02.sol";

enum RouterType {
    UniswapV2,
    UniswapV3,
    QuickswapV3
}

struct SwapParams {
    RouterType routerType;
    address routerAddress;
    address[] path;
    bytes data;
    uint256 amountOutMinimum;
}

struct RebalanceParams {
    address pocContract;
    address collateral;
    uint256 amount;
    SwapParams swapParams;
}

struct AllowanceParams {
    address token;
    address spender;
    uint256 amount;
}

/**
 * @title Rebalance Contract for Proof of Capital
 * @dev Contract for performing rebalancing operations between POC contracts and DEX
 */
contract Rebalance is Ownable {
    using SafeERC20 for IERC20;

    // Custom errors
    error CallerNotAdminOrOwner();
    error LaunchTokenBalanceDecreased();
    error MainCollateralBalanceNotIncreased();
    error AdminCannotBeZeroAddress();

    IERC20 public immutable mainCollateralToken;
    IERC20 public immutable launchToken;
    // Admin address
    address public admin;

    // Modifier for admin or owner
    modifier onlyAdminOrOwner() {
        require(msg.sender == admin || msg.sender == owner(), CallerNotAdminOrOwner());
        _;
    }

    modifier balancesAreCorrectAfterRebalance() {
        uint256 initialMainCollateralBalance = mainCollateralToken.balanceOf(address(this));
        uint256 initialLaunchTokenBalance = launchToken.balanceOf(address(this));
        _;
        uint256 finalMainCollateralBalance = mainCollateralToken.balanceOf(address(this));
        uint256 finalLaunchTokenBalance = launchToken.balanceOf(address(this));

        require(finalLaunchTokenBalance >= initialLaunchTokenBalance, LaunchTokenBalanceDecreased());
        require(finalMainCollateralBalance > initialMainCollateralBalance, MainCollateralBalanceNotIncreased());
    }

    constructor(address _mainCollateralToken, address _launchToken) Ownable(msg.sender) {
        mainCollateralToken = IERC20(_mainCollateralToken);
        launchToken = IERC20(_launchToken);
        admin = msg.sender; // Owner is also admin by default
    }

    /**
     * @dev Set admin address (only owner can call)
     */
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), AdminCannotBeZeroAddress());
        admin = newAdmin;
    }

    /**
     * @dev Increase allowance for tokens to spenders (only owner can call)
     * @param allowances Array of allowance parameters
     */
    function increaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external onlyOwner {
        for (uint256 i = 0; i < allowances.length; i++) {
            AllowanceParams memory params = allowances[i];
            IERC20(params.token).safeIncreaseAllowance(params.spender, params.amount);
        }
    }

    /**
     * @dev Decrease allowance for tokens from spenders (only owner can call)
     * @param allowances Array of allowance parameters
     */
    function decreaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external onlyOwner {
        for (uint256 i = 0; i < allowances.length; i++) {
            AllowanceParams memory params = allowances[i];
            IERC20(params.token).safeDecreaseAllowance(params.spender, params.amount);
        }
    }

    /**
     * @dev Emergency withdraw function
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev POC to POC rebalancing with multiple collaterals
     * 1. For each fallen params: mainCollateralToken -> fallen collateral via DEX
     * 2. For each fallen params: fallen collateral -> launchToken via POC (buy)
     * 3. For each risen params: launchToken -> risen collateral via POC (sell)
     * 4. For each risen params: risen collateral -> mainCollateralToken via DEX
     * 5. Check balances (launchToken same, mainCollateralToken more)
     */
    function rebalancePOCtoPOC(RebalanceParams[] calldata fallenParams, RebalanceParams[] calldata risenParams)
        external
        onlyAdminOrOwner
        balancesAreCorrectAfterRebalance
    {
        uint256 totalLaunchTokensSold = 0;

        // Remember launch token balance before buying
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        // Step 1 & 2: Process fallen collaterals (buy launch tokens)
        for (uint256 i = 0; i < fallenParams.length; i++) {
            RebalanceParams memory params = fallenParams[i];

            // Step 1: mainCollateralToken -> fallen collateral via DEX
            uint256 fallenCollateralAmount = 0;
            if (address(mainCollateralToken) == address(params.collateral)) {
                fallenCollateralAmount = params.amount;
            } else {
                fallenCollateralAmount = swap(params.amount, params.swapParams);
            }
            // Step 2: fallen collateral -> launchToken via POC (buy)
            IProofOfCapital(params.pocContract).buyTokens(fallenCollateralAmount);
        }

        // Calculate total launch tokens bought
        uint256 totalLaunchTokensBought = launchToken.balanceOf(address(this)) - initialLaunchBalance;

        // Step 3: Process risen collaterals (sell launch tokens)
        for (uint256 i = 0; i < risenParams.length; i++) {
            RebalanceParams memory params = risenParams[i];

            // Calculate launch tokens to sell for this risen collateral
            uint256 launchTokensToSell = params.amount;
            if (i == risenParams.length - 1) {
                // Last iteration gets remaining tokens to handle rounding
                launchTokensToSell = totalLaunchTokensBought - totalLaunchTokensSold;
            }

            // Step 3: launchToken -> risen collateral via POC (sell)
            IProofOfCapital(params.pocContract).sellTokens(launchTokensToSell);
            totalLaunchTokensSold += launchTokensToSell;

            // Step 4: risen collateral -> mainCollateralToken via DEX
            if (address(mainCollateralToken) != address(params.collateral)) {
                swap(IERC20(params.collateral).balanceOf(address(this)), params.swapParams);
            }
        }
    }

    /**
     * @dev LP to POC rebalancing with multiple POC contracts
     * 1. For each rebalance params: mainCollateralToken -> fallen collateral via DEX swap
     * 2. For each rebalance params: fallen collateral -> launchToken via respective POC contract
     * 3. launchToken -> mainCollateralToken via DEX (sum all launch tokens)
     * 4. Check balances (launchToken same, mainCollateralToken more)
     */
    function rebalanceLPtoPOC(RebalanceParams[] calldata rebalanceParams, SwapParams calldata finalSwapParams)
        external
        onlyAdminOrOwner
        balancesAreCorrectAfterRebalance
    {
        uint256 initialLaunchTokenBalance = launchToken.balanceOf(address(this));

        // Step 1 & 2: For each set of params - swap to collateral and buy launch tokens from POC
        for (uint256 i = 0; i < rebalanceParams.length; i++) {
            RebalanceParams memory params = rebalanceParams[i];

            // Step 1: mainCollateralToken -> fallen collateral via DEX
            uint256 fallenCollateralAmount = 0;
            if (address(mainCollateralToken) == address(params.collateral)) {
                fallenCollateralAmount = params.amount;
            } else {
                fallenCollateralAmount = swap(params.amount, params.swapParams);
            }

            // Step 2: fallen collateral -> launchToken via POC
            IProofOfCapital(params.pocContract).buyTokens(fallenCollateralAmount);
        }

        // Step 3: launchToken -> mainCollateralToken via DEX (only newly bought tokens)
        uint256 currentLaunchTokenBalance = launchToken.balanceOf(address(this));
        uint256 newlyBoughtLaunchTokens = currentLaunchTokenBalance - initialLaunchTokenBalance;
        swap(newlyBoughtLaunchTokens, finalSwapParams);
    }

    /**
     * @dev Internal swap function
     * @notice Tokens must be approved for the router before calling this function
     */
    function swap(uint256 amountIn, SwapParams memory swapParams) internal returns (uint256 amountOut) {
        if (swapParams.routerType == RouterType.UniswapV2) {
            uint256[] memory amounts = IUniswapV2Router02(swapParams.routerAddress)
                .swapExactTokensForTokens(
                    amountIn, swapParams.amountOutMinimum, swapParams.path, address(this), type(uint256).max
                );
            amountOut = amounts[1];
        } else if (swapParams.routerType == RouterType.UniswapV3) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: swapParams.data,
                recipient: address(this),
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: swapParams.amountOutMinimum
            });
            amountOut = ISwapRouter(swapParams.routerAddress).exactInput(params);
        } else if (swapParams.routerType == RouterType.QuickswapV3) {
            IQuickswapV3Router.ExactInputParams memory params = IQuickswapV3Router.ExactInputParams({
                path: swapParams.data,
                recipient: address(this),
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: swapParams.amountOutMinimum
            });
            amountOut = IQuickswapV3Router(swapParams.routerAddress).exactInput(params);
        }

        return amountOut;
    }
}
