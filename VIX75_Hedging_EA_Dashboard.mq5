//+------------------------------------------------------------------+
//|                                       VIX75_Hedging_EA_Dashboard  |
//|                                Custom Hedging EA for VIX75      |
//|                         Market Execution Only + Dashboard UI    |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input parameters
input bool      PowerOn       = true;        // Power On/Off
input double    Lot1          = 0.001;       // First Trade Lot Size
input double    Lot2          = 0.002;       // Subsequent Trade Lot Size
input double    ProfitTarget  = 0.25;        // Take Profit ($)
input double    FirstLoss     = -0.25;       // Loss trigger for first trade ($)
input double    SubsequentLoss = -0.50;      // Loss trigger for subsequent trades ($)
input double    DesiredPriceGapUnits = 250.0; // Reference price gap (price units, unused)

//--- Global variables
double EntryPrices[100];      // Entry price list
int    Directions[100];       // 1 = Buy, -1 = Sell
ulong  PositionTickets[100];   // Track position tickets
int    TradeCount     = 0;
bool   CycleActive    = false;
string CurrentSymbol;
double LastTotalProfit = 0;
bool   WaitingForOpposite = false; // Flag to prevent multiple trades in same region

//+------------------------------------------------------------------+
//| Reset Trade Cycle                                                |
//+------------------------------------------------------------------+
void ResetCycle()
  {
   ArrayInitialize(EntryPrices, 0.0);
   ArrayInitialize(Directions, 0);
   ArrayInitialize(PositionTickets, 0);
   TradeCount = 0;
   CycleActive = false;
   WaitingForOpposite = false;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   CurrentSymbol = _Symbol;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double priceGapPoints = DesiredPriceGapUnits / point; // For reference only
   double priceGapInPriceUnits = priceGapPoints * point;
   Print("Symbol: ", _Symbol, ", Point value: ", point, ", Digits: ", digits, 
         ", Reference PriceGap: ", priceGapPoints, " points, ", DoubleToString(priceGapInPriceUnits, digits), " price units");
   if(StringFind(_Symbol, "VIX", 0) < 0)
      Print("Warning: Symbol ", _Symbol, " may not be VIX75. Verify symbol properties.");
   ResetCycle();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!PowerOn) { Comment("POWER: OFF"); return; }

   double totalPL = GetTotalProfit();
   DrawDashboard(totalPL);

   if(totalPL >= ProfitTarget)
     {
      CloseAllTrades();
      ResetCycle();
      Print("Profit target reached: $", DoubleToString(totalPL, 2), ", Closing all trades");
      return;
     }

   if(TradeCount == 0 && !CycleActive)
     {
      // First trade: Market Buy
      int dir = 1;
      double entryPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      ulong ticket = PlaceTrade(dir, Lot1);
      if(ticket > 0)
        {
         EntryPrices[0] = entryPrice;
         Directions[0] = dir;
         PositionTickets[0] = ticket;
         TradeCount++;
         CycleActive = true;
         WaitingForOpposite = false;
         Print("First trade opened: Direction=Buy, EntryPrice=", DoubleToString(entryPrice, _Digits), ", Ticket=", ticket);
        }
      return;
     }

   // Monitor only the latest position
   if(!WaitingForOpposite)
     {
      int lastIndex = TradeCount - 1;
      ulong ticket = PositionTickets[lastIndex];
      if(PositionSelectByTicket(ticket))
        {
         double posPL = PositionGetDouble(POSITION_PROFIT);
         double lossThreshold = (lastIndex == 0) ? FirstLoss : SubsequentLoss;
         if(posPL <= lossThreshold)
           {
            int newDir = -Directions[lastIndex];
            double currentPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
            ulong newTicket = PlaceTrade(newDir, Lot2);
            if(newTicket > 0)
              {
               EntryPrices[TradeCount] = currentPrice;
               Directions[TradeCount] = newDir;
               PositionTickets[TradeCount] = newTicket;
               TradeCount++;
               WaitingForOpposite = true; // Wait for the new position to trigger
               Print("Loss trigger: Position Ticket=", ticket, ", P/L=$", DoubleToString(posPL, 2), 
                     ", New Trade: Direction=", newDir == 1 ? "Buy" : "Sell", 
                     ", EntryPrice=", DoubleToString(currentPrice, _Digits), ", New Ticket=", newTicket);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Place Market Trade                                               |
//+------------------------------------------------------------------+
ulong PlaceTrade(int direction, double lot)
  {
   if(direction == 1)
     {
      if(trade.Buy(lot, CurrentSymbol, 0, 0, 0, "Hedge Buy"))
         return trade.ResultOrder();
     }
   else if(direction == -1)
     {
      if(trade.Sell(lot, CurrentSymbol, 0, 0, 0, "Hedge Sell"))
         return trade.ResultOrder();
     }
   Print("Trade failed: Error=", GetLastError());
   return 0;
  }

//+------------------------------------------------------------------+
//| Close All Open Trades                                            |
//+------------------------------------------------------------------+
void CloseAllTrades()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Calculate Total Floating Profit                                  |
//+------------------------------------------------------------------+
double GetTotalProfit()
  {
   double profit = 0.0;
   for(int i=0; i<PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == CurrentSymbol)
         profit += PositionGetDouble(POSITION_PROFIT);
     }
   return profit;
  }

//+------------------------------------------------------------------+
//| Draw On-Screen Dashboard                                         |
//+------------------------------------------------------------------+
void DrawDashboard(double profit)
  {
   string msg = "";
   msg += "🔌 POWER: " + (PowerOn ? "ON" : "OFF") + "\n";
   msg += "🔁 Cycle: " + (CycleActive ? "Active" : "Reset") + "\n";
   msg += "📈 Direction: " + (TradeCount > 0 ? (Directions[TradeCount-1] > 0 ? "Buy" : "Sell") : "N/A") + "\n";
   msg += "🪙 Trades: " + IntegerToString(CountTrades(1)) + " Buy / " + IntegerToString(CountTrades(-1)) + " Sell\n";
   msg += "💼 Total P/L: $" + DoubleToString(profit, 2) + " / $" + DoubleToString(ProfitTarget, 2);
   Comment(msg);
  }

//+------------------------------------------------------------------+
//| Count trades in a given direction                                |
//+------------------------------------------------------------------+
int CountTrades(int dir)
  {
   int count = 0;
   for(int i=0; i<TradeCount; i++)
      if(Directions[i] == dir)
         count++;
   return count;
  }
//+------------------------------------------------------------------+