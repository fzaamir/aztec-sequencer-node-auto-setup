#!/usr/bin/env bash
set -euo pipefail

# Styles
BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="/root/.aztec/alpha-testnet/data"
IMAGE_TAG="latest"

detect_compose() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD=""
  fi
}

draw_banner() {
  local border="══════════════════════════════════════════════════════════════"
  echo -e "${BOLD}${CYAN}╔${border}╗${RESET}"
  echo -e "${BOLD}${CYAN}║              🚀 AZTEC NETWORK • SEQUENCER NODE               ║${RESET}"
  echo -e "${BOLD}${CYAN}╚${border}╝${RESET}"
}

install_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${GREEN}✔ Docker is already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}⏳ Installing Docker...${RESET}"
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release &>/dev/null
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list &>/dev/null
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin &>/dev/null
  sudo systemctl enable --now docker
  echo -e "${GREEN}✔ Docker installed.${RESET}"
}

install_docker_compose() {
  detect_compose
  if [[ -n "$COMPOSE_CMD" ]]; then
    echo -e "${GREEN}✔ Docker Compose already available (${COMPOSE_CMD}).${RESET}"
    return
  fi
  echo -e "${CYAN}⏳ Installing Docker Compose plugin...${RESET}"
  sudo apt-get install -y docker-compose-plugin &>/dev/null
  detect_compose
  [[ -z "$COMPOSE_CMD" ]] && { echo -e "${RED}✖ Docker Compose install failed.${RESET}"; exit 1; }
  echo -e "${GREEN}✔ Docker Compose installed (${COMPOSE_CMD}).${RESET}"
}

fetch_peer_id() {
  echo -e "${CYAN}🔍 Fetching Peer ID...${RESET}"

  peerid=$(sudo docker logs $(docker ps -q --filter ancestor=aztecprotocol/aztec:latest | head -n 1) 2>&1 \
    | grep -i "peerId" \
    | grep -o '"peerId":"[^"]*"' \
    | cut -d'"' -f4 \
    | head -n 1)

  if [[ -n "$peerid" ]]; then
    echo -e "\n${GREEN}✔ Peer ID found:${RESET} ${YELLOW}$peerid${RESET}\n"
  else
    echo -e "${RED}❌ Peer ID not found in logs.${RESET}"
  fi

  read -n1 -s -r -p "Press any key to return to the menu..."
}


animated_spinner() {
  local pid=$1 delay=0.1 spinner='|/-\\'
  while kill -0 "$pid" 2>/dev/null; do
    for char in $spinner; do echo -ne "${CYAN}$char${RESET}"; sleep $delay; echo -ne '\b'; done
  done
}

install_and_start_node() {
  read -rp "🔑 ETH private key (no 0x): " PRIV_KEY
  read -rp "📬 ETH public address (0x…): " PUB_ADDR
  read -rp "🌐 Sepolia RPC URL: " RPC_URL
  read -rp "🚀 Sepolia Beacon URL: " BCN_URL

  local IP
  IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
  echo -e "📱 Using IP: ${GREEN}${BOLD}$IP${RESET}"

  echo -e "${CYAN}📦 Installing dependencies...${RESET}"
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y curl git jq nano ufw ca-certificates gnupg lsb-release &>/dev/null

  install_docker
  install_docker_compose

  echo -e "${CYAN}🔐 Configuring UFW...${RESET}"
  sudo ufw allow 22/tcp
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  sudo ufw --force enable &>/dev/null


  echo -e "${CYAN}📥 Installing Aztec CLI...${RESET}"
  curl -s https://install.aztec.network | bash
  echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.aztec/bin:$PATH"
  aztec-up latest
  
  sudo mkdir -p "$DATA_DIR"
  mkdir -p "$AZTEC_DIR"


  cat > "$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$RPC_URL
L1_CONSENSUS_HOST_URLS=$BCN_URL
VALIDATOR_PRIVATE_KEY=0x$PRIV_KEY
COINBASE=$PUB_ADDR
P2P_IP=$IP
LOG_LEVEL=info
EOF

  cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-node:
    container_name: aztec
    network_mode: host
    image: aztecprotocol/aztec:${IMAGE_TAG}
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: \${VALIDATOR_PRIVATE_KEY}
      COINBASE: \${COINBASE}
      P2P_IP: \${P2P_IP}
      LOG_LEVEL: info
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js \
        start --network alpha-testnet --node --archiver --sequencer'
    ports:
      - 40400:40400/tcp
      - 40400:40400/udp
      - 8080:8080
    volumes:
      - /root/.aztec/alpha-testnet/data/:/data
EOF

  echo -e "${CYAN}🚀 Starting Aztec node...${RESET}"
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD up -d
  popd &>/dev/null
  echo -e "${GREEN}✔ Node started.${RESET}"
  sleep 2
}

view_logs() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Install directory missing.${RESET}"
    read -n1 -s
    return
  fi
  echo -e "${CYAN}📄 Streaming logs...${RESET}"
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD logs -f
  popd &>/dev/null
}

full_reset() {
  echo -e "${YELLOW}🧹 Full reset...${RESET}"
  if [[ -d "$AZTEC_DIR" ]]; then
    pushd "$AZTEC_DIR" &>/dev/null
    $COMPOSE_CMD down --volumes --remove-orphans
    popd &>/dev/null
  fi
  sudo rm -rf "$DATA_DIR" "$AZTEC_DIR"
  echo -e "${GREEN}✔ Reset complete.${RESET}"
  sleep 1
}

main_menu() {
  detect_compose
  while true; do
    clear
    draw_banner
    echo -e "\n${CYAN}${BOLD}1) 📦  Install and Launch Node${RESET}"
    echo -e "${CYAN}${BOLD}2) 🔗  Get Peer ID${RESET}"
    echo -e "${CYAN}${BOLD}3) 📄  View Node Logs${RESET}"
    echo -e "${CYAN}${BOLD}4) 🧹  Perform Full Reset${RESET}"
    echo -e "${CYAN}${BOLD}5) ❌  Exit${RESET}"

    read -rp "🔀 Choice [1-5]: " CHOICE
    case "$CHOICE" in
      1) install_and_start_node ;;
      2) fetch_peer_id ;;
      3) view_logs ;;
      4) full_reset ;;
      5) echo -e "${YELLOW}👋 Goodbye!${RESET}"; exit 0 ;;
      *) echo -e "${RED}❌ Invalid choice.${RESET}"; sleep 1 ;;
    esac
  done
}

detect_compose
main_menu
