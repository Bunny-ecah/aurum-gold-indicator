#include "../AurumCore.mqh"

// Tests for the shared v3 decision core (SNR + SND + Fibonacci).
// Windows: run-tests.cmd builds a freestanding DLL and runs it from Python.
// Linux/macOS: g++ -std=c++17 -DAURUM_TEST_MAIN tests/core_tests.cpp -o core_tests && ./core_tests
#ifdef _MSC_VER
// Freestanding DLL harness: no Windows SDK or C runtime dependency required.
extern "C" {
int _fltused=0;
void *memset(void *target,int value,unsigned long long count)
{ unsigned char *p=(unsigned char*)target; for(unsigned long long i=0;i<count;i++) p[i]=(unsigned char)value; return target; }
void *memcpy(void *target,const void *source,unsigned long long count)
{ unsigned char *p=(unsigned char*)target; const unsigned char *q=(const unsigned char*)source;
  for(unsigned long long i=0;i<count;i++) p[i]=q[i]; return target; }
}
#define AURUM_EXPORT extern "C" __declspec(dllexport)
#else
#define AURUM_EXPORT extern "C"
#endif

int checks=0,failures=0;
const char *firstFailure="";
void Check(bool passed,const char* name)
{
   checks++;
   if(!passed) { if(failures==0) firstFailure=name; failures++; }
}
bool Near(double a,double b) { return AurumAbs(a-b)<1e-9; }

AurumCandle C(double o,double h,double l,double c,double atr=4)
{
   AurumCandle x; x.open=o; x.high=h; x.low=l; x.close=c; x.atr=atr; return x;
}
AurumSwing S(double high,double low,int dir)
{
   AurumSwing s; s.high=high; s.low=low; s.dir=dir; return s;
}

AURUM_EXPORT int RunTests()
{
   checks=0; failures=0;
   double b=0,t=0;

   // --- Candle validity
   Check(AurumCandleValid(C(2650,2654,2649,2653)),"valid candle");
   Check(!AurumCandleValid(C(2650,2649,2654,2653)),"high below low rejected");
   Check(!AurumCandleValid(C(2650,2654,2649,2653,0)),"zero ATR rejected");
   Check(!AurumCandleValid(C(2650,2654,2649,2655)),"close above high rejected");

   // --- Rejection candles
   Check(AurumBullRejection(C(2650,2654,2649,2653)),"bullish close is BUY rejection");
   Check(!AurumBullRejection(C(2653,2654,2649,2650)),"bearish close without wick is not BUY rejection");
   Check(AurumBullRejection(C(2653,2654,2644,2652.5)),"red hammer with long lower wick counts");
   Check(!AurumBullRejection(C(2650,2650,2650,2650)),"zero-range candle rejected");
   Check(AurumBearRejection(C(2653,2654,2649,2650)),"bearish close is SELL rejection");
   Check(AurumBearRejection(C(2645,2655,2644,2645.5)),"green shooting star counts");
   Check(!AurumBearRejection(C(2650,2654,2649,2653)),"bullish close is not SELL rejection");

   // --- Demand zone creation
   AurumCandle base=C(2652,2653,2649,2650), impulse=C(2650,2660,2649.5,2659);
   Check(AurumDemandZone(base,impulse,1.5,b,t),"strong bullish impulse creates demand");
   Check(Near(b,2649) && Near(t,2652),"demand = lowest low to base body top");
   impulse=C(2650,2653.5,2649.5,2653.4);
   Check(!AurumDemandZone(base,impulse,1.5,b,t),"weak impulse body does not create demand");
   impulse=C(2645,2652.9,2644,2652.8);
   Check(!AurumDemandZone(base,impulse,1.5,b,t),"impulse must close above base high");
   base=C(2650,2650.5,2649.9,2650.2); impulse=C(2650,2660,2649.95,2659);
   Check(AurumDemandZone(base,impulse,1.5,b,t) && Near(t-b,0.8),"thin demand widened to 0.2 ATR");
   base=C(2650,2652,2638,2651); impulse=C(2651,2661,2650,2660);
   Check(!AurumDemandZone(base,impulse,1.5,b,t),"zone taller than 2 ATR rejected");

   // --- Supply zone creation
   base=C(2650,2653,2649,2652); impulse=C(2652,2652.5,2642,2643);
   Check(AurumSupplyZone(base,impulse,1.5,b,t),"strong bearish impulse creates supply");
   Check(Near(t,2653) && Near(b,2650),"supply = base body bottom to highest high");
   impulse=C(2652,2652.5,2649.5,2649.8);
   Check(!AurumSupplyZone(base,impulse,1.5,b,t),"weak bearish impulse does not create supply");

   // --- Zone touches
   Check(AurumDemandTouch(C(2654,2655,2651.5,2654.5),2649,2652,0.8),"dip into demand and close above = touch");
   Check(AurumDemandTouch(C(2654,2655,2652.6,2654.5),2649,2652,0.8),"near-miss within tolerance counts");
   Check(!AurumDemandTouch(C(2654,2655,2653,2654.5),2649,2652,0.8),"no dip = no touch");
   Check(!AurumDemandTouch(C(2654,2655,2650,2651),2649,2652,0.8),"close inside zone is not confirmation");
   Check(AurumSupplyTouch(C(2647,2650.5,2646,2646.5),2650,2653,0.8),"rally into supply and close below = touch");
   Check(!AurumSupplyTouch(C(2647,2650.5,2646,2651),2650,2653,0.8),"close inside supply is not confirmation");
   Check(AurumDemandBroken(2648.9,2649) && !AurumDemandBroken(2649,2649),"demand broken only by close below");
   Check(AurumSupplyBroken(2653.1,2653) && !AurumSupplyBroken(2653,2653),"supply broken only by close above");

   // --- Support / resistance
   Check(AurumSupportTouch(C(2652,2653,2649.9,2652.5),2650,0.8),"wick to support and close above");
   Check(!AurumSupportTouch(C(2652,2653,2649.9,2649.95),2650,0.8),"close below support is not a bounce");
   Check(!AurumSupportTouch(C(2652,2653,2651,2652.5),2650,0.8),"too far above support");
   Check(!AurumSupportTouch(C(2652,2653,2649.9,2652.5),0,0.8),"missing level ignored");
   Check(AurumResistanceTouch(C(2648,2650.2,2647,2647.5),2650,0.8),"wick to resistance and close below");
   Check(!AurumResistanceTouch(C(2648,2650.2,2647,2650.1),2650,0.8),"close above resistance is a breakout");
   Check(AurumSameLevel(2650,2650.3,0.4) && !AurumSameLevel(2650,2650.5,0.4),"level merge tolerance");

   // --- Fibonacci
   AurumSwing up=S(2700,2600,1), down=S(2700,2600,-1);
   Check(Near(AurumFibPrice(up,0.5),2650) && Near(AurumFibPrice(up,0.786),2621.4),"up-swing retracements");
   Check(Near(AurumFibPrice(down,0.5),2650) && Near(AurumFibPrice(down,0.786),2678.6),"down-swing retracements");
   Check(Near(AurumFibPrice(up,0),2700) && Near(AurumFibPrice(up,1),2600),"0 = swing end, 1 = swing start");
   Check(Near(AurumFibExtension(up,1.618),2761.8),"up-swing 1.618 extension");
   Check(Near(AurumFibExtension(down,1.618),2538.2),"down-swing 1.618 extension");
   Check(AurumFibBuy(C(2648,2652,2640,2649),up,0.8),"BUY pullback inside golden zone");
   Check(!AurumFibBuy(C(2658,2662,2655,2660),up,0.8),"shallow pullback is not golden zone");
   Check(!AurumFibBuy(C(2620,2625,2610,2622),up,0.8),"too deep: below 0.786");
   Check(!AurumFibBuy(C(2648,2652,2640,2649),down,0.8),"no BUY fib in a down-swing");
   Check(AurumFibSell(C(2652,2660,2648,2651),down,0.8),"SELL pullback inside golden zone");
   Check(!AurumFibSell(C(2652,2660,2648,2651),up,0.8),"no SELL fib in an up-swing");
   Check(!AurumFibBuy(C(2648,2652,2640,2649),S(2600,2700,1),0.8),"invalid swing ignored");

   // --- Decision
   Check(AurumScore(true,false,false)==2 && AurumScore(false,true,true)==2,"zone counts double");
   Check(AurumScore(true,true,true)==4 && AurumScore(false,false,false)==0,"score range 0-4");
   Check(AurumPointsNeeded(AURUM_AGGRESSIVE)==1 && AurumPointsNeeded(AURUM_BALANCED)==2 && AurumPointsNeeded(AURUM_STRICT)==3,"points per mode");
   Check(AurumDecide(AURUM_BALANCED,1,true,2,false,0)==1,"balanced BUY: trend + zone");
   Check(AurumDecide(AURUM_BALANCED,1,true,1,false,0)==0,"balanced needs 2 points");
   Check(AurumDecide(AURUM_BALANCED,-1,true,4,false,0)==0,"BUY blocked against trend");
   Check(AurumDecide(AURUM_BALANCED,0,true,4,false,0)==0,"BUY blocked with unknown trend");
   Check(AurumDecide(AURUM_BALANCED,1,false,4,false,0)==0,"no rejection candle = no signal");
   Check(AurumDecide(AURUM_BALANCED,-1,false,0,true,2)==-1,"balanced SELL");
   Check(AurumDecide(AURUM_STRICT,1,true,2,false,0)==0,"strict needs 3 points");
   Check(AurumDecide(AURUM_STRICT,1,true,3,false,0)==1,"strict BUY: zone + S/R");
   Check(AurumDecide(AURUM_AGGRESSIVE,1,true,1,false,0)==1,"aggressive BUY: 1 point");
   Check(AurumDecide(AURUM_AGGRESSIVE,-1,true,1,false,0)==0,"aggressive still follows trend");
   Check(AurumDecide(AURUM_AGGRESSIVE,1,true,1,true,1)==1,"trend picks the side when both areas touched");
   Check(AurumCooldownOK(10,-1,5) && !AurumCooldownOK(10,5,5) && AurumCooldownOK(11,5,5),"cooldown");

   // --- Stops and targets
   double sl=AurumBuyStop(2655,2649,4,0.2,0.5);
   Check(Near(sl,2648.2),"BUY stop below structure + buffer");
   sl=AurumBuyStop(2650,2649.9,4,0.2,0.5);
   Check(Near(sl,2648),"BUY stop respects minimum risk");
   sl=AurumSellStop(2645,2653,4,0.2,0.5);
   Check(Near(sl,2653.8),"SELL stop above structure + buffer");
   sl=AurumSellStop(2650,2650.1,4,0.2,0.5);
   Check(Near(sl,2652),"SELL stop respects minimum risk");
   double tp1=0,tp2=0;
   AurumBuyTargets(2650,2645,2660,2680,tp1,tp2);
   Check(Near(tp1,2660) && Near(tp2,2680),"BUY TP1 = resistance, TP2 = fib 1.618");
   AurumBuyTargets(2650,2645,0,0,tp1,tp2);
   Check(Near(tp1,2657.5) && Near(tp2,2662.5),"BUY fallback 1.5R / 2.5R");
   AurumBuyTargets(2650,2645,2660,2661,tp1,tp2);
   Check(Near(tp1,2660) && Near(tp2,2665),"BUY fib too close to TP1 -> TP1 + 1R");
   AurumSellTargets(2650,2655,2640,2620,tp1,tp2);
   Check(Near(tp1,2640) && Near(tp2,2620),"SELL TP1 = support, TP2 = fib 1.618");
   AurumSellTargets(2650,2655,0,0,tp1,tp2);
   Check(Near(tp1,2642.5) && Near(tp2,2637.5),"SELL fallback 1.5R / 2.5R");
   AurumSellTargets(2650,2655,2647,0,tp1,tp2);
   Check(Near(tp1,2642.5),"SELL target closer than 1R ignored");

   // --- Higher timeframe
   Check(AurumTrendDir(2650,2600)==1 && AurumTrendDir(2550,2600)==-1 && AurumTrendDir(2600,2600)==0,"trend direction");
   Check(AurumTrendDir(0,2600)==0,"missing HTF data = no trend");
   Check(AurumClosedTrendShift(0,1000,4600,3600)==0,"HTF bar closed exactly at decision");
   Check(AurumClosedTrendShift(0,1000,4599,3600)==1,"forming HTF bar skipped");
   Check(AurumClosedTrendShift(-1,1000,4600,3600)==-1,"missing HTF bar");
   Check(AurumQuoteFresh(100,90,30) && !AurumQuoteFresh(100,60,30),"quote freshness");
   Check(AurumAlertOnTime(100,90,30) && !AurumAlertOnTime(100,60,30),"alert window");

   return failures==0?0:1;
}
AURUM_EXPORT int CheckCount() { return checks; }
AURUM_EXPORT int FailureCount() { return failures; }

#ifdef AURUM_TEST_MAIN
#include <cstdio>
int main()
{
   int result=RunTests();
   std::printf("%d checks, %d failures\n",checks,failures);
   if(failures) std::printf("first failure: %s\n",firstFailure);
   return result;
}
#endif
