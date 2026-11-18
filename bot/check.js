/* Aurum Gold Telegram bot. Runs every hour on GitHub Actions (see .github/workflows/aurum-bot.yml).
 * Loads the latest 1H gold candles, runs the SAME rules as the web app (docs/aurum.js) and sends a
 * Telegram message for every new BUY/SELL signal and every trade that hits its stop or target.
 * It never places trades.
 *
 * Environment:
 *   TELEGRAM_BOT_TOKEN   bot token from @BotFather (GitHub secret)
 *   TELEGRAM_CHAT_IDS    one or more chat ids, comma separated (GitHub secret)
 *   TWELVE_DATA_KEY      optional: real XAU/USD prices from twelvedata.com instead of PAXG (GitHub secret)
 *   BALANCE, RISK_PCT    optional: for the lot size (GitHub variables AURUM_BALANCE, AURUM_RISK_PCT)
 *   MAX_LOSSES           optional: daily loss limit shown in the message (default 2)
 *   TZ_NAME              optional: your time zone for times in messages (default Asia/Kuala_Lumpur)
 *   STATE_FILE           where the last checked candle is remembered (default bot/.state/state.json)
 *   DRY_RUN=1            print messages instead of sending; MOCK_KLINES=file uses a saved Binance kline file
 * Usage: node bot/check.js [--test]
 */
"use strict";
const fs = require("fs");
const path = require("path");
const A = require("../docs/aurum.js");

const H = 3600000;
const env = process.env;
const TEST = process.argv.includes("--test");
const TZ = env.TZ_NAME || "Asia/Kuala_Lumpur";
const BALANCE = parseFloat(env.BALANCE) || 1000;
const RISK = parseFloat(env.RISK_PCT) || 1;
const MAX_LOSSES = env.MAX_LOSSES === undefined || env.MAX_LOSSES === "" ? 2 : parseInt(env.MAX_LOSSES, 10);
const SPREAD = 0.3;
const STATE_FILE = env.STATE_FILE || path.join(__dirname, ".state", "state.json");
const APP_URL = env.APP_URL || "https://bunny-ecah.github.io/aurum-gold-indicator/";

const fmt = (x) => x.toFixed(2);
const when = (ms) => new Intl.DateTimeFormat("en-GB", { timeZone: TZ, weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms));

async function getJSON(url) {
  const r = await fetch(url, { headers: { "user-agent": "aurum-gold-bot" } });
  if (!r.ok) throw new Error(url.split("?")[0] + " -> HTTP " + r.status);
  return r.json();
}

// ---- prices ----
async function binance() {
  if (env.MOCK_KLINES) return JSON.parse(fs.readFileSync(env.MOCK_KLINES, "utf8"));
  const hosts = ["https://data-api.binance.vision", "https://api.binance.com"];
  let lastErr;
  for (const host of hosts) {
    try {
      let pages = [], end = null;
      for (let n = 0; n < 4; n++) {
        const d = await getJSON(host + "/api/v3/klines?symbol=PAXGUSDT&interval=1h&limit=1000" + (end ? "&endTime=" + end : ""));
        if (!d.length) break;
        pages.unshift(d); end = +d[0][0] - 1;
        if (d.length < 1000) break;
      }
      return [].concat(...pages);
    } catch (e) { lastErr = e; }
  }
  throw lastErr;
}
async function loadBars() {
  const now = Date.now();
  if (env.TWELVE_DATA_KEY) {
    const d = await getJSON("https://api.twelvedata.com/time_series?symbol=XAU/USD&interval=1h&timezone=UTC&order=ASC&outputsize=5000&apikey=" + encodeURIComponent(env.TWELVE_DATA_KEY));
    if (d.status === "error" || !d.values) throw new Error("Twelve Data: " + (d.message || "no data"));
    const bars = d.values.map((v) => {
      const p = v.datetime.split(/[- :]/).map(Number);
      return { t: Date.UTC(p[0], p[1] - 1, p[2], p[3] || 0, p[4] || 0), o: +v.open, h: +v.high, l: +v.low, c: +v.close };
    }).filter((b) => b.t + H <= now && A.goldMarketOpen(b.t));
    return { bars, source: "XAU/USD" };
  }
  const k = await binance();
  const bars = k.filter((x) => +x[6] < now).map((x) => ({ t: +x[0], o: +x[1], h: +x[2], l: +x[3], c: +x[4] })).filter((b) => A.goldMarketOpen(b.t));
  return { bars, source: "PAXG" };
}

// ---- news (docs/news.json, kept up to date by the news workflow) ----
function newsSoon(nowMs) {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "docs", "news.json"), "utf8"));
    return (d.events || []).filter((e) => e.t > nowMs - 30 * 60000 && e.t < nowMs + 90 * 60000);
  } catch (e) { return []; }
}

// ---- telegram ----
async function send(text) {
  const ids = (env.TELEGRAM_CHAT_IDS || "").split(",").map((s) => s.trim()).filter(Boolean);
  if (env.DRY_RUN || !env.TELEGRAM_BOT_TOKEN || !ids.length) {
    console.log("---- message" + (env.DRY_RUN ? " (dry run)" : " (no TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_IDS set)") + " ----\n" + text + "\n");
    return;
  }
  for (const id of ids) {
    const r = await fetch("https://api.telegram.org/bot" + env.TELEGRAM_BOT_TOKEN + "/sendMessage", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: id, text, parse_mode: "HTML", disable_web_page_preview: true }),
    });
    const j = await r.json().catch(() => ({}));
    if (!j.ok) throw new Error("Telegram refused chat " + id + ": " + (j.description || r.status));
  }
}

function lotFor(s) {
  const lot = A.lots(BALANCE, RISK, s.entry, s.sl, 100);
  return lot >= 0.01 ? "<b>" + lot.toFixed(2) + "</b>" : "<b>0.01</b> (minimum lot = " + (0.01 * Math.abs(s.entry - s.sl) * 100 / BALANCE * 100).toFixed(1) + "% risk)";
}
function todayLosses(res, closed, nowMs) {
  const day = (ms) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date(ms));
  const today = day(nowMs);
  return res.signals.filter((s) => s.exitBar != null && day(closed[s.exitBar].t + H) === today && s.result - SPREAD / Math.abs(s.entry - s.sl) < 0).length;
}
function signalMsg(s, res, closed, source, nowMs) {
  const side = s.side > 0 ? "🟢 BUY" : "🔴 SELL";
  const risk = Math.abs(s.entry - s.sl);
  const graded = res.signals.filter((x) => x.result != null && x.grade === s.grade);
  const win = graded.length >= 5 ? Math.round(100 * graded.filter((x) => x.result > 0).length / graded.length) + "% (grade " + s.grade + ", " + graded.length + " trades)" : null;
  const lines = [
    `<b>${side} NOW · Gold 1H</b> (Aurum)`,
    `Entry <b>${fmt(s.entry)}</b>`,
    `SL <b>${fmt(s.sl)}</b>  ($${fmt(risk)} away, −${RISK}%)`,
    `TP <b>${fmt(s.tp)}</b>  ($${fmt(Math.abs(s.tp - s.entry))}, RR 1:${s.rr.toFixed(1)})`,
    `Lot ${lotFor(s)} for $${BALANCE} at ${RISK}%`,
    `Quality <b>${s.grade}</b> ${s.quality}/100 · ${s.why}`,
    `Candle closed ${when(closed[s.bar].t + H)}`,
  ];
  if (win) lines.splice(6, 0, `Win chance ${win}`);
  const news = newsSoon(nowMs);
  if (news.length) lines.push(`⚠️ News: ${news.map((e) => e.title + " " + when(e.t)).join(", ")} — big moves likely`);
  const losses = todayLosses(res, closed, nowMs);
  if (MAX_LOSSES > 0 && losses >= MAX_LOSSES) lines.push(`⛔ ${losses} losses today — daily limit reached, the plan says skip`);
  if (source === "PAXG") lines.push(`<i>Prices are PAXG: use the $ distances on your broker's chart.</i>`);
  lines.push(APP_URL);
  return lines.join("\n");
}
function closeMsg(s, closed) {
  const r = s.result - SPREAD / Math.abs(s.entry - s.sl);
  const icon = r >= 0 ? "✅" : "❌";
  return `${icon} <b>${s.side > 0 ? "BUY" : "SELL"} closed: ${s.how}</b> ${r >= 0 ? "+" : "−"}${Math.abs(r).toFixed(2)}R (after spread)\n` +
    `Opened ${when(closed[s.bar].t + H)} at ${fmt(s.entry)} · closed ${when(closed[s.exitBar].t + H)}`;
}

function readState() { try { return JSON.parse(fs.readFileSync(STATE_FILE, "utf8")); } catch (e) { return null; } }
function writeState(st) { fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true }); fs.writeFileSync(STATE_FILE, JSON.stringify(st)); }

async function main() {
  const nowMs = Date.now();
  const { bars, source } = await loadBars();
  if (bars.length < 300) throw new Error("only " + bars.length + " candles loaded");
  const trend = A.trend4H(bars, 60);
  const res = A.run(bars, trend.dir, {}, { london: bars.map((b) => A.inLondon(b.t)), newyork: bars.map((b) => A.inNewYork(b.t)) });
  const lastT = bars[bars.length - 1].t;
  const st = readState();
  // only candles that closed since the last run (first run: just the latest candle)
  const sinceT = st && st.lastT ? st.lastT : lastT - 1;
  const fresh = (i) => bars[i].t > sinceT;
  const events = [];      // in time order; on the same candle a close comes before a new signal
  res.signals.forEach((s) => { if (s.exitBar != null && fresh(s.exitBar) && s.bar !== s.exitBar) events.push([bars[s.exitBar].t, 0, closeMsg(s, bars)]); });
  res.signals.forEach((s) => { if (fresh(s.bar)) events.push([bars[s.bar].t, 1, signalMsg(s, res, bars, source, nowMs)]); });
  const msgs = events.sort((a, b) => a[0] - b[0] || a[1] - b[1]).map((e) => e[2]);
  if (TEST) {
    const dir = trend.dir[trend.dir.length - 1];
    const open = res.open;
    msgs.unshift([
      "✅ <b>Aurum bot connected</b>",
      `Prices: ${source} · last candle ${when(lastT + H)} · close ${fmt(bars[bars.length - 1].c)}`,
      `Trend: ${dir > 0 ? "UP" : dir < 0 ? "DOWN" : "FLAT"} (4H vs EMA200)`,
      open ? `Open trade: ${open.side > 0 ? "BUY" : "SELL"} from ${fmt(open.entry)} · SL ${fmt(open.sl)} · TP ${fmt(open.tp)}` : "No open trade. You'll get a message for every new signal.",
    ].join("\n"));
  }
  for (const m of msgs) await send(m);
  writeState({ lastT, checkedAt: nowMs });
  console.log(`checked ${bars.length} candles (${source}), last ${new Date(lastT).toISOString()}, sent ${msgs.length} message(s)`);
}

main().catch(async (e) => {
  console.error("Aurum bot error:", e.message);
  if (TEST) { try { await send("⚠️ Aurum bot could not run: " + e.message); } catch (e2) { console.error(e2.message); } }
  process.exit(1);
});
