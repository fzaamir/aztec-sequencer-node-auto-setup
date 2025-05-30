```bash
#!/usr/bin/env bash

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
STATE_DIR="$HOME/.aztec/alpha-testnet"
IMAGE_TAG="0.87.2"
LOG_CHECK_INTERVAL=10

clear
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              🚀 AZTEC NETWORK • SEQUENCER NODE              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}${BOLD}Please choose an option:${RESET}"
echo -e "${YELLOW}"
echo "  [1] 📦 Install & Start Node"
echo "  [2] 📄 View Logs"
echo "  [3] 🧹 Full Reset (Delete container, image & data)"
echo "  [4] ❌ Exit"
echo -e "${RESET}"
read -rp "👉 Enter choice [1-4]: " CHOICE

if [[ "$CHOICE" == "4" ]]; then
  echo -e "${YELLOW}👋 Goodbye!${RESET}"
  exit 0

elif [[ "$CHOICE" == "2" ]]; then
  if [[ -d "$AZTEC_DIR" ]]; then
    echo -e "${CYAN}📄 Streaming logs... Ctrl+C to stop.${RESET}"
    cd "$AZTEC_DIR"
    docker compose logs -f
  else
    echo -e "${RED}❌ Node directory not found: $AZTEC_DIR${RESET}"
  fi
  exit 0

elif [[ "$CHOICE" == "3" ]]; then
  echo -e "${RED}${BOLD}⚠️  Full reset will remove everything created by this script.${RESET}"
  read -rp "Proceed? (y/n): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🛑 Stopping container...${RESET}"
    docker rm -f aztec-sequencer 2>/dev/null || true
    echo -e "${YELLOW}🧯 Removing images...${RESET}"
    docker rmi -f aztecprotocol/aztec:${IMAGE_TAG} 2>/dev/null || true
    docker rmi -f aztecprotocol/aztec:alpha-testnet 2>/dev/null || true
    echo -e "${YELLOW}🧼 Deleting data and state...${RESET}"
    rm -rf "$AZTEC_DIR" "$STATE_DIR"
    echo -e "${GREEN}✅ Full reset complete.${RESET}"
  else
    echo -e "${CYAN}❎ Reset cancelled.${RESET}"
  fi
  exit 0

elif [[ "$CHOICE" == "1" ]]; then
  read -rp "🔑 ETH private key (no 0x): " ETH_PRIVATE_KEY
  read -rp "📬 ETH public address (0x…): " ETH_PUBLIC_ADDRESS
  read -rp "🌐 Sepolia RPC URL: " ETH_RPC_URL
  read -rp "🛰️ Sepolia Beacon URL: " BEACON_URL

  SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
  echo -e "📡 Detected IP: ${GREEN}${BOLD}$SERVER_IP${RESET}"
  read -rp "Use this IP? (y/n): " USE_IP
  if [[ ! "$USE_IP" =~ ^[Yy]$ ]]; then
    read -rp "Enter server IP: " SERVER_IP
  fi

  mkdir -p "$DATA_DIR"

  sudo apt update -y >/dev/null
  sudo apt install -y curl jq ufw ca-certificates gnupg lsb-release >/dev/null

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
  sudo systemctl enable --now docker

  sudo ufw allow 22
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  sudo ufw --force enable >/dev/null

  cat > "$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$ETH_RPC_URL
L1_CONSENSUS_HOST_URLS=$BEACON_URL
VALIDATOR_PRIVATE_KEY=0x$ETH_PRIVATE_KEY
COINBASE=$ETH_PUBLIC_ADDRESS
P2P_IP=$SERVER_IP
LOG_LEVEL=debug
EOF

  cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
version: "3.8"
services:
  aztec-node:
    image: aztecprotocol/aztec:${IMAGE_TAG}
    container_name: aztec-sequencer
    network_mode: host
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: \${VALIDATOR_PRIVATE_KEY}
      COINBASE: \${COINBASE}
      P2P_IP: \${P2P_IP}
      LOG_LEVEL: \${LOG_LEVEL}
    volumes:
      - ${DATA_DIR}:/data
    restart: unless-stopped
EOF

  cd "$AZTEC_DIR"
  echo -e "\n🚀 ${GREEN}${BOLD}Starting node...${RESET}"
  docker compose up -d

  echo -e "\n🛠️  ${CYAN}Monitoring logs for errors... Ctrl+C to stop.${RESET}"
  while true; do
    if ! docker ps | grep -q aztec-sequencer; then
      echo -e "\n❌ ${RED}Container stopped. Restarting...${RESET}"
      docker compose up -d
    fi
    if docker logs aztec-sequencer 2>&1 \
       | tail -n200 \
       | grep -q "Obtained L1 to L2 messages failed to be hashed"; then
      echo -e "\n${RED}🔥 Critical error detected. Recovering...${RESET}"
      docker compose down -v
      rm -rf "${STATE_DIR}"
      docker compose up -d
      echo -e "${GREEN}✅ Recovery complete.${RESET}"
    fi
    sleep $LOG_CHECK_INTERVAL
  done
else
  echo -e "${RED}❌ Invalid choice.${RESET}"
  exit 1
fi
```
