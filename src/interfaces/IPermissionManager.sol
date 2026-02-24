// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IPermissionManager is IAccessControl {
    // Role constants (documented for reference, not part of interface)
    // bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    // bytes32 public constant GAME_OPERATOR_ROLE = keccak256("GAME_OPERATOR_ROLE");
    // bytes32 public constant GAME_VIEWER_ROLE = keccak256("GAME_VIEWER_ROLE");
    // bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    // bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // Errors
    error NotAuthorized(address account, bytes32 role);

    /// @dev Initializes the permission manager contract.
    function initialize() external;

    /// @dev Grants a role to an account. Overrides IAccessControl.grantRole.
    /// @param role The role to grant.
    /// @param account The account to grant the role to.
    function grantRole(bytes32 role, address account) external;

    /// @dev Revokes a role from an account. Overrides IAccessControl.revokeRole.
    /// @param role The role to revoke.
    /// @param account The account to revoke the role from.
    function revokeRole(bytes32 role, address account) external;

    /// @dev Checks if an account has a specific role. Overrides IAccessControl.hasRole.
    /// @param role The role to check.
    /// @param account The account to check.
    /// @return True if the account has the role, false otherwise.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @dev Gets the admin role for a given role. Overrides IAccessControl.getRoleAdmin.
    /// @param role The role to get the admin for.
    /// @return The admin role for the given role.
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /// @dev Gets the oracle authorization status for a given oracle and role.
    /// @param oracle The oracle address.
    /// @param role The role to check.
    /// @return True if the oracle is authorized for the role, false otherwise.
    function oracles(address oracle, bytes32 role) external view returns (bool);

    /// @dev Allows or disallows an oracle address.
    /// @param oracle The oracle address to allow or disallow.
    /// @param isAllowed True to allow the oracle, false to disallow.
    function allowOracle(address oracle, bool isAllowed) external;

    /// @dev Revokes oracle authorization for an address.
    /// @param oracle The oracle address to revoke.
    function revokeOracle(address oracle) external;

    /// @dev Checks if an oracle is authorized.
    /// @param oracle The oracle address to check.
    /// @return True if the oracle is authorized, false otherwise.
    function isAuthorizedOracle(address oracle) external view returns (bool);
}
