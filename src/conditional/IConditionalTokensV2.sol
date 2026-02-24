// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title IConditionalTokensV2
 * @notice Interface for the optimized ConditionalTokensV2 contract
 */
interface IConditionalTokensV2 is IERC1155 {
    // Errors
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

    // Types
    struct RedemptionParams {
        IERC20 collateralToken;
        bytes32 parentCollectionId;
        bytes32 conditionId;
        uint256[] indexSets;
    }

    // Functions
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external;

    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external;

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    function splitPositionFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function redeemPositionsFor(
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    function batchRedeemPositions(RedemptionParams[] calldata redemptions) external;

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);

    function payoutNumerators(bytes32 conditionId) external view returns (uint256[] memory);

    function payoutDenominator(bytes32 conditionId) external view returns (uint256);

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32);

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        pure
        returns (bytes32);

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256);

    function pause() external;
    function unpause() external;
}
