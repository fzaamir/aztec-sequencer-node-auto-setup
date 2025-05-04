#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"

echo -e "\n🚀 ${BOLD}${GREEN}STARTING AZTEC VALIDATOR ONE-CLICK SETUP${RESET}\n"

# 0. Check required base commands
for cmd in curl jq screen; do
  command -v $cmd >/dev/null 2>&1 || { echo -e "${RED}${BOLD}Missing required command: $cmd. Please install it first.${RESET}"; exit 1; }
done

# 1. Update & Install System Dependencies
echo -e "📦 ${BLUE}${BOLD}Updating and installing system packages...${RESET}"
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y \
  curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop \
  nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
  ca-certificates gnupg software-properties-common screen

# 2. Install Docker
echo -e "\n🐳 ${BLUE}${BOLD}Installing Docker...${RESET}"
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
echo -e "\n🔧 ${BLUE}${BOLD}Installing Aztec CLI tools...${RESET}"
bash <(curl -s https://install.aztec.network)
export PATH="$HOME/.aztec/bin:$PATH"
echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc

# Confirm installation
if ! command -v aztec >/dev/null 2>&1; then
  echo -e "${RED}${BOLD}Aztec CLI installation failed. Please check installation logs.${RESET}"
  exit 1
fi

# Optional init (safe)
aztec init --network alpha-testnet || true

# 4. Gather Required Info
echo -e "\n🧠 ${BLUE}${BOLD}Please enter the following information:${RESET}"
read -p "🔑 Validator PRIVATE KEY (without 0x): " PRIVATE_KEY
read -p "🏦 Validator ADDRESS (starts with 0x): " VALIDATOR_ADDRESS
read -p "🌐 L1 RPC URL (e.g., Alchemy/Ankr): " RPC_URL
read -p "📡 BEACON URL (e.g., Ankr Beacon): " BEACON_URL
SERVER_IP=$(curl -s ipv4.icanhazip.com || echo "127.0.0.1")
echo -e "🖥️ Detected server IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"

# 5. Configure Firewall
echo -e "\n🛡️ ${BLUE}${BOLD}Setting up UFW firewall...${RESET}"
sudo ufw allow 22/tcp comment 'Allow SSH'
sudo ufw allow 40400/tcp comment 'Aztec P2P'
sudo ufw allow 8080/tcp comment 'Aztec RPC'
sudo ufw --force enable

# 6. Start Node in screen session
echo -e "\n🌀 ${BLUE}${BOLD}Launching Aztec node inside 'screen' session...${RESET}"
screen -S aztec -dm bash -c "aztec start --node --archiver --sequencer \
  --network alpha-testnet \
  --l1-rpc-urls $RPC_URL \
  --l1-consensus-host-urls $BEACON_URL \
  --sequencer.validatorPrivateKey 0x$PRIVATE_KEY \
  --sequencer.coinbase $VALIDATOR_ADDRESS \
  --p2p.p2pIp $SERVER_IP \
  --p2p.maxTxPoolSize 1000000000 2>&1 | tee ~/aztec-node.log"

# 6.1 Wait for node to respond
echo -e "\n⏳ ${YELLOW}${BOLD}Waiting for Aztec node to become responsive on port 8080...${RESET}"

ATTEMPTS=0
MAX_ATTEMPTS=60

until curl -s --max-time 2 http://localhost:8080 > /dev/null; do
  ((ATTEMPTS++))
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo -e "\n❌ ${RED}${BOLD}Node failed to start after $MAX_ATTEMPTS attempts (~5 minutes).${RESET}"
    echo -e "💡 Run ${BOLD}screen -r aztec${RESET} to view logs and troubleshoot."
    exit 1
  fi
  echo -e "🔄 Attempt $ATTEMPTS/$MAX_ATTEMPTS: Waiting 5s..."
  sleep 5
done

echo -e "\n✅ ${GREEN}${BOLD}Node is LIVE and responding on port 8080!${RESET}"
echo -e "📋 To view logs: ${BOLD}screen -r aztec${RESET}"

# 7. Instructions for Next Steps
echo -e "\n🎯 ${BLUE}${BOLD}Next Steps:${RESET}"
echo -e "1️⃣  Wait a few minutes for your node to fully sync with the network."
echo -e "2️⃣  Run the following command to check block and proof:\n"
echo -e "${YELLOW}${BOLD}BLOCK=\$(curl -s -X POST -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"method\":\"node_getL2Tips\",\"params\":[],\"id\":67}' http://localhost:8080 | jq -r \".result.proven.number\") && echo \"Block: \$BLOCK\" && echo \"Proof:\" && curl -s -X POST -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"node_getArchiveSiblingPath\\\",\\\"params\\\":[\\\"\$BLOCK\\\",\\\"\$BLOCK\\\"],\\\"id\\\":67}\" http://localhost:8080 | jq -r \".result\"${RESET}\n"
echo -e "3️⃣  Open Discord and run: ${BOLD}/operator start${RESET}"
echo -e "4️⃣  Optional: Register validator on L1:\n"
echo -e "${CYAN}${BOLD}aztec add-l1-validator \\"
echo "  --l1-rpc-urls $RPC_URL \\"
echo "  --private-key $PRIVATE_KEY \\"
echo "  --attester $VALIDATOR_ADDRESS \\"
echo "  --proposer-eoa $VALIDATOR_ADDRESS \\"
echo "  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \\"
echo -e "  --l1-chain-id 11155111${RESET}\n"

echo -e "🎉 ${GREEN}${BOLD}Setup complete! Your Aztec node is live and validating.${RESET}\n"
