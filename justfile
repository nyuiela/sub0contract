set dotenv-load

# Sub0 prediction market – Just recipes
# Lib deps: use submodules only. After clone run: git submodule update --init --recursive
# Requires .env in sub0contract/ with PRIVATE_KEY=0x... (deployer key for --broadcast).
# Base Sepolia chain id 84532; RPC https://sepolia.base.org

rpc_sepolia := "https://ethereum-sepolia-public.nodies.app"
etherscan_api_key := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
etherscan_url := "https://api-sepolia.basescan.org/api?chainid=84532"

deploy network="base-sepolia":
  # Load PRIVATE_KEY from .env (or export PRIVATE_KEY=0x... before running)
  @echo "Deploying Sub0 stack to {{network}}..."
<<<<<<< HEAD
  infisical run --path="/sub0contract" -- forge script script/deploySub0.s.sol:DeploySub0 -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \ 
    --broadcast \
    --chain-id {{if network == "base-sepolia" { base_sepolia_chain_id } else { "31337" } }}
deps:
  git submodule update --init --recursive
test:
  @echo "Running tests..."
  forge test -vvvv

generate-question-id:
  @echo "Generating questionId = keccak256(question, creator, oracle)..."
  infisical run --path="/sub0contract" -- forge script script/generateQuestionId.s.sol:GenerateQuestionId -vvvv

get-market network="base-sepolia":
  @echo "Fetching market by questionId on {{network}}..."
  forge script script/getMarket.s.sol:GetMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }}

create-market network="base-sepolia":
  @echo "Creating market on {{network}}..."
  forge script script/createMarket.s.sol:CreateMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

create-bet network="base-sepolia":
  @echo "Creating bet on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/createBet.s.sol:CreateBet -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    # --broadcast

stake network="base-sepolia":
  @echo "Staking on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/stake.s.sol:Stake -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

redeem network="base-sepolia":
  @echo "Redeeming on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/redeem.s.sol:Redeem -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

execute-trade network="base-sepolia":
  @echo "Executing trade (relayer) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/executeTrade.s.sol:ExecuteTrade -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

settle-market network="base-sepolia":
  @echo "Settling market (oracle resolve) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/settleMarket.s.sol:SettleMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

approve-vault network="base-sepolia":
  @echo "Approving vault (CTF) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/approveVault.s.sol:ApproveVault -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-token network="base-sepolia":
  @echo "Allowlisting token on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/allowListToken.s.sol:AllowListToken -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

setup-permissions network="base-sepolia":
  @echo "Setting up permissions on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/setupPermissions.s.sol:SetupPermissions -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-token-uri network="base-sepolia":
  @echo "Setting token URI (ConditionalTokensV2) on {{network}}..."
  infisical run --path="/sub0contract" -- forge script script/setTokenURI.s.sol:SetTokenURI -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-reporter network="base-sepolia":
  @echo "Allowlisting oracle reporter on {{network}}..."
  forge script script/allowListReporter.s.sol:AllowListReporter -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

upgrade-sub0 network="base-sepolia":
  @echo "Upgrading Sub0 on {{network}}..."
  forge script script/upgradeSub0.s.sol:UpgradeSub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-cre-forwarder-config network="sepolia":
  @echo "Setting CRE forwarder config on Sub0 (forwarder, author, workflow name, workflow ID)..."
  forge script script/setCreForwarderConfig.s.sol:SetCreForwarderConfig -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

# Verify on Etherscan (Sepolia). Sub0 is a proxy: verify IMPLEMENTATION address.
# Get implementation: cast implementation <PROXY_ADDRESS> --rpc-url <RPC>
# Then: just verify-sepolia <IMPLEMENTATION_ADDRESS>
verify-sepolia impl_address:
  @echo "Verifying Sub0 implementation on Sepolia..."
  forge verify-contract {{impl_address}} src/gamehub/Sub0.sol:Sub0 \
    --chain-id 11155111 \
    --verifier etherscan \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url {{rpc_sepolia}} \
    --watch
