// Shared, platform-independent decision functions. Also compiled by tests/core_tests.cpp.
#ifndef AURUM_CORE_MQH
#define AURUM_CORE_MQH

struct AurumRules
{
   double buyMin,buyMax,sellMin,sellMax;
   double minATR,maxATR,maxRangeATR,maxSpread;
   double breakoutBufferATR;
   bool rejectZeroSpread,directionalCandle;
};

struct AurumBar
{
   double open,high,low,close,fast,slow,rsi,atr,previousATR;
   double previousHigh,previousLow,trendClose,trendEMA,spread;
};

struct AurumResult
{
   bool valid,trendBuy,trendSell,emaBuy,emaSell,rsiBuy,rsiSell,breakBuy,breakSell;
   bool spreadOK,atrOK,rangeOK,candleBuy,candleSell;
   int buyCount,sellCount,raw;
};

bool AurumNumber(const double x)
{
   return x==x && x>-1.0e100 && x<1.0e100;
}

// Select the latest nominally completed HTF bar at the entry candle close.
// Handles an exact boundary, a forming containing bar, and a missing-bar gap.
int AurumClosedTrendShift(const int containing,const long containingOpen,
                          const long decision,const int seconds)
{
   if(containing<0 || containingOpen<=0 || seconds<=0 || containingOpen>decision) return -1;
   return containingOpen+seconds<=decision?containing:containing+1;
}

bool AurumQuoteFresh(const long now,const long tickTime,const int maxAge)
{
   return tickTime>0 && now>=tickTime && now-tickTime<=maxAge;
}

bool AurumAlertOnTime(const long now,const long candleClose,const int maxDelay)
{
   return now>=candleClose && now-candleClose<=maxDelay;
}

// Candidate-based quiet period, independent of the visible history-window start.
bool AurumQuietBar(const int raw,const bool historyValid,const bool recentCandidate)
{
   return raw!=0 && historyValid && !recentCandidate;
}

void AurumEvaluate(const AurumBar &b,const AurumRules &p,AurumResult &r)
{
   r.valid=AurumNumber(b.open) && AurumNumber(b.high) && AurumNumber(b.low) &&
      AurumNumber(b.close) && AurumNumber(b.fast) && AurumNumber(b.slow) &&
      AurumNumber(b.rsi) && AurumNumber(b.atr) && AurumNumber(b.previousATR) &&
      AurumNumber(b.previousHigh) && AurumNumber(b.previousLow) &&
      AurumNumber(b.trendClose) && AurumNumber(b.trendEMA) && AurumNumber(b.spread) &&
      b.open>0 && b.low>0 && b.close>0 && b.fast>0 && b.slow>0 &&
      b.high>=b.low && b.close<=b.high && b.close>=b.low &&
      b.open<=b.high && b.open>=b.low && b.rsi>=0 && b.rsi<=100 &&
      b.atr>0 && b.previousATR>0 && b.previousHigh>=b.previousLow &&
      b.previousLow>0 && b.trendClose>0 && b.trendEMA>0;
   r.trendBuy=false; r.trendSell=false; r.emaBuy=false; r.emaSell=false;
   r.rsiBuy=false; r.rsiSell=false; r.breakBuy=false; r.breakSell=false;
   r.spreadOK=false; r.atrOK=false; r.rangeOK=false;
   r.candleBuy=false; r.candleSell=false; r.buyCount=0; r.sellCount=0; r.raw=0;
   if(!r.valid) return;
   r.trendBuy=b.trendClose>b.trendEMA; r.trendSell=b.trendClose<b.trendEMA;
   r.emaBuy=b.fast>b.slow && b.close>b.fast;
   r.emaSell=b.fast<b.slow && b.close<b.fast;
   r.rsiBuy=b.rsi>=p.buyMin && b.rsi<=p.buyMax;
   r.rsiSell=b.rsi>=p.sellMin && b.rsi<=p.sellMax;
   double margin=p.breakoutBufferATR*b.previousATR;
   r.breakBuy=b.close>b.previousHigh+margin;
   r.breakSell=b.close<b.previousLow-margin;
   r.spreadOK=b.spread>=0 && (!p.rejectZeroSpread || b.spread>0) && b.spread<=p.maxSpread;
   r.atrOK=b.atr>=p.minATR && (p.maxATR==0 || b.atr<=p.maxATR);
   // Previous ATR prevents the signal candle itself from inflating its range allowance.
   r.rangeOK=b.high-b.low<=p.maxRangeATR*b.previousATR;
   r.candleBuy=!p.directionalCandle || b.close>b.open;
   r.candleSell=!p.directionalCandle || b.close<b.open;
   r.buyCount=(int)r.trendBuy+(int)r.emaBuy+(int)r.rsiBuy+(int)r.breakBuy;
   r.sellCount=(int)r.trendSell+(int)r.emaSell+(int)r.rsiSell+(int)r.breakSell;
   if(r.spreadOK && r.atrOK && r.rangeOK)
   {
      if(r.buyCount==4 && r.candleBuy) r.raw=1;
      else if(r.sellCount==4 && r.candleSell) r.raw=-1;
   }
}
#endif
