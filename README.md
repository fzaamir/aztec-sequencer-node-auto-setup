## 📘 Aztec Validator Auto-Setup

A one-click installer to deploy and run an Aztec validator node on any Ubuntu VPS (20.04+), complete with all dependencies, Docker, Aztec CLI tools, and validator configuration.

---

### 🚀 Features

* Installs all dependencies
* Installs Docker the secure way
* Installs Aztec CLI tools
* Configures firewall
* Launches node in a `screen` session
* Prompts for wallet and RPC info
* Provides next-step guidance

---

## 📦 Requirements

* Ubuntu 20.04 / 22.04 VPS (1–2 CPU, 4+ GB RAM recommended)
* Ethereum wallet (with Sepolia ETH):

  * Private key (do **not** share)
  * Public address (starts with `0x`)
* Sepolia RPC and Beacon URLs (e.g. from [Ankr](https://www.ankr.com), [Alchemy](https://alchemy.com), or [drpc](https://drpc.org))

---

## 🧑‍💻 Quick Start

> **Copy and paste this command into your terminal:**

```bash
bash <(curl -s https://raw.githubusercontent.com/<your-username>/aztec-validator-auto-setup/main/install.sh)
```

Replace `<your-username>` with your actual GitHub username after you upload the script.

---

## 🧠 What You'll Be Asked

* Validator Private Key (without `0x`)
* Validator Public Address (`0x...`)
* Sepolia L1 RPC URL (HTTP)
* Sepolia Beacon URL
* Your public IP will be auto-detected

---

## 🔍 After Setup

Once the script completes, it will:

* Launch the node inside a `screen` session (`screen -r aztec`)
* Print a command to:

  * Get the latest proven block
  * Generate a sync proof
* Help you register in Discord with `/operator start`
* Provide an optional command to register your validator on-chain

---

## 📋 Validator Registration (L1)

If you want to register your validator on-chain:

```bash
aztec add-l1-validator \
  --l1-rpc-urls <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --attester <VALIDATOR_ADDRESS> \
  --proposer-eoa <VALIDATOR_ADDRESS> \
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
  --l1-chain-id 11155111
```

---

## 🧯 Troubleshooting

* **Node crashes / stuck**:
  Re-run it by reattaching to screen:

  ```bash
  screen -r aztec
  ```

* **No proven block?**
  Wait a few minutes. The node needs time to sync.

* **Error: `Obtained L1 to L2 messages failed to be hashed`**
  Try restarting:

  ```bash
  rm -rf ~/.aztec/alpha-testnet
  screen -r aztec
  ```

---

## 🙋 Support

Need help? Ask in the official [Aztec Discord](https://discord.gg/aztecprotocol) in `#operators` or `#start-here`.


