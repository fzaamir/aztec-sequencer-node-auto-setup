#!/usr/bin/env bash
set -euo pipefail

for cmd in curl docker jq ufw; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌ Missing command: $cmd" >&2
    exit 1
  fi
done

if command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
elif docker compose version &>/dev/null; then
  COMPOSE="docker compose"
else
  echo "❌ docker-compose not found" >&2
  exit 1
fi

BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="$AZTEC_DIR/data"
STATE_DIR="$HOME/.aztec/alpha-testnet"
IMAGE_TAG="0.87.2"
LOG_CHECK=10

clear
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              🚀 AZTEC NETWORK • SEQUENCER NODE              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}${BOLD}1) 📦 Install & Start Node${RESET}"
echo -e "${CYAN}${BOLD}2) 📄 View Logs${RESET}"
echo -e "${CYAN}${BOLD}3) 🧹 Full Reset (wipe everything)${RESET}"
echo -e "${CYAN}${BOLD}4) ❌ Exit${RESET}"
read -rp "👉 Choice [1-4]: " CHOICE

if [[ $CHOICE == 4 ]]; then
  exit 0

elif [[ $CHOICE == 2 ]]; then
  [[ -d $AZTEC_DIR ]] || { echo "❌ Not found: $AZTEC_DIR"; exit 1; }
  cd "$AZTEC_DIR"
  exec $COMPOSE logs -f

elif [[ $CHOICE == 3 ]]; then
  read -rp "⚠️  Wipe all Aztec data? (y/n): " c
  [[ $c =~ ^[Yy]$ ]] || exit 0
  docker rm -f aztec-sequencer 2>/dev/null || true
  docker rmi -f $(docker images --filter=reference='aztecprotocol/aztec*' -q) 2>/dev/null || true
  rm -rf "$AZTEC_DIR" "$STATE_DIR"
  echo -e "${GREEN}✅ Cleaned up.${RESET}"
  exit 0

elif [[ $CHOICE == 1 ]]; then
  read -rp "🔑 ETH private key (no 0x): " PRIV
  read -rp "📬 ETH public addr   (0x…): " PUB
  read -rp "🌐 Sepolia RPC URL: " RPC
  read -rp "🛰️  Sepolia Beacon : " BCN

  IP=$(curl -s https://ipinfo.io/ip||echo 127.0.0.1)
  echo -e "📡 Detected IP: ${GREEN}${BOLD}$IP${RESET}"
  read -rp "Use this? (y/n): " u
  [[ $u =~ ^[Yy]$ ]] || read -rp "Enter IP: " IP

  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y \
    curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop \
    nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
    ufw ca-certificates gnupg lsb-release &>/dev/null

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list &>/dev/null
  sudo apt-get update -y
  sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
  sudo systemctl enable --now docker

  sudo ufw allow 22
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  sudo ufw --force enable &>/dev/null

  curl -s https://install.aztec.network | bash
  echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.aztec/bin:$PATH"
  aztec-up alpha-testnet

  mkdir -p "$DATA_DIR" "$AZTEC_DIR"
  cat >"$AZTEC_DIR/.env"<<EOF
ETHEREUM_HOSTS=$RPC
L1_CONSENSUS_HOST_URLS=$BCN
VALIDATOR_PRIVATE_KEY=0x$PRIV
COINBASE=$PUB
P2P_IP=$IP
LOG_LEVEL=debug
EOF

  cat >"$AZTEC_DIR/docker-compose.yml"<<EOF
services:
  aztec-node:
    image: aztecprotocol/aztec:${IMAGE_TAG}
    container_name: aztec-sequencer
    network_mode: host
    env_file: .env
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js \
        start --network alpha-testnet --node --archiver --sequencer'
    volumes:
      - ${DATA_DIR}:/data
    restart: unless-stopped
EOF

  cd "$AZTEC_DIR"
  $COMPOSE up -d

  echo -e "\n🚀 Node started. To check sync:"
  echo "curl -s -X POST -H 'Content-Type: application/json' \\"
  echo "-d '{\"jsonrpc\":\"2.0\",\"method\":\"node_getL2Tips\",\"params\":[],\"id\":1}' \\"
  echo "http://localhost:8080 | jq -r \".result.proven.number\""

  echo -e "\n🔧 Register validator once synced:"
  echo "aztec add-l1-validator --l1-rpc-urls \$RPC --private-key 0x\$PRIV \\"
  echo "--attester \$PUB --proposer-eoa \$PUB --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \\"
  echo "--l1-chain-id 11155111"

  echo -e "\n🛰️  Find peer ID:"
  echo "docker logs aztec-sequencer 2>&1 | grep -o '\"peerId\":\"[^\"]*\"' | head -n1"

  echo -e "\n🛠️  Monitoring logs for errors (Ctrl+C to stop)"
  while true; do
    if ! docker ps --filter name=aztec-sequencer | grep -q aztec-sequencer; then
      $COMPOSE up -d
    fi
    if docker logs aztec-sequencer 2>&1 | tail -n200 | grep -q "Obtained L1 to L2 messages failed"; then
      $COMPOSE down -v
      rm -rf "$STATE_DIR"
      $COMPOSE up -d
    fi
    sleep "$LOG_CHECK"
  done

else
  echo "❌ Invalid choice."
  exit 1
fi
