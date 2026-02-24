// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";

/**
 * @title GetMarket
 * @notice Script to fetch a market by questionId from the Sub0 contract (view only).
 *
 * Required Environment Variables:
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION_ID: The question ID (bytes32) as hex string (0x...)
 */
contract GetMarket is Script {
    function run() external view {
        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        bytes32 questionId = vm.envBytes32("QUESTION_ID");

        console2.log("=== Get Market ===");
        console2.log("Sub0 Address:", sub0Address);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        Sub0.Market memory market = sub0.getMarket(questionId);

        if (bytes(market.question).length == 0) {
            console2.log("(No market found for this questionId)");
            return;
        }

        console2.log("question:", market.question);
        console2.log("conditionId:", vm.toString(market.conditionId));
        console2.log("oracle:", market.oracle);
        console2.log("owner:", market.owner);
        console2.log("createdAt:", market.createdAt);
        console2.log("duration:", market.duration);
        console2.log("outcomeSlotCount:", market.outcomeSlotCount);
        console2.log("oracleType:", uint8(market.oracleType));
        console2.log("marketType:", uint8(market.marketType));
    }
}
