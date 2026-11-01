-- The guild court (SPEC §7.3): a charge, a defence, a jury of members who sign up. Guilty needs 65% of the jury (a
-- Council rule). The verdict proposes a sentence from the Stocks menu: it applies by itself when the court may
-- sentence, else a member allowed to give that punishment confirms it. Only a player with Guild Together can be charged, and
-- the Guild Master is never sentenced (SPEC §6, decision 56).
--   court       { to, why, pun, len, c, jp }   a rank that may run the court charges a member; the proposed
--                                     sentence (pun, len, c: as in the Stocks); jp: the jury's percent when charged
--   court_def   { id, text }          the accused's defence (any of their characters)
--   court_jury  { id, on }            a member signs up for the jury, or steps down (not the accused or the runner)
--   court_vote  { id, guilty }        a juror's vote, which they can change until the case closes
--   court_close { id }                the runner closes the case; the verdict is the jury's votes until then
-- The verdict is worked out when read. The sentence is a Stocks sentence that names the case (ct).
local _, ns = ...
local D, P, St = ns.GuildData, ns.Players, ns.Stocks
local Clean = ns.Raffle.Clean

local Ct = {}
ns.Court = Ct

Ct.WHY_MAX, Ct.DEF_MAX = 80, 160
Ct.JURY_MIN = 3        -- fewer jurors at the close: the case is dismissed
-- Sentences a court can propose: those that need nothing but a length or a curse (decided 29 Oct 2026).
Ct.PUNS = { "dunce", "stocks", "curse", "radio", "wheel" }
Ct.LEN = 30

local isPun = {}
for _, p in ipairs(Ct.PUNS) do isPun[p] = true end

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function host(id) return D.KeyAuthor(id) end

local function soundCase(op)
  if not party(op.to) or not Clean(op.why, Ct.WHY_MAX) or not isPun[op.pun] then return false end
  local x = D.NUMBERS.jury
  local jp = tonumber(op.jp)
  if not jp or jp < x[2] or jp > x[3] then return false end
  return St.SoundSentence({ to = op.to, pun = op.pun, len = op.len, c = op.c })
end

local function get(g, id)
  local all = D.Part(g, "cases")
  all[id] = all[id] or { def = {}, jury = {}, v = {} }
  return all[id]
end

local function take(cs, author, op, t)
  cs.h, cs.to, cs.why, cs.pun, cs.t = author, op.to, Clean(op.why, Ct.WHY_MAX), op.pun, t
  cs.len, cs.c, cs.jp = tonumber(op.len), op.c, tonumber(op.jp)
end

-- The newest entry per author: { [name] = { x, t } }.
local function newest(map, name, x, t)
  local cur = map[name]
  if cur and cur.t > t then return false end
  map[name] = { x = x, t = t }
  return true
end

D:Register("court", {
  allowed = function(g, author, op) return soundCase(op) and op.to ~= author and D:Can("court", author, g) end,
  apply = function(g, author, op, t, n)
    take(get(g, D.Key(author, n)), author, op, t)
    return true
  end,
  copy = function(g) return g.cases end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and type(e) == "table" then
        local cs = get(g, id)
        if not cs.h and party(e.h) and tonumber(e.t) and soundCase(e) then take(cs, e.h, e, e.t) end
        for _, f in ipairs({ "def", "jury", "v" }) do
          for name, x in pairs(type(e[f]) == "table" and e[f] or {}) do
            if party(name) and type(x) == "table" and tonumber(x.t) and x.x ~= nil then
              local v = x.x
              if f == "def" then v = Clean(v, Ct.DEF_MAX) end
              if v ~= nil then newest(cs[f], name, v, x.t) end
            end
          end
        end
        if tonumber(e.closed) and (not cs.closed or e.closed < cs.closed) then cs.closed = e.closed end
      end
    end
  end,
})

D:Register("court_def", {
  allowed = function(_, _, op) return host(op.id) ~= nil and Clean(op.text, Ct.DEF_MAX) ~= nil end,
  apply = function(g, author, op, t) return newest(get(g, op.id).def, author, Clean(op.text, Ct.DEF_MAX), t) end,
})

D:Register("court_jury", {
  -- (In a Warcouncil the council is the jury: SPEC decision 70.)
  allowed = function(g, author, op)
    if ns.Rules.Setup(g) == "warcouncil" and op.on and not ns.Rules.InCouncil(g, author) then return false end
    return host(op.id) ~= nil and host(op.id) ~= author and type(op.on) == "boolean"
  end,
  apply = function(g, author, op, t) return newest(get(g, op.id).jury, author, op.on, t) end,
})

D:Register("court_vote", {
  allowed = function(_, _, op) return host(op.id) ~= nil and type(op.guilty) == "boolean" end,
  apply = function(g, author, op, t) return newest(get(g, op.id).v, author, op.guilty, t) end,
})

D:Register("court_close", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local cs = get(g, op.id)
    if cs.closed and cs.closed <= t then return false end
    cs.closed = t
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The newest entry per player, until time `to`: { [key] = { x, t, name } }.
local function perPlayer(g, map, to)
  local out = {}
  for name, e in pairs(map or {}) do
    if e.t <= (to or math.huge) then
      local key = P:Of(name, g)
      if not out[key] or e.t > out[key].t then out[key] = { x = e.x, t = e.t, name = name } end
    end
  end
  return out
end

-- A case as it stands: { id, cs, key (the accused), defence, jurors = { names }, guilty, innocent, onJury, mine,
-- verdict ("guilty", "innocent", "dismissed": once closed), calls (once closed: juror's name -> "guilty" or
-- "innocent"; who voted what shows only then, SPEC decision 74), sentence (its id, once given) }.
function Ct.Case(g, id)
  local cs = g.cases and g.cases[id]
  if not cs or not cs.h then return nil end
  local s = { id = id, cs = cs, key = P:Of(cs.to, g), guilty = 0, innocent = 0, jurors = {} }
  if not P:HasAddon(s.key) then return nil end
  -- A member who had opted out of punishment is not charged (SPEC decision 69); a case opened before stays. A change
  -- of setup cancels a case still open (decision 70).
  if ns.Rules.OptedOut(g, s.key, cs.t) then return nil end
  if not cs.closed and ns.Rules.Cancelled(g, cs.t) then return nil end
  local runner = P:Of(cs.h, g)
  local me = P:Of(ns.Self(), g)
  -- The defence: the newest from any of the accused's characters.
  local best
  for name, e in pairs(cs.def or {}) do
    if P:Of(name, g) == s.key and (not best or e.t > best.t) then best = e end
  end
  s.defence = best and best.x
  local jury = {}
  for key, e in pairs(perPlayer(g, cs.jury, cs.closed)) do
    if e.x and key ~= s.key and key ~= runner then
      jury[key] = e.name
      s.jurors[#s.jurors + 1] = e.name
      if key == me then s.onJury = true end
    end
  end
  table.sort(s.jurors)
  for key, e in pairs(perPlayer(g, cs.v, cs.closed)) do
    if jury[key] then
      if e.x then s.guilty = s.guilty + 1 else s.innocent = s.innocent + 1 end
      if key == me then s.mine = e.x end
      if cs.closed then
        s.calls = s.calls or {}
        s.calls[jury[key]] = e.x and "guilty" or "innocent"
      end
    end
  end
  if cs.closed then
    if #s.jurors < Ct.JURY_MIN then s.verdict = "dismissed"
    elseif s.guilty * 100 >= cs.jp * #s.jurors then s.verdict = "guilty"
    else s.verdict = "innocent" end
  end
  for sid, se in pairs(g.sentences or {}) do
    if se.ct == id and se.by and (not s.sentence or sid < s.sentence) then s.sentence = sid end
  end
  return s
end

-- Cases, open ones first, then the newest.
function Ct.Cases(g)
  local list = {}
  for id in pairs(g and g.cases or {}) do
    local s = Ct.Case(g, id)
    if s then list[#list + 1] = s end
  end
  table.sort(list, function(a, b)
    if (a.cs.closed == nil) ~= (b.cs.closed == nil) then return a.cs.closed == nil end
    if a.cs.t ~= b.cs.t then return a.cs.t > b.cs.t end
    return a.id > b.id
  end)
  return list
end

-- May this character give the verdict's sentence: the runner when the court sentences by itself, else a rank
-- allowed to give that punishment (not the accused).
function Ct.MaySentence(g, s, name)
  name = name or ns.Self()
  if s.verdict ~= "guilty" or s.sentence or P:Of(name, g) == s.key then return false end
  if not St.Punishable(g, s.key) then return false end
  if name == s.cs.h and D:CourtSentences(g) then return true end
  return D:Can(s.cs.pun, name, g)
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function sync(op) return ns.Sync:Do(op) end

function Ct.Charge(to, why, pun, len, c)
  if St.TIMED[pun] then len = len or Ct.LEN else len = nil end
  return sync({ k = "court", to = to, why = why, pun = pun, len = len, c = pun == "curse" and (c or "murloc") or nil,
    jp = D:Number("jury") })
end

function Ct.Defend(id, text) return sync({ k = "court_def", id = id, text = text }) end
function Ct.Jury(id, on) return sync({ k = "court_jury", id = id, on = on ~= false }) end
function Ct.Vote(id, guilty) return sync({ k = "court_vote", id = id, guilty = guilty and true or false }) end

-- The verdict's sentence, named after the case.
function Ct.Sentence(id)
  local g = D:Current()
  local s = g and Ct.Case(g, id)
  if not s or not Ct.MaySentence(g, s) then return false end
  local cs = s.cs
  return St.Sentence(cs.to, cs.pun, cs.len, cs.why, { c = cs.c, ct = id })
end

-- The runner closes the case; when the court sentences by itself, a guilty verdict's sentence follows at once.
function Ct.Close(id)
  if not sync({ k = "court_close", id = id }) then return false end
  local g = D:Current()
  local s = g and Ct.Case(g, id)
  if s and s.verdict == "guilty" and D:CourtSentences(g) and Ct.MaySentence(g, s) then Ct.Sentence(id) end
  return true
end
