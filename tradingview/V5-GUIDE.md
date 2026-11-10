# Aurum Gold v5 — quick guide (SNR + SND + Fibonacci)

Source: `AurumSignalAudit.pine` (v5 replaces v4). MT5 v3 uses the same rules (`mt5/AurumCore.mqh`).

## Install (2 minutes)

1. Copy all of `AurumSignalAudit.pine`.
2. TradingView → **Pine Editor** → new indicator → paste → **Save** → **Add to chart**.
3. Remove older Aurum versions from the chart.
4. Works on any timeframe. Good starting points: **5m** (scalping), **15m** or **1h** (intraday).

You do not need to change any setting to start.

## What you see on the chart

| Drawing | Meaning |
| --- | --- |
| Green box **Demand** | Area where buyers pushed price up strongly (SND). |
| Red box **Supply** | Area where sellers pushed price down strongly (SND). |
| Green dashed **S** line | Support from a swing low (SNR). |
| Red dashed **R** line | Resistance from a swing high (SNR). |
| Orange dotted lines + shaded band | Fibonacci of the latest swing. The band is the **0.5 – 0.786 golden zone**. |
| Orange dashed **Fib 1.618 target** | Extension used for TP2. |
| **BUY ★★ / SELL ★★** label | Signal. Stars = confluence points. Text shows which areas agreed. |
| Blue / red / green lines | Entry, stop loss, TP1, TP2 of the latest signal. |
| Panel | Trend, mode, where price is now, last signal and its levels, what to wait for. |

## The rules

A **BUY** needs all three:

1. **Trend UP** — the last completed higher-timeframe candle closed above its EMA 200.
   Auto trend timeframe: 1m→15m, 5m→1h, 15m–1h→4h, 2h–4h→1D, 1D→1W.
2. **Enough confluence points** from areas the candle touched:
   - Demand zone = **2 points**
   - Support level = **1 point**
   - Fibonacci 0.5–0.786 pullback of an up-swing = **1 point**
3. **Rejection candle** — it closes back above the area, and is bullish or has a long lower wick.

**SELL** is the mirror: trend DOWN, supply (2) / resistance (1) / Fibonacci (1), close back below the area.

| Signal mode | Points needed | Use it when |
| --- | --- | --- |
| Aggressive | 1 | You want more signals and will filter by eye. |
| **Balanced** (default) | 2 | Recommended. A zone alone, or S/R + Fibonacci. |
| Strict | 3 | Fewest, strongest setups (zone + S/R or zone + Fib). |

All modes trade only **with** the trend. When the trend is flat there are no signals.
After a signal, the same side waits 5 candles (setting) to avoid repeated labels.

### How the areas are built

- **Support / Resistance (SNR):** swing highs/lows confirmed after N candles on each side (Swing size: Small 3, Normal 5, Large 10). When price closes through a level it flips (old resistance becomes support). Levels within 0.3 ATR are merged.
- **Supply / Demand (SND):** a candle whose body is at least 1.5 × ATR and closes beyond the previous candle's high/low. The previous candle is the base; the zone runs from the base body to the extreme wick. A zone is removed when a candle closes through it.
- **Fibonacci:** drawn on the latest confirmed swing (low→high = up-swing, high→low = down-swing).

### Stop loss and targets

- **Stop loss:** beyond the touched zone / level / Fib 0.786 (and the candle wick), plus 0.2 ATR. At least 0.5 ATR from entry.
- **TP1:** the nearest opposite area (resistance, supply, swing high) that is at least 1R away; otherwise 1.5R.
- **TP2:** the Fibonacci 1.618 extension if it is beyond TP1; otherwise TP1 + 1R.
- **Entry:** the signal candle's close. Your broker fill and spread will differ.

## Alerts

Create an alert on the indicator and pick either:

- **Any alert() function call** — message includes stars, reasons, Entry, SL, TP1, TP2. (Recommended.)
- **Aurum BUY / Aurum SELL / Aurum BUY or SELL** — simple alerts.

Recreate alerts after changing the script or settings.

## Why signals were missing in v4, and what changed

v4 needed 5–6 filters to agree at once (two trend timeframes, EMA alignment, RSI band, ADX/DI, breakout trigger, quiet period), so many valid moves were skipped. v5 replaces that with one idea — trend + key area + rejection — and lets you pick how many points are needed.

## Limits

- Not compiled in Pine Editor by the development workflow. If the editor shows an error, copy the exact line and message.
- Signals use closed candles and confirmed swings, so they do not repaint, but swing-based levels appear N candles after the swing.
- TradingView's feed can differ from your MT5 broker. This is demo research, not a proven strategy. Test on demo first.
