#property strict

input string CSV_FILE     = "signals.csv";
input string UPDATE_FILE  = "mt5_updates.txt";
input double DEFAULT_LOT  = 0.01;

//--- Trailing stop parameters
input bool   ENABLE_TRAILING      = true;   // Enable trailing stop
input double PROFIT_TRIGGER_PIPS  = 50.0;   // Profit pips to trigger trailing
input double TRAILING_DISTANCE_PIPS = 30.0; // SL distance from entry (pips)

//--- Write status update to file
void WriteUpdate(string id, string status) {
   int handle = FileOpen(UPDATE_FILE, FILE_WRITE | FILE_READ | FILE_ANSI | FILE_TXT);
   if (handle == INVALID_HANDLE) return;
   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, id + "," + status + "\n");
   FileClose(handle);
}

//--- Check if order with this comment (id) exists
bool OrderExistsWithComment(string comment) {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderGetTicket(i) > 0) {
         if (OrderGetString(ORDER_COMMENT) == comment) return true;
      }
   }
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (PositionGetTicket(i) > 0) {
         if (PositionGetString(POSITION_COMMENT) == comment) return true;
      }
   }
   return false;
}

//--- Calculate pip size
double GetPipSize(string symbol) {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? 0.0001 : 0.01;
}

//--- Trailing stop for open positions
void ManageTrailingStop() {
   if (!ENABLE_TRAILING) return;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      string symbol       = PositionGetString(POSITION_SYMBOL);
      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL    = PositionGetDouble(POSITION_SL);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double pipSize = GetPipSize(symbol);
      double profitPips = 0;

      if (type == POSITION_TYPE_BUY) {
         profitPips = (currentPrice - openPrice) / pipSize;
      } else {
         profitPips = (openPrice - currentPrice) / pipSize;
      }

      // If profit reached trigger level
      if (profitPips >= PROFIT_TRIGGER_PIPS) {
         double newSL = 0;

         if (type == POSITION_TYPE_BUY) {
            newSL = openPrice + (TRAILING_DISTANCE_PIPS * pipSize);
            // Only if new SL is higher than current SL
            if (newSL > currentSL || currentSL == 0) {
               ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         } else {
            newSL = openPrice - (TRAILING_DISTANCE_PIPS * pipSize);
            // Only if new SL is lower than current SL
            if (newSL < currentSL || currentSL == 0) {
               ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}

//--- Modify position SL/TP
void ModifyPosition(ulong ticket, double sl, double tp) {
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl       = NormalizeDouble(sl, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
   req.tp       = tp;

   if (OrderSend(req, res)) {
      Print("✅ Trailing SL updated: ticket=", ticket, " new SL=", sl);
   } else {
      Print("❌ Modify failed: ticket=", ticket, " error=", res.retcode);
   }
}

int OnInit() {
   EventSetTimer(30);
   return INIT_SUCCEEDED;
}

void OnTimer() {
   // Manage trailing stop
   ManageTrailingStop();

   int handle = FileOpen(CSV_FILE, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if (handle == INVALID_HANDLE) {
      Print("❌ Cannot open ", CSV_FILE);
      return;
   }

   // Skip header
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);
   FileReadString(handle);

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

      //--- Place new order
      if (status == "waiting to open" && !OrderExistsWithComment(id)) {
         ENUM_ORDER_TYPE orderType = (direction == "Buy")
            ? ORDER_TYPE_BUY_LIMIT
            : ORDER_TYPE_SELL_LIMIT;

         MqlTradeRequest req = {};
         MqlTradeResult  res = {};

         req.action  = TRADE_ACTION_PENDING;
         req.symbol  = symbol;
         req.type    = orderType;
         req.volume  = volume > 0 ? volume : DEFAULT_LOT;
         req.price   = entry;
         req.sl      = sl;
         req.tp      = tp;
         req.comment = id;

         if (OrderSend(req, res)) {
            Print("✅ Order placed: ", id, " ticket=", res.order);
            WriteUpdate(id, "open");
         } else {
            Print("❌ Order failed: ", id, " error=", res.retcode);
         }
      }

      //--- Check if position closed
      if (status == "open") {
         bool stillOpen = false;
         for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (PositionGetTicket(i) > 0) {
               if (PositionGetString(POSITION_COMMENT) == id) {
                  stillOpen = true;
                  break;
               }
            }
         }

         if (!stillOpen) {
            HistorySelect(0, TimeCurrent());
            string closeReason = "forced close";

            for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {
               ulong ticket = HistoryDealGetTicket(i);
               if (HistoryDealGetString(ticket, DEAL_COMMENT) == id) {
                  ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
                  if (reason == DEAL_REASON_SL) closeReason = "SL";
                  else if (reason == DEAL_REASON_TP) closeReason = "TP";
                  break;
               }
            }

            WriteUpdate(id, closeReason);
            Print("🔔 Position closed: ", id, " reason=", closeReason);
         }
      }
   }

   FileClose(handle);
}

void OnDeinit(const int reason) {
   EventKillTimer();
}
