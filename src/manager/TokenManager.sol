// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";

contract TokensManager is ITokensManager, Initializable {
    // constants
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    // storage
    IPermissionManager public permissionManager;
    // mappings
    mapping(address => bool) public allowedTokens;
    mapping(address => bool) public bannedTokens;
    mapping(address => uint8) public decimals;
    mapping(address => address) public priceFeed;

    // modifiers
    modifier onlyValidToken(address token) {
        if (token == address(0)) revert ZeroAddress(token);
        if (bannedTokens[token]) revert InvalidTokenBanned(token);
        _;
    }

    modifier onlyAuthorized(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    modifier onlyValidPriceFeed(address _priceFeed) {
        if (_priceFeed == address(0)) revert ZeroAddress(_priceFeed);
        _;
    }

    function initialize(address _permissionManager, address _conditionalTokens) public initializer {
        if (_conditionalTokens == address(0)) revert ZeroAddress(_conditionalTokens);
        permissionManager = IPermissionManager(_permissionManager);
    }

    function allowListToken(address token, bool _isAllowed)
        external
        onlyValidToken(token)
        onlyAuthorized(TOKEN_MANAGER_ROLE)
    {
        allowedTokens[token] = _isAllowed;
        emit TokenAllowed(token, _isAllowed);
    }

    function banToken(address token) external onlyValidToken(token) onlyAuthorized(TOKEN_MANAGER_ROLE) {
        bannedTokens[token] = true;
        allowedTokens[token] = false;
        emit TokenBanned(token);
    }

    function unbanToken(address token) external onlyValidToken(token) onlyAuthorized(TOKEN_MANAGER_ROLE) {
        bannedTokens[token] = false;
        allowedTokens[token] = true;
        emit TokenUnbanned(token);
    }

    function getDecimal(address token) public view returns (bool, uint8) {
        bool success = allowedTokens[token];
        uint8 decimal = decimals[token];
        return (success, decimal);
    }

    function setPriceFeed(address token, address _priceFeed)
        external
        onlyValidToken(token)
        onlyAuthorized(TOKEN_MANAGER_ROLE)
        onlyValidPriceFeed(_priceFeed)
    {
        priceFeed[token] = _priceFeed;
        emit PriceFeedSet(token, _priceFeed);
    }

    function getPriceFeed(address token) public view returns (address) {
        return priceFeed[token];
    }

    function removePriceFeed(address token) external onlyValidToken(token) onlyAuthorized(TOKEN_MANAGER_ROLE) {
        delete priceFeed[token];
        emit PriceFeedRemoved(token);
    }

    function setConfig(Config memory _config) external onlyAuthorized(TOKEN_MANAGER_ROLE) {
        permissionManager = IPermissionManager(_config.permissionManager);
        emit ConfigSet(_config.permissionManager);
    }

    function setDecimals(address token, uint8 _decimals)
        external
        onlyValidToken(token)
        onlyAuthorized(TOKEN_MANAGER_ROLE)
    {
        decimals[token] = _decimals;
        emit DecimalsSet(token, _decimals);
    }

    function isAllowed(address token) external view returns (bool) {
        return allowedTokens[token];
    }
}
