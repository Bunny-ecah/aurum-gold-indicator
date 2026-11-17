// Aurum v3 shared decision rules: SNR (support/resistance) + SND (supply/demand).
// Platform-independent: compiled by MT5 (MQL5) and by tests/core_tests.cpp (C++).
// The TradingView v5 script implements the same rules; keep both in sync.
#ifndef AURUM_CORE_MQH
#define AURUM_CORE_MQH

// Signal modes. Confluence points: Supply/Demand zone = 2, Support/Resistance level = 1.
// Every mode trades WITH the higher-timeframe trend only.
#define AURUM_BALANCED   0   // needs 2 points: a supply/demand zone
#define AURUM_STRICT     1   // needs 3 points: zone + S/R level together
#define AURUM_AGGRESSIVE 2   // needs 1 point: any zone or S/R level

struct AurumCandle
{
   double open,high,low,close;
   double atr;   // ATR of the PREVIOUS closed candle (the signal candle cannot inflate it)
};

bool AurumNumber(const double x)
{
   return x==x && x>-1.0e100 && x<1.0e100;
}

double AurumMin(const double a,const double b) { return a<b?a:b; }
double AurumMax(const double a,const double b) { return a>b?a:b; }
double AurumAbs(const double a) { return a<0?-a:a; }

bool AurumCandleValid(const AurumCandle &c)
{
   return AurumNumber(c.open) && AurumNumber(c.high) && AurumNumber(c.low) &&
      AurumNumber(c.close) && AurumNumber(c.atr) && c.atr>0 && c.low>0 &&
      c.high>=c.low && c.open<=c.high && c.open>=c.low &&
      c.close<=c.high && c.close>=c.low;
}

// ---------- Candle confirmation ----------
// BUY rejection: bullish close, OR a long lower wick (>= half the range) closing in the upper half.
bool AurumBullRejection(const AurumCandle &c)
{
   double range=c.high-c.low;
   if(range<=0) return false;
   if(c.close>c.open) return true;
   double lowerWick=AurumMin(c.open,c.close)-c.low;
   return lowerWick>=0.5*range && c.close>=c.low+0.5*range;
}

bool AurumBearRejection(const AurumCandle &c)
{
   double range=c.high-c.low;
   if(range<=0) return false;
   if(c.close<c.open) return true;
   double upperWick=c.high-AurumMax(c.open,c.close);
   return upperWick>=0.5*range && c.close<=c.high-0.5*range;
}

// ---------- SND: supply and demand zones ----------
// Demand: a strong bullish candle (body >= impulseATR x ATR) closing above the previous
// candle's high. The previous candle is the "base". Zone = lowest low -> base body top.
bool AurumDemandZone(const AurumCandle &base,const AurumCandle &impulse,const double impulseATR,
                     double &bottom,double &top)
{
   double atr=impulse.atr;
   if(atr<=0 || impulse.close-impulse.open<impulseATR*atr || impulse.close<=base.high) return false;
   bottom=AurumMin(base.low,impulse.low);
   top=AurumMax(base.open,base.close);
   if(top-bottom<0.2*atr) top=bottom+0.2*atr;      // too thin: give it a minimum height
   return top-bottom<=2.0*atr && top<impulse.close; // too tall = not a clean zone
}

// Supply: strong bearish candle closing below the previous candle's low.
bool AurumSupplyZone(const AurumCandle &base,const AurumCandle &impulse,const double impulseATR,
                     double &bottom,double &top)
{
   double atr=impulse.atr;
   if(atr<=0 || impulse.open-impulse.close<impulseATR*atr || impulse.close>=base.low) return false;
   top=AurumMax(base.high,impulse.high);
   bottom=AurumMin(base.open,base.close);
   if(top-bottom<0.2*atr) bottom=top-0.2*atr;
   return top-bottom<=2.0*atr && bottom>impulse.close;
}

// Price dipped into the demand zone and CLOSED back above it.
bool AurumDemandTouch(const AurumCandle &c,const double bottom,const double top,const double tol)
{
   return top>bottom && c.low<=top+tol && c.close>top;
}

// Price rallied into the supply zone and CLOSED back below it.
bool AurumSupplyTouch(const AurumCandle &c,const double bottom,const double top,const double tol)
{
   return top>bottom && c.high>=bottom-tol && c.close<bottom;
}

// Zones are removed once a candle CLOSES through them.
bool AurumDemandBroken(const double close,const double bottom) { return close<bottom; }
bool AurumSupplyBroken(const double close,const double top)    { return close>top; }

// ---------- SNR: support and resistance ----------
bool AurumSupportTouch(const AurumCandle &c,const double level,const double tol)
{
   return level>0 && c.low<=level+tol && c.close>level;
}

bool AurumResistanceTouch(const AurumCandle &c,const double level,const double tol)
{
   return level>0 && c.high>=level-tol && c.close<level;
}

// Two levels closer than tol are treated as the same level.
bool AurumSameLevel(const double a,const double b,const double tol)
{
   return AurumAbs(a-b)<=tol;
}

// ---------- Decision ----------
// Confluence points (0-3). A supply/demand zone counts double.
int AurumScore(const bool zone,const bool level)
{
   return (zone?2:0)+(level?1:0);
}

int AurumPointsNeeded(const int mode)
{
   return mode==AURUM_STRICT?3:mode==AURUM_AGGRESSIVE?1:2;
}

// Returns 1 BUY, -1 SELL, 0 none. trendDir: 1 up, -1 down, 0 unknown/flat.
int AurumDecide(const int mode,const int trendDir,
                const bool buyRejection,const int buyScore,
                const bool sellRejection,const int sellScore)
{
   int need=AurumPointsNeeded(mode);
   bool buy=buyRejection && buyScore>=need && trendDir>0;
   bool sell=sellRejection && sellScore>=need && trendDir<0;
   if(buy && sell) return 0;   // conflicting evidence on one candle: stand aside
   return buy?1:sell?-1:0;
}

// ---------- Trade levels ----------
// Stop beyond the structure that was touched, at least minRiskATR x ATR from entry.
double AurumBuyStop(const double entry,const double structureLow,const double atr,
                    const double bufferATR,const double minRiskATR)
{
   double stop=structureLow-bufferATR*atr;
   return AurumMin(stop,entry-minRiskATR*atr);
}

double AurumSellStop(const double entry,const double structureHigh,const double atr,
                     const double bufferATR,const double minRiskATR)
{
   double stop=structureHigh+bufferATR*atr;
   return AurumMax(stop,entry+minRiskATR*atr);
}

// Target = the next opposite area (resistance/supply above a BUY, support/demand below a SELL),
// capped at max(3, minRR) R. With no area, max(2, minRR) R.
// Returns false when that area is closer than minRR x risk: the trade is not worth taking.
// dir: 1 BUY, -1 SELL. nearest: price of the next opposite area, or <=0 if none.
bool AurumTarget(const int dir,const double entry,const double stop,const double nearest,
                 const double minRR,double &tp)
{
   double risk=AurumAbs(entry-stop);
   if(risk<=0 || dir==0) return false;
   if(nearest>0 && (nearest-entry)*dir>0)
   {
      double rr=(nearest-entry)*dir/risk;
      if(rr<minRR) return false;
      tp=entry+dir*AurumMin(rr,AurumMax(3.0,minRR))*risk;
      return true;
   }
   tp=entry+dir*AurumMax(2.0,minRR)*risk;
   return true;
}

// Reward-to-risk of a planned trade (2.0 means 1 : 2).
double AurumRR(const double entry,const double stop,const double tp)
{
   double risk=AurumAbs(entry-stop);
   return risk>0?AurumAbs(tp-entry)/risk:0;
}

// ---------- Trade record (also used for backtesting) ----------
// Follow an open trade for one closed candle. Returns true when the trade closes and sets
// resultR (+R won, -1 lost). Stop loss is checked first, so a candle that touches both the
// stop and the target counts as a LOSS. After maxBars candles the trade closes at the close.
bool AurumTradeStep(const int dir,const double entry,const double stop,const double tp,
                    const AurumCandle &c,const int barsHeld,const int maxBars,double &resultR)
{
   double risk=AurumAbs(entry-stop);
   if(risk<=0) { resultR=0; return true; }
   bool stopHit=dir>0?c.low<=stop:c.high>=stop;
   bool targetHit=dir>0?c.high>=tp:c.low<=tp;
   if(stopHit) { resultR=-1.0; return true; }
   if(targetHit) { resultR=AurumAbs(tp-entry)/risk; return true; }
   if(barsHeld>=maxBars) { resultR=(c.close-entry)*dir/risk; return true; }
   return false;
}

// Lot size for a fixed money risk. moneyPerPricePerLot: account money gained or lost per 1.0
// price move with 1 lot (XAUUSD standard lot of 100 oz in a USD account = 100).
// Rounded DOWN to the lot step. Returns 0 when even the minimum lot risks too much.
double AurumLots(const double riskMoney,const double entry,const double stop,
                 const double moneyPerPricePerLot,const double step,const double minLot)
{
   double distance=AurumAbs(entry-stop);
   if(riskMoney<=0 || distance<=0 || moneyPerPricePerLot<=0 || step<=0) return 0;
   double raw=riskMoney/(distance*moneyPerPricePerLot);
   double lots=step*(double)(long)(raw/step+1e-9);
   return lots>=minLot?lots:0;
}

// Select the latest COMPLETED higher-timeframe bar at the entry candle close.
// Handles an exact boundary, a forming containing bar, and a missing-bar gap.
int AurumClosedTrendShift(const int containing,const long containingOpen,
                          const long decision,const int seconds)
{
   if(containing<0 || containingOpen<=0 || seconds<=0 || containingOpen>decision) return -1;
   return containingOpen+seconds<=decision?containing:containing+1;
}

int AurumTrendDir(const double htfClose,const double htfEMA)
{
   if(!AurumNumber(htfClose) || !AurumNumber(htfEMA) || htfClose<=0 || htfEMA<=0) return 0;
   return htfClose>htfEMA?1:htfClose<htfEMA?-1:0;
}

bool AurumQuoteFresh(const long now,const long tickTime,const int maxAge)
{
   return tickTime>0 && now>=tickTime && now-tickTime<=maxAge;
}

bool AurumAlertOnTime(const long now,const long candleClose,const int maxDelay)
{
   return now>=candleClose && now-candleClose<=maxDelay;
}
#endif
