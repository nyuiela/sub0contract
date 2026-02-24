// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CTHelpersV2} from "./CTHelpersV2.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title ParimutuelConditionalTokens
 * @notice Winner-gets-share-of-total-volume: payout = (your stake / total winning stake) * total volume - platform fee
 * @dev One token type per condition; volume and user stakes tracked per outcome. No LP / 1:1 outcome tokens.
 *      Uses central IPermissionManager for roles (one permission hub). UUPS upgradeable.
 */
contract ParimutuelConditionalTokens is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable
{
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    bytes32 public constant PARIMUTUEL_ADMIN_ROLE = keccak256("PARIMUTUEL_ADMIN_ROLE");
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1000; // 10% cap

    error TooFewOutcomeSlots();
    error TooManyOutcomeSlots();
    error ConditionAlreadyPrepared();
    error ConditionNotPrepared();
    error ConditionAlreadyResolved();
    error ConditionNotResolved();
    error InvalidOutcomeIndex();
    error UnauthorizedOracle();
    error ZeroAddress();
    error InvalidFee(uint256 fee);
    error TransferFailed();
    error NoStakeToRedeem();
    error ZeroVolumeOnWinningOutcome();
    error WrongToken();
    error InvalidPayouts();
    error NotAuthorized(address account, bytes32 role);

    event ConditionPreparation(
        bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId, uint256 outcomeSlotCount
    );
    event ConditionResolution(bytes32 indexed conditionId, uint256[] payoutNumerators);
    event Staked(
        bytes32 indexed conditionId, uint256 outcomeIndex, address indexed user, address indexed token, uint256 amount
    );
    event Redeemed(
        bytes32 indexed conditionId,
        address indexed user,
        address indexed token,
        uint256 payoutGross,
        uint256 feeAmount,
        uint256 payoutNet
    );
    event FeeConfigUpdated(address feeCollector, uint256 feeBps);
    event FeesCollected(address token, uint256 amount);

    struct Condition {
        uint8 outcomeSlotCount;
        uint8 status; // 0 not prepared, 1 prepared, 2 resolved
        uint128 payoutDenominator;
        address oracle;
        uint256[] payoutNumerators; // length = outcomeSlotCount; resolution shares per outcome
    }

    mapping(bytes32 => Condition) public conditions;
    mapping(bytes32 => bytes32) public conditionQuestionId;
    /// @dev volumePerOutcome[conditionId][outcomeIndex] = total stake on that outcome (same token per condition assumed)
    mapping(bytes32 => mapping(uint256 => uint256)) public volumePerOutcome;
    /// @dev userStake[conditionId][outcomeIndex][user] = user's stake on that outcome
    mapping(bytes32 => mapping(uint256 => mapping(address => uint256))) public userStake;
    /// @dev collateral token per condition (first staker sets it; must match for same conditionId)
    mapping(bytes32 => address) public conditionToken;

    IPermissionManager public permissionManager;
    address public feeCollector;
    uint256 public platformFeeBps;
    address public payoutToken;
    uint256 public accumulatedFees;

    modifier onlyRole(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IPermissionManager _permissionManager) public initializer {
        if (address(_permissionManager) == address(0)) revert ZeroAddress();
        __Pausable_init();
        permissionManager = _permissionManager;
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32)
    {
        return CTHelpersV2.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external whenNotPaused {
        if (outcomeSlotCount < 2) revert TooFewOutcomeSlots();
        if (outcomeSlotCount > 256) revert TooManyOutcomeSlots();
        if (msg.sender != oracle) revert UnauthorizedOracle();

        bytes32 conditionId = CTHelpersV2.getConditionId(oracle, questionId, outcomeSlotCount);
        Condition storage c = conditions[conditionId];
        if (c.status != 0) revert ConditionAlreadyPrepared();

        c.outcomeSlotCount = uint8(outcomeSlotCount);
        c.status = 1;
        c.oracle = oracle;
        c.payoutNumerators = new uint256[](outcomeSlotCount);
        conditionQuestionId[conditionId] = questionId;
        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    function stake(bytes32 conditionId, uint256 outcomeIndex, IERC20 token, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        Condition storage c = conditions[conditionId];
        if (c.status != 1) revert ConditionNotPrepared();
        if (outcomeIndex >= c.outcomeSlotCount) revert InvalidOutcomeIndex();

        address tokenAddr = address(token);
        if (conditionToken[conditionId] != address(0) && conditionToken[conditionId] != tokenAddr) revert WrongToken();
        if (conditionToken[conditionId] == address(0)) conditionToken[conditionId] = tokenAddr;

        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        volumePerOutcome[conditionId][outcomeIndex] += amount;
        userStake[conditionId][outcomeIndex][msg.sender] += amount;

        emit Staked(conditionId, outcomeIndex, msg.sender, tokenAddr, amount);
    }

    function stakeFor(address account, bytes32 conditionId, uint256 outcomeIndex, IERC20 token, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(GAME_CONTRACT_ROLE)
    {
        if (account == address(0)) revert ZeroAddress();
        Condition storage c = conditions[conditionId];
        if (c.status != 1) revert ConditionNotPrepared();
        if (outcomeIndex >= c.outcomeSlotCount) revert InvalidOutcomeIndex();

        address tokenAddr = address(token);
        if (conditionToken[conditionId] != address(0) && conditionToken[conditionId] != tokenAddr) revert WrongToken();
        if (conditionToken[conditionId] == address(0)) conditionToken[conditionId] = tokenAddr;

        if (!token.transferFrom(account, address(this), amount)) revert TransferFailed();

        volumePerOutcome[conditionId][outcomeIndex] += amount;
        userStake[conditionId][outcomeIndex][account] += amount;

        emit Staked(conditionId, outcomeIndex, account, tokenAddr, amount);
    }

    /**
     * @notice Report payout numerators for a condition (oracle only). Single endpoint for all resolutions.
     * @param conditionId The condition ID
     * @param payouts Payout numerator per outcome (e.g. [1,0] single winner, [1,1] refund all, [1,1,0] two winners)
     */
    function reportPayouts(bytes32 conditionId, uint256[] calldata payouts) external whenNotPaused {
        Condition storage c = conditions[conditionId];
        if (c.status == 0) revert ConditionNotPrepared();
        if (c.status == 2) revert ConditionAlreadyResolved();
        if (payouts.length != c.outcomeSlotCount) revert InvalidPayouts();
        if (msg.sender != c.oracle) revert UnauthorizedOracle();

        uint256 denominator = 0;
        for (uint256 i = 0; i < payouts.length;) {
            denominator += payouts[i];
            c.payoutNumerators[i] = payouts[i];
            unchecked {
                ++i;
            }
        }
        if (denominator == 0) revert InvalidPayouts();

        c.payoutDenominator = uint128(denominator);
        c.status = 2;
        emit ConditionResolution(conditionId, c.payoutNumerators);
    }

    function payoutNumerators(bytes32 conditionId) external view returns (uint256[] memory) {
        return conditions[conditionId].payoutNumerators;
    }

    function payoutDenominator(bytes32 conditionId) external view returns (uint256) {
        return conditions[conditionId].payoutDenominator;
    }

    function getTotalVolume(bytes32 conditionId) public view returns (uint256 total) {
        Condition storage c = conditions[conditionId];
        for (uint256 i = 0; i < c.outcomeSlotCount;) {
            total += volumePerOutcome[conditionId][i];
            unchecked {
                ++i;
            }
        }
    }

    function redeem(bytes32 conditionId, IERC20 token) external whenNotPaused nonReentrant {
        _redeemInternal(msg.sender, conditionId, token);
    }

    function redeemFor(address account, bytes32 conditionId, IERC20 token)
        external
        whenNotPaused
        nonReentrant
        onlyRole(GAME_CONTRACT_ROLE)
        returns (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet)
    {
        if (account == address(0)) revert ZeroAddress();
        (payoutGross, feeAmount, payoutNet) = _redeemInternal(account, conditionId, token);
    }

    function _redeemInternal(address account, bytes32 conditionId, IERC20 token)
        internal
        returns (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet)
    {
        Condition storage c = conditions[conditionId];
        if (c.status != 2) revert ConditionNotResolved();
        if (address(token) != conditionToken[conditionId]) revert WrongToken();
        uint256 denominator = c.payoutDenominator;
        if (denominator == 0) revert ConditionNotResolved();

        uint256 totalVolume = getTotalVolume(conditionId);
        payoutGross = 0;

        for (uint256 i = 0; i < c.outcomeSlotCount;) {
            uint256 num = c.payoutNumerators[i];
            if (num > 0) {
                uint256 vol = volumePerOutcome[conditionId][i];
                if (vol > 0) {
                    uint256 userAmt = userStake[conditionId][i][account];
                    if (userAmt > 0) {
                        payoutGross += (userAmt * totalVolume * num) / (vol * denominator);
                    }
                }
            }
            userStake[conditionId][i][account] = 0;
            unchecked {
                ++i;
            }
        }

        if (payoutGross == 0) revert NoStakeToRedeem();

        feeAmount = (payoutGross * platformFeeBps) / MAX_BPS;
        payoutNet = payoutGross - feeAmount;
        accumulatedFees += feeAmount;

        if (!token.transfer(account, payoutNet)) revert TransferFailed();
        emit Redeemed(conditionId, account, address(token), payoutGross, feeAmount, payoutNet);
    }

    function getRedeemableAmount(address account, bytes32 conditionId, IERC20 token)
        external
        view
        returns (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet)
    {
        Condition storage c = conditions[conditionId];
        if (c.status != 2 || address(token) != conditionToken[conditionId] || c.payoutDenominator == 0) {
            return (0, 0, 0);
        }

        uint256 totalVolume = getTotalVolume(conditionId);
        for (uint256 i = 0; i < c.outcomeSlotCount;) {
            uint256 num = c.payoutNumerators[i];
            if (num > 0) {
                uint256 vol = volumePerOutcome[conditionId][i];
                if (vol > 0) {
                    uint256 userAmt = userStake[conditionId][i][account];
                    if (userAmt > 0) {
                        payoutGross += (userAmt * totalVolume * num) / (vol * c.payoutDenominator);
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
        feeAmount = (payoutGross * platformFeeBps) / MAX_BPS;
        payoutNet = payoutGross - feeAmount;
    }

    function claimFees() external {
        uint256 amount = accumulatedFees;
        require(amount > 0, "No fees to claim");
        accumulatedFees = 0;
        if (!IERC20(payoutToken).transfer(feeCollector, amount)) revert TransferFailed();
        emit FeesCollected(payoutToken, amount);
    }

    function setFeeConfig(address _feeCollector, uint256 _feeBps) external onlyRole(PARIMUTUEL_ADMIN_ROLE) {
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_PLATFORM_FEE_BPS) revert InvalidFee(_feeBps);
        feeCollector = _feeCollector;
        platformFeeBps = _feeBps;
        emit FeeConfigUpdated(_feeCollector, _feeBps);
    }

    function setPayoutToken(address _payoutToken) external onlyRole(PARIMUTUEL_ADMIN_ROLE) {
        payoutToken = _payoutToken;
    }

    function pause() external onlyRole(PARIMUTUEL_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PARIMUTUEL_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(PARIMUTUEL_ADMIN_ROLE) {}
}
