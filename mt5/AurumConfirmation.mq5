#property copyright "Aurum Gold - demo research"
#property version   "4.10"
#property description "XAUUSD supply/demand + support/resistance signals with entry, stop, target, lot size and a built-in track record. No order execution."
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

// BUY  = trend UP + price dips into DEMAND (2 pts) and/or SUPPORT (1 pt) + the candle closes back above it
//        + the target (next resistance/supply) is at least MinReward x risk away. SELL = the mirror image.
// New trades only when the signal candle opens in the chosen session (London / New York by default).
// One trade at a time; it closes at TP, SL or after MaxTradeBars candles. Closed trades form the RECORD
// (a built-in backtest of these rules). Same rules as TradingView v6.

enum AurumSignalMode
{
   SIGNALS_BALANCED=0,   // Balanced: supply/demand zone (recommended)
   SIGNALS_STRICT=1,     // Strict: zone + S/R together (fewest)
   SIGNALS_AGGRESSIVE=2  // Aggressive: any zone or S/R level (most)
};

enum AurumSessions
{
   SESSIONS_LONDON_NY=0, // London + New York
   SESSIONS_LONDON=1,    // London only
   SESSIONS_NEWYORK=2,   // New York only
   SESSIONS_ALL=3        // All day (no filter)
};

enum AurumSwingSize
{
   SWING_SMALL=3,   // Small swings (more levels, scalping)
   SWING_NORMAL=5,  // Normal
   SWING_LARGE=10   // Large swings (major levels only)
};

input group "1. Signals"
input AurumSignalMode SignalMode=SIGNALS_BALANCED;      // Signal mode
input AurumSessions   Sessions=SESSIONS_LONDON_NY;      // Trading sessions (new trades only)
input AurumSwingSize  SwingSize=SWING_NORMAL;           // Swing size for S/R levels
input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_CURRENT;    // Trend timeframe (current = auto)
input group "2. Risk"
input double RiskPercent=1.0;                           // Risk per trade (% of balance)
input double MinReward=1.5;                             // Minimum reward (x risk); closer targets are skipped
input group "3. Display"
input bool   ShowAll=false;                             // Show all nearby zones and levels (off = nearest only)
input bool   ShowHistory=true;                          // Show past signals and results
input group "4. Alerts"
input bool   PopupAlerts=true;                          // Popup alert
input bool   PushNotifications=false;                   // Phone push notification
input bool   SoundAlerts=false;                         // Sound
input double MaxSpreadPrice=0.50;                       // Pause alerts if ask-bid is wider (price units)
input group "5. Advanced (defaults are fine)"
input double ImpulseATR=1.5;                            // Zone impulse: candle body >= ATR x
input double SLBufferATR=0.2;                           // Stop-loss buffer beyond the area (ATR x)
input double MinRiskATR=0.5;                            // Minimum stop-loss distance (ATR x)
input int    MaxItems=4;                                // Max zones / levels kept per side
input int    ATRPeriod=14;                              // ATR period
input int    MaxTradeBars=100;                          // Close a trade after (candles)
input int    HistoryBars=3000;                          // Candles to scan (also the record length)
input int    ServerUTCOffset=99;                        // Broker server time in winter, UTC+hours (99 = auto)
input bool   ServerFollowsUSDST=true;                   // Manual offset only: server clock moves with US summer time
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

// Open trade
bool inTrade=false;
int tDir=0,tK=0,tScore=0,tAge=0;
datetime tTime=0;
double tEntry=0,tSL=0,tTP=0;
string tWhy="";
int tQuality=0,tGrade=2;
int gradeTrades[3],gradeWins[3];   // record per grade A/B/C, for the WIN CHANCE
int dTouch[],sTouch[];             // candles that entered each zone (fresh = 0)
// Record of closed trades (R multiples) = built-in backtest
double results[];
int lastDir=0,lastAge=0,skipAge=-1;
double lastR=0;
string lastHow="",skipText="";
// Diagnostics: every setup (rejection candle at any zone or level) and the FIRST rule that stopped it
int setupCount=0,blockWeak=0,blockTrend=0,blockBusy=0,blockSession=0,blockTarget=0,tradedCount=0;
datetime firstBarTime=0;
double lastClose=0,lastATR=0;
int trendNow=0;
// Sessions
long winterOffset=0;
bool followsUS=false,sessionFilterOn=true,londonNow=false,newYorkNow=false,sessionOKNow=true;

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

string SessionName()
{
   return Sessions==SESSIONS_LONDON?"London only":Sessions==SESSIONS_NEWYORK?"New York only":Sessions==SESSIONS_ALL?"All day":"London + New York";
}

string GradeText(const int g) { return g==0?"A":g==1?"B":"C"; }

string Price(const double p) { return p>0?DoubleToString(p,_Digits):"--"; }
string RText(const double r) { return (r>=0?"+":"")+DoubleToString(r,2)+"R"; }
string TFText(const ENUM_TIMEFRAMES tf)
{
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
}

// ---------- Risk ----------
double MoneyPerPricePerLot()
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue<=0) tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   return tickSize>0?tickValue/tickSize:0;
}

double RiskMoney() { return AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent/100.0; }

double LotSize(const double entry,const double stop)
{
   return AurumLots(RiskMoney(),entry,stop,MoneyPerPricePerLot(),
                    SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
}

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

void PushZone(double &top[],double &bot[],datetime &t[],int &touch[],const double zTop,const double zBot,const datetime when)
{
   for(int i=ArraySize(top)-1;i>=0;i--)
      if(bot[i]<=zTop && top[i]>=zBot) { ArrayRemove(top,i,1); ArrayRemove(bot,i,1); ArrayRemove(t,i,1); ArrayRemove(touch,i,1); }
   int n=ArraySize(top);
   ArrayResize(top,n+1); ArrayResize(bot,n+1); ArrayResize(t,n+1); ArrayResize(touch,n+1);
   top[n]=zTop; bot[n]=zBot; t[n]=when; touch[n]=0;
   while(ArraySize(top)>MaxItems) { ArrayRemove(top,0,1); ArrayRemove(bot,0,1); ArrayRemove(t,0,1); ArrayRemove(touch,0,1); }
}

void ResetState()
{
   ArrayFree(resP); ArrayFree(supP); ArrayFree(dTop); ArrayFree(dBot); ArrayFree(sTop); ArrayFree(sBot);
   ArrayFree(resT); ArrayFree(supT); ArrayFree(dTime); ArrayFree(sTime); ArrayFree(results);
   ArrayFree(dTouch); ArrayFree(sTouch); ArrayInitialize(gradeTrades,0); ArrayInitialize(gradeWins,0);
   tQuality=0; tGrade=2;
   inTrade=false; tDir=0; tK=0; tScore=0; tAge=0; tTime=0; tEntry=0; tSL=0; tTP=0; tWhy="";
   lastDir=0; lastAge=0; lastR=0; lastHow=""; skipAge=-1; skipText="";
   setupCount=0; blockWeak=0; blockTrend=0; blockBusy=0; blockSession=0; blockTarget=0; tradedCount=0; firstBarTime=0;
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

// ---------- Nearest areas ----------
// kind: 0 none, 1 zone, 2 level
void AreaAbove(int &kind,double &top,double &bot,datetime &start)
{
   kind=0; double best=-1;
   for(int i=0;i<ArraySize(sTop);i++)
   {
      double d=MathMax(0,sBot[i]-lastClose);
      if(sTop[i]>=lastClose && (best<0 || d<best)) { best=d; kind=1; top=sTop[i]; bot=sBot[i]; start=sTime[i]; }
   }
   for(int i=0;i<ArraySize(resP);i++)
   {
      double d=resP[i]-lastClose;
      if(d>0 && (best<0 || d<best)) { best=d; kind=2; top=resP[i]; bot=resP[i]; start=resT[i]; }
   }
}

void AreaBelow(int &kind,double &top,double &bot,datetime &start)
{
   kind=0; double best=-1;
   for(int i=0;i<ArraySize(dTop);i++)
   {
      double d=MathMax(0,lastClose-dTop[i]);
      if(dBot[i]<=lastClose && (best<0 || d<best)) { best=d; kind=1; top=dTop[i]; bot=dBot[i]; start=dTime[i]; }
   }
   for(int i=0;i<ArraySize(supP);i++)
   {
      double d=lastClose-supP[i];
      if(d>0 && (best<0 || d<best)) { best=d; kind=2; top=supP[i]; bot=supP[i]; start=supT[i]; }
   }
}

string AreaText(const int kind,const double top,const double bot,const bool above)
{
   if(kind==1) return (above?"Supply ":"Demand ")+Price(bot)+" - "+Price(top);
   if(kind==2) return (above?"Resistance ":"Support ")+Price(top);
   return "none nearby";
}

// ---------- Drawing ----------
void Line(const string name,const datetime t1,const datetime t2,const double p,const color c,
          const ENUM_LINE_STYLE style,const int width)
{
   ObjectCreate(0,name,OBJ_TREND,0,t1,p,t2,p);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Text(const string name,const datetime t,const double p,const string text,const color c,
          const ENUM_ANCHOR_POINT anchor,const int size=8)
{
   ObjectCreate(0,name,OBJ_TEXT,0,t,p);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Box(const string name,const datetime t1,const datetime t2,const double top,const double bot,const color c)
{
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bot);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void DrawZone(const string name,const datetime t1,const datetime t2,const double top,const double bot,const bool supply)
{
   Box(name,t1,t2,top,bot,supply?C'90,20,24':C'0,70,64');
   Text(name+"t",t2,top,supply?"Supply":"Demand",supply?clrTomato:clrMediumSeaGreen,ANCHOR_RIGHT_LOWER);
}

void DrawLevel(const string name,const datetime t1,const datetime t2,const double p,const bool resistance)
{
   color c=resistance?clrTomato:clrMediumSeaGreen;
   Line(name,t1,t2,p,c,STYLE_DASH,1);
   Text(name+"t",t2,p,(resistance?"R ":"S ")+Price(p),c,ANCHOR_LEFT);
}

void DrawAreas(const datetime lastTime)
{
   ObjectsDeleteAll(0,prefix+"d");
   datetime rightT=lastTime+12*PeriodSeconds(_Period);
   if(ShowAll)
   {
      double range8=8.0*lastATR;
      for(int i=0;i<ArraySize(dTop);i++)
         if(dBot[i]<=lastClose && lastClose-dTop[i]<=range8) DrawZone(prefix+"dz"+IntegerToString(i),dTime[i],rightT,dTop[i],dBot[i],false);
      for(int i=0;i<ArraySize(sTop);i++)
         if(sTop[i]>=lastClose && sBot[i]-lastClose<=range8) DrawZone(prefix+"ds"+IntegerToString(i),sTime[i],rightT,sTop[i],sBot[i],true);
      for(int i=0;i<ArraySize(supP);i++)
         if(supP[i]<lastClose && lastClose-supP[i]<=range8) DrawLevel(prefix+"dsl"+IntegerToString(i),supT[i],rightT,supP[i],false);
      for(int i=0;i<ArraySize(resP);i++)
         if(resP[i]>lastClose && resP[i]-lastClose<=range8) DrawLevel(prefix+"drl"+IntegerToString(i),resT[i],rightT,resP[i],true);
   }
   else
   {
      // Clean chart: only the nearest area above and the nearest area below
      int k; double top=0,bot=0; datetime start=0;
      AreaAbove(k,top,bot,start);
      if(k==1) DrawZone(prefix+"dza",start,rightT,top,bot,true);
      else if(k==2) DrawLevel(prefix+"dla",start,rightT,top,true);
      AreaBelow(k,top,bot,start);
      if(k==1) DrawZone(prefix+"dzb",start,rightT,top,bot,false);
      else if(k==2) DrawLevel(prefix+"dlb",start,rightT,top,false);
   }
   // Open trade: red risk box and green reward box, like a position tool
   if(inTrade)
   {
      datetime t2=lastTime+6*PeriodSeconds(_Period);
      Box(prefix+"dtr",tTime,t2,MathMax(tEntry,tSL),MathMin(tEntry,tSL),C'90,20,24');
      Box(prefix+"dtw",tTime,t2,MathMax(tEntry,tTP),MathMin(tEntry,tTP),C'0,70,64');
      Text(prefix+"dtt",t2,tTP,"TP "+Price(tTP),clrLimeGreen,ANCHOR_LEFT);
      Text(prefix+"dte",t2,tEntry,(tDir>0?"BUY ":"SELL ")+Price(tEntry),clrDodgerBlue,ANCHOR_LEFT);
      Text(prefix+"dts",t2,tSL,"SL "+Price(tSL),clrRed,ANCHOR_LEFT);
   }
}

// ---------- Panel ----------
void PanelLabel(const string name,const int x,const int y,const string text,const color c,const int size)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void PanelRect(const string name,const int x,const int y,const int w,const int h,const color bg)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrSlateGray);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void RenderPanel()
{
   if(prefix=="") return;
   int lineH=PanelFontSize+8;
   int width=(int)MathMin(520,MathMax(360,(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-PanelX-16));
   string rows[16]; color cols[16];
   for(int i=0;i<16;i++) { rows[i]=""; cols[i]=clrWhiteSmoke; }

   rows[0]="AURUM GOLD  "+_Symbol+" "+TFText(_Period)+"  trend "+TFText(trendTF); cols[0]=clrGold;
   rows[1]="TREND        "+(trendNow>0?"UP   only BUY":trendNow<0?"DOWN   only SELL":"FLAT   no trades");
   cols[1]=trendNow>0?clrMediumSeaGreen:trendNow<0?clrTomato:clrSilver;
   string nowName=londonNow && newYorkNow?"London + New York":londonNow?"London":newYorkNow?"New York":"Asia / off-hours";
   long shown=winterOffset+((followsUS && AurumUSSummer((long)TimeGMT()))?3600:0);
   string zone="server UTC"+(shown>=0?"+":"")+IntegerToString(shown/3600);
   if(tester && ServerUTCOffset==99) zone="TESTER: set ServerUTCOffset";
   rows[2]="SESSION      "+nowName+(!sessionFilterOn?"   (filter off)":sessionOKNow?"   trading":"   no new trades")+"   ["+zone+"]";
   cols[2]=!sessionFilterOn?clrWhiteSmoke:sessionOKNow?clrMediumSeaGreen:clrOrange;
   if(tester && ServerUTCOffset==99 && sessionFilterOn) cols[2]=clrOrange;
   string status=inTrade?(tAge==0?(tDir>0?"BUY NOW":"SELL NOW"):(tDir>0?"IN BUY TRADE":"IN SELL TRADE")):"WAIT";
   color statusBg=inTrade?(tDir>0?C'0,110,90':C'150,30,35'):C'70,75,85';
   if(inTrade)
   {
      double risk=MathAbs(tEntry-tSL);
      double lot=LotSize(tEntry,tSL);
      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      rows[4]="ENTRY        "+Price(tEntry)+(tAge>0?"   ("+IntegerToString(tAge)+" candles ago)":""); cols[4]=clrDodgerBlue;
      rows[5]="STOP LOSS    "+Price(tSL)+"   = -"+DoubleToString(RiskPercent,1)+"% ("+DoubleToString(RiskMoney(),2)+")"; cols[5]=clrTomato;
      rows[6]="TAKE PROFIT  "+Price(tTP)+"   = +"+DoubleToString(AurumRR(tEntry,tSL,tTP)*RiskPercent,1)+"% ("+DoubleToString(AurumRR(tEntry,tSL,tTP)*RiskMoney(),2)+")   RR 1 : "+DoubleToString(AurumRR(tEntry,tSL,tTP),1); cols[6]=clrLimeGreen;
      if(lot>0) rows[7]="LOT SIZE     "+DoubleToString(lot,2)+" lot = risk "+DoubleToString(RiskMoney(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+" ("+DoubleToString(RiskPercent,1)+"%)";
      else { rows[7]="LOT SIZE     min "+DoubleToString(minLot,2)+" lot risks "+DoubleToString(minLot*risk*MoneyPerPricePerLot(),2)+" - above "+DoubleToString(RiskPercent,1)+"%"; cols[7]=clrOrange; }
      rows[8]="QUALITY      "+GradeText(tGrade)+"   "+IntegerToString(tQuality)+"/100   "+tWhy;
      cols[8]=tGrade==0?clrMediumSeaGreen:tGrade==1?clrOrange:clrTomato;
      // Win chance = how past signals of the same grade ended (needs 10+ to mean anything)
      int gN=gradeTrades[tGrade],gW=gradeWins[tGrade],allN=ArraySize(results),allW=0;
      for(int a=0;a<allN;a++) if(results[a]>0) allW++;
      if(gN>=10) rows[9]="WIN CHANCE   "+DoubleToString(100.0*gW/gN,0)+"%   ("+IntegerToString(gW)+" of "+IntegerToString(gN)+" past grade-"+GradeText(tGrade)+" signals hit TP)";
      else { rows[9]="WIN CHANCE   Not enough grade-"+GradeText(tGrade)+" history yet ("+IntegerToString(gN)+" trades)"+(allN>0?"   all signals: "+DoubleToString(100.0*allW/allN,0)+"% of "+IntegerToString(allN):""); cols[9]=clrSilver; }
   }
   else
   {
      int k; double top=0,bot=0; datetime start=0; string next;
      if(!sessionOKNow) next="Outside "+SessionName()+" - no new trades until the session opens";
      else if(trendNow>0) { AreaBelow(k,top,bot,start); next=k==0?"No buy area below - wait":"Wait for a dip into "+AreaText(k,top,bot,false)+", then a bullish candle"; }
      else if(trendNow<0) { AreaAbove(k,top,bot,start); next=k==0?"No sell area above - wait":"Wait for a rally into "+AreaText(k,top,bot,true)+", then a bearish candle"; }
      else next="Trend is flat - no trades until it turns";
      rows[4]="NEXT         "+next;
      if(skipAge>=0 && skipAge<=10) { rows[5]="NOTE         "+skipText; cols[5]=clrOrange; }
      if(ArraySize(results)>0)
      {
         rows[6]="LAST TRADE   "+(lastDir>0?"BUY -> ":"SELL -> ")+lastHow+" "+RText(lastR)+"   ("+IntegerToString(lastAge)+" candles ago)";
         cols[6]=lastR>0?clrMediumSeaGreen:lastR<0?clrTomato:clrSilver;
      }
      else rows[6]="LAST TRADE   No closed trades yet";
   }
   int n=ArraySize(results);
   if(n>0)
   {
      int wins=0,wins20=0; double total=0,total20=0; int first20=(int)MathMax(0,n-20);
      for(int i=0;i<n;i++)
      {
         if(results[i]>0) wins++;
         total+=results[i];
         if(i>=first20) { if(results[i]>0) wins20++; total20+=results[i]; }
      }
      rows[10]="RECORD       "+IntegerToString(n)+" trades  "+DoubleToString(100.0*wins/n,0)+"% win  "+RText(total);
      cols[10]=total>=0?clrMediumSeaGreen:clrTomato;
      string byGrade="";
      for(int g=0;g<3;g++) byGrade+=(g==0?"":"  ")+GradeText(g)+" "+(gradeTrades[g]>0?DoubleToString(100.0*gradeWins[g]/gradeTrades[g],0)+"% ("+IntegerToString(gradeTrades[g])+")":"-");
      rows[11]="BY GRADE     "+byGrade;
      if(n>20) { rows[12]="LAST 20      "+DoubleToString(100.0*wins20/20,0)+"% win  "+RText(total20); cols[12]=total20>=0?clrMediumSeaGreen:clrTomato; }
   }
   else rows[10]="RECORD       no closed trades yet";
   // Why so few trades? Top 3 blockers
   if(setupCount>0)
   {
      rows[13]="SETUPS       "+IntegerToString(setupCount)+" since "+TimeToString(firstBarTime,TIME_DATE)+"  "+IntegerToString(tradedCount)+" traded";
      cols[13]=clrSilver;
      int counts[5]; string names[5]; int idx[5];
      counts[0]=blockTrend; counts[1]=blockWeak; counts[2]=blockSession; counts[3]=blockTarget; counts[4]=blockBusy;
      names[0]="trend"; names[1]="weak area"; names[2]="session"; names[3]="target"; names[4]="trade open";
      for(int a=0;a<5;a++) idx[a]=a;
      for(int a=0;a<5;a++) for(int b=a+1;b<5;b++) if(counts[idx[b]]>counts[idx[a]]) { int t=idx[a]; idx[a]=idx[b]; idx[b]=t; }
      string parts="";
      for(int a=0;a<3;a++) if(counts[idx[a]]>0) parts+=(parts==""?"":"  ")+names[idx[a]]+" "+IntegerToString(counts[idx[a]]);
      rows[14]="BLOCKED BY   "+parts;
      cols[14]=clrSilver;
   }
   string live; LiveGate(live);
   rows[15]="ALERTS       "+delivery+"  |  "+live; cols[15]=clrSilver;

   PanelRect(prefix+"pbg",PanelX,PanelY,width,18*lineH,C'25,30,38');
   int statusH=PanelFontSize*2+12;
   int y=PanelY+8;
   for(int i=0;i<16;i++)
   {
      if(i==3)
      {
         // Big status line
         PanelLabel(prefix+"pl3a",PanelX+10,y+(statusH-lineH)/2,"STATUS",clrSilver,PanelFontSize);
         PanelRect(prefix+"pst",PanelX+110,y,width-122,statusH,statusBg);
         PanelLabel(prefix+"pl3",PanelX+122,y+4,status,clrWhite,PanelFontSize+8);
         y+=statusH+4;
         continue;
      }
      PanelLabel(prefix+"pl"+IntegerToString(i),PanelX+10,y,rows[i],cols[i],PanelFontSize);
      y+=lineH;
   }
   ObjectSetInteger(0,prefix+"pbg",OBJPROP_YSIZE,y-PanelY+6);
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
   reason="spread "+DoubleToString(sp,_Digits);
   if(sp>MaxSpreadPrice) { reason="PAUSED - "+reason+" > "+DoubleToString(MaxSpreadPrice,_Digits); return false; }
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
   if(RiskPercent<0.1 || RiskPercent>10 || MinReward<1 || MinReward>5 ||
      ImpulseATR<0.5 || ImpulseATR>5 || SLBufferATR<0 || SLBufferATR>2 || MinRiskATR<0.1 || MinRiskATR>5 ||
      MaxItems<1 || MaxItems>10 || ATRPeriod<2 || ATRPeriod>200 || MaxTradeBars<5 || MaxTradeBars>500 ||
      HistoryBars<200 || HistoryBars>20000 || MaxSpreadPrice<=0 ||
      (ServerUTCOffset!=99 && (ServerUTCOffset<-12 || ServerUTCOffset>14)) ||
      PanelX<0 || PanelY<0 || PanelFontSize<8 || PanelFontSize>18)
   { Print("Aurum: an input is out of range. Reset inputs to defaults."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,Buy,INDICATOR_DATA); SetIndexBuffer(1,Sell,INDICATOR_DATA);
   ArraySetAsSeries(Buy,true); ArraySetAsSeries(Sell,true);
   PlotIndexSetInteger(0,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"Aurum v4");
   ha=iATR(_Symbol,_Period,ATRPeriod);
   ht=iMA(_Symbol,trendTF,200,0,MODE_EMA,PRICE_CLOSE);
   he=iMA(_Symbol,_Period,200,0,MODE_EMA,PRICE_CLOSE);
   if(ha==INVALID_HANDLE || ht==INVALID_HANDLE || he==INVALID_HANDLE)
   { Print("Aurum: failed to create indicator handles ",GetLastError()); ReleaseHandles(); return INIT_FAILED; }
   prefix="Aurum4_"+(string)ChartID()+"_";
   ObjectsDeleteAll(0,prefix);
   if(!EventSetTimer(2)) Print("Aurum: panel timer unavailable ",GetLastError());
   RenderPanel();
   Print("Aurum v4 ready on ",_Symbol," ",TFText(_Period),", trend timeframe ",TFText(trendTF),". Signals only; no orders.");
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

   // Broker server clock -> UTC, for the London / New York session filter
   sessionFilterOn=Sessions!=SESSIONS_ALL && PeriodSeconds(_Period)<14400;
   if(ServerUTCOffset==99)
   {
      long measured=(long)MathRound((double)(TimeTradeServer()-TimeGMT())/3600.0)*3600;
      AurumAutoServerZone(measured,(long)TimeGMT(),winterOffset,followsUS);
   }
   else { winterOffset=(long)ServerUTCOffset*3600; followsUS=ServerFollowsUSDST; }
   long nowUTC=(long)time[0]-AurumServerOffset(winterOffset,followsUS,(long)time[0]);
   londonNow=AurumLondonOpen(nowUTC); newYorkNow=AurumNewYorkOpen(nowUTC);
   sessionOKNow=!sessionFilterOn || AurumSessionAllowed((int)Sessions,nowUTC);

   ArrayInitialize(Buy,EMPTY_VALUE); ArrayInitialize(Sell,EMPTY_VALUE);
   ResetState();
   ObjectsDeleteAll(0,prefix+"s");
   int latestSignal=0,lastExitK=-1,skipK=-1;
   string latestMessage="";

   for(int i=limit;i>=1;i--)
   {
      int k=limit-i;   // increases with time
      AurumCandle c;
      c.open=open[i]; c.high=high[i]; c.low=low[i]; c.close=close[i]; c.atr=atr[i+1];
      if(!AurumCandleValid(c)) continue;
      double tol=TOUCH_ATR*c.atr;
      if(i==1) { lastClose=c.close; lastATR=atr[1]; }

      // 0) Follow the open trade: SL / TP / time limit
      bool timeExitNow=false;   // no new trade on a time-exit candle
      if(inTrade && k>tK)
      {
         double r=0;
         if(AurumTradeStep(tDir,tEntry,tSL,tTP,c,k-tK,MaxTradeBars,r))
         {
            bool slHit=tDir>0?c.low<=tSL:c.high>=tSL;
            bool tpHit=tDir>0?c.high>=tTP:c.low<=tTP;
            lastHow=slHit?"SL":tpHit?"TP":"Time exit";
            timeExitNow=!slHit && !tpHit;
            inTrade=false; lastDir=tDir; lastR=r; lastExitK=k;
            int n=ArraySize(results); ArrayResize(results,n+1); results[n]=r;
            gradeTrades[tGrade]++; if(r>0) gradeWins[tGrade]++;
            if(ShowHistory)
               Text(prefix+"sx"+IntegerToString((long)time[i]),time[i],tDir>0?c.high+0.4*c.atr:c.low-0.4*c.atr,
                    lastHow+" "+RText(r),r>0?clrMediumSeaGreen:r<0?clrTomato:clrSilver,tDir>0?ANCHOR_LOWER:ANCHOR_UPPER,9);
         }
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
      bool inDemand=false,inSupply=false,atSupport=false,atResistance=false,demandFresh=false,supplyFresh=false;
      double demandLow=0,supplyHigh=0,supportLow=0,resistanceHigh=0;
      for(int z=0;z<ArraySize(dTop);z++)
         if(AurumDemandTouch(c,dBot[z],dTop[z],tol))
         { demandLow=inDemand?MathMin(demandLow,dBot[z]):dBot[z]; inDemand=true; if(dTouch[z]==0) demandFresh=true; }
      for(int z=0;z<ArraySize(sTop);z++)
         if(AurumSupplyTouch(c,sBot[z],sTop[z],tol))
         { supplyHigh=inSupply?MathMax(supplyHigh,sTop[z]):sTop[z]; inSupply=true; if(sTouch[z]==0) supplyFresh=true; }
      for(int z=0;z<ArraySize(supP);z++)
         if(AurumSupportTouch(c,supP[z],tol))
         { supportLow=atSupport?MathMin(supportLow,supP[z]):supP[z]; atSupport=true; }
      for(int z=0;z<ArraySize(resP);z++)
         if(AurumResistanceTouch(c,resP[z],tol))
         { resistanceHigh=atResistance?MathMax(resistanceHigh,resP[z]):resP[z]; atResistance=true; }
      int buyScore=AurumScore(inDemand,atSupport);
      int sellScore=AurumScore(inSupply,atResistance);

      long barUTC=(long)time[i]-AurumServerOffset(winterOffset,followsUS,(long)time[i]);
      bool sessionOK=!sessionFilterOn || AurumSessionAllowed((int)Sessions,barUTC);
      // Diagnostics for setups stopped before the session / target checks
      int need=AurumPointsNeeded((int)SignalMode);
      for(int side=0;side<2;side++)
      {
         int score=side==0?buyScore:sellScore;
         bool rej=side==0?AurumBullRejection(c):AurumBearRejection(c);
         if(!rej || score<1) continue;
         if(firstBarTime==0) firstBarTime=time[limit];
         setupCount++;
         if(score<need) blockWeak++;
         else if(side==0?trendDir<=0:trendDir>=0) blockTrend++;
         else if(inTrade || timeExitNow) blockBusy++;
      }
      int dir=(inTrade || timeExitNow)?0:AurumDecide((int)SignalMode,trendDir,AurumBullRejection(c),buyScore,AurumBearRejection(c),sellScore);
      if(dir!=0)
      {
         double entry=c.close,stop=0,nearest=0,tp=0;
         string why;
         if(dir>0)
         {
            double structure=c.low;
            if(inDemand) structure=MathMin(structure,demandLow);
            if(atSupport) structure=MathMin(structure,supportLow);
            stop=AurumBuyStop(entry,structure,c.atr,SLBufferATR,MinRiskATR);
            for(int z=0;z<ArraySize(resP);z++) if(resP[z]>entry && (nearest==0 || resP[z]<nearest)) nearest=resP[z];
            for(int z=0;z<ArraySize(sBot);z++) if(sBot[z]>entry && (nearest==0 || sBot[z]<nearest)) nearest=sBot[z];
            why=(inDemand?"Demand ":"")+(atSupport?"Support":"");
         }
         else
         {
            double structure=c.high;
            if(inSupply) structure=MathMax(structure,supplyHigh);
            if(atResistance) structure=MathMax(structure,resistanceHigh);
            stop=AurumSellStop(entry,structure,c.atr,SLBufferATR,MinRiskATR);
            for(int z=0;z<ArraySize(supP);z++) if(supP[z]<entry && supP[z]>nearest) nearest=supP[z];
            for(int z=0;z<ArraySize(dTop);z++) if(dTop[z]<entry && dTop[z]>nearest) nearest=dTop[z];
            why=(inSupply?"Supply ":"")+(atResistance?"Resistance":"");
         }
         StringTrimRight(why);
         bool targetOK=AurumTarget(dir,entry,stop,nearest,MinReward,tp);
         if(!sessionOK)
         {
            blockSession++;
            skipK=k;
            skipText=(dir>0?"BUY":"SELL")+" setup skipped: outside "+SessionName();
         }
         else if(!targetOK)
         {
            blockTarget++;
            skipK=k;
            skipText=(dir>0?"BUY":"SELL")+" skipped: target only "+DoubleToString(AurumRR(entry,stop,nearest),1)+"R away";
         }
         else
         {
            tradedCount++;
            inTrade=true; tDir=dir; tK=k; tTime=time[i]; tEntry=entry; tSL=stop; tTP=tp; tWhy=why;
            tScore=dir>0?buyScore:sellScore;
            bool zoneHit=dir>0?inDemand:inSupply, levelHit=dir>0?atSupport:atResistance;
            bool fresh=dir>0?demandFresh:supplyFresh;
            tQuality=AurumQuality(zoneHit,levelHit,fresh,AurumRR(entry,stop,tp),AurumLondonOpen(barUTC),AurumNewYorkOpen(barUTC));
            tGrade=AurumGrade(tQuality);
            if(zoneHit && fresh) tWhy=why+" (fresh)";
            string side=(dir>0?"BUY ":"SELL ")+GradeText(tGrade);
            if(dir>0) Buy[i]=c.low-0.3*c.atr; else Sell[i]=c.high+0.3*c.atr;
            if(ShowHistory)
               Text(prefix+"s"+IntegerToString((long)time[i]),time[i],dir>0?c.low-0.6*c.atr:c.high+0.6*c.atr,side,
                    dir>0?clrMediumSeaGreen:clrTomato,dir>0?ANCHOR_UPPER:ANCHOR_LOWER,9);
            if(i==1)
            {
               latestSignal=dir;
               double rrNow=AurumRR(entry,stop,tp);
               latestMessage=StringFormat("Aurum %s %s %s | Quality %s %d/100 | Entry %s | SL %s | TP %s | RR 1:%.1f = +%.1f%% if TP | Lot %.2f | %s",
                  dir>0?"BUY":"SELL",_Symbol,TFText(_Period),GradeText(tGrade),tQuality,Price(entry),Price(stop),Price(tp),
                  rrNow,rrNow*RiskPercent,LotSize(entry,stop),tWhy);
            }
         }
      }

      // 2) Update areas with this closed candle
      double mergeTol=MERGE_ATR*c.atr;
      // Count every candle that enters a zone (a zone is "fresh" until its first touch)
      for(int z=0;z<ArraySize(dTop);z++) if(c.low<=dTop[z]+tol) dTouch[z]++;
      for(int z=0;z<ArraySize(sBot);z++) if(c.high>=sBot[z]-tol) sTouch[z]++;
      for(int z=ArraySize(dTop)-1;z>=0;z--)
         if(AurumDemandBroken(c.close,dBot[z])) { ArrayRemove(dTop,z,1); ArrayRemove(dBot,z,1); ArrayRemove(dTime,z,1); ArrayRemove(dTouch,z,1); }
      for(int z=ArraySize(sTop)-1;z>=0;z--)
         if(AurumSupplyBroken(c.close,sTop[z])) { ArrayRemove(sTop,z,1); ArrayRemove(sBot,z,1); ArrayRemove(sTime,z,1); ArrayRemove(sTouch,z,1); }
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
      if(AurumDemandZone(base,c,ImpulseATR,zb,zt)) PushZone(dTop,dBot,dTime,dTouch,zt,zb,time[i+1]);
      if(AurumSupplyZone(base,c,ImpulseATR,zb,zt)) PushZone(sTop,sBot,sTime,sTouch,zt,zb,time[i+1]);

      int pk=i+L;   // candle that becomes a confirmed swing point now
      if(PivotHigh(high,pk,L))
      {
         if(c.close<high[pk]) PushLevel(resP,resT,high[pk],time[pk],mergeTol);
         else PushLevel(supP,supT,high[pk],time[pk],mergeTol);
      }
      if(PivotLow(low,pk,L))
      {
         if(c.close>low[pk]) PushLevel(supP,supT,low[pk],time[pk],mergeTol);
         else PushLevel(resP,resT,low[pk],time[pk],mergeTol);
      }
   }
   int lastK=limit-1;
   tAge=inTrade?lastK-tK:0;
   lastAge=lastExitK>=0?lastK-lastExitK:0;
   skipAge=skipK>=0?lastK-skipK:-1;

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
