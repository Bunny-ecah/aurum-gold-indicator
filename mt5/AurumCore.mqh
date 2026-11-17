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

// ---------- Setup quality (information only: it does not change which signals appear) ----------
// Score out of 100:
//   Area:    zone + S/R level 35, zone 25, S/R level only 10
//   Fresh:   +20 when the zone is touched for the first time (zone setups only)
//   Reward:  RR >= 2.5 -> 25, >= 2.0 -> 20, >= 1.5 -> 12, else 5
//   Timing:  London and New York both open 20, one of them 12, neither 0
int AurumQuality(const bool zone,const bool level,const bool fresh,const double rr,
                 const bool london,const bool newYork)
{
   int q=(zone && level)?35:zone?25:level?10:0;
   if(zone && fresh) q+=20;
   q+=rr>=2.5?25:rr>=2.0?20:rr>=1.5?12:5;
   q+=(london && newYork)?20:(london || newYork)?12:0;
   return q;
}

// 0 = A (70+), 1 = B (50-69), 2 = C (below 50)
int AurumGrade(const int quality) { return quality>=70?0:quality>=50?1:2; }

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

// ---------- Trading sessions (all times in UTC seconds since 1970) ----------
#define AURUM_SESSIONS_LONDON_NY 0   // London or New York open
#define AURUM_SESSIONS_LONDON    1
#define AURUM_SESSIONS_NEWYORK   2
#define AURUM_SESSIONS_ALL       3   // no filter

long AurumFloorDiv(const long a,const long b) { return a>=0?a/b:-((-a+b-1)/b); }

// Days since 1970-01-01 for a calendar date (proleptic Gregorian).
long AurumDaysFromCivil(int y,const int m,const int d)
{
   y-=m<=2?1:0;
   long era=AurumFloorDiv(y,400);
   long yoe=y-era*400;
   long doy=(153*(m+(m>2?-3:9))+2)/5+d-1;
   long doe=yoe*365+yoe/4-yoe/100+doy;
   return era*146097+doe-719468;
}

int AurumYearOfDays(const long days)
{
   long z=days+719468;
   long era=AurumFloorDiv(z,146097);
   long doe=z-era*146097;
   long yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   long doy=doe-(365*yoe+yoe/4-yoe/100);
   long mp=(5*doy+2)/153;
   long m=mp<10?mp+3:mp-9;
   return (int)(yoe+era*400+(m<=2?1:0));
}

int AurumWeekday(const long days) { return (int)(((days+4)%7+7)%7); }   // 0 Sunday .. 6 Saturday

long AurumLastSunday(const int y,const int m)
{
   long last=(m==12?AurumDaysFromCivil(y+1,1,1):AurumDaysFromCivil(y,m+1,1))-1;
   return last-AurumWeekday(last);
}

long AurumNthSunday(const int y,const int m,const int n)
{
   long first=AurumDaysFromCivil(y,m,1);
   return first+(7-AurumWeekday(first))%7+7*(n-1);
}

// UK summer time: last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC.
bool AurumUKSummer(const long utc)
{
   int y=AurumYearOfDays(AurumFloorDiv(utc,86400));
   return utc>=AurumLastSunday(y,3)*86400+3600 && utc<AurumLastSunday(y,10)*86400+3600;
}

// US daylight time: second Sunday of March 02:00 EST -> first Sunday of November 02:00 EDT.
bool AurumUSSummer(const long utc)
{
   int y=AurumYearOfDays(AurumFloorDiv(utc,86400));
   return utc>=AurumNthSunday(y,3,2)*86400+7*3600 && utc<AurumNthSunday(y,11,1)*86400+6*3600;
}

// Monday-Friday, 08:00-17:00 local time.
bool AurumLocalSessionOpen(const long local)
{
   long day=AurumFloorDiv(local,86400);
   long sec=local-day*86400;
   int wd=AurumWeekday(day);
   return wd>=1 && wd<=5 && sec>=8*3600 && sec<17*3600;
}

bool AurumLondonOpen(const long utc) { return AurumLocalSessionOpen(utc+(AurumUKSummer(utc)?3600:0)); }
bool AurumNewYorkOpen(const long utc) { return AurumLocalSessionOpen(utc-5*3600+(AurumUSSummer(utc)?3600:0)); }

// New trades are allowed only inside the chosen session (candle OPEN time, UTC).
bool AurumSessionAllowed(const int sessions,const long utc)
{
   if(sessions==AURUM_SESSIONS_ALL) return true;
   bool london=AurumLondonOpen(utc),newYork=AurumNewYorkOpen(utc);
   if(sessions==AURUM_SESSIONS_LONDON) return london;
   if(sessions==AURUM_SESSIONS_NEWYORK) return newYork;
   return london || newYork;
}

// Broker server clock -> UTC. Most UTC+2/UTC+3 brokers move their clock with US daylight time.
// winterOffset: server minus UTC in winter (seconds).
long AurumServerOffset(const long winterOffset,const bool followsUS,const long serverTime)
{
   return winterOffset+((followsUS && AurumUSSummer(serverTime-winterOffset))?3600:0);
}

// From the live measured offset (server minus UTC, seconds): guess the winter offset and DST habit.
void AurumAutoServerZone(const long measured,const long nowUTC,long &winterOffset,bool &followsUS)
{
   followsUS=measured==7200 || measured==10800;
   winterOffset=measured-((followsUS && AurumUSSummer(nowUTC))?3600:0);
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
