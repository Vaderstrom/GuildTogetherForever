-- King of the Hill (SPEC §5, Arena): one crown. Decided 29 Oct 2026: an empty crown goes to the ladder's #1, and a
-- crown challenge that the holder declines, or leaves unanswered for a day, gives the crown to the challenger. The
-- holder must accept one challenge a day: one accepted in the day before or after a challenge excuses them from it.
--   crown_ch  { }      the author challenges the holder (its key is the challenge's id)
--   crown_ok  { id }   the holder accepts: the two duel in the game (Guild/Duels.lua, the match's id is the challenge's)
--   crown_no  { id }   the holder declines
-- Who holds the crown is worked out when read, by going through the guild's duels and these ops in time order, so
-- every copy agrees whatever order the ops reached it in. The ladder starts empty: the winner of the first ladder duel
-- is its #1, and takes the empty crown.
local _, ns = ...
local D = ns.GuildData
local P = ns.Players

local Cr = {}
ns.Crown = Cr
Cr.DAY = 86400
Cr.PLAY = 3 * 86400   -- an accepted challenge stays open for the duel this long

local function host(id) return D.KeyAuthor(id) end

local function get(g, id)
  local all = D.Part(g, "crown")
  all[id] = all[id] or {}
  return all[id]
end

D:Register("crown_ch", {
  allowed = function() return true end,
  apply = function(g, author, _, t, n)
    local ch = get(g, D.Key(author, n))
    ch.c, ch.t = author, t
    return true
  end,
  copy = function(g) return g.crown end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and type(e) == "table" then
        local ch = get(g, id)
        if not ch.c and type(e.c) == "string" and tonumber(e.t) then ch.c, ch.t = e.c, e.t end
        for by, x in pairs(type(e.ans) == "table" and e.ans or {}) do
          if type(by) == "string" and type(x) == "table" and (x.k == "ok" or x.k == "no") and tonumber(x.t) then
            ch.ans = ch.ans or {}
            if not ch.ans[by] then ch.ans[by] = { k = x.k, t = x.t } end
          end
        end
      end
    end
  end,
})

-- Answers are kept per author (each author's own ops arrive in order, so the first stays on every copy); only the
-- holder's counts, and who held the crown is known only when read.
for _, kind in ipairs({ "ok", "no" }) do
  D:Register("crown_" .. kind, {
    allowed = function(_, author, op) return host(op.id) ~= nil and host(op.id) ~= author end,
    apply = function(g, author, op, t)
      local ch = get(g, op.id)
      ch.ans = ch.ans or {}
      if ch.ans[author] then return false end
      ch.ans[author] = { k = kind, t = t }
      return true
    end,
  })
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- In one second: ladder duels, then challenges, then crown duels (after their own challenge, which can fall in the
-- same second in the game), then answers and lapses.
local ORDER = { duel = 1, ch = 2, crduel = 3, ans = 4, lapse = 5 }

-- The holder's answer to a challenge: "ok" or "no" and when, or nil.
local function answer(g, ch, holder)
  local best
  for by, x in pairs(ch.ans or {}) do
    if holder and P:Of(by, g) == holder and (not best or x.t < best.t) then best = x end
  end
  if best then return best.k, best.t end
  return nil
end

-- Did the holder accept a crown challenge within a day of this one (so they need not take this one)?
local function excused(g, id, holder)
  local chs = g.crown or {}
  local t = chs[id].t
  for other, ch in pairs(chs) do
    if other ~= id and ch.t then
      local k, at = answer(g, ch, holder)
      if k == "ok" and math.abs(at - t) <= Cr.DAY then return true end
    end
  end
  return false
end

-- The crown now: { holder (player), name (character), since, reigns = { { key, from, to } }, held = { [id] = holder
-- when challenged }, done = { [id] = true } }. holder is nil while nobody has won a ladder duel.
function Cr.State(g, now)
  now = now or time()
  local events = {}
  for c, e in pairs(g and g.duels or {}) do
    events[#events + 1] = { t = e.t or 0, k = e.cr and "crduel" or "duel", id = c, w = e.w, l = e.l, cr = e.cr }
  end
  local chs = g and g.crown or {}
  for id, ch in pairs(chs) do
    if ch.c and ch.t then
      events[#events + 1] = { t = ch.t, k = "ch", id = id }
      for _, x in pairs(ch.ans or {}) do
        if x.k == "no" then events[#events + 1] = { t = x.t, k = "ans", id = id } end
      end
      if ch.t + Cr.DAY <= now then events[#events + 1] = { t = ch.t + Cr.DAY, k = "lapse", id = id } end
    end
  end
  table.sort(events, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    if a.k ~= b.k then return ORDER[a.k] < ORDER[b.k] end
    return a.id < b.id
  end)
  local s = { reigns = {}, held = {}, done = {} }
  local function pass(name, t)
    if s.holder then s.reigns[#s.reigns + 1] = { key = s.holder, from = s.since, to = t } end
    s.holder, s.name, s.since = P:Of(name, g), name, t
  end
  for _, e in ipairs(events) do
    if e.k == "duel" or e.k == "crduel" then
      if not s.holder then
        pass(e.w, e.t)
      elseif e.cr and chs[e.cr] and chs[e.cr].c and s.held[e.cr] == s.holder and P:Of(e.l, g) == s.holder
        and P:Of(e.w, g) == P:Of(chs[e.cr].c, g) then
        pass(e.w, e.t)
      end
      if e.cr then s.done[e.cr] = true end
    elseif e.k == "ch" then
      s.held[e.id] = s.holder
    elseif not s.done[e.id] and s.holder and s.held[e.id] == s.holder then
      local ch = chs[e.id]
      local k, at = answer(g, ch, s.holder)
      local forfeit
      if e.k == "ans" then forfeit = k == "no" and at == e.t else forfeit = k == nil or at > ch.t + Cr.DAY end
      if forfeit and P:Of(ch.c, g) ~= s.holder and not excused(g, e.id, s.holder) then
        s.done[e.id] = true
        pass(ch.c, e.t)
      end
    end
  end
  return s
end

-- The longest reign so far (the one running included): { key, len (seconds) } or nil.
function Cr.Longest(s, now)
  local best
  local function try(key, from, to)
    local len = to - from
    if not best or len > best.len then best = { key = key, len = len } end
  end
  for _, r in ipairs(s.reigns) do try(r.key, r.from, r.to) end
  if s.holder then try(s.holder, s.since, now or time()) end
  return best
end

-- Crown challenges waiting for the holder's answer: { { id, c (challenger), t }, ... }, oldest first.
function Cr.Waiting(g, s, now)
  now = now or time()
  local list = {}
  for id, ch in pairs(g and g.crown or {}) do
    if ch.c and ch.t and ch.t + Cr.DAY > now and s.held[id] == s.holder and not s.done[id]
      and not answer(g, ch, s.holder) and P:Of(ch.c, g) ~= s.holder then
      list[#list + 1] = { id = id, c = ch.c, t = ch.t }
    end
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
  return list
end

-- Accepted crown challenges not yet fought: { { id, c, t }, ... }.
function Cr.Accepted(g, s, now)
  now = now or time()
  local list = {}
  for id, ch in pairs(g and g.crown or {}) do
    local k, at = answer(g, ch, s.holder)
    if ch.c and k == "ok" and not s.done[id] and at + Cr.PLAY > now and s.held[id] == s.holder then
      list[#list + 1] = { id = id, c = ch.c, t = at }
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- The crown match a duel between characters a and b counts for (Guild/Duels.lua), or nil.
function Cr.MatchWith(g, a, b)
  local s = Cr.State(g)
  if not s.holder then return nil end
  local pa, pb = P:Of(a, g), P:Of(b, g)
  for _, x in ipairs(Cr.Accepted(g, s)) do
    local pc = P:Of(x.c, g)
    if (pa == s.holder and pb == pc) or (pb == s.holder and pa == pc) then return { id = x.id, cr = x.id } end
  end
  return nil
end

-- My crown challenge that is still open: the challenge and "waiting" or "accepted", or nil.
function Cr.Mine(g, s)
  local me = P:MyId()
  for _, x in ipairs(Cr.Waiting(g, s)) do if P:Of(x.c, g) == me then return x, "waiting" end end
  for _, x in ipairs(Cr.Accepted(g, s)) do if P:Of(x.c, g) == me then return x, "accepted" end end
  return nil
end

-- Would declining this challenge cost the holder the crown (no other accepted in the day around it)?
function Cr.Costly(g, s, id) return not excused(g, id, s.holder) end

function Cr.Challenge() return ns.Sync:Do({ k = "crown_ch" }) end
function Cr.Accept(id) return ns.Sync:Do({ k = "crown_ok", id = id }) end
function Cr.Decline(id) return ns.Sync:Do({ k = "crown_no", id = id }) end
