-- The purse (SPEC §4): what bets, tickets and bail are paid in. Gold makes debts, paid by trade or mail and marked
-- paid by the receiver's addon (Guild/Payments.lua); Marks are points that move at once. Both are ledgers of entries
-- filed under the op that made them (D.Key), so whole copies merge by putting entries together:
--   g.debts[key] = { f, to, amt, w, t }   gold (copper): f owes to                 (to: a character or "treasury")
--   g.pays[key]  = { f, to, amt, how, t } gold (copper) from f reached to          (how: "trade", "mail", "hand")
--   g.marks[key] = { f, to, amt, w, t }   Marks moved from f to to (f nil: granted, to nil: taken away)
-- Entries name characters; totals are per player (Guild/Players.lua). Balances in Marks may go below 0 (decided
-- 29 Oct 2026). A bet is settled in the purse it was made in, whatever the purse is now.
local _, ns = ...
local L, D = ns.L, ns.GuildData
local Pu = {}
ns.Purse = Pu

Pu.TREASURY = "treasury"
Pu.GOLD = 10000           -- copper in one gold piece
Pu.GOLD_MAX = 100000      -- gold in one bet, ticket or payment at most
Pu.MARKS_MAX = 1000000
Pu.WHY_MAX = 40

local function P() return ns.Players end

-- Other ledgers that add to the purse's (Guild/Treasury.lua): functions(g) returning debts { key, f, to, amt, w, t }
-- (the guild tax), and payments that count only for debts made before them { f, to, amt, t } (gold put in the
-- guild vault, read from its log).
Pu.extraDebts, Pu.timedPays = {}, {}

-- A character's name or the Treasury.
local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
function Pu.IsPurse(p) return p == "gold" or p == "marks" end

-- A whole amount in the purse's own unit (gold pieces or Marks), within limits.
function Pu.ValidAmount(amt, purse)
  amt = tonumber(amt)
  local max = purse == "gold" and Pu.GOLD_MAX or Pu.MARKS_MAX
  return amt ~= nil and amt >= 1 and amt <= max and amt == math.floor(amt)
end

-- What an amount looks like: "5 g", "5 g 20 s" (copper in gold), "50 Marks", "1 Mark".
function Pu:Format(amt, purse, settings)
  amt = tonumber(amt) or 0
  if purse == "gold" then
    local g, s = math.floor(math.abs(amt) / 10000), math.floor(math.abs(amt) % 10000 / 100)
    local text = s > 0 and L.MONEY_GS:format(g, s) or L.MONEY_G:format(g)
    return amt < 0 and ("-" .. text) or text
  end
  settings = settings or D:Settings()
  return ("%d %s"):format(amt, (amt == 1 or amt == -1) and settings.one or settings.many)
end

-- An amount in a purse as kept in the ledger: gold in copper.
function Pu.Units(amt, purse) return purse == "gold" and amt * Pu.GOLD or amt end

-- Writes what an op costs: from pays amt (in the purse's unit) to to. key: the op's key (and ":2", ":3" for more).
function Pu:Charge(g, key, from, to, amt, purse, why, t)
  return self:ChargeUnits(g, key, from, to, Pu.Units(amt, purse), purse, why, t)
end

-- The same in the ledger's own units (copper for gold): for shares of a pot, which need not be whole gold.
function Pu:ChargeUnits(g, key, from, to, units, purse, why, t)
  units = math.floor(tonumber(units) or 0)
  if not party(from) or not party(to) or from == to or units < 1 then return false end
  if purse == "gold" then
    D.Part(g, "debts")[key] = { f = from, to = to, amt = units, w = why, t = t }
  else
    D.Part(g, "marks")[key] = { f = from, to = to, amt = units, w = why, t = t }
  end
  return true
end

---------------------------------------------------------------------------
-- Reading the ledger (per player)
---------------------------------------------------------------------------
local function who(name, g)
  if name == Pu.TREASURY then return Pu.TREASURY end
  return P():Of(name, g)
end

-- A player's balance in Marks.
function Pu:Balance(g, key)
  local sum = 0
  for _, e in pairs(g.marks or {}) do
    if e.to and who(e.to, g) == key then sum = sum + e.amt end
    if e.f and who(e.f, g) == key then sum = sum - e.amt end
  end
  return sum
end

-- Every player with Marks (or who moved some): { { key, amt }, ... }, highest first.
function Pu:Balances(g)
  local seen, list = {}, {}
  for _, e in pairs(g.marks or {}) do
    for _, name in ipairs({ e.f, e.to }) do
      local key = name and who(name, g)
      if key and key ~= Pu.TREASURY and not seen[key] then
        seen[key] = true
        list[#list + 1] = { key = key, amt = self:Balance(g, key) }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.amt ~= b.amt then return a.amt > b.amt end
    return a.key < b.key
  end)
  return list
end

local function sortByTime(list)
  table.sort(list, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
    return a.key < b.key
  end)
end

-- The debts still open, oldest first: { { key, f, to (players), amt (copper left), w, t }, ... }. Payments from one
-- player to another pay that pair's oldest debts first.
function Pu:Open(g)
  local debts, paid = {}, {}
  for key, e in pairs(g.debts or {}) do
    debts[#debts + 1] = { key = key, f = who(e.f, g), to = who(e.to, g), amt = e.amt, w = e.w, t = e.t }
  end
  -- (A period's tax that a tax punishment paid off is forgiven: Guild/Rules.lua, SPEC decision 69.)
  local forgiven = ns.Rules and ns.Rules.Forgiven(g) or {}
  for _, fn in ipairs(Pu.extraDebts) do
    for _, e in ipairs(fn(g)) do
      if not forgiven[e.key] then
        debts[#debts + 1] = { key = e.key, f = who(e.f, g), to = who(e.to, g), amt = e.amt, w = e.w, t = e.t }
      end
    end
  end
  for _, e in pairs(g.pays or {}) do
    local pair = who(e.f, g) .. ">" .. who(e.to, g)
    paid[pair] = (paid[pair] or 0) + e.amt
  end
  sortByTime(debts)
  local open = {}
  for _, d in ipairs(debts) do
    local pair = d.f .. ">" .. d.to
    local use = math.min(paid[pair] or 0, d.amt)
    paid[pair] = (paid[pair] or 0) - use
    if d.f ~= d.to and d.amt - use > 0 then
      d.amt = d.amt - use
      open[#open + 1] = d
    end
  end
  -- Payments that count from their time on: each pays the oldest debts made before it (within the hour: the vault's
  -- log tells the hour only).
  local timed = {}
  for _, fn in ipairs(Pu.timedPays) do
    for _, e in ipairs(fn(g)) do timed[#timed + 1] = { f = who(e.f, g), to = who(e.to, g), amt = e.amt, t = e.t } end
  end
  table.sort(timed, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.f < b.f end)
  for _, p in ipairs(timed) do
    local left = p.amt
    for _, d in ipairs(open) do
      if left <= 0 then break end
      if d.f == p.f and d.to == p.to and d.amt > 0 and (d.t or 0) <= p.t + 3600 then
        local use = math.min(left, d.amt)
        d.amt, left = d.amt - use, left - use
      end
    end
  end
  local out = {}
  for _, d in ipairs(open) do if d.amt > 0 then out[#out + 1] = d end end
  return out
end

-- What player from still owes player (or the Treasury) to, in copper.
function Pu:Owed(g, from, to)
  local sum = 0
  for _, d in ipairs(self:Open(g)) do if d.f == from and d.to == to then sum = sum + d.amt end end
  return sum
end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
local function soundEntry(e) return party(e.f or "x") and party(e.to or "x") and tonumber(e.amt) ~= nil and e.amt > 0 end

-- Gold that reached its receiver (by trade or mail, Guild/Payments.lua), or a debt the receiver marks paid. Made by
-- the receiver's own addon; for the Treasury, by the Guild Master's (decision 50).
D:Register("pay", {
  allowed = function(g, author, op)
    local amt = tonumber(op.amt)
    if not party(op.f) or not party(op.to) or not amt or amt < 1 or amt > Pu.GOLD_MAX * Pu.GOLD then return false end
    if op.how ~= "trade" and op.how ~= "mail" and op.how ~= "hand" then return false end
    if op.to == Pu.TREASURY or op.f == Pu.TREASURY then
      -- The Treasury's own: the Guild Master (and the winner of a prize, receiving it).
      if D:InCharge(author, g) then return true end
      if op.to == Pu.TREASURY then return false end
    end
    return P():Of(op.to, g) == P():Of(author, g)
  end,
  apply = function(g, author, op, t, n)
    D.Part(g, "pays")[D.Key(author, n)] = { f = op.f, to = op.to, amt = math.floor(op.amt), how = op.how, t = t }
    return true
  end,
  copy = function(g) return { d = g.debts, p = g.pays, m = g.marks } end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    D.Union(D.Part(g, "debts"), part.d, soundEntry)
    D.Union(D.Part(g, "pays"), part.p, soundEntry)
    D.Union(D.Part(g, "marks"), part.m, soundEntry)
  end,
})

-- Marks granted (amt above 0) or taken away (below 0) by a rank that may (SPEC §3.2, grant).
D:Register("grant", {
  allowed = function(g, author, op)
    local amt = tonumber(op.amt)
    return party(op.to) and amt ~= nil and amt ~= 0 and math.abs(amt) <= Pu.MARKS_MAX and amt == math.floor(amt)
      and D:Can("grant", author, g)
  end,
  apply = function(g, author, op, t, n)
    local why = type(op.w) == "string" and op.w:sub(1, Pu.WHY_MAX) or nil
    local e = op.amt > 0 and { to = op.to, amt = op.amt } or { f = op.to, amt = -op.amt }
    e.w, e.t, e.by = why, t, author
    D.Part(g, "marks")[D.Key(author, n)] = e
    return true
  end,
})

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
-- Gold reached this character from name (copper, by "trade" or "mail"): it pays what name's player owes our player,
-- oldest first; what is left pays their debts to the Treasury when we are the Guild Master, and gold from the Guild
-- Master pays what the Treasury owes us (a prize). Returns the copper used.
function Pu:Arrived(name, copper, how)
  local g = D:Current()
  copper = tonumber(copper)
  if not g or type(name) ~= "string" or not copper or copper < 1 then return 0 end
  local me = ns.Self()
  local from, mine = P():Of(name, g), P():Of(me, g)
  local used = 0
  local owed = self:Owed(g, from, mine)
  if owed > 0 then
    local amt = math.min(owed, copper)
    if ns.Sync:Do({ k = "pay", f = name, to = me, amt = amt, how = how }) then
      used = amt
      ns:Print(L.PAID_BY:format(P():Name(from, g), self:Format(amt, "gold")), true)
    end
  end
  local left = copper - used
  local tax = self:Owed(g, from, Pu.TREASURY)
  if left > 0 and tax > 0 and D:InCharge() then
    local amt = math.min(tax, left)
    if ns.Sync:Do({ k = "pay", f = name, to = Pu.TREASURY, amt = amt, how = how }) then
      used = used + amt
      ns:Print(L.PAID_TREASURY:format(P():Name(from, g), self:Format(amt, "gold")), true)
    end
  end
  left = copper - used
  local prize = self:Owed(g, Pu.TREASURY, mine)
  -- (A prize by mail is recorded by the member who mails it, Guild/Treasury.lua.)
  if how == "trade" and left > 0 and prize > 0 and D:InCharge(name, g) then
    local amt = math.min(prize, left)
    if ns.Sync:Do({ k = "pay", f = Pu.TREASURY, to = me, amt = amt, how = how }) then
      used = used + amt
      ns:Print(L.PAID_BY_TREASURY:format(self:Format(amt, "gold")), true)
    end
  end
  return used
end

-- The receiver marks a player's debts to them paid (paid in person, or let off).
function Pu:MarkPaid(fromKey, toKey)
  local g = D:Current()
  if not g then return false end
  local owed = self:Owed(g, fromKey, toKey)
  if owed < 1 then return false end
  local to = toKey == Pu.TREASURY and Pu.TREASURY or ns.Self()
  local f = fromKey == Pu.TREASURY and Pu.TREASURY or P():Chars(fromKey, g)[1]
  -- A prize the Treasury owed, paid by hand by a rank that may record tax payments.
  if fromKey == Pu.TREASURY and not P():IsMe(toKey, g) then to = P():Chars(toKey, g)[1] end

  return ns.Sync:Do({ k = "pay", f = f, to = to, amt = owed, how = "hand" })
end

-- Grants (or with a negative amount takes away) Marks.
function Pu:Grant(name, amt, why)
  return ns.Sync:Do({ k = "grant", to = name, amt = amt, w = why })
end
