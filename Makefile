.PHONY: all build test clean deploy-rebalance-local deploy-rebalance-testnet deploy-rebalance-polygon deploy-rebalance-holesky deploy-rebalance-base deploy-rebalance-arbitrum deploy-rebalance-bsc deploy-rebalance-mainnet deploy-rebalance-v2-local deploy-rebalance-v2-testnet deploy-rebalance-v2-polygon deploy-rebalance-v2-holesky deploy-rebalance-v2-base deploy-rebalance-v2-arbitrum deploy-rebalance-v2-bsc deploy-rebalance-v2-mainnet help

include .env

LOCAL_RPC_URL := http://127.0.0.1:8545

TESTNET_RPC := ${RPC_URL_TESTNET}

MAINNET_RPC := ${RPC_URL_MAINNET}

POLYGON_RPC := ${RPC_URL_POLYGON}

HOLESKY_RPC := ${RPC_URL_HOLESKY}

BASE_RPC := ${RPC_URL_BASE}

ARBITRUM_RPC := ${RPC_URL_ARBITRUM}

BSC_RPC := ${RPC_URL_BSC}

REBALANCE_SCRIPT := script/DeployRebalance.s.sol

REBALANCE_V2_SCRIPT := script/DeployRebalanceV2.s.sol

PRIVATE_KEY := ${PRIVATE_KEY}

all: help

build:

	@echo "Building contracts..."

	forge build

test:

	@echo "Running tests..."

	forge test -vvv

clean:

	@echo "Cleaning build artifacts..."

	forge clean

# Deploy Rebalance commands

deploy-rebalance-local:

	forge clean

	@echo "Deploying Rebalance to local network..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${LOCAL_RPC_URL} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		-vvv

deploy-rebalance-testnet:

	forge clean

	@echo "Deploying Rebalance to testnet..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${TESTNET_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${POLYGONSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-polygon:

	forge clean

	@echo "Deploying Rebalance to Polygon network..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${POLYGON_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${POLYGONSCAN_API_KEY} \

		--verifier etherscan \

		--legacy \

		-vvv

deploy-rebalance-holesky:

	forge clean

	@echo "Deploying Rebalance to Holesky test network..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${HOLESKY_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ETHERSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-base:

	forge clean

	@echo "Deploying Rebalance to Base network..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${BASE_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${BASESCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-arbitrum:

	forge clean

	@echo "Deploying Rebalance to Arbitrum network..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${ARBITRUM_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ARBISCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-bsc:

	forge clean

	@echo "Deploying Rebalance to BSC network..."

	forge script ${REBALANCE_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-rebalance-mainnet:

	forge clean

	@echo "Deploying Rebalance to Mainnet..."

	forge script ${REBALANCE_SCRIPT} \

		--rpc-url ${MAINNET_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ETHERSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

# Deploy RebalanceV2 commands

deploy-rebalance-v2-local:

	forge clean

	@echo "Deploying RebalanceV2 to local network..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${LOCAL_RPC_URL} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		-vvv

deploy-rebalance-v2-testnet:

	forge clean

	@echo "Deploying RebalanceV2 to testnet..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${TESTNET_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${POLYGONSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-v2-polygon:

	forge clean

	@echo "Deploying RebalanceV2 to Polygon network..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${POLYGON_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${POLYGONSCAN_API_KEY} \

		--verifier etherscan \

		--legacy \

		-vvv

deploy-rebalance-v2-holesky:

	forge clean

	@echo "Deploying RebalanceV2 to Holesky test network..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${HOLESKY_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ETHERSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-v2-base:

	forge clean

	@echo "Deploying RebalanceV2 to Base network..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${BASE_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${BASESCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-v2-arbitrum:

	forge clean

	@echo "Deploying RebalanceV2 to Arbitrum network..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${ARBITRUM_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ARBISCAN_API_KEY} \

		--verifier etherscan \

		-vvv

deploy-rebalance-v2-bsc:

	forge clean
	@echo "Deploying RebalanceV2 to BSC network..."
	forge script ${REBALANCE_V2_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-rebalance-v2-mainnet:

	forge clean

	@echo "Deploying RebalanceV2 to Mainnet..."

	forge script ${REBALANCE_V2_SCRIPT} \

		--rpc-url ${MAINNET_RPC} \

		--private-key ${PRIVATE_KEY} \

		--broadcast \

		--verify \

		--etherscan-api-key ${ETHERSCAN_API_KEY} \

		--verifier etherscan \

		-vvv

help:

	@echo "Available commands:"

	@echo "  make build                    - Build contracts"

	@echo "  make test                     - Run tests"

	@echo "  make clean                    - Clean build artifacts"

	@echo "  make deploy-rebalance-local   - Deploy Rebalance to local network"

	@echo "  make deploy-rebalance-testnet - Deploy Rebalance to testnet with verification"

	@echo "  make deploy-rebalance-polygon - Deploy Rebalance to Polygon with verification"

	@echo "  make deploy-rebalance-holesky - Deploy Rebalance to Holesky with verification"

	@echo "  make deploy-rebalance-base    - Deploy Rebalance to Base with verification"

	@echo "  make deploy-rebalance-arbitrum - Deploy Rebalance to Arbitrum with verification"

	@echo "  make deploy-rebalance-bsc     - Deploy Rebalance to BSC with verification"

	@echo "  make deploy-rebalance-mainnet - Deploy Rebalance to mainnet with verification (use with caution!)"

	@echo "  make deploy-rebalance-v2-local   - Deploy RebalanceV2 to local network"

	@echo "  make deploy-rebalance-v2-testnet - Deploy RebalanceV2 to testnet with verification"

	@echo "  make deploy-rebalance-v2-polygon - Deploy RebalanceV2 to Polygon with verification"

	@echo "  make deploy-rebalance-v2-holesky - Deploy RebalanceV2 to Holesky with verification"

	@echo "  make deploy-rebalance-v2-base    - Deploy RebalanceV2 to Base with verification"

	@echo "  make deploy-rebalance-v2-arbitrum - Deploy RebalanceV2 to Arbitrum with verification"

	@echo "  make deploy-rebalance-v2-bsc     - Deploy RebalanceV2 to BSC with verification"

	@echo "  make deploy-rebalance-v2-mainnet - Deploy RebalanceV2 to mainnet with verification (use with caution!)"

	@echo "  make help                     - Show this help message"

	@echo ""

	@echo "Before deploying, make sure to set up the required environment variables in .env file:"

	@echo "  For Rebalance:"

	@echo "    - MAIN_COLLATERAL_TOKEN: Address of the main collateral token (ERC20)"

	@echo "    - LAUNCH_TOKEN: Address of the launch token (ERC20)"

	@echo "  For RebalanceV2:"

	@echo "    - LAUNCH_TOKEN: Address of the launch token (ERC20)"

	@echo "    - PROFIT_WALLET_MERA_FUND: Address of MeraFund profit wallet"

	@echo "    - PROFIT_WALLET_POC_ROYALTY: Address of POC Royalty profit wallet"

	@echo "    - PROFIT_WALLET_POC_BUYBACK: Address of POC Buyback profit wallet"

	@echo "    - PROFIT_WALLET_DAO: Address of DAO profit wallet"

	@echo "  Common:"

	@echo "    - PRIVATE_KEY: Your private key for deployment"

	@echo "    - RPC_URL_*: RPC URLs for the networks you want to deploy to"

	@echo "    - *SCAN_API_KEY: API keys for contract verification"
