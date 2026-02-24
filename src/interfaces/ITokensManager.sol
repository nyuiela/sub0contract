// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokensManager {
    // errors
    error InvalidTokenAddress(address token);
    error InvalidTokenBanned(address token);
    // error InvalidPriceFeedAddress(address priceFeed);
    error NotAuthorizedToManageTokens(address account);
    error ZeroAddress(address _address);
    error NotAuthorized(address account, bytes32 role);

    // events
    event ConfigSet(address permissionManager);
    event TokenAllowed(address token, bool isAllowed);
    event TokenBanned(address token);
    event DecimalsSet(address token, uint8 decimals);
    event PriceFeedSet(address token, address priceFeed);
    event PriceFeedRemoved(address token);
    event TokenUnbanned(address token);

    // structs
    struct Config {
        address permissionManager;
    }

    /// @dev Gets whether a token is allowed.
    /// @param token The token address to check.
    /// @return True if the token is allowed, false otherwise.
    function allowedTokens(address token) external view returns (bool);

    /// @dev Gets whether a token is banned.
    /// @param token The token address to check.
    /// @return True if the token is banned, false otherwise.
    function bannedTokens(address token) external view returns (bool);

    /// @dev Initializes the tokens manager contract.
    /// @param _permissionManager The permission manager contract address.
    /// @param _conditionalTokens The conditional tokens contract address.
    function initialize(address _permissionManager, address _conditionalTokens) external;

    /// @dev Allows or disallows a token in the allow list.
    /// @param token The token address to allow or disallow.
    /// @param isAllowed True to allow the token, false to disallow.
    function allowListToken(address token, bool isAllowed) external;

    /// @dev Bans a token from being used.
    /// @param token The token address to ban.
    function banToken(address token) external;

    /// @dev gets token decimal
    /// @param token The token address's decimal e.g usdc = 6 decimals
    function getDecimal(address token) external returns (bool, uint8);

    /// @dev sets price feed
    /// @param token The token address's price feed
    /// @param priceFeed The price feed address
    function setPriceFeed(address token, address priceFeed) external;

    /// @dev gets price feed
    /// @param token The token address's price feed
    function getPriceFeed(address token) external view returns (address);

    /// @dev removes price feed
    /// @param token The token address's price feed
    function removePriceFeed(address token) external;

    /// @dev checks if a token is allowed
    /// @param token The token address to check
    /// @return True if the token is allowed, false otherwise
    function isAllowed(address token) external view returns (bool);
}
