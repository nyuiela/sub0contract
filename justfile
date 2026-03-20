set dotenv-load

# Sub0 prediction market – Just recipes
# Lib deps: use submodules only. After clone run: git submodule update --init --recursive
# All forge scripts read PRIVATE_KEY directly from .env (set dotenv-load handles this).

rpc_sepolia        := "https://virtual.rpc.tenderly.co/kaleel/project/public/sub0"
rpc_celo_sepolia   := "https://forno.celo-sepolia.celo-testnet.org"
etherscan_api_key  := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
celoscan_api_key   := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
etherscan_url      := "https://api.etherscan.io/v2/api?chainid=11155111"
celoscan_url       := "https://sepolia.celoscan.io"
etherscan_sepolia_url := "https://api.etherscan.io/v2/api?chainid=11155111"
etherscan_mainnet_url := "https://api.etherscan.io/v2/api?chainid=1"

# Deploy contracts (broadcast only — verify separately).
deploy network="sepolia":
  @echo "Deploying Sub0 stack to {{network}}..."
  forge script script/deploySub0.s.sol:DeploySub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast \
    --via-ir --optimizer-runs 200

deploy-celo:
  just deploy celo-sepolia

# ── Celo Sepolia shorthands ────────────────────────────────────────────────
create-market-celo:
  just create-market celo-sepolia

seed-market-celo:
  just seed-market celo-sepolia

setup-permissions-celo:
  just setup-permissions celo-sepolia

allowlist-token-celo:
  just allowlist-token celo-sepolia

create-bet-celo:
  just create-bet celo-sepolia

stake-celo:
  just stake celo-sepolia

settle-market-celo:
  just settle-market celo-sepolia

deps:
  git submodule update --init --recursive

test:
  @echo "Running tests..."
  forge test -vvvv

generate-question-id:
  @echo "Generating questionId..."
  forge script script/generateQuestionId.s.sol:GenerateQuestionId -vvvv

get-market network="sepolia":
  @echo "Fetching market on {{network}}..."
  forge script script/getMarket.s.sol:GetMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }}

create-market network="sepolia":
  @echo "Creating market on {{network}}..."
  forge script script/createMarket.s.sol:CreateMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

seed-market network="sepolia":
  @echo "Seeding market liquidity on PredictionVault ({{network}})..."
  forge script script/seedMarket.s.sol:SeedMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

create-bet network="sepolia":
  @echo "Creating bet on {{network}}..."
  forge script script/createBet.s.sol:CreateBet -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }}

stake network="sepolia":
  @echo "Staking on {{network}}..."
  forge script script/stake.s.sol:Stake -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

redeem network="sepolia":
  @echo "Redeeming on {{network}}..."
  forge script script/redeem.s.sol:Redeem -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

execute-trade network="sepolia":
  @echo "Executing trade on {{network}}..."
  forge script script/executeTrade.s.sol:ExecuteTrade -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

settle-market network="sepolia":
  @echo "Settling market on {{network}}..."
  forge script script/settleMarket.s.sol:SettleMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

approve-vault network="sepolia":
  @echo "Approving vault on {{network}}..."
  forge script script/approveVault.s.sol:ApproveVault -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-token network="sepolia":
  @echo "Allowlisting token on {{network}}..."
  forge script script/allowListToken.s.sol:AllowListToken -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

setup-permissions network="sepolia":
  @echo "Setting up permissions on {{network}}..."
  forge script script/setupPermissions.s.sol:SetupPermissions -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-token-uri network="sepolia":
  @echo "Setting token URI on {{network}}..."
  forge script script/setTokenURI.s.sol:SetTokenURI -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-reporter network="sepolia":
  @echo "Allowlisting oracle reporter on {{network}}..."
  forge script script/allowListReporter.s.sol:AllowListReporter -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

upgrade-sub0 network="sepolia":
  @echo "Upgrading Sub0 on {{network}}..."
  forge script script/upgradeSub0.s.sol:UpgradeSub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-cre-forwarder-config network="sepolia":
  @echo "Setting CRE forwarder config on {{network}}..."
  forge script script/setCreForwarderConfig.s.sol:SetCreForwarderConfig -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else if network == "celo-sepolia" { rpc_celo_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

# ── Verification (run after deploy, separately) ────────────────────────────
# Sub0 is a proxy — pass the IMPLEMENTATION address, not the proxy.
# Get it with: cast implementation <PROXY> --rpc-url <RPC>

verify-sepolia impl_address:
  @echo "Verifying on Sepolia..."
  forge verify-contract {{impl_address}} src/gamehub/Sub0.sol:Sub0 \
    --chain-id 11155111 \
    --verifier etherscan \
    --verifier-url {{etherscan_sepolia_url}} \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url {{rpc_sepolia}} \
    --via-ir --num-of-optimizations 200 \
    --watch

verify-mainnet impl_address:
  @echo "Verifying on mainnet..."
  forge verify-contract {{impl_address}} src/gamehub/Sub0.sol:Sub0 \
    --chain-id 1 \
    --verifier etherscan \
    --verifier-url {{etherscan_mainnet_url}} \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url https://eth.llamarpc.com \
    --via-ir --num-of-optimizations 200 \
    --watch

# Requires CELOSCAN_API_KEY in .env
verify-celo impl_address contract_path="src/gamehub/Sub0.sol:Sub0":
  @echo "Verifying on Celo Sepolia..."
  forge verify-contract {{impl_address}} {{contract_path}} \
    --chain-id 11142220 \
    --verifier etherscan \
    --verifier-url {{celoscan_url}} \
    --etherscan-api-key $CELOSCAN_API_KEY \
    --rpc-url {{rpc_celo_sepolia}} \
    --via-ir --num-of-optimizations 200 \
    --watch
