-- The guild's shared data (docs/ARCHITECTURE.md §1): the Guild Master's settings (SPEC §3) and, from later
-- milestones, one part per page. Only the logged-in character's guild is used (SPEC §2).
-- Every change is an op of some kind (Guild/Sync.lua). A kind says who may make it, how it changes the data, and how
-- to merge a whole copy (when the op log of the copy's sender no longer reaches back far enough).
local _, ns = ...
local L = ns.L
local D = { kinds = {} }
ns.GuildData = D

-- The places the Guild Master can switch on and off (SPEC §2, decision 48). Home, the Council (impeachment is always
-- there) and Manage stay.
D.PLACES = { "challenges", "games", "gambling", "treasury", "professions", "punishments" }
local isPlace = {}
for _, p in ipairs(D.PLACES) do isPlace[p] = true end
-- And one by one (SPEC decision 52): a feature ("<page>:<feature>", never Leadership), a punishment ("p:<id>") or a
-- guild game ("g:<kind>"). These start switched off; the Guild Master turns them on.
D.OFF_FIRST = { ["p:radio"] = true, ["p:servant"] = true }
D.OFF_MAX = 80
local function offFirst()
  local t = {}
  for k, v in pairs(D.OFF_FIRST) do t[k] = v end
  return t
end

-- What the Guild Master can allow per rank (SPEC §3.2, decision 50), by place: each punishment (SPEC §6) has its
-- own. The settings and the tax are the Guild Master's alone (D:InCharge), with no power to give.
D.PUNISHMENTS = { "stocks", "dunce", "wheel", "service", "walk", "curse", "radio", "servant", "idol", "trial" }
D.POWERS = {
  { place = "challenges", "tourney" },
  { place = "games", "games" },
  { place = "punishments" },
  { place = "treasury", "items", "grant" },
  { place = "council", "poll", "motion", "impeach", "sees", "strike", "confirm", "court" },
  { place = "home", "deeds", "herald" },
  { place = "calendar", "cal" },
}
for _, a in ipairs(D.PUNISHMENTS) do table.insert(D.POWERS[3], a) end
table.insert(D.POWERS[3], "spin")
table.insert(D.POWERS[3], "pardon")
D.ACTIONS = {}
for _, grp in ipairs(D.POWERS) do
  for _, a in ipairs(grp) do D.ACTIONS[#D.ACTIONS + 1] = a end
end
local isAction, isPun = {}, {}
for _, a in ipairs(D.ACTIONS) do isAction[a] = true end
for _, p in ipairs(D.PUNISHMENTS) do isPun[p] = true end

D.NAME_MAX = 16  -- letters in each name of the Marks
D.RANK_MAX = 9   -- the game has up to 10 ranks: 0 (the Guild Master) to 9

-- Powers that are not the Guild Master's alone by default (SPEC §3.2, decision 50): every rank may open polls and see
-- strikes; every rank but the lowest may file a motion (SPEC §7.2); the officer ranks run tournaments, games and
-- raffles, item requests and the Wheel, impeach (§7.5), and add calendar events (decision 61).
D.OPEN = { poll = "all", sees = "all", motion = "notLowest", impeach = "officers", tourney = "officers",
  games = "officers", items = "officers", spin = "officers", cal = "officers" }
D.RANK_NAMES = 20  -- rank names kept per power (the game has 9 below the Guild Master; old names linger)

-- The Council's numbers (SPEC §7.2, §7.3): seconds a motion needs, within hours; days of voting; percent of members
-- who must vote; percent of the jury for guilty. { default, lowest, highest }.
D.NUMBERS = {
  sec = { 3, 1, 10 }, hrs = { 48, 12, 168 }, days = { 3, 1, 7 }, quo = { 40, 0, 100 },
  jury = { 65, 51, 100 },
}
D.NUMBER_KEYS = { "sec", "hrs", "days", "quo", "jury" }
D.LADDER_MAX = 80

-- The guild tax (SPEC §8, decided 29 Oct 2026: set by the Guild Master): gold per rank, each week or month, from a
-- level up, with members let off by name.
D.TAX_MAX, D.LEVEL_MAX, D.EXEMPT_MAX = 10000, 80, 100

-- The Chronicle (SPEC §8): the guild mascot's kinds, and the Herald who posts to Discord (SPEC §9.2: a character of a
-- rank that may be Herald; none chosen, or not allowed: the Guild Master).
D.MASCOTS = { "boar", "murloc", "turtle", "wolf", "owl", "raptor" }
D.MASCOT_NAME_MAX = 24
local isMascot = {}
for _, k in ipairs(D.MASCOTS) do isMascot[k] = true end

-- The guild's look (SPEC decision 68): what the Guild Master may pick, and the motto's letters. (UI/Widgets.lua has
-- the colours.)
D.THEME = { accent = { "gold", "silver", "bronze", "crimson", "emerald", "azure", "violet" },
  leather = { "brown", "black", "red" }, shade = { "dark", "darker", "black" }, crest = { "shield", "tabard" } }
D.MOTTO_MAX = 40
local isTheme = {}
for k, list in pairs(D.THEME) do
  isTheme[k] = {}
  for _, v in ipairs(list) do isTheme[k][v] = true end
end

function D.Defaults()
  local cn = {}
  for k, x in pairs(D.NUMBERS) do cn[k] = x[1] end
  return { purse = "gold", one = L.MARK_ONE, many = L.MARK_MANY, off = offFirst(), perms = {}, officers = nil, known = nil,
    court = false, hush = false, season = "month",
    cn = cn, ladder = L.CO_LADDER_DEFAULT, tax = { on = false, per = "month", amt = {}, lv = 1, ex = {} },
    mascot = { name = L.CH_MASCOT_DEFAULT, kind = "boar" }, herald = nil,
    theme = { accent = "gold", leather = "brown", shade = "dark", crest = "shield" },
    -- (Incidents judged directly until the guild picks a setup that sends them to the court: SPEC decision 70.)
    pun = { tax = true, incidents = "direct", trial = true, closed = {} },
    gov = {} }
end

-- A name for the Marks: no chat escapes or control letters, at most NAME_MAX letters (UTF-8), trimmed. Nil if empty.
function D.CleanName(s)
  if type(s) ~= "string" then return nil end
  s = strtrim((s:gsub("[%z\1-\31|]", "")))
  local out, n = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    if n > D.NAME_MAX then break end
    out[#out + 1] = ch
  end
  s = strtrim(table.concat(out))
  return s ~= "" and s or nil
end

local function rankName(k) return type(k) == "string" and k ~= "" and #k <= 64 and not k:find("[|%c]") end

-- { [rank name] = true } (or true / false, when both) from anywhere, at most D.RANK_NAMES; nil when not a table.
local function names(t, both)
  if type(t) ~= "table" then return nil end
  local out, n = {}, 0
  for k, v in pairs(t) do
    if rankName(k) and (v == true or (both and v == false)) and n < D.RANK_NAMES then
      out[k] = v
      n = n + 1
    end
  end
  return out
end

-- A clean copy of settings from anywhere (saved data, another player's message). Unknown fields are dropped.
function D.Sanitize(s)
  local out = D.Defaults()
  if type(s) ~= "table" then return out end
  if s.purse == "marks" then out.purse = "marks" end
  out.one = D.CleanName(s.one) or out.one
  out.many = D.CleanName(s.many) or out.many
  -- Off is true; on is false (or nothing, for a place or a feature that starts on).
  if type(s.off) == "table" then
    local n = 0
    for k, v in pairs(s.off) do
      if (v == true or v == false) and type(k) == "string" and (isPlace[k] or (#k <= 32 and k:match("^%l+:%l+$")))
        and n < D.OFF_MAX then
        out.off[k], n = v, n + 1
      end
    end
  end
  -- Powers by rank name: { [action] = { [rank name] = true | false } }; a rank not named has its default.
  if type(s.perms) == "table" then
    for _, a in ipairs(D.ACTIONS) do out.perms[a] = names(s.perms[a], true) end
  end
  out.officers = names(s.officers)
  out.known = names(s.known)
  out.court = s.court == true
  if type(s.cn) == "table" then
    for k, x in pairs(D.NUMBERS) do
      local v = tonumber(s.cn[k])
      if v and v == math.floor(v) and v >= x[2] and v <= x[3] then out.cn[k] = v end
    end
  end
  if type(s.ladder) == "string" then out.ladder = ns.Raffle and ns.Raffle.Clean(s.ladder, D.LADDER_MAX) or out.ladder end
  if type(s.mascot) == "table" then
    local name = ns.Raffle and ns.Raffle.Clean(s.mascot.name, D.MASCOT_NAME_MAX)
    if name then out.mascot.name = name end
    if isMascot[s.mascot.kind] then out.mascot.kind = s.mascot.kind end
  end
  if type(s.herald) == "string" and s.herald ~= "" and #s.herald <= 64 and not s.herald:find("[|%c]") then
    out.herald = s.herald
  end
  local tax = s.tax
  if type(tax) == "table" then
    local o = out.tax
    o.on = tax.on == true
    o.per = tax.per == "week" and "week" or "month"
    local lv = tonumber(tax.lv)
    if lv and lv >= 1 and lv <= D.LEVEL_MAX and lv == math.floor(lv) then o.lv = lv end
    if type(tax.amt) == "table" then
      for r = 0, D.RANK_MAX do
        local a = tonumber(tax.amt[r])
        if a and a >= 1 and a <= D.TAX_MAX and a == math.floor(a) then o.amt[r] = a end
      end
    end
    if type(tax.ex) == "table" then
      local n = 0
      for name, on in pairs(tax.ex) do
        if on == true and type(name) == "string" and name ~= "" and #name <= 64 and n < D.EXEMPT_MAX then
          o.ex[name] = true
          n = n + 1
        end
      end
    end
  end
  -- The guild's look: each choice from its list; the motto counted in letters.
  if type(s.theme) == "table" then
    for k in pairs(D.THEME) do
      if isTheme[k][s.theme[k]] then out.theme[k] = s.theme[k] end
    end
    local clean = ns.Agenda and ns.Agenda.Clean or ns.Raffle.Clean
    out.theme.motto = type(s.theme.motto) == "string" and clean(s.theme.motto, D.MOTTO_MAX) or nil
  end
  -- The punishment rules (SPEC decision 69): the three switches, the places opting out closes with the tax off, and
  -- when they last changed.
  if type(s.pun) == "table" then
    local o = out.pun
    if type(s.pun.tax) == "boolean" then o.tax = s.pun.tax end
    if s.pun.incidents == "court" then o.incidents = "court" end
    if type(s.pun.trial) == "boolean" then o.trial = s.pun.trial end
    if type(s.pun.closed) == "table" then
      for _, place in ipairs({ "challenges", "games", "gambling", "treasury", "professions", "punishments", "calendar",
        "home" }) do
        if s.pun.closed[place] == true then o.closed[place] = true end
      end
    end
    if tonumber(s.pun.t) then o.t = tonumber(s.pun.t) end
  end
  -- The guild's setup (SPEC decision 70): which one, its option, when it was set and when it last changed.
  if type(s.gov) == "table" then
    local o, x = out.gov, s.gov
    for _, id in ipairs({ "democracy", "warcouncil", "monarchy", "dictatorship", "free" }) do
      if x.setup == id then o.setup = id end
    end
    if o.setup then
      o.elect = x.elect == true or nil
      o.sits = x.sits == "elders" and "elders" or "officers"
      o.judge = x.judge == "crown" and "crown" or "ranks"
      o.at, o.t = tonumber(x.at), tonumber(x.t)
    end
  end
  -- Guild chat announcements (Guild/Announce.lua) are on unless the Guild Master switched them off.
  out.hush = s.hush == true
  -- The duel ladder starts over each month, or each season of three months.
  if s.season == "season" then out.season = "season" end
  -- Where the stocks stand (SPEC §6): the Guild Master's spot in the world (UnitPosition's x, y and instance).
  local p = s.spot
  if type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.i) then
    out.spot = { x = tonumber(p.x), y = tonumber(p.y), i = tonumber(p.i), z = type(p.z) == "string" and p.z:sub(1, 40) or nil }
  end
  return out
end

---------------------------------------------------------------------------
-- The guild
---------------------------------------------------------------------------
-- "Guild name-Realm": the guild's realm is the one the game names, else this character's own.
function D:Id()
  -- The self-test's pretend guild, while it runs (Dev/Sandbox.lua).
  if self.sandbox then return self.sandbox end
  local name = ns.Guild()
  if not name then return nil end
  local realm = select(4, GetGuildInfo("player"))
  realm = (type(realm) == "string" and realm ~= "") and realm:gsub("[%s%-]", "") or ns.Realm()
  return name .. "-" .. realm
end

-- Settings tables already made clean (D.Sanitize): checked once, not on every read.
local clean = setmetatable({}, { __mode = "k" })
-- (done: s was just made by D.Sanitize.)
function D.Clean(s, done)
  if not clean[s] then
    if not done then s = D.Sanitize(s) end
    clean[s] = true
  end
  return s
end

function D:Get(id)
  local g = ns.db.guilds[id]
  if type(g) ~= "table" then
    g = { id = id }
    ns.db.guilds[id] = g
  end
  g.id = id
  g.settings = D.Clean(g.settings)
  g.sv = tonumber(g.sv) or 0
  if type(g.seen) ~= "table" then g.seen = {} end
  return g
end

-- This character's guild, or nil outside a guild.
function D:Current()
  local id = ns.db and self:Id()
  return id and self:Get(id) or nil
end

-- The settings in force: the current guild's, or the defaults.
function D:Settings()
  local g = self:Current()
  return g and g.settings or D.Defaults()
end

-- The places and features the guild's setup leaves out (SPEC decision 70): until one is picked, only the regular
-- features (no Punishments; of the Council only Votes; of the Treasury no item requests); a Free guild has no
-- Punishments and no court.
local REGULAR_OFF = { ["council:impeach"] = true, ["council:charter"] = true, ["council:court"] = true,
  ["council:strikes"] = true, ["treasury:req"] = true }
local function setupOf(g) return ns.Rules and ns.Rules.Setup(g) end

function D:PlaceOn(place)
  if place == "punishments" then
    local setup = setupOf()
    if setup == nil or setup == "free" then return false end
  end
  return not self:Settings().off[place]
end
-- A feature, punishment or guild game the Guild Master has not switched off (SPEC decision 52).
function D:On(key, g)
  local s = g and g.settings or self:Settings()
  local setup = setupOf(g)
  if setup == nil and REGULAR_OFF[key] then return false end
  if setup == "free" and key == "council:court" then return false end
  return not (s.off and s.off[key] == true)
end

-- The Council's rules can be changed by a vote of the guild (decided 29 Oct 2026): a passed rule change wins over
-- the Guild Master's setting. D.Rule(g, key) -> the value the guild voted, or nil (Guild/Council.lua sets it).
D.Rule = function() return nil end

-- Is rank r ({ index, name }, from Roster:Ranks) an officer rank? The ones the game lets read officer chat, as the
-- Guild Master's addon read them (D:ReadRanks); before it has, the rank under the Guild Master.
function D.Officer(r, s)
  if s.officers then return s.officers[r.name] == true end
  return r.index == 1
end

-- May rank r do action when the Guild Master has not ticked it either way (SPEC §3.2)? ranks: the guild's ranks.
function D.Default(action, r, ranks, s)
  local open = D.OPEN[action]
  if open == "all" then return true end
  if open == "notLowest" then return r.index < ranks[#ranks].index end
  if open == "officers" then return D.Officer(r, s) end
  return false
end

-- The ranks below the Guild Master that may do action: a set { [rank index] = true }. Each rank on its own, by its
-- name (decision 50).
function D:Ranks(action, g)
  g = g or self:Current()
  local voted = g and D.Rule(g, action)
  if voted then return voted end
  local s = g and g.settings or self:Settings()
  local ticks, ranks, set = s.perms[action] or {}, ns.Roster:Ranks(), {}
  for _, r in ipairs(ranks) do
    local on = ticks[r.name]
    if on == nil then on = D.Default(action, r, ranks, s) end
    if on then set[r.index] = true end
  end
  return set
end

-- The Guild Master ticks or unticks a power for the rank named name.
function D:Tick(action, name, on)
  if not isAction[action] or not rankName(name) then return false end
  return ns.Sync:ChangeSettings(function(s)
    s.perms[action] = s.perms[action] or {}
    s.perms[action][name] = on == true
  end)
end

-- The Guild Master's addon keeps the officer ranks the game reports (so every addon has the same defaults), and the
-- names of the ranks the Guild Master has seen (the first time: the guild's ranks now).
function D:ReadRanks()
  if not ns.Roster:Ready() or not self:InCharge() then return false end
  local s, officers = self:Settings(), ns.Roster:OfficerRanks()
  local same = officers == nil or s.officers ~= nil
  if same and officers then
    for k in pairs(officers) do if not s.officers[k] then same = false end end
    for k in pairs(s.officers) do if not officers[k] then same = false end end
  end
  if same and s.known then return false end
  return ns.Sync:ChangeSettings(function(x)
    if officers then x.officers = officers end
    if not x.known then
      x.known = {}
      for _, r in ipairs(ns.Roster:Ranks()) do x.known[r.name] = true end
    end
  end)
end

-- Ranks the Guild Master has not seen yet (new or renamed in the game): their count, for Manage's red number.
function D:NewRanks()
  local known = self:Settings().known
  if not known then return 0 end
  local n = 0
  for _, r in ipairs(ns.Roster:Ranks()) do if not known[r.name] then n = n + 1 end end
  return n
end

-- The Guild Master has looked at who may do what: the guild's ranks now are the ones seen.
function D:SeenRanks()
  if self:NewRanks() == 0 then return false end
  return ns.Sync:ChangeSettings(function(x)
    x.known = {}
    for _, r in ipairs(ns.Roster:Ranks()) do x.known[r.name] = true end
  end)
end

-- A moment after the roster, so the sync engine has started (at login it starts after the first roster).
ns:On("ROSTER", function() C_Timer.After(1, function() D:ReadRanks() end) end)

-- One of the Council's numbers (D.NUMBERS) in force: voted, else the Guild Master's.
function D:Number(key, g)
  g = g or self:Current()
  local voted = g and D.Rule(g, key)
  if voted then return voted end
  return (g and g.settings or self:Settings()).cn[key] or D.NUMBERS[key][1]
end

-- Does a guilty verdict sentence by itself (SPEC §3.2, the court's switch)?
function D:CourtSentences(g)
  g = g or self:Current()
  local voted = g and D.Rule(g, "sentence")
  if voted ~= nil then return voted == true end
  return (g and g.settings or self:Settings()).court == true
end

-- Is name (default: this character) the Guild Master, and still in charge? Not while an impeachment's winner waits
-- for the hand-over (SPEC §7.5, ns.Council.Ousted): until the guild is handed over, the Guild Master cannot give
-- out, start or change anything in Guild Together. Every addon checks it on the Guild Master's ops too.
function D:InCharge(name, g)
  name = name or ns.Self()
  if ns.Roster:Rank(name) ~= 0 then return false end
  g = g or self:Current()
  return not (g and ns.Council.Ousted(g, name))
end

-- Is name (default: this character) allowed to do action (SPEC §3.2)? The Guild Master in charge always is; others
-- by rank. g: whose settings decide (default: the current guild's).
function D:Can(action, name, g)
  name = name or ns.Self()
  -- The guild's setup says first (SPEC decision 70); nil: as the ranks allow.
  local over = ns.Rules and ns.Rules.May(action, name, g)
  if over ~= nil then return over end
  local rank = ns.Roster:Rank(name)
  if rank == 0 then return self:InCharge(name, g) end
  if rank == nil or not isAction[action] then return false end
  -- A punishment the Guild Master switched off is given by nobody below them (SPEC decision 52).
  if isPun[action] and not self:On("p:" .. action, g) then return false end
  return self:Ranks(action, g)[rank] == true
end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
-- def = { allowed = function(g, author, op) -> bool, apply = function(g, author, op, t, n) -> changed,
--         (n: the author's count; D.Key(author, n) names the op, for entries it adds)
--         copy = function(g) -> part of a whole copy, merge = function(g, part) }
function D:Register(kind, def) self.kinds[kind] = def end

-- Is the op of a known kind, and may its author make it? (Checked by every addon, SPEC §1 Authority.) t: when it was
-- made: an author who had opted out of punishment by then may not take part in what that closes (Guild/Rules.lua).
function D:Allowed(g, author, op, t)
  local def = type(op) == "table" and self.kinds[op.k]
  if not def then return false end
  if ns.Rules and ns.Rules.Blocked(g, author, op, t) then return false end
  return def.allowed(g, author, op, t) or false
end

function D:Apply(g, author, op, t, n)
  local def = self.kinds[op.k]
  return def and def.apply(g, author, op, t, n) or false
end

-- An op's key: entries an op adds are filed under it, so two copies merge by putting their entries together.
function D.Key(author, n) return author .. ":" .. tostring(n) end

-- Who made the op with this key. Ops that refer to another op (joining a roll-off, buying a ticket) may arrive before
-- it, since only each author's own ops come in order: so their checks use the key's author, not the other op's data.
function D.KeyAuthor(key) return type(key) == "string" and key:match("^(.+):%d+$") or nil end

-- Puts the entries of a whole copy's table into ours (entries keyed by D.Key never change once made). check(entry)
-- says whether an entry from another player's copy is sound.
function D.Union(mine, theirs, check)
  if type(theirs) ~= "table" then return end
  for key, e in pairs(theirs) do
    if type(key) == "string" and mine[key] == nil and type(e) == "table" and check(e) then mine[key] = e end
  end
end

-- A table of the guild's data, made when first used.
function D.Part(g, name)
  if type(g[name]) ~= "table" then g[name] = {} end
  return g[name]
end

-- A whole copy of the guild's data, to send when the op log does not reach back far enough.
function D:Copy(g)
  local copy = {}
  for kind, def in pairs(self.kinds) do if def.copy then copy[kind] = def.copy(g) end end
  return copy
end

function D:Merge(g, copy)
  if type(copy) ~= "table" then return end
  for kind, def in pairs(self.kinds) do
    if def.merge and copy[kind] ~= nil then def.merge(g, copy[kind]) end
  end
end

-- The settings: only the Guild Master publishes them, whole. The newest wins: a higher settings version (sv), then
-- the later time, then the author whose name sorts first (the same answer on every copy).
local function newer(sv, t, a, g)
  if sv ~= g.sv then return sv > g.sv end
  local gt = g.st or 0
  if t ~= gt then return t > gt end
  return a < (g.sa or "~")
end

local function take(g, s, sv, t, a)
  sv, t = tonumber(sv), tonumber(t) or 0
  if not sv or type(a) ~= "string" or not newer(sv, t, a, g) then return false end
  g.settings, g.sv, g.st, g.sa = D.Clean(D.Sanitize(s), true), sv, t, a
  -- (Not for the copy of a pretend member in the self-test.)
  if ns.db.guilds[g.id] == g then ns:Fire("GUILD_SETTINGS") end
  return true
end

D:Register("settings", {
  allowed = function(g, author) return D:InCharge(author, g) end,
  apply = function(g, author, op, t) return take(g, op.s, op.sv, t, author) end,
  copy = function(g) return { s = g.settings, sv = g.sv, t = g.st, a = g.sa } end,
  merge = function(g, part)
    if type(part) == "table" and D:InCharge(part.a, g) then take(g, part.s, part.sv, part.t, part.a) end
  end,
})
