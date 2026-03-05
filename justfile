# Sub0 prediction market – one justfile for Sepolia and Tenderly
# Load .env (PRIVATE_KEY, USDC_ADDRESS, CRE forwarder, RPC URLs). See env-check.
set dotenv-load

# Chain IDs
SEPOLIA_CHAIN_ID := "11155111"
TENDERLY_CHAIN_ID := "9998453"

# Default: show available commands
default:
    @just --list

# ---- Build & test (from forwarder-contract) ----
build:
    forge build

test:
    forge test

clean:
    forge clean

deps:
    git submodule update --init --recursive

# ---- Sepolia deployment ----
# Requires in .env: PRIVATE_KEY, SEPOLIA_RPC_URL (e.g. https://rpc.sepolia.org or Alchemy/Infura), optional: USDC_ADDRESS, DON_SIGNER_ADDRESS, CRE_FORWARDER_ADDRESS
deploy-sepolia:
    @echo "Deploying Sub0 stack to Sepolia..."
    forge script script/deploySub0.s.sol:DeploySub0 \
        --rpc-url $SEPOLIA_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        --chain-id {{SEPOLIA_CHAIN_ID}} \
        --optimizer-runs 200

# ---- Tenderly deployment ----
# Set CHAIN_ID=9998453 so the script uses TENDERLY_CRE_FORWARDER_ADDRESS and TENDERLY_USDC_ADDRESS (not Sepolia addresses).
# Requires: PRIVATE_KEY, TENDERLY_SUB0_RPC_URL, TENDERLY_CRE_FORWARDER_ADDRESS. Optional: TENDERLY_USDC_ADDRESS (or run just deploy-mock-usdc-tenderly first and set it).
deploy-tenderly:
    @echo "Deploying Sub0 stack to Tenderly Sub0 chain..."
    CHAIN_ID=9998453 forge script script/deploySub0.s.sol:DeploySub0 \
        --rpc-url $TENDERLY_SUB0_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        --chain-id {{TENDERLY_CHAIN_ID}} \
        --optimizer-runs 1

deploy-tenderly-complete: deploy-tenderly
    @echo "Tenderly deployment complete."

# Deploy then verify all contracts from the broadcast file. Run after a successful deploy (or redeploy then verify in one go).
deploy-tenderly-verify: deploy-tenderly
    chmod +x scripts/verify-tenderly-from-broadcast.sh
    ./scripts/verify-tenderly-from-broadcast.sh

# Verify contracts from last broadcast only (no deploy). Use after deploy-tenderly if you skipped verify.
verify-tenderly-from-broadcast:
    chmod +x scripts/verify-tenderly-from-broadcast.sh
    ./scripts/verify-tenderly-from-broadcast.sh

# Verify mock USDC (TestERC20) on Tenderly. Example: just verify-usdc-tenderly 0x7FEC6e2A596b8227ABc04967B7D1F8D8EDD244f7
verify-usdc-tenderly address:
    forge verify-contract {{address}} src/mocks/TestERC20.sol:TestERC20 \
        --chain-id {{TENDERLY_CHAIN_ID}} \
        --verifier-url $TENDERLY_VERIFIER_URL \
        --verifier custom \
        --optimizer-runs 1

# Deploy mock USDC (TestERC20) on Tenderly only. Then set TENDERLY_USDC_ADDRESS in .env to the printed address and run just deploy-tenderly.
deploy-mock-usdc-tenderly:
    @echo "Deploying mock USDC (TestERC20) on Tenderly..."
    forge script script/deployMockUsdc.s.sol:DeployMockUsdc \
        --rpc-url $TENDERLY_SUB0_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        --chain-id {{TENDERLY_CHAIN_ID}} \
        --optimizer-runs 1

# Verify contract on Tenderly (run after deploy; not part of deploy).
# Example: just verify-tenderly 0xbbd7db97abb71Fb351b7c6Dbc04692F6d9aFfA96  (Sub0 impl)
# Or: just verify-tenderly <address> "src/gamehub/PredictionVault.sol:PredictionVault"
verify-tenderly address contract="src/gamehub/Sub0.sol:Sub0":
    forge verify-contract {{address}} {{contract}} \
        --chain-id {{TENDERLY_CHAIN_ID}} \
        --verifier-url $TENDERLY_VERIFIER_URL \
        --verifier custom

# Verify contract on Sepolia (Etherscan)
verify-sepolia address:
    forge verify-contract {{address}} \
        --chain-id {{SEPOLIA_CHAIN_ID}} \
        --verifier-url https://api-sepolia.etherscan.io/api \
        --verifier etherscan \
        --etherscan-api-key $ETHERSCAN_API_KEY

# ---- Environment checks ----
env-check:
    @echo "Sub0 contract – env (set in .env):"
    @echo "  Common: PRIVATE_KEY (required for deploy)"
    @echo "  Sepolia: SEPOLIA_RPC_URL, ETHERSCAN_API_KEY (for verify-sepolia), USDC_ADDRESS, CRE_FORWARDER_ADDRESS"
    @echo "  Tenderly: TENDERLY_SUB0_RPC_URL, TENDERLY_CRE_FORWARDER_ADDRESS, TENDERLY_USDC_ADDRESS (or run just deploy-mock-usdc-tenderly first)"
    @echo "  Tenderly verify: TENDERLY_VERIFIER_URL (for just verify-tenderly <address> after deploy)"
    @echo "  Optional: DON_SIGNER_ADDRESS, BACKEND_SIGNER_ADDRESS"
    @echo ""
    @echo "Current:"
    @[ -n "$$PRIVATE_KEY" ] && echo "  PRIVATE_KEY: set" || echo "  PRIVATE_KEY: not set"
    @[ -n "$$SEPOLIA_RPC_URL" ] && echo "  SEPOLIA_RPC_URL: set" || echo "  SEPOLIA_RPC_URL: not set"
    @[ -n "$$TENDERLY_SUB0_RPC_URL" ] && echo "  TENDERLY_SUB0_RPC_URL: set" || echo "  TENDERLY_SUB0_RPC_URL: not set"
    @[ -n "$$TENDERLY_VERIFIER_URL" ] && echo "  TENDERLY_VERIFIER_URL: set" || echo "  TENDERLY_VERIFIER_URL: not set"

env-check-tenderly:
    @echo "Tenderly Sub0 Environment:"
    @echo "RPC URL: $TENDERLY_SUB0_RPC_URL"
    @echo "Verifier URL: $TENDERLY_VERIFIER_URL"
    @echo "CRE Forwarder: $TENDERLY_CRE_FORWARDER_ADDRESS"
    @echo "USDC (Tenderly): $TENDERLY_USDC_ADDRESS"
    @echo "USDC (generic): $USDC_ADDRESS"

# ---- Deployment artifacts ----
save-deployment:
    ./save-deployment-info.sh

extract-abis:
    ./extract-abis.sh

update-contracts:
    ./update-contracts-json.sh
