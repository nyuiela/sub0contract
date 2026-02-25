// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISub0Settlement {
    function resolve(bytes32 questionId, uint256[] calldata payouts) external;
}
