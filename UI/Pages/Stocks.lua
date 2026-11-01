-- Punishments (SPEC §6, decisions 48 and 56): playful punishments, for players with Guild Together but the Guild Master.
-- Three features: now serving (a click shows the sentence beside the window, with tomatoes, bids and pardons; the
-- Clown Hat), what is yours (your sentence, a verdict to give, a tribute to judge, a servant's orders), and the menu (who may give
-- each one, its bail, and where the stocks stand). Hand out... (ranks that may) opens its form beside the window.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local P, St, Pn = ns.Players, ns.Stocks, ns.Punish

local SERVING_SHOWN = 15
local function num(box) return tonumber(strtrim(box:GetText() or "")) end
local function name(key) return P:Name(key) end
local function who(key)
  local main = P:Main(key)
  return main and UI.Who(main) or P:Name(key)
end
local function punName(pun) return L["ACT_" .. pun:upper()] end
local function punIcon(pun) return UI.ICON["p_" .. pun] or UI.ICON.question end
local function bail(pun) local amt = St.Bail(pun, D:Settings().purse) return amt and Pu:Format(Pu.Units(amt, D:Settings().purse), D:Settings().purse) end

-- "12 min", "3 h", "a day".
local function left(sec)
  sec = math.max(0, math.floor(sec or 0))
  if sec >= 2 * 3600 then return L.ST_HOURS:format(math.floor(sec / 3600)) end
  return L.ST_MIN:format(math.max(1, math.ceil(sec / 60)))
end
ns.Stocks.Left = left

-- One line on what a sentence is doing now.
function ns.Stocks.Describe(s)
  local se = s.se
  if s.st == "spin" then return L.ST_WAIT_SPIN end
  if s.st == "trial" then return L.ST_WAIT_TRIAL:format(name(P:Of(se.by)), name(s.key)) end
  if s.st == "tribute" then return L.ST_WAIT_TRIBUTE end
  if s.pun == "stocks" then return L.ST_LEFT:format(left(s.left and (s.left - math.max(0, Pn.Served(s) - (s.served or 0))) or 0)) end
  if s.pun == "service" then return L.ST_FISH:format(s.n or 0, se.q or St.QUOTA) end
  if s.pun == "walk" then
    local nextZone = se.z and se.z[(s.i or 0) + 1]
    return nextZone and L.ST_WALK_NEXT:format(nextZone, (s.i or 0) + 1, #se.z) or ""
  end
  if s.pun == "servant" then
    if s.auction then return L.ST_AUCTION:format(left(s.left)) end
    return L.ST_SERVES:format(name(P:Of(s.master)), left(s.left))
  end
  if s.idol then return L.ST_IDOL end
  return L.ST_LEFT:format(left(s.left))
end

-- A trial by combat this player won, still without a verdict: the sentence and the loser, or nil.
local function verdictDue(g)
  local me = P:Of(ns.Self(), g)
  for _, s in ipairs(St.List(g)) do
    if s.st == "done" and s.how == "trial" and s.winner and P:Of(s.winner, g) == me then
      local given = false
      for _, o in pairs(g.sentences or {}) do if o.tr == s.id then given = true end end
      if not given then
        local accuser = P:Of(s.se.by, g)
        return s, accuser == me and s.se.to or s.se.by
      end
    end
  end
  return nil
end

-- The orders of a servant's master, oldest first: { { key, text, done }, ... }.
local function orders(s)
  local g, list = D:Current(), {}
  local master = s.se.hire and P:Of(s.se.hire.by, g)
  for key, o in pairs(s.se.orders or {}) do
    if master and P:Of(o.by, g) == master then list[#list + 1] = { key = key, text = o.text, t = o.t, done = s.se.odone and s.se.odone[key] ~= nil } end
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)
  return list
end

local function mayHandOut(page)
  if page.verdict then return true end
  for _, pun in ipairs(D.PUNISHMENTS) do if D:Can(pun) then return true end end
  return false
end

---------------------------------------------------------------------------
-- Now serving, and the Dunce Cap
---------------------------------------------------------------------------
local function serving(f, page)
  local g = D:Current()
  local open = {}
  for _, s in ipairs(g and St.List(g) or {}) do if St.Open(s) then open[#open + 1] = s end end
  f:Strip("now", L.ST_NOW, #open > 0 and tostring(#open) or nil)
  if #open == 0 then
    f:Empty("none", L.ST_NOBODY, mayHandOut(page) and L.ST_NOBODY_DO:format(UI.Key(L.ST_FORM_DOTS)) or nil)
  end
  local view = page.view and page.view.kind == "sentence" and page.view.id
  for i, s in ipairs(open) do
    if i > SERVING_SHOWN then break end
    f:Row("s" .. i, { icon = punIcon(s.pun), name = who(s.key), sub = St.Describe(s), value = punName(s.pun),
      vsub = L.ST_BY:format(name(P:Of(s.se.by, g))), sel = view == s.id,
      onClick = function() page.View({ kind = "sentence", id = s.id }) end })
  end
  local dunce = g and St.Dunce(g)
  f:Strip("dunce", L.ACT_DUNCE, dunce and who(dunce) or L.ST_NOBODY_SHORT)
  local foot = {}
  if mayHandOut(page) then
    foot[1] = { page.verdict and L.ST_VERDICT_GO or L.ST_FORM_DOTS, function() page.View({ kind = "form" }) end }
  end
  return foot
end

-- A sentence from the list, and what others can do about it.
local DONE_MARK = "|T" .. UI.Visuals.TEX.check .. ":12|t "
local function sentenceView(f, page)
  local g = D:Current()
  local s
  for _, x in ipairs(g and St.List(g) or {}) do
    -- One that just ended stays a while, for its scene (a pardon, bail: SPEC decision 60), without its buttons.
    if x.id == page.view.id and (St.Open(x) or (x.ends and time() - x.ends <= UI.Stage.RECENT)) then s = x end
  end
  if not s then return nil end
  local me = P:Of(ns.Self(), g)
  ns.Scenes.Sentence(f, g, s)
  f:Text("state", St.Describe(s), "GameFontNormalLarge")
  if s.se.why then f:Pair("reason", L.ST_WHY_SAID, "\"" .. s.se.why .. "\"") end
  f:Pair("by", L.ST_GIVEN_BY, who(P:Of(s.se.by, g)))
  if s.pun == "stocks" then
    local list, total = {}, 0
    for thrower, n in pairs(s.se.tom or {}) do
      list[#list + 1] = { name = thrower, v = n, text = L.ST_TOMATOES:format(n), me = thrower == ns.Self() }
      total = total + n
    end
    table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.name < b.name end)
    f:Strip("throwers", L.SIDE_THROWERS, L.ST_TOMATOES:format(total))
    if #list == 0 then f:Empty("notom", L.SIDE_NO_TOMATOES) else f:Bars("bars", list, punIcon("stocks")) end
  elseif s.pun == "service" then
    local q = s.se.q or St.QUOTA
    f:Strip("quota", L.SIDE_QUOTA)
    f:Bar("quotaBar", (s.n or 0) / q, L.ST_FISH:format(s.n or 0, q))
  elseif s.pun == "servant" and not s.auction then
    local list = orders(s)
    f:Strip("orders", L.SIDE_ORDERS:format(name(P:Of(s.master))))
    if #list == 0 then f:Empty("noorders", L.SIDE_NO_ORDERS) end
    for i, o in ipairs(list) do f:Text("o" .. i, (o.done and DONE_MARK or "") .. o.text) end
  end
  local amt = bail(s.pun)
  if amt then f:Pair("bail", L.SIDE_BAIL, amt) end
  if s.pun == "servant" and s.auction then
    f:Text("bid", s.master and L.ST_HIGH_BID:format(name(P:Of(s.master)), Pu:Format(Pu.Units(s.price, D:Settings().purse), D:Settings().purse))
      or L.ST_NO_BID, "GameFontDisableSmall")
  end
  f:Text("about", L["ACT_" .. s.pun:upper() .. "_DESC"], "GameFontDisableSmall")
  if not St.Open(s) then return {} end
  local acts = {}
  if s.pun == "stocks" and s.st == "active" and s.key ~= me then
    acts[#acts + 1] = { L.ST_TOMATO, function()
      local last = page.thrown and page.thrown[s.id]
      if last and GetTime() - last < 20 then ns:Print(L.ST_TOMATO_WAIT, true) return end
      page.thrown = page.thrown or {}
      page.thrown[s.id] = GetTime()
      St.Tomato(s.id)
    end }
  end
  if s.st == "spin" and D:Can("spin") then acts[#acts + 1] = { L.ST_SPIN, function() St.Spin(s.id) end } end
  if s.pun == "servant" and s.auction and s.key ~= me then
    acts[#acts + 1] = { L.ST_BID, function()
      local offer = (s.price or 0) + 1
      if not St.Bid(s.id, offer) then ns:Print(L.ST_BAD, true) end
    end }
  end
  if s.idol and s.key ~= me then acts[#acts + 1] = { L.ST_DEED, function() St.Deed(s.id) end } end
  if D:Can("pardon") and s.key ~= me then acts[#acts + 1] = { L.ST_PARDON, function() St.Pardon(s.id) end } end
  return acts
end

---------------------------------------------------------------------------
-- What is yours
---------------------------------------------------------------------------
local function yours(f, page)
  local g = D:Current()
  local me = g and P:Of(ns.Self(), g)
  local mine = g and St.Of(g, me) or {}
  local verdict, loser = page.verdict and page.verdict.id, page.verdict and page.verdict.to
  local master = {}
  for _, s in ipairs(g and St.List(g) or {}) do
    if s.pun == "servant" and s.st == "active" and not s.auction and s.master and P:Of(s.master, g) == me then master[#master + 1] = s end
  end
  local tribute = Pn.tribute
  local foot = {}
  if #mine == 0 and not verdict and #master == 0 and not tribute then
    f:Empty("none", L.ST_NOTHING_YOURS, L.ST_NOTHING_YOURS_ABOUT)
    return foot
  end
  for i, s in ipairs(mine) do
    local k = "m" .. i
    f:Row(k .. "r", { icon = punIcon(s.pun), name = L.ST_YOU_IN:format(punName(s.pun)), sub = St.Describe(s), sel = true })
    if s.se.why then f:Pair(k .. "why", L.ST_WHY_SAID, "\"" .. s.se.why .. "\"") end
    if s.pun == "stocks" and s.st == "active" and Pn.at == false then
      local spot = Pn.Spot(s)
      f:Text(k .. "go", L.ST_GO_BACK:format(spot and spot.z or "?"), "GameFontRedSmall")
    end
    if s.st == "active" and St.Bail(s.se.pun, D:Settings().purse) then
      foot[#foot + 1] = { (s.pun == "radio" and L.ST_BUYOUT or L.ST_BAIL):format(bail(s.se.pun)), function() St.PayBail(s) end }
    end
    if s.se.pun == "wheel" and s.spun and not s.se.reroll and s.st == "active" then
      foot[#foot + 1] = { L.ST_REROLL:format(bail("wheel")), function() St.Reroll(s) end }
    end
    if s.st == "active" and s.se.pun ~= "trial" and not s.se.tr then
      foot[#foot + 1] = { L.ST_DEMAND, function()
        Hall:Confirm(L.ST_DEMAND_ASK:format(name(P:Of(s.se.by, g))), L.ST_DEMAND, function() St.Trial(s.id) end)
      end }
    end
    if s.pun == "servant" and not s.auction then
      for j, o in ipairs(orders(s)) do
        f:Line(k .. "o" .. j, o.text, not o.done and L.ST_DONE or nil, function() St.OrderDone(s.id, o.key) end, o.done and L.ST_ORDER_DONE or nil)
      end
    end
  end
  if verdict then
    f:Row("verdict", { icon = punIcon("trial"), name = L.ST_VERDICT_TITLE, sub = L.ST_VERDICT:format(ns.Display(loser)),
      onClick = function() page.View({ kind = "form" }) end })
    foot[#foot + 1] = { L.ST_VERDICT_GO, function() page.View({ kind = "form" }) end }
  end
  if tribute then
    f:Text("tribt", L.ST_TRIBUTE:format(ns.Display(tribute.from), tribute.item or "?"))
    f:Buttons("tribb", {
      { L.ST_ACCEPT, function() St.Tribute(tribute.id, true, tribute.item); Pn.tribute = nil end },
      { L.ST_SCORN, function() St.Tribute(tribute.id, false, tribute.item); Pn.tribute = nil end },
    })
  end
  for i, s in ipairs(master) do
    f:Row("ms" .. i, { icon = punIcon("servant"), name = who(s.key), sub = L.ST_MASTER:format(name(s.key), left(s.left)) })
    if not s.se.hire then
      f:Buttons("hire" .. i, { { L.ST_HIRE:format(Pu:Format(Pu.Units(s.price, D:Settings().purse), D:Settings().purse)),
        function() St.Hire(s) end } })
    else
      local box = f:Field("ord" .. i, L.ST_ORDER, f.width - 10)
      box:SetMaxLetters(St.ORDER_MAX)
      f:Buttons("ordb" .. i, { { L.ST_GIVE_ORDER, function()
        if St.Order(s.id, box:GetText()) then box:SetText("") end
      end } })
      for j, o in ipairs(orders(s)) do
        f:Text("mo" .. i .. "." .. j, (o.done and "|cff9d9d9d" or "") .. o.text .. (o.done and "|r" or ""), "GameFontHighlightSmall")
      end
    end
  end
  return foot
end

---------------------------------------------------------------------------
-- Beside the window: handing out a punishment (or the verdict after a trial by combat)
---------------------------------------------------------------------------
local function form(f, page)
  local g = D:Current()
  local verdict = page.verdict
  local allowed = {}
  for _, pun in ipairs(D.PUNISHMENTS) do
    if (verdict or D:Can(pun)) and D:On("p:" .. pun) then allowed[#allowed + 1] = pun end
  end
  if #allowed == 0 then return nil end
  f:Strip("title", verdict and L.ST_VERDICT_TITLE or L.ST_FORM)
  -- Why (SPEC decision 69): unpaid tax, or an incident (to the court, or judged directly). A trial's verdict has none.
  local Ru = ns.Rules
  local reasons = {}
  if not verdict then
    if Ru.TaxPunishments(g) then reasons[#reasons + 1] = { "tax", L.ST_WHY_TAX } end
    reasons[#reasons + 1] = { "inc", L.ST_WHY_INC }
    local ok = false
    for _, r in ipairs(reasons) do if r[1] == page.reason then ok = true end end
    if not ok then page.reason = reasons[1][1] end
    f:Dropdown("reason", L.ST_WHY_LABEL, reasons, page.reason, function(v) page.reason = v; Hall:Refresh() end)
    if page.reason == "inc" and Ru.Court(g) then
      f:Text("court", L.ST_TO_COURT_NOTE)
      return { { L.ST_TO_COURT, function()
        Hall:ShowFeature("council", "court")
        local def = Hall.pages.council
        if def and def.frame then def.frame.View({ kind = "charge" }) end
      end }, { L.CANCEL, function() page.View(nil) end } }
    end
    if page.reason == "tax" then
      local owing = {}
      for _, x in ipairs(ns.Treasury.Liable(g)) do
        if #Ru.TaxOwed(g, x.key) > 0 then owing[#owing + 1] = ns.Display(x.name) end
      end
      f:Text("owing", #owing > 0 and L.ST_OWING:format(table.concat(owing, ", ")) or L.ST_OWING_NONE, "GameFontDisableSmall")
    end
  end
  page.pick = page.pick and math.min(page.pick, #allowed) or 1
  local pun = allowed[page.pick]
  local half = math.floor((f.width - 12) / 2)
  local whoBox = f:Field("who", L.ST_WHO, half - 10, nil, true)
  local mins = f:Field("min", L.ST_MINUTES, half - 10, half + 12)
  if verdict then whoBox:SetText(ns.Display(verdict.to)) end
  if (mins:GetText() or "") == "" then mins:SetText("30") end
  local choices = {}
  for i, p in ipairs(allowed) do
    local b = bail(p)
    choices[i] = { i, b and L.ST_PUN_BAIL:format(punName(p), b) or punName(p) }
  end
  f:Dropdown("pun", L.ST_PUN_LABEL, choices, page.pick, function(v) page.pick = v; Hall:Refresh() end)
  f:Text("desc", L["ACT_" .. pun:upper() .. "_DESC"], "GameFontDisableSmall")
  local extra = {}
  local zones, quota
  -- The Wheel takes a route and a quota too, in case it lands there (without a route it never lands on the Walk).
  if pun == "walk" or pun == "wheel" then
    zones = f:Field("zones", pun == "wheel" and L.ST_ZONES_WHEEL or L.ST_ZONES, f.width - 10)
    zones:SetMaxLetters(St.ZONES_MAX * (St.ZONE_LEN + 2))
  end
  if pun == "service" or pun == "wheel" then
    quota = f:Field("quota", L.ST_QUOTA, 80)
    if (quota:GetText() or "") == "" then quota:SetText(tostring(St.QUOTA)) end
  elseif pun == "curse" then
    page.curse = page.curse or 1
    local curses = {}
    for i, x in ipairs(St.CURSES) do curses[i] = { i, L["ST_CURSE_" .. x:upper()] } end
    f:Dropdown("curse", L.ST_CURSE_LABEL, curses, page.curse, function(v) page.curse = v; Hall:Refresh() end)
  end
  local why = f:Field("why", L.ST_REASON, f.width - 10)
  why:SetMaxLetters(St.WHY_MAX)
  return { { L.ST_SENTENCE, function()
    local text = strtrim(whoBox:GetText() or "")
    local full = verdict and verdict.to or (text ~= "" and ns.FullName(text) or nil)
    if not full or ns.Roster:Rank(full) == nil then ns:Print(L.ST_WHO_BAD, true) return end
    local key = P:Of(full, g)
    if not St.Punishable(g, key) then ns:Print(L.ST_NOT_PUNISHABLE:format(ns.Display(full)), true) return end
    if Ru.OptedOut(g, key) then ns:Print(L.ST_OPTED_OUT:format(ns.Display(full)), true) return end
    if not verdict and page.reason == "tax" then
      local owed = Ru.TaxOwed(g, key)[1]
      if not owed then ns:Print(L.ST_NO_TAX:format(ns.Display(full)), true) return end
      extra.r, extra.tx = "tax", owed.key
    elseif not verdict then
      extra.r = "inc"
    end
    if zones then
      extra.z = {}
      for z in (zones:GetText() or ""):gmatch("[^,]+") do
        z = strtrim(z)
        if z ~= "" and #extra.z < St.ZONES_MAX then extra.z[#extra.z + 1] = z end
      end
      if #extra.z == 0 and pun == "wheel" then extra.z = nil end
    end
    if quota then extra.q = num(quota) end
    if pun == "curse" then extra.c = St.CURSES[page.curse or 1] end
    if (pun == "stocks" or pun == "wheel") and not D:Settings().spot then extra.sp = Pn.Here() end
    if verdict then extra.tr = verdict.id end
    if not St.Sentence(full, pun, St.TIMED[pun] and num(mins) or nil, why:GetText(), extra) then ns:Print(L.ST_BAD, true) return end
    why:SetText("")
    if not verdict then whoBox:SetText("") end
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- The menu, and where the stocks stand
---------------------------------------------------------------------------
local function spot(f)
  local s = D:Settings().spot
  f:Strip("where", L.ST_SPOT)
  f:Text("at", s and L.ST_SPOT_AT:format(s.z or "?") or L.ST_SPOT_NONE)
  if not D:InCharge() then return {} end
  return { { L.ST_SPOT_SET, function()
    local here = Pn.Here()
    if not here then ns:Print(L.ST_SPOT_BAD, true) return end
    ns.Sync:ChangeSettings(function(set) set.spot = here end)
  end } }
end

-- How punishments work (SPEC decision 69): the rules in force, written from the settings, for every member.
local function rules(f, gg)
  local text = ns.Rules.Text(gg)
  for i, part in ipairs(text) do
    f:Strip("rh" .. i, part.head)
    for j, line in ipairs(part.lines) do f:Text("r" .. i .. "." .. j, "- " .. line) end
  end
  if text.changed then f:Text("rchanged", L.RU_CHANGED:format(ns.TimeAgo(text.changed)), "GameFontDisableSmall") end
end
Hall.PunishmentRules = rules

local function menu(f)
  rules(f, D:Current())
  f:Strip("menuHead", L.ST_MENU)
  local ranks = ns.Roster:Ranks()
  for i, pun in ipairs(D.PUNISHMENTS) do
    local list, may = { L.ST_GM }, D:Ranks(pun)
    for _, rank in ipairs(ranks) do if may[rank.index] then list[#list + 1] = rank.name end end
    if D:On("p:" .. pun) then
      f:Row("p" .. i, { icon = punIcon(pun), name = punName(pun), sub = table.concat(list, ", "), value = bail(pun),
        tip = { punName(pun), L["ACT_" .. pun:upper() .. "_DESC"] } })
    end
  end
  f:Text("note", L.ST_MENU_NOTE, "GameFontDisableSmall")
  return spot(f)
end

---------------------------------------------------------------------------
-- The features' status and red number, on the left; the sentence's heading beside the window
---------------------------------------------------------------------------
local function openList(g)
  local out = {}
  for _, s in ipairs(g and St.List(g) or {}) do if St.Open(s) then out[#out + 1] = s end end
  return out
end

local status = {
  serving = function()
    local n = #openList(D:Current())
    return n > 0 and L.FEAT_SERVING:format(n) or L.FEAT_NOTHING
  end,
  yours = function()
    local g = D:Current()
    local n = g and #St.Of(g, P:Of(ns.Self(), g)) or 0
    return n > 0 and L.FEAT_SERVING_YOU or L.FEAT_NOTHING
  end,
}
local count = {
  -- What waits for an officer: a Wheel to spin, for the ranks that may.
  serving = function()
    if not D:Can("spin") then return 0 end
    local n = 0
    for _, s in ipairs(openList(D:Current())) do if s.st == "spin" then n = n + 1 end end
    return n
  end,
  yours = function(page)
    local g = D:Current()
    local n = g and #St.Of(g, P:Of(ns.Self(), g)) or 0
    if page.verdict then n = n + 1 end
    if Pn.tribute then n = n + 1 end
    return n
  end,
}

local function sentenceHead(page)
  local g = D:Current()
  for _, s in ipairs(openList(g)) do
    if s.id == page.view.id then
      return punIcon(s.pun), punName(s.pun), L.SIDE_SENTENCED:format(P:Name(s.key), name(P:Of(s.se.by, g)))
    end
  end
end

-- What waits for you here (SPEC decision 47): the sentences you serve.
local function todo()
  local g, out = D:Current(), {}
  if not g then return out end
  for _, s in ipairs(St.Of(g, P:Of(ns.Self(), g))) do out[#out + 1] = L.TODO_SENTENCE:format(punName(s.pun)) end
  return out
end

-- Going on now, for Home: who is serving a punishment.
local function now()
  local out, g = {}, D:Current()
  for _, s in ipairs(g and St.List(g) or {}) do
    if St.Open(s) then
      out[#out + 1] = { icon = punIcon(s.pun), name = who(s.key), sub = L.NOW_STOCKS_SUB:format(punName(s.pun)),
        t = s.start, view = { kind = "sentence", id = s.id } }
    end
  end
  return out
end

Hall:Register({
  id = "stocks", label = L.PAGE_STOCKS, sub = L.PAGE_STOCKS_SUB,
  todo = todo,
  now = now,
  help = L.ST_MENU_NOTE,
  status = function()
    local g = D:Current()
    local dunce = g and St.Dunce(g)
    return dunce and (UI.Inline(punIcon("dunce")) .. " " .. who(dunce)) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "serving", L.ST_NOW, icon = UI.ICON.shackles }, { "yours", L.ST_TAB_YOURS, icon = UI.ICON.wanted },
        { "menu", L.ST_MENU, icon = UI.ICON.basket } },
      parts = { serving = serving, yours = yours, menu = menu },
      views = { sentence = sentenceView, form = form },
      heads = { sentence = sentenceHead },
      status = status, count = count,
      save = "stocksTab",
    })
    page.orders = orders
  end,
  refresh = function(page)
    local g = D:Current()
    local verdict, loser = nil, nil
    if g then verdict, loser = verdictDue(g) end
    page.verdict = verdict and { id = verdict.id, to = loser } or nil
    Hall:DrawRight(page)
  end,
})

ns:On("STOCKS", function() if Hall.current == "stocks" then Hall:Refresh() end end)
