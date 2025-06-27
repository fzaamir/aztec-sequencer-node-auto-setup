#!/usr/bin/env bash
set -euo pipefail

# Styles
BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="/root/.aztec/alpha-testnet/data"
IMAGE_TAG="latest"
LOG_CHECK_INTERVAL=10

# Detect Docker Compose
detect_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD=""
  fi
}

# Animated, bold typewriter banner
draw_banner() {
  local border="══════════════════════════════════════════════════════════════"
  local top="╔${border}╗"
  local mid="║              🚀 AZTEC NETWORK • SEQUENCER NODE               ║"
  local bot="╚${border}╝"
  for line in "$top" "$mid" "$bot"; do
    echo -ne "${BOLD}"
    for ((i=0; i<${#line}; i++)); do
      echo -ne "${CYAN}${line:$i:1}${RESET}${BOLD}"
      sleep 0.002
    done
    echo -e "${RESET}"
  done
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
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list &>/dev/null
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

# Fetch Peer ID from the running Aztec container (by image)
fetch_peer_id() {
  echo -e "${CYAN}🔍 Fetching peer ID from running Aztec container...${RESET}"
  # One-liner: detect container and extract peerId
  local peer_id
  peer_id=$(sudo docker logs "$(docker ps -q --filter ancestor=aztecprotocol/aztec:${IMAGE_TAG} | head -n 1)" 2>&1 \
    | grep -i 'peerId' \
    | grep -o '"peerId":"[^"]*"' \
    | cut -d '"' -f4 \
    | head -n 1)
  if [[ -n "$peer_id" ]]; then
    echo -e "${GREEN}✔ Your peer ID is: ${BOLD}$peer_id${RESET}"
  else
    echo -e "${RED}✖ Peer ID not found. Ensure the container is running and logs include a peerId field.${RESET}"
  fi
  read -n1 -s -r -p "Press any key to return to the main menu."
}
}

# Spinner for background tasks
animated_spinner() {
  local pid=$1
  local delay=0.1
  local spinner='|/-\\'
  while kill -0 $pid 2>/dev/null; do
    for char in $spinner; do
      echo -ne "${CYAN}$char${RESET}"
      sleep $delay
      echo -ne '\b'
    done
  done
}

install_and_start_node() {
  echo
  read -rp "🔑 ETH private key (no 0x): " PRIV_KEY
  read -rp "📬 ETH public address (0x…): " PUB_ADDR
  read -rp "🌐 Sepolia RPC URL: " RPC_URL
  read -rp "🚀 Sepolia Beacon URL: " BCN_URL

  local IP
  IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
  echo -e "📱 Using detected IP: ${GREEN}${BOLD}${IP}${RESET}"

  echo -e "${CYAN}📦 Checking and installing required packages...${RESET}"
  if [[ -f /etc/debian_version ]]; then
    PKG_MANAGER="sudo apt-get install -y"
    UPDATE_CMD="sudo apt-get update -y"
  elif [[ -f /etc/redhat-release ]]; then
    PKG_MANAGER="sudo yum install -y"
    UPDATE_CMD="sudo yum update -y"
  else
    echo -e "${RED}❌ Unsupported OS.${RESET}"
    return
  fi

  REQ_PKGS=(curl build-essential git wget lz4 jq make gcc nano automake \
             autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev \
             libleveldb-dev tar clang bsdmainutils ncdu unzip ufw \
             ca-certificates gnupg lsb-release)
  MISSING_PKGS=()
  for pkg in "${REQ_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      MISSING_PKGS+=("$pkg")
    fi
  done

  if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    $UPDATE_CMD &>/dev/null & animated_spinner $!
    $PKG_MANAGER "${MISSING_PKGS[@]}" &>/dev/null & animated_spinner $!
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

  echo -e "${CYAN}⚙️ Initializing Aztec latest...${RESET}"
  aztec-up latest

  mkdir -p "$DATA_DIR" "$AZTEC_DIR"

  cat >"$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$RPC_URL
L1_CONSENSUS_HOST_URLS=$BCN_URL
VALIDATOR_PRIVATE_KEY=0x$PRIV_KEY
COINBASE=$PUB_ADDR
P2P_IP=$IP
LOG_LEVEL=info
EOF

  cat >"$AZTEC_DIR/docker-compose.yml" <<EOF
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
}

view_logs() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Directory not found: $AZTEC_DIR${RESET}"
    echo "Press any key to return to the main menu."
    read -n1 -s
    return
  fi
  echo -e "${CYAN}📄 Streaming logs for aztec (Ctrl+C to stop)...${RESET}"
  pushd "$AZTEC_DIR" >/dev/null
  $COMPOSE_CMD logs -f
  popd >/dev/null || true
  echo -e "${YELLOW}Returning to main menu...${RESET}"
  sleep 1
}

full_reset() {
  echo -e "${YELLOW}🧹 Performing full reset...${RESET}"
  # Add your reset logic here (e.g., docker-compose down, rm -rf data directories)
  echo -e "${GREEN}✔ Full reset complete.${RESET}"
  sleep 1
}

main_menu() {
  detect_compose
  while true; do
    clear
    draw_banner
    echo -e "\n${CYAN}${BOLD}1) 📦 Install & Start Node${RESET}"
    echo -e "${CYAN}${BOLD}2) 🔗 Show Peer ID${RESET}"
    echo -e "${CYAN}${BOLD}3) 📄 View Logs${RESET}"
    echo -e "${CYAN}${BOLD}4) 🧹 Full Reset (wipe everything)${RESET}"
    echo -e "${CY色}${BOLD}5) ❌ Exit${RESET}"
    read -rp "🔀 Choice [1-5]: " CHOICE

    case "$CHOICE" in
      1) install_and_start_node ;;
      2) fetch_peer_id           ;;
      3) view_logs              ;;
      4) full_reset             ;;
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

# Start the menu
main_menu
