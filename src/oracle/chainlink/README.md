# Chainlink Functions Integration

This directory contains the Chainlink Functions integration for fetching bet results from external APIs.

## Overview

The `ChainlinkResultOracle` contract integrates Chainlink Functions with the `ResultOracle` to automatically fetch and fulfill bet results from external APIs. When a bet result is requested, it makes a Chainlink Functions request to fetch the result from an API, then automatically fulfills the result in the `ResultOracle` contract.

## Files

- **ChainlinkResultOracle.sol**: The main Chainlink Functions consumer contract that handles requests and fulfillments.
- **GetResult.js**: The JavaScript source code that runs on Chainlink Functions nodes to fetch results from the API.

## Architecture

```
User/Contract
    ↓
ChainlinkResultOracle.requestResultWithChainlink()
    ↓
ResultOracle.requestResult() [creates internal request]
    ↓
Chainlink Functions [executes GetResult.js]
    ↓
ChainlinkResultOracle._fulfillRequest() [callback]
    ↓
ResultOracle.fulfillResult() [fulfills internal request]
```

## Setup

### 1. Deploy ChainlinkResultOracle

```solidity
ChainlinkResultOracle chainlinkOracle = new ChainlinkResultOracle(
    functionsRouter,      // Chainlink Functions Router address
    owner,                // Contract owner
    resultOracle,         // ResultOracle contract address
    subscriptionId,       // Chainlink Functions subscription ID
    donId,                // DON ID (bytes32)
    callbackGasLimit,     // Gas limit for fulfillment (e.g., 300000)
    sourceCode            // JavaScript source code (from GetResult.js)
);
```

### 2. Configure ResultOracle

The `ChainlinkResultOracle` contract needs to be added as an allowed reporter in the `ResultOracle`:

```solidity
resultOracle.allowListReporter(address(chainlinkOracle), true);
```

### 3. Fund Chainlink Functions Subscription

Ensure your Chainlink Functions subscription has sufficient LINK tokens to pay for requests.

### 4. Update Source Code (Optional)

You can update the JavaScript source code at any time:

```solidity
chainlinkOracle.updateSourceCode(newSourceCode);
```

## Usage

### Request a Result

```solidity
uint256 gameId = 1;
uint256 betId = 1;
bytes memory params = abi.encodePacked(gameId, betId);

bytes32 chainlinkRequestId = chainlinkOracle.requestResultWithChainlink(
    gameId,
    betId,
    params
);
```

### Check Request Status

```solidity
// Get the internal request ID
bytes32 internalRequestId = chainlinkOracle.getInternalRequestId(chainlinkRequestId);

// Get request info
GameBetInfo memory info = chainlinkOracle.getRequestInfo(chainlinkRequestId);

// Check result in ResultOracle
BetResult memory result = resultOracle.getBetResult(info.gameId, info.betId);
```

## JavaScript Source Code

The `GetResult.js` file contains the JavaScript code that runs on Chainlink Functions nodes. It:

1. Receives `gameId` and `betId` as arguments
2. Makes an HTTP request to the API endpoint
3. Parses the response to extract the result
4. Returns the result as an encoded string

### API Response Format

The JavaScript code expects the API to return a JSON response with one of these formats:

```json
{
  "result": "one"
}
```

or

```json
{
  "resultIndex": 1
}
```

or

```json
{
  "verdict": "one"
}
```

The result can be:
- A number string: "0", "1", "2", etc.
- A word string: "zero", "one", "two", "three", etc.

## Configuration

### Update Subscription ID

```solidity
chainlinkOracle.updateSubscriptionId(newSubscriptionId);
```

### Update DON ID

```solidity
chainlinkOracle.updateDonId(newDonId);
```

### Update Callback Gas Limit

```solidity
chainlinkOracle.updateCallbackGasLimit(newCallbackGasLimit);
```

### Update ResultOracle Address

```solidity
chainlinkOracle.updateResultOracle(newResultOracle);
```

## Events

- `ChainlinkRequestSent`: Emitted when a Chainlink Functions request is sent
- `ChainlinkRequestFulfilled`: Emitted when a request is successfully fulfilled
- `ChainlinkRequestFailed`: Emitted when a request fails
- `SourceCodeUpdated`: Emitted when the source code is updated
- `SubscriptionIdUpdated`: Emitted when the subscription ID is updated
- `DonIdUpdated`: Emitted when the DON ID is updated
- `CallbackGasLimitUpdated`: Emitted when the callback gas limit is updated

## Error Handling

The contract handles errors gracefully:

- If the Chainlink Functions request fails, it calls `resultOracle.failRequest()` with the error message
- If the response cannot be parsed, it reverts with `InvalidResultIndex`
- If a request is not found, it reverts with `RequestNotFound`

## Security Considerations

1. **Access Control**: Only the owner can update configuration parameters
2. **Reporter Authorization**: The `ChainlinkResultOracle` must be added as an allowed reporter in `ResultOracle`
3. **Input Validation**: All inputs are validated in the constructor and update functions
4. **Request Mapping**: Chainlink request IDs are mapped to internal request IDs to prevent replay attacks

## Testing

To test the integration:

1. Deploy `ResultOracle` and initialize it
2. Deploy `ChainlinkResultOracle` with proper configuration
3. Add `ChainlinkResultOracle` as an allowed reporter in `ResultOracle`
4. Fund the Chainlink Functions subscription
5. Call `requestResultWithChainlink()` with test parameters
6. Wait for Chainlink Functions to execute and fulfill the request
7. Check the result in `ResultOracle` using `getBetResult()`

## Network-Specific Configuration

Different networks have different Chainlink Functions Router addresses and DON IDs. Refer to the [Chainlink Functions documentation](https://docs.chain.link/chainlink-functions) for network-specific addresses.

### Example: Base Sepolia

- Functions Router: `0x9f82a0c70247f2f2b0b0b0b0b0b0b0b0b0b0b0b0`
- DON ID: `0x66756e2d626173652d7365706f6c69612d31000000000000000000000000000000`


