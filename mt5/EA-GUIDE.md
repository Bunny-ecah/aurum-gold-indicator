# AurumEA — automatic trading on a demo account

`AurumEA.mq5` trades the Aurum Gold signals by itself in MT5: the **same entry, stop loss, take profit and lot size** as the indicator panel, with the tested settings (XAUUSD **H1**). It only trades **demo accounts** unless you change `DemoOnly`.

It does not invent its own signals: it loads the Aurum indicator and trades exactly what the indicator shows.

## Install (10 minutes)

1. In MT5: **File → Open Data Folder → MQL5**.
2. **Indicator** (skip if already installed): copy `AurumConfirmation.mq5` and `AurumCore.mqh` to `MQL5/Indicators/Aurum/`. Open `AurumConfirmation.mq5` in MetaEditor and press **F7** (0 errors).
3. **EA:** create the folder `MQL5/Experts/Aurum/` and copy `AurumEA.mq5` **and** `AurumCore.mqh` into it. Open `AurumEA.mq5` in MetaEditor and press **F7**.
4. In MT5, log in to your **demo** account (File → Open an Account → demo, if you do not have one).
5. Open an **XAUUSD H1** chart (your broker may call it XAUUSD, XAUUSDm, GOLD…).
6. Navigator → **Expert Advisors → Aurum → AurumEA** → drag onto the chart.
7. In the window: tab **Common** → tick **Allow Algo Trading**. Tab **Inputs** → check `RiskPercent` (1% is the default). **OK**.
8. Switch on the **Algo Trading** button in the MT5 toolbar (it turns green).

The chart shows the Aurum indicator and panel, and top-left the EA status:

```
AURUM EA  |  XAUUSD H1  |  account: DEMO  |  risk 1.0%
Status: No signal - waiting
Last: 2026-11-18 21:00  OPENED BUY 0.02 lot (grade A) | entry 3877.50 | SL 3871.20 | TP 3885.10 | RR 1:1.2
```

**Do not** also drag the Aurum indicator onto the same chart: the EA already shows it.

**MT5 must stay running** (computer on, internet on) for the EA to trade. If you cannot keep your laptop on, a VPS (MT5 → Tools → Options → Virtual hosting) runs it 24/5.

## What it does on every new H1 candle

1. Reads the indicator's signal for the candle that just closed.
2. Opens a trade only if **all** of these are true, otherwise it writes the reason in **Last:** and in the Experts log:
   - there is a signal, and no Aurum trade is open (one trade at a time)
   - the grade is allowed (`TradeGrades`, default all grades, as tested)
   - the account is demo (while `DemoOnly = true`) and Algo Trading is on
   - the spread is not above `MaxSpreadPrice` (0.50)
   - price is still between the stop and the target
   - the lot size for `RiskPercent` is at least the broker's minimum lot (or `AllowMinLot = true`)
3. Places the order **with stop loss and take profit already set**, so the broker closes it even if MT5 disconnects.
4. Closes a trade still open after **100 candles**, like the indicator's record.
5. Reports every open and close (and the profit) in **Last:**, the Experts log and, if `PushNotifications = true`, on your phone.

It only acts at a candle close, never on an old signal when you start it, and only on its own trades (magic number 880501). You can still close a trade by hand at any time.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| DemoOnly | true | Refuse to run on a real account |
| RiskPercent | 1.0 | % of balance lost if the stop loss is hit (0.1–5) |
| MaxSpreadPrice | 0.50 | Skip a signal if the spread is wider (price units, not pips) |
| AllowMinLot | false | Trade the minimum lot even if it risks more than RiskPercent |
| TradeGrades | All | All / A and B / A only |
| MaxTradeBars | 100 | Close after this many candles |
| MagicNumber | 880501 | Marks this EA's trades |
| SlippagePoints | 50 | Allowed slippage |
| PushNotifications | false | Phone message on open / close |
| ShowIndicator | true | Show the indicator and panel on the chart |

## Backtest it in MT5 (real broker prices and spread)

1. **View → Strategy Tester**. Choose **Expert**: `Aurum\AurumEA`.
2. Symbol **XAUUSD**, timeframe **H1**, dates: as far back as your broker has (e.g. 2 years), Modelling **Every tick based on real ticks** (or *Every tick*), Deposit 1000, Leverage 1:100.
3. **Start**. Read the **Backtest** tab: net profit, profit factor, max drawdown, total trades; and the **Graph**.

This is the most realistic test you can do before the demo: it uses your broker's real prices and spreads. Compare it with [`../BACKTEST-RESULTS.md`](../BACKTEST-RESULTS.md) (profit factor about 1.2 on 2012–2022).

## Demo plan

Run it on demo for **at least 2 months or 20 trades**, without changing settings. Then look at MT5 → History: profit factor, win %, worst losing streak. If the result is close to the backtest, discuss with your brother whether to try real money with **0.5% risk**. If it is clearly worse, stop and review.

## Limits

- Demo research, not a proven strategy. Past results do not guarantee future results.
- Not yet compiled in MetaEditor by the development workflow: if F7 shows an error, send the line and message.
- The EA follows the indicator's default settings. To change settings, change the indicator's defaults (or ask for EA inputs that pass them through).
