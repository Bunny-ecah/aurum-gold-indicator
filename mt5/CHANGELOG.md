# v4.20 + AurumEA 1.00

- New `AurumEA.mq5`: trades the indicator's signals automatically with its stop loss, take profit and risk-% lot size; demo accounts only by default; one trade at a time; spread, stop-distance and minimum-lot checks; 100-candle time exit; grade filter; status on the chart and optional phone notifications; works in the Strategy Tester.
- Indicator: hidden buffers 2-5 (direction, stop loss, take profit, grade) on each signal candle for the EA.
- Defaults are the settings that held up in the 10-year real-data test (H1, Balanced, All day, swing Large, minimum reward 1.2, stop buffer 0.5); single `Recommended-H1.set` preset.

# v4.10

- Trading-session filter: new trades only when the signal candle opens in London (08:00-17:00 London) and/or New York (08:00-17:00 New York), Monday to Friday. Daylight saving handled; checked against the IANA time-zone database. Ignored on H4 and higher.
- Broker server clock detected automatically (UTC+2/+3 brokers follow US summer time); manual `ServerUTCOffset` for the Strategy Tester.
- SESSION row on the panel; skipped setups outside the session shown as a NOTE.
- 114 core checks.

# v4.00

- Big STATUS on the panel: BUY NOW / SELL NOW / IN TRADE / WAIT, with what to wait for next.
- One trade at a time with a single target: the next opposite area (1.5R to 3R), or 2R when there is none. Setups whose target is closer than `MinReward` are skipped and shown as a NOTE.
- Lot size from account balance, `RiskPercent` and the broker tick value.
- Built-in RECORD (backtest of the rules on the scanned history): every signal is followed to TP, SL (a candle touching both = loss) or the time limit; panel shows trades, win %, average R, total R and the last 20.
- Clean chart: only the nearest area above and below price; open trade drawn as risk/reward boxes; result text where each trade ended.
- Removed cooldown, TP2 and several display switches. 82 core checks. Not yet compiled in MetaEditor.

# v3.00

- New signal logic shared with TradingView v5: higher-timeframe trend + Supply/Demand zones (2 points) and Support/Resistance (1 point) + a rejection candle.
- Signal modes: Aggressive (1 point), Balanced (2, default), Strict (3). Replaces the strict 4/4 EMA/RSI/breakout checklist that skipped many moves.
- Draws zones, S/R lines (with role flip) and Entry/SL/TP1/TP2 of the latest signal.
- Works on any timeframe with an automatic trend timeframe; removed the mode/timeframe lock.
- Simpler inputs and panel. Removed the CSV journal.
- New C++ core tests (71 checks). Not yet compiled in MetaEditor.

# v2.00

- Replaced stateful accepted-signal cooldown with fixed-neighborhood candidate quiet-period filtering, making signals independent of the visible history-window boundary.
- Added a platform-independent decision core shared by MT5 and executable C++ regression tests.
- Explicitly handles higher-timeframe close selection at exact boundaries and history gaps.
- Bulk-copies higher-timeframe OHLC and EMA data, checks series readiness, rejects invalid values, and allows incomplete older history without blocking valid recent candles.
- Checks candle range against prior ATR to avoid the signal candle inflating its own allowance.
- Added default directional-candle confirmation and optional ATR breakout margin.
- Rejects unknown zero historical spread by default; retains explicit quoted-price spread units.
- Keeps forming-candle buffers empty even during data-loading retries.
- Replaced chart Comment with independently named panel objects and timer-updated live status.
- Shows alert request/submission/failure separately from setup confirmation.
- Added broker symbol trade-mode gates, tester suppression, a live setup CSV journal, expanded input validation and two loadable mode presets.
- Source and compiled indicator delivered; broker-connected acceptance and performance testing remain outstanding.
