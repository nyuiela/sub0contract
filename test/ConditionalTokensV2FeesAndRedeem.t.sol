// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConditionalTokensV2} from "../src/conditional/ConditionalTokensV2.sol";
import {ConditionalTokensV2ViewHelper} from "../src/conditional/ConditionalTokensV2ViewHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * Tests for ConditionalTokensV2:
 * - Fee calculation on redemption (platformFeeBps)
 * - Multiple winners (4-6 users) set result and redeem
 * - Redeemable amount vs actual redeemed per user
 * - Total fee across all redeems
 * - Admin claimFees and feeCollector receives fees
 */
contract ConditionalTokensV2FeesAndRedeemTest is Test {
    ConditionalTokensV2 public ct;
    ConditionalTokensV2ViewHelper public viewHelper;
    ERC20Mock public collateral;

    address public oracle;
    address public feeCollector;
    address[] public winners;

    uint256 public constant STAKE_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant FEE_BPS = 500; // 5%
    uint256 public constant NUM_WINNERS = 6;

    bytes32 public questionId;
    bytes32 public conditionId;
    uint256[] public partition;
    uint256[] public winningIndexSets;
    uint256[] public payouts;

    function setUp() public {
        oracle = address(this);
        feeCollector = makeAddr("feeCollector");

        ct = new ConditionalTokensV2();
        ct.grantRole(ct.ORACLE_ROLE(), oracle);
        ct.grantRole(ct.DEFAULT_ADMIN_ROLE(), address(this));

        collateral = new ERC20Mock();
        collateral.mint(address(this), 100_000 * 10 ** 18);

        questionId = keccak256("who-wins");
        conditionId = ct.getConditionId(oracle, questionId, 2);
        partition = _binaryPartition();
        winningIndexSets = _winningIndexSets(); // [1] = outcome 0 wins
        payouts = _payoutsOutcomeZeroWins(); // [1, 0]

        ct.setPayoutToken(address(collateral));
        ct.setFeeConfig(feeCollector, FEE_BPS);

        viewHelper = new ConditionalTokensV2ViewHelper();

        ct.prepareCondition(oracle, questionId, 2);

        winners = new address[](NUM_WINNERS);
        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            winners[i] = makeAddr(string(abi.encodePacked("winner", i)));
            collateral.mint(winners[i], STAKE_AMOUNT * 2);
        }
    }

    function _binaryPartition() internal pure returns (uint256[] memory) {
        uint256[] memory p = new uint256[](2);
        p[0] = 1;
        p[1] = 2;
        return p;
    }

    function _winningIndexSets() internal pure returns (uint256[] memory) {
        uint256[] memory s = new uint256[](1);
        s[0] = 1;
        return s;
    }

    function _payoutsOutcomeZeroWins() internal pure returns (uint256[] memory) {
        uint256[] memory p = new uint256[](2);
        p[0] = 1;
        p[1] = 0;
        return p;
    }

    function _stakeAs(address user, uint256 amount) internal {
        vm.startPrank(user);
        collateral.approve(address(ct), amount);
        ct.splitPosition(IERC20(address(collateral)), bytes32(0), conditionId, partition, amount);
        vm.stopPrank();
    }

    function testSetResultAndRedeemMultipleWinners() public {
        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            _stakeAs(winners[i], STAKE_AMOUNT);
        }

        ct.reportPayouts(questionId, payouts);

        uint256 feePerUser = (STAKE_AMOUNT * FEE_BPS) / 10000;
        uint256 netPerUser = STAKE_AMOUNT - feePerUser;

        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            uint256 before = collateral.balanceOf(winners[i]);
            vm.prank(winners[i]);
            ct.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets);
            uint256 after_ = collateral.balanceOf(winners[i]);
            assertEq(after_ - before, netPerUser, "winner net payout");
        }

        assertEq(ct.accumulatedFees(), NUM_WINNERS * feePerUser, "total accumulated fees");
    }

    function testRedeemableAmountActualRedeemedFeeAndClaimFees() public {
        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            _stakeAs(winners[i], STAKE_AMOUNT);
        }

        ct.reportPayouts(questionId, payouts);

        uint256 expectedFeePerUser = (STAKE_AMOUNT * FEE_BPS) / 10000;
        uint256 expectedNetPerUser = STAKE_AMOUNT - expectedFeePerUser;
        uint256 totalFeesExpected = NUM_WINNERS * expectedFeePerUser;

        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet) = viewHelper.getRedeemableAmount(
                ct, winners[i], IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets
            );

            assertEq(payoutGross, STAKE_AMOUNT, "redeemable gross");
            assertEq(feeAmount, expectedFeePerUser, "redeemable fee");
            assertEq(payoutNet, expectedNetPerUser, "redeemable net");

            uint256 balanceBefore = collateral.balanceOf(winners[i]);
            vm.prank(winners[i]);
            ct.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets);
            uint256 balanceAfter = collateral.balanceOf(winners[i]);

            assertEq(balanceAfter - balanceBefore, payoutNet, "actual redeemed equals getRedeemableAmount net");
            assertEq(balanceAfter - balanceBefore, expectedNetPerUser, "actual redeemed 950e18");
        }

        assertEq(ct.accumulatedFees(), totalFeesExpected, "accumulated fees after all redeems");

        uint256 collectorBefore = collateral.balanceOf(feeCollector);
        ct.claimFees();
        uint256 collectorAfter = collateral.balanceOf(feeCollector);

        assertEq(collectorAfter - collectorBefore, totalFeesExpected, "feeCollector received all fees");
        assertEq(ct.accumulatedFees(), 0, "accumulated fees zero after claim");
    }

    function testGetRedeemableAmountBeforeResolutionReturnsZero() public {
        _stakeAs(winners[0], STAKE_AMOUNT);
        (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet) = viewHelper.getRedeemableAmount(
            ct, winners[0], IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets
        );
        assertEq(payoutGross, 0);
        assertEq(feeAmount, 0);
        assertEq(payoutNet, 0);
    }

    function testGetRedeemableAmountAfterFullRedeemReturnsZero() public {
        _stakeAs(winners[0], STAKE_AMOUNT);
        ct.reportPayouts(questionId, payouts);

        vm.prank(winners[0]);
        ct.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets);

        (uint256 payoutGross, uint256 feeAmount, uint256 payoutNet) = viewHelper.getRedeemableAmount(
            ct, winners[0], IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets
        );
        assertEq(payoutGross, 0);
        assertEq(feeAmount, 0);
        assertEq(payoutNet, 0);
    }

    function testClaimFeesRevertsWhenNoFees() public {
        vm.expectRevert("No fees to claim");
        ct.claimFees();
    }

    function testSetFeeConfigZeroFeeNoDeduction() public {
        ct.setFeeConfig(feeCollector, 0);

        _stakeAs(winners[0], STAKE_AMOUNT);
        ct.reportPayouts(questionId, payouts);

        (, uint256 feeAmount, uint256 payoutNet) = viewHelper.getRedeemableAmount(
            ct, winners[0], IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets
        );
        assertEq(feeAmount, 0);
        assertEq(payoutNet, STAKE_AMOUNT);

        uint256 before = collateral.balanceOf(winners[0]);
        vm.prank(winners[0]);
        ct.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, winningIndexSets);
        assertEq(collateral.balanceOf(winners[0]) - before, STAKE_AMOUNT);
        assertEq(ct.accumulatedFees(), 0);
    }
}
