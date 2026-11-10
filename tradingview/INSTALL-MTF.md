# Aurum Gold Multi-Timeframe v2 — TradingView

Demo research indicator for gold/USD. Adds automatic 1m, 5m, 15m, 30m and 1h profiles with distinct setup triggers. This does not change the MT5 indicator. The original TradingView build is preserved in `Aurum-Gold-TradingView-v1.zip` in the project directory.

## Install / replace the earlier TradingView version

1. Open `Aurum-Multi-Timeframe-TradingView.txt` or `AurumMultiTimeframe.pine` and copy the entire file.
2. Open a standard-candle XAUUSD chart in desktop TradingView and open Pine Editor.
3. Create a new indicator, replace its template with this code, **Save** as **Aurum Gold MTF v2**, and **Add to chart**. Remove the earlier Aurum indicator from the chart to avoid duplicate panels/markers.
4. Keep **Timeframe profile = Auto chart**, **Setup type = Auto profile** and **Use timeframe preset parameters = true**.
5. Switch among **1m, 5m, 15m, 30m and 1h**. The profile follows your chart automatically. Other timeframes and synthetic charts (Heikin Ashi, Renko etc.) are rejected.

If you choose an explicit profile, match the chart timeframe. This analyzes the current chart only; it does not scan all five entry timeframes from one chart. All profiles use BUY and SELL.

## Preset matrix

These are transparent, unoptimized starting parameters for demo evaluation. They are not claimed to be best settings or validated by trading results.

| Entry chart | Primary trend | Second trend | Default setup | Entry EMA | RSI BUY / SELL | ADX min |
| --- | --- | --- | --- | --- | --- | --- |
| 1 minute | 5m | 15m | EMA pullback reclaim | 9/21 | 58–68 / 32–42 | 22 |
| 5 minutes | 15m | 1h | Range breakout | 20/50 | 55–70 / 30–45 | 20 |
| 15 minutes | 1h | 4h | Breakout retest | 20/50 | 55–70 / 30–45 | 20 |
| 30 minutes | 2h | 4h | Momentum breakout | 20/50 | 55–70 / 30–45 | 22 |
| 1 hour | 4h | 1 day | Range breakout | 20/50 | 55–70 / 30–45 | 20 |

Higher-timeframe EMAs default to 200, RSI/ATR/DI/ADX smoothing to 14, and MACD to 12/26/9. Each higher-timeframe request uses the last completed candle available at the ENTRY BAR OPEN, using offset expressions and lookahead_on. A new higher-timeframe close becomes usable on the next entry bar. The script does not use future higher-timeframe data. Sufficient higher-timeframe history is required, including daily history for the 1h profile.

## Five confirmation blocks

An accepted BUY requires all enabled confirmations in the BUY direction; SELL mirrors them:

1. **Trend stack:** both completed higher-timeframe closes above their EMA 200 for BUY, below for SELL. Disable `Require second higher-timeframe trend` to use only the primary trend.
2. **Entry EMA alignment:** fast EMA > slow EMA and close > fast EMA for BUY; inverse for SELL.
3. **RSI momentum:** within the profile's inclusive range, shown in the matrix.
4. **Setup trigger:** one of the following exact definitions.
5. **ADX + DI:** ADX >= profile threshold and +DI > -DI for BUY, or -DI > +DI for SELL. If disabled, the panel shows OFF and reduces the denominator to 4 instead of treating the disabled check as evidence.

These indicators are related measures of price behavior, not independent statistical evidence. A 5/5 count is not a win probability. More filters may reduce signals, add delay, and still fail; demo results must determine whether each profile helps your workflow.

### 1m: EMA pullback reclaim

BUY: the previous candle's low touches or falls below its fast EMA, AND its close is on/below that EMA. The current completed candle closes above the current fast EMA AND strictly above the preceding candle's high. SELL reverses the conditions using the preceding candle's high/low.

The trigger is a one-candle pullback/reclaim, not an arbitrary multi-candle pullback detector. All five confirmation blocks and additional filters still apply.

### 5m and 1h: range breakout

BUY: completed candle closes above the highest high of the PRECEDING five candles, plus 0.05 times the previous candle's ATR. SELL closes below the preceding five candles' lowest low minus that buffer. The signal candle is excluded from the range; touching the level is insufficient.

### 15m: breakout retest

1. A prior candle closes beyond its preceding-five-candle range by 0.05 times its previous ATR.
2. On a later candle within `Retest within N candles` (default 3), price touches the original fixed range boundary inside a tolerance zone. The default tolerance is 0.20 times the BREAKOUT candle's previous ATR.
3. BUY retest candle low must lie between level minus tolerance and level plus tolerance, and close must be strictly above the level. SELL retest high must lie in the corresponding zone and close below the level.
4. Any intervening candle close below a BUY level invalidates that BUY retest; a close above a SELL level invalidates that SELL retest. A current wick beyond the tolerance also fails.

The most recent breakout in each direction takes precedence, even if its retest is invalid. Same-candle breakout/retest and expired breakouts are excluded. The anchor plots show current candidate levels; they are not guaranteed support/resistance or instructions to place orders. The quiet-period filter controls repeated candidates, not a permanent one-alert-per-zone registry.

### 30m: momentum breakout

BUY: closes above the preceding EIGHT candles' highest high plus 0.10 previous ATR, MACD histogram is positive and greater than on the prior candle, and fast EMA is rising. SELL: closes below the range minus the buffer, histogram is negative and falling, and fast EMA is falling. All the other confirmation blocks remain required.

## Additional filters

| Filter | 1m | 5m / 15m / 1h | 30m |
| --- | --- | --- | --- |
| Maximum candle high-low / previous ATR | 1.5 | 2.0 | 2.0 |
| Maximum absolute close-to-fast-EMA distance / previous ATR | 1.25 | 1.5 | 2.0 |
| Required preceding candidate-free candles | 5 | 3 | 3 |

- BUY candles must be bullish; SELL candles bearish, unless that toggle is disabled.
- Optional minimum/maximum current ATR thresholds are in the chart's quoted price units; zero turns off the corresponding bound.
- The prior ATR determines range, breakout buffer and EMA-distance gates. The signal candle cannot inflate its own range allowance.
- A raw candidate passes all confirmations and filters BEFORE the quiet-period gate. A signal requires the preceding N candles to have no raw candidate in either direction and sufficient data. Continuous candidate clusters are suppressed until enough candidate-free candles occur.
- Signals and alerts require entry-candle confirmation. The panel consistently describes the most recently completed entry candle, including its closing timestamp in the chart symbol's exchange timezone.
- `WAIT` is expected while any required rule is incomplete. The panel shows missing checks and status details such as large candle, stretched price or quiet period. Even 5/5 can be blocked by additional filters.

## Customize deliberately

`Setup type` overrides the default trigger and can be used with any supported chart. Retest tolerance/window, indicator periods, ATR bounds and filter toggles are always editable.

To override EMA periods, RSI bands, breakout length/buffer, ADX threshold, candle range, EMA distance or quiet count, turn **Use timeframe preset parameters OFF** first, then edit **Manual parameters**. Otherwise those manual fields are ignored. Turning defaults off applies the displayed manual values; it does not automatically copy the active profile's settings. The panel shows the effective EMA periods and ADX minimum.

Change one parameter group at a time and record demo results. No automatic execution, sizing, stops/targets, news calendar, VWAP or volume filter is included.

## Alerts

1. Create an alert and choose **Aurum Gold - Multi-Timeframe v2** as its Condition.
2. Select **Aurum ANY confirmation**, or separate BUY/SELL conditions.
3. Choose **Once Per Bar Close** and your notification delivery options.
4. Create a separate alert for each entry timeframe you want monitored. A 1m alert does not also monitor 15m/30m setups.
5. Recreate existing alerts after changing the script, symbol, timeframe, profile or inputs. TradingView runs each alert from its saved configuration; changing your visible chart does not update running alerts.

Adding the indicator alone does not activate alerts. Do not create ANY plus separate BUY/SELL alerts unless you want duplicate notifications. Available alerts/delivery options depend on the account plan.

## Broker spread and MT5 differences

TradingView uses your selected symbol/feed. This script does not read JustMarkets, Orca or VersusTrade account spreads or permissions. It does not implement the MT5 indicator's live freshness/spread/permission gates or CSV journal. Check actual MT5 bid/ask, trading availability and demo execution costs before entering, especially when evaluating the 1m profile. No platform-to-platform signal match is promised.

## Validation and first-run checks

25 rule-expression/model tests pass. Selected simple boolean expressions are extracted from the Pine source and evaluated against boundary fixtures; retest-window control flow is exercised with an explicit reference model. Coverage includes reclaim direction, breakout buffers, retest expiry/invalidation, most-recent-anchor precedence, MACD expansion, ADX direction/threshold, prior-ATR range, EMA distance, closed-candle gating and quiet-period gating.

These tests are NOT a Pine compiler, TradingView series-engine test or performance backtest. The source has NOT been compiled/run in TradingView in this session. The earlier MT5 version's test count does not validate this Pine version. Feed corrections, loaded history changes and EMA warmup can affect reconstructed values.

After pasting into Pine Editor, confirm it compiles. If an error appears, share its exact text and line number. On each timeframe verify the panel selects the expected profile and setup, compare recent markers against the definitions above, check there is no forming-candle marker, reload to compare historical markers, and observe a qualifying live candle for notification delivery. Keep a demo record of actual entries/exits, spread, costs, slippage, outcomes and drawdown; filter count alone does not establish performance.

## Official references

- https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/
- https://www.tradingview.com/pine-script-docs/concepts/repainting/
- https://www.tradingview.com/pine-script-docs/concepts/alerts/
- https://www.tradingview.com/pine-script-reference/v6/
