// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IConditionalTokensV2} from "../conditional/IConditionalTokensV2.sol";
import {IPredictionVault} from "../interfaces/IPredictionVault.sol";
import {ReceiverTemplate} from "./ReceiverTemplate.sol";
import {IPermissionManager} from "../interfaces/IPermissionManager.sol";

/**
 * @title PredictionVault
 * @notice Dual-signature relayer model: DON (CRE) signs LMSR quote; user signs intent (maxCostUsdc).
 *         Relayer submits both signatures; USDC is pulled from user, CTF sent to user (gasless for user).
 *         Holds ConditionalTokensV2 outcome tokens and USDC; executes inventory swaps.
 *         Implements IReceiver for CRE: only the configured forwarder can call onReport; report prefix routes to executeTrade or seedMarketLiquidity.
 */
contract PredictionVault is IPredictionVault, ReceiverTemplate, EIP712, ReentrancyGuard, ERC1155Holder {
    using ECDSA for bytes32;

    uint8 private constant CRE_ACTION_EXECUTE_TRADE = 0x00;
    uint8 private constant CRE_ACTION_SEED_LIQUIDITY = 0x01;

    error CREInvalidSender(address sender, address expected);
    error CREReportTooShort();
    error CREUnknownAction(uint8 prefix);
    error CRESeedLiquidityNotOwner();
    error NotAuthorized(address account, bytes32 role);
    bytes32 public constant DON_QUOTE_TYPEHASH = keccak256(
        "DONQuote(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 tradeCostUsdc,address user,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant USER_TRADE_TYPEHASH = keccak256(
        "UserTrade(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 maxCostUsdc,uint256 nonce,uint256 deadline)"
    );

    IERC20 public usdc;
    IConditionalTokensV2 public ctf;
    address public override backendSigner;
    address public override donSigner;
    IPermissionManager public permissionManager;
    uint256 public constant USDC_DECIMALS = 6;

    mapping(bytes32 => bytes32) private _questionConditionId;
    mapping(bytes32 => mapping(uint256 => bool)) public nonceUsed;
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");
    modifier onlyAuthorized(bytes32 role) {
        if (!permissionManager.hasRole(GAME_CONTRACT_ROLE, msg.sender)) revert NotAuthorized(msg.sender, GAME_CONTRACT_ROLE);
        _;
    }

    constructor(
        address _usdc,
        address _ctf,
        address _backendSigner,
        address _creForwarder,
        address _permissionManager
    ) EIP712("Sub0PredictionVault", "1") ReceiverTemplate(msg.sender, _creForwarder)
     {
        usdc = IERC20(_usdc);
        ctf = IConditionalTokensV2(_ctf);
        backendSigner = _backendSigner;
        donSigner = _backendSigner;
        permissionManager = IPermissionManager(_permissionManager);
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

    function registerMarket(bytes32 questionId, bytes32 conditionId) external override onlyAuthorized(GAME_CONTRACT_ROLE) {
        if (_questionConditionId[questionId] != bytes32(0)) revert InvalidOutcome();
        _questionConditionId[questionId] = conditionId;
        emit MarketRegistered(questionId, conditionId);
    }

    function getConditionId(bytes32 questionId) external view override returns (bytes32) {
        return _questionConditionId[questionId];
    }

    /**
     * @dev Seed initial liquidity: platform sends USDC to vault; vault splits into full outcome set (CTF).
     *      Uses msg.sender for onlyOwner and transferFrom (so CRE forwarder must be owner and approve USDC).
     */
    function seedMarketLiquidity(bytes32 questionId, uint256 amountUsdc) external override onlyOwner {
        _seedMarketLiquidityInternal(questionId, amountUsdc);
    }

    function _seedMarketLiquidityInternal(bytes32 questionId, uint256 amountUsdc) internal nonReentrant {
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
                    DON_QUOTE_TYPEHASH,
                    marketId,
                    outcomeIndex,
                    buy,
                    quantity,
                    tradeCostUsdc,
                    user,
                    nonce,
                    deadline
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
                abi.encode(
                    USER_TRADE_TYPEHASH,
                    marketId,
                    outcomeIndex,
                    buy,
                    quantity,
                    maxCostUsdc,
                    nonce,
                    deadline
                )
            )
        );
    }

    function _getPositionId(bytes32 conditionId, uint256 outcomeIndex) internal view returns (uint256) {
        uint256 indexSet = uint256(1 << outcomeIndex);
        bytes32 collectionId = ctf.getCollectionId(bytes32(0), conditionId, indexSet);
        return ctf.getPositionId(IERC20(usdc), collectionId);
    }

    /**
     * @dev Execute trade using dual-signature: DON quote + user intent. Relayer pays gas; USDC pulled from user, CTF sent to user.
     *      BUY: tradeCostUsdc <= maxCostUsdc; USDC from user to vault; CTF from vault to user.
     *      SELL: tradeCostUsdc >= maxCostUsdc (min receive); CTF from user to vault; USDC from vault to user.
     */
  //  function executeTrades(
  //       bytes32 questionId,
  //       uint256 outcomeIndex,
  //       bool[] calldata buys,
  //       uint256[] calldata quantities,
  //       uint256[] calldata tradeCostUsdc,
  //       uint256[] calldata maxCostUsdc,
  //       uint256 nonce,
  //       uint256 deadline,
  //       address[] calldata users,
  //       bytes calldata donSignature,
  //       bytes[] calldata userSignatures
  //   ) external override nonReentrant {
  //     // require(buys)
  //       if (block.timestamp > deadline) revert ExpiredQuote();
  //       if (nonceUsed[questionId][nonce]) revert NonceAlreadyUsed();

  //       bytes32 conditionId = _questionConditionId[questionId];
  //       if (conditionId == bytes32(0)) revert MarketNotRegistered();

  //       for (uint256 i = 0; i < buys.length; i++) {
  //         bool buy = buys[i];
  //         uint256 quantity = quantities[i];
  //         uint256 _tradeCostUsdc = tradeCostUsdc[i];
  //         uint256 _maxCostUsdc = maxCostUsdc[i];
  //         address user = users[i];
  //         bytes memory userSignature = userSignatures[i];
  //       uint256 outcomeSlotCount = ctf.getOutcomeSlotCount(conditionId);
  //       if (outcomeIndex >= outcomeSlotCount) revert InvalidOutcome();

  //       if (ECDSA.recover(_hashDonQuote(questionId, outcomeIndex, buy, quantity, _tradeCostUsdc, user, nonce, deadline), donSignature) != donSigner) {
  //           revert InvalidDonSignature();
  //       }
  //       if (ECDSA.recover(_hashUserTrade(questionId, outcomeIndex, buy, quantity, _maxCostUsdc, nonce, deadline), userSignature) != user) {
  //           revert InvalidUserSignature();
  //       }

  //       if (buy) {
  //           if (_tradeCostUsdc > _maxCostUsdc) revert SlippageExceeded();
  //       } else {
  //           if (_tradeCostUsdc < _maxCostUsdc) revert SlippageExceeded();
  //       }
  //       }


  //       uint256 positionId = _getPositionId(conditionId, outcomeIndex);

  //       if (buys[0]) {
  //           if (ctf.balanceOf(users[1], positionId) < quantities[1]) revert InsufficientVaultBalance();
  //           if (tradeCostUsdc[0] > 0 && !usdc.transferFrom(users[0], users[1], tradeCostUsdc[1])) revert TransferFailed();
  //           ctf.safeTransferFrom(users[1], users[0], positionId, quantities[1], "");
  //       } else {
  //           if (usdc.balanceOf(users[1]) < tradeCostUsdc[0]) revert InsufficientUsdcSolvency();
  //           ctf.safeTransferFrom(users[0], users[1], positionId, quantities[0], "");
  //           if (tradeCostUsdc[0] > 0 && !usdc.transfer(users[1], tradeCostUsdc[0])) revert TransferFailed();
  //       }

  //       nonceUsed[questionId][nonce] = true;
  //       // emit TradeExecuted(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, user);
  //   }
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

        if (ECDSA.recover(_hashDonQuote(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, user, nonce, deadline), donSignature) != donSigner) {
            revert InvalidDonSignature();
        }
        if (ECDSA.recover(_hashUserTrade(questionId, outcomeIndex, buy, quantity, maxCostUsdc, nonce, deadline), userSignature) != user) {
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

struct Config {
    address permissionManager;
    address usdc;
    address ctf;
    address backendSigner;
    address donSigner;
}
    function setConfig(Config memory _config) external onlyOwner {
        if (_config.permissionManager != address(0)) permissionManager = IPermissionManager(_config.permissionManager);
        if (_config.usdc != address(0)) usdc = IERC20(_config.usdc);
        if (_config.ctf != address(0)) ctf = IConditionalTokensV2(_config.ctf);
        if (_config.backendSigner != address(0)) backendSigner = _config.backendSigner;
        if (_config.donSigner != address(0)) donSigner = _config.donSigner;
    }



    /// @dev Routes CRE reports by prefix. Backend sends: prefix (1 byte) + abi.encode(...payload).
    ///      - 0x00: executeTrade → payload = abi.encode(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)
    ///      - 0x01: seedMarketLiquidity → payload = abi.encode(questionId, amountUsdc). Caller (forwarder) must be owner and must approve USDC.
    function _processReport(bytes calldata report) internal override {
        if (report.length == 0) revert CREReportTooShort();
        uint8 action = uint8(report[0]);
        bytes calldata payload = report[1:];

        if (action == CRE_ACTION_EXECUTE_TRADE) {
            (
                bytes32 questionId,
                uint256 outcomeIndex,
                bool buy,
                uint256 quantity,
                uint256 tradeCostUsdc,
                uint256 maxCostUsdc,
                uint256 nonce,
                uint256 deadline,
                address user,
                bytes memory donSignature,
                bytes memory userSignature
            ) = abi.decode(payload, (bytes32, uint256, bool, uint256, uint256, uint256, uint256, uint256, address, bytes, bytes));
            this.executeTrade(
                questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc,
                nonce, deadline, user, donSignature, userSignature
            );
            return;
        }
        if (action == CRE_ACTION_SEED_LIQUIDITY) {
            (bytes32 questionId, uint256 amountUsdc) = abi.decode(payload, (bytes32, uint256));
            _seedMarketLiquidityInternal(questionId, amountUsdc);
            return;
        }
        revert CREUnknownAction(action);
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override(ERC1155Holder, ReceiverTemplate) returns (bool) {
        return interfaceId == type(ReceiverTemplate).interfaceId
            || interfaceId == type(ERC1155Holder).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }


}
