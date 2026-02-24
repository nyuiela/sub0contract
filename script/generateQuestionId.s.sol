// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title GenerateQuestionId
 * @notice Computes the questionId used by Sub0: keccak256(abi.encodePacked(question, creator, oracle)).
 *        View only; no broadcast.
 *
 * Required Environment Variables:
 * - QUESTION: The market question (string)
 * - CREATOR_ADDRESS: The address that will call Sub0.create (msg.sender)
 * - ORACLE_ADDRESS: The oracle address for the market
 */
contract GenerateQuestionId is Script {
    function run() external view {
        string memory question = vm.envString("QUESTION");
        address creator = vm.envAddress("CREATOR_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");

        bytes32 questionId = keccak256(abi.encodePacked(question, creator, oracle));

        console2.log("=== Generate Question ID ===");
        console2.log("Question:", question);
        console2.log("Creator (msg.sender):", creator);
        console2.log("Oracle:", oracle);
        console2.log("");
        console2.log("Question ID (bytes32):", vm.toString(questionId));
    }
}
