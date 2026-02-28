// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {PredictionVault} from "../src/gamehub/PredictionVault.sol";
import {IPredictionVault} from "../src/interfaces/IPredictionVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SeedMarket
 * @notice Script to seed liquidity on PredictionVault for a registered market.
 *         Caller must be the vault owner. USDC is pulled from caller and split into
 *         full outcome set (CTF) held by the vault.
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Owner private key (must be PredictionVault owner)
 * - QUESTION_ID: The question ID (bytes32) as hex string (0x...)
 * - AMOUNT_USDC: Amount in USDC units (6 decimals), e.g. 1000000 = 1 USDC
 *
 * Optional (one required):
 * - PREDICTION_VAULT_ADDRESS: PredictionVault contract address, or
 * - SUB0_ADDRESS: Sub0 contract address (script uses sub0.predictionVault())
 */
contract SeedMarket is Script {
    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        bytes32 questionId = vm.envBytes32("QUESTION_ID");
        uint256 amountUsdc = vm.envUint("AMOUNT_USDC");

        address predictionVaultAddress;
        if (vm.envOr("PREDICTION_VAULT_ADDRESS", address(0)) != address(0)) {
            predictionVaultAddress = vm.envAddress("PREDICTION_VAULT_ADDRESS");
        } else {
            address sub0Address = vm.envAddress("SUB0_ADDRESS");
            Sub0 sub0 = Sub0(payable(sub0Address));
            predictionVaultAddress = address(sub0.predictionVault());
        }

        PredictionVault vault = PredictionVault(predictionVaultAddress);
        address usdcAddress = address(vault.usdc());

        console2.log("=== Seed Market (PredictionVault) ===");
        console2.log("Owner:", owner);
        console2.log("PredictionVault:", predictionVaultAddress);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Amount USDC:", amountUsdc);
        console2.log("USDC token:", usdcAddress);
        console2.log("");

        if (vault.getConditionId(questionId) == bytes32(0)) {
            revert("Market not registered for this questionId");
        }

        vm.startBroadcast(ownerKey);

        IERC20 usdc = IERC20(usdcAddress);
        usdc.approve(predictionVaultAddress, type(uint256).max);
        vault.seedMarketLiquidity(questionId, amountUsdc);

        vm.stopBroadcast();

        console2.log("[OK] Market liquidity seeded.");
    }
}
