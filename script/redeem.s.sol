// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CTHelpersV2} from "../src/conditional/CTHelpersV2.sol";

/**
 * @title Redeem
 * @notice Script to redeem winning positions after a bet is resolved
 * @dev Checks bet status, position balance, and approvals before calling redeem
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account that will redeem
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION_ID: The question ID (bytes32) as a hex string (0x...)
 * - OPTION: The option index to redeem (uint256)
 */
contract Redeem is Script {
    function run() external {
        uint256 redeemerKey = vm.envUint("PRIVATE_KEY");
        address redeemer = vm.addr(redeemerKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        bytes32 questionId = vm.envBytes32("QUESTION_ID");
        uint256 option = vm.envUint("OPTION");

        console2.log("=== Redeem Script ===");
        console2.log("Redeemer:", redeemer);
        console2.log("Sub0 Address:", sub0Address);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Option Index:", option);
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        address vaultAddr = address(sub0.vault());
        Vault vault = Vault(payable(vaultAddr));

        console2.log("Vault Address:", vaultAddr);
        console2.log("");

        // Get market information
        Sub0.Market memory market = sub0.getMarket(questionId);
        console2.log("Market Information:");
        console2.log("  Question:", market.question);
        console2.log("  Condition ID:", vm.toString(market.conditionId));
        console2.log("  Outcome Count:", market.outcomeSlotCount);
        console2.log("");

        // Check if condition is prepared
        bytes32 conditionId = market.conditionId;
        if (conditionId == bytes32(0)) {
            console2.log("[ERROR] Condition not prepared for this question ID");
            revert("Condition not prepared");
        }

        ConditionalTokensV2 ct = ConditionalTokensV2(address(vault.conditionalTokens()));

        // Check if condition is resolved
        uint256 denominator = ct.payoutDenominator(conditionId);
        if (denominator == 0) {
            console2.log("[ERROR] Condition not resolved yet");
            console2.log("[INFO] The bet must be resolved before redeeming");
            revert("Condition not resolved");
        }
        console2.log("[OK] Condition is resolved (denominator:", denominator, ")");

        // Check option index validity
        if (option >= market.outcomeSlotCount) {
            console2.log("[ERROR] Invalid option index");
            console2.log("[INFO] Option index must be less than outcome count:", market.outcomeSlotCount);
            revert("Invalid option index");
        }

        // Calculate position ID
        uint256 indexSet = 1 << option;
        address payoutToken = ct.payoutToken();
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(payoutToken), collectionId);

        console2.log("Position ID:", positionId);
        console2.log("");

        // Check user's position balance
        uint256 positionBalance = ct.balanceOf(redeemer, positionId);
        console2.log("Position Balance:", positionBalance);
        if (positionBalance == 0) {
            console2.log("[ERROR] No position balance found for this option");
            console2.log("[INFO] You must have staked on option", option, "to redeem");
            revert("No position balance");
        }

        // Check approval for conditional tokens (Sub0 calls redeemPositionsFor on behalf of user)
        bool isApproved = ct.isApprovedForAll(redeemer, sub0Address);
        console2.log("Sub0 Approval Status:", isApproved ? "[OK]" : "[NOT APPROVED]");
        console2.log("");

        // Get payout information (fees are on ConditionalTokensV2)
        uint256[] memory numerators = ct.payoutNumerators(conditionId);
        uint256 payoutNumerator = 0;
        for (uint256 j = 0; j < market.outcomeSlotCount;) {
            if (indexSet & (1 << j) != 0) {
                payoutNumerator += numerators[j];
            }
            unchecked {
                ++j;
            }
        }
        uint256 expectedPayout = (positionBalance * payoutNumerator) / denominator;
        uint256 feeBps = ct.platformFeeBps();
        uint256 feeAmount = (expectedPayout * feeBps) / 10000;
        uint256 netAmount = expectedPayout - feeAmount;

        console2.log("Expected Payout:", expectedPayout);
        console2.log("Fee BPS:", feeBps);
        console2.log("Net Amount (after fee):", netAmount);
        console2.log("");

        vm.startBroadcast(redeemerKey);

        // Approve Sub0 to move conditional tokens on user's behalf
        if (!isApproved) {
            console2.log("Approving Sub0 for conditional tokens...");
            ct.setApprovalForAll(sub0Address, true);
            console2.log("[OK] Sub0 approved successfully");
            console2.log("");
        }

        // Redeem via Sub0 (requires EIP-712 signature from redeemer)
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = indexSet;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = sub0.redeemNonce(redeemer);
        bytes32 indexSetsHash = keccak256(abi.encode(indexSets));
        bytes32 digest = sub0.getRedeemDigest(bytes32(0), conditionId, indexSetsHash, payoutToken, deadline, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(redeemerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        console2.log("Redeeming winning positions...");
        sub0.redeem(bytes32(0), conditionId, indexSets, payoutToken, deadline, nonce, signature);
        console2.log("[OK] Successfully redeemed option", option);
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        _verifyRedeem(ct, redeemer, positionId, payoutToken);
        console2.log("=== Redeem Complete ===");
    }

    function _verifyRedeem(ConditionalTokensV2 ct, address redeemer, uint256 positionId, address payoutToken)
        internal
        view
    {
        uint256 newPositionBalance = ct.balanceOf(redeemer, positionId);
        uint256 newTokenBalance = IERC20(payoutToken).balanceOf(redeemer);
        console2.log("Position Balance (after):", newPositionBalance);
        console2.log("Payout Token Balance:", newTokenBalance);
        console2.log("");

        if (newPositionBalance > 0) {
            console2.log("[WARNING] Position balance still exists. Redeem may have failed partially.");
        }
    }
}
