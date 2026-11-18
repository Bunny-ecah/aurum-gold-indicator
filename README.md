# Aurum Gold Indicator

**Work in progress — demo research only.** XAUUSD confirmation indicators for MetaTrader 5 and TradingView. This repository preserves the unfinished project, source, tests and known limitations. It does not contain a validated profitable trading strategy and the indicators do not place orders; the optional MT5 EA trades demo accounts by default.

## Current versions

| Platform | Current source | Status |
| --- | --- | --- |
| MT5 | [`mt5/AurumConfirmation.mq5`](mt5/AurumConfirmation.mq5) + [`AurumCore.mqh`](mt5/AurumCore.mqh) | v4.20; core tests pass; MetaEditor compile and demo testing outstanding |
| Web app | [`docs/index.html`](docs/index.html) + [`docs/aurum.js`](docs/aurum.js) | Live gold 1H chart with the same signals; works in any browser and on phones |
| TradingView | [`tradingview/AurumSignalAudit.pine`](tradingview/AurumSignalAudit.pine) | v6 all-in-one (panel + signals + Strategy Tester in one script); compiles in Pine Editor; demo testing outstanding |

Earlier TradingView sources are retained for comparison: basic indicator, multi-timeframe v2 and entry-planner v3. Install only the version you intend to use, rather than all of them on one chart.

## Features (TradingView v6 and MT5 v4 share the same rules)

- **One clear STATUS:** BUY NOW / SELL NOW / IN TRADE / WAIT, and what to wait for next.
- **Session filter:** new trades only in London and/or New York hours (daylight saving handled).
- **SNR + SND:** support/resistance from swing points and supply/demand zones from strong impulse candles. Only the nearest area above and below price is drawn.
- **Trade plan:** entry, stop loss, take profit, reward-to-risk, **% profit/loss of your balance** and **lot size** for your balance and risk %.
- **Quality grade A/B/C** (score out of 100) for each signal, and a **win chance** taken from how past signals of the same grade ended. Setups with too little room to the target are skipped.
- **SETUPS:** counts every reaction at a zone or level and the rule that stopped it, so you can see why there are few signals.
- **RECORD:** every signal is followed to its result, giving win %, average R and total R on the loaded history: a built-in backtest of the rules.
- **All-in-one TradingView script:** the same script also runs in the Strategy Tester (net profit, drawdown, profit factor, with costs), so it needs only one saved script.
- Any timeframe, few settings, closed-candle signals that do not repaint.

How to use it, read the panel and backtest: [`tradingview/GUIDE.md`](tradingview/GUIDE.md).

## Backtest result

On real XAUUSD data from 2012 to 2022, the default settings on the **1H chart** made a small profit after spread: **239 trades, 43% win, profit factor 1.19, +26.9R, worst drawdown −11.6R**, profitable in each of the three periods tested. 15m and lower lost money with every setting tried. Full results, method and a demo-account plan: [`BACKTEST-RESULTS.md`](BACKTEST-RESULTS.md). Rerun it yourself: [`backtest/`](backtest/README.md).

## Web app (live chart)

[`docs/`](docs/) is a one-page web app: a **live 1H gold chart** with the Aurum zones, levels, BUY/SELL signals, the trade plan panel (entry, stop, target, RR, lot, quality, win chance), the record and alerts. No install, no account, works on phones.

- **Prices:** PAXG/USDT live from Binance (free, no key; a gold-backed token that follows spot gold within a few dollars; weekend candles are left out because spot gold is closed). For real **XAU/USD**, paste a free [Twelve Data](https://twelvedata.com) key in *Settings* (updates every 2 minutes).
- **Same rules:** `docs/aurum.js` is a port of the reference model and gives the identical 239 signals on the 2012–2022 data (`python tradingview/tests/test_webapp.py`).
- **WATCH** means a setup is forming on the live candle; it becomes BUY NOW / SELL NOW only if the candle closes that way.
- **Alerts:** press 🔔 for a sound and a browser notification on every new signal and when a trade hits its stop or target (keep the tab open).
- **For trading:** match your broker's XAUUSD price once (Settings) so the plan shows your broker's prices; **📋 Copy plan** copies entry, SL, TP and lot; **Journal** tab to mark signals Took/Skipped with notes and export to CSV; candle-close countdown; record and equity curve after spread.
- It never places trades.

**Open it:** on Windows double-click `docs/start-webapp.bat`: it starts a small local server and opens **http://localhost:8080** (keep its window open; close it to stop). Or double-click `docs/index.html`, or publish it free with GitHub Pages: repository **Settings → Pages → Source: Deploy from a branch → Branch `main`, folder `/docs` → Save**. After a minute it is at `https://bunny-ecah.github.io/aurum-gold-indicator/` (the repository must be public for free Pages).

## Automatic demo trading (MT5 EA)

[`mt5/AurumEA.mq5`](mt5/AurumEA.mq5) trades the indicator's signals automatically in MT5 (same entry, stop loss, take profit and lot size), **demo accounts only by default**, one trade at a time. It can also be backtested in the MT5 Strategy Tester with your broker's real prices. Setup and demo plan: [`mt5/EA-GUIDE.md`](mt5/EA-GUIDE.md).

## Installation

### MT5

1. In desktop MT5 select **File > Open Data Folder > MQL5 > Indicators** and create an `Aurum` folder.
2. Copy `mt5/AurumConfirmation.mq5` and `mt5/AurumCore.mqh` into that folder.
3. Open the `.mq5` in MetaEditor and press **F7** to generate the `.ex5`. Compiled files are deliberately excluded from Git.
4. Refresh Navigator and attach to the broker's gold/USD demo chart. Any timeframe works (M5 or H1 recommended).
5. Use the **H1** chart. Optionally load `mt5/presets/Recommended-H1.set` through Inputs > Load.

See [`mt5/README.md`](mt5/README.md) for rules, spread units, push setup and acceptance checks. Its release-package instructions refer to separately built binaries; this repository is source-only. Build scripts require a fresh local compilation/log before packaging.

### TradingView v6

1. Copy the full contents of `tradingview/AurumSignalAudit.pine`.
2. In TradingView open **Pine Editor**, create a new indicator, replace the template, **Save**, then **Add to chart**.
3. Remove earlier Aurum versions from that chart. Use the **XAUUSD 1H** chart with the default settings (they are the tested ones).
4. Set **Account balance** and **Risk %** in the settings. For alerts choose **alert() function calls only** to get the full trade plan in the message. Open the **Strategy Tester** tab for the backtest report.

See [`tradingview/GUIDE.md`](tradingview/GUIDE.md). Older files (`AurumConfirmation.pine`, `AurumMultiTimeframe.pine`, `AurumEntryPlanner.pine`) are kept only for reference.

## Tests

Requires Python 3. Run from the repository root:

```powershell
python tradingview/tests/test_tradingview.py
```

`python tradingview/tests/test_webapp.py` checks the web app's engine against the model (needs Node.js).

The first command runs 35 source-contract, rule and reference-model tests (`tradingview/tests/model.py` mirrors the rules). It is **not** a Pine compiler or TradingView engine test and cannot demonstrate profitability.

For the MT5 decision core, open an x64 Native Tools Command Prompt for Visual Studio and run:

```bat
mt5\tests\run-tests.cmd
```

On Linux/macOS: `g++ -std=c++17 -DAURUM_TEST_MAIN mt5/tests/core_tests.cpp -o core_tests && ./core_tests`. The harness compiles the shared `AurumCore.mqh` as C++; the recorded run passed 120 checks. This does not test MT5 event integration or a strategy's performance.

## Remaining work

- Compile the v6 all-in-one strategy in Pine Editor (the indicator form already compiled and ran) and v4.10 in MetaEditor; fix any compiler diagnostics.
- Check zones, S/R and signals visually with Bar Replay and a live demo feed in all three modes.
- Compare TradingView and MT5 signals on the same candles (feeds differ, so small differences are expected).
- Verify alerts and phone push end-to-end.
- Read the RECORD on several timeframes/modes and backtest with Bar Replay or the MT5 Strategy Tester (see the guide). The record excludes spread and slippage; no performance claim exists.

## Data and credentials

No broker login, MetaQuotes ID, API token, account journal, private screenshot or unrelated project is included. MT5 journals created by a running installation can include account identifiers in their filenames; keep them out of Git. TradingView feed prices/spreads can differ from MT5 broker quotes.

No open-source license has been selected yet. This private repository is an unfinished project backup.
