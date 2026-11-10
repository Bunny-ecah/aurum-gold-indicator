"""Evaluate selected simple expressions extracted from the Pine source.

These tests check numeric/boolean rule semantics and a retest-window model.
They do not compile Pine or test TradingView's series engine/alert transport.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "AurumEntryPlanner.pine").read_text(encoding="utf-8")


def expression(name, context):
    match = re.search(rf"\b{name} := ([^\n]+)", SOURCE)
    if match is None:
        match = re.search(rf"\bbool {name} = ([^\n]+)", SOURCE)
    if match is None:
        raise AssertionError(f"Missing source expression: {name}")
    code = re.sub(r"\b(\w+)\[(\d+)\]", r"\1_p\2", match[1])
    code = code.replace("math.abs", "abs")
    return bool(eval(code, {"__builtins__": {}, "abs": abs, "na": lambda x: x is None}, context))


def reclaim_context():
    return dict(baseReady=True, fastEMA_p1=100.0, low_p1=99.0,
                close_p1=99.5, fastEMA=100.5, close=102.0, high_p1=101.0,
                high=103.0, low=100.0)


def retest_model(candidates, current_low, current_high, current_close, side, tolerance=0.2, window=3):
    """candidates sorted newest first: (age, level, prior_ATR, intervening closes)."""
    for age, level, previous_atr, closes in sorted(candidates):
        if 1 <= age <= window:
            held = all(c >= level for c in closes) if side == "buy" else all(c <= level for c in closes)
            context = dict(held=held, level=level, tolerance=tolerance * previous_atr,
                           low=current_low, high=current_high, close=current_close)
            return expression("retestBuy" if side == "buy" else "retestSell", context)
    return False


class SourceRuleTests(unittest.TestCase):
    def test_buy_reclaims_ema_and_previous_high(self):
        self.assertTrue(expression("reclaimBuy", reclaim_context()))

    def test_reclaim_touch_is_not_close_break(self):
        c = reclaim_context(); c["close"] = c["high_p1"]
        self.assertFalse(expression("reclaimBuy", c))

    def test_reclaim_requires_previous_close_below_ema(self):
        c = reclaim_context(); c["close_p1"] = 100.1
        self.assertFalse(expression("reclaimBuy", c))

    def test_reclaim_missing_history(self):
        c = reclaim_context(); c["fastEMA_p1"] = None
        self.assertFalse(expression("reclaimBuy", c))

    def test_reclaim_requires_data(self):
        c = reclaim_context(); c["baseReady"] = False
        self.assertFalse(expression("reclaimBuy", c))

    def test_sell_reclaim_mirror(self):
        c = dict(baseReady=True, fastEMA_p1=100, high_p1=101, close_p1=100.5,
                 fastEMA=99.5, close=98, low_p1=99)
        self.assertTrue(expression("reclaimSell", c))

    def test_breakout_at_buffer_boundary_is_not_enough(self):
        c = dict(baseReady=True, close=101, rangeHigh=100, rangeLow=90,
                 breakoutBuffer=0.25, priorATR=4)
        self.assertFalse(expression("breakoutBuy", c))
        c["close"] = 101.01
        self.assertTrue(expression("breakoutBuy", c))

    def test_momentum_needs_expanding_histogram(self):
        c = dict(breakoutBuy=True, macdHistogram=0.3, macdHistogram_p1=0.2,
                 fastEMA=101, fastEMA_p1=100)
        self.assertTrue(expression("momentumBuy", c))
        c["macdHistogram_p1"] = 0.4
        self.assertFalse(expression("momentumBuy", c))

    def test_momentum_needs_ema_slope(self):
        c = dict(breakoutBuy=True, macdHistogram=0.3, macdHistogram_p1=0.2,
                 fastEMA=100, fastEMA_p1=100)
        self.assertFalse(expression("momentumBuy", c))

    def test_sell_momentum_mirror(self):
        c = dict(breakoutSell=True, macdHistogram=-0.3, macdHistogram_p1=-0.2,
                 fastEMA=99, fastEMA_p1=100)
        self.assertTrue(expression("momentumSell", c))

    def test_adx_requires_matching_di_direction(self):
        c = dict(dataReady=True, requireDMI=True, adxValue=25, minADX=22, plusDI=10, minusDI=20)
        self.assertFalse(expression("strengthBuy", c))
        self.assertTrue(expression("strengthSell", c))

    def test_adx_threshold_inclusive(self):
        c = dict(dataReady=True, requireDMI=True, adxValue=22, minADX=22, plusDI=20, minusDI=10)
        self.assertTrue(expression("strengthBuy", c))
        c["adxValue"] = 21.99
        self.assertFalse(expression("strengthBuy", c))

    def test_atr_range_uses_previous_candle(self):
        c = dict(dataReady=True, high=110, low=100, maxRangeATR=2, priorATR=4)
        self.assertFalse(expression("rangeOK", c))
        c["high"] = 108
        self.assertTrue(expression("rangeOK", c))

    def test_extension_blocks_chasing(self):
        c = dict(dataReady=True, limitExtension=True, close=106, fastEMA=100, maxExtension=1.25, priorATR=4)
        self.assertFalse(expression("extensionOK", c))
        c["close"] = 105
        self.assertTrue(expression("extensionOK", c))

    def test_closed_candle_required(self):
        for raw in (False, True):
            self.assertFalse(expression("buySignal", {"barstate": type("State", (), {"isconfirmed": False})(), "rawBuy": raw, "quietOK": True}))

    def test_quiet_filter_blocks_signal(self):
        self.assertFalse(expression("buySignal", {"barstate": type("State", (), {"isconfirmed": True})(), "rawBuy": True, "quietOK": False}))


class RetestModelTests(unittest.TestCase):
    def test_later_buy_retest(self):
        self.assertTrue(retest_model([(1, 100, 4, [])], 100.2, 103, 102, "buy"))

    def test_same_candle_cannot_retest(self):
        self.assertFalse(retest_model([(0, 100, 4, [])], 100, 103, 102, "buy"))

    def test_expired_breakout(self):
        self.assertFalse(retest_model([(4, 100, 4, [])], 100, 103, 102, "buy"))

    def test_intervening_close_invalidates_buy(self):
        self.assertFalse(retest_model([(2, 100, 4, [99.9])], 100, 103, 102, "buy"))

    def test_deep_wick_invalidates_buy(self):
        self.assertFalse(retest_model([(1, 100, 4, [])], 99, 103, 102, "buy"))

    def test_price_must_touch_zone(self):
        self.assertFalse(retest_model([(1, 100, 4, [])], 101, 103, 102, "buy"))

    def test_most_recent_breakout_takes_precedence(self):
        self.assertFalse(retest_model([(1, 102, 4, []), (2, 100, 4, [102])], 100, 103, 101, "buy"))

    def test_sell_retest_mirror(self):
        self.assertTrue(retest_model([(1, 100, 4, [])], 97, 100.2, 98, "sell"))

    def test_sell_invalidated_by_intervening_close(self):
        self.assertFalse(retest_model([(2, 100, 4, [100.1])], 97, 100.2, 98, "sell"))


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(__import__(__name__))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = f"{result.testsRun} rule-expression/model tests; {len(result.failures)} failures; {len(result.errors)} errors.\nNot a Pine compiler or TradingView runtime test.\n"
    (ROOT / "tests/setups-v3-results.txt").write_text(report, encoding="utf-8")
    raise SystemExit(not result.wasSuccessful())
