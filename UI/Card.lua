-- The player card, your options and the game's right-click menu (SPEC decision 52).
--   The player card: one player (main and alts): the ladder and the crown, duels between you, debts between you,
--     sentences, deeds and professions, with Challenge to a duel and Deathroll. It opens in the panel's right
--     column (UI/Side.lua, Side:Over), over what the page offers, until closed or a row is picked.
--   Your options: each member's own choices: alerts, emotes, sounds, chat lines and Dress the guild window. A feature
--     of Home (SPEC decision 57).
--   The right-click menu on a guildmate (the guild window's list, a name in chat, a target): Challenge to a duel,
--     Deathroll and Player card. Menu.ModifyMenu only adds our own buttons to the game's menu; nothing of the game's is
--     changed, so its own buttons (a guild note, promote) keep working.
local _, ns = ...
local L, UI, D, Hall, Side = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Side
local P, R, Comm, Pu = ns.Players, ns.Roster, ns.Comm, ns.Purse
local Du, Cr, St, Ch, Pr = ns.Duels, ns.Crown, ns.Stocks, ns.Chronicle, ns.Professions

local Card = {}
ns.Card = Card

-- The menus of a player the game shows (Blizzard's unit menus, "MENU_UNIT_" .. which).
Card.MENUS = { "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER",
  "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }
Card.DEEDS_SHOWN = 3

-- A character of the player who can take a challenge now: online, with the addon, not me (their main first).
function Card.Reachable(key, g)
  for _, c in ipairs(P:Chars(key, g)) do
    if c ~= ns.Self() and R:Online(c) and Comm.heard[c] then return c end
  end
end

-- Duels between two players: wins of a over b, wins of b over a.
local function between(g, a, b)
  local won, lost = 0, 0
  for _, e in pairs(g and g.duels or {}) do
    local w, l = P:Of(e.w, g), P:Of(e.l, g)
    if w == a and l == b then won = won + 1 elseif w == b and l == a then lost = lost + 1 end
  end
  return won, lost
end

-- Goes to a feature in the window, then does fn (with the page) once it shows.
local function go(pid, fid, fn)
  local function show()
    Hall:ShowFeature(pid, fid)
    local def = Hall.pages[pid]
    if fn and def and Hall.current == pid then fn(def.frame) end
  end
  Hall:Go(show)
end

local function duel(char)
  if not Du:Challenge(char) then return end
  ns:Print(L.CARD_DUEL_SENT:format(ns.Display(char)), true)
  go("arena", "duels")
end

local function deathroll(char)
  go("tavern", "deathroll", function(page)
    if ns.Deathroll:Game() then return end
    page.drFilled, page.drStartTouched = nil, nil
    page.View({ kind = "challenge", key = char })
  end)
end

---------------------------------------------------------------------------
-- The player card
---------------------------------------------------------------------------
local function draw(f, key)
  local g, now = D:Current(), time()
  local me = P:Of(ns.Self(), g)
  local mine = key == me
  -- The characters: the main first, online ones say so.
  local names, main = {}, P:Main(key, g)
  local chars = P:Chars(key, g)
  table.sort(chars, function(a, b) if (a == main) ~= (b == main) then return a == main end return a < b end)
  for _, c in ipairs(chars) do
    names[#names + 1] = UI.Who(c) .. (R:Online(c) and (" |cff40c040" .. L.CARD_ONLINE .. "|r") or "")
  end
  f:Strip("charsHead", #chars == 1 and L.CARD_CHAR or L.CARD_CHARS:format(#chars))
  f:Text("chars", table.concat(names, ", "))
  -- (SPEC decision 69: others see it, so it is clear why they cannot pick them.)
  if ns.Rules.OptedOut(g, key) then f:Text("optedOut", L.CARD_OPTED_OUT, "GameFontNormal") end
  -- The ladder, the crown, and the duels between you.
  if D:PlaceOn("challenges") then
    f:Strip("duelHead", L.CARD_DUELS)
    local place, e
    local season = Du.Now(g, now)
    for i, x in ipairs(Du.Ladder(g, season.from, season.to)) do if x.key == key then place, e = i, x end end
    if e then
      f:Pair("ladder", L.CARD_LADDER, L.CARD_PLACE:format(place, e.r))
      f:Pair("record", L.AR_RECORD, L.AR_LADDER_WL:format(e.w, e.l))
    else
      f:Pair("ladder", L.CARD_LADDER, L.CARD_UNRATED)
    end
    local s = Cr.State(g, now)
    local reigns = s.holder == key and 1 or 0
    for _, x in ipairs(s.reigns) do if x.key == key then reigns = reigns + 1 end end
    local times = reigns == 1 and L.CARD_CROWN_ONCE or L.CARD_CROWN_TIMES:format(reigns)
    f:Pair("crown", L.CARD_CROWN, s.holder == key and L.CARD_CROWN_NOW or (reigns > 0 and times
      or L.CARD_NEVER))
    if not mine then
      local won, lost = between(g, key, me)
      f:Pair("vs", L.CARD_VS_YOU, (won + lost) > 0 and L.CARD_VS:format(lost, won) or L.CARD_NEVER)
    end
  end
  -- Debts between you.
  if not mine then
    local lines = {}
    for _, d in ipairs(Pu:Open(g)) do
      if d.f == key and d.to == me then lines[#lines + 1] = L.CARD_OWES_YOU:format(UI.Money(d.amt, "gold"))
      elseif d.f == me and d.to == key then lines[#lines + 1] = L.CARD_YOU_OWE:format(UI.Money(d.amt, "gold")) end
    end
    if #lines > 0 then
      f:Strip("debtHead", L.CARD_DEBTS)
      for i, line in ipairs(lines) do f:Text("debt" .. i, line) end
    end
  end
  -- The sentences running.
  if D:PlaceOn("punishments") then
    local running = St.Of(g, key, now)
    if #running > 0 then f:Strip("punHead", L.PLACE_PUNISHMENTS) end
    for i, s in ipairs(running) do
      f:Row("se" .. i, { icon = UI.ICON["p_" .. s.pun] or UI.ICON.shackles, name = L["ACT_" .. s.pun:upper()] or s.pun,
        sub = s.se.why, dim = true })
    end
  end
  -- Deeds: how many, and the latest.
  local deeds = {}
  for _, d in ipairs(Ch.Deeds(g, now)) do if d.key == key then deeds[#deeds + 1] = d end end
  if #deeds > 0 then
    f:Strip("deedHead", L.CARD_DEEDS:format(#deeds))
    for i = 1, math.min(Card.DEEDS_SHOWN, #deeds) do
      f:Text("deed" .. i, deeds[i].text .. " |cff9d9d9d· " .. ns.TimeAgo(deeds[i].t) .. "|r")
    end
  end
  -- Professions, as fresh as the player's last share.
  if D:PlaceOn("professions") then
    local list, t = {}, nil
    for _, b in ipairs(Pr.Crafters(g)) do
      for _, c in ipairs(b.list) do
        if c.key == key then
          list[#list + 1] = { b = b, c = c }
          t = math.max(t or 0, c.t or 0)
        end
      end
    end
    if #list > 0 then
      f:Strip("profHead", L.CARD_PROFESSIONS, t and t > 0 and L.PR_AS_OF:format(ns.TimeAgo(t)) or nil)
      for i, x in ipairs(list) do
        f:Row("prof" .. i, { icon = x.b.i or UI.ICON.anvil, name = x.b.n, value = ("%d/%d"):format(x.c.r, x.c.m) })
      end
    end
  end
  if mine then return {} end
  -- Duel and Deathroll, for a player online with the addon.
  local char = Card.Reachable(key, g)
  if not char then
    f:Text("away", L.AR_NOT_HERE, "GameFontDisableSmall")
    return {}
  end
  local acts = {}
  if D:PlaceOn("challenges") and not Du:Busy() then acts[#acts + 1] = { L.AR_CHALLENGE, function() duel(char) end } end
  if D:PlaceOn("gambling") and D:On("tavern:deathroll") and not ns.Deathroll:Game() then
    acts[#acts + 1] = { L.TV_DEATHROLL, function() deathroll(char) end }
  end
  return acts
end

-- The card of the player a character belongs to, in the panel's right column.
function Card:Show(name)
  local g = D:Current()
  local key = name and P:Of(name, g)
  if not key then return end
  Side:Over(function()
    local online = Card.Reachable(key, D:Current())
    return { key = "card:" .. key, player = online or P:Name(key), title = P:Name(key), flow = "card",
      sub = P:IsMe(key) and L.CARD_YOU or (online and L.CARD_ONLINE_AS:format(ns.Display(online)) or L.CARD_OFFLINE),
      draw = function(f) return draw(f, key) end }
  end)
end

---------------------------------------------------------------------------
-- Your options
---------------------------------------------------------------------------
local S = ns.Settings
local CHAT = { "all", "important", "off" }

local function options(f)
  ns.Welcomed("options")
  -- Getting started: the tour again (SPEC decision 72).
  f:Buttons("tourAgain", { { L.TOUR_AGAIN, function() ns.Tour:Start() end } }, L.TOUR_AGAIN_SUB)
  f:Strip("seeHead", L.OPT_SEE)
  for _, k in ipairs({ "alerts", "emotes", "sounds" }) do
    f:Check(k, L["OPT_" .. k:upper()], function() return S:Get(k) ~= false end, function(on)
      S:Set(k, on)
      Hall:Refresh()
    end)
  end
  local list = {}
  for _, k in ipairs(CHAT) do list[#list + 1] = { k, L["OPT_CHAT_" .. k:upper()] } end
  f:Dropdown("chat", L.OPT_CHAT, list, S:Get("chat") or "all", function(v) S:Set("chat", v) Hall:Refresh() end, 200)
  -- The alert line when Guild Together is not open: its scene, where it shows and how big (asked for on 1 Nov 2026).
  local Al = ns.Alerts
  f:Check("alertScenes", L.OPT_ALERT_SCENES, function() return S:Get("alertScenes") ~= false end, function(on)
    S:Set("alertScenes", on)
    Hall:Refresh()
  end)
  local spots, sizes = {}, {}
  for _, k in ipairs(Al.SPOTS) do spots[#spots + 1] = { k, L["OPT_SPOT_" .. k:upper()] } end
  for _, k in ipairs(Al.SIZE_ORDER) do sizes[#sizes + 1] = { k, L["OPT_SIZE_" .. k:upper()] } end
  f:Dropdown("alertSpot", L.OPT_ALERT_SPOT, spots, S:Get("alertSpot") or "top", function(v)
    S:Set("alertSpot", v)
    Al:Place()
    Hall:Refresh()
  end, 200)
  f:Dropdown("alertSize", L.OPT_ALERT_SIZE, sizes, S:Get("alertSize") or "normal", function(v)
    S:Set("alertSize", v)
    Al:Place()
    Hall:Refresh()
  end, 200)
  f:Buttons("alertTry", { { L.OPT_ALERT_TRY, function()
    local me = ns.Self()
    local dr = { id = "try", opp = me, st = "playing", s = 100, rolls = { { who = "me", v = 42 } } }
    Al:Push({ text = L.OPT_ALERT_TRY_TEXT, sub = L.OPT_ALERT_TRY_SUB, test = true, now = true, quiet = true,
      scene = { page = "options", draw = function(fl) ns.Scenes.Deathroll(fl, dr) end } })
  end } })
  -- The guild window's dressing (SPEC decisions 58 and 59): for the account, after a reload.
  local Fr = ns.Frame
  -- Opting out of punishments (SPEC decision 69): asked first, saying what it closes; back in, a wait of 7 days.
  local Ru, gg = ns.Rules, D:Current()
  local setup = gg and Ru.Setup(gg)
  if gg and (setup == nil or setup == "free") then
    f:Strip("punHead", L.OPT_PUN_HEAD)
    f:Text("optOutNone", L.OPT_OUT_NONE, "GameFontDisableSmall")
  elseif gg then
    f:Strip("punHead", L.OPT_PUN_HEAD)
    f:Check("optOut", L.OPT_OUT, function() return Ru.OptedOut(gg, ns.Players:Of(ns.Self(), gg)) end, function(on)
      local key = ns.Players:Of(ns.Self(), gg)
      if not on then Ru.SetOptOut(false) Hall:Refresh() return end
      local wait = Ru.WaitUntil(gg, key)
      if wait then ns:Print(L.OPT_OUT_WAIT:format(date(L.GM_DATE, wait)), true) Hall:Refresh() return end
      local text = Ru.Text(gg)
      Hall:Confirm(L.OPT_OUT_ASK:format(text.closes), L.OPT_OUT_YES, function() Ru.SetOptOut(true) Hall:Refresh() end)
      Hall:Refresh()
    end)
    f:Text("optOutNote", L.OPT_OUT_NOTE, "GameFontDisableSmall")
  end
  f:Strip("dressHead", L.OPT_DRESS_HEAD)
  f:Check("dress", L.OPT_DRESS, function() return Fr:WantDressed() end, function(on)
    Fr:SetDressed(on)
    Hall:Refresh()
  end)
  if Fr:WantDressed() ~= Fr:Dressed() then f:Buttons("reload", { { L.OPT_RELOAD, function() ReloadUI() end } }) end
  -- Moved by dragging its name (SPEC decision 62): one button puts it back.
  if Fr:Dressed() and Fr:Moved() then
    f:Buttons("center", { { L.OPT_CENTER, function() Fr:Center() Hall:Refresh() end } })
  end
  f:Text("dressNote", L.OPT_DRESS_NOTE, "GameFontDisableSmall")
  f:Space()
  f:Text("note", L.OPT_NOTE, "GameFontDisableSmall")
  return {}
end

-- Your options, drawn in Home's list.
Card.DrawOptions = options

-- Opens your options: Home's feature.
function Card:Options()
  Hall:ShowFeature("home", "options")
end

---------------------------------------------------------------------------
-- The right-click menu
---------------------------------------------------------------------------
-- The character a menu is about (with the realm), when it is a guildmate other than me.
function Card.MenuName(context)
  if type(context) ~= "table" then return nil end
  local name = context.name
  if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
  local server = context.server
  if type(server) == "string" and server ~= "" and not name:find("-", 1, true)
    and not (issecretvalue and issecretvalue(server)) then
    name = name .. "-" .. server
  end
  local full = ns.FullName(name)
  if not full or full == ns.Self() or R:Rank(full) == nil then return nil end
  return full
end

function Card.Fill(root, context)
  if not D:Current() then return end
  local name = Card.MenuName(context)
  if not name then return end
  local key = P:Of(name)
  local reach = Card.Reachable(key) == name
  root:CreateDivider()
  root:CreateTitle(ns.Guild() or L.ADDON_NAME)
  if D:PlaceOn("challenges") then
    local b = root:CreateButton(L.AR_CHALLENGE, function() duel(name) end)
    if b and b.SetEnabled then b:SetEnabled(reach and not Du:Busy()) end
  end
  if D:PlaceOn("gambling") and D:On("tavern:deathroll") then
    local b = root:CreateButton(L.CARD_MENU_DEATHROLL, function() deathroll(name) end)
    if b and b.SetEnabled then b:SetEnabled(reach and not ns.Deathroll:Game()) end
  end
  root:CreateButton(L.CARD_MENU, function() Hall:Go(function() Card:Show(name) end) end)
end

-- Once, at login: our buttons in each of the game's player menus.
ns:On("LOGIN", function()
  if Card.hooked or not (Menu and Menu.ModifyMenu) then return end
  Card.hooked = true
  for _, tag in ipairs(Card.MENUS) do
    Menu.ModifyMenu(tag, function(_, root, context)
      local ok, err = pcall(Card.Fill, root, context)
      if not ok then ns:LogError("menu", tag, tostring(err)) end
    end)
  end
end)
