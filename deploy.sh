#!/bin/bash
echo "Script triển khai hợp đồng Counter Seismic trên devnet trong Gitpod"

set -e
set -o pipefail
set -u

handle_error() {
    echo "Lỗi: Script thất bại tại dòng $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

cd ~

echo "Đang cập nhật hệ thống và cài đặt các phụ thuộc..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git build-essential jq

if ! command -v rustc &> /dev/null; then
    echo "Đang cài đặt Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust đã được cài đặt."
fi
rustc --version

echo "Đang cài đặt sfoundryup..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
export PATH="$HOME/.seismic/bin:$PATH"
source "$HOME/.bashrc"
sfoundryup

if [ ! -d "try-devnet" ]; then
    echo "Đang sao chép repository try-devnet..."
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
else
    echo "Repository try-devnet đã tồn tại. Đang cập nhật..."
    cd try-devnet
    git pull
    git submodule update --init --recursive
    cd ..
fi

echo "Đang triển khai hợp đồng..."
cd try-devnet/packages/contract/ || { echo "Không tìm thấy thư mục hợp đồng!"; exit 1; }
bash script/deploy.sh

echo "Đang thiết lập CLI với Bun..."
cd ~/try-devnet/packages/cli/ || { echo "Không tìm thấy thư mục CLI!"; exit 1; }
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
bun install

echo "Đang chạy script giao dịch..."
# Chạy transact.sh và lấy địa chỉ ví từ output
echo -e "\n" | bash script/transact.sh > transact_output.log 2>&1 || true
WALLET_ADDRESS=$(grep "Enter this address:" transact_output.log | awk '{print $NF}')
if [ -z "$WALLET_ADDRESS" ]; then
    echo "Lỗi: Không thể trích xuất địa chỉ ví từ output của transact.sh."
    cat transact_output.log
    exit 1
fi
echo "Địa chỉ ví: $WALLET_ADDRESS"

# Kiểm tra số dư ví
echo "Đang kiểm tra số dư ví..."
check_balance() {
    BALANCE=$(curl -s "https://explorer-2.seismicdev.net/api?module=account&action=balance&address=$WALLET_ADDRESS" | jq -r '.result')
    if [ -z "$BALANCE" ] || [ "$BALANCE" == "0" ]; then
        echo "Ví $WALLET_ADDRESS không có số dư."
        return 1
    else
        echo "Số dư ví $WALLET_ADDRESS: $BALANCE"
        return 0
    fi
}

# Hướng dẫn nạp tiền thủ công từ faucet
echo "Đang nạp tiền thủ công vào ví..."
FAUCET_URL="https://faucet-2.seismicdev.net/"
for i in {1..3}; do
    if ! check_balance; then
        echo "Vui lòng truy cập: $FAUCET_URL"
        echo "Nhập địa chỉ này: $WALLET_ADDRESS"
        echo "Hoàn tất yêu cầu faucet, sau đó nhấn Enter để tiếp tục..."
        read
    else
        echo "Đã xác nhận số dư!"
        # Chạy lại transact.sh nếu số dư đủ
        echo -e "\n" | bash script/transact.sh
        break
    fi
    if [ "$i" -eq 3 ]; then
        echo "Lỗi: Không thể nạp tiền vào ví sau 3 lần thử."
        echo "Vui lòng đảm bảo bạn đã nạp tiền cho $WALLET_ADDRESS tại $FAUCET_URL và chạy lại script."
        exit 1
    fi
done

echo "Triển khai và giao dịch hoàn tất thành công!"
