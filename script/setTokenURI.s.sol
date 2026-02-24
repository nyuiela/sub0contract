// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";

/**
 * @title SetTokenURI
 * @notice Script to set the token URI for ConditionalTokensV2 contract
 * @dev Sets the base URI that will be used for all token metadata
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account with DEFAULT_ADMIN_ROLE
 * - CONDITIONAL_TOKENS_V2_ADDRESS: ConditionalTokensV2 contract address
 * - TOKEN_URI: The base URI for tokens (supports {id} substitution, e.g., "https://api.example.com/token/{id}.json")
 */
contract SetTokenURI is Script {
    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address conditionalTokensAddress = vm.envAddress("CONDITIONAL_TOKENS_V2_ADDRESS");
        string memory tokenURI = vm.envString("TOKEN_URI");

        console2.log("=== Set Token URI Script ===");
        console2.log("Caller:", caller);
        console2.log("ConditionalTokensV2 Address:", conditionalTokensAddress);
        console2.log("Token URI:", tokenURI);
        console2.log("");

        ConditionalTokensV2 conditionalTokens = ConditionalTokensV2(conditionalTokensAddress);

        // Check current URI (for any token ID, they all use the same base URI)
        string memory currentURI = conditionalTokens.uri(0);
        console2.log("Current URI:", currentURI);
        console2.log("");

        vm.startBroadcast(callerKey);

        // Set the new URI
        console2.log("Setting token URI...");
        conditionalTokens.setURI(tokenURI);
        console2.log("[OK] Token URI set successfully");
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        string memory newURI = conditionalTokens.uri(0);
        console2.log("New URI:", newURI);

        // Check if URI was updated
        bool uriMatches = keccak256(bytes(newURI)) == keccak256(bytes(tokenURI));
        console2.log("URI matches:", uriMatches ? "[OK]" : "[MISMATCH]");
        console2.log("");
        console2.log("=== Set Token URI Complete ===");
    }
}
