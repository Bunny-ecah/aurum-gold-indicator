#property copyright "Aurum Confirmation - demo research"
#property version "2.00"
#property description "Closed-candle XAUUSD confirmation companion. No order execution."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots 4
#property indicator_label1 "BUY confirmation"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrMediumSeaGreen
#property indicator_width1 2
#property indicator_label2 "SELL confirmation"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrTomato
#property indicator_width2 2
#property indicator_label3 "Fast EMA (closed)"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrGoldenrod
#property indicator_label4 "Slow EMA (closed)"
#property indicator_type4 DRAW_LINE
#property indicator_color4 clrSlateGray
#include "AurumCore.mqh"

enum TradeMode { SCALPING=0, LONGER_TRADES=1 };
input group "Mode: match chart timeframe before attaching"
input TradeMode Mode=LONGER_TRADES;
input group "Four confirmation conditions"
input int FastEMA=20;
input int SlowEMA=50;
input int TrendEMA=200;
input int RSIPeriod=14;
input double BuyRSIMin=55.0;
input double BuyRSIMax=70.0;
input double SellRSIMin=30.0;
input double SellRSIMax=45.0;
input int BreakoutBars=5;
input double BreakoutBufferATR=0.0; // optional distance beyond breakout, previous ATR units
input bool RequireDirectionalCandle=true;
input group "Spread and volatility (quoted price units, not pips)"
input int ATRPeriod=14;
input double MinATRPrice=0.0;
input double MaxATRPrice=0.0;
input double MaxCandleATR=2.0; // signal range / PREVIOUS closed candle ATR
input double MaxSpreadPrice=0.50;
input bool RejectZeroHistoricalSpread=true;
input group "Signal timing"
input int CooldownBars=3; // require this many prior candles with NO qualifying candidate
input int HistoryBars=1500;
input int MaxTickAgeSeconds=30;
input int MaxAlertDelaySeconds=60;
input group "Notifications and journal"
input bool PopupAlerts=true;
input bool PushNotifications=false;
input bool SoundAlerts=false;
input bool WriteCSVJournal=true;
input group "Panel"
input bool ShowPanel=true;
input int PanelX=12;
input int PanelY=24;
input int PanelFontSize=10;

double Buy[],Sell[],Fast[],Slow[];
int hf=INVALID_HANDLE,hs=INVALID_HANDLE,hr=INVALID_HANDLE,ha=INVALID_HANDLE,ht=INVALID_HANDLE;
ENUM_TIMEFRAMES entryTF,trendTF;
AurumRules rules;
datetime processedBar=0;
bool primed=false;
string prefix="",baseText="Loading history...",delivery="No new signal processed yet";
string journalName="";
int journalHandle=INVALID_HANDLE;
int previousRates=0;
bool tester=false;

string Pass(const bool yes) { return yes?"PASS":"--"; }

void RenderPanel()
{
   if(!ShowPanel || prefix=="") return;
   string live;
   LiveGate(live);
   string text="AURUM v2 | "+_Symbol+" | "+EnumToString(entryTF)+" / "+EnumToString(trendTF)+
      "\n"+baseText+"\nLIVE: "+live+"\nALERT: "+delivery+
      "\nDemo research | 4/4 is not win probability";
   int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int width=(int)MathMin(650,MathMax(240,chartWidth-PanelX-16));
   int chars=(int)MathMax(20,(width-20)/(PanelFontSize*0.72));
   string source[],lines[];
   int sourceCount=StringSplit(text,'\n',source),n=0;
   for(int i=0;i<sourceCount;i++)
   {
      string line=source[i];
      while(StringLen(line)>chars)
      {
         ArrayResize(lines,n+1); lines[n++]=StringSubstr(line,0,chars);
         line=StringSubstr(line,chars);
      }
      ArrayResize(lines,n+1); lines[n++]=line;
   }
   string bg=prefix+"bg";
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,(n+1)*(PanelFontSize+7));
   for(int i=0;i<40;i++)
   {
      string name=prefix+"line"+IntegerToString(i);
      if(i>=n) { ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PanelX+10);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY+8+i*(PanelFontSize+7));
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PanelFontSize);
      ObjectSetInteger(0,name,OBJPROP_COLOR,(i==0)?clrGold:clrWhiteSmoke);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      ObjectSetString(0,name,OBJPROP_TEXT,lines[i]);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
   ChartRedraw();
}

void Display(const string text) { baseText=text; RenderPanel(); }

bool LiveGate(string &reason)
{
   if(tester) { reason="Tester: external notifications disabled"; return false; }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   { reason="BLOCKED - disconnected"; return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid || tick.ask<=0)
   { reason="BLOCKED - invalid quote"; return false; }
   if(!AurumQuoteFresh((long)TimeTradeServer(),(long)tick.time,MaxTickAgeSeconds))
   { reason="BLOCKED - stale quote / market closed"; return false; }
   long tradeMode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED || tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY)
   { reason="BLOCKED - symbol disabled / close only"; return false; }
   double sp=tick.ask-tick.bid;
   reason="spread "+DoubleToString(sp,_Digits)+" / cap "+DoubleToString(MaxSpreadPrice,_Digits);
   if(sp>MaxSpreadPrice) { reason="BLOCKED - "+reason; return false; }
   return true;
}

void ReleaseHandles()
{
   if(hf!=INVALID_HANDLE) IndicatorRelease(hf);
   if(hs!=INVALID_HANDLE) IndicatorRelease(hs);
   if(hr!=INVALID_HANDLE) IndicatorRelease(hr);
   if(ha!=INVALID_HANDLE) IndicatorRelease(ha);
   if(ht!=INVALID_HANDLE) IndicatorRelease(ht);
}

string SafeFilePart(string value)
{
   StringReplace(value,"\\","_"); StringReplace(value,"/","_");
   StringReplace(value,":","_"); StringReplace(value,"*","_");
   StringReplace(value,"?","_"); StringReplace(value,"\"","_");
   StringReplace(value,"<","_"); StringReplace(value,">","_"); StringReplace(value,"|","_");
   return value;
}

void OpenJournal()
{
   if(!WriteCSVJournal || tester) return;
   journalName="Aurum_v2_"+SafeFilePart(AccountInfoString(ACCOUNT_SERVER))+"_"+
      (string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+SafeFilePart(_Symbol)+"_"+
      EnumToString(entryTF)+"_"+(string)ChartID()+".csv";
   journalHandle=FileOpen(journalName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(journalHandle==INVALID_HANDLE)
   { Print("Aurum: journal unavailable, error ",GetLastError()); return; }
   if(FileSize(journalHandle)==0)
      FileWrite(journalHandle,"observed_server_time","signal_candle_open","symbol","entry_tf",
         "direction","signal_close","atr","historical_spread_price","delivery_status");
   FileSeek(journalHandle,0,SEEK_END);
   FileFlush(journalHandle);
   Print("Aurum journal: MQL5/Files/",journalName);
}

void Journal(const datetime signalBar,const int direction,const double price,
             const double atr,const double spreadPrice,const string status)
{
   if(journalHandle==INVALID_HANDLE) return;
   ResetLastError();
   uint written=FileWrite(journalHandle,TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),
      TimeToString(signalBar,TIME_DATE|TIME_MINUTES),_Symbol,EnumToString(entryTF),
      direction>0?"BUY":"SELL",DoubleToString(price,_Digits),DoubleToString(atr,_Digits),
      DoubleToString(spreadPrice,_Digits),status);
   if(written==0) Print("Aurum: journal write failed ",GetLastError());
   FileFlush(journalHandle);
}

int OnInit()
{
   tester=(bool)MQLInfoInteger(MQL_TESTER);
   entryTF=Mode==SCALPING?PERIOD_M5:PERIOD_H1;
   trendTF=Mode==SCALPING?PERIOD_M15:PERIOD_H4;
   if(_Period!=entryTF)
   {
      Print("Aurum: select ",EnumToString(entryTF)," for this mode, then attach again.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!AurumNumber(BuyRSIMin) || !AurumNumber(BuyRSIMax) ||
      !AurumNumber(SellRSIMin) || !AurumNumber(SellRSIMax) ||
      !AurumNumber(MinATRPrice) || !AurumNumber(MaxATRPrice) ||
      !AurumNumber(MaxCandleATR) || !AurumNumber(MaxSpreadPrice) ||
      !AurumNumber(BreakoutBufferATR) ||
      FastEMA<2 || FastEMA>1000 || SlowEMA<=FastEMA || SlowEMA>2000 ||
      TrendEMA<2 || TrendEMA>2000 || RSIPeriod<2 || RSIPeriod>1000 ||
      ATRPeriod<2 || ATRPeriod>1000 || BreakoutBars<1 || BreakoutBars>500 ||
      CooldownBars<0 || CooldownBars>100 || HistoryBars<100 || HistoryBars>10000 ||
      MaxSpreadPrice<=0 || MaxCandleATR<=0 || MinATRPrice<0 || MaxATRPrice<0 ||
      BreakoutBufferATR<0 || (MaxATRPrice>0 && MaxATRPrice<MinATRPrice) ||
      MaxTickAgeSeconds<1 || MaxTickAgeSeconds>3600 || MaxAlertDelaySeconds<1 ||
      MaxAlertDelaySeconds>=PeriodSeconds(entryTF) || BuyRSIMin<0 || BuyRSIMax>100 ||
      SellRSIMin<0 || SellRSIMax>100 || BuyRSIMin>BuyRSIMax ||
      SellRSIMin>SellRSIMax || SellRSIMax>=BuyRSIMin ||
      PanelX<0 || PanelY<0 || PanelFontSize<8 || PanelFontSize>18 || _Point<=0)
   { Print("Aurum: invalid inputs. Check periods, thresholds, panel and timing bounds."); return INIT_PARAMETERS_INCORRECT; }
   rules.buyMin=BuyRSIMin; rules.buyMax=BuyRSIMax;
   rules.sellMin=SellRSIMin; rules.sellMax=SellRSIMax;
   rules.minATR=MinATRPrice; rules.maxATR=MaxATRPrice;
   rules.maxRangeATR=MaxCandleATR; rules.maxSpread=MaxSpreadPrice;
   rules.breakoutBufferATR=BreakoutBufferATR;
   rules.rejectZeroSpread=RejectZeroHistoricalSpread;
   rules.directionalCandle=RequireDirectionalCandle;
   SetIndexBuffer(0,Buy,INDICATOR_DATA); SetIndexBuffer(1,Sell,INDICATOR_DATA);
   SetIndexBuffer(2,Fast,INDICATOR_DATA); SetIndexBuffer(3,Slow,INDICATOR_DATA);
   ArraySetAsSeries(Buy,true); ArraySetAsSeries(Sell,true);
   ArraySetAsSeries(Fast,true); ArraySetAsSeries(Slow,true);
   PlotIndexSetInteger(0,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_ARROW,234);
   for(int p=0;p<4;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"Aurum v2 "+EnumToString(entryTF));
   hf=iMA(_Symbol,entryTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hs=iMA(_Symbol,entryTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hr=iRSI(_Symbol,entryTF,RSIPeriod,PRICE_CLOSE);
   ha=iATR(_Symbol,entryTF,ATRPeriod);
   ht=iMA(_Symbol,trendTF,TrendEMA,0,MODE_EMA,PRICE_CLOSE);
   if(hf==INVALID_HANDLE || hs==INVALID_HANDLE || hr==INVALID_HANDLE || ha==INVALID_HANDLE || ht==INVALID_HANDLE)
   { Print("Aurum: failed to create indicator handles ",GetLastError()); ReleaseHandles(); return INIT_FAILED; }
   prefix="Aurum_"+(string)ChartID()+"_"+(string)GetTickCount64()+"_";
   if(ShowPanel)
   {
      string bg=prefix+"bg";
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,PanelX);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,PanelY);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'25,30,38');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,clrSlateGray);
      ObjectSetInteger(0,bg,OBJPROP_BACK,false);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   }
   OpenJournal();
   if(!EventSetTimer(2)) Print("Aurum: panel timer unavailable ",GetLastError());
   Display("Waiting for entry and trend history...");
   Print("Aurum v2 initialized. Manual confirmation only; no orders. Broker: ",AccountInfoString(ACCOUNT_SERVER));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer(); ReleaseHandles();
   if(journalHandle!=INVALID_HANDLE) FileClose(journalHandle);
   if(prefix!="") ObjectsDeleteAll(0,prefix);
   ChartRedraw();
}

void OnTimer() { RenderPanel(); }

string Notify(const int direction,const datetime barTime,const double price)
{
   string message=StringFormat("Aurum %s %s %s | bar %s | close %s | 4/4. Demo confirmation.",
      _Symbol,EnumToString(entryTF),direction>0?"BUY":"SELL",
      TimeToString(barTime,TIME_DATE|TIME_MINUTES),DoubleToString(price,_Digits));
   Print(message);
   string result="logged";
   if(PopupAlerts) { Alert(message); result+="; popup requested"; }
   if(SoundAlerts)
   { result+=PlaySound("alert.wav")?"; sound requested":"; sound FAILED"; }
   if(PushNotifications)
   {
      if(!TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
         result+="; push NOT CONFIGURED";
      else
      {
         ResetLastError();
         if(SendNotification(StringSubstr(message,0,255))) result+="; push submitted";
         else result+="; push FAILED "+IntegerToString(GetLastError());
      }
   }
   Print("Aurum delivery: ",result);
   return result;
}

int OnCalculate(const int rates_total,const int prev_calculated,
   const datetime &time[],const double &open[],const double &high[],const double &low[],
   const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,true); ArraySetAsSeries(open,true); ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true); ArraySetAsSeries(close,true); ArraySetAsSeries(spread,true);
   bool reset=prev_calculated==0 || rates_total<previousRates;
   if(reset)
   {
      ArrayInitialize(Buy,EMPTY_VALUE); ArrayInitialize(Sell,EMPTY_VALUE);
      ArrayInitialize(Fast,EMPTY_VALUE); ArrayInitialize(Slow,EMPTY_VALUE);
   }
   if(rates_total>0)
   { Buy[0]=EMPTY_VALUE; Sell[0]=EMPTY_VALUE; Fast[0]=EMPTY_VALUE; Slow[0]=EMPTY_VALUE; }
   previousRates=rates_total;
   int warm=(int)MathMax(SlowEMA,MathMax(RSIPeriod,ATRPeriod))+10;
   int limit=(int)MathMin(HistoryBars,rates_total-warm-BreakoutBars-CooldownBars-3);
   if(limit<2) { Display("Loading more entry history..."); return 0; }
   // No closed-bar work on ordinary ticks. Timer refreshes live connection/spread state.
   if(!reset && processedBar==time[0]) return rates_total;
   if(!SeriesInfoInteger(_Symbol,entryTF,SERIES_SYNCHRONIZED) ||
      !SeriesInfoInteger(_Symbol,trendTF,SERIES_SYNCHRONIZED))
   {
      MqlRates request[]; CopyRates(_Symbol,trendTF,0,TrendEMA+10,request);
      Display("Synchronizing history; alerts paused..."); return prev_calculated;
   }
   int candidates=limit+CooldownBars;
   int count=candidates+BreakoutBars+2;
   double f[],s[],r[],a[],trend[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
   ArraySetAsSeries(r,true); ArraySetAsSeries(a,true); ArraySetAsSeries(trend,true);
   int available=BarsCalculated(ht);
   int oldest=iBarShift(_Symbol,trendTF,time[candidates]+PeriodSeconds(entryTF),false);
   int trendCount=(int)MathMin(available,oldest+3);
   MqlRates trendBars[]; ArraySetAsSeries(trendBars,true);
   if(oldest<0 || trendCount<3 || available<TrendEMA+3 ||
      BarsCalculated(hf)<count || BarsCalculated(hs)<count ||
      BarsCalculated(hr)<count || BarsCalculated(ha)<count ||
      CopyBuffer(hf,0,0,count,f)!=count || CopyBuffer(hs,0,0,count,s)!=count ||
      CopyBuffer(hr,0,0,count,r)!=count || CopyBuffer(ha,0,0,count,a)!=count ||
      CopyBuffer(ht,0,0,trendCount,trend)!=trendCount ||
      CopyRates(_Symbol,trendTF,0,trendCount,trendBars)!=trendCount)
   { Display("Waiting for EMA / RSI / ATR history..."); return prev_calculated; }
   // Avoid mixing bulk snapshots if higher-timeframe series advanced during copying.
   if(trendBars[0].time!=iTime(_Symbol,trendTF,0) || time[0]!=iTime(_Symbol,entryTF,0))
   { Display("History changed during copy; retrying..."); return prev_calculated; }
   int raw[]; bool valid[];
   ArrayResize(raw,candidates+1); ArrayInitialize(raw,0);
   ArrayResize(valid,candidates+1); ArrayInitialize(valid,false);
   AurumResult latest; ZeroMemory(latest);
   int noHistory=0;
   for(int i=candidates;i>=1;i--)
   {
      datetime decision=time[i]+PeriodSeconds(entryTF);
      int containing=iBarShift(_Symbol,trendTF,decision,false);
      if(containing<0 || containing>=trendCount) { noHistory++; continue; }
      int shift=AurumClosedTrendShift(containing,(long)trendBars[containing].time,
         (long)decision,PeriodSeconds(trendTF));
      if(shift<0 || shift>=trendCount || available-shift<TrendEMA+10)
      { noHistory++; continue; }
      AurumBar b;
      b.open=open[i]; b.high=high[i]; b.low=low[i]; b.close=close[i];
      b.fast=f[i]; b.slow=s[i]; b.rsi=r[i]; b.atr=a[i]; b.previousATR=a[i+1];
      b.previousHigh=high[i+1]; b.previousLow=low[i+1];
      for(int j=i+2;j<=i+BreakoutBars;j++)
      { b.previousHigh=MathMax(b.previousHigh,high[j]); b.previousLow=MathMin(b.previousLow,low[j]); }
      b.trendClose=trendBars[shift].close; b.trendEMA=trend[shift];
      b.spread=spread[i]*_Point;
      AurumResult result; AurumEvaluate(b,rules,result);
      valid[i]=result.valid; raw[i]=result.raw;
      if(i==1) latest=result;
   }
   if(!valid[1])
   { Display("Latest closed candle / trend data unavailable; alerts paused."); return prev_calculated; }
   Buy[0]=EMPTY_VALUE; Sell[0]=EMPTY_VALUE;
   Fast[0]=EMPTY_VALUE; Slow[0]=EMPTY_VALUE;
   if(limit+1<rates_total)
   { Buy[limit+1]=EMPTY_VALUE; Sell[limit+1]=EMPTY_VALUE; Fast[limit+1]=EMPTY_VALUE; Slow[limit+1]=EMPTY_VALUE; }
   int latestDirection=0;
   bool latestQuiet=true,latestHistory=true;
   for(int i=limit;i>=1;i--)
   {
      Buy[i]=EMPTY_VALUE; Sell[i]=EMPTY_VALUE;
      Fast[i]=AurumNumber(f[i])?f[i]:EMPTY_VALUE;
      Slow[i]=AurumNumber(s[i])?s[i]:EMPTY_VALUE;
      bool recent=false,historyOK=valid[i];
      for(int j=1;j<=CooldownBars;j++)
      { if(raw[i+j]!=0) recent=true; if(!valid[i+j]) historyOK=false; }
      bool accepted=AurumQuietBar(raw[i],historyOK,recent);
      if(accepted)
      {
         if(raw[i]>0) Buy[i]=low[i]-a[i]*0.25;
         else Sell[i]=high[i]+a[i]*0.25;
      }
      if(i==1)
      { latestDirection=accepted?raw[i]:0; latestQuiet=!recent; latestHistory=historyOK; }
   }
   bool startup=!primed || reset;
   if(startup) delivery="Startup/history rebuild: past alerts suppressed";
   else if(processedBar!=time[0] && latestDirection!=0)
   {
      string reason;
      bool live=LiveGate(reason);
      if(!AurumAlertOnTime((long)TimeTradeServer(),
         (long)(time[1]+PeriodSeconds(entryTF)),MaxAlertDelaySeconds))
         delivery="Suppressed: candle notification window expired";
      else if(!live) delivery="Suppressed: "+reason;
      else
      {
         // Respect broker long-only/short-only contracts for actual notifications.
         long tm=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
         if((tm==SYMBOL_TRADE_MODE_LONGONLY && latestDirection<0) ||
            (tm==SYMBOL_TRADE_MODE_SHORTONLY && latestDirection>0))
            delivery="Suppressed: broker restricts this direction";
         else delivery=Notify(latestDirection,time[1],close[1]);
      }
      Journal(time[1],latestDirection,close[1],a[1],spread[1]*_Point,delivery);
   }
   processedBar=time[0]; primed=true;
   string status=latestDirection>0?"BUY SETUP":latestDirection<0?"SELL SETUP":"WAIT";
   string text=status+" | closed "+TimeToString(time[1],TIME_DATE|TIME_MINUTES)+
      "\nConditions         BUY / SELL"+
      "\nHTF trend          "+Pass(latest.trendBuy)+" / "+Pass(latest.trendSell)+
      "\nEMA alignment      "+Pass(latest.emaBuy)+" / "+Pass(latest.emaSell)+
      "\nRSI momentum       "+Pass(latest.rsiBuy)+" / "+Pass(latest.rsiSell)+
      "\nBreakout close     "+Pass(latest.breakBuy)+" / "+Pass(latest.breakSell)+
      "\nAligned            "+IntegerToString(latest.buyCount)+"/4 / "+IntegerToString(latest.sellCount)+"/4"+
      "\nSpread / ATR / range: "+Pass(latest.spreadOK)+" / "+Pass(latest.atrOK)+" / "+Pass(latest.rangeOK)+
      "\nCandle direction   "+Pass(latest.candleBuy)+" / "+Pass(latest.candleSell)+
      "\nQuiet bars: "+(latestQuiet?"ready":"blocked")+" | history: "+(latestHistory?"ready":"incomplete");
   if(noHistory>0) text+="\nOlder candles without trend history: "+IntegerToString(noHistory);
   Display(text);
   return rates_total;
}
