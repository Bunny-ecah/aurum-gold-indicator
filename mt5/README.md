# Aurum Confirmation for MT5 — v2.00

A gold/USD entry-confirmation companion for a desktop MT5 demo account. It uses the chart's actual broker symbol and prices, plots closed-candle BUY/SELL arrows and two EMAs, and displays a checklist and alert status. It does not place or manage orders. The rules are a testable baseline, not a proven profitable strategy.

## Install or upgrade

1. Remove the old Aurum instance from your chart before replacing files.
2. In desktop MT5 choose **File > Open Data Folder > MQL5 > Indicators**. Create an **Aurum** folder.
3. Copy **AurumConfirmation.ex5**, **AurumConfirmation.mq5** and **AurumCore.mqh** into that same folder. The compiled `.ex5` runs independently, but the `.mqh` must remain beside `.mq5` when rebuilding.
4. In Navigator right-click **Indicators > Refresh**, or restart MT5. Check the indicator name says **Aurum v2**.
5. Log into your broker's demo account and open its gold/USD chart. Symbols may be XAUUSD, GOLD, or have suffixes. Confirm the instrument's contract and quote currency in Symbol Specification. No broker names are hardcoded.
6. Set the chart timeframe BEFORE attaching the indicator:

| Mode | Entry chart | Trend timeframe | Preset |
| --- | --- | --- | --- |
| SCALPING | M5 | M15 | presets/Scalping-M5.set |
| LONGER_TRADES (default) | H1 | H4 | presets/Longer-Trades-H1.set |

7. Drag Aurum onto the chart. In **Inputs > Load**, optionally load the matching `.set`. Incorrect chart/mode combinations are rejected, with the reason in **Toolbox > Experts**.
8. Allow entry and higher-timeframe history to download. If the panel waits, open the trend chart temporarily and scroll back to load additional history. The higher-timeframe EMA needs at least 210 completed candles plus the history required for older signals.

To change mode, remove Aurum, set the new chart timeframe and attach again with the matching preset. Inputs remain editable. The presets are baseline configurations, not broker-optimized recommendations. Use one Aurum instance per chart; use only one alert-enabled copy for each broker/symbol/mode to avoid duplicate notifications across charts.

For source compilation, open `.mq5` in MetaEditor and press F7. No DLL, WebRequest, external account, library installation or trading permission is needed to run the indicator. The test DLL under `tests` is only a developer harness; the indicator never loads it.

## What confirms an entry?

All four conditions must align in the same direction on the **completed entry candle**:

| Confirmation | BUY | SELL |
| --- | --- | --- |
| Higher-timeframe trend | Last available completed trend candle closes above EMA 200 | Closes below EMA 200 |
| Entry EMA alignment | EMA 20 > EMA 50, and entry candle closes above EMA 20 | EMA 20 < EMA 50, and close is below EMA 20 |
| RSI 14 momentum | 55 to 70 inclusive | 30 to 45 inclusive |
| Breakout close | Close is strictly above the highest high of the preceding 5 candles | Close is strictly below the lowest low of the preceding 5 candles |

Touching a range boundary is not a breakout. Wicks alone do not count. The signal candle is excluded from the preceding-five-candle range. `BreakoutBufferATR` can optionally require extra breakout distance, measured against the previous candle's ATR; its default is zero. This version does not implement breakout-retest or order-block detection.

Additional gates must pass:

- **Candle direction:** BUY requires close > open; SELL requires close < open. Enabled by default with `RequireDirectionalCandle=true`.
- **Historical spread:** must be within `MaxSpreadPrice`. Unknown zero spread is rejected by default. Negative values are always blocked. If your broker supplies zero historical spread, investigate before deliberately setting `RejectZeroHistoricalSpread=false`; that weakens the historical cost check.
- **ATR bounds:** optional `MinATRPrice` / `MaxATRPrice`, in quoted price units. Zero disables the corresponding bound.
- **Unusually large candle:** high-low range cannot exceed `MaxCandleATR` times the **preceding completed candle's ATR 14**. Default 2.0. The signal candle cannot inflate its own range allowance.
- **Quiet period:** a signal requires the preceding `CooldownBars` candles to contain no raw candidate in either direction. A raw candidate means all four confirmations and spread/ATR/range/direction gates pass, before cooldown. Default 3; zero disables this filter. A continuous cluster produces one initial signal, then none until three candidate-free candles have passed. This is intentionally stricter than the old “three bars since accepted signal” behavior.
- **Data:** required OHLC and indicator values must be valid; higher-timeframe EMA warmup and cooldown history must be available. Older missing trend data does not block a valid recent signal.

Both trade modes use the same periods and thresholds on different timeframes. “Longer trades” supports both BUY and SELL; it does not mean buy-only. A 4/4 checklist is a rule count, not an estimated win rate. A setup can still lose.

### Prices, spread and broker differences

`MaxSpreadPrice=0.50` means **ask - bid <= 0.50 in the instrument's quoted price**, not pips or points. For example, bid 2650.00 / ask 2650.35 gives a 0.35 spread. If `_Point=0.01`, the cap is 50 points; if `_Point=0.001`, it is 500 points. Historical MT5 spread points are converted with the chart symbol's `_Point`.

Review Symbol Specification and actual spreads separately for each JustMarkets, Orca and VersusTrade demo account. The indicator does not certify or identify broker contracts. The 0.50 default is a demo starting value, not a claim that it suits any of these brokers. Historical candle spread is not a complete reconstruction of execution costs or slippage. Arrows do not prove that a live alert was delivered or that a trade could be filled at the displayed close.

## What appears on the chart

- Green up-arrow / red down-arrow: accepted BUY / SELL confirmation on a completed candle.
- Gold / gray lines: entry EMA 20 / EMA 50 on completed candles only.
- Panel: BUY and SELL checklists, rule counts, spread/ATR/range and candle gates, quiet-period readiness, current live spread, and the most recent alert status.

The forming candle always has empty indicator buffers. Higher-timeframe selection uses the most recently nominally completed trend candle as of the entry candle's scheduled close, with explicit handling of exact timeframe boundaries and history gaps. There is no use of future higher-timeframe closes.

The quiet-period rule depends only on a fixed number of nearby raw candidates, so sliding the visible `HistoryBars` window does not change shared signals. Missing or revised broker history, revised EMA seeds, or changed inputs can still change reconstructed history. The earliest candles without sufficient trend/cooldown history are omitted. Only the last `HistoryBars` entry candles are plotted.

Panel position/font are configurable. Set `ShowPanel=false` if you prefer only plots. The panel uses uniquely named chart objects and does not overwrite other programs' `Comment()` text. On narrow or short charts, reduce font size, move the panel or hide it. Runtime chart layout has not yet been visually verified.

## Live alerts

`PopupAlerts=true` by default. `SoundAlerts` and `PushNotifications` are off by default.

Live notifications require:

1. A newly observed accepted setup after startup.
2. Connected desktop MT5 and a valid, recent quote (`MaxTickAgeSeconds`, default 30).
3. Current bid/ask spread at or below the price-unit cap.
4. A quote arriving within `MaxAlertDelaySeconds` after the signal candle's scheduled close (default 60).
5. A broker symbol that allows opening positions in the signal direction. Disabled/close-only contracts block notifications; long-only/short-only contracts restrict direction.

No historical notifications are sent on attachment, reinitialization or entry-history rebuild. A failed live gate consumes the bar: it does not queue a late notification. Notifications are attempted once per accepted new candle per instance. No retries or cross-chart duplicate suppression are implemented. The panel reports requested/submitted/failed channels; a successful push API call is not proof that the phone displayed the message. Startup/history signals remain visible without sending notifications.

Broker trade-session calendars and economic-news events are not filtered in this version. Fresh quote and symbol trade-mode checks are not a guarantee of immediate order availability.

### Phone setup

1. In MT5 mobile, locate your **MetaQuotes ID** in Messages settings.
2. In desktop MT5 open **Tools > Options > Notifications**, enable push and enter the ID.
3. Use MT5's **Test** button and verify the phone receives the test.
4. Set `PushNotifications=true` in Aurum Inputs.

Desktop MT5 must remain running and connected. MT5 mobile cannot directly run this custom indicator. Push notifications have terminal-wide rate limits and do not work in Strategy Tester; this indicator disables external alerts and CSV journaling in tester mode. Avoid enabling several copies that could exceed terminal-wide limits.

## Signal journal

`WriteCSVJournal=true` records accepted newly observed live setups, including ones whose delivery was suppressed by live gates. It does not export historical arrows or record manual trades/P&L. Startup signals are not journalled.

Find the CSV in **File > Open Data Folder > MQL5 > Files**. File name includes broker server, account number, symbol, timeframe and chart ID. Columns contain observation time, signal candle's opening time, direction, close, ATR, historical spread in price units and delivery status. All timestamps use broker server time. Journal write failure is logged in Experts and does not stop calculation. Treat CSVs as private because file names include the account number.

## Demo acceptance checklist

1. On H1 load the longer-trade preset; verify **Aurum v2** and the panel after history loads. Repeat M5/scalping on a separate chart.
2. Add MT5 EMA, RSI and ATR tools and manually verify several recent arrows against the exact rules above, including the previous ATR for range gating.
3. Watch a forming candle: no arrow should appear. Verify the signal becomes eligible only after close.
4. Refresh/reload: no historical alert should replay. Compare shared historical arrows before/after changing HistoryBars, ignoring bars omitted because of insufficient warmup.
5. Temporarily set the spread cap below the live spread; verify live status is blocked. Restore a cap chosen from your broker's demo observations.
6. Disconnect MT5 or observe a market break. Verify stale/disconnected status and absence of delayed alerts after reconnecting.
7. Use MT5's notification Test button, then observe a genuine qualifying candle to validate end-to-end indicator delivery. Confirm the CSV distinguishes alert attempts from suppressed delivery.
8. Keep a separate demo trading journal with actual entry, exit, stop, target, costs, slippage and outcomes. Evaluate expectancy/drawdown per broker and mode over a meaningful sample before considering any broader use.

There is no automatic execution, sizing, stop-loss/target generation, news filter, web dashboard or strategy performance report. Those are separate features and require separate validation.

## Validation and developer tests

- MetaEditor compiles the actual MT5 indicator and shared header with **0 errors, 0 warnings**; see `compile.log`.
- **773 checks passed, 0 failures** in `tests/test-results.txt`. These execute the same platform-independent `AurumCore.mqh` used by the indicator, compiled as C++ in a local test harness, not a Python reimplementation.
- Tests cover BUY/SELL conditions, RSI/breakout boundaries, optional filters, invalid values, zero/wide spreads, prior ATR range checks, higher-timeframe close selection, stale quotes, late alerts and cooldown consistency across overlapping windows. Most checks are repeated window comparisons, not 773 independent trading scenarios.
- Re-run from an **x64 Native Tools Command Prompt for Visual Studio** with Python installed: `tests\run-tests.cmd`. Test binaries are generated locally and are not needed to run MT5.
- These tests do **not** exercise MT5's CopyBuffer/history event integration, broker sessions, chart rendering, notification transport or trading profitability. No broker-connected runtime test or performance backtest is claimed. Complete the demo acceptance checklist.

## Official API references

- https://www.mql5.com/en/docs/event_handlers/oncalculate
- https://www.mql5.com/en/docs/series/copybuffer
- https://www.mql5.com/en/docs/series/ibarshift
- https://www.mql5.com/en/docs/network/sendnotification
- https://www.mql5.com/en/docs/dateandtime/timetradeserver
