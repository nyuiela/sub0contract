// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICCIPMarketReceiver
 * @notice Interface for contracts that receive CCIP cross-chain market metadata broadcasts.
 * @dev Implement this interface on destination chains (Arbitrum, Polygon) to receive
 *      market metadata from the Sub0 cross-chain-sync CRE workflow.
 *
 *      CCIP message format (encoded in Client.Any2EVMMessage.data):
 *        ABI-encoded: (string marketId, bytes32 questionId, string name, string outcomes, uint256 resolutionDate)
 */
interface ICCIPMarketReceiver {
    struct MarketMetadata {
        string marketId;
        bytes32 questionId;
        string name;
        string outcomes;
        uint256 resolutionDate;
    }

    /**
     * @notice Called by CCIPMarketReceiver when a market metadata message arrives from the source chain.
     * @param sourceChainSelector CCIP selector of the source chain (e.g. Ethereum Sepolia).
     * @param sender Address of the sender on the source chain.
     * @param metadata Decoded market metadata from the CCIP message.
     */
    function onMarketReceived(
        uint64 sourceChainSelector,
        address sender,
        MarketMetadata calldata metadata
    ) external;
}

/**
 * @title CCIPMarketReceiver
 * @notice Base implementation for receiving CCIP market metadata on destination chains.
 * @dev Deploy this contract on each destination chain. The cross-chain-sync CRE workflow
 *      sends CCIP messages to this contract whenever a new market is created on the source chain.
 *
 *      Storage is minimal — this contract emits events and optionally forwards to a registry.
 */
abstract contract CCIPMarketReceiver {
    address public immutable ccipRouter;
    address public immutable sourceChainSender;
    uint64 public immutable sourceChainSelector;

    mapping(bytes32 => bool) public receivedMarkets;

    event MarketMetadataReceived(
        bytes32 indexed questionId,
        string marketId,
        string name,
        uint256 resolutionDate,
        uint64 sourceChainSelector
    );

    error OnlyCCIPRouter();
    error InvalidSourceChain();
    error InvalidSourceSender();
    error MarketAlreadyReceived(bytes32 questionId);

    constructor(
        address _ccipRouter,
        address _sourceChainSender,
        uint64 _sourceChainSelector
    ) {
        ccipRouter = _ccipRouter;
        sourceChainSender = _sourceChainSender;
        sourceChainSelector = _sourceChainSelector;
    }

    /**
     * @notice Entry point called by CCIP router when a message arrives.
     * @dev Implements IAny2EVMMessageReceiver.ccipReceive.
     */
    function ccipReceive(
        bytes32 messageId,
        uint64 _sourceChainSelector,
        bytes memory _sender,
        bytes memory data,
        address[] memory tokenAmounts,
        uint256[] memory amounts
    ) external {
        if (msg.sender != ccipRouter) revert OnlyCCIPRouter();
        if (_sourceChainSelector != sourceChainSelector) revert InvalidSourceChain();

        address sender;
        assembly {
            sender := mload(add(_sender, 20))
        }
        if (sender != sourceChainSender) revert InvalidSourceSender();

        (
            string memory marketId,
            bytes32 questionId,
            string memory name,
            string memory outcomes,
            uint256 resolutionDate
        ) = abi.decode(data, (string, bytes32, string, string, uint256));

        if (receivedMarkets[questionId]) revert MarketAlreadyReceived(questionId);
        receivedMarkets[questionId] = true;

        emit MarketMetadataReceived(questionId, marketId, name, resolutionDate, _sourceChainSelector);

        _handleMarketReceived(messageId, _sourceChainSelector, sender, ICCIPMarketReceiver.MarketMetadata({
            marketId: marketId,
            questionId: questionId,
            name: name,
            outcomes: outcomes,
            resolutionDate: resolutionDate
        }));
    }

    /**
     * @notice Override to handle the received market metadata (e.g. store in local registry).
     */
    function _handleMarketReceived(
        bytes32 messageId,
        uint64 sourceSelector,
        address sender,
        ICCIPMarketReceiver.MarketMetadata memory metadata
    ) internal virtual;
}
