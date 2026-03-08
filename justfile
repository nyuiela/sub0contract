set dotenv-load

# Sub0 prediction market – Just recipes
# Lib deps: use submodules only. After clone run: git submodule update --init --recursive

# rpc_sepolia := "https://ethereum-sepolia-public.nodies.app"
rpc_sepolia := "https://virtual.rpc.tenderly.co/kaleel/project/public/sub0"
etherscan_api_key := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
etherscan_url := "https://api.etherscan.io/v2/api?chainid=11155111"

deploy network="sepolia":
  @echo "Deploying Sub0 stack to {{network}}..."
  forge script script/deploySub0.s.sol:DeploySub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} --broadcast --verify --etherscan-api-key {{etherscan_api_key}} --chain {{network}} \
    --via-ir --optimizer-runs 200

# Install lib dependencies (submodules). Run after clone.
deps:
  git submodule update --init --recursive

test:
  @echo "Running tests..."
  forge test -vvvv

generate-question-id:
  @echo "Generating questionId = keccak256(question, creator, oracle)..."
  infisical run --path="/sub0contract" -- forge script script/generateQuestionId.s.sol:GenerateQuestionId -vvvv

get-market network="sepolia":
  @echo "Fetching market by questionId on {{network}}..."
  forge script script/getMarket.s.sol:GetMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }}

create-market network="sepolia":
  @echo "Creating market on {{network}}..."
  forge script script/createMarket.s.sol:CreateMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

seed-market network="sepolia":
  @echo "Seeding market liquidity on PredictionVault ({{network}})..."
  forge script script/seedMarket.s.sol:SeedMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

create-bet network="sepolia":
  @echo "Creating bet on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/createBet.s.sol:CreateBet -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    # --broadcast

stake network="sepolia":
  @echo "Staking on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/stake.s.sol:Stake -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

redeem network="sepolia":
  @echo "Redeeming on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/redeem.s.sol:Redeem -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

execute-trade network="sepolia":
  @echo "Executing trade (relayer) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/executeTrade.s.sol:ExecuteTrade -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

settle-market network="sepolia":
  @echo "Settling market (oracle resolve) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/settleMarket.s.sol:SettleMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

approve-vault network="sepolia":
  @echo "Approving vault (CTF) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/approveVault.s.sol:ApproveVault -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-token network="sepolia":
  @echo "Allowlisting token on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/allowListToken.s.sol:AllowListToken -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

setup-permissions network="sepolia":
  @echo "Setting up permissions on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/setupPermissions.s.sol:SetupPermissions -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-token-uri network="sepolia":
  @echo "Setting token URI (ConditionalTokensV2) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/setTokenURI.s.sol:SetTokenURI -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-reporter network="sepolia":
  @echo "Allowlisting oracle reporter on {{network}}..."
  forge script script/allowListReporter.s.sol:AllowListReporter -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

upgrade-sub0 network="sepolia":
  @echo "Upgrading Sub0 on {{network}}..."
  forge script script/upgradeSub0.s.sol:UpgradeSub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-cre-forwarder-config network="sepolia":
  @echo "Setting CRE forwarder config on Sub0 (forwarder, author, workflow name, workflow ID)..."
  forge script script/setCreForwarderConfig.s.sol:SetCreForwarderConfig -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

# Verify on Etherscan (Etherscan API V2 required; V1 is deprecated).
# Sub0 is a proxy: verify the IMPLEMENTATION address, not the proxy.
# Get implementation: cast implementation <PROXY_ADDRESS> --rpc-url <RPC>
# Requires ETHERSCAN_API_KEY in .env (or export before running).
#
# Sepolia: just verify-sepolia <IMPLEMENTATION_ADDRESS>
# Mainnet: just verify-mainnet <IMPLEMENTATION_ADDRESS>
etherscan_sepolia_url := "https://api.etherscan.io/v2/api?chainid=11155111"
etherscan_mainnet_url := "https://api.etherscan.io/v2/api?chainid=1"

verify-sepolia impl_address:
  @echo "Verifying Sub0 implementation on Sepolia (Etherscan V2)..."
  forge verify-contract {{impl_address}} src/gamehub/Sub0.sol:Sub0 \
    --chain-id 11155111 \
    --verifier etherscan \
    --verifier-url {{etherscan_sepolia_url}} \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url {{rpc_sepolia}} \
    --via-ir --num-of-optimizations 200 \
    --watch

verify-mainnet impl_address:
  @echo "Verifying Sub0 implementation on mainnet (Etherscan V2)..."
  forge verify-contract {{impl_address}} src/gamehub/Sub0.sol:Sub0 \
    --chain-id 1 \
    --verifier etherscan \
    --verifier-url {{etherscan_mainnet_url}} \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url https://eth.llamarpc.com \
    --via-ir --num-of-optimizations 200 \
    --watch
