// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ParimutuelConditionalTokens} from "../src/conditional/ParimutuelConditionalTokens.sol";
import {MeVsYouParimutuel} from "../src/gamehub/MeVsYouParimutuel.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PermissionManager} from "../src/manager/PermissionManager.sol";
import {TokensManager} from "../src/manager/TokenManager.sol";
import {Hub} from "../src/gamehub/Hub.sol";
import {Oracle} from "../src/oracle/oracle.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";
import {IHub} from "../src/interfaces/IHub.sol";
import {InvitationManager} from "../src/manager/InvitationManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Parimutuel: payout = (your stake / total winning stake) * total volume - platform fee.
 * Example: 100 on option 0, 200 total on option 0, 10k on option 1. Total volume = 10,200.
 * Your share = 100/200 = 50%. Gross = 50% * 10,200 = 5,100. Net = 5,100 - 5% fee.
 */
contract ParimutuelFlowTest is Test {
    ParimutuelConditionalTokens public parimutuel;
    MeVsYouParimutuel public game;
    PermissionManager public permissionManager;
    TokensManager public tokensManager;
    Hub public hub;
    Oracle public oracleManager;
    ERC20Mock public collateral;

    address public owner;
    address public oracle;
    address public userOption0_100;
    address public userOption0_100b;
    address public userOption1_10k;
    address public feeCollector;

    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public constant FEE_BPS = 500; // 5%

    function setUp() public {
        owner = address(this);
        oracle = makeAddr("oracle");
        userOption0_100 = makeAddr("userOption0_100");
        userOption0_100b = makeAddr("userOption0_100b");
        userOption1_10k = makeAddr("userOption1_10k");
        feeCollector = makeAddr("feeCollector");

        permissionManager = new PermissionManager();
        permissionManager.initialize();
        permissionManager.grantRole(permissionManager.DEFAULT_ADMIN_ROLE(), owner);
        permissionManager.grantRole(keccak256("GAME_CREATOR_ROLE"), owner);
        permissionManager.grantRole(keccak256("ORACLE"), oracle);

        tokensManager = new TokensManager();
        tokensManager.initialize(address(permissionManager), address(1));
        permissionManager.grantRole(keccak256("TOKEN_MANAGER_ROLE"), owner);

        oracleManager = new Oracle();
        oracleManager.initialize(address(permissionManager), address(1));
        permissionManager.grantRole(keccak256("ORACLE_MANAGER_ROLE"), owner);
        oracleManager.allowListReporter(oracle, true);
        hub = new Hub();
        hub.initialize(address(permissionManager), address(tokensManager), address(oracleManager));

        collateral = new ERC20Mock();
        collateral.mint(userOption0_100, 500 * 10 ** 18);
        collateral.mint(userOption0_100b, 500 * 10 ** 18);
        collateral.mint(userOption1_10k, 15000 * 10 ** 18);

        ParimutuelConditionalTokens parimutuelImpl = new ParimutuelConditionalTokens();
        bytes memory parimutuelInitData = abi.encodeWithSelector(
            ParimutuelConditionalTokens.initialize.selector, IPermissionManager(address(permissionManager))
        );
        ERC1967Proxy parimutuelProxy = new ERC1967Proxy(address(parimutuelImpl), parimutuelInitData);
        parimutuel = ParimutuelConditionalTokens(address(parimutuelProxy));

        permissionManager.grantRole(parimutuel.PARIMUTUEL_ADMIN_ROLE(), owner);
        parimutuel.setPayoutToken(address(collateral));
        parimutuel.setFeeConfig(feeCollector, FEE_BPS);

        game = new MeVsYouParimutuel();
        game.initialize(
            MeVsYouParimutuel.Config({
                hub: address(hub),
                tokenManager: address(tokensManager),
                permissionManager: address(permissionManager),
                parimutuelToken: address(parimutuel)
            })
        );
        permissionManager.grantRole(parimutuel.GAME_CONTRACT_ROLE(), address(game));

        tokensManager.allowListToken(address(collateral), true);
        tokensManager.setDecimals(address(collateral), 18);
    }

    function testParimutuelPayoutFormula() public {
        string memory question = "Who wins?";
        questionId = keccak256(abi.encodePacked(question, owner, oracle));

        MeVsYouParimutuel.Market memory market = MeVsYouParimutuel.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: oracle,
            owner: owner,
            createdAt: 0,
            duration: 1 days,
            outcomeSlotCount: 2,
            oracleType: MeVsYouParimutuel.OracleType.PLATFORM,
            marketType: InvitationManager.InvitationType.Public
        });

        game.create(market);
        conditionId = game.getMarket(questionId).conditionId;

        uint256 stake0a = 100 * 10 ** 18;
        uint256 stake0b = 100 * 10 ** 18;
        uint256 stake1 = 10000 * 10 ** 18;

        vm.startPrank(userOption0_100);
        collateral.approve(address(parimutuel), stake0a);
        game.stake(questionId, 0, address(collateral), stake0a);
        vm.stopPrank();

        vm.startPrank(userOption0_100b);
        collateral.approve(address(parimutuel), stake0b);
        game.stake(questionId, 0, address(collateral), stake0b);
        vm.stopPrank();

        vm.startPrank(userOption1_10k);
        collateral.approve(address(parimutuel), stake1);
        game.stake(questionId, 1, address(collateral), stake1);
        vm.stopPrank();

        uint256 totalVolume = stake0a + stake0b + stake1; // 10,200e18
        assertEq(parimutuel.getTotalVolume(conditionId), totalVolume, "total volume");
        assertEq(parimutuel.volumePerOutcome(conditionId, 0), 200 * 10 ** 18, "volume option 0");
        assertEq(parimutuel.volumePerOutcome(conditionId, 1), 10000 * 10 ** 18, "volume option 1");

        vm.prank(oracle);
        game.resolve(questionId, _payouts(1, 0)); // option 0 wins

        (uint256 grossA,, uint256 netA) =
            parimutuel.getRedeemableAmount(userOption0_100, conditionId, IERC20(address(collateral)));
        uint256 expectedGrossA = (stake0a * totalVolume) / (200 * 10 ** 18); // 100/200 * 10200 = 5100e18
        assertEq(grossA, 5100 * 10 ** 18, "gross payout 50% of pool");
        assertEq(grossA, expectedGrossA, "gross formula");
        uint256 expectedFeeA = (5100 * 10 ** 18 * FEE_BPS) / 10000;
        assertEq(netA, 5100 * 10 ** 18 - expectedFeeA, "net after 5% fee");

        uint256 balanceBefore = collateral.balanceOf(userOption0_100);
        vm.prank(userOption0_100);
        game.redeem(questionId, address(collateral));
        uint256 balanceAfter = collateral.balanceOf(userOption0_100);
        assertEq(balanceAfter - balanceBefore, netA, "user received net payout");

        vm.prank(userOption0_100b);
        game.redeem(questionId, address(collateral));

        assertEq(parimutuel.accumulatedFees(), 2 * expectedFeeA, "fees from both winners");
        parimutuel.claimFees();
        assertEq(collateral.balanceOf(feeCollector), 2 * expectedFeeA, "feeCollector received");
    }

    /**
     * Refund all: resolve with [1,1]. Each outcome gets 50% of total pool; users get proportional share of that half.
     * Option 0: 200e18 total stake -> gets (1/2)*10200 = 5100e18. User A 100/200 -> 2550e18 gross, B same.
     * Option 1: 10k stake -> gets 5100e18. User C 10k/10k -> 5100e18 gross.
     */
    function testParimutuelRefundAll() public {
        string memory question = "Refund market?";
        bytes32 qId = keccak256(abi.encodePacked(question, owner, oracle));
        MeVsYouParimutuel.Market memory market = MeVsYouParimutuel.Market({
            question: question,
            conditionId: bytes32(0),
            oracle: oracle,
            owner: owner,
            createdAt: 0,
            duration: 1 days,
            outcomeSlotCount: 2,
            oracleType: MeVsYouParimutuel.OracleType.PLATFORM,
            marketType: InvitationManager.InvitationType.Public
        });
        game.create(market);
        bytes32 cId = game.getMarket(qId).conditionId;

        uint256 aStake = 100 * 10 ** 18;
        uint256 bStake = 100 * 10 ** 18;
        uint256 cStake = 10000 * 10 ** 18;

        vm.startPrank(userOption0_100);
        collateral.approve(address(parimutuel), aStake);
        game.stake(qId, 0, address(collateral), aStake);
        vm.stopPrank();
        vm.startPrank(userOption0_100b);
        collateral.approve(address(parimutuel), bStake);
        game.stake(qId, 0, address(collateral), bStake);
        vm.stopPrank();
        vm.startPrank(userOption1_10k);
        collateral.approve(address(parimutuel), cStake);
        game.stake(qId, 1, address(collateral), cStake);
        vm.stopPrank();

        uint256 totalVol = aStake + bStake + cStake; // 10200e18
        vm.prank(oracle);
        game.resolve(qId, _payouts(1, 1)); // refund: [1,1]

        assertEq(parimutuel.payoutDenominator(cId), 2, "denom");
        uint256 halfPool = totalVol / 2; // 5100e18 for each outcome
        // Outcome 0: 200 total. A gets (100/200)*5100 = 2550e18 gross
        (uint256 grossA,, uint256 netA) =
            parimutuel.getRedeemableAmount(userOption0_100, cId, IERC20(address(collateral)));
        uint256 expectedGrossA = (aStake * halfPool) / (200 * 10 ** 18);
        assertEq(grossA, expectedGrossA, "A gross");
        assertEq(grossA, 2550 * 10 ** 18, "A gross 2550");
        uint256 feeA = (grossA * FEE_BPS) / 10000;
        assertEq(netA, grossA - feeA, "A net");

        vm.prank(userOption0_100);
        game.redeem(qId, address(collateral));
        vm.prank(userOption0_100b);
        game.redeem(qId, address(collateral));
        (uint256 grossC,, uint256 netC) =
            parimutuel.getRedeemableAmount(userOption1_10k, cId, IERC20(address(collateral)));
        assertEq(grossC, halfPool, "C gross half pool");
        vm.prank(userOption1_10k);
        game.redeem(qId, address(collateral));

        // All stakers got something; total redeemed + fees = totalVolume
        assertEq(collateral.balanceOf(userOption0_100), 500 * 10 ** 18 - aStake + netA, "A balance");
        assertEq(collateral.balanceOf(userOption1_10k), 15000 * 10 ** 18 - cStake + netC, "C balance");
    }

    function _payouts(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory p = new uint256[](2);
        p[0] = a;
        p[1] = b;
        return p;
    }
}
