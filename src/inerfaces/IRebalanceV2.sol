/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRebalanceV2 Interface
 * @dev Interface for RebalanceV2 contract with rebalancing operations and profit distribution
 */

/// @notice Router types supported by the contract
enum RouterType {
    UniswapV2,
    UniswapV3,
    QuickswapV3
}

/**
 * @notice Parameters for DEX swap operations
 * @param routerType Type of router to use (UniswapV2, UniswapV3, or QuickswapV3)
 * @param routerAddress Address of the router contract
 * @param path Swap path for V2 routers (empty array for V3 routers)
 * @param data Encoded path for V3 routers (token0 + fee + token1)
 * @param amountOutMinimum Minimum amount of output tokens to accept
 */
struct SwapParams {
    RouterType routerType;
    address routerAddress;
    address[] path;
    bytes data;
    uint256 amountOutMinimum;
}

/**
 * @notice Parameters for buying tokens from POC contract
 * @param pocContract Address of the POC contract
 * @param collateral Collateral token address to use for purchase
 * @param collateralAmount Amount of collateral tokens to spend
 */
struct POCBuyParams {
    address pocContract;
    address collateral;
    uint256 collateralAmount;
}

/**
 * @notice Parameters for selling tokens to POC contract
 * @param pocContract Address of the POC contract
 * @param launchAmount Amount of launch tokens to sell
 */
struct POCSellParams {
    address pocContract;
    uint256 launchAmount;
}

/**
 * @notice Parameters for setting token allowances
 * @param token Token address to set allowance for
 * @param spender Address that will be allowed to spend tokens
 * @param amount Amount of tokens to allow
 */
struct AllowanceParams {
    address token;
    address spender;
    uint256 amount;
}

/**
 * @notice Profit distribution wallet addresses
 * @param meraFund MeraFund wallet address (receives 5% of profits)
 * @param pocRoyalty POC Royalty wallet address (receives 5% of profits)
 * @param pocBuyback POC Buyback wallet address (receives 45% of profits)
 * @param dao DAO wallet address (receives 45% of profits)
 */
struct ProfitWallets {
    address meraFund;
    address pocRoyalty;
    address pocBuyback;
    address dao;
}

/**
 * @title IRebalanceV2
 * @dev Interface for RebalanceV2 contract
 */
interface IRebalanceV2 {
    // ============ Errors ============

    /// @notice Thrown when launch token balance doesn't increase after rebalancing
    error LaunchTokenBalanceNotIncreased();

    /// @notice Thrown when trying to withdraw launch token before lock expires
    error WithdrawLaunchLocked();

    /// @notice Thrown when trying to perform operation before withdraw lock expires
    error WithdrawLockNotExpired();

    /// @notice Thrown when profit wallet address is zero
    error InvalidProfitWalletAddress();

    /// @notice Thrown when no profit is generated
    error NoProfit();

    /// @notice Thrown when trying to decrease withdraw lock
    error LockCannotBeDecreased();

    /// @notice Thrown when V3 swap path is invalid
    error InvalidV3Path();

    /// @notice Thrown when swap path is invalid
    error InvalidPath();

    // ============ Events ============

    /// @notice Emitted when withdraw lock is updated
    /// @param lockUntil Timestamp until which withdrawals are locked
    event WithdrawLockUpdated(uint256 lockUntil);

    /// @notice Emitted when profit is distributed
    /// @param totalProfit Total profit amount distributed
    event ProfitDistributed(uint256 totalProfit);

    /// @notice Emitted when profit is withdrawn to a wallet
    /// @param wallet Address of the wallet receiving profit
    /// @param amount Amount of profit withdrawn
    event ProfitWithdrawn(address indexed wallet, uint256 amount);

    // ============ View Functions ============

    /// @notice Returns the launch token address
    /// @return Address of the launch token
    function launchToken() external view returns (IERC20);

    /// @notice Returns the timestamp until which launch token withdrawals are locked
    /// @return Timestamp until which withdrawals are locked
    function withdrawLaunchLockUntil() external view returns (uint256);

    /// @notice Returns the MeraFund profit wallet address
    /// @return Address of the MeraFund wallet
    function profitWalletMeraFund() external view returns (address);

    /// @notice Returns the POC Royalty profit wallet address
    /// @return Address of the POC Royalty wallet
    function profitWalletPocRoyalty() external view returns (address);

    /// @notice Returns the POC Buyback profit wallet address
    /// @return Address of the POC Buyback wallet
    function profitWalletPocBuyback() external view returns (address);

    /// @notice Returns the DAO profit wallet address
    /// @return Address of the DAO wallet
    function profitWalletDao() external view returns (address);

    /// @notice Returns accumulated profit for MeraFund wallet
    /// @return Accumulated profit amount
    function accumulatedProfitMeraFund() external view returns (uint256);

    /// @notice Returns accumulated profit for POC Royalty wallet
    /// @return Accumulated profit amount
    function accumulatedProfitPocRoyalty() external view returns (uint256);

    /// @notice Returns accumulated profit for POC Buyback wallet
    /// @return Accumulated profit amount
    function accumulatedProfitPocBuyback() external view returns (uint256);

    /// @notice Returns accumulated profit for DAO wallet
    /// @return Accumulated profit amount
    function accumulatedProfitDao() external view returns (uint256);

    // ============ State-Changing Functions ============

    /// @notice Set withdraw lock for launch token (only owner)
    /// @dev Lock cannot be decreased, only increased
    /// @param lockUntil Timestamp until which withdrawals should be locked
    function setWithdrawLaunchLock(uint256 lockUntil) external;

    /// @notice Withdraw accumulated profits to all profit wallets
    /// @dev Transfers profits to all wallets if they have accumulated profits (skips zero amounts)
    function withdrawProfits() external;

    /// @notice Increase allowance for tokens to spenders (only owner)
    /// @param allowances Array of allowance parameters
    function increaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external;

    /// @notice Decrease allowance for tokens from spenders (only owner)
    /// @param allowances Array of allowance parameters
    function decreaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external;

    /// @notice Withdraw tokens from contract (only owner)
    /// @dev Cannot withdraw launch token if locked
    /// @param token Token address to withdraw
    /// @param amount Amount to withdraw
    function withdraw(address token, uint256 amount) external;

    /// @notice LP to POC rebalancing
    /// @dev Algorithm:
    ///      1. Swap launch -> collateral(s) on DEX (multiple swaps)
    ///      2. Buy launch from POC contract(s) using collateral(s)
    ///      3. Check that launch balance increased (profit)
    /// @param swapParamsArray Array of swap parameters for DEX swaps
    /// @param pocBuyParamsArray Array of POC buy parameters
    function rebalanceLPtoPOC(SwapParams[] calldata swapParamsArray, POCBuyParams[] calldata pocBuyParamsArray) external;

    /// @notice POC to LP rebalancing
    /// @dev Algorithm:
    ///      1. Sell launch to POC contract for collateral
    ///      2. Buy launch for all received collateral in LP pool
    ///      3. Check that in profit (launch balance increased)
    /// @param pocSellParamsArray Array of POC sell parameters
    /// @param swapParamsArray Array of swap parameters for DEX swaps
    function rebalancePOCtoLP(POCSellParams[] calldata pocSellParamsArray, SwapParams[] calldata swapParamsArray)
        external;

    /// @notice POC to LP to POC rebalancing
    /// @dev Algorithm:
    ///      1. Sell launch to POC contract for collateral
    ///      2. Swap all received collateral to another collateral via specified path
    ///      3. Buy launch from another POC contract using new collateral
    ///      4. Check that in profit (launch balance increased)
    /// @param pocSellParamsArray Array of POC sell parameters
    /// @param swapParamsArray Array of swap parameters for DEX swaps
    /// @param pocBuyParamsArray Array of POC buy parameters
    function rebalancePOCtoPOC(
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external;
}

