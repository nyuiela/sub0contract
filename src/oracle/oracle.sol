// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
/**
 * @title ResultOracle
 * @notice Custom oracle coordinator responsible for emitting bet result requests and recording fulfilments.
 * @dev Designed to sit between the game hub and whichever off-chain stack computes outcomes. It supports multiple
 *      games and multiple bets per game by deriving a deterministic `betKey = keccak256(gameId, betId)`. Each request
 *      is tracked through a lifecycle so integrators can handle success, failure, or cancellation flows.
 */

interface IGame {
    function resolve(bytes32 betId, uint256[] calldata payouts) external;
}

contract Oracle is Initializable, UUPSUpgradeable {
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    IPermissionManager public permissionManager;
    /// @notice Life-cycle states for a bet request.

    enum RequestStatus {
        None,
        Pending,
        Fulfilled,
        Failed,
        Cancelled
    }

    /// @notice Outcome metadata recorded once a request is fulfilled.
    struct BetResult {
        RequestStatus status;
        uint256[] result;
        address reporter;
        uint256 updatedAt;
        bytes supplementaryData;
    }

    /// @notice Data tracked for every emitted request.
    struct BetRequest {
        bytes32 requestId;
        bytes32 questionId;
        address game;
        address requester;
        uint256 createdAt;
        RequestStatus status;
        bytes params;
    }

    /// @notice Address permitted to submit fulfilments or failures.
    // address public reporter;

    /// @dev Monotonic counter used to derive unique request ids.
    uint256 private _nonce;

    /// @dev requestId => request details.
    mapping(bytes32 => BetRequest) private _requests;

    /// @dev betKey => latest bet result.
    mapping(bytes32 => BetResult) private _betResults;

    /// @dev betKey => active request id (if any).
    mapping(bytes32 => bytes32) private _activeRequestByBet;
    mapping(address => bool) private _allowedReporters;

    event ReporterUpdated(address indexed newReporter);
    event ResultRequested(bytes32 indexed requestId, bytes32 indexed questionId, address requester, bytes params);
    event ResultFulfilled(
        bytes32 indexed requestId,
        bytes32 indexed questionId,
        uint256[] payouts,
        address reporter,
        bytes supplementaryData
    );
    event ResultFailed(bytes32 indexed requestId, bytes32 indexed questionId, address reporter, string reason);
    event ResultCancelled(bytes32 indexed requestId, bytes32 indexed questionId, address cancelledBy, string reason);
    event ReporterAllowed(address indexed reporter);
    event ReporterRemoved(address indexed reporter);

    error ReporterNotSet();
    error UnauthorizedReporter(address caller);
    error RequestNotPending(bytes32 requestId);
    error RequestAlreadyExists(bytes32 questionId);
    error RequestUnknown(bytes32 requestId);
    error InvalidStatusTransition(RequestStatus current, RequestStatus attempted);
    error UnauthorizedCanceller(address caller);
    error ReporterAlreadyAllowed(address reporter);
    error InvalidReporter(address reporter);
    error ReporterNotAllowed(address reporter);
    error NotAuthorized(address account, bytes32 role);
    error InvalidOptionIndex(uint256 optionIndex);
    error ResultAlreadyFulfilled(bytes32 requestId);
    error RequestNotFound(bytes32 questionId);

    // modifiers

    modifier onlyAllowedReporter() {
        if (!_allowedReporters[msg.sender]) revert ReporterNotAllowed(msg.sender);
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    /**
     * @notice Initialises the oracle contract.
     * @param _permissionManager manage roles.
     * @param initialReporter Reporter authorised to submit results.
     */
    function initialize(address _permissionManager, address initialReporter) public initializer {
        if (initialReporter == address(0)) revert InvalidReporter(initialReporter);
        permissionManager = IPermissionManager(_permissionManager);
        _allowedReporters[initialReporter] = true;
    }

    function allowListReporter(address _reporter, bool allowed) external onlyRole(ORACLE_MANAGER_ROLE) {
        if (_reporter == address(0)) revert InvalidReporter(_reporter);
        // if (_allowedReporters[reporter] == true) revert ReporterAlreadyAllowed(reporter);
        _allowedReporters[_reporter] = allowed;
        if (allowed) emit ReporterAllowed(_reporter);
        else emit ReporterRemoved(_reporter);
    }

    /**
     * @notice Emits a new bet result request for off-chain processing.
     * @param questionId Question identifier.
     * @param game Game address.
     * @param params Arbitrary payload forwarded to off-chain processors (e.g. API hints, match metadata).
     * @return requestId Unique identifier representing this request.
     */
    function requestResult(address game, bytes32 questionId, bytes calldata params)
        public
        returns (bytes32 requestId)
    {
        // if (_activeRequestByBet[questionId] != bytes32(0)) {
        //     revert RequestAlreadyExists(questionId);
        // }

        _nonce++;
        requestId = keccak256(abi.encodePacked(block.chainid, address(this), questionId, _nonce, block.timestamp));
        BetRequest storage request = _requests[requestId];
        request.requestId = requestId;
        request.questionId = questionId;
        request.requester = msg.sender;
        request.createdAt = block.timestamp;
        request.status = RequestStatus.Pending;
        request.params = params;
        request.game = game;

        _activeRequestByBet[questionId] = requestId;

        emit ResultRequested(requestId, questionId, msg.sender, params);
        return requestId;
    }

    /**
     * @notice Records a successful fulfilment from the reporter.
     * @param questionId Question identifier.
     * @param payouts Final payouts.
     * @param supplementaryData Optional metadata (serialized proof, raw feed, etc).
     */
    function fulfillResult(bytes32 questionId, uint256[] calldata payouts, bytes calldata supplementaryData)
        external
        onlyAllowedReporter
    {
        if (payouts.length == 0 || payouts.length > 255) revert InvalidOptionIndex(payouts.length);
        bytes32 requestId = _activeRequestByBet[questionId];
        if (requestId == bytes32(0)) revert RequestNotFound(questionId);
        BetRequest storage request = _requests[requestId];

        request.status = RequestStatus.Fulfilled;
        BetResult storage result = _betResults[questionId];
        if (result.status == RequestStatus.Fulfilled) revert ResultAlreadyFulfilled(requestId);
        result.status = RequestStatus.Fulfilled;
        result.result = payouts;
        result.reporter = msg.sender;
        result.updatedAt = block.timestamp;
        result.supplementaryData = supplementaryData;

        delete _activeRequestByBet[questionId];
        IGame(request.game).resolve(questionId, payouts);

        emit ResultFulfilled(requestId, questionId, payouts, msg.sender, supplementaryData);
    }

    /**
     * @notice Marks a request as failed if the reporter cannot determine an outcome.
     * @param questionId Question identifier.
     * @param reason Human readable explanation stored on-chain.
     */
    // function failRequest(bytes32 questionId, string calldata reason) external onlyAllowedReporter {
    //     if (_activeRequestByBet[questionId] == bytes32(0)) {
    //         revert RequestNotFound(questionId);
    //     }
    //     bytes32 requestId = _activeRequestByBet[questionId];
    //     _requests[requestId].status = RequestStatus.Failed;

    //     BetResult storage result = _betResults[questionId];
    //     result.status = RequestStatus.Failed;
    //     result.result = new uint256[](0);
    //     result.reporter = msg.sender;
    //     result.updatedAt = block.timestamp;
    //     result.supplementaryData = bytes(reason);

    //     delete _activeRequestByBet[questionId];

    //     emit ResultFailed(requestId, questionId, msg.sender, reason);
    // }
    /**
     * @notice Marks a request as failed if the reporter cannot determine an outcome.
     * @param requestId Identifier of the request.
     * @param reason Human readable explanation stored on-chain.
     */
    function failRequest(bytes32 requestId, string calldata reason) external onlyAllowedReporter {
        _requests[requestId].status = RequestStatus.Failed;
        BetRequest storage request = _requests[requestId];
        BetResult storage result = _betResults[request.questionId];
        result.status = RequestStatus.Failed;
        result.result = new uint256[](0);
        result.reporter = msg.sender;
        result.updatedAt = block.timestamp;
        result.supplementaryData = bytes(reason);

        delete _activeRequestByBet[request.questionId];

        emit ResultFailed(requestId, request.questionId, msg.sender, reason);
    }

    /**
     * @notice Cancels a pending request (e.g., if the bet was withdrawn).
     * @param requestId Identifier of the request.
     * @param reason Optional note explaining the cancellation.
     */
    function cancelRequest(bytes32 requestId, string calldata reason) external {
        BetRequest storage request = _requests[requestId];
        if (request.status == RequestStatus.None) revert RequestUnknown(requestId);
        if (request.status != RequestStatus.Pending) {
            revert RequestNotPending(requestId);
        }

        request.status = RequestStatus.Cancelled;

        BetResult storage result = _betResults[request.questionId];
        result.status = RequestStatus.Cancelled;
        result.result = new uint256[](0);
        result.reporter = msg.sender;
        result.updatedAt = block.timestamp;
        result.supplementaryData = bytes(reason);

        delete _activeRequestByBet[request.questionId];

        emit ResultCancelled(requestId, request.questionId, msg.sender, reason);
    }

    /**
     * @notice Retrieves a stored request by id.
     * @param requestId Request identifier.
     * @return The request details.
     */
    // function getRequest(bytes32 requestId) external view returns (BetRequest memory) {
    //     return _requests[requestId];
    // }

    /**
     * @notice Retrieves a stored request by question id.
     * @param questionId Question identifier.
     * @return The request details.
     */
    function getRequest(bytes32 questionId) external view returns (BetRequest memory) {
        if (_activeRequestByBet[questionId] == bytes32(0)) {
            revert RequestNotFound(questionId);
        }
        bytes32 requestId = _activeRequestByBet[questionId];
        return _requests[requestId];
    }

    /**
     * @notice Fetches the latest result stored for a specific bet.
     * @param questionId Question identifier.
     */
    function getBetResult(bytes32 questionId) external view returns (BetResult memory) {
        return _betResults[questionId];
    }

    /**
     * @notice Returns the active request id for a bet, if any.
     */
    function getActiveRequestId(bytes32 questionId) external view returns (bytes32) {
        return _activeRequestByBet[questionId];
    }

    // function
    function isAllowed(address oracle) public view returns (bool) {
        return _allowedReporters[oracle];
    }

    /**
     * @dev Authorize upgrade (required by UUPSUpgradeable)
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ORACLE_MANAGER_ROLE) {}
}
