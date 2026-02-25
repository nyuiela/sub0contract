// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";
import {TokensManager} from "./TokenManager.sol";
import {IConditionalTokensV2} from "../conditional/IConditionalTokensV2.sol";
import {CTHelpersV2} from "../conditional/CTHelpersV2.sol";
import {
    AggregatorV3Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title Vault
 * @notice Vault implementation using conditional tokens for position tracking
 * @dev Integrates with ConditionalTokensV2 to manage user stakes as ERC1155 positions
 *      Each bet option becomes a conditional token position, enabling composability
 *      Backward compatible with simple deposit/withdraw for existing tests
 */
contract Vault is IVault, Initializable, IERC1155Receiver {
    // constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    uint256 public constant MAX_BPS = 10000; // 100%
    uint256 public constant MAX_PLATFORM_FEE = 1000; // Max fee cap 10%

    // Core dependencies
    ITokensManager public tokenManager;
    IPermissionManager public permissionManager;
    IConditionalTokensV2 public conditionalTokens;

    // Fee Configuration
    address public feeCollector;
    uint256 public platformFeeBps; // 500 = 5%
    address public payoutToken;

    // Mappings
    mapping(bytes32 => uint256) public gameVaultBalance; // questionId => total balance
    mapping(bytes32 => bool) public isWithdrawn; // questionId + owner + game => withdrawn
    mapping(bytes32 => bytes32) public questionConditionId; // questionId + game => conditionId
    mapping(bytes32 => uint256) public questionOutcomeCount; // questionId + game => outcome count
    mapping(bytes32 => address) public questionOracle; // questionId + game => oracle address
    mapping(bytes32 => address) public questionGame; // questionId + game => game address
    uint256 public accumulatedFees;
    mapping(address => uint256) public heartbeats;

    // Events
    event ConditionPrepared(bytes32 indexed questionId, bytes32 indexed conditionId, uint256 outcomeCount);
    event PositionCreated(
        bytes32 indexed questionId,
        address indexed user,
        uint256 indexed optionIndex,
        uint256 positionId,
        uint256 amount
    );

    // Custom errors
    error ConditionNotPrepared(bytes32 questionId);
    error InvalidOutcomeCount();
    error PositionNotFound();

    function initialize(Config memory _config) external initializer {
        if (_config.tokenManager == address(0)) revert ZeroAddress();
        if (_config.permissionManager == address(0)) revert ZeroAddress();
        tokenManager = ITokensManager(_config.tokenManager);
        permissionManager = IPermissionManager(_config.permissionManager);
    }

    /**
     * @notice Set the conditional tokens contract
     * @param _conditionalTokens Address of ConditionalTokensV2 contract
     */
    function setConditionalTokens(address _conditionalTokens) external onlyAuthorized(DEFAULT_ADMIN_ROLE) {
        if (_conditionalTokens == address(0)) revert ZeroAddress();
        conditionalTokens = IConditionalTokensV2(_conditionalTokens);
    }

    /**
     * @notice Prepare a condition for a question (must be called before first deposit)
     * @dev Includes game address in condition ID to prevent collisions across games
     * @param questionId The question identifier
     * @param outcomeCount Number of possible outcomes (options)
     */
    function prepareCondition(bytes32 questionId, uint256 outcomeCount)
        external
        onlyAuthorized(GAME_CONTRACT_ROLE)
        returns (bytes32)
    {
        require(address(conditionalTokens) != address(0), "Conditional tokens not set");
        if (outcomeCount < 2 || outcomeCount > 256) revert InvalidOutcomeCount();

        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        require(questionConditionId[questionGameKey] == bytes32(0), "Condition already prepared");

        // Vault is the oracle so it can call reportPayouts later; conditionId = getConditionId(vault, questionId, outcomeCount)
        conditionalTokens.prepareCondition(address(this), questionId, outcomeCount);

        bytes32 conditionId = CTHelpersV2.getConditionId(address(this), questionId, outcomeCount);

        questionConditionId[questionGameKey] = conditionId;
        questionOutcomeCount[questionGameKey] = outcomeCount;
        questionOracle[questionGameKey] = address(this);
        questionGame[questionGameKey] = msg.sender;

        emit ConditionPrepared(questionId, conditionId, outcomeCount);
        return conditionId;
    }

    /**
     * @notice Resolve a condition by reporting payouts (oracle only)
     * @param questionId The question identifier
     * @param payouts Array of payout numerators for each outcome
     */
    function resolveCondition(bytes32 questionId, uint256[] calldata payouts)
        external
        onlyAuthorized(GAME_CONTRACT_ROLE)
    {
        require(address(conditionalTokens) != address(0), "Conditional tokens not set");

        // Get condition info using msg.sender as the game address
        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        bytes32 conditionId = questionConditionId[questionGameKey];
        require(conditionId != bytes32(0), "Condition not found");

        uint256 outcomeCount = questionOutcomeCount[questionGameKey];
        require(payouts.length == outcomeCount, "Invalid payouts length");

        // Vault is the oracle; reportPayouts uses getConditionId(msg.sender, questionId, outcomeCount)
        conditionalTokens.reportPayouts(questionId, payouts);
    }

    /**
     * @notice Deposit tokens (compatible with IVault interface)
     * @dev For conditional tokens, use depositWithOption instead
     */
    // function deposit(
    //     bytes32 questionId,
    //     address token,
    //     uint256 amount,
    //     address owner
    // ) external onlyAuthorized(GAME_CONTRACT_ROLE) {
    //     // For backward compatibility, this just stores the balance
    //     // Use depositWithOption for conditional token positions
    //     (bool success,) = tokenManager.getDecimal(token);
    //     if (!success) revert TokenNotAllowedListed(token);

    //     uint256 convertedValue = calculateValue(token, amount);
    //     IERC20(token).transferFrom(owner, address(this), amount);

    //     bytes32 id = keccak256(abi.encodePacked(questionId, msg.sender));
    //     gameVaultBalance[id] += convertedValue;
    //     emit Deposit(owner, token, amount, convertedValue);
    // }

    /**
     * @notice Deposit tokens and create conditional token positions
     * @param questionId The question identifier
     * @param token The collateral token address
     * @param amount The amount to deposit
     * @param owner The owner of the tokens
     * @param optionIndex The option index to stake on (0-indexed)
     */
    function deposit(bytes32 questionId, address token, uint256 amount, address owner, uint256 optionIndex)
        external
        onlyAuthorized(GAME_CONTRACT_ROLE)
    {
        require(address(conditionalTokens) != address(0), "Conditional tokens not set");

        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        bytes32 conditionId = questionConditionId[questionGameKey];
        if (conditionId == bytes32(0)) revert ConditionNotPrepared(questionId);

        // Validation
        (bool success,) = tokenManager.getDecimal(token);
        if (!success) revert TokenNotAllowedListed(token);

        uint256 outcomeCount = questionOutcomeCount[questionGameKey];
        require(optionIndex < outcomeCount, "Invalid option index");

        uint256 convertedValue = calculateValue(token, amount);

        // Transfer tokens from owner to vault
        IERC20(token).transferFrom(owner, address(this), amount);

        // Create partition for the specific option
        // For option 0, indexSet = 1 (0b001)
        // For option 1, indexSet = 2 (0b010)
        // For option 2, indexSet = 4 (0b100)
        uint256 indexSet = 1 << optionIndex;
        uint256[] memory partition = new uint256[](2);

        // Create partition: one set for the chosen option, rest for other options
        partition[0] = indexSet; // Chosen option
        uint256 otherOptions = ((1 << outcomeCount) - 1) ^ indexSet; // All other options
        partition[1] = otherOptions;

        // Split collateral into conditional tokens
        // This creates positions for the chosen option and all other options
        IERC20(token).approve(address(conditionalTokens), amount);

        conditionalTokens.splitPosition(
            IERC20(token),
            bytes32(0), // Root collection
            conditionId, // Use stored conditionId
            partition,
            amount
        );

        // Calculate position IDs using stored condition ID
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(token), collectionId);

        // Transfer the chosen option position to the user
        conditionalTokens.safeTransferFrom(address(this), owner, positionId, amount, "");

        // Track balances
        gameVaultBalance[questionId] += convertedValue;

        emit Deposit(owner, token, amount, convertedValue);
        emit PositionCreated(questionId, owner, optionIndex, positionId, amount);
    }

    /**
     * @notice Withdraw tokens (compatible with IVault interface)
     * @dev For conditional tokens, use withdrawWithOption instead
     */
    // function withdraw(
    //     bytes32 questionId,
    //     address owner,
    //     uint256 _amount
    // ) external onlyAuthorized(GAME_CONTRACT_ROLE) {
    //     bytes32 id = keccak256(abi.encodePacked(questionId, owner, msg.sender));
    //     require(!isWithdrawn[id], AlreadyWithdrawn(id));
    //     id = keccak256(abi.encodePacked(questionId, msg.sender));
    //     if (gameVaultBalance[id] < _amount) revert InsufficientBalance(_amount);
    //     gameVaultBalance[id] -= _amount;
    //     isWithdrawn[id] = true;

    //     uint256 feeAmount = (_amount * platformFeeBps) / MAX_BPS;
    //     uint256 netAmount = _amount - feeAmount;
    //     accumulatedFees += feeAmount;
    //     IERC20(payoutToken).transfer(owner, netAmount);
    //     emit Withdrawal(owner, questionId, msg.sender, netAmount);
    // }

    /**
     * @notice Withdraw/redeem winning positions after condition resolution
     * @param questionId The question identifier
     * @param owner The owner of the positions
     * @param optionIndex The winning option index
     */
    function withdraw(bytes32 questionId, address owner, uint256 optionIndex)
        external
        onlyAuthorized(GAME_CONTRACT_ROLE)
    {
        require(address(conditionalTokens) != address(0), "Conditional tokens not set");
        if (isWithdrawn[questionId]) revert AlreadyWithdrawn(questionId);

        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        bytes32 conditionId = questionConditionId[questionGameKey];
        if (conditionId == bytes32(0)) revert ConditionNotPrepared(questionId);

        // Check if condition is resolved
        uint256 denominator = conditionalTokens.payoutDenominator(conditionId);
        require(denominator > 0, "Condition not resolved");

        uint256 outcomeCount = questionOutcomeCount[questionGameKey];
        require(optionIndex < outcomeCount, "Invalid option index");

        // Calculate position ID for the winning option
        uint256 indexSet = 1 << optionIndex;
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        address token = payoutToken; // Use payout token for redemption
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(token), collectionId);

        // Get user's position balance
        uint256 positionBalance = conditionalTokens.balanceOf(owner, positionId);
        if (positionBalance == 0) revert PositionNotFound();

        // Calculate expected payout before redemption
        uint256[] memory numerators = conditionalTokens.payoutNumerators(conditionId);
        uint256 payoutNumerator = 0;
        for (uint256 j = 0; j < outcomeCount;) {
            if (indexSet & (1 << j) != 0) {
                unchecked {
                    payoutNumerator += numerators[j];
                }
            }
            unchecked {
                ++j;
            }
        }

        // Calculate the actual payout amount for this user's position
        uint256 expectedPayout = (positionBalance * payoutNumerator) / denominator;

        // User redeems their own positions (they call redeemPositions themselves)
        // Or we can do it on their behalf if they approve
        // For now, we'll require the user to have approved the vault
        conditionalTokens.safeTransferFrom(owner, address(this), positionId, positionBalance, "");

        // Get balance before redemption to calculate actual payout
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        // Redeem winning positions (now owned by vault)
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = indexSet;

        conditionalTokens.redeemPositions(
            IERC20(token),
            bytes32(0), // Root collection
            conditionId, // Use stored conditionId
            indexSets
        );

        // Calculate actual payout received (difference in balance)
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualPayout = balanceAfter - balanceBefore;

        // Ensure we got the expected amount (with small tolerance for rounding)
        require(actualPayout >= expectedPayout - 1, "Payout mismatch");

        // Calculate fee on the actual payout amount
        uint256 feeAmount = (actualPayout * platformFeeBps) / MAX_BPS;
        uint256 netAmount = actualPayout - feeAmount;

        accumulatedFees += feeAmount;
        isWithdrawn[questionId] = true;

        IERC20(token).transfer(owner, netAmount);

        emit Withdrawal(owner, questionId, msg.sender, netAmount);
    }

    /**
     * @notice Get user's position balance for a specific option
     * @param questionId The question identifier
     * @param owner The owner address
     * @param optionIndex The option index
     * @param token The collateral token address
     * @return The position balance
     */
    function getPositionBalance(bytes32 questionId, address owner, uint256 optionIndex, address token)
        external
        view
        returns (uint256)
    {
        if (address(conditionalTokens) == address(0)) return 0;
        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        bytes32 conditionId = questionConditionId[questionGameKey];
        if (conditionId == bytes32(0)) return 0;

        uint256 indexSet = 1 << optionIndex;
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(token), collectionId);

        return conditionalTokens.balanceOf(owner, positionId);
    }

    /**
     * @notice Get total balance for a question (all options)
     * @param questionId The question identifier
     * @param token The collateral token address
     * @return The total balance across all positions
     */
    function getTotalBalance(bytes32 questionId, address token) external view returns (uint256) {
        if (address(conditionalTokens) == address(0)) return 0;
        bytes32 questionGameKey = keccak256(abi.encodePacked(questionId, msg.sender));
        bytes32 conditionId = questionConditionId[questionGameKey];
        if (conditionId == bytes32(0)) return 0;

        uint256 outcomeCount = questionOutcomeCount[questionGameKey];
        uint256 total = 0;

        for (uint256 i = 0; i < outcomeCount;) {
            uint256 indexSet = 1 << i;
            CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
            // Note: positionId from collectionId kept for potential future use

            // Sum all balances for this position ID (across all users)
            // Note: This is a simplified version - in production you might want to track this differently
            total += IERC20(token).balanceOf(address(conditionalTokens));

            unchecked {
                ++i;
            }
        }

        return total;
    }

    function balanceOf(bytes32 questionId) external view returns (uint256) {
        return gameVaultBalance[questionId];
    }

    function getChainlinkDataFeedLatestAnswer(address token) public view returns (int256) {
        address _priceFeed = tokenManager.getPriceFeed(token);

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(_priceFeed).latestRoundData();

        if (answer <= 0) revert NegativePrice();
        if (updatedAt == 0) revert UpdatedAtIsZero();
        if (answeredInRound < roundId) revert StaleRound();

        uint256 heartbeat = heartbeats[token];
        if (heartbeat == 0) heartbeat = 24 hours;

        if (block.timestamp - updatedAt > heartbeat + 60 seconds) {
            revert StalePrice();
        }

        return answer;
    }

    function convertPrice(address token, uint256 amount) public view returns (uint256) {
        address _priceFeed = tokenManager.getPriceFeed(token);
        if (_priceFeed == address(0)) revert ZeroAddress();
        return amount * uint256(getChainlinkDataFeedLatestAnswer(_priceFeed));
    }

    function calculateValue(address _tokenIn, uint256 _amountIn) public view returns (uint256) {
        address _priceFeed = tokenManager.getPriceFeed(_tokenIn);
        if (_priceFeed == address(0)) revert ZeroAddress();

        // Get token decimals from tokenManager's public mapping
        // Cast to concrete type to access public mapping
        uint8 decimalsIn = TokensManager(address(tokenManager)).decimals(_tokenIn);
        // If decimals is 0 (not set in tokenManager), default to 18
        // Note: This assumes 0 means "not set" rather than "token has 0 decimals"
        // If a token truly has 0 decimals, it should be explicitly set to 0 in tokenManager
        if (decimalsIn == 0) {
            decimalsIn = 18; // Default to 18 decimals
        }

        uint8 decimalsOut = 6; // USDC base

        (, int256 price,,,) = AggregatorV3Interface(_priceFeed).latestRoundData();
        uint256 unsignedPrice = uint256(price);
        uint8 priceDecimals = AggregatorV3Interface(_priceFeed).decimals();

        uint256 numerator = _amountIn * unsignedPrice;
        uint256 decimalsNumerator = decimalsIn + priceDecimals;
        uint256 decimalsDenominator = decimalsOut;

        if (decimalsNumerator > decimalsDenominator) {
            uint256 shift = decimalsNumerator - decimalsDenominator;
            return numerator / (10 ** shift);
        } else {
            uint256 shift = decimalsDenominator - decimalsNumerator;
            return numerator * (10 ** shift);
        }
    }

    function setConfig(Config memory _config) external onlyAuthorized(DEFAULT_ADMIN_ROLE) {
        tokenManager = ITokensManager(_config.tokenManager);
        permissionManager = IPermissionManager(_config.permissionManager);
        emit ConfigSet(_config.tokenManager, _config.permissionManager);
    }

    function setFeeConfig(address _feeCollector, uint256 _feeBps) external onlyAuthorized(DEFAULT_ADMIN_ROLE) {
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_PLATFORM_FEE) revert InvalidFee(_feeBps);

        feeCollector = _feeCollector;
        platformFeeBps = _feeBps;
        emit FeeConfigUpdated(_feeCollector, _feeBps);
    }

    function claimFees() external {
        uint256 amount = accumulatedFees;
        require(amount > 0, "No fees to claim");

        accumulatedFees = 0;
        IERC20(payoutToken).transfer(feeCollector, amount);

        emit FeesCollected(payoutToken, amount);
    }

    function setPayoutToken(address _t) public onlyAuthorized(DEFAULT_ADMIN_ROLE) {
        payoutToken = _t;
    }

    // Modifiers
    modifier onlyAuthorized(bytes32 role) {
        if (!permissionManager.hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
        _;
    }

    /**
     * @notice ERC1155 receiver implementation
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    receive() external payable {}
    fallback() external payable {}
}
