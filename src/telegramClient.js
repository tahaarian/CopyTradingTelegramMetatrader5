const { TelegramClient } = require('telegram');
const { StringSession } = require('telegram/sessions');
const input = require('input');

// const SL_DISTANCE_DOLLARS = 10;
// const TP_DISTANCE_DOLLARS = 10;

class TelegramChannelReader {
  constructor() {
    this.apiId = parseInt(process.env.TELEGRAM_API_ID);
    this.apiHash = process.env.TELEGRAM_API_HASH;
    this.channelUsername = BigInt(process.env.TELEGRAM_CHANNEL_USERNAME);
    this.sessionString = process.env.TELEGRAM_SESSION || '';
    
    this.client = null;
    this.isConnecting = false;
    this.isConnected = false;
  }

  async connect() {
    if (this.isConnected) return;
    if (this.isConnecting) {
      await new Promise(resolve => setTimeout(resolve, 2000));
      return;
    }

    this.isConnecting = true;

    try {
      const session = new StringSession(this.sessionString);
      
      this.client = new TelegramClient(session, this.apiId, this.apiHash, {
        connectionRetries: 3,
        useWSS: false,
        timeout: 10000
      });

      await this.client.start({
        phoneNumber: async () => await input.text('Phone number: '),
        password: async () => await input.text('Password: '),
        phoneCode: async () => await input.text('Code: '),
        onError: (err) => console.error('Telegram auth error:', err.message),
      });

      this.isConnected = true;
      console.log('✅ Connected to Telegram');
      
      if (!this.sessionString) {
        const newSession = this.client.session.save();
        console.log('\n📝 Save this to .env file:');
        console.log('TELEGRAM_SESSION=' + newSession + '\n');
      }

    } catch (error) {
      console.error('❌ Connection failed:', error.message);
      this.isConnected = false;
    } finally {
      this.isConnecting = false;
    }
  }

  parseSignalMessage(text) {
    if (this.isCloseSignal(text)) {
      return { type: 'CLOSE_ALL', timestamp: new Date().toISOString() };
    }

    const lines = text.split('\n').map(l => l.trim()).filter(l => l);
    if (lines.length < 3) return null;

    // ─── Format 1: قدیمی (📊#BUY📍#XAUUSD @4677)
    const headerMatch = lines[0].match(/#(BUY|SELL)[^\#]*#(\w+)\s*@([\d.-]+)/i);
    if (headerMatch) {
      const direction = headerMatch[1].toUpperCase();
      const symbol = headerMatch[2];
      const priceStr = headerMatch[3];

      let entryPrice;
      if (priceStr.includes('-')) {
        const parts = priceStr.split('-');
        const base = parseFloat(parts[0]);
        let price2;
        if (parts[1].length === 2) {
          const baseInt = Math.floor(base);
          price2 = (baseInt - (baseInt % 100)) + parseInt(parts[1]);
        } else {
          price2 = parseFloat(parts[1]);
        }
        entryPrice = direction === 'BUY' ? Math.min(base, price2) : Math.max(base, price2);
      } else {
        entryPrice = parseFloat(priceStr);
      }

      if (!entryPrice) return null;

      // const sl = direction === 'BUY' ? entryPrice - SL_DISTANCE_DOLLARS : entryPrice + SL_DISTANCE_DOLLARS;
      // const tp = direction === 'BUY' ? entryPrice + TP_DISTANCE_DOLLARS : entryPrice - TP_DISTANCE_DOLLARS;

      return {
        type: 'OPEN',
        symbol,
        direction: direction.charAt(0) + direction.slice(1).toLowerCase(),
        entryPrice,
        sl: null,
        tp: null,
        timestamp: new Date().toISOString()
      };
    }

    // ─── Format 2: (#XAUUSD / BUY LIMIT SCALP / EN ...)
    const symbolLineMatch = lines[0].match(/^#(\w+)/);
    const dirLineMatch = lines[1]?.match(/\b(BUY|SELL)\b/i);

    if (symbolLineMatch && dirLineMatch) {
      const symbol = symbolLineMatch[1];
      const direction = dirLineMatch[1].toUpperCase();

      let entryPrice = null;
      for (const line of lines) {
        const enMatch = line.match(/^EN\s+([\d.]+)/i);
        if (enMatch) {
          entryPrice = parseFloat(enMatch[1]);
          break;
        }
      }

      if (!entryPrice) {
        console.log('❌ EN not found in signal');
        return null;
      }

      // const sl = direction === 'BUY' ? entryPrice - SL_DISTANCE_DOLLARS : entryPrice + SL_DISTANCE_DOLLARS;
      // const tp = direction === 'BUY' ? entryPrice + TP_DISTANCE_DOLLARS : entryPrice - TP_DISTANCE_DOLLARS;

      return {
        type: 'OPEN',
        symbol,
        direction: direction.charAt(0) + direction.slice(1).toLowerCase(),
        entryPrice,
        sl: null,
        tp: null,
        timestamp: new Date().toISOString()
      };
    }

    // ─── Format 3: (⚫️ XAUUSD BUY / Entry / TP1,TP2,TP3 / SL)
    // نماد و جهت از خط اول — Entry نادیده گرفته میشه — TP=TP2 — SL از سیگنال
    const firstLine = lines[0];
    const fmt3DirMatch = firstLine.match(/\b(BUY|SELL)\b/i);
    const fmt3SymMatch = firstLine.match(/\b([A-Z]{3,10}(?:USD|JPY|GBP|EUR|XAU|BTC)?)\b/i);

    if (fmt3DirMatch && fmt3SymMatch) {
      const direction = fmt3DirMatch[1].toUpperCase();
      const symbol = fmt3SymMatch[1].toUpperCase();

      // TP2 — خطی که TP2 داره و بعد 🟰 یا = یا فاصله یه عدد داره
      let tp = null;
      for (const line of lines) {
        if (/TP2/i.test(line)) {
          const tpMatch = line.match(/[🟰=]\s*([\d.]+)/);
          if (tpMatch) {
            tp = parseFloat(tpMatch[1]);
            break;
          }
        }
      }

      // SL — خطی که SL داره
      let sl = null;
      for (const line of lines) {
        if (/SL/i.test(line)) {
          const slMatch = line.match(/SL\s*[🟰=]?\s*([\d.]+)/i);
          if (slMatch) {
            sl = parseFloat(slMatch[1]);
            break;
          }
        }
      }

      if (!tp || !sl) {
        console.log('❌ Format 3: TP2 or SL not found');
        return null;
      }

      console.log(`✅ Format 3 — ${symbol} ${direction} | SL: ${sl} | TP2: ${tp} | Market order`);

      return {
        type: 'OPEN',
        symbol,
        direction: direction.charAt(0) + direction.slice(1).toLowerCase(),
        entryPrice: null, // market order — لحظه ورود
        sl,
        tp,
        timestamp: new Date().toISOString()
      };
    }

    return null;
  }

  isCloseSignal(text) {
    const normalizedText = text.toLowerCase().trim();
    return normalizedText.includes('اسکلپرا');
  }

  async getRecentSignals() {
    try {
      if (!this.isConnected) {
        await this.connect();
      }

      if (!this.client || !this.isConnected) {
        console.log('⏳ Telegram not connected yet');
        return { items: [] };
      }

      const messages = await this.client.getMessages(this.channelUsername, {
        limit: 2
      });

      const items = [];

      for (const msg of messages) {
        if (!msg.message) continue;

        const signal = this.parseSignalMessage(msg.message);
        
        if (signal) {
          if (signal.type === 'CLOSE_ALL') {
            items.push({
              position: `TG-CLOSE-${msg.id}`,
              copyPosition: `TG-CLOSE-${msg.id}`,
              symbol: 'ALL',
              openPrice: 0,
              closePrice: 0,
              profit: 0,
              totalProfit: 0,
              openDirection: 'Close',
              currentDirection: 'Close',
              openVolume: 0,
              currentVolume: 0,
              status: 'Closed',
              state: 'Closed',
              openTime: signal.timestamp,
              closeTime: signal.timestamp,
              sl: 0,
              tp: 0
            });
            console.log('🔴 CLOSE ALL signal detected!');
          } else if (signal.type === 'OPEN') {
            items.push({
              position: `TG-${msg.id}`,
              copyPosition: `TG-${msg.id}`,
              symbol: signal.symbol,
              openPrice: signal.entryPrice,  // null = market order در MT5
              closePrice: null,
              profit: 0,
              totalProfit: 0,
              openDirection: signal.direction,
              currentDirection: signal.direction,
              openVolume: 0.01,
              currentVolume: 0.01,
              status: 'Copied',
              state: 'Open',
              openTime: signal.timestamp,
              closeTime: null,
              sl: signal.sl,
              tp: signal.tp
            });
          }
        }
      }

      console.log(`📊 Found ${items.length} signals from Telegram`);
      return { items };

    } catch (error) {
      console.error('❌ Telegram error:', error.message);
      return { items: [] };
    }
  }

  async disconnect() {
    if (this.client && this.isConnected) {
      await this.client.disconnect();
      this.isConnected = false;
      console.log('👋 Disconnected from Telegram');
    }
  }
}

module.exports = TelegramChannelReader;

if (require.main === module) {
  require('dotenv').config();

  (async () => {
    const reader = new TelegramChannelReader();

    try {
      await reader.connect();

      console.log('\n--- Last 20 Messages ---\n' + '-'.repeat(50));

      const messages = await reader.client.getMessages(reader.channelUsername, {
        limit: 20
      });

      messages.forEach((msg, index) => {
        const date = new Date(msg.date * 1000).toISOString();
        console.log(`\n[${index + 1}] Time: ${date}`);
        console.log(`Text: ${msg.message || '(no text)'}`);
        
        if (msg.message) {
          const signal = reader.parseSignalMessage(msg.message);
          if (signal) {
            console.log('✅ PARSED SIGNAL:', JSON.stringify(signal, null, 2));
          }
        }
        
        console.log('-'.repeat(50));
      });

    } catch (err) {
      console.error('❌ Error:', err.message);
    } finally {
      await reader.disconnect();
    }
  })();
}
