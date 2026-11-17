# Aurum Gold for MT5 — v4.20

Signals indicator for gold/USD on desktop MT5. The indicator does **not** place orders; to trade its signals automatically on a demo account, use **AurumEA** ([`EA-GUIDE.md`](EA-GUIDE.md)). Same rules as TradingView v6. The full trader's guide (panel, rules, record, backtesting) is [`../tradingview/GUIDE.md`](../tradingview/GUIDE.md).

## Install or upgrade

1. Remove the old Aurum from your chart.
2. In MT5: **File > Open Data Folder > MQL5 > Indicators**. Create (or reuse) an **Aurum** folder.
3. Copy **AurumConfirmation.mq5** and **AurumCore.mqh** into it (replace the old files).
4. Open the `.mq5` in MetaEditor and press **F7**. It should say 0 errors.
5. Navigator → right-click **Indicators** → **Refresh**. Drag **AurumConfirmation** onto your gold chart.

Use the **H1 chart**: the defaults are the settings that held up in a 10-year test on real XAUUSD; M15 and lower lost money with every setting (see [`../BACKTEST-RESULTS.md`](../BACKTEST-RESULTS.md)). The panel title turns orange on other timeframes. `presets/Recommended-H1.set` holds the same values.

## What you get

- **Panel:** TREND, SESSION, a big **STATUS** (BUY NOW / SELL NOW / IN TRADE / WAIT), Entry, Stop loss, Take profit with RR and % of balance, **lot size**, **QUALITY** grade A/B/C and **WIN CHANCE**, what to wait for next, the last trade, the **RECORD** of all closed signals in the scanned history (win %, average R, total R, last 20), and **SETUPS**: why setups did not become trades (see the guide).
- **Chart:** only the nearest supply/resistance above and demand/support below (set `ShowAll=true` for more), BUY/SELL text at signals, the result text where each trade ended, and red/green risk/reward boxes for the open trade.
- **Lot size** uses your account balance, `RiskPercent` and the broker's tick value, rounded down to the volume step. If even the minimum lot risks more than your %, the panel says so in orange.

## Inputs

| Group | Input | Default |
| --- | --- | --- |
| 1. Signals | Signal mode | Balanced |
| | Swing size | Large (10) |
| | Trading sessions (new trades only) | All day |
| | Trend timeframe | Current = auto |
| 2. Risk | Risk per trade (% of balance) | 1.0 |
| | Minimum reward (× risk) | 1.2 |
| 3. Display | Show all nearby zones and levels | false |
| | Show past signals and results | true |
| 4. Alerts | Popup / push / sound | popup on |
| | Pause alerts if spread is wider than | 0.50 (price units, not pips) |
| 5. Advanced | Stop-loss buffer 0.5 (tested), zone impulse ATR, minimum stop, items kept, ATR period, trade time limit (100), history (3000), panel position | keep defaults |
| | Broker server time in winter (UTC+hours) | 99 = auto |
| | Server clock moves with US summer time (manual offset only) | true |

## Alerts

- Sent only for a **new** closed candle after the indicator is running. Old signals are never alerted on load.
- Skipped (and shown on the panel) when MT5 is disconnected, the quote is stale, the spread is above the cap, or more than 60 s passed after the candle closed.
- Message: `Aurum BUY XAUUSD M15 | Quality A 77/100 | Entry … | SL … | TP … | RR 1:2.0 = +2.0% if TP | Lot 0.05 | Demand (fresh)`.
- Phone: in MT5 mobile copy your **MetaQuotes ID** → desktop **Tools > Options > Notifications** → enable, paste ID, **Test** → set `Phone push notification = true`.

## Sessions and your broker's clock

The session filter needs to know how your broker's server clock relates to UTC. Live, this is detected automatically (`ServerUTCOffset = 99`) and shown on the SESSION row, for example `[server UTC+2]`. Most brokers on UTC+2 in winter move to UTC+3 with US summer time, and that is assumed. If the SESSION row shows the wrong market for the current time, set `ServerUTCOffset` to your broker's **winter** offset by hand.

## Backtest in MT5

*View → Strategy Tester* → choose **Indicator**, select AurumConfirmation, XAUUSD, M15, a date range of a few months, enable **Visualization**, Start. **Set `ServerUTCOffset` by hand** (for example 2), because the tester cannot detect the broker's clock; the SESSION row turns orange as a reminder. At the end the panel's RECORD shows the result for the last `HistoryBars` candles. Notifications are off in the tester.

For a full report (profit factor, drawdown, costs) use the TradingView strategy version; see the guide.

## Developer tests

The shared rules in `AurumCore.mqh` are compiled as C++ and tested (120 checks):

- Windows (x64 Native Tools prompt): `tests\run-tests.cmd`
- Linux/macOS: `g++ -std=c++17 -DAURUM_TEST_MAIN tests/core_tests.cpp -o core_tests && ./core_tests`

These do not test MT5 charts, history loading or alert delivery. **v4.20 and AurumEA have not yet been compiled in MetaEditor.** Press F7 and report any error line.

## Limits

Demo research only. No profitability is claimed. The record ignores spread, commission and slippage. Broker spreads, fills and history differ.
