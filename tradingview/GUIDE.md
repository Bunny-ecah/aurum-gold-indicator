# Aurum Gold — trader's guide (TradingView v6 / MT5 v4)

Source: `tradingview/AurumSignalAudit.pine` and `mt5/AurumConfirmation.mq5`. Both use the same rules (`mt5/AurumCore.mqh`).

## Install (2 minutes)

**TradingView:** copy all of `AurumSignalAudit.pine` → **Pine Editor** → paste over the template → **Save** → **Add to chart**. Remove older Aurum versions first.

**MT5:** see [`../mt5/README.md`](../mt5/README.md).

Recommended start: **XAUUSD 15m chart** (trend from 4H) or **5m** (trend from 1H). Leave the settings at their defaults, except **Account balance** and **Risk %** on TradingView.

## Read the panel in 3 seconds

| Row | What it tells you |
| --- | --- |
| **TREND** | UP = only BUY trades. DOWN = only SELL trades. FLAT = no trades. |
| **STATUS** | **BUY NOW / SELL NOW** = a signal just closed: the trade plan is below. **IN BUY / SELL TRADE** = a signal is still running. **WAIT** = do nothing yet. |
| ENTRY / STOP LOSS / TAKE PROFIT | The plan for the open signal, with its reward-to-risk (RR 1 : 2 means you win 2 for every 1 you risk). |
| LOT SIZE | Lot size so that hitting the stop loss costs your risk % of the balance. |
| NEXT | When waiting: which zone to watch and what candle you need. |
| NOTE | A setup was skipped because the target was too close (not worth the risk). |
| LAST TRADE | How the previous signal ended. |
| **RECORD** | Every closed signal in the loaded history: win %, average R, total R. |
| LAST 20 | The same, for the 20 most recent signals: is it working *now*? |

## On the chart

- **One red area above price and one green area below.** These are the nearest Supply/Resistance (where SELLs come from) and Demand/Support (where BUYs come from). Turn on *Show all nearby zones and levels* to see more.
- **BUY / SELL labels** at each signal. Hover a label (TradingView) to see its entry, stop, target and reason. *STRONG* means a zone and an S/R level agreed.
- **Result text** where each trade ended, for example `TP +2.0R` or `SL -1.00R`.
- **Red and green boxes** for the open trade: red = what you risk, green = what you aim to win.

## The rules

A **BUY** needs all four:

1. **Trend UP:** the last *completed* higher-timeframe candle closed above its EMA 200.
2. **Price in a buy area:** a Demand zone (2 points) and/or Support level (1 point). Points needed: Aggressive 1, **Balanced 2** (a zone), Strict 3 (zone + support).
3. **Rejection candle:** it closes back above the area: a bullish candle or a long lower wick.
4. **Room to the target:** the next Resistance/Supply above is at least **1.5 × risk** away. If it is closer, the setup is skipped and the panel shows a NOTE.

A **SELL** is the mirror image.

**Stop loss:** just beyond the area that was touched (+0.2 ATR), at least 0.5 ATR from entry.
**Take profit:** the next opposite area, capped at 3R. No area ahead → 2R.
**One trade at a time.** A new signal can only appear after the current one ends.

## The RECORD (built-in backtest)

Every signal is followed until one of these happens:

| Event | Result |
| --- | --- |
| Price reaches TAKE PROFIT | **+R** (for example +2.0R) |
| Price reaches STOP LOSS | **−1R** |
| A candle touches both stop and target | **−1R** (counted as a loss to stay honest) |
| 100 candles pass | closed at that candle's close |

**R** is profit measured in "risk units". With 1% risk per trade, +2R ≈ +2% and −1R ≈ −1% of the balance.

How to judge it:

- **avg R above 0** over many trades = the rules made money on that history. Below 0 = they lost.
- You need **at least 30–50 trades** before the numbers mean anything. Fewer than that is mostly luck.
- Compare timeframes and modes: put the indicator on 5m, 15m and 1H, then switch Balanced/Strict, and write down RECORD for each.
- **LAST 20** going negative while RECORD is positive = the market changed; be careful.

What the record does **not** include: spread, commission, slippage, and news spikes. Gold spreads are often 0.20–0.50, so a real result is a bit worse, especially with small stops on 1m/5m. Entry is the signal candle's close; your real fill will differ slightly.

## Backtesting later

1. **Quick check (today):** read RECORD on several timeframes. TradingView loads only a limited number of candles (more on paid plans), so the sample is the loaded history.
2. **Bar Replay (TradingView):** go back a few months, press play, and trade the signals by hand as if live. This tests whether *you* can follow them.
3. **MT5 visual tester:** *View → Strategy Tester*, choose the indicator, enable *Visualization*, run on XAUUSD 15m over a few months. The panel RECORD covers the last `HistoryBars` candles (default 3000).
4. **Export:** the TradingView *Data Window* shows `Trade result (R)` on each exit candle, which you can export to a spreadsheet.
5. **Next step if the record looks good:** turn the same rules into a TradingView *strategy* or an MT5 Expert Advisor for a full report (drawdown, profit factor, costs).

## Alerts

TradingView: create an alert on the indicator and pick **Any alert() function call**. The message has everything:

`Aurum BUY XAUUSD 15m | Entry 4082.50 | SL 4076.20 | TP 4095.10 | RR 1:2.0 | Lot 0.01 | Demand`

Recreate alerts after changing the script or settings.

## Settings

| Group | Setting | Default |
| --- | --- | --- |
| 1. Signals | Signal mode | Balanced |
| | Swing size | Normal |
| | Trend timeframe | auto |
| 2. Risk | Account balance ($) *(TradingView only; MT5 reads it from the account)* | 1000 |
| | Risk per trade (%) | 1 |
| | Minimum reward (× risk) | 1.5 |
| 3. Display | Show all nearby zones and levels | off |
| | Show past signals and results | on |
| 4. Advanced | Zone impulse, stop buffer, minimum stop, items kept, ATR period, trade time limit, contract size (100 oz) | keep defaults |

## Limits

Demo research, not a proven strategy. Signals use closed candles and do not repaint, but S/R levels appear a few candles after a swing is confirmed. TradingView and MT5 feeds differ, so signals will not match exactly. Not yet compiled in Pine Editor / MetaEditor by the development workflow.
