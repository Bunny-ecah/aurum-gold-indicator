/* Aurum Gold rules engine for the web app.
 * JavaScript port of tradingview/tests/model.py (the reference model of AurumSignalAudit.pine
 * and mt5/AurumCore.mqh). Same rules: SNR + SND, trend from the last completed 4H candle vs
 * EMA200, one trade at a time, SL checked before TP, 100-candle time limit.
 * Works in the browser (window.Aurum) and in Node (module.exports) for the parity tests.
 */
(function (root) {
  "use strict";
  var TOUCH_ATR = 0.2, MERGE_ATR = 0.3;
  var POINTS_NEEDED = { Aggressive: 1, Balanced: 2, Strict: 3 };
  var SWING = { Small: 3, Normal: 5, Large: 10 };
  var DEFAULTS = { mode: "Balanced", swing: "Large", sessions: "All day", minRR: 1.2, slBuffer: 0.5,
    impulse: 1.5, minRisk: 0.5, cap: 4, maxBars: 100, balance: 1000, riskPct: 1, contract: 100 };

  function atrSeries(bars, length) {
    length = length || 14;
    var out = [], prev = null, v = null;
    for (var i = 0; i < bars.length; i++) {
      var b = bars[i];
      var tr = prev === null ? b.h - b.l : Math.max(b.h - b.l, Math.abs(b.h - prev), Math.abs(b.l - prev));
      v = v === null ? tr : (v * (length - 1) + tr) / length;
      out.push(i >= length ? v : null);
      prev = b.c;
    }
    return out;
  }

  function bullRejection(b) {
    var rng = b.h - b.l;
    return rng > 0 && (b.c > b.o || (Math.min(b.o, b.c) - b.l >= 0.5 * rng && b.c >= b.l + 0.5 * rng));
  }
  function bearRejection(b) {
    var rng = b.h - b.l;
    return rng > 0 && (b.c < b.o || (b.h - Math.max(b.o, b.c) >= 0.5 * rng && b.c <= b.h - 0.5 * rng));
  }

  function addLevel(levels, price, bar, tol, cap) {
    for (var i = levels.length - 1; i >= 0; i--) if (Math.abs(levels[i].p - price) <= tol) levels.splice(i, 1);
    levels.push({ p: price, bar: bar });
    while (levels.length > cap) levels.shift();
  }
  function addZone(zones, top, bot, bar, cap) {
    for (var i = zones.length - 1; i >= 0; i--) if (zones[i].bot <= top && zones[i].top >= bot) zones.splice(i, 1);
    zones.push({ top: top, bot: bot, bar: bar, touch: 0 });
    while (zones.length > cap) zones.shift();
  }

  function target(side, entry, stop, nearest, minRR) {
    var risk = Math.abs(entry - stop);
    if (!(risk > 0)) return null;
    if (nearest !== null && nearest !== undefined) {
      var rr = (nearest - entry) / risk * side;
      if (rr < minRR) return null;
      return entry + side * Math.min(rr, Math.max(3, minRR)) * risk;
    }
    return entry + side * Math.max(2, minRR) * risk;
  }

  function tradeStep(t, b, held, maxBars) {
    var risk = Math.abs(t.entry - t.sl);
    if (t.side > 0 ? b.l <= t.sl : b.h >= t.sl) return { r: -1, how: "Stop loss" };
    if (t.side > 0 ? b.h >= t.tp : b.l <= t.tp) return { r: Math.abs(t.tp - t.entry) / risk, how: "Take profit" };
    if (held >= maxBars) return { r: (b.c - t.entry) / risk * t.side, how: "Time exit" };
    return null;
  }

  function quality(zone, level, fresh, rr, london, newYork) {
    var q = zone && level ? 35 : zone ? 25 : level ? 10 : 0;
    q += zone && fresh ? 20 : 0;
    q += rr >= 2.5 ? 25 : rr >= 2.0 ? 20 : rr >= 1.5 ? 12 : 5;
    q += london && newYork ? 20 : london || newYork ? 12 : 0;
    return q;
  }
  function grade(q) { return q >= 70 ? "A" : q >= 50 ? "B" : "C"; }

  function lots(balance, riskPct, entry, stop, contract, step) {
    contract = contract || 100; step = step || 0.01;
    var raw = balance * riskPct / 100 / (Math.abs(entry - stop) * contract);
    return Math.floor(raw / step + 1e-9) * step;
  }

  // ---- time helpers (DST-correct through Intl) ----
  var fmtCache = {};
  function localParts(ms, tz) {
    var f = fmtCache[tz] || (fmtCache[tz] = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hourCycle: "h23",
      weekday: "short", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }));
    var p = {};
    f.formatToParts(new Date(ms)).forEach(function (x) { p[x.type] = x.value; });
    return { wd: p.weekday, y: +p.year, mo: +p.month, d: +p.day, h: +p.hour, mi: +p.minute };
  }
  function sessionOpen(ms, tz) {          // 08:00-17:00 local, Monday-Friday (candle open time)
    var p = localParts(ms, tz);
    return p.wd !== "Sat" && p.wd !== "Sun" && p.h >= 8 && p.h < 17;
  }
  function inLondon(ms) { return sessionOpen(ms, "Europe/London"); }
  function inNewYork(ms) { return sessionOpen(ms, "America/New_York"); }
  // Spot gold trades Sunday 18:00 to Friday 17:00 New York time, with a daily break 17:00-18:00.
  function goldMarketOpen(ms) {
    var p = localParts(ms, "America/New_York");
    if (p.wd === "Sat") return false;
    if (p.wd === "Sun") return p.h >= 18;
    if (p.wd === "Fri") return p.h < 17;
    return p.h !== 17;
  }

  // Higher-timeframe candles on the broker clock used in the backtest (server = New York + 7 h):
  // 4H boundaries fall at 17:00, 21:00, 01:00 ... New York time; 1H candles on the hour.
  function buildHTF(bars, htfMin, barMin) {
    var out = [], cur = null, barMs = (barMin || 60) * 60000;
    for (var i = 0; i < bars.length; i++) {
      var b = bars[i], p = localParts(b.t, "America/New_York");
      var serverMin = ((p.h + 7) % 24) * 60 + p.mi;
      var key = b.t - (serverMin % htfMin) * 60000;
      if (!cur || cur.t !== key) {
        cur = { t: key, o: b.o, h: b.h, l: b.l, c: b.c };
        out.push(cur);
      } else {
        cur.h = Math.max(cur.h, b.h); cur.l = Math.min(cur.l, b.l); cur.c = b.c;
      }
    }
    for (var j = 0; j < out.length; j++) out[j].end = out[j].t + htfMin * 60000;
    return out;
  }
  function build4H(bars) { return buildHTF(bars, 240, 60); }
  function tfLabel(m) { return m >= 1440 ? "1D" : m >= 60 ? (m / 60) + "H" : m + "m"; }

  // Trend per chart candle: last COMPLETED higher-timeframe candle at the chart candle's close -> sign(close - EMA200).
  // Until 210 higher-timeframe candles exist, the chart's own EMA200 is used (as the TradingView script does).
  // 1H signals use the 4H trend; 30m signals use the 1H trend (the tested setups).
  function trendHTF(bars, barMinutes, htfMinutes) {
    barMinutes = barMinutes || 60; htfMinutes = htfMinutes || 240;
    var hb = buildHTF(bars, htfMinutes, barMinutes), k = 2 / 201, ema = null, closes = [];
    for (var i = 0; i < hb.length; i++) {
      ema = ema === null ? hb[i].c : ema + (hb[i].c - ema) * k;
      closes.push({ end: hb[i].end, c: hb[i].c, e: ema, n: i });
    }
    var hl = tfLabel(htfMinutes), cl = tfLabel(barMinutes);
    var out = [], src = [], ema4 = [], j = -1, cur = null, curE = null, e1 = null;
    for (var n = 0; n < bars.length; n++) {
      var b = bars[n];
      e1 = e1 === null ? b.c : e1 + (b.c - e1) * k;
      var decision = b.t + barMinutes * 60000;
      while (j + 1 < closes.length && closes[j + 1].end <= decision) {
        j++;
        cur = closes[j].n >= 210 ? (closes[j].c > closes[j].e ? 1 : closes[j].c < closes[j].e ? -1 : 0) : null;
        curE = closes[j].n >= 210 ? closes[j].e : null;
      }
      if (cur !== null) { out.push(cur); src.push(hl); ema4.push(curE); }
      else { out.push(n >= 200 ? (b.c > e1 ? 1 : b.c < e1 ? -1 : 0) : 0); src.push(cl); ema4.push(n >= 200 ? e1 : null); }
    }
    return { dir: out, source: src, ema: ema4 };
  }
  function trend4H(bars, barMinutes) { return trendHTF(bars, barMinutes || 60, 240); }

  // The two tested setups (BACKTEST-RESULTS.md)
  var SETUPS = {
    "60": { label: "1H", barMin: 60, htfMin: 240, settings: { mode: "Balanced", swing: "Large", sessions: "All day", minRR: 1.2, slBuffer: 0.5 } },
    "30": { label: "30m", barMin: 30, htfMin: 60, settings: { mode: "Balanced", swing: "Large", sessions: "New York only", minRR: 1.2, slBuffer: 0.5 } }
  };

  /* run(bars, trend, settings, opts)
   * bars: [{t, o, h, l, c}] closed candles; trend: [1/-1/0]; opts.allowed: optional [bool] (session filter);
   * opts.london / opts.newyork: optional [bool] for the quality score.
   * Returns signals, the areas after the last candle and the SETUPS diagnostics. */
  function run(bars, trend, s, opts) {
    s = Object.assign({}, DEFAULTS, s || {});
    opts = opts || {};
    var L = s.pivot || SWING[s.swing] || 10;
    var atr = atrSeries(bars, 14);
    var res = [], sup = [], demand = [], supply = [], signals = [];
    var stats = { setups: 0, weak: 0, trend: 0, busy: 0, session: 0, target: 0, traded: 0 };
    var trade = null, lastSkip = null, need = POINTS_NEEDED[s.mode];
    for (var i = 0; i < bars.length; i++) {
      var b = bars[i], a = i > 0 ? atr[i - 1] : null;
      if (a === null || !(a > 0) || i <= 2 * L + 14) continue;
      var timeExit = false;
      if (trade) {
        var st = tradeStep(trade, b, i - trade.bar, s.maxBars);
        if (st) {
          timeExit = st.how === "Time exit";
          trade.exitBar = i; trade.result = st.r; trade.how = st.how; trade.exitPrice =
            st.how === "Stop loss" ? trade.sl : st.how === "Take profit" ? trade.tp : b.c;
          trade = null;
        }
      }
      var tol = TOUCH_ATR * a;
      var dHits = demand.filter(function (z) { return z.top > z.bot && b.l <= z.top + tol && b.c > z.top; });
      var sHits = supply.filter(function (z) { return z.top > z.bot && b.h >= z.bot - tol && b.c < z.bot; });
      var supHits = sup.filter(function (x) { return b.l <= x.p + tol && b.c > x.p; }).map(function (x) { return x.p; });
      var resHits = res.filter(function (x) { return b.h >= x.p - tol && b.c < x.p; }).map(function (x) { return x.p; });
      var buyScore = 2 * (dHits.length > 0) + (supHits.length > 0);
      var sellScore = 2 * (sHits.length > 0) + (resHits.length > 0);
      var buyRej = bullRejection(b), sellRej = bearRejection(b);
      var buyRaw = buyRej && buyScore >= need && trend[i] > 0;
      var sellRaw = sellRej && sellScore >= need && trend[i] < 0;
      var canOpen = !trade && !timeExit;
      var inSession = !opts.allowed || opts.allowed[i];
      [[buyRej, buyScore, trend[i] > 0, 1], [sellRej, sellScore, trend[i] < 0, -1]].forEach(function (x) {
        if (x[0] && x[1] >= 1) {
          stats.setups++;
          var why = null;
          if (x[1] < need) { stats.weak++; why = "area too weak for " + s.mode; }
          else if (!x[2]) { stats.trend++; why = "against the 4H trend"; }
          else if (!canOpen) { stats.busy++; why = "a trade is already open"; }
          else if (!inSession) { stats.session++; why = "outside " + s.sessions; }
          if (why) lastSkip = { bar: i, side: x[3], why: why };
        }
      });
      var buy = buyRaw && !sellRaw && canOpen && inSession;
      var sell = sellRaw && !buyRaw && canOpen && inSession;
      if (buy || sell) {
        var side = buy ? 1 : -1, entry = b.c, sl, nearest, hits, lvl;
        if (buy) {
          var structure = Math.min.apply(null, [b.l].concat(dHits.map(function (z) { return z.bot; }), supHits));
          sl = Math.min(structure - s.slBuffer * a, entry - s.minRisk * a);
          var above = res.filter(function (x) { return x.p > entry; }).map(function (x) { return x.p; })
            .concat(supply.filter(function (z) { return z.bot > entry; }).map(function (z) { return z.bot; }));
          nearest = above.length ? Math.min.apply(null, above) : null;
          hits = dHits; lvl = supHits;
        } else {
          var structureS = Math.max.apply(null, [b.h].concat(sHits.map(function (z) { return z.top; }), resHits));
          sl = Math.max(structureS + s.slBuffer * a, entry + s.minRisk * a);
          var below = sup.filter(function (x) { return x.p < entry; }).map(function (x) { return x.p; })
            .concat(demand.filter(function (z) { return z.top < entry; }).map(function (z) { return z.top; }));
          nearest = below.length ? Math.max.apply(null, below) : null;
          hits = sHits; lvl = resHits;
        }
        var tp = target(side, entry, sl, nearest, s.minRR);
        if (tp === null) {
          stats.target++;
          lastSkip = { bar: i, side: side, why: "target only " + (Math.abs(nearest - entry) / Math.abs(entry - sl)).toFixed(1) + "R away" };
        } else {
          stats.traded++;
          var zoneHit = hits.length > 0, levelHit = lvl.length > 0;
          var fresh = hits.some(function (z) { return z.touch === 0; });
          var rr = Math.abs(tp - entry) / Math.abs(entry - sl);
          var ln = opts.london ? opts.london[i] : false, ny = opts.newyork ? opts.newyork[i] : false;
          var q = quality(zoneHit, levelHit, fresh, rr, ln, ny);
          var names = buy ? [["Demand", zoneHit], ["Support", levelHit]] : [["Supply", zoneHit], ["Resistance", levelHit]];
          var why = names.filter(function (x) { return x[1]; }).map(function (x) { return x[0]; }).join(" ");
          trade = { bar: i, t: b.t, side: side, score: buy ? buyScore : sellScore, why: why + (zoneHit && fresh ? " (fresh)" : ""),
            entry: entry, sl: sl, tp: tp, rr: rr, quality: q, grade: grade(q), exitBar: null, result: null, how: null };
          signals.push(trade);
        }
      }
      // ---- update areas with this closed candle
      var merge = MERGE_ATR * a;
      demand.forEach(function (z) { if (b.l <= z.top + tol) z.touch++; });
      supply.forEach(function (z) { if (b.h >= z.bot - tol) z.touch++; });
      demand = demand.filter(function (z) { return !(b.c < z.bot); });
      supply = supply.filter(function (z) { return !(b.c > z.top); });
      var toSup = res.filter(function (x) { return b.c > x.p; }), toRes = sup.filter(function (x) { return b.c < x.p; });
      res = res.filter(function (x) { return !(b.c > x.p); });
      sup = sup.filter(function (x) { return !(b.c < x.p); });
      for (var u = toSup.length - 1; u >= 0; u--) addLevel(sup, toSup[u].p, toSup[u].bar, merge, s.cap);
      for (var v = toRes.length - 1; v >= 0; v--) addLevel(res, toRes[v].p, toRes[v].bar, merge, s.cap);
      var pb = bars[i - 1];
      if (b.c - b.o >= s.impulse * a && b.c > pb.h) {
        var bot = Math.min(pb.l, b.l), top = Math.max(pb.o, pb.c);
        if (top - bot < 0.2 * a) top = bot + 0.2 * a;
        if (top - bot <= 2 * a && top < b.c) addZone(demand, top, bot, i - 1, s.cap);
      }
      if (b.o - b.c >= s.impulse * a && b.c < pb.l) {
        var top2 = Math.max(pb.h, b.h), bot2 = Math.min(pb.o, pb.c);
        if (top2 - bot2 < 0.2 * a) bot2 = top2 - 0.2 * a;
        if (top2 - bot2 <= 2 * a && bot2 > b.c) addZone(supply, top2, bot2, i - 1, s.cap);
      }
      var k = i - L, hiK = bars[k].h, loK = bars[k].l, isPH = true, isPL = true;
      for (var m = k - L; m <= i; m++) {
        if (bars[m].h > hiK || (m < k && bars[m].h >= hiK)) isPH = false;
        if (bars[m].l < loK || (m < k && bars[m].l <= loK)) isPL = false;
      }
      if (isPH) addLevel(b.c < hiK ? res : sup, hiK, k, merge, s.cap);
      if (isPL) addLevel(b.c > loK ? sup : res, loK, k, merge, s.cap);
    }
    return { signals: signals, open: trade, demand: demand, supply: supply, res: res, sup: sup, stats: stats,
      lastSkip: lastSkip, atr: atr[bars.length - 1], settings: s };
  }

  function record(signals, filter) {
    var done = signals.filter(function (x) { return x.result !== null && (!filter || filter(x)); });
    var wins = done.filter(function (x) { return x.result > 0; }).length;
    var total = done.reduce(function (acc, x) { return acc + x.result; }, 0);
    var gain = done.filter(function (x) { return x.result > 0; }).reduce(function (acc, x) { return acc + x.result; }, 0);
    var loss = -done.filter(function (x) { return x.result < 0; }).reduce(function (acc, x) { return acc + x.result; }, 0);
    var n = done.length;
    return { n: n, wins: wins, winPct: n ? 100 * wins / n : 0, avg: n ? total / n : 0, total: total,
      pf: loss > 0 ? gain / loss : (gain > 0 ? Infinity : 0) };
  }

  var api = { DEFAULTS: DEFAULTS, SWING: SWING, POINTS_NEEDED: POINTS_NEEDED, atrSeries: atrSeries, target: target,
    tradeStep: tradeStep, quality: quality, grade: grade, lots: lots, inLondon: inLondon, inNewYork: inNewYork,
    goldMarketOpen: goldMarketOpen, build4H: build4H, buildHTF: buildHTF, trend4H: trend4H, trendHTF: trendHTF, SETUPS: SETUPS, run: run, record: record, localParts: localParts };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.Aurum = api;
})(typeof window !== "undefined" ? window : this);
