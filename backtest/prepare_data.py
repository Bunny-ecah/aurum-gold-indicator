"""Step 1: turn the ejtraderLabs XAUUSD CSV files into gold.pkl (bars, trend, session flags).

Usage: python backtest/prepare_data.py <folder with XAUUSDm15.csv, XAUUSDh1.csv, XAUUSDh4.csv> [output.pkl]
Server time in these files = New York time + 7 hours (week opens Monday 01:00, daily break 00:00-01:00).
"""
import csv, os, sys, pickle, datetime as dt
from zoneinfo import ZoneInfo
D = sys.argv[1]
NY, LDN, UTC = ZoneInfo("America/New_York"), ZoneInfo("Europe/London"), dt.timezone.utc

def load(name):
    out = []
    with open(f"{D}/{name}") as f:
        r = csv.reader(f); next(r)
        for row in r:
            t = dt.datetime.fromisoformat(row[0])
            out.append((t, float(row[1]) / 100, float(row[2]) / 100, float(row[3]) / 100, float(row[4]) / 100))
    return out

def to_utc(server):            # server clock = New York local time + 7 hours
    return (server - dt.timedelta(hours=7)).replace(tzinfo=NY).astimezone(UTC)

def session_open(utc, tz):
    l = utc.astimezone(tz)
    return l.weekday() < 5 and 8 <= l.hour < 17

def htf_trend(bars, htf, htf_minutes, bar_minutes):
    """For each chart bar: last COMPLETED htf bar at the chart bar's close -> sign(close - EMA200)."""
    ema, k, closes = None, 2 / 201, []
    for t, o, h, l, c in htf:
        ema = c if ema is None else ema + (c - ema) * k
        closes.append((t + dt.timedelta(minutes=htf_minutes), c, ema))
    out, j, cur = [], -1, 0
    for t, *_ in bars:
        decision = t + dt.timedelta(minutes=bar_minutes)
        while j + 1 < len(closes) and closes[j + 1][0] <= decision:
            j += 1
            _, c, e = closes[j]
            cur = (1 if c > e else -1 if c < e else 0) if j >= 210 else 0
        out.append(cur)
    return out

data = {}
for chart, minutes in (("XAUUSDm15.csv", 15), ("XAUUSDh1.csv", 60)):
    bars = load(chart)
    utc = [to_utc(t) for t, *_ in bars]
    entry = {
        "time": [t for t, *_ in bars],
        "bars": [b[1:] for b in bars],
        "london": [session_open(u, LDN) for u in utc],
        "newyork": [session_open(u, NY) for u in utc],
        "trend_h1": htf_trend(bars, load("XAUUSDh1.csv"), 60, minutes) if minutes < 60 else None,
        "trend_h4": htf_trend(bars, load("XAUUSDh4.csv"), 240, minutes),
    }
    data[minutes] = entry
    print(chart, len(bars), bars[0][0], bars[-1][0])
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "gold.pkl")
pickle.dump(data, open(out, "wb"))
print("saved", out)
