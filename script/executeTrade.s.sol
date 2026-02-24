// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {IPredictionVault} from "../src/interfaces/IPredictionVault.sol";

/**
 * @title ExecuteTrade
 * @notice Relayer script: submit DON + user signatures to PredictionVault.executeTrade.
 *        User must have approved USDC to PredictionVault (for buy). Relayer pays gas.
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Relayer private key (pays gas)
 * - SUB0_ADDRESS: Sub0 (used to get PredictionVault) or set PREDICTION_VAULT_ADDRESS
 * - QUESTION_ID: Market question ID (bytes32 hex)
 * - OUTCOME_INDEX: Outcome index (uint256)
 * - BUY: true/false (string or 1/0)
 * - QUANTITY: Outcome token amount (18 decimals)
 * - TRADE_COST_USDC: From DON quote (6 decimals)
 * - MAX_COST_USDC: User-authorized max (buy) or min receive (sell)
 * - NONCE: Per-market nonce
 * - DEADLINE: Unix timestamp
 * - USER_ADDRESS: The user (signer of userSignature; pays/receives USDC)
 * - DON_SIGNATURE: Hex string (0x...) of DON EIP-712 signature
 * - USER_SIGNATURE: Hex string (0x...) of user EIP-712 signature
 */
contract ExecuteTrade is Script {
    function run() external {
        uint256 relayerKey = vm.envUint("PRIVATE_KEY");

        address predictionVaultAddress;
        if (vm.envOr("PREDICTION_VAULT_ADDRESS", address(0)) != address(0)) {
            predictionVaultAddress = vm.envAddress("PREDICTION_VAULT_ADDRESS");
        } else {
            address sub0Address = vm.envAddress("SUB0_ADDRESS");
            predictionVaultAddress = address(Sub0(payable(sub0Address)).predictionVault());
        }

        bytes32 questionId = vm.envBytes32("QUESTION_ID");
        uint256 outcomeIndex = vm.envUint("OUTCOME_INDEX");
        bool buy = vm.envOr("BUY", uint256(1)) != 0;
        uint256 quantity = vm.envUint("QUANTITY");
        uint256 tradeCostUsdc = vm.envUint("TRADE_COST_USDC");
        uint256 maxCostUsdc = vm.envUint("MAX_COST_USDC");
        uint256 nonce = vm.envUint("NONCE");
        uint256 deadline = vm.envUint("DEADLINE");
        address user = vm.envAddress("USER_ADDRESS");

        bytes memory donSignature = vm.parseBytes(vm.envString("DON_SIGNATURE"));
        bytes memory userSignature = vm.parseBytes(vm.envString("USER_SIGNATURE"));

        console2.log("=== Execute Trade ===");
        console2.log("Relayer:", vm.addr(relayerKey));
        console2.log("PredictionVault:", predictionVaultAddress);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Outcome Index:", outcomeIndex);
        console2.log("Buy:", buy);
        console2.log("Quantity:", quantity);
        console2.log("Trade Cost USDC:", tradeCostUsdc);
        console2.log("Max Cost USDC:", maxCostUsdc);
        console2.log("User:", user);
        console2.log("Nonce:", nonce);
        console2.log("Deadline:", deadline);
        console2.log("");

        IPredictionVault vault = IPredictionVault(predictionVaultAddress);

        vm.startBroadcast(relayerKey);
        vault.executeTrade(
            questionId,
            outcomeIndex,
            buy,
            quantity,
            tradeCostUsdc,
            maxCostUsdc,
            nonce,
            deadline,
            user,
            donSignature,
            userSignature
        );
        vm.stopBroadcast();

        console2.log("[OK] Trade executed.");
    }
}
