#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo -e "\n🚀 \033[1;32mStarting Aztec Validator One-Click Setup\033[0m\n"

# 1. Update & Install System Dependencies
echo -e "📦 \033[1;34mUpdating and installing system packages...\033[0m"
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y \
  curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop \
  nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
  libleveldb-dev ca-certificates gnupg software-properties-common screen

# 2. Install Docker
echo -e "\n🐳 \033[1;34mInstalling Docker...\033[0m"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg || true
done

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl restart docker
sudo docker run hello-world || true

# 3. Install Aztec CLI
echo -e "\n🔧 \033[1;34mInstalling Aztec CLI tools...\033[0m"
bash <(curl -s https://install.aztec.network)
export PATH="$HOME/.aztec/bin:$PATH"

# 4. Gather Required Info
echo -e "\n🧠 \033[1;34mPlease enter the following info:\033[0m"
read -p "🔑 Validator PRIVATE KEY (without 0x): " PRIVATE_KEY
read -p "🏦 Validator ADDRESS (starts with 0x): " VALIDATOR_ADDRESS
read -p "🌐 L1 RPC URL (e.g., Alchemy/Ankr): " RPC_URL
read -p "📡 BEACON URL (e.g., Ankr Beacon): " BEACON_URL
SERVER_IP=$(curl -s ipv4.icanhazip.com)
echo -e "🖥️ Detected server IP: \033[1;32m$SERVER_IP\033[0m"

# 5. Configure Firewall
echo -e "\n🛡️ \033[1;34mSetting up UFW firewall...\033[0m"
yes | sudo ufw allow 22
yes | sudo ufw allow ssh
yes | sudo ufw allow 40400
yes | sudo ufw allow 8080
yes | sudo ufw --force enable

# 6. Start Node in screen session
echo -e "\n🌀 \033[1;34mLaunching Aztec node inside 'screen'...\033[0m"
screen -S aztec -dm bash -c "aztec start --node --archiver --sequencer \
  --network alpha-testnet \
  --l1-rpc-urls $RPC_URL \
  --l1-consensus-host-urls $BEACON_URL \
  --sequencer.validatorPrivateKey 0x$PRIVATE_KEY \
  --sequencer.coinbase $VALIDATOR_ADDRESS \
  --p2p.p2pIp $SERVER_IP \
  --p2p.maxTxPoolSize 1000000000"

echo -e "\n⏳ \033[1;33mWaiting for Aztec node to start on port 8080...\033[0m"
until curl -s http://localhost:8080 > /dev/null; do
  echo -e "🔄 Still waiting... \033[2m(trying again in 5s)\033[0m"
  sleep 5
done

echo -e "✅ \033[1;32mNode is up and running!\033[0m You can check logs with: \033[1m'screen -r aztec'\033[0m"

# 7. Instructions for Next Steps
echo -e "\n🎯 \033[1;34mNext Steps:\033[0m"
echo -e "1️⃣  Wait a few minutes for your node to fully sync with the network."
echo -e "2️⃣  Then run the following command to check block and proof:"
echo
echo -e "\033[1;33mBLOCK=\$(curl -s -X POST -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"method\":\"node_getL2Tips\",\"params\":[],\"id\":67}' http://localhost:8080 | jq -r \".result.proven.number\") && echo \"Block: \$BLOCK\" && echo \"Proof:\" && curl -s -X POST -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"node_getArchiveSiblingPath\\\",\\\"params\\\":[\\\"\$BLOCK\\\",\\\"\$BLOCK\\\"],\\\"id\\\":67}\" http://localhost:8080 | jq -r \".result\"\033[0m"
echo
echo -e "3️⃣  Open Discord and run: \033[1m/operator start\033[0m"
echo -e "4️⃣  Optional: Register validator on L1:"
echo
echo -e "\033[1;36maztec add-l1-validator \\"
echo "  --l1-rpc-urls $RPC_URL \\"
echo "  --private-key $PRIVATE_KEY \\"
echo "  --attester $VALIDATOR_ADDRESS \\"
echo "  --proposer-eoa $VALIDATOR_ADDRESS \\"
echo "  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \\"
echo -e "  --l1-chain-id 11155111\033[0m"

echo -e "\n🎉 \033[1;32mSetup complete! Your Aztec node is live and validating.\033[0m\n"
