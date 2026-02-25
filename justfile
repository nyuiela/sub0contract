set dotenv-load

# Sub0 prediction market – Just recipes
# Requires .env in sub0contract/ with PRIVATE_KEY=0x... (deployer key for --broadcast).
# Base Sepolia chain id 84532; RPC https://sepolia.base.org

base_sepolia_rpc := "https://sepolia.base.org"
base_sepolia_chain_id := "84532"
etherscan_api_key := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
etherscan_url := "https://api-sepolia.basescan.org/api?chainid=84532"

deploy network="base-sepolia":
  # Load PRIVATE_KEY from .env (or export PRIVATE_KEY=0x... before running)
  @echo "Deploying Sub0 stack to {{network}}..."
  forge script script/deploySub0.s.sol:DeploySub0 -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast \
    --chain-id {{if network == "base-sepolia" { base_sepolia_chain_id } else { "31337" } }}
  # After deploy: set SUB0_ADDRESS in .env to "Sub0 (proxy):" from the log, then run: just set-cre-forwarder

test:
  @echo "Running tests..."
  forge test -vvvv

generate-question-id:
  @echo "Generating questionId = keccak256(question, creator, oracle)..."
  forge script script/generateQuestionId.s.sol:GenerateQuestionId -vvvv

get-market network="base-sepolia":
  @echo "Fetching market by questionId on {{network}}..."
  forge script script/getMarket.s.sol:GetMarket -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }}

create-market network="base-sepolia":
  @echo "Creating market on {{network}}..."
  forge script script/createMarket.s.sol:CreateMarket -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

create-bet network="base-sepolia":
  @echo "Creating bet on {{network}}..."
  forge script script/createBet.s.sol:CreateBet -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    # --broadcast

stake network="base-sepolia":
  @echo "Staking on {{network}}..."
  forge script script/stake.s.sol:Stake -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

redeem network="base-sepolia":
  @echo "Redeeming on {{network}}..."
  forge script script/redeem.s.sol:Redeem -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

execute-trade network="base-sepolia":
  @echo "Executing trade (relayer) on {{network}}..."
  forge script script/executeTrade.s.sol:ExecuteTrade -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

settle-market network="base-sepolia":
  @echo "Settling market (oracle resolve) on {{network}}..."
  forge script script/settleMarket.s.sol:SettleMarket -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

approve-vault network="base-sepolia":
  @echo "Approving vault (CTF) on {{network}}..."
  forge script script/approveVault.s.sol:ApproveVault -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-token network="base-sepolia":
  @echo "Allowlisting token on {{network}}..."
  forge script script/allowListToken.s.sol:AllowListToken -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

setup-permissions network="base-sepolia":
  @echo "Setting up permissions on {{network}}..."
  forge script script/setupPermissions.s.sol:SetupPermissions -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

# Set Chainlink CRE Keystone Forwarder on Sub0 and grant it GAME_CREATOR_ROLE.
# Requires .env: PRIVATE_KEY (Sub0 owner), SUB0_ADDRESS. Optional: CRE_FORWARDER_ADDRESS (defaults to Base Sepolia).
# Uses Base Sepolia RPC by default; pass network=local for localhost.
set-cre-forwarder network="base-sepolia":
  @echo "Setting CRE forwarder on Sub0 ({{network}})..."
  forge script script/setCreForwarder.s.sol:SetCreForwarder -vvvv \
    --rpc-url {{ base_sepolia_rpc }} \
    --broadcast

set-token-uri network="base-sepolia":
  @echo "Setting token URI (ConditionalTokensV2) on {{network}}..."
  forge script script/setTokenURI.s.sol:SetTokenURI -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-reporter network="base-sepolia":
  @echo "Allowlisting oracle reporter on {{network}}..."
  forge script script/allowListReporter.s.sol:AllowListReporter -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast

upgrade-sub0 network="base-sepolia":
  @echo "Upgrading Sub0 on {{network}}..."
  forge script script/upgradeSub0.s.sol:UpgradeSub0 -vvvv \
    --rpc-url {{if network == "base-sepolia" { base_sepolia_rpc } else { "http://localhost:8545" } }} \
    --broadcast
