require('dotenv').config();
const TelegramChannelReader = require('./telegramClient');
const csv = require('./csvManager');

const reader = new TelegramChannelReader();

async function poll() {
  // 1. آپدیت‌های MT5 رو اعمال کن
  csv.processMT5Updates();

  // 2. سیگنال‌های جدید تلگرام رو بخون
  try {
    const { items } = await reader.getRecentSignals();
    for (const item of items) {
      if (!csv.exists(item.position)) {
        csv.append({
          id:         item.position,
          symbol:     item.symbol,
          direction:  item.openDirection,
          entryPrice: item.openPrice,
          sl:         item.sl,
          tp:         item.tp,
          volume:     item.openVolume,
          timestamp:  item.openTime
        });
        console.log(`✅ New signal: ${item.symbol} ${item.openDirection} @ ${item.openPrice}`);
      }
    }
  } catch (err) {
    console.error('❌ Error fetching signals:', err.message);
  }
}

(async () => {
  await reader.connect();
  console.log('👀 Watching for signals...');
  await poll();
  setInterval(poll, 3000);
})();
