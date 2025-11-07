#!/usr/bin/env bash
set -euo pipefail

BOLD=$(tput bold) RESET=$(tput sgr0)
GREEN="\033[1;32m" CYAN="\033[1;36m" YELLOW="\033[1;33m" RED="\033[1;31m"

AZTEC_VERSION="2.1.2"
IMAGE_TAG="2.1.2"
ROLLUP_ADDR="0xebd99ff0ff6677205509ae73f93d0ca52ac85d67"
STAKE_TOKEN="0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A"

AZTEC_DIR="$HOME/aztec-sequencer"
KEYS_DIR="$AZTEC_DIR/keys"
DATA_DIR="${DATA_DIR:-$HOME/.aztec/testnet/data}"
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

draw_banner() {
  local border="══════════════════════════════════════════════════════════════"
  echo -e "${BOLD}${CYAN}╔${border}╗${RESET}"
  echo -e "${BOLD}${CYAN}║      🚀 AZTEC SEQUENCER INSTALLER — v${AZTEC_VERSION}         ║${RESET}"
  echo -e "${BOLD}${CYAN}╚${border}╝${RESET}"
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null || false
}

install_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${GREEN}✔ Docker already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}Installing Docker...${RESET}"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker || true
  sudo usermod -aG docker "$USER" || true
  echo -e "${GREEN}✔ Docker installed.${RESET}"
}

install_foundry() {
  if command -v cast &>/dev/null; then
    echo -e "${GREEN}✔ Foundry (cast) already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}Installing Foundry (foundryup)...${RESET}"
  curl -L https://foundry.paradigm.xyz | bash
  # shellcheck disable=SC1090
  source "$HOME/.foundry/bin/foundryup" || true
  foundryup || true
  echo -e "${GREEN}✔ Foundry installed (cast available).${RESET}"
}

install_aztec_cli() {
  if command -v aztec &>/dev/null; then
    echo -e "${GREEN}✔ Aztec CLI already installed.${RESET}"
  else
    echo -e "${CYAN}Installing Aztec CLI...${RESET}"
    curl -s https://install.aztec.network | bash
    echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.aztec/bin:$PATH"
  fi
  echo -e "${CYAN}Ensuring Aztec CLI version ${AZTEC_VERSION}...${RESET}"
  aztec-up "${AZTEC_VERSION}" || true
  echo -e "${GREEN}✔ Aztec CLI ready.${RESET}"
}

configure_ufw() {
  if is_wsl; then
    echo -e "${YELLOW}⚠ Detected WSL - skipping UFW configuration.${RESET}"
    return
  fi
  echo -e "${CYAN}Configuring UFW (22, 40400 TCP/UDP, 8080)...${RESET}"
  sudo ufw allow 22/tcp
  sudo ufw allow 40400/tcp
  sudo ufw allow 40400/udp
  sudo ufw allow 8080/tcp
  sudo ufw --force enable || true
  echo -e "${GREEN}✔ UFW rules applied.${RESET}"
}

generate_keystore() {
  mkdir -p "$KEYS_DIR"
  echo -e "${CYAN}Generating sequencer keystore (Aztec CLI)...${RESET}"
  # Allow override via env for non-interactive usage
  FEE_RECIPIENT="${FEE_RECIPIENT:-0x0000000000000000000000000000000000000000000000000000000000000000}"
  MNEMONIC_OPTION=""
  if [[ -n "${MNEMONIC:-}" ]]; then
    MNEMONIC_OPTION="--mnemonic \"$MNEMONIC\""
  fi
  PUBLISHER_COUNT_OPTION=""
  if [[ -n "${PUBLISHER_COUNT:-}" ]]; then
    PUBLISHER_COUNT_OPTION="--publisher-count ${PUBLISHER_COUNT}"
  fi
  DATA_DIR_OPT="--data-dir \"$KEYS_DIR\" --file sequencer.json"

  # Use eval because MNEMONIC_OPTION may contain spaces/quotes
  eval aztec validator-keys new --fee-recipient "$FEE_RECIPIENT" $MNEMONIC_OPTION $PUBLISHER_COUNT_OPTION $DATA_DIR_OPT
  KEYFILE="$KEYS_DIR/sequencer.json"
  if [[ ! -f "$KEYFILE" ]]; then
    echo -e "${RED}✖ Keystore not found at ${KEYFILE}. Aborting.${RESET}" >&2
    exit 1
  fi
  chmod 600 "$KEYFILE"
  echo -e "${GREEN}✔ Keystore created: ${KEYFILE}${RESET}"
  jq . "$KEYFILE" >/dev/null 2>&1 || { echo -e "${RED}✖ Keystore invalid JSON.${RESET}"; exit 1; }
}

parse_keystore() {
  KEYFILE="$KEYS_DIR/sequencer.json"
  ATTESTER_ETH=$(jq -r '.validators[0].attester.eth' "$KEYFILE")
  BLS_SECRET=$(jq -r '.validators[0].attester.bls' "$KEYFILE")
  COINBASE=$(jq -r '.validators[0].coinbase' "$KEYFILE")
  FEE_RECIPIENT_OUT=$(jq -r '.validators[0].feeRecipient' "$KEYFILE")
  echo -e "${GREEN}Keystore parsed:${RESET}"
  echo -e "  Attester (eth): ${YELLOW}${ATTESTER_ETH}${RESET}"
  echo -e "  Coinbase:       ${YELLOW}${COINBASE}${RESET}"
  echo -e "  Fee recipient:  ${YELLOW}${FEE_RECIPIENT_OUT}${RESET}"
}

approve_stake() {
  if ! command -v cast &>/dev/null; then
    echo -e "${YELLOW}cast not found. Installing Foundry...${RESET}"
    install_foundry
  fi
  echo -e "${CYAN}Approving 200k STAKE for rollup contract (${ROLLUP_ADDR})...${RESET}"
  if [[ -z "${ETH_PRIV:-}" ]]; then
    read -rp "Enter your Ethereum private key for approval (no 0x): " ETH_PRIV
  fi
  if [[ -z "${ETH_RPC:-}" ]]; then
    read -rp "Enter your Ethereum RPC URL (e.g. https://sepolia.infura.io/v3/KEY): " ETH_RPC
  fi
  set +e
  cast send "$STAKE_TOKEN" "approve(address,uint256)" "$ROLLUP_ADDR" 200000ether --private-key "0x${ETH_PRIV}" --rpc-url "${ETH_RPC}"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo -e "${YELLOW}⚠ Approval may have failed or returned non-zero. Inspect and retry if necessary.${RESET}"
  else
    echo -e "${GREEN}✔ Approval transaction submitted.${RESET}"
  fi
}

register_validator() {
  echo -e "${CYAN}Registering L1 validator via Aztec CLI...${RESET}"
  if [[ -z "${ETH_PRIV:-}" ]]; then
    read -rp "Enter your Ethereum private key for registration (no 0x): " ETH_PRIV
  fi
  if [[ -z "${ETH_RPC:-}" ]]; then
    read -rp "Enter your Ethereum RPC URL: " ETH_RPC
  fi

  ATTESTER_ADDR="${ATTESTER_ETH:-}"
  if [[ -z "$ATTESTER_ADDR" ]]; then
    parse_keystore
    ATTESTER_ADDR="$ATTESTER_ETH"
  fi
  WITHDRAWER_ADDR="${WITHDRAWER:-$ATTESTER_ADDR}"

  aztec add-l1-validator \
    --l1-rpc-urls "$ETH_RPC" \
    --network testnet \
    --private-key "0x${ETH_PRIV}" \
    --attester "$ATTESTER_ADDR" \
    --withdrawer "$WITHDRAWER_ADDR" \
    --bls-secret-key "$BLS_SECRET" \
    --rollup "$ROLLUP_ADDR"

  echo -e "${GREEN}✔ aztec add-l1-validator executed (inspect output above).${RESET}"
}

generate_docker_compose() {
  mkdir -p "$AZTEC_DIR"
  cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-node:
    container_name: aztec
    image: aztecprotocol/aztec:${IMAGE_TAG}
    restart: unless-stopped
    environment:
      DATA_DIRECTORY: /data
      LOG_LEVEL: info
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js \
        start --network testnet --node --archiver --sequencer'
    ports:
      - 40400:40400/tcp
      - 40400:40400/udp
      - 8080:8080
    volumes:
      - ${DATA_DIR}:/data
    healthcheck:
      test: ["CMD","curl","-fsS","http://127.0.0.1:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 10
EOF
  echo -e "${GREEN}✔ docker-compose.yml written to ${AZTEC_DIR}/docker-compose.yml${RESET}"
}

start_node() {
  detect_compose
  if [[ -z "$COMPOSE_CMD" ]]; then
    if command -v docker-compose &>/dev/null; then
      COMPOSE_CMD="docker-compose"
    elif docker compose version &>/dev/null; then
      COMPOSE_CMD="docker compose"
    else
      echo -e "${RED}✖ Docker Compose not found. Install docker compose or run the node manually.${RESET}"
      return 1
    fi
  fi
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD up -d
  popd &>/dev/null
  echo -e "${GREEN}✔ Aztec node started (container name: aztec).${RESET}"
}

fetch_peer_id() {
  cid=$(docker ps -q --filter "ancestor=aztecprotocol/aztec:${IMAGE_TAG}" | head -n1)
  if [[ -z "$cid" ]]; then
    echo -e "${YELLOW}No running aztec container found for image ${IMAGE_TAG}.${RESET}"
    return 1
  fi
  peerid=$(docker logs "$cid" 2>&1 | grep -i '"peerId"' | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4 | head -n 1 || true)
  if [[ -n "$peerid" ]]; then
    echo -e "${GREEN}Peer ID: ${YELLOW}${peerid}${RESET}"
  else
    echo -e "${YELLOW}Peer ID not found in logs yet. Check container logs.${RESET}"
  fi
}

view_logs() {
  detect_compose
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD logs -f --since=1h
  popd &>/dev/null
}

full_reset() {
  detect_compose
  if [[ -d "$AZTEC_DIR" ]]; then
    pushd "$AZTEC_DIR" &>/dev/null
    $COMPOSE_CMD down --volumes --remove-orphans || true
    popd &>/dev/null
  fi
  echo -e "${YELLOW}Removing data directory: ${DATA_DIR} and keys dir: ${KEYS_DIR}${RESET}"
  sudo rm -rf "$DATA_DIR" "$KEYS_DIR" "$AZTEC_DIR"
  echo -e "${GREEN}✔ Reset complete.${RESET}"
}

update_image() {
  detect_compose
  pushd "$AZTEC_DIR" &>/dev/null
  $COMPOSE_CMD pull
  $COMPOSE_CMD up -d
  popd &>/dev/null
  echo -e "${GREEN}✔ Image updated and node restarted.${RESET}"
}

print_summary() {
  echo -e "\n${BOLD}SUMMARY${RESET}"
  echo -e "Keystore: ${YELLOW}${KEYS_DIR}/sequencer.json${RESET}"
  echo -e "Data dir: ${YELLOW}${DATA_DIR}${RESET}"
  echo -e "Rollup:   ${YELLOW}${ROLLUP_ADDR}${RESET}"
  echo -e "To view logs: ${YELLOW}sudo ${COMPOSE_CMD} logs -f --since=1h${RESET}"
}

main_interactive() {
  draw_banner
  install_docker
  detect_compose
  install_aztec_cli
  configure_ufw
  generate_keystore
  parse_keystore
  echo -e "${CYAN}Now we will approve stake and register the validator. You will be prompted for ETH private key + RPC.${RESET}"
  approve_stake
  register_validator
  generate_docker_compose
  start_node
  print_summary
}

main_noninteractive() {
  # Expects environment variables:
  # ETH_PRIV, ETH_RPC, FEE_RECIPIENT (optional), MNEMONIC (optional), PUBLISHER_COUNT (optional), WITHDRAWER(optional)
  if [[ -z "${ETH_PRIV:-}" || -z "${ETH_RPC:-}" ]]; then
    echo -e "${RED}ETH_PRIV and ETH_RPC must be set for non-interactive mode.${RESET}"
    exit 1
  fi
  draw_banner
  install_docker
  detect_compose
  install_aztec_cli
  configure_ufw
  generate_keystore
  parse_keystore
  approve_stake
  # set WITHDRAWER if provided:
  if [[ -n "${WITHDRAWER:-}" ]]; then
    export WITHDRAWER
  fi
  register_validator
  generate_docker_compose
  start_node
  print_summary
}

main_menu() {
  while true; do
    clear
    draw_banner
    echo -e "\n${CYAN}1) Install & Launch (interactive)${RESET}"
    echo -e "${CYAN}2) Install & Launch (non-interactive via ENV)${RESET}"
    echo -e "${CYAN}3) Get Peer ID${RESET}"
    echo -e "${CYAN}4) View Logs${RESET}"
    echo -e "${CYAN}5) Full Reset (wipe)${RESET}"
    echo -e "${CYAN}6) Update Image & Restart${RESET}"
    echo -e "${CYAN}7) Exit${RESET}"
    read -rp "Choice [1-7]: " CH
    case "$CH" in
      1) main_interactive; read -n1 -s -r -p "Press any key to continue..." ;;
      2) main_noninteractive; read -n1 -s -r -p "Press any key to continue..." ;;
      3) fetch_peer_id; read -n1 -s -r -p "Press any key to continue..." ;;
      4) view_logs ;;
      5) read -rp "Are you sure? This will delete data and keys (y/N): " CONF; [[ "${CONF,,}" == "y" ]] && full_reset; read -n1 -s -r -p "Press any key to continue..." ;;
      6) update_image; read -n1 -s -r -p "Press any key to continue..." ;;
      7) echo -e "${YELLOW}Goodbye!${RESET}"; exit 0 ;;
      *) echo -e "${RED}Invalid choice${RESET}"; sleep 1 ;;
    esac
  done
}

# ENTRYPOINT
if [[ "${1:-}" == "--noninteractive" ]]; then
  main_noninteractive
else
  detect_compose
  main_menu
fi
