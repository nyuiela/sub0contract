// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConditionalTokensV2} from "./ConditionalTokensV2.sol";

/**
 * @title ConditionalTokensV2ViewHelper
 * @notice Offloads view logic (e.g. getRedeemableAmount) to avoid stack-too-deep in ConditionalTokensV2
 */
contract ConditionalTokensV2ViewHelper {
    uint256 private constant MAX_BPS = 10000;

    /**
     * @notice Get redeemable amounts and fee for an account (view, no state change)
     * @param ct ConditionalTokensV2 contract
     * @param account The account that would redeem
     * @param collateralToken The collateral token address
     * @param parentCollectionId Parent collection ID (bytes32(0) for root)
     * @param conditionId The condition ID
     * @param indexSets Array of index sets that would be redeemed (e.g. [1] for outcome 0)
     * @return payoutGross Gross payout before fee (raw redemption value)
     * @return feeAmount Fee that would be deducted (platformFeeBps applied when parentCollectionId is 0)
     * @return payoutNet Net amount the account would receive after fee
     */
    function getRedeemableAmount(
        ConditionalTokensV2 ct,
        address account,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external view returns (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet) {
        uint256 nSlots = ct.getOutcomeSlotCount(conditionId);
        uint256 denom = ct.payoutDenominator(conditionId);
        if (denom == 0) return (0, 0, 0);

        uint256 fullSet = (1 << nSlots) - 1;

        for (uint256 i = 0; i < indexSets.length;) {
            uint256 idxSet = indexSets[i];
            if (idxSet == 0 || idxSet >= fullSet) return (0, 0, 0);

            uint256 num = _sumPayoutNumerator(ct, conditionId, idxSet, nSlots);
            bytes32 collectionId = ct.getCollectionId(parentCollectionId, conditionId, idxSet);
            uint256 posId = ct.getPositionId(collateralToken, collectionId);
            payoutGross += (ct.balanceOf(account, posId) * num) / denom;
            unchecked {
                ++i;
            }
        }

        if (parentCollectionId == bytes32(0)) {
            uint256 feeBps = ct.platformFeeBps();
            feeAmount = (payoutGross * feeBps) / MAX_BPS;
            payoutNet = payoutGross - feeAmount;
        } else {
            feeAmount = 0;
            payoutNet = payoutGross;
        }
    }

    function _sumPayoutNumerator(
        ConditionalTokensV2 ct,
        bytes32 conditionId,
        uint256 indexSet,
        uint256 outcomeSlotCount
    ) internal view returns (uint256 num) {
        uint256[] memory nums = ct.payoutNumerators(conditionId);
        for (uint256 j = 0; j < outcomeSlotCount;) {
            if (indexSet & (1 << j) != 0) num += nums[j];
            unchecked {
                ++j;
            }
        }
    }
}
