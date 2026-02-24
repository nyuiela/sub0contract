/**
 * Chainlink CRE workflow: LMSR pricing with on-chain state.
 * Fetches outstanding shares (q) from the PredictionVault/CTF, computes cost via
 * Cost = b * ln(sum(exp(q_i / b))), signs DONQuote EIP-712, returns quote + signature.
 *
 * Expects CRE Secrets: DON_PRIVATE_KEY (hex, no 0x prefix ok).
 * Config: PREDICTION_VAULT_ADDRESS, CTF_ADDRESS, USDC_ADDRESS, CHAIN_ID.
 */

import Decimal from "decimal.js";
import { hashTypedData, type Hex } from "viem";

const USDC_DECIMALS = 6;
const OUTCOME_DECIMALS = 18;

export type TradeRequest = {
  marketId: Hex;
  outcomeIndex: number;
  quantity: string; // wei (18 decimals) as string
  bParameter: string; // LMSR b as string
  buy: boolean;
  user: Hex; // for DON quote binding
};

export type QuoteResult = {
  tradeCostUsdc: string; // 6 decimals (raw, e.g. "1000000" = 1 USDC)
  donSignature: Hex;
  deadline: number;
  nonce: number;
};

/**
 * LMSR cost function: C(q) = b * ln(sum_i exp(q_i / b)).
 * Cost to buy Q of outcome k = C(q') - C(q) where q'_k = q_k + Q, q'_i = q_i for i != k.
 */
function lmsrCost(
  q: Decimal[],
  b: Decimal,
  outcomeIndex: number,
  quantity: Decimal,
  buy: boolean
): Decimal {
  const n = q.length;
  const qPrime = q.map((qi, i) =>
    i === outcomeIndex ? (buy ? qi.plus(quantity) : qi.minus(quantity)) : qi
  );
  const sumExpQ = (qs: Decimal[]) =>
    qs.reduce((acc, qi) => acc.plus(Decimal.exp(qi.div(b))), new Decimal(0));
  const C = (qs: Decimal[]) => b.times(Decimal.ln(sumExpQ(qs)));
  const cost = C(qPrime).minus(C(q));
  return buy ? cost : cost.neg();
}

/**
 * Fetch outstanding shares (vault balances) for each outcome of the market from chain.
 * Returns array of balances in 18-decimal (wei) string form.
 */
export async function fetchOutstandingShares(
  evmClient: {
    readContract: (args: {
      address: Hex;
      abi: unknown[];
      functionName: string;
      args?: unknown[];
    }) => Promise<bigint | Hex>;
  },
  ctfAddress: Hex,
  usdcAddress: Hex,
  vaultAddress: Hex,
  conditionId: Hex,
  outcomeSlotCount: number
): Promise<string[]> {
  const shares: string[] = [];
  for (let i = 0; i < outcomeSlotCount; i++) {
    const indexSet = 1 << i;
    const collectionId = await evmClient.readContract({
      address: ctfAddress,
      abi: [
        {
          type: "function",
          name: "getCollectionId",
          inputs: [
            { name: "parentCollectionId", type: "bytes32" },
            { name: "conditionId", type: "bytes32" },
            { name: "indexSet", type: "uint256" },
          ],
          outputs: [{ type: "bytes32" }],
        },
      ],
      functionName: "getCollectionId",
      args: ["0x0000000000000000000000000000000000000000000000000000000000000000", conditionId, BigInt(indexSet)],
    });
    const positionId = await evmClient.readContract({
      address: ctfAddress,
      abi: [
        {
          type: "function",
          name: "getPositionId",
          inputs: [
            { name: "collateralToken", type: "address" },
            { name: "collectionId", type: "bytes32" },
          ],
          outputs: [{ type: "uint256" }],
        },
      ],
      functionName: "getPositionId",
      args: [usdcAddress, collectionId],
    });
    const balance = await evmClient.readContract({
      address: ctfAddress,
      abi: [
        {
          type: "function",
          name: "balanceOf",
          inputs: [
            { name: "account", type: "address" },
            { name: "id", type: "uint256" },
          ],
          outputs: [{ type: "uint256" }],
        },
      ],
      functionName: "balanceOf",
    args: [vaultAddress, positionId],
  });
  shares.push(balance.toString());
}
  return shares;
}

/**
 * Build EIP-712 digest for DONQuote (Sub0PredictionVault domain).
 * Matches Solidity PredictionVault._hashTypedDataV4(keccak256(abi.encode(DON_QUOTE_TYPEHASH, ...))).
 */
function buildDonQuoteDigest(
  domain: { name: string; version: string; chainId: number; verifyingContract: Hex },
  marketId: Hex,
  outcomeIndex: number,
  buy: boolean,
  quantity: bigint,
  tradeCostUsdc: bigint,
  user: Hex,
  nonce: number,
  deadline: number
): Hex {
  return hashTypedData({
    domain: {
      name: domain.name,
      version: domain.version,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract,
    },
    types: {
      DONQuote: [
        { name: "marketId", type: "bytes32" },
        { name: "outcomeIndex", type: "uint256" },
        { name: "buy", type: "bool" },
        { name: "quantity", type: "uint256" },
        { name: "tradeCostUsdc", type: "uint256" },
        { name: "user", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    },
    primaryType: "DONQuote",
    message: {
      marketId,
      outcomeIndex: BigInt(outcomeIndex),
      buy,
      quantity,
      tradeCostUsdc,
      user,
      nonce: BigInt(nonce),
      deadline: BigInt(deadline),
    },
  });
}

export type DonQuoteTypedData = {
  domain: { name: string; version: string; chainId: number; verifyingContract: Hex };
  types: { DONQuote: Array<{ name: string; type: string }> };
  primaryType: "DONQuote";
  message: {
    marketId: Hex;
    outcomeIndex: bigint;
    buy: boolean;
    quantity: bigint;
    tradeCostUsdc: bigint;
    user: Hex;
    nonce: bigint;
    deadline: bigint;
  };
};

/**
 * Sign DON quote: call signTypedData (e.g. viem's account.signTypedData) with the given typed data.
 * CRE injects a signer that uses the DON private key from CRE Secrets.
 */
async function signDonQuote(typedData: DonQuoteTypedData, signTypedData: (args: DonQuoteTypedData) => Promise<Hex>): Promise<Hex> {
  return signTypedData(typedData);
}

/**
 * Main workflow entry: compute LMSR cost from on-chain q, build DON quote, sign, return.
 */
export async function runLmsrPricing(
  request: TradeRequest,
  config: {
    predictionVaultAddress: Hex;
    ctfAddress: Hex;
    usdcAddress: Hex;
    chainId: number;
    donPrivateKey?: string; // from CRE Secrets (optional if signTypedData provided)
    signTypedData?: (args: DonQuoteTypedData) => Promise<Hex>; // e.g. viem account.signTypedData
  },
  evmClient: {
    readContract: (args: {
      address: Hex;
      abi: unknown[];
      functionName: string;
      args?: unknown[];
    }) => Promise<bigint | Hex>;
  }
): Promise<QuoteResult> {
  const { marketId, outcomeIndex, quantity, bParameter, buy, user } = request;
  const b = new Decimal(bParameter);
  const Q = new Decimal(quantity);

  const conditionId = (await evmClient.readContract({
    address: config.predictionVaultAddress,
    abi: [
      { type: "function", name: "getConditionId", inputs: [{ name: "questionId", type: "bytes32" }], outputs: [{ type: "bytes32" }] },
    ],
    functionName: "getConditionId",
    args: [marketId],
  })) as Hex;
  const outcomeSlotCount = Number(
    await evmClient.readContract({
      address: config.ctfAddress,
      abi: [
        { type: "function", name: "getOutcomeSlotCount", inputs: [{ name: "conditionId", type: "bytes32" }], outputs: [{ type: "uint256" }] },
      ],
      functionName: "getOutcomeSlotCount",
      args: [conditionId],
    })
  );

  const sharesWei = await fetchOutstandingShares(
    evmClient,
    config.ctfAddress,
    config.usdcAddress,
    config.predictionVaultAddress,
    conditionId,
    outcomeSlotCount
  );
  const q = sharesWei.map((s) => new Decimal(s));

  const costWei = lmsrCost(q, b, outcomeIndex, Q, buy);
  const tradeCostUsdcRaw = costWei
    .times(10 ** USDC_DECIMALS)
    .div(10 ** OUTCOME_DECIMALS)
    .floor()
    .abs()
    .toFixed(0);
  const tradeCostUsdc = BigInt(tradeCostUsdcRaw);

  const deadline = Math.floor(Date.now() / 1000) + 300; // 5 min
  const nonce = Math.floor(Math.random() * 2 ** 48);

  const domain = {
    name: "Sub0PredictionVault",
    version: "1",
    chainId: config.chainId,
    verifyingContract: config.predictionVaultAddress,
  };
  const quantityBigInt = BigInt(quantity);
  const typedData: DonQuoteTypedData = {
    domain: {
      name: domain.name,
      version: domain.version,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract,
    },
    types: {
      DONQuote: [
        { name: "marketId", type: "bytes32" },
        { name: "outcomeIndex", type: "uint256" },
        { name: "buy", type: "bool" },
        { name: "quantity", type: "uint256" },
        { name: "tradeCostUsdc", type: "uint256" },
        { name: "user", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    },
    primaryType: "DONQuote",
    message: {
      marketId,
      outcomeIndex: BigInt(outcomeIndex),
      buy,
      quantity: quantityBigInt,
      tradeCostUsdc,
      user,
      nonce: BigInt(nonce),
      deadline: BigInt(deadline),
    },
  };

  let donSignature: Hex;
  if (config.signTypedData) {
    donSignature = await signDonQuote(typedData, config.signTypedData);
  } else if (config.donPrivateKey) {
    const digest = buildDonQuoteDigest(
      domain,
      marketId,
      outcomeIndex,
      buy,
      quantityBigInt,
      tradeCostUsdc,
      user,
      nonce,
      deadline
    );
    const sign = (globalThis as unknown as { __creSign?: (d: Hex, pk: string) => Hex }).__creSign;
    if (!sign) throw new Error("Inject __creSign(digest, donPrivateKey) or pass config.signTypedData");
    donSignature = sign(digest, config.donPrivateKey);
  } else {
    throw new Error("Provide config.signTypedData or config.donPrivateKey and __creSign");
  }

  return {
    tradeCostUsdc: tradeCostUsdc.toString(),
    donSignature,
    deadline,
    nonce,
  };
}
