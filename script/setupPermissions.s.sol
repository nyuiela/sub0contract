// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";

/**
 * @title SetupPermissions
 * @notice Comprehensive permission setup script for the Sub0 prediction market platform
 * @dev Categorizes and grants all necessary permissions to different actors in the system
 *
 * ACTOR CATEGORIES:
 * 1. SUPER_ADMIN - Overall system administrator (manages all permissions)
 * 2. TOKEN_MANAGER - Manages token allowlisting, decimals, and price feeds
 * 3. ORACLE_MANAGER - Manages oracle contracts and reporters
 * 4. GAME_CREATOR - Creates and initializes new games
 * 5. GAME_CONTRACT - Game contract instances (e.g., Sub0)
 * 6. ESCROW_MANAGER - Manages escrow operations (shutdown, open, sweep)
 * 7. ORACLE_REPORTER - Reports bet results to the Oracle contract
 * 8. USER - Regular users (no special permissions needed)
 */
contract SetupPermissions is Script {
    // Role Constants
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");
    bytes32 public constant ORACLE = keccak256("ORACLE");

    // Contract addresses (set via environment or constructor)
    PermissionManager public permissionManager;
    Oracle public oracle;
    Hub public hub;
    Vault public vault;
    TokensManager public tokensManager;

    // Actor addresses
    address public superAdmin;
    address public tokenManager;
    address public oracleManager;
    address public gameCreator;
    address public escrowManager;
    address public oracleReporter;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Get contract addresses from environment
        address permissionManagerAddr = vm.envAddress("PERMISSION_MANAGER_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");
        address hubAddr = vm.envAddress("HUB_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address tokensManagerAddr = vm.envAddress("TOKENS_MANAGER_ADDRESS");
        vm.envAddress("ESCROW_ADDRESS");

        // Get actor addresses from environment (with deployer as default)
        superAdmin = vm.envOr("SUPER_ADMIN_ADDRESS", deployer);
        tokenManager = vm.envOr("TOKEN_MANAGER_ADDRESS", deployer);
        oracleManager = vm.envOr("ORACLE_MANAGER_ADDRESS", deployer);
        gameCreator = vm.envOr("GAME_CREATOR_ADDRESS", deployer);
        escrowManager = vm.envOr("ESCROW_MANAGER_ADDRESS", deployer);
        oracleReporter = vm.envOr("ORACLE_REPORTER_ADDRESS", deployer);

        // Initialize contract instances
        permissionManager = PermissionManager(permissionManagerAddr);
        oracle = Oracle(payable(oracleAddr));
        hub = Hub(payable(hubAddr));
        vault = Vault(payable(vaultAddr));
        tokensManager = TokensManager(tokensManagerAddr);

        console2.log("=== Permission Setup Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Super Admin:", superAdmin);
        console2.log("");

        vm.startBroadcast(deployerKey);

        // Setup all permissions
        setupSuperAdminPermissions();
        setupTokenManagerPermissions();
        setupOracleManagerPermissions();
        setupGameCreatorPermissions();
        setupOracleReporterPermissions();

        vm.stopBroadcast();

        console2.log("\n=== Permission Setup Complete ===");
        verifyPermissions();
    }

    /**
     * @notice Setup permissions for SUPER_ADMIN
     * @dev Super admin has DEFAULT_ADMIN_ROLE and can manage all other roles
     */
    function setupSuperAdminPermissions() internal {
        console2.log("--- Setting up SUPER_ADMIN permissions ---");

        // Grant DEFAULT_ADMIN_ROLE to super admin (if not already granted)
        if (!permissionManager.hasRole(DEFAULT_ADMIN_ROLE, superAdmin)) {
            permissionManager.grantRole(DEFAULT_ADMIN_ROLE, superAdmin);
            console2.log("  [OK] Granted DEFAULT_ADMIN_ROLE to super admin");
        } else {
            console2.log("  [OK] Super admin already has DEFAULT_ADMIN_ROLE");
        }

        // Super admin also needs other roles for direct management
        grantRoleIfNeeded(TOKEN_MANAGER_ROLE, superAdmin, "TOKEN_MANAGER_ROLE");
        grantRoleIfNeeded(ORACLE_MANAGER_ROLE, superAdmin, "ORACLE_MANAGER_ROLE");
        grantRoleIfNeeded(GAME_CREATOR_ROLE, superAdmin, "GAME_CREATOR_ROLE");
        grantRoleIfNeeded(ESCROW_MANAGER_ROLE, superAdmin, "ESCROW_MANAGER_ROLE");
    }

    /**
     * @notice Setup permissions for TOKEN_MANAGER
     * @dev Token manager can allowlist tokens, set decimals, and configure price feeds
     */
    function setupTokenManagerPermissions() internal {
        console2.log("--- Setting up TOKEN_MANAGER permissions ---");

        // Grant TOKEN_MANAGER_ROLE
        grantRoleIfNeeded(TOKEN_MANAGER_ROLE, tokenManager, "TOKEN_MANAGER_ROLE");
        grantRoleIfNeeded(TOKEN_MANAGER_ROLE, address(tokensManager), "TOKEN_MANAGER_ROLE (to TokensManager contract)");

        console2.log("  Token Manager can:");
        console2.log("    - Allowlist/ban tokens");
        console2.log("    - Set token decimals");
        console2.log("    - Configure price feeds");
    }

    /**
     * @notice Setup permissions for ORACLE_MANAGER
     * @dev Oracle manager can manage oracle contracts and allowlist reporters
     */
    function setupOracleManagerPermissions() internal {
        console2.log("--- Setting up ORACLE_MANAGER permissions ---");

        // Grant ORACLE_MANAGER_ROLE
        grantRoleIfNeeded(ORACLE_MANAGER_ROLE, oracleManager, "ORACLE_MANAGER_ROLE");
        grantRoleIfNeeded(ORACLE_MANAGER_ROLE, address(oracle), "ORACLE_MANAGER_ROLE (to Oracle contract)");

        // Allowlist oracle manager as reporter in Oracle contract
        try oracle.allowListReporter(oracleManager, true) {
            console2.log("  [OK] Allowlisted oracle manager as reporter");
        } catch {
            console2.log("  [WARN] Could not allowlist oracle manager (may need ORACLE_MANAGER_ROLE first)");
        }

        console2.log("  Oracle Manager can:");
        console2.log("    - Allowlist/remove oracle reporters");
        console2.log("    - Manage oracle configurations");
    }

    /**
     * @notice Setup permissions for GAME_CREATOR
     * @dev Game creator can create and initialize new games
     */
    function setupGameCreatorPermissions() internal {
        console2.log("--- Setting up GAME_CREATOR permissions ---");

        // Grant GAME_CREATOR_ROLE
        grantRoleIfNeeded(GAME_CREATOR_ROLE, gameCreator, "GAME_CREATOR_ROLE");

        console2.log("  Game Creator can:");
        console2.log("    - Create new games via Hub");
        console2.log("    - Initialize game contracts");
    }

    /**
     * @notice Setup permissions for GAME_CONTRACT
     * @dev Game contracts need GAME_CONTRACT_ROLE
     * @param gameContract Address of the game contract (e.g., OneVsOne)
     * @param gameId Optional game ID for game-specific role
     */
    function setupGameContractPermissions(address gameContract, bytes32 gameId) internal {
        console2.log("--- Setting up GAME_CONTRACT permissions ---");
        console2.log("Game Contract:", gameContract);

        // Grant base GAME_CONTRACT_ROLE
        grantRoleIfNeeded(GAME_CONTRACT_ROLE, gameContract, "GAME_CONTRACT_ROLE");

        // Grant game-specific GAME_CONTRACT_ROLE if gameId provided
        if (gameId != bytes32(0)) {
            bytes32 gameContractRole = keccak256(abi.encodePacked(GAME_CONTRACT_ROLE, gameId));
            grantRoleIfNeeded(gameContractRole, gameContract, "GAME_CONTRACT_ROLE (game-specific)");
        }

        // GAME_CONTRACT_ROLE already granted above (allows calling vault deposit/withdraw)

        console2.log("  Game Contract can:");
        console2.log("    - Create bet escrows");
        console2.log("    - Deposit/withdraw from vault");
        console2.log("    - Resolve bets");
    }

    /**
     * @notice Setup permissions for ORACLE_REPORTER
     * @dev Oracle reporters can fulfill and fail bet results
     */
    function setupOracleReporterPermissions() internal {
        console2.log("--- Setting up ORACLE_REPORTER permissions ---");

        // Allowlist reporter in Oracle contract
        try oracle.allowListReporter(oracleReporter, true) {
            console2.log("  [OK] Allowlisted oracle reporter");
        } catch {
            console2.log("  [WARN] Could not allowlist oracle reporter (may need ORACLE_MANAGER_ROLE first)");
        }

        console2.log("  Oracle Reporter can:");
        console2.log("    - Fulfill bet results");
        console2.log("    - Fail bet requests");
    }

    /**
     * @notice Grant a role to an address if not already granted
     */
    function grantRoleIfNeeded(bytes32 role, address account, string memory roleName) internal {
        if (!permissionManager.hasRole(role, account)) {
            permissionManager.grantRole(role, account);
            console2.log("  [OK] Granted", roleName, "to", account);
        } else {
            console2.log("  [OK]", roleName, "already granted to", account);
        }
    }

    /**
     * @notice Verify all permissions are correctly set
     */
    function verifyPermissions() internal view {
        console2.log("\n=== Permission Verification ===");

        // Verify Super Admin
        require(permissionManager.hasRole(DEFAULT_ADMIN_ROLE, superAdmin), "Super admin missing DEFAULT_ADMIN_ROLE");
        console2.log("[OK] Super Admin has DEFAULT_ADMIN_ROLE");

        // Verify Token Manager
        if (tokenManager != address(0)) {
            require(
                permissionManager.hasRole(TOKEN_MANAGER_ROLE, tokenManager), "Token manager missing TOKEN_MANAGER_ROLE"
            );
            console2.log("[OK] Token Manager has TOKEN_MANAGER_ROLE");
        }

        // Verify Oracle Manager
        if (oracleManager != address(0)) {
            require(
                permissionManager.hasRole(ORACLE_MANAGER_ROLE, oracleManager),
                "Oracle manager missing ORACLE_MANAGER_ROLE"
            );
            console2.log("[OK] Oracle Manager has ORACLE_MANAGER_ROLE");
        }

        // Verify Game Creator
        if (gameCreator != address(0)) {
            require(permissionManager.hasRole(GAME_CREATOR_ROLE, gameCreator), "Game creator missing GAME_CREATOR_ROLE");
            console2.log("[OK] Game Creator has GAME_CREATOR_ROLE");
        }

        // Verify Oracle Reporter
        if (oracleReporter != address(0)) {
            bool isAllowed = oracle.isAllowed(oracleReporter);
            require(isAllowed, "Oracle reporter not allowlisted");
            console2.log("[OK] Oracle Reporter is allowlisted");
        }

        console2.log("\nAll permissions verified successfully!");
    }

    /**
     * @notice Setup permissions for a specific game contract
     * @dev Call this after deploying a new game contract
     * @param gameContract Address of the game contract
     * @param gameId Game ID from Hub
     */
    function setupNewGameContract(address gameContract, bytes32 gameId) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Get contract addresses from environment
        address permissionManagerAddr = vm.envAddress("PERMISSION_MANAGER_ADDRESS");
        vm.envAddress("ESCROW_ADDRESS");

        // Initialize contract instances
        permissionManager = PermissionManager(permissionManagerAddr);

        vm.startBroadcast(deployerKey);

        setupGameContractPermissions(gameContract, gameId);

        vm.stopBroadcast();

        console2.log("\n=== Game Contract Permission Setup Complete ===");
    }
}
