-- Council (SPEC §7): the charter, votes and polls, strikes, the Guild Master's election, and motions. A motion is a change to one of
-- the Council's rules (decided 29 Oct 2026: the Guild Master sets the rules, and a vote of the guild can change them:
-- seconds, then a vote of every member), or leadership (SPEC §7.5, decision 46, the old Guild Hall laws): an
-- impeachment by the officers, a Mak'gora, or the crown the Guild Master opens.
--   charter     { v, lines }              the Guild Master writes version v of the charter
--   charter_ok  { v }                     a member accepts version v
--   poll        { q, ch, sec, wt, days }  a rank that may open polls: a question, 2 to 6 choices (none: yes or no),
--                                         secret (only totals show), weighted by rank, open 1 to 7 days
--   poll_vote   { id, on, who }           on: the choice's number (yes 1, no 2); who: a member without the addon who
--                                         whispered !vote to the author
--   strike      { to, why, days }         a rank that may give strikes; it counts once a second member confirms it
--   strike_ok   { id }                    a rank that may confirm strikes, not the one who gave it
--   strike_x    { id }                    the Guild Master takes a strike back (a Monarchy, SPEC decision 70)
--   motion      { kind, why, ... }        kind "rule" { r, v, m, sec, hrs, days, quo }: rule r becomes v (a rank that
--                                         may file motions; the numbers in force travel with it); "lead" { gm, vt }:
--                                         an officer starts an impeachment, vt the officers who vote, fixed now;
--                                         "mak" { gm, m }: a member challenges the Guild Master to Mak'gora; "crown":
--                                         the Guild Master opens the crown. m: members (who may vote) when made
--   motion_sec  { id }                    a member seconds a rule change
--   motion_vote { id, on, who }           yes (true) or no, on a rule change or a declined Mak'gora; who: as for polls
--   motion_say  { id, text }              the Guild Master's statement
--   imp_vote    { id, on, c }             an officer's vote in an impeachment: yes with who should lead (c), or no
--   motion_cancel { id }                  the impeachment's starter cancels it
--   mak_ok      { id, on }                the Guild Master accepts (true) or declines a Mak'gora
--   mak_duel    { id, w }                 the Mak'gora's duel, by its loser's addon: w won
--   lead_done   { id }                    the winner's addon, once it leads: the hand-over is done
--   rebel       { id, m }                 a Dictatorship's declined Mak'gora: its challenger declares a rebellion (m:
--                                         members with Guild Together now, SPEC decision 70)
--   rebel_sign  { id }                    a member signs the rebellion
--   elect_run   { m, line }               a member stands for Guild Master in month m's election ("2026-11")
--   elect_vote  { m, on, who }            a vote in it (on: the character who stood, or the Guild Master)
--   elect_done  { m }                     the winner's addon, once it leads
-- The crown's tournament is a cup with the motion's id (Guild/Cup.lua, lead_cup), run by the Guild Master who opened it.
-- Everything else is worked out when read: who seconded in time, the votes inside the window, whether it passed.
-- Members without the addon vote by whisper (SPEC §7.2): !vote 2, !vote yes, !vote <name>.
local _, ns = ...
local L, D, R, P = ns.L, ns.GuildData, ns.Roster, ns.Players
local Clean = ns.Raffle.Clean

local Co = { ver = 0, offset = 0 }
ns.Council = Co

-- The time the Council reads at. offset: only the self-test moves it on (days pass in an instant there), and the
-- pretend guild's end puts it back (Dev/Sandbox.lua).
function Co.Now() return time() + Co.offset end

-- The guild's months are counted in UTC: "2026-11", the day of the month, the month before.
local function month(t) return date("!%Y-%m", t) end
local function day(t) return tonumber(date("!%d", t)) end
local function lastMonth(t)
  local y, m = month(t):match("^(%d+)%-(%d+)$")
  y, m = tonumber(y), tonumber(m) - 1
  if m == 0 then y, m = y - 1, 12 end
  return ("%04d-%02d"):format(y, m)
end
Co.Month, Co.LastMonth = month, lastMonth

Co.LINES_MAX, Co.LINE_MAX = 40, 120
Co.Q_MAX, Co.CHOICE_MAX, Co.CHOICES_MAX = 80, 40, 6
Co.WHY_MAX, Co.SAY_MAX, Co.CAMPAIGN_MAX = 80, 160, 80
Co.STRIKE_DAYS, Co.STRIKE_DAYS_MAX = 30, 90
Co.STAND_DAYS, Co.VOTE_DAYS = 4, 7     -- the election, each month: stand on the 1st to the 4th, vote the 5th to the 7th
Co.REBEL_WAIT = 3 * 86400              -- after a declined Mak'gora in a Dictatorship: to declare a rebellion
Co.REBEL_SIGN = 3 * 86400              -- to sign it
Co.REBEL_FIGHT = 3 * 86400             -- the duel, once a third have signed
Co.SIGNUP = 3 * 86400                  -- the crown tournament's sign-up (SPEC §7.5)
Co.WEEK = 7 * 86400
Co.TICK = 10

-- The rules a vote can change: who may (rows of the rank table), the Council's numbers, the court's switch, and the
-- three punishment switches (SPEC decisions 69 and 70: ptax Tax punishments, pcourt incidents by the court, ptrial
-- Trial by combat; Guild/Rules.lua reads them).
Co.PERM_RULES = { "poll", "motion", "sees", "court", "strike", "confirm" }
Co.PUN_RULES = { "ptax", "pcourt", "ptrial" }
Co.RULES = {}
for _, r in ipairs(Co.PERM_RULES) do Co.RULES[r] = "ranks" end
for _, k in ipairs(D.NUMBER_KEYS) do Co.RULES[k] = "number" end
Co.RULES.sentence = "flag"
for _, r in ipairs(Co.PUN_RULES) do Co.RULES[r] = "flag" end

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function bump() Co.ver = Co.ver + 1 end

-- A rule's value: a list of ranks (1 to 9), a number in its range, or true / false.
local function soundValue(r, v)
  local kind = Co.RULES[r]
  if kind == "ranks" then
    if type(v) ~= "table" or #v > D.RANK_MAX then return false end
    for _, i in ipairs(v) do if not whole(i, 1, D.RANK_MAX) then return false end end
    return true
  elseif kind == "number" then
    local x = D.NUMBERS[r]
    return whole(v, x[2], x[3])
  elseif kind == "flag" then
    return type(v) == "boolean"
  end
  return false
end

---------------------------------------------------------------------------
-- The guild's members, as players (one vote each, SPEC §1)
---------------------------------------------------------------------------
local function roster() return R.pretend and R.pretend.ranks or R.ranks end

function Co.Members(g)
  local seen, n = {}, 0
  for name in pairs(roster()) do
    local key = P:Of(name, g)
    if not seen[key] then seen[key] = true; n = n + 1 end
  end
  return n
end

-- The Guild Master's character now, from the roster.
function Co.GM()
  for name, rank in pairs(roster()) do if rank == 0 then return name end end
  return nil
end

-- Does one of the player's characters hold rank 0 now?
local function leads(g, key)
  for _, name in ipairs(P:Chars(key, g)) do if R:Rank(name) == 0 then return true end end
  return false
end

local function inGuild(g, key)
  for _, name in ipairs(P:Chars(key, g)) do if R:Rank(name) ~= nil then return true end end
  return false
end

-- The newest choice per player among votes { [name] = { on, t } }, with t inside [from, to].
local function latest(g, votes, from, to)
  local per = {}
  for name, x in pairs(votes or {}) do
    if type(x) == "table" and x.t >= (from or 0) and x.t <= (to or math.huge) then
      local key = P:Of(name, g)
      local cur = per[key]
      if not cur or x.t > cur.t or (x.t == cur.t and name < cur.name) then per[key] = { on = x.on, t = x.t, name = name } end
    end
  end
  return per
end

local function newest(map, name, on, t)
  local cur = map[name]
  if cur and cur.t > t then return false end
  map[name] = { on = on, t = t }
  return true
end

---------------------------------------------------------------------------
-- The charter (SPEC §7.1)
---------------------------------------------------------------------------
local function soundLines(lines)
  if type(lines) ~= "table" or #lines < 1 or #lines > Co.LINES_MAX then return false end
  for _, l in ipairs(lines) do if type(l) ~= "string" then return false end end
  return true
end

local function takeCharter(g, author, op, t)
  local c = g.charter
  local v = tonumber(op.v)
  if c and (c.v > v or (c.v == v and c.t >= t)) then return false end
  local lines = {}
  for _, l in ipairs(op.lines) do
    local clean = Clean(l, Co.LINE_MAX)
    if clean then lines[#lines + 1] = clean end
  end
  g.charter = { v = v, lines = lines, t = t, a = author }
  bump()
  return true
end

D:Register("charter", {
  allowed = function(g, author, op) return D:InCharge(author, g) and whole(op.v, 1, 100000) and soundLines(op.lines) end,
  apply = function(g, author, op, t) return takeCharter(g, author, op, t) end,
  -- The whole Council travels with the charter's kind.
  copy = function(g)
    return { charter = g.charter, ok = g.charterOk, polls = g.polls, strikes = g.strikes, motions = g.motions,
      elections = g.elections }
  end,
  merge = function(g, part) Co.Merge(g, part) end,
})

D:Register("charter_ok", {
  allowed = function(_, _, op) return whole(op.v, 1, 100000) end,
  apply = function(g, author, op)
    local ok = D.Part(g, "charterOk")
    if (ok[author] or 0) >= op.v then return false end
    ok[author] = op.v
    bump()
    return true
  end,
})

-- The charter, how many players accepted this version, and how many there are.
function Co.Charter(g)
  local c = g and g.charter
  if not c then return nil, 0, Co.Members(g) end
  return c, #Co.AcceptedBy(g), Co.Members(g)
end

-- Who accepted the charter in force: one name for each player in the guild (SPEC §1), sorted.
function Co.AcceptedBy(g)
  local c, out = g and g.charter, {}
  if not c then return out end
  local seen = {}
  for name, v in pairs(g.charterOk or {}) do
    local key = P:Of(name, g)
    if v >= c.v and not seen[key] and roster()[name] ~= nil then seen[key] = true; out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Has this player accepted the charter in force?
function Co.Accepted(g, key)
  local c = g and g.charter
  if not c then return true end
  for _, name in ipairs(P:Chars(key, g)) do if ((g.charterOk or {})[name] or 0) >= c.v then return true end end
  return false
end

---------------------------------------------------------------------------
-- Votes and polls (SPEC §7.2)
---------------------------------------------------------------------------
local function soundPoll(op)
  if not Clean(op.q, Co.Q_MAX) or not whole(op.days, 1, 7) then return false end
  if op.ch ~= nil then
    if type(op.ch) ~= "table" or #op.ch < 2 or #op.ch > Co.CHOICES_MAX then return false end
    for _, c in ipairs(op.ch) do if not Clean(c, Co.CHOICE_MAX) then return false end end
  end
  return true
end

local function takePoll(po, author, op, t)
  po.h, po.t, po.q, po.days = author, t, Clean(op.q, Co.Q_MAX), tonumber(op.days)
  po.sec, po.wt = op.sec == true or nil, op.wt == true or nil
  if op.ch then
    po.ch = {}
    for i, c in ipairs(op.ch) do po.ch[i] = Clean(c, Co.CHOICE_MAX) end
  end
  po.v = po.v or {}
end

D:Register("poll", {
  allowed = function(g, author, op) return soundPoll(op) and D:Can("poll", author, g) end,
  apply = function(g, author, op, t, n)
    local all = D.Part(g, "polls")
    local id = D.Key(author, n)
    all[id] = all[id] or {}
    takePoll(all[id], author, op, t)
    bump()
    return true
  end,
})

local function choices(po) return po.ch and #po.ch or 2 end

D:Register("poll_vote", {
  allowed = function(_, author, op)
    return host(op.id) ~= nil and whole(op.on, 1, Co.CHOICES_MAX) and (op.who == nil or (party(op.who) and op.who ~= author))
  end,
  apply = function(g, author, op, t)
    local all = D.Part(g, "polls")
    all[op.id] = all[op.id] or { v = {} }
    local po = all[op.id]
    po.v = po.v or {}
    if not newest(po.v, op.who or author, op.on, t) then return false end
    bump()
    return true
  end,
})

-- A vote's weight: one, or by rank when the poll is weighted (decided 29 Oct 2026: the ranks below plus one, so the
-- lowest rank counts 1 and the Guild Master the most).
function Co.Weight(po, name)
  if not po.wt then return 1 end
  local rank = R:Rank(name)
  if rank == nil then return 1 end
  local n = R.pretend and #R.pretend.names or (#R:Ranks() + 1)
  return math.max(1, n - rank)
end

-- A poll as it stands: { id, q, rows = { { label, n, who = { names } } }, cast, open, ends, mine }.
function Co.Poll(g, id, now)
  local po = g.polls and g.polls[id]
  if not po or not po.h then return nil end
  now = now or Co.Now()
  local ends = po.t + po.days * 86400
  -- (A change of setup closes a poll still open: SPEC decision 70.)
  local s = { id = id, po = po, q = po.q, ends = ends, open = now < ends and not ns.Rules.Cancelled(g, po.t), rows = {},
    cast = 0, voters = {} }
  for i = 1, choices(po) do s.rows[i] = { label = po.ch and po.ch[i] or (i == 1 and L.CO_YES or L.CO_NO), n = 0, who = {} } end
  local me = P:Of(ns.Self(), g)
  for key, x in pairs(latest(g, po.v, po.t, ends)) do
    local row = s.rows[x.on]
    if row then
      row.n = row.n + Co.Weight(po, x.name)
      row.who[#row.who + 1] = x.name
      s.voters[#s.voters + 1] = { name = x.name, t = x.t }
      s.cast = s.cast + 1
      if key == me then s.mine = x.on end
    end
  end
  for _, row in ipairs(s.rows) do table.sort(row.who) end
  table.sort(s.voters, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.name < b.name end)
  return s
end

-- Polls, open ones first, then the newest.
function Co.Polls(g, now)
  local list = {}
  for id in pairs(g and g.polls or {}) do
    local s = Co.Poll(g, id, now)
    if s then list[#list + 1] = s end
  end
  table.sort(list, function(a, b)
    if a.open ~= b.open then return a.open end
    if a.po.t ~= b.po.t then return a.po.t > b.po.t end
    return a.id > b.id
  end)
  return list
end

---------------------------------------------------------------------------
-- Strikes (SPEC §7.4): real warnings, kept apart from the fun. Every member with the addon sees them (decided 29 Oct
-- 2026), unless the rule "sees" says otherwise.
---------------------------------------------------------------------------
local function soundStrike(op)
  return party(op.to) and Clean(op.why, Co.WHY_MAX) ~= nil and whole(op.days, 1, Co.STRIKE_DAYS_MAX)
end

D:Register("strike", {
  -- (Protection, SPEC §7.5: not a challenger during their Mak'gora.)
  allowed = function(g, author, op)
    return soundStrike(op) and op.to ~= author and D:Can("strike", author, g) and not Co.Protected(g, op.to)
  end,
  apply = function(g, author, op, t, n)
    local all = D.Part(g, "strikes")
    local id = D.Key(author, n)
    local s = all[id] or {}
    s.by, s.to, s.why, s.days, s.t = author, op.to, Clean(op.why, Co.WHY_MAX), tonumber(op.days), t
    s.ok = s.ok or {}
    all[id] = s
    bump()
    return true
  end,
})

D:Register("strike_ok", {
  allowed = function(g, author, op) return host(op.id) ~= nil and host(op.id) ~= author and D:Can("confirm", author, g) end,
  apply = function(g, author, op, t)
    local all = D.Part(g, "strikes")
    all[op.id] = all[op.id] or { ok = {} }
    local s = all[op.id]
    s.ok = s.ok or {}
    if s.ok[author] and s.ok[author] <= t then return false end
    s.ok[author] = t
    bump()
    return true
  end,
})

-- The Guild Master takes a strike back, in a Monarchy (SPEC decision 70).
D:Register("strike_x", {
  allowed = function(g, author, op)
    return host(op.id) ~= nil and D:InCharge(author, g) and ns.Rules.Setup(g) == "monarchy"
  end,
  apply = function(g, _, op, t)
    local all = D.Part(g, "strikes")
    all[op.id] = all[op.id] or { ok = {} }
    local s = all[op.id]
    if s.x and s.x <= t then return false end
    s.x = t
    bump()
    return true
  end,
})

-- Strikes, newest first: { id, to, key, why, by, t, ends, ok (who confirmed), st ("wait", "ok", "over", "taken") }; and how
-- many confirmed strikes each player has running. Only players with Guild Together get strikes (SPEC decision 56).
function Co.Strikes(g, now)
  now = now or Co.Now()
  local list, count = {}, {}
  for id, s in pairs(g and g.strikes or {}) do
    if s.by and P:HasAddon(P:Of(s.to, g)) then
      local okBy, okT
      for name, t in pairs(s.ok or {}) do
        if name ~= s.by and P:Of(name, g) ~= P:Of(s.to, g) and (not okT or t < okT) then okBy, okT = name, t end
      end
      local ends = s.t + s.days * 86400
      local e = { id = id, to = s.to, key = P:Of(s.to, g), why = s.why, by = s.by, t = s.t, ends = ends, ok = okBy }
      -- (In a Dictatorship a strike counts at once, with no second: SPEC decision 70.)
      e.st = now >= ends and "over" or ((okBy or ns.Rules.StrikeAtOnce(g)) and "ok" or "wait")
      if s.x and s.x <= now then e.st = "taken" end
      if e.st == "ok" then count[e.key] = (count[e.key] or 0) + 1 end
      list[#list + 1] = e
    end
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id > b.id end)
  return list, count
end

-- May this character see the strikes? Those the rule allows, those who give or confirm them; and everyone sees their
-- own.
function Co.SeesStrikes(name, g)
  return D:Can("sees", name, g) or D:Can("strike", name, g) or D:Can("confirm", name, g)
end

---------------------------------------------------------------------------
-- Motions: rule changes (seconds, then every member votes), and leadership (SPEC §7.5, decision 46: the old Guild
-- Hall laws): an impeachment by the officers ("lead"), a Mak'gora ("mak"), or the crown the Guild Master opens
-- ("crown"). Only one leadership motion runs at a time.
---------------------------------------------------------------------------
local KINDS = { lead = true, rule = true, crown = true, mak = true, setup = true }
local RULE_NUMBERS = { "sec", "hrs", "days", "quo" }
Co.VOTERS_MAX = 120   -- (in a Democracy every member votes in an impeachment)

-- The old laws' numbers (fixed, SPEC §7.5).
Co.IMPEACH_DAYS = 7 * 86400   -- an impeachment's vote
Co.IMPEACH_GAP = 7 * 86400    -- one a week, counted from the last one's start
Co.MAK_SINCE = 30 * 86400     -- in the guild this long before a challenge
Co.MAK_ACCEPT = 7 * 86400     -- the Guild Master's answer
Co.MAK_VOTE = 3 * 86400       -- the guild's vote when they decline
Co.MAK_QUORUM = 50            -- percent of members who must vote
Co.MAK_FIGHT = 7 * 86400      -- the duel, once accepted or forced
Co.MAK_AGAIN = 30 * 86400     -- after a lost challenge
Co.SEEN_GM = 3600             -- the Guild Master online this long without handing over: everyone is told

local function soundVoters(list)
  if type(list) ~= "table" or #list < 1 or #list > Co.VOTERS_MAX then return false end
  for _, n in ipairs(list) do if not party(n) then return false end end
  return true
end

local function soundMotion(op)
  if not KINDS[op.kind] then return false end
  if op.kind == "crown" then return true end
  if not Clean(op.why, Co.WHY_MAX) then return false end
  if op.kind == "lead" then return party(op.gm) and soundVoters(op.vt) end
  if not whole(op.m, 1, 100000) then return false end
  if op.kind == "mak" then return party(op.gm) end
  for _, k in ipairs(RULE_NUMBERS) do if not soundValue(k, op[k]) then return false end end
  if op.vt ~= nil and not soundVoters(op.vt) then return false end
  if op.kind == "setup" then
    local ok = false
    for _, id in ipairs(ns.Rules.SETUPS) do if op.setup == id then ok = true end end
    return ok
  end
  return soundValue(op.r, op.v)
end

local function takeMotion(mo, author, op, t)
  mo.a, mo.kind, mo.t = author, op.kind, t
  mo.why = Clean(op.why, Co.WHY_MAX)
  mo.m, mo.gm = tonumber(op.m), op.kind == "crown" and author or op.gm
  if op.kind == "lead" then
    mo.vt = {}
    for i, name in ipairs(op.vt) do mo.vt[i] = name end
  elseif op.kind == "rule" or op.kind == "setup" then
    for _, k in ipairs(RULE_NUMBERS) do mo[k] = tonumber(op[k]) end
    -- Who votes when not every member (the council, the officers: SPEC decision 70), fixed when made.
    if op.vt then
      mo.vt = {}
      for i, name in ipairs(op.vt) do mo.vt[i] = name end
    end
    if op.kind == "setup" then
      mo.setup, mo.elect = op.setup, op.elect == true or nil
      mo.sits = op.sits == "elders" and "elders" or "officers"
      mo.judge = op.judge == "crown" and "crown" or "ranks"
    end
    mo.r = op.r
    if type(op.v) == "table" then
      mo.v = {}
      for i, x in ipairs(op.v) do mo.v[i] = tonumber(x) end
    else
      mo.v = op.v
    end
  end
  mo.sd, mo.votes, mo.iv, mo.duels = mo.sd or {}, mo.votes or {}, mo.iv or {}, mo.duels or {}
end

local function motion(g, id)
  local all = D.Part(g, "motions")
  all[id] = all[id] or { sd = {}, votes = {}, iv = {}, duels = {} }
  return all[id]
end

-- The lowest rank (the rank no one may name as Guild Master).
local function lowest()
  local low = 0
  for _, r in ipairs(R:Ranks()) do low = math.max(low, r.index) end
  return low
end

-- The impeachment's voters as the starter's addon sees them: every character of a rank that may impeach, but the
-- Guild Master's (fixed when it starts, SPEC §7.5).
function Co.Officers(g)
  local list = {}
  local Ru = ns.Rules
  local setup = Ru.Setup(g)
  for name, rank in pairs(roster()) do
    -- Who votes in an impeachment (SPEC decision 70): every member with Guild Together in a Democracy or a Free guild,
    -- the council in a Warcouncil, the officers in a Monarchy.
    local yes
    if setup == "democracy" or setup == "free" then yes = P:HasAddon(P:Of(name, g))
    elseif setup == "warcouncil" then yes = Ru.InCouncil(g, name)
    elseif setup == "monarchy" then yes = Ru.Officer(g, name)
    else yes = D:Ranks("impeach", g)[rank] end
    if rank ~= 0 and yes then list[#list + 1] = name end
  end
  table.sort(list)
  while #list > Co.VOTERS_MAX do table.remove(list) end
  return list
end

-- Is name the Guild Master's rightful successor-to-be someone may vote for: in the guild, not the Guild Master, not
-- of the lowest rank?
function Co.Candidate(name)
  local rank = R:Rank(name)
  return rank ~= nil and rank ~= 0 and rank ~= lowest()
end

-- May name put a change to the vote, of kind "rule" or "setup" (SPEC decision 70)? A rule change: who may file
-- motions (in a Democracy or a Warcouncil the Guild Master too). A change of setup: in a Democracy anyone who may
-- file motions, or the Guild Master; in a Warcouncil the Guild Master puts it to the council; in a Monarchy the
-- officers may overrule the Guild Master's.
function Co.MayPropose(g, name, kind)
  local setup = ns.Rules.Setup(g)
  if kind == "setup" then
    if setup == "democracy" then return D:InCharge(name, g) or D:Can("motion", name, g) end
    if setup == "warcouncil" then return D:InCharge(name, g) end
    if setup == "monarchy" then return R:Rank(name) ~= 0 and D:Can("motion", name, g) end
    return false
  end
  if (setup == "democracy" or setup == "warcouncil") and D:InCharge(name, g) then return true end
  return R:Rank(name) ~= nil and R:Rank(name) ~= 0 and D:Can("motion", name, g)
end

D:Register("motion", {
  allowed = function(g, author, op)
    if not soundMotion(op) then return false end
    if op.kind == "rule" or op.kind == "setup" then return Co.MayPropose(g, author, op.kind) end
    if op.kind == "crown" then return D:InCharge(author, g) end
    if op.kind == "lead" then return R:Rank(author) ~= 0 and D:Can("impeach", author, g) end
    return R:Rank(author) ~= nil and R:Rank(author) ~= 0
  end,
  apply = function(g, author, op, t, n)
    -- The laws that depend on time are read at the op's own time: one at a time, one impeachment a week, Mak'gora's
    -- days in the guild and the wait after a lost challenge.
    if op.kind ~= "rule" and not Co.MayStart(g, op.kind, author, t) then return false end
    local mo = motion(g, D.Key(author, n))
    takeMotion(mo, author, op, t)
    -- (A Mak'gora made in a Dictatorship has no guild vote: a rebellion instead, SPEC decision 70.)
    if op.kind == "mak" then mo.dict = ns.Rules.Setup(g) == "dictatorship" or nil end
    bump()
    return true
  end,
})

D:Register("motion_sec", {
  allowed = function(_, author, op) return host(op.id) ~= nil and host(op.id) ~= author end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    if mo.sd[author] and mo.sd[author] <= t then return false end
    mo.sd[author] = t
    bump()
    return true
  end,
})

-- A rule change's vote, or the guild's vote on a Mak'gora the Guild Master declined.
D:Register("motion_vote", {
  allowed = function(_, author, op)
    return host(op.id) ~= nil and type(op.on) == "boolean" and (op.who == nil or (party(op.who) and op.who ~= author))
  end,
  apply = function(g, author, op, t)
    if not newest(motion(g, op.id).votes, op.who or author, op.on, t) then return false end
    bump()
    return true
  end,
})

D:Register("motion_veto", {
  allowed = function(g, author, op)
    local mo = g.motions and g.motions[op.id]
    return host(op.id) ~= nil and D:InCharge(author, g) and ns.Rules.Setup(g) == "warcouncil"
      and (mo == nil or mo.kind == "rule" or mo.kind == "setup")
  end,
  apply = function(g, _, op, t)
    local mo = motion(g, op.id)
    if mo.veto and mo.veto <= t then return false end
    mo.veto = t
    bump()
    return true
  end,
})

D:Register("motion_say", {
  allowed = function(_, author, op) return host(op.id) ~= nil and R:Rank(author) == 0 and Clean(op.text, Co.SAY_MAX) ~= nil end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    if mo.say and mo.say.t > t then return false end
    mo.say = { text = Clean(op.text, Co.SAY_MAX), a = author, t = t }
    bump()
    return true
  end,
})

-- An officer's vote in an impeachment: yes with who should be Guild Master (c), or no. Every vote is kept, so each copy
-- reads them in the same order and stops where it passed or failed.
local function addVote(mo, author, on, c, t)
  local list = mo.iv[author] or {}
  mo.iv[author] = list
  for _, x in ipairs(list) do if x.t == t and x.on == on and x.c == c then return false end end
  list[#list + 1] = { on = on, c = c, t = t }
  table.sort(list, function(a, b) return a.t < b.t end)
  return true
end

D:Register("imp_vote", {
  allowed = function(_, _, op)
    return host(op.id) ~= nil and type(op.on) == "boolean" and (not op.on or (party(op.c) and Co.Candidate(op.c)))
  end,
  apply = function(g, author, op, t)
    if not addVote(motion(g, op.id), author, op.on, op.on and op.c or nil, t) then return false end
    bump()
    return true
  end,
})

-- The impeachment's starter cancels it.
D:Register("motion_cancel", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local mo = motion(g, op.id)
    if mo.x and mo.x <= t then return false end
    mo.x = t
    bump()
    return true
  end,
})

-- The Guild Master answers a Mak'gora: accepted (true) or declined. The first answer counts.
D:Register("mak_ok", {
  allowed = function(_, author, op) return host(op.id) ~= nil and type(op.on) == "boolean" and R:Rank(author) == 0 end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    if mo.ok and mo.ok.t <= t then return false end
    mo.ok = { on = op.on, a = author, t = t }
    bump()
    return true
  end,
})

-- A rebellion (a Dictatorship's declined Mak'gora, SPEC decision 70): its challenger declares it, members sign it.
-- Kept per character; reading counts only the challenger's and the signatures in time.
D:Register("rebel", {
  allowed = function(_, _, op) return host(op.id) ~= nil and whole(op.m, 1, 10000) end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    mo.rbs = mo.rbs or {}
    if mo.rbs[author] and mo.rbs[author].t <= t then return false end
    mo.rbs[author] = { t = t, m = op.m }
    bump()
    return true
  end,
})

D:Register("rebel_sign", {
  allowed = function(_, _, op) return host(op.id) ~= nil end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    mo.sg = mo.sg or {}
    if mo.sg[author] and mo.sg[author] <= t then return false end
    mo.sg[author] = t
    bump()
    return true
  end,
})

-- A Mak'gora's duel, written by the loser's addon (as every duel is, Guild/Duels.lua): w won.
D:Register("mak_duel", {
  allowed = function(_, author, op) return host(op.id) ~= nil and party(op.w) and op.w ~= author end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    local cur = mo.duels[author]
    if cur and cur.t <= t then return false end
    mo.duels[author] = { w = op.w, t = t }
    bump()
    return true
  end,
})

-- The new Guild Master's addon: the hand-over happened (it stays done whatever the roster does later).
D:Register("lead_done", {
  allowed = function(_, author, op) return host(op.id) ~= nil and R:Rank(author) == 0 end,
  apply = function(g, author, op, t)
    local mo = motion(g, op.id)
    if mo.done and mo.done <= t then return false end
    mo.done, mo.da = t, author
    bump()
    return true
  end,
})

-- The winner known: handed over, kept by the Guild Master, or waiting for the hand-over (no time limit, decision 45;
-- unless the winner has left the guild).
local function handover(g, s)
  local mo, wkey = s.mo, P:Of(s.winner, g)
  if wkey == P:Of(mo.gm, g) then s.phase = "kept" return s end
  if (mo.done and P:Of(mo.da, g) == wkey) or leads(g, wkey) then s.phase = "handed" return s end
  s.phase = R:Ready() and not inGuild(g, wkey) and "kept" or "handover"
  return s
end

-- Votes in an impeachment: { yes, no, cands = { { name, n } } (most first) } from each voter's newest vote.
local function count(g, cur)
  local yes, no, by = 0, 0, {}
  for _, e in pairs(cur) do
    if e.on then
      yes = yes + 1
      local k = P:Of(e.c, g)
      by[k] = by[k] or { name = e.c, n = 0 }
      by[k].n = by[k].n + 1
    else
      no = no + 1
    end
  end
  local cands = {}
  for _, x in pairs(by) do cands[#cands + 1] = x end
  table.sort(cands, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return yes, no, cands
end

-- The impeachment: the officers' votes in the order they came, up to the moment it passed or failed.
local function impeach(g, s, now)
  local mo = s.mo
  local gk, voters, n = P:Of(mo.gm, g), {}, 0
  s.voters = {}
  for _, name in ipairs(mo.vt or {}) do
    local key = P:Of(name, g)
    if key ~= gk and not voters[key] then
      voters[key] = true
      n = n + 1
      s.voters[#s.voters + 1] = name
    end
  end
  s.n, s.need = n, math.floor(n / 2) + 1
  s.ve = mo.t + Co.IMPEACH_DAYS
  local stop = math.min(now, s.ve, mo.x or math.huge)
  local events = {}
  for name, list in pairs(mo.iv or {}) do
    local key = P:Of(name, g)
    if voters[key] then
      for _, x in ipairs(list) do
        if x.t >= mo.t and x.t <= stop then events[#events + 1] = { key = key, name = name, on = x.on, c = x.c, t = x.t } end
      end
    end
  end
  table.sort(events, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.name < b.name end)
  local cur, failed = {}, false
  for _, e in ipairs(events) do
    cur[e.key] = e
    local yes, no, cands = count(g, cur)
    if yes >= s.need and cands[1] and (not cands[2] or cands[2].n < cands[1].n) then
      s.winner, s.passedAt = cands[1].name, e.t
      break
    end
    if no > n - s.need then failed = true break end
  end
  s.yes, s.no, s.cands = count(g, cur)
  s.cast = s.yes + s.no
  local mine = cur[P:Of(ns.Self(), g)]
  if mine then s.mine, s.mineC = mine.on, mine.c end
  if s.winner then return handover(g, s) end
  if failed then s.phase = "failed"
  elseif mo.x and mo.x <= math.min(now, s.ve) then s.phase = "cancelled"
  elseif now > s.ve then s.phase = "failed"
  else s.phase = "vote" end
  return s
end

-- The Mak'gora's duel between the two, due from `from` for `fight` seconds: the earliest, written by its loser, in
-- time; none, and the challenger leads by walkover.
local function duel(g, s, now, from, fight)
  local mo = s.mo
  local ck, gk = P:Of(mo.a, g), P:Of(mo.gm, g)
  s.from, s.deadline = from, from + fight
  local best
  for name, d in pairs(mo.duels or {}) do
    local lk, wk = P:Of(name, g), P:Of(d.w, g)
    if ((lk == ck and wk == gk) or (lk == gk and wk == ck)) and d.t >= from and d.t <= s.deadline
      and (not best or d.t < best.t) then
      best = { w = d.w, t = d.t }
    end
  end
  if best then
    s.winner, s.fought = best.w, best.t
    if P:Of(best.w, g) == gk then s.lost = best.t end
    return handover(g, s)
  end
  if now < s.deadline then s.phase = "duel" return s end
  s.winner, s.walkover = mo.a, true
  return handover(g, s)
end

-- A Dictatorship's declined Mak'gora (SPEC decision 70): the challenger may declare a rebellion within REBEL_WAIT;
-- members sign it for REBEL_SIGN, one signature a player, the challenger's first. When a third of the members with
-- Guild Together (when declared) have signed, the Guild Master must fight within REBEL_FIGHT or the challenger leads.
-- Too few, or none declared: it failed, and the challenger waits as after a lost challenge.
local function rebellion(g, s, now)
  local mo = s.mo
  local ck, gk = P:Of(mo.a, g), P:Of(mo.gm, g)
  local open = s.vs + Co.REBEL_WAIT
  s.rebel = true
  local rb
  for name, x in pairs(mo.rbs or {}) do
    if P:Of(name, g) == ck and x.t >= s.vs and x.t <= open and (not rb or x.t < rb.t) then rb = x end
  end
  if not rb then
    if now < open then s.phase, s.deadline = "declined", open return s end
    s.phase, s.lost = "failed", open
    return s
  end
  s.rb, s.ve = rb.t, rb.t + Co.REBEL_SIGN
  s.need = math.max(1, math.ceil((tonumber(rb.m) or 1) / 3))
  local first = { [ck] = { name = mo.a, t = rb.t } }
  for name, t in pairs(mo.sg or {}) do
    local key = P:Of(name, g)
    if key ~= gk and t >= rb.t and t <= s.ve and (not first[key] or t < first[key].t) then first[key] = { name = name, t = t } end
  end
  local list = {}
  for _, x in pairs(first) do list[#list + 1] = x end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.name < b.name end)
  local me = P:Of(ns.Self(), g)
  s.signers = {}
  for _, x in ipairs(list) do
    if x.t <= now then
      s.signers[#s.signers + 1] = x.name
      if P:Of(x.name, g) == me then s.mine = true end
    end
  end
  s.signed = #s.signers
  local at = list[s.need] and list[s.need].t
  if at and at <= now then
    s.forced = true
    return duel(g, s, now, at, Co.REBEL_FIGHT)
  end
  if now < s.ve then s.phase, s.deadline = "rebellion", s.ve return s end
  s.phase, s.lost = "failed", s.ve
  return s
end

-- Mak'gora: the Guild Master's answer, the guild's vote when they decline (a rebellion in a Dictatorship), then the
-- duel.
local function makgora(g, s, now)
  local mo = s.mo
  local ck, gk = P:Of(mo.a, g), P:Of(mo.gm, g)
  s.challenger = mo.a
  local ok = mo.ok
  if ok and (ok.t > mo.t + Co.MAK_ACCEPT or P:Of(ok.a, g) ~= gk) then ok = nil end
  s.answer = ok and ok.on
  local from
  if ok and ok.on then
    from = ok.t
  else
    s.vs = ok and ok.t or mo.t + Co.MAK_ACCEPT
    if now < s.vs then s.phase, s.deadline = "challenge", mo.t + Co.MAK_ACCEPT return s end
    if mo.dict then return rebellion(g, s, now) end
    s.ve = s.vs + Co.MAK_VOTE
    local me = P:Of(ns.Self(), g)
    for key, x in pairs(latest(g, mo.votes, s.vs, s.ve)) do
      if key ~= ck and key ~= gk then
        if x.on then s.yes = s.yes + 1 else s.no = s.no + 1 end
        if key == me then s.mine = x.on end
      end
    end
    s.cast = s.yes + s.no
    if now < s.ve then s.phase = "vote" return s end
    if not (s.cast * 100 >= Co.MAK_QUORUM * mo.m and s.yes * 2 > s.cast) then
      s.phase, s.lost = "failed", s.ve
      return s
    end
    s.forced = true
    from = s.ve
  end
  return duel(g, s, now, from, Co.MAK_FIGHT)
end

-- The crown the Guild Master opened: the tournament, then the hand-over.
local function crown(g, s)
  local c = g.cups and g.cups[s.id]
  s.cup = c and c.h and c or nil
  if not s.cup or s.cup.st == "open" then s.phase = "signup" return s end
  if s.cup.st == "cancelled" then s.phase = "kept" return s end
  if s.cup.st == "running" then s.phase = "tourney" return s end
  s.winner = s.cup.places and s.cup.places[1] and s.cup.places[1][1]
  if not s.winner then s.phase = "kept" return s end
  return handover(g, s)
end

-- A motion as it stands. phase:
--   rule: "motion" (gathering seconds), "lapsed", "vote", "failed", "passed";
--   lead (impeachment): "vote", "failed", "cancelled", then "handover", "handed", "kept";
--   mak: "challenge" (waiting for the Guild Master), "vote" (declined: the guild votes), "failed", "duel", then
--     "handover", "handed", "kept" (the Guild Master won);
--   crown: "signup", "tourney", then "handover", "handed", "kept".
-- s = { id, mo, kind, phase, yes, no, cast, mine, winner, ... }: rule: seconds, need, vs, ve; lead: voters, n, need,
-- ve, cands, mineC; mak: challenger, answer, vs, ve, forced, deadline, walkover, lost; crown: cup.
-- (While Co.SetupVoted reads the passed changes of setup, a motion's own cancelling is not asked: it would ask them.)
local deciding = false
-- Did a change of setup come after the motion was made, before by (SPEC decision 70)?
local function cut(g, mo, by)
  if deciding then return false end
  local _, _, changed = ns.Rules.Setup(g)
  return changed ~= nil and changed > mo.t and changed < by
end

function Co.Motion(g, id, now)
  local mo = g.motions and g.motions[id]
  if not mo or not mo.kind then return nil end
  now = now or Co.Now()
  local s = { id = id, mo = mo, kind = mo.kind, yes = 0, no = 0, cast = 0, seconds = {}, need = mo.sec or 0 }
  if mo.kind == "lead" then return impeach(g, s, now) end
  if mo.kind == "mak" then return makgora(g, s, now) end
  if mo.kind == "crown" then return crown(g, s) end
  local filer, first = P:Of(mo.a, g), {}
  local deadline = mo.t + (mo.hrs or 48) * 3600
  -- Only the voters it names, when it names them (the council, the officers: SPEC decision 70).
  local only, m = nil, mo.m
  if mo.vt then
    only, m = {}, 0
    for _, name in ipairs(mo.vt) do
      local key = P:Of(name, g)
      if not only[key] then only[key] = true; m = m + 1 end
    end
  end
  for name, t in pairs(mo.sd or {}) do
    local key = P:Of(name, g)
    if key ~= filer and t <= deadline and (not only or only[key]) and (not first[key] or t < first[key].t) then
      first[key] = { name = name, t = t }
    end
  end
  local list = {}
  for _, x in pairs(first) do list[#list + 1] = x end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.name < b.name end)
  for i, x in ipairs(list) do s.seconds[i] = x.name end
  -- (The council or the officers may be fewer than the seconds asked for: then all of them but the one who made it.)
  local need = mo.sec
  if only then need = math.min(need, math.max(0, m - 1)) end
  s.need = need
  if #list < need then
    s.deadline = deadline
    if mo.veto and mo.veto <= math.min(now, deadline) then s.phase = "vetoed" return s end
    s.phase = now > deadline and "lapsed" or (cut(g, mo, math.huge) and "cancelled" or "motion")
    return s
  end
  s.vs = need > 0 and list[need].t or mo.t
  s.ve = s.vs + mo.days * 86400
  local me = P:Of(ns.Self(), g)
  for key, x in pairs(latest(g, mo.votes, s.vs, s.ve)) do
    if not only or only[key] then
      if x.on then s.yes = s.yes + 1 else s.no = s.no + 1 end
      if key == me then s.mine = x.on end
    end
  end
  s.cast = s.yes + s.no
  -- The Guild Master's veto (a Warcouncil), and a change of setup, end it before it is decided (SPEC decision 70).
  if mo.veto and mo.veto <= math.min(now, s.ve) then s.phase = "vetoed" return s end
  if cut(g, mo, now < s.ve and math.huge or s.ve) then s.phase = "cancelled" return s end
  if now < s.ve then s.phase = "vote" return s end
  local enough = s.cast * 100 >= mo.quo * m and s.cast > 0
  s.phase = enough and s.yes * 2 > s.cast and "passed" or "failed"
  return s
end

-- The newest passed change of setup after the Guild Master last set it (SPEC decision 70), for Guild/Rules.lua:
-- { setup, elect, sits, judge, t (when its vote ended), changed (when the setup last became another) } or nil. The
-- votes are read oldest first: one a change of setup came in the middle of was cancelled.
local voted = setmetatable({}, { __mode = "k" })
function Co.SetupVoted(g)
  g = g or D:Current()
  if not g or not g.motions then return nil end
  local now, gov = Co.Now(), g.settings and g.settings.gov or {}
  local c = voted[g]
  if c and c.ver == Co.ver and c.now == now and c.gov == gov then return c.best end
  local list = {}
  deciding = true
  for id, mo in pairs(g.motions) do
    if mo.kind == "setup" and mo.setup then
      local s = Co.Motion(g, id, now)
      if s and s.phase == "passed" and s.ve > (gov.at or 0) then list[#list + 1] = { id = id, mo = mo, t = s.ve } end
    end
  end
  deciding = false
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
  local best, cur, changed = nil, gov.setup, gov.t
  for _, x in ipairs(list) do
    if not (changed and changed > x.mo.t and changed < x.t) then
      if x.mo.setup ~= cur then changed, cur = x.t, x.mo.setup end
      best = { setup = x.mo.setup, elect = x.mo.elect, sits = x.mo.sits, judge = x.mo.judge, t = x.t }
    end
  end
  if best then best.changed = changed end
  voted[g] = { ver = Co.ver, now = now, gov = gov, best = best }
  return best
end

-- Motions, the newest first. kind "lead": every leadership motion (impeachment, Mak'gora and the crown); "rule": the
-- votes on the guild's rules, rule changes and changes of setup.
local VOTE = { rule = true, setup = true }
function Co.Motions(g, now, kind)
  local list = {}
  for id, mo in pairs(g and g.motions or {}) do
    local mk = mo.kind
    if mk and (not kind or (kind == "lead" and not VOTE[mk]) or (kind == "rule" and VOTE[mk]) or mk == kind) then
      list[#list + 1] = Co.Motion(g, id, now)
    end
  end
  table.sort(list, function(a, b) if a.mo.t ~= b.mo.t then return a.mo.t > b.mo.t end return a.id > b.id end)
  return list
end

-- A leadership motion still under way (an impeachment, a Mak'gora, the crown, or a hand-over waiting), else nil.
local DONE = { lapsed = true, failed = true, handed = true, kept = true, passed = true, cancelled = true, vetoed = true }
Co.DONE = DONE
function Co.Lead(g, now)
  for _, s in ipairs(Co.Motions(g, now, "lead")) do
    if not DONE[s.phase] and (not now or s.mo.t <= now) then return s end
  end
  return nil
end

-- A player's days with Guild Together in this guild (SPEC §7.5): from their first "player" op here (Guild/Players.lua).
-- Members of the guild's first day may challenge at once.
local function sinceOk(g, key, t)
  local since, first = P:Since(key, g), P:FirstDay(g)
  if not since then return false end
  return t - since >= Co.MAK_SINCE or (first ~= nil and since < first + 86400)
end

-- The last Mak'gora this player lost (or whose vote failed): when it ended.
local function lostAt(g, key, t)
  local last
  for id, mo in pairs(g.motions or {}) do
    if mo.kind == "mak" and mo.t <= t and P:Of(mo.a, g) == key then
      local s = Co.Motion(g, id, t)
      if s.lost and s.lost <= t and (not last or s.lost > last) then last = s.lost end
    end
  end
  return last
end

-- May author start a leadership motion of kind at time t (the laws read at that time)? Then why not, as a reason key.
function Co.MayStart(g, kind, author, t)
  t = t or Co.Now()
  local open = Co.Lead(g, t)
  if open then return false, "busy" end
  if kind == "lead" then
    for _, mo in pairs(g.motions or {}) do
      if mo.kind == "lead" and mo.t <= t and t - mo.t < Co.IMPEACH_GAP then return false, "week" end
    end
  elseif kind == "setup" then
    -- One change of setup at a time.
    for id, mo in pairs(g.motions or {}) do
      if mo.kind == "setup" and mo.t <= t then
        local s = Co.Motion(g, id, t)
        if s and (s.phase == "motion" or s.phase == "vote") then return false, "busy" end
      end
    end
  elseif kind == "mak" then
    local key = P:Of(author, g)
    if not sinceOk(g, key, t) then return false, "days" end
    local lost = lostAt(g, key, t)
    if lost and t - lost < Co.MAK_AGAIN then return false, "again" end
  end
  return true
end

-- The leadership motion whose winner waits for the hand-over while name holds the Guild Master's rank and is not that
-- winner, or nil. Until the winner leads, such a Guild Master cannot give out, start or change anything in Guild
-- Together (D:InCharge, SPEC §7.5, decisions 45 and 46).
function Co.Ousted(g, name, now)
  name = name or ns.Self()
  now = now or Co.Now()
  local key = P:Of(name, g)
  -- (Asked on every check of the Guild Master's rights: only motions that can have a winner are read.)
  for id, mo in pairs(g.motions or {}) do
    local maybe = mo.kind and not mo.done and not VOTE[mo.kind]
    if maybe and mo.kind == "crown" then maybe = g.cups and g.cups[id] and g.cups[id].places ~= nil end
    if maybe and mo.kind == "lead" then maybe = next(mo.iv or {}) ~= nil end
    if maybe and mo.kind == "mak" then maybe = mo.ok ~= nil or now >= mo.t + Co.MAK_ACCEPT end
    if maybe then
      local s = Co.Motion(g, id, now)
      if s.phase == "handover" and P:Of(s.winner, g) ~= key then return s end
    end
  end
  -- The Guild Master's election (SPEC decision 70), this month's or last month's.
  if g.elections and Co.Elects and Co.Elects(g) then
    for _, s in ipairs(Co.Elections(g, now)) do
      if s.phase == "handover" and P:Of(s.winner, g) ~= key then return s end
    end
  end
  return nil
end

-- A Mak'gora's duel, for Guild/Duels.lua: { mak = id } when a and b are its challenger and Guild Master and the duel
-- is due.
function Co.MatchWith(g, a, b)
  local ka, kb = P:Of(a, g), P:Of(b, g)
  for id, mo in pairs(g and g.motions or {}) do
    if mo.kind == "mak" then
      local ck, gk = P:Of(mo.a, g), P:Of(mo.gm, g)
      if (ka == ck and kb == gk) or (ka == gk and kb == ck) then
        local s = Co.Motion(g, id)
        if s.phase == "duel" then return { mak = id } end
      end
    end
  end
  return nil
end

-- Protection (SPEC §7.5): a challenger cannot get strikes during their Mak'gora.
function Co.Protected(g, name)
  local key = P:Of(name, g)
  for id, mo in pairs(g and g.motions or {}) do
    if mo.kind == "mak" and P:Of(mo.a, g) == key then
      local s = Co.Motion(g, id)
      if not DONE[s.phase] and s.phase ~= "handover" then return true end
    end
  end
  return false
end

-- The rules the guild changed by vote: { [rule] = { v, t (when the vote ended), id } }, the newest vote per rule.
local cache = setmetatable({}, { __mode = "k" })
function Co.Rules(g, now)
  now = now or Co.Now()
  local c = cache[g]
  if c and c.ver == Co.ver and c.now == now then return c.rules end
  local rules = {}
  for id, mo in pairs(g.motions or {}) do
    if mo.kind == "rule" then
      local s = Co.Motion(g, id, now)
      if s and s.phase == "passed" then
        local cur = rules[mo.r]
        if not cur or s.ve > cur.t or (s.ve == cur.t and id > cur.id) then rules[mo.r] = { v = mo.v, t = s.ve, id = id } end
      end
    end
  end
  cache[g] = { ver = Co.ver, now = now, rules = rules }
  return rules
end

D.Rule = function(g, key)
  local x = Co.Rules(g)[key]
  if not x then return nil end
  if Co.RULES[key] == "ranks" then
    local set = {}
    for _, i in ipairs(x.v) do set[i] = true end
    return set
  end
  return x.v
end

-- A rule's value as a vote would set it, from the value in force: a list of ranks, a number, or true / false.
function Co.Current(g, r)
  local kind = Co.RULES[r]
  if kind == "ranks" then
    local list = {}
    for i in pairs(D:Ranks(r, g)) do list[#list + 1] = i end
    table.sort(list)
    return list
  elseif kind == "number" then
    return D:Number(r, g)
  end
  if r == "ptax" then return ns.Rules.Pun(g).tax == true end
  if r == "pcourt" then return ns.Rules.Court(g) end
  if r == "ptrial" then return ns.Rules.Trial(g) end
  return D:CourtSentences(g)
end

-- The players who have voted on a rule or setup change, in its window: { [player key] = true }.
function Co.VotedKeys(g, s)
  local out = {}
  if not s or not s.vs then return out end
  for key in pairs(latest(g, s.mo.votes, s.vs, s.ve)) do out[key] = true end
  return out
end

-- Who votes on a motion that names them (the council, the officers): may name vote on it?
function Co.Votes(g, mo, name)
  if not mo.vt then return true end
  local key = P:Of(name or ns.Self(), g)
  for _, n in ipairs(mo.vt) do if P:Of(n, g) == key then return true end end
  return false
end

---------------------------------------------------------------------------
-- The Guild Master's election (SPEC decision 70): in a Democracy that elects its Guild Master, every month (UTC).
-- Members stand on the 1st to the 4th (the Guild Master stands without asking), and every member votes on the 5th
-- to the 7th. The winner leads after the hand-over, as after an impeachment; a Guild Master who wins stays.
---------------------------------------------------------------------------
local function soundMonth(m) return type(m) == "string" and m:match("^%d%d%d%d%-%d%d$") ~= nil end

-- Does the guild elect its Guild Master now?
function Co.Elects(g)
  local setup, opt = ns.Rules.Setup(g)
  return setup == "democracy" and opt.elect == true
end

-- 00:00 UTC on day d of month m.
local function utc(m, d)
  local y, mo = m:match("^(%d+)%-(%d+)$")
  local t = time({ year = tonumber(y), month = tonumber(mo), day = d, hour = 0 })
  local u, l = date("!*t", t), date("*t", t)
  u.isdst, l.isdst = nil, nil
  return t + (time(l) - time(u))
end
Co.UTC = utc

local function election(g, m)
  local all = D.Part(g, "elections")
  all[m] = all[m] or { run = {}, v = {} }
  return all[m]
end

-- Who the election is about: the Guild Master when its first op arrived.
local function sitting(e) if not e.gm then e.gm = Co.GM() end end

-- May name stand: the Guild Master, or a member of a rank someone may name as Guild Master?
local function mayStand(name)
  local rank = R:Rank(name)
  return rank ~= nil and (rank == 0 or rank ~= lowest())
end
Co.MayStand = mayStand

D:Register("elect_run", {
  allowed = function(g, author, op)
    return soundMonth(op.m) and Clean(op.line, Co.CAMPAIGN_MAX) ~= nil and Co.Elects(g) and mayStand(author)
  end,
  apply = function(g, author, op, t)
    if month(t) ~= op.m or day(t) > Co.STAND_DAYS then return false end
    local e = election(g, op.m)
    local cur = e.run[author]
    if cur and cur.t > t then return false end
    sitting(e)
    e.run[author] = { line = Clean(op.line, Co.CAMPAIGN_MAX), t = t }
    bump()
    return true
  end,
})

D:Register("elect_vote", {
  allowed = function(g, author, op)
    return soundMonth(op.m) and party(op.on) and (op.who == nil or (party(op.who) and op.who ~= author)) and Co.Elects(g)
  end,
  apply = function(g, author, op, t)
    local e = election(g, op.m)
    if not newest(e.v, op.who or author, op.on, t) then return false end
    sitting(e)
    bump()
    return true
  end,
})

D:Register("elect_done", {
  allowed = function(_, author, op) return soundMonth(op.m) and R:Rank(author) == 0 end,
  apply = function(g, author, op, t)
    local e = election(g, op.m)
    if e.done and e.done <= t then return false end
    e.done, e.da = t, author
    bump()
    return true
  end,
})

-- Month m's election: { m, gm, cands = { { name, line, t, n, sitting } } (most votes first; a tie goes to the Guild
-- Master, then to who stood first), mine, winner, phase }. phase: "stand", "vote", then "kept" (the Guild Master
-- stays), "handover" (the winner waits for it), "handed", or "gone" (the winner left the guild); "off" when the guild
-- does not elect, or changed its setup since the month began.
function Co.Election(g, m, now)
  now = now or Co.Now()
  local e = g and g.elections and g.elections[m] or { run = {}, v = {} }
  local s = { m = m, cands = {}, e = e }
  local gm = e.gm or Co.GM()
  s.gm = gm
  local by = {}
  if gm then by[P:Of(gm, g)] = { name = gm, line = L.CO_ELECT_SITTING, t = 0, n = 0, sitting = true } end
  for name, x in pairs(e.run or {}) do
    if month(x.t) == m and day(x.t) <= Co.STAND_DAYS then
      local key = P:Of(name, g)
      local c = by[key]
      if c and c.sitting then
        c.line = x.line
      elseif not c or x.t < c.t then
        by[key] = { name = name, line = x.line, t = x.t, n = 0 }
      end
    end
  end
  local me = P:Of(ns.Self(), g)
  for key, x in pairs(latest(g, e.v, utc(m, Co.STAND_DAYS + 1), utc(m, Co.VOTE_DAYS + 1) - 1)) do
    local c = by[P:Of(x.on, g)]
    if c then
      c.n = c.n + 1
      if key == me then s.mine = c.name end
    end
  end
  for _, c in pairs(by) do s.cands[#s.cands + 1] = c end
  table.sort(s.cands, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.t ~= b.t then return a.t < b.t end
    return a.name < b.name
  end)
  if not g or not Co.Elects(g) or ns.Rules.Cancelled(g, utc(m, 1)) then s.phase = "off" return s end
  local nm, nd = month(now), day(now)
  if nm < m or (nm == m and nd <= Co.STAND_DAYS) then s.phase = "stand" return s end
  if nm == m and nd <= Co.VOTE_DAYS then s.phase = "vote" return s end
  local w = s.cands[1]
  if not w or w.sitting or w.n == 0 then
    s.phase, s.winner = "kept", gm
    return s
  end
  s.winner = w.name
  local wkey = P:Of(w.name, g)
  if (e.done and P:Of(e.da, g) == wkey) or leads(g, wkey) then s.phase = "handed" return s end
  s.phase = R:Ready() and not inGuild(g, wkey) and "gone" or "handover"
  return s
end

-- This month's and last month's elections (a winner may still wait for the hand-over from last month).
function Co.Elections(g, now)
  now = now or Co.Now()
  return { Co.Election(g, month(now), now), Co.Election(g, lastMonth(now), now) }
end

---------------------------------------------------------------------------
-- A whole copy
---------------------------------------------------------------------------
local function mergeVotes(mine, theirs)
  for name, x in pairs(type(theirs) == "table" and theirs or {}) do
    if party(name) and type(x) == "table" and tonumber(x.t) and x.on ~= nil then newest(mine, name, x.on, x.t) end
  end
end

local function mergeTimes(mine, theirs)
  for name, t in pairs(type(theirs) == "table" and theirs or {}) do
    if party(name) and tonumber(t) and (not mine[name] or t < mine[name]) then mine[name] = t end
  end
end

function Co.Merge(g, part)
  if type(part) ~= "table" then return end
  local c = part.charter
  if type(c) == "table" and party(c.a) and tonumber(c.t) and whole(c.v, 1, 100000) and soundLines(c.lines)
    and R:Rank(c.a) == 0 then
    takeCharter(g, c.a, c, c.t)
  end
  if type(part.ok) == "table" then
    local ok = D.Part(g, "charterOk")
    for name, v in pairs(part.ok) do
      if party(name) and whole(v, 1, 100000) and (ok[name] or 0) < v then ok[name] = v end
    end
  end
  for id, e in pairs(type(part.polls) == "table" and part.polls or {}) do
    if type(id) == "string" and host(id) and type(e) == "table" then
      local all = D.Part(g, "polls")
      all[id] = all[id] or { v = {} }
      local po = all[id]
      if not po.h and party(e.h) and tonumber(e.t) and soundPoll({ q = e.q, days = e.days, ch = e.ch }) then
        takePoll(po, e.h, { q = e.q, days = e.days, ch = e.ch, sec = e.sec, wt = e.wt }, e.t)
      end
      po.v = po.v or {}
      mergeVotes(po.v, e.v)
    end
  end
  for id, e in pairs(type(part.strikes) == "table" and part.strikes or {}) do
    if type(id) == "string" and host(id) and type(e) == "table" then
      local all = D.Part(g, "strikes")
      all[id] = all[id] or { ok = {} }
      local s = all[id]
      if not s.by and party(e.by) and tonumber(e.t) and soundStrike(e) then
        s.by, s.to, s.why, s.days, s.t = e.by, e.to, Clean(e.why, Co.WHY_MAX), tonumber(e.days), e.t
      end
      s.ok = s.ok or {}
      mergeTimes(s.ok, e.ok)
      if tonumber(e.x) and (not s.x or e.x < s.x) then s.x = e.x end
    end
  end
  for id, e in pairs(type(part.motions) == "table" and part.motions or {}) do
    if type(id) == "string" and host(id) and type(e) == "table" then
      local mo = motion(g, id)
      if not mo.kind and party(e.a) and tonumber(e.t) and soundMotion(e) then takeMotion(mo, e.a, e, e.t) end
      mergeTimes(mo.sd, e.sd)
      mergeVotes(mo.votes, e.votes)
      for name, list in pairs(type(e.iv) == "table" and e.iv or {}) do
        for _, x in ipairs(party(name) and type(list) == "table" and list or {}) do
          if type(x) == "table" and tonumber(x.t) and type(x.on) == "boolean" and (not x.on or party(x.c)) then
            addVote(mo, name, x.on, x.on and x.c or nil, x.t)
          end
        end
      end
      for name, d in pairs(type(e.duels) == "table" and e.duels or {}) do
        if party(name) and type(d) == "table" and party(d.w) and tonumber(d.t)
          and (not mo.duels[name] or d.t < mo.duels[name].t) then
          mo.duels[name] = { w = d.w, t = d.t }
        end
      end
      if tonumber(e.x) and (not mo.x or e.x < mo.x) then mo.x = e.x end
      if e.dict == true and mo.kind == "mak" then mo.dict = true end
      mo.sg = mo.sg or {}
      mergeTimes(mo.sg, e.sg)
      for name, x in pairs(type(e.rbs) == "table" and e.rbs or {}) do
        if party(name) and type(x) == "table" and tonumber(x.t) and whole(x.m, 1, 10000) then
          mo.rbs = mo.rbs or {}
          if not mo.rbs[name] or x.t < mo.rbs[name].t then mo.rbs[name] = { t = x.t, m = x.m } end
        end
      end
      local ok = e.ok
      if type(ok) == "table" and type(ok.on) == "boolean" and party(ok.a) and tonumber(ok.t) and (not mo.ok or ok.t < mo.ok.t) then
        mo.ok = { on = ok.on, a = ok.a, t = ok.t }
      end
      if tonumber(e.done) and party(e.da) and (not mo.done or e.done < mo.done) then mo.done, mo.da = e.done, e.da end
      local say = e.say
      if type(say) == "table" and tonumber(say.t) and Clean(say.text, Co.SAY_MAX) and (not mo.say or say.t > mo.say.t) then
        mo.say = { text = Clean(say.text, Co.SAY_MAX), a = say.a, t = say.t }
      end
    end
  end
  for m, e in pairs(type(part.elections) == "table" and part.elections or {}) do
    if soundMonth(m) and type(e) == "table" then
      local mine = election(g, m)
      for name, x in pairs(type(e.run) == "table" and e.run or {}) do
        if party(name) and type(x) == "table" and tonumber(x.t) and Clean(x.line, Co.CAMPAIGN_MAX)
          and (not mine.run[name] or x.t > mine.run[name].t) then
          mine.run[name] = { line = Clean(x.line, Co.CAMPAIGN_MAX), t = x.t }
        end
      end
      mergeVotes(mine.v, e.v)
      -- (Two copies that saw another Guild Master first agree on the one whose name sorts first.)
      if party(e.gm) and (not mine.gm or e.gm < mine.gm) then mine.gm = e.gm end
      if tonumber(e.done) and party(e.da) and (not mine.done or e.done < mine.done) then mine.done, mine.da = e.done, e.da end
    end
  end
  bump()
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function sync(op) return ns.Sync:Do(op) end

function Co.WriteCharter(lines)
  local g = D:Current()
  local v = ((g and g.charter and g.charter.v) or 0) + 1
  return sync({ k = "charter", v = v, lines = lines })
end

function Co.Accept()
  local g = D:Current()
  return g and g.charter and sync({ k = "charter_ok", v = g.charter.v }) or false
end

function Co.OpenPoll(q, ch, secret, weighted, days)
  return sync({ k = "poll", q = q, ch = ch, sec = secret and true or nil, wt = weighted and true or nil, days = days })
end

function Co.Vote(id, on, who) return sync({ k = "poll_vote", id = id, on = on, who = who }) end

function Co.Strike(to, why, days) return sync({ k = "strike", to = to, why = why, days = days or Co.STRIKE_DAYS }) end
function Co.Confirm(id) return sync({ k = "strike_ok", id = id }) end

-- The numbers in force travel with the motion, so a change made during it applies to the next one.
local function numbers(op)
  for _, k in ipairs(RULE_NUMBERS) do op[k] = D:Number(k) end
  op.m = math.max(1, Co.Members(D:Current()))
  return op
end

-- A leadership motion starts only when the laws allow it now (the ops' own check reads them at the op's time).
local function start(op)
  local g = D:Current()
  if not g or not Co.MayStart(g, op.kind, ns.Self()) then return false end
  return sync(op)
end

-- Impeachment: an officer starts it; the officers who can vote are fixed now.
function Co.Impeach(why)
  local g = D:Current()
  local voters = {}
  for _, name in ipairs(g and Co.Officers(g) or {}) do voters[#voters + 1] = name end
  if #voters == 0 then return false end
  return start({ k = "motion", kind = "lead", why = why, gm = Co.GM(), vt = voters })
end
function Co.ImpVote(id, on, c) return sync({ k = "imp_vote", id = id, on = on and true or false, c = on and c or nil }) end
function Co.Cancel(id) return sync({ k = "motion_cancel", id = id }) end

-- Mak'gora: a member challenges the Guild Master; the Guild Master answers.
function Co.Challenge(why)
  local m = math.max(1, Co.Members(D:Current()) - 2)
  return start({ k = "motion", kind = "mak", why = why, gm = Co.GM(), m = m })
end
function Co.Answer(id, on) return sync({ k = "mak_ok", id = id, on = on and true or false }) end

function Co.Propose(r, v, why) return sync(numbers({ k = "motion", kind = "rule", r = r, v = v, why = why, vt = ns.Rules.Voters(D:Current()) })) end
-- A change of setup put to the vote (SPEC decision 70): opt = { elect, sits, judge }.
function Co.ProposeSetup(setup, opt, why)
  opt = opt or {}
  return start(numbers({ k = "motion", kind = "setup", setup = setup, elect = opt.elect, sits = opt.sits,
    judge = opt.judge, why = why, vt = ns.Rules.Voters(D:Current()) }))
end
-- The Guild Master's veto on a vote in a Warcouncil (never an impeachment or a Mak'gora).
function Co.Veto(id) return sync({ k = "motion_veto", id = id }) end
function Co.OpenCrown() return start({ k = "motion", kind = "crown" }) end
function Co.Second(id) return sync({ k = "motion_sec", id = id }) end
function Co.VoteMotion(id, on, who) return sync({ k = "motion_vote", id = id, on = on and true or false, who = who }) end
function Co.Say(id, text) return sync({ k = "motion_say", id = id, text = text }) end

-- The Guild Master's election: stand with a line, vote (who: a member without the addon who whispered).
function Co.Stand(line) return sync({ k = "elect_run", m = month(Co.Now()), line = line }) end
function Co.VoteElect(on, who) return sync({ k = "elect_vote", m = month(Co.Now()), on = on, who = who }) end
-- A rebellion: declared by a declined Mak'gora's challenger (with the members who have Guild Together now), and signed.
function Co.Rebel(id)
  local n = 0
  local seen = {}
  for name in pairs(roster()) do
    local key = P:Of(name, D:Current())
    if not seen[key] and P:HasAddon(key) then seen[key] = true; n = n + 1 end
  end
  return sync({ k = "rebel", id = id, m = math.max(1, n) })
end
function Co.Sign(id) return sync({ k = "rebel_sign", id = id }) end
-- A strike taken back by the Guild Master (a Monarchy).
function Co.TakeBack(id) return sync({ k = "strike_x", id = id }) end

-- The crown tournament's sign-up, run by the motion's filer (or the Guild Master who opened the crown): single
-- elimination, best of 3 by default (mockup); the Guild Master is entered as the defending champion.
function Co.OpenCup(id, fmt, bo)
  local g = D:Current()
  local s = g and Co.Motion(g, id)
  if not s or s.phase ~= "signup" or s.cup or host(id) ~= ns.Self() then return false end
  if not sync({ k = "lead_cup", id = id, fmt = fmt or "single", bo = bo or 3 }) then return false end
  local gm = s.mo.gm
  if gm and roster()[gm] ~= nil then ns.Cup.Join(id, true, gm ~= ns.Self() and gm or nil) end
  return true
end

---------------------------------------------------------------------------
-- What the filer's addon does by itself: opens the sign-up when the vote passed, closes it after 3 days, and ends
-- the tournament when it is decided. The new Guild Master's addon tells the guild.
---------------------------------------------------------------------------
function Co:Tick(now)
  local g = D:Current()
  if not g or not ns.Sync then return end
  now = now or Co.Now()
  local me = ns.Self()
  for _, s in ipairs(Co.Motions(g, now, "lead")) do
    if host(s.id) == me then
      if s.phase == "signup" and not s.cup then
        Co.OpenCup(s.id)
      elseif s.phase == "signup" and s.cup and now >= s.cup.t + Co.SIGNUP then
        local joined = ns.Cup.Joined(s.cup)
        if #joined >= 2 then ns.Cup.Go(s.id)
        elseif #joined == 1 then sync({ k = "cup_end", id = s.id, places = { { joined[1] } } })
        else ns.Cup.Cancel(s.id) end
      elseif s.phase == "tourney" then
        ns.Cup.Finish(s.id)
      end
    end
    if s.phase == "handed" and s.winner and P:IsMe(P:Of(s.winner, g), g) then
      -- The new Guild Master's addon writes it down, so it stays done whatever the roster does later.
      if not s.mo.done and R:Rank(me) == 0 then sync({ k = "lead_done", id = s.id }) end
      ns.db.handed = ns.db.handed or {}
      if not ns.db.handed[s.id] then
        ns.db.handed[s.id] = true
        ns:Fire("NEW_GM", s.winner)
      end
    end
    Co:Watch(g, s)
  end
  Co:Moments(g, now)
  -- The election's winner's addon writes the hand-over down, as for a motion.
  if g.elections and Co.Elects(g) then
    for _, s in ipairs(Co.Elections(g, now)) do
      if s.phase == "handed" and s.winner and P:IsMe(P:Of(s.winner, g), g) then
        if not s.e.done and R:Rank(me) == 0 then sync({ k = "elect_done", m = s.m }) end
        ns.db.handed = ns.db.handed or {}
        if not ns.db.handed["elect:" .. s.m] then
          ns.db.handed["elect:" .. s.m] = true
          ns:Fire("NEW_GM", s.winner)
        end
      end
    end
  end
end

-- Moments (the 1 Nov review): a new setup (picked, changed, or voted in) and a rule the guild changed by vote play on
-- every member's alert line once; the Guild Master's addon says them in guild chat (Guild/Announce.lua). What was so
-- when this client first looked at the guild is not news. Kept per guild in GuildTogetherForeverDB.seen.
local function setupSig(g)
  local id, opt = ns.Rules.Setup(g)
  return tostring(id) .. ":" .. tostring(opt.elect == true) .. ":" .. tostring(opt.sits) .. ":" .. tostring(opt.judge), id
end

function Co:Moments(g, now)
  if not g or not g.id or not ns.db then return end
  now = now or Co.Now()
  ns.db.seen = type(ns.db.seen) == "table" and ns.db.seen or {}
  local seen = ns.db.seen[g.id]
  local first = type(seen) ~= "table"
  if first then
    seen = { rules = {} }
    ns.db.seen[g.id] = seen
  end
  seen.rules = type(seen.rules) == "table" and seen.rules or {}
  local sig, id = setupSig(g)
  if seen.setup ~= sig then
    local known = seen.setup ~= nil
    seen.setup = sig
    if known and id then ns:Fire("SETUP_CHANGED", g, id) end
  end
  for _, s in ipairs(Co.Motions(g, now, "rule")) do
    if s.kind == "rule" and s.phase == "passed" and not seen.rules[s.id] then
      seen.rules[s.id] = true
      if not first and now - (s.ve or 0) < Co.WEEK then ns:Fire("RULE_CHANGED", g, s) end
    end
  end
end

-- What every member is told (SPEC §7.5, once each, on this screen): the Guild Master online for an hour without
-- handing over; an officer who votes in an impeachment demoted during the vote; a challenger removed from the guild
-- during their Mak'gora. (Not in the pretend guild's saved list: it is wiped with it.)
function Co:Watch(g, s)
  ns.db.told = type(ns.db.told) == "table" and ns.db.told or {}
  local told = ns.db.told
  local function tell(key, what, ...)
    if told[key] then return end
    told[key] = true
    ns:Fire("LEAD_WARNING", what, ...)
  end
  if s.phase == "handover" then
    local gm = Co.GM()
    if gm and R:Online(gm) then
      self.seen = self.seen or {}
      self.seen[s.id] = self.seen[s.id] or GetTime()
      if GetTime() - self.seen[s.id] >= Co.SEEN_GM then tell(s.id .. ":gm", "gm", gm, s.winner) end
    end
  elseif s.phase == "vote" and s.kind == "lead" and R:Ready() then
    for _, name in ipairs(s.voters or {}) do
      local rank = R:Rank(name)
      if rank ~= nil and rank ~= 0 and not D:Ranks("impeach", g)[rank] then tell(s.id .. ":" .. name, "demoted", name) end
    end
  elseif s.kind == "mak" and not DONE[s.phase] and R:Ready() and not inGuild(g, P:Of(s.challenger, g)) then
    tell(s.id .. ":removed", "removed", s.challenger)
  end
end

---------------------------------------------------------------------------
-- !vote by whisper, for members without the addon (SPEC §7.2): a number for the newest open poll, yes or no for an
-- open motion (else the newest yes-or-no poll), a name in the Guild Master election. The answer goes back by whisper.
---------------------------------------------------------------------------
function Co.Whispered(msg, sender, now)
  local g = D:Current()
  if not g or type(msg) ~= "string" or type(sender) ~= "string" then return nil end
  local arg = msg:lower():match("^%s*!vote%s+(.-)%s*$")
  if not arg or arg == "" then return nil end
  sender = ns.FullName(sender)
  if roster()[sender] == nil then return nil end
  now = now or Co.Now()
  local n = tonumber(arg)
  if arg == "yes" or arg == "no" then
    for _, s in ipairs(Co.Motions(g, now)) do
      if s.phase == "vote" and s.kind ~= "lead" then
        Co.VoteMotion(s.id, arg == "yes", sender)
        return L.CO_WHISPER_TAKEN:format(L["CO_" .. arg:upper()])
      end
    end
    n = arg == "yes" and 1 or 2
    for _, s in ipairs(Co.Polls(g, now)) do
      if s.open and not s.po.ch then
        Co.Vote(s.id, n, sender)
        return L.CO_WHISPER_TAKEN:format(s.rows[n].label)
      end
    end
    return L.CO_WHISPER_NONE
  end
  if n then
    for _, s in ipairs(Co.Polls(g, now)) do
      if s.open then
        if not s.rows[n] then return L.CO_WHISPER_BAD:format(#s.rows) end
        Co.Vote(s.id, n, sender)
        return L.CO_WHISPER_TAKEN:format(s.rows[n].label)
      end
    end
    return L.CO_WHISPER_NONE
  end
  local e = Co.Election(g, month(now), now)
  if e.phase == "vote" then
    for _, c in ipairs(e.cands) do
      if Ambiguate(c.name, "short"):lower() == arg or c.name:lower() == arg then
        Co.VoteElect(c.name, sender)
        return L.CO_WHISPER_TAKEN:format(ns.Display(c.name))
      end
    end
  end
  return L.CO_WHISPER_NONE
end

ns:RegisterEvent("CHAT_MSG_WHISPER", function(_, msg, sender)
  local answer = Co.Whispered(msg, sender)
  if answer and ns.Announce then ns.Announce:Whisper(answer, ns.FullName(sender)) end
end)

ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Co.TICK, function() Co:Tick() end) end
end)
