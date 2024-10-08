//20240821あまりにも複雑すぎるのでストップ

//+------------------------------------------------------------------+
//|                                                    PairTrade.mq5 |
//|                        ChatGPTと人間の支援により生成されました    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, ChatGPT and Human"
#property link      "https://www.example.com"
#property version   "1.04"
#property strict

// 入力パラメータ
input string Symbol1 = "US100Cash"; // ペアの最初の銘柄
input string Symbol2 = "FRA40Cash"; // ペアの2番目の銘柄

input double EntryThreshold = 2.0; // エントリーのためのz-scoreしきい値
input double ExitThreshold = 0.5;  // エグジットのためのz-scoreしきい値

input double TakeProfitPercent = 5.0; // 口座残高に対する利益確定の割合
input double DisasterLimitPercent = 49.0; // 口座残高に対する災害限度の割合

input int AtrPeriod = 14; // ポジションサイジングのためのATR期間
input double LotSizeRisk = 0.01; // 1取引あたりのリスク割合

input int Slippage = 3; // スリッページの許容範囲（ポイント）
input int CointPeriod = 100; // 共和分テストの期間
input double LotSizeMultiplier = 0.1; // ロットサイズの倍率（0.1 = 10分の1）

// 新しい取引時間制御用のinputパラメーター
input string TradingStartTime = "09:00"; // 取引開始時間 (HH:MM)
input string TradingEndTime = "17:00";   // 取引終了時間 (HH:MM)

// ポジションハンドルを格納する変数
int posTicket1 = 0;
int posTicket2 = 0;

// インジケーターのハンドル
int maHandle1, maHandle2, stdDevHandle1, stdDevHandle2, atrHandle1, atrHandle2;

//+------------------------------------------------------------------+
//| エキスパートアドバイザーの初期化関数                               |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("ペアトレードEAが初期化されました。");
  
  // インジケーターハンドルの初期化
  maHandle1 = iMA(Symbol1, PERIOD_CURRENT, CointPeriod, 0, MODE_SMA, PRICE_CLOSE);
  maHandle2 = iMA(Symbol2, PERIOD_CURRENT, CointPeriod, 0, MODE_SMA, PRICE_CLOSE);
  stdDevHandle1 = iStdDev(Symbol1, PERIOD_CURRENT, CointPeriod, 0, MODE_SMA, PRICE_CLOSE);
  stdDevHandle2 = iStdDev(Symbol2, PERIOD_CURRENT, CointPeriod, 0, MODE_SMA, PRICE_CLOSE);
  atrHandle1 = iATR(Symbol1, PERIOD_CURRENT, AtrPeriod);
  atrHandle2 = iATR(Symbol2, PERIOD_CURRENT, AtrPeriod);
  
  // インジケーターハンドルの作成に失敗した場合、エラーを返す
  if(maHandle1 == INVALID_HANDLE || maHandle2 == INVALID_HANDLE || 
     stdDevHandle1 == INVALID_HANDLE || stdDevHandle2 == INVALID_HANDLE ||
     atrHandle1 == INVALID_HANDLE || atrHandle2 == INVALID_HANDLE)
  {
    Print("インジケーターハンドルの作成に失敗しました");
    return(INIT_FAILED);
  }
  
  // シンボルのロットサイズ制限をチェック
  CheckSymbolLotSizeRestrictions(Symbol1);
  CheckSymbolLotSizeRestrictions(Symbol2);
  
  // 取引時間の妥当性チェック
  if(!CheckTradingTimeValidity())
  {
    return INIT_PARAMETERS_INCORRECT;
  }

  Print("取引時間設定: ", TradingStartTime, " - ", TradingEndTime);
  
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| エキスパートアドバイザーの終了化関数                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  // インジケーターハンドルの解放
  IndicatorRelease(maHandle1);
  IndicatorRelease(maHandle2);
  IndicatorRelease(stdDevHandle1);
  IndicatorRelease(stdDevHandle2);
  IndicatorRelease(atrHandle1);
  IndicatorRelease(atrHandle2);
  
  Print("ペアトレードEAが終了化されました。");
}

//+------------------------------------------------------------------+
//| エキスパートアドバイザーのティック関数                             |
//+------------------------------------------------------------------+
void OnTick()
{
  // 現在の時間が取引時間内かつ平日かチェック
  if(!IsWithinTradingHours())
  {
    return;
  }

  // 標準化された価格スプレッドに基づいてz-scoreを計算
  double zScore = CalculateZScore();

  // エントリー条件のチェック
  if(zScore >= EntryThreshold && posTicket1 == 0 && posTicket2 == 0)
  {
    double lotSize = CalculateLotSize(Symbol1, Symbol2, AtrPeriod, LotSizeRisk);
    if(lotSize > 0)
    {
      posTicket1 = SendOrder(Symbol1, ORDER_TYPE_BUY, lotSize);
      posTicket2 = SendOrder(Symbol2, ORDER_TYPE_SELL, lotSize);
    }
  }

  // エグジット条件のチェック
  if(posTicket1 != 0 && posTicket2 != 0)
  {
    double profit = CalculateNetProfit();
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(zScore <= ExitThreshold || 
       profit >= equity * (TakeProfitPercent / 100.0) || 
       profit <= -equity * (DisasterLimitPercent / 100.0))
    {
      CloseAllPositions();
      if(profit <= -equity * (DisasterLimitPercent / 100.0))
      {
        Print("災害限度に達しました。EAを停止します。");
        ExpertRemove();
      }
    }
  }
}

//+------------------------------------------------------------------+
//| 現在の時間が取引時間内かつ平日かチェックする                       |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
  datetime currentTime = TimeCurrent();
  MqlDateTime structTime;
  TimeToStruct(currentTime, structTime);

  // 週末チェック
  if(structTime.day_of_week == SATURDAY || structTime.day_of_week == SUNDAY)
  {
    return false;
  }

  // 時間のみを抽出して比較
  int currentMinutes = structTime.hour * 60 + structTime.min;
  int startMinutes = StringToTime(TradingStartTime) / 60 % 1440; // 1440 = 24 * 60
  int endMinutes = StringToTime(TradingEndTime) / 60 % 1440;

  return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
}

//+------------------------------------------------------------------+
//| 取引時間の妥当性をチェックする                                     |
//+------------------------------------------------------------------+
bool CheckTradingTimeValidity()
{
  int startMinutes = StringToTime(TradingStartTime) / 60 % 1440;
  int endMinutes = StringToTime(TradingEndTime) / 60 % 1440;

  if(startMinutes >= endMinutes)
  {
    Print("エラー: 取引開始時間は終了時間より前である必要があります");
    return false;
  }

  return true;
}

//+------------------------------------------------------------------+
//| 標準化された価格スプレッドに基づいてz-scoreを計算する               |
//+------------------------------------------------------------------+
double CalculateZScore()
{
  double price1 = SymbolInfoDouble(Symbol1, SYMBOL_LAST);
  double price2 = SymbolInfoDouble(Symbol2, SYMBOL_LAST);
  
  double avg1[], avg2[], stdDev1[], stdDev2[];
  
  // インジケーターバッファからデータをコピー
  CopyBuffer(maHandle1, 0, 0, 1, avg1);
  CopyBuffer(maHandle2, 0, 0, 1, avg2);
  CopyBuffer(stdDevHandle1, 0, 0, 1, stdDev1);
  CopyBuffer(stdDevHandle2, 0, 0, 1, stdDev2);

  // データの取得に失敗した場合はエラーを返す
  if(ArraySize(avg1) == 0 || ArraySize(avg2) == 0 || ArraySize(stdDev1) == 0 || ArraySize(stdDev2) == 0)
  {
    Print("インジケーターデータの取得に失敗しました");
    return 0;
  }

  // z-scoreの計算
  double z1 = (price1 - avg1[0]) / stdDev1[0];
  double z2 = (price2 - avg2[0]) / stdDev2[0];

  return z1 - z2;
}

//+------------------------------------------------------------------+
//| ATRとリスク割合に基づいてロットサイズを計算する                    |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym1, string sym2, int atrPeriod, double riskPercent)
{
  double atr1[], atr2[];
  
  // ATRデータをコピー
  if(CopyBuffer(atrHandle1, 0, 0, 1, atr1) <= 0 || CopyBuffer(atrHandle2, 0, 0, 1, atr2) <= 0)
  {
    Print("ATRデータのコピーに失敗しました");
    return 0;
  }
  
  // ATR値が0の場合はエラーを返す
  if(atr1[0] == 0 || atr2[0] == 0)
  {
    Print("ATRの計算に失敗しました");
    return 0;
  }
  
  // ティック値の取得
  double tickValue1 = SymbolInfoDouble(sym1, SYMBOL_TRADE_TICK_VALUE);
  double tickValue2 = SymbolInfoDouble(sym2, SYMBOL_TRADE_TICK_VALUE);
  
  // ロットサイズの計算
  double lotSize1 = (AccountInfoDouble(ACCOUNT_EQUITY) * riskPercent) / (atr1[0] * tickValue1);
  double lotSize2 = (AccountInfoDouble(ACCOUNT_EQUITY) * riskPercent) / (atr2[0] * tickValue2);

  // 2つのロットサイズの小さい方を選択し、倍率を適用
  double finalLotSize = MathMin(lotSize1, lotSize2) * LotSizeMultiplier;

  // 各シンボルに対してロットサイズを調整
  double adjustedLot1 = AdjustLotSize(sym1, finalLotSize);
  double adjustedLot2 = AdjustLotSize(sym2, finalLotSize);

  // 2つの調整後のロットサイズの小さい方を選択
  finalLotSize = MathMin(adjustedLot1, adjustedLot2);

  if(finalLotSize == 0)
  {
    Print("警告: 計算されたロットサイズが取引可能な最小サイズを下回っています。取引をスキップします。");
    return 0;
  }

  return finalLotSize;
}

//+------------------------------------------------------------------+
//| ブローカーの制限に合わせてロットサイズを調整する                    |
//+------------------------------------------------------------------+
double AdjustLotSize(string symbol, double lotSize)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    // 最小ロットサイズ未満の場合、最小ロットサイズに調整
    if(lotSize < minLot) lotSize = minLot;

    // 最大ロットサイズを超える場合、最大ロットサイズに調整
    if(lotSize > maxLot) lotSize = maxLot;

    // ステップサイズに合わせて調整
    lotSize = MathRound(lotSize / stepLot) * stepLot;

    // 調整後のロットサイズが再び最小値を下回らないことを確認
    if(lotSize < minLot) lotSize = 0; // 取引不可能なサイズの場合は0を返す

    Print("調整後のロットサイズ (", symbol, "): ", lotSize, 
          " (最小: ", minLot, ", 最大: ", maxLot, ", ステップ: ", stepLot, ")");

    return lotSize;
}

//+------------------------------------------------------------------+
//| オープンポジションの純利益を計算する                               |
//+------------------------------------------------------------------+
double CalculateNetProfit()
{
  double profit = 0;
  for(int i = 0; i < PositionsTotal(); i++)
  {
    if(PositionSelectByTicket(PositionGetTicket(i)))
    {
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) - PositionGetDouble(POSITION_COMMISSION);
    }
  }
  return profit;
}

//+------------------------------------------------------------------+
//| 全てのオープンポジションをクローズする                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
if(PositionSelectByTicket(PositionGetTicket(i)))
    {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string symbol = PositionGetString(POSITION_SYMBOL);
      
      if(type == POSITION_TYPE_BUY)
        TradeAction(ticket, ORDER_TYPE_SELL, volume, symbol);
      else
        TradeAction(ticket, ORDER_TYPE_BUY, volume, symbol);
    }
  }
  posTicket1 = 0;
  posTicket2 = 0;
}

//+------------------------------------------------------------------+
//| 注文を送信する                                                    |
//+------------------------------------------------------------------+
int SendOrder(string symbol, ENUM_ORDER_TYPE type, double lotSize)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    // 注文リクエストの設定
    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.type = type;
    request.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.deviation = Slippage;
    request.magic = 123456; // マジックナンバー
    request.comment = "ペアトレード";
    
    // サポートされている約定方法を取得
    uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    
    if((filling & SYMBOL_FILLING_FOK) != 0)
        request.type_filling = ORDER_FILLING_FOK;
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        request.type_filling = ORDER_FILLING_IOC;
    else
        request.type_filling = ORDER_FILLING_RETURN; // これがサポートされていない場合はエラーになる可能性があります

    // 注文の送信
    if(!OrderSend(request, result))
    {
        Print("注文の送信に失敗しました: ", GetLastError(), " 銘柄: ", symbol, " タイプ: ", EnumToString(type), " ロットサイズ: ", lotSize);
        return 0;
    }

    Print("注文が成功しました: ", result.order, " 銘柄: ", symbol, " タイプ: ", EnumToString(type), " ロットサイズ: ", lotSize);
    return (int)result.order;
}

//+------------------------------------------------------------------+
//| ポジションをクローズするためのトレードアクション                    |
//+------------------------------------------------------------------+
void TradeAction(ulong ticket, ENUM_ORDER_TYPE type, double lotSize, string symbol)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    // トレードリクエストの設定
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = symbol;
    request.volume = lotSize;
    request.type = type;
    request.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.deviation = Slippage;
    request.magic = 123456; // マジックナンバー
    request.comment = "ペアトレードのクローズ";
    request.type_filling = ORDER_FILLING_FOK;

    // トレードアクションの実行
    if(!OrderSend(request, result))
    {
        Print("トレードアクションの実行に失敗しました: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| シンボルのロットサイズ制限をチェックする                           |
//+------------------------------------------------------------------+
void CheckSymbolLotSizeRestrictions(string symbol)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    Print(symbol, " ロットサイズ制限: 最小 = ", minLot, ", 最大 = ", maxLot, ", ステップ = ", stepLot);

    if(minLot > 0.01)
    {
        Print("警告: ", symbol, " の最小ロットサイズが 0.01 より大きいです。EA の設定を確認してください。");
    }
}