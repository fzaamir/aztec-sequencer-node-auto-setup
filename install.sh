#!/bin/bash

set -euo pipefail

BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="$AZTEC_DIR/data"
IMAGE_TAG="0.85.0-alpha-testnet.8"
TCP_UDP_PORT=40400
HTTP_PORT=8080
LOG_CHECK_INTERVAL=10

clear
echo -e "${BLUE}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                       🚀 AZTEC NODE INSTALLER                      ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${CYAN}${BOLD}Choose an option below:${RESET}"
echo -e "${YELLOW}${BOLD}"
echo "   [1] 📦 Install Aztec Node"
echo "   [2] 📄 View Node Logs"
echo "   [3] ❌ Exit"
echo -e "${RESET}"
read -rp "👉 Enter choice [1-3]: " CHOICE

if [[ "$CHOICE" == "3" ]]; then
  echo -e "${YELLOW}👋 Goodbye!${RESET}"
  exit 0
elif [[ "$CHOICE" == "2" ]]; then
  if [[ -d "$AZTEC_DIR" ]]; then
    echo -e "${CYAN}📄 Streaming logs... Ctrl+C to exit.${RESET}"
    cd "$AZTEC_DIR"
    docker compose logs -f
  else
    echo -e "${RED}❌ Node not found at $AZTEC_DIR${RESET}"
  fi
  exit 0
fi

echo -e "${CYAN}${BOLD}🔧 Installing Docker & Dependencies...${RESET}"
sudo apt update -y > /dev/null
sudo apt install -y curl jq ufw ca-certificates gnupg lsb-release software-properties-common > /dev/null

if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo bash
fi

if ! command -v docker-compose &>/dev/null; then
  sudo apt install -y docker-compose-plugin
fi

sudo systemctl enable docker
sudo systemctl restart docker

sudo ufw allow 22
sudo ufw allow "$TCP_UDP_PORT"/tcp
sudo ufw allow "$TCP_UDP_PORT"/udp
sudo ufw allow "$HTTP_PORT"/tcp
sudo ufw --force enable

SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
echo -e "\n${YELLOW}🌐 Detected IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"
read -rp "Use this IP? (y/n): " USE_IP
if [[ "$USE_IP" != "y" && "$USE_IP" != "Y" ]]; then
  read -rp "Enter custom server IP: " SERVER_IP
fi

mkdir -p "$DATA_DIR"

read -rp "🔑 ETH Private Key (no 0x): " ETH_PRIVATE_KEY
PRIVATE_KEY="${ETH_PRIVATE_KEY}"
unset ETH_PRIVATE_KEY

read -rp "🔗 ETHEREUM_HOSTS [default: https://ethereum-sepolia-rpc.publicnode.com]: " ETHEREUM_HOSTS
ETHEREUM_HOSTS=${ETHEREUM_HOSTS:-"https://ethereum-sepolia-rpc.publicnode.com"}

read -rp "📡 L1_CONSENSUS_HOST_URLS [default: https://ethereum-sepolia-beacon-api.publicnode.com]: " L1_CONSENSUS_HOST_URLS
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS:-"https://ethereum-sepolia-beacon-api.publicnode.com"}

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
      - "$TCP_UDP_PORT:50500/tcp"
      - "$TCP_UDP_PORT:50500/udp"
      - "$HTTP_PORT:9090"
    volumes:
      - $DATA_DIR:/data
    restart: unless-stopped
EOF

cd "$AZTEC_DIR"
docker compose up -d

echo -e "\n${GREEN}✅ Aztec Node started successfully!${RESET}"
echo -e "${CYAN}🔍 Monitoring logs for issues...${RESET}"

while true; do
  if ! docker ps | grep -q aztec-sequencer; then
    echo -e "\n${RED}❌ Node stopped. Restarting...${RESET}"
    docker compose up -d
  fi

  if docker logs aztec-sequencer 2>&1 | tail -n 200 | grep -q "Obtained L1 to L2 messages failed to be hashed to the block inHash"; then
    echo -e "\n${RED}🔥 Critical error detected. Restarting...${RESET}"
    docker compose down -v
    rm -rf "$HOME/.aztec/alpha-testnet"
    docker compose up -d
    echo -e "${GREEN}✅ Recovery complete.${RESET}"
  fi

  sleep $LOG_CHECK_INTERVAL
done
