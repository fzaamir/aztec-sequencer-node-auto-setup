#!/bin/bash

set -e

# --- STYLES ---
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"

# --- MENU HEADER ---
clear
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  🚀 FZ AMIR • AZTEC NODE TOOL                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# --- MENU OPTIONS ---
echo -e "${CYAN}${BOLD}Please choose an option below:${RESET}"
echo -e "${YELLOW}"
echo "  [1] 📦  Install Aztec Sequencer Node"
echo "  [2] 📄  View Aztec Node Logs"
echo "  [3] ❌  Exit"
echo -e "${RESET}"
read -p "🔧 Enter your choice [1-3]: " CHOICE

if [[ "$CHOICE" == "3" ]]; then
  echo -e "${YELLOW}👋 Exiting. Have a great day!${RESET}"
  exit 0
elif [[ "$CHOICE" == "2" ]]; then
  if [[ -d "$AZTEC_DIR" ]]; then
    echo -e "${CYAN}📄 Streaming logs from $AZTEC_DIR ... Press Ctrl+C to exit.${RESET}"
    cd "$AZTEC_DIR"
    docker-compose logs -f
  else
    echo -e "${RED}❌ Aztec node directory not found: $AZTEC_DIR${RESET}"
  fi
  exit 0
fi

# --- Option 1: Full Install ---
IMAGE_TAG="0.85.0-alpha-testnet.8"
SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
echo -e "📱 ${YELLOW}Detected server IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"
read -p "🌐 Use this IP? (y/n): " use_detected_ip
if [[ "$use_detected_ip" != "y" && "$use_detected_ip" != "Y" ]]; then
    read -p "🔧 Enter your VPS/Server IP: " SERVER_IP
fi

mkdir -p "$AZTEC_DIR"

read -p "🔑 Enter your ETH private key (no 0x): " ETH_PRIVATE_KEY
PRIVATE_KEY="${ETH_PRIVATE_KEY}"
unset ETH_PRIVATE_KEY

read -p "🔗 ETHEREUM_HOSTS [default: https://ethereum-sepolia-rpc.publicnode.com]: " ETHEREUM_HOSTS
ETHEREUM_HOSTS=${ETHEREUM_HOSTS:-"https://ethereum-sepolia-rpc.publicnode.com"}

read -p "📱 L1_CONSENSUS_HOST_URLS [default: https://ethereum-sepolia-beacon-api.publicnode.com]: " L1_CONSENSUS_HOST_URLS
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS:-"https://ethereum-sepolia-beacon-api.publicnode.com"}

TCP_UDP_PORT=40400
HTTP_PORT=8080

# --- Install Dependencies ---
echo -e "\n🔧 ${YELLOW}${BOLD}Setting up system dependencies...${RESET}"
sudo apt update && sudo apt install -y curl jq ufw ca-certificates gnupg

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker && sudo systemctl restart docker

sudo ufw allow 22
sudo ufw allow "$TCP_UDP_PORT"/tcp
sudo ufw allow "$TCP_UDP_PORT"/udp
sudo ufw allow "$HTTP_PORT"/tcp
sudo ufw --force enable

# --- Docker Compose Setup ---
cat <<EOF > "$AZTEC_DIR/docker-compose.yml"
services:
  node:
    image: aztecprotocol/aztec:$IMAGE_TAG
    container_name: aztec-sequencer
    environment:
      ETHEREUM_HOSTS: $ETHEREUM_HOSTS
      L1_CONSENSUS_HOST_URLS: $L1_CONSENSUS_HOST_URLS
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: $PRIVATE_KEY
      P2P_IP: $SERVER_IP
      LOG_LEVEL: debug
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer'
    ports:
      - $TCP_UDP_PORT:40400/tcp
      - $TCP_UDP_PORT:40400/udp
      - $HTTP_PORT:8080
    volumes:
      - /home/my-node/node:/data
    restart: unless-stopped
EOF

# --- Start Node ---
cd "$AZTEC_DIR"
docker compose up -d

# --- Continuous Health Monitoring ---
echo -e "\n🛠️  ${CYAN}Monitoring logs for critical errors...${RESET}"
LOG_CHECK_INTERVAL=10
while true; do
  if ! docker ps | grep -q aztec-sequencer; then
    echo -e "\n❌ ${RED}Container stopped. Restarting...${RESET}"
    docker compose up -d
  fi

  ERROR_DETECTED=$(docker logs aztec-sequencer 2>&1 | tail -n 200 | grep -F "Obtained L1 to L2 messages failed to be hashed to the block inHash")
  if [[ -n "$ERROR_DETECTED" ]]; then
    echo -e "\n${RED}🔥 Critical error detected. Restarting node and clearing state...${RESET}"
    docker compose down -v
    rm -rf /root/.aztec/alpha-testnet
    docker compose up -d
    echo -e "${GREEN}✅ Node restarted after error recovery.${RESET}"
  fi
  sleep $LOG_CHECK_INTERVAL
done
