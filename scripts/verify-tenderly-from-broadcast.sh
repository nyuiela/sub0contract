#!/usr/bin/env bash
# Verify Sub0 contracts from the latest Tenderly deploy (broadcast/deploySub0.s.sol/9998453/run-latest.json).
# Run after a successful deploy-tenderly. Requires jq and TENDERLY_VERIFIER_URL.

set -e
RUN_FILE="broadcast/deploySub0.s.sol/9998453/run-latest.json"
CHAIN_ID="9998453"

if [ ! -f "$RUN_FILE" ]; then
  echo "Error: $RUN_FILE not found. Run just deploy-tenderly first."
  exit 1
fi
if [ -z "$TENDERLY_VERIFIER_URL" ]; then
  echo "Error: TENDERLY_VERIFIER_URL not set."
  exit 1
fi

case "$(jq -r '.transactions[0].contractName // empty' "$RUN_FILE" 2>/dev/null)" in
  "") echo "Error: no transactions in broadcast or jq failed."; exit 1 ;;
esac

# Map contractName -> path:contract for forge verify-contract
verify_one() {
  local addr="$1"
  local name="$2"
  case "$name" in
    PermissionManager)   path="src/manager/PermissionManager.sol:PermissionManager" ;;
    ConditionalTokensV2) path="src/conditional/ConditionalTokensV2.sol:ConditionalTokensV2" ;;
    TokensManager)       path="src/manager/TokenManager.sol:TokensManager" ;;
    Oracle)              path="src/oracle/oracle.sol:Oracle" ;;
    Hub)                 path="src/gamehub/Hub.sol:Hub" ;;
    Vault)               path="src/manager/VaultV2.sol:Vault" ;;
    PredictionVault)    path="src/gamehub/PredictionVault.sol:PredictionVault" ;;
    Sub0)                path="src/gamehub/Sub0.sol:Sub0" ;;
    ERC1967Proxy)        return 0 ;;
    *)                   return 0 ;;
  esac
  echo "Verifying $name at $addr"
  forge verify-contract "$addr" "$path" \
    --chain-id "$CHAIN_ID" \
    --verifier-url "$TENDERLY_VERIFIER_URL" \
    --verifier custom \
    --optimizer-runs 1 || echo "  (skip or already verified)"
}

# Unique by address (first occurrence wins)
declare -A done_addr
while IFS= read -r line; do
  addr=$(echo "$line" | cut -d' ' -f1)
  name=$(echo "$line" | cut -d' ' -f2-)
  addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
  [ -n "${done_addr[$addr_lower]}" ] && continue
  done_addr[$addr_lower]=1
  verify_one "$addr" "$name"
done < <(jq -r '.transactions[] | select(.contractAddress != null and .contractAddress != "") | "\(.contractAddress) \(.contractName)"' "$RUN_FILE" 2>/dev/null)

echo "Verify from broadcast done."
