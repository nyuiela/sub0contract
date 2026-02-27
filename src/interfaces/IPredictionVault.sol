// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPredictionVault
 * @notice Interface for the Sub0 Prediction Vault (Inventory Model AMM).
 *         Executes LMSR-priced trades against ConditionalTokensV2 positions.
 */
interface IPredictionVault {
    // Errors
    error InvalidSignature();
    error InvalidDonSignature();
    error InvalidUserSignature();
    error ExpiredQuote();
    error NonceAlreadyUsed();
    error SlippageExceeded();
    error MarketNotRegistered();
    error InvalidOutcome();
    error TransferFailed();
    error InsufficientVaultBalance();
    error InsufficientUsdcSolvency();

    // Events
    event TradeExecuted(
        bytes32 indexed questionId,
        uint256 outcomeIndex,
        bool buy,
        uint256 quantity,
        uint256 tradeCostUsdc,
        address user
    );
    event MarketRegistered(bytes32 indexed questionId, bytes32 conditionId);
    event MarketLiquiditySeeded(bytes32 indexed questionId, uint256 amountUsdc);
    event BackendSignerSet(address oldSigner, address newSigner);
    event DonSignerSet(address oldSigner, address newSigner);

    /**
     * @dev Register a market (conditionId) with the vault. Called by the factory on create.
     * @param questionId The question/market identifier (from factory)
     * @param conditionId The ConditionalTokensV2 condition ID
     */
    function registerMarket(bytes32 questionId, bytes32 conditionId) external;

    /**
     * @dev Seed initial liquidity: pull USDC from caller, split into full outcome set in vault.
     * @param questionId The question/market identifier
     * @param amountUsdc Amount of USDC (6 decimals) to convert into outcome tokens
     */
    function seedMarketLiquidity(bytes32 questionId, uint256 amountUsdc) external;

    /**
     * @dev Execute a dual-signature trade. DON signs the quote; user signs intent (maxCostUsdc). Relayer submits both; user pays USDC / receives CTF.
     * @param questionId The question/market identifier (must be registered)
     * @param outcomeIndex Zero-based outcome index (0 = first outcome)
     * @param buy True = user buys outcome tokens; false = user sells
     * @param quantity Amount of outcome tokens (18 decimals)
     * @param tradeCostUsdc USDC amount (6 decimals) from DON quote; must be <= maxCostUsdc (buy) or user receives this (sell)
     * @param maxCostUsdc User-authorized max USDC to pay (buy) or min to receive (sell); tradeCostUsdc must be <= maxCostUsdc for buy
     * @param nonce Unique per-market nonce (replay protection)
     * @param deadline Quote expiry timestamp
     * @param user The account that pays USDC (buy) or receives USDC (sell); must match userSignature
     * @param donSignature EIP-712 signature from DON (quote: marketId, outcomeIndex, buy, quantity, tradeCostUsdc, user, nonce, deadline)
     * @param userSignature EIP-712 signature from user (intent: marketId, outcomeIndex, buy, quantity, maxCostUsdc, nonce, deadline)
     */
    function executeTrade(
        bytes32 questionId,
        uint256 outcomeIndex,
        bool buy,
        uint256 quantity,
        uint256 tradeCostUsdc,
        uint256 maxCostUsdc,
        uint256 nonce,
        uint256 deadline,
        address user,
        bytes calldata donSignature,
        bytes calldata userSignature
    ) external;
    

    /**
     * @dev Returns the CTF condition ID for a registered question.
     */
    function getConditionId(bytes32 questionId) external view returns (bytes32);

    /**
     * @dev Returns the backend signer address (legacy); prefer donSigner for new flows.
     */
    function backendSigner() external view returns (address);

    /**
     * @dev Returns the DON signer address used to verify CRE quote signatures.
     */
    function donSigner() external view returns (address);
}
