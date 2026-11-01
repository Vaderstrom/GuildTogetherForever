-- Secret Santa (SPEC §8, Games; decided 29 Oct 2026: gifts go by mail, straight to the giftee). Players sign up
-- (game_join, Guild/Games.lua) until the draw. The host's addon draws a circle in secret (nobody gives to themselves,
-- no two give to each other) and whispers each Santa their giftee. A Santa mails their giftee a gift. The giftee's
-- addon sees the letter in their mailbox and asks the sender's addon whether it was their Santa's gift; only that
-- addon says yes, so the guild learns that a gift arrived, never who sent it. On the night, the host reveals every
-- pair on every screen. Only members with the addon take part: giftees go by whisper.
--   santa_go   { id, p }       the host draws: p, the players (the pairs stay secret)
--   santa_got  { id }          the author's gift arrived (the giftee's own addon, after the Santa's addon said yes)
--   santa_end  { id, pairs }   the reveal: { { santa, giftee }, ... }; the game is done
-- Whispers:
--   SSG { id, to }   from the host: your giftee        SSQ { id }   asks the host for your giftee
--   SSA { id }       a giftee asks a letter's sender: "was this my gift?"   SSY { id }   the Santa: "yes, it was me"
local _, ns = ...
local L, D, Comm = ns.L, ns.GuildData, ns.Comm
local Gm = ns.Games

local Sa = {}
ns.Santa = Sa
Sa.MIN = 3
Sa.PLAYERS_MAX = 60

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function host(id) return D.KeyAuthor(id) end

Gm.OnGame("santa_go", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or type(op.p) ~= "table" or #op.p < Sa.MIN or #op.p > Sa.PLAYERS_MAX then return false end
    for _, name in ipairs(op.p) do if not party(name) then return false end end
    return true
  end,
  apply = function(g, _, op, t)
    local ga = Gm.Get(g, op.id)
    if ga.pl then return false end
    ga.pl, ga.go = {}, t
    for i, name in ipairs(op.p) do ga.pl[i] = name end
    return true
  end,
})

Gm.OnGame("santa_got", {
  allowed = function() return true end,
  apply = function(g, author, op, t)
    local ga = Gm.Get(g, op.id)
    ga.got = ga.got or {}
    if ga.got[author] and ga.got[author] <= t then return false end
    ga.got[author] = t
    return true
  end,
})

Gm.OnGame("santa_end", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or type(op.pairs) ~= "table" or #op.pairs > Sa.PLAYERS_MAX then return false end
    for _, x in ipairs(op.pairs) do
      if type(x) ~= "table" or not party(x[1]) or not party(x[2]) then return false end
    end
    return true
  end,
  apply = function(g, _, op, t)
    local ga = Gm.Get(g, op.id)
    if ga.st then return false end
    ga.pairs = {}
    for i, x in ipairs(op.pairs) do ga.pairs[i] = { x[1], x[2] } end
    ga.st, ga.te = "done", t
    return true
  end,
})

table.insert(Gm.mergers, function(ga, e)
  if ga.kind ~= "santa" and e.kind ~= "santa" then return end
  if not ga.pl and type(e.pl) == "table" and tonumber(e.go) then
    ga.pl, ga.go = {}, e.go
    for _, name in ipairs(e.pl) do if party(name) then ga.pl[#ga.pl + 1] = name end end
  end
  for name, t in pairs(type(e.got) == "table" and e.got or {}) do
    if party(name) and tonumber(t) then
      ga.got = ga.got or {}
      if not ga.got[name] or t < ga.got[name] then ga.got[name] = t end
    end
  end
  if not ga.pairs and type(e.pairs) == "table" then
    ga.pairs = {}
    for _, x in ipairs(e.pairs) do
      if type(x) == "table" and party(x[1]) and party(x[2]) then ga.pairs[#ga.pairs + 1] = { x[1], x[2] } end
    end
  end
end)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- How many gifts have arrived, of how many.
function Sa.Count(ga)
  local n = 0
  for _, name in ipairs(ga.pl or {}) do if ga.got and ga.got[name] then n = n + 1 end end
  return n, #(ga.pl or {})
end

-- Is name one of the players?
function Sa.Plays(ga, name)
  for _, n in ipairs(ga.pl or {}) do if n == name then return true end end
  return false
end

---------------------------------------------------------------------------
-- Secrets (this account): to[id] = my giftee; as host rings[id] = { names in the circle }.
---------------------------------------------------------------------------
local function store()
  ns.db.santa = type(ns.db.santa) == "table" and ns.db.santa or {}
  local gid = D:Id() or "?"
  if type(ns.db.santa[gid]) ~= "table" then ns.db.santa[gid] = {} end
  local s = ns.db.santa[gid]
  for _, k in ipairs({ "to", "rings" }) do s[k] = type(s[k]) == "table" and s[k] or {} end
  return s
end
Sa.Store = store

-- My giftee (nil until told).
function Sa.Giftee(id) return store().to[id] end

local function current(id)
  local g = D:Current()
  return g, g and g.games and g.games[id]
end

-- The draw (the host): everyone who signed up, in a random circle; each Santa is told their giftee.
function Sa.Draw(id)
  local g, ga = current(id)
  if not ga or ga.h ~= ns.Self() or ga.pl or ga.st then return false end
  local players = {}
  for _, name in pairs(Gm.Joined(g, ga)) do players[#players + 1] = name end
  table.sort(players)
  if #players < Sa.MIN then return false end
  if not ns.Sync:Do({ k = "santa_go", id = id, p = players }) then return false end
  local ring = {}
  for i, n in ipairs(players) do ring[i] = n end
  for i = #ring, 2, -1 do
    local j = math.random(1, i)
    ring[i], ring[j] = ring[j], ring[i]
  end
  store().rings[id] = ring
  for i, n in ipairs(ring) do
    local to = ring[i % #ring + 1]
    if n == ns.Self() then store().to[id] = to else Comm:Send(n, "SSG", { id = id, to = to }, true) end
  end
  ns:Fire("GAMES")
  return true
end

-- The reveal (the host): every pair, on every screen.
function Sa.Reveal(id)
  local _, ga = current(id)
  local ring = store().rings[id]
  if not ga or ga.h ~= ns.Self() or not ga.pl or ga.st or not ring then return false end
  local pairs_ = {}
  for i, n in ipairs(ring) do pairs_[i] = { n, ring[i % #ring + 1] } end
  return ns.Sync:Do({ k = "santa_end", id = id, pairs = pairs_ })
end

---------------------------------------------------------------------------
-- The mailbox: a letter with a gift (an item, or gold) from a fellow player. Its sender's addon is asked once per
-- session whether it was their gift to us.
---------------------------------------------------------------------------
Sa.asked = {}
function Sa:Letter(sender)
  local g = D:Current()
  local me = ns.Self()
  for _, item in ipairs(g and Gm.List(g) or {}) do
    local ga, id = item.ga, item.id
    if ga.kind == "santa" and ga.pl and not ga.st and Sa.Plays(ga, me) and Sa.Plays(ga, sender) and sender ~= me
      and not (ga.got and ga.got[me]) and not self.asked[id .. "|" .. sender] then
      self.asked[id .. "|" .. sender] = true
      Comm:Send(sender, "SSA", { id = id }, true)
    end
  end
end

ns:RegisterEvent("MAIL_INBOX_UPDATE", function()
  if not GetInboxNumItems or not GetInboxHeaderInfo then return end
  local n = GetInboxNumItems()
  if type(n) ~= "number" or (issecretvalue and issecretvalue(n)) then return end
  for i = 1, n do
    local _, _, sender, _, money, cod, _, hasItem, _, returned = GetInboxHeaderInfo(i)
    local secret = issecretvalue and (issecretvalue(sender) or issecretvalue(money) or issecretvalue(hasItem))
    if not secret and type(sender) == "string" and not returned and (tonumber(cod) or 0) == 0
      and (hasItem or (tonumber(money) or 0) > 0) then
      Sa:Letter(ns.FullName(sender))
    end
  end
end)

Comm:On("SSG", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" or not party(d.to) or sender ~= host(d.id) then return end
  store().to[d.id] = d.to
  ns:Fire("GAMES")
end)

Comm:On("SSQ", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" then return end
  local ring = store().rings[d.id]
  if not ring then return end
  for i, n in ipairs(ring) do
    if n == sender then Comm:Send(sender, "SSG", { id = d.id, to = ring[i % #ring + 1] }, true) end
  end
end)

-- A giftee asks: was it us? Only when they are our giftee.
Comm:On("SSA", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" then return end
  if store().to[d.id] == sender then Comm:Send(sender, "SSY", { id = d.id }, true) end
end)

-- Our Santa says yes: the gift arrived.
Comm:On("SSY", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" then return end
  local _, ga = current(d.id)
  local me = ns.Self()
  if not ga or ga.st or not Sa.Plays(ga, sender) or not Sa.asked[d.id .. "|" .. sender] then return end
  if not (ga.got and ga.got[me]) then
    ns.Sync:Do({ k = "santa_got", id = d.id })
    ns:Print(L.SA_GOT, true)
  end
end)

-- After login: ask the host for our giftee if we play and were not told.
Sa.askedHost = {}
ns:On("ROSTER", function()
  local g = D:Current()
  for _, item in ipairs(g and Gm.List(g) or {}) do
    local ga, id = item.ga, item.id
    if ga.kind == "santa" and ga.pl and not ga.st and not Sa.Giftee(id) and ga.h ~= ns.Self()
      and Sa.Plays(ga, ns.Self()) and not Sa.askedHost[id] then
      Sa.askedHost[id] = true
      Comm:Send(ga.h, "SSQ", { id = id }, true)
    end
  end
end)
