#!/bin/bash

set -e

echo "🚀 Starting Aztec Validator One-Click Setup"

# 1. Update & Install System Dependencies
echo "📦 Updating and installing system packages..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop \
  nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
  libleveldb-dev ca-certificates gnupg

# 2. Install Docker
echo "🐳 Installing Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg || true
done

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl restart docker
sudo docker run hello-world || true

# 3. Install Aztec CLI
echo "🔧 Installing Aztec CLI tools..."
bash -i <(curl -s https://install.aztec.network)
exec bash

# 4. Gather Required Info
echo "🧠 Please enter the following info:"
read -p "🔑 Validator PRIVATE KEY (without 0x): " PRIVATE_KEY
read -p "🏦 Validator ADDRESS (starts with 0x): " VALIDATOR_ADDRESS
read -p "🌐 L1 RPC URL (e.g., Alchemy/Ankr): " RPC_URL
read -p "📡 BEACON URL (e.g., Ankr Beacon): " BEACON_URL
SERVER_IP=$(curl -s ipv4.icanhazip.com)
echo "🖥️ Detected server IP: $SERVER_IP"

# 5. Configure Firewall
echo "🛡️ Setting up UFW firewall..."
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw allow 40400
sudo ufw allow 8080
sudo ufw --force enable

# 6. Start Node in screen session
echo "🌀 Launching Aztec node inside 'screen'..."
screen -S aztec -dm bash -c "aztec start --node --archiver --sequencer \
  --network alpha-testnet \
  --l1-rpc-urls $RPC_URL \
  --l1-consensus-host-urls $BEACON_URL \
  --sequencer.validatorPrivateKey 0x$PRIVATE_KEY \
  --sequencer.coinbase $VALIDATOR_ADDRESS \
  --p2p.p2pIp $SERVER_IP \
  --p2p.maxTxPoolSize 1000000000"

echo "✅ Node started. Use 'screen -r aztec' to view logs."

# 7. Instructions for Next Steps
echo -e "\n🎯 Next Steps:"
echo "1. Wait a few minutes for your node to sync."
echo "2. Run this to get block number and sync proof:"
echo
echo 'BLOCK=$(curl -s -X POST -H "Content-Type: application/json" -d '\''{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}'\'' http://localhost:8080 | jq -r ".result.proven.number") && echo "Block: $BLOCK" && echo "Proof:" && curl -s -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK\",\"$BLOCK\"],\"id\":67}" http://localhost:8080 | jq -r ".result"'
echo
echo "3. Go to Discord and run: /operator start"
echo "4. Optional: Register validator on L1:"
echo
echo "aztec add-l1-validator \\"
echo "  --l1-rpc-urls $RPC_URL \\"
echo "  --private-key $PRIVATE_KEY \\"
echo "  --attester $VALIDATOR_ADDRESS \\"
echo "  --proposer-eoa $VALIDATOR_ADDRESS \\"
echo "  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \\"
echo "  --l1-chain-id 11155111"

echo -e "\n🎉 Setup complete! Happy validating on Aztec!"
