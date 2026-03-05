// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";

/**
 * @title DeployMockUsdc
 * @notice Deploys a mintable TestERC20 as USDC and mints to deployer. Use for Tenderly when no USDC exists.
 * Set TENDERLY_USDC_ADDRESS in .env to the logged address, then run just deploy-tenderly.
 */
contract DeployMockUsdc is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        TestERC20 mockUsdc = new TestERC20("USD Coin", "USDC", 6, deployer);
        mockUsdc.mint(deployer, 1_000_000 * 10 ** 6);
        vm.stopBroadcast();
        console2.log("Deployed TestERC20 (USDC) at:", address(mockUsdc));
        console2.log("Set in .env: TENDERLY_USDC_ADDRESS=%s", address(mockUsdc));
    }
}
