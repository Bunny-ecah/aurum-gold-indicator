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
 *   SIGNAL_TF            optional: 60 (1H, default), 30 (30m, New York session) or 60,30 for both
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
const TFS = (env.SIGNAL_TF || "60").split(",").map((x) => x.trim()).filter((x) => A.SETUPS[x]);
if (!TFS.length) TFS.push("60");

const fmt = (x) => x.toFixed(2);
const when = (ms) => new Intl.DateTimeFormat("en-GB", { timeZone: TZ, weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms));

async function getJSON(url) {
  const r = await fetch(url, { headers: { "user-agent": "aurum-gold-bot" } });
  if (!r.ok) throw new Error(url.split("?")[0] + " -> HTTP " + r.status);
  return r.json();
}

// ---- prices ----
async function binance(iv) {
  if (env.MOCK_KLINES) return JSON.parse(fs.readFileSync(env.MOCK_KLINES.replace("{tf}", iv), "utf8"));
  const hosts = ["https://data-api.binance.vision", "https://api.binance.com"];
  let lastErr;
  for (const host of hosts) {
    try {
      let pages = [], end = null;
      for (let n = 0; n < 4; n++) {
        const d = await getJSON(host + "/api/v3/klines?symbol=PAXGUSDT&interval=" + iv + "&limit=1000" + (end ? "&endTime=" + end : ""));
        if (!d.length) break;
        pages.unshift(d); end = +d[0][0] - 1;
        if (d.length < 1000) break;
      }
      return [].concat(...pages);
    } catch (e) { lastErr = e; }
  }
  throw lastErr;
}
async function loadBars(setup) {
  const now = Date.now(), barMs = setup.barMin * 60000;
  if (env.TWELVE_DATA_KEY) {
    const d = await getJSON("https://api.twelvedata.com/time_series?symbol=XAU/USD&interval=" + (setup.barMin === 30 ? "30min" : "1h") + "&timezone=UTC&order=ASC&outputsize=5000&apikey=" + encodeURIComponent(env.TWELVE_DATA_KEY));
    if (d.status === "error" || !d.values) throw new Error("Twelve Data: " + (d.message || "no data"));
    const bars = d.values.map((v) => {
      const p = v.datetime.split(/[- :]/).map(Number);
      return { t: Date.UTC(p[0], p[1] - 1, p[2], p[3] || 0, p[4] || 0), o: +v.open, h: +v.high, l: +v.low, c: +v.close };
    }).filter((b) => b.t + barMs <= now && A.goldMarketOpen(b.t));
    return { bars, source: "XAU/USD" };
  }
  const k = await binance(setup.barMin === 30 ? "30m" : "1h");
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
let BAR = H, LABEL = "1H";      // set per signal timeframe in main()
function todayLosses(res, closed, nowMs) {
  const day = (ms) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date(ms));
  const today = day(nowMs);
  return res.signals.filter((s) => s.exitBar != null && day(closed[s.exitBar].t + BAR) === today && s.result - SPREAD / Math.abs(s.entry - s.sl) < 0).length;
}
function signalMsg(s, res, closed, source, nowMs) {
  const side = s.side > 0 ? "🟢 BUY" : "🔴 SELL";
  const risk = Math.abs(s.entry - s.sl);
  const graded = res.signals.filter((x) => x.result != null && x.grade === s.grade);
  const win = graded.length >= 5 ? Math.round(100 * graded.filter((x) => x.result > 0).length / graded.length) + "% (grade " + s.grade + ", " + graded.length + " trades)" : null;
  const lines = [
    `<b>${side} NOW · Gold ${LABEL}</b> (Aurum)`,
    `Entry <b>${fmt(s.entry)}</b>`,
    `SL <b>${fmt(s.sl)}</b>  ($${fmt(risk)} away, −${RISK}%)`,
    `TP <b>${fmt(s.tp)}</b>  ($${fmt(Math.abs(s.tp - s.entry))}, RR 1:${s.rr.toFixed(1)})`,
    `Lot ${lotFor(s)} for $${BALANCE} at ${RISK}%`,
    `Quality <b>${s.grade}</b> ${s.quality}/100 · ${s.why}`,
    `Candle closed ${when(closed[s.bar].t + BAR)}`,
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
  return `${icon} <b>${LABEL} ${s.side > 0 ? "BUY" : "SELL"} closed: ${s.how}</b> ${r >= 0 ? "+" : "−"}${Math.abs(r).toFixed(2)}R (after spread)\n` +
    `Opened ${when(closed[s.bar].t + BAR)} at ${fmt(s.entry)} · closed ${when(closed[s.exitBar].t + BAR)}`;
}

function readState() { try { return JSON.parse(fs.readFileSync(STATE_FILE, "utf8")); } catch (e) { return null; } }
function writeState(st) { fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true }); fs.writeFileSync(STATE_FILE, JSON.stringify(st)); }

async function checkTf(tf, st, nowMs, msgs) {
  const setup = A.SETUPS[tf];
  BAR = setup.barMin * 60000; LABEL = setup.label;
  const { bars, source } = await loadBars(setup);
  if (bars.length < 300) throw new Error(LABEL + ": only " + bars.length + " candles loaded");
  const trend = A.trendHTF(bars, setup.barMin, setup.htfMin);
  const london = bars.map((b) => A.inLondon(b.t)), newyork = bars.map((b) => A.inNewYork(b.t));
  const ss = setup.settings.sessions;
  const allowed = ss === "All day" ? null : bars.map((b, i) => ss === "New York only" ? newyork[i] : ss === "London only" ? london[i] : london[i] || newyork[i]);
  const res = A.run(bars, trend.dir, setup.settings, { allowed, london, newyork });
  const lastT = bars[bars.length - 1].t;
  // only candles that closed since the last run (first run: just the latest candle)
  const sinceT = st[tf] ? st[tf] : lastT - 1;
  const fresh = (i) => bars[i].t > sinceT;
  const events = [];      // in time order; on the same candle a close comes before a new signal
  res.signals.forEach((s) => { if (s.exitBar != null && fresh(s.exitBar) && s.bar !== s.exitBar) events.push([bars[s.exitBar].t + BAR, 0, closeMsg(s, bars)]); });
  res.signals.forEach((s) => { if (fresh(s.bar)) events.push([bars[s.bar].t + BAR, 1, signalMsg(s, res, bars, source, nowMs)]); });
  events.forEach((e) => msgs.push(e));
  if (TEST) {
    const dir = trend.dir[trend.dir.length - 1], open = res.open;
    msgs.push([0, -1, [
      `✅ <b>Aurum bot connected · ${LABEL} signals</b>`,
      `Prices: ${source} · last candle closed ${when(lastT + BAR)} · ${fmt(bars[bars.length - 1].c)}`,
      `Trend: ${dir > 0 ? "UP" : dir < 0 ? "DOWN" : "FLAT"} (${trend.source[trend.source.length - 1]} vs EMA200)` + (ss !== "All day" ? ` · new trades: ${ss}` : ""),
      open ? `Open trade: ${open.side > 0 ? "BUY" : "SELL"} from ${fmt(open.entry)} · SL ${fmt(open.sl)} · TP ${fmt(open.tp)}` : "No open trade. You'll get a message for every new signal.",
    ].join("\n")]);
  }
  st[tf] = lastT;
  console.log(`${LABEL}: checked ${bars.length} candles (${source}), last ${new Date(lastT).toISOString()}, ${events.length} event(s)`);
}

async function main() {
  const nowMs = Date.now();
  const old = readState() || {};
  const st = Object.assign({}, old.tf || {});
  if (old.lastT && !st["60"]) st["60"] = old.lastT;      // state from the first bot version
  const msgs = [];
  for (const tf of TFS) await checkTf(tf, st, nowMs, msgs);
  msgs.sort((a, b) => a[1] === -1 || b[1] === -1 ? a[1] - b[1] : a[0] - b[0] || a[1] - b[1]);
  for (const m of msgs) await send(m[2]);
  writeState({ tf: st, checkedAt: nowMs });
  console.log(`sent ${msgs.length} message(s)`);
}

main().catch(async (e) => {
  console.error("Aurum bot error:", e.message);
  if (TEST) { try { await send("⚠️ Aurum bot could not run: " + e.message); } catch (e2) { console.error(e2.message); } }
  process.exit(1);
});
