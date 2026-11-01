-- One player is one player (SPEC §1): a player is the characters of one account in the guild. Every account has an
-- id of its own (made once, saved account-wide), and each copy of the addon tells the guild which of the account's
-- characters are in the guild (the "player" op, at login).
-- Ops and ledger entries name characters ("Name-Realm"); they are put together per player when read (P:Of), so an
-- op made before its author's "player" op arrived still counts for the right player. A member without the addon is a
-- player of one character: their own name.
local _, ns = ...
local D, R = ns.GuildData, ns.Roster
local P = { cache = setmetatable({}, { __mode = "k" }) }
ns.Players = P

P.CHARS_MAX = 20

-- A short hash, for this account's id.
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return h
end

-- This account's id: "#" and 8 hex digits, made once.
function P:MyId()
  local db = ns.db
  if type(db.player) ~= "string" or not db.player:match("^#%x+$") then
    local seed = tostring(ns.Self()) .. time() .. tostring(GetTime()) .. math.random(1, 2 ^ 30)
    db.player = ("#%08x"):format(hash(seed))
  end
  return db.player
end

-- This account's characters in guild g (by the account-wide list of characters, Core/Characters.lua).
function P:MyChars()
  local guild = ns.Guild()
  local me = ns.Self()
  local list, main = { me }, me
  local best = UnitLevel("player") or 0
  for name, e in pairs(ns.db.characters) do
    if name ~= me and type(e) == "table" and guild and e.guild == guild and #list < self.CHARS_MAX then
      list[#list + 1] = name
      local lv = tonumber(e.level) or 0
      if lv > best or (lv == best and name < main) then best, main = lv, name end
    end
  end
  table.sort(list)
  return list, main
end

local function sound(e)
  if type(e) ~= "table" or type(e.c) ~= "table" or #e.c == 0 or #e.c > P.CHARS_MAX or type(e.m) ~= "string" then
    return false
  end
  local hasMain = false
  for _, name in ipairs(e.c) do
    if type(name) ~= "string" then return false end
    if name == e.m then hasMain = true end
  end
  return hasMain
end

-- g.players[id] = { c = { characters }, m = the main (shown as the player's name), t, f }: the newest wins; f is the
-- first claim's time, the player's first day with Guild Together in this guild (Mak'gora, SPEC §7.5).
local function take(g, id, e, t)
  local players = D.Part(g, "players")
  local cur = players[id]
  local f = math.min(tonumber(e.f) or t, cur and (tonumber(cur.f) or tonumber(cur.t)) or math.huge)
  if cur and (tonumber(cur.t) or 0) > t then
    if f < (tonumber(cur.f) or math.huge) then cur.f = f end
    return false
  end
  local c = {}
  for i, name in ipairs(e.c) do c[i] = name end
  players[id] = { c = c, m = e.m, t = t, f = f }
  P.cache[g] = nil
  return true
end

D:Register("player", {
  allowed = function(_, author, op)
    if type(op.id) ~= "string" or not op.id:match("^#%x+$") or not sound(op) then return false end
    for _, name in ipairs(op.c) do if name == author then return true end end
    return false
  end,
  apply = function(g, _, op, t) return take(g, op.id, op, t) end,
  copy = function(g) return g.players end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and id:match("^#%x+$") and sound(e) then take(g, id, e, tonumber(e.t) or 0) end
    end
  end,
})

-- character -> player id, from the newest claim on each character.
local function map(g)
  local m = P.cache[g]
  if m then return m end
  m = {}
  local when = {}
  for id, e in pairs(g.players or {}) do
    for _, name in ipairs(e.c) do
      local t = tonumber(e.t) or 0
      if not when[name] or t > when[name] or (t == when[name] and id < m[name]) then m[name], when[name] = id, t end
    end
  end
  P.cache[g] = m
  return m
end

-- The player a character belongs to: an account id, or the character itself (no addon, or not heard from yet). Our
-- own characters are always ours.
function P:Of(name, g)
  if type(name) ~= "string" then return nil end
  g = g or D:Current()
  if g and ns.db.guilds[g.id] == g and type(ns.db.characters[name]) == "table" then return self:MyId() end
  local m = g and map(g)
  return m and m[name] or name
end

-- Is this player me?
function P:IsMe(key, g) return key ~= nil and key == self:Of(ns.Self(), g) end

-- Does the player have Guild Together: have they told the guild their characters (an account id)? Punishments, warnings,
-- the court, tax, debts and bets count only these players (SPEC decision 56).
function P:HasAddon(key) return type(key) == "string" and key:sub(1, 1) == "#" end

-- The player's first day with Guild Together in guild g (their first claim), or nil before it arrives.
function P:Since(key, g)
  g = g or D:Current()
  local e = g and g.players and g.players[key]
  return e and (tonumber(e.f) or tonumber(e.t)) or nil
end

-- The guild's first day with Guild Together: the earliest claim of any player.
function P:FirstDay(g)
  g = g or D:Current()
  local first
  for _, e in pairs(g and g.players or {}) do
    local f = tonumber(e.f) or tonumber(e.t)
    if f and (not first or f < first) then first = f end
  end
  return first
end

-- The name a player is shown by: their main's (without the realm when it is ours).
function P:Name(key, g)
  if type(key) ~= "string" then return "" end
  local main = self:Main(key, g)
  return main and ns.Display(main) or key
end

-- The player's main, with the realm (nil for an unknown player id).
function P:Main(key, g)
  if type(key) ~= "string" then return nil end
  if key:sub(1, 1) ~= "#" then return key end
  if key == self:MyId() then return (select(2, self:MyChars())) end
  g = g or D:Current()
  local e = g and g.players and g.players[key]
  return e and e.m
end

-- The player's characters (just the one for a member without the addon).
function P:Chars(key, g)
  if type(key) ~= "string" then return {} end
  if key:sub(1, 1) ~= "#" then return { key } end
  if key == self:MyId() then return (self:MyChars()) end
  g = g or D:Current()
  local e = g and g.players and g.players[key]
  return e and e.c or {}
end

-- The player's character that is online now, if any.
function P:Online(key, g)
  for _, name in ipairs(self:Chars(key, g)) do
    if name ~= ns.Self() and R:Online(name) then return name end
  end
end

-- Tells the guild this account's characters, when the guild's copy does not have them yet (at login, once the roster
-- is in).
function P:Publish()
  local g = D:Current()
  if not g or not R:Ready() then return false end
  local chars, main = self:MyChars()
  local e = g.players and g.players[self:MyId()]
  if e and e.m == main and #e.c == #chars then
    local same = true
    for i, name in ipairs(chars) do if e.c[i] ~= name then same = false end end
    if same then return false end
  end
  return ns.Sync:Do({ k = "player", id = self:MyId(), c = chars, m = main })
end

ns:On("ROSTER", function(first)
  if first or not P.published then
    P.published = P:Publish() or P.published
  end
end)
ns:On("GUILD_CHANGED", function() P.published = nil end)
