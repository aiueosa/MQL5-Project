#include <Trade\Trade.mqh>

// Input parameters
input double Exposure = 1.0; // Exposure for position sizing
input int MagicNumber = 123456; // Magic number for trade identification
input bool DebugMode = true; // Toggle debugging
input int KPeriod = 5; // Stochastic %K period
input int DPeriod = 3; // Stochastic %D period
input int Slowing = 3; // Stochastic slowing
input double ProfitTargetPercent = 0.04; // Profit target percentage

// Constants
#define SYMBOL_COUNT 5
#define RETURN_PERIOD 100

// Global variables
double weights[];
double positionSizes[];
int stochasticHandles[];
CTrade trade;
double initialBalance;

// Symbols array
string symbols[SYMBOL_COUNT] = {"EURUSD", "USDJPY", "GBPUSD", "USDCAD", "AUDUSD"};

// Function to calculate standard deviation
double CalculateStandardDeviation(const double &data[], int size) {
    if(size <= 1) return 0;
    
    double mean = 0.0, sum = 0.0;
    for (int i = 0; i < size; i++) {
        mean += data[i];
    }
    mean /= size;
    for (int i = 0; i < size; i++) {
        sum += MathPow(data[i] - mean, 2);
    }
    return MathSqrt(sum / (size - 1)); // Using n-1 for sample standard deviation
}

// Function to calculate position sizes based on risk parity
bool CalculatePositionSizes() {
    double returns[];
    double volatilities[];
    double totalWeight = 0.0;
    
    ArrayResize(weights, SYMBOL_COUNT);
    ArrayResize(positionSizes, SYMBOL_COUNT);
    ArrayResize(volatilities, SYMBOL_COUNT);
    ArrayResize(returns, RETURN_PERIOD);
    ArrayResize(stochasticHandles, SYMBOL_COUNT);

    // Calculate log returns and volatilities
    for (int i = 0; i < SYMBOL_COUNT; i++) {
        for (int j = 0; j < RETURN_PERIOD; j++) {
            double closePrice = iClose(symbols[i], PERIOD_D1, j);
            double prevClosePrice = iClose(symbols[i], PERIOD_D1, j + 1);
            if(closePrice <= 0 || prevClosePrice <= 0) {
                Print("Error: Invalid price data for ", symbols[i]);
                return false;
            }
            returns[j] = MathLog(closePrice / prevClosePrice);
        }
        volatilities[i] = CalculateStandardDeviation(returns, RETURN_PERIOD);
        if(volatilities[i] == 0) {
            Print("Error: Zero volatility for ", symbols[i]);
            return false;
        }
    }

    // Calculate weights based on inverse volatility
    for (int i = 0; i < SYMBOL_COUNT; i++) {
        weights[i] = 1.0 / volatilities[i];
        totalWeight += weights[i];
    }
    if(totalWeight == 0) {
        Print("Error: Total weight is zero");
        return false;
    }

    // Normalize weights and calculate position sizes
    for (int i = 0; i < SYMBOL_COUNT; i++) {
        weights[i] /= totalWeight;
        double contractSize = SymbolInfoDouble(symbols[i], SYMBOL_TRADE_CONTRACT_SIZE);
        double lotStep = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_STEP);
        double minLot = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MAX);

        if(contractSize <= 0 || lotStep <= 0) {
            Print("Error: Invalid contract size or lot step for ", symbols[i]);
            return false;
        }

        positionSizes[i] = weights[i] * Exposure / contractSize;
        positionSizes[i] = MathMax(minLot, MathMin(maxLot, MathRound(positionSizes[i] / lotStep) * lotStep));

        // Create Stochastic handle
        stochasticHandles[i] = iStochastic(symbols[i], PERIOD_H4, KPeriod, DPeriod, Slowing, MODE_SMA, STO_LOWHIGH);
        if(stochasticHandles[i] == INVALID_HANDLE) {
            Print("Error: Failed to create Stochastic handle for ", symbols[i]);
            return false;
        }
    }

    if (DebugMode) {
        for (int i = 0; i < SYMBOL_COUNT; i++) {
            Print("Symbol: ", symbols[i], " Weight: ", DoubleToString(weights[i], 4), " Position Size: ", DoubleToString(positionSizes[i], 2));
        }
    }
    
    return true;
}

// Function to check stochastic crossover for entry conditions
bool CheckEntryConditions(int index) {
    if(index < 0 || index >= SYMBOL_COUNT) return false;
    
    double k[], d[];
    ArraySetAsSeries(k, true);
    ArraySetAsSeries(d, true);
    
    if (CopyBuffer(stochasticHandles[index], 0, 0, 2, k) != 2 || CopyBuffer(stochasticHandles[index], 1, 0, 2, d) != 2) {
        Print("Error: Failed to copy Stochastic buffer for ", symbols[index]);
        return false;
    }
    
    return k[1] <= d[1] && k[0] > d[0]; // Checking for crossover
}

// Function to check if a position is open for a given symbol
bool IsPositionOpen(const string symbol) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if (PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                return true;
            }
        }
    }
    return false;
}

// Function to calculate total floating profit
double CalculateTotalFloatingProfit() {
    double totalProfit = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                totalProfit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    return totalProfit;
}

// Function to close all positions
void CloseAllPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

// Function to execute trades
void ExecuteTrades() {
    double totalProfit = CalculateTotalFloatingProfit();
    if (totalProfit >= initialBalance * ProfitTargetPercent / 100.0) {
        CloseAllPositions();
    } else {
        for (int i = 0; i < SYMBOL_COUNT; i++) {
            if (!IsPositionOpen(symbols[i]) && CheckEntryConditions(i)) {
                trade.Buy(positionSizes[i], symbols[i], 0, 0, 0, "EA Trade");
            }
        }
    }
}

// OnInit function
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(!CalculatePositionSizes()) {
        Print("Failed to initialize EA");
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

// OnTick function
void OnTick() {
    ExecuteTrades();
}

// OnDeinit function
void OnDeinit(const int reason) {
    for (int i = 0; i < ArraySize(stochasticHandles); i++) {
        if(stochasticHandles[i] != INVALID_HANDLE) {
            IndicatorRelease(stochasticHandles[i]);
        }
    }
    if (DebugMode) Print("Deinitializing EA");
}