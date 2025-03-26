#!/bin/bash
echo "Script deploy Counter Seismic contract on devnet in Gitpod"

set -e
set -o pipefail
set -u

handle_error() {
    echo "Error: Script failed at line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

cd ~

echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git build-essential jq

if ! command -v rustc &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust is already installed."
fi
rustc --version

echo "Installing sfoundryup..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
export PATH="$HOME/.seismic/bin:$PATH"
source "$HOME/.bashrc"
sfoundryup

if [ ! -d "try-devnet" ]; then
    echo "Cloning try-devnet repository..."
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
else
    echo "try-devnet repository exists. Updating..."
    cd try-devnet
    git pull
    git submodule update --init --recursive
    cd ..
fi

echo "Deploying contract..."
cd try-devnet/packages/contract/ || { echo "Contract directory not found!"; exit 1; }
bash script/deploy.sh

echo "Setting up CLI with Bun..."
cd ~/try-devnet/packages/cli/ || { echo "CLI directory not found!"; exit 1; }
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
bun install

echo "Running transaction script..."
# Chạy transact.sh và lấy địa chỉ ví từ output
echo -e "\n" | bash script/transact.sh > transact_output.log 2>&1 || true
WALLET_ADDRESS=$(grep "Enter this address:" transact_output.log | awk '{print $NF}')
if [ -z "$WALLET_ADDRESS" ]; then
    echo "Error: Could not extract wallet address from transact.sh output."
    cat transact_output.log
    exit 1
fi
echo "Wallet address: $WALLET_ADDRESS"

# Kiểm tra số dư ví
echo "Checking wallet balance..."
check_balance() {
    # Giả định dùng API explorer để kiểm tra số dư
    BALANCE=$(curl -s "https://explorer-2.seismicdev.net/api?module=account&action=balance&address=$WALLET_ADDRESS" | jq -r '.result')
    if [ -z "$BALANCE" ] || [ "$BALANCE" == "0" ]; then
        echo "Wallet $WALLET_ADDRESS has no funds."
        return 1
    else
        echo "Wallet $WALLET_ADDRESS balance: $BALANCE"
        return 0
    fi
}

# Tự động nạp tiền từ faucet và kiểm tra số dư
FAUCET_URL="https://faucet-2.seismicdev.net/api"  # Giả định API endpoint
echo "Attempting to fund wallet automatically..."
for i in {1..3}; do
    if ! check_balance; then
        echo "Attempt $i: Requesting funds from faucet..."
        # Giả định faucet hỗ trợ POST request với địa chỉ ví
        RESPONSE=$(curl -s -X POST "$FAUCET_URL" -H "Content-Type: application/json" -d "{\"address\": \"$WALLET_ADDRESS\"}")
        if echo "$RESPONSE" | grep -q "success"; then
            echo "Faucet request submitted. Waiting 30 seconds for transaction..."
            sleep 30
        else
            echo "Warning: Faucet request failed. Response: $RESPONSE"
        fi
    else
        echo "Funds verified!"
        # Chạy lại transact.sh nếu số dư đủ
        echo -e "\n" | bash script/transact.sh
        break
    fi
    if [ "$i" -eq 3 ]; then
        echo "Error: Failed to fund wallet after 3 attempts."
        echo "Please fund manually at https://faucet-2.seismicdev.net/ with address $WALLET_ADDRESS and rerun the script."
        exit 1
    fi
done

echo "Deployment and transaction completed successfully!"
