#!/usr/bin/env bash
set -euo pipefail

# === COLORS & STYLES ===
BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" BLUE="\033[1;34m"
YELLOW="\033[1;33m" CYAN="\033[1;36m" RED="\033[1;31m"

# === CONFIG ===
AZTEC_DIR="$HOME/aztec-sequencer"
DATA_DIR="/root/.aztec/testnet/data"
IMAGE_TAG="2.1.2"
ROLLUP_CONTRACT="0xebd99ff0ff6677205509ae73f93d0ca52ac85d67"
STAKE_TOKEN="0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A"

COMPOSE_CMD=""

# === FUNCTIONS ===

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
  echo -e "${BOLD}${CYAN}║        🚀 AZTEC NETWORK • SEQUENCER NODE — Image ${IMAGE_TAG}        ║${RESET}"
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
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list &>/dev/null
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin &>/dev/null
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER" || true
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

full_reset() {
  echo -e "${YELLOW}🧹 Performing full reset...${RESET}"
  if [[ -d "$AZTEC_DIR" ]]; then
    pushd "$AZTEC_DIR" &>/dev/null
    $COMPOSE_CMD down --volumes --remove-orphans || true
    popd &>/dev/null
  fi
  sudo rm -rf "$DATA_DIR" "$AZTEC_DIR"
  echo -e "${GREEN}✔ Reset complete.${RESET}"
  sleep 1
}

fetch_peer_id() {
  echo -e "${CYAN}🔍 Fetching Peer ID...${RESET}"
  local cid
  cid=$(sudo docker ps -q --filter "ancestor=aztecprotocol/aztec:${IMAGE_TAG}" | head -n 1)
  if [[ -z "$cid" ]]; then
    echo -e "${RED}❌ No running aztec container found.${RESET}"
    read -n1 -s -r -p "Press any key to return..."
    return
  fi
  peerid=$(sudo docker logs "$cid" 2>&1 | grep -i '"peerId"' | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4 | head -n 1)
  if [[ -n "${peerid:-}" ]]; then
    echo -e "\n${GREEN}✔ Peer ID:${RESET} ${YELLOW}$peerid${RESET}\n"
  else
    echo -e "${RED}❌ Peer ID not found.${RESET}"
  fi
  read -n1 -s -r -p "Press any key to return..."
}

install_and_start_node() {
  echo -e "${CYAN}🔧 Validator Configuration:${RESET}"

  read -rp "🔑 Validator Private Key (no 0x): " KEY
  read -rp "📬 Attester Wallet Address (0x...): " ATTESTER
  read -rp "💸 Withdrawer Wallet Address (0x...): " WITHDRAWER
  read -rp "🔐 BLS Secret Key (no 0x): " BLSKEY
  read -rp "🌐 Sepolia RPC URL: " RPC_URL
  read -rp "🚀 Sepolia Beacon URL: " BCN_URL

  IP=$(curl -4s https://ifconfig.co || echo "127.0.0.1")
  echo -e "📱 Using IP: ${GREEN}${BOLD}$IP${RESET}"

  echo -e "${CYAN}📦 Installing dependencies...${RESET}"
  sudo apt-get update -y &>/dev/null
  sudo apt-get install -y curl git jq nano ufw ca-certificates gnupg lsb-release &>/dev/null

  install_docker
  install_docker_compose

  echo -e "${CYAN}🔐 Configuring UFW (22, 40400/tcp+udp, 8080)...${RESET}"
  sudo ufw allow 22/tcp
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  read -rp "Enable UFW now? [y/N]: " ENABLE_UFW
  if [[ "${ENABLE_UFW,,}" == "y" ]]; then
    sudo ufw --force enable &>/dev/null
    echo -e "${GREEN}✔ UFW enabled.${RESET}"
  fi

  echo -e "${CYAN}📥 Installing Aztec CLI...${RESET}"
  curl -s https://install.aztec.network | bash
  echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.aztec/bin:$PATH"
  aztec-up 2.1.2

  echo -e "${CYAN}🪙 Approving 200k STAKE for rollup...${RESET}"
  cast send $STAKE_TOKEN \
    "approve(address,uint256)" \
    $ROLLUP_CONTRACT 200000ether \
    --private-key "0x$KEY" \
    --rpc-url "$RPC_URL" || true
  echo -e "${GREEN}✔ STAKE approved.${RESET}"

  echo -e "${CYAN}🪩 Registering L1 Validator...${RESET}"
  aztec add-l1-validator \
    --l1-rpc-urls "$RPC_URL" \
    --network testnet \
    --private-key "0x$KEY" \
    --attester "$ATTESTER" \
    --withdrawer "$WITHDRAWER" \
    --bls-secret-key "0x$BLSKEY" \
    --rollup $ROLLUP_CONTRACT
  echo -e "${GREEN}✔ Validator registered.${RESET}"

  sudo mkdir -p "$DATA_DIR"
  sudo chown -R "$USER":"$USER" /root/.aztec || true
  mkdir -p "$AZTEC_DIR"

  echo -e "${CYAN}📝 Generating .env file...${RESET}"
  {
    echo "ETHEREUM_HOSTS=\"$RPC_URL\""
    echo "L1_CONSENSUS_HOST_URLS=\"$BCN_URL\""
    echo "VALIDATOR_PRIVATE_KEYS=\"0x$KEY\""
    echo "COINBASE=\"$ATTESTER\""
    echo "P2P_IP=\"$IP\""
    echo "LOG_LEVEL=info"
  } > "$AZTEC_DIR/.env"

  echo -e "${CYAN}⚙️ Generating docker-compose.yml...${RESET}"
  cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-node:
    container_name: aztec
    image: aztecprotocol/aztec:${IMAGE_TAG}
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEYS: \${VALIDATOR_PRIVATE_KEYS}
      COINBASE: \${COINBASE}
      P2P_IP: \${P2P_IP}
      LOG_LEVEL: info
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js \
        start --network testnet --node --archiver --sequencer'
    ports:
      - 40400:40400/tcp
      - 40400:40400/udp
      - 8080:8080
    volumes:
      - /root/.aztec/testnet/data/:/data
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 10
EOF

  echo -e "${CYAN}🚀 Starting Aztec node...${RESET}"
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD up -d
  popd &>/dev/null

  echo -e "\n${GREEN}${BOLD}🎉 Aztec node successfully installed and registered on v${IMAGE_TAG}!${RESET}"
  read -n1 -s -r -p "👉 Press any key to return to the menu..."
}

view_logs() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Install directory missing.${RESET}"
    read -n1 -s
    return
  fi
  echo -e "${CYAN}📄 Streaming logs (last 1h)...${RESET}"
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD logs -f --since=1h
  popd &>/dev/null
}

update_image() {
  if [[ ! -d "$AZTEC_DIR" ]]; then
    echo -e "${RED}❌ Install directory missing.${RESET}"
    read -n1 -s
    return
  fi
  echo -e "${CYAN}🔄 Pulling latest image ${IMAGE_TAG}...${RESET}"
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD pull
  $COMPOSE_CMD up -d
  popd &>/dev/null
  echo -e "${GREEN}✔ Node updated and restarted.${RESET}"
  read -n1 -s -r -p "Press any key to return..."
}

main_menu() {
  detect_compose
  while true; do
    clear
    draw_banner
    echo -e "\n${CYAN}${BOLD}1) 🚀 Install, Register & Launch Node${RESET}"
    echo -e "${CYAN}${BOLD}2) 🔗 Get Peer ID${RESET}"
    echo -e "${CYAN}${BOLD}3) 📄 View Logs${RESET}"
    echo -e "${CYAN}${BOLD}4) 🧹 Full Reset${RESET}"
    echo -e "${CYAN}${BOLD}5) 🔄 Update Node Image${RESET}"
    echo -e "${CYAN}${BOLD}6) ❌ Exit${RESET}"
    read -rp "🔀 Choice [1-6]: " CHOICE
    case "$CHOICE" in
      1) install_and_start_node ;;
      2) fetch_peer_id ;;
      3) view_logs ;;
      4) full_reset ;;
      5) update_image ;;
      6) echo -e "${YELLOW}👋 Goodbye!${RESET}"; exit 0 ;;
      *) echo -e "${RED}❌ Invalid choice.${RESET}"; sleep 1 ;;
    esac
  done
}

detect_compose
main_menu
