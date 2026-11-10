"""v4 regressions plus previous source-expression suites.

Executes selected source expressions and lifecycle reference models, NOT Pine.
"""
from pathlib import Path
import unittest
import test_setups_v3
import test_planner

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "AurumSignalAudit.pine").read_text(encoding="utf-8")
test_setups_v3.SOURCE = SOURCE
test_planner.SOURCE = SOURCE


def setup_plot(side, *, confirmed, qualifies, visible=True, busy=False):
    signal_name = "buySignal" if side == 1 else "sellSignal"
    raw_name = "rawBuy" if side == 1 else "rawSell"
    signal = test_setups_v3.expression(signal_name, {
        "barstate": type("State", (), {"isconfirmed": confirmed})(),
        raw_name: qualifies, "quietOK": True})
    title = 'title="BUY setup confirmed"' if side == 1 else 'title="SELL setup confirmed"'
    statement = next(line for line in SOURCE.splitlines() if line.startswith("plotshape(") and title in line)
    condition = statement[len("plotshape("):].split(", title=")[0]
    return bool(eval(condition, {"__builtins__": {}}, {
        "showSignals": visible, signal_name: signal,
        "busyAtStart": busy, "planState": 2 if busy else 0}))


def lifecycle_model(events, expiry=3):
    """Replay fixture models pending expiry; markers use source-derived expressions."""
    state, created, accepted, markers = 0, None, [], []
    for index, event in enumerate(events):
        busy = state == 1
        if state == 1 and index - created >= expiry:
            state = 3
        marker = setup_plot(1, confirmed=event["closed"], qualifies=event["setup"], busy=busy)
        if marker:
            markers.append(index)
        if marker and not busy:
            state, created = 1, index
            accepted.append(index)
    return markers, accepted


class SignalAuditTests(unittest.TestCase):
    def test_confirmed_buy_visible_with_existing_plan(self):
        self.assertTrue(setup_plot(1, confirmed=True, qualifies=True, busy=True))

    def test_confirmed_sell_visible_with_existing_plan(self):
        self.assertTrue(setup_plot(-1, confirmed=True, qualifies=True, busy=True))

    def test_open_candle_cannot_emit_temporary_setup(self):
        for qualifies in (False, True, False, True):
            self.assertFalse(setup_plot(1, confirmed=False, qualifies=qualifies))

    def test_close_locks_in_marker_in_reference_replay(self):
        events = [dict(closed=True, setup=x) for x in (False, True, False, False, True)]
        once = lifecycle_model(events)[0]
        for end in range(1, len(events) + 1):
            prefix = lifecycle_model(events[:end])[0]
            self.assertEqual(prefix, [x for x in once if x < end])

    def test_plan_suppression_not_setup_suppression(self):
        events = [dict(closed=True, setup=x) for x in (True, True, False, True, True)]
        markers, plans = lifecycle_model(events)
        self.assertEqual(markers, [0, 1, 3, 4])
        self.assertEqual(plans, [0, 4])

    def test_hide_display_does_not_modify_underlying_signal(self):
        self.assertFalse(setup_plot(1, confirmed=True, qualifies=True, visible=False))
        self.assertTrue(test_setups_v3.expression("buySignal", {
            "barstate": type("State", (), {"isconfirmed": True})(),
            "rawBuy": True, "quietOK": True}))

    def test_finished_price_display_is_explicitly_opt_in(self):
        self.assertIn('input.bool(false, "Keep finished plan price references"', SOURCE)
        self.assertIn("bool displayPrices = activePlan or showFinishedPlan", SOURCE)

    def test_no_active_plan_is_not_old_sell_instruction(self):
        self.assertIn('string directionText = activePlan ? (planDirection == 1 ? "BUY" : "SELL") : "NO ACTIVE PLAN"', SOURCE)

    def test_deleted_drawings_are_not_setup_plotshapes(self):
        self.assertNotIn("plotshape(showSignals and newBuyPlan", SOURCE)
        self.assertIn('plotshape(showSignals and buySignal, title="BUY setup confirmed"', SOURCE)
        self.assertNotIn("offset=-", SOURCE)
        self.assertNotIn("varip", SOURCE)

    def test_closed_higher_timeframe_requests_preserved(self):
        self.assertEqual(SOURCE.count("[close[1], ta.ema(close, trendLength)[1], bar_index[1]]"), 2)
        self.assertEqual(SOURCE.count("lookahead=barmerge.lookahead_on"), 2)

    def test_audit_and_alert_stages_are_distinct(self):
        for title in ("Aurum BUY setup confirmed", "Aurum BUY plan", "Aurum entry level observed"):
            self.assertIn(f'title="{title}"', SOURCE)
        for name in ("Confirmed Setup: BUY=1 SELL=-1", "Accepted Plan: BUY=1 SELL=-1", "Entry Touch: BUY=1 SELL=-1"):
            self.assertIn(f'"{name}", display=display.data_window', SOURCE)

    def test_last_setup_is_independent_of_plan_creation(self):
        self.assertIn('if buySignal or sellSignal\n    lastSetupTime := time_close', SOURCE)


if __name__ == "__main__":
    suite = unittest.TestSuite()
    loader = unittest.defaultTestLoader
    for test_class in (test_setups_v3.SourceRuleTests, test_setups_v3.RetestModelTests,
                       test_planner.PlannerTests, SignalAuditTests):
        suite.addTests(loader.loadTestsFromTestCase(test_class))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = f"{result.testsRun} source-expression/contract/model tests; {len(result.failures)} failures; {len(result.errors)} errors.\nNot a Pine compiler, series-engine or broker test.\n"
    (ROOT / "tests/audit-v4-results.txt").write_text(summary, encoding="utf-8")
    raise SystemExit(not result.wasSuccessful())
