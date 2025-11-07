# ⚡ Aztec Sequencer Node Installer (v2.1.2)

Fully automated deployment & management of an **Aztec Sequencer Node** on **Ubuntu 20.04 / 22.04**.

---

## ✨ Features

* 🧩 Installs all dependencies (Docker, Docker Compose, CLI)
* 🚀 Supports the new **Aztec 2.1.2 testnet join method**
* 🔐 Auto-generates **BLS**, **Attester**, and **Withdrawer** keys
* 🌐 Detects and applies your public IP automatically
* 🐳 Runs node using Docker Compose with auto-restart
* 🔄 Updates automatically to the latest image tag
* 🧹 One-click reset and cleanup
* 📊 Real-time logs and Peer ID viewer
* 🧠 No manual key entry fully automated setup

---

## 📦 System Requirements

| Resource     | Minimum Specification                     |
| ------------ | ----------------------------------------- |
| OS           | Ubuntu 20.04 / 22.04                      |
| CPU          | 4–8 cores                                 |
| RAM          | 16 GB                                     |
| Disk         | 100 GB SSD                                |
| Network Keys | Ethereum private key, RPC URL, Beacon URL |

---

## 🚀 Quick Install

Paste the following in your terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/fzaamir/aztec-sequencer-node-auto-setup/main/install.sh)
```

> 🆕 Compatible with Aztec **v2.1.2** — includes automated key creation and validator registration.

---

## ⚙️ What’s New in 2.1.2

Aztec Labs has introduced a new **rollup contract and staking system**.
This means you must rejoin the testnet using the **CLI** and have `STAKE` tokens.

### Joining Steps (auto-handled by this script):

1. Approves the rollup contract to spend your 200k STAKE:

   ```bash
   cast send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A \
     "approve(address,uint256)" 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 \
     200000ether --private-key "$PRIVATE_KEY" --rpc-url $ETH_RPC
   ```
2. Generates new **BLS keys** (using Aztec CLI)
3. Registers your validator with:

   ```bash
   aztec add-l1-validator \
     --l1-rpc-urls $ETH_RPC \
     --network testnet \
     --private-key $PRIVATE_KEY \
     --attester $ATTESTER_ADDRESS \
     --withdrawer $WITHDRAWER_ADDRESS \
     --bls-secret-key $BLS_SECRET_KEY \
     --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67
   ```

All of the above are now automated by this installer.

---

## 🧪 Interactive Menu

```
1️⃣  Install and Launch Node
2️⃣  Get Peer ID
3️⃣  View Real-Time Logs
4️⃣  Perform Full Reset
5️⃣  Update & Restart Node
6️⃣  Exit
```

---

## 🔒 Security Notes

* All keys are stored locally under `$HOME/aztec-sequencer/keys`
* BLS and Ethereum keys are auto-generated if missing
* UFW firewall setup is skipped automatically on WSL
* On bare-metal Ubuntu, ports **22, 40400 (TCP/UDP), 8080** are opened automatically

---

## 💬 Support & Resources

* 💬 [Aztec Discord — #operators](https://discord.gg/aztecprotocol)
* 📘 [Aztec Docs — Creating Keystores](https://docs.aztec.network/the_aztec_network/operation/keystore/creating_keystores)
* 🛠️ [GitHub Issues](https://github.com/fzaamir/aztec-validator-auto-setup)

---

## 🛡️ Built for Operators

Minimal. Secure. Resilient.
**Plug it in. Let it run. 🟢**



If yes, I’ll give you the full updated script next.
