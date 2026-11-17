"""Reference model of the Aurum v6 (TradingView) / v4 (MT5) rules: SNR + SND, one trade at a time.

Mirrors the per-candle replay used by AurumSignalAudit.pine and AurumConfirmation.mq5:
evaluate the closed candle against EXISTING areas, then update the areas.
This is a model for tests, NOT TradingView's engine.
"""
from dataclasses import dataclass, field

TOUCH_ATR, MERGE_ATR = 0.2, 0.3
POINTS_NEEDED = {"Aggressive": 1, "Balanced": 2, "Strict": 3}


def atr_series(bars, length=14):
    out, prev_close, value = [], None, None
    for i, (o, h, l, c) in enumerate(bars):
        tr = h - l if prev_close is None else max(h - l, abs(h - prev_close), abs(l - prev_close))
        value = tr if value is None else (value * (length - 1) + tr) / length  # RMA
        out.append(value if i >= length else None)
        prev_close = c
    return out


def bull_rejection(o, h, l, c):
    rng = h - l
    return rng > 0 and (c > o or (min(o, c) - l >= 0.5 * rng and c >= l + 0.5 * rng))


def bear_rejection(o, h, l, c):
    rng = h - l
    return rng > 0 and (c < o or (h - max(o, c) >= 0.5 * rng and c <= h - 0.5 * rng))


def add_level(levels, price, bar, tol, cap):
    levels[:] = [x for x in levels if abs(x[0] - price) > tol]
    levels.append((price, bar))
    del levels[:-cap]


def add_zone(zones, top, bot, bar, cap):
    zones[:] = [z for z in zones if not (z[1] <= top and z[0] >= bot)]
    zones.append((top, bot, bar))
    del zones[:-cap]


@dataclass
class Settings:
    mode: str = "Balanced"
    pivot: int = 5
    impulse: float = 1.5
    sl_buffer: float = 0.2
    min_risk: float = 0.5
    cap: int = 4
    min_rr: float = 1.5
    max_bars: int = 100


def target(side, entry, stop, nearest, min_rr):
    """TP = next opposite area (capped at max(3, minRR) R); none -> max(2, minRR) R.
    Returns None when the next opposite area is closer than minRR (trade not worth it)."""
    risk = abs(entry - stop)
    if risk <= 0:
        return None
    if nearest is not None:
        rr = (nearest - entry) / risk * side
        if rr < min_rr:
            return None
        return entry + side * min(rr, max(3.0, min_rr)) * risk
    return entry + side * max(2.0, min_rr) * risk


def trade_step(side, entry, stop, tp, bar, held, max_bars):
    """Follow an open trade for one closed candle. Returns R when it closes, else None.
    SL is checked first: a candle touching both SL and TP counts as a loss."""
    o, h, l, c = bar
    risk = abs(entry - stop)
    if (l <= stop) if side > 0 else (h >= stop):
        return -1.0
    if (h >= tp) if side > 0 else (l <= tp):
        return abs(tp - entry) / risk
    if held >= max_bars:
        return (c - entry) / risk * side
    return None


def lots(balance, risk_pct, entry, stop, contract=100.0, step=0.01):
    raw = balance * risk_pct / 100.0 / (abs(entry - stop) * contract)
    return int(raw / step + 1e-9) * step


@dataclass
class Signal:
    bar: int
    side: int
    score: int
    why: str
    entry: float
    sl: float
    tp: float
    exit_bar: int = None
    result: float = None


def run(bars, trend, s=Settings(), allowed=None):
    """bars: list of (open, high, low, close); trend: list of 1/-1/0 per bar;
    allowed: optional list of bools, False = candle outside the trading session (no new trades)."""
    atr = atr_series(bars)
    res, sup, demand, supply, signals = [], [], [], [], []
    trade = None
    L = s.pivot
    for i in range(len(bars)):
        o, h, l, c = bars[i]
        a = atr[i - 1] if i > 0 else None
        if a is None or a <= 0 or i <= 2 * L + 14:
            continue
        # 0) follow the open trade
        if trade is not None:
            r = trade_step(trade.side, trade.entry, trade.sl, trade.tp, bars[i], i - trade.bar, s.max_bars)
            if r is not None:
                trade.exit_bar, trade.result, trade = i, r, None
        tol = TOUCH_ATR * a
        d_hits = [z for z in demand if z[0] > z[1] and l <= z[0] + tol and c > z[0]]
        s_hits = [z for z in supply if z[0] > z[1] and h >= z[1] - tol and c < z[1]]
        sup_hits = [p for p, _ in sup if l <= p + tol and c > p]
        res_hits = [p for p, _ in res if h >= p - tol and c < p]
        buy_score = 2 * bool(d_hits) + bool(sup_hits)      # zone counts double
        sell_score = 2 * bool(s_hits) + bool(res_hits)
        need = POINTS_NEEDED[s.mode]
        buy_raw = bull_rejection(o, h, l, c) and buy_score >= need and trend[i] > 0
        sell_raw = bear_rejection(o, h, l, c) and sell_score >= need and trend[i] < 0
        in_session = allowed is None or allowed[i]
        buy = buy_raw and not sell_raw and trade is None and in_session     # one trade at a time
        sell = sell_raw and not buy_raw and trade is None and in_session
        if buy or sell:
            entry = c
            if buy:
                structure = min([l] + [z[1] for z in d_hits] + sup_hits)
                sl = min(structure - s.sl_buffer * a, entry - s.min_risk * a)
                above = [p for p, _ in res if p > entry] + [z[1] for z in supply if z[1] > entry]
                tp = target(1, entry, sl, min(above) if above else None, s.min_rr)
                if tp is not None:
                    why = " ".join(n for n, f in (("Demand", d_hits), ("Support", sup_hits)) if f)
                    trade = Signal(i, 1, buy_score, why, entry, sl, tp)
                    signals.append(trade)
            else:
                structure = max([h] + [z[0] for z in s_hits] + res_hits)
                sl = max(structure + s.sl_buffer * a, entry + s.min_risk * a)
                below = [p for p, _ in sup if p < entry] + [z[0] for z in demand if z[0] < entry]
                tp = target(-1, entry, sl, max(below) if below else None, s.min_rr)
                if tp is not None:
                    why = " ".join(n for n, f in (("Supply", s_hits), ("Resistance", res_hits)) if f)
                    trade = Signal(i, -1, sell_score, why, entry, sl, tp)
                    signals.append(trade)
        # --- update areas
        merge = MERGE_ATR * a
        demand[:] = [z for z in demand if not c < z[1]]
        supply[:] = [z for z in supply if not c > z[0]]
        to_sup = [x for x in res if c > x[0]]
        to_res = [x for x in sup if c < x[0]]
        res[:] = [x for x in res if not c > x[0]]
        sup[:] = [x for x in sup if not c < x[0]]
        for p, b in reversed(to_sup):
            add_level(sup, p, b, merge, s.cap)
        for p, b in reversed(to_res):
            add_level(res, p, b, merge, s.cap)
        po, ph_, pl_, pc = bars[i - 1]
        if c - o >= s.impulse * a and c > ph_:
            bot, top = min(pl_, l), max(po, pc)
            top = bot + 0.2 * a if top - bot < 0.2 * a else top
            if top - bot <= 2 * a and top < c:
                add_zone(demand, top, bot, i - 1, s.cap)
        if o - c >= s.impulse * a and c < pl_:
            top, bot = max(ph_, h), min(po, pc)
            bot = top - 0.2 * a if top - bot < 0.2 * a else bot
            if top - bot <= 2 * a and bot > c:
                add_zone(supply, top, bot, i - 1, s.cap)
        k = i - L
        highs = [b[1] for b in bars[k - L:i + 1]]
        lows = [b[2] for b in bars[k - L:i + 1]]
        if bars[k][1] == max(highs) and all(x < bars[k][1] for x in highs[:L]):
            p = bars[k][1]
            add_level(res if c < p else sup, p, k, merge, s.cap)
        if bars[k][2] == min(lows) and all(x > bars[k][2] for x in lows[:L]):
            p = bars[k][2]
            add_level(sup if c > p else res, p, k, merge, s.cap)
    return signals


def record(signals):
    """Closed-trade statistics: (trades, wins, win %, avg R, total R)."""
    done = [x.result for x in signals if x.result is not None]
    wins = sum(1 for r in done if r > 0)
    total = sum(done)
    n = len(done)
    return n, wins, (100.0 * wins / n if n else 0.0), (total / n if n else 0.0), total
