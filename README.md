# ⚡️ Aztec Sequencer Node Installer

Fully automated deployment & management of an **Aztec Sequencer Node** on **Ubuntu 20.04/22.04**.

---


## ✨ Features

* 🔧 Automatically installs Docker, Docker Compose, and all required dependencies
* 🔐 Sets up a secure UFW firewall configuration
* 🌐 Automatically detects and applies your public IP address
* 🧠 Prompts for Ethereum private key, public address, RPC, and Beacon URLs
* 🐳 Runs the node using Docker Compose with auto-restart enabled
* 🔗 Displays your node's Peer ID
* 🧹 Includes a full reset option to wipe and reinitialize the environment
* 🖥️ Provides a real-time log viewer for live monitoring
* 📋 Offers an interactive menu for complete control


---

## 📦 Requirements

| Resource     | Minimum                                         |
| ------------ | ----------------------------------------------- |
| OS           | Ubuntu 20.04+                                   |
| CPU          | 8 cores                                         |
| RAM          | 16 GB                                           |
| Disk         | 100 GB SSD                                      |
| Network Keys | Ethereum privkey (no `0x`), RPC URL, Beacon URL |

---

## 🚀 Quick Install

Paste into terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-sequencer-node-auto-setup/main/install.sh)
```

---

## 🧪 Interactive Menu Options

```
1️⃣  Install and Launch Node
2️⃣  Get Peer ID
3️⃣  View Real-Time Logs
4️⃣  Perform Full Reset
5️⃣  Exit

```

---

## 🔧 Manual Commands

Start node:

```bash
cd ~/aztec-sequencer && docker compose up -d
```

Stop node:

```bash
cd ~/aztec-sequencer && docker compose down
```

View logs:

```bash
cd ~/aztec-sequencer && docker compose logs -f
```

Reset everything:

```bash
docker compose down -v
rm -rf ~/aztec-sequencer ~/.aztec/alpha-testnet
```

---

## 📊 Get Block Number & Sync Proof

``` #!/bin/bash

BLOCK=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
  http://localhost:8080/ | jq -r '.result.proven.number')

if [[ -z "$BLOCK" || "$BLOCK" == "null" ]]; then
  echo "❌ Failed to get block number"
else
  echo "✅ Block Number: $BLOCK"
  echo "🔗 Sync Proof:"
  curl -s -X POST -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK\",\"$BLOCK\"],\"id\":67}" \
    http://localhost:8080/ | jq -r '.result'
fi 
```

---

## 💬 Support

* 💬 [Aztec Discord](https://discord.gg/aztecprotocol) → `#operators`
* 🛠️ [GitHub Issues](https://github.com/fzaamir/aztec-validator-auto-setup)

---

### 🛡️ Built for Operators

Minimal. Secure. Resilient.
Plug it in. Let it run. 🟢
