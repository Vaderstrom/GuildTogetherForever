-- Pretend members for the self-test (Dev/SelfTest.lua), so the paths that normally need several accounts run in one
-- client. Each pretend member runs a sync engine of its own (Guild/Sync.lua, Sync.New) with its own copy of the
-- guild, its own op log and its own counts: it answers exactly as another player's addon would, because it is the
-- same code. Messages between this client and the pretend members go through the serializer and arrive a moment
-- later, as over the wire; nothing leaves the client (Dev/Sandbox.lua catches every message while it runs).
-- A pretend member that is offline sends and receives nothing. Nothing is saved.
local _, ns = ...
local D, Comm = ns.GuildData, ns.Comm
local Pe = { list = {}, DELAY = 0 }
ns.Peers = Pe

-- Through the serializer, as a real message would be.
local function wire(t) return (ns.Serialize.Decode(ns.Serialize.Encode(t))) end

local function later(fn) C_Timer.After(Pe.DELAY, fn) end

-- Pretend members live on a realm that does not exist ("Mirelle-Selftest"), so they can never be a real character,
-- this one included.
Pe.REALM = "Selftest"
function Pe:Full(name) return name:find("-", 1, true) and name or (name .. "-" .. self.REALM) end

function Pe:Get(name) return name and self.list[self:Full(name)] or nil end

-- Each online pretend member, in name order (the same order every run).
function Pe:Online()
  local out = {}
  for _, p in pairs(self.list) do if p.online then out[#out + 1] = p end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- A pretend member of guild id, online, with an empty copy (as a member who just installed the addon).
function Pe:Add(name, id)
  local full = self:Full(name)
  local p = { name = full, online = true, got = {}, log = {}, opn = {} }
  p.g = { id = id, settings = D.Defaults(), sv = 0, seen = {} }
  p.engine = ns.Sync.New({
    me = function() return full end,
    guild = function() return p.g end,
    log = function() return p.log end,
    opn = function() return p.opn end,
    send = function(target, tag, data) Pe:FromPeer(p, target, tag, data) end,
  })
  -- Its own deathroll: it accepts every challenge and rolls by itself (a fair roll, as the game's).
  p.dice = ns.Deathroll.New({
    me = function() return full end,
    send = function(target, tag, data) Pe:FromPeer(p, target, tag, data) end,
    sync = p.engine,
    auto = true,
    roll = function(max) later(function() p.dice:Rolled(math.random(1, max), 1, max) end) end,
  })
  -- Its own duel challenges (Guild/Duels.lua): it accepts every challenge, and writes the result when it loses.
  p.duel = ns.Duels.New({
    me = function() return full end,
    g = function() return p.g end,
    send = function(target, tag, data) Pe:FromPeer(p, target, tag, data) end,
    sync = p.engine,
    auto = true,
  })
  self.list[full] = p
  return p
end

-- Its "player" op, as every addon sends at login: it has Guild Together, so it is a player of its own (an account id made
-- from its name), and may be punished, warned, charged and taxed (SPEC decision 56).
function Pe:Claim(p)
  local h = 5381
  for i = 1, #p.name do h = (h * 33 + p.name:byte(i)) % 4294967296 end
  p.id = ("#%08x"):format(h)
  return p.engine:Do({ k = "player", id = p.id, c = { p.name }, m = p.name })
end

-- A duel the game shows (the self-test's pretend one): this client and every online pretend member see it.
function Pe:Duel(winner, loser) ns.Duels.Heard(self:Full(winner), self:Full(loser)) end

ns.Duels.Listen(function(w, l)
  for _, p in pairs(Pe.list) do if p.online then p.duel:Seen(w, l) end end
end)

function Pe:Forget() wipe(self.list) end

function Pe:SetOnline(name, on)
  local p = self:Get(name)
  if p then p.online = on and true or false end
end

-- A message reaches a pretend member (counted by tag, so the self-test can see who was asked).
local function deliver(p, tag, sender, data, channel)
  if not p.online then return end
  p.got[tag] = (p.got[tag] or 0) + 1
  local d = wire(data)
  p.engine:Receive(tag, sender, d, channel)
  p.dice:Receive(tag, sender, d, channel)
  p.duel:Receive(tag, sender, d, channel)
end

-- What a pretend member sends: to the guild (this client and every other online member), or by whisper. lose: the
-- next message never arrives anywhere (lost in a fight).
function Pe:FromPeer(p, target, tag, data)
  if not p.online then return end
  if p.lose then p.lose = nil return end
  local me = ns.Self()
  if target == Comm.GUILD then
    later(function() Comm:Inject(p.name, tag, wire(data), "GUILD") end)
    for _, q in ipairs(self:Online()) do
      if q ~= p then later(function() deliver(q, tag, p.name, data, "GUILD") end) end
    end
  elseif target == me then
    later(function() Comm:Inject(p.name, tag, wire(data), "WHISPER") end)
  elseif self.list[target] then
    later(function() deliver(self.list[target], tag, p.name, data, "WHISPER") end)
  end
end

-- What this client sends while the sandbox runs (Dev/Sandbox.lua): to the pretend guild, or to one of them.
function Pe:FromClient(target, tag, data)
  local me = ns.Self()
  if target == Comm.GUILD then
    for _, q in ipairs(self:Online()) do later(function() deliver(q, tag, me, data, "GUILD") end) end
  elseif self.list[target] then
    later(function() deliver(self.list[target], tag, me, data, "WHISPER") end)
  end
end

-- The pretend member makes an op (checked by its own addon first, as a real one would). lost: nobody gets it.
function Pe:Do(name, op, lost)
  local p = self:Get(name)
  if not p then return false end
  p.lose = lost or nil
  local ok = p.engine:Do(op)
  if not ok then p.lose = nil end
  return ok
end

-- A changed addon: sends the op even though its own rules say no. Every other addon must ignore it.
function Pe:Forge(name, op)
  local p = self:Get(name)
  if not p then return end
  local e = p.engine
  local n, t = e:NextN(p.g, p.name), time()
  p.g.seen[p.name] = n
  p.log[#p.log + 1] = { a = p.name, n = n, t = t, op = op }
  self:FromPeer(p, Comm.GUILD, "OP", { g = p.g.id, a = p.name, n = n, t = t, op = op })
end
