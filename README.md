# Aurum Gold Indicator

**Work in progress — demo research only.** XAUUSD confirmation indicators for MetaTrader 5 and TradingView. This repository preserves the unfinished project, source, tests and known limitations. It does not contain a validated profitable trading strategy and does not place orders.

## Current versions

| Platform | Current source | Status |
| --- | --- | --- |
| MT5 | [`mt5/AurumConfirmation.mq5`](mt5/AurumConfirmation.mq5) + [`AurumCore.mqh`](mt5/AurumCore.mqh) | v3 (SNR + SND); core tests pass; MetaEditor compile and demo testing outstanding |
| TradingView | [`tradingview/AurumSignalAudit.pine`](tradingview/AurumSignalAudit.pine) | v5 (SNR + SND, replaces v4); model/contract tests pass; Pine Editor compile and demo testing outstanding |

Earlier TradingView sources are retained for comparison: basic indicator, multi-timeframe v2 and entry-planner v3. Install only the version you intend to use, rather than all of them on one chart.

## Features (TradingView v5 and MT5 v3 share the same rules)

- **SNR:** support and resistance from confirmed swing points, merged when close together, flipped when broken.
- **SND:** supply and demand zones from strong impulse candles, removed when price closes through them.
- **Signals:** higher-timeframe trend + confluence points (zone 2, S/R 1) + rejection candle. Modes: Aggressive / Balanced / Strict.
- **Trade levels:** Entry, Stop loss, TP1 (next opposite area) and TP2 (the area after it) for every signal, plus a simple info panel and alerts.
- Any timeframe, few settings, closed-candle signals that do not repaint.

How it works and how to read the chart: [`tradingview/V5-GUIDE.md`](tradingview/V5-GUIDE.md).

## Installation

### MT5

1. In desktop MT5 select **File > Open Data Folder > MQL5 > Indicators** and create an `Aurum` folder.
2. Copy `mt5/AurumConfirmation.mq5` and `mt5/AurumCore.mqh` into that folder.
3. Open the `.mq5` in MetaEditor and press **F7** to generate the `.ex5`. Compiled files are deliberately excluded from Git.
4. Refresh Navigator and attach to the broker's gold/USD demo chart. Any timeframe works (M5 or H1 recommended).
5. Optionally load `mt5/presets/Scalping-M5.set` or `Longer-Trades-H1.set` through Inputs > Load.

See [`mt5/README.md`](mt5/README.md) for rules, spread units, push setup and acceptance checks. Its release-package instructions refer to separately built binaries; this repository is source-only. Build scripts require a fresh local compilation/log before packaging.

### TradingView v5

1. Copy the full contents of `tradingview/AurumSignalAudit.pine`.
2. In TradingView open **Pine Editor**, create a new indicator, replace the template, **Save**, then **Add to chart**.
3. Remove earlier Aurum versions from that chart. Any timeframe works; 5m, 15m and 1h are good starting points.
4. For alerts choose **Any alert() function call** to get Entry/SL/TP in the message.

See [`tradingview/V5-GUIDE.md`](tradingview/V5-GUIDE.md). Older files (`AurumConfirmation.pine`, `AurumMultiTimeframe.pine`, `AurumEntryPlanner.pine`) are kept only for reference.

## Tests

Requires Python 3. Run from the repository root:

```powershell
python tradingview/tests/test_v5.py
```

This runs 16 source-contract and reference-model tests (`tradingview/tests/model_v5.py` mirrors the rules). It is **not** a Pine compiler or TradingView engine test and cannot demonstrate profitability.

For the MT5 decision core, open an x64 Native Tools Command Prompt for Visual Studio and run:

```bat
mt5\tests\run-tests.cmd
```

On Linux/macOS: `g++ -std=c++17 -DAURUM_TEST_MAIN mt5/tests/core_tests.cpp -o core_tests && ./core_tests`. The harness compiles the shared `AurumCore.mqh` as C++; the recorded run passed 71 checks. This does not test MT5 event integration or a strategy's performance.

## Remaining work

- Compile v5 in TradingView Pine Editor and v3 in MetaEditor; fix any compiler diagnostics.
- Check zones, S/R and signals visually with Bar Replay and a live demo feed in all three modes.
- Compare TradingView and MT5 signals on the same candles (feeds differ, so small differences are expected).
- Verify alerts and phone push end-to-end.
- Evaluate costs, slippage, expectancy and drawdown with recorded demo trades; no performance claim exists.

## Data and credentials

No broker login, MetaQuotes ID, API token, account journal, private screenshot or unrelated project is included. MT5 journals created by a running installation can include account identifiers in their filenames; keep them out of Git. TradingView feed prices/spreads can differ from MT5 broker quotes.

No open-source license has been selected yet. This private repository is an unfinished project backup.
