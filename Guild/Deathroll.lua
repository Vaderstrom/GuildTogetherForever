-- Deathroll (SPEC §8, Tavern): two players roll down from a starting number until someone rolls 1; that player owes
-- the stake. The challenger picks the stake and the starting number (100 x the stake unless changed, decided
-- 29 Oct 2026) and rolls first. Only the game's own /roll results count (Guild/Dice.lua): each player's own addon
-- reads its player's roll and tells the other one. The game itself goes by whisper between the two addons:
--   DRC  a challenge { id, amt, p (purse), s (start) }     DRA  accepted { id }
--   DRN  declined or called off { id, busy }               DRR  a roll { id, i (its number), v }
-- The loser's addon writes the result for the guild (the "deathroll" op): the debt, or the Marks moved.
-- Face to face (SPEC decision 72): a challenge is sent and accepted only while the other player is near you (io.near);
-- walking away after that does not stop the game.
-- The rules are an engine, like Guild/Sync.lua: ns.Deathroll is this client's, the self-test's pretend members run
-- their own (they accept and roll by themselves).
local _, ns = ...
local L, D, Comm, Pu = ns.L, ns.GuildData, ns.Comm, ns.Purse

local E = {}
E.__index = E
E.STALE = 600   -- a game nobody rolled in for this long is over
E.START_MAX = 1000000

-- io = { me = function() -> "Name-Realm", send = function(target, tag, data), sync = the op engine,
--        roll = function(max), main = true for this client, auto = true to accept and roll by itself,
--        near = function(name) -> is that player near (none: always) }
local function new(io) return setmetatable({ io = io, seq = 0 }, E) end

local function changed(self) if self.io.main then ns:Fire("TAVERN") end end

-- The game in hand (nil when there is none, or it went stale).
function E:Game()
  local game = self.game
  if game and game.st ~= "over" and GetTime() - game.at > self.STALE then self.game = nil end
  return self.game
end

function E:Busy()
  local game = self:Game()
  return game ~= nil and game.st ~= "over"
end

-- Whose roll is next ("me" or "them"), and from what number.
function E:Turn()
  local game = self:Game()
  if not game or game.st ~= "playing" then return nil end
  local i = #game.rolls + 1
  local challengerRolls = i % 2 == 1
  local mine = challengerRolls == game.mine
  return mine and "me" or "them", i == 1 and game.s or game.rolls[i - 1].v
end

function E.Valid(amt, purse, start)
  start = tonumber(start)
  return Pu.IsPurse(purse) and Pu.ValidAmount(amt, purse) and start ~= nil and start >= 2 and start <= E.START_MAX
    and start == math.floor(start)
end

function E:Near(name) return not self.io.near or self.io.near(name) end

-- Challenges opp ("Name-Realm"). False when a game is in hand or the numbers are wrong; false, "far" when opp is not
-- near.
function E:Challenge(opp, amt, purse, start)
  if self:Busy() or type(opp) ~= "string" or opp == self.io.me() or not E.Valid(amt, purse, start) then return false end
  if not self:Near(opp) then return false, "far" end
  self.seq = self.seq + 1
  local id = ("%d.%d"):format(time(), self.seq)
  self.game = { id = id, opp = opp, amt = amt, p = purse, s = start, mine = true, st = "asked", rolls = {}, at = GetTime() }
  self.io.send(opp, "DRC", { id = id, amt = amt, p = purse, s = start })
  changed(self)
  return true
end

function E:Accept()
  local game = self:Game()
  if not game or game.st ~= "incoming" then return false end
  if not self:Near(game.opp) then return false, "far" end
  game.st, game.at = "playing", GetTime()
  self.io.send(game.opp, "DRA", { id = game.id })
  changed(self)
  return true
end

-- Declines a challenge, or calls off a game (before the first roll only: after it, the dice decide).
function E:CallOff()
  local game = self:Game()
  if not game or game.st == "over" or #game.rolls > 0 then return false end
  self.io.send(game.opp, "DRN", { id = game.id })
  self.game = nil
  changed(self)
  return true
end

-- A finished game is put away.
function E:Clear()
  if self.game and self.game.st == "over" then self.game = nil; changed(self) end
end

-- Rolls when it is this player's turn.
function E:RollNow()
  local whose, max = self:Turn()
  if whose ~= "me" then return false end
  self.io.roll(max)
  return true
end

local function record(self, game, who, v)
  game.rolls[#game.rolls + 1] = { who = who, v = v }
  game.at = GetTime()
  if v == 1 then
    game.st, game.loser = "over", who
    if who == "me" then
      self.io.sync:Do({ k = "deathroll", w = game.opp, l = self.io.me(), amt = game.amt, p = game.p, s = game.s,
        n = #game.rolls })
    end
  end
  changed(self)
end

-- This player's own roll, as the game reported it. Counts when it is their turn and from the right number.
function E:Rolled(v, lo, hi)
  local whose, max = self:Turn()
  if whose ~= "me" or lo ~= 1 or hi ~= max or not v or v < 1 or v > max then return false end
  local game = self.game
  self.io.send(game.opp, "DRR", { id = game.id, i = #game.rolls + 1, v = v })
  record(self, game, "me", v)
  return true
end

---------------------------------------------------------------------------
-- Receiving (by whisper only)
---------------------------------------------------------------------------
local receive = {}

receive.DRC = function(self, sender, d)
  if not E.Valid(d.amt, d.p, d.s) or type(d.id) ~= "string" then return end
  if self:Busy() then
    self.io.send(sender, "DRN", { id = d.id, busy = true })
    return
  end
  self.game = { id = d.id, opp = sender, amt = d.amt, p = d.p, s = d.s, mine = false, st = "incoming", rolls = {},
    at = GetTime() }
  if self.io.main then
    ns:Print(L.DR_CHALLENGED:format(ns.Display(sender), Pu:Format(Pu.Units(d.amt, d.p), d.p), d.s), true)
  end
  changed(self)
  if self.io.auto then self:Accept() end
end

local function ours(self, sender, d)
  local game = self:Game()
  return game and game.id == d.id and game.opp == sender and game or nil
end

receive.DRA = function(self, sender, d)
  local game = ours(self, sender, d)
  if not game or game.st ~= "asked" then return end
  game.st, game.at = "playing", GetTime()
  changed(self)
  if self.io.auto then self:RollNow() end
end

receive.DRN = function(self, sender, d)
  local game = ours(self, sender, d)
  if not game or game.st == "over" or #game.rolls > 0 then return end
  self.game = nil
  if self.io.main then ns:Print((d.busy and L.DR_BUSY or L.DR_DECLINED):format(ns.Display(sender)), true) end
  changed(self)
end

receive.DRR = function(self, sender, d)
  local game = ours(self, sender, d)
  local whose, max = self:Turn()
  local v = tonumber(d.v)
  if not game or whose ~= "them" or tonumber(d.i) ~= #game.rolls + 1 or not v or v < 1 or v > max or v ~= math.floor(v) then
    return
  end
  record(self, game, "them", v)
  if self.io.auto and game.st == "playing" then self:RollNow() end
end

function E:Receive(tag, sender, d, channel)
  local fn = receive[tag]
  if fn and channel == "WHISPER" and type(d) == "table" then fn(self, sender, d) end
end

---------------------------------------------------------------------------
-- The result: written by the loser's addon
---------------------------------------------------------------------------
D:Register("deathroll", {
  allowed = function(_, author, op)
    return op.l == author and type(op.w) == "string" and op.w ~= op.l and E.Valid(op.amt, op.p, op.s)
  end,
  apply = function(g, author, op, t, n)
    local key = D.Key(author, n)
    Pu:Charge(g, key, op.l, op.w, op.amt, op.p, "deathroll", t)
    D.Part(g, "tavern")[key] = { k = "dr", w = op.w, l = op.l, amt = op.amt, p = op.p, n = tonumber(op.n), t = t }
    return true
  end,
  copy = function(g) return g.tavern end,
  merge = function(g, part)
    D.Union(D.Part(g, "tavern"), part, function(e) return type(e.k) == "string" end)
  end,
})

---------------------------------------------------------------------------
-- This client's engine
---------------------------------------------------------------------------
local DR = new({
  main = true,
  me = function() return ns.Self() end,
  send = function(target, tag, data) Comm:Send(target, tag, data, true) end,
  sync = ns.Sync,
  roll = function(max) ns.Dice:Roll(max) end,
  near = function(name) return ns.Looks.Near(name) end,
})
ns.Deathroll = DR
DR.New = new

for tag in pairs(receive) do
  Comm:On(tag, function(sender, d, channel) DR:Receive(tag, sender, d, channel) end)
end

ns.Dice:Listen(function(name, v, lo, hi)
  if name == ns.Self() then DR:Rolled(v, lo, hi) end
end)
