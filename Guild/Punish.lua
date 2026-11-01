-- What the prisoner's own addon checks (SPEC §6), and what other members' addons draw:
-- * The Stocks: the time counts only while the prisoner stands within NEAR yards of the stocks (the Guild Master's
--   spot, else where the sentencer stood). Reported to the guild every REPORT seconds and when served.
-- * The Radio: a jingle every RADIO_EVERY seconds on the prisoner's screen.
-- * Community service: fish caught (the loot window says it is fishing loot), reported every few.
-- * Walk of shame: each zone on the route, in order, reached with no gear on.
-- * Tribute: the Guild Master's addon sees what a prisoner who owes tribute hands over by trade.
-- * The chat filter: tags ([Crown], [In the Stocks], [Dunce]) and curses on guild chat, on members' own screens.
--   The player never says anything they did not type: only how it looks to others changes.
local _, ns = ...
local L, D = ns.L, ns.GuildData
local P, St = ns.Players, ns.Stocks

local Pn = { TICK = 5, REPORT = 300, NEAR = 10, RADIO_EVERY = 240, FISH_REPORT = 5, JINGLE = 888 }
ns.Punish = Pn

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- This account's own counts, per guild (they survive a /reload; the guild has the last report).
local function store()
  ns.db.stocks = type(ns.db.stocks) == "table" and ns.db.stocks or {}
  local gid = D:Id() or "?"
  if type(ns.db.stocks[gid]) ~= "table" then ns.db.stocks[gid] = {} end
  local s = ns.db.stocks[gid]
  for _, k in ipairs({ "s", "sent", "n", "i" }) do if type(s[k]) ~= "table" then s[k] = {} end end
  return s
end

local function mine(g)
  if not g then return {} end
  return St.Of(g, P:Of(ns.Self(), g))
end

-- Where the stocks stand for a sentence, or nil when nobody knows.
function Pn.Spot(s) return D:Settings().spot or s.se.sp end

-- This character's place: x, y, instance and zone; nil where the game does not tell (instances, secret values).
function Pn.Here()
  if not UnitPosition then return nil end
  local y, x, _, inst = UnitPosition("player")
  if x == nil or secret(x) or secret(y) or secret(inst) then return nil end
  local zone = GetSubZoneText and GetSubZoneText() or nil
  if not zone or zone == "" or secret(zone) then zone = GetRealZoneText and GetRealZoneText() or nil end
  return { x = x, y = y, i = inst, z = type(zone) == "string" and not secret(zone) and zone or nil }
end

-- Yards from the stocks (nil: another continent, or unknown).
function Pn.Distance(spot)
  local here = Pn.Here()
  if not spot or not here or here.i ~= spot.i then return nil end
  return math.sqrt((here.x - spot.x) ^ 2 + (here.y - spot.y) ^ 2)
end

-- Is this character wearing nothing (the Walk of shame)? Shirt and tabard may stay.
Pn.GEAR = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }
function Pn.Naked()
  if not GetInventoryItemLink then return false end
  for _, slot in ipairs(Pn.GEAR) do if GetInventoryItemLink("player", slot) then return false end end
  return true
end

---------------------------------------------------------------------------
-- The prisoner's clock
---------------------------------------------------------------------------
function Pn:Tick()
  local g = D:Current()
  local now = GetTime()
  local st = store()
  self.at = nil
  for _, s in ipairs(mine(g)) do
    if s.st == "active" and s.pun == "stocks" then
      local spot = Pn.Spot(s)
      local dist = spot and Pn.Distance(spot)
      local at = not spot or (dist ~= nil and dist <= Pn.NEAR)
      self.at = at
      if at then
        local total = (s.se.len or 0) * 60
        st.s[s.id] = math.min(total, math.max(st.s[s.id] or 0, s.served or 0) + Pn.TICK)
        if st.s[s.id] - (st.sent[s.id] or 0) >= Pn.REPORT or st.s[s.id] >= total then
          st.sent[s.id] = st.s[s.id]
          ns.Sync:Do({ k = "stk", id = s.id, s = st.s[s.id] })
          if st.s[s.id] >= total then ns:Print(L.ST_SERVED, true) end
        end
        ns:Fire("STOCKS")
      end
    elseif s.st == "active" and s.pun == "radio" then
      self.radio = self.radio or {}
      if not self.radio[s.id] or now - self.radio[s.id] >= Pn.RADIO_EVERY then
        self.radio[s.id] = now
        if PlaySound then PlaySound(Pn.JINGLE) end
        ns:Print(L.ST_RADIO_PLAYS, true)
      end
    end
  end
end

-- What this character has served at the stocks (ours: may be ahead of the last report).
function Pn.Served(s) return math.max(store().s[s.id] or 0, s.served or 0) end

-- A fish caught counts for Community service.
ns:RegisterEvent("LOOT_OPENED", function()
  if not IsFishingLoot or not IsFishingLoot() then return end
  local st = store()
  for _, s in ipairs(mine(D:Current())) do
    if s.st == "active" and s.pun == "service" then
      local n = math.max(st.n[s.id] or 0, s.n or 0) + 1
      st.n[s.id] = n
      if n % Pn.FISH_REPORT == 0 or n >= (s.se.q or St.QUOTA) then ns.Sync:Do({ k = "stk", id = s.id, n = n }) end
      ns:Fire("STOCKS")
    end
  end
end)

-- A zone on the Walk of shame's route, reached in order, with no gear on.
function Pn.Zone()
  local here = {}
  for _, fn in ipairs({ GetSubZoneText, GetRealZoneText, GetZoneText }) do
    local z = fn and fn()
    if type(z) == "string" and z ~= "" and not secret(z) then here[strtrim(z):lower()] = true end
  end
  local st = store()
  for _, s in ipairs(mine(D:Current())) do
    if s.st == "active" and s.pun == "walk" then
      local i = math.max(st.i[s.id] or 0, s.i or 0) + 1
      local want = s.se.z and s.se.z[i]
      if want and here[strtrim(want):lower()] then
        if Pn.Naked() then
          st.i[s.id] = i
          ns.Sync:Do({ k = "stk", id = s.id, i = i })
          ns:Print(L.ST_WALK_REACHED:format(want, i, #s.se.z), true)
        else
          ns:Print(L.ST_WALK_GEAR, true)
        end
      end
    end
  end
end
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do ns:RegisterEvent(e, Pn.Zone) end

-- The Guild Master sees what a prisoner who owes tribute handed over (Guild/Payments.lua): accept or scorn it.
ns:On("TRADE_DONE", function(t)
  local g = D:Current()
  if not g or not t or ns.Roster:Rank(ns.Self()) ~= 0 then return end
  local key = P:Of(t.with, g)
  for _, s in ipairs(St.Of(g, key)) do
    if s.st == "tribute" then
      Pn.tribute = { id = s.id, from = t.with, item = t.items and t.items[1] or (t.money and t.money > 0 and ns.Purse:Format(t.money, "gold")) }
      ns:Print(L.ST_TRIBUTE_CAME:format(ns.Display(t.with)), true)
      ns:Fire("STOCKS")
      return
    end
  end
end)

ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Pn.TICK, function() Pn:Tick() end) end
end)

---------------------------------------------------------------------------
-- The chat filter (SPEC §10): tags and curses in guild chat, as this member sees it
---------------------------------------------------------------------------
-- Tags and the curse for a player, worked out once every few seconds.
local cache, cacheAt = {}, 0
-- Anything new (a sentence, a crown, a deposit) shows on the next line, not five seconds later.
local function stale() cacheAt = 0 end
ns:On("OP", stale)
ns:On("GUILD_DATA", stale)
function Pn.Look(g, key)
  local now = GetTime()
  if now - cacheAt > 5 or cache.g ~= g then
    cache, cacheAt = { g = g }, now
    -- This month's Patron (Guild/Treasury.lua): worked out once per cache.
    cache.patron = ns.Treasury and ns.Treasury.Patron(g) or false
  end
  if cache[key] then return cache[key] end
  local tags, curse = {}, nil
  local crown = ns.Crown.State(g)
  if crown.holder == key then tags[#tags + 1] = L.TAG_CROWN end
  for _, s in ipairs(St.Of(g, key)) do
    if s.st == "active" and s.pun == "stocks" then tags[#tags + 1] = L.TAG_STOCKS end
    if s.st == "active" and s.pun == "curse" then curse = s.se.c end
  end
  if St.Dunce(g) == key then tags[#tags + 1] = L.TAG_DUNCE end
  if cache.patron == key then tags[#tags + 1] = L.TAG_PATRON end
  cache[key] = { tags = tags, curse = curse }
  return cache[key]
end

local MRGL = { "Mrgl", "mrrgl", "Mglrmgl", "mrrrglrgl", "Mrlgrl" }
function Pn.Curse(kind, msg)
  if kind == "praise" then return msg .. L.CURSE_PRAISE end
  local i = 0
  return (msg:gsub("%a+", function()
    i = i + 1
    return MRGL[(i - 1) % #MRGL + 1]
  end))
end

function Pn.Filter(_, _, msg, sender, ...)
  if type(msg) ~= "string" or type(sender) ~= "string" or secret(msg) or secret(sender) then return false end
  local g = D:Current()
  if not g then return false end
  local look = Pn.Look(g, P:Of(ns.FullName(sender), g))
  if #look.tags == 0 and not look.curse then return false end
  local text = look.curse and Pn.Curse(look.curse, msg) or msg
  if #look.tags > 0 then text = table.concat(look.tags, " ") .. " " .. text end
  return false, text, sender, ...
end

local addFilter = ChatFrame_AddMessageEventFilter
  or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter and not ns.off then addFilter("CHAT_MSG_GUILD", Pn.Filter) end
