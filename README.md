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

This project bridges **Telegram signal channels** and **MetaTrader 5** using a Node.js middleware layer and an MQL5 Expert Advisor. It listens to Telegram messages in real time, parses trading signals, writes them to a shared CSV file, and the EA picks them up to place orders automatically.

---

## 🏗️ Architecture
```text
┌─────────────────────────────────────────────────────────────────┐
│                        TELEGRAM CHANNELS                        │
│              (Signal providers via MTProto API)                │
└───────────────────────────┬─────────────────────────────────────┘
│  Real-time messages
▼
┌─────────────────────────────────────────────────────────────────┐
│                     NODE.JS MIDDLEWARE                         │
│                                                                 │
│  ┌─────────────────┐   ┌──────────────────┐   ┌──────────────┐ │
│  │ telegramClient  │──▶│  signalWatcher   │──▶│  csvManager  │ │
│  │  (MTProto/API)  │   │  (parser/filter) │   │ (read/write) │ │
│  └─────────────────┘   └──────────────────┘   └──────┬───────┘ │
└───────────────────────────────────────────────────────┼─────────┘
│
┌───────────────────────────┤
│    Shared File System     │
│   (MT5 Common Files dir)  │
│                           │
│   📄 signals.csv          │
│   📄 mt5_updates.txt      │
└───────────────────────────┤
│
┌───────────────────────────────────────────────────────┼─────────┐
│                      METATRADER 5                     │         │
│                                                       ▼         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   ExpertAdvisor.mq5                        │ │
│  │                                                            │ │
│  │  • Reads signals.csv every 30s                             │ │
│  │  • Places Market / Pending orders                          │ │
│  │  • Manages breakeven automatically                         │ │
│  │  • Deletes expired pending orders at EOD                   │ │
│  │  • Writes status back to mt5_updates.txt                   │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘


✨ Features

Feature	Description
📡 Real-time Listening	Connects to Telegram via MTProto with no bot token required
🧠 Smart Signal Parsing	Supports multiple signal formats including limit, market, and multi-TP
💰 Custom Lot Sizing	Separate lot sizing for Gold (XAU), USD pairs, and all other symbols
⚡ Market & Pending Orders	Detects order type automatically from incoming signals
🔒 Breakeven Management	Moves stop loss to breakeven after configurable profit
🗑️ Auto Cleanup	Deletes unfilled pending orders at the end of the day
🔄 Status Sync	Writes trade status updates from MT5 back to Node.js
📊 CSV Bridge	Uses file-based communication between Node.js and MT5

📁 Project Structure

CopyTradingTelegramMetatrader5/
│
├── telegramClient.js     # MTProto connection and message listener
├── signalWatcher.js      # Signal parser and main orchestrator
├── csvManager.js         # Read/write logic for signals and updates
├── ExpertAdvisor.mq5     # MQL5 EA for order execution
├── package.json          # Node.js dependencies
├── .env.example          # Environment variable template
├── signals.csv           # Shared signal queue (auto-generated)
└── mt5_updates.txt       # Status feedback from MT5 (auto-generated)

⚙️ Prerequisites

Node.js 18 or higher
MetaTrader 5
Telegram account (a real user account, not a bot)
Telegram API ID and API Hash from my.telegram.org

🚀 Setup Guide

Step 1 — Clone the Repository
bash
git clone https://github.com/tahaarian/CopyTradingTelegramMetatrader5.git
cd CopyTradingTelegramMetatrader5
Step 2 — Install Dependencies
bash
npm install
Step 3 — Configure Environment Variables
Copy the example file:

bash
cp .env.example .env
Edit .env:

env
# Telegram API credentials
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_PHONE=+1234567890

# Telegram channel/group username or ID
SIGNAL_CHANNEL=@your_signal_channel

# MT5 Common Files path
# Windows default:
# C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\Common\Files
MT5_FILES_PATH=C:\Users\YourUser\AppData\Roaming\MetaQuotes\Terminal\Common\Files
Tip: In MetaTrader 5, go to File -> Open Data Folder, then navigate to ..\Common\Files.

Step 4 — Install the Expert Advisor in MT5
Open MetaTrader 5
Press F4 to open MetaEditor
Open ExpertAdvisor.mq5
Press F7 to compile and confirm there are no errors
Return to MT5 and open the Navigator panel with Ctrl+N
Find ExpertAdvisor under Expert Advisors
Drag it onto any chart, for example EURUSD M5
Step 5 — Configure EA Parameters
When attaching the EA, set these inputs as needed:


Parameter	Default	Description
CSV_FILE	signals.csv	Signal file name
UPDATE_FILE	mt5_updates.txt	Status update file
DEFAULT_LOT	0.01	Lot size for other pairs
GOLD_LOT	0.02	Lot size for XAU symbols
USD_LOT	0.01	Lot size for symbols ending in USD
ENABLE_BREAKEVEN	true	Enable automatic breakeven
INITIAL_BREAKEVEN_PIPS	50	Profit in pips before breakeven activates
BREAKEVEN_OFFSET_PIPS	5	Offset from entry price for breakeven stop
EXPIRY_HOUR	23	Hour to delete unfilled pending orders
Important: Make sure AutoTrading is enabled in MT5.

Step 6 — Run the Node.js Bot
bash
node signalWatcher.js
On the first run, Telegram will send a verification code to your phone. Enter it in the terminal. The session will be saved locally for future runs.

📶 Supported Signal Formats

Format 1 — Limit Order
text
EURUSD Buy
Entry: 1.0850
SL: 1.0800
TP: 1.0920
Format 2 — Market Order
text
XAUUSD Sell Now
SL: 1980.00
TP: 1950.00
Format 3 — Multi-TP
text
GBPUSD Buy
Entry: 1.2700
SL: 1.2650
TP1: 1.2750
TP2: 1.2800
🔄 Trade Lifecycle
text
Signal received
│
▼
signals.csv  ──────────────────────────►  status: waiting to open
│
▼  (EA checks every 30s)
Order placed (Pending / Market)  ───────►  status: placed
│
▼  (order fills)
Position open  ─────────────────────────►  status: open
│
├── hits Take Profit  ────────────►  status: TP
├── hits Stop Loss    ────────────►  status: SL
└── pending expired   ────────────►  status: expired
💰 Lot Sizing Logic

The EA determines lot size based on the symbol name. CSV volume is ignored.

text
Symbol contains "XAU"   -> GOLD_LOT
Symbol ends with "USD"  -> USD_LOT
Everything else         -> DEFAULT_LOT
🛡️ Risk Warning

This software is provided for educational purposes only.

Trading forex and metals involves significant financial risk.

Always test on a demo account before using live funds.

Past performance of any signal provider does not guarantee future results.

🤝 Contributing

Pull requests are welcome. For major changes, open an issue first to discuss the proposed update.

📜 License
This project is licensed under the MIT License. See LICENSE for details.