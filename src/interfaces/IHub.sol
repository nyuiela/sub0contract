// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IPermissionManager.sol";
import "./ITokensManager.sol";

interface IHub {
    // Enums
    enum GameStatus {
        None,
        Pending,
        Active,
        Paused,
        Banned,
        Shutdown
    }

    // Structs
    struct GameStruct {
        address sourceAddress;
        GameStatus status;
        string description;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Config {
        address permissionManager;
        address tokensManager;
        address oracleManager;
    }

    // Errors
    error ZeroAddress();
    error InvalidGameAddress(address game);
    error NotAuthorizedToCreateGame(address account);
    error InvalidGameId(bytes32 gameId);
    error GameApprovalDurationNotMet(bytes32 gameId);
    error GameShutdownAlreadyInitiated(bytes32 gameId);
    error GameShutdownDurationNotMet(bytes32 gameId);
    error BanDurationNotMet(bytes32 gameId);
    error InvalidGameApprovalDuration(uint256 gameApprovalDuration);
    error NotAuthorized(address account, bytes32 role);

    // Events
    event GameCreated(bytes32 gameId, address sourceAddress);
    event GameActivated(bytes32 gameId);
    event GamePaused(bytes32 gameId);
    event GameUnpaused(bytes32 gameId);
    event GameBanned(bytes32 gameId);
    event GameUnbanned(bytes32 gameId);
    event GameShutdown(bytes32 gameId);
    event ConfigSet(Config config);

    // Constants (documented for reference)
    // uint256 public constant GAME_APPROVAL_DURATION = 3 days;
    // uint256 public constant GAME_SHUTDOWN_DURATION = 30 days;
    // uint256 public constant BAN_DURATION = 7 days;

    /// @dev Gets the permission manager contract.
    /// @return The permission manager contract address.
    // function permissionManager() external view returns (IPermissionManager);

    /// @dev Gets the tokens manager contract.
    /// @return The tokens manager contract address.
    // function tokensManager() external view returns (ITokensManager);

    /// @dev Gets the game contract.
    /// @return The game contract address.
    // function game() external view returns (address);

    /// @dev Gets game information by game ID.
    /// @param gameId The game ID.
    /// @return The game struct containing game information.
    // function games(bytes32 gameId) external view returns (GameStruct memory);

    /// @dev Gets the game ID for a given game address.
    /// @param gameAddress The game contract address.
    /// @return The game ID.
    // function gameToId(address gameAddress) external view returns (bytes32);

    /// @dev Gets whether a game is shutdown.
    /// @param gameId The game ID.
    /// @return True if the game is shutdown, false otherwise.
    // function gameShutdown(bytes32 gameId) external view returns (bool);

    /// @dev Gets the shutdown timestamp for a game.
    /// @param gameId The game ID.
    /// @return The timestamp when the game shutdown was initiated, or 0 if not shutdown.
    // function gameShutdownTimestamp(bytes32 gameId) external view returns (uint256);

    /// @dev Initializes the hub contract.
    /// @param _permissionManager The permission manager contract address.
    /// @param _tokensManager The tokens manager contract address.
    // function initialize(address _permissionManager, address _tokensManager) external;

    /// @dev Initializes a new game.
    /// @param _description The game description.
    function initializeGame(string memory _description, address _game) external;

    /// @dev Gets the game ID for a given game address.
    /// @param _game The game contract address.
    /// @return The game ID.
    function getGameId(address _game) external view returns (bytes32);

    /// @dev Activates a game after the approval duration has passed.
    /// @param _game The game contract address.
    function activateGame(address _game) external;

    /// @dev Pauses a game.
    /// @param _game The game contract address.
    function pauseGame(address _game) external;

    /// @dev Unpauses a game.
    /// @param _game The game contract address.
    function unpauseGame(address _game) external;

    /// @dev Bans a game after the ban duration has passed.
    /// @param _game The game contract address.
    function banGame(address _game) external;

    /// @dev Unbans a game.
    /// @param _game The game contract address.
    function unbanGame(address _game) external;

    /// @dev Shuts down a game after the shutdown duration has passed.
    /// @param _game The game contract address.
    function shutdownGame(address _game) external;

    /// @dev Verifies if a game is active.
    /// @param _game The game contract address.
    /// @return True if the game is active, false otherwise.
    function verifyGame(address _game) external view returns (bool);

    /// @dev Gets the oracle manager contract address.
    /// @return The oracle manager contract address.
    function getOracleManager() external view returns (address);

    /// @dev checks if a role is allowed
    /// @param add The address to check
    /// @param role The role to check e.g ORACLE, TOKENS
    /// @return True if the role is allowed, false otherwise
    function isAllowed(address add, bytes32 role) external view returns (bool);

    function setConfig(Config memory _config) external;
}
