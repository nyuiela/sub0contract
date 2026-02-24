// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {InvitationManager} from "../manager/InvitationManager.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";
import {IHub} from "../interfaces/IHub.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ParimutuelConditionalTokens} from "../conditional/ParimutuelConditionalTokens.sol";

/**
 * @title MeVsYouParimutuel
 * @notice Game hub for parimutuel (winner-gets-share-of-total-volume) markets.
 * Payout = (your stake on winning outcome / total stake on winning outcome) * total volume - platform fee.
 * Works with existing oracle, permission manager, and token manager.
 */
contract MeVsYouParimutuel is Initializable, UUPSUpgradeable, OwnableUpgradeable, InvitationManager {
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");

    ITokensManager public tokenManager;
    IHub public hub;
    IPermissionManager public permissionManager;
    ParimutuelConditionalTokens public parimutuelToken;

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
        address tokenManager;
        address permissionManager;
        address parimutuelToken;
    }

    enum OracleType {
        NONE,
        PLATFORM,
        ARBITRATOR,
        CUSTOM
    }

    error InvalidQuestion(string question);
    error InvalidOutcomeSlotCount(uint256 outcomeSlotCount);
    error InvalidBetDuration(uint256 betDuration);
    error ZeroAddress();
    error TokenNotAllowedListed(address token);
    error OracleNotAllowed(address oracle);
    error InvalidOptionIndex(uint256 optionIndex);
    error QuestionAlreadyExists(bytes32 questionId);
    error PublicBetNotAllowed();
    error NotAuthorized(address account, bytes32 role);

    event MarketCreated(
        bytes32 questionId,
        string question,
        OracleType oracleType,
        InvitationManager.InvitationType marketType,
        address owner
    );
    event MarketResolved(bytes32 questionId, uint256[] payouts);
    event Staked(
        bytes32 indexed questionId,
        bytes32 indexed conditionId,
        address indexed user,
        uint256 outcomeIndex,
        uint256 amount
    );
    event Redeemed(
        bytes32 indexed questionId, bytes32 indexed conditionId, address indexed user, uint256 fee, uint256 amount
    );

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
        require(_questionId != bytes32(0), "Invalid questionId");
        if (_token == address(0)) revert ZeroAddress();
        if (!tokenManager.allowedTokens(_token)) revert TokenNotAllowedListed(_token);
        _;
    }

    function initialize(Config memory _config) public initializer {
        if (_config.permissionManager == address(0)) revert ZeroAddress();
        if (_config.hub == address(0)) revert ZeroAddress();
        if (_config.parimutuelToken == address(0)) revert ZeroAddress();
        __Ownable_init(msg.sender);
        tokenManager = ITokensManager(_config.tokenManager);
        hub = IHub(_config.hub);
        permissionManager = IPermissionManager(_config.permissionManager);
        parimutuelToken = ParimutuelConditionalTokens(_config.parimutuelToken);
    }

    function create(Market memory market) public onlyValidMarket(market) returns (bytes32) {
        if (market.oracleType == OracleType.NONE) revert OracleNotAllowed(market.oracle);
        if (
            !permissionManager.hasRole(GAME_CREATOR_ROLE, msg.sender)
                && market.marketType == InvitationManager.InvitationType.Public
        ) {
            revert PublicBetNotAllowed();
        }

        bytes32 questionId = keccak256(abi.encodePacked(market.question, msg.sender, market.oracle));
        if (markets[questionId].owner != address(0)) revert QuestionAlreadyExists(questionId);

        if (market.oracleType == OracleType.PLATFORM || market.oracleType == OracleType.CUSTOM) {
            if (!hub.isAllowed(market.oracle, ORACLE)) revert OracleNotAllowed(market.oracle);
        }

        parimutuelToken.prepareCondition(address(this), questionId, market.outcomeSlotCount);
        bytes32 conditionId = parimutuelToken.getConditionId(address(this), questionId, market.outcomeSlotCount);

        markets[questionId] = market;
        markets[questionId].owner = msg.sender;
        markets[questionId].createdAt = block.timestamp;
        markets[questionId].conditionId = conditionId;
        createInvitation(questionId, msg.sender, market.marketType);

        emit MarketCreated(questionId, market.question, market.oracleType, market.marketType, market.owner);
        return questionId;
    }

    function stake(bytes32 questionId, uint256 outcomeIndex, address token, uint256 amount)
        public
        whenInvited(questionId)
        onlyValidStake(questionId, token, amount)
    {
        bytes32 conditionId = markets[questionId].conditionId;
        require(conditionId != bytes32(0), "Market not found");
        if (outcomeIndex >= markets[questionId].outcomeSlotCount) revert InvalidOptionIndex(outcomeIndex);

        parimutuelToken.stakeFor(msg.sender, conditionId, outcomeIndex, IERC20(token), amount);
        emit Staked(questionId, conditionId, msg.sender, outcomeIndex, amount);
    }

    function redeem(bytes32 questionId, address token) public {
        bytes32 conditionId = markets[questionId].conditionId;
        require(conditionId != bytes32(0), "Market not found");

        (, uint256 feeAmount, uint256 payoutNet) = parimutuelToken.redeemFor(msg.sender, conditionId, IERC20(token));
        emit Redeemed(questionId, conditionId, msg.sender, feeAmount, payoutNet);
    }

    /**
     * @notice Resolve market with payout numerators. Single endpoint for all resolutions.
     * @param questionId The market question ID
     * @param payouts Payout numerator per outcome (e.g. [1,0] single winner, [1,1] refund all, [1,1,0] two winners)
     */
    function resolve(bytes32 questionId, uint256[] calldata payouts) public {
        if (msg.sender != markets[questionId].oracle) revert NotAuthorized(msg.sender, ORACLE);
        if (payouts.length != markets[questionId].outcomeSlotCount) revert InvalidOptionIndex(payouts.length);

        bytes32 conditionId = markets[questionId].conditionId;
        parimutuelToken.reportPayouts(conditionId, payouts);
        emit MarketResolved(questionId, payouts);
    }

    function getMarket(bytes32 questionId) public view returns (Market memory) {
        return markets[questionId];
    }

    function getMarket(bytes32 questionId, address owner, address _oracle) public view returns (Market memory) {
        bytes32 id = keccak256(abi.encodePacked(questionId, owner, _oracle));
        return markets[id];
    }

    function setConfig(Config memory _config) public onlyOwner {
        hub = IHub(_config.hub);
        permissionManager = IPermissionManager(_config.permissionManager);
        if (_config.parimutuelToken != address(0)) {
            parimutuelToken = ParimutuelConditionalTokens(_config.parimutuelToken);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
