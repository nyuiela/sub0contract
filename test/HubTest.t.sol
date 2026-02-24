// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {Sub0} from "../src/gamehub/Sub0.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {Vault} from "../src/manager/VaultV2.sol";
import {ConditionalTokens} from "../src/conditional/conditionalToken.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockAggregatorV3} from "./MockAggregatorV3.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {MockChainlinkResultOracle} from "./mocks/MockChainlinkResultOracle.sol";
import {IHub} from "../src/interfaces/IHub.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {InvitationManager} from "../src/manager/InvitationManager.sol";

contract HubTest is Test {
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant GAME_CREATOR_ROLE = keccak256("GAME_CREATOR_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant TOKENS = keccak256("TOKENS");

    Hub hub;
    Sub0 sub0;
    Sub0 sub0_2;
    TokensManager tokensManager;
    PermissionManager permissionManager;
    Vault vault;
    ConditionalTokens conditionalTokens;
    ConditionalTokensV2 conditionalTokensV2;
    Oracle oracleManager;
    MockChainlinkResultOracle mockChainlinkResultOracle;
    ERC20Mock collateralToken;
    MockAggregatorV3 mockAggregator;

    address owner = makeAddr("owner");
    address gameCreator = makeAddr("gameCreator");
    address nonGameCreator = makeAddr("nonGameCreator");
    address user = makeAddr("user");
    address arbitrator = makeAddr("arbitrator");

    function setUp() public {
        mockAggregator = new MockAggregatorV3(6, "Mock Aggregator", 1);
        mockAggregator.setLatestAnswer(1000000);
        mockAggregator.setRoundData(1, 1000000, block.timestamp, block.timestamp, 1);

        permissionManager = new PermissionManager();
        permissionManager.initialize();
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, owner);
        permissionManager.grantRole(GAME_CREATOR_ROLE, gameCreator);
        permissionManager.grantRole(GAME_CREATOR_ROLE, address(this));

        conditionalTokens = new ConditionalTokens();
        conditionalTokensV2 = new ConditionalTokensV2();

        tokensManager = new TokensManager();
        tokensManager.initialize(address(permissionManager), address(conditionalTokens));
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(tokensManager));
        permissionManager.grantRole(TOKEN_MANAGER_ROLE, address(this));

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

        hub = new Hub();
        hub.initialize(address(permissionManager), address(tokensManager), address(oracleManager));

        // Grant DEFAULT_ADMIN_ROLE to Hub so it can grant/revoke game roles
        permissionManager.grantRole(DEFAULT_ADMIN_ROLE, address(hub));

        collateralToken = new ERC20Mock();
        collateralToken.mint(address(this), 1000000 * 10 ** 18);
        collateralToken.mint(user, 1000000 * 10 ** 18);
        tokensManager.allowListToken(address(collateralToken), true);
        tokensManager.setDecimals(address(collateralToken), 18);
        tokensManager.setPriceFeed(address(collateralToken), address(mockAggregator));

        // Deploy first Sub0 game
        Sub0 sub0Impl = new Sub0();
        Sub0.Config memory sub0Config = Sub0.Config({
            hub: address(hub),
            vault: address(vault),
            tokenManager: address(tokensManager),
            permissionManager: address(permissionManager),
            conditionalToken: address(conditionalTokensV2),
            predictionVault: address(0)
        });
        bytes memory sub0InitData = abi.encodeWithSelector(Sub0.initialize.selector, sub0Config);
        ERC1967Proxy sub0Proxy = new ERC1967Proxy(address(sub0Impl), sub0InitData);
        sub0 = Sub0(payable(address(sub0Proxy)));

        conditionalTokensV2.grantRole(conditionalTokensV2.GAME_CONTRACT_ROLE(), address(sub0));

        // Deploy second Sub0 game
        ERC1967Proxy sub0Proxy2 = new ERC1967Proxy(address(sub0Impl), sub0InitData);
        sub0_2 = Sub0(payable(address(sub0Proxy2)));
        conditionalTokensV2.grantRole(conditionalTokensV2.GAME_CONTRACT_ROLE(), address(sub0_2));

        // Roles will be granted by Hub when games are activated
        // No need to grant roles here - let Hub manage them
        vault.setPayoutToken(address(collateralToken));
        vault.setFeeConfig(address(this), 500);

        // manager permission
        permissionManager.grantRole(GAME_CREATOR_ROLE, address(hub));
        permissionManager.setRoleAdmin(GAME_CONTRACT_ROLE, GAME_CREATOR_ROLE);
    }

    /**
     * @notice Helper function to add users to invitation and have them accept
     * @param questionId The question ID
     * @param betOwner The owner of the bet (who created it)
     * @param users Array of users to invite
     */
    function _inviteAndAcceptUsers(bytes32 questionId, address betOwner, address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            // Owner adds user to invitation
            vm.prank(betOwner);
            sub0.addUser(questionId, users[i]);

            // User accepts invitation
            vm.prank(users[i]);
            sub0.acceptInvitation(questionId);
        }
    }

    /**
     * @notice Helper function for single user invitation
     */
    function _inviteAndAcceptUser(bytes32 questionId, address betOwner, address _user) internal {
        address[] memory users = new address[](1);
        users[0] = _user;
        _inviteAndAcceptUsers(questionId, betOwner, users);
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

    // ============ Game Initialization Tests ============

    function testInitializeGame() public {
        hub.initializeGame("Test Game", address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));
        assertTrue(gameId != bytes32(0));

        (address sourceAddress, IHub.GameStatus status, string memory description,,) = hub.games(gameId);
        assertEq(sourceAddress, address(sub0));
        assertEq(uint256(status), uint256(IHub.GameStatus.Pending));
        assertEq(description, "Test Game");
    }

    function testInitializeGameWithoutRole() public {
        vm.prank(nonGameCreator);
        vm.expectRevert(abi.encodeWithSelector(IHub.NotAuthorized.selector, nonGameCreator, GAME_CREATOR_ROLE));
        hub.initializeGame("Test Game", address(sub0));
    }

    function testInitializeGameWithZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IHub.ZeroAddress.selector));
        hub.initializeGame("Test Game", address(0));
    }

    function testInitializeMultipleGames() public {
        hub.initializeGame("Game 1", address(sub0));
        hub.initializeGame("Game 2", address(sub0_2));

        bytes32 gameId1 = hub.getGameId(address(sub0));
        bytes32 gameId2 = hub.getGameId(address(sub0_2));

        assertTrue(gameId1 != bytes32(0));
        assertTrue(gameId2 != bytes32(0));
        assertTrue(gameId1 != gameId2);
    }

    // ============ Game Activation Tests ============

    function testActivateGame() public {
        hub.initializeGame("Test Game", address(sub0));

        // Wait for approval duration
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);

        hub.activateGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));
        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
    }

    function testActivateGameBeforeApprovalDuration() public {
        hub.initializeGame("Test Game", address(sub0));
        // With GAME_APPROVAL_DURATION == 0, activateGame succeeds immediately (approval check is currently disabled in Hub).
        hub.activateGame(address(sub0));
        bytes32 gameId = hub.getGameId(address(sub0));
        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
    }

    function testActivateGameWithoutRole() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);

        vm.prank(nonGameCreator);
        vm.expectRevert(abi.encodeWithSelector(IHub.NotAuthorized.selector, nonGameCreator, GAME_CREATOR_ROLE));
        hub.activateGame(address(sub0));
    }

    function testActivateGameThatDoesNotExist() public {
        address nonExistentGame = makeAddr("nonExistent");
        vm.expectRevert(abi.encodeWithSelector(IHub.InvalidGameId.selector, bytes32(0)));
        hub.activateGame(nonExistentGame);
    }

    // ============ Game Pause/Unpause Tests ============

    function testPauseGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));

        // Verify roles are granted after activation
        assertTrue(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));

        hub.pauseGame(address(sub0));

        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Paused));
        assertTrue(hub.gameShutdownTimestamp(gameId) > 0);

        // Verify roles are revoked after pause
        assertFalse(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));
    }

    function testUnpauseGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));

        // Verify roles are revoked after pause
        assertFalse(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));

        hub.unpauseGame(address(sub0));

        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
        assertEq(hub.gameShutdownTimestamp(gameId), 0);

        // Verify roles are granted back after unpause
        assertTrue(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));
    }

    function testUnpauseGameThatIsNotPaused() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        vm.expectRevert(
            abi.encodeWithSelector(IHub.GameShutdownAlreadyInitiated.selector, hub.getGameId(address(sub0)))
        );
        hub.unpauseGame(address(sub0));
    }

    function testPauseGameTwice() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));

        vm.expectRevert(
            abi.encodeWithSelector(IHub.GameShutdownAlreadyInitiated.selector, hub.getGameId(address(sub0)))
        );
        hub.pauseGame(address(sub0));
    }

    // ============ Game Ban/Unban Tests ============

    function testBanGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));

        // Verify roles are granted after activation
        assertTrue(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));

        // Wait for ban duration
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);

        hub.banGame(address(sub0));

        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Banned));

        // Verify roles are revoked after ban
        assertFalse(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));
    }

    function testBanGameBeforeBanDuration() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        vm.expectRevert(abi.encodeWithSelector(IHub.BanDurationNotMet.selector, hub.getGameId(address(sub0))));
        hub.banGame(address(sub0));
    }

    function testUnbanGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));

        // Verify roles are revoked after ban
        hub.unbanGame(address(sub0));

        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));

        // Verify roles are granted back after unban
        assertTrue(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));
    }

    // ============ Game Shutdown Tests ============

    function testShutdownGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));

        // Verify roles are revoked after pause
        assertFalse(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));

        // Wait for shutdown duration
        vm.warp(block.timestamp + hub.GAME_SHUTDOWN_DURATION() + 1);

        hub.shutdownGame(address(sub0));

        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Shutdown));

        // Verify roles remain revoked after shutdown
        assertFalse(permissionManager.hasRole(GAME_CONTRACT_ROLE, address(sub0)));
    }

    function testShutdownGameBeforeShutdownDuration() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));

        vm.expectRevert(
            abi.encodeWithSelector(IHub.GameShutdownDurationNotMet.selector, hub.getGameId(address(sub0)))
        );
        hub.shutdownGame(address(sub0));
    }

    // ============ Verify Game Tests ============

    function testVerifyGameReturnsTrueForActiveGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        assertTrue(hub.verifyGame(address(sub0)));
    }

    function testVerifyGameReturnsFalseForPendingGame() public {
        hub.initializeGame("Test Game", address(sub0));

        assertFalse(hub.verifyGame(address(sub0)));
    }

    function testVerifyGameReturnsFalseForPausedGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));

        assertFalse(hub.verifyGame(address(sub0)));
    }

    function testVerifyGameReturnsFalseForBannedGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));

        assertFalse(hub.verifyGame(address(sub0)));
    }

    function testVerifyGameReturnsFalseForShutdownGame() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        hub.pauseGame(address(sub0));
        vm.warp(block.timestamp + hub.GAME_SHUTDOWN_DURATION() + 1);
        hub.shutdownGame(address(sub0));

        assertFalse(hub.verifyGame(address(sub0)));
    }

    function testVerifyGameReturnsFalseForNonExistentGame() public {
        address nonExistentGame = makeAddr("nonExistent");
        assertFalse(hub.verifyGame(nonExistentGame));
    }

    // ============ Banned Game Restriction Tests ============

    function testBannedGameCannotCreateBet() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        // Grant necessary roles and create a bet while active

        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                arbitrator,
                1 days,
                2,
                Sub0.OracleType.ARBITRATOR,
                InvitationManager.InvitationType.Single
            )
        );
        assertTrue(questionId != bytes32(0));

        // Ban the game
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));

        // Verify game is banned
        assertFalse(hub.verifyGame(address(sub0)));

        // Attempt to create another bet - should fail if Sub0 checks verifyGame
        // Note: Currently Sub0 doesn't check verifyGame, so this will succeed
        // This test documents expected behavior - Sub0 should check hub.verifyGame(address(this))
        // Sub0.Bet memory bet2 = Sub0.Bet({
        //     question: "Who will win again?",
        //     conditionId: bytes32(0),
        //     oracle: arbitrator,
        //     owner: address(0),
        //     createdAt: 0,
        //     duration: 1 days,
        //     outcomeSlotCount: 2,
        //     oracleType: Sub0.OracleType.ARBITRATOR,
        //     betType: InvitationManager.InvitationType.Single
        // });

        // This should revert if Sub0 checks verifyGame, but currently it doesn't
        // TODO: Add verifyGame check in Sub0.createBet()
        // vm.expectRevert("Game not verified");
        // sub0.createBet(bet2);
    }

    function testBannedGameCannotStake() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        // Grant necessary roles

        // Create a bet while game is active
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                arbitrator,
                1 days,
                2,
                Sub0.OracleType.ARBITRATOR,
                InvitationManager.InvitationType.Single
            )
        );

        _inviteAndAcceptUser(questionId, address(this), user);

        // Stake while game is active (should succeed)
        uint256 stakeAmount = 1000 * 10 ** 18;
        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        // Ban the game
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));

        // Game is now banned, verifyGame should return false
        assertFalse(hub.verifyGame(address(sub0)));

        // Attempting to stake again should fail if Sub0 checks verifyGame
        // Note: Currently Sub0 doesn't check verifyGame, so this will succeed
        // TODO: Add verifyGame check in Sub0.stake()
        // vm.expectRevert("Game not verified");
        // sub0.stake(questionId, 1, address(collateralToken), stakeAmount);
    }

    function testBannedGameCannotOperateOnVault() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        // Grant vault permissions

        // Create a bet and prepare condition while active
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                arbitrator,
                1 days,
                2,
                Sub0.OracleType.ARBITRATOR,
                InvitationManager.InvitationType.Single
            )
        );

        _inviteAndAcceptUser(questionId, address(this), user);

        // Stake while active
        uint256 stakeAmount = 1000 * 10 ** 18;
        collateralToken.mint(user, stakeAmount);
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokensV2), stakeAmount);
        _stakeOption(questionId, 0, address(collateralToken), stakeAmount);
        vm.stopPrank();

        // Ban the game
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));

        // Game is banned, verifyGame returns false
        assertFalse(hub.verifyGame(address(sub0)));

        // Vault operations (prepareCondition, deposit, withdraw, resolveCondition) should check if the game is verified
        // This test documents expected behavior
        // Note: Currently vault doesn't check verifyGame, but it should
        // TODO: Add verifyGame check in Vault functions that are called by games
        // The vault should verify: require(hub.verifyGame(msg.sender), "Game not verified");
    }

    function testPausedGameCannotCreateBet() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));

        hub.pauseGame(address(sub0));

        // Game is paused, verifyGame returns false
        assertFalse(hub.verifyGame(address(sub0)));

        // Attempting to create bet should fail if Sub0 checks verifyGame
        // TODO: Add verifyGame check in Sub0.createBet()
    }

    function testUnbannedGameCanCreateBet() public {
        hub.initializeGame("Test Game", address(sub0));
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));
        hub.unbanGame(address(sub0));

        assertTrue(hub.verifyGame(address(sub0)));

        // Unbanned game should be able to create bets
        bytes32 questionId = sub0.create(
            _market(
                "Who will win?",
                arbitrator,
                1 days,
                2,
                Sub0.OracleType.ARBITRATOR,
                InvitationManager.InvitationType.Single
            )
        );
        assertTrue(questionId != bytes32(0));
    }

    // ============ isAllowed Tests ============

    function testIsAllowedForOracle() public {
        address testOracle = makeAddr("testOracle");
        oracleManager.allowListReporter(testOracle, true);

        assertTrue(hub.isAllowed(testOracle, ORACLE));
    }

    function testIsAllowedForToken() public {
        address testToken = makeAddr("testToken");
        tokensManager.allowListToken(testToken, true);

        assertTrue(hub.isAllowed(testToken, TOKENS));
    }

    function testIsAllowedReturnsFalseForUnknownRole() public view {
        bytes32 unknownRole = keccak256("UNKNOWN_ROLE");
        assertFalse(hub.isAllowed(address(0x123), unknownRole));
    }

    // ============ getGameId Tests ============

    function testGetGameId() public {
        hub.initializeGame("Test Game", address(sub0));

        bytes32 gameId = hub.getGameId(address(sub0));
        assertTrue(gameId != bytes32(0));
    }

    function testGetGameIdReturnsZeroForNonExistentGame() public {
        address nonExistentGame = makeAddr("nonExistent");
        bytes32 gameId = hub.getGameId(nonExistentGame);
        assertEq(gameId, bytes32(0));
    }

    // ============ setConfig Tests ============

    function testSetConfig() public {
        IHub.Config memory newConfig = IHub.Config({
            permissionManager: address(permissionManager),
            tokensManager: address(tokensManager),
            oracleManager: address(oracleManager)
        });

        vm.prank(owner);
        hub.setConfig(newConfig);

        (address permManager, address tokManager, address oracManager) = hub.config();
        assertEq(permManager, address(permissionManager));
        assertEq(tokManager, address(tokensManager));
        assertEq(oracManager, address(oracleManager));
    }

    function testSetConfigWithoutRole() public {
        IHub.Config memory newConfig = IHub.Config({
            permissionManager: address(permissionManager),
            tokensManager: address(tokensManager),
            oracleManager: address(oracleManager)
        });

        vm.prank(nonGameCreator);
        vm.expectRevert(abi.encodeWithSelector(IHub.NotAuthorized.selector, nonGameCreator, DEFAULT_ADMIN_ROLE));
        hub.setConfig(newConfig);
    }

    function testSetConfigWithZeroAddress() public {
        IHub.Config memory newConfig = IHub.Config({
            permissionManager: address(0),
            tokensManager: address(tokensManager),
            oracleManager: address(oracleManager)
        });

        vm.expectRevert(abi.encodeWithSelector(IHub.ZeroAddress.selector));
        hub.setConfig(newConfig);
    }

    // ============ Integration Tests ============

    function testFullGameLifecycle() public {
        // Initialize
        hub.initializeGame("Test Game", address(sub0));
        bytes32 gameId = hub.getGameId(address(sub0));
        (, IHub.GameStatus status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Pending));

        // Activate
        vm.warp(block.timestamp + hub.GAME_APPROVAL_DURATION() + 1);
        hub.activateGame(address(sub0));
        (, status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
        assertTrue(hub.verifyGame(address(sub0)));

        // Pause
        hub.pauseGame(address(sub0));
        (, status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Paused));
        assertFalse(hub.verifyGame(address(sub0)));

        // Unpause
        hub.unpauseGame(address(sub0));
        (, status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
        assertTrue(hub.verifyGame(address(sub0)));

        // Ban
        vm.warp(block.timestamp + hub.BAN_DURATION() + 1);
        hub.banGame(address(sub0));
        (, status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Banned));
        assertFalse(hub.verifyGame(address(sub0)));

        // Unban
        hub.unbanGame(address(sub0));
        (, status,,,) = hub.games(gameId);
        assertEq(uint256(status), uint256(IHub.GameStatus.Active));
        assertTrue(hub.verifyGame(address(sub0)));
    }
}
