// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";

/**
 * @title SetCreForwarderConfig
 * @notice Sets CRE receiver config on Sub0 (forwarder, expected author, workflow name, workflow ID).
 *
 * Environment Variables:
 * - PRIVATE_KEY: Owner private key (required)
 * - SUB0_ADDRESS: Sub0 proxy address (required)
 * - CRE_FORWARDER_ADDRESS: Set forwarder address (optional)
 * - CRE_EXPECTED_AUTHOR: Set expected workflow author address (optional)
 * - CRE_EXPECTED_WORKFLOW_NAME: Set expected workflow name string (optional; use empty to clear)
 * - CRE_EXPECTED_WORKFLOW_ID: Set expected workflow ID as 32-byte hex, e.g. 0x... (optional)
 */
contract SetCreForwarderConfig is Script {
    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);
        address sub0Addr = vm.envAddress("SUB0_ADDRESS");
        Sub0 sub0 = Sub0(payable(sub0Addr));

        console2.log("=== Set CRE Forwarder Config ===");
        console2.log("Sub0:", sub0Addr);
        console2.log("Caller (owner):", owner);
        console2.log("");

        vm.startBroadcast(ownerKey);

        if (vm.envExists("CRE_FORWARDER_ADDRESS")) {
            address forwarder = vm.envAddress("CRE_FORWARDER_ADDRESS");
            sub0.setForwarderAddress(forwarder);
            console2.log("setForwarderAddress:", forwarder);
        }
        if (vm.envExists("CRE_EXPECTED_AUTHOR")) {
            address author = vm.envAddress("CRE_EXPECTED_AUTHOR");
            sub0.setExpectedAuthor(author);
            console2.log("setExpectedAuthor:", author);
        }
        if (vm.envExists("CRE_EXPECTED_WORKFLOW_NAME")) {
            string memory name = vm.envString("CRE_EXPECTED_WORKFLOW_NAME");
            sub0.setExpectedWorkflowName(name);
            console2.log("setExpectedWorkflowName:", name);
        }
        if (vm.envExists("CRE_EXPECTED_WORKFLOW_ID")) {
            bytes32 id = vm.envBytes32("CRE_EXPECTED_WORKFLOW_ID");
            sub0.setExpectedWorkflowId(id);
            console2.log("setExpectedWorkflowId:", vm.toString(id));
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("Current config:");
        console2.log("  forwarder:", sub0.getForwarderAddress());
        console2.log("  expectedAuthor:", sub0.getExpectedAuthor());
        console2.log("=== Done ===");
    }
}
