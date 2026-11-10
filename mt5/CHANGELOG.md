# v3.00

- New signal logic shared with TradingView v5: higher-timeframe trend + Supply/Demand zones (2 points), Support/Resistance (1 point) and Fibonacci 0.5-0.786 pullbacks (1 point) + a rejection candle.
- Signal modes: Aggressive (1 point), Balanced (2, default), Strict (3). Replaces the strict 4/4 EMA/RSI/breakout checklist that skipped many moves.
- Draws zones, S/R lines (with role flip), latest-swing Fibonacci with 1.618 target, and Entry/SL/TP1/TP2 of the latest signal.
- Works on any timeframe with an automatic trend timeframe; removed the mode/timeframe lock.
- Simpler inputs and panel. Removed the CSV journal.
- New C++ core tests (79 checks). Not yet compiled in MetaEditor.

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
