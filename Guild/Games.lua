-- Guild games (SPEC §8, Games): a rank that may start games (SPEC §3.2, tourney) hosts one, with an optional prize
-- the Treasury pays (decided 29 Oct 2026). Every player's own addon reports what only it can see.
--   bingo    Guild bingo: each player who joins gets their own 4 × 4 card (Guild/Seen.lua's squares, one free);
--            the first full row, column or diagonal wins
--   derby    Fishing contest: the most fish caught while it runs
--   flash    Meet-up: everyone at the host's spot when the countdown hits zero
--   hunt     Treasure hunt: clues that lead to places; your addon checks your position when you claim one
--   fashion  Transmog contest: entrants join, everyone votes for one (not themselves); the most votes wins
--   gnomes   Survival race: low-level runners race the host's checkpoints in order; a death ends the run;
--            everyone who reaches the finish alive shares the prize (decided 29 Oct 2026)
--   traitors Hidden traitors (Guild/Traitors.lua): the host presents, secret roles, murders and the round table
--   santa    Gift exchange (Guild/Santa.lua): pairs drawn in secret, gifts by mail, revealed on the night
-- Ops:
--   game      { kind, at, len, prize, p, spot, clues, lv, rv, note }   opened (its key is the game's id); at:
--                                       when it starts, len: minutes it runs; spot: the flash mob's; clues: the hunt's
--                                       clues or the gnome run's checkpoints { { text, x, y, i, z } }; lv: the gnome
--                                       run's highest level; rv: Secret Santa's reveal; note: the host's rules
--   game_join { id, on, lv }            signs up (or leaves); lv: the runner's level (the gnome run)
--   game_rep  { id, n, sq, here, c, dead }   the player's own addon: fish caught so far, a bingo square, at the flash
--                                       mob, a clue found or a checkpoint reached, died on the run
--   game_vote { id, on }                a Fashion show vote
--   game_cal  { id }                    the host put it into the game's calendar (before decision 74: now cal_in,
--                                       Guild/Agenda.lua)
--   game_end  { id, w, each, p }        ended: w, the winners; the Treasury owes each of them `each` (ledger units)
--   game_off  { id }                    called off by its host
-- Scores and winners are worked out when read, so the order ops arrive in never matters. The prize is charged by
-- game_end from the names it carries, so every copy charges the same.
local _, ns = ...
local L, D, Pu = ns.L, ns.GuildData, ns.Purse
local P = ns.Players

local Gm = {}
ns.Games = Gm

Gm.KINDS = { "bingo", "derby", "flash", "hunt", "fashion", "gnomes", "traitors", "santa" }
Gm.SQUARES = { "ding", "fish", "duel", "boss", "die", "quest", "inn", "hearth", "trade", "tomato", "skill", "flight",
  "repair", "group", "loot" }
Gm.SIZE, Gm.FREE_AT = 4, 6            -- the card: 4 × 4, the free square second in the second row
Gm.CLUE_LEN, Gm.CLUES_MAX = 80, 5
Gm.LEN_MAX = 14 * 24 * 60             -- minutes
Gm.FLASH_LEN = 2                      -- minutes after zero that still count at the flash mob
Gm.EARLY = 60                         -- seconds before zero that count too
Gm.NEAR, Gm.FLASH_NEAR = 10, 20       -- yards: a clue's place; the flash mob's spot
Gm.AHEAD, Gm.DAY = 60 * 86400, 86400
Gm.KEEP = 7 * 86400                   -- a finished game shows for a week
Gm.WINNERS_MAX = 50
Gm.CHECKS_MAX, Gm.GNOME_NEAR = 8, 20  -- the gnome run's checkpoints; how near counts as reaching one (yards)
Gm.LV_MAX, Gm.NOTE_MAX = 80, 80
Gm.REVEAL_MAX = 60 * 86400            -- Secret Santa: the reveal at most 60 days after the draw
-- Merging a whole copy (Guild/Traitors.lua and Guild/Santa.lua add theirs): fn(ga, theirs).
Gm.mergers = {}

local isKind, isSquare = {}, {}
for _, k in ipairs(Gm.KINDS) do isKind[k] = true end
for _, s in ipairs(Gm.SQUARES) do isSquare[s] = true end
function Gm.IsKind(k) return isKind[k] == true end

local Clean = ns.Raffle.Clean
local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function amount(v, p) return v == 0 or Pu.ValidAmount(v, p) end

local function place(s)
  if type(s) ~= "table" or not tonumber(s.x) or not tonumber(s.y) or not tonumber(s.i) then return nil end
  return { x = tonumber(s.x), y = tonumber(s.y), i = tonumber(s.i), z = Clean(s.z, 40) }
end

-- The hunt's clues (each with its text) or the gnome run's checkpoints (text optional). Nil if unsound.
local function places(list, text)
  if type(list) ~= "table" or #list < 1 or #list > (text and Gm.CLUES_MAX or Gm.CHECKS_MAX) then return nil end
  local out = {}
  for i, c in ipairs(list) do
    local s = place(c)
    if not s then return nil end
    s.text = Clean(c.text, Gm.CLUE_LEN)
    if text and not s.text then return nil end
    out[i] = s
  end
  return out
end

local function get(g, id)
  local all = D.Part(g, "games")
  local ga = all[id]
  if not ga then
    ga = { j = {}, r = {}, v = {} }
    all[id] = ga
  end
  return ga
end

local function sound(op)
  if not isKind[op.kind] or not whole(op.at, 1, 4e9) then return false end
  if not Pu.IsPurse(op.p) or not amount(op.prize, op.p) then return false end
  if op.note ~= nil and type(op.note) ~= "string" then return false end
  if op.kind == "flash" then return place(op.spot) ~= nil end
  if op.kind == "traitors" then return true end
  if op.kind == "santa" then return op.prize == 0 and whole(op.rv, op.at + 60, op.at + Gm.REVEAL_MAX) end
  if not whole(op.len, 1, Gm.LEN_MAX) then return false end
  if op.kind == "hunt" then return places(op.clues, true) ~= nil end
  if op.kind == "gnomes" then return places(op.clues, false) ~= nil and whole(op.lv, 1, Gm.LV_MAX) end
  return true
end

local function take(ga, author, op, t)
  ga.h, ga.kind, ga.at, ga.t = author, op.kind, tonumber(op.at), t
  ga.len = op.kind == "flash" and Gm.FLASH_LEN or tonumber(op.len)
  ga.prize, ga.p = tonumber(op.prize), op.p
  ga.spot = op.kind == "flash" and place(op.spot) or nil
  if op.kind == "hunt" or op.kind == "gnomes" then ga.clues = places(op.clues, op.kind == "hunt") end
  ga.lv = op.kind == "gnomes" and tonumber(op.lv) or nil
  ga.rv = op.kind == "santa" and tonumber(op.rv) or nil
  ga.note = Clean(op.note, Gm.NOTE_MAX)
end

-- The earliest time per key: each first stays.
local function first(map, k, t) if not map[k] or t < map[k] then map[k] = t end end
-- The newest choice per author ({ on, t }).
local function newest(map, author, on, t, lv)
  if not map[author] or map[author].t <= t then map[author] = { on = on, t = t, lv = lv } end
end

local function soundRep(op)
  return (op.n == nil or whole(op.n, 0, 1e5)) and (op.sq == nil or isSquare[op.sq] == true)
    and (op.here == nil or op.here == true) and (op.c == nil or whole(op.c, 1, Gm.CHECKS_MAX))
    and (op.dead == nil or op.dead == true)
end

local function report(ga, author, op, t)
  local r = ga.r[author] or { sq = {}, c = {} }
  ga.r[author] = r
  if op.n and op.n > (r.n or -1) then r.n, r.nt = op.n, t end
  if op.sq then first(r.sq, op.sq, t) end
  if op.here and (not r.here or t < r.here) then r.here = t end
  if op.c then first(r.c, op.c, t) end
  if op.dead and (not r.dead or t < r.dead) then r.dead = t end
end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
D:Register("game", {
  allowed = function(g, author, op) return sound(op) and D:Can("games", author, g) end,
  apply = function(g, author, op, t, n)
    if op.at < t - Gm.DAY or op.at > t + Gm.AHEAD then return false end
    take(get(g, D.Key(author, n)), author, op, t)
    return true
  end,
  copy = function(g) return g.games end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and type(e) == "table" then
        local ga = get(g, id)
        if not ga.h and party(e.h) and tonumber(e.t) and sound({ kind = e.kind, at = e.at, len = e.len,
          prize = e.prize, p = e.p, spot = e.spot, clues = e.clues, lv = e.lv, rv = e.rv, note = e.note }) then
          take(ga, e.h, e, e.t)
        end
        for _, f in ipairs({ "j", "v" }) do
          for name, x in pairs(type(e[f]) == "table" and e[f] or {}) do
            if party(name) and type(x) == "table" and tonumber(x.t) then newest(ga[f], name, x.on, x.t, tonumber(x.lv)) end
          end
        end
        for name, x in pairs(type(e.r) == "table" and e.r or {}) do
          if party(name) and type(x) == "table" then
            local r = ga.r[name] or { sq = {}, c = {} }
            ga.r[name] = r
            if whole(x.n, 0, 1e5) and tonumber(x.nt) and x.n > (r.n or -1) then r.n, r.nt = x.n, x.nt end
            if tonumber(x.here) and (not r.here or x.here < r.here) then r.here = x.here end
            if tonumber(x.dead) and (not r.dead or x.dead < r.dead) then r.dead = x.dead end
            for k, t in pairs(type(x.sq) == "table" and x.sq or {}) do if isSquare[k] and tonumber(t) then first(r.sq, k, t) end end
            for k, t in pairs(type(x.c) == "table" and x.c or {}) do if whole(k, 1, Gm.CHECKS_MAX) and tonumber(t) then first(r.c, k, t) end end
          end
        end
        if tonumber(e.cal) and (not ga.cal or e.cal < ga.cal) then ga.cal = e.cal end
        for _, fn in ipairs(Gm.mergers) do fn(ga, e) end
        if (e.st == "done" or e.st == "off") and not ga.st and tonumber(e.te) then
          ga.st, ga.te = e.st, e.te
          if e.st == "done" and type(e.w) == "table" then
            ga.w = {}
            for i, name in ipairs(e.w) do if party(name) and i <= Gm.WINNERS_MAX then ga.w[#ga.w + 1] = name end end
            ga.each = tonumber(e.each)
          end
        end
      end
    end
  end,
})

local function onGame(kind, def)
  local allowed = def.allowed
  def.allowed = function(g, author, op) return host(op.id) ~= nil and allowed(g, author, op) end
  D:Register(kind, def)
end
-- For the games with parts of their own (Guild/Traitors.lua, Guild/Santa.lua).
Gm.Get, Gm.OnGame = get, onGame

onGame("game_join", {
  allowed = function(_, _, op) return type(op.on) == "boolean" and (op.lv == nil or whole(op.lv, 1, Gm.LV_MAX)) end,
  apply = function(g, author, op, t)
    newest(get(g, op.id).j, author, op.on, t, op.lv)
    return true
  end,
})

onGame("game_rep", {
  allowed = function(_, _, op) return soundRep(op) end,
  apply = function(g, author, op, t)
    report(get(g, op.id), author, op, t)
    return true
  end,
})

onGame("game_vote", {
  allowed = function(_, author, op) return party(op.on) and op.on ~= author end,
  apply = function(g, author, op, t)
    newest(get(g, op.id).v, author, op.on, t)
    return true
  end,
})

onGame("game_cal", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local ga = get(g, op.id)
    if not ga.cal or t < ga.cal then ga.cal = t end
    return true
  end,
})

onGame("game_end", {
  allowed = function(g, author, op)
    if host(op.id) ~= author and not D:Can("games", author, g) then return false end
    if type(op.w) ~= "table" or #op.w > Gm.WINNERS_MAX or not whole(op.each, 0, 1e12) or not Pu.IsPurse(op.p) then return false end
    for _, name in ipairs(op.w) do if not party(name) then return false end end
    return true
  end,
  apply = function(g, author, op, t, n)
    local ga = get(g, op.id)
    if ga.st then return false end
    ga.st, ga.te, ga.w, ga.each = "done", t, {}, op.each
    local key = D.Key(author, n)
    for i, name in ipairs(op.w) do
      ga.w[i] = name
      if op.each > 0 then Pu:ChargeUnits(g, key .. ":" .. i, Pu.TREASURY, name, op.each, op.p, "game", t) end
    end
    return true
  end,
})

onGame("game_off", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local ga = get(g, op.id)
    if ga.st then return false end
    ga.st, ga.te = "off", t
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- An event's kind, and its title: the kind and when (SPEC decision 55), "Fishing contest · Sat 20:00". Hosts do not
-- name them.
function Gm.KindName(kind) return L["GM_" .. tostring(kind):upper()] or "" end
function Gm.Title(ga)
  local at = ga.kind == "santa" and ga.rv or ga.at
  if not at then return Gm.KindName(ga.kind) end
  return L.GM_TITLE:format(Gm.KindName(ga.kind), date(L.GM_DATE, at))
end

-- When the game stops counting (its time). The Traitors run until the host ends them; Secret Santa until the reveal.
function Gm.Ends(ga)
  if ga.kind == "traitors" then return math.huge end
  if ga.kind == "santa" then return ga.rv or 0 end
  return (ga.at or 0) + (ga.len or 0) * 60
end

-- "soon" (not started), "on", "over" (time is up, not ended yet), "done" or "off".
function Gm.State(ga, now)
  if ga.st then return ga.st end
  now = now or time()
  if now < (ga.at or 0) then return "soon" end
  if now < Gm.Ends(ga) then return "on" end
  return "over"
end

local function counts(ga, t)
  local from = (ga.at or 0) - (ga.kind == "flash" and Gm.EARLY or 0)
  return t >= from and t <= Gm.Ends(ga)
end

-- Who has joined, per player: { [key] = name } (the character that joined first). Not the host of The Traitors
-- (they present it); on the gnome run, only characters at or under its level.
function Gm.Joined(g, ga)
  local out, at = {}, {}
  for name, x in pairs(ga.j or {}) do
    if x.on and not (ga.kind == "traitors" and name == ga.h)
      and (ga.kind ~= "gnomes" or (x.lv or math.huge) <= (ga.lv or 0)) then
      local key = P:Of(name, g)
      if key and (not at[key] or x.t < at[key]) then out[key], at[key] = name, x.t end
    end
  end
  return out
end

function Gm.IsIn(g, ga, key) return Gm.Joined(g, ga)[key] ~= nil end

-- A card of squares (Gm.SQUARES in an order of its own, the free square at Gm.FREE_AT), the same on every copy:
-- drawn from the game's id and the name of the character that joined.
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h == 0 and 1 or h
end
function Gm.Card(id, name)
  local seed = hash(id .. "|" .. name)
  local list = {}
  for i, s in ipairs(Gm.SQUARES) do list[i] = s end
  for i = #list, 2, -1 do
    seed = (seed * 16807) % 2147483647
    local j = seed % i + 1
    list[i], list[j] = list[j], list[i]
  end
  table.insert(list, Gm.FREE_AT, "free")
  return list
end

-- Rows, columns and both diagonals of the card, as lists of positions.
local LINES = {}
do
  local n = Gm.SIZE
  for r = 0, n - 1 do
    local row, col = {}, {}
    for c = 0, n - 1 do row[#row + 1] = r * n + c + 1; col[#col + 1] = c * n + r + 1 end
    LINES[#LINES + 1] = row
    LINES[#LINES + 1] = col
  end
  local d1, d2 = {}, {}
  for i = 0, n - 1 do d1[#d1 + 1] = i * n + i + 1; d2[#d2 + 1] = i * n + (n - 1 - i) + 1 end
  LINES[#LINES + 1] = d1
  LINES[#LINES + 1] = d2
end
Gm.LINES = LINES

-- A player's reports, put together over their characters (only those made while the game counted).
local function merged(g, ga, key)
  local m = { sq = {}, c = {} }
  for name, r in pairs(ga.r or {}) do
    if P:Of(name, g) == key then
      m.name = m.name or name
      if r.n and r.nt and counts(ga, r.nt) and r.n > (m.n or -1) then m.n, m.nt = r.n, r.nt end
      if r.here and counts(ga, r.here) and (not m.here or r.here < m.here) then m.here = r.here end
      if r.dead and counts(ga, r.dead) and (not m.dead or r.dead < m.dead) then m.dead = r.dead end
      for k, t in pairs(r.sq or {}) do if counts(ga, t) then first(m.sq, k, t) end end
      for k, t in pairs(r.c or {}) do if counts(ga, t) then first(m.c, k, t) end end
    end
  end
  return m
end
Gm.Merged = merged

-- When the card got its first full line (nil: not yet), and how many squares are done.
function Gm.Bingo(ga, card, sq)
  local done = 0
  for _, s in ipairs(card) do if s == "free" or sq[s] then done = done + 1 end end
  local best
  for _, line in ipairs(LINES) do
    local last = ga.at or 0
    for _, pos in ipairs(line) do
      local s = card[pos]
      local t = s == "free" and ga.at or sq[s]
      if not t then last = nil break end
      if t > last then last = t end
    end
    if last and (not best or last < best) then best = last end
  end
  return best, done
end

-- The standings: { { key, name, v, t, bingo }, ... }, best first. v: fish, squares, clues found, votes, or 1 (at the
-- flash mob); t: when the player got there (the earlier is ahead).
-- The gnome run: how far a runner got, checkpoints in order (each after the one before, and before a death).
-- Returns the checkpoints reached, when the last was reached, and whether they finished alive.
function Gm.Run(ga, m)
  local n, last = 0, nil
  for i = 1, #(ga.clues or {}) do
    local t = m.c[i]
    if not t or (last and t < last) or (m.dead and t > m.dead) then break end
    n, last = i, t
  end
  return n, last, n > 0 and n == #ga.clues
end

function Gm.Scores(g, ga, id)
  local list = {}
  if ga.kind == "gnomes" then
    for key, name in pairs(Gm.Joined(g, ga)) do
      local m = merged(g, ga, key)
      local n, last, done = Gm.Run(ga, m)
      list[#list + 1] = { key = key, name = name, v = n, t = last or math.huge, done = done,
        dead = not done and m.dead or nil }
    end
    -- Finished first (the earliest first), then those still running, then the fallen.
    local function rank(e) return e.done and 1 or (e.dead and 3 or 2) end
    table.sort(list, function(a, b)
      if rank(a) ~= rank(b) then return rank(a) < rank(b) end
      if a.v ~= b.v then return a.v > b.v end
      if a.t ~= b.t then return a.t < b.t end
      return a.name < b.name
    end)
    return list
  end
  if ga.kind == "bingo" then
    for key, name in pairs(Gm.Joined(g, ga)) do
      local m = merged(g, ga, key)
      local bingo, done = Gm.Bingo(ga, Gm.Card(id, name), m.sq)
      list[#list + 1] = { key = key, name = name, v = done, t = bingo or math.huge, bingo = bingo }
    end
    table.sort(list, function(a, b)
      if a.t ~= b.t then return a.t < b.t end
      if a.v ~= b.v then return a.v > b.v end
      return a.name < b.name
    end)
    return list
  end
  local keys = {}
  if ga.kind == "fashion" then
    for key, name in pairs(Gm.Joined(g, ga)) do keys[key] = name end
  else
    for name in pairs(ga.r or {}) do local key = P:Of(name, g) if key then keys[key] = keys[key] or name end end
  end
  local votes = {}
  if ga.kind == "fashion" then
    -- One vote per player: their newest, made while it ran, for an entrant who is not themselves.
    local best = {}
    for name, x in pairs(ga.v or {}) do
      local voter = P:Of(name, g)
      if voter and counts(ga, x.t) and (not best[voter] or x.t > best[voter].t) then best[voter] = x end
    end
    for voter, x in pairs(best) do
      local on = P:Of(x.on, g)
      if on and on ~= voter and keys[on] then votes[on] = (votes[on] or 0) + 1 end
    end
  end
  for key, name in pairs(keys) do
    local m = merged(g, ga, key)
    local e = { key = key, name = m.name or name, v = 0, t = math.huge }
    if ga.kind == "derby" and m.n then e.v, e.t = m.n, m.nt
    elseif ga.kind == "flash" and m.here then e.v, e.t = 1, m.here
    elseif ga.kind == "hunt" then
      for _, t in pairs(m.c) do e.v = e.v + 1; e.t = e.t == math.huge and t or math.max(e.t, t) end
    elseif ga.kind == "fashion" then e.v, e.t = votes[key] or 0, 0 end
    if e.v > 0 or ga.kind == "fashion" then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    if a.v ~= b.v then return a.v > b.v end
    if a.t ~= b.t then return a.t < b.t end
    return a.name < b.name
  end)
  return list
end

-- Who wins: the first in the standings (bingo: only a full line); the Fashion show's ties share; at the flash mob,
-- everyone who was there. A list of characters' names.
function Gm.Winners(g, ga, id)
  local list, out = Gm.Scores(g, ga, id), {}
  if ga.kind == "flash" then
    for _, e in ipairs(list) do out[#out + 1] = e.name end
  elseif ga.kind == "fashion" then
    for _, e in ipairs(list) do if e.v > 0 and e.v == list[1].v then out[#out + 1] = e.name end end
  elseif ga.kind == "traitors" then
    out = ns.Traitors.Winners(ga)
  elseif ga.kind == "gnomes" then
    -- Every survivor shares the prize.
    for _, e in ipairs(list) do if e.done then out[#out + 1] = e.name end end
  elseif list[1] and (ga.kind ~= "bingo" or list[1].bingo) and list[1].v > 0 then
    out[1] = list[1].name
  end
  return out
end

-- Who found clue i first (a character's name), or nil.
function Gm.Finder(ga, i)
  local best, by
  for name, r in pairs(ga.r or {}) do
    local t = r.c and r.c[i]
    if t and counts(ga, t) and (not best or t < best) then best, by = t, name end
  end
  return by
end

-- The games to show, soonest first: open ones, then those finished in the last week. { { id, ga, st }, ... }
function Gm.List(g, now)
  now = now or time()
  local list = {}
  for id, ga in pairs(g and g.games or {}) do
    if ga.kind then
      local st = Gm.State(ga, now)
      if (st ~= "done" and st ~= "off") or now - (ga.te or 0) < Gm.KEEP then list[#list + 1] = { id = id, ga = ga, st = st } end
    end
  end
  local order = { on = 1, over = 2, soon = 3, done = 4, off = 5 }
  table.sort(list, function(a, b)
    if order[a.st] ~= order[b.st] then return order[a.st] < order[b.st] end
    if a.ga.at ~= b.ga.at then return a.ga.at < b.ga.at end
    return a.id < b.id
  end)
  return list
end

---------------------------------------------------------------------------
-- When: "now", "20:00" (today, or tomorrow when it has passed), "Sat 20:00" (the next Saturday), "24 Dec 20:00"
-- (the next 24 December)
---------------------------------------------------------------------------
local function month(word)
  for i, name in ipairs(L.GM_MONTHS) do
    if name:lower():sub(1, 3) == word:sub(1, 3) then return i end
  end
  return nil
end

function Gm.When(text, now)
  now = now or time()
  text = strtrim(tostring(text or "")):lower()
  if text == "" or text == L.GM_NOW_WORD:lower() then return now end
  local dd, mon, dh, dm = text:match("^(%d%d?)%s+(%a+)%s+(%d%d?)[:.](%d%d)$")
  if not dd then mon, dd, dh, dm = text:match("^(%a+)%s+(%d%d?)%s+(%d%d?)[:.](%d%d)$") end
  if dd then
    local mo = month(mon)
    dd, dh, dm = tonumber(dd), tonumber(dh), tonumber(dm)
    if not mo or dd < 1 or dd > 31 or dh > 23 or dm > 59 then return nil end
    local y = date("*t", now).year
    local at = time({ year = y, month = mo, day = dd, hour = dh, min = dm, sec = 0 })
    if at < now then at = time({ year = y + 1, month = mo, day = dd, hour = dh, min = dm, sec = 0 }) end
    -- 31 February and the like roll into the next month: refused.
    if date("*t", at).day ~= dd then return nil end
    return at
  end
  local day, h, m = text:match("^(%a+)%s+(%d%d?)[:.](%d%d)$")
  if not day then h, m = text:match("^(%d%d?)[:.](%d%d)$") end
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  local d = date("*t", now)
  local at = time({ year = d.year, month = d.month, day = d.day, hour = h, min = m, sec = 0 })
  if day then
    local want
    for i, name in ipairs(L.GM_DAYS) do
      if name:lower():sub(1, 3) == day:sub(1, 3) then want = i end
    end
    if not want then return nil end
    local ahead = (want - d.wday) % 7
    at = time({ year = d.year, month = d.month, day = d.day + ahead, hour = h, min = m, sec = 0 })
    if at < now then at = time({ year = d.year, month = d.month, day = d.day + ahead + 7, hour = h, min = m, sec = 0 }) end
  elseif at < now then
    at = time({ year = d.year, month = d.month, day = d.day + 1, hour = h, min = m, sec = 0 })
  end
  return at
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function purse() return D:Settings().purse end

function Gm.Open(kind, at, len, prize, extra)
  local op = { k = "game", kind = kind, at = at, len = len, prize = prize or 0, p = purse() }
  for k, v in pairs(extra or {}) do op[k] = v end
  return ns.Sync:Do(op)
end

-- The games joined face to face with the host (SPEC decision 72): Bingo and the transmog contest (its votes too).
Gm.FACE = { bingo = true, fashion = true }

-- Joins (or leaves). The gnome run tells this character's level, and refuses one above the run's.
function Gm.Join(id, on)
  local g = D:Current()
  local ga = g and g.games and g.games[id]
  if on and ga and Gm.FACE[ga.kind] and ga.h and not ns.Looks.Need(ga.h) then return false end
  local lv
  if ga and ga.kind == "gnomes" then
    lv = UnitLevel("player")
    if on and (issecretvalue and issecretvalue(lv) or (tonumber(lv) or 999) > (ga.lv or 0)) then
      ns:Print(L.GM_TOO_HIGH:format(ga.lv or 0), true)
      return false
    end
    lv = tonumber(lv)
  end
  return ns.Sync:Do({ k = "game_join", id = id, on = on and true or false, lv = lv })
end
function Gm.Vote(id, name)
  local g = D:Current()
  local ga = g and g.games and g.games[id]
  if ga and Gm.FACE[ga.kind] and ga.h and not ns.Looks.Need(ga.h) then return false end
  return ns.Sync:Do({ k = "game_vote", id = id, on = name })
end
function Gm.Cancel(id) return ns.Sync:Do({ k = "game_off", id = id }) end

-- Ends the game with the winners this copy sees; the Treasury owes each their share of the prize.
function Gm.Finish(id)
  local g = D:Current()
  local ga = g and g.games and g.games[id]
  if not ga or ga.st then return false end
  local w = Gm.Winners(g, ga, id)
  local units = Pu.Units(ga.prize or 0, ga.p)
  local each = 0
  if #w > 0 and units > 0 then each = ga.kind == "flash" and units or math.floor(units / #w) end
  return ns.Sync:Do({ k = "game_end", id = id, w = w, each = each, p = ga.p })
end

-- A clue claimed: this character's own position must be at its place.
function Gm.Claim(id, i)
  local g = D:Current()
  local ga = g and g.games and g.games[id]
  local clue = ga and ga.clues and ga.clues[i]
  if not clue or Gm.State(ga) ~= "on" then return false end
  local dist = ns.Punish.Distance(clue)
  if not dist or dist > Gm.NEAR then ns:Print(L.GM_NOT_HERE, true) return false end
  return ns.Sync:Do({ k = "game_rep", id = id, c = i })
end

---------------------------------------------------------------------------
-- This character's own addon: what it saw, for the games it is in
---------------------------------------------------------------------------
Gm.caught, Gm.there, Gm.reached, Gm.fallen = {}, {}, {}, {}

ns:On("SEEN", function(what)
  local g = D:Current()
  if not g then return end
  local me = P:Of(ns.Self(), g)
  for _, item in ipairs(Gm.List(g)) do
    local ga, id = item.ga, item.id
    local name = item.st == "on" and Gm.Joined(g, ga)[me]
    if name and ga.kind == "bingo" and isSquare[what] then
      local card, m = Gm.Card(id, name), merged(g, ga, me)
      for _, s in ipairs(card) do
        if s == what and not m.sq[what] then ns.Sync:Do({ k = "game_rep", id = id, sq = what }) end
      end
    elseif name == ns.Self() and ga.kind == "gnomes" and what == "die" and not Gm.fallen[id] then
      local m = merged(g, ga, me)
      if not m.dead and not select(3, Gm.Run(ga, m)) then
        Gm.fallen[id] = true
        ns.Sync:Do({ k = "game_rep", id = id, dead = true })
      end
    elseif name and ga.kind == "derby" and what == "fish" then
      local n = math.max(Gm.caught[id] or 0, merged(g, ga, me).n or 0) + 1
      Gm.caught[id] = n
      ns.Sync:Do({ k = "game_rep", id = id, n = n })
    end
  end
end)

-- The flash mob: at zero, is this character at the spot?
function Gm:Tick()
  local g = D:Current()
  if not g then return end
  local now = time()
  for _, item in ipairs(Gm.List(g, now)) do
    local ga, id = item.ga, item.id
    -- The gnome run: the next checkpoint, for the character that joined.
    if ga.kind == "gnomes" and item.st == "on" and Gm.Joined(g, ga)[P:Of(ns.Self(), g)] == ns.Self() then
      local m = merged(g, ga, P:Of(ns.Self(), g))
      local n, _, done = Gm.Run(ga, m)
      local nextUp = ga.clues[n + 1]
      local dist = not done and not m.dead and nextUp and ns.Punish.Distance(nextUp)
      if dist and dist <= Gm.GNOME_NEAR and not Gm.reached[id .. ":" .. (n + 1)] then
        Gm.reached[id .. ":" .. (n + 1)] = true
        ns.Sync:Do({ k = "game_rep", id = id, c = n + 1 })
        ns:Print(n + 1 == #ga.clues and L.GM_GNOME_FINISH or L.GM_GNOME_CHECK:format(n + 1, #ga.clues), true)
      end
    end
    if ga.kind == "flash" and not ga.st and not Gm.there[id] and now >= ga.at and now <= Gm.Ends(ga) then
      local dist = ns.Punish.Distance(ga.spot)
      if dist and dist <= Gm.FLASH_NEAR then
        Gm.there[id] = true
        ns.Sync:Do({ k = "game_rep", id = id, here = true })
        ns:Print(L.GM_FLASH_THERE, true)
      end
    end
  end
end
Gm.TICK = 2

ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Gm.TICK, function() Gm:Tick() end) end
end)
