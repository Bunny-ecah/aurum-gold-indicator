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

// Same-direction signals need a gap of more than cooldown candles. lastBar<0 = none yet.
bool AurumCooldownOK(const int bar,const int lastBar,const int cooldown)
{
   return lastBar<0 || bar-lastBar>cooldown;
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

// TP1 = nearest opposing area (resistance or supply) at least 1R away, else 1.5R.
// TP2 = the next opposing area at least 0.5R beyond TP1, else TP1 + 1R.
// Pass <=0 when there is no such area.
double AurumBuyTP1(const double entry,const double stop,const double nearest)
{
   double risk=entry-stop;
   return nearest>=entry+risk?nearest:entry+1.5*risk;
}

double AurumBuyTP2(const double entry,const double stop,const double tp1,const double next)
{
   double risk=entry-stop;
   return next>=tp1+0.5*risk?next:tp1+risk;
}

double AurumSellTP1(const double entry,const double stop,const double nearest)
{
   double risk=stop-entry;
   return (nearest>0 && nearest<=entry-risk)?nearest:entry-1.5*risk;
}

double AurumSellTP2(const double entry,const double stop,const double tp1,const double next)
{
   double risk=stop-entry;
   return (next>0 && next<=tp1-0.5*risk)?next:tp1-risk;
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
