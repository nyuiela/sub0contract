// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";

/**
 * @title Stake
 * @notice Script to stake tokens on a bet option in the Sub0 contract
 * @dev Approves the vault and calls the stake function
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Private key for the account that will stake
 * - SUB0_ADDRESS: Sub0 contract address
 * - QUESTION_ID: The question ID (bytes32) as a hex string (0x...)
 * - OPTION: The option index to stake on (uint256)
 * - TOKEN_ADDRESS: The token contract address to stake
 * - AMOUNT: The amount to stake (uint256, in token's smallest unit)
 */
contract Stake is Script {
    function run() external {
        uint256 stakerKey = vm.envUint("PRIVATE_KEY");
        address staker = vm.addr(stakerKey);

        address sub0Address = vm.envAddress("SUB0_ADDRESS");
        bytes32 questionId = vm.envBytes32("QUESTION_ID");
        uint256 option = vm.envUint("OPTION");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT");

        console2.log("=== Stake Script ===");
        console2.log("Staker:", staker);
        console2.log("Sub0 Address:", sub0Address);
        console2.log("Question ID:", vm.toString(questionId));
        console2.log("Option Index:", option);
        console2.log("Token Address:", tokenAddress);
        console2.log("Amount:", amount);
        console2.log("");

        Sub0 sub0 = Sub0(payable(sub0Address));
        ConditionalTokensV2 ct = ConditionalTokensV2(sub0.conditionalToken());
        IERC20 token = IERC20(tokenAddress);

        console2.log("Vault Address:", address(sub0.vault()));
        console2.log("ConditionalTokens Address:", address(ct));
        console2.log("");

        // Check token balance
        uint256 balance = token.balanceOf(staker);
        console2.log("Staker Token Balance:", balance);
        if (balance < amount) {
            console2.log("[ERROR] Insufficient token balance");
            revert("Insufficient token balance");
        }
        console2.log("");

        uint256 outcomeSlotCount = sub0.getMarket(questionId).outcomeSlotCount;
        uint256 indexSet = 1 << option;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 otherSet = fullIndexSet ^ indexSet;
        uint256[] memory partition = new uint256[](2);
        partition[0] = indexSet;
        partition[1] = otherSet;

        vm.startBroadcast(stakerKey);

        // Approve ConditionalTokens to pull collateral
        uint256 currentAllowance = token.allowance(staker, address(ct));
        console2.log("Current Allowance (CT):", currentAllowance);

        if (currentAllowance < amount) {
            console2.log("Approving ConditionalTokens to spend tokens...");
            token.approve(address(ct), amount);
            console2.log("[OK] Approved ConditionalTokens to spend", amount, "tokens");
        } else {
            console2.log("[SKIP] Sufficient allowance already exists");
        }
        console2.log("");

        // Stake tokens (parentCollectionId = 0, partition, token, amount)
        console2.log("Staking tokens...");
        sub0.stake(questionId, bytes32(0), partition, tokenAddress, amount);
        console2.log("[OK] Successfully staked", amount, "tokens on option", option);
        console2.log("");

        vm.stopBroadcast();

        console2.log("=== Stake Complete ===");
    }
}
