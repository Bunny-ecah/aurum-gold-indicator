"""Reference model of the Aurum v5 / MT5 v3 rules (SNR + SND + Fibonacci).

Mirrors the per-candle replay used by AurumSignalAudit.pine and AurumConfirmation.mq5:
evaluate the closed candle against EXISTING areas, then update the areas.
This is a model for tests, NOT TradingView's engine.
"""
from dataclasses import dataclass, field

TOUCH_ATR, MERGE_ATR, FIB_NEAR, FIB_FAR = 0.2, 0.3, 0.5, 0.786
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
    cooldown: int = 5
    impulse: float = 1.5
    sl_buffer: float = 0.2
    min_risk: float = 0.5
    cap: int = 4


@dataclass
class Signal:
    bar: int
    side: int
    score: int
    why: str
    entry: float
    sl: float
    tp1: float
    tp2: float


def run(bars, trend, s=Settings()):
    """bars: list of (open, high, low, close); trend: list of 1/-1/0 per bar."""
    atr = atr_series(bars)
    res, sup, demand, supply, signals = [], [], [], [], []
    sw_high = sw_low = sw_high_bar = sw_low_bar = None
    last_buy = last_sell = None
    L = s.pivot
    for i in range(len(bars)):
        o, h, l, c = bars[i]
        a = atr[i - 1] if i > 0 else None
        if a is None or a <= 0 or i <= 2 * L + 14:
            continue
        tol = TOUCH_ATR * a
        d_hits = [z for z in demand if z[0] > z[1] and l <= z[0] + tol and c > z[0]]
        s_hits = [z for z in supply if z[0] > z[1] and h >= z[1] - tol and c < z[1]]
        sup_hits = [p for p, _ in sup if l <= p + tol and c > p]
        res_hits = [p for p, _ in res if h >= p - tol and c < p]
        sw_dir = 0 if sw_high_bar is None or sw_low_bar is None else (1 if sw_high_bar > sw_low_bar else -1)
        swing_ok = sw_dir != 0 and sw_high > sw_low
        size = sw_high - sw_low if swing_ok else None
        fib = (lambda r: sw_high - r * size if sw_dir > 0 else sw_low + r * size) if swing_ok else None
        fib_buy = fib_sell = False
        if swing_ok:
            near, far = fib(FIB_NEAR), fib(FIB_FAR)
            if sw_dir > 0:
                fib_buy = l <= near + tol and l >= far - tol and c > far
            else:
                fib_sell = h >= near - tol and h <= far + tol and c < far
        buy_score = 2 * bool(d_hits) + bool(sup_hits) + fib_buy      # zone counts double
        sell_score = 2 * bool(s_hits) + bool(res_hits) + fib_sell
        need = POINTS_NEEDED[s.mode]
        buy_raw = bull_rejection(o, h, l, c) and buy_score >= need and trend[i] > 0
        sell_raw = bear_rejection(o, h, l, c) and sell_score >= need and trend[i] < 0
        buy = buy_raw and not sell_raw and (last_buy is None or i - last_buy > s.cooldown)
        sell = sell_raw and not buy_raw and (last_sell is None or i - last_sell > s.cooldown)
        if buy or sell:
            entry = c
            if buy:
                structure = min([l] + [z[1] for z in d_hits] + sup_hits + ([fib(FIB_FAR)] if fib_buy else []))
                sl = min(structure - s.sl_buffer * a, entry - s.min_risk * a)
                risk = entry - sl
                cands = [p for p, _ in res if p >= entry + risk] + [z[1] for z in supply if z[1] >= entry + risk]
                if swing_ok and sw_dir > 0 and sw_high >= entry + risk:
                    cands.append(sw_high)
                ext = sw_high + 0.618 * size if swing_ok and sw_dir > 0 else None
                tp1 = min(cands) if cands else entry + 1.5 * risk
                tp2 = ext if ext is not None and ext > tp1 + 0.5 * risk else tp1 + risk
                last_buy = i
                why = " ".join(n for n, f in (("Demand", d_hits), ("Support", sup_hits), ("Fib", fib_buy)) if f)
                signals.append(Signal(i, 1, buy_score, why, entry, sl, tp1, tp2))
            else:
                structure = max([h] + [z[0] for z in s_hits] + res_hits + ([fib(FIB_FAR)] if fib_sell else []))
                sl = max(structure + s.sl_buffer * a, entry + s.min_risk * a)
                risk = sl - entry
                cands = [p for p, _ in sup if p <= entry - risk] + [z[0] for z in demand if z[0] <= entry - risk]
                if swing_ok and sw_dir < 0 and sw_low <= entry - risk:
                    cands.append(sw_low)
                ext = sw_low - 0.618 * size if swing_ok and sw_dir < 0 else None
                tp1 = max(cands) if cands else entry - 1.5 * risk
                tp2 = ext if ext is not None and ext < tp1 - 0.5 * risk else tp1 - risk
                last_sell = i
                why = " ".join(n for n, f in (("Supply", s_hits), ("Resistance", res_hits), ("Fib", fib_sell)) if f)
                signals.append(Signal(i, -1, sell_score, why, entry, sl, tp1, tp2))
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
            sw_high, sw_high_bar = p, k
        if bars[k][2] == min(lows) and all(x > bars[k][2] for x in lows[:L]):
            p = bars[k][2]
            add_level(sup if c > p else res, p, k, merge, s.cap)
            sw_low, sw_low_bar = p, k
    return signals
