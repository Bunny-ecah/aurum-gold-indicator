# v4 signal visibility and debugging notes

The latest source is `AurumSignalAudit.pine`. This is unfinished and has not yet been compiled or runtime-tested in Pine Editor by the development workflow.

## Three stages

1. **BUY/SELL SETUP label:** the configured closed-candle setup and quiet-period checks passed. These markers do not depend on plan tracking and are not deleted when the latest plan drawings change.
2. **P dot:** a setup also passed stop-distance and optional S/R-room gates, and there was no existing plan at the start of that candle. A pending plan was accepted.
3. **TOUCH triangle:** a later completed candle reached the pending entry reference without the modeled gap/ambiguity rejection. This is not a broker fill receipt.

A pending/observed plan still blocks replacement plans, but no longer hides independent confirmed SETUP markers. The panel records the last setup decision, recent setup/plan counts and separate reasons for missing BUY and SELL prerequisites. No active plan means there is no current entry reference, even if an old plan was a SELL.

Finished plan drawings and prices are hidden by default. `Keep finished plan price references` restores the latest historical reference if desired. A new plan replaces the latest-plan drawings by design; setup plotshapes are independent.

## What remains unproven

- The earlier screenshot showed a finished plan, BUY RSI outside its band and SELL higher-timeframe trend mismatch. That explains the displayed WAIT state but does not establish why any particular historical marker might differ after a reload.
- Closed-candle guards and offset higher-timeframe requests are present, but a local expression test does not verify TradingView's complete execution engine.
- Different timeframes calculate different profiles; they are not expected to have identical markers. Feed corrections, changed inputs, EMA initialization, available history and recalculated stateful plan tracking can change reconstructed results.
- Filters have not been loosened to manufacture entries. No win probability or profitable performance is claimed.

## Reproduction checklist

Record the TradingView symbol including provider, timeframe, version, input settings, exact candle timestamp and whether the candle was closed. Compare SETUP, P and TOUCH separately. Hover the candle in Data Window to inspect Confirmed Setup, Accepted Plan, Entry Touch and Plan State codes. Use Bar Replay, then reload with the same data and settings. Recreate alerts for v4 and select the intended stage; setup alerts are not entry alerts.
