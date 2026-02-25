// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    // errors
    error ReporterNotSet();
    error UnauthorizedReporter(address caller);
    error RequestNotPending(bytes32 requestId);
    error RequestAlreadyExists(bytes32 betKey);
    error RequestUnknown(bytes32 requestId);
    error InvalidStatusTransition(RequestStatus current, RequestStatus attempted);
    error UnauthorizedCanceller(address caller);
    error ReporterAlreadyAllowed(address reporter);
    error InvalidReporter(address reporter);
    error ReporterNotAllowed(address reporter);
    error NotAuthorized(address account, bytes32 role);
    error InvalidOptionIndex(uint256 optionIndex);
    error ResultAlreadyFulfilled(bytes32 betKey);
    error RequestNotFound(bytes32 betKey);

    // events
    event ReporterUpdated(address indexed newReporter);
    event ResultRequested(
        bytes32 indexed requestId, address indexed game, bytes32 indexed betId, address requester, bytes params
    );
    event ResultFulfilled(
        bytes32 indexed requestId,
        bytes32 indexed betKey,
        uint256 resultIndex,
        address reporter,
        bytes supplementaryData
    );
    event ResultFailed(bytes32 indexed requestId, bytes32 indexed betKey, address reporter, string reason);
    event ResultCancelled(bytes32 indexed requestId, bytes32 indexed betKey, address cancelledBy, string reason);
    event ReporterAllowed(address indexed reporter);
    event ReporterRemoved(address indexed reporter);

    // enums
    enum RequestStatus {
        None,
        Pending,
        Fulfilled,
        Failed,
        Cancelled
    }

    // structs
    struct BetResult {
        RequestStatus status;
        uint256 resultIndex;
        address reporter;
        uint256 updatedAt;
        bytes supplementaryData;
    }

    struct BetRequest {
        bytes32 requestId;
        address game;
        bytes32 betId;
        address requester;
        uint256 createdAt;
        RequestStatus status;
        bytes params;
    }

    // functions
    /// @notice Emits a new bet result request for off-chain processing
    /// @param game Identifier of the game within the hub
    /// @param betId Identifier of the bet within the game
    /// @param params Arbitrary payload forwarded to off-chain processors (e.g. API hints, match metadata)
    /// @return requestId Unique identifier representing this request
    function requestResult(address game, bytes32 betId, bytes calldata params) external returns (bytes32 requestId);

    /// @notice Records a successful fulfilment from the reporter
    /// @param game Game address
    /// @param betId Bet identifier within the game
    /// @param resultIndex Final index of the winning option
    /// @param supplementaryData Optional metadata (serialized proof, raw feed, etc)
    function fulfillResult(address game, bytes32 betId, uint256 resultIndex, bytes calldata supplementaryData) external;

    /// @notice Marks a request as failed if the reporter cannot determine an outcome (by game and betId)
    /// @param game Game address
    /// @param betId Bet identifier within the game
    /// @param reason Human readable explanation stored on-chain
    function failRequest(address game, uint256 betId, string calldata reason) external;

    /// @notice Marks a request as failed if the reporter cannot determine an outcome (by requestId)
    /// @param requestId Identifier of the request
    /// @param reason Human readable explanation stored on-chain
    function failRequest(bytes32 requestId, string calldata reason) external;

    /// @notice Cancels a pending request (e.g., if the bet was withdrawn)
    /// @param requestId Identifier of the request
    /// @param reason Optional note explaining the cancellation
    function cancelRequest(bytes32 requestId, string calldata reason) external;

    /// @notice Retrieves a stored request by id
    /// @param requestId The request identifier
    /// @return The request details
    function getRequest(bytes32 requestId) external view returns (BetRequest memory);

    /// @notice Retrieves a stored request by game and betId
    /// @param game Game address
    /// @param betId Bet identifier within the game
    /// @return The request details
    function getRequest(address game, uint256 betId) external view returns (BetRequest memory);

    /// @notice Fetches the latest result stored for a specific bet
    /// @param game Game address
    /// @param betId Bet identifier within the game
    /// @return The bet result details
    function getBetResult(address game, uint256 betId) external view returns (BetResult memory);

    /// @notice Returns the active request id for a bet, if any
    /// @param _game Game address
    /// @param betId Bet identifier within the game
    /// @return The active request id, or bytes32(0) if none exists
    function getActiveRequestId(address _game, uint256 betId) external view returns (bytes32);

    /// @notice Checks if an oracle/reporter is allowed
    /// @param oracle The oracle/reporter address to check
    /// @return True if the oracle is allowed, false otherwise
    function isAllowed(address oracle) external view returns (bool);

    /// @notice Allows or removes a reporter from the allow list
    /// @param _reporter The reporter address to allow or remove
    /// @param allowed True to allow, false to remove
    function allowListReporter(address _reporter, bool allowed) external;
}
