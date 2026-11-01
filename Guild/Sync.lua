-- Changes to the guild's data, sent on the guild addon channel (docs/ARCHITECTURE.md §3). The model is Journey's
-- (Fellowship/Sync.lua): every change is an op that carries who made it (a, the character) and that character's own
-- count (n). Each copy knows the highest count it has taken of every author (g.seen) and keeps its latest ops (the op
-- log, ns.db.oplog, not sent) to pass on to members who missed them.
--   OP     one op, to the guild (also an op passed on for someone else: a is then not the sender)
--   HELLO  at login: "this is what I have" (g.seen), to the guild
--   HAVE   answer to a HELLO, by whisper: how many ops I can give you, and which of yours I am missing
--   OPQ    "send me what I am missing" (with g.seen)            OPS / COPY  the ops, or a whole copy
--   HI     answer to a HELLO with nothing to give or ask: "I have the addon too" (so the Tavern knows who plays)
-- An op is taken in each author's order: one that skips ahead waits while the missing ones are asked for. Every
-- addon checks the author's rank (Guild/Data.lua, kinds) when taking an op; an op the author was not allowed to make
-- is counted as seen and changes nothing.
-- The rules live in an engine: ns.Sync is this client's. The self-test's pretend members (Dev/Peers.lua) each run an
-- engine of their own, with their own copy, log and messages, so they answer exactly as another addon would.
local _, ns = ...
local D, Comm, R = ns.GuildData, ns.Comm, ns.Roster

local E = {}
E.__index = E
E.LOG_MAX = 500     -- ops each addon keeps per guild
E.HELLO_DELAY = 5   -- seconds after login (and the roster) before saying HELLO
E.OFFER_WAIT = 4    -- seconds to collect HAVE answers
E.ASK_EVERY = 30    -- at most one OPQ per member in this many seconds
E.PUBLISH_WAIT = 2  -- the Guild Master's settings go out this long after the last change
E.WAITING_MAX = 200

-- io = { me = function() -> "Name-Realm", guild = function() -> g or nil, log = function(g) -> op list,
--        opn = { [name] = last count }, send = function(target, tag, data, urgent), main = true for this client }
local function new(io)
  return setmetatable({ io = io, held = {}, waiting = {}, asked = {}, hello = nil }, E)
end

function E:Reset()
  self.held, self.waiting, self.asked, self.hello, self.publishAt = {}, {}, {}, nil, nil
end

local function changed(self)
  if self.io.main then ns:Fire("GUILD_DATA") end
end

-- The next count for an op made here. Never below what any copy has seen of this character (saved data lost).
function E:NextN(g, me)
  local opn = self.io.opn()
  local n = math.max(opn[me] or 0, g.seen[me] or 0) + 1
  opn[me] = n
  return n
end

-- A count of this character seen elsewhere (a copy that knew more than this one).
function E:Bump(seen)
  local me = self.io.me()
  local n = type(seen) == "table" and tonumber(seen[me])
  if n then
    local opn = self.io.opn()
    opn[me] = math.max(opn[me] or 0, n)
  end
end

-- Takes an op this copy has not seen: counts it, logs it, and applies it if its author was allowed. made: the op was
-- made here, just now (E:Do).
function E:Take(g, a, n, t, op, made)
  g.seen[a] = n
  local l = self.io.log(g)
  l[#l + 1] = { a = a, n = n, t = t, op = op }
  while #l > self.LOG_MAX do table.remove(l, 1) end
  g.heard = time()
  if D:Allowed(g, a, op, t) then
    -- Before and after it changes the copy: announcements and alerts (Guild/Announce.lua, UI/Alerts.lua).
    if self.io.main then ns:Fire("OP_BEFORE", g, a, op, t, n) end
    D:Apply(g, a, op, t, n)
    if self.io.main then ns:Fire("OP", g, a, op, t, n, made == true) end
  end
  changed(self)
end

-- Makes an op here and sends it to the guild. Returns true and the op's key ("author:n", what the op's entries are
-- filed under: D.Key), or false when this character may not make it (or has no guild).
function E:Do(op)
  local g = self.io.guild()
  local me = self.io.me()
  if not g then return false end
  -- (Opted out of punishment: the places that closes say so, SPEC decision 69.)
  if ns.Rules and ns.Rules.Blocked(g, me, op, time()) then ns:Print(ns.L.RU_CANT_OPTED, true) return false end
  if not D:Allowed(g, me, op, time()) then return false end
  local n, t = self:NextN(g, me), time()
  self:Take(g, me, n, t, op, true)
  self.io.send(Comm.GUILD, "OP", { g = g.id, a = me, n = n, t = t, op = op })
  return true, D.Key(me, n)
end

-- An op from the guild channel, a list (OPS) or the queue below. from: who sent it (asked when one is missing).
function E:Incoming(g, a, n, t, op, from)
  if type(a) ~= "string" or type(op) ~= "table" or type(op.k) ~= "string" then return end
  n, t = tonumber(n), tonumber(t) or 0
  if not n or n <= (g.seen[a] or 0) then return end
  -- The roster has not arrived: authority cannot be checked yet.
  if not R:Ready() then
    if #self.waiting < self.WAITING_MAX then self.waiting[#self.waiting + 1] = { g.id, a, n, t, op, from } end
    return
  end
  if a == self.io.me() then self:Bump({ [a] = n }) end
  local held = self.held[a] or {}
  self.held[a] = held
  if n > (g.seen[a] or 0) + 1 then
    held[n] = { t, op }
    self:Ask(from, g)
    return
  end
  self:Take(g, a, n, t, op)
  -- Ops of this author that came early and waited.
  local nxt = held[g.seen[a] + 1]
  while nxt do
    held[g.seen[a] + 1] = nil
    self:Take(g, a, g.seen[a] + 1, nxt[1], nxt[2])
    nxt = held[g.seen[a] + 1]
  end
end

function E:Ask(name, g)
  if not name or name == self.io.me() then return end
  local last = self.asked[name]
  if last and GetTime() - last < self.ASK_EVERY then return end
  self.asked[name] = GetTime()
  self.io.send(name, "OPQ", { g = g.id, seen = g.seen }, true)
end

local function cleanSeen(seen)
  local out = {}
  if type(seen) ~= "table" then return out end
  for a, n in pairs(seen) do if type(a) == "string" and tonumber(n) then out[a] = tonumber(n) end end
  return out
end

-- The ops this copy has that seen lacks, oldest first; covered is false when the log no longer reaches back to the
-- first of them for some author (a whole copy is needed then).
function E:Missing(g, seen)
  local list, first = {}, {}
  for _, e in ipairs(self.io.log(g)) do
    if e.n > (seen[e.a] or 0) then
      list[#list + 1] = e
      first[e.a] = math.min(first[e.a] or e.n, e.n)
    end
  end
  for a, n in pairs(g.seen) do
    if n > (seen[a] or 0) and first[a] ~= (seen[a] or 0) + 1 then return list, false end
  end
  return list, true
end

-- How many ops this copy has that seen lacks, and which authors seen is ahead on (from which count).
local function compare(g, seen)
  local give, want = 0, nil
  for a, n in pairs(g.seen) do if n > (seen[a] or 0) then give = give + n - (seen[a] or 0) end end
  for a, n in pairs(seen) do
    if n > (g.seen[a] or 0) then want = want or {}; want[a] = (g.seen[a] or 0) + 1 end
  end
  return give, want
end

---------------------------------------------------------------------------
-- Catching up at login: HELLO, the HAVE answers, then OPQ to the member who can give the most.
---------------------------------------------------------------------------
function E:Hello()
  local g = self.io.guild()
  if not g then return end
  self.hello = { id = g.id, offers = {}, want = {} }
  self.io.send(Comm.GUILD, "HELLO", { g = g.id, seen = g.seen, v = ns.VERSION })
  C_Timer.After(self.OFFER_WAIT, function() self:Choose() end)
end

function E:Choose()
  local h, g = self.hello, self.io.guild()
  self.hello = nil
  if not h or not g or g.id ~= h.id then return end
  local best, most = nil, 0
  for name, give in pairs(h.offers) do
    if give > most or (give == most and best and name < best) then best, most = name, give end
  end
  if best then
    self.asked[best] = GetTime()
    self.io.send(best, "OPQ", { g = g.id, seen = g.seen }, true)
  end
  -- What others are missing of ours: passed on to the whole guild once (the others skip what they already have).
  if next(h.want) then self:PassOn(g, h.want) end
  g.heard = time()
  changed(self)
end

-- Sends to the guild the logged ops of each author from count want[author] on.
function E:PassOn(g, want)
  for _, e in ipairs(self.io.log(g)) do
    local from = want[e.a]
    if from and e.n >= from then self.io.send(Comm.GUILD, "OP", { g = g.id, a = e.a, n = e.n, t = e.t, op = e.op }) end
  end
end

---------------------------------------------------------------------------
-- The Guild Master's settings: changed at once here, sent to the guild PUBLISH_WAIT seconds after the last change.
---------------------------------------------------------------------------
function E:ChangeSettings(fn)
  local g = self.io.guild()
  if not g or not D:InCharge(self.io.me(), g) then return false end
  local s = D.Sanitize(g.settings)
  fn(s)
  g.settings = D.Clean(D.Sanitize(s), true)
  if self.io.main then ns:Fire("GUILD_SETTINGS") end
  self.publishAt = GetTime() + self.PUBLISH_WAIT
  C_Timer.After(self.PUBLISH_WAIT, function()
    if self.publishAt and GetTime() >= self.publishAt then self:PublishSettings() end
  end)
  return true
end

function E:PublishSettings()
  self.publishAt = nil
  local g = self.io.guild()
  if not g then return false end
  return self:Do({ k = "settings", s = g.settings, sv = g.sv + 1 })
end

-- A new Guild Master (a hand-over) publishes the settings as theirs, so every copy has them from someone who is the
-- Guild Master now: copies check the author's rank today.
function E:Adopt()
  local g = self.io.guild()
  local me = self.io.me()
  if g and g.sa and g.sa ~= me and R:IsGM(me) and not self.publishAt then self:PublishSettings() end
end

-- The roster arrived (or changed): ops that waited for it are taken.
function E:RosterReady()
  local list = self.waiting
  self.waiting = {}
  local g = self.io.guild()
  for _, w in ipairs(list) do
    if g and w[1] == g.id then self:Incoming(g, w[2], w[3], w[4], w[5], w[6]) end
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local receive = {}

receive.OP = function(self, g, sender, d, channel)
  if channel == Comm.GUILD then self:Incoming(g, d.a, d.n, d.t, d.op, sender) end
end

receive.HELLO = function(self, g, sender, d, channel)
  if channel ~= Comm.GUILD then return end
  local give, want = compare(g, cleanSeen(d.seen))
  if give > 0 or want then self.io.send(sender, "HAVE", { g = g.id, give = give, want = want, seen = g.seen }, true)
  else self.io.send(sender, "HI", { g = g.id }) end
end

receive.HI = function() end

receive.HAVE = function(self, g, sender, d)
  local h = self.hello
  if not h or h.id ~= g.id then return end
  self:Bump(d.seen)
  local give = tonumber(d.give) or 0
  if give > 0 then h.offers[sender] = give end
  for a, n in pairs(cleanSeen(d.want)) do h.want[a] = math.min(h.want[a] or n, n) end
end

receive.OPQ = function(self, g, sender, d)
  local list, covered = self:Missing(g, cleanSeen(d.seen))
  if not covered then
    self.io.send(sender, "COPY", { g = g.id, copy = D:Copy(g), seen = g.seen })
  elseif #list > 0 then
    self.io.send(sender, "OPS", { g = g.id, list = list, seen = g.seen })
  end
end

receive.OPS = function(self, g, sender, d)
  if type(d.list) ~= "table" then return end
  self:Bump(d.seen)
  local list = {}
  for _, e in ipairs(d.list) do if type(e) == "table" then list[#list + 1] = e end end
  table.sort(list, function(x, y)
    if x.a ~= y.a then return tostring(x.a) < tostring(y.a) end
    return (tonumber(x.n) or 0) < (tonumber(y.n) or 0)
  end)
  for _, e in ipairs(list) do self:Incoming(g, e.a, e.n, e.t, e.op, sender) end
end

-- A whole copy: each kind merges its part (the newest wins), and every author's count moves up to the copy's. Ops
-- this copy has that the sender lacks are passed on to the guild.
receive.COPY = function(self, g, _, d)
  if not R:Ready() then return end
  local seen = cleanSeen(d.seen)
  self:Bump(seen)
  D:Merge(g, d.copy)
  for a, n in pairs(seen) do
    if n > (g.seen[a] or 0) then g.seen[a] = n; self.held[a] = nil end
  end
  g.heard = time()
  changed(self)
  local _, theyLack = compare({ seen = seen }, g.seen)
  if theyLack then self:PassOn(g, theyLack) end
end

-- A message for this engine. Only about its own guild.
function E:Receive(tag, sender, d, channel)
  local fn = receive[tag]
  local g = fn and type(d) == "table" and self.io.guild()
  if g and d.g == g.id then fn(self, g, sender, d, channel) end
end

---------------------------------------------------------------------------
-- This client's engine
---------------------------------------------------------------------------
local S = new({
  main = true,
  me = function() return ns.Self() end,
  guild = function() return D:Current() end,
  log = function(g)
    ns.db.oplog = type(ns.db.oplog) == "table" and ns.db.oplog or {}
    if type(ns.db.oplog[g.id]) ~= "table" then ns.db.oplog[g.id] = {} end
    return ns.db.oplog[g.id]
  end,
  opn = function()
    ns.db.opn = type(ns.db.opn) == "table" and ns.db.opn or {}
    return ns.db.opn
  end,
  send = function(target, tag, data, urgent) Comm:Send(target, tag, data, urgent) end,
})
ns.Sync = S
S.Engine, S.New = E, new

for tag in pairs(receive) do
  Comm:On(tag, function(sender, d, channel) S:Receive(tag, sender, d, channel) end)
end

-- When to say HELLO: at login and when the guild changes, once the roster is in.
function S:Start()
  self:Reset()
  self.guildId = D:Id()
  if not self.guildId then return end
  C_Timer.After(self.HELLO_DELAY, function()
    if R:Ready() then S:Hello() else S.helloAfterRoster = true end
  end)
end

ns:On("LOGIN", function() S:Start() end)
ns:On("GUILD_CHANGED", function()
  if D:Id() ~= S.guildId then S:Start() end
end)

ns:On("ROSTER", function()
  if not R:Ready() then return end
  S:RosterReady()
  if S.helloAfterRoster then
    S.helloAfterRoster = nil
    S:Hello()
  end
  S:Adopt()
end)
