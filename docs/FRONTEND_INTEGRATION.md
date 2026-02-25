# MeVsYou Contract - Frontend Integration Guide

## Table of Contents
1. [Overview](#overview)
2. [Contract Addresses & Setup](#contract-addresses--setup)
3. [Data Structures](#data-structures)
4. [Enums](#enums)
5. [Core Functions](#core-functions)
6. [Integration Flow](#integration-flow)
7. [Events](#events)
8. [Error Handling](#error-handling)
9. [Token Approvals](#token-approvals)
10. [Permission Requirements](#permission-requirements)
11. [Example Code](#example-code)

---

## Overview

The `MeVsYou` contract is a betting platform that allows users to create bets, stake tokens on outcomes, and resolve bets through various oracle mechanisms. The contract integrates with:

- **Vault**: Manages collateral and conditional tokens
- **Hub**: Manages game lifecycle and permissions
- **InvitationManager**: Handles user invitations for private bets
- **TokensManager**: Manages allowed tokens and price feeds

---

## Contract Addresses & Setup

### Required Contract Addresses

You'll need the following contract addresses (typically from your deployment):

```typescript
const CONTRACTS = {
  meVsYou: "0x...",           // MeVsYou contract address
  vault: "0x...",              // Vault contract address
  hub: "0x...",               // Hub contract address
  tokenManager: "0x...",       // TokensManager contract address
  permissionManager: "0x...", // PermissionManager contract address
  conditionalTokens: "0x...",  // ConditionalTokensV2 contract address
};
```

### ABI Imports

You'll need ABIs for:
- `MeVsYou.sol`
- `IVault.sol`
- `IHub.sol`
- `ITokensManager.sol`
- `ERC20` (for token approvals)

---

## Data Structures

### Bet Struct

```typescript
interface Bet {
  question: string;              // The bet question/description
  conditionId: bytes32;          // Condition ID from Vault (auto-generated)
  oracle: address;                // Oracle address that will resolve the bet
  owner: address;                 // Address that created the bet
  createdAt: uint256;             // Timestamp when bet was created
  duration: uint256;               // Duration of the bet in seconds
  outcomeSlotCount: uint256;       // Number of possible outcomes (2-255)
  oracleType: OracleType;         // Type of oracle (enum)
  betType: InvitationType;         // Type of bet (enum)
}
```

### Config Struct

```typescript
interface Config {
  hub: address;
  vault: address;
  tokenManager: address;
  permissionManager: address;
}
```

---

## Enums

### OracleType

```typescript
enum OracleType {
  NONE = 0,      // Invalid/not set
  PLATFORM = 1,  // Platform-managed oracle (must be allowed in Hub)
  ARBITRATOR = 2, // Arbitrator oracle (can be any address)
  CUSTOM = 3     // Custom oracle (must be allowed in Hub)
}
```

### InvitationType

```typescript
enum InvitationType {
  Single = 0,   // 1:1 bet (requires invitation)
  Group = 1,    // 1:n private bet (requires invitation)
  Public = 2    // 1:n public bet (no invitation needed)
}
```

### InvitationStatus

```typescript
enum InvitationStatus {
  None = 0,      // No invitation
  Pending = 1,   // Invitation sent, awaiting acceptance
  Accepted = 2,  // Invitation accepted
  Rejected = 3,  // Invitation rejected
  Banned = 4     // User banned from bet
}
```

---

## Core Functions

### 1. createBet

Creates a new bet and prepares the condition in the Vault.

**Function Signature:**
```solidity
function createBet(Bet memory bet) public returns (bytes32 questionId)
```

**Parameters:**
```typescript
interface CreateBetParams {
  question: string;              // REQUIRED: Bet question/description
  oracle: string;                 // REQUIRED: Oracle address (must be valid for oracleType)
  duration: bigint;                // REQUIRED: Duration in seconds (> 0)
  outcomeSlotCount: number;       // REQUIRED: Number of outcomes (2-255)
  oracleType: OracleType;         // REQUIRED: Type of oracle (1-3, not 0)
  betType: InvitationType;        // REQUIRED: Bet type (0=Single, 1=Group, 2=Public)
}
```

**Returns:**
- `bytes32 questionId` - Unique identifier for the bet

**Validation Rules:**
- `duration > 0`
- `outcomeSlotCount >= 2 && outcomeSlotCount <= 255`
- `oracleType != NONE (0)`
- For `Public` bets: caller must have `GAME_CREATOR_ROLE` (unless they have it)
- For `PLATFORM` or `CUSTOM` oracle types: oracle must be allowed in Hub
- `questionId` must be unique (derived from `question + owner + oracle`)

**Example:**
```typescript
const betParams = {
  question: "Will Team A win the match?",
  oracle: "0x...", // Oracle address
  duration: 86400, // 1 day in seconds
  outcomeSlotCount: 2, // Yes/No
  oracleType: 1, // PLATFORM
  betType: 2, // Public
};

const tx = await meVsYouContract.createBet(betParams);
const receipt = await tx.wait();
const questionId = receipt.events.find(e => e.event === "BetCreated")?.args?.questionId;
```

**Important Notes:**
- The `questionId` is calculated as: `keccak256(question + msg.sender + oracle)`
- For `Single` and `Group` bets, an invitation is automatically created for the owner
- The function automatically calls `vault.prepareCondition()` to set up conditional tokens

---

### 2. stake

Stakes tokens on a specific outcome of a bet.

**Function Signature:**
```solidity
function stake(
  bytes32 questionId,
  uint256 optionIndex,
  address token,
  uint256 amount
) public
```

**Parameters:**
```typescript
interface StakeParams {
  questionId: string;    // REQUIRED: Bet question ID (bytes32)
  optionIndex: number;   // REQUIRED: Outcome index (0-indexed, must be < outcomeSlotCount)
  token: string;         // REQUIRED: ERC20 token address (must be allowed in TokensManager)
  amount: bigint;        // REQUIRED: Amount to stake (in token's native decimals)
}
```

**Validation Rules:**
- `questionId != bytes32(0)`
- `token != address(0)`
- Token must be allowed in `TokensManager`
- For `Single` or `Group` bets: user must have `Accepted` invitation status
- `optionIndex` must be valid (checked by Vault)

**Prerequisites:**
1. User must approve the Vault contract to spend tokens
2. For `Single`/`Group` bets: User must be invited and have accepted invitation
3. Token must be allowed in TokensManager

**Example:**
```typescript
// 1. Check invitation status (for Single/Group bets)
const invitationStatus = await meVsYouContract.getInvitationStatus(questionId, userAddress);
if (invitationStatus !== 2) { // Not Accepted
  throw new Error("User must accept invitation first");
}

// 2. Approve token (if not already approved)
const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
const vaultAddress = await meVsYouContract.vault();
const approveTx = await tokenContract.approve(vaultAddress, amount);
await approveTx.wait();

// 3. Stake
const stakeTx = await meVsYouContract.stake(questionId, optionIndex, tokenAddress, amount);
await stakeTx.wait();
```

---

### 3. redeem

Redeems winning conditional tokens after a bet is resolved.

**Function Signature:**
```solidity
function redeem(bytes32 questionId, uint256 optionIndex) public
```

**Parameters:**
```typescript
interface RedeemParams {
  questionId: string;   // REQUIRED: Bet question ID
  optionIndex: number;  // REQUIRED: Winning outcome index
}
```

**Prerequisites:**
1. Bet must be resolved (`resolve()` called)
2. User must have staked on the winning outcome
3. User must approve ConditionalTokensV2 contract for the Vault

**Example:**
```typescript
// 1. Check if bet is resolved (check BetResolved event or call getBet)
const bet = await meVsYouContract.getBet(questionId);
// Bet is resolved when oracle has called resolve()

// 2. Approve conditional tokens (if needed)
const conditionalTokensAddress = await vaultContract.conditionalTokens();
const conditionalTokens = new ethers.Contract(conditionalTokensAddress, CONDITIONAL_TOKENS_ABI, signer);
const vaultAddress = await meVsYouContract.vault();
const setApprovalTx = await conditionalTokens.setApprovalForAll(vaultAddress, true);
await setApprovalTx.wait();

// 3. Redeem
const redeemTx = await meVsYouContract.redeem(questionId, winningOptionIndex);
await redeemTx.wait();
```

---

### 4. resolve

Resolves a bet by reporting payouts. **Only callable by the bet's oracle address.**

**Function Signature:**
```solidity
function resolve(bytes32 questionId, uint256[] calldata payouts) public
```

**Parameters:**
```typescript
interface ResolveParams {
  questionId: string;      // REQUIRED: Bet question ID
  payouts: number[];       // REQUIRED: Array of payout numerators for each outcome
}
```

**Validation Rules:**
- `msg.sender == bets[questionId].oracle` (only the oracle can resolve)
- `payouts.length == outcomeSlotCount`
- Payouts are typically `[0, 10000]` for winner, `[10000, 0]` for loser (denominator is 10000)

**Example:**
```typescript
// Only the oracle address can call this
const bet = await meVsYouContract.getBet(questionId);
if (bet.oracle.toLowerCase() !== signer.address.toLowerCase()) {
  throw new Error("Only the oracle can resolve this bet");
}

// For a 2-outcome bet where option 0 wins:
const payouts = [10000, 0]; // 100% to option 0, 0% to option 1

const resolveTx = await meVsYouContract.resolve(questionId, payouts);
await resolveTx.wait();
```

---

### 5. getBet

Retrieves bet information.

**Function Signature:**
```solidity
function getBet(bytes32 questionId) public view returns (Bet memory)
function getBet(bytes32 questionId, address owner, address _oracle) public view returns (Bet memory)
```

**Parameters:**
```typescript
// Option 1: Direct lookup
const questionId: string;

// Option 2: Reconstruct questionId
const questionId: string;
const owner: string;
const oracle: string;
```

**Returns:**
```typescript
interface Bet {
  question: string;
  conditionId: string;
  oracle: string;
  owner: string;
  createdAt: bigint;
  duration: bigint;
  outcomeSlotCount: number;
  oracleType: number;
  betType: number;
}
```

**Example:**
```typescript
const bet = await meVsYouContract.getBet(questionId);
console.log("Question:", bet.question);
console.log("Outcomes:", bet.outcomeSlotCount);
console.log("Oracle:", bet.oracle);
```

---

## Invitation Management Functions

### 6. addUser

Adds a user to a bet (bet owner only, for Single/Group bets).

**Function Signature:**
```solidity
function addUser(bytes32 questionId, address user) external
```

**Parameters:**
```typescript
interface AddUserParams {
  questionId: string;  // REQUIRED: Bet question ID
  user: string;        // REQUIRED: User address to invite
}
```

**Validation:**
- Only bet owner can call
- For `Single`: User must not already be invited
- For `Group`: Sets status to `Pending`
- For `Public`: No-op (users can join directly)

**Example:**
```typescript
const addUserTx = await meVsYouContract.addUser(questionId, userAddress);
await addUserTx.wait();
```

---

### 7. acceptInvitation

Accepts a pending invitation (user calls this).

**Function Signature:**
```solidity
function acceptInvitation(bytes32 questionId) external
```

**Parameters:**
```typescript
interface AcceptInvitationParams {
  questionId: string;  // REQUIRED: Bet question ID
}
```

**Validation:**
- User must have `Pending` invitation status
- For `Public` bets: Automatically sets to `Accepted`

**Example:**
```typescript
// Check status first
const status = await meVsYouContract.getInvitationStatus(questionId, userAddress);
if (status === 1) { // Pending
  const acceptTx = await meVsYouContract.acceptInvitation(questionId);
  await acceptTx.wait();
}
```

---

### 8. joinGroup

Joins a Group or Public bet (alternative to acceptInvitation for Public bets).

**Function Signature:**
```solidity
function joinGroup(bytes32 questionId) external
```

**Parameters:**
```typescript
interface JoinGroupParams {
  questionId: string;  // REQUIRED: Bet question ID
}
```

**Example:**
```typescript
const joinTx = await meVsYouContract.joinGroup(questionId);
await joinTx.wait();
```

---

### 9. getInvitationStatus

Gets the invitation status for a user.

**Function Signature:**
```solidity
function getInvitationStatus(bytes32 questionId, address user) external view returns (InvitationStatus)
```

**Returns:**
- `0` = None
- `1` = Pending
- `2` = Accepted
- `3` = Rejected
- `4` = Banned

**Example:**
```typescript
const status = await meVsYouContract.getInvitationStatus(questionId, userAddress);
const statusNames = ["None", "Pending", "Accepted", "Rejected", "Banned"];
console.log("Status:", statusNames[status]);
```

---

## Integration Flow

### Complete Flow: Create Bet → Invite Users → Stake → Resolve → Redeem

```typescript
// 1. CREATE BET
const betParams = {
  question: "Will it rain tomorrow?",
  oracle: oracleAddress,
  duration: 86400,
  outcomeSlotCount: 2,
  oracleType: 2, // ARBITRATOR
  betType: 1, // Group
};

const createTx = await meVsYouContract.createBet(betParams);
const receipt = await createTx.wait();
const questionId = receipt.events.find(e => e.event === "BetCreated")?.args?.questionId;

// 2. INVITE USERS (for Single/Group bets)
const users = [user1Address, user2Address];
for (const user of users) {
  await meVsYouContract.addUser(questionId, user);
}

// 3. USERS ACCEPT INVITATIONS
// Each user calls:
await meVsYouContract.acceptInvitation(questionId);

// 4. USERS STAKE
// User 1 stakes on option 0
await tokenContract.approve(vaultAddress, amount1);
await meVsYouContract.stake(questionId, 0, tokenAddress, amount1);

// User 2 stakes on option 1
await tokenContract.approve(vaultAddress, amount2);
await meVsYouContract.stake(questionId, 1, tokenAddress, amount2);

// 5. ORACLE RESOLVES (after event occurs)
const payouts = [10000, 0]; // Option 0 wins
await meVsYouContract.resolve(questionId, payouts);

// 6. WINNERS REDEEM
// User 1 (winner) redeems
await conditionalTokens.setApprovalForAll(vaultAddress, true);
await meVsYouContract.redeem(questionId, 0);
```

---

## Events

### BetCreated

Emitted when a bet is created.

```typescript
event BetCreated(
  bytes32 indexed questionId,
  string question,
  OracleType oracleType,
  InvitationType betType,
  address owner
);
```

**Listen:**
```typescript
meVsYouContract.on("BetCreated", (questionId, question, oracleType, betType, owner) => {
  console.log("New bet created:", question);
});
```

---

### BetResolved

Emitted when a bet is resolved.

```typescript
event BetResolved(bytes32 indexed questionId, uint256[] payouts);
```

**Listen:**
```typescript
meVsYouContract.on("BetResolved", (questionId, payouts) => {
  console.log("Bet resolved:", questionId);
  // Find winning option (payout > 0)
  const winningOption = payouts.findIndex(p => p > 0);
});
```

---

### Staked

Emitted when a user stakes.

```typescript
event Staked(
  bytes32 indexed questionId,
  uint256 optionIndex,
  address token,
  uint256 amount
);
```

**Listen:**
```typescript
meVsYouContract.on("Staked", (questionId, optionIndex, token, amount) => {
  console.log("User staked:", amount, "on option", optionIndex);
});
```

---

### Redeemed

Emitted when a user redeems.

```typescript
event Redeemed(bytes32 indexed questionId, address token, uint256 amount);
```

---

## Error Handling

### Common Errors

```typescript
// Error: InvalidBetDuration
// Cause: duration <= 0
// Fix: Ensure duration > 0

// Error: InvalidOutcomeSlotCount
// Cause: outcomeSlotCount < 2 or > 255
// Fix: Use 2-255 outcomes

// Error: OracleNotAllowed
// Cause: Oracle not allowed in Hub (for PLATFORM/CUSTOM types)
// Fix: Ensure oracle is allowlisted in Hub

// Error: PublicBetNotAllowed
// Cause: User without GAME_CREATOR_ROLE trying to create Public bet
// Fix: Use Single or Group bet type, or get GAME_CREATOR_ROLE

// Error: QuestionAlreadyExists
// Cause: Bet with same questionId already exists
// Fix: Use unique question or different oracle

// Error: UserNotInvited
// Cause: User trying to stake on Single/Group bet without accepted invitation
// Fix: Owner must addUser() and user must acceptInvitation()

// Error: TokenNotAllowedListed
// Cause: Token not allowed in TokensManager
// Fix: Use an allowed token

// Error: NotAuthorized
// Cause: Wrong address trying to resolve bet
// Fix: Only the bet's oracle can resolve
```

### Error Handling Example

```typescript
try {
  const tx = await meVsYouContract.stake(questionId, optionIndex, token, amount);
  await tx.wait();
} catch (error) {
  if (error.message.includes("UserNotInvited")) {
    // Handle invitation required
    await handleInvitationFlow(questionId);
  } else if (error.message.includes("TokenNotAllowedListed")) {
    // Handle token not allowed
    alert("Token not supported");
  } else {
    // Handle other errors
    console.error("Stake failed:", error);
  }
}
```

---

## Token Approvals

### Required Approvals

1. **ERC20 Token Approval (for staking)**
   - Approve: `Vault` contract address
   - Amount: At least the stake amount (or `max` for convenience)

```typescript
const vaultAddress = await meVsYouContract.vault();
const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);

// Check current allowance
const currentAllowance = await tokenContract.allowance(userAddress, vaultAddress);
if (currentAllowance < amount) {
  const approveTx = await tokenContract.approve(vaultAddress, ethers.constants.MaxUint256);
  await approveTx.wait();
}
```

2. **ERC1155 Conditional Tokens Approval (for redeeming)**
   - Approve: `Vault` contract address
   - Use: `setApprovalForAll(vaultAddress, true)`

```typescript
const vaultAddress = await meVsYouContract.vault();
const conditionalTokensAddress = await vaultContract.conditionalTokens();
const conditionalTokens = new ethers.Contract(conditionalTokensAddress, ERC1155_ABI, signer);

const isApproved = await conditionalTokens.isApprovedForAll(userAddress, vaultAddress);
if (!isApproved) {
  const approveTx = await conditionalTokens.setApprovalForAll(vaultAddress, true);
  await approveTx.wait();
}
```

---

## Permission Requirements

### Roles

```typescript
// Constants (use these for permission checks)
const GAME_CREATOR_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GAME_CREATOR_ROLE"));
const ORACLE_MANAGER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ORACLE_MANAGER_ROLE"));
```

### Permission Checks

```typescript
// Check if user can create Public bets
const hasGameCreatorRole = await permissionManager.hasRole(
  GAME_CREATOR_ROLE,
  userAddress
);

// Check if oracle is allowed (for PLATFORM/CUSTOM types)
const isOracleAllowed = await hub.isAllowed(oracleAddress, ORACLE);
```

---

## Helper Functions

### Calculate questionId

```typescript
function calculateQuestionId(question: string, owner: string, oracle: string): string {
  const encoded = ethers.utils.solidityKeccak256(
    ["string", "address", "address"],
    [question, owner, oracle]
  );
  return encoded;
}
```

### Get Allowed Tokens

```typescript
// You'll need to query TokensManager or maintain a list
const isTokenAllowed = await tokenManager.allowedTokens(tokenAddress);
```

### Get Bet Status

```typescript
async function getBetStatus(questionId: string) {
  const bet = await meVsYouContract.getBet(questionId);
  const now = Math.floor(Date.now() / 1000);
  const isExpired = now > Number(bet.createdAt) + Number(bet.duration);
  
  // Check if resolved (you'd need to track BetResolved events)
  // or check Vault for condition resolution
  
  return {
    active: !isExpired,
    expired: isExpired,
    resolved: false, // Track via events
  };
}
```

---

## Example Code

### Complete React Hook Example

```typescript
import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import MeVsYouABI from './abis/MeVsYou.json';
import ERC20ABI from './abis/ERC20.json';

export function useMeVsYou(contractAddress: string, signer: ethers.Signer) {
  const [contract, setContract] = useState<ethers.Contract | null>(null);
  const [vaultAddress, setVaultAddress] = useState<string | null>(null);

  useEffect(() => {
    if (signer && contractAddress) {
      const meVsYou = new ethers.Contract(contractAddress, MeVsYouABI, signer);
      setContract(meVsYou);
      
      // Get vault address
      meVsYou.vault().then(setVaultAddress);
    }
  }, [signer, contractAddress]);

  const createBet = async (params: CreateBetParams) => {
    if (!contract) throw new Error("Contract not initialized");
    
    const tx = await contract.createBet(params);
    const receipt = await tx.wait();
    const event = receipt.events.find((e: any) => e.event === "BetCreated");
    return event.args.questionId;
  };

  const stake = async (
    questionId: string,
    optionIndex: number,
    tokenAddress: string,
    amount: bigint
  ) => {
    if (!contract || !vaultAddress) throw new Error("Contract not initialized");
    
    // Approve token
    const token = new ethers.Contract(tokenAddress, ERC20ABI, signer);
    const allowance = await token.allowance(await signer.getAddress(), vaultAddress);
    if (allowance < amount) {
      const approveTx = await token.approve(vaultAddress, ethers.constants.MaxUint256);
      await approveTx.wait();
    }
    
    // Stake
    const tx = await contract.stake(questionId, optionIndex, tokenAddress, amount);
    return await tx.wait();
  };

  const getBet = async (questionId: string) => {
    if (!contract) throw new Error("Contract not initialized");
    return await contract.getBet(questionId);
  };

  return {
    contract,
    vaultAddress,
    createBet,
    stake,
    getBet,
  };
}
```

---

## Summary Checklist

### Before Creating a Bet:
- [ ] Determine bet type (Single/Group/Public)
- [ ] Choose oracle address and type
- [ ] Ensure oracle is allowed (for PLATFORM/CUSTOM types)
- [ ] Have GAME_CREATOR_ROLE for Public bets (if needed)

### Before Staking:
- [ ] Check invitation status (for Single/Group bets)
- [ ] Accept invitation if needed
- [ ] Approve ERC20 token for Vault
- [ ] Verify token is allowed in TokensManager
- [ ] Ensure bet is not expired

### Before Resolving:
- [ ] Verify you are the bet's oracle address
- [ ] Prepare payout array (length = outcomeSlotCount)
- [ ] Ensure bet duration has passed (if applicable)

### Before Redeeming:
- [ ] Verify bet is resolved
- [ ] Check you staked on winning outcome
- [ ] Approve ConditionalTokensV2 for Vault
- [ ] Call redeem with correct optionIndex

---

## Additional Resources

- Contract Addresses: Check deployment scripts
- ABIs: Generated in `out/` directory after compilation
- Test Files: See `test/` directory for integration examples
- Vault Integration: See `IVault.sol` for vault-specific functions
- Hub Integration: See `IHub.sol` for game lifecycle management

---

**Last Updated:** Based on MeVsYou.sol v0.8.24

