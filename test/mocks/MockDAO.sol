// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "../../src/interfaces/DataTypes.sol";

// Mock DAO contract for testing
contract MockDAO {
    DataTypes.Stage private _currentStage;
    bool private _shouldRevert;

    // POC contracts mapping
    mapping(address => uint256) private _pocIndex;
    DataTypes.POCInfo[] private _pocContracts;

    constructor() {
        _currentStage = DataTypes.Stage.Active; // Default to Active stage
        _shouldRevert = false;
        // Add dummy entry at index 0 (since 0 means "not found")
        _pocContracts.push(
            DataTypes.POCInfo({
                pocContract: address(0),
                collateralToken: address(0),
                priceFeed: address(0),
                sharePercent: 0,
                active: false,
                exchanged: false,
                exchangedAmount: 0
            })
        );
    }

    /**
     * @notice Set the current stage of the DAO
     * @param stage The stage to set
     */
    function setCurrentStage(DataTypes.Stage stage) external {
        _currentStage = stage;
    }

    /**
     * @notice Set whether the getDaoState should revert
     * @param value true to make it revert, false otherwise
     */
    function setShouldRevert(bool value) external {
        _shouldRevert = value;
    }

    /**
     * @notice Add a POC contract for testing
     * @param pocContract POC contract address
     * @param collateralToken Collateral token address
     */
    function addPOCContract(address pocContract, address collateralToken) external {
        uint256 index = _pocContracts.length;
        _pocIndex[pocContract] = index;
        _pocContracts.push(
            DataTypes.POCInfo({
                pocContract: pocContract,
                collateralToken: collateralToken,
                priceFeed: address(0),
                sharePercent: 0,
                active: true,
                exchanged: false,
                exchangedAmount: 0
            })
        );
    }

    /**
     * @notice Get POC contract index
     * @param pocContract POC contract address
     * @return Index of the POC contract (0 if not found)
     */
    function pocIndex(address pocContract) external view returns (uint256) {
        return _pocIndex[pocContract];
    }

    /**
     * @notice Get POC contract info by index
     * @param index Index of the POC contract
     * @return POC contract info
     */
    function getPOCContract(uint256 index) external view returns (DataTypes.POCInfo memory) {
        require(index < _pocContracts.length, "Invalid index");
        return _pocContracts[index];
    }

    /**
     * @notice Get the DAO state (mocked)
     * @return DAOState with the current stage set
     */
    function getDaoState() external view returns (DataTypes.DAOState memory) {
        require(!_shouldRevert, "DAO unavailable");

        return DataTypes.DAOState({
            currentStage: _currentStage,
            royaltyRecipient: address(0),
            royaltyPercent: 0,
            creator: address(0),
            creatorProfitPercent: 0,
            totalCollectedMainCollateral: 0,
            lastCreatorAllocation: 0,
            totalExitQueueShares: 0,
            totalDepositedUSD: 0,
            lastPOCReturn: 0,
            pendingExitQueuePayment: 0,
            marketMaker: address(0)
        });
    }
}
