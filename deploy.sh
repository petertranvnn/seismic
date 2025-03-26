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
# Cập nhật PATH và source .bashrc để sử dụng sfoundryup ngay lập tức
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
bash script/transact.sh

echo "Deployment and transaction completed successfully!"
