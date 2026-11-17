"""Step 2: backtest the Aurum rules on real XAUUSD data and print a report.

Uses tradingview/tests/model.py, the reference model that follows the same rules as
AurumSignalAudit.pine and mt5/AurumCore.mqh (one trade at a time, SL checked before TP,
the same zones, levels, trend, sessions and targets).

Usage (from the repository root, after prepare_data.py):
    python backtest/run_backtest.py                      # recommended settings, report per period
    python backtest/run_backtest.py --tf 15 --mode Aggressive --sessions LN --swing 5 --buffer 0.2 --rr 1.5
    python backtest/run_backtest.py --grid               # try many settings on 2016-2019, check the best on unseen years

Results are in R (1R = the amount risked). A 0.30 spread is subtracted from every trade.
"""
import argparse
import itertools
import os
import pickle
import sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tradingview", "tests"))
from model import Settings, run  # noqa: E402

SWING = {"Small": 3, "Normal": 5, "Large": 10}
SESSIONS = {"ALL": "All day", "LN": "London + New York", "L": "London only", "N": "New York only"}
PERIODS = [(2012, 2015), (2016, 2019), (2020, 2022)]
DATA = None


def load(path):
    global DATA
    DATA = pickle.load(open(path, "rb"))


def evaluate(tf=60, years=(2012, 2022), mode="Balanced", trend="h4", sessions="ALL", swing=10,
             buffer=0.5, rr=1.2, min_risk=0.5, spread=0.30):
    d = DATA[tf]
    idx = [i for i, t in enumerate(d["time"]) if years[0] <= t.year <= years[1]]
    a, b = idx[0], idx[-1] + 1
    lon, ny = d["london"][a:b], d["newyork"][a:b]
    allowed = None if sessions == "ALL" else [x or y for x, y in zip(lon, ny)] if sessions == "LN" else lon if sessions == "L" else ny
    stats = {}
    sig = run(d["bars"][a:b], d["trend_" + trend][a:b],
              Settings(mode=mode, pivot=swing, sl_buffer=buffer, min_rr=rr, min_risk=min_risk),
              allowed=allowed, stats=stats)
    closed = [s for s in sig if s.result is not None]
    res = [s.result - spread / abs(s.entry - s.sl) for s in closed]
    out = dict(n=len(res), stats=stats)
    if not res:
        return out
    wins = sum(r > 0 for r in res)
    gain, loss = sum(r for r in res if r > 0), -sum(r for r in res if r < 0)
    equity = peak = drawdown = 0.0
    for r in res:
        equity += r
        peak = max(peak, equity)
        drawdown = max(drawdown, peak - equity)
    by_year = {}
    for s, r in zip(closed, res):
        y = d["time"][a + s.bar].year
        by_year[y] = by_year.get(y, 0) + r
    out.update(win=100 * wins / len(res), avg=sum(res) / len(res), total=sum(res),
               pf=gain / loss if loss else float("inf"), dd=drawdown, by_year=by_year)
    return out


def line(r):
    if not r["n"]:
        return "no trades"
    return f"{r['n']:4d} trades  win {r['win']:3.0f}%  PF {r['pf']:4.2f}  avg {r['avg']:+.2f}R  total {r['total']:+7.1f}R  max drawdown {r['dd']:5.1f}R"


def report(kw):
    print("Settings:", f"{kw['tf']}m chart" if kw["tf"] < 60 else "1H chart", "|", kw["mode"], "|", SESSIONS[kw["sessions"]],
          "| swing", kw["swing"], "| stop buffer", kw["buffer"], "| minimum reward", kw["rr"], "| trend", kw["trend"].upper())
    for p in PERIODS:
        print(f"  {p[0]}-{p[1]}: " + line(evaluate(years=p, **kw)))
    r = evaluate(years=(2012, 2022), **kw)
    print("  ALL      : " + line(r))
    if r["n"]:
        print("  by year  : " + "  ".join(f"{y}:{v:+.1f}" for y, v in sorted(r["by_year"].items())))
    st = r["stats"]
    print("  setups   :", st["setups"], "| blocked by: weak area", st["weak"], "trend", st["trend"], "session", st["session"],
          "target", st["target"], "trade open", st["busy"], "| traded", st["traded"])


def grid_job(p):
    tf, mode, sessions, swing, buffer, rr = p
    kw = dict(tf=tf, mode=mode, trend="h4", sessions=sessions, swing=swing, buffer=buffer, rr=rr)
    r = evaluate(years=PERIODS[1], **kw)
    r.pop("stats"), r.pop("by_year", None)
    return kw, r


def grid(tf, workers):
    combos = list(itertools.product([tf], ["Aggressive", "Balanced", "Strict"], list(SESSIONS), [3, 5, 10],
                                    [0.2, 0.5, 1.0], [1.2, 1.5, 2.0, 2.5]))
    with Pool(workers, initializer=load, initargs=(ARGS.data,)) as pool:
        results = pool.map(grid_job, combos, chunksize=4)
    good = sorted([x for x in results if x[1]["n"] >= (80 if tf == 60 else 150)], key=lambda x: -x[1]["pf"])
    print(f"{len(results)} settings tried on 2016-2019; {sum(r['pf'] > 1 for _, r in good)} profitable with enough trades.")
    print("Best 10 on 2016-2019, then checked on the unseen periods 2012-2015 and 2020-2022:")
    for kw, r in good[:10]:
        a = evaluate(years=PERIODS[0], **kw)
        c = evaluate(years=PERIODS[2], **kw)
        ok = a.get("pf", 0) > 1 and c.get("pf", 0) > 1
        print(("  KEEPS WORKING " if ok else "  fails later   "), {k: v for k, v in kw.items() if k not in ("tf", "trend")},
              f"PF 2016-19 {r['pf']:.2f} | 2012-15 {a.get('pf', 0):.2f} | 2020-22 {c.get('pf', 0):.2f}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.join(HERE, "gold.pkl"))
    ap.add_argument("--tf", type=int, default=60, choices=[15, 60], help="chart timeframe in minutes")
    ap.add_argument("--mode", default="Balanced", choices=["Aggressive", "Balanced", "Strict"])
    ap.add_argument("--sessions", default="ALL", choices=list(SESSIONS))
    ap.add_argument("--swing", type=int, default=10, choices=[3, 5, 10])
    ap.add_argument("--buffer", type=float, default=0.5, help="stop-loss buffer (ATR x)")
    ap.add_argument("--rr", type=float, default=1.2, help="minimum reward (x risk)")
    ap.add_argument("--trend", default="h4", choices=["h1", "h4"])
    ap.add_argument("--grid", action="store_true")
    ap.add_argument("--workers", type=int, default=os.cpu_count())
    ARGS = ap.parse_args()
    load(ARGS.data)
    if ARGS.grid:
        grid(ARGS.tf, ARGS.workers)
    else:
        if ARGS.tf == 60 and ARGS.trend == "h1":
            sys.exit("On the 1H chart the trend comes from 4H (--trend h4).")
        report(dict(tf=ARGS.tf, mode=ARGS.mode, trend=ARGS.trend, sessions=ARGS.sessions, swing=ARGS.swing, buffer=ARGS.buffer, rr=ARGS.rr))
