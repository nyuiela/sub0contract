// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CTHelpersV2} from "./CTHelpersV2.sol";

/**
 * @title ConditionalTokensV2
 * @notice Optimized conditional tokens contract with improved gas efficiency and security
 * @dev Based on Gnosis Conditional Token Framework with modern optimizations
 *
 * Key Improvements:
 * - Gas-optimized collection ID generation (removed expensive EC operations)
 * - Custom errors for better gas efficiency
 * - Batch operations support
 * - Access control for oracle management
 * - Pausable functionality
 * - Reentrancy protection
 * - Optimized payout calculations
 * - Better storage packing
 */
contract ConditionalTokensV2 is ERC1155, Pausable, AccessControl, ReentrancyGuard {
    using CTHelpersV2 for *;
    using Math for uint256;

    // Role constants
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    uint256 public constant MAX_BPS = 10000; // 100%
    uint256 public constant MAX_PLATFORM_FEE = 1000; // Max fee cap 10%

    // Custom errors (gas efficient)
    error TooManyOutcomeSlots();
    error TooFewOutcomeSlots();
    error ConditionAlreadyPrepared();
    error ConditionNotPrepared();
    error ConditionAlreadyResolved();
    error ConditionNotResolved();
    error InvalidPartition();
    error InvalidIndexSet();
    error PartitionNotDisjoint();
    error EmptyPartition();
    error InvalidPayouts();
    error TransferFailed();
    error UnauthorizedOracle();
    error InvalidParentCollection();
    error ZeroAddress();
    error InvalidFee(uint256 fee);

    // Events
    event ConditionPreparation(
        bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId, uint256 outcomeSlotCount
    );

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    event PositionSplit(
        address indexed stakeholder,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PositionsMerge(
        address indexed stakeholder,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );
    event FeeConfigUpdated(address feeCollector, uint256 feeBps);
    event FeesCollected(address token, uint256 amount);

    // Storage (packed for gas efficiency)
    struct Condition {
        uint8 outcomeSlotCount; // Max 256 outcomes
        uint8 status; // 0 = not prepared, 1 = prepared, 2 = resolved
        uint128 payoutDenominator; // Denominator for payouts
        uint256[] payoutNumerators; // Payout numerators array
    }

    // Mapping: conditionId => Condition
    mapping(bytes32 => Condition) public conditions;

    // Mapping: conditionId => oracle address (for quick lookup)
    mapping(bytes32 => address) public conditionOracle;

    // Mapping: conditionId => questionId (for quick lookup)
    mapping(bytes32 => bytes32) public conditionQuestionId;

    // Fee Configuration
    address public feeCollector;
    uint256 public platformFeeBps; // 500 = 5%
    address public payoutToken;
    uint256 public accumulatedFees;

    constructor() ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Prepare a condition by initializing payout vector
     * @param oracle The account assigned to report the result
     * @param questionId An identifier for the question
     * @param outcomeSlotCount Number of outcome slots (2-256)
     */
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external whenNotPaused {
        if (outcomeSlotCount > 256) revert TooManyOutcomeSlots();
        if (outcomeSlotCount < 2) revert TooFewOutcomeSlots();
        if (msg.sender != oracle) revert UnauthorizedOracle();

        bytes32 conditionId = CTHelpersV2.getConditionId(oracle, questionId, outcomeSlotCount);
        Condition storage condition = conditions[conditionId];

        if (condition.status != 0) revert ConditionAlreadyPrepared();

        condition.outcomeSlotCount = uint8(outcomeSlotCount);
        condition.status = 1; // Prepared
        condition.payoutNumerators = new uint256[](outcomeSlotCount);
        conditionOracle[conditionId] = oracle;
        conditionQuestionId[conditionId] = questionId;

        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /**
     * @notice Report payouts for a condition (oracle only)
     * @param questionId The question ID
     * @param payouts Array of payout numerators
     */
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external whenNotPaused {
        uint256 outcomeSlotCount = payouts.length;
        if (outcomeSlotCount < 2) revert TooFewOutcomeSlots();

        bytes32 conditionId = CTHelpersV2.getConditionId(msg.sender, questionId, outcomeSlotCount);
        Condition storage condition = conditions[conditionId];

        if (condition.status == 0) revert ConditionNotPrepared();
        if (condition.status == 2) revert ConditionAlreadyResolved();
        if (condition.payoutNumerators.length != outcomeSlotCount) revert ConditionNotPrepared();

        // Verify oracle has permission (either ORACLE_ROLE or is the original oracle)
        // if (!hasRole(ORACLE_ROLE, msg.sender) && conditionOracle[conditionId] != msg.sender) {
        //     revert UnauthorizedOracle();
        // }

        uint256 denominator = 0;
        uint256[] storage numerators = condition.payoutNumerators;

        // Calculate denominator and validate payouts
        for (uint256 i = 0; i < outcomeSlotCount;) {
            uint256 payout = payouts[i];
            if (numerators[i] != 0) revert InvalidPayouts(); // Already set

            unchecked {
                denominator += payout;
                numerators[i] = payout;
                ++i;
            }
        }

        if (denominator == 0) revert InvalidPayouts();

        condition.payoutDenominator = uint128(denominator);
        condition.status = 2; // Resolved

        emit ConditionResolution(conditionId, msg.sender, questionId, outcomeSlotCount, payouts);
    }

    /**
     * @notice Split a position into multiple outcome positions
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID (bytes32(0) for root)
     * @param conditionId The condition ID
     * @param partition Array of disjoint index sets
     * @param amount Amount to split
     */
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (partition.length < 2) revert EmptyPartition();

        Condition storage condition = conditions[conditionId];
        if (condition.status == 0) revert ConditionNotPrepared();

        uint256 outcomeSlotCount = condition.outcomeSlotCount;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        // Validate partition and prepare position IDs
        uint256[] memory positionIds = new uint256[](partition.length);
        uint256[] memory amounts = new uint256[](partition.length);

        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();

            unchecked {
                freeIndexSet ^= indexSet;
                positionIds[i] = CTHelpersV2.getPositionId(
                    collateralToken, CTHelpersV2.getCollectionId(parentCollectionId, conditionId, indexSet)
                );
                amounts[i] = amount;
                ++i;
            }
        }

        // Handle collateral transfer or burn
        if (freeIndexSet == 0) {
            // Full partition - transfer from collateral or burn parent
            if (parentCollectionId == bytes32(0)) {
                if (!collateralToken.transferFrom(msg.sender, address(this), amount)) {
                    revert TransferFailed();
                }
            } else {
                uint256 parentPositionId = CTHelpersV2.getPositionId(collateralToken, parentCollectionId);
                _burn(msg.sender, parentPositionId, amount);
            }
        } else {
            // Partial partition - burn subset position
            uint256 subsetPositionId = CTHelpersV2.getPositionId(
                collateralToken,
                CTHelpersV2.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)
            );
            _burn(msg.sender, subsetPositionId, amount);
        }

        // Mint new positions
        _mintBatch(msg.sender, positionIds, amounts, "");

        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /**
     * @notice Split position on behalf of an account (for game hubs; uses account as stakeholder)
     * @param account The account to split position for (receives outcome tokens, provides collateral)
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID
     * @param conditionId The condition ID
     * @param partition Array of disjoint index sets
     * @param amount Amount to split
     */
    function splitPositionFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external whenNotPaused nonReentrant onlyRole(GAME_CONTRACT_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (partition.length < 2) revert EmptyPartition();

        Condition storage condition = conditions[conditionId];
        if (condition.status == 0) revert ConditionNotPrepared();

        uint256 outcomeSlotCount = condition.outcomeSlotCount;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        uint256[] memory positionIds = new uint256[](partition.length);
        uint256[] memory amounts = new uint256[](partition.length);

        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();

            unchecked {
                freeIndexSet ^= indexSet;
                positionIds[i] = CTHelpersV2.getPositionId(
                    collateralToken, CTHelpersV2.getCollectionId(parentCollectionId, conditionId, indexSet)
                );
                amounts[i] = amount;
                ++i;
            }
        }

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                if (!collateralToken.transferFrom(account, address(this), amount)) {
                    revert TransferFailed();
                }
            } else {
                uint256 parentPositionId = CTHelpersV2.getPositionId(collateralToken, parentCollectionId);
                _burn(account, parentPositionId, amount);
            }
        } else {
            uint256 subsetPositionId = CTHelpersV2.getPositionId(
                collateralToken,
                CTHelpersV2.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)
            );
            _burn(account, subsetPositionId, amount);
        }

        _mintBatch(account, positionIds, amounts, "");

        emit PositionSplit(account, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /**
     * @notice Merge positions back into collateral
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID
     * @param conditionId The condition ID
     * @param partition Array of disjoint index sets to merge
     * @param amount Amount to merge
     */
    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (partition.length < 2) revert EmptyPartition();

        Condition storage condition = conditions[conditionId];
        if (condition.status == 0) revert ConditionNotPrepared();

        uint256 outcomeSlotCount = condition.outcomeSlotCount;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        uint256[] memory positionIds = new uint256[](partition.length);
        uint256[] memory amounts = new uint256[](partition.length);

        // Validate partition
        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();

            unchecked {
                freeIndexSet ^= indexSet;
                positionIds[i] = CTHelpersV2.getPositionId(
                    collateralToken, CTHelpersV2.getCollectionId(parentCollectionId, conditionId, indexSet)
                );
                amounts[i] = amount;
                ++i;
            }
        }

        // Burn positions
        _burnBatch(msg.sender, positionIds, amounts);

        // Mint collateral or parent position
        if (freeIndexSet == 0) {
            // Full merge - return collateral or mint parent
            if (parentCollectionId == bytes32(0)) {
                if (!collateralToken.transfer(msg.sender, amount)) {
                    revert TransferFailed();
                }
            } else {
                uint256 parentPositionId = CTHelpersV2.getPositionId(collateralToken, parentCollectionId);
                _mint(msg.sender, parentPositionId, amount, "");
            }
        } else {
            // Partial merge - mint subset position
            uint256 subsetPositionId = CTHelpersV2.getPositionId(
                collateralToken,
                CTHelpersV2.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)
            );
            _mint(msg.sender, subsetPositionId, amount, "");
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /**
     * @notice Redeem winning positions for collateral
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID
     * @param conditionId The condition ID
     * @param indexSets Array of index sets to redeem
     */
    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external whenNotPaused nonReentrant {
        _redeemPositionsInternal(collateralToken, parentCollectionId, conditionId, indexSets);
    }

    /**
     * @notice Redeem winning positions on behalf of an account (for game hubs)
     * @param account The account to redeem for (burns their positions, receives payout)
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID
     * @param conditionId The condition ID
     * @param indexSets Array of index sets to redeem
     */
    function redeemPositionsFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external whenNotPaused nonReentrant onlyRole(GAME_CONTRACT_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        _redeemPositionsInternalFor(account, collateralToken, parentCollectionId, conditionId, indexSets);
    }

    /**
     * @notice Batch redeem multiple positions (gas optimized)
     * @param redemptions Array of redemption parameters
     */
    function batchRedeemPositions(RedemptionParams[] calldata redemptions) external whenNotPaused nonReentrant {
        uint256 totalRedemptions = redemptions.length;

        for (uint256 r = 0; r < totalRedemptions;) {
            RedemptionParams calldata params = redemptions[r];
            _redeemPositionsInternal(
                params.collateralToken, params.parentCollectionId, params.conditionId, params.indexSets
            );
            unchecked {
                ++r;
            }
        }
    }

    function _sumPayoutNumerator(Condition storage condition, uint256 indexSet, uint256 outcomeSlotCount)
        internal
        view
        returns (uint256 n)
    {
        uint256[] memory nums = condition.payoutNumerators;
        for (uint256 j = 0; j < outcomeSlotCount;) {
            if (indexSet & (1 << j) != 0) n += nums[j];
            unchecked {
                ++j;
            }
        }
    }

    /**
     * @notice Internal redemption (used by redeemPositions, redeemPositionsFor, batchRedeemPositions)
     */
    function _redeemPositionsInternal(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) internal {
        _redeemPositionsFor(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets);
    }

    function _redeemPositionsInternalFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) internal {
        _redeemPositionsFor(account, collateralToken, parentCollectionId, conditionId, indexSets);
    }

    function _redeemPositionsFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) private {
        Condition storage condition = conditions[conditionId];
        if (condition.status != 2) revert ConditionNotResolved();
        uint256 denominator = condition.payoutDenominator;
        if (denominator == 0) revert ConditionNotResolved();

        uint256 outcomeSlotCount = condition.outcomeSlotCount;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 totalPayout = 0;

        for (uint256 i = 0; i < indexSets.length;) {
            uint256 indexSet = indexSets[i];
            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();

            uint256 positionId = CTHelpersV2.getPositionId(
                collateralToken, CTHelpersV2.getCollectionId(parentCollectionId, conditionId, indexSet)
            );
            uint256 num = _sumPayoutNumerator(condition, indexSet, outcomeSlotCount);
            uint256 bal = balanceOf(account, positionId);
            if (bal > 0) {
                totalPayout += (bal * num) / denominator;
                _burn(account, positionId, bal);
            }
            unchecked {
                ++i;
            }
        }

        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                uint256 feeAmount = (totalPayout * platformFeeBps) / MAX_BPS;
                totalPayout -= feeAmount;
                accumulatedFees += feeAmount;
                if (!collateralToken.transfer(account, totalPayout)) revert TransferFailed();
            } else {
                uint256 parentPositionId = CTHelpersV2.getPositionId(collateralToken, parentCollectionId);
                _mint(account, parentPositionId, totalPayout, "");
            }
        }

        emit PayoutRedemption(account, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    // View functions
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256) {
        return conditions[conditionId].outcomeSlotCount;
    }

    function payoutNumerators(bytes32 conditionId) external view returns (uint256[] memory) {
        return conditions[conditionId].payoutNumerators;
    }

    function payoutDenominator(bytes32 conditionId) external view returns (uint256) {
        return conditions[conditionId].payoutDenominator;
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32)
    {
        return CTHelpersV2.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        pure
        returns (bytes32)
    {
        return CTHelpersV2.getCollectionId(parentCollectionId, conditionId, indexSet);
    }

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256) {
        return CTHelpersV2.getPositionId(collateralToken, collectionId);
    }

    // Admin functions
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Set the URI for all token types
     * @dev Uses {id} substitution for token IDs, e.g., https://api.example.com/token/{id}.json
     * @param newuri The new URI to set for all token types
     */
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    function claimFees() external {
        uint256 amount = accumulatedFees;
        require(amount > 0, "No fees to claim");

        accumulatedFees = 0;
        IERC20(payoutToken).transfer(feeCollector, amount);

        emit FeesCollected(payoutToken, amount);
    }

    function withdraw(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // force withdraw of fees from vault.
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient balance");
        require(to != address(0), "Invalid address");
        IERC20(token).transfer(to, amount);
    }

    function setFeeConfig(address _feeCollector, uint256 _feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_PLATFORM_FEE) revert InvalidFee(_feeBps);

        feeCollector = _feeCollector;
        platformFeeBps = _feeBps;
        emit FeeConfigUpdated(_feeCollector, _feeBps);
    }

    function setPayoutToken(address _payoutToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payoutToken = _payoutToken;
    }

    /**
     * @dev See {IERC165-supportsInterface}
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Types
    struct RedemptionParams {
        IERC20 collateralToken;
        bytes32 parentCollectionId;
        bytes32 conditionId;
        uint256[] indexSets;
    }
}
