// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVault {
    // errors
    error TokenNotAllowedListed(address token);
    error InvalidAddress(address _address);
    error NotAuthorized(address, bytes32 role);
    error ZeroAddress();
    error InsufficientBalance(uint256 amount);
    error StalePrice();
    error NegativePrice();
    error UpdatedAtIsZero();
    error StaleRound();
    error InvalidFee(uint256 fee);
    error AlreadyWithdrawn(bytes32 id);

    // events
    event ConfigSet(address tokenManager, address permissionManager);
    event FeeConfigUpdated(address feeCollector, uint256 feeBps);
    event FeesCollected(address token, uint256 amount);
    event Deposit(address indexed user, address token, uint256 amount, uint256 creditedValue);
    event Withdrawal(address indexed user, bytes32 indexed questionId, address gameContract, uint256 amount);

    // structs
    struct Config {
        address tokenManager;
        address permissionManager;
    }

    // functions
    /// @dev prepares a condition for a question (must be called before first deposit)
    /// @param questionId The question identifier
    /// @param outcomeCount Number of possible outcomes (options)
    function prepareCondition(bytes32 questionId, uint256 outcomeCount) external returns (bytes32);

    /// @dev resolves a condition by reporting payouts (oracle only)
    /// @param questionId The question identifier
    /// @param payouts Array of payout numerators for each outcome
    function resolveCondition(bytes32 questionId, uint256[] calldata payouts) external;

    /// @dev gets the game vault balance for a specific question
    /// @param questionId The question id
    /// @return The game vault balance
    function balanceOf(bytes32 questionId) external view returns (uint256);

    /// @dev calculates the value of a token in the vault's base currency
    /// @param _tokenIn The token address to calculate value for
    /// @param _amountIn The amount to calculate the value of
    /// @return The value of the token in the vault's base currency
    function calculateValue(address _tokenIn, uint256 _amountIn) external view returns (uint256);

    /// @dev gets the latest Chainlink price feed answer for a token
    /// @param token The token address
    /// @return The latest price answer
    function getChainlinkDataFeedLatestAnswer(address token) external view returns (int256);

    /// @dev converts a token amount to the vault's base currency using price feed
    /// @param token The token address
    /// @param amount The amount to convert
    /// @return The converted amount in the vault's base currency
    function convertPrice(address token, uint256 amount) external view returns (uint256);

    /// @dev sets the vault configuration
    /// @param _config The configuration struct
    function setConfig(Config memory _config) external;

    /// @dev sets the fee collector and percentage
    /// @param _feeCollector Address to receive fees
    /// @param _feeBps Fee in basis points (500 = 5%). Max 1000 (10%).
    function setFeeConfig(address _feeCollector, uint256 _feeBps) external;

    /// @dev sweeps accumulated fees to the fee collector
    function claimFees() external;
}
