```markdown
# 🤖 Telegram → MetaTrader 5 Copy Trading Bot

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Node.js](https://img.shields.io/badge/Node.js-18%2B-green.svg)
![MT5](https://img.shields.io/badge/MetaTrader-5-blueviolet.svg)
![MQL5](https://img.shields.io/badge/MQL5-Expert%20Advisor-orange.svg)

**Automatically copy trading signals from Telegram channels directly into MetaTrader 5.**  
No manual entry. No delay. Just signals → live trades.

</div>

---

## 📖 Overview

This project bridges **Telegram signal channels** and **MetaTrader 5** using a Node.js middleware layer and an MQL5 Expert Advisor. It listens to Telegram messages in real-time, parses trading signals, writes them to a shared CSV file, and the EA picks them up to place orders automatically.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        TELEGRAM CHANNELS                        │
│              (Signal providers via MTProto API)                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │  Real-time messages
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     NODE.JS MIDDLEWARE                          │
│                                                                 │
│  ┌─────────────────┐   ┌──────────────────┐  ┌──────────────┐  │
│  │ telegramClient  │──▶│  signalWatcher   │─▶│ csvManager   │  │
│  │  (MTProto/API)  │   │  (parser/filter) │  │ (read/write) │  │
│  └─────────────────┘   └──────────────────┘  └──────┬───────┘  │
└──────────────────────────────────────────────────────┼──────────┘
                                                       │
                            ┌──────────────────────────┤
                            │  Shared File System      │
                            │  (MT5 Common Files dir)  │
                            │                          │
                            │  📄 signals.csv          │
                            │  📄 mt5_updates.txt      │
                            └──────────────────────────┤
                                                       │
┌──────────────────────────────────────────────────────┼──────────┐
│                    METATRADER 5                       │          │
│                                                       ▼          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   ExpertAdvisor.mq5                        │  │
│  │                                                            │  │
│  │  • Reads signals.csv every 30s                             │  │
│  │  • Places Market / Pending orders                          │  │
│  │  • Manages Breakeven automatically                         │  │
│  │  • Deletes expired pending orders at EOD                   │  │
│  │  • Writes status back to mt5_updates.txt                   │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

---

## ✨ Features

| Feature | Description |
|---|---|
| 📡 **Real-time Listening** | Connects to Telegram via MTProto — no bot token needed |
| 🧠 **Smart Signal Parsing** | Supports multiple signal formats (Limit, Market, multi-TP) |
| 💰 **Custom Lot Sizing** | Separate lot config for Gold (XAU), USD pairs, and others |
| ⚡ **Market & Pending Orders** | Automatically detects order type from signal |
| 🔒 **Breakeven Management** | Auto-moves SL to breakeven after configurable profit |
| 🗑️ **Auto Cleanup** | Deletes unfilled pending orders at end of day |
| 🔄 **Status Sync** | EA writes back trade status (placed → open → TP/SL) |
| 📊 **CSV Bridge** | File-based IPC — no network dependency between Node and MT5 |

---

## 📁 Project Structure


CopyTradingTelegramMetatrader5/
│
├── 📄 telegramClient.js     # MTProto connection & message listener
├── 📄 signalWatcher.js      # Signal parser & main orchestrator
├── 📄 csvManager.js         # Read/write signals.csv & updates
├── 📄 ExpertAdvisor.mq5     # MQL5 EA — order execution engine
├── 📄 package.json          # Node.js dependencies
├── 📄 .env.example          # Environment variables template
│
├── 📄 signals.csv           # Shared signal queue (auto-generated)
└── 📄 mt5_updates.txt       # Status feedback from MT5 (auto-generated)

---

## ⚙️ Prerequisites

- **Node.js** v18 or higher
- **MetaTrader 5** (any broker)
- **Telegram Account** (not a bot — a real user account)
- A Telegram **API ID** and **API Hash** from [my.telegram.org](https://my.telegram.org)

---

## 🚀 Setup Guide

### Step 1 — Clone the Repository

bash
git clone https://github.com/tahaarian/CopyTradingTelegramMetatrader5.git
cd CopyTradingTelegramMetatrader5

### Step 2 — Install Node.js Dependencies

bash
npm install

### Step 3 — Configure Environment Variables

Copy the example file and fill in your credentials:

bash
cp .env.example .env

Edit `.env`:

env
# Telegram API credentials — get from https://my.telegram.org
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_PHONE=+1234567890

# Telegram channel/group username or ID to listen to
SIGNAL_CHANNEL=@your_signal_channel

# Path to MT5 Common Files directory
# Windows default:
# C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\Common\Files
MT5_FILES_PATH=C:\Users\YourUser\AppData\Roaming\MetaQuotes\Terminal\Common\Files

> 💡 **Finding MT5 Files Path:** In MetaTrader 5, go to `File → Open Data Folder`,
> then navigate to `..\Common\Files`.

### Step 4 — Install the Expert Advisor in MT5

1. Open **MetaTrader 5**
2. Press `F4` to open **MetaEditor**
3. In MetaEditor: `File → Open` → select `ExpertAdvisor.mq5`
4. Press `F7` to compile — confirm **zero errors**
5. Back in MT5, open the **Navigator** panel (`Ctrl+N`)
6. Under **Expert Advisors**, find `ExpertAdvisor`
7. Drag it onto any chart (e.g., EURUSD M5)

### Step 5 — Configure EA Parameters

When attaching the EA, set these inputs:

| Parameter | Default | Description |
|---|---|---|
| `CSV_FILE` | `signals.csv` | Signal file name |
| `UPDATE_FILE` | `mt5_updates.txt` | Status feedback file |
| `DEFAULT_LOT` | `0.01` | Lot size for other pairs |
| `GOLD_LOT` | `0.02` | Lot size for XAU symbols |
| `USD_LOT` | `0.01` | Lot size for xxx/USD pairs |
| `ENABLE_BREAKEVEN` | `true` | Enable auto breakeven |
| `INITIAL_BREAKEVEN_PIPS` | `50` | Pips profit to trigger breakeven |
| `BREAKEVEN_OFFSET_PIPS` | `5` | Pips above open price for BE SL |
| `EXPIRY_HOUR` | `23` | Hour to delete unfilled pending orders |

> ⚠️ Make sure **AutoTrading** is enabled in MT5 (green button in the toolbar).

### Step 6 — Run the Node.js Bot

bash
node signalWatcher.js

On first run, Telegram will ask for a **verification code** sent to your phone.
Enter it in the terminal. The session is saved locally for future runs — no re-auth needed.

---

## 📶 Signal Formats

The parser supports multiple message formats from your Telegram channel:

**Format 1 — Limit Order**

EURUSD Buy
Entry: 1.0850
SL: 1.0800
TP: 1.0920

**Format 2 — Market Order** *(entry omitted or set to 0)*

XAUUSD Sell Now
SL: 1980.00
TP: 1950.00

**Format 3 — Multi-TP**

GBPUSD Buy
Entry: 1.2700
SL: 1.2650
TP1: 1.2750
TP2: 1.2800

---

## 🔄 Trade Lifecycle


Signal received
      │
      ▼
signals.csv  ──────────────────────────►  status: waiting to open
      │
      ▼  (EA picks up every 30s)
Order placed (Pending / Market)  ───────►  status: placed
      │
      ▼  (order fills)
Position open  ─────────────────────────►  status: open
      │
      ├──  hits Take Profit  ────────────►  status: TP
      ├──  hits Stop Loss    ────────────►  status: SL
      └──  pending expired   ────────────►  status: expired

---

## 💰 Lot Sizing Logic

The EA determines lot size purely based on the **symbol name** — CSV volume is ignored:


Symbol contains "XAU"          →  GOLD_LOT
Symbol ends with "USD"         →  USD_LOT
Everything else                →  DEFAULT_LOT

---

## 🛡️ Risk Warning

> **This software is provided for educational purposes only.**  
> Trading forex and metals involves significant risk of financial loss.  
> Always test thoroughly on a **demo account** before using with live funds.  
> Past performance of any signal channel does not guarantee future results.

---

## 🤝 Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.

---

## 📜 License

MIT — see [LICENSE](LICENSE) for details.

---

<div align="center">
Made with ❤️ for traders who hate manual entry
</div>
