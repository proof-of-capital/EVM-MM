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
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRebalanceV2.sol";
import "./interfaces/IProofOfCapital.sol";
import "./interfaces/IQuickswapV3Router.sol";
import "./interfaces/IQuoterQuickswap.sol";
import "./interfaces/IQuoterV2.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/ISwapRouterBase.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/DataTypes.sol";
import "./interfaces/IOTCv2.sol";

/**
 * @title RebalanceV2 Contract for Proof of Capital
 * @dev Contract for performing rebalancing operations between POC contracts and DEX with profit distribution
 */
contract RebalanceV2 is Ownable, IRebalanceV2 {
    using SafeERC20 for IERC20;

    IERC20 public immutable override launchToken;

    // Withdraw lock timestamp for launch token
    uint256 public override withdrawLaunchLockUntil;

    // Profit distribution wallets (MeraFund, Royalty, and Buyback can be changed by their owners)
    address public override profitWalletMeraFund;
    address public override profitWalletPocRoyalty;
    address public override profitWalletPocBuyback;
    address public override profitWalletDao;

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

    // Minimum profit percentage in basis points (10000 bps = 100%)
    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MIN_PROFIT_BPS = 100; // 1%
    uint256 private constant MAX_PROFIT_BPS = 500; // 5%

    // Minimum profit percentage required (in basis points)
    uint256 public override minProfitBps;

    // Admin role (can be set by DAO)
    address public admin;

    // Action publishing system
    mapping(bytes32 => uint256) public publishedActions; // action hash => publication timestamp
    mapping(bytes32 => bool) public executedActions; // action hash => executed flag

    // Time constants for action publishing
    uint256 private constant DELAY = 60; // 1 minute delay before execution
    uint256 private constant WINDOW = 600; // 10 minutes execution window

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, OnlyAdmin());
        _;
    }

    modifier onlyDao() {
        require(msg.sender == profitWalletDao, OnlyDao());
        _;
    }

    /**
     * @notice Set admin address (only DAO can call)
     * @param newAdmin New admin address
     */
    function setAdmin(address newAdmin) external onlyDao {
        require(newAdmin != address(0), InvalidProfitWalletAddress());
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminSet(oldAdmin, newAdmin);
    }

    /**
     * @notice Internal function to check profit and distribute it
     * @dev Checks that launch token balance increased and profit meets minimum requirement based on used launch tokens
     * @param initialLaunchBalance Initial launch token balance before operation
     * @param usedLaunchTokens Amount of launch tokens used in the operation
     */
    function _checkProfitAndDistribute(uint256 initialLaunchBalance, uint256 usedLaunchTokens) internal {
        uint256 finalLaunchBalance = launchToken.balanceOf(address(this));
        require(finalLaunchBalance > initialLaunchBalance, LaunchTokenBalanceNotIncreased());

        // Calculate profit
        uint256 profit = finalLaunchBalance - initialLaunchBalance;

        // Check minimum profit percentage requirement based on used launch tokens
        uint256 minRequiredProfit = (usedLaunchTokens * minProfitBps) / BPS_DENOMINATOR;
        require(profit >= minRequiredProfit, MinProfitNotReached());

        // Distribute profit
        _distributeProfitInternal(profit);
    }

    constructor(address _launchToken, ProfitWallets memory _profitWallets) Ownable(msg.sender) {
        launchToken = IERC20(_launchToken);
        require(_profitWallets.meraFund != address(0), InvalidProfitWalletAddress());
        require(_profitWallets.pocRoyalty != address(0), InvalidProfitWalletAddress());
        require(_profitWallets.pocBuyback != address(0), InvalidProfitWalletAddress());
        profitWalletMeraFund = _profitWallets.meraFund;
        profitWalletPocRoyalty = _profitWallets.pocRoyalty;
        profitWalletPocBuyback = _profitWallets.pocBuyback;
        profitWalletDao = _profitWallets.dao;
        minProfitBps = MIN_PROFIT_BPS; // Default: 1% (100 bps)
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
     * @notice Set minimum profit percentage in basis points (only owner)
     * @dev Value must be between MIN_PROFIT_BPS (100) and MAX_PROFIT_BPS (500)
     * @param _minProfitBps Minimum profit percentage in basis points (100 = 1%, 500 = 5%)
     */
    function setMinProfitBps(uint256 _minProfitBps) external override onlyOwner {
        require(_minProfitBps >= MIN_PROFIT_BPS && _minProfitBps <= MAX_PROFIT_BPS, InvalidMinProfitBps());
        minProfitBps = _minProfitBps;
        emit MinProfitBpsUpdated(_minProfitBps);
    }

    /**
     * @notice Set DAO profit wallet address (only owner, only when current DAO is zero)
     * @dev Can be called only once when profitWalletDao is address(0)
     * @param _dao New DAO wallet address (must be non-zero)
     */
    function setProfitWalletDao(address _dao) external override onlyOwner {
        require(profitWalletDao == address(0), DaoAlreadySet());
        require(_dao != address(0), InvalidProfitWalletAddress());
        profitWalletDao = _dao;
        emit DaoWalletSet(_dao);
    }

    /**
     * @notice Change MeraFund wallet address (only current MeraFund wallet can call)
     * @dev Transfers accumulated profit to new wallet if any exists
     * @param newWallet New MeraFund wallet address
     */
    function changeMeraFundWallet(address newWallet) external override {
        require(msg.sender == profitWalletMeraFund, OnlyMeraFundWalletCanChange());
        require(newWallet != address(0), InvalidProfitWalletAddress());

        address oldWallet = profitWalletMeraFund;
        uint256 accumulatedProfit = accumulatedProfitMeraFund;

        // Transfer accumulated profit to new wallet if any exists
        if (accumulatedProfit > 0) {
            accumulatedProfitMeraFund = 0;
            launchToken.safeTransfer(newWallet, accumulatedProfit);
            emit ProfitWithdrawn(newWallet, accumulatedProfit);
        }

        // Update wallet address
        profitWalletMeraFund = newWallet;
        emit MeraFundWalletChanged(oldWallet, newWallet);
    }

    /**
     * @notice Change Royalty wallet address (only current Royalty wallet can call)
     * @dev Transfers accumulated profit to new wallet if any exists
     * @param newWallet New Royalty wallet address
     */
    function changeRoyaltyWallet(address newWallet) external override {
        require(msg.sender == profitWalletPocRoyalty, OnlyRoyaltyWalletCanChange());
        require(newWallet != address(0), InvalidProfitWalletAddress());

        address oldWallet = profitWalletPocRoyalty;
        uint256 accumulatedProfit = accumulatedProfitPocRoyalty;

        // Transfer accumulated profit to new wallet if any exists
        if (accumulatedProfit > 0) {
            accumulatedProfitPocRoyalty = 0;
            launchToken.safeTransfer(newWallet, accumulatedProfit);
            emit ProfitWithdrawn(newWallet, accumulatedProfit);
        }

        // Update wallet address
        profitWalletPocRoyalty = newWallet;
        emit RoyaltyWalletChanged(oldWallet, newWallet);
    }

    /**
     * @notice Change Return wallet address (only current Return wallet can call)
     * @dev Transfers accumulated profit to new wallet if any exists
     * @param newWallet New Return wallet address
     */
    function changeReturnWallet(address newWallet) external override {
        require(msg.sender == profitWalletPocBuyback, OnlyReturnWalletCanChange());
        require(newWallet != address(0), InvalidProfitWalletAddress());

        address oldWallet = profitWalletPocBuyback;
        uint256 accumulatedProfit = accumulatedProfitPocBuyback;

        // Transfer accumulated profit to new wallet if any exists
        if (accumulatedProfit > 0) {
            accumulatedProfitPocBuyback = 0;
            launchToken.safeTransfer(newWallet, accumulatedProfit);
            emit ProfitWithdrawn(newWallet, accumulatedProfit);
        }

        // Update wallet address
        profitWalletPocBuyback = newWallet;
        emit ReturnWalletChanged(oldWallet, newWallet);
    }

    /**
     * @notice Internal function to check if withdraw is unlocked
     * @dev Checks if DAO is in Dissolved stage
     * @return true if DAO is dissolved, false otherwise
     */
    function _isWithdrawUnlocked() internal view returns (bool) {
        // No DAO means no lock (withdrawal unlocked)
        if (profitWalletDao == address(0)) return true;
        // Check if DAO is dissolved
        try IDAO(profitWalletDao).getDaoState() returns (DataTypes.DAOState memory daoState) {
            return daoState.currentStage == DataTypes.Stage.Dissolved;
        } catch {
            // If DAO call fails, withdrawal remains locked
            return false;
        }
    }

    /**
     * @notice Check if address is an active POC contract in DAO
     * @param spender Address to check
     * @return true if spender is an active POC contract
     */
    function _isPOCContract(address spender) internal view returns (bool) {
        if (profitWalletDao == address(0)) return false;
        try IDAO(profitWalletDao).pocIndex(spender) returns (uint256 index) {
            try IDAO(profitWalletDao).getPOCContract(index) returns (DataTypes.POCInfo memory pocInfo) {
                return pocInfo.active && pocInfo.pocContract == spender;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /**
     * @notice Check if withdraw is unlocked (DAO is dissolved)
     * @return true if DAO is dissolved, false otherwise
     */
    function isWithdrawUnlocked() external view override returns (bool) {
        return _isWithdrawUnlocked();
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

        // Withdraw DAO profit (only when DAO is set)
        if (profitWalletDao != address(0) && accumulatedProfitDao > 0) {
            uint256 amount = accumulatedProfitDao;
            accumulatedProfitDao = 0;
            launchToken.safeTransfer(profitWalletDao, amount);
            emit ProfitWithdrawn(profitWalletDao, amount);
        }
    }

    /**
     * @notice Increase allowance for tokens to spenders (only owner)
     * @dev Cannot increase allowance unless: DAO is dissolved OR spender is an active POC contract in DAO
     * @param allowances Array of allowance parameters
     */
    function increaseAllowanceForSpenders(AllowanceParams[] calldata allowances) external override onlyOwner {
        bool isUnlocked = _isWithdrawUnlocked();

        for (uint256 i = 0; i < allowances.length; i++) {
            // Allow if DAO is dissolved OR spender is POC contract
            bool allowed = isUnlocked || _isPOCContract(allowances[i].spender);

            require(allowed, WithdrawLockNotExpired());
            IERC20(allowances[i].token).safeIncreaseAllowance(allowances[i].spender, allowances[i].amount);
        }
    }

    /**
     * @notice Withdraw tokens from contract (only owner)
     * @dev Cannot withdraw launch token if locked (requires DAO to be dissolved)
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external override onlyOwner {
        if (token == address(launchToken)) {
            require(_isWithdrawUnlocked(), WithdrawLaunchLocked());
        }
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice LP to POC rebalancing (internal)
     * @dev Algorithm:
     *      1. Swap launch -> collateral(s) on DEX (multiple swaps)
     *      2. Buy launch from POC contract(s) using collateral(s)
     *      3. Check that launch balance increased (profit)
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param amountsIn Array of input amounts for each swap (must match swapParamsArray length)
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function _rebalanceLPtoPOC(
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        POCBuyParams[] calldata pocBuyParamsArray
    ) internal {
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        // Calculate sum of all used launch tokens
        uint256 sumOfAmountsIn = 0;
        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            sumOfAmountsIn += amountsIn[i];
            address collateralToken = _getTokenOut(swapParamsArray[i]);
            require(collateralToken == pocBuyParamsArray[i].collateral, InvalidCollateralToken());
            _swap(amountsIn[i], swapParamsArray[i]);
        }

        for (uint256 i = 0; i < pocBuyParamsArray.length; i++) {
            POCBuyParams calldata pocParams = pocBuyParamsArray[i];
            IProofOfCapital(pocParams.pocContract)
                .buyLaunchTokens(IERC20(pocParams.collateral).balanceOf(address(this)), 0);
        }

        _checkProfitAndDistribute(initialLaunchBalance, sumOfAmountsIn);
    }

    /**
     * @notice POC to LP rebalancing (internal)
     * @dev Algorithm:
     *      1. Sell launch to POC contract for collateral
     *      2. Buy launch for all received collateral in LP pool
     *      3. Check that in profit (launch balance increased)
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     */
    function _rebalancePOCtoLP(POCSellParams[] calldata pocSellParamsArray, SwapParams[] calldata swapParamsArray)
        internal
    {
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        uint256 sumOfLaunchAmounts = 0;
        for (uint256 i = 0; i < pocSellParamsArray.length; i++) {
            sumOfLaunchAmounts += pocSellParamsArray[i].launchAmount;
            POCSellParams calldata pocParams = pocSellParamsArray[i];
            uint256 minOut = (i == 0) ? pocSellParamsArray[0].minCollateralOut : 0;
            IProofOfCapital(pocParams.pocContract).sellLaunchTokens(pocParams.launchAmount, minOut);
        }

        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            SwapParams calldata swapParams = swapParamsArray[i];
            address collateralToken = _getTokenIn(swapParams);
            require(
                collateralToken == address(IProofOfCapital(pocSellParamsArray[i].pocContract).collateralToken()),
                InvalidCollateralToken()
            );
            address tokenOut = _getTokenOut(swapParams);
            require(tokenOut == address(launchToken), InvalidLaunchToken());
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));

            _swap(collateralBalance, swapParams);
        }

        _checkProfitAndDistribute(initialLaunchBalance, sumOfLaunchAmounts);
    }

    /**
     * @notice POC to LP to POC rebalancing (internal)
     * @dev Algorithm:
     *      1. Sell launch to POC contract for collateral
     *      2. Swap all received collateral to another collateral via specified path
     *      3. Buy launch from another POC contract using new collateral
     *      4. Check that in profit (launch balance increased)
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function _rebalancePOCtoPOC(
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray,
        POCBuyParams[] calldata pocBuyParamsArray
    ) internal {
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        uint256 sumOfLaunchAmounts = 0;
        for (uint256 i = 0; i < pocSellParamsArray.length; i++) {
            sumOfLaunchAmounts += pocSellParamsArray[i].launchAmount;
            POCSellParams calldata pocParams = pocSellParamsArray[i];
            uint256 minCollateral = (i == 0) ? pocSellParamsArray[0].minCollateralOut : 0;
            IProofOfCapital(pocParams.pocContract).sellLaunchTokens(pocParams.launchAmount, minCollateral);
        }

        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            SwapParams calldata swapParams = swapParamsArray[i];
            address tokenIn = _getTokenIn(swapParams);
            require(
                address(IProofOfCapital(pocSellParamsArray[i].pocContract).collateralToken()) == tokenIn,
                InvalidCollateralToken()
            );
            address tokenOut = _getTokenOut(swapParams);
            require(tokenOut == pocBuyParamsArray[i].collateral, InvalidCollateralToken());
            uint256 tokenInBalance = IERC20(tokenIn).balanceOf(address(this));

            _swap(tokenInBalance, swapParams);
        }

        for (uint256 i = 0; i < pocBuyParamsArray.length; i++) {
            POCBuyParams calldata pocParams = pocBuyParamsArray[i];
            IProofOfCapital(pocParams.pocContract)
                .buyLaunchTokens(IERC20(pocParams.collateral).balanceOf(address(this)), 0);
        }

        _checkProfitAndDistribute(initialLaunchBalance, sumOfLaunchAmounts);
    }

    /**
     * @notice OTC supply rebalancing (internal): supply LAUNCH to OTC, receive INPUT, buy LAUNCH from POC with INPUT as collateral
     * @dev Single transaction, no DEX swaps. ERC20 INPUT only (no ETH).
     * @param otc OTCv2 supply contract (this contract must be its admin)
     * @param pocBuyParams Single POC buy (collateral must equal otc.INPUT_TOKEN())
     */
    function _rebalanceSupplyOTC(IOTCv2 otc, POCBuyParams calldata pocBuyParams) internal {
        require(address(otc) != address(0), InvalidOTC());
        require(otc.ADMIN_ADDRESS() == address(this), NotOTCAdmin());
        require(otc.OUTPUT_TOKEN() == address(launchToken), OTCOutputMismatch());
        require(otc.INPUT_TOKEN() != address(0), OTCInputIsEth());
        require(pocBuyParams.collateral == otc.INPUT_TOKEN(), CollateralNotOTCInput());

        (, uint256 outputAmount) = otc.supplies(otc.currentSupplyIndex());
        uint256 usedLaunchTokens = outputAmount;
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        launchToken.safeIncreaseAllowance(address(otc), usedLaunchTokens);
        otc.supplyOutput();

        uint256 collateralBalance = IERC20(pocBuyParams.collateral).balanceOf(address(this));
        require(pocBuyParams.collateralAmount <= collateralBalance, InsufficientCollateralBalance());

        IERC20(pocBuyParams.collateral).safeIncreaseAllowance(pocBuyParams.pocContract, pocBuyParams.collateralAmount);
        IProofOfCapital(pocBuyParams.pocContract)
            .buyLaunchTokens(pocBuyParams.collateralAmount, pocBuyParams.minLaunchTokensOut);

        _checkProfitAndDistribute(initialLaunchBalance, usedLaunchTokens);
    }

    /**
     * @notice OTC supply via LP (internal): supply LAUNCH to OTC, receive INPUT, swap INPUT→LAUNCH on DEX
     * @dev Launch→Collateral direction; conversion via DEX only
     * @param otc OTCv2 supply contract (this contract must be its admin)
     * @param swapParamsArray Swap parameters (path collateral → launch)
     * @param amountsIn Input amounts for each swap
     */
    function _rebalanceSupplyOTCViaLP(IOTCv2 otc, SwapParams[] calldata swapParamsArray, uint256[] calldata amountsIn)
        internal
    {
        require(address(otc) != address(0), InvalidOTC());
        require(otc.ADMIN_ADDRESS() == address(this), NotOTCAdmin());
        require(otc.OUTPUT_TOKEN() == address(launchToken), OTCOutputMismatch());
        require(otc.INPUT_TOKEN() != address(0), OTCInputIsEth());
        address collateralToken = otc.INPUT_TOKEN();

        (, uint256 outputAmount) = otc.supplies(otc.currentSupplyIndex());
        uint256 usedLaunchTokens = outputAmount;
        uint256 initialLaunchBalance = launchToken.balanceOf(address(this));

        launchToken.safeIncreaseAllowance(address(otc), usedLaunchTokens);
        otc.supplyOutput();

        uint256 collateralBalanceBefore = IERC20(collateralToken).balanceOf(address(this));
        require(swapParamsArray.length == amountsIn.length, InvalidPath());
        uint256 sumOfAmountsIn = 0;
        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            sumOfAmountsIn += amountsIn[i];
            require(_getTokenIn(swapParamsArray[i]) == collateralToken, InvalidCollateralToken());
            require(_getTokenOut(swapParamsArray[i]) == address(launchToken), InvalidLaunchToken());
            _swap(amountsIn[i], swapParamsArray[i]);
        }
        require(sumOfAmountsIn == collateralBalanceBefore, InvalidCollateralToken());

        _checkProfitAndDistribute(initialLaunchBalance, usedLaunchTokens);
    }

    /**
     * @notice Supply to OTC from collateral via POC (internal): withdraw INPUT from OTC, buy LAUNCH on POC, send LAUNCH to OTC
     * @dev Collateral→Launch direction; conversion via POC only
     * @param otc OTCv2 contract (this contract must be its admin)
     * @param collateralAmount Amount of INPUT to withdraw from OTC
     * @param pocBuyParamsArray POC buy parameters (collateral must equal otc.INPUT_TOKEN())
     * @param minLaunchToSendToOtc Minimum launch tokens to send to OTC
     */
    function _supplyToOTCFromCollateralViaPOC(
        IOTCv2 otc,
        uint256 collateralAmount,
        POCBuyParams[] calldata pocBuyParamsArray,
        uint256 minLaunchToSendToOtc
    ) internal {
        require(address(otc) != address(0), InvalidOTC());
        require(otc.ADMIN_ADDRESS() == address(this), NotOTCAdmin());
        require(otc.OUTPUT_TOKEN() == address(launchToken), OTCOutputMismatch());
        require(otc.INPUT_TOKEN() != address(0), OTCInputIsEth());

        otc.withdrawInput(collateralAmount);
        address collateralToken = otc.INPUT_TOKEN();

        uint256 launchBalanceBefore = launchToken.balanceOf(address(this));
        for (uint256 i = 0; i < pocBuyParamsArray.length; i++) {
            require(pocBuyParamsArray[i].collateral == collateralToken, CollateralNotOTCInput());
            IERC20(collateralToken)
                .safeIncreaseAllowance(pocBuyParamsArray[i].pocContract, pocBuyParamsArray[i].collateralAmount);
            uint256 minOut = (i == 0) ? pocBuyParamsArray[i].minLaunchTokensOut : 0;
            IProofOfCapital(pocBuyParamsArray[i].pocContract)
                .buyLaunchTokens(pocBuyParamsArray[i].collateralAmount, minOut);
        }

        uint256 totalLaunchReceived = launchToken.balanceOf(address(this)) - launchBalanceBefore;
        require(totalLaunchReceived >= minLaunchToSendToOtc, InsufficientLaunchForOTC());
        uint256 profit = totalLaunchReceived - minLaunchToSendToOtc;
        if (profit > 0) {
            _distributeProfitInternal(profit);
        }
        launchToken.safeTransfer(address(otc), minLaunchToSendToOtc);
        otc.receiveSupplyFromAdmin(minLaunchToSendToOtc);
    }

    /**
     * @notice Supply to OTC from collateral via LP (internal): withdraw INPUT from OTC, swap to LAUNCH on DEX, send LAUNCH to OTC
     * @dev Collateral→Launch direction; conversion via DEX only
     * @param otc OTCv2 contract (this contract must be its admin)
     * @param collateralAmount Amount of INPUT to withdraw from OTC
     * @param swapParamsArray Swap parameters (collateral → launch)
     * @param amountsIn Input amounts per swap
     * @param minLaunchToSendToOtc Minimum launch tokens to send to OTC
     */
    function _supplyToOTCFromCollateralViaLP(
        IOTCv2 otc,
        uint256 collateralAmount,
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        uint256 minLaunchToSendToOtc
    ) internal {
        require(address(otc) != address(0), InvalidOTC());
        require(otc.ADMIN_ADDRESS() == address(this), NotOTCAdmin());
        require(otc.OUTPUT_TOKEN() == address(launchToken), OTCOutputMismatch());
        require(otc.INPUT_TOKEN() != address(0), OTCInputIsEth());
        address collateralToken = otc.INPUT_TOKEN();

        otc.withdrawInput(collateralAmount);

        require(swapParamsArray.length == amountsIn.length, InvalidPath());
        uint256 sumOfAmountsIn = 0;
        for (uint256 i = 0; i < amountsIn.length; i++) {
            sumOfAmountsIn += amountsIn[i];
        }
        require(sumOfAmountsIn == collateralAmount, InvalidCollateralToken());
        uint256 launchBalanceBefore = launchToken.balanceOf(address(this));
        for (uint256 i = 0; i < swapParamsArray.length; i++) {
            require(_getTokenIn(swapParamsArray[i]) == collateralToken, InvalidCollateralToken());
            require(_getTokenOut(swapParamsArray[i]) == address(launchToken), InvalidLaunchToken());
            _swap(amountsIn[i], swapParamsArray[i]);
        }

        uint256 totalLaunchReceived = launchToken.balanceOf(address(this)) - launchBalanceBefore;
        require(totalLaunchReceived >= minLaunchToSendToOtc, InsufficientLaunchForOTC());
        uint256 profit = totalLaunchReceived - minLaunchToSendToOtc;
        if (profit > 0) {
            _distributeProfitInternal(profit);
        }
        launchToken.safeTransfer(address(otc), minLaunchToSendToOtc);
        otc.receiveSupplyFromAdmin(minLaunchToSendToOtc);
    }

    /**
     * @notice Admin LP to POC rebalancing (no delays)
     * @dev Admin can execute rebalancing without any delays
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param amountsIn Array of input amounts for each swap (must match swapParamsArray length)
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function adminRebalanceLPtoPOC(
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external onlyAdmin {
        _rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);
    }

    /**
     * @notice Admin POC to LP rebalancing (no delays)
     * @dev Admin can execute rebalancing without any delays
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     */
    function adminRebalancePOCtoLP(POCSellParams[] calldata pocSellParamsArray, SwapParams[] calldata swapParamsArray)
        external
        onlyAdmin
    {
        _rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    /**
     * @notice Admin POC to LP to POC rebalancing (no delays)
     * @dev Admin can execute rebalancing without any delays
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function adminRebalancePOCtoPOC(
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external onlyAdmin {
        _rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);
    }

    /**
     * @notice Admin OTC supply rebalancing (no delays)
     * @param otc OTCv2 supply contract
     * @param pocBuyParams POC buy parameters
     */
    function adminRebalanceSupplyOTC(IOTCv2 otc, POCBuyParams calldata pocBuyParams) external override onlyAdmin {
        _rebalanceSupplyOTC(otc, pocBuyParams);
    }

    /**
     * @notice Admin OTC supply via LP: supply LAUNCH to OTC, receive INPUT, swap INPUT→LAUNCH on DEX
     * @param otc OTCv2 supply contract
     * @param swapParamsArray Swap parameters (collateral → launch)
     * @param amountsIn Input amounts per swap
     */
    function adminRebalanceSupplyOTCViaLP(
        IOTCv2 otc,
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn
    ) external override onlyAdmin {
        _rebalanceSupplyOTCViaLP(otc, swapParamsArray, amountsIn);
    }

    /**
     * @notice Admin supply to OTC from collateral via POC: withdraw INPUT from OTC, buy LAUNCH on POC, send LAUNCH to OTC
     * @param otc OTCv2 supply contract
     * @param collateralAmount Amount of collateral to withdraw from OTC
     * @param pocBuyParamsArray POC buy parameters (collateral = otc.INPUT_TOKEN())
     * @param minLaunchToSendToOtc Minimum launch tokens to send to OTC (slippage)
     */
    function adminSupplyToOTCFromCollateralViaPOC(
        IOTCv2 otc,
        uint256 collateralAmount,
        POCBuyParams[] calldata pocBuyParamsArray,
        uint256 minLaunchToSendToOtc
    ) external override onlyAdmin {
        _supplyToOTCFromCollateralViaPOC(otc, collateralAmount, pocBuyParamsArray, minLaunchToSendToOtc);
    }

    /**
     * @notice Admin supply to OTC from collateral via LP: withdraw INPUT from OTC, swap to LAUNCH on DEX, send LAUNCH to OTC
     * @param otc OTCv2 supply contract
     * @param collateralAmount Amount of collateral to withdraw from OTC
     * @param swapParamsArray Swap parameters (collateral → launch)
     * @param amountsIn Input amounts per swap
     * @param minLaunchToSendToOtc Minimum launch tokens to send to OTC (slippage)
     */
    function adminSupplyToOTCFromCollateralViaLP(
        IOTCv2 otc,
        uint256 collateralAmount,
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        uint256 minLaunchToSendToOtc
    ) external override onlyAdmin {
        _supplyToOTCFromCollateralViaLP(otc, collateralAmount, swapParamsArray, amountsIn, minLaunchToSendToOtc);
    }

    /**
     * @notice Admin buyback launch tokens from OTC (sends collateral to OTC, receives launch to this contract)
     * @param otc OTCv2 contract
     * @param collateralAmount Amount of INPUT (collateral) to spend on buyback
     */
    function adminBuybackFromOTC(IOTCv2 otc, uint256 collateralAmount) external override onlyAdmin {
        require(address(otc) != address(0), InvalidOTC());
        require(otc.ADMIN_ADDRESS() == address(this), NotOTCAdmin());
        require(otc.OUTPUT_TOKEN() == address(launchToken), OTCOutputMismatch());
        require(otc.INPUT_TOKEN() != address(0), OTCInputIsEth());
        address inputToken = otc.INPUT_TOKEN();
        require(IERC20(inputToken).balanceOf(address(this)) >= collateralAmount, InsufficientCollateralBalance());
        IERC20(inputToken).safeIncreaseAllowance(address(otc), collateralAmount);
        otc.buybackWithToken(collateralAmount);
    }

    /**
     * @notice Publish action for delayed execution
     * @dev Users can publish their action calldata which will be executable after DELAY
     * @param actionData Future calldata with function selector and all parameters (including nonce if needed)
     */
    function publishAction(bytes calldata actionData) external {
        bytes32 actionHash = _calculateActionHash(msg.sender, actionData);
        require(publishedActions[actionHash] == 0, ActionAlreadyPublished());

        publishedActions[actionHash] = block.timestamp;
        emit ActionPublished(msg.sender, actionHash, block.timestamp);
    }

    /**
     * @notice Execute published LP to POC rebalancing action
     * @dev Executes published action after delay and within execution window
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param amountsIn Array of input amounts for each swap (must match swapParamsArray length)
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function executePublishedRebalanceLPtoPOC(
        uint256,
        /* nonce - not used in logic, only for hash calculation */
        SwapParams[] calldata swapParamsArray,
        uint256[] calldata amountsIn,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external {
        _validateAndMarkPublishedActionExecuted();
        _rebalanceLPtoPOC(swapParamsArray, amountsIn, pocBuyParamsArray);
    }

    /**
     * @notice Execute published POC to LP rebalancing action
     * @dev Executes published action after delay and within execution window
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     */
    function executePublishedRebalancePOCtoLP(
        uint256,
        /* nonce - not used in logic, only for hash calculation */
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray
    ) external {
        _validateAndMarkPublishedActionExecuted();
        _rebalancePOCtoLP(pocSellParamsArray, swapParamsArray);
    }

    /**
     * @notice Execute published POC to LP to POC rebalancing action
     * @dev Executes published action after delay and within execution window
     * @param pocSellParamsArray Array of POC sell parameters
     * @param swapParamsArray Array of swap parameters for DEX swaps
     * @param pocBuyParamsArray Array of POC buy parameters
     */
    function executePublishedRebalancePOCtoPOC(
        uint256,
        /* nonce - not used in logic, only for hash calculation */
        POCSellParams[] calldata pocSellParamsArray,
        SwapParams[] calldata swapParamsArray,
        POCBuyParams[] calldata pocBuyParamsArray
    ) external {
        _validateAndMarkPublishedActionExecuted();
        _rebalancePOCtoPOC(pocSellParamsArray, swapParamsArray, pocBuyParamsArray);
    }

    /**
     * @notice Execute published OTC supply rebalancing action
     * @dev Executes published action after delay and within execution window. OTC supply only via publish/execute.
     * @param nonce Nonce parameter (not used in logic, only for hash calculation)
     * @param otc OTCv2 supply contract
     * @param pocBuyParams POC buy parameters
     */
    function executePublishedRebalanceSupplyOTC(uint256 nonce, IOTCv2 otc, POCBuyParams calldata pocBuyParams)
        external
        override
    {
        _validateAndMarkPublishedActionExecuted();
        _rebalanceSupplyOTC(otc, pocBuyParams);
    }

    /**
     * @notice Validate published action timing and mark as executed
     * @dev Shared preamble for all executePublished*; uses msg.sender and msg.data from caller
     */
    function _validateAndMarkPublishedActionExecuted() internal returns (bytes32 actionHash) {
        actionHash = _calculateActionHash(msg.sender, msg.data);
        _validateActionTiming(actionHash);

        executedActions[actionHash] = true;
        emit ActionExecuted(msg.sender, actionHash);
    }

    /**
     * @notice Calculate action hash from user address and action data
     * @param user User address
     * @param actionData Action calldata
     * @return Action hash
     */
    function _calculateActionHash(address user, bytes calldata actionData) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, actionData));
    }

    /**
     * @notice Validate action timing (delay and window)
     * @param actionHash Action hash
     */
    function _validateActionTiming(bytes32 actionHash) internal view {
        uint256 publishedAt = publishedActions[actionHash];
        require(publishedAt != 0, ActionNotPublished());
        require(!executedActions[actionHash], ActionAlreadyExecuted());

        uint256 elapsed = block.timestamp - publishedAt;
        require(elapsed >= DELAY, ActionTooEarly());
        require(elapsed <= DELAY + WINDOW, ActionExpired());
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
     * @notice Get output token address from swap params
     * @dev For V2: from path[path.length - 1], For V3: from encoded path in data (last 20 bytes)
     * @param swapParams Swap parameters
     * @return Output token address
     */
    function _getTokenOut(SwapParams calldata swapParams) internal pure returns (address) {
        if (swapParams.routerType == RouterType.UniswapV2) {
            require(swapParams.path.length > 0, InvalidPath());
            return swapParams.path[swapParams.path.length - 1];
        } else {
            // For V3, path is encoded as: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
            // For multi-hop: token0 (20) + fee (3) + token1 (20) + fee (3) + token2 (20) + ...
            // Output token is always the last 20 bytes
            require(swapParams.data.length >= 20, InvalidV3Path());
            // Get last 20 bytes explicitly using slice
            uint256 dataLength = swapParams.data.length;
            bytes calldata last20Bytes = swapParams.data[dataLength - 20:dataLength];
            return address(bytes20(last20Bytes));
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
        } else if (swapParams.routerType == RouterType.SwapRouterBase) {
            ISwapRouterBase.ExactInputParams memory params = ISwapRouterBase.ExactInputParams({
                path: swapParams.data,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: swapParams.amountOutMinimum
            });
            amountOut = ISwapRouterBase(swapParams.routerAddress).exactInput(params);
        }
    }
}

