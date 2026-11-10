#property copyright "Aurum Gold - demo research"
#property version   "3.00"
#property description "XAUUSD SNR + SND + Fibonacci confluence signals on closed candles. No order execution."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "BUY signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "SELL signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2
#include "AurumCore.mqh"

// BUY  = trend UP + price dips into DEMAND (2 pts) / SUPPORT (1 pt) / FIBONACCI 0.5-0.786 (1 pt)
//        + the candle closes back above it. SELL = the mirror image.
// Points needed: Aggressive 1, Balanced 2, Strict 3. Stars (*) = points. Same rules as TradingView v5.

enum AurumSignalMode
{
   SIGNALS_BALANCED=0,   // Balanced: 2 points (recommended)
   SIGNALS_STRICT=1,     // Strict: 3 points (fewest, strongest)
   SIGNALS_AGGRESSIVE=2  // Aggressive: 1 point (most signals)
};

enum AurumSwingSize
{
   SWING_SMALL=3,   // Small swings (more levels, scalping)
   SWING_NORMAL=5,  // Normal
   SWING_LARGE=10   // Large swings (major levels only)
};

input group "1. Signals"
input AurumSignalMode SignalMode=SIGNALS_BALANCED;      // Signal mode
input AurumSwingSize  SwingSize=SWING_NORMAL;           // Swing size for S/R and Fibonacci
input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_CURRENT;    // Trend timeframe (current = auto)
input int    CooldownBars=5;                            // Candles between same-side signals
input group "2. Show on chart"
input bool   ShowSR=true;                               // Support / Resistance (SNR)
input bool   ShowZones=true;                            // Supply / Demand zones (SND)
input bool   ShowFib=true;                              // Fibonacci of latest swing
input bool   ShowTrade=true;                            // Entry / SL / TP of last signal
input bool   ShowPanel=true;                            // Info panel
input group "3. Alerts"
input bool   PopupAlerts=true;                          // Popup alert
input bool   PushNotifications=false;                   // Phone push notification
input bool   SoundAlerts=false;                         // Sound
input double MaxSpreadPrice=0.50;                       // Pause alerts if ask-bid is wider (price units)
input group "4. Advanced (defaults are fine)"
input double ImpulseATR=1.5;                            // Zone impulse: candle body >= ATR x
input double SLBufferATR=0.2;                           // Stop-loss buffer beyond structure (ATR x)
input double MinRiskATR=0.5;                            // Minimum stop-loss distance (ATR x)
input int    MaxItems=4;                                // Max zones / levels kept per side
input int    ATRPeriod=14;                              // ATR period
input int    HistoryBars=1500;                          // Candles to scan
input int    PanelX=12;                                 // Panel X
input int    PanelY=24;                                 // Panel Y
input int    PanelFontSize=10;                          // Panel font size

#define TOUCH_ATR 0.2
#define MERGE_ATR 0.3
#define MAX_ALERT_DELAY 60
#define MAX_TICK_AGE 30

double Buy[],Sell[];
int ha=INVALID_HANDLE,ht=INVALID_HANDLE,he=INVALID_HANDLE;
ENUM_TIMEFRAMES trendTF;
int pivotLen=5;
string prefix="";
datetime processedBar=0;
bool primed=false;
int previousRates=0;
bool tester=false;
string delivery="No new signal yet";

// Areas (rebuilt by replaying closed candles)
double resP[],supP[],dTop[],dBot[],sTop[],sBot[];
datetime resT[],supT[],dTime[],sTime[];
double swHigh=0,swLow=0;
datetime swHighT=0,swLowT=0;

// Last signal
int sigDir=0,sigScore=0,sigState=0,sigK=0;   // sigState: 0 none, 1 active, 2 finished
bool sigTP1Hit=false;
string sigResult="";
double lastClose=0,lastATR=0;
datetime sigTime=0;
double sigEntry=0,sigSL=0,sigTP1=0,sigTP2=0;
string sigWhy="",areaText="--";
int trendNow=0;

ENUM_TIMEFRAMES AutoTrendTF()
{
   int s=PeriodSeconds(_Period);
   if(s<=60) return PERIOD_M15;
   if(s<=300) return PERIOD_H1;
   if(s<=3600) return PERIOD_H4;
   if(s<=14400) return PERIOD_D1;
   if(s<=86400) return PERIOD_W1;
   return PERIOD_MN1;
}

string Stars(const int n) { return n>=4?"****":n==3?"***":n==2?"**":"*"; }
string Price(const double p) { return p>0?DoubleToString(p,_Digits):"--"; }

// ---------- Area bookkeeping ----------
void PushLevel(double &p[],datetime &t[],const double price,const datetime when,const double tol)
{
   for(int i=ArraySize(p)-1;i>=0;i--)
      if(AurumSameLevel(p[i],price,tol)) { ArrayRemove(p,i,1); ArrayRemove(t,i,1); }
   int n=ArraySize(p);
   ArrayResize(p,n+1); ArrayResize(t,n+1);
   p[n]=price; t[n]=when;
   while(ArraySize(p)>MaxItems) { ArrayRemove(p,0,1); ArrayRemove(t,0,1); }
}

void PushZone(double &top[],double &bot[],datetime &t[],const double zTop,const double zBot,const datetime when)
{
   for(int i=ArraySize(top)-1;i>=0;i--)
      if(bot[i]<=zTop && top[i]>=zBot) { ArrayRemove(top,i,1); ArrayRemove(bot,i,1); ArrayRemove(t,i,1); }
   int n=ArraySize(top);
   ArrayResize(top,n+1); ArrayResize(bot,n+1); ArrayResize(t,n+1);
   top[n]=zTop; bot[n]=zBot; t[n]=when;
   while(ArraySize(top)>MaxItems) { ArrayRemove(top,0,1); ArrayRemove(bot,0,1); ArrayRemove(t,0,1); }
}

void ResetState()
{
   ArrayFree(resP); ArrayFree(supP); ArrayFree(dTop); ArrayFree(dBot); ArrayFree(sTop); ArrayFree(sBot);
   ArrayFree(resT); ArrayFree(supT); ArrayFree(dTime); ArrayFree(sTime);
   swHigh=0; swLow=0; swHighT=0; swLowT=0;
   sigDir=0; sigScore=0; sigTime=0; sigEntry=0; sigSL=0; sigTP1=0; sigTP2=0; sigWhy=""; areaText="--";
   sigState=0; sigK=0; sigTP1Hit=false; sigResult="";
}

// Pivot at series index k: higher than the L older candles, not lower than the L newer candles.
bool PivotHigh(const double &high[],const int k,const int L)
{
   for(int j=1;j<=L;j++)
      if(high[k+j]>=high[k] || high[k-j]>high[k]) return false;
   return true;
}

bool PivotLow(const double &low[],const int k,const int L)
{
   for(int j=1;j<=L;j++)
      if(low[k+j]<=low[k] || low[k-j]<low[k]) return false;
   return true;
}

// ---------- Drawing ----------
void Line(const string name,const datetime t1,const datetime t2,const double p,const color c,
          const ENUM_LINE_STYLE style,const int width,const bool ray)
{
   ObjectCreate(0,name,OBJ_TREND,0,t1,p,t2,p);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,ray);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Text(const string name,const datetime t,const double p,const string text,const color c,const ENUM_ANCHOR_POINT anchor)
{
   ObjectCreate(0,name,OBJ_TEXT,0,t,p);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Zone(const string name,const datetime t1,const datetime t2,const double top,const double bot,const color c,const color textColor,const string text)
{
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bot);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   Text(name+"t",t2,top,text,textColor,ANCHOR_RIGHT_LOWER);
}

// Only areas near the current price are drawn, so old far-away levels do not clutter the chart.
bool Near(const double p) { return MathAbs(p-lastClose)<=8.0*lastATR; }

void DrawAreas(const datetime lastTime)
{
   ObjectsDeleteAll(0,prefix+"d");
   datetime rightT=lastTime+12*PeriodSeconds(_Period);
   if(ShowZones)
   {
      for(int i=0;i<ArraySize(dTop);i++)
         if((Near(dTop[i]) || Near(dBot[i])) && dBot[i]<=lastClose) Zone(prefix+"dz"+IntegerToString(i),dTime[i],rightT,dTop[i],dBot[i],C'0,70,64',clrMediumSeaGreen,"Demand");
      for(int i=0;i<ArraySize(sTop);i++)
         if((Near(sTop[i]) || Near(sBot[i])) && sTop[i]>=lastClose) Zone(prefix+"ds"+IntegerToString(i),sTime[i],rightT,sTop[i],sBot[i],C'90,20,24',clrTomato,"Supply");
   }
   if(ShowSR)
   {
      for(int i=0;i<ArraySize(supP);i++)
      {
         if(!Near(supP[i])) continue;
         Line(prefix+"dsl"+IntegerToString(i),supT[i],rightT,supP[i],clrMediumSeaGreen,STYLE_DASH,1,false);
         Text(prefix+"dslt"+IntegerToString(i),rightT,supP[i],"S "+Price(supP[i]),clrMediumSeaGreen,ANCHOR_LEFT);
      }
      for(int i=0;i<ArraySize(resP);i++)
      {
         if(!Near(resP[i])) continue;
         Line(prefix+"drl"+IntegerToString(i),resT[i],rightT,resP[i],clrTomato,STYLE_DASH,1,false);
         Text(prefix+"drlt"+IntegerToString(i),rightT,resP[i],"R "+Price(resP[i]),clrTomato,ANCHOR_LEFT);
      }
   }
   AurumSwing sw; sw.high=swHigh; sw.low=swLow;
   sw.dir=(swHighT==0 || swLowT==0)?0:(swHighT>swLowT?1:-1);
   if(ShowFib && AurumSwingValid(sw) && Near(AurumFibPrice(sw,0.618)))
   {
      // One golden-zone box with a single label instead of six overlapping labels
      datetime startT=sw.dir>0?swLowT:swHighT;
      double nearP=AurumFibPrice(sw,AURUM_FIB_NEAR),farP=AurumFibPrice(sw,AURUM_FIB_FAR);
      Zone(prefix+"dfz",startT,rightT,MathMax(nearP,farP),MathMin(nearP,farP),C'70,50,10',clrOrange,"Fib 0.5-0.786");
      Line(prefix+"dfm",startT,rightT,AurumFibPrice(sw,0.618),clrOrange,STYLE_DOT,1,false);
      double ext=AurumFibExtension(sw,1.618);
      if(Near(ext))
      {
         Line(prefix+"dfe",startT,rightT,ext,clrOrange,STYLE_DASH,1,false);
         Text(prefix+"dfet",startT,ext,"Fib 1.618 target  "+Price(ext),clrOrange,ANCHOR_RIGHT);
      }
   }
   // Trade lines only while the trade is still active (not SL / TP2 / expired)
   if(ShowTrade && sigDir!=0 && sigState==1)
   {
      double values[4]; values[0]=sigEntry; values[1]=sigSL; values[2]=sigTP1; values[3]=sigTP2;
      string names[4]; names[0]=sigDir>0?"BUY entry":"SELL entry"; names[1]="Stop loss"; names[2]="TP1"; names[3]="TP2";
      for(int i=0;i<4;i++)
      {
         color c=i==0?clrDodgerBlue:i==1?clrRed:clrLimeGreen;
         datetime tradeT=lastTime+4*PeriodSeconds(_Period);
         Line(prefix+"dtl"+IntegerToString(i),sigTime,tradeT,values[i],c,STYLE_SOLID,2,false);
         Text(prefix+"dtlt"+IntegerToString(i),tradeT,values[i],names[i]+"  "+Price(values[i]),c,ANCHOR_LEFT);
      }
   }
}

// ---------- Panel ----------
void RenderPanel()
{
   if(!ShowPanel || prefix=="") return;
   string live; LiveGate(live);
   string trendText=trendNow>0?"UP (look for BUY)":trendNow<0?"DOWN (look for SELL)":"FLAT (wait)";
   string modeText=SignalMode==SIGNALS_STRICT?"Strict":SignalMode==SIGNALS_AGGRESSIVE?"Aggressive":"Balanced";
   string last="None yet";
   if(sigDir!=0)
   {
      int ago=iBarShift(_Symbol,_Period,sigTime,false);
      last=(sigDir>0?"BUY ":"SELL ")+Stars(sigScore)+" "+sigWhy+" - "+IntegerToString(ago)+" bars ago - "+(sigState==1?"ACTIVE":sigResult);
   }
   string next=trendNow>0?"Wait: dip into Demand/Support/Fib + bullish close":
      trendNow<0?"Wait: rally into Supply/Resistance/Fib + bearish close":
      "Trend flat: no signals until it turns";
   string rows[11];
   rows[0]="AURUM GOLD v3 | "+_Symbol+" "+EnumToString(_Period)+" | trend "+EnumToString(trendTF);
   rows[1]="Trend      : "+trendText;
   rows[2]="Mode       : "+modeText;
   rows[3]="Price at   : "+areaText;
   rows[4]="Last signal: "+last;
   bool active=sigState==1;
   rows[5]="Entry      : "+(active?Price(sigEntry):"-- (no active trade)");
   rows[6]="Stop loss  : "+(active?Price(sigSL):"--");
   rows[7]="TP1 / TP2  : "+(active?Price(sigTP1)+" / "+Price(sigTP2)+(sigTP1Hit?" (TP1 hit)":""):"--");
   rows[8]="Next       : "+next;
   rows[9]="Live       : "+live;
   rows[10]="Alert      : "+delivery;
   int lineH=PanelFontSize+7;
   int width=(int)MathMin(620,MathMax(320,(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-PanelX-16));
   string bg=prefix+"pbg";
   if(ObjectFind(0,bg)<0)
   {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'25,30,38');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,clrSlateGray);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   }
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,PanelX);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,PanelY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,12*lineH);
   for(int i=0;i<11;i++)
   {
      string name=prefix+"pl"+IntegerToString(i);
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PanelX+10);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY+8+i*lineH);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PanelFontSize);
      color c=clrWhiteSmoke;
      if(i==0) c=clrGold;
      else if(i==1) c=trendNow>0?clrMediumSeaGreen:trendNow<0?clrTomato:clrSilver;
      else if(i==4 && sigDir!=0) c=sigDir>0?clrMediumSeaGreen:clrTomato;
      else if(i==5) c=clrDodgerBlue;
      else if(i==6) c=clrRed;
      else if(i==7) c=clrLimeGreen;
      ObjectSetInteger(0,name,OBJPROP_COLOR,c);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      ObjectSetString(0,name,OBJPROP_TEXT,rows[i]);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
   ChartRedraw();
}

bool LiveGate(string &reason)
{
   if(tester) { reason="Tester: notifications off"; return false; }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { reason="disconnected"; return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) { reason="no valid quote"; return false; }
   if(!AurumQuoteFresh((long)TimeTradeServer(),(long)tick.time,MAX_TICK_AGE)) { reason="market closed / stale quote"; return false; }
   double sp=tick.ask-tick.bid;
   reason="spread "+DoubleToString(sp,_Digits)+" (max "+DoubleToString(MaxSpreadPrice,_Digits)+")";
   if(sp>MaxSpreadPrice) { reason="PAUSED - "+reason; return false; }
   return true;
}

string Notify(const string message)
{
   Print(message);
   string result="logged";
   if(PopupAlerts) { Alert(message); result+=", popup"; }
   if(SoundAlerts) result+=PlaySound("alert.wav")?", sound":", sound FAILED";
   if(PushNotifications)
   {
      if(!TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED)) result+=", push NOT SET UP";
      else
      {
         ResetLastError();
         result+=SendNotification(StringSubstr(message,0,255))?", push sent":", push FAILED "+IntegerToString(GetLastError());
      }
   }
   return result;
}

void ReleaseHandles()
{
   if(ha!=INVALID_HANDLE) IndicatorRelease(ha);
   if(ht!=INVALID_HANDLE) IndicatorRelease(ht);
   if(he!=INVALID_HANDLE) IndicatorRelease(he);
}

int OnInit()
{
   tester=(bool)MQLInfoInteger(MQL_TESTER);
   pivotLen=(int)SwingSize;
   trendTF=TrendTimeframe==PERIOD_CURRENT?AutoTrendTF():TrendTimeframe;
   if(CooldownBars<0 || CooldownBars>50 || ImpulseATR<0.5 || ImpulseATR>5 ||
      SLBufferATR<0 || SLBufferATR>2 || MinRiskATR<0.1 || MinRiskATR>5 ||
      MaxItems<1 || MaxItems>10 || ATRPeriod<2 || ATRPeriod>200 ||
      HistoryBars<200 || HistoryBars>10000 || MaxSpreadPrice<=0 ||
      PanelX<0 || PanelY<0 || PanelFontSize<8 || PanelFontSize>18)
   { Print("Aurum: an input is out of range. Reset inputs to defaults."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,Buy,INDICATOR_DATA); SetIndexBuffer(1,Sell,INDICATOR_DATA);
   ArraySetAsSeries(Buy,true); ArraySetAsSeries(Sell,true);
   PlotIndexSetInteger(0,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"Aurum v3");
   ha=iATR(_Symbol,_Period,ATRPeriod);
   ht=iMA(_Symbol,trendTF,200,0,MODE_EMA,PRICE_CLOSE);
   he=iMA(_Symbol,_Period,200,0,MODE_EMA,PRICE_CLOSE);
   if(ha==INVALID_HANDLE || ht==INVALID_HANDLE || he==INVALID_HANDLE)
   { Print("Aurum: failed to create indicator handles ",GetLastError()); ReleaseHandles(); return INIT_FAILED; }
   prefix="Aurum3_"+(string)ChartID()+"_";
   ObjectsDeleteAll(0,prefix);
   if(!EventSetTimer(2)) Print("Aurum: panel timer unavailable ",GetLastError());
   RenderPanel();
   Print("Aurum v3 ready on ",_Symbol," ",EnumToString(_Period),", trend timeframe ",EnumToString(trendTF),". Signals only; no orders.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer(); ReleaseHandles();
   if(prefix!="") ObjectsDeleteAll(0,prefix);
   ChartRedraw();
}

void OnTimer() { RenderPanel(); }

int OnCalculate(const int rates_total,const int prev_calculated,
   const datetime &time[],const double &open[],const double &high[],const double &low[],
   const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,true); ArraySetAsSeries(open,true); ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true); ArraySetAsSeries(close,true);
   bool reset=prev_calculated==0 || rates_total<previousRates;
   previousRates=rates_total;
   if(rates_total>0) { Buy[0]=EMPTY_VALUE; Sell[0]=EMPTY_VALUE; }
   // All work happens once per NEW closed candle; ticks only refresh the panel timer.
   if(!reset && processedBar==time[0]) return rates_total;
   int L=pivotLen;
   int limit=(int)MathMin(HistoryBars,rates_total-2*L-ATRPeriod-5);
   if(limit<50) { delivery="Loading history..."; RenderPanel(); return 0; }

   // Chart ATR and EMA 200 (fallback trend)
   int count=limit+3;
   double atr[],ema[];
   ArraySetAsSeries(atr,true); ArraySetAsSeries(ema,true);
   if(BarsCalculated(ha)<count || BarsCalculated(he)<count ||
      CopyBuffer(ha,0,0,count,atr)!=count || CopyBuffer(he,0,0,count,ema)!=count)
   { delivery="Waiting for ATR / EMA data..."; RenderPanel(); return prev_calculated; }

   // Higher-timeframe trend: last COMPLETED trend candle close vs its EMA 200
   double htfEMA[]; MqlRates htfBars[];
   ArraySetAsSeries(htfEMA,true); ArraySetAsSeries(htfBars,true);
   int available=BarsCalculated(ht);
   int oldest=iBarShift(_Symbol,trendTF,time[limit]+PeriodSeconds(_Period),false);
   int trendCount=(int)MathMin(available,oldest+3);
   bool htfOK=oldest>=0 && trendCount>=3 &&
      CopyBuffer(ht,0,0,trendCount,htfEMA)==trendCount &&
      CopyRates(_Symbol,trendTF,0,trendCount,htfBars)==trendCount;
   if(!htfOK)
   {
      // Ask the terminal to load trend history; meanwhile the chart EMA 200 is used.
      MqlRates request[]; CopyRates(_Symbol,trendTF,0,300,request);
   }

   ArrayInitialize(Buy,EMPTY_VALUE); ArrayInitialize(Sell,EMPTY_VALUE);
   ResetState();
   ObjectsDeleteAll(0,prefix+"s");
   int lastBuyK=-1,lastSellK=-1,latestSignal=0;
   string latestMessage="";

   for(int i=limit;i>=1;i--)
   {
      int k=limit-i;   // increases with time
      AurumCandle c;
      c.open=open[i]; c.high=high[i]; c.low=low[i]; c.close=close[i]; c.atr=atr[i+1];
      if(!AurumCandleValid(c)) continue;
      double tol=TOUCH_ATR*c.atr;
      if(i==1) { lastClose=c.close; lastATR=atr[1]; }

      // 0) Follow the active trade: SL / TP hit or expired
      if(sigState==1 && k>sigK)
      {
         bool slHit=sigDir>0?c.low<=sigSL:c.high>=sigSL;
         bool tp2Hit=sigDir>0?c.high>=sigTP2:c.low<=sigTP2;
         if(sigDir>0?c.high>=sigTP1:c.low<=sigTP1) sigTP1Hit=true;
         if(slHit) { sigState=2; sigResult=sigTP1Hit?"TP1 hit, then SL":"SL hit"; }
         else if(tp2Hit) { sigState=2; sigResult="TP2 hit"; }
         else if(k-sigK>=100) { sigState=2; sigResult=sigTP1Hit?"TP1 hit, expired":"Expired"; }
      }

      // Trend for this candle
      int trendDir=0; bool gotTrend=false;
      if(htfOK)
      {
         datetime decision=time[i]+PeriodSeconds(_Period);
         int containing=iBarShift(_Symbol,trendTF,decision,false);
         if(containing>=0 && containing<trendCount)
         {
            int shift=AurumClosedTrendShift(containing,(long)htfBars[containing].time,(long)decision,PeriodSeconds(trendTF));
            if(shift>=0 && shift<trendCount && available-shift>=210)
            { trendDir=AurumTrendDir(htfBars[shift].close,htfEMA[shift]); gotTrend=true; }
         }
      }
      if(!gotTrend) trendDir=AurumTrendDir(close[i],ema[i]);
      if(i==1) trendNow=trendDir;

      // 1) Evaluate this closed candle against EXISTING areas
      bool inDemand=false,inSupply=false,atSupport=false,atResistance=false;
      double demandLow=0,supplyHigh=0,supportLow=0,resistanceHigh=0;
      for(int z=0;z<ArraySize(dTop);z++)
         if(AurumDemandTouch(c,dBot[z],dTop[z],tol))
         { demandLow=inDemand?MathMin(demandLow,dBot[z]):dBot[z]; inDemand=true; }
      for(int z=0;z<ArraySize(sTop);z++)
         if(AurumSupplyTouch(c,sBot[z],sTop[z],tol))
         { supplyHigh=inSupply?MathMax(supplyHigh,sTop[z]):sTop[z]; inSupply=true; }
      for(int z=0;z<ArraySize(supP);z++)
         if(AurumSupportTouch(c,supP[z],tol))
         { supportLow=atSupport?MathMin(supportLow,supP[z]):supP[z]; atSupport=true; }
      for(int z=0;z<ArraySize(resP);z++)
         if(AurumResistanceTouch(c,resP[z],tol))
         { resistanceHigh=atResistance?MathMax(resistanceHigh,resP[z]):resP[z]; atResistance=true; }
      AurumSwing sw; sw.high=swHigh; sw.low=swLow;
      sw.dir=(swHighT==0 || swLowT==0)?0:(swHighT>swLowT?1:-1);
      bool fibBuy=AurumFibBuy(c,sw,tol);
      bool fibSell=AurumFibSell(c,sw,tol);
      double fibFar=AurumSwingValid(sw)?AurumFibPrice(sw,AURUM_FIB_FAR):0;
      int buyScore=AurumScore(inDemand,atSupport,fibBuy);
      int sellScore=AurumScore(inSupply,atResistance,fibSell);
      string buyWhy=(inDemand?"Demand ":"")+(atSupport?"Support ":"")+(fibBuy?"Fib":"");
      string sellWhy=(inSupply?"Supply ":"")+(atResistance?"Resistance ":"")+(fibSell?"Fib":"");
      StringTrimRight(buyWhy); StringTrimRight(sellWhy);
      if(i==1)
         areaText=buyScore>0 && sellScore>0?buyWhy+" / "+sellWhy:
            buyScore>0?buyWhy+" (buy area)":sellScore>0?sellWhy+" (sell area)":"No key area";

      int dir=AurumDecide((int)SignalMode,trendDir,AurumBullRejection(c),buyScore,AurumBearRejection(c),sellScore);
      if(dir>0 && !AurumCooldownOK(k,lastBuyK,CooldownBars)) dir=0;
      if(dir<0 && !AurumCooldownOK(k,lastSellK,CooldownBars)) dir=0;
      if(dir!=0)
      {
         double entry=c.close,stop=0,nearest=0,fibTarget=0,tp1=0,tp2=0;
         if(dir>0)
         {
            double structure=c.low;
            if(inDemand) structure=MathMin(structure,demandLow);
            if(atSupport) structure=MathMin(structure,supportLow);
            if(fibBuy) structure=MathMin(structure,fibFar);
            stop=AurumBuyStop(entry,structure,c.atr,SLBufferATR,MinRiskATR);
            double risk=entry-stop;
            for(int z=0;z<ArraySize(resP);z++) if(resP[z]>=entry+risk && (nearest==0 || resP[z]<nearest)) nearest=resP[z];
            for(int z=0;z<ArraySize(sBot);z++) if(sBot[z]>=entry+risk && (nearest==0 || sBot[z]<nearest)) nearest=sBot[z];
            if(AurumSwingValid(sw) && sw.dir>0 && swHigh>=entry+risk && (nearest==0 || swHigh<nearest)) nearest=swHigh;
            fibTarget=AurumSwingValid(sw) && sw.dir>0?AurumFibExtension(sw,1.618):0;
            AurumBuyTargets(entry,stop,nearest,fibTarget,tp1,tp2);
            Buy[i]=c.low-0.3*c.atr; lastBuyK=k;
         }
         else
         {
            double structure=c.high;
            if(inSupply) structure=MathMax(structure,supplyHigh);
            if(atResistance) structure=MathMax(structure,resistanceHigh);
            if(fibSell) structure=MathMax(structure,fibFar);
            stop=AurumSellStop(entry,structure,c.atr,SLBufferATR,MinRiskATR);
            double risk=stop-entry;
            for(int z=0;z<ArraySize(supP);z++) if(supP[z]<=entry-risk && supP[z]>nearest) nearest=supP[z];
            for(int z=0;z<ArraySize(dTop);z++) if(dTop[z]<=entry-risk && dTop[z]>nearest) nearest=dTop[z];
            if(AurumSwingValid(sw) && sw.dir<0 && swLow<=entry-risk && swLow>nearest) nearest=swLow;
            fibTarget=AurumSwingValid(sw) && sw.dir<0?AurumFibExtension(sw,1.618):0;
            AurumSellTargets(entry,stop,nearest,fibTarget,tp1,tp2);
            Sell[i]=c.high+0.3*c.atr; lastSellK=k;
         }
         sigDir=dir; sigScore=dir>0?buyScore:sellScore; sigWhy=dir>0?buyWhy:sellWhy;
         sigTime=time[i]; sigEntry=entry; sigSL=stop; sigTP1=tp1; sigTP2=tp2;
         sigState=1; sigK=k; sigTP1Hit=false; sigResult="Active";
         string tag=(dir>0?"BUY ":"SELL ")+Stars(sigScore)+" "+sigWhy;
         Text(prefix+"s"+IntegerToString((long)time[i]),time[i],dir>0?c.low-0.6*c.atr:c.high+0.6*c.atr,tag,
              dir>0?clrMediumSeaGreen:clrTomato,dir>0?ANCHOR_UPPER:ANCHOR_LOWER);
         if(i==1)
         {
            latestSignal=dir;
            latestMessage=StringFormat("Aurum %s %s %s | %s | Entry %s | SL %s | TP1 %s | TP2 %s",
               dir>0?"BUY":"SELL",Stars(sigScore),_Symbol+" "+EnumToString(_Period),sigWhy,
               Price(entry),Price(stop),Price(tp1),Price(tp2));
         }
      }

      // 2) Update areas with this closed candle
      double mergeTol=MERGE_ATR*c.atr;
      for(int z=ArraySize(dTop)-1;z>=0;z--)
         if(AurumDemandBroken(c.close,dBot[z])) { ArrayRemove(dTop,z,1); ArrayRemove(dBot,z,1); ArrayRemove(dTime,z,1); }
      for(int z=ArraySize(sTop)-1;z>=0;z--)
         if(AurumSupplyBroken(c.close,sTop[z])) { ArrayRemove(sTop,z,1); ArrayRemove(sBot,z,1); ArrayRemove(sTime,z,1); }
      double flipSup[],flipRes[]; datetime flipSupT[],flipResT[];
      for(int z=ArraySize(resP)-1;z>=0;z--)
         if(c.close>resP[z])
         {
            int n=ArraySize(flipSup); ArrayResize(flipSup,n+1); ArrayResize(flipSupT,n+1);
            flipSup[n]=resP[z]; flipSupT[n]=resT[z];
            ArrayRemove(resP,z,1); ArrayRemove(resT,z,1);
         }
      for(int z=ArraySize(supP)-1;z>=0;z--)
         if(c.close<supP[z])
         {
            int n=ArraySize(flipRes); ArrayResize(flipRes,n+1); ArrayResize(flipResT,n+1);
            flipRes[n]=supP[z]; flipResT[n]=supT[z];
            ArrayRemove(supP,z,1); ArrayRemove(supT,z,1);
         }
      for(int z=0;z<ArraySize(flipSup);z++) PushLevel(supP,supT,flipSup[z],flipSupT[z],mergeTol);
      for(int z=0;z<ArraySize(flipRes);z++) PushLevel(resP,resT,flipRes[z],flipResT[z],mergeTol);

      AurumCandle base;
      base.open=open[i+1]; base.high=high[i+1]; base.low=low[i+1]; base.close=close[i+1]; base.atr=atr[i+2];
      double zb=0,zt=0;
      if(AurumDemandZone(base,c,ImpulseATR,zb,zt)) PushZone(dTop,dBot,dTime,zt,zb,time[i+1]);
      if(AurumSupplyZone(base,c,ImpulseATR,zb,zt)) PushZone(sTop,sBot,sTime,zt,zb,time[i+1]);

      int pk=i+L;   // candle that becomes a confirmed swing point now
      if(PivotHigh(high,pk,L))
      {
         if(c.close<high[pk]) PushLevel(resP,resT,high[pk],time[pk],mergeTol);
         else PushLevel(supP,supT,high[pk],time[pk],mergeTol);
         swHigh=high[pk]; swHighT=time[pk];
      }
      if(PivotLow(low,pk,L))
      {
         if(c.close>low[pk]) PushLevel(supP,supT,low[pk],time[pk],mergeTol);
         else PushLevel(resP,resT,low[pk],time[pk],mergeTol);
         swLow=low[pk]; swLowT=time[pk];
      }
   }

   // Notify only for a brand-new closed candle (never for history rebuilt at startup)
   bool startup=!primed || reset;
   if(startup) delivery="Ready. Past signals are not alerted.";
   else if(latestSignal!=0)
   {
      string reason;
      if(!AurumAlertOnTime((long)TimeTradeServer(),(long)(time[1]+PeriodSeconds(_Period)),MAX_ALERT_DELAY))
         delivery="Skipped: candle closed too long ago";
      else if(!LiveGate(reason)) delivery="Skipped: "+reason;
      else delivery=Notify(latestMessage);
   }
   processedBar=time[0]; primed=true;
   DrawAreas(time[0]);
   RenderPanel();
   return rates_total;
}
