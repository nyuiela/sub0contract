# Sub0 Contracts and Functions for CRE

Report on contracts and functions the CRE (backend / AI agents) uses to integrate with the Sub0 prediction market stack: market creation, liquidity seeding, LMSR quoting and signing, and resolution.

---

## 1. Overview

CRE interacts with:

| Contract | CRE role |
|----------|-----------|
| **Sub0** | Source of truth for markets (`questionId`, `conditionId`, `oracle`, `outcomeSlotCount`). CRE does not call Sub0 directly for trading; CRE signs quotes and users call PredictionVault. |
| **PredictionVault** | Execution layer for inventory trades. CRE **signs EIP-712 quotes**; users call `executeTrade`. Optionally CRE (as platform) calls `seedMarketLiquidity`. |
| **ConditionalTokensV2 (CTF)** | CRE uses **view functions** only: derive `conditionId`, `collectionId`, `positionId`, read `outcomeSlotCount` and vault balances. No CRE-sent write calls. |
| **Vault (VaultV2)** | CRE does not call. Sub0 calls `prepareCondition` / `resolveCondition`; oracle resolution is done via Sub0.`resolve`. |

Contract addresses come from deployment (e.g. `just deploy`) or `.env` / config.

---

## 2. Sub0 (Factory)

**Purpose:** Create markets, prepare conditions in the vault, register markets with PredictionVault, resolve outcomes, and gate staking/redemption via CTF.

### 2.1 Functions CRE Uses (Read-Only)

| Function | Returns | Use in CRE |
|----------|---------|------------|
| `getMarket(bytes32 questionId)` | `Market` | Get `conditionId`, `outcomeSlotCount`, `oracle`, `owner`, `question`, `duration`, `oracleType`, `marketType`. Required to build quotes and validate markets. |
| `getMarket(bytes32 questionId, address owner, address _oracle)` | `Market` | Same as above when market is keyed by `keccak256(questionId, owner, oracle)`. Prefer `getMarket(questionId)` for standard flow. |
| `predictionVault()` | `address` | Resolve PredictionVault address for `executeTrade` and `getConditionId`. |
| `conditionalToken()` | `address` | CTF address for `getConditionId`, `getCollectionId`, `getPositionId`, `balanceOf`. |
| `vault()` | `address` | Vault address; needed only if CRE ever talks to the vault directly. |

### 2.2 Market and Question IDs

- **questionId** (bytes32): `keccak256(abi.encodePacked(question, creator, oracle))`. Emitted and stored at market creation. CRE must use the same `questionId` the frontend/Sub0 uses for a given market.
- **conditionId** (bytes32): Returned by `getMarket(questionId).conditionId`. In this stack the vault is the CTF “oracle”; conditionId is `keccak256(abi.encodePacked(vaultAddress, questionId, outcomeSlotCount))` (vault computes it when Sub0 calls `prepareCondition`). CRE should **read** `conditionId` from Sub0 or PredictionVault, not recompute.

### 2.3 Functions CRE Does Not Call

- `create`, `stake`, `redeem`, `resolve`, `setConfig`, `addUser`, `acceptInvitation`, etc. are used by the frontend, oracle, or platform; CRE only needs to **read** `getMarket` and contract addresses.

---

## 3. PredictionVault (Dual-Signature Relayer Model)

**Purpose:** DON (CRE) signs the LMSR quote; the user signs an intent (maxCostUsdc). A relayer submits both signatures; USDC is pulled from the user and CTF is sent to the user (gasless for the user).

### 3.1 Functions CRE Must Support (Signing and Invariants)

| Function | Caller | CRE responsibility |
|----------|--------|---------------------|
| `executeTrade(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)` | Relayer | CRE **produces** the DON signature (see EIP-712 below). User (or agent) produces the user signature. Relayer submits both. CRE must ensure: correct `questionId`; `outcomeIndex` in range; `quantity`/`tradeCostUsdc` from LMSR; unique per-market `nonce`; `deadline` in the future; quote includes `user` for DON_QUOTE. |

### 3.2 Functions CRE May Call (Platform / Seeder)

| Function | Caller | CRE responsibility |
|----------|--------|---------------------|
| `seedMarketLiquidity(bytes32 questionId, uint256 amountUsdc)` | Owner (or address that owns PredictionVault) | If CRE/platform seeds liquidity: send USDC to the vault (or have owner call). Vault pulls USDC from `msg.sender`, approves CTF, and calls CTF.`splitPosition` so the vault holds a full outcome set. Only for markets already registered (via Sub0.`create`). |

Note: `registerMarket` is called by Sub0 on `create`; CRE does not call it.

### 3.3 View Functions CRE Uses

| Function | Returns | Use in CRE |
|----------|---------|------------|
| `getConditionId(bytes32 questionId)` | `bytes32 conditionId` | Map `questionId` → `conditionId` for CTF view calls and for quote context. |
| `donSigner()` | `address` | CRE must sign the DON quote with the private key for this address (injected via CRE Secrets). |
| `backendSigner()` | `address` | Legacy; may equal `donSigner`. Prefer `donSigner()` for new flows. |
| `nonceUsed(bytes32 questionId, uint256 nonce)` | `bool` | Before issuing a new quote, CRE should ensure (or track) that this nonce is not yet used for this `questionId`. |

### 3.4 EIP-712: Dual-Signature Model

CRE signs DONQuote; user/agent signs UserTrade. Relayer submits both to `executeTrade`.

- **Domain**
  - `name`: `"Sub0PredictionVault"`
  - `version`: `"1"`
  - `chainId`: current chain id
  - `verifyingContract`: PredictionVault contract address

- **DONQuote** (CRE signs): `DONQuote(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 tradeCostUsdc,address user,uint256 nonce,uint256 deadline)` — marketId = questionId.
- **UserTrade** (user signs): `UserTrade(bytes32 marketId,uint256 outcomeIndex,bool buy,uint256 quantity,uint256 maxCostUsdc,uint256 nonce,uint256 deadline)` — maxCostUsdc = max pay (buy) or min receive (sell).
- **Domain**: name `Sub0PredictionVault`, version `1`, chainId, verifyingContract = PredictionVault.

(Deprecated: single-signature flow. Use dual-signature below.)

CRE must (dual-signature):
1. DON signs DONQuote (marketId, outcomeIndex, buy, quantity, tradeCostUsdc, user, nonce, deadline) with donSigner key.
2. User/agent signs UserTrade (marketId, outcomeIndex, buy, quantity, maxCostUsdc, nonce, deadline).
3. Relayer calls executeTrade(..., user, donSignature, userSignature). DON recovers to donSigner; user sig to user. Contract enforces tradeCostUsdc <= maxCostUsdc (buy) or >= maxCostUsdc (sell).

### 3.5 PredictionVault Errors (for CRE / clients)

| Error | When |
|-------|------|
| `InvalidDonSignature()` | DON signature does not recover to `donSigner`. |
| `InvalidUserSignature()` | User signature does not recover to `user`. |
| `SlippageExceeded()` | Buy: `tradeCostUsdc > maxCostUsdc`. Sell: `tradeCostUsdc < maxCostUsdc`. |
| `ExpiredQuote()` | `block.timestamp > deadline`. |
| `NonceAlreadyUsed()` | This `(questionId, nonce)` was already used. |
| `MarketNotRegistered()` | No `conditionId` registered for `questionId`. |
| `InvalidOutcome()` | `outcomeIndex >= outcomeSlotCount` or invalid market. |
| `TransferFailed()` | USDC transfer failed. |
| `InsufficientVaultBalance()` | Buy: vault does not have enough CTF tokens for this outcome. |
| `InsufficientUsdcSolvency()` | Sell: vault does not have enough USDC to pay the user. |

---

## 4. ConditionalTokensV2 (CTF)

**Purpose:** Holds conditions and outcome positions (ERC-1155). CRE uses **view** and **pure** functions only; trading is done via PredictionVault.

### 4.1 View / Pure Functions CRE Uses

| Function | Returns | Use in CRE |
|----------|---------|------------|
| `getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)` | `bytes32` | Derive conditionId. In this deployment the “oracle” for the vault-backed conditions is the **Vault** address, not Sub0. Prefer reading `conditionId` from Sub0.`getMarket(questionId).conditionId` or PredictionVault.`getConditionId(questionId)`. |
| `getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)` | `bytes32` | For root: `parentCollectionId = bytes32(0)`. `indexSet = 1 << outcomeIndex` (single outcome). Used to compute positionId. |
| `getPositionId(IERC20 collateralToken, bytes32 collectionId)` | `uint256` | ERC-1155 token id for (collateralToken, collectionId). Collateral for PredictionVault is USDC. CRE can use this to reason about positions. |
| `getOutcomeSlotCount(bytes32 conditionId)` | `uint256` | Validate `outcomeIndex < outcomeSlotCount` when building quotes. |
| `balanceOf(address account, uint256 id)` | `uint256` | Check vault inventory: `balanceOf(predictionVaultAddress, positionId)` for a given outcome to ensure solvency for buys. |
| `payoutNumerators(bytes32 conditionId)` | `uint256[]` | After resolution; for payout math. Optional for CRE if CRE does not compute redemption amounts. |
| `payoutDenominator(bytes32 conditionId)` | `uint256` | After resolution. Optional for CRE. |

### 4.2 Position ID Derivation (for CRE logic)

For a given market and outcome:

1. `conditionId = predictionVault.getConditionId(questionId)` (or from Sub0.`getMarket(questionId).conditionId`).
2. `indexSet = 1 << outcomeIndex` (e.g. outcome 0 → 1, outcome 1 → 2).
3. `collectionId = ctf.getCollectionId(bytes32(0), conditionId, indexSet)`.
4. `positionId = ctf.getPositionId(usdcAddress, collectionId)`.

CRE can use this to check vault balance before issuing a buy quote.

### 4.3 Functions CRE Does Not Call

- `prepareCondition`, `reportPayouts`, `splitPosition`, `splitPositionFor`, `mergePositions`, `redeemPositions`, `redeemPositionsFor`, `batchRedeemPositions`, `pause`, `unpause`, admin setters. These are used by Sub0, Vault, PredictionVault, or admins.

---

## 5. Vault (VaultV2)

**Purpose:** Implements `IVault`; prepares and resolves conditions in CTF. Sub0 calls it on `create` and `resolve`. CRE does not call the Vault directly.

- **prepareCondition(questionId, outcomeCount)**  
  Called by Sub0 on market creation. Vault uses itself as the CTF “oracle” and stores condition by `(questionId, game)`.

- **resolveCondition(questionId, payouts)**  
  Called by Sub0.`resolve(questionId, payouts)`; only the market’s oracle may call Sub0.`resolve`.

CRE only needs to know that `conditionId` for a given Sub0 market is the one returned by Sub0 or PredictionVault, not recomputed from an oracle address chosen by CRE.

---

## 6. End-to-End Flows Involving CRE

### 6.1 Market creation (no CRE call)

1. User/platform calls Sub0.`create(market)`.
2. Sub0 calls Vault.`prepareCondition(questionId, outcomeSlotCount)` and, if PredictionVault is set, PredictionVault.`registerMarket(questionId, conditionId)`.
3. CRE can then use `questionId` and `getMarket(questionId)` / `getConditionId(questionId)` for all subsequent logic.

### 6.2 Seeding liquidity (optional; platform)

1. Ensure market exists and is registered in PredictionVault.
2. Caller (owner of PredictionVault or approved) approves USDC to PredictionVault and calls PredictionVault.`seedMarketLiquidity(questionId, amountUsdc)`.
3. Vault receives USDC and mints a full set of outcome tokens via CTF.`splitPosition`.

### 6.3 User buy/sell (CRE signs; user executes)

1. User requests a quote (outcome, side, size).
2. CRE:  
   - Reads `getMarket(questionId)` (or at least `conditionId`, `outcomeSlotCount`).  
   - Optionally checks `nonceUsed(questionId, nonce)` and vault `balanceOf` for the outcome’s `positionId`.  
   - Computes LMSR price and sets `quantity`, `tradeCostUsdc`, `nonce`, `deadline`.  
   - Builds EIP-712 struct and signs with `backendSigner` private key.  
   - Returns quote + signature to the client.
3. User (or agent) signs UserTrade (maxCostUsdc). Relayer calls PredictionVault.`executeTrade(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)`.
4. Vault verifies signature, marks nonce used, and performs USDC/CTF swap.

### 6.4 Resolution and redemption (no CRE signing)

1. Oracle calls Sub0.`resolve(questionId, payouts)`; Sub0 calls Vault.`resolveCondition(questionId, payouts)`.
2. Users redeem via Sub0.`redeem(...)` (which uses CTF.`redeemPositionsFor`). CRE does not need to call these.

---

## 7. Summary: CRE Contract and Function Checklist

| Contract | CRE action | Functions / data |
|----------|------------|-------------------|
| **Sub0** | Read only | `getMarket(questionId)`, `predictionVault()`, `conditionalToken()`, `vault()`. |
| **PredictionVault** | Sign DON quote; optionally seed | Sign EIP-712 DONQuote for `executeTrade`. Read: `getConditionId(questionId)`, `donSigner()`, `nonceUsed(questionId, nonce)`. Optional: `seedMarketLiquidity(questionId, amountUsdc)` (platform). |
| **ConditionalTokensV2** | Read only | `getConditionId`, `getCollectionId`, `getPositionId`, `getOutcomeSlotCount`, `balanceOf(vault, positionId)`. |
| **Vault** | None | No direct CRE calls. |

---

## 8. Constants and Conventions

- **USDC decimals:** 6.
- **Outcome token quantity in quotes:** 18 decimals (CTF uses 18 for positions).
- **questionId:** `keccak256(abi.encodePacked(question, creator, oracle))` (from Sub0.`create`).
- **indexSet for one outcome:** `1 << outcomeIndex` (outcome 0 → 1, outcome 1 → 2, etc.).
- **Parent collection for root positions:** `bytes32(0)`.

This document is the single reference for which contracts and functions CRE should use in the Sub0 stack.
