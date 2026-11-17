# Aurum Gold — trader's guide (TradingView v6 / MT5 v4.10)

Source: `tradingview/AurumSignalAudit.pine` and `mt5/AurumConfirmation.mq5`. Both use the same rules (`mt5/AurumCore.mqh`).

## Install (2 minutes)

**TradingView:** copy all of `AurumSignalAudit.pine` → **Pine Editor** → paste over your existing script (or *Create new → Strategy*) → **Save** → **Add to chart**. Remove older Aurum versions first.

It is **one all-in-one script**: the panel and signals on the chart *and* the Strategy Tester report, so it needs only one saved script and one chart slot (fits the TradingView Basic plan). It never places real orders. TradingView draws its own small trade arrows next to the BUY/SELL labels; that is normal for a strategy.

**MT5:** see [`../mt5/README.md`](../mt5/README.md).

Recommended start: **XAUUSD 15m chart** (trend from 4H) or **5m** (trend from 1H). Leave the settings at their defaults, except **Account balance** and **Risk %** on TradingView.

## Read the panel in 3 seconds

| Row | What it tells you |
| --- | --- |
| **TREND** | UP = only BUY trades. DOWN = only SELL trades. FLAT = no trades. |
| **SESSION** | Which market is open now. ✓ trading = new signals allowed. ✗ = outside your chosen session, so no new signals. |
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

A **BUY** needs all five:

1. **Trend UP:** the last *completed* higher-timeframe candle closed above its EMA 200.
2. **Price in a buy area:** a Demand zone (2 points) and/or Support level (1 point). Points needed: Aggressive 1, **Balanced 2** (a zone), Strict 3 (zone + support).
3. **Rejection candle:** it closes back above the area: a bullish candle or a long lower wick.
4. **Room to the target:** the next Resistance/Supply above is at least **1.5 × risk** away. If it is closer, the setup is skipped and the panel shows a NOTE.
5. **Inside the trading session:** the signal candle opened during the chosen session (London + New York by default). Outside it, the setup is skipped and shown as a NOTE. A trade that is already open is always followed to its end.

A **SELL** is the mirror image.

**Stop loss:** just beyond the area that was touched (+0.2 ATR), at least 0.5 ATR from entry.
**Take profit:** the next opposite area, capped at 3R. No area ahead → 2R.
**One trade at a time.** A new signal can only appear after the current one ends.

## Trading sessions

Gold moves cleanly when London and New York are open. The Asian session is often slow and choppy, which suits zone trading badly.

| Session | Local time | Malaysia time (winter / summer) |
| --- | --- | --- |
| London | 08:00–17:00 London | 16:00–01:00 / 15:00–00:00 |
| New York | 08:00–17:00 New York | 21:00–06:00 / 20:00–05:00 |

Daylight saving is handled automatically. Choose **London + New York** (default), **London only**, **New York only** or **All day**. The filter is ignored on 4H and higher charts.

**Does it help?** Test it: read the RECORD with *London + New York*, then with *All day*. Keep the one with the better average R over more trades.

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

## Full backtest: the Strategy Tester (TradingView)

The same script also places *simulated* orders with the panel's entry, stop and target, so TradingView's Strategy Tester reports net profit, max drawdown, profit factor, win rate and every trade.

1. Use OANDA:XAUUSD or another spot XAUUSD where 1 contract = 1 oz.
2. Open the **Strategy Tester** tab under the chart.
3. Settings → **Properties**: *Initial capital* (default 1000), *Commission* 0.15 per contract (= about 0.30 spread per trade; change it to your broker's spread ÷ 2).
4. Settings → **Inputs**: mode, sessions, minimum reward and *Risk per trade (%)* apply to the backtest too. *Account balance* is only for the panel's lot size; the backtest uses *Initial capital*.
5. Read **Net profit**, **Max drawdown**, **Profit factor** (above 1.3 is good, below 1.0 loses), **Total closed trades** (need 50+).

Suggested test plan, writing the results in a table:

| Chart | Mode | Sessions | Trades | Win % | Profit factor | Max drawdown |
| --- | --- | --- | --- | --- | --- | --- |
| 15m | Balanced | London + New York | | | | |
| 15m | Balanced | All day | | | | |
| 5m | Balanced | London + New York | | | | |
| 1H | Balanced | London + New York | | | | |
| 15m | Strict | London + New York | | | | |

Small differences between the panel's RECORD and the Strategy Tester are normal: the Strategy Tester includes the commission, and when one candle touches both stop and target it guesses the order of prices inside the candle, while the RECORD always counts that as a loss.

Other ways to test:

- **Bar Replay (TradingView):** go back a few months, press play, and trade the signals by hand as if live. This tests whether *you* can follow them.
- **MT5 visual tester:** *View → Strategy Tester* → Indicator → AurumConfirmation, XAUUSD, a few months, *Visualization* on. **Set `ServerUTCOffset`** to your broker's winter offset (for example 2), because the tester cannot detect it. The panel RECORD covers the last `HistoryBars` candles (default 3000).

## Alerts

TradingView: create an alert on the script and pick **alert() function calls only**. The message has everything:

`Aurum BUY XAUUSD 15m | Entry 4082.50 | SL 4076.20 | TP 4095.10 | RR 1:2.0 | Lot 0.01 | Demand`

Recreate alerts after changing the script or settings.

## Settings

| Group | Setting | Default |
| --- | --- | --- |
| 1. Signals | Signal mode | Balanced |
| | Swing size | Normal |
| | Trend timeframe | auto |
| | Trading sessions | London + New York |
| | Minimum reward (× risk) | 1.5 |
| 2. Risk | Account balance ($) *(TradingView only; MT5 reads it from the account)* | 1000 |
| | Risk per trade (%) | 1 |
| 3. Display | Show all nearby zones and levels | off |
| | Show past signals and results | on |
| 4. Advanced | Zone impulse, stop buffer, minimum stop, items kept, ATR period, trade time limit, contract size (100 oz) | keep defaults |

## Limits

Demo research, not a proven strategy. Signals use closed candles and do not repaint, but S/R levels appear a few candles after a swing is confirmed. TradingView and MT5 feeds differ, so signals will not match exactly. Not yet compiled in Pine Editor / MetaEditor by the development workflow.
