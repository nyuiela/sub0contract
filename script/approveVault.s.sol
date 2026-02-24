// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";

/**
 * @title ApproveVault
 * @notice Script to approve the vault to transfer conditional tokens from the user
 * @dev Sets approval for the vault to transfer ERC1155 conditional tokens
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account that will approve
 * - SUB0_ADDRESS: Sub0 contract address
 *
 * Optional Environment Variables:
 * - VAULT_ADDRESS: Vault contract address (if not provided, will get from SUB0_ADDRESS)
 * - IS_APPROVED: Whether to approve (true) or revoke (false) (default: true)
 */
contract ApproveVault is Script {
    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        bool isApproved = vm.envOr("IS_APPROVED", bool(true));

        // Get vault address
        Sub0 sub0 = Sub0(payable(sub0Address));
        address vaultAddress = vm.envExists("VAULT_ADDRESS") ? vm.envAddress("VAULT_ADDRESS") : address(sub0.vault());

        console2.log("=== Approve Vault Script ===");
        console2.log("Caller:", caller);
        console2.log("Vault Address:", vaultAddress);
        console2.log("Is Approved:", isApproved);
        console2.log("");

        Vault vault = Vault(payable(vaultAddress));
        ConditionalTokensV2 ct = ConditionalTokensV2(address(vault.conditionalTokens()));

        console2.log("ConditionalTokens Address:", address(ct));
        console2.log("");

        // Check current approval status
        bool currentlyApproved = ct.isApprovedForAll(caller, vaultAddress);
        console2.log("Current Approval Status:", currentlyApproved);
        console2.log("");

        vm.startBroadcast(callerKey);

        // Set approval
        if (currentlyApproved != isApproved) {
            console2.log(isApproved ? "Approving vault..." : "Revoking vault approval...");
            ct.setApprovalForAll(vaultAddress, isApproved);
            console2.log("[OK] Vault", isApproved ? "approved" : "revoked", "successfully");
        } else {
            console2.log("[SKIP] Vault is already", isApproved ? "approved" : "not approved");
        }
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        bool newStatus = ct.isApprovedForAll(caller, vaultAddress);
        console2.log("Vault is now approved:", newStatus ? "[OK]" : "[NOT APPROVED]");
        console2.log("");

        if (newStatus != isApproved) {
            console2.log("[WARNING] Status mismatch!");
        }

        console2.log("=== Approve Vault Complete ===");
    }
}
