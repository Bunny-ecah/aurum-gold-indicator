#property copyright "Aurum Gold - demo research"
#property version   "1.00"
#property description "Trades the Aurum Gold signals automatically: same entry, stop loss, take profit and lot size as the indicator panel."
#property description "Demo accounts only by default. Use on XAUUSD H1 (the tested setup)."
#property tester_indicator "Aurum\\AurumConfirmation.ex5"
#include <Trade/Trade.mqh>
#include "AurumCore.mqh"

// HOW IT WORKS
// The Aurum indicator (Indicators/Aurum/AurumConfirmation) decides every signal with its default,
// tested settings. On each new H1 candle this EA reads the signal of the candle that just closed and,
// if there is one and no Aurum trade is open, it opens the trade with the indicator's stop loss and
// take profit and a lot size that risks RiskPercent of the balance. A trade still open after
// MaxTradeBars candles is closed, like the indicator's record. One trade at a time.

enum AurumGrades
{
   GRADES_ALL=2,   // All grades (A, B, C) - as tested
   GRADES_AB=1,    // A and B only
   GRADES_A=0      // A only
};

input group "1. Safety"
input bool        DemoOnly=true;              // Trade on DEMO accounts only (recommended)
input double      RiskPercent=1.0;            // Risk per trade (% of balance)
input double      MaxSpreadPrice=0.50;        // Skip a signal if ask-bid is wider (price units)
input bool        AllowMinLot=false;          // Use the minimum lot even if it risks more than RiskPercent
input group "2. Signals"
input AurumGrades TradeGrades=GRADES_ALL;     // Which quality grades to trade
input int         MaxTradeBars=100;           // Close a trade after (candles) - same as the indicator
input group "3. Other"
input long        MagicNumber=880501;         // Magic number (identifies this EA's trades)
input int         SlippagePoints=50;          // Allowed slippage (points)
input bool        PushNotifications=false;    // Phone push notification on open / close
input bool        ShowIndicator=true;         // Show the Aurum indicator and panel on this chart

#define INDICATOR_PATH "Aurum\\AurumConfirmation"

CTrade trade;
int handle=INVALID_HANDLE;
datetime lastBar=0;
string status="Starting...";
string lastAction="No trades yet";
bool tester=false;

string GradeText(const int g) { return g==0?"A":g==1?"B":"C"; }

bool IsDemo() { return AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO; }

void Report(const string text)
{
   lastAction=TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)+"  "+text;
   Print("AurumEA: ",text);
   if(PushNotifications && !tester && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification(StringSubstr("AurumEA "+_Symbol+": "+text,0,255));
}

void ShowStatus()
{
   if(tester && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   string acc=IsDemo()?"DEMO":"REAL";
   Comment("AURUM EA  |  ",_Symbol," ",StringSubstr(EnumToString(_Period),7),"  |  account: ",acc,
           "  |  risk ",DoubleToString(RiskPercent,1),"%",
           "\nStatus: ",status,
           "\nLast: ",lastAction);
}

// The open Aurum position on this symbol, if any (selected on return).
bool SelectOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return true;
   }
   return false;
}

double MoneyPerPricePerLot()
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue<=0) tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   return tickSize>0?tickValue/tickSize:0;
}

double RoundToTick(const double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) return NormalizeDouble(price,_Digits);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}

int OnInit()
{
   tester=(bool)MQLInfoInteger(MQL_TESTER);
   if(RiskPercent<0.1 || RiskPercent>5 || MaxSpreadPrice<=0 || MaxTradeBars<5 || MaxTradeBars>500 || SlippagePoints<0)
   { Print("AurumEA: an input is out of range (risk must be 0.1-5%)."); return INIT_PARAMETERS_INCORRECT; }
   if(DemoOnly && !tester && !IsDemo())
   {
      Alert("AurumEA: this is a REAL account. The EA only trades demo accounts while DemoOnly = true.");
      return INIT_FAILED;
   }
   if(StringFind(_Symbol,"XAU")<0 && StringFind(_Symbol,"GOLD")<0)
      Print("AurumEA: warning - made and tested for gold (XAUUSD); this chart is ",_Symbol);
   if(_Period!=PERIOD_H1)
      Print("AurumEA: warning - tested on the H1 chart; this chart is ",EnumToString(_Period));
   handle=iCustom(_Symbol,_Period,INDICATOR_PATH);
   if(handle==INVALID_HANDLE)
   {
      Alert("AurumEA: cannot load the indicator ",INDICATOR_PATH,". Copy AurumConfirmation.mq5 + AurumCore.mqh to MQL5/Indicators/Aurum and compile it (F7).");
      return INIT_FAILED;
   }
   if(ShowIndicator && !tester) ChartIndicatorAdd(0,0,handle);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   // Never trade a signal from before the EA was started: act from the next candle close on
   if(!tester) lastBar=iTime(_Symbol,_Period,0);
   status="Waiting for the next candle close";
   ShowStatus();
   Print("AurumEA ready on ",_Symbol," ",EnumToString(_Period),", account ",IsDemo()?"DEMO":"REAL",", risk ",RiskPercent,"%.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handle!=INVALID_HANDLE) IndicatorRelease(handle);
   Comment("");
}

// Close the Aurum position after MaxTradeBars candles (the indicator's record does the same).
void CheckTimeExit()
{
   if(!SelectOurPosition()) return;
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   int held=iBarShift(_Symbol,_Period,opened,false);
   if(held>=MaxTradeBars)
   {
      ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      if(trade.PositionClose(ticket)) Report("Closed after "+IntegerToString(held)+" candles (time limit)");
      else Report("Time-limit close FAILED: "+trade.ResultRetcodeDescription());
   }
}

void OnTick()
{
   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==0 || bar==lastBar) return;

   // Wait until the indicator has processed the new candle
   if(BarsCalculated(handle)<Bars(_Symbol,_Period)) { status="Waiting for the indicator..."; ShowStatus(); return; }
   double dir[1],sl[1],tp[1],grade[1];
   if(CopyBuffer(handle,2,1,1,dir)!=1 || CopyBuffer(handle,3,1,1,sl)!=1 ||
      CopyBuffer(handle,4,1,1,tp)!=1 || CopyBuffer(handle,5,1,1,grade)!=1)
   { status="Waiting for the indicator data..."; ShowStatus(); return; }
   lastBar=bar;

   CheckTimeExit();
   bool open=SelectOurPosition();
   int signal=(int)dir[0];
   if(signal==0)
   {
      status=open?"In a trade - stop loss and take profit are set":"No signal - waiting";
      ShowStatus();
      return;
   }
   string side=signal>0?"BUY":"SELL";
   int g=(int)grade[0];
   if(open) { Report(side+" signal skipped: an Aurum trade is already open"); ShowStatus(); return; }
   if(g>(int)TradeGrades) { Report(side+" grade "+GradeText(g)+" skipped (grade filter)"); ShowStatus(); return; }
   if(DemoOnly && !tester && !IsDemo()) { Report(side+" skipped: not a demo account"); ShowStatus(); return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Report(side+" skipped: Algo Trading is switched off"); ShowStatus(); return; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) { Report(side+" skipped: no price"); ShowStatus(); return; }
   double spread=tick.ask-tick.bid;
   if(spread>MaxSpreadPrice) { Report(side+" skipped: spread "+DoubleToString(spread,_Digits)+" > "+DoubleToString(MaxSpreadPrice,_Digits)); ShowStatus(); return; }

   double entry=signal>0?tick.ask:tick.bid;
   double stop=RoundToTick(sl[0]),target=RoundToTick(tp[0]);
   // The price must still be between the stop and the target, with the broker's minimum distance
   double minDist=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   bool valid=signal>0?(stop<entry-minDist && target>entry+minDist):(stop>entry+minDist && target<entry-minDist);
   if(!valid) { Report(side+" skipped: price already moved past the stop or target"); ShowStatus(); return; }

   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent/100.0;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lots=AurumLots(riskMoney,entry,stop,MoneyPerPricePerLot(),step,minLot);
   if(lots<=0)
   {
      if(!AllowMinLot) { Report(side+" skipped: even "+DoubleToString(minLot,2)+" lot risks more than "+DoubleToString(RiskPercent,1)+"%"); ShowStatus(); return; }
      lots=minLot;
   }
   lots=MathMin(lots,maxLot);
   int lotDigits=(int)MathMax(0,MathCeil(-MathLog10(step)));
   lots=NormalizeDouble(lots,lotDigits);

   string comment="Aurum "+side+" "+GradeText(g);
   bool ok=signal>0?trade.Buy(lots,_Symbol,0,stop,target,comment):trade.Sell(lots,_Symbol,0,stop,target,comment);
   uint code=trade.ResultRetcode();
   if(ok && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE_PARTIAL))
   {
      double rr=AurumRR(entry,stop,target);
      Report(StringFormat("OPENED %s %.2f lot (grade %s) | entry %s | SL %s | TP %s | RR 1:%.1f",
             side,lots,GradeText(g),DoubleToString(trade.ResultPrice(),_Digits),DoubleToString(stop,_Digits),DoubleToString(target,_Digits),rr));
      status="In a trade - stop loss and take profit are set";
   }
   else Report(side+" order FAILED: "+IntegerToString(code)+" "+trade.ResultRetcodeDescription());
   ShowStatus();
}

// Report closed trades (stop loss, take profit or manual)
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   long reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   string why=reason==DEAL_REASON_SL?"stop loss":reason==DEAL_REASON_TP?"take profit":"closed";
   Report("CLOSED by "+why+": "+(profit>=0?"+":"")+DoubleToString(profit,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
   status="No trade open - waiting for a signal";
   ShowStatus();
}
