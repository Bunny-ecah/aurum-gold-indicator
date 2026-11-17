# Aurum Gold Indicator

**Work in progress — demo research only.** XAUUSD confirmation indicators for MetaTrader 5 and TradingView. This repository preserves the unfinished project, source, tests and known limitations. It does not contain a validated profitable trading strategy and does not place orders.

## Current versions

| Platform | Current source | Status |
| --- | --- | --- |
| MT5 | [`mt5/AurumConfirmation.mq5`](mt5/AurumConfirmation.mq5) + [`AurumCore.mqh`](mt5/AurumCore.mqh) | v4.10; core tests pass; MetaEditor compile and demo testing outstanding |
| TradingView | [`tradingview/AurumSignalAudit.pine`](tradingview/AurumSignalAudit.pine) | v6 all-in-one (panel + signals + Strategy Tester in one script); compiles in Pine Editor; demo testing outstanding |

Earlier TradingView sources are retained for comparison: basic indicator, multi-timeframe v2 and entry-planner v3. Install only the version you intend to use, rather than all of them on one chart.

## Features (TradingView v6 and MT5 v4 share the same rules)

- **One clear STATUS:** BUY NOW / SELL NOW / IN TRADE / WAIT, and what to wait for next.
- **Session filter:** new trades only in London and/or New York hours (daylight saving handled).
- **SNR + SND:** support/resistance from swing points and supply/demand zones from strong impulse candles. Only the nearest area above and below price is drawn.
- **Trade plan:** entry, stop loss, take profit, reward-to-risk and **lot size** for your balance and risk %. Setups with too little room to the target are skipped.
- **SETUPS:** counts every reaction at a zone or level and the rule that stopped it, so you can see why there are few signals.
- **RECORD:** every signal is followed to its result, giving win %, average R and total R on the loaded history: a built-in backtest of the rules.
- **All-in-one TradingView script:** the same script also runs in the Strategy Tester (net profit, drawdown, profit factor, with costs), so it needs only one saved script.
- Any timeframe, few settings, closed-candle signals that do not repaint.

How to use it, read the panel and backtest: [`tradingview/GUIDE.md`](tradingview/GUIDE.md).

## Installation

### MT5

1. In desktop MT5 select **File > Open Data Folder > MQL5 > Indicators** and create an `Aurum` folder.
2. Copy `mt5/AurumConfirmation.mq5` and `mt5/AurumCore.mqh` into that folder.
3. Open the `.mq5` in MetaEditor and press **F7** to generate the `.ex5`. Compiled files are deliberately excluded from Git.
4. Refresh Navigator and attach to the broker's gold/USD demo chart. Any timeframe works (M5 or H1 recommended).
5. Optionally load `mt5/presets/Scalping-M5.set` or `Longer-Trades-H1.set` through Inputs > Load.

See [`mt5/README.md`](mt5/README.md) for rules, spread units, push setup and acceptance checks. Its release-package instructions refer to separately built binaries; this repository is source-only. Build scripts require a fresh local compilation/log before packaging.

### TradingView v6

1. Copy the full contents of `tradingview/AurumSignalAudit.pine`.
2. In TradingView open **Pine Editor**, create a new indicator, replace the template, **Save**, then **Add to chart**.
3. Remove earlier Aurum versions from that chart. Any timeframe works; 5m, 15m and 1h are good starting points.
4. Set **Account balance** and **Risk %** in the settings. For alerts choose **alert() function calls only** to get the full trade plan in the message. Open the **Strategy Tester** tab for the backtest report.

See [`tradingview/GUIDE.md`](tradingview/GUIDE.md). Older files (`AurumConfirmation.pine`, `AurumMultiTimeframe.pine`, `AurumEntryPlanner.pine`) are kept only for reference.

## Tests

Requires Python 3. Run from the repository root:

```powershell
python tradingview/tests/test_tradingview.py
```

This runs 29 source-contract, rule and reference-model tests (`tradingview/tests/model.py` mirrors the rules). It is **not** a Pine compiler or TradingView engine test and cannot demonstrate profitability.

For the MT5 decision core, open an x64 Native Tools Command Prompt for Visual Studio and run:

```bat
mt5\tests\run-tests.cmd
```

On Linux/macOS: `g++ -std=c++17 -DAURUM_TEST_MAIN mt5/tests/core_tests.cpp -o core_tests && ./core_tests`. The harness compiles the shared `AurumCore.mqh` as C++; the recorded run passed 114 checks. This does not test MT5 event integration or a strategy's performance.

## Remaining work

- Compile the v6 all-in-one strategy in Pine Editor (the indicator form already compiled and ran) and v4.10 in MetaEditor; fix any compiler diagnostics.
- Check zones, S/R and signals visually with Bar Replay and a live demo feed in all three modes.
- Compare TradingView and MT5 signals on the same candles (feeds differ, so small differences are expected).
- Verify alerts and phone push end-to-end.
- Read the RECORD on several timeframes/modes and backtest with Bar Replay or the MT5 Strategy Tester (see the guide). The record excludes spread and slippage; no performance claim exists.

## Data and credentials

No broker login, MetaQuotes ID, API token, account journal, private screenshot or unrelated project is included. MT5 journals created by a running installation can include account identifiers in their filenames; keep them out of Git. TradingView feed prices/spreads can differ from MT5 broker quotes.

No open-source license has been selected yet. This private repository is an unfinished project backup.
