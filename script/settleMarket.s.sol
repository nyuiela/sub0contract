// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";

/**
 * @title SettleMarket
 * @notice Script to resolve a market (oracle only). Calls Sub0.resolve(questionId, payouts).
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Oracle private key (must match market.oracle)
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION_ID: Market question ID (bytes32 hex)
 * - OUTCOME_SLOT_COUNT: Number of outcomes (2-16)
 * - PAYOUT_0, PAYOUT_1, ... PAYOUT_(n-1): Payout numerators (e.g. 1,0 for outcome 0 wins)
 */
contract SettleMarket is Script {
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory b = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k--;
            b[k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(b);
    }

    function run() external {
        uint256 oracleKey = vm.envUint("PRIVATE_KEY");
        address oracle = vm.addr(oracleKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        bytes32 questionId = vm.envBytes32("QUESTION_ID");
        uint256 outcomeSlotCount = vm.envUint("OUTCOME_SLOT_COUNT");

        require(outcomeSlotCount >= 2 && outcomeSlotCount <= 16, "OUTCOME_SLOT_COUNT 2-16");

        uint256[] memory payouts = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            payouts[i] = vm.envUint(string.concat("PAYOUT_", _uint2str(i)));
        }

        console2.log("=== Settle Market ===");
        console2.log("Oracle:", oracle);
        console2.log("Sub0:", sub0Address);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Outcome Slot Count:", outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            console2.log("  Payout", i, ":", payouts[i]);
        }
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        Sub0.Market memory market = sub0.getMarket(questionId);
        require(market.oracle == oracle, "Caller is not the market oracle");

        vm.startBroadcast(oracleKey);
        sub0.resolve(questionId, payouts);
        vm.stopBroadcast();

        console2.log("[OK] Market resolved.");
    }
}
