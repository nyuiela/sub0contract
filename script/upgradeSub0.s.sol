// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";

/**
 * @title UpgradeSub0
 * @notice Script to upgrade the Sub0 contract to a new implementation.
 *
 * Environment Variables:
 * - PRIVATE_KEY: Private key for the account with OWNER role
 * - SUB0_PROXY_ADDRESS: Sub0 proxy contract address
 *
 * Optional:
 * - NEW_IMPLEMENTATION_ADDRESS: New implementation address (if not set, deploys new one)
 * - CALL_DATA: Optional hex-encoded call data for upgradeToAndCall
 */
contract UpgradeSub0 is Script {
    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);
        address proxyAddress = vm.envAddress("SUB0_PROXY_ADDRESS");

        console2.log("=== Upgrade Sub0 ===");
        console2.log("Caller:", caller);
        console2.log("Proxy:", proxyAddress);
        console2.log("");

        Sub0 proxy = Sub0(payable(proxyAddress));
        bytes32 implementationSlot =
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImpl = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
        console2.log("Current implementation:", currentImpl);
        console2.log("");

        vm.startBroadcast(callerKey);

        address newImplementation;
        if (vm.envExists("NEW_IMPLEMENTATION_ADDRESS")) {
            newImplementation = vm.envAddress("NEW_IMPLEMENTATION_ADDRESS");
            console2.log("Using existing implementation:", newImplementation);
        } else {
            Sub0 newImpl = new Sub0();
            newImplementation = address(newImpl);
            console2.log("New implementation deployed:", newImplementation);
        }
        console2.log("");

        if (currentImpl == newImplementation) revert("Same implementation");

        require(proxy.owner() == caller, "Not owner");
        console2.log("[OK] Caller is owner");

        bytes memory callData = vm.envOr("CALL_DATA", bytes(""));
        if (callData.length > 0) {
            proxy.upgradeToAndCall(newImplementation, callData);
            console2.log("Upgraded with call data");
        } else {
            proxy.upgradeToAndCall(newImplementation, "");
            console2.log("Upgraded to new implementation");
        }
        console2.log("[OK] Upgrade successful");
        console2.log("");

        vm.stopBroadcast();

        address verifiedImpl = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
        console2.log("Verified implementation:", verifiedImpl);
        console2.log(verifiedImpl == newImplementation ? "Match: [OK]" : "Mismatch");
        console2.log("=== Upgrade complete ===");
    }
}
