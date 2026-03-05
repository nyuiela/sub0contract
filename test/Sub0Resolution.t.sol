// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {IConditionalTokensV2} from "../src/conditional/IConditionalTokensV2.sol";
import {ConditionalTokens} from "../src/conditional/conditionalToken.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {CTHelpersV2} from "../src/conditional/CTHelpersV2.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {IHub} from "../src/interfaces/IHub.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockAggregatorV3} from "./MockAggregatorV3.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {MockChainlinkResultOracle} from "./mocks/MockChainlinkResultOracle.sol";

contract Sub0ResolutionTest is Test {
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant TOKENS = keccak256("TOKENS");

    Sub0 sub0;
    Hub hub;
    TokensManager tokensManager;
    Oracle oracleManager;
    MockChainlinkResultOracle mockChainlinkResultOracle;
    ConditionalTokens conditionalTokens;
    ConditionalTokensV2 conditionalTokensV2;
    Vault vault;
    PermissionManager permissionManager;
    ERC20Mock collateralToken;
    MockAggregatorV3 mockAggregator;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address attacker = makeAddr("attacker");
    address oracle = address(oracleManager);

    function setUp() public {
        mockAggregator = new MockAggregatorV3(6, "Mock Aggregator", 1);
        mockAggregator.setLatestAnswer(1000000);
        mockAggregator.setRoundData(1, 1000000, block.timestamp, block.timestamp, 1);

        permissionManager = new PermissionManager();
        permissionManager.initialize();
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, owner);
        conditionalTokens = new ConditionalTokens();
        conditionalTokensV2 = new ConditionalTokensV2();

        tokensManager = new TokensManager();
        tokensManager.initialize(address(permissionManager), address(conditionalTokens));
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(tokensManager));
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(this));
        permissionManager.grantRole(GAME_CONTRACT_ROLE, address(this));

        oracleManager = new Oracle();
        mockChainlinkResultOracle = new MockChainlinkResultOracle(
            address(this), address(oracleManager), uint64(1), bytes32(keccak256("donId")), uint32(1000000), "sourceCode"
        );

        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(mockChainlinkResultOracle));
        oracleManager.initialize(address(permissionManager), address(mockChainlinkResultOracle));
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(oracleManager));
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(this));
        oracleManager.allowListReporter(address(mockChainlinkResultOracle), true);
        oracleManager.allowListReporter(address(oracleManager), true);
        oracleManager.allowListReporter(address(this), true);

        vault = new Vault();
        vault.initialize(
            IVault.Config({tokenManager: address(tokensManager), permissionManager: address(permissionManager)})
        );
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, address(this));
        vault.setConditionalTokens(address(conditionalTokensV2));

        bytes32 ORACLE_ROLE = conditionalTokensV2.ORACLE_ROLE();
        conditionalTokensV2.grantRole(ORACLE_ROLE, address(vault));

        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(this));

        hub = new Hub();
        hub.initialize(address(permissionManager), address(tokensManager), address(oracleManager));

        collateralToken = new ERC20Mock();
        collateralToken.mint(address(this), 1000000 * 10 ** 18);
        collateralToken.mint(user, 1000000 * 10 ** 18);
        collateralToken.mint(user2, 1000000 * 10 ** 18);
        tokensManager.allowListToken(address(collateralToken), true);
        tokensManager.setDecimals(address(collateralToken), 18);
        tokensManager.setPriceFeed(address(collateralToken), address(mockAggregator));

        Sub0 sub0Impl = new Sub0();
        Sub0.Config memory sub0Config = Sub0.Config({
            owner: address(this),
            hub: address(hub),
            vault: address(vault),
            tokenManager: address(tokensManager),
            permissionManager: address(permissionManager),
            conditionalToken: address(conditionalTokensV2),
            predictionVault: address(0),
            creForwarder: address(1)
        });
        bytes memory sub0InitData = abi.encodeWithSelector(Sub0.initialize.selector, sub0Config);
        ERC1967Proxy sub0Proxy = new ERC1967Proxy(address(sub0Impl), sub0InitData);
        sub0 = Sub0(payable(address(sub0Proxy)));

        conditionalTokensV2.grantRole(conditionalTokensV2.GAME_CONTRACT_ROLE(), address(sub0));
        conditionalTokensV2.setPayoutToken(address(collateralToken));
        conditionalTokensV2.setFeeConfig(address(this), 500);

        permissionManager.grantRole(GAME_CREATOR_ROLE, address(this));
        hub.initializeGame("Sub0", address(sub0));
        permissionManager.grantRole(GAME_CREATOR_ROLE, address(hub));
        permissionManager.setRoleAdmin(GAME_CONTRACT_ROLE, GAME_CREATOR_ROLE);
        vm.warp(block.timestamp + 4 days);
        hub.activateGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));
        bytes32 gameContractRole = keccak256(abi.encodePacked(GAME_CONTRACT_ROLE, gameId));
        permissionManager.grantRole(gameContractRole, address(sub0));
        permissionManager.grantRole(GAME_CONTRACT_ROLE, address(sub0));

        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(this));
        permissionManager.grantRole(GAME_CONTRACT_ROLE, address(sub0));
        tokensManager.allowListToken(address(collateralToken), true);
        tokensManager.setDecimals(address(collateralToken), 18);
        oracle = address(oracleManager);
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, address(this));
        vault.setPayoutToken(address(collateralToken));
        vault.setFeeConfig(address(this), 500);
    }


    function _market(
        string memory question,
        address _oracle,
        uint256 duration,
        uint256 outcomeSlotCount,
        Sub0.OracleType oracleType,
        Sub0.MarketType marketType
    ) internal pure returns (Sub0.Market memory) {
        return Sub0.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: _oracle,
            owner: address(0),
            createdAt: 0,
            duration: duration,
            outcomeSlotCount: outcomeSlotCount,
            oracleType: oracleType,
            marketType: marketType
        });
    }

    function _stakeOption(bytes32 questionId, uint256 optionIndex, address token, uint256 amount) internal {
        uint256 outcomeSlotCount = sub0.getMarket(questionId).outcomeSlotCount;
        uint256 indexSet = 1 << optionIndex;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 otherSet = fullIndexSet ^ indexSet;
        uint256[] memory partition = new uint256[](2);
        partition[0] = indexSet;
        partition[1] = otherSet;
        sub0.stake(questionId, bytes32(0), partition, token, amount);
    }

    function testResolveBetWithTwoOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 denominator = conditionalTokensV2.payoutDenominator(conditionId);
        assertTrue(denominator > 0);
    }

    function testResolveBetWithThreeOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 3, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 1, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](3);
        payouts[0] = 0;
        payouts[1] = 1;
        payouts[2] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 denominator = conditionalTokensV2.payoutDenominator(conditionId);
        assertTrue(denominator > 0);
    }

    function testResolveBetWithMultipleWinners() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 3, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](3);
        payouts[0] = 1;
        payouts[1] = 1;
        payouts[2] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 denominator = conditionalTokensV2.payoutDenominator(conditionId);
        assertTrue(denominator > 0);
    }

    function testResolveBetDirectlyWithoutOracle() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(this));

        vm.expectRevert(abi.encodeWithSelector(Sub0.NotAuthorized.selector, address(this), ORACLE));
        sub0.resolve(questionId, payouts);
    }

    function testResolveBetWithoutOracleRole() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Sub0.NotAuthorized.selector, attacker, ORACLE));
        sub0.resolve(questionId, payouts);
    }

    function testResolveBetWithWrongOracle() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        address wrongOracle = makeAddr("wrongOracle");
        permissionManager.grantRole(ORACLE_MANAGER_ROLE, wrongOracle);

        vm.prank(wrongOracle);
        vm.expectRevert(abi.encodeWithSelector(Sub0.NotAuthorized.selector, wrongOracle, ORACLE));
        sub0.resolve(questionId, payouts);
    }

    function testResolveBetWithInvalidPayoutsLength() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );
        uint256[] memory payouts = new uint256[](3);
        payouts[0] = 1;
        payouts[1] = 0;
        payouts[2] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        vm.expectRevert();
        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);
    }

    function testResolveBetTwice() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);

        bytes32 chainlinkRequestId2 =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        bytes32 activeRequestId = oracleManager.getActiveRequestId(questionId);
        vm.expectRevert(abi.encodeWithSelector(Oracle.ResultAlreadyFulfilled.selector, activeRequestId));
        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId2, payouts);
    }

    function testResolveBetWithFiveOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 5, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 2, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](5);
        payouts[0] = 0;
        payouts[1] = 0;
        payouts[2] = 1;
        payouts[3] = 0;
        payouts[4] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 denominator = conditionalTokensV2.payoutDenominator(conditionId);
        assertTrue(denominator > 0);
    }

    function testResolveBetWithMultipleStakes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );

        address[] memory users = new address[](2);
        users[0] = user;
        users[1] = user2;

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        collateralToken.mint(user2, stakeAmount);

        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 1, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        vm.expectEmit(true, false, false, false);
        emit Sub0.BetResolved(questionId, payouts);

        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);
    }

    function testRequestFailure() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        mockChainlinkResultOracle.failRequest(chainlinkRequestId, "Oracle could not determine result");

        Oracle.BetResult memory betResult = oracleManager.getBetResult(questionId);
        assertEq(uint256(betResult.status), 3);
    }

    function testResolveBetWithZeroPayouts() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, Sub0.MarketType.Private
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 0;

        bytes32 chainlinkRequestId =
            mockChainlinkResultOracle.requestResultWithChainlink(address(sub0), questionId, "");

        vm.expectRevert(abi.encodeWithSelector(ConditionalTokensV2.InvalidPayouts.selector));
        mockChainlinkResultOracle.fulfillRequest(chainlinkRequestId, payouts);
    }
}
