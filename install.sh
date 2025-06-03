#!/usr/bin/env bash
set -euo pipefail

BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="$AZTEC_DIR/data"
STATE_DIR="$HOME/.aztec/alpha-testnet"
IMAGE_TAG="0.87.6"
LOG_CHECK_INTERVAL=10

detect_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD=""
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo -e "${GREEN}✔ Docker is already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}⏳ Installing Docker...${RESET}"
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release &>/dev/null
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list &>/dev/null
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin &>/dev/null
  sudo systemctl enable --now docker
  echo -e "${GREEN}✔ Docker installation complete.${RESET}"
}

install_docker_compose() {
  detect_compose
  if [[ -n "$COMPOSE_CMD" ]]; then
    echo -e "${GREEN}✔ Docker Compose is already installed (${COMPOSE_CMD}).${RESET}"
    return
  fi
  echo -e "${CYAN}⏳ Installing Docker Compose (plugin)...${RESET}"
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y docker-compose-plugin &>/dev/null
  detect_compose
  if [[ -z "$COMPOSE_CMD" ]]; then
    echo -e "${RED}✖ Failed to install Docker Compose.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}✔ Docker Compose installation complete (${COMPOSE_CMD}).${RESET}"
}

prompt_yes_no() {
  local prompt_msg="$1"
  local response
  while true; do
    read -rp "$prompt_msg (y/n): " response
    case "$response" in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) echo "Please answer y or n." ;;
    esac
  done
}

full_reset() {
  echo -e "${YELLOW}⚠️  You are about to wipe all Aztec sequencer data.${RESET}"
  if ! prompt_yes_no "Are you sure you want to proceed?"; then
    echo -e "${CYAN}Operation cancelled. Returning to menu...${RESET}"
    sleep 1
    return
  fi
  echo -e "${CYAN}🧹 Removing Docker containers and images...${RESET}"
  docker rm -f aztec-sequencer 2>/dev/null || true
  docker rmi -f "$(docker images --filter=reference='aztecprotocol/aztec*' -q)" 2>/dev/null || true
  echo -e "${CYAN}🗑️ Deleting directories:${RESET}"
  rm -rf "$AZTEC_DIR" "$STATE_DIR"
  echo -e "${GREEN}✅ All data wiped. Returning to menu...${RESET}"
  sleep 1
}

install_and_start_node() {
  echo
  read -rp "🔑 ETH private key (no 0x): " PRIV_KEY
  read -rp "📬 ETH public address (0x…): " PUB_ADDR
  read -rp "🌐 Sepolia RPC URL: " RPC_URL
  read -rp "🛰️  Sepolia Beacon URL: " BCN_URL

  local IP
  IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
  echo -e "📡 Using detected IP: ${GREEN}${BOLD}${IP}${RESET}"

  echo -e "${CYAN}📦 Checking and installing required packages...${RESET}"
  REQ_PKGS=(curl build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip ufw ca-certificates gnupg lsb-release)
  MISSING_PKGS=()
  for pkg in "${REQ_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      MISSING_PKGS+=("$pkg")
    fi
  done
  if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    sudo apt-get update -y &>/dev/null
    sudo apt-get install -y "${MISSING_PKGS[@]}" &>/dev/null
    echo -e "${GREEN}✔ Installed missing packages: ${MISSING_PKGS[*]}.${RESET}"
  else
    echo -e "${GREEN}✔ All required packages are already installed.${RESET}"
  fi

  install_docker
  install_docker_compose

  echo -e "${CYAN}🔐 Configuring UFW firewall...${RESET}"
  sudo ufw allow 22/tcp
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  sudo ufw --force enable &>/dev/null

  echo -e "${CYAN}📥 Installing Aztec CLI...${RESET}"
  curl -s https://install.aztec.network | bash
  echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.aztec/bin:$PATH"

  echo -e "${CYAN}⚙️ Initializing Aztec alpha-testnet...${RESET}"
  aztec-up alpha-testnet

  mkdir -p "$DATA_DIR" "$AZTEC_DIR"

  cat >"$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$RPC_URL
L1_CONSENSUS_HOST_URLS=$BCN_URL
VALIDATOR_PRIVATE_KEY=0x$PRIV_KEY
COINBASE=$PUB_ADDR
P2P_IP=$IP
LOG_LEVEL=debug
EOF

  cat >"$AZTEC_DIR/docker-compose.yml" <<EOF
version: '3.8'
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

  echo -e "${CYAN}🚀 Starting Aztec sequencer container...${RESET}"
  pushd "$AZTEC_DIR" >/dev/null
  if [[ "$COMPOSE_CMD" == "docker-compose" ]]; then
    $COMPOSE_CMD up -d
  else
    $COMPOSE_CMD up -d
  fi
  popd >/dev/null

  echo -e "\n${GREEN}✅ Node started successfully!${RESET}"
  echo "Press any key to return to the main menu."
  read -n1 -s
}

view_logs() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Directory not found: $AZTEC_DIR${RESET}"
    echo "Press any key to return to the main menu."
    read -n1 -s
    return
  fi
  echo -e "${CYAN}📄 Streaming logs for aztec-sequencer (Ctrl+C to stop)...${RESET}"
  pushd "$AZTEC_DIR" >/dev/null
  if [[ "$COMPOSE_CMD" == "docker-compose" ]]; then
    $COMPOSE_CMD logs -f
  else
    $COMPOSE_CMD logs -f
  fi
  popd >/dev/null || true
  echo -e "${YELLOW}Returning to main menu...${RESET}"
  sleep 1
}

get_block_and_proof() {
  BLOCK=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080/ | jq -r '.result.proven.number')
  if [[ -z "$BLOCK" || "$BLOCK" == "null" ]]; then
    echo -e "${RED}❌ Failed to get block number${RESET}"
  else
    echo -e "${GREEN}✅ Block Number: $BLOCK${RESET}"
    echo -e "${CYAN}🔗 Sync Proof:${RESET}"
    curl -s -X POST -H 'Content-Type: application/json' -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK\",\"$BLOCK\"],\"id\":67}" http://localhost:8080/ | jq -r '.result'
  fi
  echo "Press any key to return to the main menu."
  read -n1 -s
}

main_menu() {
  detect_compose
  while true; do
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              🚀 AZTEC NETWORK • SEQUENCER NODE               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}1) 📦 Install & Start Node${RESET}"
    echo -e "${CYAN}${BOLD}2) 📊 Get Block Number & Sync Proof${RESET}"
    echo -e "${CYAN}${BOLD}3) 📄 View Logs${RESET}"
    echo -e "${CYAN}${BOLD}4) 🧹 Full Reset (wipe everything)${RESET}"
    echo -e "${CYAN}${BOLD}5) ❌ Exit${RESET}"
    read -rp "👉 Choice [1-5]: " CHOICE

    case "$CHOICE" in
      1) install_and_start_node ;;
      2) get_block_and_proof ;;
      3) view_logs ;;
      4) full_reset ;;
      5)
        echo -e "${YELLOW}👋 Goodbye!${RESET}"
        exit 0
        ;;
      *)
        echo -e "${RED}❌ Invalid choice. Please enter a number between 1 and 5.${RESET}"
        sleep 1
        ;;
    esac
  done
}

main_menu
