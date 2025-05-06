# 📘 Aztec Validator Auto-Setup
 
 Deploy and run an Aztec sequencer validator node on **Ubuntu 20.04 or 22.04** using this simple auto-setup script.
 
 ---
 
 ## 🚀 Features
 
 - ✅ Installs all required dependencies
 - ✅ Secure Docker setup
 - ✅ Firewall configuration for validator ports
 - ✅ Prompts for validator wallet & RPC info
 - ✅ Starts validator using Docker Compose
 - ✅ Includes logs, status, and reinstall options
 
 ---
 
 ## 📦 Requirements
 
 ### Recommended for Sequencer Node:
 - 8 CPU cores
 - 16 GB RAM
 - 100+ GB SSD
 
 ### Ethereum Wallet:
 - 🔐 Private key (without `0x`)
 - 🧾 Public address (starts with `0x`)
 
 ### Sepolia Endpoints:
 - L1 RPC URL (HTTP)
 - Beacon URL (HTTP)
 
 ---
 
 ## 🧑‍💻 Quick Start
 
 Run this in your terminal:
 
 ```bash
 bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-validator-auto-setup/main/install.sh)
 ```
 
 ---
 
 ## 🧠 You'll Be Asked
 
 - ETH private key (no `0x`)
 - Public address (`0x...`)
 - Sepolia L1 RPC URL
 - Beacon URL
 - Custom ports (optional)
 
 ---
 
 ## 🔍 After Setup
 
 - Validator runs in background via Docker Compose
 - Menu options include:
   - View logs
   - Check block + sync proof
   - Reinstall with saved config
 
 ---
 
 ## 🧯 Troubleshooting
 
 **Restart the node:**
 ```bash
 cd ~/aztec-sequencer && docker compose up -d
 ```
 
 **Fix sync error:**
 ```bash
 rm -rf /home/my-node/node && docker compose up -d
 ```
 
 ---
 
 ## 🙋 Need Help?
 
 Ask in the [Aztec Discord](https://discord.gg/aztecprotocol) under `#operators`.
