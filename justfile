set dotenv-load

# Sub0 prediction market – Just recipes

rpc_sepolia := "https://sepolia.base.org"
etherscan_api_key := "KZUFSFGHCEXRX2RITQI1PHX9SYEV6PGDQG"
etherscan_url := "https://api.etherscan.io/v2/api?chainid=11155111"

deploy network="sepolia":
  @echo "Deploying Sub0 stack to {{network}}..."
  forge script script/deploySub0.s.sol:DeploySub0 -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

test:
  @echo "Running tests..."
  forge test -vvvv

generate-question-id:
  @echo "Generating questionId = keccak256(question, creator, oracle)..."
  forge script script/generateQuestionId.s.sol:GenerateQuestionId -vvvv

get-market network="sepolia":
  @echo "Fetching market by questionId on {{network}}..."
  forge script script/getMarket.s.sol:GetMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }}

create-market network="sepolia":
  @echo "Creating market on {{network}}..."
  forge script script/createMarket.s.sol:CreateMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

create-bet network="sepolia":
  @echo "Creating bet on {{network}}..."
  forge script script/createBet.s.sol:CreateBet -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    # --broadcast

stake network="sepolia":
  @echo "Staking on {{network}}..."
  forge script script/stake.s.sol:Stake -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

redeem network="sepolia":
  @echo "Redeeming on {{network}}..."
  forge script script/redeem.s.sol:Redeem -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

execute-trade network="sepolia":
  @echo "Executing trade (relayer) on {{network}}..."
  forge script script/executeTrade.s.sol:ExecuteTrade -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

settle-market network="sepolia":
  @echo "Settling market (oracle resolve) on {{network}}..."
  forge script script/settleMarket.s.sol:SettleMarket -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

approve-vault network="sepolia":
  @echo "Approving vault (CTF) on {{network}}..."
  forge script script/approveVault.s.sol:ApproveVault -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

allowlist-token network="sepolia":
  @echo "Allowlisting token on {{network}}..."
  forge script script/allowListToken.s.sol:AllowListToken -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

setup-permissions network="sepolia":
  @echo "Setting up permissions on {{network}}..."
  forge script script/setupPermissions.s.sol:SetupPermissions -vvvv \
    --rpc-url {{if network == "sepolia" { rpc_sepolia } else { "http://localhost:8545" } }} \
    --broadcast

set-token-uri network="sepolia":
  @echo "Setting token URI (ConditionalTokensV2) on {{network}}..."
  forge script script/setTokenURI.s.sol:SetTokenURI -vvvv \
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
