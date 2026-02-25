// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {PredictionVault} from "../src/gamehub/PredictionVault.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";

/**
 * @title DeploySub0
 * @notice Deployment script for Sub0 prediction market (ConditionalTokensV2 + PredictionVault + Sub0 factory).
 *
 * Environment Variables:
 * - PRIVATE_KEY: Deployer private key (required)
 * - USDC_ADDRESS: USDC for PredictionVault (optional; deploys TestERC20 if not set)
 * - DON_SIGNER_ADDRESS: DON signer for CRE quote signatures (used for PredictionVault; fallback: BACKEND_SIGNER_ADDRESS, then deployer)
 * - BACKEND_SIGNER_ADDRESS: Legacy fallback if DON_SIGNER_ADDRESS not set
 * - CRE_FORWARDER_ADDRESS: Chainlink CRE forwarder allowed to call onReport (optional; default: address(0))
 */
contract DeploySub0 is Script {
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address donSigner = vm.envOr("DON_SIGNER_ADDRESS", vm.envOr("BACKEND_SIGNER_ADDRESS", deployer));
        address creForwarder = vm.envOr("CRE_FORWARDER_ADDRESS", address(0));

        console2.log("=== Sub0 Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("DON signer (CRE quotes):", donSigner);
        console2.log("");

        vm.startBroadcast(deployerKey);

        PermissionManager permissionManager = new PermissionManager();
        permissionManager.initialize();
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, deployer);
        console2.log("PermissionManager:", address(permissionManager));

        ConditionalTokensV2 ctf = new ConditionalTokensV2();
        console2.log("ConditionalTokensV2:", address(ctf));

        TokensManager tokensManager = new TokensManager();
        tokensManager.initialize(address(permissionManager), address(ctf));
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(tokensManager));
        console2.log("TokensManager:", address(tokensManager));

        Oracle oracle = new Oracle();
        oracle.initialize(address(permissionManager), deployer);
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(oracle));
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, deployer);
        console2.log("Oracle:", address(oracle));

        Hub hub = new Hub();
        hub.initialize(address(permissionManager), address(tokensManager), address(oracle));
        console2.log("Hub:", address(hub));

        Vault vault = new Vault();
        vault.initialize(
            IVault.Config({tokenManager: address(tokensManager), permissionManager: address(permissionManager)})
        );
        vault.setConditionalTokens(address(ctf));
        console2.log("Vault (VaultV2):", address(vault));

        address usdcAddress = getOrDeployUsdc(deployer);

        PredictionVault predictionVault = new PredictionVault(usdcAddress, address(ctf), donSigner, creForwarder);
        console2.log("PredictionVault:", address(predictionVault));

        Sub0 sub0Impl = new Sub0();
        Sub0.Config memory sub0Config = Sub0.Config({
            hub: address(hub),
            vault: address(vault),
            tokenManager: address(tokensManager),
            permissionManager: address(permissionManager),
            conditionalToken: address(ctf),
            predictionVault: address(predictionVault),
            creForwarder: creForwarder
        });
        bytes memory sub0InitData = abi.encodeWithSelector(Sub0.initialize.selector, sub0Config);
        ERC1967Proxy sub0Proxy = new ERC1967Proxy(address(sub0Impl), sub0InitData);
        Sub0 sub0 = Sub0(payable(address(sub0Proxy)));
        console2.log("Sub0 (implementation):", address(sub0Impl));
        console2.log("Sub0 (proxy):", address(sub0));

        permissionManager.setRoleAdmin(GAME_CONTRACT_ROLE, GAME_CREATOR_ROLE);
        permissionManager.grantRole(GAME_CREATOR_ROLE, deployer);
        permissionManager.grantRole(GAME_CREATOR_ROLE, address(hub));
        permissionManager.grantRole(GAME_CONTRACT_ROLE, address(sub0));
        ctf.grantRole(ctf.GAME_CONTRACT_ROLE(), address(sub0));

        predictionVault.transferOwnership(address(sub0));
        console2.log("PredictionVault owner set to Sub0 proxy");

        hub.initializeGame("Sub0", address(sub0));
        hub.activateGame(address(sub0));
        console2.log("Sub0 registered and activated in Hub");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Summary ===");
        console2.log("Sub0 (proxy):", address(sub0));
        console2.log("PredictionVault:", address(predictionVault));
        console2.log("ConditionalTokensV2:", address(ctf));
        console2.log("Vault:", address(vault));
        console2.log("Hub:", address(hub));
        console2.log("USDC/collateral:", usdcAddress);
    }

    function getOrDeployUsdc(address deployer) internal returns (address) {
        if (vm.envExists("USDC_ADDRESS")) {
            address addr = vm.envAddress("USDC_ADDRESS");
            console2.log("Using USDC at:", addr);
            return addr;
        }
        TestERC20 mockUsdc = new TestERC20("USD Coin", "USDC", 6, deployer);
        mockUsdc.mint(deployer, 1_000_000 * 10 ** 6);
        console2.log("Deployed TestERC20 as USDC:", address(mockUsdc));
        return address(mockUsdc);
    }
}
