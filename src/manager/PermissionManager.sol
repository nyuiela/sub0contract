// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract PermissionManager is AccessControl, Initializable {
    // constants
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_OPERATOR_ROLE = keccak256("GAME_OPERATOR_ROLE");
    bytes32 public constant GAME_VIEWER_ROLE = keccak256("GAME_VIEWER_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // mappings
    mapping(address => mapping(bytes32 => bool)) public oracles;

    // modifiers
    modifier onlyOracle(address oracle) {
        require(oracles[oracle][ORACLE_MANAGER_ROLE], NotAuthorized(oracle, ORACLE_MANAGER_ROLE));
        _;
    }

    // errors
    error NotAuthorized(address account, bytes32 role);

    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // function grantRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) {
    //     _grantRole(role, account);
    // }

    // function revokeRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) {
    //     _revokeRole(role, account);
    // }

    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        return super.getRoleAdmin(role);
    }

    function allowOracle(address oracle, bool isAllowed) public onlyRole(DEFAULT_ADMIN_ROLE) {
        oracles[oracle][ORACLE_MANAGER_ROLE] = isAllowed;
    }

    function revokeOracle(address oracle) public onlyRole(DEFAULT_ADMIN_ROLE) {
        oracles[oracle][ORACLE_MANAGER_ROLE] = false;
    }

    function isAuthorizedOracle(address oracle) public view returns (bool) {
        return oracles[oracle][ORACLE_MANAGER_ROLE];
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
}
