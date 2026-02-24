// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title AllowListToken
 * @notice Script to allow list a token and configure it in the TokensManager contract
 * @dev Calls allowListToken, setDecimals, and setPriceFeed
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account with TOKEN_MANAGER_ROLE
 * - TOKEN_ADDRESS: The token contract address to allow list
 * - PRICE_FEED_ADDRESS: Chainlink price feed address for the token (required for vault deposits)
 *
 * Optional Environment Variables:
 * - TOKENS_MANAGER_ADDRESS: TokensManager contract address (if not provided, will get from SUB0_ADDRESS)
 * - SUB0_ADDRESS: Sub0 contract address (only needed if TOKENS_MANAGER_ADDRESS not provided)
 * - DECIMALS: Token decimals to set (uint8, optional - will try to read from token if not provided, defaults to 18)
 * - IS_ALLOWED: Whether to allow (true) or disallow (false) the token (default: true)
 */
contract AllowListToken is Script {
    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        bool isAllowed = vm.envOr("IS_ALLOWED", bool(true));

        // Get TokensManager address
        address tokensManagerAddress;
        if (vm.envExists("TOKENS_MANAGER_ADDRESS")) {
            tokensManagerAddress = vm.envAddress("TOKENS_MANAGER_ADDRESS");
        } else if (vm.envExists("SUB0_ADDRESS")) {
            address sub0Address = vm.envAddress("SUB0_ADDRESS");
            Sub0 sub0 = Sub0(payable(sub0Address));
            tokensManagerAddress = address(sub0.tokenManager());
        } else {
            revert("Either TOKENS_MANAGER_ADDRESS or SUB0_ADDRESS must be set");
        }

        // Get price feed address (required for vault deposits)
        address priceFeedAddress = address(0);
        if (vm.envExists("PRICE_FEED_ADDRESS")) {
            priceFeedAddress = vm.envAddress("PRICE_FEED_ADDRESS");
        }

        console2.log("=== Allow List Token Script ===");
        console2.log("Caller:", caller);
        console2.log("TokensManager Address:", tokensManagerAddress);
        console2.log("Token Address:", tokenAddress);
        console2.log("Price Feed Address:", priceFeedAddress);
        console2.log("Is Allowed:", isAllowed);
        console2.log("");

        TokensManager tokensManager = TokensManager(tokensManagerAddress);

        // Check current configuration
        bool currentlyAllowed = tokensManager.allowedTokens(tokenAddress);
        bool isBanned = tokensManager.bannedTokens(tokenAddress);
        address currentPriceFeed = tokensManager.getPriceFeed(tokenAddress);
        (, uint8 currentDecimals) = tokensManager.getDecimal(tokenAddress);

        console2.log("Current Configuration:");
        console2.log("  Allowed:", currentlyAllowed);
        console2.log("  Banned:", isBanned);
        console2.log("  Price Feed:", currentPriceFeed);
        console2.log("  Decimals:", currentDecimals);
        console2.log("");

        // Try to read decimals from token contract if not provided and token is ERC20Metadata
        uint8 tokenDecimals = 18; // Default to 18
        if (!vm.envExists("DECIMALS")) {
            try IERC20Metadata(tokenAddress).decimals() returns (uint8 decimals) {
                tokenDecimals = decimals;
                console2.log("Token decimals (from contract):", tokenDecimals);
            } catch {
                console2.log("[INFO] Could not read decimals from token contract, will use default: 18");
            }
        } else {
            tokenDecimals = uint8(vm.envUint("DECIMALS"));
        }
        console2.log("");

        vm.startBroadcast(callerKey);

        // Step 1: Allow list the token
        if (currentlyAllowed != isAllowed) {
            console2.log(isAllowed ? "Allowing token..." : "Disallowing token...");
            tokensManager.allowListToken(tokenAddress, isAllowed);
            console2.log("[OK] Token", isAllowed ? "allowed" : "disallowed", "successfully");
        } else {
            console2.log("[SKIP] Token is already", isAllowed ? "allowed" : "disallowed");
        }
        console2.log("");

        // Step 2: Set decimals (if token is being allowed)
        if (isAllowed) {
            if (currentDecimals != tokenDecimals) {
                console2.log("Setting token decimals to:", tokenDecimals);
                tokensManager.setDecimals(tokenAddress, tokenDecimals);
                console2.log("[OK] Decimals set successfully");
            } else {
                console2.log("[SKIP] Decimals already set to:", currentDecimals);
            }
            console2.log("");
        }

        // Step 3: Set price feed (required for vault deposits, only if allowing token)
        if (isAllowed && priceFeedAddress != address(0)) {
            if (currentPriceFeed != priceFeedAddress) {
                console2.log("Setting price feed to:", priceFeedAddress);
                tokensManager.setPriceFeed(tokenAddress, priceFeedAddress);
                console2.log("[OK] Price feed set successfully");
            } else {
                console2.log("[SKIP] Price feed already set to:", currentPriceFeed);
            }
            console2.log("");
        } else if (isAllowed && priceFeedAddress == address(0)) {
            console2.log("[WARNING] PRICE_FEED_ADDRESS not set!");
            console2.log("[WARNING] Token deposits will fail without a price feed.");
            console2.log("[WARNING] Set PRICE_FEED_ADDRESS env var and run again to set price feed.");
            console2.log("");
        }

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        bool newStatus = tokensManager.allowedTokens(tokenAddress);
        address newPriceFeed = tokensManager.getPriceFeed(tokenAddress);
        (, uint8 newDecimals) = tokensManager.getDecimal(tokenAddress);

        console2.log("Token Configuration:");
        console2.log("  Allowed:", newStatus ? "[OK]" : "[NOT ALLOWED]");
        console2.log("  Decimals:", newDecimals, newDecimals == tokenDecimals ? "[OK]" : "[MISMATCH]");
        console2.log("  Price Feed:", newPriceFeed, newPriceFeed != address(0) ? "[OK]" : "[NOT SET]");
        console2.log("");

        if (isAllowed && newPriceFeed == address(0)) {
            console2.log("[WARNING] Price feed is not set. Vault deposits will fail!");
            console2.log("[WARNING] Run again with PRICE_FEED_ADDRESS env var to set it.");
            console2.log("");
        }

        console2.log("=== Allow List Token Complete ===");
    }
}
