# Aurum Gold — TradingView edition

This is a separate Pine Script v6 indicator. Keep using the `.ex5` files for MT5. TradingView cannot import the MT5 files.

## Add it to your Indicators

1. Open `AurumConfirmation.pine` (or the identical `.txt` copy) in a text editor and copy ALL the text, including `//@version=6`.
2. Open TradingView in a desktop browser, sign in and open your chosen XAUUSD chart.
3. Use standard candles. Choose **1 hour** initially (the default mode is Longer trades).
4. Open **Pine Editor**, then create a **new indicator**. Replace the template completely with the copied code.
5. Click **Save**, name it **Aurum Gold**, then click **Add to chart**.
6. It is now saved to your account. Find it later under **Indicators > My scripts** (the exact section label can vary by interface). This is a private personal script; publishing is not required.

No DLL, MT5 installation or broker password is required in TradingView. Account permissions and plan limits still apply. If TradingView displays a compiler error, copy the exact message and line number for diagnosis; do not delete parts of the code to suppress the error.

## Two modes

| Mode in Settings > Inputs | Chart timeframe | Trend |
| --- | --- | --- |
| Scalping | 5 minutes | 15 minutes |
| Longer trades (default) | 1 hour | 4 hours |

The code rejects mismatched timeframes and synthetic charts. When switching modes, change the chart timeframe and the indicator Mode to match. A temporary mismatch warning is expected until both match.

## Entry confirmation

BUY requires: completed higher-timeframe close above EMA 200; entry EMA 20 above EMA 50 and price above EMA 20; RSI 14 between 55 and 70; entry candle close strictly above the preceding five candles' highs. SELL reverses the trend/EMA/breakout checks and uses RSI 30–45.

Default additional filters: bullish BUY/bearish SELL candle; signal range <= 2 times previous candle ATR 14; no raw qualifying candidate in the previous three entry candles. Optional ATR bounds and extra breakout distance are configurable. Both modes support BUY and SELL. This detects breakout closes, not retests.

Markers appear only after an entry candle closes. The panel shows the most recently closed entry candle rather than a developing intrabar checklist. 4/4 counts rules, not a probability. A qualifying setup can lose.

## Create notifications — adding the indicator alone does not create alerts

1. Click TradingView's **Create alert** control.
2. Under **Condition**, select **Aurum Confirmation - Gold Demo**.
3. Choose **Aurum ANY confirmation** for both directions, or create separate BUY/SELL alerts.
4. Set frequency to **Once Per Bar Close**.
5. Select your preferred notification options and create the alert. Phone notifications require the TradingView app and its notification permissions.

Do not create ANY plus separate BUY/SELL alerts unless you intentionally want duplicate notifications. Existing historical markers do not generate new historical alerts. Alerts run from a saved configuration: recreate them after changing symbol, timeframe, mode or inputs. Available alert counts/expiry/delivery options depend on your TradingView account.

## Differences from MT5 v2

- TradingView uses the selected TradingView symbol's feed; it is not necessarily your JustMarkets, Orca or VersusTrade account feed. Signals may differ.
- This port does NOT read your MT5 bid/ask, historical spread, connection status, symbol trade permissions or CSV journal. **Check broker spread and trading availability in MT5 before any manual demo entry.** It does not silently assume a zero spread.
- For a documented, stable higher-timeframe request pattern, the script uses `close[1]` and `EMA[1]` with `lookahead_on`. Trend is a confirmed snapshot available at the entry candle's OPEN. A newly closed HTF candle becomes available on the next entry candle. At an HTF boundary this can delay a trend change by one entry candle compared with MT5 v2's close-time selection. Signals are not promised to match exactly.
- No orders, position sizing, stop-loss/target generation or performance backtest is included. This is an indicator, not a TradingView strategy.

## Validation status

The Pine source has been reviewed against TradingView's v6 documentation and checked for expected file structure, alert declarations and mode defaults. It has NOT been compiled or run in TradingView's Pine Editor in this session. The MT5 version's 773 shared-core checks do not constitute validation of this separate Pine implementation.

After adding it, verify the editor accepts the source, the panel loads, there are no markers on forming candles, the 5-minute/1-hour modes match their higher-timeframe checks, and markers persist after a chart reload. Observe a genuine live qualifying candle to test alert delivery. Feed corrections and changes in loaded historical data can affect recalculated indicator values. No trading profitability is claimed.

## Official references

- https://www.tradingview.com/pine-script-docs/concepts/repainting/
- https://www.tradingview.com/pine-script-docs/concepts/alerts/
- https://www.tradingview.com/pine-script-docs/visuals/tables/
- https://www.tradingview.com/support/solutions/43000561836-what-is-pine-script/
