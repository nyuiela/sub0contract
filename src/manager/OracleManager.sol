// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {IOracleManager} from "../interfaces/IOracleManager.sol";

contract OracleManager is IOracleManager, Initializable {
    // constants
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant ORACLE = keccak256("ORACLE");

    IPermissionManager public permissionManager;
    //STORAGE
    address[] public oracles;
    // mappings
    mapping(address => bool) public allowedOracles;
    mapping(bytes32 => bool) public fulfilled;
    mapping(bytes32 => uint256) public result;

    // modifiers
    modifier onlyOracleManager() {
        if (!permissionManager.hasRole(ORACLE_MANAGER_ROLE, msg.sender)) {
            revert NotAuthorized(msg.sender, ORACLE_MANAGER_ROLE);
        }
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    function fulfill(bytes32 questionId, uint256 optionIndex, address gameContract, uint256 amount)
        public
        onlyRole(ORACLE)
    {
        if (!allowedOracles[msg.sender]) revert OracleNotFound(msg.sender);
        bytes32 id = keccak256(abi.encodePacked(questionId, gameContract));
        if (gameContract == address(0)) revert ZeroAddress();
        if (optionIndex == 0 || optionIndex > 255) revert InvalidOptionIndex(optionIndex);
        if (fulfilled[id]) revert QuestionAlreadyFulfilled(id);
        fulfilled[id] = true;
        result[id] = optionIndex;
        emit OracleFulfilled(questionId, optionIndex, gameContract, amount);
    }

    function overrideResult(bytes32 questionId, address gameContract, uint256 optionIndex) public onlyOracleManager {
        bytes32 id = keccak256(abi.encodePacked(questionId, gameContract));
        if (!fulfilled[id]) revert QuestionNotFulfilled(questionId);
        result[id] = optionIndex;
        emit OracleResultOverridden(questionId, gameContract, optionIndex);
    }

    function getResult(bytes32 questionId, address gameContract) public view returns (bool, uint256) {
        bytes32 id = keccak256(abi.encodePacked(questionId, gameContract));
        return (fulfilled[id], result[id]);
    }

    function getFulfilled(bytes32 questionId, address gameContract) public view returns (bool) {
        bytes32 id = keccak256(abi.encodePacked(questionId, gameContract));
        return fulfilled[id];
    }

    function initialize(address _permissionManager) public initializer {
        if (_permissionManager == address(0)) revert ZeroAddress();
        permissionManager = IPermissionManager(_permissionManager);
    }

    // functions
    function allow(address oracle) public onlyOracleManager {
        if (allowedOracles[oracle]) revert OracleAlreadyExists(oracle);
        allowedOracles[oracle] = true;
        oracles.push(oracle);
        emit OracleAdded(oracle);
    }

    function revoke(address oracle) public onlyOracleManager {
        if (!allowedOracles[oracle]) revert OracleNotFound(oracle);
        allowedOracles[oracle] = false;
        for (uint256 i = 0; i < oracles.length; i++) {
            if (oracles[i] == oracle) {
                oracles[i] = oracles[oracles.length - 1];
                oracles.pop();
                break;
            }
        } // limiting the scope of the loop to the length of the array.
        emit OracleRemoved(oracle);
    }

    function getOracles() public view onlyOracleManager returns (address[] memory) {
        return oracles;
    }

    function isAllowed(address oracle) public view returns (bool) {
        return allowedOracles[oracle];
    }
}
