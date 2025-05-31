# ⚡️ Aztec Sequencer Node Installer

Fully automated deployment & management of an **Aztec Sequencer Node** on **Ubuntu 20.04/22.04**.

---

## ✨ Features

* 🔧 Auto-installs Docker, Compose & required dependencies
* 🔐 Configures UFW firewall securely
* 🌐 Detects and applies your public IP automatically
* 🧠 Prompts for ETH key, public address, RPC & Beacon URLs
* 🐳 Runs node in Docker Compose with auto-restart
* 📊 Fetches L2 block number & sync proof
* 🧹 Full reset option to wipe and reinitialize
* 🖥️ Real-time log viewer
* 📋 Interactive menu for full control

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
bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-sequencer-auto-setup/main/install.sh)
```

---

## 🧪 Interactive Menu Options

```
1️⃣  Install & Start Node
2️⃣  Get Latest Block + Sync Proof
3️⃣  View Real-Time Logs
4️⃣  Full Reset (wipe everything)
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

```bash
curl -s -X POST -H 'Content-Type: application/json' \
-d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' \
http://localhost:8080/ | jq -r '.result.proven.number'
```

```bash
curl -s -X POST -H 'Content-Type: application/json' \
-d '{"jsonrpc":"2.0","method":"node_getArchiveSiblingPath","params":["BLOCK_NUM","BLOCK_NUM"],"id":1}' \
http://localhost:8080/ | jq -r '.result'
```

---

## 💬 Support

* 💬 [Aztec Discord](https://discord.gg/aztecprotocol) → `#operators`
* 🛠️ [GitHub Issues](https://github.com/fzaamir/aztec-sequencer-auto-setup)

---

### 🛡️ Built for Operators

Minimal. Secure. Resilient.
Plug it in. Let it run. 🟢
