-- Assassins (SPEC §5, Arena): everyone signed up gets a secret target. Beat your target in a duel and you take
-- theirs. It runs a week; the last one standing wins (when the week ends with more standing, they are listed as the
-- ones still standing). A rank that may start games (SPEC §3.2, tourney) hosts it. Only members with the addon take
-- part: targets are secret, so they go by whisper.
--   asn       { days }          sign-up opens (its key is the game's id)
--   asn_join  { id, on }        the author signs up or leaves, while sign-up is open
--   asn_go    { id, p }         the host starts it: p, everyone who takes part
--   asn_kill  { id, v }         the author beat their target v in a duel (the author's own addon saw it)
-- The host's addon deals the targets (a circle in random order, kept only by the host) and whispers each player theirs:
--   ASN { id, t }   your target (from the host, or from the player you beat: their target is yours now)
--   ASQ { id }      asks the host for your target (after logging in, or when the one you beat did not say)
-- Who is still standing is worked out when read, from the kills in time order.
local _, ns = ...
local L, D, Comm = ns.L, ns.GuildData, ns.Comm

local As = {}
ns.Assassins = As
As.DAYS = 7
As.MIN = 3

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function host(id) return D.KeyAuthor(id) end

local function get(g, id)
  local all = D.Part(g, "assassins")
  all[id] = all[id] or { j = {}, k = {} }
  return all[id]
end

local function sound(e) return type(e) == "table" end

D:Register("asn", {
  allowed = function(g, author, op)
    local days = tonumber(op.days)
    return days ~= nil and days >= 1 and days <= 14 and days == math.floor(days) and D:Can("tourney", author, g)
  end,
  apply = function(g, author, op, t, n)
    local a = get(g, D.Key(author, n))
    a.h, a.days, a.t = author, op.days, t
    return true
  end,
  copy = function(g) return g.assassins end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and sound(e) then
        local a = get(g, id)
        if not a.h and party(e.h) and tonumber(e.days) and tonumber(e.t) then a.h, a.days, a.t = e.h, e.days, e.t end
        if not a.p and type(e.p) == "table" and tonumber(e.go) then a.p, a.go = e.p, e.go end
        for name, x in pairs(type(e.j) == "table" and e.j or {}) do
          if party(name) and type(x) == "table" and tonumber(x.t) and (not a.j[name] or x.t > a.j[name].t) then
            a.j[name] = { on = x.on == true, t = x.t }
          end
        end
        for v, x in pairs(type(e.k) == "table" and e.k or {}) do
          if party(v) and type(x) == "table" and party(x.by) and tonumber(x.t) and not a.k[v] then a.k[v] = { by = x.by, t = x.t } end
        end
      end
    end
  end,
})

D:Register("asn_join", {
  allowed = function(_, _, op) return host(op.id) ~= nil end,
  apply = function(g, author, op, t)
    local a = get(g, op.id)
    local cur = a.j[author]
    if cur and cur.t > t then return false end
    a.j[author] = { on = op.on ~= false, t = t }
    return true
  end,
})

D:Register("asn_go", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or type(op.p) ~= "table" or #op.p < 2 or #op.p > 200 then return false end
    for _, name in ipairs(op.p) do if not party(name) then return false end end
    return true
  end,
  apply = function(g, _, op, t)
    local a = get(g, op.id)
    if a.p then return false end
    a.p, a.go = op.p, t
    return true
  end,
})

D:Register("asn_kill", {
  allowed = function(_, author, op) return host(op.id) ~= nil and party(op.v) and op.v ~= author end,
  apply = function(g, author, op, t)
    local a = get(g, op.id)
    if a.k[op.v] and a.k[op.v].t <= t then return false end
    a.k[op.v] = { by = author, t = t }
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The newest game (any state), its id, and its state: "signup", "running" or "done".
function As.Current(g, now)
  now = now or time()
  local best, bestId
  for id, a in pairs(g and g.assassins or {}) do
    if a.h and (not best or a.t > best.t or (a.t == best.t and id > bestId)) then best, bestId = a, id end
  end
  if not best then return nil end
  return best, bestId, As.Phase(best, now)
end

-- Who still stands: the players in order, kills counted in time order (a kill counts while both still stand).
-- Returns the list standing, and { [name] = kills }.
function As.Standing(a)
  local out, kills = {}, {}
  if not a.p then return out, kills end
  local alive = {}
  for _, name in ipairs(a.p) do alive[name] = true end
  local list = {}
  for v, x in pairs(a.k) do list[#list + 1] = { v = v, by = x.by, t = x.t } end
  table.sort(list, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.v < y.v end)
  local left = #a.p
  for _, x in ipairs(list) do
    if left > 1 and alive[x.v] and alive[x.by] and (a.go + a.days * 86400) >= x.t then
      alive[x.v] = nil
      left = left - 1
      kills[x.by] = (kills[x.by] or 0) + 1
    end
  end
  for _, name in ipairs(a.p) do if alive[name] then out[#out + 1] = name end end
  return out, kills
end

function As.Phase(a, now)
  if not a.p then return "signup" end
  local standing = As.Standing(a)
  if #standing <= 1 or (now or time()) >= a.go + a.days * 86400 then return "done" end
  return "running"
end

-- Signed up, in the order they joined.
function As.Joined(a)
  local list = {}
  for name, x in pairs(a.j) do if x.on then list[#list + 1] = { name = name, t = x.t } end end
  table.sort(list, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.name < y.name end)
  local out = {}
  for i, x in ipairs(list) do out[i] = x.name end
  return out
end

-- The day of the game (1 to days).
function As.Day(a, now) return math.min(a.days, math.floor(((now or time()) - a.go) / 86400) + 1) end

---------------------------------------------------------------------------
-- Targets (this client)
---------------------------------------------------------------------------
-- What this account knows, per guild: targets[id] = name, and as host rings[id] = { names in the circle }.
local function store()
  ns.db.assassins = type(ns.db.assassins) == "table" and ns.db.assassins or {}
  local gid = D:Id() or "?"
  if type(ns.db.assassins[gid]) ~= "table" then ns.db.assassins[gid] = {} end
  local s = ns.db.assassins[gid]
  s.targets = type(s.targets) == "table" and s.targets or {}
  s.rings = type(s.rings) == "table" and s.rings or {}
  return s
end

function As.Target(id) return store().targets[id] end

-- The host's answer: the next one still standing after name in the circle.
local function nextUp(ring, standing, name)
  local up = {}
  for _, n in ipairs(standing) do up[n] = true end
  local at
  for i, n in ipairs(ring) do if n == name then at = i end end
  if not at then return nil end
  for step = 1, #ring - 1 do
    local n = ring[(at - 1 + step) % #ring + 1]
    if up[n] then return n end
  end
  return nil
end

function As.Open(days) return ns.Sync:Do({ k = "asn", days = days or As.DAYS }) end
function As.Join(id, on) return ns.Sync:Do({ k = "asn_join", id = id, on = on ~= false }) end

-- The host starts the game: everyone signed up takes part; the circle is dealt and each player told their target.
function As.Go(id)
  local g = D:Current()
  local a = g and g.assassins and g.assassins[id]
  if not a or a.h ~= ns.Self() or a.p then return false end
  local players = As.Joined(a)
  if #players < As.MIN then return false end
  if not ns.Sync:Do({ k = "asn_go", id = id, p = players }) then return false end
  local ring = {}
  for i, n in ipairs(players) do ring[i] = n end
  for i = #ring, 2, -1 do
    local j = math.random(1, i)
    ring[i], ring[j] = ring[j], ring[i]
  end
  store().rings[id] = ring
  for i, n in ipairs(ring) do As.Tell(id, n, ring[i % #ring + 1]) end
  return true
end

-- Tells name their target (to ourselves: straight into the store).
function As.Tell(id, name, target)
  if name == ns.Self() then
    store().targets[id] = target
    ns:Fire("ARENA")
  else
    Comm:Send(name, "ASN", { id = id, t = target }, true)
  end
end

-- Asks the host for our target (or works it out, as the host).
function As.Ask(id)
  local g = D:Current()
  local a = g and g.assassins and g.assassins[id]
  if not a or not a.p then return end
  if a.h == ns.Self() then
    local ring = store().rings[id]
    if ring then store().targets[id] = nextUp(ring, (As.Standing(a)), ns.Self()); ns:Fire("ARENA") end
  else
    Comm:Send(a.h, "ASQ", { id = id }, true)
  end
end

Comm:On("ASN", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" or not party(d.t) then return end
  local me = ns.Self()
  local s = store()
  -- From the host (it may come before the op that starts the game); or from the one we just beat (our target, or
  -- the one we beat last), passing on theirs.
  if sender == host(d.id) or sender == s.targets[d.id] or sender == s.beat then
    s.targets[d.id] = d.t ~= me and d.t or nil
    ns:Fire("ARENA")
  end
end)

Comm:On("ASQ", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" then return end
  local g = D:Current()
  local a = g and g.assassins and g.assassins[d.id]
  local ring = store().rings[d.id]
  if not a or a.h ~= ns.Self() or not ring then return end
  local standing = As.Standing(a)
  local up = false
  for _, n in ipairs(standing) do if n == sender then up = true end end
  if up then Comm:Send(sender, "ASN", { id = d.id, t = nextUp(ring, standing, sender) }, true) end
end)

-- A duel the game reported: our target beaten (a kill), or we were beaten (we tell the winner our target).
ns.Duels.Listen(function(w, l)
  local g = D:Current()
  local a, id, phase = As.Current(g)
  if not a or phase ~= "running" then return end
  local me, s = ns.Self(), store()
  local standing = As.Standing(a)
  local up = {}
  for _, n in ipairs(standing) do up[n] = true end
  if not up[w] or not up[l] then return end
  if w == me and s.targets[id] == l then
    s.beat, s.targets[id] = l, nil
    ns.Sync:Do({ k = "asn_kill", id = id, v = l })
    ns:Print(L.AS_KILL:format(ns.Display(l)), true)
    -- The one we beat tells us their target; if they do not, the host does.
    C_Timer.After(5, function() if not store().targets[id] then As.Ask(id) end end)
  elseif l == me and s.targets[id] then
    Comm:Send(w, "ASN", { id = id, t = s.targets[id] }, true)
  end
end)

-- After login: ask for our target if we take part and do not know it.
ns:On("ROSTER", function()
  if As.asked then return end
  local g = D:Current()
  local a, id, phase = As.Current(g)
  if not a or phase ~= "running" or As.Target(id) then return end
  for _, n in ipairs(As.Standing(a)) do
    if n == ns.Self() then As.asked = true; As.Ask(id) end
  end
end)
