// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {InvitationManager} from "../src/manager/InvitationManager.sol";
import {IHub} from "../src/interfaces/IHub.sol";

/**
 * @title CreateBet
 * @notice Script to create a bet in the Sub0 contract
 * @dev Creates a bet with specified parameters and returns the question ID
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account creating the bet
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION: The bet question (string)
 * - ORACLE_ADDRESS: The oracle address that will resolve the bet
 * - ORACLE_TYPE: Oracle type as uint8 (0=NONE, 1=PLATFORM, 2=ARBITRATOR, 3=CUSTOM)
 * - BET_TYPE: Bet type as uint8 (0=Single, 1=Group, 2=Public)
 * - DURATION: Bet duration in seconds (uint256)
 * - OUTCOME_SLOT_COUNT: Number of possible outcomes (uint256, must be >= 2 and <= 255)
 *
 * Note: If BET_TYPE is Public, caller must have GAME_CREATOR_ROLE
 *       If ORACLE_TYPE is PLATFORM or CUSTOM, oracle must be allowlisted in Hub
 */
contract CreateBet is Script {
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

        console2.log("=== Create Bet Script ===");
        console2.log("Caller:", caller);
        console2.log("Sub0 Address:", sub0Address);
        console2.log("Question:", question);
        console2.log("Oracle Address:", oracleAddress);
        console2.log("Oracle Type:", oracleTypeRaw);
        console2.log("Bet Type:", betTypeRaw);
        console2.log("Duration (seconds):", duration);
        console2.log("Outcome Slot Count:", outcomeSlotCount);
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));

        // Validate OracleType
        require(oracleTypeRaw <= 3, "Invalid OracleType (must be 0-3)");
        Sub0.OracleType oracleType = Sub0.OracleType(oracleTypeRaw);

        if (oracleType == Sub0.OracleType.NONE) {
            console2.log("[ERROR] OracleType cannot be NONE");
            revert("OracleType.NONE is not allowed");
        }

        // Validate InvitationType
        require(betTypeRaw <= 2, "Invalid BetType (must be 0-2)");
        InvitationManager.InvitationType betType = InvitationManager.InvitationType(betTypeRaw);

        // Validate outcome slot count
        require(outcomeSlotCount >= 2 && outcomeSlotCount <= 255, "Invalid outcome slot count (must be 2-255)");

        // Validate duration
        require(duration > 0, "Duration must be greater than 0");

        // Check oracle allowlist if needed
        if (oracleType == Sub0.OracleType.PLATFORM || oracleType == Sub0.OracleType.CUSTOM) {
            IHub hub = sub0.hub();
            bool isAllowed = hub.isAllowed(oracleAddress, ORACLE);
            console2.log("Oracle allowlisted:", isAllowed ? "[YES]" : "[NO]");
            if (!isAllowed) {
                console2.log("[ERROR] Oracle must be allowlisted for PLATFORM or CUSTOM oracle types");
                revert("Oracle not allowlisted");
            }
        }

        // Check if Public bet requires GAME_CREATOR_ROLE
        if (betType == InvitationManager.InvitationType.Public) {
            console2.log("[INFO] Public bets require GAME_CREATOR_ROLE");
            // This will be checked by the contract
        }

        console2.log("");

        vm.startBroadcast(callerKey);

        Sub0.Market memory market = Sub0.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: oracleAddress,
            owner: address(0),
            createdAt: 0,
            duration: duration,
            outcomeSlotCount: outcomeSlotCount,
            oracleType: oracleType,
            marketType: betType
        });

        console2.log("Creating bet...");
        bytes32 questionId = sub0.create(market);
        console2.log("[OK] Bet created successfully");
        console2.log("");

        vm.stopBroadcast();

        // Verification
        console2.log("=== Verification ===");
        Sub0.Market memory createdMarket = sub0.getMarket(questionId);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Created Market Details:");
        console2.log("  Question:", createdMarket.question);
        console2.log("  Oracle:", createdMarket.oracle);
        console2.log("  Owner:", createdMarket.owner);
        console2.log("  Condition ID:", vm.toString(createdMarket.conditionId));
        console2.log("  Created At:", createdMarket.createdAt);
        console2.log("  Duration:", createdMarket.duration);
        console2.log("  Outcome Slot Count:", createdMarket.outcomeSlotCount);
        console2.log("  Oracle Type:", uint256(createdMarket.oracleType));
        console2.log("  Market Type:", uint256(createdMarket.marketType));
        console2.log("");

        // Verify values match
        require(keccak256(bytes(createdMarket.question)) == keccak256(bytes(question)), "Question mismatch");
        require(createdMarket.oracle == oracleAddress, "Oracle mismatch");
        require(createdMarket.owner == caller, "Owner mismatch");
        require(createdMarket.duration == duration, "Duration mismatch");
        require(createdMarket.outcomeSlotCount == outcomeSlotCount, "Outcome slot count mismatch");
        require(createdMarket.oracleType == oracleType, "Oracle type mismatch");
        require(createdMarket.marketType == betType, "Market type mismatch");
        require(createdMarket.conditionId != bytes32(0), "Condition ID not set");

        console2.log("All values verified: [OK]");
        console2.log("");
        console2.log("=== Create Bet Complete ===");
        console2.log("Question ID:", vm.toString(questionId));
    }
}
