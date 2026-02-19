// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/**
 * @title IOTCv2 Interface
 * @notice Interface for OTCv2 contract with DAO integration
 */
interface IOTCv2 {
    // Custom Errors
    error OnlyAdmin();
    error OnlyClient();
    error OnlyAdminOrClient();
    error InvalidState(uint8 current, uint8 expected);
    error SupplyLockActive();
    error TotalLockActive();
    error InsufficientValue();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidToken();
    error FarmAccountNotProposed();
    error ProposeLockActive();
    error NotEnoughOutputToken();
    error SupplyMismatch();
    error InputTokenIsEth();
    error InputTokenIsToken();
    error OutputSumTooLow();
    error InputSumTooLow();
    error InvalidSupplyCount();
    error EthTransferFailed();
    error FarmCallFailed();
    error NoFarmData();
    error ZeroAddress();
    error InvalidBuybackPrice();
    error InvalidSupplyData();
    error SameAddress();
    error SameTokens();
    error NotSupplyContract();
    error NotDemandContract();
    error InvalidStateForBuyback(uint8 current);
    error InvalidStateForVote(uint8 current);

    // Structs
    struct Supply {
        uint256 input;
        uint256 output;
    }

    struct FarmWithdrawData {
        address daoAddress;
        uint256 vaultId;
    }

    // Events
    event DepositedInput(address indexed depositor, uint256 amount);
    event DepositedOutput(address indexed depositor, uint256 amount);
    event InputChecked(uint256 totalAmount);
    event OutputChecked(uint256 totalAmount);
    event Withdrawn(address indexed recipient, uint256 amount);
    event InputWithdrawn(address indexed recipient, uint256 amount);
    event OutputWithdrawn(address indexed recipient, uint256 amount);
    event SupplyProcessed(uint8 indexed supplyIndex, uint256 inputAmount, uint256 outputAmount);
    event FarmAccountProposed(address indexed daoAddress, uint256 indexed vaultId, uint64 proposedTime);
    event ClientVoted(bool approved);
    event TokensSentToFarm(address indexed farmAccount, uint256 amount);
    event BuybackExecuted(uint256 inputAmount, uint256 outputAmount);
    event StateChanged(uint8 oldState, uint8 newState);

    // View functions
    function INPUT_TOKEN() external view returns (address);
    function OUTPUT_TOKEN() external view returns (address);
    function ADMIN_ADDRESS() external view returns (address);
    function CLIENT_ADDRESS() external view returns (address);
    function BUYBACK_PRICE() external view returns (uint256);
    function MIN_INPUT_AMOUNT() external view returns (uint256);
    function MIN_OUTPUT_AMOUNT() external view returns (uint256);
    function supplyCount() external view returns (uint8);
    function currentSupplyIndex() external view returns (uint8);
    function supplyLockEndTime() external view returns (uint64);
    function totalLockEndTime() external view returns (uint64);
    function proposedTime() external view returns (uint64);
    function currentState() external view returns (uint8);
    function IS_SUPPLY() external view returns (bool);
    function supplies(uint8) external view returns (uint256 input, uint256 output);
    function withdrawData() external view returns (address daoAddress, uint256 vaultId);

    // External functions
    function depositEth() external payable;
    function depositToken(uint256 amount) external;
    function depositOutput(uint256 amount) external;
    function withdrawEth(uint256 amount) external;
    function withdrawInput(uint256 amount) external;
    function withdrawOutput(uint256 amount) external;
    function supplyOutput() external;
    function proposeDaoAccount(FarmWithdrawData calldata _withdrawData) external;
    function voteYes() external;
    function voteNo() external;
    function sendToFarm() external;
    function buybackWithToken(uint256 amount) external;
    function buybackWithEth() external payable;
}
