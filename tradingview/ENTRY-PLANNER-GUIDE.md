# Aurum Gold Entry Planner v3 — TradingView demo

This update makes the earlier multi-timeframe confirmation script more explicit about the next price level to watch. It is an indicator, not an automated trading system. All entry, stop and target levels are planning references; chart touches are not broker fills or confirmed trade outcomes.

## What changed

- A qualified setup creates a **pending entry reference beyond the signal candle's high or low**, rather than suggesting an entry at an already-past close.
- Four tick-aligned levels identify entry, stop, TP1 and TP2. Levels remain fixed after the signal and only the latest plan is drawn.
- The panel displays pending, trigger observed, expired, invalid, missed-gap and ambiguous states.
- A structure-based stop must satisfy minimum/maximum ATR distance bounds. Plans with excessively wide stops are rejected.
- Optional confirmed support/resistance room filtering checks whether the latest available opposing pivot lies before target 1.
- A compact bottom-right panel is the default. Its colors follow the chart theme. Position, text size and detail level are configurable; the panel can be hidden independently of drawings and alerts.

The five confirmation blocks and timeframe profiles are inherited from v2: higher-timeframe trends, entry EMAs, RSI band, setup trigger and optional ADX/DI. ATR, candle direction, EMA distance and quiet-period gates remain. Existing mode-specific triggers have not been performance-optimized.

## Install

1. Open `Aurum-Entry-Planner-TradingView.txt` or `AurumEntryPlanner.pine` and copy everything, including `//@version=6`.
2. In TradingView, open **Pine Editor** from the right toolbar. Create a new indicator, replace its template, **Save** as **Aurum Entry Planner v3**, and **Add to chart**.
3. Remove earlier Aurum versions from the chart to avoid duplicate panels. The old saved scripts need not be deleted.
4. Use standard candles on **1m, 5m, 15m, 30m or 1h**. Keep **Timeframe profile = Auto chart** and **Setup type = Auto profile** initially.
5. Under Display, keep **Panel detail = Compact**, choose a corner, or set **Show closed-candle checklist = false** to hide it. `Draw latest entry / stop / targets` controls drawings independently.

The MT5 version is unchanged by this update.

## Timeframe profiles

| Entry | Trend checks | Default trigger |
| --- | --- | --- |
| 1m | 5m + 15m | EMA 9/21 pullback reclaim |
| 5m | 15m + 1h | Five-candle range breakout |
| 15m | 1h + 4h | Later breakout retest |
| 30m | 2h + 4h | Eight-candle breakout + expanding MACD histogram + EMA slope |
| 1h | 4h + daily | Five-candle range breakout |

See `INSTALL-MTF.md` for the exact v2 trigger definitions and effective preset parameters. In v3, chart labels/alerts refer only to accepted PLANS, not every raw qualifying setup. A raw setup can be blocked by invalid stop distance, optional S/R room, or a plan already being tracked.

## How to read an entry plan

1. **Wait for candle close.** All required setup checks must pass. The signal candle does not also trigger its own pending entry.
2. **Read the direction and entry reference.** BUY entry is above the signal high by `Entry beyond signal high/low / prior ATR` (default 0.05 prior ATR), with at least one chart tick of separation. SELL is below the signal low. BUY entries round up to the chart tick; SELL entries round down.
3. **Read the stop reference.** BUY starts below the lowest low of the last `Structure stop lookback` candles (default 5 INCLUDING the signal), minus 0.15 prior ATR. SELL starts above the corresponding highest high plus that buffer. The stop is moved farther out if needed to keep at least 0.75 prior ATR between entry and stop. If tick rounding/structure makes risk greater than 3.0 prior ATR, no plan is created.
4. **Read targets.** Default TP1 is 1 times the entry-to-stop distance (1R); TP2 is 2 times it (2R), with targets rounded outward to chart ticks. Values freeze at plan creation. These are geometric references, not forecasts or evidence that the target is reachable.
5. **Check actual broker quotes and costs.** TradingView does not provide this script with your MT5 account spread, execution price or order state. A BUY stop conventionally depends on broker ask, whereas a TradingView chart may reflect a different feed/price basis. Do not copy chart levels blindly into a broker order.

### Fictional arithmetic example

An illustrative BUY plan with entry 2650.00 and stop 2647.00 has reference risk 3.00. Default TP1 is 2653.00 and TP2 2656.00 before chart-tick rounding. These are invented numbers explaining the calculation, not a current XAUUSD setup or a recommendation.

## State meanings

| Status | Meaning |
| --- | --- |
| WAIT FOR SETUP | No plan has yet been created from the available data. |
| PENDING | A completed signal exists; entry is eligible only on later candles within the expiry window. |
| TRIGGER OBSERVED | A later completed candle's range reached the entry reference. It does not establish that any broker order filled. |
| TP1 OBSERVED | The target-1 reference was reached; the stop and TP2 remain fixed. No partial close or breakeven move is assumed. |
| TP2 LEVEL OBSERVED | The target-2 reference was reached; tracking ends. No P&L is calculated. |
| STOP LEVEL OBSERVED | The stop reference was reached after a trigger observation; tracking ends. |
| EXPIRED | No trigger within the next 3 entry candles by default. The last eligible candle is checked before expiration. |
| INVALID: stop before entry | A candle touched the stop reference before an unambiguous entry observation. |
| MISSED: opening gap | A triggering candle opened beyond the entry by more than 0.20 of the plan's frozen ATR; tracking ends instead of treating that as an entry at the old price. |
| AMBIGUOUS | The same candle reached entry and stop, or stop and TP2. OHLC cannot establish the event order, so no favorable outcome is assumed. |
| TRACKING ENDED | After a trigger, 30 candles elapsed by default without another terminal event. This does not imply a trade exit. |

The script processes observations at candle close. It is not an intrabar execution engine. If entry and stop are both reached on the same candle, it reports ambiguity even when a particular path might be inferred from the open; this is deliberately conservative.

A pending or triggered plan blocks all replacement plans, including opposite-direction setups. When a plan ends, the earliest possible replacement is on a subsequent candle, not the same ending candle. Finished levels stop projecting and turn dashed/gray-labeled. They remain historical references; **do not treat a finished plan as a current entry**. The signal's closing timestamp is shown in the symbol's exchange timezone.

## Optional support/resistance filter

`Block target 1 behind latest confirmed S/R` is OFF by default. If enabled, a BUY plan is blocked if the latest unbroken confirmed pivot high lies strictly between entry and TP1. SELL uses the latest unbroken pivot low. Pivots default to three left and three right candles and become available only AFTER the right candles close; no signals are backdated to a pivot's original bar. A close beyond a tracked pivot invalidates that level.

This is a single-level pivot S/R filter, not a comprehensive SNR-zone system. If no corresponding confirmed level is available, this optional gate does not block the plan and must not be interpreted as affirmative evidence of clear space. No supply/demand-zone engine or Fibonacci confluence is implemented.

## Alerts

Recreate earlier Aurum alerts after installing v3. Choose **Aurum Gold - Entry Planner v3** and one of:

- **Aurum ANY plan**: both directions, with entry/stop/target references in the message. Inspect the direction on the chart.
- **Aurum BUY plan** / **Aurum SELL plan**: direction-specific pending-plan messages with levels.
- **Aurum entry level observed**: a separate optional notification when a later completed candle reaches the entry reference. The same candle may also reach TP2, so inspect current plan status. This message is not a fill receipt.

Use **Once Per Bar Close**. Do not combine ANY plan with both direction-specific plan alerts unless duplicate messages are intended. Adding the indicator alone does not create an active alert. Each alert monitors its saved symbol/timeframe/profile only. The script does not send separate stop/target alerts and never places orders.

## Why it may wait

Compact mode shows the first missing BUY and SELL check: data, trend, EMA, RSI, ADX/DI, trigger, ATR/range, EMA distance, candle direction, quiet period, stop-distance bounds or optional S/R room. Detailed mode exposes all these checks. Counts measure enabled rule blocks, not confidence percentages. Several checks measure related price behavior and are not independent evidence.

## Verification limits

- 25 setup-expression/model tests and 24 planner-expression/contract tests pass locally. The planner tests execute numeric/boolean formulas extracted from the Pine source, including pending/observed event functions, tick-rounded level arithmetic, risk caps, gap handling and same-candle ambiguity. Some lifecycle checks verify source contracts rather than running Pine's bar-by-bar engine.
- Basic package/source checks pass. **The new v3 source has NOT been compiled or run in TradingView's Pine Editor.** Chrome page text could be read, but automated clicks failed with missing input geometry and screen-capture timeout, preventing editor validation.
- These checks do not verify TradingView series behavior, chart layout, broker execution, alert transport or profitable results. Feed/history changes can affect recalculated setups. Review the source in Pine Editor, report exact compiler errors if any, then use Bar Replay and live demo observation to check expiry, gaps, stop/target ambiguity and alert messages.
- No win rate, profit, live-trading suitability or risk-size recommendation is claimed.

## References

- https://www.tradingview.com/pine-script-docs/visuals/lines-and-boxes/
- https://www.tradingview.com/pine-script-docs/concepts/alerts/
- https://www.tradingview.com/pine-script-docs/concepts/repainting/
- https://www.tradingview.com/support/solutions/43000763320-how-to-work-with-pine-editor/
