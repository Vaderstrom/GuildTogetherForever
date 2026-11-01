-- The Treasury (SPEC §8): the guild tax, the long ledger from vault visits, Patrons, item requests, and paying out.
--   tax_run   { per, d = { { name, amt } } }   a rank that may record tax payments charges a period's tax (gold per
--                                     player); the first run of a period wins. Unpaid tax adds up (decided 29 Oct
--                                     2026): each line is a debt to the Treasury, paid like any other (Guild/Purse.lua)
--   vault     { l = { { s, h, c, nm } } }   lines of the vault's log a member saw that the guild's ledger lacked:
--                                     s, what happened ("m|deposit|Name-Realm|copper", "i|withdraw|Name-Realm|item id|
--                                     count|tab"); h, the hour (time / 3600) it happened; c, how many such lines
--                                     that hour; nm, the item's name. A line seen by a rank that may record tax
--                                     payments is confirmed (ok): only confirmed gold pays tax (SPEC §8)
--   req       { item, iid, n, why }   a member asks for an item from the vault (its name, and its id when known)
--   req_ans   { id, ok }              a rank that may approve item requests says yes or no
--   req_sent  { id }                  the approver's addon: the item is mailed
--   req_drop  { id }                  the member takes the request back
-- Gold put in the vault pays its giver's tax and other debts to the Treasury made before it. Patrons (decided 29 Oct
-- 2026): the members who gave the Treasury the most gold, this month and ever; this month's first is tagged [Patron].
local _, ns = ...
local L, D, R, P, Pu = ns.L, ns.GuildData, ns.Roster, ns.Players, ns.Purse
local Clean = ns.Raffle.Clean

local Tx = {}
ns.Treasury = Tx

Tx.WEEK, Tx.MONDAY = 7 * 86400, 4 * 86400   -- 1 January 1970 was a Thursday: weeks start on Mondays
Tx.LINES_OP = 25        -- ledger lines in one op
Tx.LEDGER_MAX = 4000    -- lines kept; the oldest go first
Tx.ITEM_MAX, Tx.WHY_MAX, Tx.COUNT_MAX = 80, 80, 1000
Tx.ATTACH_MAX = 12      -- the game's letter holds 12 items
Tx.TICK = 60

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- An event that may not exist in this client (the game refuses to register one it does not know).
local function listen(event, fn)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
  ns:RegisterEvent(event, fn)
end

---------------------------------------------------------------------------
-- The guild tax
---------------------------------------------------------------------------
-- The period a time falls in: "2026-11" for a month, "w2965" for a week (counted from 5 January 1970, a Monday).
function Tx.Period(per, t)
  if per == "week" then return "w" .. math.floor((t - Tx.MONDAY) / Tx.WEEK) end
  return date("!%Y-%m", t)
end

-- The period's name on the page: "November", "the week of 26 Oct".
function Tx.PeriodName(id)
  local w = id:match("^w(%d+)$")
  if w then return L.TS_WEEK_OF:format(date("!%d %b", Tx.MONDAY + tonumber(w) * Tx.WEEK)) end
  local m = tonumber(id:match("^%d+%-(%d+)$"))
  return m and L["TS_MONTH_" .. m] or id
end

-- Who owes tax now, by the Guild Master's settings and the roster: { { name, amt (gold), key } }, one per player with
-- Guild Together (their best rank, their highest level; let off when any of their characters is). A member without the
-- addon owes nothing: nothing keeps score of them (SPEC decision 56).
function Tx.Liable(g)
  local tax = (g and g.settings or D:Settings()).tax
  local per = {}
  for name, rank in pairs(R:All()) do
    local key = P:Of(name, g)
    local e = per[key] or { key = key, rank = 99, lv = 0 }
    if rank < e.rank then e.rank, e.name = rank, name end
    e.lv = math.max(e.lv, R:Level(name) or 0)
    if tax.ex[name] or tax.ex[Ambiguate(name, "short")] then e.ex = true end
    per[key] = e
  end
  local list = {}
  for _, e in pairs(per) do
    local amt = tax.amt[e.rank]
    -- (A player who opted out of punishment owes no tax from then on: SPEC decision 69.)
    if amt and not e.ex and e.lv >= tax.lv and P:HasAddon(e.key) and not (ns.Rules and ns.Rules.OptedOut(g, e.key)) then
      list[#list + 1] = { name = e.name, amt = amt, key = e.key }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function soundRun(op)
  if type(op.per) ~= "string" or #op.per > 12 or type(op.d) ~= "table" or #op.d > 1000 then return false end
  for _, x in ipairs(op.d) do
    if type(x) ~= "table" or not party(x[1]) or not whole(x[2], 1, D.TAX_MAX) then return false end
  end
  return true
end

D:Register("tax_run", {
  -- (Not before the guild's setup is picked: only the regular features work then, SPEC decision 70.)
  allowed = function(g, author, op) return soundRun(op) and D:InCharge(author, g) and ns.Rules.Setup(g) ~= nil end,
  apply = function(g, author, op, t, n)
    local runs = D.Part(g, "taxRuns")
    runs[op.per] = runs[op.per] or {}
    local d = {}
    for i, x in ipairs(op.d) do d[i] = { x[1], tonumber(x[2]) } end
    runs[op.per][D.Key(author, n)] = { a = author, t = t, d = d }
    return true
  end,
  -- The whole Treasury travels with the tax's part.
  copy = function(g) return { runs = g.taxRuns, vault = g.vault, req = g.requests } end,
  merge = function(g, part) Tx.Merge(g, part) end,
})

-- The run that counts for each period (the first made; a tie by key): { [per] = { key, a, t, d } }.
function Tx.Runs(g)
  local out = {}
  for per, runs in pairs(g and g.taxRuns or {}) do
    for key, r in pairs(runs) do
      local cur = out[per]
      if not cur or r.t < cur.t or (r.t == cur.t and key < cur.key) then out[per] = { key = key, a = r.a, t = r.t, d = r.d } end
    end
  end
  return out
end

-- The tax as debts to the Treasury, for the purse.
Pu.extraDebts[#Pu.extraDebts + 1] = function(g)
  local list = {}
  for per, r in pairs(Tx.Runs(g)) do
    for i, x in ipairs(r.d) do
      list[#list + 1] = { key = r.key .. ":" .. i, f = x[1], to = Pu.TREASURY, amt = x[2] * Pu.GOLD, w = "tax", t = r.t, per = per }
    end
  end
  return list
end

-- This period's tax: { per, name (of the period), run, n (players charged), paid (players with nothing left of it),
-- overdue (players who still owe an earlier period's), mine (gold, or nil), myLeft (copper) }.
function Tx.Status(g, now)
  now = now or time()
  local tax = g.settings.tax
  local per = Tx.Period(tax.per, now)
  local runs = Tx.Runs(g)
  local s = { per = per, name = Tx.PeriodName(per), run = runs[per], n = 0, paid = 0, overdue = 0, exempt = 0 }
  for name in pairs(tax.ex) do if R:All()[name] then s.exempt = s.exempt + 1 end end
  local left, old = {}, {}
  for _, d in ipairs(Pu:Open(g)) do
    if d.w == "tax" and d.to == Pu.TREASURY then
      if s.run and d.key:sub(1, #s.run.key + 1) == s.run.key .. ":" then left[d.f] = (left[d.f] or 0) + d.amt
      else old[d.f] = true end
    end
  end
  local me = P:Of(ns.Self(), g)
  if s.run then
    for _, x in ipairs(s.run.d) do
      local key = P:Of(x[1], g)
      s.n = s.n + 1
      if not left[key] then s.paid = s.paid + 1 end
      if key == me then s.mine, s.myLeft = x[2], left[key] or 0 end
    end
  end
  for _ in pairs(old) do s.overdue = s.overdue + 1 end
  s.myOld = old[me] == true
  return s
end

-- Charges this period's tax, when it is on and nobody has yet (the Guild Master's addon, decision 50).
function Tx.Charge(now)
  local g = D:Current()
  now = now or time()
  if not g or not g.settings.tax.on or not D:InCharge() or not R:Ready() or ns.Rules.Setup(g) == nil then return false end
  local per = Tx.Period(g.settings.tax.per, now)
  if g.taxRuns and g.taxRuns[per] and next(g.taxRuns[per]) then return false end
  local d = {}
  for _, x in ipairs(Tx.Liable(g)) do d[#d + 1] = { x.name, x.amt } end
  if #d == 0 then return false end
  return ns.Sync:Do({ k = "tax_run", per = per, d = d })
end

---------------------------------------------------------------------------
-- The long ledger
---------------------------------------------------------------------------
local function ledger(g) return D.Part(g, "vault") end

-- The line kept for s at hour h, or one an hour either side (two visits may round the same line apart).
local function find(store, s, h)
  return store[s .. "@" .. h] or store[s .. "@" .. (h - 1)] or store[s .. "@" .. (h + 1)]
end

local function soundLine(x)
  return type(x) == "table" and type(x.s) == "string" and #x.s <= 160 and x.s:match("^[mi]|") ~= nil
    and whole(x.h, 0, 2 ^ 31) and whole(x.c, 1, 1000) and (x.nm == nil or type(x.nm) == "string")
end

-- Puts lines into the ledger: a line already there keeps the larger count. ok: the lines are confirmed (seen by a
-- rank that may record tax payments); lineOk: each line says itself (a whole copy). Returns how many changed.
local function put(store, lines, ok, lineOk)
  local changed = 0
  for _, x in ipairs(lines) do
    if soundLine(x) then
      local e = find(store, x.s, x.h)
      local sure = ok or (lineOk and x.ok == true)
      if not e then
        store[x.s .. "@" .. x.h] = { s = x.s, h = x.h, c = x.c, nm = x.nm and Clean(x.nm, 60), ok = sure or nil }
        changed = changed + 1
      else
        if x.c > e.c then e.c, changed = x.c, changed + 1 end
        if sure and not e.ok then e.ok, changed = true, changed + 1 end
      end
    end
  end
  return changed
end

-- Keeps the newest Tx.LEDGER_MAX lines.
local function trim(store)
  local list = {}
  for k, e in pairs(store) do list[#list + 1] = { k = k, h = e.h } end
  if #list <= Tx.LEDGER_MAX then return end
  table.sort(list, function(a, b) if a.h ~= b.h then return a.h > b.h end return a.k < b.k end)
  for i = Tx.LEDGER_MAX + 1, #list do store[list[i].k] = nil end
end

D:Register("vault", {
  allowed = function(_, _, op)
    if type(op.l) ~= "table" or #op.l < 1 or #op.l > Tx.LINES_OP * 2 then return false end
    for _, x in ipairs(op.l) do if not soundLine(x) then return false end end
    return true
  end,
  apply = function(g, author, op, t)
    -- Any member's visit confirms what it saw (decision 50).
    local n = put(ledger(g), op.l, true)
    local v = D.Part(g, "visits")
    v[author] = math.max(v[author] or 0, t)
    trim(ledger(g))
    return n > 0
  end,
})

-- What a visit saw that the ledger lacks (or holds fewer of, or has not had confirmed): the lines to send.
function Tx.Missing(g, lines)
  local store, out = ledger(g), {}
  for _, x in ipairs(lines) do
    local e = find(store, x.s, x.h)
    if not e or x.c > e.c or not e.ok then out[#out + 1] = x end
  end
  return out
end

-- Lines from the vault's log (as the game gives them) to ledger lines: each counted per kind and hour.
-- raw = { { kind = "m"|"i", type, name, amount | id, count, tab, nm, ago (hours) } }
function Tx.Lines(raw, now)
  local hour = math.floor((now or time()) / 3600)
  local by, list = {}, {}
  for _, r in ipairs(raw) do
    local s
    if r.kind == "m" then s = ("m|%s|%s|%d"):format(r.type, r.name or "", r.amount or 0)
    else s = ("i|%s|%s|%d|%d|%d"):format(r.type, r.name or "", r.id or 0, r.count or 1, r.tab or 0) end
    local h = hour - (r.ago or 0)
    local k = s .. "@" .. h
    if by[k] then by[k].c = by[k].c + 1
    else
      by[k] = { s = s, h = h, c = 1, nm = r.nm }
      list[#list + 1] = by[k]
    end
  end
  return list
end

-- A visit to the vault: what the log shows, sent to the guild in parts where the ledger lacks it.
function Tx.Visit(raw, now)
  local g = D:Current()
  if not g then return 0 end
  local missing = Tx.Missing(g, Tx.Lines(raw, now))
  for i = 1, #missing, Tx.LINES_OP do
    local part = {}
    for j = i, math.min(i + Tx.LINES_OP - 1, #missing) do part[#part + 1] = missing[j] end
    ns.Sync:Do({ k = "vault", l = part })
  end
  return #missing
end

-- The ledger, newest first: { { kind, type, name, amount, id, count, tab, nm, h, c } }.
function Tx.Ledger(g)
  local list = {}
  for _, e in pairs(g and g.vault or {}) do
    local parts = { strsplit("|", e.s) }
    local x = { kind = parts[1], type = parts[2], name = parts[3] ~= "" and parts[3] or nil, h = e.h, c = e.c, nm = e.nm,
      ok = e.ok }
    if x.kind == "m" then x.amount = tonumber(parts[4]) or 0
    else x.id, x.count, x.tab = tonumber(parts[4]), tonumber(parts[5]) or 1, tonumber(parts[6]) end
    list[#list + 1] = x
  end
  table.sort(list, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    return (a.name or "") < (b.name or "")
  end)
  return list
end

-- Gold put in the vault (confirmed) pays its giver's debts to the Treasury made before it.
local function deposits(g)
  local list = {}
  for _, e in pairs(g and g.vault or {}) do
    local kind, typ, name, amt = strsplit("|", e.s)
    if e.ok and kind == "m" and typ == "deposit" and name and name ~= "" then
      list[#list + 1] = { f = name, to = Pu.TREASURY, amt = (tonumber(amt) or 0) * e.c, t = e.h * 3600 + 3599 }
    end
  end
  return list
end
Pu.timedPays[#Pu.timedPays + 1] = deposits

-- How many members' visits the ledger is made of.
function Tx.Visits(g)
  local n = 0
  for _ in pairs(g and g.visits or {}) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- Patrons
---------------------------------------------------------------------------
-- Gold given to the Treasury per player (copper): this month, and ever. { { key, month, ever } }, this month's most
-- first.
function Tx.Patrons(g, now)
  now = now or time()
  local month = date("!%Y-%m", now)
  local per = {}
  local function add(name, amt, t)
    local key = P:Of(name, g)
    local e = per[key] or { key = key, month = 0, ever = 0 }
    e.ever = e.ever + amt
    if date("!%Y-%m", t) == month then e.month = e.month + amt end
    per[key] = e
  end
  for _, d in ipairs(deposits(g)) do add(d.f, d.amt, d.t) end
  for _, e in pairs(g and g.pays or {}) do if e.to == Pu.TREASURY and party(e.f) then add(e.f, e.amt, e.t) end end
  local list = {}
  for _, e in pairs(per) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if a.month ~= b.month then return a.month > b.month end
    if a.ever ~= b.ever then return a.ever > b.ever end
    return a.key < b.key
  end)
  return list
end

-- This month's Patron: the player who gave the most (at least a gold piece), else nil.
function Tx.Patron(g, now)
  local top = Tx.Patrons(g, now)[1]
  return top and top.month >= Pu.GOLD and top.key or nil
end

---------------------------------------------------------------------------
-- Item requests
---------------------------------------------------------------------------
local function request(g, id)
  local all = D.Part(g, "requests")
  all[id] = all[id] or {}
  return all[id]
end

local function soundReq(op)
  return Clean(op.item, Tx.ITEM_MAX) ~= nil and whole(op.n, 1, Tx.COUNT_MAX) and (op.why == nil or type(op.why) == "string")
    and (op.iid == nil or whole(op.iid, 1, 2 ^ 31))
end

local function takeReq(rq, author, op, t)
  rq.by, rq.t, rq.item, rq.n, rq.why = author, t, Clean(op.item, Tx.ITEM_MAX), tonumber(op.n), Clean(op.why, Tx.WHY_MAX)
  rq.iid = tonumber(op.iid)
end

D:Register("req", {
  allowed = function(_, _, op) return soundReq(op) end,
  apply = function(g, author, op, t, n)
    takeReq(request(g, D.Key(author, n)), author, op, t)
    return true
  end,
})

D:Register("req_ans", {
  allowed = function(g, author, op) return host(op.id) ~= nil and type(op.ok) == "boolean" and D:Can("items", author, g) end,
  apply = function(g, author, op, t)
    local rq = request(g, op.id)
    if rq.ans and rq.ans.t <= t then return false end
    rq.ans = { ok = op.ok, by = author, t = t }
    return true
  end,
})

D:Register("req_sent", {
  allowed = function(g, author, op) return host(op.id) ~= nil and D:Can("items", author, g) end,
  apply = function(g, author, op, t)
    local rq = request(g, op.id)
    if rq.sent and rq.sent.t <= t then return false end
    rq.sent = { by = author, t = t }
    return true
  end,
})

D:Register("req_drop", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local rq = request(g, op.id)
    if rq.drop and rq.drop <= t then return false end
    rq.drop = t
    return true
  end,
})

-- A request as it stands: st "open", "approved", "denied", "sent", "dropped".
function Tx.Request(g, id)
  local rq = g.requests and g.requests[id]
  if not rq or not rq.by then return nil end
  local s = { id = id, rq = rq }
  if rq.sent then s.st = "sent"
  elseif rq.drop then s.st = "dropped"
  elseif rq.ans then s.st = rq.ans.ok and "approved" or "denied"
  else s.st = "open" end
  return s
end

-- Requests: open and approved first, then the newest.
local ORDER = { approved = 1, open = 2, sent = 3, denied = 3, dropped = 4 }
function Tx.Requests(g)
  local list = {}
  for id in pairs(g and g.requests or {}) do
    local s = Tx.Request(g, id)
    if s then list[#list + 1] = s end
  end
  table.sort(list, function(a, b)
    if ORDER[a.st] ~= ORDER[b.st] then return ORDER[a.st] < ORDER[b.st] end
    if a.rq.t ~= b.rq.t then return a.rq.t > b.rq.t end
    return a.id > b.id
  end)
  return list
end

---------------------------------------------------------------------------
-- A whole copy
---------------------------------------------------------------------------
function Tx.Merge(g, part)
  if type(part) ~= "table" then return end
  for per, runs in pairs(type(part.runs) == "table" and part.runs or {}) do
    if type(per) == "string" and type(runs) == "table" then
      local mine = D.Part(g, "taxRuns")
      mine[per] = mine[per] or {}
      for key, r in pairs(runs) do
        if type(key) == "string" and host(key) and type(r) == "table" and party(r.a) and tonumber(r.t)
          and soundRun({ per = per, d = r.d }) and not mine[per][key] then
          mine[per][key] = { a = r.a, t = r.t, d = r.d }
        end
      end
    end
  end
  if type(part.vault) == "table" then
    local lines = {}
    for _, e in pairs(part.vault) do lines[#lines + 1] = e end
    put(ledger(g), lines, false, true)
    trim(ledger(g))
  end
  for id, e in pairs(type(part.req) == "table" and part.req or {}) do
    if type(id) == "string" and host(id) and type(e) == "table" then
      local rq = request(g, id)
      if not rq.by and party(e.by) and tonumber(e.t) and soundReq(e) then takeReq(rq, e.by, e, e.t) end
      for _, f in ipairs({ "ans", "sent" }) do
        local x = e[f]
        if type(x) == "table" and tonumber(x.t) and party(x.by) and (not rq[f] or x.t < rq[f].t) then
          rq[f] = { ok = f == "ans" and x.ok == true or nil, by = x.by, t = x.t }
        end
      end
      if tonumber(e.drop) and (not rq.drop or e.drop < rq.drop) then rq.drop = e.drop end
    end
  end
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function sync(op) return ns.Sync:Do(op) end

-- item: a name, or an item link (shift-click): its name and id are kept.
function Tx.Ask(item, n, why)
  local iid = tonumber((item or ""):match("|Hitem:(%d+)"))
  local name = Clean((item or ""):match("|h%[(.-)%]|h") or item, Tx.ITEM_MAX)
  if not name or not whole(n, 1, Tx.COUNT_MAX) then return false end
  return sync({ k = "req", item = name, iid = iid, n = n, why = Clean(why, Tx.WHY_MAX) })
end
function Tx.Answer(id, ok) return sync({ k = "req_ans", id = id, ok = ok and true or false }) end
function Tx.Drop(id) return sync({ k = "req_drop", id = id }) end

---------------------------------------------------------------------------
-- At the mailbox: the item or a prize mailed with one press (the press is the game's hardware event for SendMail).
-- Never from the self-test's pretend guild: a pretend name could be a real player's.
---------------------------------------------------------------------------
Tx.atMailbox = false

local function itemId(text)
  return tonumber((text or ""):match("item:(%d+)"))
end

local function itemName(text)
  return (text or ""):match("%[(.-)%]") or text
end

-- Where the requested item (by id when known, else by name) is in this character's bags: { { bag, slot, count } },
-- and how many in all.
function Tx.Find(item, iid)
  local want, wantName = iid, itemName(item):lower()
  local found, total = {}, 0
  if not C_Container then return found, 0 end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and not secret(info.itemID) then
        local name = itemName(info.hyperlink or ""):lower()
        if (want and info.itemID == want) or (not want and name == wantName) then
          found[#found + 1] = { bag = bag, slot = slot, count = info.stackCount or 1 }
          total = total + (info.stackCount or 1)
        end
      end
    end
  end
  return found, total
end

-- Mails the approved request's item to the member who asked.
function Tx.MailItem(id)
  local g = D:Current()
  local s = g and Tx.Request(g, id)
  if not s or s.st ~= "approved" or not D:Can("items") then return false end
  if not Tx.atMailbox then ns:Print(L.TS_GO_MAILBOX, true) return false end
  -- (The pretend guild's letter "goes" without bags or mail.)
  if D.sandbox then
    Tx.pending = { kind = "req", id = id }
    Tx.Sent()
    return true
  end
  local found, total = Tx.Find(s.rq.item, s.rq.iid)
  if total < s.rq.n then ns:Print(L.TS_NOT_IN_BAGS:format(s.rq.n, s.rq.item), true) return false end
  ClearSendMail()
  local left, slot = s.rq.n, 0
  for _, x in ipairs(found) do
    if left <= 0 or slot >= Tx.ATTACH_MAX then break end
    slot = slot + 1
    local take = math.min(left, x.count)
    if take == x.count then C_Container.PickupContainerItem(x.bag, x.slot)
    else C_Container.SplitContainerItem(x.bag, x.slot, take) end
    ClickSendMailItemButton(slot)
    left = left - take
  end
  if left > 0 then ClearSendMail() ns:Print(L.TS_TOO_MANY, true) return false end
  Tx.pending = { kind = "req", id = id }
  SendMail(Ambiguate(s.rq.by, "none"), L.TS_MAIL_SUBJECT:format(s.rq.item), s.rq.why or "")
  return true
end

-- Mails a prize the Treasury owes (copper) to the player's character.
function Tx.MailGold(key, copper)
  local g = D:Current()
  if not g or not D:InCharge() or copper < 1 then return false end
  if not Tx.atMailbox then ns:Print(L.TS_GO_MAILBOX, true) return false end
  local to = P:Chars(key, g)[1]
  if not to then return false end
  if D.sandbox then
    Tx.pending = { kind = "gold", to = to, amt = copper }
    Tx.Sent()
    return true
  end
  if (GetMoney and GetMoney() or 0) < copper + 30 then ns:Print(L.TS_NO_GOLD, true) return false end
  ClearSendMail()
  SetSendMailMoney(copper)
  Tx.pending = { kind = "gold", to = to, amt = copper }
  SendMail(Ambiguate(to, "none"), L.TS_MAIL_PRIZE, "")
  return true
end

-- The game says the letter went.
function Tx.Sent()
  local p = Tx.pending
  Tx.pending = nil
  if not p then return end
  if p.kind == "req" then
    sync({ k = "req_sent", id = p.id })
  else
    sync({ k = "pay", f = Pu.TREASURY, to = p.to, amt = p.amt, how = "mail" })
  end
  ns:Print(L.TS_MAILED, true)
end

listen("MAIL_SHOW", function() Tx.atMailbox = true; ns:Fire("GUILD_DATA") end)
listen("MAIL_CLOSED", function() Tx.atMailbox = false; ns:Fire("GUILD_DATA") end)
listen("MAIL_SEND_SUCCESS", function() Tx.Sent() end)
listen("MAIL_FAILED", function()
  if Tx.pending then ns:Print(L.TS_MAIL_FAILED, true) end
  Tx.pending = nil
end)

---------------------------------------------------------------------------
-- At the vault: read its log once the game has it
---------------------------------------------------------------------------
local function ago(y, m, d, h)
  return ((tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30 + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)
end

-- What the vault's log shows now, as Tx.Lines takes it.
function Tx.ReadLog()
  local raw = {}
  if GetNumGuildBankMoneyTransactions then
    for i = 1, GetNumGuildBankMoneyTransactions() or 0 do
      local typ, name, amount, y, m, d, h = GetGuildBankMoneyTransaction(i)
      if typ and not secret(typ) and not secret(name) and not secret(amount) then
        raw[#raw + 1] = { kind = "m", type = typ, name = name and ns.FullName(name), amount = tonumber(amount) or 0,
          ago = ago(y, m, d, h) }
      end
    end
  end
  if GetNumGuildBankTabs and GetNumGuildBankTransactions then
    for tab = 1, GetNumGuildBankTabs() or 0 do
      for i = 1, GetNumGuildBankTransactions(tab) or 0 do
        local typ, name, link, count, _, _, y, m, d, h = GetGuildBankTransaction(tab, i)
        if typ and not secret(typ) and not secret(name) and not secret(link) then
          raw[#raw + 1] = { kind = "i", type = typ, name = name and ns.FullName(name), id = itemId(link),
            nm = itemName(link), count = tonumber(count) or 1, tab = tab, ago = ago(y, m, d, h) }
        end
      end
    end
  end
  return raw
end

local function askLogs()
  if not QueryGuildBankLog then return end
  for tab = 1, (GetNumGuildBankTabs and GetNumGuildBankTabs() or 0) do QueryGuildBankLog(tab) end
  QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1)
end

local function opened()
  Tx.atVault = true
  askLogs()
end

listen("GUILDBANKFRAME_OPENED", opened)
listen("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
  local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  if banker and kind == banker then opened() end
end)
listen("GUILDBANKFRAME_CLOSED", function() Tx.atVault = false end)
listen("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  if banker and kind == banker then Tx.atVault = false end
end)
-- The logs come in one tab at a time: read them all a moment after the last.
listen("GUILDBANKLOG_UPDATE", function()
  if not Tx.atVault or D.sandbox then return end
  Tx.readAt = GetTime() + 1
  C_Timer.After(1.1, function()
    if Tx.readAt and GetTime() >= Tx.readAt then
      Tx.readAt = nil
      local n = Tx.Visit(Tx.ReadLog())
      if n > 0 then ns:Print(L.TS_LEDGER_ADDED:format(n), true) end
    end
  end)
end)

ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Tx.TICK, function() Tx.Charge() end) end
end)
