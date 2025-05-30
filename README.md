# 🚀 AZTEC-NETWORK • FULLY AUTOMATED SEQUENCER NODE

Deploy and manage an **Aztec Sequencer Node** on **Ubuntu 20.04/22.04** using this fully automated installer.

---

## 🚀 Features

✅ Installs all required dependencies
✅ Secure Docker + UFW firewall setup
✅ Prompts for Ethereum private key & RPC endpoints
✅ Detects your server IP
✅ Runs Aztec validator node via Docker Compose
✅ Auto-restarts if container crashes
✅ Monitors logs for critical sync errors
✅ Clears corrupted state and auto-recovers
✅ Interactive menu to:

* View real-time logs
* Exit safely

---

## 📦 Requirements

### Hardware

* **8+ CPU cores**
* **16+ GB RAM**
* **100+ GB SSD (NVMe preferred)**

### Network / Wallet

* 🔐 Ethereum private key (without `0x`)
* 🌐 Sepolia L1 RPC URL (HTTP)
* 🌐 Sepolia Beacon API URL (HTTP)

---

## 🧑‍💻 Quick Start

Paste this into your terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-validator-auto-setup/main/install.sh)
```

---

## 🧠 What You'll Provide During Setup

* Ethereum private key (no `0x` prefix)
* Sepolia RPC endpoint URL
* Sepolia Beacon (Consensus) API URL
* Confirmation or override of detected server IP

---

## 🔍 After Installation

Your node will:

* Run in the background using Docker Compose
* Auto-restart on crash
* Recover automatically from sync errors
* Monitor logs continuously for critical issues

---

## 🔧 Manual Commands

Restart node:

```bash
cd ~/aztec-sequencer && docker compose up -d
```

Stop node:

```bash
cd ~/aztec-sequencer && docker compose down
```

Clear corrupted state and restart:

```bash
cd ~/aztec-sequencer
docker compose down -v
rm -rf ~/.aztec/alpha-testnet
docker compose up -d
```

View logs:

```bash
cd ~/aztec-sequencer && docker compose logs -f
```

---

## 🙋 Support

Need help?
Join the [Aztec Discord](https://discord.gg/aztecprotocol) and ask in [`#operators`](https://discord.com/channels/1144692727120937080/1367196595866828982).


