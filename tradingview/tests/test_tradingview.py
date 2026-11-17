"""Aurum v6 tests: source contracts for AurumSignalAudit.pine + reference-model behaviour.

Run from the repository root:  python tradingview/tests/test_tradingview.py
This is NOT a Pine compiler or TradingView engine test. Compile in Pine Editor as well.
"""
from pathlib import Path
import random
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import POINTS_NEEDED, Settings, grade, lots, quality, record, run, target, trade_step  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PINE = (ROOT / "tradingview" / "AurumSignalAudit.pine").read_text(encoding="utf-8")

CORE = (ROOT / "mt5" / "AurumCore.mqh").read_text(encoding="utf-8")
MQ5 = (ROOT / "mt5" / "AurumConfirmation.mq5").read_text(encoding="utf-8")
EA = (ROOT / "mt5" / "AurumEA.mq5").read_text(encoding="utf-8")


def calm(n, price=2650.0):
    """Sideways candles with ~2.0 range, alternating colour."""
    bars = []
    for i in range(n):
        o = price + (0.4 if i % 2 else -0.4)
        c = price - (0.4 if i % 2 else -0.4)
        bars.append((o, max(o, c) + 0.6, min(o, c) - 0.6, c))
    return bars


def demand_scenario():
    bars = calm(40)
    bars.append((2650.4, 2650.8, 2649.0, 2649.6))   # base candle (bearish)
    bars.append((2649.6, 2659.0, 2649.4, 2658.6))   # impulse: body 9 >> 1.5 x ATR, closes above base high
    bars += [(2658.6, 2661.0, 2658.0, 2660.5), (2660.5, 2662.0, 2659.5, 2661.5), (2661.5, 2662.2, 2658.0, 2658.5),
             (2658.5, 2659.0, 2655.0, 2655.5), (2655.5, 2656.0, 2652.5, 2653.0)]
    bars.append((2653.0, 2654.5, 2650.2, 2654.0))   # dips into demand (top 2650.4), closes above, bullish
    return bars


def mirror(bars, pivot=5300.0):
    return [(pivot - o, pivot - l, pivot - h, pivot - c) for o, h, l, c in bars]


def random_bars(seed, n=2500):
    r = random.Random(seed)
    p, bars, drift = 2650.0, [], 0.0
    for i in range(n):
        if i % 300 == 0:
            drift = r.choice([-0.4, 0.4])
        o = p
        c = o + drift + r.gauss(0, 3)
        if r.random() < 0.03:
            c = o + r.choice([-1, 1]) * r.uniform(8, 15)
        h = max(o, c) + abs(r.gauss(0, 1.5))
        l = min(o, c) - abs(r.gauss(0, 1.5))
        bars.append((o, h, l, c))
        p = c
    ema, trend = None, []
    for _, _, _, c in bars:
        ema = c if ema is None else ema + (c - ema) * 2 / 201
        trend.append(1 if c > ema else -1)
    return bars, trend


class PineContract(unittest.TestCase):
    def test_version_and_title(self):
        self.assertTrue(PINE.startswith("//@version=6"))
        self.assertIn('strategy("Aurum Gold v6', PINE)

    def test_signals_only_on_closed_candles(self):
        self.assertIn("if barstate.isconfirmed and ready\n    float tol", PINE)
        self.assertIn("alert.freq_once_per_bar_close", PINE)

    def test_htf_uses_completed_candle(self):
        line = next(x for x in PINE.splitlines() if "request.security(" in x)
        self.assertIn("close[1]", line)
        self.assertIn("ta.ema(close, 200)[1]", line)
        self.assertIn("barmerge.lookahead_on", line)

    def test_modes_and_points_match_core(self):
        self.assertIn('modeInput == "Strict" ? 3 : modeInput == "Aggressive" ? 1 : 2', PINE)
        self.assertIn("(inDemand ? 2 : 0) + (atSupport ? 1 : 0)\n", PINE)
        self.assertIn("(zone?2:0)+(level?1:0);", CORE)
        self.assertIn("mode==AURUM_STRICT?3:mode==AURUM_AGGRESSIVE?1:2", CORE)
        self.assertEqual(POINTS_NEEDED, {"Aggressive": 1, "Balanced": 2, "Strict": 3})

    def test_constants_match_core(self):
        for pine, core in (("TOUCH_ATR = 0.2", "TOUCH_ATR 0.2"), ("MERGE_ATR = 0.3", "MERGE_ATR 0.3")):
            self.assertIn(pine, PINE)
            self.assertIn(core, MQ5)

    def test_no_fibonacci_left(self):
        for source in (PINE, CORE, MQ5):
            self.assertNotIn("fib", source.lower())

    def test_defaults_match_mt5(self):
        for name, value in (("impulseATR", "1.5"), ("slBufferATR", "0.5"), ("minRiskATR", "0.5"), ("maxItems", "4"), ("minRR", "1.2")):
            self.assertRegex(PINE, rf"{name} = input\.(float|int)\({re.escape(value)},")
        for name, value in (("ImpulseATR", "1.5"), ("SLBufferATR", "0.5"), ("MinRiskATR", "0.5"), ("MaxItems", "4"), ("MinReward", "1.2")):
            self.assertRegex(MQ5, rf"input (double|int)\s+{name}={re.escape(value)};")

    def test_empty_array_loops_are_guarded(self):
        # Pine counts DOWN when end < start, so "size - 1 to 0" needs a size > 0 guard.
        lines = PINE.splitlines()
        for i, line in enumerate(lines):
            if re.search(r"for i = array\.size\((\w+)\) - 1 to 0", line):
                name = re.search(r"array\.size\((\w+)\)", line).group(1)
                self.assertIn(f"if array.size({name}) > 0", lines[i - 1], line)

    def test_tested_defaults(self):
        # Defaults = settings that held up in the 10-year real-data test (BACKTEST-RESULTS.md)
        self.assertIn('string modeInput = input.string("Balanced"', PINE)
        self.assertIn('string sessionInput = input.string("All day"', PINE)
        self.assertIn('string swingInput = input.string("Large"', PINE)
        self.assertIn("Sessions=SESSIONS_ALL;", MQ5)
        self.assertIn("SwingSize=SWING_LARGE;", MQ5)
        defaults = Settings()
        self.assertEqual((defaults.mode, defaults.pivot, defaults.sl_buffer, defaults.min_rr), ("Balanced", 10, 0.5, 1.2))

    def test_inputs_are_few(self):
        self.assertLessEqual(PINE.count("= input."), 18)

    def test_trade_rules_match_core(self):
        # Target: cap max(3, minRR), fallback max(2, minRR); stop loss checked before target
        self.assertIn("math.min(rr, math.max(3.0, minRR))", PINE)
        self.assertIn("math.max(2.0, minRR)", PINE)
        self.assertIn("AurumMin(rr,AurumMax(3.0,minRR))", CORE)
        self.assertIn("AurumMax(2.0,minRR)", CORE)
        self.assertLess(PINE.index("if slHit\n        closedR := -1.0"), PINE.index("else if tpHit"))
        self.assertLess(CORE.index("if(stopHit)"), CORE.index("if(targetHit)"))
        self.assertIn("and canOpen    // one trade at a time", PINE)

    def test_panel_has_status_and_record(self):
        for text in ('"BUY NOW"', '"SELL NOW"', '"WAIT"', '"RECORD"', '"RR · LOT"', '"TAKE PROFIT"', '"SETUPS"', '"SESSION"', '"QUALITY"', '"WIN CHANCE"', '"BLOCKED BY"', '"BY GRADE"'):
            self.assertIn(text, PINE)


class AllInOneContract(unittest.TestCase):
    """One script = panel + signals + Strategy Tester (TradingView Basic allows one saved script)."""

    def test_is_a_strategy(self):
        self.assertTrue(PINE.startswith("//@version=6\nstrategy("))
        # calc_on_every_tick: without it a strategy skips the forming candle, so the panel
        # (drawn on barstate.islast) is missing while the market is open
        for setting in ("process_orders_on_close=true", "calc_on_every_tick=true", "pyramiding=0", "commission_value=0.15", "initial_capital=1000"):
            self.assertIn(setting, PINE)
        self.assertNotIn("alertcondition(", PINE)   # not allowed in strategies
        self.assertFalse((ROOT / "tradingview" / "AurumStrategy.pine").exists())

    def test_orders_follow_the_panel(self):
        self.assertIn("stop=newSL, limit=newTP", PINE)
        self.assertIn('strategy.close_all(comment="Time exit")', PINE)
        self.assertIn('bool canOpen = not inTrade and not (not na(closedR) and lastHow == "Time exit")', PINE)
        self.assertIn("timeExitNow=!slHit && !tpHit;", MQ5)
        self.assertLess(PINE.index("strategy.entry("), PINE.index("alert(\"Aurum \""))

    def test_sessions(self):
        self.assertIn('time(timeframe.period, "0800-1700:23456", "Europe/London")', PINE)
        self.assertIn('time(timeframe.period, "0800-1700:23456", "America/New_York")', PINE)
        self.assertIn("tfSec < 14400", PINE)
        self.assertIn("sessions==AURUM_SESSIONS_ALL", CORE)


class EAContract(unittest.TestCase):
    """AurumEA.mq5 must trade exactly the indicator's signals, safely."""

    def test_reads_the_indicator_buffers(self):
        for idx, name in ((2, "SigDir"), (3, "SigSL"), (4, "SigTP"), (5, "SigGrade")):
            self.assertIn(f"SetIndexBuffer({idx},{name},INDICATOR_CALCULATIONS)", MQ5)
            self.assertIn(f"CopyBuffer(handle,{idx},1,1,", EA)   # shift 1 = the candle that just closed
        self.assertIn("#property indicator_buffers 6", MQ5)
        self.assertIn("SigDir[i]=dir; SigSL[i]=stop; SigTP[i]=tp; SigGrade[i]=tGrade;", MQ5)
        self.assertIn('#define INDICATOR_PATH "Aurum\\\\AurumConfirmation"', EA)

    def test_safety_defaults(self):
        self.assertIn("input bool        DemoOnly=true;", EA)
        self.assertIn("input double      RiskPercent=1.0;", EA)
        self.assertIn("RiskPercent>5", EA)                      # refuses more than 5% risk
        self.assertIn("if(open) { Report(side+\" signal skipped: an Aurum trade is already open\")", EA)
        self.assertIn("if(!tester) lastBar=iTime(_Symbol,_Period,0);", EA)   # no stale signal at start
        self.assertIn("AurumLots(riskMoney,entry,stop,MoneyPerPricePerLot(),step,minLot)", EA)

    def test_time_limit_matches_indicator(self):
        self.assertIn("input int         MaxTradeBars=100;", EA)
        self.assertIn("input int    MaxTradeBars=100;", MQ5)


class ModelBehaviour(unittest.TestCase):
    def test_demand_pullback_gives_buy(self):
        bars = demand_scenario()
        sig = run(bars, [1] * len(bars))
        self.assertTrue(sig, "expected a BUY")
        last = sig[-1]
        self.assertEqual((last.bar, last.side), (len(bars) - 1, 1))
        self.assertIn("Demand", last.why)
        self.assertGreaterEqual(last.score, 2)
        self.assertTrue(last.sl < 2649.0 < last.entry < last.tp)
        self.assertGreaterEqual((last.tp - last.entry) / (last.entry - last.sl), 1.2)

    def test_supply_pullback_gives_sell(self):
        bars = mirror(demand_scenario())
        sig = run(bars, [-1] * len(bars))
        self.assertTrue(sig)
        last = sig[-1]
        self.assertEqual((last.bar, last.side), (len(bars) - 1, -1))
        self.assertIn("Supply", last.why)
        self.assertTrue(last.sl > last.entry > last.tp)

    def test_trend_blocks_counter_signals(self):
        bars = demand_scenario()
        self.assertFalse([s for s in run(bars, [-1] * len(bars)) if s.side > 0])
        self.assertFalse(run(bars, [0] * len(bars)))

    def test_strict_needs_more_than_a_zone(self):
        bars = demand_scenario()
        self.assertFalse([s for s in run(bars, [1] * len(bars), Settings(mode="Strict")) if s.bar == len(bars) - 1])

    def test_signals_never_repaint(self):
        bars, trend = random_bars(7, 900)
        full = [(s.bar, s.side) for s in run(bars, trend)]
        for end in range(300, 900, 97):
            part = [(s.bar, s.side) for s in run(bars[:end], trend[:end])]
            self.assertEqual(part, [x for x in full if x[0] < end])

    def test_levels_are_ordered(self):
        for seed in range(4):
            bars, trend = random_bars(seed)
            for mode in POINTS_NEEDED:
                for s in run(bars, trend, Settings(mode=mode)):
                    if s.side > 0:
                        self.assertTrue(s.sl < s.entry < s.tp, s)
                    else:
                        self.assertTrue(s.sl > s.entry > s.tp, s)
                    rr = abs(s.tp - s.entry) / abs(s.entry - s.sl)
                    self.assertTrue(1.2 - 1e-9 <= rr <= 3 + 1e-9, rr)

    def test_mode_frequency(self):
        counts = {}
        for mode in POINTS_NEEDED:
            counts[mode] = sum(len(run(*random_bars(seed), Settings(mode=mode))) for seed in range(4))
        self.assertGreater(counts["Aggressive"], counts["Balanced"])
        self.assertGreater(counts["Balanced"], counts["Strict"])
        self.assertGreater(counts["Strict"], 0)
        per_1000 = counts["Balanced"] / (4 * 2.5)
        self.assertTrue(2 <= per_1000 <= 40, per_1000)

    def test_one_trade_at_a_time(self):
        for seed in range(3):
            sig = run(*random_bars(seed), Settings(mode="Aggressive"))
            for a, b in zip(sig, sig[1:]):
                self.assertIsNotNone(a.exit_bar)
                self.assertGreaterEqual(b.bar, a.exit_bar)

    def test_every_trade_gets_a_result(self):
        sig = run(*random_bars(1), Settings(mode="Aggressive"))
        for s in sig[:-1]:
            self.assertTrue(s.result == -1.0 or s.result > 0 or s.exit_bar - s.bar >= 100, s)
        n, wins, pct, avg, total = record(sig)
        self.assertEqual(n, sum(1 for s in sig if s.result is not None))
        self.assertAlmostEqual(avg * n, total)

    def test_session_mask_blocks_new_trades(self):
        bars, trend = random_bars(3)
        everything = run(bars, trend, Settings(mode="Aggressive"))
        allowed = [(i // 60) % 24 >= 8 for i in range(len(bars))]   # pretend 1 candle = 1 minute
        filtered = run(bars, trend, Settings(mode="Aggressive"), allowed=allowed)
        self.assertTrue(all(allowed[x.bar] for x in filtered))
        self.assertLess(len(filtered), len(everything))
        self.assertEqual(run(bars, trend, allowed=[False] * len(bars)), [])

    def test_setup_diagnostics_add_up(self):
        for mode in POINTS_NEEDED:
            bars, trend = random_bars(5)
            allowed = [(i // 60) % 24 >= 8 for i in range(len(bars))]
            stats = {}
            sig = run(bars, trend, Settings(mode=mode), allowed=allowed, stats=stats)
            parts = ("weak", "trend", "busy", "session", "target", "traded")
            self.assertEqual(sum(stats[k] for k in parts), stats["setups"], (mode, stats))
            self.assertEqual(stats["traded"], len(sig))
            if mode == "Aggressive":
                self.assertEqual(stats["weak"], 0)   # 1 point is always enough
        self.assertEqual(run(*random_bars(5), stats=stats), run(*random_bars(5)))   # counting changes nothing

    def test_min_reward_filter(self):
        counts = [len(run(*random_bars(2), Settings(mode="Aggressive", min_rr=m))) for m in (1.0, 2.0, 3.0)]
        self.assertGreaterEqual(counts[0], counts[1])
        self.assertGreaterEqual(counts[1], counts[2])


class TradeRules(unittest.TestCase):
    """Same cases as mt5/tests/core_tests.cpp, so both platforms follow one rule book."""

    def test_target(self):
        self.assertAlmostEqual(target(1, 2650, 2645, 2660, 1.5), 2660)
        self.assertIsNone(target(1, 2650, 2645, 2656, 1.5))
        self.assertAlmostEqual(target(1, 2650, 2645, 2690, 1.5), 2665)
        self.assertAlmostEqual(target(1, 2650, 2645, None, 1.5), 2660)
        self.assertAlmostEqual(target(1, 2650, 2645, None, 2.5), 2662.5)
        self.assertAlmostEqual(target(-1, 2650, 2655, 2640, 1.5), 2640)
        self.assertIsNone(target(-1, 2650, 2655, 2645, 1.5))

    def test_trade_step(self):
        self.assertIsNone(trade_step(1, 2650, 2645, 2660, (2650, 2655, 2647, 2652), 1, 100))
        self.assertAlmostEqual(trade_step(1, 2650, 2645, 2660, (2652, 2661, 2650, 2658), 2, 100), 2.0)
        self.assertEqual(trade_step(1, 2650, 2645, 2660, (2648, 2649, 2644, 2646), 2, 100), -1.0)
        self.assertEqual(trade_step(1, 2650, 2645, 2660, (2650, 2662, 2644, 2655), 2, 100), -1.0)
        self.assertAlmostEqual(trade_step(1, 2650, 2645, 2660, (2650, 2653, 2648, 2652.5), 100, 100), 0.5)
        self.assertAlmostEqual(trade_step(-1, 2650, 2655, 2640, (2645, 2646, 2639, 2641), 3, 100), 2.0)

    def test_quality(self):
        self.assertEqual(quality(True, True, True, 2.5, True, True), 100)
        self.assertEqual(quality(True, False, True, 2.0, False, True), 77)
        self.assertEqual(quality(True, False, False, 1.5, True, False), 49)
        self.assertEqual(quality(False, True, True, 3.0, True, True), 55)
        self.assertEqual(quality(False, True, False, 1.2, False, False), 15)
        self.assertEqual([grade(q) for q in (100, 70, 69, 50, 49)], ["A", "A", "B", "B", "C"])

    def test_quality_formula_matches_pine(self):
        for line in ("int q = zoneHit and levelHit ? 35 : zoneHit ? 25 : levelHit ? 10 : 0",
                     "q += zoneHit and fresh ? 20 : 0",
                     "q += rr >= 2.5 ? 25 : rr >= 2.0 ? 20 : rr >= 1.5 ? 12 : 5",
                     "q += inLondon and inNewYork ? 20 : inLondon or inNewYork ? 12 : 0",
                     "newGrade := q >= 70 ? 0 : q >= 50 ? 1 : 2"):
            self.assertIn(line, PINE)
        self.assertIn("int q=(zone && level)?35:zone?25:level?10:0;", CORE)
        self.assertIn("return quality>=70?0:quality>=50?1:2;", CORE)
        # zone freshness is tracked alongside every zone array
        for arr in ("dTouch", "sTouch"):
            self.assertIn(arr, PINE)
            self.assertIn(arr, MQ5)

    def test_lots(self):
        self.assertAlmostEqual(lots(1000, 1, 2650, 2645), 0.02)
        self.assertAlmostEqual(lots(10000, 1, 2650, 2647), 0.33)
        self.assertEqual(lots(100, 1, 2650, 2645), 0)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    total = result.testsRun
    summary = (f"{total} v6 contract/model tests; {len(result.failures)} failures; {len(result.errors)} errors.\n"
               "Not a Pine compiler or TradingView runtime test.\n")
    (Path(__file__).resolve().parent / "test-results.txt").write_text(summary, encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
