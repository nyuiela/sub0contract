// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IConditionalTokens} from "../conditional/IConditionalTokens.sol";
import {InvitationManager} from "../manager/InvitationManager.sol";
import {ITokensManager} from "../interfaces/ITokensManager.sol";
import {IHub} from "../interfaces/IHub.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Game is Initializable, OwnableUpgradeable, InvitationManager {
    // constants
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant TOKENS = keccak256("TOKENS");

    // storage
    IConditionalTokens public conditionalTokens;
    ITokensManager public tokensManager;
    address public oracle;
    IHub public hub;
    IVault public vault;
    IERC20 public collateralToken;

    //  mappings
    mapping(bytes32 => Bet) public bets;

    struct Bet {
        string question;
        bytes32 conditionId;
        uint256 outcomeSlotCount;
        address oracle;
        uint256[] partition;
        address owner;
        uint256 createdAt;
        uint256 betDuration;
        InvitationManager.InvitationType betType;
    }
    // modifiers

    modifier onlyValidBet(Bet memory bet) {
        // require(bet.question != bytes32(0), InvalidQuestion(bet.question));
        require(bet.outcomeSlotCount > 0, InvalidOutcomeSlotCount(bet.outcomeSlotCount));
        require(bet.betDuration > 0, InvalidBetDuration(bet.betDuration));
        require(bet.outcomeSlotCount >= 2 && bet.outcomeSlotCount <= 255, InvalidOutcomeSlotCount(bet.outcomeSlotCount));
        _;
    }
    //m

    modifier onlyValidStake(bytes32 _questionId, address _token, uint256 amount) {
        require(_questionId != bytes32(0), InvalidQuestionId(_questionId));
        require(_token != address(0), ZeroAddress());
        require(tokensManager.allowedTokens(_token), TokenNotAllowedListed(_token));
        _;
    }

    // errors
    // error InvalidQuestionId(bytes32 questionId);
    error InvalidQuestion(string question);
    error InvalidOutcomeSlotCount(uint256 outcomeSlotCount);
    error InvalidBetDuration(uint256 betDuration);
    error InvalidPrivateBet(bool privateBet);
    error BetAlreadyExists(bytes32 conditionId);
    error ZeroAddress();
    error TokenNotAllowedListed(address token);
    error InvalidTokenDecimal(address token);
    error OracleNotAllowed(address oracle);
    error InvalidOptionIndex(uint256 optionIndex);
    error QuestionAlreadyExists(bytes32 questionId);

    // events
    event BetCreated(
        bytes32 conditionId,
        string question,
        uint256 outcomeSlotCount,
        InvitationManager.InvitationType betType,
        address owner
    );

    function initialize(
        address _tokensManager,
        address _conditionalTokens,
        address _hub,
        address _vault,
        address _collateralToken
    ) public initializer {
        require(_conditionalTokens != address(0), ZeroAddress());
        require(_vault != address(0), ZeroAddress());
        require(_tokensManager != address(0), ZeroAddress());
        __Ownable_init(msg.sender);
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        tokensManager = ITokensManager(_tokensManager);
        hub = IHub(_hub);
        vault = IVault(_vault);
        collateralToken = IERC20(_collateralToken);
    }

    function createBet(Bet memory bet) public onlyValidBet(bet) returns (bytes32) {
        // authenticate the oracle
        bytes32 questionId = keccak256(abi.encodePacked(bet.question, msg.sender, bet.oracle));
        require(bets[questionId].owner == address(0), QuestionAlreadyExists(questionId));

        // validate the oracle
        require(hub.isAllowed(bet.oracle, ORACLE), OracleNotAllowed(bet.oracle));

        // prepare the condition
        conditionalTokens.prepareCondition(bet.oracle, questionId, bet.outcomeSlotCount); // faulty
        bytes32 conditionId = conditionalTokens.getConditionId(bet.oracle, questionId, bet.outcomeSlotCount); // faulty
        bets[questionId] = bet;
        bets[questionId].conditionId = conditionId;
        bets[questionId].owner = msg.sender;
        bets[questionId].createdAt = block.timestamp;
        createInvitation(questionId, msg.sender, bet.betType); // faulty
        emit BetCreated(questionId, bet.question, bet.outcomeSlotCount, bet.betType, bet.owner);
        return questionId;
    }

    function stake(bytes32 questionId, address token, uint256 amount, uint256 optionIndex)
        public
        onlyValidStake(questionId, token, amount)
    {
        // validate the token
        // require(tokensManager.allowedTokens(token), TokenNotAllowedListed(token));
        // vault.deposit(questionId, optionIndex, token, amount, msg.sender);
        // uint256[] memory partition = new uint256[](bets[questionId].outcomeSlotCount);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), bets[questionId].conditionId, bets[questionId].partition, amount
        );
    }

    function unstake(bytes32 questionId, address token, uint256 amount, uint256 optionIndex)
        public
        onlyValidStake(questionId, token, amount)
    {
        // vault.withdraw(questionId, optionIndex, token, amount, msg.sender);
        uint256[] memory partition = new uint256[](bets[questionId].outcomeSlotCount);
        conditionalTokens.mergePositions(IERC20(token), bytes32(0), bets[questionId].conditionId, partition, amount);
    }

    function redeem(bytes32 questionId, address token, uint256 amount, uint256 optionIndex)
        public
        onlyValidStake(questionId, token, amount)
    {
        // vault.withdraw(questionId, optionIndex, token, amount, msg.sender);
        uint256[] memory partition = new uint256[](bets[questionId].outcomeSlotCount);
        conditionalTokens.redeemPositions(IERC20(token), bytes32(0), bets[questionId].conditionId, partition);
    }

    // function getBet(bytes32 conditionId) public view returns (Bet memory) {
    //   return bets[conditionId];
    // }

    // helpers

    // function getConditionId(address oracle, string memory question, uint256 outcomeSlotCount) public view returns (bytes32) {
    //   return conditionalTokens.getConditionId(oracle, question, outcomeSlotCount);
    // }

    function getBet(bytes32 questionId) public view returns (Bet memory) {
        return bets[questionId];
    }

    function getBet(bytes32 questionId, address owner, address _oracle) public view returns (Bet memory) {
        bytes32 id = keccak256(abi.encodePacked(questionId, owner, _oracle));
        return bets[id];
    }
}
