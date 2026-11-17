# Aurum Gold — backtest results and demo plan

**Short version:** on 10 years of real XAUUSD data, the Aurum rules made a **small profit on the 1H chart** with the recommended settings (profit factor about 1.2 after spread), and **lost money on 15m with every setting tested**. The recommended settings are now the defaults. Next step: a demo account, not real money.

## Recommended settings (now the defaults)

| Setting | Value |
| --- | --- |
| **Chart** | **XAUUSD 1H** (the panel shows ⚠ on other timeframes) |
| Signal mode | Balanced |
| Trading sessions | All day |
| Swing size | Large |
| Trend timeframe | auto (4H) |
| Minimum reward | 1.2 |
| Stop-loss buffer | 0.5 ATR |
| Risk per trade | 1% (0.5% while learning is fine) |

MT5: load `mt5/presets/Recommended-H1.set` on an H1 chart.

## Results (real XAUUSD, May 2012 – March 2022, 0.30 spread taken off every trade)

R = the amount risked on a trade. With 1% risk, +1R ≈ +1% of the balance.

| Period | Trades | Win % | Profit factor | Total | Worst drawdown |
| --- | --- | --- | --- | --- | --- |
| 2012–2015 *(not used to choose settings)* | 85 | 41% | 1.15 | +7.8R | −10.0R |
| 2016–2019 *(settings chosen here)* | 97 | 45% | 1.21 | +11.8R | −10.0R |
| 2020–2022 *(not used to choose settings)* | 56 | 39% | 1.16 | +5.3R | −6.2R |
| **All** | **239** | **43%** | **1.19** | **+26.9R** | **−11.6R** |

By year: 2012 +0.9 · 2013 +3.6 · 2014 −0.9 · 2015 +4.1 · 2016 +3.0 · 2017 +9.4 · 2018 −1.4 · 2019 +0.7 · 2020 +1.9 · 2021 +6.7 · 2022 (2 months) −1.4

With a 0.50 spread instead of 0.30: profit factor 1.13, +19.0R.

### What did not work

| Settings | Profit factor | Total |
| --- | --- | --- |
| Old defaults: 15m, London + New York, swing Normal, stop buffer 0.2, reward 1.5 | 0.80 | −89.1R |
| 1H but the old tight stop buffer (0.2) | 0.89 | −23.6R |
| 1H, Aggressive mode | 0.87 | −125.7R |
| 15m: best of 879 combinations | 0.99 | about break-even |

Lessons: gold's 15m noise hits zone stops too often; a stop buffer of 0.5 ATR matters; only real supply/demand zones (Balanced) carry an edge.

### How it was tested (so the numbers can be trusted, and checked)

- **Data:** XAUUSD M15/H1/H4 from the public [ejtraderLabs historical-data](https://github.com/ejtraderLabs/historical-data) repository. Server time = New York + 7 h, converted to UTC for the sessions.
- **Rules:** `tradingview/tests/model.py`, the reference model of the same rules as the TradingView script and `mt5/AurumCore.mqh` (tests keep them in line): one trade at a time, entry at the signal candle close, a candle touching stop and target counts as a loss, 100-candle time limit.
- **Avoiding a lucky result:** about 1,700 setting combinations were tried on **2016–2019 only**. The best were then checked on **2012–2015 and 2020–2022**, which they had never seen. The recommended settings stayed profitable in both, and neighbouring settings did too.
- **Rerun it:** see [`backtest/README.md`](backtest/README.md).

### Limits — read before trading

- The edge is **small**: about +0.11R per trade, ~2 trades a month, ~+2–3% a year at 1% risk, with losing years and a worst drawdown of about −12R.
- The data ends in **March 2022**. Gold has behaved differently since (much higher prices and volatility). Check recent results in the TradingView Strategy Tester on the 1H chart before trusting it.
- Past results do not guarantee future results. Slippage and news spikes are not included.

## Demo plan (before real money)

1. **TradingView:** paste `AurumSignalAudit.pine`, open **XAUUSD 1H** (OANDA), keep the defaults. Check the Strategy Tester on recent data: profit factor above 1.0 with 20+ trades is a good sign.
2. **Alerts:** create an alert → condition *Aurum v6* → **alert() function calls only** → notify in app.
3. **Demo account** (MT5 demo, or TradingView paper trading) for **at least 2 months or 20 trades**, whichever is later.
4. Take **every** signal with the panel's entry, stop, target and lot size. No skipping, no moving the stop.
5. Write each trade in a journal:

| Date | BUY/SELL | Grade | Entry | SL | TP | Result (R) | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

6. **After 20 trades**, compare your journal with the panel's RECORD:
   - Profit factor above 1.0 and results close to the RECORD → move to real money with **small** risk (0.5%).
   - Clearly worse than the RECORD → find out why (spread, late entries, skipped trades) before going further.
   - Losing → stop and review; do not increase risk to "win it back".
7. Check **BY GRADE**: if grade C keeps losing, trade only A and B.
