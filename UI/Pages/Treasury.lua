-- The Treasury (SPEC §8, decision 48). Five features: the guild tax and the open debts in gold, the long ledger (G7),
-- the Patrons, item requests and the Marks (SPEC §3.2). A click on a debt or a request shows it beside the window with
-- what can be done (Pay by trade for the one who owes, Mark paid for the one owed, Approve for the ranks that may, Mail
-- it for what the Treasury owes); the forms (ask the vault, record a payment, give or take Marks) open there too.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local P, Tx = ns.Players, ns.Treasury

local WHY = { deathroll = "WHY_DEATHROLL", rolloff = "WHY_ROLLOFF", raffle = "WHY_RAFFLE", wager = "WHY_WAGER", cup = "WHY_CUP",
  bail = "WHY_BAIL", servant = "WHY_SERVANT", game = "WHY_GAME", tax = "WHY_TAX", craft = "WHY_CRAFT" }
local WHY_ICON = { deathroll = "skull", rolloff = "dice", raffle = "ticket", wager = "duel", cup = "prize", bail = "shackles",
  servant = "p_servant", game = "rosette", tax = "purse", craft = "parcel" }
local DEBTS_SHOWN, PATRONS_SHOWN, REQUESTS_SHOWN, LEDGER_SHOWN, MARKS_SHOWN = 30, 8, 20, 30, 40

-- A player (or the Treasury) as the game shows names: in class colour.
local function who(key)
  if key == Pu.TREASURY then return L.TREASURY end
  local main = P:Main(key)
  return main and UI.Who(main) or P:Name(key)
end
local function gold(copper) return UI.Money(copper, "gold") end
local function red(text) return "|cffff6040" .. text .. "|r" end
local function quiet(text) return "|cff9d9d9d" .. text .. "|r" end

local function itemIcon(item)
  local fn = C_Item and C_Item.GetItemIconByID
  local icon = fn and item and fn(item)
  -- 134400 is the question mark the game shows for an item it has not loaded.
  return (icon and icon ~= 134400) and icon or UI.ICON.bag
end

-- Reads a name and a whole number from two boxes; nil when either is wrong.
local function nameAndCount(nameBox, countBox, max)
  local n = tonumber(strtrim(countBox:GetText() or ""))
  local target = strtrim(nameBox:GetText() or "")
  local full = target ~= "" and ns.FullName(target) or nil
  if not full or ns.Roster:Rank(full) == nil or not n or n < 1 or n ~= math.floor(n) or (max and n > max) then return nil end
  return full, n
end

---------------------------------------------------------------------------
-- Open debts: what can be done with each, and by whom
---------------------------------------------------------------------------
local function debtActions(d)
  local list = {}
  if P:IsMe(d.to) or (d.to == Pu.TREASURY and D:InCharge()) then
    list[#list + 1] = { L.TR_MARK_PAID, function() UI.Sound("pay") Pu:MarkPaid(d.f, d.to) end }
  elseif d.f == Pu.TREASURY and D:InCharge() then
    -- A prize the Treasury owes: mailed from the mailbox with one press, or marked paid when given by hand.
    if Tx.atMailbox then list[#list + 1] = { L.TS_MAIL_IT, function() UI.Sound("pay") Tx.MailGold(d.to, d.amt) end } end
    list[#list + 1] = { L.TR_MARK_PAID, function() UI.Sound("pay") Pu:MarkPaid(d.f, d.to) end }
  elseif P:IsMe(d.f) and d.to ~= Pu.TREASURY then
    list[#list + 1] = { L.TR_PAY, function() ns.Payments:Trade(d.to) end, next = true }
  end
  return list
end

local function debtRow(d, sel, onClick)
  local why = d.w and WHY[d.w] and L[WHY[d.w]] or nil
  local acts = debtActions(d)
  return {
    icon = UI.ICON[WHY_ICON[d.w] or "coin"], name = L.TR_OWES:format(who(d.f), who(d.to)),
    sub = why and (why .. " · " .. ns.TimeAgo(d.t or time())) or ns.TimeAgo(d.t or time()),
    value = gold(d.amt), vsub = acts[1] and acts[1][1] or nil, sel = sel, onClick = onClick,
  }
end

local function findDebt(key)
  local g = D:Current()
  for _, d in ipairs(g and Pu:Open(g) or {}) do if d.key == key then return d end end
end

---------------------------------------------------------------------------
-- The guild tax and the debts
---------------------------------------------------------------------------
local function debts(f, page)
  local g = D:Current()
  local t = D:Settings().tax
  local foot = {}
  if not g or not t.on then
    f:Strip("tax", L.TS_TAX)
    f:Text("off", L.TS_TAX_OFF, "GameFontDisableSmall")
  else
    local s = Tx.Status(g)
    f:Strip("tax", L.TS_TAX_TITLE:format(s.name), L.TS_LEVEL:format(t.lv) .. ", " .. (t.per == "week" and L.TS_WEEKLY or L.TS_MONTHLY))
    if s.run then
      f:Bar("paid", s.n > 0 and s.paid / s.n or 1, L.TS_PAID:format(s.paid, s.n))
    else
      f:Text("paid", L.TS_NOT_YET, "GameFontDisableSmall")
    end
    if s.mine then
      f:Pair("mine", L.TS_YOURS:format(s.mine), s.myLeft > 0 and L.TS_OWE:format(gold(s.myLeft)) or L.TS_PAID_YOU, s.myLeft > 0)
    end
    local pills = {}
    if s.overdue > 0 then pills[#pills + 1] = red(L.TS_OVERDUE:format(s.overdue)) end
    if s.exempt > 0 then pills[#pills + 1] = quiet(L.TS_EXEMPT:format(s.exempt)) end
    if #pills > 0 then f:Text("pills", table.concat(pills, "   ")) end
    if D:InCharge() and not s.run then foot[#foot + 1] = { L.TS_CHARGE, function() Tx.Charge() end } end
  end
  if D:InCharge() then foot[#foot + 1] = { L.TS_NEW_PAY, function() page.View({ kind = "record" }) end } end

  local open = g and Pu:Open(g) or {}
  f:Strip("debts", L.TR_DEBTS, #open > 0 and tostring(#open) or nil)
  if #open == 0 then f:Empty("none", L.TR_NO_DEBTS, L.TR_NO_DEBTS_ABOUT) end
  local owesTreasury = false
  for i, d in ipairs(open) do
    if P:IsMe(d.f) and d.to == Pu.TREASURY then owesTreasury = true end
    if i <= DEBTS_SHOWN then
      local sel = page.view and page.view.kind == "debt" and page.view.key == d.key
      f:Row("d" .. i, debtRow(d, sel, function() page.View({ kind = "debt", key = d.key }) end))
    end
  end
  if owesTreasury then f:Text("officer", L.TR_PAY_OFFICER, "GameFontHighlightSmall") end
  if #foot == 0 and #open > 0 then f:Text("pick", L.TR_PICK, "GameFontDisableSmall") end
  return foot
end

---------------------------------------------------------------------------
-- The ledger, the Patrons, item requests and the Marks
---------------------------------------------------------------------------
local function ledger(f)
  local g = D:Current()
  local lines = g and Tx.Ledger(g) or {}
  -- Prizes the Treasury paid, from the purse, in time with the vault's lines.
  local list = {}
  for _, x in ipairs(lines) do list[#list + 1] = { t = x.h * 3600, x = x } end
  for _, e in pairs(g and g.pays or {}) do
    if e.f == Pu.TREASURY then list[#list + 1] = { t = e.t, pay = e } end
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  if #list == 0 then f:Empty("none", L.TS_NO_LEDGER) end
  for i, it in ipairs(list) do
    if i > LEDGER_SHOWN then break end
    local row = { sub = ns.TimeAgo(it.t) }
    if it.pay then
      row.icon, row.name, row.value = UI.ICON.prize, L.TS_LOG_PRIZE:format(UI.Who(it.pay.to)), red("-" .. gold(it.pay.amt))
    else
      local x = it.x
      local what = L["TS_LOG_" .. (x.type or ""):upper()] or x.type or "?"
      local name = x.name and UI.Who(x.name) or L.TREASURY
      if x.kind == "m" then
        local out = x.type ~= "deposit"
        row.icon = out and UI.ICON.coin or UI.ICON.coins
        row.name = L.TS_LOG_LINE:format(name, what) .. (x.c > 1 and (" ×" .. x.c) or "")
        row.value = out and red("-" .. gold(x.amount * x.c)) or gold(x.amount * x.c)
      else
        row.icon = itemIcon(x.id)
        row.name = L.TS_LOG_ITEM:format(name, what, x.nm or "?", x.count * x.c)
      end
    end
    f:Row("l" .. i, row)
  end
  f:Text("note", L.TS_LEDGER_NOTE:format(#lines, g and Tx.Visits(g) or 0), "GameFontDisableSmall")
  return {}
end

local function patrons(f)
  local g = D:Current()
  local list = g and Tx.Patrons(g) or {}
  local shown = 0
  for i, e in ipairs(list) do
    if e.month <= 0 or i > PATRONS_SHOWN then break end
    shown = shown + 1
    f:Row("m" .. i, { icon = i == 1 and UI.ICON.chalice or UI.ICON.coins, name = who(e.key), value = gold(e.month),
      vsub = i == 1 and L.TAG_PATRON or nil })
  end
  if shown == 0 then f:Empty("none", L.TS_NO_PATRONS, L.TS_NO_PATRONS_DO) end
  -- All time: the biggest givers ever.
  local ever = {}
  for _, e in ipairs(list) do ever[#ever + 1] = e end
  table.sort(ever, function(a, b) if a.ever ~= b.ever then return a.ever > b.ever end return a.key < b.key end)
  if #ever > 0 then
    f:Strip("ever", L.TS_EVER)
    for i, e in ipairs(ever) do
      if i > PATRONS_SHOWN then break end
      f:Row("e" .. i, { icon = UI.ICON.coin, name = who(e.key), value = gold(e.ever) })
    end
  end
  f:Text("note", L.TS_PATRON_NOTE, "GameFontDisableSmall")
  return {}
end

local function requestRow(s, sel, onClick)
  local rq = s.rq
  local state = L["TS_REQ_" .. s.st:upper()]
  return { icon = itemIcon(rq.item), name = rq.item .. " ×" .. rq.n, sub = UI.Who(rq.by) .. " · " .. ns.TimeAgo(rq.t),
    value = s.st == "open" and state or quiet(state), sel = sel, onClick = onClick, dim = s.st == "denied" or s.st == "dropped" }
end

local function requests(f, page)
  local g = D:Current()
  local shown = 0
  for i, s in ipairs(g and Tx.Requests(g) or {}) do
    if shown >= REQUESTS_SHOWN then break end
    local mine = P:IsMe(P:Of(s.rq.by))
    -- Answered requests of others fade after a week.
    if s.st == "open" or s.st == "approved" or mine or time() - s.rq.t < 7 * 86400 then
      shown = shown + 1
      f:Row("r" .. i, requestRow(s, false, function() page.View({ kind = "request", id = s.id }) end))
    end
  end
  if shown == 0 then f:Empty("none", L.TS_NO_REQ, L.TS_NO_REQ_DO:format(UI.Key(L.TS_NEW_REQ))) end
  f:Text("note", L.TS_REQ_NOTE, "GameFontDisableSmall")
  return { { L.TS_NEW_REQ, function() page.View({ kind = "ask" }) end } }
end

local function marks(f, page)
  local g = D:Current()
  local s = D:Settings()
  local list = g and Pu:Balances(g) or {}
  if #list == 0 then
    f:Empty("none", L.TR_NO_MARKS:format(s.many), D:Can("grant") and L.TR_NO_MARKS_DO:format(UI.Key(L.TR_NEW_GRANT)) or nil)
  end
  for i, e in ipairs(list) do
    if i > MARKS_SHOWN then break end
    local amt = Pu:Format(e.amt, "marks", s)
    f:Row("m" .. i, { icon = UI.ICON.marks, name = who(e.key), value = e.amt < 0 and red(amt) or amt, dim = e.amt < 0 })
  end
  f:Text("note", L.TR_MARKS_NOTE, "GameFontDisableSmall")
  if D:Can("grant") then return { { L.TR_NEW_GRANT, function() page.View({ kind = "grant" }) end } } end
  return {}
end

---------------------------------------------------------------------------
-- Beside the window: a debt or a request, and the forms
---------------------------------------------------------------------------
local function back(page) return { L.CANCEL, function() page.View(nil) end } end

local function debtView(f, page)
  local d = findDebt(page.view.key)
  if not d then page.view = nil return nil end
  f:Row("hero", debtRow(d, true))
  local why = d.w and WHY[d.w] and L[WHY[d.w]] or nil
  if why then f:Pair("for", L.TR_FOR, why) end
  f:Pair("since", L.TR_SINCE, ns.TimeAgo(d.t or time()))
  if P:IsMe(d.f) and d.to == Pu.TREASURY then f:Text("officer", L.TR_PAY_OFFICER) end
  f:Text("note", L.TR_DEBTS_NOTE, "GameFontDisableSmall")
  local acts = debtActions(d)
  acts[#acts + 1] = back(page)
  return acts
end

local function requestView(f, page)
  local g = D:Current()
  local s
  for _, x in ipairs(g and Tx.Requests(g) or {}) do if x.id == page.view.id then s = x end end
  if not s then page.view = nil return nil end
  local rq = s.rq
  f:Row("hero", requestRow(s, true))
  f:Text("line", L.TS_REQ_LINE:format(rq.item, rq.n, UI.Who(rq.by)))
  if rq.why then f:Pair("reason", L.TS_WHY, rq.why) end
  local acts, note = {}, nil
  local approver, mine = D:Can("items"), P:IsMe(P:Of(rq.by))
  if s.st == "open" and approver then
    acts[#acts + 1] = { L.TS_APPROVE, function() Tx.Answer(s.id, true) end }
    acts[#acts + 1] = { L.TS_DENY, function() Tx.Answer(s.id, false) end }
  end
  if s.st == "approved" and approver then
    if Tx.atMailbox then acts[#acts + 1] = { L.TS_MAIL_IT, function() Tx.MailItem(s.id) end }
    else note = L.TS_AT_MAILBOX end
  end
  if (s.st == "open" or s.st == "approved") and mine then
    acts[#acts + 1] = { L.TS_TAKE_BACK, function() Tx.Drop(s.id) end }
  end
  if note then f:Text("mailbox", note, "GameFontDisableSmall") end
  f:Text("note", L.TS_REQ_NOTE, "GameFontDisableSmall")
  acts[#acts + 1] = back(page)
  return acts
end

local function askForm(f, page)
  f:Strip("title", L.TS_ASK)
  local w = f.width
  local item = f:Field("item", L.TS_ITEM, w - 70, nil, true)
  item:SetMaxLetters(255)
  local n = f:Field("n", L.TS_COUNT, 50, w - 56)
  if not n.filled then n:SetText("1") n.filled = true end
  local why = f:Field("why", L.TS_WHY, w - 12)
  why:SetMaxLetters(Tx.WHY_MAX)
  f:Text("note", L.TS_REQ_NOTE, "GameFontDisableSmall")
  return { { L.TS_ASK, function()
    local count = tonumber(strtrim(n:GetText() or ""))
    if not Tx.Ask(strtrim(item:GetText() or ""), count, strtrim(why:GetText() or "")) then
      ns:Print(L.TS_ASK_BAD, true)
      return
    end
    item:SetText("")
    why:SetText("")
    page.View(nil)
  end }, back(page) }
end

local function recordForm(f, page)
  f:Strip("title", L.TS_RECORD)
  local w = f.width
  local name = f:Field("pwho", L.TR_GRANT_WHO, w - 90, nil, true)
  local amt = f:Field("pamt", L.TS_AMT_GOLD, 64, w - 70)
  f:Text("note", L.TS_TAX_NOTE, "GameFontDisableSmall")
  return { { L.TS_RECORD, function()
    -- A payment by hand: gold given to me (or to the vault while nobody looked).
    local full, n = nameAndCount(name, amt, Pu.GOLD_MAX)
    if not full then ns:Print(L.TR_GRANT_BAD, true) return end
    ns.Sync:Do({ k = "pay", f = full, to = Pu.TREASURY, amt = n * Pu.GOLD, how = "hand" })
    amt:SetText("")
    page.View(nil)
  end }, back(page) }
end

local function grantForm(f, page)
  f:Strip("title", D:Settings().many)
  local w = f.width
  local name = f:Field("gwho", L.TR_GRANT_WHO, w - 90, nil, true)
  local amt = f:Field("gamt", L.TR_GRANT_AMT, 64, w - 70)
  f:Text("note", L.TR_MARKS_NOTE, "GameFontDisableSmall")
  local function grant(sign)
    local full, n = nameAndCount(name, amt)
    if not full or not Pu:Grant(full, sign * n) then ns:Print(L.TR_GRANT_BAD, true) return end
    amt:SetText("")
  end
  return { { L.TR_GRANT, function() grant(1) end }, { L.TR_TAKE, function() grant(-1) end }, back(page) }
end

-- What waits for you here (SPEC decision 47): what you owe.
local function todo()
  local g, out = D:Current(), {}
  if not g then return out end
  for _, d in ipairs(Pu:Open(g)) do
    if P:IsMe(d.f) then out[#out + 1] = L.TODO_DEBT:format(gold(d.amt), who(d.to)) end
  end
  return out
end

---------------------------------------------------------------------------
-- The features' status and red number, on the left
---------------------------------------------------------------------------
local function openRequests(g)
  local n = 0
  for _, s in ipairs(g and Tx.Requests(g) or {}) do if s.st == "open" then n = n + 1 end end
  return n
end

local status = {
  debts = function()
    local g, t = D:Current(), D:Settings().tax
    if g and t.on then
      local s = Tx.Status(g)
      if s.run then return L.TS_PAID:format(s.paid, s.n) end
    end
    local n = g and #Pu:Open(g) or 0
    return n > 0 and L.FEAT_DEBTS:format(n) or L.FEAT_NO_DEBTS
  end,
  patrons = function()
    local g = D:Current()
    local top = g and Tx.Patron(g)
    return top and ns.Short(P:Name(top)) or L.FEAT_NOTHING
  end,
  req = function()
    local n = openRequests(D:Current())
    return n > 0 and L.FEAT_OPEN:format(n) or L.FEAT_NOTHING
  end,
}
local count = {
  debts = function()
    local g, n = D:Current(), 0
    for _, d in ipairs(g and Pu:Open(g) or {}) do if P:IsMe(d.f) then n = n + 1 end end
    return n
  end,
  -- What waits for an officer: open requests, for the ranks that may approve them.
  req = function() return D:Can("items") and openRequests(D:Current()) or 0 end,
}

-- At a glance, with nothing picked (UI/Side.lua): this period's tax and your part of it, and this month's top givers.
local function glance(_, _, f)
  local g = D:Current()
  if not g then return false end
  local drew = false
  if g.settings.tax.on then
    local s = Tx.Status(g)
    f:Strip("gtax", L.GL_TAX:format(s.name))
    f:Bar("gtaxbar", s.n > 0 and s.paid / s.n or 0, L.GL_TAX_PAID:format(s.paid, s.n))
    if s.mine then
      f:Text("gtaxme", (s.myLeft or 0) > 0 and L.GL_TAX_YOU_OWE:format(gold(s.myLeft)) or L.GL_TAX_YOU_PAID)
    end
    drew = true
  end
  local top = {}
  for _, e in ipairs(Tx.Patrons(g)) do if e.month > 0 and #top < 3 then top[#top + 1] = e end end
  if #top > 0 then
    f:Strip("gtop", L.GL_TOP_GIVERS)
    for i, e in ipairs(top) do f:Pair("gtop" .. i, who(e.key), gold(e.month)) end
    drew = true
  end
  return drew
end

Hall:Register({
  id = "treasury", label = L.PAGE_TREASURY, sub = L.PAGE_TREASURY_SUB,
  todo = todo,
  glance = glance,
  help = L.TR_DEBTS_NOTE .. "\n\n" .. L.TS_TAX_NOTE,
  status = function()
    local g = D:Current()
    local top = g and Tx.Patron(g)
    return top and L.TS_PATRON_NOW:format(who(top)) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "debts", L.TS_TAX_DEBTS, icon = UI.ICON.purse }, { "ledger", L.TS_TAB_LEDGER, icon = UI.ICON.quill },
        { "patrons", L.TS_PATRONS, icon = UI.ICON.chalice }, { "req", L.TS_TAB_REQ, icon = UI.ICON.vault },
        { "marks", function() return D:Settings().many end, icon = UI.ICON.marks,
          on = function() return D:Settings().purse == "marks" end } },
      parts = { debts = debts, ledger = ledger, patrons = patrons, req = requests, marks = marks },
      views = { debt = debtView, request = requestView, ask = askForm, record = recordForm, grant = grantForm },
      status = status, count = count,
      save = "treasuryTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})
