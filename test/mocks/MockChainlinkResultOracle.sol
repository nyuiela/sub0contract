// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Oracle} from "../../src/oracle/oracle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MockChainlinkResultOracle
 * @notice Mock implementation of ChainlinkResultOracle for testing purposes
 * @dev Allows tests to manually control request fulfillments without needing actual Chainlink Functions.
 *      This mock simulates the Chainlink Functions request/response cycle by allowing tests to manually
 *      trigger fulfillments with success or failure responses.
 *
 * @notice Usage in tests:
 *  1. Deploy the mock with an Oracle contract address
 *  2. Add the mock as an allowed reporter: oracle.allowListReporter(address(mock), true)
 *  3. Call requestResultWithChainlink() to create a request
 *  4. Use fulfillRequest() to manually fulfill with a result index
 *  5. Use failRequest() to manually fail a request with an error message
 */
contract MockChainlinkResultOracle is Ownable {
    using Strings for address;

    /// @notice Reference to the Oracle contract for fulfilling results.
    Oracle public resultOracle;

    /// @notice Chainlink Functions subscription ID (mock).
    uint64 public subscriptionId;

    /// @notice DON ID for Chainlink Functions (mock).
    bytes32 public donId;

    /// @notice Gas limit for the fulfillment callback (mock).
    uint32 public callbackGasLimit;

    /// @notice JavaScript source code for Chainlink Functions execution (mock).
    string public sourceCode;

    /// @notice Mapping from request ID to internal request ID.
    mapping(bytes32 => bytes32) private _chainlinkRequestToInternalRequest;

    /// @notice Mapping from request ID to game and bet IDs.
    mapping(bytes32 => GameBetInfo) private _requestInfo;

    /// @notice Counter for generating unique request IDs.
    uint256 private _requestCounter;

    struct GameBetInfo {
        address game;
        bytes32 questionId;
        address requester;
    }

    event ChainlinkRequestSent(
        bytes32 indexed chainlinkRequestId, bytes32 indexed internalRequestId, address game, bytes32 questionId
    );
    event ChainlinkRequestFulfilled(
        bytes32 indexed chainlinkRequestId, bytes32 indexed internalRequestId, uint256[] resultIndex
    );
    event ChainlinkRequestFailed(bytes32 indexed chainlinkRequestId, bytes32 indexed internalRequestId, string reason);
    event SourceCodeUpdated(string newSourceCode);
    event SubscriptionIdUpdated(uint64 newSubscriptionId);
    event DonIdUpdated(bytes32 newDonId);
    event CallbackGasLimitUpdated(uint32 newCallbackGasLimit);

    error ResultOracleNotSet();
    error InvalidResultOracle(address oracle);
    error InvalidSubscriptionId();
    error InvalidDonId();
    error InvalidCallbackGasLimit();
    error RequestNotFound(bytes32 chainlinkRequestId);

    /**
     * @notice Constructor for MockChainlinkResultOracle.
     * @param initialOwner Owner of the contract.
     * @param _resultOracle Address of the Oracle contract.
     * @param _subscriptionId Mock subscription ID.
     * @param _donId Mock DON ID.
     * @param _callbackGasLimit Mock callback gas limit.
     * @param _sourceCode Mock source code.
     */
    constructor(
        address initialOwner,
        address _resultOracle,
        uint64 _subscriptionId,
        bytes32 _donId,
        uint32 _callbackGasLimit,
        string memory _sourceCode
    ) Ownable(initialOwner) {
        if (_resultOracle == address(0)) revert InvalidResultOracle(_resultOracle);
        if (_subscriptionId == 0) revert InvalidSubscriptionId();
        if (_donId == bytes32(0)) revert InvalidDonId();
        if (_callbackGasLimit == 0) revert InvalidCallbackGasLimit();

        resultOracle = Oracle(_resultOracle);
        subscriptionId = _subscriptionId;
        donId = _donId;
        callbackGasLimit = _callbackGasLimit;
        sourceCode = _sourceCode;
    }

    /**
     * @notice Requests a bet result (mock implementation).
     * @param _game Identifier of the game.
     * @param questionId Identifier of the question.
     * @param params Additional parameters (unused in mock).
     * @return chainlinkRequestId The mock request ID.
     */
    function requestResultWithChainlink(address _game, bytes32 questionId, bytes calldata params)
        external
        returns (bytes32 chainlinkRequestId)
    {
        if (address(resultOracle) == address(0)) revert ResultOracleNotSet();

        // Create a request in the Oracle to track it
        bytes32 internalRequestId = resultOracle.requestResult(_game, questionId, params);

        // Generate a mock Chainlink request ID
        _requestCounter++;
        chainlinkRequestId = keccak256(abi.encodePacked(block.timestamp, block.number, _requestCounter, msg.sender));

        // Store the mapping
        _chainlinkRequestToInternalRequest[chainlinkRequestId] = internalRequestId;
        _requestInfo[chainlinkRequestId] = GameBetInfo({game: _game, questionId: questionId, requester: msg.sender});

        emit ChainlinkRequestSent(chainlinkRequestId, internalRequestId, _game, questionId);
    }

    /**
     * @notice Manually fulfill a request with a successful result (for testing).
     * @param chainlinkRequestId The Chainlink request ID to fulfill.
     * @param resultIndex The result index to fulfill with.
     */
    function fulfillRequest(bytes32 chainlinkRequestId, uint256[] calldata resultIndex) external {
        bytes32 internalRequestId = _chainlinkRequestToInternalRequest[chainlinkRequestId];
        if (internalRequestId == bytes32(0)) {
            revert RequestNotFound(chainlinkRequestId);
        }

        GameBetInfo memory info = _requestInfo[chainlinkRequestId];

        // Encode the result as bytes (simulating Chainlink response)
        // bytes memory response = abi.encode(resultIndex, (uint256[]));
        bytes memory response = abi.encode(resultIndex);

        // Fulfill the result in Oracle (do not create a new request; use existing one)
        resultOracle.fulfillResult(info.questionId, resultIndex, response);

        emit ChainlinkRequestFulfilled(chainlinkRequestId, internalRequestId, resultIndex);

        // Clean up mappings
        delete _chainlinkRequestToInternalRequest[chainlinkRequestId];
        delete _requestInfo[chainlinkRequestId];
    }

    /**
     * @notice Manually fail a request (for testing).
     * @param chainlinkRequestId The Chainlink request ID to fail.
     * @param reason The reason for failure.
     */
    function failRequest(bytes32 chainlinkRequestId, string calldata reason) external {
        bytes32 internalRequestId = _chainlinkRequestToInternalRequest[chainlinkRequestId];
        if (internalRequestId == bytes32(0)) {
            revert RequestNotFound(chainlinkRequestId);
        }

        // Fail the request in Oracle using the internal request ID
        resultOracle.failRequest(internalRequestId, reason);

        emit ChainlinkRequestFailed(chainlinkRequestId, internalRequestId, reason);

        // Clean up mappings
        delete _chainlinkRequestToInternalRequest[chainlinkRequestId];
        delete _requestInfo[chainlinkRequestId];
    }

    /**
     * @notice Updates the JavaScript source code for Chainlink Functions.
     * @param newSourceCode The new source code.
     */
    function updateSourceCode(string memory newSourceCode) external onlyOwner {
        sourceCode = newSourceCode;
        emit SourceCodeUpdated(newSourceCode);
    }

    /**
     * @notice Updates the subscription ID.
     * @param newSubscriptionId The new subscription ID.
     */
    function updateSubscriptionId(uint64 newSubscriptionId) external onlyOwner {
        if (newSubscriptionId == 0) revert InvalidSubscriptionId();
        subscriptionId = newSubscriptionId;
        emit SubscriptionIdUpdated(newSubscriptionId);
    }

    /**
     * @notice Updates the DON ID.
     * @param newDonId The new DON ID.
     */
    function updateDonId(bytes32 newDonId) external onlyOwner {
        if (newDonId == bytes32(0)) revert InvalidDonId();
        donId = newDonId;
        emit DonIdUpdated(newDonId);
    }

    /**
     * @notice Updates the callback gas limit.
     * @param newCallbackGasLimit The new callback gas limit.
     */
    function updateCallbackGasLimit(uint32 newCallbackGasLimit) external onlyOwner {
        if (newCallbackGasLimit == 0) revert InvalidCallbackGasLimit();
        callbackGasLimit = newCallbackGasLimit;
        emit CallbackGasLimitUpdated(newCallbackGasLimit);
    }

    /**
     * @notice Updates the Oracle contract address.
     * @param newResultOracle The new Oracle address.
     */
    function updateResultOracle(address newResultOracle) external onlyOwner {
        if (newResultOracle == address(0)) revert InvalidResultOracle(newResultOracle);
        resultOracle = Oracle(newResultOracle);
    }

    /**
     * @notice Gets the internal request ID for a Chainlink request ID.
     * @param chainlinkRequestId The Chainlink Functions request ID.
     * @return The internal request ID.
     */
    function getInternalRequestId(bytes32 chainlinkRequestId) external view returns (bytes32) {
        return _chainlinkRequestToInternalRequest[chainlinkRequestId];
    }

    /**
     * @notice Gets the game and bet info for a Chainlink request ID.
     * @param chainlinkRequestId The Chainlink Functions request ID.
     * @return The game and bet information.
     */
    function getRequestInfo(bytes32 chainlinkRequestId) external view returns (GameBetInfo memory) {
        return _requestInfo[chainlinkRequestId];
    }
}
