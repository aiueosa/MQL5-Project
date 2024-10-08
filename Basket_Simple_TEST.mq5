//+------------------------------------------------------------------+
//|                                        MT5バスケットトレードEA |
//|                                  Copyright 2024, Your Name Here |
//|                                             https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name Here"
#property link      "https://www.yourwebsite.com"
#property version   "1.08"
#property strict

#include <Trade\Trade.mqh>

// 外部パラメーター
input string   Symbols                = "US30Cash,US100Cash,US500Cash"; // 取引銘柄（カンマ区切り）
input ENUM_TIMEFRAMES DataTimeframe   = PERIOD_M15;                     // データ時間枠
input int      DataPoints             = 100;                            // 使用データポイント数
input double   EntryThreshold         = 2.0;                            // エントリー閾値（標準偏差の倍数）
input double   TpPercent              = 4.0;                            // 利益確定率（%）
input double   MaxPositionSize        = 5.0;                            // 最大ポジションサイズ（%）
input int      SlippageTolerance      = 1;                              // スリッページ許容範囲（ポイント）
input bool     AllowTrade24H          = true;                           // 24時間取引許可
input double   MaxLotPerSymbol        = 0.1;                            // 1銘柄あたりの最大ロット数
input int      LossCutCheckInterval   = 5;                              // ロスカットチェック間隔（分）
input double   ADFCriticalValue       = -3.34;                          // ADFテストの臨界値

// グローバル変数
string g_symbols[];
int g_symbol_count;
CTrade trade;
double g_price_data[][100]; // 100はDataPointsと同じ値、適宜変更可能
datetime g_last_losscut_check = 0;

// キャッシュ用変数
double g_cached_beta[];
int g_cached_data_points = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    g_symbol_count = StringSplit(Symbols, ',', g_symbols);
    if (g_symbol_count != 3) {
        Print("エラー: 正確に3つの銘柄が必要です。");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    ArrayResize(g_price_data, g_symbol_count);
    for (int i = 0; i < g_symbol_count; i++) {
        ArrayInitialize(g_price_data[i], 0); // 各行を0で初期化
    }
    
    Print("EA初期化完了。設定された銘柄:");
    ArrayPrint(g_symbols);
    
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // クリーンアップ処理が必要な場合はここに記述
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (!AllowTrade24H && !IsTradeAllowed()) return;
    
    datetime current_time = TimeCurrent();
    if (current_time - g_last_losscut_check >= LossCutCheckInterval * 60)
    {
        ManagePositions();
        g_last_losscut_check = current_time;
    }
    
    if (IsNewBar()) {
        UpdatePriceData();
        CheckEntrySignals();
    }
}

//+------------------------------------------------------------------+
//| ポジション管理                                                    |
//+------------------------------------------------------------------+
void ManagePositions()
{
    double total_profit = 0, total_margin = 0;
    bool has_positions = false;
    
    for (int i = 0; i < g_symbol_count; i++) {
        if (PositionSelect(g_symbols[i])) {
            has_positions = true;
            double position_profit = PositionGetDouble(POSITION_PROFIT);
            double position_volume = PositionGetDouble(POSITION_VOLUME);
            double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            total_profit += position_profit;
            total_margin += position_volume * SymbolInfoDouble(g_symbols[i], SYMBOL_MARGIN_INITIAL);
            
            if ((position_profit / (position_volume * position_open_price)) >= (TpPercent / 100)) {
                if (trade.PositionClose(g_symbols[i], SlippageTolerance)) {
                    Print("利益確定: ", g_symbols[i], ", 利益: ", position_profit);
                }
            }
        }
    }
    
    if (has_positions && total_margin > 0) {
        if (total_profit <= -(total_margin * 0.49)) {
            CloseAllPositions("ロスカット");
            Print("ロスカット条件を満たしました。全ポジションをクローズし、EAを停止します。総損失: ", total_profit);
            ExpertRemove();
        }
    }
}

//+------------------------------------------------------------------+
//| すべてのポジションを閉じる                                         |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    for (int i = 0; i < g_symbol_count; i++) {
        if (PositionSelect(g_symbols[i])) {
            double position_profit = PositionGetDouble(POSITION_PROFIT);
            double position_volume = PositionGetDouble(POSITION_VOLUME);
            if (trade.PositionClose(g_symbols[i], SlippageTolerance)) {
                Print("ポジションクローズ: ", g_symbols[i], 
                      ", 理由: ", reason, 
                      ", ロット: ", position_volume, 
                      ", 利益: ", position_profit);
            } else {
                Print("ポジションクローズ失敗: ", g_symbols[i], 
                      ", 理由: ", reason, 
                      ", エラー: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 価格データの更新                                                  |
//+------------------------------------------------------------------+
void UpdatePriceData()
{
    for (int i = 0; i < g_symbol_count; i++) {
        double close[];
        ArraySetAsSeries(close, true);
        int copied = CopyClose(g_symbols[i], DataTimeframe, 0, DataPoints, close);
        
        if (copied == DataPoints) {
            for (int j = 0; j < DataPoints; j++) {
                g_price_data[i][j] = close[j];
            }
        } else {
            Print("警告: 価格データのコピーに失敗しました。シンボル: ", g_symbols[i], ", コピーされた数: ", copied);
        }
    }
    // 新しいデータが来たのでキャッシュをリセット
    g_cached_data_points = 0;
}

//+------------------------------------------------------------------+
//| エントリーシグナルのチェック                                       |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    if (EngleGrangerThreeAssets()) {
        double relative_prices[3];
        for (int i = 0; i < g_symbol_count; i++) {
            relative_prices[i] = CalculateRelativePrice(i);
        }
        
        int entry_directions[3];
        bool should_enter = false;
        for (int i = 0; i < g_symbol_count; i++) {
            entry_directions[i] = DetermineEntryDirection(relative_prices[i], EntryThreshold);
            if (entry_directions[i] != 0) should_enter = true;
        }
        
        if (should_enter) {
            string entry_reason = StringFormat("相対価格: %.5f, %.5f, %.5f", 
                                               relative_prices[0], relative_prices[1], relative_prices[2]);
            ExecuteBasketTrade(entry_directions, entry_reason);
        }
    }
}

//+------------------------------------------------------------------+
//| エングル・グレンジャー2段階法（3銘柄版）                            |
//+------------------------------------------------------------------+
bool EngleGrangerThreeAssets()
{
    // ペアワイズ分析
    double temp1[100], temp2[100]; // DataPointsと同じサイズ
    ArrayCopy(temp1, g_price_data[0]);
    ArrayCopy(temp2, g_price_data[1]);
    bool pair12 = EngleGrangerTest(temp1, temp2);
    
    ArrayCopy(temp1, g_price_data[1]);
    ArrayCopy(temp2, g_price_data[2]);
    bool pair23 = EngleGrangerTest(temp1, temp2);
    
    ArrayCopy(temp1, g_price_data[0]);
    ArrayCopy(temp2, g_price_data[2]);
    bool pair13 = EngleGrangerTest(temp1, temp2);
    
    // すべてのペアがコインテグレーションの関係にあるかチェック
    if (pair12 && pair23 && pair13) {
        return true;
    }
    
    // 条件付き分析
    double residuals[];
    ArrayResize(residuals, DataPoints);
    
    double beta[];
    double temp3[];
    ArrayCopy(temp1, g_price_data[0]);
    ArrayCopy(temp2, g_price_data[1]);
    ArrayCopy(temp3, g_price_data[2]);
    if (!CalculateMultipleRegression(temp1, temp2, temp3, beta))
        return false;
    
    // 残差の計算
    for (int i = 0; i < DataPoints; i++)
        residuals[i] = g_price_data[0][i] - (beta[0] + beta[1] * g_price_data[1][i] + beta[2] * g_price_data[2][i]);
    
    // 残差に対するADFテスト
    double adf_statistic = ADFTest(residuals, 1);
    
    // ADF統計量を基準値と比較して判断
    return (adf_statistic < ADFCriticalValue);
}

//+------------------------------------------------------------------+
//| エングル・グレンジャーテスト（2銘柄版）                            |
//+------------------------------------------------------------------+
bool EngleGrangerTest(const double &price1[], const double &price2[])
{
    double residuals[];
    ArrayResize(residuals, DataPoints);
    
    double beta[];
    if(!CalculateRegression(price1, price2, beta))
        return false;
    
    // 残差の計算
    for(int i = 0; i < DataPoints; i++)
        residuals[i] = price1[i] - (beta[0] + beta[1] * price2[i]);
    
    // 残差に対するADFテスト
    double adf_statistic = ADFTest(residuals, 1);
    
    // ADF統計量を基準値と比較して判断
    return (adf_statistic < ADFCriticalValue);
}

//+------------------------------------------------------------------+
//| ADFテスト                                                        |
//+------------------------------------------------------------------+
double ADFTest(const double &price[], int lag)
{
    int n = ArraySize(price);
    double y[], x1[], x2[];
    ArrayResize(y, n-1-lag);
    ArrayResize(x1, n-1-lag);
    ArrayResize(x2, n-1-lag);
    
    for(int i = lag; i < n-1; i++)
    {
        y[i-lag] = price[i+1] - price[i];
        x1[i-lag] = price[i];
        x2[i-lag] = i+1;
    }
    
    double beta[];
if(!CalculateRegression(y, x1, beta)) // 2つの配列を受け取り、betaを計算するために3つの引数に修正
        return 0;
    
    double se = CalculateStandardError(y, x1, beta);
    return beta[1] / se;
}

//+------------------------------------------------------------------+
//| 回帰分析                                                         |
//+------------------------------------------------------------------+
bool CalculateRegression(const double &y[], const double &x[], double &beta[])
{
    int n = ArraySize(y);
    if (n != ArraySize(x)) return false;
    
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
    for (int i = 0; i < n; i++) {
        sum_x += x[i];
        sum_y += y[i];
        sum_xy += x[i] * y[i];
        sum_xx += x[i] * x[i];
    }
    
    double denominator = n * sum_xx - sum_x * sum_x;
    if (denominator == 0) return false;
    
    ArrayResize(beta, 2);
    beta[1] = (n * sum_xy - sum_x * sum_y) / denominator;
    beta[0] = (sum_y - beta[1] * sum_x) / n;
    
    return true;
}

//+------------------------------------------------------------------+
//| 3x3行列の逆行列を計算                                             |
//+------------------------------------------------------------------+
bool InverseMatrix3x3(const double matrix[3][3], double (&inverse)[3][3])

{
    double det = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) -
                 matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) +
                 matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]);
    
    if (MathAbs(det) < 1e-10) return false;
    
    double invDet = 1.0 / det;
    
    inverse[0][0] = (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) * invDet;
    inverse[0][1] = (matrix[0][2] * matrix[2][1] - matrix[0][1] * matrix[2][2]) * invDet;
    inverse[0][2] = (matrix[0][1] * matrix[1][2] - matrix[0][2] * matrix[1][1]) * invDet;
inverse[1][0] = (matrix[1][2] * matrix[2][0] - matrix[1][0] * matrix[2][2]) * invDet;
    inverse[1][1] = (matrix[0][0] * matrix[2][2] - matrix[0][2] * matrix[2][0]) * invDet;
    inverse[1][2] = (matrix[0][2] * matrix[1][0] - matrix[0][0] * matrix[1][2]) * invDet;
    inverse[2][0] = (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]) * invDet;
    inverse[2][1] = (matrix[0][1] * matrix[2][0] - matrix[0][0] * matrix[2][1]) * invDet;
    inverse[2][2] = (matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]) * invDet;
    
    return true;
}

//+------------------------------------------------------------------+
//| 多重回帰分析を実行                                                |
//+------------------------------------------------------------------+
bool CalculateMultipleRegression(const double &y[], const double &x1[], const double &x2[], double &beta[])
{
    int n = ArraySize(y);
    if (n != ArraySize(x1) || n != ArraySize(x2))
        return false;
    
    // キャッシュされたデータがある場合はそれを使用
    if (g_cached_data_points == n && ArraySize(g_cached_beta) == 3) {
        ArrayCopy(beta, g_cached_beta);
        return true;
    }
    
    double xtx[3][3] = {{0}};
    double xty[3] = {0};
    
    // X^T * X と X^T * Y の計算
    for (int i = 0; i < n; i++)
    {
        double x[3] = {1, x1[i], x2[i]}; // 1は定数項のため
        
        for (int j = 0; j < 3; j++)
        {
            for (int k = 0; k < 3; k++)
            {
                xtx[j][k] += x[j] * x[k];
            }
            xty[j] += x[j] * y[i];
        }
    }
    
    // (X^T * X)^(-1) の計算
    double inverse[3][3];
    if (!InverseMatrix3x3(xtx, inverse))
        return false;
    
    // β = (X^T * X)^(-1) * X^T * Y の計算
    ArrayResize(beta, 3);
    for (int i = 0; i < 3; i++)
    {
        beta[i] = 0;
        for (int j = 0; j < 3; j++)
        {
            beta[i] += inverse[i][j] * xty[j];
        }
    }
    
    // 結果をキャッシュ
    g_cached_data_points = n;
    ArrayCopy(g_cached_beta, beta);
    
    return true;
}

//+------------------------------------------------------------------+
//| 標準誤差の計算                                                    |
//+------------------------------------------------------------------+
double CalculateStandardError(const double &y[], const double &x[], const double &beta[])
{
    int n = ArraySize(y);
    double rss = 0;
    
    for (int i = 0; i < n; i++) {
        double residual = y[i] - (beta[0] + beta[1] * x[i]);
        rss += residual * residual;
    }
    
    return MathSqrt(rss / (n - 2));
}

//+------------------------------------------------------------------+
//| 相対価格の計算                                                    |
//+------------------------------------------------------------------+
double CalculateRelativePrice(int symbol_index)
{
    double price = g_price_data[symbol_index][0];
    double avg_price = 0;
    for (int i = 0; i < g_symbol_count; i++) {
        if (i != symbol_index) {
            avg_price += g_price_data[i][0];
        }
    }
    avg_price /= (g_symbol_count - 1);
    return (price - avg_price) / avg_price;
}

//+------------------------------------------------------------------+
//| エントリー方向の決定                                              |
//+------------------------------------------------------------------+
int DetermineEntryDirection(double relative_price, double threshold)
{
    if (relative_price > threshold) return -1; // ショート
    if (relative_price < -threshold) return 1; // ロング
    return 0; // エントリーなし
}

//+------------------------------------------------------------------+
//| バスケットトレードの実行                                           |
//+------------------------------------------------------------------+
void ExecuteBasketTrade(const int& entry_directions[], string entry_reason)
{
    double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double volatilities[], lot_sizes[];
    double total_volatility = 0, total_lot_size = 0, total_min_lot = 0;
    
    ArrayResize(volatilities, g_symbol_count);
    ArrayResize(lot_sizes, g_symbol_count);
    
    for (int i = 0; i < g_symbol_count; i++) {
        volatilities[i] = CalculateVolatility(g_symbols[i]);
        total_volatility += volatilities[i];
        total_min_lot += SymbolInfoDouble(g_symbols[i], SYMBOL_VOLUME_MIN);
    }
    
    for (int i = 0; i < g_symbol_count; i++) {
        lot_sizes[i] = CalculateLotSize(g_symbols[i], account_equity, volatilities[i], total_volatility);
        total_lot_size += lot_sizes[i];
    }
    
    if (total_lot_size >= total_min_lot) {
        Print("バスケットトレードエントリー理由: ", entry_reason);
        
        for (int i = 0; i < g_symbol_count; i++) {
            if (entry_directions[i] == 1) {
                trade.Buy(lot_sizes[i], g_symbols[i], 0, 0, 0, "バスケットトレード（ロング）");
                Print("トレード実行: ", g_symbols[i], ", 方向: ロング, ロットサイズ: ", lot_sizes[i]);
            } else if (entry_directions[i] == -1) {
                trade.Sell(lot_sizes[i], g_symbols[i], 0, 0, 0, "バスケットトレード（ショート）");
                Print("トレード実行: ", g_symbols[i], ", 方向: ショート, ロットサイズ: ", lot_sizes[i]);
            }
        }
    } else {
        Print("警告: 適切なロットサイズ配分ができないため、エントリーをスキップします。");
    }
}

//+------------------------------------------------------------------+
//| ロットサイズの計算                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double equity, double volatility, double total_volatility)
{
    double position_size = equity * (MaxPositionSize / 100) * (1 - (volatility / total_volatility));
    double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double symbol_price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    double lot_size = NormalizeDouble(position_size / (contract_size * symbol_price), (int)(-MathLog10(lot_step)));
    lot_size = MathMax(min_lot, MathMin(MathMin(max_lot, MaxLotPerSymbol), lot_size));
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| ボラティリティの計算                                              |
//+------------------------------------------------------------------+
double CalculateVolatility(string symbol)
{
    double close[];
    ArraySetAsSeries(close, true);
    
    int copied = CopyClose(symbol, PERIOD_D1, 0, 20, close);
    
    if (copied != 20) {
        Print("警告: ボラティリティ計算のためのデータのコピーに失敗しました。シンボル: ", symbol, ", コピーされた数: ", copied);
        return 1;
    }
    
    double sum = 0, sum2 = 0;
    for (int i = 1; i < 20; i++) {
        double returns = (close[i] - close[i-1]) / close[i-1];
        sum += returns;
        sum2 += MathPow(returns, 2);
    }
    
    double mean = sum / 19;
    return MathSqrt((sum2 / 19) - MathPow(mean, 2));
}

//+------------------------------------------------------------------+
//| 新しいバーの確認                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime last_time = 0;
    datetime current_time = iTime(Symbol(), DataTimeframe, 0);
    
    if (current_time != last_time) {
        last_time = current_time;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| 取引許可時間のチェック                                             |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    
    int day_of_week = time.day_of_week;
    int hour = time.hour;
    int minute = time.min;
    
    // 月曜日の00:05から金曜日の23:55まで取引を許可
    return (day_of_week > 0 && day_of_week < 5) || 
           (day_of_week == 0 && (hour > 0 || (hour == 0 && minute >= 5))) ||
           (day_of_week == 5 && (hour < 23 || (hour == 23 && minute <= 55)));
}