#include "../AurumCore.mqh"

// Freestanding DLL harness: no Windows SDK or C runtime dependency required.
extern "C" {
int _fltused=0;
void *memset(void *target,int value,unsigned long long count)
{ unsigned char *p=(unsigned char*)target; for(unsigned long long i=0;i<count;i++) p[i]=(unsigned char)value; return target; }
void *memcpy(void *target,const void *source,unsigned long long count)
{ unsigned char *p=(unsigned char*)target; const unsigned char *q=(const unsigned char*)source;
  for(unsigned long long i=0;i<count;i++) p[i]=q[i]; return target; }
}
double Special(unsigned long long bits)
{ union { unsigned long long bits; double number; } value; value.bits=bits; return value.number; }

int checks=0,failures=0;
void Check(bool passed,const char* name)
{
   checks++;
   (void)name;
   if(!passed) failures++;
}
AurumRules Rules()
{
   AurumRules p={};
   p.buyMin=55; p.buyMax=70; p.sellMin=30; p.sellMax=45;
   p.maxRangeATR=2; p.maxSpread=0.5;
   p.rejectZeroSpread=true; p.directionalCandle=true;
   return p;
}
AurumBar BuyBar()
{
   AurumBar b={};
   b.open=2650; b.high=2654; b.low=2649; b.close=2653;
   b.fast=2651; b.slow=2648; b.rsi=60; b.atr=4; b.previousATR=4;
   b.previousHigh=2652; b.previousLow=2645;
   b.trendClose=2640; b.trendEMA=2630; b.spread=0.3;
   return b;
}
AurumBar SellBar()
{
   AurumBar b=BuyBar();
   b.open=2650; b.high=2651; b.low=2646; b.close=2647;
   b.fast=2649; b.slow=2652; b.rsi=40;
   b.previousHigh=2655; b.previousLow=2648;
   b.trendClose=2630; b.trendEMA=2640;
   return b;
}
int Direction(const AurumBar &b,const AurumRules &p)
{ AurumResult r={}; AurumEvaluate(b,p,r); return r.raw; }

extern "C" __declspec(dllexport) int RunTests()
{
   checks=0; failures=0;
   AurumRules p=Rules(); AurumBar b=BuyBar(); AurumResult r={};
   AurumEvaluate(b,p,r);
   Check(r.valid && r.raw==1 && r.buyCount==4,"all BUY rules");
   Check(Direction(SellBar(),p)==-1,"all SELL rules");
   b=BuyBar(); b.trendClose=b.trendEMA; Check(Direction(b,p)==0,"equal HTF EMA neutral");
   b=BuyBar(); b.fast=b.slow; Check(Direction(b,p)==0,"equal entry EMAs neutral");
   b=BuyBar(); b.fast=b.close; Check(Direction(b,p)==0,"price must exceed fast EMA");
   b=BuyBar(); b.rsi=54.99; Check(Direction(b,p)==0,"BUY RSI below threshold");
   b.rsi=55; Check(Direction(b,p)==1,"BUY lower RSI inclusive");
   b.rsi=70; Check(Direction(b,p)==1,"BUY upper RSI inclusive");
   b.rsi=70.01; Check(Direction(b,p)==0,"BUY RSI overextension");
   b=SellBar(); b.rsi=30; Check(Direction(b,p)==-1,"SELL lower RSI inclusive");
   b.rsi=45; Check(Direction(b,p)==-1,"SELL upper RSI inclusive");
   b.rsi=29.99; Check(Direction(b,p)==0,"SELL RSI overextension");
   b=BuyBar(); b.previousHigh=b.close; Check(Direction(b,p)==0,"touch is not breakout");
   b=BuyBar(); p.breakoutBufferATR=0.25; Check(Direction(b,p)==0,"ATR buffer exact boundary rejected");
   p.breakoutBufferATR=0.24; Check(Direction(b,p)==1,"ATR buffer exceeded"); p=Rules();
   b=BuyBar(); b.open=2654; Check(Direction(b,p)==0,"bearish BUY candle rejected");
   p.directionalCandle=false; Check(Direction(b,p)==1,"directional filter optional"); p=Rules();
   b=BuyBar(); b.spread=0.5; Check(Direction(b,p)==1,"spread limit inclusive");
   b.spread=0.501; Check(Direction(b,p)==0,"excess spread rejected");
   b.spread=0; Check(Direction(b,p)==0,"unknown zero spread blocked by default");
   p.rejectZeroSpread=false; Check(Direction(b,p)==1,"explicit zero spread override");
   b.spread=-1; Check(Direction(b,p)==0,"negative spread always rejected"); p=Rules();
   b=BuyBar(); b.previousATR=2; b.atr=100; Check(Direction(b,p)==0,"large signal candle cannot inflate range cap");
   b=BuyBar(); p.minATR=4; p.maxATR=4; Check(Direction(b,p)==1,"ATR bounds inclusive");
   p.minATR=4.1; Check(Direction(b,p)==0,"ATR lower bound");
   p=Rules(); p.maxATR=3.9; Check(Direction(b,p)==0,"ATR upper bound"); p=Rules();
   b=BuyBar(); b.atr=0; Check(Direction(b,p)==0,"zero ATR rejected");
   b=BuyBar(); b.previousATR=-1; Check(Direction(b,p)==0,"negative previous ATR rejected");
   b=BuyBar(); b.fast=Special(0x7ff8000000000000ULL); Check(Direction(b,p)==0,"NaN rejected");
   b=BuyBar(); b.trendEMA=Special(0x7ff0000000000000ULL); Check(Direction(b,p)==0,"infinity rejected");
   b=BuyBar(); b.slow=Special(0x7fefffffffffffffULL); Check(Direction(b,p)==0,"MQL EMPTY_VALUE rejected");
   b=BuyBar(); b.close=b.high+1; Check(Direction(b,p)==0,"invalid OHLC rejected");
   b=BuyBar(); b.open=b.low-1; Check(Direction(b,p)==0,"invalid open rejected");
   b=BuyBar(); b.rsi=101; Check(Direction(b,p)==0,"invalid RSI rejected");
   Check(AurumClosedTrendShift(0,3600,3900,900)==1,"forming HTF uses prior bar");
   Check(AurumClosedTrendShift(0,4500,4500,900)==1,"exact boundary uses just completed previous bar");
   Check(AurumClosedTrendShift(3,3600,4500,900)==3,"gap uses containing HTF if nominally closed");
   Check(AurumClosedTrendShift(3,3600,7200,900)==3,"weekend/history gap cannot use future HTF");
   Check(AurumClosedTrendShift(-1,3600,3900,900)==-1,"missing HTF rejected");
   Check(AurumClosedTrendShift(0,4500,3900,900)==-1,"future HTF rejected");
   Check(AurumQuoteFresh(100,70,30),"quote age exact boundary");
   Check(!AurumQuoteFresh(100,69,30),"stale quote rejected");
   Check(!AurumQuoteFresh(100,101,30),"future quote rejected");
   Check(!AurumQuoteFresh(100,0,30),"absent quote rejected");
   Check(AurumAlertOnTime(1060,1000,60),"alert delay exact boundary");
   Check(!AurumAlertOnTime(1061,1000,60),"late alert rejected");
   Check(!AurumAlertOnTime(999,1000,60),"future candle alert rejected");
   Check(AurumQuietBar(1,true,false),"new isolated candidate accepted");
   Check(AurumQuietBar(-1,true,false),"isolated sell candidate accepted");
   Check(!AurumQuietBar(1,true,true),"candidate in quiet period rejected");
   Check(!AurumQuietBar(1,false,false),"incomplete quiet history rejected");
   Check(!AurumQuietBar(0,true,false),"absent candidate rejected");
   // Long sequences: overlapping visible windows must give identical shared signals.
   int raw[300]={}; bool accepted[300]={};
   for(int i=0;i<300;i++) raw[i]=(i%7==0 || i%7==1)?1:0;
   for(int start=20;start<=100;start+=20)
      for(int i=start;i<250;i++)
      {
         bool recent=false;
         for(int j=1;j<=3;j++) if(raw[i-j]!=0) recent=true;
         bool current=AurumQuietBar(raw[i],true,recent);
         if(start==20) accepted[i]=current;
         else Check(current==accepted[i],"window-independent candidate cooldown");
      }
   // Repeated raw candidates cannot alert repeatedly until three quiet candles elapsed.
   Check(accepted[21] && !accepted[22] && accepted[28],"cluster fires once then requires quiet candles");
   return failures?1:0;
}
extern "C" __declspec(dllexport) int CheckCount() { return checks; }
extern "C" __declspec(dllexport) int FailureCount() { return failures; }
