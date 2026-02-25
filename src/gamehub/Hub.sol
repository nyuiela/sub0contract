// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {IHub} from "../interfaces/IHub.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract Hub is IHub, Initializable {
    // constants
    uint256 public constant GAME_APPROVAL_DURATION = 0 seconds;
    uint256 public constant GAME_SHUTDOWN_DURATION = 30 days;
    uint256 public constant BAN_DURATION = 7 days;
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant TOKENS = keccak256("TOKENS");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");

    // storage
    IPermissionManager public permissionManager;
    ITokensManager public tokensManager;
    IOracle public oracleManager;
    Config public config;

    // mappings
    mapping(bytes32 => GameStruct) public games;
    mapping(address => bytes32) public gameToId;
    mapping(bytes32 => bool) public gameShutdown;
    mapping(bytes32 => uint256) public gameShutdownTimestamp;

    function initialize(address _permissionManager, address _tokensManager, address _oracleManager) public initializer {
        if (_permissionManager == address(0)) revert ZeroAddress();
        if (_tokensManager == address(0)) revert ZeroAddress();
        if (_oracleManager == address(0)) revert ZeroAddress();
        permissionManager = IPermissionManager(_permissionManager);
        tokensManager = ITokensManager(_tokensManager);
        oracleManager = IOracle(_oracleManager);
    }

    modifier onlyRole(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    function initializeGame(string memory _description, address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (_game == address(0)) revert ZeroAddress();
        // require(tokensManager.allowedTokens(_conditionalTokens), InvalidConditionalTokensAddress(_conditionalTokens));
        // game = new Game();
        // game.initialize(_tokensManager, _conditionalTokens, address(this));
        bytes32 gameId = keccak256(abi.encode(_game, block.timestamp, msg.sender));
        games[gameId] = GameStruct({
            sourceAddress: _game,
            status: GameStatus.Pending,
            description: _description, // might be removed
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        gameToId[_game] = gameId;
        emit GameCreated(gameId, _game);
    }

    function activateGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (gameToId[_game] == bytes32(0)) revert InvalidGameId(gameToId[_game]);
        // @TODO: Uncomment this when we have a real approval duration
        // require(
        //     block.timestamp > games[gameToId[_game]].createdAt + GAME_APPROVAL_DURATION,
        //     GameApprovalDurationNotMet(gameToId[_game])
        // );
        bytes32 gameId = gameToId[_game];
        games[gameId].sourceAddress = _game;
        games[gameId].status = GameStatus.Active;
        games[gameId].updatedAt = block.timestamp;

        // Grant necessary roles for game to operate
        _grantGameRoles(_game);

        emit GameActivated(gameId);
    }

    function pauseGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (gameShutdownTimestamp[gameToId[_game]] != 0) revert GameShutdownAlreadyInitiated(gameToId[_game]);
        bytes32 gameId = gameToId[_game];
        gameShutdownTimestamp[gameId] = block.timestamp;
        games[gameId].status = GameStatus.Paused;
        games[gameId].updatedAt = block.timestamp;

        // Revoke roles to prevent game operations while paused
        _revokeGameRoles(_game);

        emit GamePaused(gameId);
    }

    function _unsetShutdown(bytes32 gameId) internal {
        gameShutdownTimestamp[gameId] = 0;
    }

    function unpauseGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (gameShutdownTimestamp[gameToId[_game]] == 0) revert GameShutdownAlreadyInitiated(gameToId[_game]);
        bytes32 gameId = gameToId[_game];
        _unsetShutdown(gameId);
        games[gameId].status = GameStatus.Active;
        games[gameId].updatedAt = block.timestamp;

        // Grant roles back when game is unpaused
        _grantGameRoles(_game);

        emit GameUnpaused(gameId);
    }

    function banGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (block.timestamp <= games[gameToId[_game]].createdAt + BAN_DURATION) {
            revert BanDurationNotMet(gameToId[_game]);
        }
        bytes32 gameId = gameToId[_game];
        games[gameId].status = GameStatus.Banned;
        games[gameId].updatedAt = block.timestamp;

        // Revoke all roles to prevent banned game from operating
        _revokeGameRoles(_game);

        emit GameBanned(gameId);
    }

    function unbanGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        bytes32 gameId = gameToId[_game];
        games[gameId].status = GameStatus.Active;
        games[gameId].updatedAt = block.timestamp;
        _unsetShutdown(gameId);

        // Grant roles back when game is unbanned
        _grantGameRoles(_game);

        emit GameUnbanned(gameId);
    }

    function shutdownGame(address _game) public onlyRole(GAME_CREATOR_ROLE) {
        if (block.timestamp <= gameShutdownTimestamp[gameToId[_game]] + GAME_SHUTDOWN_DURATION) {
            revert GameShutdownDurationNotMet(gameToId[_game]);
        }
        bytes32 gameId = gameToId[_game];
        games[gameId].status = GameStatus.Shutdown;
        games[gameId].updatedAt = block.timestamp;

        // Revoke all roles when game is shutdown
        _revokeGameRoles(_game);

        emit GameShutdown(gameId);
    }

    function isAllowed(address add, bytes32 role) public view returns (bool) {
        if (role == ORACLE) {
            return oracleManager.isAllowed(add);
        } else if (role == TOKENS) {
            return tokensManager.isAllowed(add);
        }
        return false;
    }

    function verifyGame(address _game) public view returns (bool) {
        if (gameToId[_game] == bytes32(0)) {
            return false;
        }
        return games[gameToId[_game]].status == GameStatus.Active;
    }

    function getGameId(address _game) public view returns (bytes32) {
        return gameToId[_game];
    }

    function getOracleManager() public view returns (address) {
        return address(oracleManager);
    }

    function setConfig(Config memory _config) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_config.permissionManager == address(0)) revert ZeroAddress();
        if (_config.tokensManager == address(0)) revert ZeroAddress();
        if (_config.oracleManager == address(0)) revert ZeroAddress();
        config = _config;
        permissionManager = IPermissionManager(_config.permissionManager);
        tokensManager = ITokensManager(_config.tokensManager);
        oracleManager = IOracle(_config.oracleManager);
        emit ConfigSet(config);
    }

    /**
     * @notice Grant necessary roles to a game contract
     * @dev Grants GAME_CONTRACT_ROLE, game-specific GAME_CONTRACT_ROLE, and ONLY_GAME_ROLE
     * @param _game The game contract address
     */
    function _grantGameRoles(address _game) internal {
        // Grant base GAME_CONTRACT_ROLE
        if (!permissionManager.hasRole(GAME_CONTRACT_ROLE, _game)) {
            permissionManager.grantRole(GAME_CONTRACT_ROLE, _game);
        }
    }

    /**
     * @notice Revoke all roles from a game contract
     * @dev Revokes GAME_CONTRACT_ROLE and game-specific GAME_CONTRACT_ROLE
     * @param _game The game contract address
     */
    function _revokeGameRoles(address _game) internal {
        // Revoke base GAME_CONTRACT_ROLE
        if (permissionManager.hasRole(GAME_CONTRACT_ROLE, _game)) {
            permissionManager.revokeRole(GAME_CONTRACT_ROLE, _game);
        }
    }
}
