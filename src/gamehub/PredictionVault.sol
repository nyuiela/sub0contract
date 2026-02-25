// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IConditionalTokensV2} from "../conditional/IConditionalTokensV2.sol";
import {IPredictionVault} from "../interfaces/IPredictionVault.sol";
// import {ReceivableTemplate} from "../templates/ReceivableTemplate.sol";

/**
 * @title PredictionVault
 * @notice Dual-signature relayer model: DON (CRE) signs LMSR quote; user signs intent (maxCostUsdc).
 *         Relayer submits both signatures; USDC is pulled from user, CTF sent to user (gasless for user).
 *         Holds ConditionalTokensV2 outcome tokens and USDC; executes inventory swaps.
 */
contract PredictionVault is IPredictionVault, EIP712, Ownable, ReentrancyGuard, ERC1155Holder {
    using ECDSA for bytes32;

    bytes32 public constant DON_QUOTE_TYPEHASH = keccak256(
        "DONQuote(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 tradeCostUsdc,address user,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant USER_TRADE_TYPEHASH = keccak256(
        "UserTrade(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 maxCostUsdc,uint256 nonce,uint256 deadline)"
    );

    IERC20 public immutable usdc;
    IConditionalTokensV2 public immutable ctf;
    address public override backendSigner;
    address public override donSigner;

    uint256 public constant USDC_DECIMALS = 6;

    mapping(bytes32 => bytes32) private _questionConditionId;
    mapping(bytes32 => mapping(uint256 => bool)) public nonceUsed;

    constructor(address _usdc, address _ctf, address _backendSigner)
        EIP712("Sub0PredictionVault", "1")
        Ownable(msg.sender)
    {
        usdc = IERC20(_usdc);
        ctf = IConditionalTokensV2(_ctf);
        // __ReceivableTemplate_init(msg.sender, );
        backendSigner = _backendSigner;
        donSigner = _backendSigner;
    }

    function setBackendSigner(address _backendSigner) external onlyOwner {
        address old = backendSigner;
        backendSigner = _backendSigner;
        emit BackendSignerSet(old, _backendSigner);
    }

    function setDonSigner(address _donSigner) external onlyOwner {
        address old = donSigner;
        donSigner = _donSigner;
        emit DonSignerSet(old, _donSigner);
    }

    function registerMarket(bytes32 questionId, bytes32 conditionId) external override onlyOwner {
        if (conditionId == bytes32(0)) revert InvalidOutcome();
        if (_questionConditionId[questionId] != bytes32(0)) revert InvalidOutcome();
        _questionConditionId[questionId] = conditionId;
        emit MarketRegistered(questionId, conditionId);
    }

    function getConditionId(bytes32 questionId) external view override returns (bytes32) {
        return _questionConditionId[questionId];
    }

    /**
     * @dev Seed initial liquidity: platform sends USDC to vault; vault splits into full outcome set (CTF).
     */
    function seedMarketLiquidity(bytes32 questionId, uint256 amountUsdc) external override onlyOwner nonReentrant {
        bytes32 conditionId = _questionConditionId[questionId];
        if (conditionId == bytes32(0)) revert MarketNotRegistered();

        uint256 outcomeSlotCount = ctf.getOutcomeSlotCount(conditionId);
        if (outcomeSlotCount < 2) revert InvalidOutcome();

        if (amountUsdc > 0 && !usdc.transferFrom(msg.sender, address(this), amountUsdc)) revert TransferFailed();

        uint256[] memory partition = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount;) {
            partition[i] = uint256(1 << i);
            unchecked {
                ++i;
            }
        }

        if (amountUsdc > 0) {
            usdc.approve(address(ctf), amountUsdc);
            ctf.splitPosition(IERC20(usdc), bytes32(0), conditionId, partition, amountUsdc);
            usdc.approve(address(ctf), 0);
        }

        emit MarketLiquiditySeeded(questionId, amountUsdc);
    }

    function _hashDonQuote(
        bytes32 marketId,
        uint256 outcomeIndex,
        bool buy,
        uint256 quantity,
        uint256 tradeCostUsdc,
        address user,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    DON_QUOTE_TYPEHASH, marketId, outcomeIndex, buy, quantity, tradeCostUsdc, user, nonce, deadline
                )
            )
        );
    }

    function _hashUserTrade(
        bytes32 marketId,
        uint256 outcomeIndex,
        bool buy,
        uint256 quantity,
        uint256 maxCostUsdc,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(USER_TRADE_TYPEHASH, marketId, outcomeIndex, buy, quantity, maxCostUsdc, nonce, deadline)
            )
        );
    }

    function _getPositionId(bytes32 conditionId, uint256 outcomeIndex) internal view returns (uint256) {
        uint256 indexSet = uint256(1 << outcomeIndex);
        bytes32 collectionId = ctf.getCollectionId(bytes32(0), conditionId, indexSet);
        return ctf.getPositionId(IERC20(usdc), collectionId);
    }

    /**
     * @dev Execute trade (dual-signature): DON quote + user intent. Relayer pays gas; USDC pulled from user, CTF sent to user.
     *      BUY: tradeCostUsdc <= maxCostUsdc; USDC from user to vault; CTF from vault to user.
     *      SELL: tradeCostUsdc >= maxCostUsdc (min receive); CTF from user to vault; USDC from vault to user.
     */
    function executeTrade(
        bytes32 questionId,
        uint256 outcomeIndex,
        bool buy,
        uint256 quantity,
        uint256 tradeCostUsdc,
        uint256 maxCostUsdc,
        uint256 nonce,
        uint256 deadline,
        address user,
        bytes calldata donSignature,
        bytes calldata userSignature
    ) external override nonReentrant {
        if (block.timestamp > deadline) revert ExpiredQuote();
        if (nonceUsed[questionId][nonce]) revert NonceAlreadyUsed();

        bytes32 conditionId = _questionConditionId[questionId];
        if (conditionId == bytes32(0)) revert MarketNotRegistered();

        uint256 outcomeSlotCount = ctf.getOutcomeSlotCount(conditionId);
        if (outcomeIndex >= outcomeSlotCount) revert InvalidOutcome();

        if (
            ECDSA.recover(
                    _hashDonQuote(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, user, nonce, deadline),
                    donSignature
                ) != donSigner
        ) {
            revert InvalidDonSignature();
        }
        if (
            ECDSA.recover(
                    _hashUserTrade(questionId, outcomeIndex, buy, quantity, maxCostUsdc, nonce, deadline), userSignature
                ) != user
        ) {
            revert InvalidUserSignature();
        }

        if (buy) {
            if (tradeCostUsdc > maxCostUsdc) revert SlippageExceeded();
        } else {
            if (tradeCostUsdc < maxCostUsdc) revert SlippageExceeded();
        }

        nonceUsed[questionId][nonce] = true;

        uint256 positionId = _getPositionId(conditionId, outcomeIndex);

        if (buy) {
            if (ctf.balanceOf(address(this), positionId) < quantity) revert InsufficientVaultBalance();
            if (tradeCostUsdc > 0 && !usdc.transferFrom(user, address(this), tradeCostUsdc)) revert TransferFailed();
            ctf.safeTransferFrom(address(this), user, positionId, quantity, "");
        } else {
            if (usdc.balanceOf(address(this)) < tradeCostUsdc) revert InsufficientUsdcSolvency();
            ctf.safeTransferFrom(user, address(this), positionId, quantity, "");
            if (tradeCostUsdc > 0 && !usdc.transfer(user, tradeCostUsdc)) revert TransferFailed();
        }

        emit TradeExecuted(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, user);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Holder) returns (bool) {
        return ERC1155Holder.supportsInterface(interfaceId);
    }
}
