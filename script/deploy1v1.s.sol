// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MeVsYouParimutuel} from "../src/gamehub/MeVsYouParimutuel.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {ParimutuelConditionalTokens} from "../src/conditional/ParimutuelConditionalTokens.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";

/**
 * @title DeployMeVsYouParimutuel
 * @notice Deployment script for MeVsYou Parimutuel (winner-gets-share-of-total-volume).
 * @dev Deploys ParimutuelConditionalTokens + MeVsYouParimutuel as default stack.
 *
 * Environment Variables:
 * - PRIVATE_KEY: Deployer private key (required)
 * - PERMISSION_MANAGER_ADDRESS: Existing PermissionManager (optional)
 * - TOKENS_MANAGER_ADDRESS: Existing TokensManager (optional)
 * - PARIMUTUEL_ADDRESS: Existing ParimutuelConditionalTokens proxy (optional)
 * - HUB_ADDRESS: Existing Hub (optional)
 * - ORACLE_ADDRESS: Existing Oracle (optional)
 * - COLLATERAL_TOKEN_ADDRESS: Existing collateral token (optional, deploys TestERC20 if not set)
 */
contract DeployMeVsYou is Script {
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("=== MeVsYou Parimutuel Deployment Script ===");
        console2.log("Deployer:", deployer);
        console2.log("");

        vm.startBroadcast(deployerKey);

        (PermissionManager permissionManager, address permissionManagerAddress) = getOrDeployPermissionManager(deployer);
        (ParimutuelConditionalTokens parimutuel, address parimutuelAddress) =
            getOrDeployParimutuel(IPermissionManager(permissionManagerAddress));
        (TokensManager tokensManager, address tokensManagerAddress) =
            getOrDeployTokensManager(permissionManager, parimutuelAddress);
        (, address oracleAddress) = getOrDeployOracle(permissionManager, deployer);
        (Hub hub, address hubAddress) = getOrDeployHub(permissionManager, tokensManagerAddress, oracleAddress);
        address collateralTokenAddress = getOrDeployCollateralToken();

        mintInitialTokens(collateralTokenAddress, deployer);

        MeVsYouParimutuel gameImpl = new MeVsYouParimutuel();
        console2.log("MeVsYouParimutuel implementation deployed at:", address(gameImpl));

        MeVsYouParimutuel.Config memory gameConfig = MeVsYouParimutuel.Config({
            hub: hubAddress,
            tokenManager: tokensManagerAddress,
            permissionManager: permissionManagerAddress,
            parimutuelToken: parimutuelAddress
        });

        bytes memory gameInitData = abi.encodeWithSelector(MeVsYouParimutuel.initialize.selector, gameConfig);
        ERC1967Proxy gameProxy = new ERC1967Proxy(address(gameImpl), gameInitData);
        MeVsYouParimutuel game = MeVsYouParimutuel(payable(address(gameProxy)));
        console2.log("MeVsYouParimutuel proxy deployed at:", address(game));
        console2.log("");

        setupPermissions(
            permissionManager, hub, parimutuel, tokensManager, address(game), deployer, collateralTokenAddress
        );

        IPermissionManager pm = IPermissionManager(permissionManagerAddress);
        pm.grantRole(GAME_CREATOR_ROLE, deployer);
        hub.initializeGame("MeVsYou Parimutuel", address(game));
        console2.log("Game registered in Hub");

        hub.activateGame(address(game));
        console2.log("[OK] Game activated");
        console2.log("[OK] GAME_CONTRACT_ROLE granted to MeVsYouParimutuel via PermissionManager");
        console2.log("");

        bytes32 gameId = hub.getGameId(address(game));
        console2.log("Game ID:", vm.toString(gameId));
        console2.log("");

        vm.stopBroadcast();

        printDeploymentSummary(
            address(game),
            address(gameImpl),
            hubAddress,
            tokensManagerAddress,
            parimutuelAddress,
            oracleAddress,
            collateralTokenAddress
        );
    }

    function getOrDeployPermissionManager(address deployer) internal returns (PermissionManager, address) {
        if (vm.envExists("PERMISSION_MANAGER_ADDRESS")) {
            address addr = vm.envAddress("PERMISSION_MANAGER_ADDRESS");
            console2.log("Using existing PermissionManager at:", addr);
            return (PermissionManager(addr), addr);
        }

        console2.log("Deploying PermissionManager...");
        PermissionManager pm = new PermissionManager();
        pm.initialize();
        pm.grantRole(DEFAULT_ADMIN_ROLE, deployer);
        console2.log("PermissionManager deployed at:", address(pm));
        return (pm, address(pm));
    }

    function getOrDeployParimutuel(IPermissionManager permissionManager)
        internal
        returns (ParimutuelConditionalTokens, address)
    {
        if (vm.envExists("PARIMUTUEL_ADDRESS")) {
            address addr = vm.envAddress("PARIMUTUEL_ADDRESS");
            console2.log("Using existing ParimutuelConditionalTokens at:", addr);
            return (ParimutuelConditionalTokens(addr), addr);
        }

        console2.log("Deploying ParimutuelConditionalTokens...");
        ParimutuelConditionalTokens impl = new ParimutuelConditionalTokens();
        bytes memory initData =
            abi.encodeWithSelector(ParimutuelConditionalTokens.initialize.selector, permissionManager);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ParimutuelConditionalTokens parimutuel = ParimutuelConditionalTokens(address(proxy));
        console2.log("ParimutuelConditionalTokens implementation:", address(impl));
        console2.log("ParimutuelConditionalTokens proxy:", address(parimutuel));
        return (parimutuel, address(parimutuel));
    }

    function getOrDeployTokensManager(PermissionManager permissionManager, address parimutuelAddress)
        internal
        returns (TokensManager, address)
    {
        if (vm.envExists("TOKENS_MANAGER_ADDRESS")) {
            address addr = vm.envAddress("TOKENS_MANAGER_ADDRESS");
            console2.log("Using existing TokensManager at:", addr);
            return (TokensManager(addr), addr);
        }

        console2.log("Deploying TokensManager...");
        TokensManager tm = new TokensManager();
        tm.initialize(address(permissionManager), parimutuelAddress);
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(tm));
        console2.log("TokensManager deployed at:", address(tm));
        return (tm, address(tm));
    }

    function getOrDeployOracle(PermissionManager permissionManager, address deployer)
        internal
        returns (Oracle, address)
    {
        if (vm.envExists("ORACLE_ADDRESS")) {
            address addr = vm.envAddress("ORACLE_ADDRESS");
            console2.log("Using existing Oracle at:", addr);
            return (Oracle(addr), addr);
        }

        console2.log("Deploying Oracle...");
        Oracle oracle = new Oracle();
        oracle.initialize(address(permissionManager), deployer);
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(oracle));
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, deployer);
        oracle.allowListReporter(deployer, true);
        console2.log("Oracle deployed at:", address(oracle));
        console2.log("  [OK] Allowlisted deployer as oracle reporter");
        return (oracle, address(oracle));
    }

    function getOrDeployHub(PermissionManager permissionManager, address tokensManagerAddress, address oracleAddress)
        internal
        returns (Hub, address)
    {
        if (vm.envExists("HUB_ADDRESS")) {
            address addr = vm.envAddress("HUB_ADDRESS");
            console2.log("Using existing Hub at:", addr);
            return (Hub(addr), addr);
        }

        console2.log("Deploying Hub...");
        Hub hub = new Hub();
        hub.initialize(address(permissionManager), tokensManagerAddress, oracleAddress);
        console2.log("Hub deployed at:", address(hub));
        return (hub, address(hub));
    }

    function getOrDeployCollateralToken() internal returns (address) {
        if (vm.envExists("COLLATERAL_TOKEN_ADDRESS")) {
            address addr = vm.envAddress("COLLATERAL_TOKEN_ADDRESS");
            console2.log("Using existing CollateralToken at:", addr);
            return addr;
        }

        console2.log("Deploying TestERC20 as CollateralToken...");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        TestERC20 token = new TestERC20("Test Collateral Token", "TCT", 18, deployer);
        console2.log("TestERC20 deployed at:", address(token));
        return address(token);
    }

    function mintInitialTokens(address tokenAddress, address deployer) internal {
        if (!vm.envExists("COLLATERAL_TOKEN_ADDRESS") && tokenAddress != address(0)) {
            TestERC20 token = TestERC20(tokenAddress);
            uint256 initialAmount = 1000000 * 10 ** 18;
            token.mint(deployer, initialAmount);
            console2.log("  [OK] Minted", initialAmount / 10 ** 18, "tokens to deployer");
        }
    }

    function setupPermissions(
        PermissionManager permissionManager,
        Hub hub,
        ParimutuelConditionalTokens parimutuel,
        TokensManager tokensManager,
        address gameContract,
        address deployer,
        address collateralToken
    ) internal {
        console2.log("=== Setting up Permissions ===");

        IPermissionManager pm = IPermissionManager(address(permissionManager));

        permissionManager.setRoleAdmin(GAME_CONTRACT_ROLE, GAME_CREATOR_ROLE);
        console2.log("[OK] Set GAME_CONTRACT_ROLE admin to GAME_CREATOR_ROLE");

        grantRoleIfNeeded(pm, TOKEN_MANAGER_ROLE, deployer, "TOKEN_MANAGER_ROLE");
        grantRoleIfNeeded(pm, ORACLE_MANAGER_ROLE, deployer, "ORACLE_MANAGER_ROLE");
        grantRoleIfNeeded(pm, GAME_CREATOR_ROLE, deployer, "GAME_CREATOR_ROLE");
        grantRoleIfNeeded(pm, TOKEN_MANAGER_ROLE, address(tokensManager), "TOKEN_MANAGER_ROLE (to TokensManager)");
        grantRoleIfNeeded(pm, GAME_CREATOR_ROLE, address(hub), "GAME_CREATOR_ROLE (to Hub)");

        grantRoleIfNeeded(pm, parimutuel.PARIMUTUEL_ADMIN_ROLE(), deployer, "PARIMUTUEL_ADMIN_ROLE");
        grantRoleIfNeeded(
            pm, parimutuel.GAME_CONTRACT_ROLE(), gameContract, "GAME_CONTRACT_ROLE (to MeVsYouParimutuel)"
        );

        parimutuel.setPayoutToken(collateralToken);
        console2.log("[OK] Set parimutuel payout token");
        parimutuel.setFeeConfig(deployer, 500);
        console2.log("[OK] Set parimutuel fee config (5%)");

        if (collateralToken != address(0)) {
            tokensManager.allowListToken(collateralToken, true);
            tokensManager.setDecimals(collateralToken, 18);
            console2.log("[OK] Allowlisted collateral token and set decimals");
        }

        console2.log("");
        verifyPermissions(pm, hub, deployer);
    }

    function grantRoleIfNeeded(
        IPermissionManager permissionManager,
        bytes32 role,
        address account,
        string memory roleName
    ) internal {
        if (!permissionManager.hasRole(role, account)) {
            permissionManager.grantRole(role, account);
            console2.log("[OK] Granted", roleName, "to", account);
        } else {
            console2.log("[OK]", roleName, "already granted to", account);
        }
    }

    function verifyPermissions(IPermissionManager permissionManager, Hub hub, address deployer) internal view {
        console2.log("=== Permission Verification ===");
        require(permissionManager.hasRole(DEFAULT_ADMIN_ROLE, deployer), "Deployer missing DEFAULT_ADMIN_ROLE");
        console2.log("[OK] Deployer has DEFAULT_ADMIN_ROLE");
        require(permissionManager.hasRole(GAME_CREATOR_ROLE, deployer), "Deployer missing GAME_CREATOR_ROLE");
        console2.log("[OK] Deployer has GAME_CREATOR_ROLE");
        require(permissionManager.hasRole(TOKEN_MANAGER_ROLE, deployer), "Deployer missing TOKEN_MANAGER_ROLE");
        console2.log("[OK] Deployer has TOKEN_MANAGER_ROLE");
        require(permissionManager.hasRole(ORACLE_MANAGER_ROLE, deployer), "Deployer missing ORACLE_MANAGER_ROLE");
        console2.log("[OK] Deployer has ORACLE_MANAGER_ROLE");
        require(permissionManager.hasRole(GAME_CREATOR_ROLE, address(hub)), "Hub missing GAME_CREATOR_ROLE");
        console2.log("[OK] Hub has GAME_CREATOR_ROLE");
        address oracleAddress = hub.getOracleManager();
        if (oracleAddress != address(0)) {
            bool isAllowed = Oracle(payable(oracleAddress)).isAllowed(deployer);
            if (isAllowed) {
                console2.log("[OK] Deployer is allowlisted as oracle reporter");
            } else {
                console2.log("[WARN] Deployer not yet allowlisted as oracle reporter");
            }
        }
        console2.log("[OK] All permissions verified successfully");
        console2.log("");
    }

    function printDeploymentSummary(
        address gameProxy,
        address gameImpl,
        address hub,
        address tokensManager,
        address parimutuel,
        address oracle,
        address collateralToken
    ) internal pure {
        console2.log("=== Deployment Summary ===");
        console2.log("MeVsYouParimutuel (proxy):", gameProxy);
        console2.log("MeVsYouParimutuel (implementation):", gameImpl);
        console2.log("Hub:", hub);
        console2.log("TokensManager:", tokensManager);
        console2.log("ParimutuelConditionalTokens (proxy):", parimutuel);
        console2.log("Oracle:", oracle);
        console2.log("CollateralToken:", collateralToken);
        console2.log("==========================");
    }
}
