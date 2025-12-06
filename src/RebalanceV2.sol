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

// This is the V2 version of the Rebalance contract with new algorithms and profit distribution system.
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./inerfaces/IRebalanceV2.sol";
import "./inerfaces/IProofOfCapital.sol";
import "./inerfaces/IQuickswapV3Router.sol";
import "./inerfaces/IQuoterQuickswap.sol";
import "./inerfaces/IQuoterV2.sol";
import "./inerfaces/ISwapRouter.sol";
import "./inerfaces/ISwapRouterBase.sol";
import "./inerfaces/IUniswapV2Router01.sol";
import "./inerfaces/IUniswapV2Router02.sol";

/**
 * @title RebalanceV2 Contract for Proof of Capital
 * @dev Contract for performing rebalancing operations between POC contracts and DEX with profit distribution
 */
contract RebalanceV2 is Ownable, IRebalanceV2 {
    using SafeERC20 for IERC20;

    IERC20 public immutable override launchToken;

    // Withdraw lock timestamp for launch token
    uint256 public override withdrawLaunchLockUntil;

    // Profit distribution wallets (immutable)
    address public immutable override profitWalletMeraFund;
    address public immutable override profitWalletPocRoyalty;
    address public immutable override profitWalletPocBuyback;
    address public immutable override profitWalletDao;

    // Accumulated profits per wallet
    uint256 public override accumulatedProfitMeraFund;
    uint256 public override accumulatedProfitPocRoyalty;
    uint256 public override accumulatedProfitPocBuyback;
    uint256 public override accumulatedProfitDao;

    // Profit distribution percentages (in basis points, where 100 = 1%)
    uint256 private constant PERCENTAGE_DENOMINATOR = 100;
    uint256 private constant PROFIT_SHARE_MERA_FUND = 5; // 5%
    uint256 private constant PROFIT_SHARE_POC_ROYALTY = 5; // 5%
    uint256 private constant PROFIT_SHARE_POC_BUYBACK = 45; // 45%

    // Modifier to check launch token balance increased
    modifier launchBalanceIncreased() {
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));
        _;
        uint256 finalLaunchBalance = launchToken.balanceOf(address(this));
        require(finalLaunchBalance > initialLaunchBalance, LaunchTokenBalanceNotIncreased());

        // Distribute profit
        uint256 profit = finalLaunchBalance - initialLaunchBalance;
        _distributeProfitInternal(profit);
    }

    constructor(address _launchToken, ProfitWallets memory _profitWallets) Ownable(msg.sender) {
        launchToken = IERC20(_launchToken);
        require(_profitWallets.meraFund != address(0), InvalidProfitWalletAddress());
        require(_profitWallets.pocRoyalty != address(0), InvalidProfitWalletAddress());
        require(_profitWallets.pocBuyback != address(0), InvalidProfitWalletAddress());
        require(_profitWallets.dao != address(0), InvalidProfitWalletAddress());
        profitWalletMeraFund = _profitWallets.meraFund;
        profitWalletPocRoyalty = _profitWallets.pocRoyalty;
        profitWalletPocBuyback = _profitWallets.pocBuyback;
        profitWalletDao = _profitWallets.dao;
    }

    /**
     * @notice Set withdraw lock for launch token (only owner)
     * @dev Lock cannot be decreased, only increased
     * @param lockUntil Timestamp until which withdrawals should be locked
     */
    function setWithdrawLaunchLock(uint256 lockUntil) external override onlyOwner {
        require(lockUntil >= withdrawLaunchLockUntil, LockCannotBeDecreased());
        withdrawLaunchLockUntil = lockUntil;
        emit WithdrawLockUpdated(lockUntil);
    }

    /**
     * @notice Internal function to distribute profit
     * @dev Distribution: 5% MeraFund, 5% POC Royalty, 45% POC Buyback, 45% DAO
     * @param profit Profit amount to distribute
     */
    function _distributeProfitInternal(uint256 profit) internal {
        if (profit == 0) return;

        uint256 meraFundAmount = (profit * PROFIT_SHARE_MERA_FUND) / PERCENTAGE_DENOMINATOR;
        uint256 pocRoyaltyAmount = (profit * PROFIT_SHARE_POC_ROYALTY) / PERCENTAGE_DENOMINATOR;
        uint256 pocBuybackAmount = (profit * PROFIT_SHARE_POC_BUYBACK) / PERCENTAGE_DENOMINATOR;
        uint256 daoAmount = profit - meraFundAmount - pocRoyaltyAmount - pocBuybackAmount; // Remaining goes to DAO

        accumulatedProfitMeraFund += meraFundAmount;
        accumulatedProfitPocRoyalty += pocRoyaltyAmount;
        accumulatedProfitPocBuyback += pocBuybackAmount;
        accumulatedProfitDao += daoAmount;

        emit ProfitDistributed(profit);
    }

    /**
     * @notice Withdraw accumulated profits to all profit wallets
     * @dev Transfers profits to all wallets if they have accumulated profits (skips zero amounts)
     */
    function withdrawProfits() external override {
        // Withdraw MeraFund profit
        if (accumulatedProfitMeraFund > 0) {
            uint256 amount = accumulatedProfitMeraFund;
            accumulatedProfitMeraFund = 0;
            launchToken.safeTransfer(profitWalletMeraFund, amount);
            emit ProfitWithdrawn(profitWalletMeraFund, amount);
        }

        // Withdraw POC Royalty profit
        if (accumulatedProfitPocRoyalty > 0) {
            uint256 amount = accumulatedProfitPocRoyalty;
            accumulatedProfitPocRoyalty = 0;
            launchToken.safeTransfer(profitWalletPocRoyalty, amount);
            emit ProfitWithdrawn(profitWalletPocRoyalty, amount);
        }

        // Withdraw POC Buyback profit
        if (accumulatedProfitPocBuyback > 0) {
            uint256 amount = accumulatedProfitPocBuyback;
            accumulatedProfitPocBuyback = 0;
            launchToken.safeTransfer(profitWalletPocBuyback, amount);
            emit ProfitWithdrawn(profitWalletPocBuyback, amount);
        }

        // Withdraw DAO profit
        if (accumulatedProfitDao > 0) {
            uint256 amount = accumulatedProfitDao;
            accumulatedProfitDao = 0;
            launchToken.safeTransfer(profitWalletDao, amount);
            emit ProfitWithdrawn(profitWalletDao, amount);
        }
    }

    /**
     * @notice Increase allowance for tokens to spenders (only owner)
     * @dev Cannot increase allowance for launch token if locked
     * @param allowances Array of allowance parameters
     */
    function increaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external override onlyOwner {
        require(block.timestamp >= withdrawLaunchLockUntil, WithdrawLockNotExpired());
        for (uint256 i = 0; i < allowances.length; i++) {
            IERC20(allowances[i].token).safeIncreaseAllowance(allowances[i].spender, allowances[i].amount);
        }
    }

    /**
     * @notice Decrease allowance for tokens from spenders (only owner)
     * @param allowances Array of allowance parameters
     */
    function decreaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external override onlyOwner {
        for (uint256 i = 0; i < allowances.length; i++) {
            IERC20(allowances[i].token).safeDecreaseAllowance(allowances[i].spender, allowances[i].amount);
        }
    }

    /**
     * @notice Withdraw tokens from contract (only owner)
     * @dev Cannot withdraw launch token if locked
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external override onlyOwner {
        if (token == address(launchToken)) {
            require(block.timestamp >= withdrawLaunchLockUntil, WithdrawLaunchLocked());
        }
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice LP to POC rebalancing
     * @dev Algorithm:
     *      1. Swap launch -> collateral(s) on DEX (multiple swaps)
     *      2. Buy launch from POC contract(s) using collateral(s)
     *      3. Check that launch balance increased (profit)
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param amountsIn Array of input amounts for each swap (must match swapParamsArray length)
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function rebalanceLPtoPOC(
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external override launchBalanceIncreased {
        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            _swap(amountsIn[i], swapParamsArray[i]);
        }

        for (uint256 i = 0; i < pocBuyParamsArray.length; i++) {
            POCBuyParams calldata pocParams = pocBuyParamsArray[i];
            IProofOfCapital(pocParams.pocContract).buyTokens(pocParams.collateralAmount);
        }
    }

    /**
     * @notice POC to LP rebalancing
     * @dev Algorithm:
     *      1. Sell launch to POC contract for collateral
     *      2. Buy launch for all received collateral in LP pool
     *      3. Check that in profit (launch balance increased)
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     */
    function rebalancePOCtoLP(POCSellParams[] calldata pocSellParamsArray, SwapParams[] calldata swapParamsArray)
        external
        override
        launchBalanceIncreased
    {
        for (uint256 i = 0; i < pocSellParamsArray.length; i++) {
            POCSellParams calldata pocParams = pocSellParamsArray[i];
            IProofOfCapital(pocParams.pocContract).sellTokens(pocParams.launchAmount);
        }

        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            SwapParams calldata swapParams = swapParamsArray[i];
            address collateralToken = _getTokenIn(swapParams);
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));

            _swap(collateralBalance, swapParams);
        }
    }

    /**
     * @notice POC to LP to POC rebalancing
     * @dev Algorithm:
     *      1. Sell launch to POC contract for collateral
     *      2. Swap all received collateral to another collateral via specified path
     *      3. Buy launch from another POC contract using new collateral
     *      4. Check that in profit (launch balance increased)
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function rebalancePOCtoPOC(
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external override launchBalanceIncreased {
        for (uint256 i = 0; i < pocSellParamsArray.length; i++) {
            POCSellParams calldata pocParams = pocSellParamsArray[i];
            IProofOfCapital(pocParams.pocContract).sellTokens(pocParams.launchAmount);
        }

        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            SwapParams calldata swapParams = swapParamsArray[i];
            address collateralToken = _getTokenIn(swapParams);
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));

            _swap(collateralBalance, swapParams);
        }

        for (uint256 i = 0; i < pocBuyParamsArray.length; i++) {
            POCBuyParams calldata pocParams = pocBuyParamsArray[i];
            IProofOfCapital(pocParams.pocContract).buyTokens(pocParams.collateralAmount);
        }
    }

    /**
     * @notice Get input token address from swap params
     * @dev For V2: from path[0], For V3: from encoded path in data (first 20 bytes)
     * @param swapParams Swap parameters
     * @return Input token address
     */
    function _getTokenIn(SwapParams calldata swapParams) internal pure returns (address) {
        if (swapParams.routerType == RouterType.UniswapV2) {
            require(swapParams.path.length > 0, InvalidPath());
            return swapParams.path[0];
        } else {
            // For V3, path is encoded as: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
            require(swapParams.data.length >= 20, InvalidV3Path());
            // Get first 20 bytes explicitly using slice
            bytes calldata first20Bytes = swapParams.data[0:20];
            return address(bytes20(first20Bytes));
        }
    }

    /**
     * @notice Internal swap function
     * @dev Tokens must be approved for the router before calling this function
     * @param amountIn Amount of input tokens to swap
     * @param swapParams Swap parameters
     * @return amountOut Amount of output tokens received
     */
    function _swap(uint256 amountIn, SwapParams calldata swapParams) internal returns (uint256 amountOut) {
        if (swapParams.routerType == RouterType.UniswapV2) {
            uint256[] memory amounts = IUniswapV2Router02(swapParams.routerAddress)
                .swapExactTokensForTokens(
                    amountIn, swapParams.amountOutMinimum, swapParams.path, address(this), type(uint256).max
                );
            amountOut = amounts[amounts.length - 1];
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
    }
}

