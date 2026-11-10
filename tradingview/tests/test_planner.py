"""Execute simple planner expressions extracted from Pine, not its series engine."""
from pathlib import Path
import math
import re
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "AurumEntryPlanner.pine").read_text(encoding="utf-8")


def top_level_mark(text, symbol):
    quote = None
    depth = 0
    for i, c in enumerate(text):
        if quote:
            if c == quote and (i == 0 or text[i-1] != "\\"):
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == symbol and depth == 0:
            return i
    return -1


def ternary(text):
    """The source functions use right-associative flat ternaries only."""
    pos = top_level_mark(text, "?")
    if pos < 0:
        return text
    tail = text[pos+1:]
    end = top_level_mark(tail, ":")
    assert end >= 0
    return f"({ternary(tail[:end])} if {text[:pos]} else {ternary(tail[end+1:])})"


def evaluate(text, context):
    return eval(ternary(text), {"__builtins__": {}}, context)


def run_function(name, context):
    body = re.search(rf"^{name}\([^\n]+=>\n((?:    [^\n]+\n)+)", SOURCE, re.M).group(1)
    context = context.copy()
    lines = body.splitlines()
    for line in lines[:-1]:
        declaration = re.fullmatch(r"    bool (\w+) = (.+)", line)
        assert declaration is not None
        context[declaration[1]] = evaluate(declaration[2], context)
    return evaluate(lines[-1].strip(), context)


def geometry(**changes):
    context = dict(high=105., low=102., priorATR=4., entryBufferATR=.05,
                   structureLow=100., structureHigh=110., stopBufferATR=.15,
                   minimumRiskATR=.75, maximumRiskATR=3., target1R=1., target2R=2.,
                   dataReady=True, syminfo=SimpleNamespace(mintick=.01),
                   math=SimpleNamespace(ceil=math.ceil, floor=math.floor, min=min, max=max),
                   na=lambda value: value is None)
    context.update(changes)
    for name in ("f_up", "f_down"):
        formula = re.search(rf"^{name}\(float price\) => (.+)$", SOURCE, re.M)[1]
        context[name] = lambda price, formula=formula: evaluate(formula, dict(context, price=price))
    for name in ("nextBuyEntry", "nextSellEntry", "nextBuyStop", "nextSellStop", "buyRisk", "sellRisk", "nextBuyT1", "nextBuyT2", "nextSellT1", "nextSellT2", "buyRiskOK", "sellRiskOK"):
        code = re.search(rf"^(?:float|bool) {name} = (.+)$", SOURCE, re.M)[1]
        context[name] = evaluate(code, context)
    return context


class PlannerTests(unittest.TestCase):
    def pending(self, direction=1, o=99., h=99.5, l=98., e=100., s=95., gap=.5):
        return run_function("f_pending_event", dict(direction=direction, o=o, h=h, l=l, e=e, s=s, gap=gap))

    def observed(self, direction=1, h=105., l=98., s=95., t2=110.):
        return run_function("f_observed_event", dict(direction=direction, h=h, l=l, s=s, t2=t2))

    def test_pending_without_touch(self):
        self.assertEqual(self.pending(), "PENDING")

    def test_buy_entry_touch(self):
        self.assertEqual(self.pending(h=101), "TRIGGER OBSERVED")

    def test_sell_entry_touch(self):
        self.assertEqual(self.pending(direction=-1, o=101, h=102, l=99, s=105), "TRIGGER OBSERVED")

    def test_stop_before_buy_entry(self):
        self.assertEqual(self.pending(l=94), "INVALID: stop before entry")

    def test_entry_stop_same_bar_ambiguous(self):
        self.assertEqual(self.pending(h=101, l=94), "AMBIGUOUS: entry + stop")

    def test_sell_entry_stop_ambiguous(self):
        self.assertEqual(self.pending(direction=-1, o=101, h=106, l=99, s=105), "AMBIGUOUS: entry + stop")

    def test_gap_beyond_buy_entry_rejected(self):
        self.assertEqual(self.pending(o=101, h=102, l=100), "MISSED: opening gap")

    def test_gap_boundary_inclusive(self):
        self.assertEqual(self.pending(o=100.5, h=102, l=100), "TRIGGER OBSERVED")

    def test_sell_gap_rejected(self):
        self.assertEqual(self.pending(direction=-1, o=99, h=100, l=98, s=105), "MISSED: opening gap")

    def test_stop_and_target_two_ambiguous(self):
        self.assertEqual(self.observed(h=112, l=94), "AMBIGUOUS: stop + TP2")

    def test_stop_observed(self):
        self.assertEqual(self.observed(l=95), "STOP LEVEL OBSERVED")

    def test_target_two_observed(self):
        self.assertEqual(self.observed(h=110), "TP2 LEVEL OBSERVED")

    def test_sell_target_two_observed(self):
        self.assertEqual(self.observed(direction=-1, h=102, l=90, s=105, t2=90), "TP2 LEVEL OBSERVED")

    def test_no_terminal_touch(self):
        self.assertEqual(self.observed(), "TRIGGER OBSERVED")

    def test_plan_price_order(self):
        g = geometry()
        self.assertLess(g["nextBuyStop"], g["nextBuyEntry"])
        self.assertLess(g["nextBuyEntry"], g["nextBuyT1"])
        self.assertLess(g["nextBuyT1"], g["nextBuyT2"])
        self.assertGreater(g["nextSellStop"], g["nextSellEntry"])
        self.assertGreater(g["nextSellEntry"], g["nextSellT1"])
        self.assertGreater(g["nextSellT1"], g["nextSellT2"])

    def test_tick_aligned(self):
        for tick in (.001, .01, .1):
            g = geometry(syminfo=SimpleNamespace(mintick=tick))
            for key in ("nextBuyEntry", "nextSellEntry", "nextBuyStop", "nextSellStop", "nextBuyT1", "nextBuyT2"):
                self.assertAlmostEqual(g[key] / tick, round(g[key] / tick), places=7)

    def test_entry_is_outside_signal(self):
        g = geometry(entryBufferATR=0)
        self.assertGreater(g["nextBuyEntry"], g["high"])
        self.assertLess(g["nextSellEntry"], g["low"])

    def test_risk_cap_blocks_wide_structure(self):
        g = geometry(structureLow=80)
        self.assertFalse(g["buyRiskOK"])

    def test_no_data_blocks_plan(self):
        g = geometry(dataReady=False)
        self.assertFalse(g["buyRiskOK"])
        self.assertFalse(g["sellRiskOK"])

    def test_stop_enforces_minimum_distance(self):
        g = geometry(structureLow=104.9)
        self.assertGreaterEqual(g["buyRisk"] + 1e-9, g["minimumRiskATR"] * g["priorATR"])

    def test_plan_does_not_start_on_signal_bar(self):
        self.assertIn("if planState == 1 and bar_index > planBar", SOURCE)

    def test_expiry_and_tracking_bounds_are_explicit(self):
        self.assertIn("bar_index - planBar > entryExpiry", SOURCE)
        self.assertIn("bar_index - triggerBar >= observationBars", SOURCE)

    def test_current_plan_not_replaced(self):
        self.assertIn("buySignal and buyRiskOK and buyRoomOK and not busyAtStart", SOURCE)
        self.assertIn("sellSignal and sellRiskOK and sellRoomOK and not busyAtStart", SOURCE)

    def test_empty_line_array_is_guarded(self):
        self.assertIn("if showPlan and array.size(levelLines) > 0", SOURCE)


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PlannerTests))
    summary = f"{result.testsRun} planner-expression/contract tests; {len(result.failures)} failures; {len(result.errors)} errors.\nNot a Pine compiler or TradingView runtime test.\n"
    (ROOT / "tests/planner-v3-results.txt").write_text(summary, encoding="utf-8")
    raise SystemExit(not result.wasSuccessful())
