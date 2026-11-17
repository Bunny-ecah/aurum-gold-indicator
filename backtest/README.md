# Backtest on real XAUUSD data

Reproduces [`../BACKTEST-RESULTS.md`](../BACKTEST-RESULTS.md). Needs Python 3.9+ only (no extra packages).

## 1. Get the data (once)

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/ejtraderLabs/historical-data
cd historical-data && git sparse-checkout set XAUUSD && cd ..
```

Uses `XAUUSDm15.csv`, `XAUUSDh1.csv` and `XAUUSDh4.csv` (May 2012 – March 2022). The data is not stored in this repository.

## 2. Prepare it

```bash
python backtest/prepare_data.py historical-data/XAUUSD
```

Creates `backtest/gold.pkl` with candles, the 4H/1H trend (last completed candle vs EMA 200) and London / New York session flags.

## 3. Run

```bash
python backtest/run_backtest.py                       # recommended settings (1H, Balanced, All day, Large, 0.5, 1.2)
python backtest/run_backtest.py --tf 15 --sessions LN # try other settings
python backtest/run_backtest.py --grid                # search settings on 2016-2019, check the best on unseen years
```

Options: `--tf 15|60`, `--mode Aggressive|Balanced|Strict`, `--sessions ALL|LN|L|N`, `--swing 3|5|10`, `--buffer` (stop-loss buffer, ATR), `--rr` (minimum reward), `--trend h1|h4` (15m chart only).

The report shows trades, win %, profit factor, total R and worst drawdown for 2012–2015, 2016–2019, 2020–2022 and all years, the result by year, and the SETUPS breakdown. A 0.30 spread is subtracted from every trade.

## How it works

`run_backtest.py` runs `tradingview/tests/model.py`, the reference model that follows the same rules as `tradingview/AurumSignalAudit.pine` and `mt5/AurumCore.mqh`; the tests in `tradingview/tests/` check that they stay the same. It is not TradingView's own engine: TradingView's Strategy Tester on its own data will give somewhat different numbers.
