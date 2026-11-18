/* Updates docs/news.json with high-impact USD events (NFP, CPI, Fed, ...) from the free
 * Forex Factory weekly calendar. Run by .github/workflows/aurum-news.yml every 6 hours.
 * Keeps events from the last 14 days, so the file builds up week by week.
 * Usage: node bot/news.js [calendar.json]   (a file argument is used instead of downloading, for tests)
 */
"use strict";
const fs = require("fs");
const path = require("path");
const OUT = path.join(__dirname, "..", "docs", "news.json");
const URLS = ["https://nfs.faireconomy.media/ff_calendar_thisweek.json", "https://nfs.faireconomy.media/ff_calendar_nextweek.json"];

async function load() {
  if (process.argv[2]) return [JSON.parse(fs.readFileSync(process.argv[2], "utf8"))];
  const out = [];
  for (const u of URLS) {
    try {
      const r = await fetch(u, { headers: { "user-agent": "aurum-gold-news" } });
      if (r.ok) out.push(await r.json()); else console.log(u, "HTTP", r.status);
    } catch (e) { console.log(u, e.message); }
  }
  if (!out.length) throw new Error("no calendar could be downloaded");
  return out;
}
(async () => {
  const lists = await load();
  const fresh = [].concat(...lists)
    .filter((e) => e && e.country === "USD" && /high/i.test(e.impact || ""))
    .map((e) => ({ t: Date.parse(e.date), title: String(e.title).trim() }))
    .filter((e) => e.t > 0);
  let old = [];
  try { old = JSON.parse(fs.readFileSync(OUT, "utf8")).events || []; } catch (e) {}
  const now = Date.now(), map = new Map();
  for (const e of old.concat(fresh)) if (e.t > now - 14 * 864e5) map.set(e.t + "|" + e.title, e);
  const events = [...map.values()].sort((a, b) => a.t - b.t);
  const before = (() => { try { return JSON.stringify(JSON.parse(fs.readFileSync(OUT, "utf8")).events); } catch (e) { return ""; } })();
  if (JSON.stringify(events) === before) { console.log("news.json unchanged (" + events.length + " events)"); return; }
  fs.writeFileSync(OUT, JSON.stringify({ updated: now, source: "Forex Factory (USD, high impact)", events }, null, 1) + "\n");
  console.log("news.json updated: " + events.length + " events");
})().catch((e) => { console.error(e.message); process.exit(1); });
