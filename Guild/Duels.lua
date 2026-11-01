-- Duels (SPEC §5, Arena): challenges, results, the ladder and wagers.
-- Only challenged duels move the ladder (decided 29 Oct 2026). A challenge goes by whisper between the two addons:
--   DUC  a challenge { id }     DUA  accepted { id }     DUN  declined, withdrawn or called off { id, busy }
-- Once it is accepted, the challenger's addon tells the guild the match is on (the "match" op, so others can bet),
-- and the two duel in the game within WINDOW. Both addons see the game's message ("X has defeated Y in a duel", or
-- "Y has fled from X in a duel"); the loser's writes the result (the "duel" op), the winner's only when the loser's
-- has not after WINNER_WAIT. Both use the match's id as the key, so the duel counts once.
-- A crown challenge (Guild/Crown.lua) and a cup's match (Guild/Cup.lua) are matches too: a duel between their two
-- players counts for them.
--   match  { c, b }              c: the match id (the challenger's name, "/", a number); the author is the challenger
--   duel   { c, w, l, cr, bk }   the result of match c (cr: a crown challenge's id); bk: the wagers on it, from the
--                                loser's copy: { { name, on, amt, purse }, ... } (only the loser's op carries it)
--   bet    { m, on, amt, p }     a wager on match m: amt in purse p on the player on
-- Ratings are worked out when read, from every duel in time order (Elo, from 1500, K = 32), per player. The ladder
-- starts over each season (SPEC decision 52): a month or three, the Guild Master picks (settings.season); a season's
-- ladder counts only its own duels, and past seasons' top three stay in Records.
-- The challenge rules are an engine (like Guild/Deathroll.lua): ns.Duels is this client's, the self-test's pretend
-- members run their own (they accept by themselves).
local _, ns = ...
local L, D, Comm, Pu = ns.L, ns.GuildData, ns.Comm, ns.Purse
local P = ns.Players

local Du = {}
Du.__index = Du
Du.WINDOW = 1800      -- an accepted challenge stays open this long for the duel
Du.ASK = 300          -- a challenge nobody answers lapses after this long
Du.WINNER_WAIT = 20   -- the winner's addon writes the result when the loser's has not after this long
Du.START, Du.K = 1500, 32
Du.ID_MAX = 80

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function changed(self) if self.io.main then ns:Fire("ARENA") end end

local function new(io) return setmetatable({ io = io, seq = 0 }, Du) end

---------------------------------------------------------------------------
-- Reading the guild's data
---------------------------------------------------------------------------
-- Is the match still open: no result yet, and accepted less than WINDOW ago?
function Du.Open(g, c, m)
  return m ~= nil and not (g.duels and g.duels[c]) and time() - (m.t or 0) < Du.WINDOW
end

-- The open ladder matches: { { id, a, b, t }, ... }, newest first.
function Du.Matches(g)
  local list = {}
  for c, m in pairs(g and g.matches or {}) do
    if Du.Open(g, c, m) then list[#list + 1] = { id = c, a = m.a, b = m.b, t = m.t } end
  end
  table.sort(list, function(x, y) if x.t ~= y.t then return x.t > y.t end return x.id < y.id end)
  return list
end

-- The match between two characters a duel would count for: a cup's first, then the crown's or a trial by combat
-- (Guild/Stocks.lua), then a ladder match.
-- Returns { id, cup, key, cr } or nil.
function Du.MatchWith(g, a, b)
  if not g then return nil end
  local m = (ns.Cup and ns.Cup.MatchWith(g, a, b)) or (ns.Council and ns.Council.MatchWith(g, a, b))
  if m then return m end
  m = (ns.Crown and ns.Crown.MatchWith(g, a, b)) or (ns.Stocks and ns.Stocks.MatchWith(g, a, b))
  if m then return m end
  for _, x in ipairs(Du.Matches(g)) do
    if (x.a == a and x.b == b) or (x.a == b and x.b == a) then return { id = x.id } end
  end
  return nil
end

-- The wagers on match m, as the loser's addon writes them into the result: { { name, on, amt, purse }, ... }. A
-- player in the match may only bet on themselves.
function Du.Book(g, m, a, b)
  local list = {}
  for name, e in pairs(g and g.bets and g.bets[m] or {}) do
    local own = name == a or name == b
    if not own or e.on == name then list[#list + 1] = { name, e.on, e.amt, e.p } end
  end
  table.sort(list, function(x, y) return x[1] < y[1] end)
  return list
end

-- What is bet on each side of match m, per purse: { [name] = units } (gold in copper).
function Du.Pot(g, m)
  local pot = { gold = {}, marks = {} }
  for _, e in pairs(g and g.bets and g.bets[m] or {}) do
    local side = pot[e.p]
    if side then side[e.on] = (side[e.on] or 0) + Pu.Units(e.amt, e.p) end
  end
  return pot
end

local function soundBet(b)
  return type(b) == "table" and party(b[1]) and party(b[2]) and Pu.IsPurse(b[4]) and Pu.ValidAmount(b[3], b[4])
end

-- Settles the wagers of a match won by w: the winners share the pot, each by what they bet. Every loser pays each
-- winner (loser's bet × winner's bet ÷ all bet on the winner). With nobody on the winner, nobody pays.
function Du.Settle(g, key, w, book, t)
  if type(book) ~= "table" then return end
  for _, purse in ipairs({ "gold", "marks" }) do
    local win, lose, total = {}, {}, 0
    for _, b in ipairs(book) do
      if soundBet(b) and b[4] == purse then
        local units = Pu.Units(b[3], purse)
        if b[2] == w then win[#win + 1] = { b[1], units }; total = total + units else lose[#lose + 1] = { b[1], units } end
      end
    end
    if total > 0 then
      for i, x in ipairs(lose) do
        for j, y in ipairs(win) do
          Pu:ChargeUnits(g, key .. ":b" .. i .. "." .. j, x[1], y[1], x[2] * y[2] / total, purse, "wager", t)
        end
      end
    end
  end
end

-- The duel ladder: { { key (player), r (rating), w (wins), l (losses) }, ... }, highest first. With from and to:
-- only the duels in that time (a season).
function Du.Ladder(g, from, to)
  local duels = {}
  for c, e in pairs(g and g.duels or {}) do
    local t = e.t or 0
    if (not from or t >= from) and (not to or t < to) then duels[#duels + 1] = { c = c, w = e.w, l = e.l, t = t } end
  end
  table.sort(duels, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.c < y.c end)
  local r, won, lost = {}, {}, {}
  for _, d in ipairs(duels) do
    local a, b = P:Of(d.w, g), P:Of(d.l, g)
    if a ~= b then
      local ra, rb = r[a] or Du.START, r[b] or Du.START
      local gain = Du.K * (1 - 1 / (1 + 10 ^ ((rb - ra) / 400)))
      r[a], r[b] = ra + gain, rb - gain
      won[a], lost[b] = (won[a] or 0) + 1, (lost[b] or 0) + 1
    end
  end
  local list = {}
  for key, v in pairs(r) do list[#list + 1] = { key = key, r = math.floor(v + 0.5), w = won[key] or 0, l = lost[key] or 0 } end
  table.sort(list, function(x, y) if x.r ~= y.r then return x.r > y.r end return x.key < y.key end)
  return list
end

---------------------------------------------------------------------------
-- Seasons
---------------------------------------------------------------------------
-- Seconds at midnight (UTC, as the months of the tax and the awards) on the 1st of month m of year y.
local function monthStart(y, m)
  local a = math.floor((14 - m) / 12)
  local yy, mm = y + 4800 - a, m + 12 * a - 3
  local day = 1 + math.floor((153 * mm + 2) / 5) + 365 * yy + math.floor(yy / 4) - math.floor(yy / 100)
    + math.floor(yy / 400) - 32045
  return (day - 2440588) * 86400
end

-- The season holding t, for per ("month", or "season": three months, from January, April, July and October):
-- { per, y, m (its first month), from, to }.
function Du.Season(per, t)
  per = per == "season" and "season" or "month"
  local y, m = tonumber(date("!%Y", t)), tonumber(date("!%m", t))
  local len = per == "season" and 3 or 1
  local first = per == "season" and (math.floor((m - 1) / 3) * 3 + 1) or m
  local ny, nm = y, first + len
  if nm > 12 then ny, nm = y + 1, nm - 12 end
  return { per = per, y = y, m = first, from = monthStart(y, first), to = monthStart(ny, nm) }
end

-- This guild's season now.
function Du.Now(g, now)
  local s = g and g.settings or D:Settings()
  return Du.Season(s.season, now or time())
end

-- Its name: "October 2026", "October to December 2026".
function Du.SeasonName(s)
  if s.per == "season" then return L.AR_SEASON_QUARTER:format(L["TS_MONTH_" .. s.m], L["TS_MONTH_" .. (s.m + 2)], s.y) end
  return L.AR_SEASON_MONTH:format(L["TS_MONTH_" .. s.m], s.y)
end

-- The past seasons with ladder duels, newest first, each with its top three: { { season, top = { ladder rows } } }.
-- (At most max; it looks back as far as the oldest duel.)
function Du.Seasons(g, now, max)
  local out = {}
  local oldest
  for _, e in pairs(g and g.duels or {}) do if e.t and (not oldest or e.t < oldest) then oldest = e.t end end
  if not oldest then return out end
  local s = Du.Now(g, now)
  while #out < (max or 4) and s.from > oldest do
    s = Du.Season(s.per, s.from - 1)
    local list = Du.Ladder(g, s.from, s.to)
    if list[1] then out[#out + 1] = { season = s, top = { list[1], list[2], list[3] } } end
  end
  return out
end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
D:Register("match", {
  allowed = function(_, author, op)
    return type(op.c) == "string" and #op.c <= Du.ID_MAX and op.c:sub(1, #author + 1) == author .. "/" and party(op.b)
      and op.b ~= author
  end,
  apply = function(g, author, op, t)
    local all = D.Part(g, "matches")
    if not all[op.c] then all[op.c] = { a = author, b = op.b, t = t } end
    return true
  end,
  copy = function(g) return { m = g.matches, d = g.duels, b = g.bets } end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    D.Union(D.Part(g, "matches"), part.m, function(e) return party(e.a) and party(e.b) and tonumber(e.t) ~= nil end)
    local duels = D.Part(g, "duels")
    for c, e in pairs(type(part.d) == "table" and part.d or {}) do
      if type(c) == "string" and type(e) == "table" and party(e.w) and party(e.l) and tonumber(e.t) then
        local cur = duels[c]
        if not cur or e.t < (cur.t or 0) then duels[c] = { w = e.w, l = e.l, cr = e.cr, t = e.t } end
      end
    end
    local bets = D.Part(g, "bets")
    for m, list in pairs(type(part.b) == "table" and part.b or {}) do
      if type(m) == "string" and type(list) == "table" then
        bets[m] = bets[m] or {}
        for name, e in pairs(list) do
          local cur = bets[m][name]
          if party(name) and type(e) == "table" and soundBet({ name, e.on, e.amt, e.p }) and tonumber(e.t)
            and (not cur or e.t > (cur.t or 0)) then
            bets[m][name] = { on = e.on, amt = e.amt, p = e.p, t = e.t }
          end
        end
      end
    end
  end,
})

D:Register("duel", {
  allowed = function(_, author, op)
    return type(op.c) == "string" and #op.c <= Du.ID_MAX and party(op.w) and party(op.l) and op.w ~= op.l
      and (author == op.w or author == op.l) and (op.cr == nil or type(op.cr) == "string")
  end,
  apply = function(g, author, op, t, n)
    local all = D.Part(g, "duels")
    local cur = all[op.c]
    -- The loser's and the winner's op are the same duel: the earlier time stands.
    if not cur or t < (cur.t or 0) then all[op.c] = { w = op.w, l = op.l, cr = op.cr, t = t } end
    if author == op.l then Du.Settle(g, D.Key(author, n), op.w, op.bk, t) end
    return true
  end,
})

D:Register("bet", {
  allowed = function(_, _, op)
    return type(op.m) == "string" and #op.m <= Du.ID_MAX + 40 and party(op.on) and Pu.IsPurse(op.p)
      and Pu.ValidAmount(op.amt, op.p)
  end,
  apply = function(g, author, op, t)
    local bets = D.Part(g, "bets")
    bets[op.m] = bets[op.m] or {}
    local cur = bets[op.m][author]
    if cur and (cur.t or 0) > t then return false end
    bets[op.m][author] = { on = op.on, amt = op.amt, p = op.p, t = t }
    return true
  end,
})

---------------------------------------------------------------------------
-- The challenge in hand (one at a time)
---------------------------------------------------------------------------
function Du:Game()
  local c = self.ch
  if c and GetTime() - c.at > (c.st == "on" and Du.WINDOW or Du.ASK) then self.ch = nil end
  return self.ch
end

function Du:Busy() return self:Game() ~= nil end

function Du:Challenge(opp)
  local me = self.io.me()
  if self:Busy() or not party(opp) or opp == me then return false end
  self.seq = self.seq + 1
  local id = ("%s/%d.%d"):format(me, time(), self.seq)
  self.ch = { id = id, opp = opp, mine = true, st = "asked", at = GetTime() }
  self.io.send(opp, "DUC", { id = id })
  changed(self)
  return true
end

function Du:Accept()
  local c = self:Game()
  if not c or c.st ~= "incoming" then return false end
  c.st, c.at = "on", GetTime()
  self.io.send(c.opp, "DUA", { id = c.id })
  changed(self)
  return true
end

-- Declines a challenge, withdraws one, or calls off an accepted one before the duel.
function Du:CallOff()
  local c = self:Game()
  if not c then return false end
  self.io.send(c.opp, "DUN", { id = c.id })
  self.ch = nil
  changed(self)
  return true
end

-- The game said w beat l in a duel. When this player is one of them and it counts for a match, write the result.
function Du:Seen(w, l)
  local me = self.io.me()
  if w ~= me and l ~= me then return false end
  local g = self.io.g()
  local m = Du.MatchWith(g, w, l)
  if self.ch and self.ch.opp == (w == me and l or w) then self.ch = nil end
  if not m then changed(self) return false end
  if m.cup then
    ns.Cup.Report(self.io, g, m, w, l)
  elseif m.mak then
    -- Mak'gora (SPEC §7.5): the loser's addon writes it.
    if l == me then self.io.sync:Do({ k = "mak_duel", id = m.mak, w = w }) end
  else
    local op = { k = "duel", c = m.id, w = w, l = l, cr = m.cr }
    if l == me then
      op.bk = Du.Book(g, m.id, w, l)
      self.io.sync:Do(op)
    else
      C_Timer.After(Du.WINNER_WAIT, function()
        -- (Still the same guild: the self-test's pretend one may be gone by then.)
        local now = self.io.g()
        if now and now == g and not (now.duels and now.duels[m.id]) then self.io.sync:Do(op) end
      end)
    end
  end
  changed(self)
  return true
end

---------------------------------------------------------------------------
-- Receiving (by whisper only)
---------------------------------------------------------------------------
local receive = {}

receive.DUC = function(self, sender, d)
  if type(d.id) ~= "string" or #d.id > Du.ID_MAX or d.id:sub(1, #sender + 1) ~= sender .. "/" then return end
  if self:Busy() then
    self.io.send(sender, "DUN", { id = d.id, busy = true })
    return
  end
  self.ch = { id = d.id, opp = sender, mine = false, st = "incoming", at = GetTime() }
  if self.io.main then ns:Print(L.DU_CHALLENGED:format(ns.Display(sender)), true) end
  changed(self)
  if self.io.auto then self:Accept() end
end

local function ours(self, sender, d)
  local c = self:Game()
  return c and c.id == d.id and c.opp == sender and c or nil
end

receive.DUA = function(self, sender, d)
  local c = ours(self, sender, d)
  if not c or c.st ~= "asked" then return end
  c.st, c.at = "on", GetTime()
  self.io.sync:Do({ k = "match", c = c.id, b = sender })
  if self.io.main then ns:Print(L.DU_ACCEPTED:format(ns.Display(sender)), true) end
  changed(self)
end

receive.DUN = function(self, sender, d)
  if not ours(self, sender, d) then return end
  self.ch = nil
  if self.io.main then ns:Print((d.busy and L.DU_BUSY or L.DU_DECLINED):format(ns.Display(sender)), true) end
  changed(self)
end

function Du:Receive(tag, sender, d, channel)
  local fn = receive[tag]
  if fn and channel == "WHISPER" and type(d) == "table" then fn(self, sender, d) end
end

---------------------------------------------------------------------------
-- The game's duel message
---------------------------------------------------------------------------
-- A game format string ("%1$s has defeated %2$s in a duel") as a Lua pattern, and which capture is which argument.
-- (From Journey Together Forever, Fellowship/Tourney.lua.)
function Du.FormatPattern(fmt)
  local order = {}
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%(%d)%%%$s", function(i) order[#order + 1] = tonumber(i); return "(.-)" end)
  p = p:gsub("%%s", function() order[#order + 1] = #order + 1; return "(.-)" end)
  return "^" .. p .. "$", order
end

-- Winner and loser (full names) from a system message, or nil.
function Du.ParseDuel(msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
  for _, fmt in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
    if type(fmt) == "string" then
      local pattern, order = Du.FormatPattern(fmt)
      local caps = { msg:match(pattern) }
      if #caps >= 2 then
        local args = {}
        for i, argN in ipairs(order) do args[argN] = caps[i] end
        if args[1] and args[2] then return ns.FullName(args[1]), ns.FullName(args[2]) end
      end
    end
  end
  return nil
end

-- Listeners for every duel the game reports (the self-test hands in pretend ones): fn(winner, loser).
Du.listeners = {}
function Du.Listen(fn) Du.listeners[#Du.listeners + 1] = fn end
function Du.Heard(w, l) for _, fn in ipairs(Du.listeners) do fn(w, l) end end

---------------------------------------------------------------------------
-- This client's engine
---------------------------------------------------------------------------
local main = new({
  main = true,
  me = function() return ns.Self() end,
  g = function() return D:Current() end,
  send = function(target, tag, data) Comm:Send(target, tag, data, true) end,
  sync = ns.Sync,
})
ns.Duels = main
main.New = new

for tag in pairs(receive) do
  Comm:On(tag, function(sender, d, channel) main:Receive(tag, sender, d, channel) end)
end

Du.Listen(function(w, l) main:Seen(w, l) end)

ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
  local w, l = Du.ParseDuel(msg)
  if w then Du.Heard(w, l) end
end)

-- Actions for the page.
function Du:Bet(m, on, amt) return ns.Sync:Do({ k = "bet", m = m, on = on, amt = amt, p = D:Settings().purse }) end
