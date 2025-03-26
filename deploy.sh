#!/bin/bash
echo "Script deploy Counter Seismic contract on devnet in Gitpod"

# Cài đặt các cờ để tăng độ an toàn
set -e  # Thoát ngay nếu lệnh thất bại
set -o pipefail  # Bắt lỗi trong pipeline
set -u  # Báo lỗi nếu biến chưa được khai báo

# Hàm xử lý lỗi
handle_error() {
    echo "Error: Script failed at line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

# Navigate đến thư mục home
cd ~

# Cập nhật hệ thống và cài đặt phụ thuộc
echo "Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y curl git build-essential jq -y

# Cài đặt Rust nếu chưa có
if ! command -v rustc &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust is already installed."
fi
rustc --version

# Cài đặt sfoundryup
echo "Installing sfoundryup..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
sfoundryup

# Clone hoặc cập nhật repository try-devnet
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

# Deploy contract
echo "Deploying contract..."
cd try-devnet/packages/contract/ || { echo "Contract directory not found!"; exit 1; }
bash script/deploy.sh

# Cài đặt Bun và chạy CLI
echo "Setting up CLI with Bun..."
cd ~/try-devnet/packages/cli/ || { echo "CLI directory not found!"; exit 1; }
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
bun install

# Chạy giao dịch
echo "Running transaction script..."
bash script/transact.sh

echo "Deployment and transaction completed successfully!"
