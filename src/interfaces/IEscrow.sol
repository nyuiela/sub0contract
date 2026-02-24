// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokensManager} from "./ITokensManager.sol";
import {IVault} from "./IVault.sol";
import {IPermissionManager} from "./IPermissionManager.sol";
import {IHub} from "./IHub.sol";

interface IEscrow {
    // Errors
    error Unauthorized();
    error NotAuthorized(address account, bytes32 role);
    error BetAlreadyInitialized(bytes32 betEscrowId);
    error BetNotActive(bytes32 betEscrowId);
    error InvalidStatus(bytes32 betEscrowId);
    error ZeroAmount();
    error ZeroAddress();
    error NothingToWithdraw();
    error DisputeActive(bytes32 betEscrowId);
    error TokenNotAllowedListed(address token);
    error InvalidWinningOption();
    error InvalidRecipient(address recipient);
    error MinSettlementTimeNotMet();
    error MaxSettlementTimeExceeded();
    error InvalidGame(address game);
    error UseConditionalTokensFlow();
    // Enums

    enum BetEscrowStatus {
        None,
        Active,
        Closed,
        Resolved,
        Cancelled
    }

    enum DisputeStatus {
        None,
        Open,
        Resolved
    }

    // Structs
    struct BetEscrowData {
        BetEscrowStatus status;
        uint256 totalStaked;
        uint256 winningOption;
        uint256 createdAt;
        uint256 resolvedAt;
        uint256 released;
        uint256 duration;
        address oracle;
        bytes32 gameId;
    }

    struct Dispute {
        DisputeStatus status;
        address raisedBy;
        string reason;
        uint256 raisedAt;
        address resolver;
        string resolutionNote;
        uint256 resolvedAt;
    }

    struct Config {
        address tokensManager;
        address vault;
        address permissionManager;
        address hub;
    }

    // Events
    event BetEscrowCreated(bytes32 indexed betEscrowId, address indexed creator);
    event StakeDeposited(
        bytes32 indexed betEscrowId, address indexed user, uint256 indexed optionIndex, uint256 amount
    );
    event BetResolved(bytes32 indexed betEscrowId, uint256 winningOption);
    event RewardWithdrawn(bytes32 indexed betEscrowId, address indexed user, uint256 amount);
    event BetEscrowClosed(bytes32 indexed betEscrowId, uint256 closedAt);
    event BetEscrowOpened(bytes32 indexed betEscrowId, uint256 openedAt);

    // Constants
    function ESCROW_MANAGER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    // State Variables
    function manager() external view returns (address);
    function hub() external view returns (IHub);
    function tokensManager() external view returns (ITokensManager);
    function vault() external view returns (IVault);
    function permissionManager() external view returns (IPermissionManager);

    // Functions
    /// @notice Initialises the contract.
    /// @param _config Configuration struct containing tokensManager, vault, permissionManager, and hub.
    function initialize(Config memory _config) external;

    /// @notice Updates the configuration.
    /// @param _config Configuration struct containing tokensManager, vault, permissionManager, and hub.
    function setConfig(Config memory _config) external;

    /// @notice Creates an escrow entry for a bet. Must be called before accepting stakes.
    /// @param betId Identifier of the bet as tracked by the game hub.
    /// @param oracleManager Address of the oracle manager.
    /// @param duration time for bet to end
    function createBetEscrow(bytes32 betId, address oracleManager, uint256 duration) external returns (bytes32);

    /// @notice Shuts down an escrow, closing it.
    /// @param betEscrowId Identifier of the bet escrow.
    function shutdown(bytes32 betEscrowId) external;

    /// @notice Opens a closed escrow, making it active again.
    /// @param betEscrowId Identifier of the bet escrow.
    function open(bytes32 betEscrowId) external;

    /// @notice Deposit stake for a bet option. Value sent equals the stake amount.
    /// @param betEscrowId Identifier of the bet.
    /// @param optionIndex Index of the option being backed (as defined in the game).
    /// @param token Token address to deposit.
    /// @param amount Amount to deposit.
    // function depositStake(bytes32 betEscrowId, uint256 optionIndex, address token, uint256 amount) external payable;

    /// @notice Deposit stake for a bet option on behalf of another user.
    /// @param betEscrowId Identifier of the bet.
    /// @param optionIndex Index of the option being backed (as defined in the game).
    /// @param from Address of the user depositing the stake.
    /// @param token Token address to deposit.
    /// @param amount Amount to deposit.
    function depositStakeFrom(bytes32 betEscrowId, uint256 optionIndex, address from, address token, uint256 amount)
        external
        payable;

    /// @notice Marks a bet as resolved and declares the winning option.
    /// @param betEscrowId Identifier of the bet.
    /// @param winningOption Index of the winning option.
    function resolveBet(bytes32 betEscrowId, uint256 winningOption) external;

    /// @notice Withdraw winning rewards after the bet is resolved.
    /// @param betEscrowId Identifier of the bet.
    function withdrawReward(bytes32 betEscrowId, address owner) external;

    /// @notice Returns escrow metadata for a bet.
    /// @param betEscrowId Identifier of the bet escrow.
    /// @return BetEscrowData struct containing escrow information.
    function getBetEscrow(bytes32 betEscrowId) external view returns (BetEscrowData memory);

    /// @notice Total stake placed on an option within a bet.
    /// @param betEscrowId Identifier of the bet escrow.
    /// @param optionIndex Index of the option.
    /// @return Total stake amount for the option.
    function getOptionTotal(bytes32 betEscrowId, uint256 optionIndex) external view returns (uint256);

    /// @notice Stake a user placed on a specific option.
    /// @param betEscrowId Identifier of the bet escrow.
    /// @param user Address of the user.
    /// @param optionIndex Index of the option.
    /// @return Stake amount for the user on the option.
    function getUserStake(bytes32 betEscrowId, address user, uint256 optionIndex) external view returns (uint256);

    /// @notice Aggregate stake a user has across all options for a bet.
    /// @param betEscrowId Identifier of the bet escrow.
    /// @param user Address of the user.
    /// @return Total stake amount for the user across all options.
    function getUserTotal(bytes32 betEscrowId, address user) external view returns (uint256);

    /// @notice Remaining funds (if any) that have not been claimed after resolution or cancellation.
    /// @dev Allows manager with ESCROW_MANAGER_ROLE to recover negligible dust caused by integer division.
    /// @param betEscrowId Identifier of the bet escrow.
    /// @param recipient Address to receive the residual funds.
    function sweepResidual(bytes32 betEscrowId, address payable recipient) external;
}
