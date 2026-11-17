#include "../AurumCore.mqh"

// Tests for the shared v3 decision core (SNR + SND).
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

   // --- Decision
   Check(AurumScore(true,false)==2 && AurumScore(false,true)==1,"zone counts double");
   Check(AurumScore(true,true)==3 && AurumScore(false,false)==0,"score range 0-3");
   Check(AurumPointsNeeded(AURUM_AGGRESSIVE)==1 && AurumPointsNeeded(AURUM_BALANCED)==2 && AurumPointsNeeded(AURUM_STRICT)==3,"points per mode");
   Check(AurumDecide(AURUM_BALANCED,1,true,2,false,0)==1,"balanced BUY: trend + zone");
   Check(AurumDecide(AURUM_BALANCED,1,true,1,false,0)==0,"balanced needs 2 points");
   Check(AurumDecide(AURUM_BALANCED,-1,true,3,false,0)==0,"BUY blocked against trend");
   Check(AurumDecide(AURUM_BALANCED,0,true,3,false,0)==0,"BUY blocked with unknown trend");
   Check(AurumDecide(AURUM_BALANCED,1,false,4,false,0)==0,"no rejection candle = no signal");
   Check(AurumDecide(AURUM_BALANCED,-1,false,0,true,2)==-1,"balanced SELL");
   Check(AurumDecide(AURUM_STRICT,1,true,2,false,0)==0,"strict needs 3 points");
   Check(AurumDecide(AURUM_STRICT,1,true,3,false,0)==1,"strict BUY: zone + S/R");
   Check(AurumDecide(AURUM_AGGRESSIVE,1,true,1,false,0)==1,"aggressive BUY: 1 point");
   Check(AurumDecide(AURUM_AGGRESSIVE,-1,true,1,false,0)==0,"aggressive still follows trend");
   Check(AurumDecide(AURUM_AGGRESSIVE,1,true,1,true,1)==1,"trend picks the side when both areas touched");

   // --- Stops and targets
   double sl=AurumBuyStop(2655,2649,4,0.2,0.5);
   Check(Near(sl,2648.2),"BUY stop below structure + buffer");
   sl=AurumBuyStop(2650,2649.9,4,0.2,0.5);
   Check(Near(sl,2648),"BUY stop respects minimum risk");
   sl=AurumSellStop(2645,2653,4,0.2,0.5);
   Check(Near(sl,2653.8),"SELL stop above structure + buffer");
   sl=AurumSellStop(2650,2650.1,4,0.2,0.5);
   Check(Near(sl,2652),"SELL stop respects minimum risk");
   double tp=0,r=0;
   Check(AurumTarget(1,2650,2645,2660,1.5,tp) && Near(tp,2660),"BUY TP = next resistance (2R)");
   Check(!AurumTarget(1,2650,2645,2656,1.5,tp),"BUY skipped: resistance only 1.2R away");
   Check(AurumTarget(1,2650,2645,2690,1.5,tp) && Near(tp,2665),"BUY TP capped at 3R");
   Check(AurumTarget(1,2650,2645,0,1.5,tp) && Near(tp,2660),"BUY no area -> 2R");
   Check(AurumTarget(1,2650,2645,2640,1.5,tp) && Near(tp,2660),"area below a BUY is ignored");
   Check(AurumTarget(1,2650,2645,0,2.5,tp) && Near(tp,2662.5),"fallback never below minRR");
   Check(AurumTarget(-1,2650,2655,2640,1.5,tp) && Near(tp,2640),"SELL TP = next support");
   Check(!AurumTarget(-1,2650,2655,2645,1.5,tp),"SELL skipped: support only 1R away");
   Check(AurumTarget(-1,2650,2655,0,1.5,tp) && Near(tp,2640),"SELL no area -> 2R");
   Check(!AurumTarget(1,2650,2650,0,1.5,tp),"zero risk rejected");
   Check(Near(AurumRR(2650,2645,2660),2.0) && Near(AurumRR(2650,2655,2642.5),1.5),"reward to risk");

   // --- Trade record
   Check(!AurumTradeStep(1,2650,2645,2660,C(2650,2655,2647,2652),1,100,r),"BUY still open");
   Check(AurumTradeStep(1,2650,2645,2660,C(2652,2661,2650,2658),2,100,r) && Near(r,2.0),"BUY TP hit = +2R");
   Check(AurumTradeStep(1,2650,2645,2660,C(2648,2649,2644,2646),2,100,r) && Near(r,-1.0),"BUY SL hit = -1R");
   Check(AurumTradeStep(1,2650,2645,2660,C(2650,2662,2644,2655),2,100,r) && Near(r,-1.0),"SL and TP in one candle = loss");
   Check(AurumTradeStep(1,2650,2645,2660,C(2650,2653,2648,2652.5),100,100,r) && Near(r,0.5),"expired at close +0.5R");
   Check(AurumTradeStep(-1,2650,2655,2640,C(2645,2646,2639,2641),3,100,r) && Near(r,2.0),"SELL TP hit = +2R");
   Check(AurumTradeStep(-1,2650,2655,2640,C(2652,2656,2651,2654),3,100,r) && Near(r,-1.0),"SELL SL hit = -1R");

   // --- Lot size
   Check(Near(AurumLots(10,2650,2645,100,0.01,0.01),0.02),"$10 risk, $5 stop, 100 oz = 0.02 lot");
   Check(Near(AurumLots(100,2650,2647,100,0.01,0.01),0.33),"lots rounded down");
   Check(AurumLots(1,2650,2645,100,0.01,0.01)==0,"below minimum lot = 0");
   Check(AurumLots(10,2650,2650,100,0.01,0.01)==0,"zero stop distance = 0");

   // --- Trading sessions (vectors from the IANA time-zone database)
   Check(AurumLondonOpen(1768377540)==0 && AurumNewYorkOpen(1768377540)==0,"Wed 07:59 London winter: closed");
   Check(AurumLondonOpen(1768377600)==1 && AurumNewYorkOpen(1768377600)==0,"Wed 08:00 London winter: open");
   Check(AurumLondonOpen(1768395600)==1 && AurumNewYorkOpen(1768395600)==1,"Wed 13:00 UTC winter: London + New York");
   Check(AurumLondonOpen(1768409940)==1 && AurumNewYorkOpen(1768409940)==1,"Wed 16:59 UTC winter: both");
   Check(AurumLondonOpen(1768410000)==0 && AurumNewYorkOpen(1768410000)==1,"Wed 17:00 UTC winter: London closed");
   Check(AurumLondonOpen(1768427940)==0 && AurumNewYorkOpen(1768427940)==1,"Wed 21:59 UTC winter: NY 16:59");
   Check(AurumLondonOpen(1768428000)==0 && AurumNewYorkOpen(1768428000)==0,"Wed 22:00 UTC winter: NY closed");
   Check(AurumLondonOpen(1784098800)==1 && AurumNewYorkOpen(1784098800)==0,"Jul 07:00 UTC = London 08:00 BST");
   Check(AurumLondonOpen(1784116800)==1 && AurumNewYorkOpen(1784116800)==1,"Jul 12:00 UTC = NY 08:00 EDT");
   Check(AurumLondonOpen(1784149200)==0 && AurumNewYorkOpen(1784149200)==0,"Jul 21:00 UTC = NY 17:00 EDT closed");
   Check(AurumLondonOpen(1773144000)==1 && AurumNewYorkOpen(1773144000)==1,"US summer started, UK not yet (Mar 10)");
   Check(AurumLondonOpen(1773126000)==0 && AurumNewYorkOpen(1773126000)==0,"UK still winter on Mar 10");
   Check(AurumLondonOpen(1774854000)==1 && AurumNewYorkOpen(1774854000)==0,"UK summer from Mar 29");
   Check(AurumLondonOpen(1793361600)==1 && AurumNewYorkOpen(1793361600)==1,"UK winter, US still summer (Oct 30)");
   Check(AurumLondonOpen(1794900600)==0 && AurumNewYorkOpen(1794900600)==0,"Today 15:30 Malaysia: before London");
   Check(AurumLondonOpen(1794904200)==1 && AurumNewYorkOpen(1794904200)==0,"Today 16:30 Malaysia: London");
   Check(AurumLondonOpen(1768651200)==0 && AurumNewYorkOpen(1768651200)==0,"Saturday: closed");
   Check(AurumLondonOpen(1768744800)==0 && AurumNewYorkOpen(1768744800)==0,"Sunday: closed");
   Check(AurumLondonOpen(1709197200)==1 && AurumNewYorkOpen(1709197200)==0,"leap day");
   Check(AurumSessionAllowed(AURUM_SESSIONS_LONDON_NY,1768374000)==false,"filter blocks Asia");
   Check(AurumSessionAllowed(AURUM_SESSIONS_ALL,1768374000)==true,"All day allows Asia");
   Check(AurumSessionAllowed(AURUM_SESSIONS_LONDON,1768413600)==false,"London only blocks NY afternoon");
   Check(AurumSessionAllowed(AURUM_SESSIONS_NEWYORK,1768413600)==true,"New York only");
   Check(AurumDaysFromCivil(1970,1,1)==0 && AurumDaysFromCivil(2000,3,1)==11017,"calendar days");
   Check(AurumYearOfDays(AurumDaysFromCivil(2028,12,31))==2028 && AurumYearOfDays(AurumDaysFromCivil(2029,1,1))==2029,"year of day");
   Check(AurumWeekday(AurumDaysFromCivil(2026,11,17))==2,"17 Nov 2026 is a Tuesday");
   // Broker clock: UTC+2 winter / UTC+3 summer (follows US daylight time)
   Check(AurumServerOffset(7200,true,1768399200)==7200,"broker winter UTC+2");
   Check(AurumServerOffset(7200,true,1784041200)==10800,"broker summer UTC+3");
   Check(AurumServerOffset(0,false,1784030400)==0,"UTC broker never shifts");
   long wo=0; bool fu=false;
   AurumAutoServerZone(10800,1784030400,wo,fu);
   Check(wo==7200 && fu,"auto: UTC+3 in US summer = UTC+2 winter broker");
   AurumAutoServerZone(7200,1768392000,wo,fu);
   Check(wo==7200 && fu,"auto: UTC+2 in winter");
   AurumAutoServerZone(0,1784030400,wo,fu);
   Check(wo==0 && !fu,"auto: UTC server");

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
