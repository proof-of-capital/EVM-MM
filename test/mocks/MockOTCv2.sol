// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IOTCv2} from "../../src/interfaces/IOTCv2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockOTCv2
 * @notice Minimal mock of IOTCv2 for testing _rebalanceSupplyOTC / adminRebalanceSupplyOTC.
 *        supplyOutput() pulls OUTPUT_TOKEN from msg.sender and sends INPUT_TOKEN to msg.sender
 *        according to supplies(currentSupplyIndex). Mock must hold INPUT_TOKEN for supplyOutput.
 */
contract MockOTCv2 is IOTCv2 {
    using SafeERC20 for IERC20;

    address private _inputToken;
    address private _outputToken;
    address private _adminAddress;
    uint8 private _currentSupplyIndex;
    mapping(uint8 => Supply) private _supplies;

    constructor(
        address inputToken_,
        address outputToken_,
        address adminAddress_
    ) {
        _inputToken = inputToken_;
        _outputToken = outputToken_;
        _adminAddress = adminAddress_;
    }

    function setCurrentSupplyIndex(uint8 index) external {
        _currentSupplyIndex = index;
    }

    function setSupply(uint8 index, uint256 inputAmount, uint256 outputAmount) external {
        _supplies[index] = Supply({input: inputAmount, output: outputAmount});
    }

    function setInputToken(address token) external {
        _inputToken = token;
    }

    function setOutputToken(address token) external {
        _outputToken = token;
    }

    function setAdminAddress(address admin) external {
        _adminAddress = admin;
    }

    function INPUT_TOKEN() external view returns (address) {
        return _inputToken;
    }

    function OUTPUT_TOKEN() external view returns (address) {
        return _outputToken;
    }

    function ADMIN_ADDRESS() external view returns (address) {
        return _adminAddress;
    }

    function currentSupplyIndex() external view returns (uint8) {
        return _currentSupplyIndex;
    }

    function supplies(uint8 index) external view returns (uint256 input, uint256 output) {
        Supply memory s = _supplies[index];
        return (s.input, s.output);
    }

    /**
     * @dev Pulls OUTPUT_TOKEN from msg.sender, sends INPUT_TOKEN to msg.sender.
     *      Amounts from supplies(currentSupplyIndex). Caller must have minted INPUT_TOKEN to this contract.
     */
    function supplyOutput() external {
        Supply memory s = _supplies[_currentSupplyIndex];
        uint256 outputAmount = s.output;
        uint256 inputAmount = s.input;
        require(outputAmount != 0, "MockOTCv2: zero output");
        IERC20(_outputToken).safeTransferFrom(msg.sender, address(this), outputAmount);
        if (inputAmount != 0 && _inputToken != address(0)) {
            IERC20(_inputToken).safeTransfer(msg.sender, inputAmount);
        }
    }

    // --- Stubs for interface compliance ---

    function CLIENT_ADDRESS() external pure returns (address) {
        return address(0);
    }

    function BUYBACK_PRICE() external pure returns (uint256) {
        return 0;
    }

    function MIN_INPUT_AMOUNT() external pure returns (uint256) {
        return 0;
    }

    function MIN_OUTPUT_AMOUNT() external pure returns (uint256) {
        return 0;
    }

    function supplyCount() external pure returns (uint8) {
        return 1;
    }

    function supplyLockEndTime() external pure returns (uint64) {
        return 0;
    }

    function totalLockEndTime() external pure returns (uint64) {
        return 0;
    }

    function proposedTime() external pure returns (uint64) {
        return 0;
    }

    function currentState() external pure returns (uint8) {
        return 0;
    }

    function IS_SUPPLY() external pure returns (bool) {
        return true;
    }

    function withdrawData() external pure returns (address daoAddress, uint256 vaultId) {
        return (address(0), 0);
    }

    function depositEth() external payable {
        revert("MockOTCv2: not implemented");
    }

    function depositToken(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function depositOutput(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function withdrawEth(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function withdrawInput(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function withdrawOutput(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function proposeDaoAccount(FarmWithdrawData calldata) external pure {
        revert("MockOTCv2: not implemented");
    }

    function voteYes() external pure {
        revert("MockOTCv2: not implemented");
    }

    function voteNo() external pure {
        revert("MockOTCv2: not implemented");
    }

    function sendToFarm() external pure {
        revert("MockOTCv2: not implemented");
    }

    function buybackWithToken(uint256) external pure {
        revert("MockOTCv2: not implemented");
    }

    function buybackWithEth() external payable {
        revert("MockOTCv2: not implemented");
    }
}
