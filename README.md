# 📘 Aztec Sequencer Node Auto-Setup

Deploy and manage an **Aztec Sequencer Validator Node** on **Ubuntu 20.04/22.04** using this interactive installer.

---

## 🚀 Features

* ✅ Installs all required dependencies
* ✅ Secure Docker + Firewall configuration
* ✅ Prompts for Ethereum wallet & RPC settings
* ✅ Starts Aztec validator node using Docker Compose
* ✅ Saves configuration for reinstallation
* ✅ Menu options to:

  * View logs
  * Show block info + sync proof
  * Reinstall with saved config
* ✅ Auto-monitors logs for fatal sync errors
* ✅ Automatically clears corrupted state and restarts the node

---

## 📦 Requirements

### System

* **8+ CPU cores**
* **16+ GB RAM**
* **100+ GB SSD (NVMe preferred)**

### Wallet & Network

* 🔐 Ethereum private key (without `0x`)
* 🧾 Ethereum public address
* 🌐 Sepolia L1 RPC URL (HTTP)
* 🌐 Sepolia Beacon URL (HTTP)

---

## 🧑‍💻 Quick Start

Paste this into your terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-validator-auto-setup/main/install.sh)
```

---

## 🧠 During Setup, You'll Provide:

* Ethereum private key (without `0x`)
* Ethereum public address (starts with `0x`)
* Sepolia RPC & Beacon endpoints
* Custom ports (optional)

---

## 🔍 Post-Installation

After setup, your node will:

* Run in the background via Docker Compose
* Monitor logs and recover from sync issues automatically

Use the menu to:

* View logs
* Check sync status
* Reinstall or update

---

## 🔧 Manual Commands

Restart node:

```bash
cd ~/aztec-sequencer && docker compose up -d
```

Clear state and re-run node:

```bash
rm -rf /home/my-node/node
docker compose up -d
```

---

## 🙋 Support

For help, visit the [Aztec Discord](https://discord.gg/aztecprotocol) and ask in the [`#operators` ](https://discord.com/channels/1144692727120937080/1367196595866828982) channel.

