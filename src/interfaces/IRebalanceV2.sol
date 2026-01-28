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
    QuickswapV3,
    SwapRouterBase
}

/**
 * @notice Parameters for DEX swap operations
 * @param routerType Type of router to use (UniswapV2, UniswapV3, QuickswapV3, or SwapRouterBase)
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

    /// @notice Thrown when collateral token is invalid
    error InvalidCollateralToken();

    /// @notice Thrown when launch token is invalid
    error InvalidLaunchToken();

    /// @notice Thrown when minimum profit BPS value is invalid (not between 100 and 500)
    error InvalidMinProfitBps();

    /// @notice Thrown when profit doesn't reach minimum required percentage
    error MinProfitNotReached();

    /// @notice Thrown when trying to change MeraFund wallet from unauthorized address
    error OnlyMeraFundWalletCanChange();

    /// @notice Thrown when trying to change Royalty wallet from unauthorized address
    error OnlyRoyaltyWalletCanChange();

    /// @notice Thrown when trying to change Return wallet from unauthorized address
    error OnlyReturnWalletCanChange();

    /// @notice Thrown when trying to set DAO wallet but it is already set
    error DaoAlreadySet();

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

    /// @notice Emitted when minimum profit BPS is updated
    /// @param newMinProfitBps New minimum profit percentage in basis points
    event MinProfitBpsUpdated(uint256 newMinProfitBps);

    /// @notice Emitted when MeraFund wallet is changed
    /// @param oldWallet Previous MeraFund wallet address
    /// @param newWallet New MeraFund wallet address
    event MeraFundWalletChanged(address indexed oldWallet, address indexed newWallet);

    /// @notice Emitted when Royalty wallet is changed
    /// @param oldWallet Previous Royalty wallet address
    /// @param newWallet New Royalty wallet address
    event RoyaltyWalletChanged(address indexed oldWallet, address indexed newWallet);

    /// @notice Emitted when Return wallet is changed
    /// @param oldWallet Previous Return wallet address
    /// @param newWallet New Return wallet address
    event ReturnWalletChanged(address indexed oldWallet, address indexed newWallet);

    /// @notice Emitted when DAO wallet is set (only when current DAO is zero)
    /// @param dao Address of the DAO wallet
    event DaoWalletSet(address indexed dao);

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

    /// @notice Check if withdraw is unlocked (DAO is dissolved)
    /// @return true if DAO is dissolved, false otherwise
    function isWithdrawUnlocked() external view returns (bool);

    /// @notice Returns the minimum profit percentage in basis points
    /// @return Minimum profit percentage in basis points (100 = 1%, 500 = 5%)
    function minProfitBps() external view returns (uint256);

    // ============ State-Changing Functions ============

    /// @notice Set withdraw lock for launch token (only owner)
    /// @dev Lock cannot be decreased, only increased
    /// @param lockUntil Timestamp until which withdrawals should be locked
    function setWithdrawLaunchLock(uint256 lockUntil) external;

    /// @notice Set minimum profit percentage in basis points (only owner)
    /// @dev Value must be between 100 (1%) and 500 (5%) basis points
    /// @param _minProfitBps Minimum profit percentage in basis points
    function setMinProfitBps(uint256 _minProfitBps) external;

    /// @notice Set DAO profit wallet address (only owner, only when current DAO is zero)
    /// @dev Can be called only once when profitWalletDao is address(0)
    /// @param _dao New DAO wallet address (must be non-zero)
    function setProfitWalletDao(address _dao) external;

    /// @notice Change MeraFund wallet address (only current MeraFund wallet can call)
    /// @dev Transfers accumulated profit to new wallet if any exists
    /// @param newWallet New MeraFund wallet address
    function changeMeraFundWallet(address newWallet) external;

    /// @notice Change Royalty wallet address (only current Royalty wallet can call)
    /// @dev Transfers accumulated profit to new wallet if any exists
    /// @param newWallet New Royalty wallet address
    function changeRoyaltyWallet(address newWallet) external;

    /// @notice Change Return wallet address (only current Return wallet can call)
    /// @dev Transfers accumulated profit to new wallet if any exists
    /// @param newWallet New Return wallet address
    function changeReturnWallet(address newWallet) external;

    /// @notice Withdraw accumulated profits to all profit wallets
    /// @dev Transfers profits to all wallets if they have accumulated profits (skips zero amounts)
    function withdrawProfits() external;

    /// @notice Increase allowance for tokens to spenders (only owner)
    /// @param allowances Array of allowance parameters
    function increaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external;

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
    /// @param amountsIn Array of input amounts for each swap (must match swapParamsArray length)
    /// @param pocBuyParamsArray Array of POC buy parameters
    function rebalanceLPtoPOC(
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external;

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

