// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Oracle} from "../src/oracle/oracle.sol";

/**
 * @title AllowListReporter
 * @notice Script to allow or remove reporters in the Oracle contract
 * @dev Calls allowListReporter to manage reporter permissions
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account with ORACLE_MANAGER_ROLE
 * - ORACLE_ADDRESS: Oracle contract address
 * - REPORTER_ADDRESS: The reporter address to allow or remove
 *
 * Optional Environment Variables:
 * - IS_ALLOWED: Whether to allow (true) or remove (false) the reporter (default: true)
 */
contract AllowListReporter is Script {
    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address reporterAddress = vm.envAddress("REPORTER_ADDRESS");
        bool isAllowed = vm.envOr("IS_ALLOWED", bool(true));

        console2.log("=== Allow List Reporter Script ===");
        console2.log("Caller:", caller);
        console2.log("Oracle Address:", oracleAddress);
        console2.log("Reporter Address:", reporterAddress);
        console2.log("Is Allowed:", isAllowed);
        console2.log("");

        Oracle oracle = Oracle(oracleAddress);

        // Check current status
        bool currentlyAllowed = oracle.isAllowed(reporterAddress);
        console2.log("Current Status:");
        console2.log("  Reporter is allowed:", currentlyAllowed);
        console2.log("");

        vm.startBroadcast(callerKey);

        // Allow or remove reporter
        if (currentlyAllowed != isAllowed) {
            console2.log(isAllowed ? "Allowing reporter..." : "Removing reporter...");
            oracle.allowListReporter(reporterAddress, isAllowed);
            console2.log("[OK] Reporter", isAllowed ? "allowed" : "removed", "successfully");
        } else {
            console2.log("[SKIP] Reporter is already", isAllowed ? "allowed" : "removed");
        }
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        bool newStatus = oracle.isAllowed(reporterAddress);
        console2.log("Reporter is now allowed:", newStatus ? "[OK]" : "[NOT ALLOWED]");
        console2.log("");

        if (newStatus != isAllowed) {
            console2.log("[WARNING] Status mismatch! Expected:", isAllowed, "but got:", newStatus);
            console2.log("");
        }

        console2.log("=== Allow List Reporter Complete ===");
    }
}
