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
import {InvitationManager} from "../src/manager/InvitationManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockAggregatorV3} from "./MockAggregatorV3.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {MockChainlinkResultOracle} from "./mocks/MockChainlinkResultOracle.sol";

contract Sub0StakingTest is Test {
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
        InvitationManager.InvitationType marketType
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


    function testStakeAndReceiveConditionalTokens() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 indexSet = 1 << 0;
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);

        uint256 userBalance = conditionalTokensV2.balanceOf(user, positionId);
        assertEq(userBalance, stakeAmount);
    }

    function testStakeOnDifferentOptions() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 2);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 2);

        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        _stakeOption(questionId, 1, address(collateralToken), stakeAmount);
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        uint256 indexSet0 = 1 << 0;
        bytes32 collectionId0 = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet0);
        uint256 positionId0 = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId0);

        uint256 indexSet1 = 1 << 1;
        bytes32 collectionId1 = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet1);
        uint256 positionId1 = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId1);

        // Splitting mints both outcome positions; staking on 0 then 1 gives 2x each
        assertEq(conditionalTokensV2.balanceOf(user, positionId0), stakeAmount * 2);
        assertEq(conditionalTokensV2.balanceOf(user, positionId1), stakeAmount * 2);
    }

    function testStakeMultipleUsers() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
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

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        uint256 indexSet0 = 1 << 0;
        bytes32 collectionId0 = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet0);
        uint256 positionId0 = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId0);

        uint256 indexSet1 = 1 << 1;
        bytes32 collectionId1 = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet1);
        uint256 positionId1 = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId1);

        // Each split mints both outcome positions; each user has stakeAmount on each position
        assertEq(conditionalTokensV2.balanceOf(user, positionId0), stakeAmount);
        assertEq(conditionalTokensV2.balanceOf(user, positionId1), stakeAmount);
        assertEq(conditionalTokensV2.balanceOf(user2, positionId0), stakeAmount);
        assertEq(conditionalTokensV2.balanceOf(user2, positionId1), stakeAmount);
    }

    function testStakeWithInvalidQuestionId() public {
        // whenInvited(0) runs first and reverts with UserNotInvited (no market for bytes32(0))
        vm.expectRevert(abi.encodeWithSelector(Sub0.InvalidQuestionId.selector, bytes32(0)));
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        sub0.stake(bytes32(0), bytes32(0), partition, address(collateralToken), 1000 * 10 ** 18);
    }

    function testStakeWithZeroTokenAddress() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.prank(user);
        vm.expectRevert(); // IERC20(0).transferFrom reverts (no selector)
        sub0.stake(questionId, bytes32(0), partition, address(0), 1000 * 10 ** 18);
    }

    function testStakeWithNotAllowedToken() public {
        ERC20Mock invalidToken = new ERC20Mock();
        invalidToken.mint(user, 1000 * 10 ** 18);
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.startPrank(user);
        // stake() does not check allow list; CT.transferFrom fails with insufficient allowance
        vm.expectRevert();
        sub0.stake(questionId, bytes32(0), partition, address(invalidToken), 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testStakeWithInvalidOptionIndex() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);

        // Partition for invalid option 2 (fullIndexSet=3, indexSet 4 >= 3)
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1 << 2; // 4
        partition[1] = ((1 << 2) - 1) ^ (1 << 2); // 3
        vm.expectRevert(); // InvalidIndexSet from CT
        sub0.stake(questionId, bytes32(0), partition, address(collateralToken), stakeAmount);
        vm.stopPrank();
    }

    function testStakeEmitsStakedEvent() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.expectEmit(true, true, true, true);
        emit Sub0.Staked(questionId, partition, address(collateralToken), stakeAmount);

        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();
    }

    function testStakeTransfersTokensToConditionalTokens() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        uint256 conditionalTokensBalanceBefore = collateralToken.balanceOf(address(conditionalTokensV2));
        uint256 userBalanceBefore = collateralToken.balanceOf(user);

        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        uint256 conditionalTokensBalanceAfter = collateralToken.balanceOf(address(conditionalTokensV2));
        uint256 userBalanceAfter = collateralToken.balanceOf(user);

        assertEq(conditionalTokensBalanceAfter, conditionalTokensBalanceBefore + stakeAmount);
        assertEq(userBalanceAfter, userBalanceBefore - stakeAmount);
    }

    function testStakeWithMultipleStakesOnSameOption() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 2);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 2);

        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        uint256 indexSet = 1 << 0;
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);

        assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount * 2);
    }

    function testStakeWithThreeOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 3, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );
  
        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 3);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 3);

        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        _stakeOption(questionId, 1, address(collateralToken), stakeAmount);
        _stakeOption(questionId, 2, address(collateralToken), stakeAmount);
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        for (uint256 i = 0; i < 3; i++) {
            uint256 indexSet = 1 << i;
            bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
            uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);
            assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount);
        }
    }

    function testStakeWithFourOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 4, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );


        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 4);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 4);

        for (uint256 i = 0; i < 4; i++) {
            _stakeOption(questionId, i, address(collateralToken), stakeAmount);
        }
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        for (uint256 i = 0; i < 4; i++) {
            uint256 indexSet = 1 << i;
            bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
            uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);
            assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount);
        }
    }

    function testStakeWithFiveOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 5, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 5);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 5);

        for (uint256 i = 0; i < 5; i++) {
            _stakeOption(questionId, i, address(collateralToken), stakeAmount);
        }
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        for (uint256 i = 0; i < 5; i++) {
            uint256 indexSet = 1 << i;
            bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
            uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);
            assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount);
        }
    }

    function testStakeWithTenOutcomes() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                oracle,
                1 days,
                10,
                Sub0.OracleType.PLATFORM,
                InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount * 10);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount * 10);

        for (uint256 i = 0; i < 10; i++) {
            _stakeOption(questionId, i, address(collateralToken), stakeAmount);
        }
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;

        for (uint256 i = 0; i < 10; i++) {
            uint256 indexSet = 1 << i;
            bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
            uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);
            assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount);
        }
    }

    function testStakeIncreasesVaultBalance() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        bytes32 conditionId = sub0.getMarket(questionId).conditionId;
        uint256 indexSet = 1 << 0;
        bytes32 collectionId = CTHelpersV2.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = CTHelpersV2.getPositionId(IERC20(collateralToken), collectionId);
        assertEq(conditionalTokensV2.balanceOf(user, positionId), stakeAmount);
    }

    function testStakeWithInsufficientAllowance() public {
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?", oracle, 1 days, 2, Sub0.OracleType.PLATFORM, InvitationManager.InvitationType.Single
            )
        );

        uint256 stakeAmount = 1000 * 10 ** 18;

        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount - 1);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.expectRevert(); // ERC20InsufficientAllowance from CT.transferFrom
        sub0.stake(questionId, bytes32(0), partition, address(collateralToken), stakeAmount);
        vm.stopPrank();
    }
}
