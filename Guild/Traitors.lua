-- The Traitors (SPEC §8, Games; decided 29 Oct 2026: the host presents, like the show, and does not play). Players
-- join the game (game_join, Guild/Games.lua). The host deals the roles in secret: their addon picks the traitors and
-- whispers each player their role (a traitor learns the others too). Then rounds, each begun by the host's press:
--   night: each traitor's addon whispers the host their pick of a victim
--   morning: the host's addon names the murdered (the most picked; ties at random; nobody when none picked)
--   the round table: every player still in votes, openly, for someone to banish
--   banish: the most votes goes (ties at random), and their role is shown on every screen
-- The Faithful win when every traitor is gone; the traitors win once they are as many as the Faithful. The survivors on
-- the winning side share the prize. Only members with the addon take part: roles go by whisper.
--   tr_go    { id, p, n }        the host deals: p, the players; n, how many traitors (only the count)
--   tr_night { id, r }           night r falls
--   tr_dawn  { id, r, v }        morning r: v was murdered ("" for nobody)
--   tr_vote  { id, r, on }       a vote at round table r (the voter's newest counts; never for oneself)
--   tr_ban   { id, r, v, role }  banished at round table r ("" for nobody), and their role: "traitor" or "faithful"
--   tr_end   { id, side, tr }    the end: the winning side, and every traitor; then game_end pays the prize
-- Whispers, only between the host's addon and a player's:
--   TRR { id, r, m }   your role, and for a traitor the other traitors     TRQ { id }   asks the host for your role
--   TRM { id, r, v }   a traitor's pick of a victim for night r
local _, ns = ...
local D, Comm = ns.GuildData, ns.Comm
local Gm = ns.Games

local Tr = {}
ns.Traitors = Tr
Tr.MIN = 4          -- players, at least
Tr.PLAYERS_MAX = 40

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function isHost(_, author, op) return host(op.id) == author end

-- How many traitors for a number of players: one up to 7, two up to 13, then three.
function Tr.Default(n) return n <= 7 and 1 or (n <= 13 and 2 or 3) end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
local function sub(t, k) t[k] = t[k] or {} return t[k] end

Gm.OnGame("tr_go", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or type(op.p) ~= "table" or #op.p < Tr.MIN or #op.p > Tr.PLAYERS_MAX then return false end
    for _, name in ipairs(op.p) do if not party(name) or name == author then return false end end
    return whole(op.n, 1, #op.p) and op.n * 2 < #op.p
  end,
  apply = function(g, _, op, t)
    local ga = Gm.Get(g, op.id)
    if ga.pl then return false end
    ga.pl, ga.n, ga.go = {}, op.n, t
    for i, name in ipairs(op.p) do ga.pl[i] = name end
    return true
  end,
})

Gm.OnGame("tr_night", {
  allowed = function(_, author, op) return isHost(_, author, op) and whole(op.r, 1, Tr.PLAYERS_MAX) end,
  apply = function(g, _, op, t)
    local nights = sub(Gm.Get(g, op.id), "nights")
    if nights[op.r] then return false end
    nights[op.r] = t
    return true
  end,
})

-- The host's answers for round r: who was murdered, who was banished. The first stays.
for _, kind in ipairs({ "tr_dawn", "tr_ban" }) do
  Gm.OnGame(kind, {
    allowed = function(_, author, op)
      return isHost(_, author, op) and whole(op.r, 1, Tr.PLAYERS_MAX) and type(op.v) == "string" and #op.v <= 64
        and (kind == "tr_dawn" or op.v == "" or op.role == "traitor" or op.role == "faithful")
    end,
    apply = function(g, _, op, t)
      local all = sub(Gm.Get(g, op.id), kind == "tr_dawn" and "dawn" or "ban")
      if all[op.r] then return false end
      all[op.r] = { v = op.v, role = kind == "tr_ban" and op.v ~= "" and op.role or nil, t = t }
      return true
    end,
  })
end

Gm.OnGame("tr_vote", {
  allowed = function(_, author, op) return whole(op.r, 1, Tr.PLAYERS_MAX) and party(op.on) and op.on ~= author end,
  apply = function(g, author, op, t)
    local votes = sub(sub(Gm.Get(g, op.id), "tv"), op.r)
    if votes[author] and votes[author].t > t then return false end
    votes[author] = { on = op.on, t = t }
    return true
  end,
})

Gm.OnGame("tr_end", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or (op.side ~= "traitors" and op.side ~= "faithful") or type(op.tr) ~= "table" then return false end
    for _, name in ipairs(op.tr) do if not party(name) then return false end end
    return #op.tr <= Tr.PLAYERS_MAX
  end,
  apply = function(g, _, op, t)
    local ga = Gm.Get(g, op.id)
    if ga.side then return false end
    ga.side, ga.tr, ga.tend = op.side, {}, t
    for i, name in ipairs(op.tr) do ga.tr[i] = name end
    return true
  end,
})

-- A whole copy (Guild/Games.lua's merge): the parts above.
table.insert(Gm.mergers, function(ga, e)
  if not ga.pl and type(e.pl) == "table" and whole(e.n, 1, Tr.PLAYERS_MAX) and tonumber(e.go) then
    ga.pl, ga.n, ga.go = {}, e.n, e.go
    for i, name in ipairs(e.pl) do if party(name) then ga.pl[i] = name end end
  end
  for r, t in pairs(type(e.nights) == "table" and e.nights or {}) do
    if whole(r, 1, Tr.PLAYERS_MAX) and tonumber(t) then sub(ga, "nights")[r] = ga.nights[r] or t end
  end
  for _, f in ipairs({ "dawn", "ban" }) do
    for r, x in pairs(type(e[f]) == "table" and e[f] or {}) do
      if whole(r, 1, Tr.PLAYERS_MAX) and type(x) == "table" and type(x.v) == "string" and tonumber(x.t) and not sub(ga, f)[r] then
        ga[f][r] = { v = x.v, role = (x.role == "traitor" or x.role == "faithful") and x.role or nil, t = x.t }
      end
    end
  end
  for r, votes in pairs(type(e.tv) == "table" and e.tv or {}) do
    if whole(r, 1, Tr.PLAYERS_MAX) and type(votes) == "table" then
      local mine = sub(sub(ga, "tv"), r)
      for name, x in pairs(votes) do
        if party(name) and type(x) == "table" and party(x.on) and tonumber(x.t) and (not mine[name] or mine[name].t < x.t) then
          mine[name] = { on = x.on, t = x.t }
        end
      end
    end
  end
  if not ga.side and (e.side == "traitors" or e.side == "faithful") and type(e.tr) == "table" and tonumber(e.tend) then
    ga.side, ga.tr, ga.tend = e.side, {}, e.tend
    for _, name in ipairs(e.tr) do if party(name) then ga.tr[#ga.tr + 1] = name end end
  end
end)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The round now, and where it stands: "signup" (no roles yet), "dusk" (waiting for the night), "night", "table" (the
-- round table votes) or "done".
function Tr.Phase(ga)
  if not ga.pl then return "signup", 0 end
  local r = 0
  for k in pairs(ga.nights or {}) do if k > r then r = k end end
  if ga.side then return "done", r end
  if r == 0 then return "dusk", 0 end
  if not (ga.dawn and ga.dawn[r]) then return "night", r end
  if not (ga.ban and ga.ban[r]) then return "table", r end
  return "dusk", r
end

-- Who is still in: { [name] = true }, and how the others went: { { name, how = "murdered"|"banished", r, role } }.
function Tr.Alive(ga)
  local alive, out = {}, {}
  for _, name in ipairs(ga.pl or {}) do alive[name] = true end
  local rounds = 0
  for k in pairs(ga.nights or {}) do if k > rounds then rounds = k end end
  for r = 1, rounds do
    local d, b = ga.dawn and ga.dawn[r], ga.ban and ga.ban[r]
    if d and alive[d.v] then alive[d.v] = nil; out[#out + 1] = { name = d.v, how = "murdered", r = r } end
    if b and alive[b.v] then alive[b.v] = nil; out[#out + 1] = { name = b.v, how = "banished", r = r, role = b.role } end
  end
  return alive, out
end

-- The votes at round table r: { { name, n } }, the most first; and each voter's choice { [voter] = name }.
function Tr.Tally(ga, r)
  local alive = Tr.Alive(ga)
  local count, choice = {}, {}
  for voter, x in pairs(ga.tv and ga.tv[r] or {}) do
    if alive[voter] and alive[x.on] and x.on ~= voter then
      count[x.on] = (count[x.on] or 0) + 1
      choice[voter] = x.on
    end
  end
  local list = {}
  for name, n in pairs(count) do list[#list + 1] = { name = name, n = n } end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return list, choice
end

-- The winners, once it ended: the survivors on the winning side.
function Tr.Winners(ga)
  if not ga.side then return {} end
  local traitor = {}
  for _, name in ipairs(ga.tr or {}) do traitor[name] = true end
  local alive, out = Tr.Alive(ga), {}
  for _, name in ipairs(ga.pl or {}) do
    if alive[name] and (traitor[name] == true) == (ga.side == "traitors") then out[#out + 1] = name end
  end
  return out
end

---------------------------------------------------------------------------
-- Secrets (this account): roles[id] = { r, m }; as host deals[id] = { [name] = role } and picks[id][r][traitor] = v;
-- as a traitor mine[id][r] = v.
---------------------------------------------------------------------------
local function store()
  ns.db.traitors = type(ns.db.traitors) == "table" and ns.db.traitors or {}
  local gid = D:Id() or "?"
  if type(ns.db.traitors[gid]) ~= "table" then ns.db.traitors[gid] = {} end
  local s = ns.db.traitors[gid]
  for _, k in ipairs({ "roles", "deals", "picks", "mine" }) do s[k] = type(s[k]) == "table" and s[k] or {} end
  return s
end
Tr.Store = store

-- This character's role: "traitor", "faithful" or nil (not told yet, or not playing), and the other traitors.
function Tr.Role(id)
  local x = store().roles[id]
  if not x then return nil end
  return x.r, x.m or {}
end

local function current(id)
  local g = D:Current()
  return g, g and g.games and g.games[id]
end

local function tell(id, name, role, mates)
  if name == ns.Self() then
    store().roles[id] = { r = role, m = mates }
    ns:Fire("GAMES")
  else
    Comm:Send(name, "TRR", { id = id, r = role, m = mates }, true)
  end
end

-- What the host's addon tells a player: their role, and a traitor the others.
local function told(id, name)
  local deal = store().deals[id]
  local role = deal and deal[name]
  if not role then return nil end
  local mates
  if role == "traitor" then
    mates = {}
    for n, r in pairs(deal) do if r == "traitor" and n ~= name then mates[#mates + 1] = n end end
    table.sort(mates)
  end
  return role, mates
end

---------------------------------------------------------------------------
-- The host
---------------------------------------------------------------------------
-- Deals the roles to everyone who joined: n traitors (default by the number of players).
function Tr.Deal(id, n)
  local g, ga = current(id)
  if not ga or ga.h ~= ns.Self() or ga.pl or ga.st then return false end
  local players = {}
  for _, name in pairs(Gm.Joined(g, ga)) do players[#players + 1] = name end
  table.sort(players)
  n = n or Tr.Default(#players)
  if #players < Tr.MIN then return false end
  if not ns.Sync:Do({ k = "tr_go", id = id, p = players, n = n }) then return false end
  local order = {}
  for i, name in ipairs(players) do order[i] = name end
  for i = #order, 2, -1 do
    local j = math.random(1, i)
    order[i], order[j] = order[j], order[i]
  end
  local deal = {}
  for i, name in ipairs(order) do deal[name] = i <= n and "traitor" or "faithful" end
  store().deals[id] = deal
  for _, name in ipairs(players) do tell(id, name, told(id, name)) end
  return true
end

function Tr.Night(id)
  local _, ga = current(id)
  if not ga or ga.h ~= ns.Self() then return false end
  local phase, r = Tr.Phase(ga)
  if phase ~= "dusk" then return false end
  return ns.Sync:Do({ k = "tr_night", id = id, r = r + 1 })
end

-- Picks one of the most chosen (at random among a tie); "" when nobody was chosen.
local function most(count)
  local best, list = 0, {}
  for name, n in pairs(count) do
    if n > best then best, list = n, { name } elseif n == best then list[#list + 1] = name end
  end
  if #list == 0 then return "" end
  table.sort(list)
  return list[math.random(1, #list)]
end

-- The game ends when no traitor is left, or the traitors are as many as the Faithful.
local function over(id, ga)
  local deal = store().deals[id]
  if not deal then return nil end
  local alive = Tr.Alive(ga)
  local tr, fa = 0, 0
  for name in pairs(alive) do if deal[name] == "traitor" then tr = tr + 1 else fa = fa + 1 end end
  if tr == 0 then return "faithful" end
  if tr >= fa then return "traitors" end
  return nil
end

local function ending(id, ga)
  local side = over(id, ga)
  if not side then return end
  local list = {}
  for name, role in pairs(store().deals[id]) do if role == "traitor" then list[#list + 1] = name end end
  table.sort(list)
  if ns.Sync:Do({ k = "tr_end", id = id, side = side, tr = list }) then Gm.Finish(id) end
end

-- How many traitors have picked tonight (for the host's page).
function Tr.Picked(id, r)
  local n = 0
  for _ in pairs(store().picks[id] and store().picks[id][r] or {}) do n = n + 1 end
  return n
end

function Tr.Morning(id)
  local _, ga = current(id)
  if not ga or ga.h ~= ns.Self() then return false end
  local phase, r = Tr.Phase(ga)
  local deal = store().deals[id]
  if phase ~= "night" or not deal then return false end
  local alive = Tr.Alive(ga)
  local count = {}
  for traitor, v in pairs(store().picks[id] and store().picks[id][r] or {}) do
    if alive[traitor] and deal[traitor] == "traitor" and alive[v] and deal[v] == "faithful" then
      count[v] = (count[v] or 0) + 1
    end
  end
  if not ns.Sync:Do({ k = "tr_dawn", id = id, r = r, v = most(count) }) then return false end
  ending(id, ga)
  return true
end

function Tr.Banish(id)
  local _, ga = current(id)
  if not ga or ga.h ~= ns.Self() then return false end
  local phase, r = Tr.Phase(ga)
  local deal = store().deals[id]
  if phase ~= "table" or not deal then return false end
  local count = {}
  for _, e in ipairs((Tr.Tally(ga, r))) do count[e.name] = e.n end
  local v = most(count)
  if not ns.Sync:Do({ k = "tr_ban", id = id, r = r, v = v, role = deal[v] or "faithful" }) then return false end
  ending(id, ga)
  return true
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
function Tr.Vote(id, name)
  local _, ga = current(id)
  if not ga then return false end
  local phase, r = Tr.Phase(ga)
  if phase ~= "table" then return false end
  return ns.Sync:Do({ k = "tr_vote", id = id, r = r, on = name })
end

-- A traitor's pick tonight, whispered to the host.
function Tr.Pick(id, name)
  local _, ga = current(id)
  if not ga or Tr.Role(id) ~= "traitor" then return false end
  local phase, r = Tr.Phase(ga)
  if phase ~= "night" or not Tr.Alive(ga)[ns.Self()] then return false end
  local mine = store().mine
  mine[id] = mine[id] or {}
  mine[id][r] = name
  Comm:Send(ga.h, "TRM", { id = id, r = r, v = name }, true)
  ns:Fire("GAMES")
  return true
end

-- This traitor's pick tonight (or nil).
function Tr.MyPick(id, r) return store().mine[id] and store().mine[id][r] end

Comm:On("TRR", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" or sender ~= host(d.id) then return end
  if d.r ~= "traitor" and d.r ~= "faithful" then return end
  local mates = {}
  for _, name in ipairs(type(d.m) == "table" and d.m or {}) do if party(name) then mates[#mates + 1] = name end end
  store().roles[d.id] = { r = d.r, m = mates }
  ns:Fire("GAMES")
end)

Comm:On("TRQ", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" then return end
  local _, ga = current(d.id)
  if not ga or ga.h ~= ns.Self() then return end
  local role, mates = told(d.id, sender)
  if role then Comm:Send(sender, "TRR", { id = d.id, r = role, m = mates }, true) end
end)

Comm:On("TRM", function(sender, d, channel)
  if channel ~= "WHISPER" or type(d) ~= "table" or type(d.id) ~= "string" or not party(d.v) then return end
  local _, ga = current(d.id)
  local deal = store().deals[d.id]
  if not ga or ga.h ~= ns.Self() or not deal or deal[sender] ~= "traitor" then return end
  local phase, r = Tr.Phase(ga)
  if phase ~= "night" or tonumber(d.r) ~= r then return end
  local picks = store().picks
  picks[d.id] = picks[d.id] or {}
  picks[d.id][r] = picks[d.id][r] or {}
  picks[d.id][r][sender] = d.v
  ns:Fire("GAMES")
end)

-- After login: ask the host for our role in a game we play and were not told about.
Tr.asked = {}
ns:On("ROSTER", function()
  local g = D:Current()
  for _, item in ipairs(g and Gm.List(g) or {}) do
    local ga = item.ga
    if ga.kind == "traitors" and ga.pl and not ga.side and not Tr.Role(item.id) and ga.h ~= ns.Self()
      and not Tr.asked[item.id] then
      Tr.asked[item.id] = true
      for _, name in ipairs(ga.pl) do
        if name == ns.Self() then Comm:Send(ga.h, "TRQ", { id = item.id }, true) end
      end
    end
  end
end)
