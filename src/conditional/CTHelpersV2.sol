// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CTHelpersV2
 * @notice Optimized helper library for conditional tokens
 * @dev Gas-optimized version without expensive elliptic curve operations
 */
library CTHelpersV2 {
    /**
     * @notice Constructs a condition ID from oracle, question ID, and outcome slot count
     * @param oracle The oracle address
     * @param questionId The question identifier
     * @param outcomeSlotCount Number of outcome slots
     * @return conditionId The computed condition ID
     */
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /**
     * @notice Constructs a condition ID with game address to prevent collisions across games
     * @param gameAddress The game contract address
     * @param oracle The oracle address
     * @param questionId The question identifier
     * @param outcomeSlotCount Number of outcome slots
     * @return conditionId The computed condition ID (unique per game)
     */
    function getConditionIdWithGame(address gameAddress, address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(gameAddress, oracle, questionId, outcomeSlotCount));
    }

    /**
     * @notice Constructs a collection ID (optimized version without EC operations)
     * @dev Uses simple keccak256 hash instead of expensive elliptic curve addition
     *      This is safe because collection IDs are only used internally and don't need
     *      cryptographic properties of EC operations
     * @param parentCollectionId Parent collection ID (bytes32(0) for root)
     * @param conditionId The condition ID
     * @param indexSet The index set (bitmap of outcomes)
     * @return collectionId The computed collection ID
     */
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        internal
        pure
        returns (bytes32)
    {
        // Optimized: Use simple hash instead of expensive EC operations
        // This saves ~50k+ gas per operation while maintaining uniqueness
        if (parentCollectionId == bytes32(0)) {
            return keccak256(abi.encodePacked(conditionId, indexSet));
        }
        return keccak256(abi.encodePacked(parentCollectionId, conditionId, indexSet));
    }

    /**
     * @notice Constructs a position ID from collateral token and collection ID
     * @param collateralToken The collateral token address
     * @param collectionId The collection ID
     * @return positionId The computed position ID (ERC1155 token ID)
     */
    function getPositionId(IERC20 collateralToken, bytes32 collectionId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }
}
