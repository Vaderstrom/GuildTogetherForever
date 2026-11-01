-- Guild games (SPEC §8, §9.1, decisions 48, 52 and 54), in Games. Two features: the guild games (this week's games as
-- rows; the game picked opens beside the window: your part first, then what you can do, its picture, the facts and
-- its buttons, so nothing is ever below the list), and Gatherings from Journey (one press into the calendar; only with
-- Journey). Start a game... (ranks that may start games) opens beside the window: the games that are on as rows, then
-- their fields.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local P, Gm, Ga, Cal = ns.Players, ns.Games, ns.Gatherings, ns.Calendar
local Tr, Sa = ns.Traitors, ns.Santa

local WEEK_SHOWN = 12
local function num(box) return tonumber(strtrim(box:GetText() or "")) end
local function money(amt, purse) return Pu:Format(Pu.Units(amt, purse), purse) end
local function unit(purse) return purse == "gold" and L.UNIT_GOLD or D:Settings().many end
local function when(at) return date(L.GM_DATE, at) end
local kindName = Gm.KindName
local function name(n) return ns.Display(n) end
-- "1 vote", "3 votes".
local function voteCount(n)
  n = n or 0
  return (n == 1 and L.GM_VOTES_ONE or L.GM_VOTES):format(n)
end

local function left(sec)
  sec = math.max(0, math.floor(sec))
  if sec >= 2 * 86400 then return L.AR_DAYS:format(math.floor(sec / 86400)) end
  if sec >= 2 * 3600 then return L.ST_HOURS:format(math.floor(sec / 3600)) end
  return L.ST_MIN:format(math.max(1, math.ceil(sec / 60)))
end

-- One line on where a game stands.
local function status(item, now)
  local ga = item.ga
  if ga.kind == "traitors" and (item.st == "on" or item.st == "soon") then
    local phase, r = Tr.Phase(ga)
    if phase == "signup" then return item.st == "soon" and L.GM_STARTS:format(when(ga.at)) or L.TR_SIGNUP end
    local alive = 0
    for _ in pairs(Tr.Alive(ga)) do alive = alive + 1 end
    local line = (phase == "dusk" and r == 0) and L.TR_PHASE_DEALT or L["TR_PHASE_" .. phase:upper()]:format(r)
    return line .. " · " .. L.TR_LEFT:format(alive)
  end
  if ga.kind == "santa" and not ga.st then
    if not ga.pl then return L.SA_DRAWN_AT:format(when(ga.at)) end
    if item.st == "over" then return L.SA_REVEAL_DUE end
    return L.SA_GIFTS:format(Sa.Count(ga)) .. " · " .. L.SA_REVEAL_AT:format(when(ga.rv))
  end
  if item.st == "soon" then return L.GM_STARTS:format(when(ga.at)) end
  if item.st == "on" then return L.GM_ON:format(left(Gm.Ends(ga) - now)) end
  if item.st == "over" then return L.GM_OVER end
  if item.st == "off" then return L.GM_CALLED_OFF end
  if ga.w and #ga.w > 0 then
    local names = {}
    for i, n in ipairs(ga.w) do if i <= 3 then names[#names + 1] = name(n) end end
    if #ga.w > 3 then names[#names + 1] = L.GM_MORE:format(#ga.w - 3) end
    return L.GM_WON:format(table.concat(names, ", "))
  end
  return L.GM_NO_WINNER
end

---------------------------------------------------------------------------
-- The game picked: the Traitors and Secret Santa
---------------------------------------------------------------------------
local NEEDS_JOIN = { bingo = true, derby = true, fashion = true, gnomes = true, traitors = true, santa = true }
-- The games the host runs step by step: no "End and pay out", and sign-up closes when roles or pairs are dealt.
local HOSTED = { traitors = true, santa = true }

-- Hidden traitors: your role, and what you (or the host) can do now. The players still in show as a list only while
-- you have a choice to make (murder at night, a vote at the round table); the board below shows everyone.
local function traitors(f, page, g, ga, id, isHost, buttons, tools)
  local phase, r = Tr.Phase(ga)
  local me = ns.Self()
  local alive = Tr.Alive(ga)
  local role, mates = Tr.Role(id)
  local playing = alive[me] == true
  if isHost then
    f:Text("youH", L.TR_YOU_HOST, "GameFontDisableSmall")
    if phase == "signup" then
      local n = 0
      for _ in pairs(Gm.Joined(g, ga)) do n = n + 1 end
      page.trN = page.trN or Tr.Default(n)
      if page.trN * 2 >= n then page.trN = math.max(1, math.ceil(n / 2) - 1) end
      tools[#tools + 1] = { L.TR_COUNT:format(page.trN), function()
        page.trN = page.trN + 1
        if page.trN * 2 >= n then page.trN = 1 end
        Hall:Refresh()
      end }
      buttons[#buttons + 1] = { L.TR_DEAL, function()
        Hall:Confirm(L.TR_DEAL_ASK:format(n, page.trN), L.TR_DEAL, function()
          if not Tr.Deal(id, page.trN) then ns:Print(L.TR_NEED:format(Tr.MIN), true) end
        end)
      end }
    elseif phase == "dusk" then
      buttons[#buttons + 1] = { L.TR_NIGHT, function() Tr.Night(id) end }
    elseif phase == "night" then
      buttons[#buttons + 1] = { L.TR_MORNING, function() Tr.Morning(id) end }
      f:Text("picked", L.TR_PICKED:format(Tr.Picked(id, r), ga.n or 0), "GameFontDisableSmall")
    elseif phase == "table" then
      buttons[#buttons + 1] = { L.TR_BANISH, function()
        Hall:Confirm(L.TR_BANISH_ASK, L.TR_BANISH, function() Tr.Banish(id) end)
      end }
    end
  elseif role == "traitor" then
    f:Text("youT", L.TR_YOU_TRAITOR, "GameFontRedSmall")
    if #mates > 0 then
      local list = {}
      for i, n in ipairs(mates) do list[i] = name(n) end
      f:Text("mates", L.TR_MATES:format(table.concat(list, ", ")), "GameFontRedSmall")
    end
  elseif role == "faithful" then
    f:Text("youF", L.TR_YOU_FAITHFUL, "GameFontGreenSmall")
  elseif ga.pl then
    for _, n in ipairs(ga.pl) do if n == me then f:Text("youW", L.TR_WAIT_ROLE, "GameFontDisableSmall") end end
  end
  if phase == "done" then
    local list = {}
    for i, n in ipairs(ga.tr or {}) do list[i] = name(n) end
    f:Text("end", ga.side == "faithful" and L.TR_WON_FAITHFUL or L.TR_WON_TRAITORS, "GameFontNormal")
    f:Text("were", L.TR_WERE:format(table.concat(list, ", ")), "GameFontDisableSmall")
  end
  local choosing =playing and ((phase == "night" and role == "traitor") or phase == "table")
  if not ga.pl or not choosing then return end
  -- The players still in: murder (a traitor, at night) or vote (at the round table).
  local tally, choice = {}, {}
  if phase == "table" then
    local list
    list, choice = Tr.Tally(ga, r)
    for _, e in ipairs(list) do tally[e.name] = e.n end
  end
  local mate = {}
  for _, n in ipairs(mates or {}) do mate[n] = true end
  local pick = phase == "night" and Tr.MyPick(id, r)
  local list = {}
  for n in pairs(alive) do if n ~= me and not (phase == "night" and mate[n]) then list[#list + 1] = n end end
  table.sort(list)
  f:Strip("in", phase == "night" and L.TR_CHOOSE or L.TR_VOTE_OUT)
  for i, n in ipairs(list) do
    local label, fn, sub
    if phase == "night" then
      if pick ~= n then label, fn = L.TR_MURDER, function() Tr.Pick(id, n) end end
      if pick == n then sub = L.TR_YOUR_PICK end
    else
      if choice[me] ~= n then label, fn = L.GM_VOTE, function() Tr.Vote(id, n) end end
      sub = voteCount(tally[n]) .. (choice[me] == n and (" · " .. L.GM_YOUR_VOTE) or "")
    end
    f:Line("p" .. i, name(n), label, fn, sub, label ~= nil and (phase == "night" and not pick or not choice[me]))
  end
end

-- The gift exchange: who you give to, whether your gift came, and the pairs once revealed.
local function santa(f, ga, id, isHost, buttons, item)
  local me = ns.Self()
  if isHost and not ga.pl and not ga.st then
    buttons[#buttons + 1] = { L.SA_DRAW, function()
      Hall:Confirm(L.SA_DRAW_ASK, L.SA_DRAW, function()
        if not Sa.Draw(id) then ns:Print(L.SA_NEED:format(Sa.MIN), true) end
      end)
    end }
  elseif isHost and ga.pl and not ga.st then
    buttons[#buttons + 1] = { L.SA_REVEAL_NOW, function()
      Hall:Confirm(item.st == "over" and L.SA_REVEAL_ASK or L.SA_REVEAL_EARLY_ASK, L.SA_REVEAL_NOW, function() Sa.Reveal(id) end)
    end }
  end
  if ga.pl and Sa.Plays(ga, me) and not ga.st then
    local to = Sa.Giftee(id)
    f:Text("to", to and L.SA_YOURS:format(name(to)) or L.SA_WAIT, to and "GameFontNormal" or "GameFontDisableSmall")
    if to then f:Text("mail", L.SA_MAIL, "GameFontDisableSmall") end
    f:Text("got", ga.got and ga.got[me] and L.SA_GOT or L.SA_NOT_YET, "GameFontHighlightSmall")
  end
  if ga.pairs and #ga.pairs > 0 then f:Strip("pairs", L.SA_PAIRS) end
  for i, x in ipairs(ga.pairs or {}) do
    local giver, to = x[1], x[2]
    f:Pair("pr" .. i, name(giver), L.SA_GAVE:format(name(to)) .. (ga.got and ga.got[to] and "" or (" · " .. L.SA_NO_GIFT)))
  end
end

---------------------------------------------------------------------------
-- This week's games: one row each, the one picked lit up. It opens beside the window.
---------------------------------------------------------------------------
-- The game to show first: the one picked before, else one you are in that is running, else the first.
local function pickFirst(page, list, g)
  for _, item in ipairs(list) do if item.id == page.sel then return end end
  local me = g and P:Of(ns.Self(), g)
  page.sel = list[1] and list[1].id or nil
  for _, item in ipairs(list) do
    if item.st == "on" and Gm.IsIn(g, item.ga, me) then page.sel = item.id return end
  end
end

local function week(f, page)
  local g = D:Current()
  local now = time()
  local list = g and Gm.List(g, now) or {}
  page.list = list
  pickFirst(page, list, g)
  local me = g and P:Of(ns.Self(), g)
  f:Strip("week", L.GM_WEEK)
  if #list == 0 then
    f:Empty("none", L.GM_NONE, D:Can("games") and L.GM_NONE_DO:format(UI.Key(L.GM_NEW_DOTS)) or L.GM_NONE_ASK)
  end
  for i, item in ipairs(list) do
    if i > WEEK_SHOWN then break end
    local ga = item.ga
    local live = item.st == "on" or item.st == "soon"
    local inIt = live and Gm.IsIn(g, ga, me)
    local prized = (ga.prize or 0) > 0
    f:Row("w" .. i, { icon = UI.ICON[ga.kind] or UI.ICON.question, name = Gm.Title(ga),
      sub = status(item, now) .. (inIt and (" · " .. L.GM_YOU_IN) or ""),
      value = prized and money(ga.prize, ga.p) or nil, sel = item.id == page.sel,
      dim = item.st == "done" or item.st == "off", tip = { Gm.Title(ga), status(item, now) },
      onClick = function()
        page.sel = item.id
        ns.Side:Undismiss()
        page.View(nil)
      end })
  end
  local foot = {}
  if D:Can("games") then foot[1] = { L.GM_NEW_DOTS, function() page.View({ kind = "start" }) end } end
  return foot
end

---------------------------------------------------------------------------
-- The side window (UI/Side.lua): the game picked, as a picture
---------------------------------------------------------------------------
local BAR_TEXT = {
  derby = function(e) return L.GM_FISH:format(e.v) end,
  hunt = function(e, ga) return L.GM_CLUES:format(e.v, #(ga.clues or {})) end,
  fashion = function(e) return voteCount(e.v) end,
  bingo = function(e) return e.bingo and L.GM_HAS_BINGO or L.GM_SQUARES:format(e.v, Gm.SIZE * Gm.SIZE) end,
}
local BAR_ICON = { derby = UI.ICON.fish, hunt = UI.ICON.hunt, fashion = UI.ICON.fashion, bingo = UI.ICON.bingo }

-- The Traitors' board: everyone still in, then the fallen (the newest murder shakes).
local function board(f, g, ga)
  local phase, r = Tr.Phase(ga)
  local list, me = {}, ns.Self()
  if not ga.pl then
    for _, n in pairs(Gm.Joined(g, ga)) do list[#list + 1] = { name = n, me = n == me } end
    table.sort(list, function(a, b) return a.name < b.name end)
    f:Strip("board", L.SIDE_SIGNED, tostring(#list))
    f:Tiles("tiles", list, 3)
    return
  end
  local alive, fallen = Tr.Alive(ga)
  local tally = {}
  if phase == "table" then for _, e in ipairs((Tr.Tally(ga, r))) do tally[e.name] = e.n end end
  for n in pairs(alive) do
    list[#list + 1] = { name = n, me = n == me, sub = phase == "table" and voteCount(tally[n]) or nil }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  local stillIn, lastMurder = #list, nil
  for _, x in ipairs(fallen) do
    local e = { name = x.name, out = x.how, role = x.role, me = x.name == me,
      sub = x.how == "murdered" and L.SIDE_MURDERED or L.SIDE_BANISHED,
      tip = x.how == "murdered" and L.TR_MURDERED:format(x.r)
        or L.TR_BANISHED:format(x.r, x.role == "traitor" and L.TR_A_TRAITOR or L.TR_A_FAITHFUL) }
    list[#list + 1] = e
    if x.how == "murdered" then lastMurder = e end
  end
  if lastMurder then lastMurder.fresh = true end
  f:Strip("board", L.SIDE_BOARD, L.TR_LEFT:format(stillIn))
  f:Tiles("tiles", list, 3)
end

local function picture(f, g, ga, id, me)
  if ga.kind == "traitors" then
    board(f, g, ga)
  elseif ga.kind == "flash" then
    local scores = Gm.Scores(g, ga, id)
    f:Countdown("clock", ga.at, Gm.Ends(ga), #scores)
    local names = {}
    for i, e in ipairs(scores) do if i <= 12 then names[#names + 1] = UI.Who(e.name) end end
    f:Text("there", #names > 0 and L.SIDE_THERE:format(table.concat(names, ", ")) or L.SIDE_NOBODY_YET)
  elseif ga.kind == "gnomes" then
    local runners = {}
    for i, e in ipairs(Gm.Scores(g, ga, id)) do
      runners[i] = { name = e.name, at = e.v, done = e.done, dead = e.dead ~= nil, me = e.key == me,
        tip = e.done and L.GM_SURVIVED or (e.dead and L.GM_FELL:format(e.v) or L.GM_CHECKS:format(e.v, #(ga.clues or {}))) }
    end
    f:Strip("race", L.SIDE_RACE, L.GM_CHECKS:format(#(ga.clues or {}), #(ga.clues or {})))
    if #runners == 0 then f:Empty("nobody", L.GM_NO_SCORES) else f:Track("track", #(ga.clues or {}), runners) end
  elseif BAR_TEXT[ga.kind] then
    if ga.kind == "hunt" then
      local mine, trail = Gm.Merged(g, ga, me).c, {}
      for i, clue in ipairs(ga.clues or {}) do trail[i] = { found = Gm.Finder(ga, i), mine = mine[i] ~= nil, text = clue.text } end
      f:Strip("trail", L.SIDE_TRAIL)
      f:Trail("trailMap", trail)
    end
    local bars = {}
    for i, e in ipairs(Gm.Scores(g, ga, id)) do
      bars[i] = { name = e.name, v = e.v, text = BAR_TEXT[ga.kind](e, ga), me = e.key == me }
    end
    f:Strip("lead", L.GM_STANDINGS)
    if #bars == 0 then f:Empty("noscores", L.GM_NO_SCORES) else f:Bars("bars", bars, BAR_ICON[ga.kind]) end
  else
    return false
  end
  return true
end

-- Your bingo card, in a bingo game you joined.
local function card(f, g, item, me)
  local key = Gm.Joined(g, item.ga)[me]
  if item.ga.kind ~= "bingo" or not key or item.st == "done" or item.st == "off" then return end
  local sq = Gm.Merged(g, item.ga, me).sq
  local cells = {}
  for i, s in ipairs(Gm.Card(item.id, key)) do cells[i] = { L["SQ_" .. s:upper()], s == "free" or sq[s] ~= nil } end
  f:Strip("card", L.GM_TAB_BINGO)
  f:Grid("cardGrid", Gm.SIZE, cells)
  f:Text("cardNote", L.GM_BINGO_NOTE, "GameFontDisableSmall")
end

-- What you can do in a game kind by kind: the clues (I'm here), the entrants (Vote), the checkpoints you reached.
local function actions(f, g, item, me)
  local ga, id = item.ga, item.id
  if ga.kind == "hunt" then
    local mine, found = Gm.Merged(g, ga, me).c, 0
    for _ in pairs(mine) do found = found + 1 end
    f:Strip("clues", L.GM_CLUES_HEAD, L.GM_CLUES:format(found, #(ga.clues or {})))
    for i, clue in ipairs(ga.clues or {}) do
      local finder = Gm.Finder(ga, i)
      local sub = finder and L.GM_FOUND_BY:format(name(finder)) or L.GM_NOT_FOUND
      f:Line("c" .. i, L.GM_CLUE:format(i, clue.text), (item.st == "on" and not mine[i]) and L.GM_HERE or nil,
        function() Gm.Claim(id, i) end, mine[i] and (sub .. " · " .. L.GM_YOU_FOUND) or sub)
    end
  elseif ga.kind == "fashion" then
    local votes = {}
    for _, e in ipairs(Gm.Scores(g, ga, id)) do votes[e.key] = e.v end
    local mine = ga.v and ga.v[ns.Self()]
    local list = {}
    for key, n in pairs(Gm.Joined(g, ga)) do list[#list + 1] = { key = key, name = n } end
    table.sort(list, function(a, b) return a.name < b.name end)
    f:Strip("entrants", L.GM_ENTRANTS, tostring(#list))
    if #list == 0 then f:Text("noent", L.GM_NO_ENTRANTS, "GameFontDisableSmall") end
    if item.st == "on" and #list > 0 and not ns.Looks.Near(ga.h) then
      f:Text("farvote", L.NEAR_VOTE:format(ns.Display(ga.h)), "GameFontNormal")
    end
    for i, e in ipairs(list) do
      local voted = mine and P:Of(mine.on, g) == e.key
      -- (Votes come from the show: near the host, SPEC decision 72.)
      local can = item.st == "on" and e.key ~= me and not voted and ns.Looks.Near(ga.h)
      f:Line("e" .. i, UI.Who(e.name) .. (voted and (" · " .. L.GM_YOUR_VOTE) or ""), can and L.GM_VOTE or nil,
        function() Gm.Vote(id, e.name) end, voteCount(votes[e.key]), can and not mine)
    end
  elseif ga.kind == "gnomes" then
    local mine = Gm.Joined(g, ga)[me] and Gm.Run(ga, Gm.Merged(g, ga, me)) or 0
    f:Strip("route", L.GM_ROUTE)
    for i, c in ipairs(ga.clues or {}) do
      local label = i == #ga.clues and L.GM_FINISH_LINE or L.GM_CHECK:format(i)
      f:Pair("c" .. i, label .. ": " .. (c.text or c.z or "?"), i <= mine and L.GM_REACHED or "")
    end
  end
end

-- The facts: when, the host, the prize, where, who may run, the rules; then how it works.
local function facts(f, item)
  local ga, now = item.ga, time()
  f:Strip("facts", L.GM_FACTS)
  f:Pair("when", L.GM_WHEN, item.st == "soon" and when(ga.at) or status(item, now))
  f:Pair("host", L.GM_HOST, UI.Who(ga.h))
  if (ga.prize or 0) > 0 then f:Pair("prize", ga.kind == "flash" and L.GM_PRIZE_EACH or L.GM_PRIZE, money(ga.prize, ga.p)) end
  if ga.kind == "flash" and ga.spot then f:Pair("spot", L.GM_SPOT, ga.spot.z or "?") end
  if ga.kind == "gnomes" then f:Pair("lv", L.GM_LEVEL, L.GM_LEVEL_MAX:format(ga.lv or 1)) end
  if ga.kind == "santa" then
    if ga.rv then f:Pair("rv", L.SA_REVEAL, when(ga.rv)) end
    if ga.pl then f:Pair("count", L.SA_ARRIVED, L.SA_OF:format(Sa.Count(ga))) end
    if ga.note then f:Pair("gift", L.SA_GIFT, ga.note) end
  elseif ga.note then
    f:Pair("note0", L.GM_RULES, ga.note)
  end
  f:Text("about", L["GM_ABOUT_" .. ga.kind:upper()], "GameFontDisableSmall")
  f:Text("note", L["GM_NOTE_" .. ga.kind:upper()], "GameFontDisableSmall")
end

-- The game picked, beside the window (SPEC decision 52): your part first (your role, who you give to, your bingo card),
-- then what you can do now, its picture, the facts, and the host's tools; Join and the host's next step along the
-- bottom. Returns those buttons.
local function details(f, page, g, item)
  local ga, id = item.ga, item.id
  local me = P:Of(ns.Self(), g)
  local isHost = P:Of(ga.h, g) == me
  local open = item.st == "soon" or item.st == "on"
  if HOSTED[ga.kind] then open = not ga.pl and not ga.st and not (ga.kind == "traitors" and isHost) end
  local joined = Gm.IsIn(g, ga, me)
  local buttons, tools = {}, {}
  if NEEDS_JOIN[ga.kind] and open then
    -- Bingo and the transmog contest are joined face to face with the host (SPEC decision 72).
    local far = not joined and Gm.FACE[ga.kind] and not ns.Looks.Near(ga.h)
    if far then f:Text("far", L.NEAR_HOST:format(ns.Display(ga.h)), "GameFontNormal") end
    buttons[#buttons + 1] = { joined and L.GM_LEAVE or (ga.kind == "fashion" and L.GM_ENTER or L.GM_JOIN),
      function() Gm.Join(id, not joined) end, next = not joined and item.st == "on", off = far }
  end
  if ga.kind == "traitors" then traitors(f, page, g, ga, id, isHost, buttons, tools)
  elseif ga.kind == "santa" then santa(f, ga, id, isHost, buttons, item) end
  card(f, g, item, me)
  if not HOSTED[ga.kind] and (isHost or D:Can("games")) and (item.st == "on" or item.st == "over") then
    buttons[#buttons + 1] = { L.GM_FINISH, function()
      Hall:Confirm(L.GM_FINISH_ASK, L.GM_FINISH, function() if not Gm.Finish(id) then ns:Print(L.GM_BAD, true) end end)
    end, next = item.st == "over" }
  end
  if isHost and not ga.st then
    tools[#tools + 1] = { L.GM_CALL_OFF, function()
      Hall:Confirm(L.GM_CALL_OFF_ASK, L.GM_CALL_OFF, function() Gm.Cancel(id) end)
    end }
  end
  actions(f, g, item, me)
  -- The game's scene above its picture (UI/Scenes.lua, SPEC decision 60).
  ns.Scenes.Game(f, g, ga, id, me)
  picture(f, g, ga, id, me)
  facts(f, item)
  while #buttons > ns.Side.BUTTONS do table.insert(tools, 1, table.remove(buttons)) end
  if #tools > 0 then
    f:Strip("toolsHead", L.GM_FOR_HOST)
    tools.quiet = true
    f:Buttons("tools", tools)
  end
  return buttons
end

local function side(page)
  if page.part ~= "game" then return nil end
  local g = D:Current()
  local item
  for _, x in ipairs(page.list or {}) do if x.id == page.sel then item = x end end
  if not item or not g then return nil end
  local ga = item.ga
  return { key = "game:" .. item.id, icon = UI.ICON[ga.kind] or UI.ICON.question, title = Gm.Title(ga),
    sub = status(item, time()),
    draw = function(f) return details(f, page, g, item) end }
end

---------------------------------------------------------------------------
-- Gatherings from Journey
---------------------------------------------------------------------------
local function gatherings(f)
  if not Ga.Available() then
    f:Empty("none", L.GA_NO_JOURNEY)
    return {}
  end
  local list = Ga.List()
  if #list == 0 then f:Empty("none", L.GA_NONE) end
  local calOn = Cal.On()
  for i, e in ipairs(list) do
    if i > 6 then break end
    local k = "g" .. i
    f:Row(k .. "r", { icon = UI.ICON.journey, name = e.what, sub = when(e.at), value = e.by and UI.Who(e.by) or nil })
    if not calOn then
      f:Text(k .. "s", e.mine and L.GA_YOURS_NOCAL or L.GA_BY:format(name(e.by or "?")), "GameFontDisableSmall")
    elseif e.mine and e.st == "new" then
      if #e.members == 0 then
        f:Text(k .. "s", L.GA_NOBODY, "GameFontDisableSmall")
      else
        f:Text(k .. "s", L.GA_YOURS:format(#e.members))
        f:Buttons(k .. "b", { { L.GA_ADD, function() Ga.Add(e) end } })
      end
    elseif e.mine and (e.st == "moved" or e.st == "cancelled") then
      f:Text(k .. "s", e.st == "moved" and L.GA_WAS_MOVED or L.GA_WAS_CANCELLED)
      f:Buttons(k .. "b", { { e.st == "moved" and L.GA_MOVE or L.GA_REMOVE, function() Ga.Change(e) end } })
    elseif e.st == "added" or (not e.mine and e.st ~= "new") then
      f:Text(k .. "s", e.mine and L.GA_IN_CAL:format(#e.members) or L.GA_IN_YOUR_CAL)
    else
      f:Text(k .. "s", L.GA_NOT_YET:format(name(e.by or "?")), "GameFontDisableSmall")
    end
  end
  f:Text("note", calOn and L.GA_NOTE or L.GA_CAL_OFF, "GameFontDisableSmall")
  return {}
end

---------------------------------------------------------------------------
-- Starting a game, beside the window. First the eight games as rows, then the fields of the one picked.
---------------------------------------------------------------------------
local function startForm(f, page)
  if not D:Can("games") then return nil end
  local back = { L.CANCEL, function() page.View(nil) end }
  if not page.view.picked then
    f:Strip("which", L.GM_PICK_KIND)
    for i, k in ipairs(Gm.KINDS) do
      if D:On("g:" .. k) then
        f:Row("k" .. i, { icon = UI.ICON[k], name = kindName(k), sub = L["GM_ABOUT_" .. k:upper()],
          tip = { kindName(k), L["GM_ABOUT_" .. k:upper()] },
          onClick = function()
            page.kind = i
            page.View({ kind = "start", picked = true })
          end })
      end
    end
    return { back }
  end
  local purse = D:Settings().purse
  page.kind = page.kind or 1
  local kind = Gm.KINDS[page.kind]
  f:Row("kind", { icon = UI.ICON[kind], name = kindName(kind), sub = L.ST_PRESS, sel = true,
    onClick = function() page.View({ kind = "start" }) end })
  f:Text("about", L["GM_ABOUT_" .. kind:upper()], "GameFontDisableSmall")
  local third = math.floor((f.width - 16) / 3)
  local whenBox = f:Field("when", kind == "santa" and L.SA_F_DRAW or L.GM_F_WHEN, third - 10, nil, true)
  local lenBox, prizeBox, rvBox, lvBox, noteBox
  if kind == "santa" then
    rvBox = f:Field("rv", L.SA_F_REVEAL, 2 * third - 2, third + 8)
  else
    local x = third + 8
    if kind ~= "flash" and kind ~= "traitors" then
      lenBox = f:Field("len", L.GM_F_LEN, third - 10, x, true)
      x = x + third + 8
    end
    prizeBox = f:Field("prize", L.GM_F_PRIZE:format(unit(purse)), third - 10, x)
    if (prizeBox:GetText() or "") == "" then prizeBox:SetText("0") end
  end
  if lenBox and (lenBox:GetText() or "") == "" then lenBox:SetText("60") end
  if kind == "gnomes" then
    lvBox = f:Field("lv", L.GM_F_LEVEL, third - 10)
    if (lvBox:GetText() or "") == "" then lvBox:SetText("1") end
  end
  if kind == "traitors" or kind == "santa" then
    noteBox = f:Field("note", kind == "santa" and L.SA_F_GIFT or L.GM_F_NOTE, f.width - 10)
    noteBox:SetMaxLetters(Gm.NOTE_MAX)
  end
  local hints = { flash = L.GM_F_HINT_FLASH, gnomes = L.GM_F_HINT_GNOMES, traitors = L.GM_F_HINT_TRAITORS, santa = L.GM_F_HINT_SANTA }
  f:Text("hint", hints[kind] or L.GM_F_HINT, "GameFontDisableSmall")
  local clueBox
  if kind == "hunt" or kind == "gnomes" then
    local hunt = kind == "hunt"
    if page.cluesFor ~= kind then page.clues, page.cluesFor = nil, kind end
    page.clues = page.clues or {}
    for i, c in ipairs(page.clues) do
      f:Pair("cl" .. i, hunt and L.GM_CLUE:format(i, c.text) or (L.GM_CHECK:format(i) .. (c.text and (": " .. c.text) or "")), c.z or "?")
    end
    clueBox = f:Field("clue", hunt and L.GM_F_CLUE or L.GM_F_CHECK, f.width - 10)
    clueBox:SetMaxLetters(Gm.CLUE_LEN)
    local max = hunt and Gm.CLUES_MAX or Gm.CHECKS_MAX
    f:Buttons("addclue", { { hunt and L.GM_F_ADD_CLUE or L.GM_F_ADD_CHECK, function()
      local text = ns.Raffle.Clean(clueBox:GetText(), Gm.CLUE_LEN)
      local here = ns.Punish.Here()
      if (hunt and not text) or not here then ns:Print(here and L.GM_F_CLUE_BAD or L.ST_SPOT_BAD, true) return end
      if #page.clues >= max then return end
      here.text = text
      page.clues[#page.clues + 1] = here
      clueBox:SetText("")
      Hall:Refresh()
    end } }, (hunt and L.GM_F_CLUES or L.GM_F_CHECKS):format(#page.clues, max))
  end
  return { { L.GM_START, function()
    local at = Gm.When(whenBox:GetText())
    local len, prize = lenBox and num(lenBox) or nil, prizeBox and num(prizeBox) or 0
    local extra = { note = noteBox and ns.Raffle.Clean(noteBox:GetText(), Gm.NOTE_MAX) or nil }
    if kind == "santa" then
      extra.rv = at and Gm.When(rvBox:GetText(), at)
      if not extra.rv then ns:Print(L.SA_F_BAD, true) return end
    end
    if kind == "gnomes" then
      extra.lv = num(lvBox)
      if not page.clues or #page.clues == 0 then ns:Print(L.GM_F_NEED_CHECK, true) return end
      extra.clues = page.clues
    end
    if kind == "flash" then
      extra.spot = ns.Punish.Here()
      if not extra.spot then ns:Print(L.ST_SPOT_BAD, true) return end
    end
    if kind == "hunt" then
      if not page.clues or #page.clues == 0 then ns:Print(L.GM_F_NEED_CLUE, true) return end
      extra.clues = page.clues
    end
    if not at or (prize ~= 0 and not Pu.ValidAmount(prize, purse)) or not Gm.Open(kind, at, len, prize, extra) then
      ns:Print(L.GM_F_BAD, true)
      return
    end
    whenBox:SetText("")
    if noteBox then noteBox:SetText("") end
    page.clues = nil
    page.View(nil)
  end }, back }
end

-- Going on now, for Home: the guild games under way.
local function now()
  local out, t = {}, time()
  for _, item in ipairs(Gm.List(D:Current(), t)) do
    if item.st == "on" then
      local ga = item.ga
      out[#out + 1] = { icon = UI.ICON[ga.kind] or UI.ICON.question, name = Gm.Title(ga), sub = status(item, t), t = ga.at,
        open = function(page) page.sel, page.part, page.view = item.id, "game", nil end }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- The features' status, on the left
---------------------------------------------------------------------------
local featStatus = {
  -- The games on this week; with none, who won the last one.
  game = function()
    local g, n, last = D:Current(), 0, nil
    for _, item in ipairs(g and Gm.List(g, time()) or {}) do
      if item.st == "on" or item.st == "soon" then n = n + 1 end
      if item.st == "done" and item.ga.w and #item.ga.w > 0 and (not last or item.ga.at > last.ga.at) then last = item end
    end
    if n > 0 then return L.FEAT_GAMES_ON:format(n) end
    return last and L.FEAT_LAST_WON:format(ns.Short(last.ga.w[1])) or L.FEAT_NOTHING
  end,
  journey = function()
    local n = #Ga.List()
    return n > 0 and L.FEAT_PLANNED:format(n) or L.FEAT_NOTHING
  end,
}

Hall:Register({
  id = "games", label = L.PAGE_GAMES, sub = L.PAGE_GAMES_SUB,
  now = now,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "game", L.GM_GUILD_GAMES, icon = UI.ICON.rosette },
        { "journey", L.GA_HEAD, icon = UI.ICON.journey, on = function() return Ga.Available() end } },
      parts = { game = week, journey = gatherings },
      views = { start = startForm },
      status = featStatus,
      save = "gamesTab",
    })
  end,
  refresh = function(page)
    Cal.Load()
    Hall:DrawRight(page)
  end,
  side = side,
})

ns:On("GATHERINGS", function() if Hall.current == "games" then Hall:Refresh() end end)
-- A secret arrived (a role, a giftee, a pick): only this page shows it.
ns:On("GAMES", function() if Hall.current == "games" then Hall:Refresh() end end)
