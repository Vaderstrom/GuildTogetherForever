-- Gambling (SPEC §8, decisions 48 and 55): bets and raffles, in the purse. Three features: the deathroll
-- (Guild/Deathroll.lua), the high roll (Guild/RollOff.lua) and the lottery (Guild/Raffle.lua). The challenge and a
-- new lottery open beside the window as forms.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local R, Comm = ns.Roster, ns.Comm

local PLAYERS_SHOWN = 12
local function money(amt, purse) return Pu:Format(Pu.Units(amt, purse), purse) end
local function unit(purse) return purse == "gold" and L.UNIT_GOLD or D:Settings().many end
local function num(box) return tonumber(strtrim(box:GetText() or "")) end

local function near(name) return ns.Looks.Near(name) end

-- Online members heard from this session (they have the addon): those near you first (face to face, SPEC decision
-- 72), then in name order.
local function here()
  local list, me = {}, ns.Self()
  for name in pairs(Comm.heard) do
    if name ~= me and R:Online(name) and R:Rank(name) ~= nil then list[#list + 1] = name end
  end
  table.sort(list, function(a, b)
    local na, nb = near(a), near(b)
    if na ~= nb then return na end
    return a < b
  end)
  return list
end

local function raffleHead(ra, sold)
  if ra.st == "done" then return ra.prize or "" end
  return (ra.max or 0) > 0 and L.RA_TITLE:format(ra.prize or "", sold, ra.max) or L.RA_TITLE_OPEN:format(ra.prize or "", sold)
end

---------------------------------------------------------------------------
-- The deathroll: the game in hand, or the online members to challenge (the challenge opens beside the window)
---------------------------------------------------------------------------
local function players(f, page)
  local list = here()
  f:Strip("players", L.TV_PLAYERS)
  if #list == 0 then f:Empty("nobody", L.DR_NOBODY, L.DR_NOBODY_DO) end
  local view = page.view and page.view.kind == "challenge" and page.view.key
  for i, name in ipairs(list) do
    if i > PLAYERS_SHOWN then break end
    local close = near(name)
    f:Row("p" .. i, { icon = UI.ICON.skull, name = UI.Who(name), vsub = close and L.DR_CHALLENGE or L.NEAR_FAR,
      dim = not close, sel = view == name,
      onClick = function()
        page.drFilled, page.drStartTouched = nil, nil
        page.View({ kind = "challenge", key = name })
      end })
  end
  f:Text("pick", L.DR_PICK, "GameFontDisableSmall")
end

local function deathroll(f, page)
  local DR = ns.Deathroll
  local game = DR:Game()
  if not game then
    f:Text("about", L.DR_HOW, "GameFontDisableSmall")
    players(f, page)
    return {}
  end
  local opp = ns.Display(game.opp)
  local foot = {}
  f:Strip("title", L.DR_VS:format(UI.Who(game.opp), money(game.amt, game.p)))
  if game.st == "asked" then
    f:Text("wait", L.DR_WAITING:format(opp))
    foot[1] = { L.CANCEL, function() DR:CallOff() end }
  elseif game.st == "incoming" then
    f:Text("incoming", L.DR_INCOMING:format(opp, money(game.amt, game.p), game.s), "GameFontNormal")
    local close = near(game.opp)
    if not close then f:Text("far", L.NEAR_ACCEPT:format(opp), "GameFontNormal") end
    foot = { { L.DR_ACCEPT, function() if not DR:Accept() then ns.Looks.Need(game.opp) end end, next = true, off = not close },
      { L.DR_DECLINE, function() DR:CallOff() end } }
  else
    local chips = { { tostring(game.s), L.DR_START_CHIP } }
    for _, r in ipairs(game.rolls) do chips[#chips + 1] = { tostring(r.v), r.who == "me" and L.DR_YOU or ns.Short(game.opp), r.v == 1 } end
    f:Chips("rolls", chips)
    if game.st == "over" then
      local text = game.loser == "me" and L.DR_LOST_YOU:format(opp, money(game.amt, game.p))
        or L.DR_LOST_THEM:format(opp, money(game.amt, game.p))
      f:Text("result", text .. " " .. (game.p == "gold" and L.DR_LEDGER_GOLD or L.DR_LEDGER_MARKS), "GameFontNormal")
      foot[1] = { L.DR_AGAIN, function() DR:Clear() end }
    else
      local whose, max = DR:Turn()
      if whose == "me" then
        f:Text("yours", L.DR_YOUR_ROLL, "GameFontNormal")
        foot[1] = { L.DR_ROLL:format(max), function() DR:RollNow() end, next = true }
      else
        f:Text("theirs", L.DR_THEIR_ROLL:format(opp), "GameFontDisableSmall")
      end
    end
  end
  f:Text("note", L.DR_NOTE, "GameFontDisableSmall")
  return foot
end

local function challenge(f, page)
  local DR, target = ns.Deathroll, page.view.key
  if DR:Game() then return nil end
  local purse = D:Settings().purse
  f:Strip("title", L.DR_FORM:format(UI.Who(target)))
  local half = math.floor((f.width - 12) / 2)
  local stake = f:Field("stake", L.DR_STAKE:format(unit(purse)), half - 10, nil, true)
  local start = f:Field("start", L.DR_START, half - 10, half + 12)
  if not page.drFilled then
    stake:SetText("5")
    start:SetText("500")
    page.drFilled = true
  end
  -- The start follows the stake (100 x) until the player changes it.
  stake:SetScript("OnTextChanged", function(box, user)
    if user and not page.drStartTouched and num(box) then start:SetText(tostring(num(box) * 100)) end
  end)
  start:SetScript("OnTextChanged", function(_, user) if user then page.drStartTouched = true end end)
  local close = near(target)
  if not close then f:Text("far", L.NEAR_CHALLENGE:format(ns.Display(target)), "GameFontNormal") end
  f:Text("note", L.DR_NOTE, "GameFontDisableSmall")
  return {
    { L.DR_SEND, off = not close, function()
      local ok, why = DR:Challenge(target, num(stake), purse, num(start))
      if why == "far" then ns.Looks.Need(target) return end
      if not ok then ns:Print(L.DR_BAD, true) return end
      page.part = "deathroll"
      page.View(nil)
    end },
    { L.CANCEL, function() page.View(nil) end },
  }
end

---------------------------------------------------------------------------
-- Right: the roll-off
---------------------------------------------------------------------------
local function rolloff(f, page)
  local RO, g, me = ns.RollOff, D:Current(), ns.Self()
  local ro, id = RO:Current(g)
  local foot = {}
  -- Starting one opens beside the window (SPEC decision 52).
  local function startForm(label)
    if D:Can("games") then foot[#foot + 1] = { label, function() page.View({ kind = "newrolloff" }) end } end
  end
  if not ro then
    f:Text("about", L.RO_ABOUT)
    if D:Can("games") then startForm(L.RO_START_DOTS) else f:Empty("none", L.RO_NONE, L.RO_NONE_ASK) end
  else
    local hostName = ns.Display(ro.h)
    f:Strip("title", L.RO_TITLE:format(ro.max or 0, UI.Who(ro.h)))
    if ro.st == "done" then
      if (ro.amt or 0) > 0 then
        local hiV, loV = ro.r[ro.hi] or 0, ro.r[ro.lo] or 0
        f:Text("result", L.RO_RESULT:format(UI.Who(ro.hi), hiV, UI.Who(ro.lo), loV, UI.Who(ro.lo), UI.Who(ro.hi),
          money(ro.amt, ro.p)), "GameFontNormal")
      else
        f:Text("result", L.RO_RESULT_NONE)
      end
      startForm(L.RO_NEW_DOTS)
    else
      local rolled = {}
      for _, r in ipairs(RO:Rolls(ro)) do rolled[r.name] = r.v end
      local joined = RO:Joined(ro)
      if #joined == 0 then
        f:Empty("nobody", L.RO_NOBODY, ro.st == "open" and L.RO_NOBODY_DO:format(UI.Key(L.RO_JOIN)) or nil)
      end
      for i, name in ipairs(joined) do
        f:Row("j" .. i, { icon = UI.ICON.dice, name = UI.Who(name), value = rolled[name] and tostring(rolled[name]) or nil,
          dim = ro.st == "rolling" and rolled[name] == nil })
      end
      if ro.st == "open" and not ro.j[me] then
        local close = near(ro.h)
        if not close then f:Text("far", L.NEAR_HOST:format(hostName), "GameFontNormal") end
        foot[#foot + 1] = { L.RO_JOIN, function() RO:Join(id) end, off = not close }
      end
      if ro.st == "rolling" and ro.j[me] and ro.r[me] == nil then
        foot[#foot + 1] = { L.RO_ROLL:format(ro.max), function() ns.Dice:Roll(ro.max) end, next = true }
      end
      if ro.h == me and ro.st == "open" then foot[#foot + 1] = { L.RO_GO, function() RO:Go(id) end } end
      if ro.h == me and ro.st == "rolling" then foot[#foot + 1] = { L.RO_FINISH, function() RO:Finish(id) end } end
      if ro.st == "open" and ro.h ~= me and ro.j[me] then f:Text("wait", L.RO_WAIT_GO:format(hostName), "GameFontDisableSmall") end
      if ro.st == "rolling" and ro.r[me] ~= nil and ro.h ~= me then f:Text("rolled", L.RO_ROLLED, "GameFontDisableSmall") end
    end
  end
  return foot
end

---------------------------------------------------------------------------
-- Right: raffles, and starting one
---------------------------------------------------------------------------
local function raffles(f, page)
  local RA, g, me = ns.Raffle, D:Current(), ns.Self()
  local list = RA:List(g)
  if #list == 0 then
    f:Empty("none", L.RA_NONE, D:Can("games") and L.RA_NONE_DO:format(UI.Key(L.RA_NEW_DOTS)) or L.RA_NONE_ASK)
  end
  for i, item in ipairs(list) do
    local ra, id = item.ra, item.id
    local k = "r" .. i
    local tickets, sold = RA:Tickets(ra)
    local mine = 0
    for _, e in ipairs(tickets) do if e[1] == me then mine = e[2] end end
    if ra.st == "done" then
      f:Row(k, { icon = UI.ICON.ticket, name = ra.prize or "", dim = true,
        sub = L.RA_WINNER:format(UI.Who(ra.w), ra.roll or 0, ra.sold or 0) })
    else
      f:Row(k, { icon = UI.ICON.ticket, name = ra.prize or "", sub = raffleHead(ra, sold):gsub("^.- · ", ""),
        value = money(ra.price or 0, ra.p), vsub = mine > 0 and (L.RA_YOURS .. " " .. mine) or L.RA_TICKET })
      if ra.when then f:Pair(k .. "when", L.RA_DRAW_AT, ra.when) end
      local buttons = {}
      if (ra.max or 0) == 0 or sold < ra.max then
        local close = near(ra.h)
        if not close then f:Text(k .. "far", L.NEAR_TICKET:format(ns.Display(ra.h)), "GameFontDisableSmall") end
        buttons[#buttons + 1] = { L.RA_BUY, function() RA:Buy(id, 1) end, off = not close }
      end
      if ra.h == me and sold > 0 then buttons[#buttons + 1] = { L.RA_DRAW, function() RA:Draw(id) end } end
      if #buttons > 0 then f:Buttons(k .. "act", buttons) else f:Text(k .. "out", L.RA_SOLD_OUT, "GameFontDisableSmall") end
    end
  end
  f:Text("note", L.RA_NOTE, "GameFontDisableSmall")
  if D:Can("games") then return { { L.RA_NEW_DOTS, function() page.View({ kind = "newraffle" }) end } } end
  return {}
end

---------------------------------------------------------------------------
-- The features' status and red number, on the left
---------------------------------------------------------------------------
local status = {
  deathroll = function()
    local game = ns.Deathroll:Game()
    if not game then return L.FEAT_NOTHING end
    return L.FEAT_DR_VS:format(ns.Short(game.opp), money(game.amt, game.p))
  end,
  rolloff = function()
    local ro = ns.RollOff:Current(D:Current())
    if ro and ro.st == "done" and ro.hi then return L.FEAT_LAST_WON:format(ns.Short(ro.hi)) end
    if not ro or ro.st == "done" then return L.FEAT_NOTHING end
    return L.FEAT_RO_ON:format(ro.max or 0)
  end,
  raffles = function()
    local n = 0
    for _, x in ipairs(ns.Raffle:List(D:Current())) do if x.ra.st ~= "done" then n = n + 1 end end
    return n > 0 and L.FEAT_OPEN:format(n) or L.FEAT_NOTHING
  end,
}
local count = {
  deathroll = function()
    local DR = ns.Deathroll
    local game = DR:Game()
    if not game then return 0 end
    if game.st == "incoming" then return 1 end
    return (game.st ~= "asked" and game.st ~= "over" and DR:Turn() == "me") and 1 or 0
  end,
  rolloff = function()
    local ro = ns.RollOff:Current(D:Current())
    local me = ns.Self()
    return (ro and ro.st == "rolling" and ro.j[me] and ro.r[me] == nil) and 1 or 0
  end,
}

local function raffleForm(f, page)
  local RA = ns.Raffle
  if not D:Can("games") then return nil end
  local purse = D:Settings().purse
  f:Strip("title", L.RA_NEW)
  local prize = f:Field("prize", L.RA_F_PRIZE, f.width - 10)
  prize:SetMaxLetters(RA.PRIZE_MAX)
  local third = math.floor((f.width - 16) / 3)
  local price = f:Field("price", L.RA_F_PRICE:format(unit(purse)), third - 10, nil, true)
  local max = f:Field("rmax", L.RA_F_MAX, third - 10, third + 8, true)
  local when = f:Field("when", L.RA_F_WHEN, third - 10, 2 * (third + 8))
  when:SetMaxLetters(RA.WHEN_MAX)
  if (max:GetText() or "") == "" then max:SetText("0") end
  f:Text("hint", L.RA_F_HINT, "GameFontDisableSmall")
  return { { L.RA_NEW, function()
    local p, n = num(price), num(max) or 0
    local text = RA.Clean(prize:GetText(), RA.PRIZE_MAX)
    if not text or not Pu.ValidAmount(p, purse) or n < 0 or not RA:Start(text, p, n, when:GetText()) then
      ns:Print(L.RA_BAD, true)
      return
    end
    prize:SetText("")
    price:SetText("")
    when:SetText("")
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

-- Starting a roll-off, beside the window: the number to roll to.
local function rollOffForm(f, page)
  local RO = ns.RollOff
  if not D:Can("games") then return nil end
  f:Text("about", L.RO_ABOUT)
  local box = f:Field("max", L.RO_MAX, 80)
  if (box:GetText() or "") == "" then box:SetText("100") end
  return { { L.RO_START, function()
    local max = num(box)
    if not max or max < 2 or max > RO.MAX_MAX or max ~= math.floor(max) or not RO:Start(max) then
      ns:Print(L.RO_BAD, true)
      return
    end
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

-- The side window (UI/Side.lua): the deathroll in hand, as a ladder going down, with the deathroll picked; the high
-- roll and the lottery's draw as their scenes (UI/Scenes.lua, SPEC decision 60).
local function side(page)
  local g = D:Current()
  if page.part == "rolloff" then
    local ro, id = ns.RollOff:Current(g)
    if not ro or #ns.RollOff:Joined(ro) == 0 then return nil end
    return { key = "ro:" .. id, icon = UI.ICON.dice, title = L.TV_ROLLOFF, sub = L.RO_TITLE:format(ro.max or 0, UI.Who(ro.h)),
      draw = function(f) ns.Scenes.HighRoll(f, ro, id) end }
  elseif page.part == "raffles" then
    local pick
    for _, x in ipairs(ns.Raffle:List(g)) do
      if x.ra.st ~= "done" or (x.ra.td and time() - x.ra.td <= UI.Stage.RECENT) then pick = x end
    end
    if not pick then return nil end
    return { key = "ra:" .. pick.id, icon = UI.ICON.ticket, title = pick.ra.prize or L.TV_RAFFLES,
      sub = raffleHead(pick.ra, select(2, ns.Raffle:Tickets(pick.ra))),
      draw = function(f) ns.Scenes.Lottery(f, pick.ra, pick.id) end }
  end
  if page.part ~= "deathroll" then return nil end
  local game = ns.Deathroll:Game()
  if not game or (game.st ~= "playing" and game.st ~= "over") then return nil end
  return { key = "dr:" .. game.id, icon = UI.ICON.skull, title = L.TV_DEATHROLL,
    sub = L.SIDE_DR_SUB:format(ns.Display(game.opp), money(game.amt, game.p), game.s),
    draw = function(f)
      ns.Scenes.Deathroll(f, game)
      local rolls = {}
      for i, r in ipairs(game.rolls) do
        rolls[i] = { v = r.v, mine = r.who == "me", who = r.who == "me" and L.DR_YOU or ns.Short(game.opp) }
      end
      f:Ladder("ladder", game.s, rolls)
      if game.st == "over" then
        f:Text("result", game.loser == "me" and L.DR_LOST_YOU:format(ns.Display(game.opp), money(game.amt, game.p))
          or L.DR_LOST_THEM:format(ns.Display(game.opp), money(game.amt, game.p)), "GameFontNormal")
      end
    end }
end

-- What waits for you here (SPEC decision 47): a deathroll to answer or your roll, your roll in a roll-off.
local function todo()
  local out, me = {}, ns.Self()
  local DR, RO = ns.Deathroll, ns.RollOff
  local game = DR:Game()
  if game and game.st == "incoming" then
    out[#out + 1] = L.TODO_DR_ANSWER:format(ns.Display(game.opp))
  elseif game and game.st ~= "asked" and game.st ~= "over" and DR:Turn() == "me" then
    out[#out + 1] = L.TODO_DR_ROLL:format(ns.Display(game.opp))
  end
  local ro = RO:Current(D:Current())
  if ro and ro.st == "rolling" and ro.j[me] and ro.r[me] == nil then out[#out + 1] = L.TODO_RO_ROLL end
  return out
end

-- Going on now, for Home: the roll-off and the raffles that are open.
local function now()
  local out, g = {}, D:Current()
  local ro = ns.RollOff:Current(g)
  if ro and ro.st ~= "done" then
    out[#out + 1] = { icon = UI.ICON.dice, name = L.NOW_ROLLOFF, sub = L.NOW_ROLLOFF_SUB:format(ns.Display(ro.h)),
      t = ro.t, pick = "rolloff" }
  end
  for _, x in ipairs(ns.Raffle:List(g)) do
    if x.ra.st ~= "done" then
      out[#out + 1] = { icon = UI.ICON.ticket, name = x.ra.prize, sub = L.NOW_RAFFLE_SUB, t = x.ra.t, pick = "raffles" }
    end
  end
  return out
end

Hall:Register({
  id = "tavern", label = L.PAGE_TAVERN, sub = L.PAGE_TAVERN_SUB,
  side = side,
  todo = todo,
  now = now,
  help = L.NEAR_RULE .. "\n\n" .. L.DR_NOTE .. "\n\n" .. L.RA_NOTE,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "deathroll", L.TV_DEATHROLL, icon = UI.ICON.skull },
        { "rolloff", L.TV_ROLLOFF, icon = UI.ICON.dice }, { "raffles", L.TV_RAFFLES, icon = UI.ICON.ticket } },
      parts = { deathroll = deathroll, rolloff = rolloff, raffles = raffles },
      views = { challenge = challenge, newraffle = raffleForm, newrolloff = rollOffForm },
      status = status, count = count,
      save = "tavernTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})

ns:On("TAVERN", function() if Hall.current == "tavern" then Hall:Refresh() end end)
-- Our roll asked for, and given up on (Guild/Dice.lua): the deathroll's die rattles meanwhile.
ns:On("DICE", function() if Hall.current == "tavern" then Hall:Refresh() end end)
