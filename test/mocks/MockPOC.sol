// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IProofOfCapital} from "../../src/inerfaces/IProofOfCapital.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock POC contract
contract MockPOC is IProofOfCapital {
    IERC20 public launchToken;
    IERC20 public collateralToken;
    uint256 public tokensReceivedOnBuy;
    uint256 public tokensSoldOnSell;
    address public caller;

    constructor(address _launchToken, address _collateralToken) {
        launchToken = IERC20(_launchToken);
        collateralToken = IERC20(_collateralToken);
    }

    function buyTokens(uint256 amount) external override {
        caller = msg.sender;
        tokensReceivedOnBuy = amount;
        // Simulate: transfer collateral from caller
        collateralToken.transferFrom(msg.sender, address(this), amount);
        // Simulate: send launch tokens to caller with profit (1.1:1 ratio to ensure balance increases)
        // This simulates buying launch tokens at a better price than selling them
        uint256 launchAmount = (amount * 110) / 100; // 10% profit
        launchToken.transfer(msg.sender, launchAmount);
    }

    function sellTokens(uint256 amount) external override {
        caller = msg.sender;
        tokensSoldOnSell = amount;
        // Simulate: transfer launch tokens from caller and send collateral to caller
        launchToken.transferFrom(msg.sender, address(this), amount);
        // Simulate sending collateral back with profit (1:1.1 ratio to ensure balance increases)
        // In real scenario, this would be based on price difference
        uint256 collateralAmount = (amount * 110) / 100; // 10% profit
        collateralToken.transfer(msg.sender, collateralAmount);
    }

    // Stub implementations for interface compliance
    function extendLock(uint256) external pure override {
        revert("Not implemented");
    }

    function blockDeferredWithdrawal() external pure override {
        revert("Not implemented");
    }

    function assignNewOwner(address) external pure override {
        revert("Not implemented");
    }

    function assignNewReserveOwner(address) external pure override {
        revert("Not implemented");
    }

    function switchProfitMode(bool) external pure override {
        revert("Not implemented");
    }

    function changeReturnWallet(address) external pure override {
        revert("Not implemented");
    }

    function changeRoyaltyWallet(address) external pure override {
        revert("Not implemented");
    }

    function changeProfitPercentage(uint256) external pure override {
        revert("Not implemented");
    }

    function setMarketMaker(address, bool) external pure override {
        revert("Not implemented");
    }

    function deposit(uint256) external pure override {
        revert("Not implemented");
    }

    function tokenDeferredWithdrawal(address, uint256) external pure override {
        revert("Not implemented");
    }

    function stopTokenDeferredWithdrawal() external pure override {
        revert("Not implemented");
    }

    function confirmTokenDeferredWithdrawal() external pure override {
        revert("Not implemented");
    }

    function collateralDeferredWithdrawal(address) external pure override {
        revert("Not implemented");
    }

    function stopCollateralDeferredWithdrawal() external pure override {
        revert("Not implemented");
    }

    function confirmCollateralDeferredWithdrawal() external pure override {
        revert("Not implemented");
    }

    function withdrawAllTokens() external pure override {
        revert("Not implemented");
    }

    function withdrawAllCollateralTokens() external pure override {
        revert("Not implemented");
    }

    function getProfitOnRequest() external pure override {
        revert("Not implemented");
    }

    function remainingSeconds() external pure override returns (uint256) {
        return 0;
    }

    function tradingOpportunity() external pure override returns (bool) {
        return true;
    }

    function tokenAvailable() external pure override returns (uint256) {
        return 0;
    }

    function isActive() external pure override returns (bool) {
        return true;
    }

    function lockEndTime() external pure override returns (uint256) {
        return 0;
    }

    function currentPrice() external pure override returns (uint256) {
        return 0;
    }

    function totalLaunchSold() external pure override returns (uint256) {
        return 0;
    }

    function contractCollateralBalance() external pure override returns (uint256) {
        return 0;
    }

    function profitInTime() external pure override returns (bool) {
        return false;
    }

    function canWithdrawal() external pure override returns (bool) {
        return false;
    }
}

