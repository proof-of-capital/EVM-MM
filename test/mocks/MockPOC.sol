// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IProofOfCapital} from "../../src/interfaces/IProofOfCapital.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock POC contract
contract MockPOC is IProofOfCapital {
    IERC20 internal _launchToken;
    IERC20 internal _collateralToken;
    uint256 public tokensReceivedOnBuy;
    uint256 public tokensSoldOnSell;
    address public caller;

    constructor(address launchToken_, address collateralToken_) {
        _launchToken = IERC20(launchToken_);
        _collateralToken = IERC20(collateralToken_);
    }

    function buyLaunchTokens(uint256 amount) external {
        caller = msg.sender;
        tokensReceivedOnBuy = amount;
        // Simulate: transfer collateral from caller
        _collateralToken.transferFrom(msg.sender, address(this), amount);
        // Simulate: send launch tokens to caller with profit (1.1:1 ratio to ensure balance increases)
        // This simulates buying launch tokens at a better price than selling them
        uint256 launchAmount = (amount * 110) / 100; // 10% profit
        _launchToken.transfer(msg.sender, launchAmount);
    }

    function sellLaunchTokens(uint256 amount) public {
        caller = msg.sender;
        tokensSoldOnSell = amount;
        // Simulate: transfer launch tokens from caller and send collateral to caller
        _launchToken.transferFrom(msg.sender, address(this), amount);
        // Simulate sending collateral back with profit (1:1.1 ratio to ensure balance increases)
        // In real scenario, this would be based on price difference
        uint256 collateralAmount = (amount * 110) / 100; // 10% profit
        _collateralToken.transfer(msg.sender, collateralAmount);
    }

    function sellLaunchTokensReturnWallet(uint256 amount) external {
        sellLaunchTokens(amount);
    }

    // Stub implementations for interface compliance
    function extendLock(uint256) external pure {
        revert("Not implemented");
    }

    function toggleDeferredWithdrawal() external pure {
        revert("Not implemented");
    }

    function assignNewReserveOwner(address) external pure {
        revert("Not implemented");
    }

    function switchProfitMode(bool) external pure {
        revert("Not implemented");
    }

    function setReturnWallet(address, bool) external pure {
        revert("Not implemented");
    }

    function changeRoyaltyWallet(address) external pure {
        revert("Not implemented");
    }

    function changeProfitPercentage(uint256) external pure {
        revert("Not implemented");
    }

    function setMarketMaker(address, bool) external pure {
        revert("Not implemented");
    }

    function registerOldContract(address) external pure {
        revert("Not implemented");
    }

    function depositCollateral(uint256) external pure {
        revert("Not implemented");
    }

    function depositLaunch(uint256) external pure {
        revert("Not implemented");
    }

    function launchDeferredWithdrawal(address, uint256) external pure {
        revert("Not implemented");
    }

    function stopLaunchDeferredWithdrawal() external pure {
        revert("Not implemented");
    }

    function confirmLaunchDeferredWithdrawal() external pure {
        revert("Not implemented");
    }

    function collateralDeferredWithdrawal(address) external pure {
        revert("Not implemented");
    }

    function stopCollateralDeferredWithdrawal() external pure {
        revert("Not implemented");
    }

    function confirmCollateralDeferredWithdrawal() external pure {
        revert("Not implemented");
    }

    function withdrawAllLaunchTokens() external pure {
        revert("Not implemented");
    }

    function withdrawAllCollateralTokens() external pure {
        revert("Not implemented");
    }

    function withdrawToken(address, uint256) external pure {
        revert("Not implemented");
    }

    function claimProfitOnRequest() external pure {
        revert("Not implemented");
    }

    function setDao(address) external pure {
        revert("Not implemented");
    }

    function calculateUnaccountedCollateralBalance(uint256) external pure {
        revert("Not implemented");
    }

    function calculateUnaccountedOffsetBalance(uint256) external pure {
        revert("Not implemented");
    }

    function calculateUnaccountedOffsetLaunchBalance(uint256) external pure {
        revert("Not implemented");
    }

    function remainingSeconds() external pure returns (uint256) {
        return 0;
    }

    function tradingOpportunity() external pure returns (bool) {
        return true;
    }

    function launchAvailable() external pure returns (uint256) {
        return 0;
    }

    function isActive() external pure returns (bool) {
        return true;
    }

    function oldContractAddress(address) external pure returns (bool) {
        return false;
    }

    function reserveOwner() external pure returns (address) {
        return address(0);
    }

    function launchToken() external view returns (IERC20) {
        return _launchToken;
    }

    function returnWalletAddresses(address) external pure returns (bool) {
        return false;
    }

    function royaltyWalletAddress() external pure returns (address) {
        return address(0);
    }

    function daoAddress() external pure returns (address) {
        return address(0);
    }

    function lockEndTime() external pure returns (uint256) {
        return 0;
    }

    function controlDay() external pure returns (uint256) {
        return 0;
    }

    function controlPeriod() external pure returns (uint256) {
        return 0;
    }

    function initialPricePerToken() external pure returns (uint256) {
        return 0;
    }

    function firstLevelTokenQuantity() external pure returns (uint256) {
        return 0;
    }

    function currentPrice() external pure returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevel() external pure returns (uint256) {
        return 0;
    }

    function remainderOfStep() external pure returns (uint256) {
        return 0;
    }

    function currentStep() external pure returns (uint256) {
        return 0;
    }

    function priceIncrementMultiplier() external pure returns (uint256) {
        return 0;
    }

    function levelIncreaseMultiplier() external pure returns (int256) {
        return 0;
    }

    function trendChangeStep() external pure returns (uint256) {
        return 0;
    }

    function levelDecreaseMultiplierAfterTrend() external pure returns (int256) {
        return 0;
    }

    function profitPercentage() external pure returns (uint256) {
        return 0;
    }

    function royaltyProfitPercent() external pure returns (uint256) {
        return 0;
    }

    function creatorProfitPercent() external pure returns (uint256) {
        return 0;
    }

    function profitBeforeTrendChange() external pure returns (uint256) {
        return 0;
    }

    function totalLaunchSold() external pure returns (uint256) {
        return 0;
    }

    function contractCollateralBalance() external pure returns (uint256) {
        return 0;
    }

    function launchBalance() external pure returns (uint256) {
        return 0;
    }

    function launchTokensEarned() external pure returns (uint256) {
        return 0;
    }

    function currentStepEarned() external pure returns (uint256) {
        return 0;
    }

    function remainderOfStepEarned() external pure returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevelEarned() external pure returns (uint256) {
        return 0;
    }

    function currentPriceEarned() external pure returns (uint256) {
        return 0;
    }

    function offsetLaunch() external pure returns (uint256) {
        return 0;
    }

    function offsetStep() external pure returns (uint256) {
        return 0;
    }

    function offsetPrice() external pure returns (uint256) {
        return 0;
    }

    function remainderOfStepOffset() external pure returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevelOffset() external pure returns (uint256) {
        return 0;
    }

    function collateralToken() external view returns (IERC20) {
        return _collateralToken;
    }

    function marketMakerAddresses(address) external pure returns (bool) {
        return false;
    }

    function ownerCollateralBalance() external pure returns (uint256) {
        return 0;
    }

    function royaltyCollateralBalance() external pure returns (uint256) {
        return 0;
    }

    function profitInTime() external pure returns (bool) {
        return false;
    }

    function canWithdrawal() external pure returns (bool) {
        return false;
    }

    function launchDeferredWithdrawalDate() external pure returns (uint256) {
        return 0;
    }

    function launchDeferredWithdrawalAmount() external pure returns (uint256) {
        return 0;
    }

    function recipientDeferredWithdrawalLaunch() external pure returns (address) {
        return address(0);
    }

    function collateralTokenDeferredWithdrawalDate() external pure returns (uint256) {
        return 0;
    }

    function recipientDeferredWithdrawalCollateralToken() external pure returns (address) {
        return address(0);
    }

    function unaccountedCollateralBalance() external pure returns (uint256) {
        return 0;
    }

    function unaccountedOffset() external pure returns (uint256) {
        return 0;
    }

    function unaccountedOffsetLaunchBalance() external pure returns (uint256) {
        return 0;
    }

    function unaccountedReturnBuybackBalance() external pure returns (uint256) {
        return 0;
    }

    function isInitialized() external pure returns (bool) {
        return true;
    }

    function isFirstLaunchDeposit() external pure returns (bool) {
        return false;
    }
}

