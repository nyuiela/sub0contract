// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {IConditionalTokens} from "../src/conditional/IConditionalTokens.sol";
import {ConditionalTokens} from "../src/conditional/conditionalToken.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {IHub} from "../src/interfaces/IHub.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {InvitationManager} from "../src/manager/InvitationManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockAggregatorV3} from "./MockAggregatorV3.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {MockChainlinkResultOracle} from "./mocks/MockChainlinkResultOracle.sol";
import {CTHelpersV2} from "../src/conditional/CTHelpersV2.sol";

contract Sub0BetCreationTest is Test {
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

        permissionManager.grantRole(ORACLE_MANAGER_ROLE, address(this));

        hub = new Hub();
        hub.initialize(address(permissionManager), address(tokensManager), address(oracleManager));

        collateralToken = new ERC20Mock();
        collateralToken.mint(address(this), 1000000 * 10 ** 18);
        collateralToken.mint(user, 1000000 * 10 ** 18);
        tokensManager.allowListToken(address(collateralToken), true);
        tokensManager.setDecimals(address(collateralToken), 18);
        tokensManager.setPriceFeed(address(collateralToken), address(mockAggregator));

        Sub0 sub0Impl = new Sub0();
        Sub0.Config memory sub0Config = Sub0.Config({
            hub: address(hub),
            vault: address(vault),
            tokenManager: address(tokensManager),
            permissionManager: address(permissionManager),
            conditionalToken: address(conditionalTokensV2),
            predictionVault: address(0),
            creForwarder: address(0)
        });
        bytes memory sub0InitData = abi.encodeWithSelector(Sub0.initialize.selector, sub0Config);
        ERC1967Proxy sub0Proxy = new ERC1967Proxy(address(sub0Impl), sub0InitData);
        sub0 = Sub0(payable(address(sub0Proxy)));

        permissionManager.grantRole(GAME_CREATOR_ROLE, address(this));
        hub.initializeGame("Sub0", address(sub0));
        permissionManager.grantRole(GAME_CREATOR_ROLE, address(hub));
        permissionManager.setRoleAdmin(GAME_CONTRACT_ROLE, GAME_CREATOR_ROLE);
        vm.warp(block.timestamp + 4 days);
        hub.activateGame(address(sub0));

        permissionManager.grantRole(GAME_CONTRACT_ROLE, address(sub0));

        conditionalTokensV2.grantRole(conditionalTokensV2.GAME_CONTRACT_ROLE(), address(sub0));
        conditionalTokensV2.setPayoutToken(address(collateralToken));
        conditionalTokensV2.setFeeConfig(address(this), 500);

        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(this));
        tokensManager.allowListToken(address(collateralToken), true);
        tokensManager.setDecimals(address(collateralToken), 18);
        oracle = address(oracleManager);
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    function _market(
        string memory question,
        address oracleAddr,
        uint256 duration,
        uint256 outcomeSlotCount,
        Sub0.OracleType oracleType,
        InvitationManager.InvitationType marketType
    ) internal pure returns (Sub0.Market memory) {
        return Sub0.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: oracleAddr,
            owner: address(0),
            createdAt: 0,
            duration: duration,
            outcomeSlotCount: outcomeSlotCount,
            oracleType: oracleType,
            marketType: marketType
        });
    }

    function testInitialize() public view {
        assertEq(address(sub0.tokenManager()), address(tokensManager));
        assertEq(address(sub0.hub()), address(hub));
        assertEq(address(sub0.vault()), address(vault));
        assertEq(address(sub0.permissionManager()), address(permissionManager));
    }

    function testCreateBet() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );
        assertTrue(questionId != bytes32(0));

        Sub0.Market memory retrievedMarket = sub0.getMarket(questionId);
        assertEq(retrievedMarket.question, "Who will win?");
        assertEq(retrievedMarket.oracle, oracle);
        assertEq(uint256(retrievedMarket.oracleType), uint256(Sub0.OracleType.PLATFORM));
        assertEq(retrievedMarket.owner, address(this));
        assertEq(retrievedMarket.duration, 1 days);
        assertEq(retrievedMarket.outcomeSlotCount, 2);
        assertTrue(retrievedMarket.createdAt > 0);
        assertTrue(retrievedMarket.conditionId != bytes32(0));
    }

    function testCreateBetWithZeroDuration() public {
        vm.expectRevert(abi.encodeWithSelector(Sub0.InvalidBetDuration.selector, 0));
        sub0.create(
            _market("Who will win?", oracle, 0, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single)
        );
    }

    function testCreateBetWithInvalidOutcomeSlotCountLessThanTwo() public {
        vm.expectRevert(abi.encodeWithSelector(Sub0.InvalidOutcomeSlotCount.selector, 1));
        sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 1, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );
    }

    function testCreateBetWithInvalidOutcomeSlotCountGreaterThan255() public {
        vm.expectRevert(abi.encodeWithSelector(Sub0.InvalidOutcomeSlotCount.selector, 256));
        sub0.create(
            _market(
                "Who will win?",
                oracle,
                1 days,
                256,
                Sub0.OracleType.PLATFORM,
                InvitationManager.InvitationType.Single
            )
        );
    }

    function testCreateBetWithDuplicateQuestionId() public {
        Sub0.Market memory market = _market(
            "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
        );
        bytes32 questionId = sub0.create(market);

        vm.expectRevert(abi.encodeWithSelector(Sub0.QuestionAlreadyExists.selector, questionId));
        sub0.create(market);
    }

    function testCreateBetWithNoneOracleType() public {
        vm.expectRevert(abi.encodeWithSelector(Sub0.OracleNotAllowed.selector, oracle));
        sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.NONE, InvitationManager.InvitationType.Single
            )
        );
    }

    function testCreateBetWithPublicTypeWithoutRole() public {
        vm.prank(user);
        vm.expectRevert(Sub0.PublicBetNotAllowed.selector);
        sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Public
            )
        );
    }

    function testCreateBetWithPublicTypeWithRole() public {
        permissionManager.grantRole(GAME_CREATOR_ROLE, user);
        vm.prank(user);
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Public
            )
        );
        assertTrue(questionId != bytes32(0));
    }

    function testCreateBetWithAutratorOracleType() public {
        address autratorOracle = makeAddr("autratorOracle");
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                autratorOracle,
                1 days,
                2,
                Sub0.OracleType.ARBITRATOR,
                InvitationManager.InvitationType.Single
            )
        );
        assertTrue(questionId != bytes32(0));
        Sub0.Market memory retrievedMarket = sub0.getMarket(questionId);
        assertEq(uint256(retrievedMarket.oracleType), uint256(Sub0.OracleType.ARBITRATOR));
    }

    function testCreateBetWithAllInvitationTypes() public {
        uint256 typesLength = 2;
        for (uint256 i = 0; i < typesLength; i++) {
            bytes32 questionId = sub0.create(
                _market(
                    string(abi.encodePacked("Who will win? ", i)),
                    oracle,
                    1 days,
                    2,
                    Sub0.OracleType.PLATFORM,
                    InvitationManager.InvitationType(i)
                )
            );
            assertTrue(questionId != bytes32(0));
            assertEq(uint256(sub0.getMarket(questionId).marketType), uint256(InvitationManager.InvitationType(i)));
        }
    }

    function testCreateMultipleBets() public {
        bytes32 questionId1 = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );
        bytes32 questionId2 = sub0.create(
            _market(
                "Who will win? 2",
                oracle,
                1 days,
                2,
                Sub0.OracleType.PLATFORM,
                InvitationManager.InvitationType.Single
            )
        );

        assertTrue(questionId1 != questionId2);
        assertTrue(sub0.getMarket(questionId1).owner == address(this));
        assertTrue(sub0.getMarket(questionId2).owner == address(this));
    }

    function testCreateBetWithDifferentOutcomeSlotCounts() public {
        uint256[] memory outcomeCounts = new uint256[](3);
        outcomeCounts[0] = 2;
        outcomeCounts[1] = 3;
        outcomeCounts[2] = 255;

        for (uint256 i = 0; i < outcomeCounts.length; i++) {
            bytes32 questionId = sub0.create(
                _market(
                    string(abi.encodePacked("Question with ", outcomeCounts[i], " outcomes")),
                    oracle,
                    1 days,
                    outcomeCounts[i],
                    Sub0.OracleType.PLATFORM,
                    InvitationManager.InvitationType.Single
                )
            );
            assertTrue(questionId != bytes32(0));
            assertEq(sub0.getMarket(questionId).outcomeSlotCount, outcomeCounts[i]);
        }
    }

    function testCreateBetEmitsBetCreatedEvent() public {
        Sub0.Market memory market = _market(
            "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
        );
        bytes32 expectedQuestionId = keccak256(abi.encodePacked(market.question, address(this), market.oracle));

        vm.expectEmit(true, true, true, true);
        emit Sub0.MarketCreated(
            expectedQuestionId, market.question, market.oracleType, market.marketType, market.owner
        );

        sub0.create(market);
    }

    function testCreateBetPreparesConditionInVault() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );
        Sub0.Market memory retrievedMarket = sub0.getMarket(questionId);

        assertTrue(retrievedMarket.conditionId != bytes32(0));
    }

    function testGetBetWithOwnerAndOracle() public {
        Sub0.Market memory market = _market(
            "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
        );
        bytes32 questionId = sub0.create(market);
        Sub0.Market memory retrievedMarket = sub0.getMarket(questionId);
        assertEq(retrievedMarket.question, market.question);
        assertEq(retrievedMarket.owner, address(this));
        assertEq(retrievedMarket.oracle, oracle);
    }
}
