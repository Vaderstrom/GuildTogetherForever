-- Gold that reaches this character (SPEC §4): Guild Together never moves gold itself; the receiver's addon sees it
-- arrive and marks debts paid (Guild/Purse.lua, Arrived).
-- * Trade: the partner and the gold they put in are noted while the trade window is open; "Trade complete" pays.
-- * Mail: gold taken from a letter (TakeInboxMoney, AutoLootMailItem, observed with hooksecurefunc) pays, read from
--   the letter before the game removes it. Cash on delivery and returned letters do not count.
local _, ns = ...
local Pu = ns.Purse
local Pay = {}
ns.Payments = Pay

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

---------------------------------------------------------------------------
-- Trade
---------------------------------------------------------------------------
local function tradeMoney()
  local m = GetTargetTradeMoney and GetTargetTradeMoney()
  if secret(m) then return nil end
  return tonumber(m)
end

ns:RegisterEvent("TRADE_SHOW", function()
  local name, realm = UnitName("NPC")
  if secret(name) or type(name) ~= "string" then Pay.trade = nil return end
  if type(realm) == "string" and realm ~= "" and not secret(realm) then name = name .. "-" .. realm end
  Pay.trade = { with = ns.FullName(name), money = 0 }
end)

-- What the partner puts in: the gold, and the names of the items (a tribute to the Guild Master, SPEC §6).
local function note()
  local t = Pay.trade
  if not t then return end
  t.money = tradeMoney() or t.money
  if GetTradeTargetItemInfo then
    t.items = {}
    for slot = 1, 6 do
      local item = GetTradeTargetItemInfo(slot)
      if type(item) == "string" and not secret(item) then t.items[#t.items + 1] = item end
    end
  end
end
ns:RegisterEvent("TRADE_MONEY_CHANGED", note)
ns:RegisterEvent("TRADE_TARGET_ITEM_CHANGED", note)
ns:RegisterEvent("TRADE_ACCEPT_UPDATE", note)

ns:RegisterEvent("UI_INFO_MESSAGE", function(_, _, msg)
  if secret(msg) or msg ~= ERR_TRADE_COMPLETE then return end
  local t = Pay.trade
  Pay.trade = nil
  if t then ns:Fire("TRADE_DONE", t) end
  if t and t.money and t.money > 0 then Pu:Arrived(t.with, t.money, "trade") end
end)

ns:RegisterEvent("TRADE_REQUEST_CANCEL", function() Pay.trade = nil end)

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
local function letter(i)
  if not GetInboxHeaderInfo then return end
  local _, _, sender, _, money, cod, _, _, _, returned = GetInboxHeaderInfo(i)
  if secret(sender) or secret(money) or type(sender) ~= "string" then return end
  money, cod = tonumber(money) or 0, tonumber(cod) or 0
  if money > 0 and cod == 0 and not returned then Pu:Arrived(ns.FullName(sender), money, "mail") end
end

-- Hooks are set once the game's mail functions exist (they always do in the game; the tests add them).
local hooked = false
local function hook()
  if hooked or not hooksecurefunc then return end
  hooked = true
  if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", letter) end
  if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", letter) end
end
ns:On("LOGIN", hook)

---------------------------------------------------------------------------
-- Paying
---------------------------------------------------------------------------
-- Opens a trade with the player when one of their characters is the target (the game needs them near).
function Pay:Trade(key)
  local target = UnitName("target")
  if type(target) == "string" and not secret(target) then
    local tname, trealm = UnitName("target")
    local full = ns.FullName((type(trealm) == "string" and trealm ~= "") and (tname .. "-" .. trealm) or tname)
    for _, name in ipairs(ns.Players:Chars(key)) do
      if name == full and InitiateTrade then
        InitiateTrade("target")
        return true
      end
    end
  end
  ns:Print(ns.L.PAY_TARGET:format(ns.Players:Name(key)), true)
  return false
end
