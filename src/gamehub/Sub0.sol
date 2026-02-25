// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {InvitationManager} from "../manager/InvitationManager.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";
import {IHub} from "../interfaces/IHub.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConditionalTokensV2} from "../conditional/IConditionalTokensV2.sol";
import {IPredictionVault} from "../interfaces/IPredictionVault.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReceiverTemplate} from "../interfaces/ReceiverTemplate.sol";

/**
 * @title Sub0
 * @notice Sub0 prediction market factory: creates markets, integrates with PredictionVault (inventory AMM) and ConditionalTokensV2.
 * @dev Implements IReceiver for CRE: set CRE Forwarder via setCreForwarderAddress and grant it GAME_CREATOR_ROLE for Public markets.
 *      After upgrade: (1) setCreForwarderAddress(chainForwarder), (2) grant GAME_CREATOR_ROLE to that forwarder.
 */
contract Sub0 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReceiverTemplate {
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant TOKENS = keccak256("TOKENS");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    ITokensManager public tokenManager;
    address public oracle;
    IHub public hub;
    IVault public vault;
    IPermissionManager public permissionManager;
    address public conditionalToken;
    IPredictionVault public predictionVault;

    /// @notice Chainlink CRE Forwarder; only this address can call onReport. Set via setCreForwarderAddress.
    address private _creForwarderAddress;

    mapping(bytes32 => Market) public markets;

    struct Market {
        string question;
        bytes32 conditionId;
        address oracle;
        address owner;
        uint256 createdAt;
        uint256 duration;
        uint256 outcomeSlotCount;
        OracleType oracleType;
        InvitationManager.InvitationType marketType;
    }

    struct Config {
        address hub;
        address vault;
        address tokenManager;
        address permissionManager;
        address conditionalToken;
        address predictionVault;
        address creForwarder;
    }

    enum OracleType {
        NONE,
        PLATFORM,
        ARBITRATOR,
        CUSTOM
    }

    modifier onlyValidMarket(Market memory market) {
        if (bytes(market.question).length == 0) revert InvalidQuestion(market.question);
        if (market.duration == 0) revert InvalidBetDuration(market.duration);
        if (market.outcomeSlotCount < 2 || market.outcomeSlotCount > 255) {
            revert InvalidOutcomeSlotCount(market.outcomeSlotCount);
        }
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    modifier onlyValidStake(bytes32 _questionId, address _token, uint256 amount) {
        if (_questionId == bytes32(0)) revert InvalidQuestionId(_questionId);
        if (_token == address(0)) revert ZeroAddress();
        if (!tokenManager.allowedTokens(_token)) revert TokenNotAllowedListed(_token);
        _;
    }
    error InvalidQuestionId(bytes32 questionId);
    error InvalidQuestion(string question);
    error InvalidOutcomeSlotCount(uint256 outcomeSlotCount);
    error InvalidBetDuration(uint256 betDuration);
    error InvalidPrivateBet(bool privateBet);
    error BetAlreadyExists(bytes32 conditionId);
    error ZeroAddress();
    error TokenNotAllowedListed(address token);
    error InvalidTokenDecimal(address token);
    error OracleNotAllowed(address oracle);
    error InvalidOptionIndex(uint256 optionIndex);
    error QuestionAlreadyExists(bytes32 questionId);
    error PublicBetNotAllowed();
    error NotAuthorized(address account, bytes32 role);
    error CREInvalidSender(address sender, address expectedForwarder);
    error CREReportTooShort();
    error CREForwarderNotSet();
    error CREUnknownAction(uint8 prefix);

    /// @dev CRE report action prefixes: first byte of report routes to the correct handler.
    uint8 private constant CRE_ACTION_CREATE = 0x00;
    uint8 private constant CRE_ACTION_RESOLVE = 0x01;
    uint8 private constant CRE_ACTION_STAKE = 0x02;
    uint8 private constant CRE_ACTION_REDEEM = 0x03;

    event MarketCreated(
        bytes32 questionId,
        string question,
        OracleType oracleType,
        InvitationManager.InvitationType marketType,
        address owner
    );
    event BetResolved(bytes32 questionId, uint256[] payouts);
    event Staked(bytes32 questionId, uint256[] partition, address token, uint256 amount);
    event Redeemed(bytes32 questionId, uint256[] indexSets, address token, uint256 amount);

    function initialize(Config memory _config) public initializer {
        if (_config.vault == address(0)) revert ZeroAddress();
        if (_config.permissionManager == address(0)) revert ZeroAddress();
        if (_config.hub == address(0)) revert ZeroAddress();
        __Ownable_init(msg.sender);
        __ReceiverTemplate_init(_config.creForwarder);
        tokenManager = ITokensManager(_config.tokenManager);
        hub = IHub(_config.hub);
        vault = IVault(_config.vault);
        permissionManager = IPermissionManager(_config.permissionManager);
        conditionalToken = _config.conditionalToken;
        predictionVault = IPredictionVault(_config.predictionVault);
        _creForwarderAddress = _config.creForwarder;
    }


    /// @dev Internal creation logic that accepts the true creator address
    function _createInternal(Market memory market, address actualCreator) internal returns (bytes32) {
        if (market.oracleType == OracleType.NONE) revert OracleNotAllowed(market.oracle);
        
        // Verify the actual creator has the right roles
        if (
            !permissionManager.hasRole(GAME_CREATOR_ROLE, actualCreator)
                && market.marketType == InvitationManager.InvitationType.Public
        ) {
            revert PublicBetNotAllowed();
        }

        bytes32 questionId = keccak256(abi.encodePacked(market.question, actualCreator, market.oracle));
        if (markets[questionId].owner != address(0)) revert QuestionAlreadyExists(questionId);

        // ... rest of your standard create logic ...
        bytes32 conditionId = vault.prepareCondition(questionId, market.outcomeSlotCount);
        markets[questionId] = market;
        markets[questionId].owner = actualCreator; // Set true owner
        markets[questionId].createdAt = block.timestamp;
        markets[questionId].conditionId = conditionId;
        
        if (address(predictionVault) != address(0)) {
            predictionVault.registerMarket(questionId, conditionId);
        }
        
        emit MarketCreated(questionId, market.question, market.oracleType, market.marketType, actualCreator);
        return questionId;
    }

    /// @notice For normal users calling directly (if you still allow it outside of CRE)
    function create(Market memory market) public onlyValidMarket(market) returns (bytes32) {
        return _createInternal(market, msg.sender);
    }
    function stake(
        bytes32 questionId,
        bytes32 parentCollectionId,
        uint256[] calldata partition,
        address token,
        uint256 amount
    ) public {
        _stakeInternal(questionId, parentCollectionId, partition, token, amount, msg.sender);
    }

    function redeem(bytes32 parentCollectionId, bytes32 conditionId, uint256[] calldata indexSets, address token)
        public
    {
        _redeemInternal(parentCollectionId, conditionId, indexSets, token, msg.sender);
    }

    function resolve(bytes32 questionId, uint256[] calldata payouts) public {
        _resolveInternal(questionId, payouts, msg.sender);
    }

    function _resolveInternal(bytes32 questionId, uint256[] memory payouts, address oracleAccount) internal {
        if (markets[questionId].oracle != oracleAccount) revert NotAuthorized(oracleAccount, ORACLE);
        vault.resolveCondition(questionId, payouts);
        emit BetResolved(questionId, payouts);
    }

    function _stakeInternal(
        bytes32 questionId,
        bytes32 parentCollectionId,
        uint256[] memory partition,
        address token,
        uint256 amount,
        address _owner
    ) internal {
        bytes32 conditionId = markets[questionId].conditionId;
        IConditionalTokensV2(conditionalToken).splitPositionFor(
            _owner, IERC20(token), parentCollectionId, conditionId, partition, amount
        );
        emit Staked(questionId, partition, token, amount);
    }

    function _redeemInternal(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] memory indexSets,
        address token,
        address _owner
    ) internal {
        IConditionalTokensV2(conditionalToken).redeemPositionsFor(
            _owner, IERC20(token), parentCollectionId, conditionId, indexSets
        );
        emit Redeemed(conditionId, indexSets, token, 0);
    }

    function getMarket(bytes32 questionId) public view returns (Market memory) {
        return markets[questionId];
    }

    function getMarket(bytes32 questionId, address _owner, address _oracle) public view returns (Market memory) {
        bytes32 id = keccak256(abi.encodePacked(questionId, _owner, _oracle));
        return markets[id];
    }

    function setConfig(Config memory _config) public onlyOwner {
        hub = IHub(_config.hub);
        vault = IVault(_config.vault);
        permissionManager = IPermissionManager(_config.permissionManager);
        if (_config.predictionVault != address(0)) {
            predictionVault = IPredictionVault(_config.predictionVault);
        }
    }
    /// @inheritdoc ReceiverTemplate
    /// @dev Routes CRE reports by prefix byte. Backend must send: prefix (1 byte) + abi.encode(...payload).
    ///      All resolve/stake/redeem payloads include the account that is acting (oracle or owner).
    ///      - 0x00: create  → payload = abi.encode(Market)
    ///      - 0x01: resolve → payload = abi.encode(questionId, payouts, oracle)
    ///      - 0x02: stake   → payload = abi.encode(questionId, parentCollectionId, partition, token, amount, owner)
    ///      - 0x03: redeem  → payload = abi.encode(parentCollectionId, conditionId, indexSets, token, owner)
    function _processReport(bytes calldata report) internal override {
        if (report.length == 0) revert CREReportTooShort();
        uint8 action = uint8(report[0]);
        bytes calldata payload = report[1:];

        if (action == CRE_ACTION_CREATE) {
            Market memory market = abi.decode(payload, (Market));
            _createInternal(market, market.owner);
            return;
        }
        if (action == CRE_ACTION_RESOLVE) {
            (bytes32 questionId, uint256[] memory payouts, address oracleAccount) =
                abi.decode(payload, (bytes32, uint256[], address));
            _resolveInternal(questionId, payouts, oracleAccount);
            return;
        }
        if (action == CRE_ACTION_STAKE) {
            (
                bytes32 questionId,
                bytes32 parentCollectionId,
                uint256[] memory partition,
                address token,
                uint256 amount,
                address _owner
            ) = abi.decode(payload, (bytes32, bytes32, uint256[], address, uint256, address));
            _stakeInternal(questionId, parentCollectionId, partition, token, amount, _owner);
            return;
        }
        if (action == CRE_ACTION_REDEEM) {
            (bytes32 parentCollectionId, bytes32 conditionId, uint256[] memory indexSets, address token, address _owner) =
                abi.decode(payload, (bytes32, bytes32, uint256[], address, address));
            _redeemInternal(parentCollectionId, conditionId, indexSets, token, _owner);
            return;
        }
        revert CREUnknownAction(action);
    }
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
