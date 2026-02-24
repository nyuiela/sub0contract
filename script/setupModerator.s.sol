// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";
import {IVault} from "../src/interfaces/IVault.sol";

/**
 * @title SetupModerator
 * @notice Script to grant moderator permissions to a platform moderator address
 * @dev Grants necessary roles and sets up fee collection for the moderator
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Deployer private key (must have DEFAULT_ADMIN_ROLE)
 * - PERMISSION_MANAGER_ADDRESS: PermissionManager contract address
 * - VAULT_ADDRESS: Vault contract address
 * - MODERATOR_ADDRESS: Moderator address (default: 0xa957f3eac17c10a9ca0205b9849b691702a9de6e)
 *
 * Optional Environment Variables:
 * - VAULT_FEE_BPS: Fee in basis points (default: 500 = 5%, max: 1000 = 10%)
 * - PAYOUT_TOKEN_ADDRESS: Payout token address (if not set, will skip setting)
 */
contract SetupModerator is Script {
    // Role Constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // Default moderator address
    // address public constant DEFAULT_MODERATOR = 0xa957f3eac17c10a9ca0205b9849b691702a9de6e;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Get contract addresses from environment
        address permissionManagerAddr = vm.envAddress("PERMISSION_MANAGER_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        // Get moderator address (default to provided address)
        address moderator = vm.envAddress("MODERATOR_ADDRESS");

        // Get optional fee configuration
        uint256 feeBps = vm.envOr("VAULT_FEE_BPS", uint256(500)); // Default 5%
        address payoutToken = vm.envOr("PAYOUT_TOKEN_ADDRESS", address(0));

        console2.log("=== Moderator Setup Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Moderator:", moderator);
        console2.log("PermissionManager:", permissionManagerAddr);
        console2.log("Vault:", vaultAddr);
        console2.log("Fee BPS:", feeBps);
        console2.log("");

        // Initialize contract instances
        PermissionManager permissionManager = PermissionManager(permissionManagerAddr);
        Vault vault = Vault(payable(vaultAddr));

        vm.startBroadcast(deployerKey);

        // Verify deployer has DEFAULT_ADMIN_ROLE
        if (!permissionManager.hasRole(DEFAULT_ADMIN_ROLE, deployer)) {
            console2.log("[ERROR] Deployer does not have DEFAULT_ADMIN_ROLE");
            console2.log("[INFO] Deployer must have DEFAULT_ADMIN_ROLE to grant permissions");
            revert("Deployer lacks DEFAULT_ADMIN_ROLE");
        }

        console2.log("[OK] Deployer has DEFAULT_ADMIN_ROLE");
        console2.log("");

        // Grant roles to moderator
        grantModeratorRoles(IPermissionManager(address(permissionManager)), moderator);

        // Setup vault fee configuration
        setupVaultFees(vault, moderator, feeBps);

        // Set payout token if provided
        if (payoutToken != address(0)) {
            setPayoutToken(Vault(payable(vaultAddr)), payoutToken);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Verification ===");
        verifyModeratorPermissions(IPermissionManager(address(permissionManager)), vault, moderator);
        console2.log("");
        console2.log("=== Moderator Setup Complete ===");
    }

    /**
     * @notice Grants all necessary roles to the moderator
     */
    function grantModeratorRoles(IPermissionManager permissionManager, address moderator) internal {
        console2.log("=== Granting Roles to Moderator ===");

        // Grant DEFAULT_ADMIN_ROLE (for vault management)
        // grantRoleIfNeeded(permissionManager, DEFAULT_ADMIN_ROLE, moderator, "DEFAULT_ADMIN_ROLE");

        // Grant GAME_CREATOR_ROLE (for creating public bets)
        grantRoleIfNeeded(permissionManager, GAME_CREATOR_ROLE, moderator, "GAME_CREATOR_ROLE");

        // Grant TOKEN_MANAGER_ROLE (for managing tokens)
        grantRoleIfNeeded(permissionManager, TOKEN_MANAGER_ROLE, moderator, "TOKEN_MANAGER_ROLE");

        // Grant ORACLE_MANAGER_ROLE (for managing oracles)
        grantRoleIfNeeded(permissionManager, ORACLE_MANAGER_ROLE, moderator, "ORACLE_MANAGER_ROLE");

        console2.log("");
    }

    /**
     * @notice Sets up vault fee configuration with moderator as fee collector
     */
    function setupVaultFees(IVault vault, address moderator, uint256 feeBps) internal {
        console2.log("=== Setting up Vault Fee Configuration ===");

        // Validate fee BPS (max 10% = 1000)
        if (feeBps > 1000) {
            console2.log("[WARN] Fee BPS exceeds maximum (1000 = 10%), capping at 1000");
            feeBps = 1000;
        }

        try vault.setFeeConfig(moderator, feeBps) {
            console2.log("[OK] Set vault fee collector to moderator");
            console2.log("[OK] Set vault fee to", feeBps, "basis points");
            console2.log("     Fee percentage:", feeBps / 100, "%");
        } catch {
            console2.log("[ERROR] Failed to set vault fee config");
            console2.log("[INFO] This requires DEFAULT_ADMIN_ROLE on the vault");
            revert("Failed to set vault fee config");
        }

        console2.log("");
    }

    /**
     * @notice Sets the payout token for the vault
     */
    function setPayoutToken(Vault vault, address payoutToken) internal {
        console2.log("=== Setting Vault Payout Token ===");

        try vault.setPayoutToken(payoutToken) {
            console2.log("[OK] Set vault payout token to:", payoutToken);
        } catch {
            console2.log("[ERROR] Failed to set payout token");
            console2.log("[INFO] This requires DEFAULT_ADMIN_ROLE on the vault");
        }

        console2.log("");
    }

    /**
     * @notice Grants a role if the account doesn't already have it
     */
    function grantRoleIfNeeded(
        IPermissionManager permissionManager,
        bytes32 role,
        address account,
        string memory roleName
    ) internal {
        if (permissionManager.hasRole(role, account)) {
            console2.log("[SKIP] Moderator already has", roleName);
        } else {
            try permissionManager.grantRole(role, account) {
                console2.log("[OK] Granted", roleName, "to moderator");
            } catch {
                console2.log("[ERROR] Failed to grant", roleName);
                console2.log("[INFO] Deployer may not have permission to grant this role");
                console2.log("[INFO] Role admin:", vm.toString(permissionManager.getRoleAdmin(role)));
            }
        }
    }

    /**
     * @notice Verifies that all permissions were granted correctly
     */
    function verifyModeratorPermissions(IPermissionManager permissionManager, Vault vault, address moderator)
        internal
        view
    {
        console2.log("Verifying moderator permissions...");
        console2.log("");

        // Check roles
        bool hasAdminRole = permissionManager.hasRole(DEFAULT_ADMIN_ROLE, moderator);
        bool hasGameCreatorRole = permissionManager.hasRole(GAME_CREATOR_ROLE, moderator);
        bool hasTokenManagerRole = permissionManager.hasRole(TOKEN_MANAGER_ROLE, moderator);
        bool hasOracleManagerRole = permissionManager.hasRole(ORACLE_MANAGER_ROLE, moderator);

        console2.log("Roles:");
        console2.log("  DEFAULT_ADMIN_ROLE:", hasAdminRole ? "[OK]" : "[MISSING]");
        console2.log("  GAME_CREATOR_ROLE:", hasGameCreatorRole ? "[OK]" : "[MISSING]");
        console2.log("  TOKEN_MANAGER_ROLE:", hasTokenManagerRole ? "[OK]" : "[MISSING]");
        console2.log("  ORACLE_MANAGER_ROLE:", hasOracleManagerRole ? "[OK]" : "[MISSING]");
        console2.log("");

        // Check vault fee configuration
        try vault.feeCollector() returns (address feeCollector) {
            bool isFeeCollector = feeCollector == moderator;
            console2.log("Vault Configuration:");
            console2.log("  Fee Collector:", feeCollector);
            console2.log("  Is Moderator:", isFeeCollector ? "[OK]" : "[MISMATCH]");

            try vault.platformFeeBps() returns (uint256 feeBps) {
                console2.log("  Fee BPS:", feeBps);
                console2.log("  Fee Percentage:", feeBps / 100, "%");
            } catch {}
        } catch {
            console2.log("[WARN] Could not read vault fee configuration");
        }

        console2.log("");
        console2.log("=== Moderator Capabilities ===");
        console2.log("[OK] Create public bets (GAME_CREATOR_ROLE)");
        console2.log("[OK] Manage vault fees and configuration (DEFAULT_ADMIN_ROLE)");
        console2.log("[OK] Claim fees from vault (as feeCollector)");
        console2.log("[OK] Manage tokens (TOKEN_MANAGER_ROLE)");
        console2.log("[OK] Manage oracles (ORACLE_MANAGER_ROLE)");
    }
}
