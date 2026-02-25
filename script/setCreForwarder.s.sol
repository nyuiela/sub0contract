// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Sub0 } from "../src/gamehub/Sub0.sol";
import { PermissionManager } from "../src/manager/PermissionManager.sol";

/**
 * @title SetCreForwarder
 * @notice Sets the Chainlink CRE Keystone Forwarder on Sub0 and grants it GAME_CREATOR_ROLE
 *        so that CRE workflows can create markets via writeReport -> Forwarder -> Sub0.onReport().
 *
 * ----------------------------------------------------------------------------
 * HOW TO GET THE FORWARDER ADDRESS (no simulation required)
 * ----------------------------------------------------------------------------
 * The Keystone Forwarder address is PUBLIC and CHAIN-SPECIFIC. You do NOT need to run
 * a workflow simulation to discover it. Use either:
 *
 * 1. Chainlink docs: Check the CRE / Keystone Forwarder documentation for your target
 *    chain (e.g. Base Sepolia, Sepolia). The forwarder contract address is usually
 *    listed per network.
 *
 * 2. From any successful writeReport tx: Run your CRE workflow with --broadcast once;
 *    open the resulting transaction on the block explorer. The "To" address of that
 *    transaction IS the Forwarder. Use that address for this script on the same chain.
 *
 * For Base Sepolia (ethereum-testnet-sepolia-base-1) the forwarder used in this
 * project is set below as DEFAULT_CRE_FORWARDER; override with env CRE_FORWARDER_ADDRESS.
 *
 * ----------------------------------------------------------------------------
 * SUB0 vs RECEIVER TEMPLATE
 * ----------------------------------------------------------------------------
 * Sub0 does NOT use Chainlink's ReceiverTemplate. It has only setCreForwarderAddress.
 * There are no "expected author", "expected workflow name", or "expected workflow id"
 * setters on Sub0. You only need to: (1) set the forwarder address, (2) grant
 * GAME_CREATOR_ROLE to that forwarder. If your consumer used ReceiverTemplate you
 * would call those extra setters; for Sub0 they are not needed.
 *
 * ----------------------------------------------------------------------------
 * ADAPTING FOR OTHER CRE WORKFLOWS
 * ----------------------------------------------------------------------------
 * - Use the same flow: set your consumer's "forwarder" / "allowed caller" to the
 *   Keystone Forwarder address for your chain, and grant any role that your
 *   consumer's onReport() requires (e.g. GAME_CREATOR_ROLE for Sub0 Public markets).
 * - Required env: PRIVATE_KEY (owner of Sub0, or DEFAULT_ADMIN_ROLE to only grant role), SUB0_ADDRESS.
 * - Optional env: CRE_FORWARDER_ADDRESS (defaults to Base Sepolia forwarder below).
 */
contract SetCreForwarder is Script {
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// Base Sepolia Keystone Forwarder (used when CRE_FORWARDER_ADDRESS is not set)
    address public constant DEFAULT_CRE_FORWARDER = 0x82300bd7c3958625581cc2F77bC6464dcEcDF3e5;

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        address forwarder = _getForwarderAddress();

        console2.log("=== Set CRE Forwarder and Grant GAME_CREATOR_ROLE ===");
        console2.log("Sub0:", sub0Address);
        console2.log("Forwarder:", forwarder);
        console2.log("Caller:", owner);
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        PermissionManager pm = PermissionManager(address(sub0.permissionManager()));
        require(pm.hasRole(DEFAULT_ADMIN_ROLE, owner), "Caller must have DEFAULT_ADMIN_ROLE on PermissionManager");

        address sub0Owner = sub0.owner();
        bool canSetForwarder = (sub0Owner != address(0)) && (sub0Owner == owner);

        if (sub0Owner == address(0)) {
            console2.log("[WARN] Sub0.owner() is zero (wrong proxy address or proxy not initialized).");
            console2.log("       We will only grant GAME_CREATOR_ROLE to the forwarder.");
            console2.log("       After fixing Sub0 ownership, call setCreForwarderAddress(forwarder) as owner.");
            console2.log("");
        } else if (!canSetForwarder) {
            revert("Caller is not Sub0 owner; run with the key that owns Sub0 or only grant role (see script).");
        }

        vm.startBroadcast(ownerKey);

        if (canSetForwarder) {
            sub0.setCreForwarderAddress(forwarder);
            console2.log("[OK] Sub0.setCreForwarderAddress(forwarder)");
        }

        if (!pm.hasRole(GAME_CREATOR_ROLE, forwarder)) {
            pm.grantRole(GAME_CREATOR_ROLE, forwarder);
            console2.log("[OK] PermissionManager.grantRole(GAME_CREATOR_ROLE, forwarder)");
        } else {
            console2.log("[OK] Forwarder already has GAME_CREATOR_ROLE");
        }

        vm.stopBroadcast();

        require(pm.hasRole(GAME_CREATOR_ROLE, forwarder), "Forwarder missing GAME_CREATOR_ROLE");
        if (canSetForwarder) {
            require(sub0.getCreForwarderAddress() == forwarder, "Sub0 forwarder mismatch");
            console2.log("\n[OK] CRE forwarder setup complete. Run your create-market workflow with --broadcast.");
        } else {
            console2.log("\n[OK] GAME_CREATOR_ROLE granted to forwarder. Set Sub0 forwarder when owner is fixed.");
        }
    }

    function _getForwarderAddress() internal view returns (address) {
        return vm.envOr("CRE_FORWARDER_ADDRESS", DEFAULT_CRE_FORWARDER);
    }
}
