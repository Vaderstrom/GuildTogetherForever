-- The self-test's pretend guild. While it runs:
-- * this client's guild data is a pretend guild ("Selftest-<realm>"), so the real guild's data is never touched;
-- * the roster is pretend (Roster.pretend): this character is its Guild Master, with four pretend members below;
-- * every addon message is caught (ns.Dev:Intercept, called by Core/Comm.lua) and goes to the pretend members
--   (Dev/Peers.lua) instead of the real guild. Nothing is sent to other players.
-- Stop puts everything back: the pretend guild's data is removed and the real guild's catch-up runs again.
local _, ns = ...
local D, R, Pe = ns.GuildData, ns.Roster, ns.Peers
local SB = {}
ns.Sandbox = SB

SB.RANKS = { "Guild Master", "Officer", "Veteran", "Member", "Trial" }
SB.MEMBERS = { { "Mirelle", 1, "PRIEST" }, { "Korgath", 2, "WARRIOR" }, { "Fenwick", 3, "PALADIN" }, { "Odo", 4, "ROGUE" } }
-- Shorter waits while it runs, so the self-test takes seconds (restored by Stop).
SB.FAST = { HELLO_DELAY = 0.2, OFFER_WAIT = 1, PUBLISH_WAIT = 0.5, ASK_EVERY = 0 }

ns.Dev = ns.Dev or {}
function ns.Dev:Intercept(target, tag, data)
  if not SB.active then return false end
  Pe:FromClient(target, tag, data)
  return true
end

-- A test-only kind of op: "name used action" (SPEC §3.2 permissions, before the pages that use them exist). Counted
-- in g.probes when the author's rank may do the action. Only ever made in the pretend guild.
D:Register("probe", {
  allowed = function(g, author, op) return type(op.action) == "string" and D:Can(op.action, author, g) end,
  apply = function(g, author)
    g.probes = g.probes or {}
    g.probes[author] = (g.probes[author] or 0) + 1
    return true
  end,
})

local function wipeGuild(id)
  ns.db.guilds[id] = nil
  if type(ns.db.oplog) == "table" then ns.db.oplog[id] = nil end
  if type(ns.db.assassins) == "table" then ns.db.assassins[id] = nil end
  if type(ns.db.stocks) == "table" then ns.db.stocks[id] = nil end
  ns.Games.caught, ns.Games.there, ns.Games.reached, ns.Games.fallen = {}, {}, {}, {}
  if type(ns.db.traitors) == "table" then ns.db.traitors[id] = nil end
  if type(ns.db.seen) == "table" then ns.db.seen[id] = nil end
  if type(ns.db.santa) == "table" then ns.db.santa[id] = nil end
  if type(ns.db.handed) == "table" then wipe(ns.db.handed) end
end

-- members: { { name, rank, class }, ... } (SB.MEMBERS when nil; the demo guild brings its own, Dev/Demo.lua).
function SB:Start(members)
  if self.active then return end
  local E, me = ns.Sync.Engine, ns.Self()
  self.saved = {}
  for k, v in pairs(self.FAST) do self.saved[k] = E[k]; E[k] = v end
  -- Our op count belongs to the real guild: put back afterwards (the others would wait for counts never sent).
  ns.db.opn = type(ns.db.opn) == "table" and ns.db.opn or {}
  self.opn = ns.db.opn[me]
  self.id = "Selftest-" .. ns.Realm()
  wipeGuild(self.id)
  -- (Saved too: a /reload in the middle is put right at the next login.)
  ns.db.sandbox = { id = self.id, opn = self.opn }
  D.sandbox = self.id
  R.pretend = { ranks = { [me] = 0 }, names = self.RANKS, classes = { [me] = UnitClass and select(2, UnitClass("player")) } }
  Pe:Forget()
  -- The pretend members stand near you (face to face, SPEC decision 72), unless a check sends one away (SB:Near).
  local Lk = ns.Looks
  Lk.pretend = Lk.pretend or {}
  self.near = {}
  for _, m in ipairs(members or self.MEMBERS) do
    local p = Pe:Add(m[1], self.id)
    R.pretend.ranks[p.name] = m[2]
    R.pretend.classes[p.name] = m[3]
    self.near[p.name] = true
    rawset(Lk.pretend, p.name, true)
  end
  -- The pretend guild is a Democracy whose incidents are judged directly, as the guild worked before setups (SPEC
  -- decision 70).
  self:Govern("democracy", members)
  self.active = true
  ns.Dice.silent = true
  ns.Sync:Reset()
  ns.Sync.guildId = self.id
  ns:Fire("GUILD_SETTINGS")
  for _, p in ipairs(Pe:Online()) do Pe:Claim(p) end
end

-- The pretend guild's setup, on our copy and every pretend member's, as if it had always been so (nothing running is
-- cancelled). Incidents are judged directly. While it runs, our addon publishes it too (when in charge), so settings
-- still on their way do not bring the old one back: wait for SB:Governed. opt: { elect } (a Democracy's election).
function SB:Govern(setup, members, opt)
  local elect = opt and opt.elect or nil
  local function govern(gg)
    gg.settings.gov = { setup = setup, at = 1, elect = elect }
    gg.settings.pun.incidents = "direct"
  end
  govern(D:Get(self.id))
  for _, m in ipairs(members or self.MEMBERS) do
    local p = Pe:Get(m[1])
    if p and p.g then govern(p.g) end
  end
  if self.active then ns.Sync:ChangeSettings(function(s) s.gov = { setup = setup, at = 1, elect = elect } end) end
end

-- Has every copy the setup, with our newest settings?
function SB:Governed(setup)
  local mine = D:Get(self.id)
  if ns.Rules.Setup(mine) ~= setup then return false end
  for _, p in ipairs(Pe:Online()) do
    if p.g.sv ~= mine.sv or ns.Rules.Setup(p.g) ~= setup then return false end
  end
  return true
end

-- A rank changes in the pretend roster (a hand-over): every addon hears of it, as from the game's roster.
function SB:SetRank(name, rank)
  if not self.active then return end
  R.pretend.ranks[Pe:Full(name)] = rank
  ns:Fire("ROSTER")
  for _, p in ipairs(Pe:Online()) do p.engine:Adopt() end
end

function SB:Near(name, on)
  local full = Pe:Full(name)
  rawset(ns.Looks.pretend, full, on == true)
  ns:Fire("NEAR")
end

function SB:Stop()
  if not self.active then return end
  local E = ns.Sync.Engine
  for k, v in pairs(self.saved) do E[k] = v end
  self.active = false
  self.demo = nil
  -- A deathroll or duel challenge with a pretend member is dropped (it would whisper a realm that does not exist).
  local function pretend(name) return type(name) == "string" and name:find("-" .. Pe.REALM, 1, true) ~= nil end
  if ns.Deathroll.game and pretend(ns.Deathroll.game.opp) then ns.Deathroll.game = nil end
  if ns.Duels.ch and pretend(ns.Duels.ch.opp) then ns.Duels.ch = nil end
  ns.Council.offset = 0
  ns.Dice.silent = nil
  for name in pairs(self.near or {}) do rawset(ns.Looks.pretend, name, nil) end
  self.near = nil
  D.sandbox = nil
  R.pretend = nil
  wipeGuild(self.id)
  ns.db.opn[ns.Self()] = self.opn
  ns.db.sandbox = nil
  Pe:Forget()
  R:Refresh()
  ns.Sync:Start()
  ns:Fire("GUILD_SETTINGS")
end

-- A self-test cut short by a /reload or logout: put back what Stop would have.
ns:On("DB_READY", function()
  local s = ns.db.sandbox
  if type(s) ~= "table" then return end
  if type(s.id) == "string" then wipeGuild(s.id) end
  ns.db.opn = type(ns.db.opn) == "table" and ns.db.opn or {}
  ns.db.opn[ns.Self()] = tonumber(s.opn)
  ns.db.sandbox = nil
end)
