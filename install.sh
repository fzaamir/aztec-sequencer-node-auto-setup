#!/usr/bin/env bash
set -euo pipefail

BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="/root/.aztec/alpha-testnet/data"
IMAGE_TAG="latest"
COMPOSE_CMD=""

detect_compose() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD=""
  fi
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
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin &>/dev/null
  sudo systemctl enable --now docker
  echo -e "${GREEN}✔ Docker installed.${RESET}"
}

install_docker_compose() {
  detect_compose
  if [[ -n "$COMPOSE_CMD" ]]; then
    echo -e "${GREEN}✔ Docker Compose available (${COMPOSE_CMD}).${RESET}"
    return
  fi
  echo -e "${CYAN}⏳ Installing Docker Compose plugin...${RESET}"
  sudo apt-get install -y docker-compose-plugin &>/dev/null
  detect_compose
  [[ -z "$COMPOSE_CMD" ]] && { echo -e "${RED}✖ Docker Compose install failed.${RESET}"; exit 1; }
  echo -e "${GREEN}✔ Docker Compose installed (${COMPOSE_CMD}).${RESET}"
}

ensure_figlet() {
  if ! command -v figlet &>/dev/null; then
    sudo apt-get update -y &>/dev/null
    sudo apt-get install -y figlet &>/dev/null
  fi
}

print_centered() {
  local w="$1" t="$2" pad
  pad=$(( (w - ${#t}) / 2 ))
  (( pad < 0 )) && pad=0
  printf "%*s%s\n" "$pad" "" "$t"
}

draw_banner() {
  ensure_figlet
  local cols
  cols=$(tput cols 2>/dev/null || echo 100)
  echo -e "${BOLD}${CYAN}"
  figlet -f big -w "$cols" "AZTEC"
  figlet -f big -w "$cols" "NETWORK"
  echo -e "${RESET}${YELLOW}${BOLD}"
  print_centered "$cols" "🚀 Sequencer Node — Alpha Testnet"
  echo -e "${RESET}"
}

fetch_peer_id() {
  echo -e "${CYAN}🔍 Fetching Peer ID...${RESET}"
  local cid
  cid=$(docker ps -q --filter "name=aztec" --filter "ancestor=aztecprotocol/aztec:${IMAGE_TAG}" | head -n1)
  if [[ -z "${cid}" ]]; then
    echo -e "${RED}❌ No running aztec container found.${RESET}"
    read -n1 -s -r -p "Press any key..."
    return
  fi
  local peerid
  peerid=$(docker logs "${cid}" 2>&1 \
    | grep -i "peerId" \
    | grep -o '"peerId":"[^"]*"' \
    | cut -d'"' -f4 \
    | head -n 1 || true)
  if [[ -n "${peerid:-}" ]]; then
    echo -e "\n${GREEN}✔ Peer ID found:${RESET} ${YELLOW}$peerid${RESET}\n"
  else
    echo -e "${RED}❌ Peer ID not found in logs yet.${RESET}"
  fi
  read -n1 -s -r -p "Press any key..."
}

install_and_start_node() {
  echo -e "${CYAN}🔧 Validator Configuration:${RESET}"
  local MODE=""
  while [[ "$MODE" != "single" && "$MODE" != "multiple" ]]; do
    read -rp "❓ Run a single validator or multiple? [single/multiple]: " MODE
  done
  local VALIDATOR_KEYS="" COINBASE_ADDR="" RPC_URL="" BCN_URL="" PUBLISHER_PRIV="" IP
  IP=$(curl -s https://ipinfo.io/ip || echo "127.0.0.1")
  echo -e "📱 Using IP: ${GREEN}${BOLD}$IP${RESET}"
  if [[ "$MODE" == "multiple" ]]; then
    local NUM=0
    while ! [[ "$NUM" =~ ^[1-9][0-9]*$ ]]; do
      read -rp "🔢 How many validators to run? " NUM
    done
    for ((i = 1; i <= NUM; i++)); do
      local KEY=""
      while [[ -z "$KEY" ]]; do
        read -rp "🔑 Validator Private Key #$i (no 0x): " KEY
      done
      VALIDATOR_KEYS+="0x$KEY"
      [[ $i -lt $NUM ]] && VALIDATOR_KEYS+=","
    done
    while [[ -z "$PUBLISHER_PRIV" ]]; do
      read -rp "🗝️  Publisher Private Key (no 0x): " PUBLISHER_PRIV
    done
  else
    local KEY=""
    while [[ -z "$KEY" ]]; do
      read -rp "🔑 Validator Private Key (no 0x): " KEY
    done
    VALIDATOR_KEYS="0x$KEY"
  fi
  while [[ -z "$COINBASE_ADDR" ]]; do
    read -rp "📬 Wallet (coinbase) address (0x...): " COINBASE_ADDR
  done
  while [[ -z "$RPC_URL" ]]; do
    read -rp "🌐 Sepolia RPC URL: " RPC_URL
  done
  while [[ -z "$BCN_URL" ]]; do
    read -rp "🚀 Sepolia Beacon URL: " BCN_URL
  done
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y curl git jq nano ufw ca-certificates gnupg lsb-release &>/dev/null
  install_docker
  install_docker_compose
  sudo ufw allow 22/tcp >/dev/null
  sudo ufw allow 40400/tcp >/dev/null
  sudo ufw allow 40400/udp >/dev/null
  sudo ufw allow 8080/tcp >/dev/null
  sudo ufw --force enable >/dev/null
  curl -s https://install.aztec.network | bash
  if ! grep -q 'export PATH="$HOME/.aztec/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  fi
  export PATH="$HOME/.aztec/bin:$PATH"
  aztec-up latest
  sudo mkdir -p "$DATA_DIR"
  mkdir -p "$AZTEC_DIR"
  {
    echo "ETHEREUM_HOSTS=$RPC_URL"
    echo "L1_CONSENSUS_HOST_URLS=$BCN_URL"
    echo "VALIDATOR_PRIVATE_KEYS=$VALIDATOR_KEYS"
    [[ "$MODE" == "multiple" ]] && echo "PUBLISHER_PRIVATE_KEY=0x$PUBLISHER_PRIV"
    echo "COINBASE=$COINBASE_ADDR"
    echo "P2P_IP=$IP"
    echo "LOG_LEVEL=info"
  } > "$AZTEC_DIR/.env"
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
      VALIDATOR_PRIVATE_KEYS: \${VALIDATOR_PRIVATE_KEYS}
      COINBASE: \${COINBASE}
      P2P_IP: \${P2P_IP}
      LOG_LEVEL: \${LOG_LEVEL}
      \${PUBLISHER_PRIVATE_KEY:+PUBLISHER_PRIVATE_KEY=\${PUBLISHER_PRIVATE_KEY}}
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js
        start --network alpha-testnet --node --archiver --sequencer'
    ports:
      - 40400:40400/tcp
      - 40400:40400/udp
      - 8080:8080
    volumes:
      - /root/.aztec/alpha-testnet/data/:/data
EOF
  pushd "$AZTEC_DIR" >/dev/null
  $COMPOSE_CMD up -d
  popd >/dev/null
  echo -e "\n${GREEN}${BOLD}🎉 Aztec node successfully started.${RESET}"
  read -n1 -s -r -p "Press any key..."
}

update_node() {
  detect_compose
  if [[ -z "$COMPOSE_CMD" ]]; then
    echo -e "${RED}❌ Docker Compose is not installed.${RESET}"
    read -n1 -s -r -p "Press any key..."
    return
  fi
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Install directory not found.${RESET}"
    read -n1 -s -r -p "Press any key..."
    return
  fi
  pushd "$AZTEC_DIR" >/dev/null
  $COMPOSE_CMD down --remove-orphans || true
  $COMPOSE_CMD pull
  docker image prune -f >/dev/null || true
  aztec-up latest
  $COMPOSE_CMD up -d
  popd >/dev/null
  echo -e "${GREEN}✔ Update complete.${RESET}"
  read -n1 -s -r -p "Press any key..."
}

view_logs() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Install directory missing.${RESET}"
    read -n1 -s -r -p "Press any key..."
    return
  fi
  detect_compose
  $COMPOSE_CMD logs -f
}

full_reset() {
  if [[ -d "$AZTEC_DIR" ]]; then
    pushd "$AZTEC_DIR" >/dev/null
    detect_compose
    if [[ -n "$COMPOSE_CMD" ]]; then
      $COMPOSE_CMD down --volumes --remove-orphans || true
    fi
    popd >/dev/null
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
    echo -e "\n${CYAN}${BOLD}1) Install and Launch Node${RESET}"
    echo -e "${CYAN}${BOLD}2) Get Peer ID${RESET}"
    echo -e "${CYAN}${BOLD}3) View Node Logs${RESET}"
    echo -e "${CYAN}${BOLD}4) Update to Latest${RESET}"
    echo -e "${CYAN}${BOLD}5) Full Reset${RESET}"
    echo -e "${CYAN}${BOLD}6) Exit${RESET}\n"
    read -rp "Choice [1-6]: " CHOICE
    case "$CHOICE" in
      1) install_and_start_node ;;
      2) fetch_peer_id ;;
      3) view_logs ;;
      4) update_node ;;
      5) full_reset ;;
      6) exit 0 ;;
      *) echo -e "${RED}❌ Invalid choice.${RESET}"; sleep 1 ;;
    esac
  done
}

detect_compose
main_menu
