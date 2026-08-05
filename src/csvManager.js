require('dotenv').config();
const fs = require('fs');
const path = require('path');

const BASE = process.env.MT5_FILES_PATH || __dirname;
const CSV_FILE    = path.join(BASE, 'signals.csv');
const UPDATE_FILE = path.join(BASE, 'mt5_updates.txt');
const HEADERS = 'id,symbol,direction,entryPrice,sl,tp,volume,timestamp,status\n';

function init() {
  if (!fs.existsSync(CSV_FILE)) fs.writeFileSync(CSV_FILE, HEADERS);
}

function readAll() {
  init();
  const lines = fs.readFileSync(CSV_FILE, 'utf8').trim().split('\n');
  if (lines.length <= 1) return [];
  return lines.slice(1).map(line => {
    const [id, symbol, direction, entryPrice, sl, tp, volume, timestamp, status] = line.split(',');
    return { id, symbol, direction, entryPrice, sl, tp, volume, timestamp, status };
  });
}

function exists(id) {
  return readAll().some(r => r.id === id);
}

function append(signal) {
  init();
  const row = [
    signal.id,
    signal.symbol,
    signal.direction,
    signal.entryPrice,
    signal.sl ?? '',
    signal.tp ?? '',
    signal.volume ?? 0.01,
    signal.timestamp,
    'waiting to open'
  ].join(',') + '\n';
  fs.appendFileSync(CSV_FILE, row);
}

function updateStatus(id, status) {
  const rows = readAll();
  const updated = rows.map(r => r.id === id ? { ...r, status } : r);
  const content = HEADERS + updated.map(r =>
    [r.id, r.symbol, r.direction, r.entryPrice, r.sl, r.tp, r.volume, r.timestamp, r.status].join(',')
  ).join('\n') + '\n';
  fs.writeFileSync(CSV_FILE, content);
}

function processMT5Updates() {
  if (!fs.existsSync(UPDATE_FILE)) return;
  const content = fs.readFileSync(UPDATE_FILE, 'utf8').trim();
  if (!content) return;

  // اضافه شدن 'placed' به لیست valid states
  const valid = ['waiting to open', 'placed', 'open', 'SL', 'TP', 'forced close'];
  let count = 0;

  for (const line of content.split('\n').map(l => l.trim()).filter(l => l)) {
    const [id, status] = line.split(',').map(s => s.trim());
    if (!id || !status || !valid.includes(status)) continue;
    updateStatus(id, status);
    console.log(`🔄 Updated ${id} → ${status}`);
    count++;
  }

  fs.writeFileSync(UPDATE_FILE, '');
  if (count > 0) console.log(`✅ Processed ${count} MT5 updates`);
}

module.exports = { init, readAll, exists, append, updateStatus, processMT5Updates };
