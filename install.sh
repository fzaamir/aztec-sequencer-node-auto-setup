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

# --- HEADER ---
clear
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║              FZ AMIR • AZTEC NODE INSTALLER          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# --- IP Detection ---
SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
echo -e "📡 ${YELLOW}Detected server IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"
read -p "🌐 Use this IP? (y/n): " use_detected_ip
if [[ "$use_detected_ip" != "y" && "$use_detected_ip" != "Y" ]]; then
    read -p "🔧 Enter your VPS/Server IP: " SERVER_IP
fi

# --- Private Key ---
read -p "🔑 Enter your ETH private key (no 0x): " ETH_PRIVATE_KEY

# --- Port Configuration ---
echo -e "\n📦 ${YELLOW}Default ports are 40400 (P2P) and 8080 (RPC)${RESET}"
read -p "⚙️  Do you want to use custom ports? (y/n): " use_custom_ports

if [[ "$use_custom_ports" == "y" || "$use_custom_ports" == "Y" ]]; then
    read -p "📍 Enter P2P port [default: 40400]: " TCP_UDP_PORT
    read -p "📍 Enter RPC port [default: 8080]: " HTTP_PORT
    TCP_UDP_PORT=${TCP_UDP_PORT:-40400}
    HTTP_PORT=${HTTP_PORT:-8080}
else
    TCP_UDP_PORT=40400
    HTTP_PORT=8080
fi

# --- Ask for RPC endpoints ---
echo -e "\n🌐 ${YELLOW}Enter L1 RPC endpoint (e.g. Ankr, Alchemy, or public node):${RESET}"
read -p "🔗 ETHEREUM_HOSTS [default: https://ethereum-sepolia-rpc.publicnode.com]: " ETHEREUM_HOSTS
ETHEREUM_HOSTS=${ETHEREUM_HOSTS:-"https://ethereum-sepolia-rpc.publicnode.com"}

echo -e "\n🛰️  ${YELLOW}Enter Beacon API endpoint:${RESET}"
read -p "📡 L1_CONSENSUS_HOST_URLS [default: https://ethereum-sepolia-beacon-api.publicnode.com]: " L1_CONSENSUS_HOST_URLS
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS:-"https://ethereum-sepolia-beacon-api.publicnode.com"}

# --- Update System ---
echo -e "\n🔧 ${BLUE}${BOLD}Updating system and installing prerequisites...${RESET}"
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl jq git ufw apt-transport-https ca-certificates software-properties-common

# --- Fix for Ubuntu 24.04 containerd conflict ---
echo -e "\n🔧 ${BLUE}${BOLD}Resolving Docker containerd conflicts...${RESET}"
sudo apt-get remove -y containerd || true
sudo apt-get purge -y containerd || true

# --- Install Docker ---
echo -e "\n🐳 ${BLUE}${BOLD}Installing Docker...${RESET}"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# --- Enable Docker ---
sudo systemctl enable docker
sudo systemctl restart docker

# --- Configure Firewall ---
echo -e "\n🛡️  ${BLUE}${BOLD}Configuring UFW Firewall...${RESET}"
sudo ufw allow 22/tcp comment 'Allow SSH'
sudo ufw allow "${TCP_UDP_PORT}"/tcp comment 'Aztec TCP'
sudo ufw allow "${TCP_UDP_PORT}"/udp comment 'Aztec UDP'
sudo ufw allow "${HTTP_PORT}"/tcp comment 'Aztec RPC'
sudo ufw --force enable

# --- Install Aztec CLI (optional for tooling) ---
echo -e "\n🔩 ${BLUE}${BOLD}Installing Aztec CLI tools...${RESET}"
curl -s https://install.aztec.network > aztec_install.sh
echo "y" | bash aztec_install.sh
echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.aztec/bin:$PATH"

# --- Setup Aztec Sequencer Directory ---
echo -e "\n📁 ${BLUE}${BOLD}Setting up Aztec Sequencer files...${RESET}"
mkdir -p ~/aztec-sequencer
cd ~/aztec-sequencer

# --- Create .env ---
echo -e "${CYAN}→ Creating .env file...${RESET}"
cat <<EOF > .env
VALIDATOR_PRIVATE_KEY=${ETH_PRIVATE_KEY}
P2P_IP=${SERVER_IP}
ETHEREUM_HOSTS=${ETHEREUM_HOSTS}
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS}
EOF

# --- Create docker-compose.yml ---
echo -e "${CYAN}→ Creating docker-compose.yml...${RESET}"
cat <<EOF > docker-compose.yml
services:
  node:
    image: aztecprotocol/aztec:0.85.0-alpha-testnet.5
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
      - ${TCP_UDP_PORT}:40400/tcp
      - ${TCP_UDP_PORT}:40400/udp
      - ${HTTP_PORT}:8080
    volumes:
      - /home/my-node/node:/data
    restart: unless-stopped
EOF

# --- Start Docker Container ---
echo -e "\n🚀 ${BLUE}${BOLD}Starting Aztec Sequencer Node via Docker Compose...${RESET}"
docker compose up -d

# --- Health Check and Recovery ---
echo -e "\n⏳ ${YELLOW}${BOLD}Waiting for Aztec node to respond on port ${HTTP_PORT} (up to 15 minutes)...${RESET}"
MAX_ATTEMPTS=180
ATTEMPTS=0

while (( ATTEMPTS < MAX_ATTEMPTS )); do
  if curl -s --max-time 2 http://localhost:${HTTP_PORT} > /dev/null; then
    echo -e "\n✅ ${GREEN}${BOLD}Aztec node is live on port ${HTTP_PORT}!${RESET}"
    break
  fi

  if ! docker ps | grep -q aztec-sequencer; then
    echo -e "\n❌ ${RED}${BOLD}Aztec container stopped. Attempting recovery...${RESET}"
    docker compose down -v
    rm -rf /home/my-node/node
    docker compose up -d
    ATTEMPTS=0
    sleep 10
    continue
  fi

  LOG_PATH="$(docker inspect --format='{{.LogPath}}' aztec-sequencer 2>/dev/null)"
  if [[ -f "$LOG_PATH" ]] && grep -q "failed to be hashed to the block inHash" "$LOG_PATH"; then
    echo -e "\n⚠️  ${RED}${BOLD}Detected sync hash error in logs. Cleaning corrupted state...${RESET}"
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

if (( ATTEMPTS >= MAX_ATTEMPTS )); then
  echo -e "\n❌ ${RED}${BOLD}Node failed to respond after $MAX_ATTEMPTS attempts.${RESET}"
  echo -e "🧪 Run ${BOLD}docker-compose logs -f${RESET} in ~/aztec-sequencer to debug."
  exit 1
fi

# --- Summary ---
echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════════"
echo -e "          ✅ FZ AMIR • AZTEC NODE IS READY ✅"
echo -e "══════════════════════════════════════════════════════${RESET}"
echo
echo -e "${BOLD}Node Info:${RESET}"
echo -e "🌐 IP Address   : ${GREEN}$SERVER_IP${RESET}"
echo -e "📡 P2P Port     : ${YELLOW}$TCP_UDP_PORT${RESET}"
echo -e "🧠 RPC Port     : ${YELLOW}$HTTP_PORT${RESET}"
echo -e "🔗 L1 RPC       : ${CYAN}$ETHEREUM_HOSTS${RESET}"
echo -e "📡 Beacon URL   : ${CYAN}$L1_CONSENSUS_HOST_URLS${RESET}"
echo
echo -e "${BOLD}Commands:${RESET}"
echo -e "📄 View logs     : ${CYAN}cd ~/aztec-sequencer && docker-compose logs -f${RESET}"
echo -e "🛑 Stop node     : ${CYAN}cd ~/aztec-sequencer && docker compose down -v${RESET}"
echo -e "🔄 Restart node  : ${CYAN}cd ~/aztec-sequencer && docker restart aztec-sequencer${RESET}"
echo
echo -e "🎉 ${GREEN}${BOLD}Installation complete! Your Aztec Sequencer Node is running.${RESET}"
echo
