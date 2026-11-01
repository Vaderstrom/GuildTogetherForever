-- The duels (SPEC §5, decision 48), in Challenges. Three features: Duels and the crown (Guild/Duels.lua,
-- Guild/Crown.lua: what waits for you first (the challenge in hand, the crown and its challenges, bets on the duels
-- being fought now), then the ladder), the tournament (Guild/Cup.lua) and Assassins (Guild/Assassins.lua). A player
-- from the ladder and a new tournament open beside the window.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local R, Comm, P = ns.Roster, ns.Comm, ns.Players
local Du, Cr, As, Cu = ns.Duels, ns.Crown, ns.Assassins, ns.Cup

local LADDER_SHOWN, FACES_SHOWN, MATCHES_SHOWN = 30, 8, 8
local function money(amt, purse) return Pu:Format(Pu.Units(amt, purse), purse) end
local function unit(purse) return purse == "gold" and L.UNIT_GOLD or D:Settings().many end
local function num(box) return tonumber(strtrim(box:GetText() or "")) end
local function who(key)
  local main = P:Main(key)
  return main and UI.Who(main) or P:Name(key)
end

-- "4 days", "1 day", "5 hours", "under an hour".
local function span(sec)
  if sec >= 2 * 86400 then return L.AR_DAYS:format(math.floor(sec / 86400)) end
  if sec >= 86400 then return L.AR_DAY end
  if sec >= 3600 then return L.AR_HOURS:format(math.floor(sec / 3600)) end
  return L.AR_UNDER_HOUR
end

-- Online members heard from this session (they have the addon), in name order.
local function here()
  local list, me = {}, ns.Self()
  for name in pairs(Comm.heard) do
    if name ~= me and R:Online(name) and R:Rank(name) ~= nil then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- An online character of a player, to challenge (their main first).
local function onlineChar(key, g)
  for _, c in ipairs(P:Chars(key, g)) do if c ~= ns.Self() and R:Online(c) and Comm.heard[c] then return c end end
  return nil
end

---------------------------------------------------------------------------
-- Duels and the crown: what waits for you at the top (the challenge in hand, the crown, bets on the duels being
-- fought now), then this season's ladder and who else is online, so nothing you must answer is below a long list
---------------------------------------------------------------------------
local function yourDuel(f)
  local foot = {}
  local ch = Du:Game()
  if ch then
    f:Strip("duel", L.AR_YOUR_DUEL)
    local opp = ns.Display(ch.opp)
    if ch.st == "asked" then
      f:Text("ch", L.AR_DU_ASKED:format(opp))
      foot = { { L.CANCEL, function() Du:CallOff() end } }
    elseif ch.st == "incoming" then
      f:Text("ch", L.AR_DU_INCOMING:format(opp), "GameFontNormal")
      foot = { { L.AR_ACCEPT, function() Du:Accept() end, next = true }, { L.AR_DECLINE, function() Du:CallOff() end } }
    else
      f:Text("ch", L.AR_DU_ON:format(opp), "GameFontNormal")
      foot = { { L.CANCEL, function() Du:CallOff() end } }
    end
  end
  return foot
end

local function ladder(f, page)
  local g = D:Current()
  local ch = Du:Game()
  -- This season's ladder (SPEC decision 52): it starts over each month or season.
  local season = Du.Now(g)
  local list = Du.Ladder(g, season.from, season.to)
  local holder = g and Cr.State(g).holder
  f:Strip("ladder", L.AR_LADDER_OF:format(Du.SeasonName(season)))
  f:Text("ends", L.AR_SEASON_ENDS:format(span(season.to - time())), "GameFontDisableSmall")
  if #list == 0 then f:Empty("empty", L.AR_LADDER_EMPTY, L.AR_LADDER_DO) end
  local rated = {}
  local view = page.view and page.view.kind == "player" and page.view.key
  for i, e in ipairs(list) do
    rated[e.key] = true
    if i <= LADDER_SHOWN then
      local can = not ch and not P:IsMe(e.key) and onlineChar(e.key, g)
      f:Row("r" .. i, { icon = e.key == holder and UI.ICON.crown or UI.ICON.duel, name = i .. ". " .. who(e.key),
        sub = L.AR_LADDER_WL:format(e.w, e.l), value = tostring(e.r), vsub = can and L.AR_DUEL or nil, sel = view == e.key,
        onClick = function() page.View({ kind = "player", key = e.key }) end })
    end
  end
  if not ch then
    local others = {}
    for _, name in ipairs(here()) do if not rated[P:Of(name, g)] then others[#others + 1] = name end end
    if #others > 0 then f:Strip("new", (L.AR_NEW_FACES:gsub(":$", ""))) end
    for i, name in ipairs(others) do
      if i > FACES_SHOWN then break end
      local key = P:Of(name, g)
      f:Row("o" .. i, { icon = UI.ICON.duel, name = UI.Who(name), vsub = L.AR_DUEL, sel = view == key, dim = true,
        onClick = function() page.View({ kind = "player", key = key, char = name }) end })
    end
  end
  return #list > 0 and L.AR_PICK or nil
end

-- A player from the ladder, with Challenge to a duel.
local function playerView(f, page)
  local g, key = D:Current(), page.view.key
  local e, place
  local season = Du.Now(g)
  for i, x in ipairs(Du.Ladder(g, season.from, season.to)) do if x.key == key then e, place = x, i end end
  f:Row("hero", { icon = UI.ICON.duel, name = (place and (place .. ". ") or "") .. who(key), sel = true,
    sub = e and L.AR_LADDER_WL:format(e.w, e.l) or nil, value = e and tostring(e.r) or nil })
  if e then
    f:Pair("rating", L.AR_RATING, tostring(e.r))
    f:Pair("record", L.AR_RECORD, L.AR_LADDER_WL:format(e.w, e.l))
  end
  local acts = {}
  local char = not P:IsMe(key) and (page.view.char or onlineChar(key, g))
  if char and not Du:Game() then
    acts[1] = { L.AR_CHALLENGE, function() Du:Challenge(char) page.View(nil) end }
  elseif not P:IsMe(key) and not char then
    f:Text("away", L.AR_NOT_HERE, "GameFontDisableSmall")
  end
  f:Text("note", L.AR_LADDER_NOTE, "GameFontDisableSmall")
  acts[#acts + 1] = { L.CANCEL, function() page.View(nil) end }
  return acts
end

local function crown(f)
  local g, now = D:Current(), time()
  local s = Cr.State(g, now)
  f:Strip("crown", L.AR_CROWN)
  if not s.holder then
    f:Row("holder", { icon = UI.ICON.crown, name = L.AR_CROWN_FREE, sub = L.AR_CROWN_NOBODY, dim = true,
      tip = { L.AR_CROWN, L.AR_CROWN_NOBODY } })
    return {}
  end
  local best = Cr.Longest(s, now)
  local rule = (best and best.len >= 86400) and L.AR_CROWN_RULE:format(P:Name(best.key), span(best.len))
    or L.AR_CROWN_RULE_SHORT
  f:Row("holder", { icon = UI.ICON.crown, name = who(s.holder), sub = P:IsMe(s.holder) and L.AR_CROWN_YOU or rule,
    value = span(now - s.since), vsub = L.AR_CROWN_HELD, tip = { L.AR_CROWN, rule } })
  if P:IsMe(s.holder) then
    for i, x in ipairs(Cr.Waiting(g, s, now)) do
      f:Text("w" .. i, L.AR_CROWN_FROM:format(UI.Who(x.c), span(x.t + Cr.DAY - now)))
      f:Buttons("wb" .. i, {
        { L.AR_ACCEPT, function() Cr.Accept(x.id) end },
        { L.AR_DECLINE, function()
          if Cr.Costly(g, Cr.State(g), x.id) then
            Hall:Confirm(L.AR_CROWN_DECLINE_COST:format(ns.Display(x.c)), L.AR_DECLINE, function() Cr.Decline(x.id) end)
          else
            Cr.Decline(x.id)
          end
        end },
      })
    end
    for i, x in ipairs(Cr.Accepted(g, s, now)) do f:Text("a" .. i, L.AR_CROWN_FIGHT:format(UI.Who(x.c)), "GameFontNormal") end
    return {}
  end
  local mine, how = Cr.Mine(g, s)
  if how == "waiting" then
    f:Text("mine", L.AR_CROWN_WAITING:format(UI.Who(s.name)))
  elseif how == "accepted" then
    f:Text("mine", L.AR_CROWN_ACCEPTED:format(UI.Who(s.name)), "GameFontNormal")
  elseif not mine then
    return { { L.AR_CROWN_CHALLENGE, function() Cr.Challenge() end } }
  end
  return {}
end

---------------------------------------------------------------------------
-- The tournament, and starting one (for the ranks that may)
---------------------------------------------------------------------------
local function cup(f, page)
  local g, me = D:Current(), ns.Self()
  local c, id = Cu.Current(g)
  local canStart = D:Can("tourney")
  local start = { L.AR_NC_NEW, function() page.View({ kind = "newcup" }) end }
  if not c then
    f:Empty("none", L.AR_CUP_NONE, canStart and L.AR_CUP_NONE_DO:format(UI.Key(L.AR_NC_NEW)) or L.AR_CUP_NONE_ASK)
    return canStart and { start } or {}
  end
  local fee = (c.fee or 0) > 0 and money(c.fee, c.p) or L.AR_FREE
  local about = (c.prize or 0) > 0 and L.AR_CUP_NOTE_PRIZE:format(money(c.prize, c.p), L["AR_FMT_" .. c.fmt], c.bo)
    or L.AR_CUP_NOTE:format(L["AR_FMT_" .. c.fmt], c.bo)
  local pot = Cu.Pot(c)
  local foot = {}
  if c.st == "open" then
    f:Strip("title", L.AR_CUP_OPEN:format(c.name or ""))
    local joined = Cu.Joined(c)
    f:Pair("fee", L.AR_CUP_ENTRY, fee)
    f:Pair("n", L.AR_CUP_ENTRANTS, c.when and L.AR_CUP_CLOSES:format(#joined, c.when) or tostring(#joined))
    f:Pair("pot", L.AR_CUP_POT, money(pot, c.p))
    local cuts = {}
    for i, pct in ipairs(Cu.SHARES) do cuts[i] = Pu:Format(math.floor(Pu.Units(pot, c.p) * pct / 100), c.p) end
    f:Pair("cuts", L.AR_CUP_CUTS, table.concat(cuts, " · "))
    if c.j[me] and c.j[me].on then
      f:Text("signed", L.AR_CUP_SIGNED, "GameFontNormal")
      foot[#foot + 1] = { L.AR_CUP_WITHDRAW, function() Cu.Join(id, false) end }
    else
      foot[#foot + 1] = { (c.fee or 0) > 0 and L.AR_CUP_SIGN:format(fee) or L.AR_CUP_SIGN_FREE, function() Cu.Join(id, true) end }
    end
    if c.h == me then
      foot[#foot + 1] = { L.AR_CUP_GO, function() if not Cu.Go(id) then ns:Print(L.AR_CUP_FEW, true) end end }
      foot[#foot + 1] = { L.AR_CUP_CANCEL, function() Cu.Cancel(id) end }
    end
  elseif c.st == "running" then
    local B, wins = Cu.Build(c)
    local live = Cu.Live(B)
    f:Strip("title", L.AR_CUP_RUN:format(c.name or "", live[1] and live[1].label or ""), money(pot, c.p))
    for i, m in ipairs(live) do
      if i > MATCHES_SHOWN then break end
      local w = wins[m.key] or {}
      local mineNow = m.a == me or m.b == me
      f:Row("m" .. i, { icon = UI.ICON.duel, name = L.AR_VS:format(UI.Who(m.a), UI.Who(m.b)), sel = mineNow,
        sub = mineNow and L.AR_CUP_YOURS:format(ns.Display(m.a == me and m.b or m.a)) or m.label,
        value = (w[m.a] or 0) .. "-" .. (w[m.b] or 0) })
      if c.h == me then
        f:Buttons("wo" .. i, {
          { L.AR_CUP_WO:format(ns.Display(m.a)), function() Cu.Walkover(id, m, m.a) end },
          { L.AR_CUP_WO:format(ns.Display(m.b)), function() Cu.Walkover(id, m, m.b) end },
        })
      end
    end
    if B and B.champion then
      f:Row("champ", { icon = UI.ICON.prize, name = L.AR_CUP_CHAMPION:format(UI.Who(B.champion)) })
      if c.h == me then foot[#foot + 1] = { L.AR_CUP_FINISH, function() Cu.Finish(id) end } end
    elseif c.h == me then
      foot[#foot + 1] = { L.AR_CUP_CANCEL, function() Cu.Cancel(id) end }
    end
  elseif c.st == "done" then
    f:Strip("title", L.AR_CUP_DONE:format(c.name or ""))
    local places = c.places or {}
    for i = 1, 3 do
      local list = places[i]
      if list and #list > 0 then
        local names = {}
        for j, n in ipairs(list) do names[j] = UI.Who(n) end
        f:Row("p" .. i, { icon = i == 1 and UI.ICON.prize or UI.ICON.coins, name = table.concat(names, ", "),
          sub = L["AR_PLACE_" .. i] })
      end
    end
    f:Text("paid", c.p == "gold" and L.AR_CUP_PAID_GOLD or L.AR_CUP_PAID_MARKS, "GameFontDisableSmall")
    if canStart then foot[#foot + 1] = start end
  else
    f:Strip("title", L.AR_CUP_DONE:format(c.name or ""))
    f:Text("off", L.AR_CUP_CANCELLED, "GameFontDisableSmall")
    if canStart then foot[#foot + 1] = start end
  end
  f:Text("about", about, "GameFontDisableSmall")
  return foot
end

local function newCup(f, page)
  if not D:Can("tourney") then return nil end
  local purse = D:Settings().purse
  page.ncFmt, page.ncBo = page.ncFmt or 1, page.ncBo or 2
  f:Strip("title", L.AR_NC)
  local title = f:Field("name", L.AR_NC_NAME, f.width - 10)
  title:SetMaxLetters(Cu.NAME_MAX)
  local third = math.floor((f.width - 16) / 3)
  local fee = f:Field("fee", L.AR_NC_FEE:format(unit(purse)), third - 10, nil, true)
  local prize = f:Field("prize", L.AR_NC_PRIZE, third - 10, third + 8, true)
  local when = f:Field("when", L.AR_NC_WHEN, third - 10, 2 * (third + 8))
  when:SetMaxLetters(Cu.WHEN_MAX)
  if (fee:GetText() or "") == "" then fee:SetText("0") end
  if (prize:GetText() or "") == "" then prize:SetText("0") end
  local half = math.floor((f.width - 8) / 2)
  local fmts, bos = {}, {}
  for i, x in ipairs(Cu.FORMATS) do fmts[i] = { i, L["AR_FMT_" .. x] } end
  for i, n in ipairs(Cu.BO) do bos[i] = { i, L.AR_NC_BO:format(n) } end
  f:Dropdown("fmt", L.AR_NC_KIND, fmts, page.ncFmt, function(v) page.ncFmt = v; Hall:Refresh() end, half - 4, nil, true)
  f:Dropdown("bo", L.AR_NC_MATCH, bos, page.ncBo, function(v) page.ncBo = v; Hall:Refresh() end, half - 4, half + 8)
  f:Text("hint", L.AR_NC_HINT, "GameFontDisableSmall")
  return { { L.AR_NC_START, function()
    local text = ns.Raffle.Clean(title:GetText(), Cu.NAME_MAX)
    local a, b = num(fee), num(prize)
    local ok = text and a and b and (a == 0 or Pu.ValidAmount(a, purse)) and (b == 0 or Pu.ValidAmount(b, purse))
    if not ok or not Cu.Open(text, Cu.FORMATS[page.ncFmt], Cu.BO[page.ncBo], a, b, when:GetText()) then
      ns:Print(L.AR_NC_BAD, true)
      return
    end
    title:SetText("")
    when:SetText("")
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- Assassins
---------------------------------------------------------------------------
local function assassins(f, page)
  local g, me, now = D:Current(), ns.Self(), time()
  local a, id, phase = As.Current(g, now)
  local canHost = D:Can("tourney")
  local foot = {}
  if not a or (phase == "done" and canHost and page.asNew) then
    f:Text("about", L.AR_AS_ABOUT)
    if canHost then
      foot[1] = { L.AR_AS_OPEN, function() page.asNew = nil; As.Open() end }
    else
      f:Empty("none", L.AR_AS_NONE, L.AR_AS_NONE_ASK)
    end
  elseif phase == "signup" then
    local joined = As.Joined(a)
    f:Text("about", L.AR_AS_ABOUT)
    f:Strip("joined", L.AR_AS_SIGNED, tostring(#joined))
    if #joined == 0 then f:Empty("nobody", L.AR_AS_NOBODY, L.AR_AS_NOBODY_DO:format(UI.Key(L.AR_AS_JOIN))) end
    for i, n in ipairs(joined) do f:Row("j" .. i, { icon = UI.ICON.duel, name = UI.Who(n) }) end
    local signed = a.j[me] and a.j[me].on
    foot[1] = signed and { L.AR_AS_LEAVE, function() As.Join(id, false) end } or { L.AR_AS_JOIN, function() As.Join(id, true) end }
    if a.h == me then
      foot[2] = { L.AR_AS_GO, function() if not As.Go(id) then ns:Print(L.AR_AS_MIN:format(As.MIN), true) end end }
    end
  else
    local standing, kills = As.Standing(a)
    local up = {}
    for _, n in ipairs(standing) do up[n] = true end
    local inGame = false
    for _, n in ipairs(a.p) do if n == me then inGame = true end end
    if phase == "running" then
      f:Strip("day", L.AR_AS_DAY:format(As.Day(a, now), a.days))
      f:Text("left", L.AR_AS_RUNNING:format(#standing, #a.p))
      if not inGame then
        f:Text("watch", L.AR_AS_WATCH, "GameFontDisableSmall")
      elseif not up[me] then
        f:Text("out", L.AR_AS_OUT, "GameFontDisableSmall")
      else
        local target = As.Target(id)
        if page.asShow then
          if target then f:Row("target", { icon = UI.ICON.hood, name = L.AR_AS_TARGET:format(UI.Who(target)) })
          else f:Text("target", L.AR_AS_NO_TARGET) end
          foot[1] = { L.AR_AS_HIDE, function() page.asShow = nil; Hall:Refresh() end }
          if not target then foot[2] = { L.AR_AS_ASK, function() As.Ask(id) end } end
        else
          foot[1] = { L.AR_AS_REVEAL, function() page.asShow = true; Hall:Refresh() end }
        end
      end
    else
      if #standing == 1 then
        f:Row("won", { icon = UI.ICON.crown, name = L.AR_AS_WON:format(UI.Who(standing[1])) })
      else
        local names = {}
        for i, n in ipairs(standing) do names[i] = UI.Who(n) end
        f:Text("won", L.AR_AS_SURVIVORS:format(table.concat(names, ", ")))
      end
      local best, most = nil, 0
      for n, k in pairs(kills) do if k > most or (k == most and best and n < best) then best, most = n, k end end
      if best then f:Text("kills", L.AR_AS_KILLS:format(UI.Who(best), most), "GameFontDisableSmall") end
      if canHost then foot[1] = { L.AR_AS_OPEN, function() As.Open() end } end
    end
  end
  f:Text("note", L.AR_AS_NOTE, "GameFontDisableSmall")
  return foot
end

---------------------------------------------------------------------------
-- The bets, under the crown
-- Matches to bet on: accepted ladder duels, accepted crown duels, and live tournament matches.
local function bettable(g)
  local list = {}
  for _, m in ipairs(Du.Matches(g)) do list[#list + 1] = { id = m.id, a = m.a, b = m.b } end
  local s = Cr.State(g)
  if s.holder then
    for _, x in ipairs(Cr.Accepted(g, s)) do list[#list + 1] = { id = x.id, a = s.name, b = x.c, crown = true } end
  end
  local c, cid = Cu.Current(g)
  if c and c.st == "running" then
    for _, m in ipairs(Cu.Live((Cu.Build(c)))) do list[#list + 1] = { id = Cu.MatchId(cid, m.key), a = m.a, b = m.b } end
  end
  return list
end

local function wagers(f)
  local g, me = D:Current(), ns.Self()
  local purse = D:Settings().purse
  local list = g and bettable(g) or {}
  -- Only while there is a duel to bet on: it is now or never.
  if #list == 0 then return end
  f:Strip("bets", L.AR_WAGERS)
  local stake = f:Field("stake", L.AR_WA_STAKE:format(unit(purse)), 80)
  if (stake:GetText() or "") == "" then stake:SetText("5") end
  for i, m in ipairs(list) do
    if i > MATCHES_SHOWN then break end
    local pot = Du.Pot(g, m.id)[purse]
    local total = 0
    for _, v in pairs(pot) do total = total + v end
    local bet = g.bets and g.bets[m.id] and g.bets[m.id][me]
    f:Row("bm" .. i, { icon = m.crown and UI.ICON.crown or UI.ICON.duel, name = L.AR_VS:format(UI.Who(m.a), UI.Who(m.b)),
      sub = bet and L.AR_WA_MINE:format(money(bet.amt, bet.p), ns.Display(bet.on)) or (m.crown and L.AR_WA_CROWN or nil),
      value = purse == "gold" and UI.Money(total, "gold") or Pu:Format(total, purse), vsub = L.AR_CUP_POT })
    -- A bet is made at the duel, face to face (SPEC decision 72).
    local close = ns.Looks.NearAny(m.a, m.b)
    local function place(on)
      if not ns.Looks.Need(m.a, m.b) then return end
      local amt = num(stake)
      if not Pu.ValidAmount(amt, purse) or not Du:Bet(m.id, on, amt) then ns:Print(L.AR_WA_BAD, true) end
    end
    local buttons = {}
    -- A player in the match may only bet on themselves.
    if m.b ~= me then buttons[#buttons + 1] = { L.AR_WA_ON:format(ns.Display(m.a)), function() place(m.a) end, off = not close } end
    if m.a ~= me then buttons[#buttons + 1] = { L.AR_WA_ON:format(ns.Display(m.b)), function() place(m.b) end, off = not close } end
    if not close and not bet then
      f:Text("bf" .. i, L.NEAR_BET:format(ns.Display(m.a), ns.Display(m.b)), "GameFontDisableSmall")
    end
    f:Buttons("bb" .. i, buttons)
  end
  f:Text("betnote", L.AR_WA_NOTE, "GameFontDisableSmall")
end

local function duels(f, page)
  local foot = yourDuel(f)
  for _, b in ipairs(crown(f)) do foot[#foot + 1] = b end
  wagers(f)
  local note = ladder(f, page)
  return foot, #foot == 0 and note or nil
end

---------------------------------------------------------------------------
-- The side window (UI/Side.lua): the cup's bracket, with the tournament picked, while it runs and for a week after
---------------------------------------------------------------------------
local CUP_SHOWN = 7 * 86400
local function side(page)
  local g = D:Current()
  -- The duels and Secret target as their scenes (UI/Scenes.lua, SPEC decision 60).
  if page.part == "duels" then
    if not g or not ns.Scenes.HasDuels(g) then return nil end
    return { key = "duels", icon = UI.ICON.duel, title = L.AR_DUELS, sub = L.AR_CROWN,
      draw = function(f) ns.Scenes.Duels(f, g) end }
  elseif page.part == "assassins" then
    local a, aid, phase = As.Current(g, time())
    local target = a and phase == "running" and page.asShow and As.Target(aid)
    if not target then return nil end
    return { key = "as:" .. aid, icon = UI.ICON.hood, title = L.AR_ASSASSINS, sub = L.AR_AS_TARGET:format(UI.Who(target)),
      draw = function(f) ns.Scenes.Target(f, aid, target) end }
  end
  if page.part ~= "cup" then return nil end
  local c, id = Cu.Current(g)
  if not c or not (c.st == "running" or (c.st == "done" and time() - (c.te or 0) < CUP_SHOWN)) then return nil end
  local pot = Cu.Pot(c)
  return { key = "cup:" .. id, icon = UI.ICON.prize, title = c.name or L.AR_CUP,
    sub = L.SIDE_CUP_SUB:format(#(c.seeds or {}), L["AR_FMT_" .. c.fmt], c.bo),
    draw = function(f)
      ns.Scenes.Cup(f, g, c, id)
      f:Strip("bracket", L.SIDE_BRACKET, pot > 0 and money(pot, c.p) or nil)
      if not f:Cup("cup", c, ns.Self()) then f:Empty("nobracket", L.SIDE_NO_BRACKET) end
      for i = 1, 3 do
        local list = c.places and c.places[i]
        if list and #list > 0 then
          local names = {}
          for j, n in ipairs(list) do names[j] = UI.Who(n) end
          f:Pair("place" .. i, L["AR_PLACE_" .. i], table.concat(names, ", "))
        end
      end
    end }
end

-- What waits for you here (SPEC decision 47): a duel to answer, your tournament match.
local function todo()
  local g, me = D:Current(), ns.Self()
  local out = {}
  if not g then return out end
  local ch = Du:Game()
  if ch and ch.st == "incoming" then out[#out + 1] = L.TODO_DUEL:format(ns.Display(ch.opp)) end
  local c = Cu.Current(g)
  if c and c.st == "running" then
    local mine = P:Of(me, g)
    for _, m in ipairs(Cu.Live((Cu.Build(c)))) do
      if P:Of(m.a, g) == mine then out[#out + 1] = L.TODO_CUP:format(ns.Display(m.b))
      elseif P:Of(m.b, g) == mine then out[#out + 1] = L.TODO_CUP:format(ns.Display(m.a)) end
    end
  end
  return out
end

-- Going on now, for Home: the tournament, while it signs up or runs.
local function now()
  local c = Cu.Current(D:Current())
  if not c or (c.st ~= "open" and c.st ~= "running") then return {} end
  return { { icon = UI.ICON.prize, name = c.name, sub = c.st == "open" and L.NOW_CUP_OPEN or L.NOW_CUP_RUNNING, t = c.t,
    pick = "cup" } }
end

---------------------------------------------------------------------------
-- The features' status and red number, on the left
---------------------------------------------------------------------------
local function myMatch(g, c)
  local mine = P:Of(ns.Self(), g)
  for _, m in ipairs(Cu.Live((Cu.Build(c)))) do
    if P:Of(m.a, g) == mine or P:Of(m.b, g) == mine then return m end
  end
end

local status = {
  duels = function()
    local g = D:Current()
    local s = g and Cr.State(g)
    return s and s.holder and L.FEAT_CROWN:format(ns.Short(P:Name(s.holder))) or L.FEAT_NO_CROWN
  end,
  cup = function()
    local c = Cu.Current(D:Current())
    local champ = c and c.places and c.places[1] and c.places[1][1]
    if champ then return L.FEAT_LAST_WON:format(ns.Short(P:Name(champ))) end
    if not c or (c.st ~= "open" and c.st ~= "running") then return L.FEAT_NOTHING end
    if c.st == "open" then return L.FEAT_CUP_OPEN:format(c.name or "") end
    local live = Cu.Live((Cu.Build(c)))
    return L.FEAT_CUP_RUN:format(c.name or "", live[1] and live[1].label or "")
  end,
  assassins = function()
    local a, _, phase = As.Current(D:Current(), time())
    if not a or phase == "done" then return L.FEAT_NOTHING end
    if phase == "signup" then return L.FEAT_AS_SIGNUP:format(#As.Joined(a)) end
    return L.FEAT_AS_DAY:format(As.Day(a, time()), a.days)
  end,
}
local count = {
  duels = function()
    local g, ch = D:Current(), Du:Game()
    local n = (ch and ch.st == "incoming") and 1 or 0
    local s = g and Cr.State(g)
    if s and s.holder and P:IsMe(s.holder) then n = n + #Cr.Waiting(g, s, time()) end
    return n
  end,
  cup = function()
    local g = D:Current()
    local c = g and Cu.Current(g)
    return (c and c.st == "running" and myMatch(g, c)) and 1 or 0
  end,
}

Hall:Register({
  id = "arena", label = L.PAGE_ARENA, sub = L.PAGE_ARENA_SUB,
  side = side,
  todo = todo,
  now = now,
  help = L.AR_LADDER_NOTE,
  status = function()
    local g = D:Current()
    local s = g and Cr.State(g)
    return s and s.holder and (UI.Inline(UI.ICON.crown) .. " " .. who(s.holder)) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "duels", L.AR_DUELS, icon = UI.ICON.duel }, { "cup", L.AR_CUPS, icon = UI.ICON.prize },
        { "assassins", L.AR_ASSASSINS, icon = UI.ICON.hood } },
      parts = { duels = duels, cup = cup, assassins = assassins },
      views = { player = playerView, newcup = newCup },
      status = status, count = count,
      save = "arenaTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})

ns:On("ARENA", function() if Hall.current == "arena" then Hall:Refresh() end end)
