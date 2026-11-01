-- Roll-off night (SPEC §8, Tavern): everyone who joined rolls 1 to the host's number; the highest takes the
-- difference from the lowest, in the purse. A rank that may start games (SPEC §3.2, tourney) hosts it.
--   rolloff       { max }               the host opens it (its key is the roll-off's id)
--   rolloff_join  { id }                a member with Guild Together joins
--   rolloff_go    { id }                the host calls the roll
--   rolloff_roll  { id, v }             a roll the roller's own addon saw
--   rolloff_end   { id, hi, lo, amt, p, max }   the host's result: lo pays amt to hi
-- Only players with Guild Together take part: nothing keeps score of a member without it (SPEC decision 56).
-- Ops from different players may arrive in any order: each one is checked on its own (the host is the author of the
-- id, D.KeyAuthor), and one that comes before the roll-off it belongs to waits in a stub.
local _, ns = ...
local D, Pu = ns.GuildData, ns.Purse
local RO = {}
ns.RollOff = RO

RO.MAX_MAX = 100000
local ORDER = { open = 1, rolling = 2, done = 3 }

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end

local function get(g, id)
  local all = D.Part(g, "rolloffs")
  local ro = all[id]
  if not ro then
    ro = { j = {}, r = {}, st = "open" }
    all[id] = ro
  end
  return ro
end

local function advance(ro, st) if ORDER[st] > (ORDER[ro.st] or 1) then ro.st = st end end

D:Register("rolloff", {
  allowed = function(g, author, op) return whole(op.max, 2, RO.MAX_MAX) and Pu.IsPurse(op.p) and D:Can("games", author, g) end,
  apply = function(g, author, op, t, n)
    local ro = get(g, D.Key(author, n))
    ro.h, ro.max, ro.p, ro.t = author, op.max, op.p, t
    return true
  end,
  copy = function(g) return g.rolloffs end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, theirs in pairs(part) do
      if type(id) == "string" and host(id) and type(theirs) == "table" then
        local ro = get(g, id)
        if not ro.h and party(theirs.h) and whole(theirs.max, 2, RO.MAX_MAX) and Pu.IsPurse(theirs.p) then
          ro.h, ro.max, ro.p, ro.t = theirs.h, theirs.max, theirs.p, tonumber(theirs.t)
        end
        for name in pairs(type(theirs.j) == "table" and theirs.j or {}) do if party(name) then ro.j[name] = true end end
        for name, v in pairs(type(theirs.r) == "table" and theirs.r or {}) do
          if party(name) and ro.r[name] == nil and whole(v, 1, RO.MAX_MAX) then ro.r[name] = v end
        end
        if ORDER[theirs.st] then advance(ro, theirs.st) end
        if theirs.st == "done" and ro.amt == nil and whole(theirs.amt, 0, RO.MAX_MAX) then
          ro.hi, ro.lo, ro.amt = theirs.hi, theirs.lo, theirs.amt
        end
      end
    end
  end,
})

D:Register("rolloff_join", {
  allowed = function(_, _, op) return host(op.id) ~= nil end,
  apply = function(g, author, op)
    get(g, op.id).j[author] = true
    return true
  end,
})

D:Register("rolloff_go", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op)
    advance(get(g, op.id), "rolling")
    return true
  end,
})

D:Register("rolloff_roll", {
  allowed = function(_, _, op) return host(op.id) ~= nil and whole(op.v, 1, RO.MAX_MAX) end,
  apply = function(g, author, op)
    local ro = get(g, op.id)
    -- The first roll counts.
    if ro.r[author] == nil then ro.r[author] = op.v end
    return true
  end,
})

D:Register("rolloff_end", {
  allowed = function(_, author, op)
    return host(op.id) == author and Pu.IsPurse(op.p) and whole(op.amt, 0, RO.MAX_MAX)
      and (op.amt == 0 or (party(op.hi) and party(op.lo) and op.hi ~= op.lo))
  end,
  apply = function(g, author, op, t, n)
    local ro = get(g, op.id)
    advance(ro, "done")
    ro.hi, ro.lo, ro.amt, ro.p, ro.max = op.hi, op.lo, op.amt, op.p, ro.max or op.max
    ro.te = t   -- when it ended (its scene plays for whoever opens it soon after, SPEC decision 60)
    if op.amt > 0 then Pu:Charge(g, D.Key(author, n), op.lo, op.hi, op.amt, op.p, "rolloff", t) end
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The roll-off to show: the newest one not done; else the newest done one. Nil when there was none.
function RO:Current(g)
  g = g or D:Current()
  local best, bestId
  for id, ro in pairs(g and g.rolloffs or {}) do
    if ro.h then
      local open = ro.st ~= "done"
      local better = not best or (open and best.st == "done")
        or (open == (best.st ~= "done") and ((ro.t or 0) > (best.t or 0) or ((ro.t or 0) == (best.t or 0) and id > bestId)))
      if better then best, bestId = ro, id end
    end
  end
  return best, bestId
end

-- The rolls that count (joined, within the range), highest first: { { name, v }, ... }.
function RO:Rolls(ro)
  local list = {}
  for name, v in pairs(ro.r) do
    if ro.j[name] and v >= 1 and v <= (ro.max or 0) then list[#list + 1] = { name = name, v = v } end
  end
  table.sort(list, function(a, b)
    if a.v ~= b.v then return a.v > b.v end
    return a.name < b.name
  end)
  return list
end

function RO:Joined(ro)
  local list = {}
  for name in pairs(ro.j) do list[#list + 1] = name end
  table.sort(list)
  return list
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
function RO:Start(max) return ns.Sync:Do({ k = "rolloff", max = tonumber(max), p = D:Settings().purse }) end
-- Joining is face to face with the host (SPEC decision 72).
function RO:Join(id)
  local g = D:Current()
  local ro = g and g.rolloffs and g.rolloffs[id]
  if ro and ro.h and not ns.Looks.Need(ro.h) then return false end
  return ns.Sync:Do({ k = "rolloff_join", id = id })
end
function RO:Go(id) return ns.Sync:Do({ k = "rolloff_go", id = id }) end

-- The host ends it: the highest roll takes the difference from the lowest (ties: the name first in order).
function RO:Finish(id)
  local g = D:Current()
  local ro = g and g.rolloffs and g.rolloffs[id]
  if not ro or ro.h ~= ns.Self() or ro.st == "done" then return false end
  local rolls = self:Rolls(ro)
  local op = { k = "rolloff_end", id = id, p = ro.p, max = ro.max, amt = 0 }
  if #rolls >= 2 then
    local hi, lo = rolls[1], rolls[#rolls]
    op.hi, op.lo, op.amt = hi.name, lo.name, hi.v - lo.v
  end
  return ns.Sync:Do(op)
end

-- Our own roll seen in the game, once we joined.
ns.Dice:Listen(function(name, v, lo, hi)
  if name ~= ns.Self() then return end
  local ro, id = RO:Current(D:Current())
  if not ro or ro.st ~= "rolling" or lo ~= 1 or hi ~= ro.max or not ro.j[name] or ro.r[name] ~= nil then return end
  ns.Sync:Do({ k = "rolloff_roll", id = id, v = v })
end)
