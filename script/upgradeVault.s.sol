// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Vault} from "../src/manager/vault.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";

/**
 * @title UpgradeVault
 * @notice Script to upgrade the Vault contract to a new implementation
 * @dev Deploys new implementation and calls upgradeToAndCall on the proxy
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account with DEFAULT_ADMIN_ROLE (to authorize upgrade)
 * - VAULT_PROXY_ADDRESS: Vault proxy contract address
 *
 * Optional Environment Variables:
 * - NEW_IMPLEMENTATION_ADDRESS: Address of new implementation (if not provided, will deploy new one)
 * - CALL_DATA: Optional call data for upgradeToAndCall (hex encoded, e.g., "0x...")
 * - PERMISSION_MANAGER_ADDRESS: PermissionManager address (required for authorization check)
 */
contract UpgradeVault is Script {
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address proxyAddress = vm.envAddress("VAULT_PROXY_ADDRESS");
        address permissionManagerAddress = vm.envAddress("PERMISSION_MANAGER_ADDRESS");

        console2.log("=== Upgrade Vault Script ===");
        console2.log("Caller:", caller);
        console2.log("Proxy Address:", proxyAddress);
        console2.log("PermissionManager Address:", permissionManagerAddress);
        console2.log("");

        Vault proxy = Vault(payable(proxyAddress));
        IPermissionManager permissionManager = IPermissionManager(permissionManagerAddress);

        // Get current implementation from storage slot
        // ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
        console2.log("Current Implementation:", currentImplementation);
        console2.log("");

        // Check if caller has DEFAULT_ADMIN_ROLE
        bool hasAdminRole = permissionManager.hasRole(DEFAULT_ADMIN_ROLE, caller);
        console2.log("Caller has DEFAULT_ADMIN_ROLE:", hasAdminRole ? "[YES]" : "[NO]");
        if (!hasAdminRole) {
            console2.log("[ERROR] Caller does not have DEFAULT_ADMIN_ROLE");
            console2.log("[INFO] Only accounts with DEFAULT_ADMIN_ROLE can authorize upgrades");
            revert("Not authorized");
        }
        console2.log("[OK] Caller is authorized");
        console2.log("");

        vm.startBroadcast(callerKey);

        // Deploy or use existing new implementation
        address newImplementation;
        if (vm.envExists("NEW_IMPLEMENTATION_ADDRESS")) {
            newImplementation = vm.envAddress("NEW_IMPLEMENTATION_ADDRESS");
            console2.log("Using existing implementation:", newImplementation);
        } else {
            console2.log("Deploying new Vault implementation...");
            Vault newImpl = new Vault();
            newImplementation = address(newImpl);
            console2.log("New Implementation deployed at:", newImplementation);
        }
        console2.log("");

        // Verify new implementation is different
        if (currentImplementation == newImplementation) {
            console2.log("[ERROR] New implementation is the same as current implementation");
            revert("Implementation addresses are the same");
        }

        // Upgrade the proxy
        bytes memory callData = "";
        if (vm.envExists("CALL_DATA")) {
            callData = vm.envBytes("CALL_DATA");
            console2.log("Upgrading with call data...");
            proxy.upgradeToAndCall(newImplementation, callData);
        } else {
            console2.log("Upgrading to new implementation...");
            proxy.upgradeToAndCall(newImplementation, "");
        }
        console2.log("[OK] Upgrade successful");
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        address verifiedImplementation = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
        console2.log("New Implementation Address:", verifiedImplementation);

        if (verifiedImplementation == newImplementation) {
            console2.log("Implementation matches: [OK]");
        } else {
            console2.log("[ERROR] Implementation mismatch!");
            console2.log("  Expected:", newImplementation);
            console2.log("  Got:", verifiedImplementation);
        }
        console2.log("");

        console2.log("=== Upgrade Complete ===");
    }
}
