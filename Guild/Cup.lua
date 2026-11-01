-- Tournaments for the purse (SPEC §5, Arena): single or double elimination, groups, or round robin (the bracket is
-- Journey's, Guild/Bracket.lua), best of 1, 3 or 5. A rank that may start tournaments (SPEC §3.2, tourney) hosts one.
-- An optional entry fee goes into the pot, and the Treasury can add a prize; the pot is shared among the top places,
-- 60 / 30 / 10% (a place nobody takes adds its share to the first; two third places share the third's).
-- Decided 29 Oct 2026, in gold: nothing is held. At the end, every entrant owes each placed player their share of the
-- fee, and the Treasury owes them their share of its prize (Guild/Purse.lua).
--   cup         { name, fmt, bo, fee, prize, p, when }   sign-up opens (its key is the cup's id)
--   cup_join    { id, who, on }       signs up or withdraws (who: the author, or anyone when the host adds them)
--   cup_go      { id, seeds }         the host closes sign-up; seeds in order (random, fixed by the cup's id)
--   cup_duel    { id, key, w, l, wo, bk }   one duel of match key, won by w: written by the loser's addon, or by the
--                                     host (for a member without the addon, or a walkover: wo); bk: the wagers on the
--                                     match, when this duel decides it (Guild/Duels.lua)
--   cup_end     { id, places }        the host's result: { { first }, { second }, { third, ... } }; the pot is shared
--   cup_cancel  { id }                the host calls it off (nothing is paid)
--   lead_cup    { id, fmt, bo }       the crown tournament of an impeachment (SPEC §7.5): its id is the motion's, so
--                                     the motion's filer hosts it (Guild/Council.lua); no fee, no prize, shown on the
--                                     Council page, not in the Arena
-- The bracket and its results are worked out when read, from the duels in time order.
local _, ns = ...
local D, Pu = ns.GuildData, ns.Purse
local T, Du = ns.Tournament, ns.Duels

local Cu = {}
ns.Cup = Cu
Cu.FORMATS = { "single", "double", "groups", "rr" }
Cu.BO = { 1, 3, 5 }
Cu.SHARES = { 60, 30, 10 }
Cu.NAME_MAX, Cu.WHEN_MAX = 32, 24
Cu.MAX = 64

local isFormat, isBo = {}, {}
for _, f in ipairs(Cu.FORMATS) do isFormat[f] = true end
for _, b in ipairs(Cu.BO) do isBo[b] = true end
local ORDER = { open = 1, running = 2, done = 3, cancelled = 3 }

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function host(id) return D.KeyAuthor(id) end
local function amount(v, purse) return tonumber(v) == 0 or Pu.ValidAmount(v, purse) end
local Clean = ns.Raffle.Clean

local function get(g, id)
  local all = D.Part(g, "cups")
  all[id] = all[id] or { j = {}, d = {}, st = "open" }
  return all[id]
end

local function advance(c, st) if ORDER[st] > (ORDER[c.st] or 1) then c.st = st end end

local function soundOpen(op)
  return Clean(op.name, Cu.NAME_MAX) ~= nil and isFormat[op.fmt] and isBo[tonumber(op.bo)] and Pu.IsPurse(op.p)
    and amount(op.fee, op.p) and amount(op.prize, op.p)
end

local function open(c, author, op, t)
  c.h, c.name, c.fmt, c.bo, c.p, c.t = author, Clean(op.name, Cu.NAME_MAX), op.fmt, tonumber(op.bo), op.p, t
  c.fee, c.prize, c.when = tonumber(op.fee), tonumber(op.prize), Clean(op.when, Cu.WHEN_MAX)
end

local function soundSeeds(seeds)
  if type(seeds) ~= "table" or #seeds < 2 or #seeds > Cu.MAX then return false end
  local seen = {}
  for _, n in ipairs(seeds) do
    if not party(n) or seen[n] then return false end
    seen[n] = true
  end
  return true
end

local function soundPlaces(places)
  if type(places) ~= "table" or #places > 3 then return false end
  for _, list in ipairs(places) do
    if type(list) ~= "table" or #list > 2 then return false end
    for _, n in ipairs(list) do if not party(n) then return false end end
  end
  return true
end

D:Register("cup", {
  allowed = function(g, author, op) return soundOpen(op) and D:Can("tourney", author, g) end,
  apply = function(g, author, op, t, n)
    open(get(g, D.Key(author, n)), author, op, t)
    return true
  end,
  copy = function(g) return g.cups end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and type(e) == "table" then
        local c = get(g, id)
        if not c.h and party(e.h) and soundOpen(e) and tonumber(e.t) then
          open(c, e.h, e, e.t)
          c.lead = e.lead == true or nil
        end
        if tonumber(e.te) and not c.te then c.te = tonumber(e.te) end
        for name, x in pairs(type(e.j) == "table" and e.j or {}) do
          if party(name) and type(x) == "table" and tonumber(x.t) and (not c.j[name] or x.t > c.j[name].t) then
            c.j[name] = { on = x.on == true, t = x.t }
          end
        end
        if not c.seeds and soundSeeds(e.seeds) then c.seeds = e.seeds end
        D.Union(c.d, e.d, function(x) return type(x.key) == "string" and party(x.w) and tonumber(x.t) ~= nil end)
        if ORDER[e.st] then advance(c, e.st) end
        if not c.places and soundPlaces(e.places) then c.places = e.places end
      end
    end
  end,
})

D:Register("cup_join", {
  allowed = function(_, author, op)
    local who = op.who or author
    return host(op.id) ~= nil and party(who) and (who == author or author == host(op.id))
  end,
  apply = function(g, author, op, t)
    local c = get(g, op.id)
    local who = op.who or author
    local cur = c.j[who]
    if cur and cur.t > t then return false end
    c.j[who] = { on = op.on ~= false, t = t }
    return true
  end,
})

D:Register("cup_go", {
  allowed = function(_, author, op) return host(op.id) == author and soundSeeds(op.seeds) end,
  apply = function(g, _, op)
    local c = get(g, op.id)
    if c.seeds then return false end
    c.seeds = op.seeds
    advance(c, "running")
    return true
  end,
})

D:Register("cup_duel", {
  allowed = function(_, author, op)
    return host(op.id) ~= nil and type(op.key) == "string" and #op.key <= 24 and party(op.w) and party(op.l)
      and op.w ~= op.l and (author == op.l or author == host(op.id))
  end,
  apply = function(g, author, op, t, n)
    local c = get(g, op.id)
    local key = D.Key(author, n)
    c.d[key] = { key = op.key, w = op.w, l = op.l, t = t, a = author, wo = op.wo == true or nil }
    if op.bk then Du.Settle(g, key, op.w, op.bk, t) end
    return true
  end,
})

D:Register("cup_end", {
  allowed = function(_, author, op) return host(op.id) == author and soundPlaces(op.places) end,
  apply = function(g, author, op, t, n)
    local c = get(g, op.id)
    if c.places or c.st == "cancelled" then return false end
    c.places, c.te = op.places, t
    advance(c, "done")
    Cu.Pay(g, c, D.Key(author, n), t)
    return true
  end,
})

D:Register("lead_cup", {
  allowed = function(_, author, op) return host(op.id) == author and isFormat[op.fmt] and isBo[tonumber(op.bo)] end,
  apply = function(g, author, op, t)
    local c = get(g, op.id)
    if c.h then return false end
    open(c, author, { name = "crown", fmt = op.fmt, bo = op.bo, p = "marks", fee = 0, prize = 0 }, t)
    c.lead = true
    return true
  end,
})

D:Register("cup_cancel", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op)
    local c = get(g, op.id)
    if c.places then return false end
    advance(c, "cancelled")
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- Signed up, in the order they joined.
function Cu.Joined(c)
  local list = {}
  for name, x in pairs(c.j) do if x.on then list[#list + 1] = { name = name, t = x.t } end end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.name < b.name end)
  local out = {}
  for i, x in ipairs(list) do out[i] = x.name end
  return out
end

function Cu.Need(c) return math.ceil((c.bo or 1) / 2) end

-- The bracket with every result so far, and the duel wins in matches not yet decided: wins[key][name].
function Cu.Build(c)
  if not c.seeds then return nil end
  local list = {}
  for k, e in pairs(c.d) do list[#list + 1] = { k = k, key = e.key, w = e.w, a = e.a, wo = e.wo, t = e.t } end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.k < b.k end)
  local need, results = Cu.Need(c), {}
  local B, wins
  for _ = 1, 4 * Cu.MAX do
    B, wins = T.Build(c.fmt, c.seeds, results), {}
    local more = false
    for _, e in ipairs(list) do
      local m = B.byKey[e.key]
      if m and results[e.key] == nil and type(m.a) == "string" and type(m.b) == "string" and (e.w == m.a or e.w == m.b)
        and (e.a == c.h or (e.a ~= e.w and (e.a == m.a or e.a == m.b))) then
        if e.wo then
          results[e.key], more = e.w, true
        else
          wins[e.key] = wins[e.key] or {}
          wins[e.key][e.w] = (wins[e.key][e.w] or 0) + 1
          if wins[e.key][e.w] >= need then results[e.key], more = e.w, true end
        end
      end
      if more then break end
    end
    if not more then return B, wins end
  end
  return B, wins
end

-- Matches being played: both players known, no winner yet. { m, ... } in slot order.
function Cu.Live(B)
  local list = {}
  for _, m in ipairs(B and B.matches or {}) do
    if type(m.a) == "string" and type(m.b) == "string" and m.w == nil then list[#list + 1] = m end
  end
  table.sort(list, function(a, b) if a.slot ~= b.slot then return a.slot < b.slot end return a.key < b.key end)
  return list
end

-- The places once there is a champion: { { first }, { second }, { third, ... } }, or nil.
function Cu.Places(c, B)
  if not B or not B.champion then return nil end
  local function other(m, name) return m.a == name and m.b or m.a end
  if c.fmt == "rr" then
    local wins, seedOf = {}, {}
    for i, n in ipairs(c.seeds) do wins[n], seedOf[n] = 0, i end
    for _, m in ipairs(B.matches) do if m.w then wins[m.w] = wins[m.w] + 1 end end
    local order = {}
    for i, n in ipairs(c.seeds) do order[i] = n end
    table.sort(order, function(a, b) if wins[a] ~= wins[b] then return wins[a] > wins[b] end return seedOf[a] < seedOf[b] end)
    local places = {}
    for i = 1, math.min(3, #order) do places[i] = { order[i] } end
    return places
  end
  local final
  for _, m in ipairs(B.matches) do
    if m.w == B.champion and (not final or m.slot > final.slot) then final = m end
  end
  if not final then return { { B.champion } } end
  local places = { { B.champion } }
  local second = other(final, B.champion)
  if type(second) == "string" then places[2] = { second } end
  local thirds = {}
  if c.fmt == "double" then
    local src = final.sb and final.sb.win
    local l = src and B.Loser(src)
    if type(l) == "string" then thirds[1] = l end
  else
    for _, m in ipairs(B.matches) do
      if m.stage == final.stage and m.col == final.col - 1 and m.w then
        local l = other(m, m.w)
        if type(l) == "string" then thirds[#thirds + 1] = l end
      end
    end
  end
  if #thirds > 0 then places[3] = thirds end
  return places
end

-- Each placed player's share of the pot, in percent: { { name, pct }, ... }.
function Cu.Shares(places)
  local out, spare = {}, 0
  for i, pct in ipairs(Cu.SHARES) do
    local list = places[i]
    if list and #list > 0 then
      for _, n in ipairs(list) do out[#out + 1] = { n, pct / #list } end
    else
      spare = spare + pct
    end
  end
  if out[1] then out[1][2] = out[1][2] + spare end
  return out
end

-- The pot in the purse's units: entry fees and the Treasury's prize.
function Cu.Pot(c)
  local n = c.seeds and #c.seeds or #Cu.Joined(c)
  return (c.fee or 0) * n + (c.prize or 0)
end

-- The end: every entrant pays each placed player their share of the fee; the Treasury pays its prize.
function Cu.Pay(g, c, key, t)
  local shares = Cu.Shares(c.places)
  local fee, prize = Pu.Units(c.fee or 0, c.p), Pu.Units(c.prize or 0, c.p)
  for i, e in ipairs(c.seeds or {}) do
    for j, s in ipairs(shares) do
      Pu:ChargeUnits(g, key .. ":f" .. i .. "." .. j, e, s[1], fee * s[2] / 100, c.p, "cup", t)
    end
  end
  for j, s in ipairs(shares) do
    Pu:ChargeUnits(g, key .. ":p" .. j, Pu.TREASURY, s[1], prize * s[2] / 100, c.p, "cup", t)
  end
end

-- The newest cup that is not over, else the newest one; and its id. (Not the crown's: it shows under Council.)
function Cu.Current(g)
  local best, bestId
  for id, c in pairs(g and g.cups or {}) do
    if c.h and not c.lead then
      local live = c.st == "open" or c.st == "running"
      local bestLive = best and (best.st == "open" or best.st == "running")
      local better = not best or (live and not bestLive)
        or (live == bestLive and (c.t > best.t or (c.t == best.t and id > bestId)))
      if better then best, bestId = c, id end
    end
  end
  return best, bestId
end

-- The match id for wagers on a cup match.
function Cu.MatchId(id, key) return "cup|" .. id .. "|" .. key end

-- The live cup match between characters a and b (Guild/Duels.lua): { cup, key, id }, or nil.
function Cu.MatchWith(g, a, b)
  for id, c in pairs(g and g.cups or {}) do
    if c.st == "running" then
      for _, m in ipairs(Cu.Live((Cu.Build(c)))) do
        if (m.a == a and m.b == b) or (m.a == b and m.b == a) then return { cup = id, key = m.key, id = Cu.MatchId(id, m.key) } end
      end
    end
  end
  return nil
end

-- A duel of a cup match: the loser's addon writes it (io: Guild/Duels.lua's engine), with the wagers when it decides.
function Cu.Report(io, g, m, w, l)
  if l ~= io.me() then return end
  local c = g.cups[m.cup]
  local _, wins = Cu.Build(c)
  local op = { k = "cup_duel", id = m.cup, key = m.key, w = w, l = l }
  if ((wins[m.key] or {})[w] or 0) + 1 >= Cu.Need(c) then op.bk = Du.Book(g, m.id, w, l) end
  io.sync:Do(op)
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
function Cu.Open(name, fmt, bo, fee, prize, when)
  return ns.Sync:Do({ k = "cup", name = name, fmt = fmt, bo = bo, fee = fee, prize = prize, when = when,
    p = D:Settings().purse })
end

function Cu.Join(id, on, who) return ns.Sync:Do({ k = "cup_join", id = id, on = on ~= false, who = who }) end

function Cu.Go(id)
  local g = D:Current()
  local c = g and g.cups and g.cups[id]
  if not c or c.h ~= ns.Self() or c.seeds then return false end
  local joined = Cu.Joined(c)
  if #joined < 2 then return false end
  return ns.Sync:Do({ k = "cup_go", id = id, seeds = T.Seed(joined, "random", nil, id) })
end

-- The host gives a match to w without a duel (the other did not turn up).
function Cu.Walkover(id, m, w)
  return ns.Sync:Do({ k = "cup_duel", id = id, key = m.key, w = w, l = m.a == w and m.b or m.a, wo = true })
end

function Cu.Finish(id)
  local g = D:Current()
  local c = g and g.cups and g.cups[id]
  if not c or c.h ~= ns.Self() or c.st ~= "running" then return false end
  local places = Cu.Places(c, (Cu.Build(c)))
  if not places then return false end
  return ns.Sync:Do({ k = "cup_end", id = id, places = places })
end

function Cu.Cancel(id) return ns.Sync:Do({ k = "cup_cancel", id = id }) end

-- The host reports a duel the game showed between two players of a live match when the loser has no addon to.
Du.Listen(function(w, l)
  local g = D:Current()
  local me = ns.Self()
  if l == me or ns.Comm.heard[l] then return end
  local m = Cu.MatchWith(g, w, l)
  if m and g.cups[m.cup].h == me then
    local c = g.cups[m.cup]
    local _, wins = Cu.Build(c)
    local op = { k = "cup_duel", id = m.cup, key = m.key, w = w, l = l }
    if ((wins[m.key] or {})[w] or 0) + 1 >= Cu.Need(c) then op.bk = Du.Book(g, m.id, w, l) end
    ns.Sync:Do(op)
  end
end)
