#property strict

input string CSV_FILE     = "signals.csv";
input string UPDATE_FILE  = "mt5_updates.txt";
input double DEFAULT_LOT  = 0.01;
input double GOLD_LOT     = 0.02;
input double USD_LOT      = 0.01;

input bool   ENABLE_BREAKEVEN          = true;
input double INITIAL_BREAKEVEN_PIPS    = 50.0;
input double BREAKEVEN_OFFSET_PIPS     = 5.0;

input int    EXPIRY_HOUR = 23;

bool dailyCleanupDone = false;

//+------------------------------------------------------------------+
//| تابع نوشتن به‌روزرسانی در فایل                                    |
//+------------------------------------------------------------------+
void WriteUpdate(string id, string status) {
   int handle = FileOpen(UPDATE_FILE, FILE_WRITE | FILE_READ | FILE_ANSI | FILE_TXT);
   if (handle == INVALID_HANDLE) return;
   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, id + "," + status + "\n");
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| بررسی وجود سفارش یا پوزیشن با کامنت مشخص                         |
//+------------------------------------------------------------------+
bool OrderExistsWithComment(string comment) {
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderGetTicket(i) > 0 && OrderGetString(ORDER_COMMENT) == comment) return true;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
      if (PositionGetTicket(i) > 0 && PositionGetString(POSITION_COMMENT) == comment) return true;
   return false;
}

//+------------------------------------------------------------------+
//| محاسبه اندازه Pip                                                |
//+------------------------------------------------------------------+
double GetPipSize(string symbol) {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? 0.0001 : 0.01;
}

//+------------------------------------------------------------------+
//| تعیین Filling Mode                                               |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol) {
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if ((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   else if ((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| محاسبه Lot بر اساس نوع نماد (بدون توجه به CSV)                   |
//+------------------------------------------------------------------+
double GetLotForSymbol(string symbol, double csvVolume) {
   // نادیده گرفتن csvVolume - فقط بر اساس نماد تصمیم‌گیری
   
   if (StringFind(symbol, "XAU") >= 0) return GOLD_LOT;
   
   if (StringLen(symbol) >= 6) {
      string lastThree = StringSubstr(symbol, StringLen(symbol) - 3, 3);
      if (lastThree == "USD") return USD_LOT;
   }
   
   return DEFAULT_LOT;
}

//+------------------------------------------------------------------+
//| مدیریت Breakeven                                                 |
//+------------------------------------------------------------------+
void ManageBreakeven() {
   if (!ENABLE_BREAKEVEN) return;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      string symbol       = PositionGetString(POSITION_SYMBOL);
      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL    = PositionGetDouble(POSITION_SL);
      double currentTP    = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double pipSize    = GetPipSize(symbol);
      double profitPips = (type == POSITION_TYPE_BUY)
         ? (currentPrice - openPrice) / pipSize
         : (openPrice - currentPrice) / pipSize;

      if (profitPips < INITIAL_BREAKEVEN_PIPS) continue;

      double breakevenSL;
      bool   shouldUpdate = false;

      if (type == POSITION_TYPE_BUY) {
         breakevenSL = openPrice + (BREAKEVEN_OFFSET_PIPS * pipSize);
         if (currentSL < breakevenSL) shouldUpdate = true;
      } else {
         breakevenSL = openPrice - (BREAKEVEN_OFFSET_PIPS * pipSize);
         if (currentSL > breakevenSL || currentSL == 0) shouldUpdate = true;
      }

      if (shouldUpdate) {
         ModifyPosition(ticket, breakevenSL, currentTP);
         Print("🔒 Breakeven: ticket=", ticket, " SL=", DoubleToString(breakevenSL, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
      }
   }
}

//+------------------------------------------------------------------+
//| تغییر SL/TP پوزیشن                                               |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp) {
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl       = NormalizeDouble(sl, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
   req.tp       = tp;
   if (OrderSend(req, res))
      Print("✅ SL updated: ticket=", ticket, " SL=", sl);
   else
      Print("❌ Modify failed: ticket=", ticket, " error=", res.retcode);
}

//+------------------------------------------------------------------+
//| حذف سفارشات Pending منقضی شده                                    |
//+------------------------------------------------------------------+
void DeleteExpiredPendingOrders() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if (dt.hour != EXPIRY_HOUR) { dailyCleanupDone = false; return; }
   if (dailyCleanupDone) return;

   int deletedCount = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0) continue;
      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT) continue;

      string comment = OrderGetString(ORDER_COMMENT);
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      if (OrderSend(req, res)) {
         deletedCount++;
         Print("🗑️ Pending deleted: ticket=", ticket);
         if (comment != "") WriteUpdate(comment, "expired");
      } else {
         Print("❌ Delete failed: ticket=", ticket, " error=", res.retcode);
      }
   }
   if (deletedCount > 0)
      Print("🕚 Cleanup: ", deletedCount, " orders deleted at ", EXPIRY_HOUR, ":00");
   dailyCleanupDone = true;
}

//+------------------------------------------------------------------+
//| مقداردهی اولیه                                                   |
//+------------------------------------------------------------------+
int OnInit() { 
   EventSetTimer(30); 
   Print("✅ Expert Advisor initialized");
   return INIT_SUCCEEDED; 
}

//+------------------------------------------------------------------+
//| تابع اصلی Timer                                                  |
//+------------------------------------------------------------------+
void OnTimer() {
   ManageBreakeven();
   DeleteExpiredPendingOrders();

   int handle = FileOpen(CSV_FILE, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if (handle == INVALID_HANDLE) { 
      Print("❌ Cannot open ", CSV_FILE); 
      return; 
   }

   for (int i = 0; i < 9; i++) FileReadString(handle);

   while (!FileIsEnding(handle)) {
      string id        = FileReadString(handle);
      string symbol    = FileReadString(handle);
      string direction = FileReadString(handle);
      double entry     = StringToDouble(FileReadString(handle));
      double sl        = StringToDouble(FileReadString(handle));
      double tp        = StringToDouble(FileReadString(handle));
      double volume    = StringToDouble(FileReadString(handle));
      string timestamp = FileReadString(handle);
      string status    = FileReadString(handle);

      if (id == "") continue;

      if (status == "waiting to open" && !OrderExistsWithComment(id)) {
         string fullSymbol = symbol + ".ec";
         int    digits     = (int)SymbolInfoInteger(fullSymbol, SYMBOL_DIGITS);
         double lot        = GetLotForSymbol(symbol, volume);
         
         MqlTradeRequest req = {};
         MqlTradeResult  res = {};

         if (entry == 0.0) {
            bool isBuy = (direction == "Buy");
            req.action       = TRADE_ACTION_DEAL;
            req.symbol       = fullSymbol;
            req.type         = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            req.volume       = lot;
            req.price        = isBuy ? SymbolInfoDouble(fullSymbol, SYMBOL_ASK)
                                     : SymbolInfoDouble(fullSymbol, SYMBOL_BID);
            req.sl           = NormalizeDouble(sl, digits);
            req.tp           = NormalizeDouble(tp, digits);
            req.comment      = id;
            req.type_filling = GetFillingMode(fullSymbol);
            req.deviation    = 10;
            
            if (OrderSend(req, res)) {
               Print("✅ Market order opened: ", id, " lot=", lot);
               WriteUpdate(id, "open");
            } else {
               Print("❌ Market order failed: ", id, " error=", res.retcode);
            }
         } else {
            ENUM_ORDER_TYPE orderType = (direction == "Buy") ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
            req.action       = TRADE_ACTION_PENDING;
            req.symbol       = fullSymbol;
            req.type         = orderType;
            req.volume       = lot;
            req.price        = NormalizeDouble(entry, digits);
            req.sl           = NormalizeDouble(sl, digits);
            req.tp           = NormalizeDouble(tp, digits);
            req.comment      = id;
            req.type_filling = GetFillingMode(fullSymbol);
            req.type_time    = ORDER_TIME_GTC;
            
            if (OrderSend(req, res)) {
               Print("✅ Pending order placed: ", id, " lot=", lot);
               WriteUpdate(id, "placed");
            } else {
               Print("❌ Pending order failed: ", id, " error=", res.retcode);
            }
         }
      }

      if (status == "placed") {
         bool isPending = false, isOpen = false;
         for (int i = OrdersTotal() - 1; i >= 0; i--)
            if (OrderGetTicket(i) > 0 && OrderGetString(ORDER_COMMENT) == id) { isPending = true; break; }
         for (int i = PositionsTotal() - 1; i >= 0; i--)
            if (PositionGetTicket(i) > 0 && PositionGetString(POSITION_COMMENT) == id) { isOpen = true; break; }
         if (!isPending && isOpen) { 
            WriteUpdate(id, "open"); 
            Print("🟢 Activated: ", id); 
         }
      }

      if (status == "open") {
         bool stillOpen = false;
         for (int i = PositionsTotal() - 1; i >= 0; i--)
            if (PositionGetTicket(i) > 0 && PositionGetString(POSITION_COMMENT) == id) { stillOpen = true; break; }
         
         if (!stillOpen) {
            HistorySelect(0, TimeCurrent());
            string closeReason = "SL";
            for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {
               ulong dTicket = HistoryDealGetTicket(i);
               if (HistoryDealGetString(dTicket, DEAL_COMMENT) == id) {
                  ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dTicket, DEAL_REASON);
                  if (reason == DEAL_REASON_TP) closeReason = "TP";
                  break;
               }
            }
            WriteUpdate(id, closeReason);
            Print("🔔 Closed: ", id, " reason=", closeReason);
         }
      }
   }
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| پایان کار Expert Advisor                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   EventKillTimer(); 
   Print("Expert Advisor stopped");
}
