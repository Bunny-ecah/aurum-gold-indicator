"""The web app's rules engine (docs/aurum.js) must give the same signals as the reference model.

Runs both on synthetic gold-like candles (no data download needed). Needs Node.js; skipped without it.
With backtest/gold.pkl present, also compares on the 10 years of real XAUUSD 1H data.
Run: python tradingview/tests/test_webapp.py
"""
import json, os, pickle, random, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
from model import Settings, run  # noqa: E402

JS = r"""
const A = require(process.argv[2]); const d = JSON.parse(require('fs').readFileSync(process.argv[3]));
const bars = d.bars.map((b, i) => ({ t: i * 3600000, o: b[0], h: b[1], l: b[2], c: b[3] }));
const r = A.run(bars, d.trend, d.s, {});
console.log(JSON.stringify(r.signals.map(s => [s.bar, s.side, s.entry, s.sl, s.tp, s.result])));
"""


def synthetic(n, seed):
    rnd, p, bars, trend = random.Random(seed), 1800.0, [], []
    for i in range(n):
        o = p
        c = o + rnd.gauss(0, 4) + (6 * rnd.choice((-1, 1)) if rnd.random() < 0.05 else 0)
        h, l = max(o, c) + abs(rnd.gauss(0, 2)), min(o, c) - abs(rnd.gauss(0, 2))
        bars.append((o, h, l, c)); p = c
        trend.append(1 if (i // 300) % 2 == 0 else -1)
    return bars, trend


@unittest.skipUnless(shutil.which("node"), "Node.js not installed")
class WebAppParity(unittest.TestCase):
    def compare(self, bars, trend, settings, js_settings):
        expected = [[s.bar, s.side, s.entry, s.sl, s.tp, s.result] for s in run(bars, trend, settings)]
        with tempfile.TemporaryDirectory() as tmp:
            data, script = os.path.join(tmp, "d.json"), os.path.join(tmp, "p.js")
            json.dump({"bars": bars, "trend": trend, "s": js_settings}, open(data, "w"))
            open(script, "w").write(JS)
            out = subprocess.run(["node", script, os.path.abspath(os.path.join(ROOT, "docs", "aurum.js")), data],
                                 capture_output=True, text=True, check=True).stdout
        got = json.loads(out)
        self.assertEqual(len(got), len(expected))
        for g, e in zip(got, expected):
            self.assertEqual(g[:2], e[:2])
            for a, b in zip(g[2:], e[2:]):
                if b is None:
                    self.assertIsNone(a)
                else:
                    self.assertAlmostEqual(a, b, places=6)
        return len(got)

    def test_synthetic_defaults(self):
        bars, trend = synthetic(6000, 1)
        self.assertGreater(self.compare(bars, trend, Settings(), {}), 5)

    def test_synthetic_other_settings(self):
        bars, trend = synthetic(6000, 2)
        self.compare(bars, trend, Settings(mode="Aggressive", pivot=5, sl_buffer=0.2, min_rr=1.5),
                     {"mode": "Aggressive", "swing": "Normal", "slBuffer": 0.2, "minRR": 1.5})

    @unittest.skipUnless(os.path.exists(os.path.join(ROOT, "backtest", "gold.pkl")), "no backtest/gold.pkl")
    def test_real_xauusd_1h(self):
        d = pickle.load(open(os.path.join(ROOT, "backtest", "gold.pkl"), "rb"))[60]
        self.assertEqual(self.compare([list(b) for b in d["bars"]], d["trend_h4"], Settings(), {}), 239)


if __name__ == "__main__":
    unittest.main(verbosity=2)
