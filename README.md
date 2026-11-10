# Aurum Gold Indicator

**Work in progress — demo research only.** XAUUSD confirmation indicators for MetaTrader 5 and TradingView. This repository preserves the unfinished project, source, tests and known limitations. It does not contain a validated profitable trading strategy and does not place orders.

## Current versions

| Platform | Current source | Status |
| --- | --- | --- |
| MT5 | [`mt5/AurumConfirmation.mq5`](mt5/AurumConfirmation.mq5) + [`AurumCore.mqh`](mt5/AurumCore.mqh) | v2; previously compiled with 0 errors/warnings; broker-connected acceptance testing incomplete |
| TradingView | [`tradingview/AurumSignalAudit.pine`](tradingview/AurumSignalAudit.pine) | v4; local expression/model checks pass; Pine Editor compilation and runtime validation outstanding |

Earlier TradingView sources are retained for comparison: basic indicator, multi-timeframe v2 and entry-planner v3. Install only the version you intend to use, rather than all of them on one chart.

## Features

- MT5: M5/M15 scalping and H1/H4 longer-trade confirmation, EMA/RSI/breakout checks, ATR/spread gates, chart panel and optional notifications.
- TradingView: 1m/5m/15m/30m/1h profiles, confirmed higher-timeframe trend snapshots, setup-specific triggers and optional ADX/DI filters.
- TradingView planner: pending entry, stop and 1R/2R target references, expiry/gap/ambiguity states, with no assumption that a chart touch equals a broker fill.
- TradingView v4: distinct confirmed SETUP labels, accepted PLAN dots and entry TOUCH triangles, plus counts and reasons explaining why an entry plan was blocked.

## Installation

### MT5

1. In desktop MT5 select **File > Open Data Folder > MQL5 > Indicators** and create an `Aurum` folder.
2. Copy `mt5/AurumConfirmation.mq5` and `mt5/AurumCore.mqh` into that folder.
3. Open the `.mq5` in MetaEditor and press **F7** to generate the `.ex5`. Compiled files are deliberately excluded from Git.
4. Refresh Navigator and attach to the broker's gold/USD demo chart. Use M5 with `SCALPING`, or H1 with `LONGER_TRADES`.
5. Optionally load the corresponding file in `mt5/presets` through Inputs > Load.

See [`mt5/README.md`](mt5/README.md) for rules, spread units, push setup and acceptance checks. Its release-package instructions refer to separately built binaries; this repository is source-only. Build scripts require a fresh local compilation/log before packaging.

### TradingView v4

1. Copy the full contents of `tradingview/AurumSignalAudit.pine`.
2. In desktop TradingView open **Pine Editor** from the right toolbar, create a new indicator, replace the template, Save, then Add to chart.
3. Use standard candles and keep `Timeframe profile = Auto chart`. Supported charts: 1m, 5m, 15m, 30m and 1h.
4. Remove earlier Aurum versions from that chart to avoid overlapping panels. Create alerts separately and recreate them after changing the script/timeframe/inputs.

See [`tradingview/V4-NOTES.md`](tradingview/V4-NOTES.md) for current marker semantics and limitations. [`INSTALL-MTF.md`](tradingview/INSTALL-MTF.md) documents inherited profile rules and [`ENTRY-PLANNER-GUIDE.md`](tradingview/ENTRY-PLANNER-GUIDE.md) documents v3 planning arithmetic; the v4 notes override their old marker/display behavior.

## Tests

Requires Python 3. Run from the repository root:

```powershell
python tradingview/tests/test_v4.py
```

This executes 61 source-expression/contract/reference-model tests. It is **not** a Pine compiler or TradingView series-engine/broker integration test. It cannot demonstrate profitability or guarantee unchanged signals after feed/history corrections.

For the MT5 decision core, open an x64 Native Tools Command Prompt for Visual Studio and run:

```bat
mt5\tests\run-tests.cmd
```

The harness compiles the shared `AurumCore.mqh` as C++ and executes it using Python ctypes. The recorded development run passed 773 checks, including many repeated history-window comparisons. This does not test MT5 event integration or a strategy's performance. The generated test DLL is only a developer harness; the indicator does not load it.

## Remaining work

- Compile v4 in TradingView Pine Editor and resolve any compiler diagnostics.
- Verify closed-candle setup persistence, chart layout and all modes using Bar Replay and a live demo feed.
- Verify plan expiry, gap handling, same-bar ambiguity and alert messages end-to-end.
- Investigate the reported missing signals with exact chart timestamps, symbol/feed and saved inputs. The screenshot alone does not establish a repainting defect.
- Complete MT5 broker-specific acceptance checks and phone delivery testing.
- Evaluate costs, slippage, expectancy and drawdown with recorded demo trades; no performance claim exists.

## Data and credentials

No broker login, MetaQuotes ID, API token, account journal, private screenshot or unrelated project is included. MT5 journals created by a running installation can include account identifiers in their filenames; keep them out of Git. TradingView feed prices/spreads can differ from MT5 broker quotes.

No open-source license has been selected yet. This private repository is an unfinished project backup.
