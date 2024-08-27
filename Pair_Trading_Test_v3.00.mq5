//+------------------------------------------------------------------+
//| Optimized Pair Trading EA_v5.02.mq5                              |
//| A highly robust statistical arbitrage pairs trading strategy      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Optimized by ChatGPT"
#property link      "https://www.example.com"
#property version   "5.02"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input parameters
input string Symbol1 = "US100Cash";               // Symbol 1
input string Symbol2 = "FRA40Cash";               // Symbol 2
input double InpEntryThreshold = 2.0;             // Entry threshold (standard deviations)
input double InpExitThreshold = 0.5;              // Exit threshold (standard deviations)
input int    InpLookbackPeriod = 100;             // Lookback period
input double InpMaxLossPercentage = 5.0;          // Max loss percentage
input double InpMaxExposurePercentage = 15.0;     // Max exposure percentage
input int    InpReEvaluationInterval = 30;        // Re-evaluation interval (minutes)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;  // Analysis timeframe

//--- Global variables
double g_hedgeRatio = 0;
double g_meanSpread = 0;
double g_stdDevSpread = 0;
datetime g_lastEvaluationTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if (!CalculateCointegrationParameters())
   {
      Print("Failed to calculate cointegration parameters. EA initialization failed.");
      return(INIT_FAILED);
   }
   g_lastEvaluationTime = TimeCurrent();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up if necessary
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (CheckForLosses())
      return;

   if (DynamicParameterAdjustment())
      GenerateTradeSignals();
}

//+------------------------------------------------------------------+
//| Calculate Cointegration Parameters                               |
//+------------------------------------------------------------------+
bool CalculateCointegrationParameters()
{
   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   for (int i = 0; i < InpLookbackPeriod; i++)
   {
      double priceA = iClose(Symbol1, InpTimeframe, i);
      double priceB = iClose(Symbol2, InpTimeframe, i);
      if (priceA == 0 || priceB == 0)
      {
         Print("Error: Price data unavailable for symbols. Skipping calculation.");
         return false;
      }
      sumX += log(priceA);
      sumY += log(priceB);
      sumXY += log(priceA) * log(priceB);
      sumXX += log(priceB) * log(priceB);
   }

   g_hedgeRatio = (InpLookbackPeriod * sumXY - sumX * sumY) / (InpLookbackPeriod * sumXX - sumY * sumY);
   g_meanSpread = sumX / InpLookbackPeriod - g_hedgeRatio * (sumY / InpLookbackPeriod);

   // Calculate the standard deviation of the spread
   double sumSpreadSquared = 0;
   for (int i = 0; i < InpLookbackPeriod; i++)
   {
      double priceA = iClose(Symbol1, InpTimeframe, i);
      double priceB = iClose(Symbol2, InpTimeframe, i);
      double spread = log(priceA) - g_hedgeRatio * log(priceB) - g_meanSpread;
      sumSpreadSquared += spread * spread;
   }
   g_stdDevSpread = sqrt(sumSpreadSquared / InpLookbackPeriod);

   Print("Parameters updated - Hedge Ratio: ", g_hedgeRatio, " Mean Spread: ", g_meanSpread, " Std Dev Spread: ", g_stdDevSpread);
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Position Volume                                        |
//+------------------------------------------------------------------+
void CalculatePositionVolume(double &volumeA, double &volumeB)
{
   double exposure = AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxExposurePercentage / 100;
   double priceA = SymbolInfoDouble(Symbol1, SYMBOL_ASK);
   double priceB = SymbolInfoDouble(Symbol2, SYMBOL_ASK);

   double volA = iStdDev(Symbol1, InpTimeframe, InpLookbackPeriod, 0, MODE_SMA, PRICE_CLOSE);
   double volB = iStdDev(Symbol2, InpTimeframe, InpLookbackPeriod, 0, MODE_SMA, PRICE_CLOSE);

   double weightA = 1 / volA;
   double weightB = 1 / volB;
   double totalWeight = weightA + weightB;

   volumeA = (weightA / totalWeight) * exposure / priceA;
   volumeB = (weightB / totalWeight) * exposure / priceB;

   // Apply symbol-specific limits
   volumeA = NormalizeVolume(Symbol1, volumeA);
   volumeB = NormalizeVolume(Symbol2, volumeB);

   Print("Calculated volumes - Symbol1: ", volumeA, " Symbol2: ", volumeB);
}

//+------------------------------------------------------------------+
//| Normalize Volume to Symbol Limits                                |
//+------------------------------------------------------------------+
double NormalizeVolume(string symbol, double volume)
{
   double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   volume = MathMax(minVolume, MathMin(maxVolume, volume));
   volume = MathRound(volume / lotStep) * lotStep;
   return volume;
}

//+------------------------------------------------------------------+
//| Generate Trade Signals                                           |
//+------------------------------------------------------------------+
void GenerateTradeSignals()
{
   double currentPriceA = SymbolInfoDouble(Symbol1, SYMBOL_ASK);
   double currentPriceB = SymbolInfoDouble(Symbol2, SYMBOL_ASK);
   double currentSpread = log(currentPriceA) - g_hedgeRatio * log(currentPriceB) - g_meanSpread;
   double volumeA, volumeB;
   CalculatePositionVolume(volumeA, volumeB);

   Print("Current spread: ", currentSpread, " Threshold: ", InpEntryThreshold * g_stdDevSpread);

   if (!PositionSelect(Symbol1) && !PositionSelect(Symbol2))
   {
      if (currentSpread > InpEntryThreshold * g_stdDevSpread)
      {
         OpenPairTrade(volumeA, volumeB, ORDER_TYPE_SELL, ORDER_TYPE_BUY);
      }
      else if (currentSpread < -InpEntryThreshold * g_stdDevSpread)
      {
         OpenPairTrade(volumeA, volumeB, ORDER_TYPE_BUY, ORDER_TYPE_SELL);
      }
   }
   else if (PositionSelect(Symbol1) && PositionSelect(Symbol2))
   {
      if (MathAbs(currentSpread) < InpExitThreshold * g_stdDevSpread)
      {
         ClosePairTrade();
      }
   }
}

//+------------------------------------------------------------------+
//| Open Pair Trade                                                  |
//+------------------------------------------------------------------+
void OpenPairTrade(double volumeA, double volumeB, ENUM_ORDER_TYPE orderTypeA, ENUM_ORDER_TYPE orderTypeB)
{
    bool tradeOpened = false;

    // Handle the first leg of the trade
    if (orderTypeA == ORDER_TYPE_SELL)
        tradeOpened = trade.Sell(volumeA, Symbol1);
    else if (orderTypeA == ORDER_TYPE_BUY)
        tradeOpened = trade.Buy(volumeA, Symbol1);

    if (tradeOpened)
    {
        tradeOpened = false; // Reset flag for the second trade

        // Handle the second leg of the trade
        if (orderTypeB == ORDER_TYPE_BUY)
            tradeOpened = trade.Buy(volumeB, Symbol2);
        else if (orderTypeB == ORDER_TYPE_SELL)
            tradeOpened = trade.Sell(volumeB, Symbol2);

        if (tradeOpened)
        {
            Print("Pair trade opened - Symbol1: ", Symbol1, " Symbol2: ", Symbol2);
        }
        else
        {
            Print("Failed to open second leg of pair trade. Closing first leg.");
            trade.PositionClose(Symbol1); // Close the first position if the second fails
        }
    }
    else
    {
        Print("Failed to open first leg of pair trade. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Close Pair Trade                                                 |
//+------------------------------------------------------------------+
void ClosePairTrade()
{
   bool closedSymbol1 = trade.PositionClose(Symbol1);
   bool closedSymbol2 = trade.PositionClose(Symbol2);

   if (closedSymbol1 && closedSymbol2)
   {
      Print("Pair trade closed successfully.");
   }
   else
   {
      Print("Failed to close pair trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check for Excessive Losses                                       |
//+------------------------------------------------------------------+
bool CheckForLosses()
{
   double currentLoss = 0;
   if (PositionSelect(Symbol1))
      currentLoss += PositionGetDouble(POSITION_PROFIT);
   if (PositionSelect(Symbol2))
      currentLoss += PositionGetDouble(POSITION_PROFIT);

   if (currentLoss < -AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxLossPercentage / 100)
   {
      Print("Excessive loss detected. Closing positions. Current loss: ", currentLoss);
      ClosePairTrade();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Dynamic Parameter Adjustment                                     |
//+------------------------------------------------------------------+
bool DynamicParameterAdjustment()
{
   if (TimeCurrent() - g_lastEvaluationTime > InpReEvaluationInterval * 60)
   {
      if (!CalculateCointegrationParameters())
      {
         Print("Parameter re-evaluation failed. Continuing with old parameters.");
         return false;
      }
      g_lastEvaluationTime = TimeCurrent();
   }
   return true;
}