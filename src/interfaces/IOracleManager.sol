// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracleManager {
    // errors
    error OracleAlreadyExists(address oracle);
    error OracleNotFound(address oracle);
    error NotAuthorized(address account, bytes32 role);
    error ZeroAddress();
    error InvalidOptionIndex(uint256 optionIndex);
    error QuestionAlreadyFulfilled(bytes32 questionId);
    error QuestionNotFulfilled(bytes32 questionId);
    error WinningOptionNotSet(bytes32 questionId, address gameContract);

    // events
    event OracleAdded(address oracle);
    event OracleRemoved(address oracle);
    event OracleFulfilled(bytes32 questionId, uint256 optionIndex, address gameContract, uint256 amount);
    event OracleResultOverridden(bytes32 questionId, address gameContract, uint256 optionIndex);

    // functions
    function allow(address oracle) external;

    /// @dev Revokes an oracle from the allow list.
    /// @param oracle The oracle address to revoke.
    function revoke(address oracle) external;

    /// @dev Gets the oracles from the allow list.
    /// @return The oracles.
    function getOracles() external view returns (address[] memory);

    /// @dev Checks if an oracle is allowed.
    /// @param oracle The oracle address to check.
    /// @return True if the oracle is allowed, false otherwise.
    function isAllowed(address oracle) external view returns (bool);
}
