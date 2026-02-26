# CRE Workflow Report: onReport and _processReport

This document describes how to build and send reports for the Chainlink CRE (Contract Report Encoding) workflow. Both **Sub0** and **PredictionVault** implement a receiver that accepts `onReport(metadata, report)`. Only the configured **forwarder address** may call `onReport`; the first byte of `report` is the **action prefix** and the rest is the **payload** (ABI-encoded arguments).

---

## 1. Entry Point

| Contract        | Method                | Restriction                          |
|----------------|-----------------------|--------------------------------------|
| Sub0           | `onReport(metadata, report)` | Caller must equal configured forwarder (set at init / `setForwarderAddress`) |
| PredictionVault| `onReport(metadata, report)` | Caller must equal configured forwarder (`ReceiverTemplate` / constructor)     |

- **metadata**: Forwarder-supplied (workflow id, name, owner); optional validation is configurable on the contract.
- **report**: `bytes` = **prefix (1 byte)** + **abi.encode(...payload)**. The contract routes on `report[0]` and decodes `report[1:]` as the payload for that action.

---

## 2. Sub0 CRE Actions (_processReport)

Sub0 routes on the first byte of `report`. All resolve/stake/redeem payloads include the **account that is acting** (oracle or owner).

### 2.1 Action Prefixes (Sub0)

| Prefix | Constant              | Action   | Payload (after prefix) |
|--------|------------------------|----------|-------------------------|
| `0x00` | CRE_ACTION_CREATE     | Create market | `abi.encode(Market)` |
| `0x01` | CRE_ACTION_RESOLVE    | Resolve market | `abi.encode(questionId, payouts, oracle)` |
| `0x02` | CRE_ACTION_STAKE      | Stake on behalf of owner | `abi.encode(questionId, parentCollectionId, partition, token, amount, owner)` |
| `0x03` | CRE_ACTION_REDEEM     | Redeem on behalf of owner (with signature) | `abi.encode(parentCollectionId, conditionId, indexSets, token, owner, deadline, nonce, signature)` |

### 2.2 Payload Layout and Types (Sub0)

**0x00 Create**

- **Payload:** `abi.encode(Market)`
- **Market** (struct): `question` (string), `conditionId` (bytes32), `oracle` (address), `owner` (address), `createdAt` (uint256), `duration` (uint256), `outcomeSlotCount` (uint256), `oracleType` (uint8), `marketType` (uint8).
- **oracleType:** 0=NONE, 1=PLATFORM, 2=ARBITRATOR, 3=CUSTOM.
- **marketType:** 0=Private, 1=Public. Public requires creator to have GAME_CREATOR_ROLE.
- **Note:** `conditionId` and `createdAt` are overwritten by the contract; you can pass `bytes32(0)` and `0` when encoding.

**0x01 Resolve**

- **Payload:** `abi.encode(questionId, payouts, oracle)`
- **questionId:** bytes32 (market id).
- **payouts:** uint256[] (payout numerators per outcome; length must match market’s outcomeSlotCount).
- **oracle:** address that must equal `markets[questionId].oracle`.

**0x02 Stake**

- **Payload:** `abi.encode(questionId, parentCollectionId, partition, token, amount, owner)`
- **questionId:** bytes32.
- **parentCollectionId:** bytes32 (use `bytes32(0)` for root).
- **partition:** uint256[] (e.g. `[1, 2]` for two outcomes; index sets).
- **token:** address (collateral ERC20, must be allowlisted).
- **amount:** uint256 (collateral amount).
- **owner:** address that receives the conditional tokens (CTF positions).

**0x03 Redeem**

- **Payload:** `abi.encode(parentCollectionId, conditionId, indexSets, token, owner, deadline, nonce, signature)`
- **parentCollectionId:** bytes32.
- **conditionId:** bytes32 (from market).
- **indexSets:** uint256[] (which index sets to redeem).
- **token:** address (payout token).
- **owner:** address that owns the positions and whose signature is required.
- **deadline:** uint256 (timestamp; must be >= block.timestamp when report is processed).
- **nonce:** uint256 (owner’s current redeem nonce; use `sub0.redeemNonce(owner)`).
- **signature:** bytes (EIP-712 signature from `owner` over the Redeem typed data).

**Redeem EIP-712 (Sub0)**

- **Domain:** name `"Sub0"`, version `"1"`, chainId, verifyingContract = Sub0 proxy address.
- **Type:** `Redeem(bytes32 parentCollectionId,bytes32 conditionId,bytes32 indexSetsHash,address token,uint256 deadline,uint256 nonce)`
- **indexSetsHash:** `keccak256(abi.encode(indexSets))`.
- The contract exposes **`getRedeemDigest(parentCollectionId, conditionId, indexSetsHash, token, deadline, nonce)`** so the backend can compute the digest to sign. Recover signer from signature; must equal `owner`. After a successful redeem, `redeemNonce[owner]` is incremented.

### 2.3 Backend Encoding Examples (Sub0)

Report bytes = **prefix** concatenated with **payload**:

- **Create:** `report = 0x00 || abi.encode(marketStruct)`
- **Resolve:** `report = 0x01 || abi.encode(questionId, payouts, oracle)`
- **Stake:** `report = 0x02 || abi.encode(questionId, parentCollectionId, partition, token, amount, owner)`
- **Redeem:**  
  1. Compute `indexSetsHash = keccak256(abi.encode(indexSets))`.  
  2. Get digest via `getRedeemDigest(parentCollectionId, conditionId, indexSetsHash, token, deadline, nonce)`.  
  3. Have `owner` sign the digest (EIP-712).  
  4. `report = 0x03 || abi.encode(parentCollectionId, conditionId, indexSets, token, owner, deadline, nonce, signature)`

### 2.4 Sub0 CRE Errors

| Error | When |
|-------|------|
| CREReportTooShort | `report.length == 0` |
| CREUnknownAction | First byte is not 0x00–0x03 |
| RedeemExpired | Redeem: `block.timestamp > deadline` |
| RedeemBadNonce | Redeem: `redeemNonce[signer] != nonce` |
| RedeemInvalidSignature | Redeem: recovered signer != `owner` |
| (Plus existing contract errors, e.g. NotAuthorized, QuestionAlreadyExists, etc.) |

---

## 3. PredictionVault CRE Actions (_processReport)

PredictionVault routes on the first byte of `report` to either execute a trade or seed liquidity.

### 3.1 Action Prefixes (PredictionVault)

| Prefix | Constant                    | Action              | Payload (after prefix) |
|--------|-----------------------------|---------------------|-------------------------|
| `0x00` | CRE_ACTION_EXECUTE_TRADE    | Execute dual-sig trade | `abi.encode(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)` |
| `0x01` | CRE_ACTION_SEED_LIQUIDITY   | Seed market liquidity | `abi.encode(questionId, amountUsdc)` |

### 3.2 Payload Layout and Types (PredictionVault)

**0x00 Execute trade**

- **Payload:** `abi.encode(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)`
- **questionId:** bytes32.
- **outcomeIndex:** uint256 (0-based).
- **buy:** bool (true = user buys outcome tokens).
- **quantity:** uint256 (outcome token amount, 18 decimals).
- **tradeCostUsdc:** uint256 (USDC amount from DON quote, 6 decimals).
- **maxCostUsdc:** uint256 (user’s max pay (buy) or min receive (sell)).
- **nonce:** uint256 (per-market; must not be already used).
- **deadline:** uint256 (quote expiry).
- **user:** address (pays USDC on buy / receives on sell).
- **donSignature:** bytes (EIP-712 DONQuote signature from donSigner).
- **userSignature:** bytes (EIP-712 UserTrade signature from user).

**0x01 Seed liquidity**

- **Payload:** `abi.encode(questionId, amountUsdc)`
- **questionId:** bytes32 (must be registered in PredictionVault).
- **amountUsdc:** uint256 (6 decimals). USDC is pulled from **msg.sender** (the forwarder); the forwarder must be the **owner** of PredictionVault and must have approved USDC to the vault.

### 3.3 Backend Encoding Examples (PredictionVault)

- **Execute trade:**  
  `report = 0x00 || abi.encode(questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature)`
- **Seed liquidity:**  
  `report = 0x01 || abi.encode(questionId, amountUsdc)`

### 3.4 PredictionVault CRE Errors

| Error | When |
|-------|------|
| CREReportTooShort | `report.length == 0` |
| CREUnknownAction | First byte is not 0x00 or 0x01 |
| CRESeedLiquidityNotOwner | Seed liquidity: `msg.sender` (forwarder) is not owner |
| (Plus executeTrade errors: ExpiredQuote, NonceAlreadyUsed, InvalidDonSignature, InvalidUserSignature, SlippageExceeded, MarketNotRegistered, InvalidOutcome, TransferFailed, InsufficientVaultBalance, InsufficientUsdcSolvency) |

---

## 4. Summary Table: Report Format

| Contract        | Prefix | Action           | Payload summary |
|----------------|--------|------------------|------------------|
| **Sub0**       | 0x00   | Create           | Market struct |
| **Sub0**       | 0x01   | Resolve          | questionId, payouts, oracle |
| **Sub0**       | 0x02   | Stake            | questionId, parentCollectionId, partition, token, amount, owner |
| **Sub0**       | 0x03   | Redeem           | parentCollectionId, conditionId, indexSets, token, owner, deadline, nonce, signature |
| **PredictionVault** | 0x00 | Execute trade    | questionId, outcomeIndex, buy, quantity, tradeCostUsdc, maxCostUsdc, nonce, deadline, user, donSignature, userSignature |
| **PredictionVault** | 0x01 | Seed liquidity   | questionId, amountUsdc |

---

## 5. Workflow Integration Notes

1. **Forwarder:** The CRE forwarder contract is the only address allowed to call `onReport`. Set Sub0’s forwarder at init or via `setForwarderAddress`; set PredictionVault’s at construction or via `setCreForwarder` (if exposed).
2. **Two receivers:** Sub0 and PredictionVault are separate receivers. The backend must send the report to the correct contract (Sub0 for create/resolve/stake/redeem; PredictionVault for executeTrade and seedMarketLiquidity).
3. **Redeem nonce:** For Sub0 redeem (0x03), the backend must use the current `redeemNonce(owner)` and ensure the owner signs the exact Redeem params; after success the nonce increments.
4. **Seed liquidity:** For PredictionVault 0x01, the account calling `onReport` (the forwarder) must be the owner of PredictionVault and must have approved USDC to the vault for `amountUsdc`.

This report is the reference for building CRE workflow reports for Sub0 and PredictionVault.
