// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {InvitationManager} from "../src/manager/InvitationManager.sol";

/**
 * @title CreateMarket
 * @notice Script to create a market in Sub0. questionId = keccak256(abi.encodePacked(question, msg.sender, oracle)).
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Creator private key (msg.sender)
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION: The market question (string)
 * - ORACLE_ADDRESS: Oracle that will resolve the market
 * - ORACLE_TYPE: uint8 (1=PLATFORM, 2=ARBITRATOR, 3=CUSTOM)
 * - BET_TYPE: uint8 (0=Single, 1=Group, 2=Public)
 * - DURATION: Duration in seconds
 * - OUTCOME_SLOT_COUNT: Number of outcomes (2-255)
 */
contract CreateMarket is Script {
    bytes32 public constant ORACLE = keccak256("ORACLE");

    function run() external {
        uint256 callerKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(callerKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        string memory question = vm.envString("QUESTION");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        uint8 oracleTypeRaw = uint8(vm.envUint("ORACLE_TYPE"));
        uint8 betTypeRaw = uint8(vm.envUint("BET_TYPE"));
        uint256 duration = vm.envUint("DURATION");
        uint256 outcomeSlotCount = vm.envUint("OUTCOME_SLOT_COUNT");

        console2.log("=== Create Market ===");
        console2.log("Creator (msg.sender):", caller);
        console2.log("Sub0:", sub0Address);
        console2.log("Question:", question);
        console2.log("Oracle:", oracleAddress);
        console2.log("Oracle Type:", oracleTypeRaw);
        console2.log("Bet Type:", betTypeRaw);
        console2.log("Duration:", duration);
        console2.log("Outcome Slot Count:", outcomeSlotCount);

        bytes32 questionId = keccak256(abi.encodePacked(question, caller, oracleAddress));
        console2.log("Expected questionId:", vm.toString(questionId));
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        require(oracleTypeRaw <= 3 && oracleTypeRaw != 0, "Invalid OracleType");
        require(betTypeRaw <= 2, "Invalid BetType");
        require(outcomeSlotCount >= 2 && outcomeSlotCount <= 255, "Invalid outcome slot count");
        require(duration > 0, "Duration must be > 0");

        Sub0.OracleType oracleType = Sub0.OracleType(oracleTypeRaw);
        if (oracleType == Sub0.OracleType.PLATFORM || oracleType == Sub0.OracleType.CUSTOM) {
            require(sub0.hub().isAllowed(oracleAddress, ORACLE), "Oracle not allowlisted");
        }

        Sub0.Market memory market = Sub0.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: oracleAddress,
            owner: address(0),
            createdAt: 0,
            duration: duration,
            outcomeSlotCount: outcomeSlotCount,
            oracleType: oracleType,
            marketType: InvitationManager.InvitationType(betTypeRaw)
        });

        vm.startBroadcast(callerKey);
        bytes32 id = sub0.create(market);
        vm.stopBroadcast();

        require(id == questionId, "questionId mismatch");
        console2.log("[OK] Market created. Question ID:", vm.toString(id));
    }
}
