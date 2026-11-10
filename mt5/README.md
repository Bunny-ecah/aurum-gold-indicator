# Aurum Gold for MT5 — v3.00 (SNR + SND)

Signals-only indicator for gold/USD on desktop MT5. It does **not** place orders. Same rules as TradingView v5 — see [`../tradingview/V5-GUIDE.md`](../tradingview/V5-GUIDE.md) for the full explanation.

## Install or upgrade

1. Remove the old Aurum (v2) from your chart.
2. In MT5: **File > Open Data Folder > MQL5 > Indicators**. Create (or reuse) an **Aurum** folder.
3. Copy **AurumConfirmation.mq5** and **AurumCore.mqh** into it (replace the old files).
4. Open the `.mq5` in MetaEditor and press **F7**. It should say 0 errors.
5. Navigator → right-click **Indicators** → **Refresh**. Drag **AurumConfirmation** onto your gold chart.

Any timeframe works — v2's "wrong timeframe" lock is gone. Optional presets in `presets/`:

| Preset | Chart | Auto trend timeframe |
| --- | --- | --- |
| `Scalping-M5.set` | M5 | H1 |
| `Longer-Trades-H1.set` | H1 | H4 |

## The rules in one line

**BUY** = trend UP + price dips into **Demand (2 pts) and/or Support (1 pt)** + candle closes back above it. **SELL** is the mirror. Balanced needs 2 points (a zone), Strict 3 (zone + S/R), Aggressive 1 (any zone or S/R). Trend = last completed higher-timeframe candle vs its EMA 200 (chart EMA 200 is used while trend history loads).

## On the chart

- Green / red arrows with `BUY ** Demand` text: signals (stars = points).
- Shaded rectangles: Demand (green) and Supply (red) zones.
- Dashed lines: Support **S** and Resistance **R**.
- Solid lines: Entry, Stop loss, TP1, TP2 of the latest signal.
- Panel: trend, mode, where price is now, last signal, levels, next step, live spread and alert status.

## Inputs

| Group | Input | Default |
| --- | --- | --- |
| 1. Signals | Signal mode | Balanced |
| | Swing size for S/R levels | Normal (5) |
| | Trend timeframe | Current = auto |
| | Candles between same-side signals | 5 |
| 2. Show on chart | S/R, zones, trade lines, panel | all on |
| 3. Alerts | Popup / push / sound | popup on |
| | Pause alerts if spread is wider than | 0.50 (price units, not pips) |
| 4. Advanced | Zone impulse ATR, stop buffer, minimum stop, max items, ATR period, history, panel position | keep defaults |

## Alerts

- Sent only for a **new** closed candle after the indicator is running. Old signals are never alerted on load.
- Skipped (and shown on the panel) when MT5 is disconnected, the quote is stale, the spread is above the cap, or more than 60 s passed after the candle closed.
- Message: `Aurum BUY ** XAUUSD PERIOD_M5 | Demand Support | Entry … | SL … | TP1 … | TP2 …`.
- Phone: in MT5 mobile copy your **MetaQuotes ID** → desktop **Tools > Options > Notifications** → enable, paste ID, **Test** → set `Phone push notification = true`.

## Developer tests

The shared rules in `AurumCore.mqh` are compiled as C++ and tested (71 checks):

- Windows (x64 Native Tools prompt): `tests\run-tests.cmd`
- Linux/macOS: `g++ -std=c++17 -DAURUM_TEST_MAIN tests/core_tests.cpp -o core_tests && ./core_tests`

These do not test MT5 charts, history loading or alert delivery. **v3 has not yet been compiled in MetaEditor** — press F7 and report any error line.

## Limits

Demo research only. No profitability is claimed. Broker spreads, fills and history differ. The v2 CSV journal was removed to keep the indicator simple.
