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
MAGENTA="\033[1;35m"

AZTEC_DIR="$HOME/aztec-sequencer"
CONFIG_FILE="$AZTEC_DIR/config.json"
ENV_FILE="$AZTEC_DIR/.env"

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
echo "  [3] ♻️   Reinstall Node (using saved config)"
echo "  [4] 🔎  Show L2 Block Info + Sync Proof"
echo "  [5] ❌  Exit"
echo -e "${RESET}"
read -p "🔧 Enter your choice [1-5]: " CHOICE

# --- Fetch Latest Image Tag ---
fetch_latest_image_tag() {
  echo -e "${CYAN}🔍 Checking for latest Aztec Docker image...${RESET}"
  LATEST_TAG=$(curl -s "https://registry.hub.docker.com/v2/repositories/aztecprotocol/aztec/tags?page_size=100" \
    | jq -r '.results[].name' \
    | grep 'alpha-testnet' \
    | sort -Vr \
    | head -n 1)

  if [[ -z "$LATEST_TAG" ]]; then
    echo -e "${RED}❌ Failed to fetch latest tag. Falling back to default: 0.85.0-alpha-testnet.5${RESET}"
    LATEST_TAG="0.85.0-alpha-testnet.5"
  else
    echo -e "${GREEN}✅ Found latest tag: ${BOLD}$LATEST_TAG${RESET}"
  fi
  echo "$LATEST_TAG"
}

if [[ "$CHOICE" == "5" ]]; then
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
elif [[ "$CHOICE" == "4" ]]; then
  echo -e "\n🔍 ${CYAN}Fetching latest L2 block info...${RESET}"
  HTTP_PORT=$(jq -r .HTTP_PORT "$CONFIG_FILE" 2>/dev/null || echo 8080)

  BLOCK=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
    http://localhost:$HTTP_PORT | jq -r ".result.proven.number")

  if [[ -z "$BLOCK" || "$BLOCK" == "null" ]]; then
    echo -e "❌ ${RED}Failed to fetch block number.${RESET}"
  else
    echo -e "✅ ${GREEN}Current L2 Block Number: ${BOLD}$BLOCK${RESET}"
    echo -e "🔗 ${CYAN}Sync Proof:${RESET}"
    curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK\",\"$BLOCK\"],\"id\":67}" \
      http://localhost:$HTTP_PORT | jq
  fi
  exit 0
elif [[ "$CHOICE" == "3" ]]; then
  if [[ ! -f "$CONFIG_FILE" || ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ No saved config found. Run full install first (Option 1).${RESET}"
    exit 1
  fi

  echo -e "${CYAN}♻️  Reinstalling Aztec Node using saved config...${RESET}"
  cd "$AZTEC_DIR"
  IMAGE_TAG=$(fetch_latest_image_tag)
  docker pull aztecprotocol/aztec:$IMAGE_TAG
  docker compose down -v
  rm -rf /home/my-node/node
  sudo apt update -y && sudo apt upgrade -y
  docker compose up -d
  echo -e "${GREEN}✅ Node restarted with latest image and saved config.${RESET}"
  exit 0
fi

# --- Option 1: Full Install ---
IMAGE_TAG=$(fetch_latest_image_tag)
SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
echo -e "📡 ${YELLOW}Detected server IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"
read -p "🌐 Use this IP? (y/n): " use_detected_ip
if [[ "$use_detected_ip" != "y" && "$use_detected_ip" != "Y" ]]; then
    read -p "🔧 Enter your VPS/Server IP: " SERVER_IP
fi

read -p "🔑 Enter your ETH private key (no 0x): " ETH_PRIVATE_KEY

echo -e "\n📦 ${YELLOW}Default ports are 40400 (P2P) and 8080 (RPC)${RESET}"
read -p "⚙️  Use custom ports? (y/n): " use_custom_ports

if [[ "$use_custom_ports" == "y" || "$use_custom_ports" == "Y" ]]; then
    read -p "📍 Enter P2P port [default: 40400]: " TCP_UDP_PORT
    read -p "📍 Enter RPC port [default: 8080]: " HTTP_PORT
    TCP_UDP_PORT=${TCP_UDP_PORT:-40400}
    HTTP_PORT=${HTTP_PORT:-8080}
else
    TCP_UDP_PORT=40400
    HTTP_PORT=8080
fi

read -p "🔗 ETHEREUM_HOSTS [default: https://ethereum-sepolia-rpc.publicnode.com]: " ETHEREUM_HOSTS
ETHEREUM_HOSTS=${ETHEREUM_HOSTS:-"https://ethereum-sepolia-rpc.publicnode.com"}

read -p "📡 L1_CONSENSUS_HOST_URLS [default: https://ethereum-sepolia-beacon-api.publicnode.com]: " L1_CONSENSUS_HOST_URLS
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS:-"https://ethereum-sepolia-beacon-api.publicnode.com"}

# Save config
mkdir -p "$AZTEC_DIR"
cat <<EOF > "$CONFIG_FILE"
{
  "SERVER_IP": "$SERVER_IP",
  "TCP_UDP_PORT": "$TCP_UDP_PORT",
  "HTTP_PORT": "$HTTP_PORT",
  "ETHEREUM_HOSTS": "$ETHEREUM_HOSTS",
  "L1_CONSENSUS_HOST_URLS": "$L1_CONSENSUS_HOST_URLS"
}
EOF

cat <<EOF > "$ENV_FILE"
VALIDATOR_PRIVATE_KEY=$ETH_PRIVATE_KEY
P2P_IP=$SERVER_IP
ETHEREUM_HOSTS=$ETHEREUM_HOSTS
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS_HOST_URLS
EOF

# --- Install Dependencies ---
echo -e "\n🔧 ${YELLOW}${BOLD}Setting up system dependencies...${RESET}"
sudo apt update && sudo apt install -y curl jq git ufw apt-transport-https ca-certificates software-properties-common
sudo apt-get remove -y containerd || true
sudo apt-get purge -y containerd || true

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
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: \${VALIDATOR_PRIVATE_KEY}
      P2P_IP: \${P2P_IP}
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

# --- Health Check ---
echo -e "\n⏳ ${YELLOW}Waiting for Aztec node to come online...${RESET}"
MAX_ATTEMPTS=180
ATTEMPTS=0

while (( ATTEMPTS < MAX_ATTEMPTS )); do
  if curl -s --max-time 2 http://localhost:$HTTP_PORT > /dev/null; then
    echo -e "\n✅ ${GREEN}${BOLD}Aztec node is live on port ${HTTP_PORT}!${RESET}"
    break
  fi

  if ! docker ps | grep -q aztec-sequencer; then
    echo -e "\n❌ ${RED}Container crashed. Restarting...${RESET}"
    docker compose down -v
    rm -rf /home/my-node/node
    docker compose up -d
    ATTEMPTS=0
    sleep 10
    continue
  fi

  ((ATTEMPTS++))
  echo -e "🔄 Attempt $ATTEMPTS/$MAX_ATTEMPTS... waiting 5s"
  sleep 5
done
