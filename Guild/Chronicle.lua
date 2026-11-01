-- The Chronicle (SPEC §8): the guild's story, read from everything else and from a few ops of its own.
--   feat      { to, text, m }        a deed written by a rank that may edit the Chronicle's deeds; m: Marks it earns
--   feat_del  { id }                 such a rank strikes a deed out
--   lvl       { lv }                 the player's own addon: a character reached level lv (10, 20, ... and the cap)
--   memorial  { name, lv, class, where, text }   a rank that may edit deeds remembers a fallen or departed member
--                                    (decided 29 Oct 2026: written by hand; the combat log is closed to addons)
--   memorial_del { id }
--   feed      { n }                  the player's own addon: fish caught since its last report feed the mascot (decided
--                                    29 Oct 2026: every fish a member with the addon catches)
-- Read, not stored: deeds (the hand-written ones, the first to each level, champions, game winners, crowns, ten duels
-- in a row, a new Guild Master), the Hall of fame, the weekly Gazette and the Rolling Pin awards (decided 29 Oct 2026:
-- each month's, worked out from the numbers on the 1st).
local _, ns = ...
local L, D, P, Pu = ns.L, ns.GuildData, ns.Players, ns.Purse
local Clean = ns.Raffle.Clean

local Ch = {}
ns.Chronicle = Ch

Ch.TEXT_MAX, Ch.WHERE_MAX, Ch.NAME_MAX = 120, 40, 64
Ch.MARKS_MAX = 1000
Ch.CAP = 60                -- WoW Forever's level cap
Ch.STREAK = 10             -- duels in a row for a deed
Ch.WEEK, Ch.MONDAY = 7 * 86400, 4 * 86400
Ch.FEED_EVERY, Ch.FEED_WAIT = 5, 300   -- fish per report, or seconds after the last unreported fish

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function name(key, g) return P:Name(key, g) end

---------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------
local function soundFeat(op)
  return party(op.to) and Clean(op.text, Ch.TEXT_MAX) ~= nil and (op.m == nil or whole(op.m, 0, Ch.MARKS_MAX))
end
local function soundLv(lv) return whole(lv, 2, D.LEVEL_MAX) and (lv % 10 == 0 or lv == Ch.CAP) end
local function soundMemorial(op)
  return Clean(op.name, Ch.NAME_MAX) ~= nil and (op.lv == nil or whole(op.lv, 1, D.LEVEL_MAX))
    and (op.class == nil or (type(op.class) == "string" and #op.class <= 20))
    and (op.where == nil or type(op.where) == "string") and (op.text == nil or type(op.text) == "string")
end

D:Register("feat", {
  allowed = function(g, author, op) return soundFeat(op) and D:Can("deeds", author, g) end,
  apply = function(g, author, op, t, n)
    local key = D.Key(author, n)
    D.Part(g, "feats")[key] = { a = author, to = op.to, text = Clean(op.text, Ch.TEXT_MAX), m = tonumber(op.m), t = t }
    -- Marks it earns go into the Marks ledger with the same key, so a whole copy carries them.
    if (tonumber(op.m) or 0) > 0 then D.Part(g, "marks")[key] = { to = op.to, amt = tonumber(op.m), w = "deed", t = t, by = author } end
    return true
  end,
  copy = function(g) return { f = g.feats, x = g.featsOut, l = g.lvls, mem = g.memorials, memx = g.memorialsOut, fd = g.feed } end,
  merge = function(g, part) Ch.Merge(g, part) end,
})

D:Register("feat_del", {
  allowed = function(g, author, op) return host(op.id) ~= nil and D:Can("deeds", author, g) end,
  apply = function(g, _, op, t)
    local out = D.Part(g, "featsOut")
    if out[op.id] and out[op.id] <= t then return false end
    out[op.id] = t
    return true
  end,
})

D:Register("lvl", {
  allowed = function(_, _, op) return soundLv(op.lv) end,
  apply = function(g, author, op, t)
    local lvls = D.Part(g, "lvls")
    local k = author .. "#" .. op.lv
    if lvls[k] and lvls[k].t <= t then return false end
    lvls[k] = { a = author, lv = tonumber(op.lv), t = t }
    return true
  end,
})

D:Register("memorial", {
  allowed = function(g, author, op) return soundMemorial(op) and D:Can("deeds", author, g) end,
  apply = function(g, author, op, t, n)
    D.Part(g, "memorials")[D.Key(author, n)] = { a = author, t = t, name = Clean(op.name, Ch.NAME_MAX), lv = tonumber(op.lv),
      class = op.class, where = Clean(op.where, Ch.WHERE_MAX), text = Clean(op.text, Ch.TEXT_MAX) }
    return true
  end,
})

D:Register("memorial_del", {
  allowed = function(g, author, op) return host(op.id) ~= nil and D:Can("deeds", author, g) end,
  apply = function(g, _, op, t)
    local out = D.Part(g, "memorialsOut")
    if out[op.id] and out[op.id] <= t then return false end
    out[op.id] = t
    return true
  end,
})

D:Register("feed", {
  allowed = function(_, _, op) return whole(op.n, 1, 100) end,
  apply = function(g, author, op, t, n)
    D.Part(g, "feed")[D.Key(author, n)] = { a = author, n = tonumber(op.n), t = t }
    return true
  end,
})

function Ch.Merge(g, part)
  if type(part) ~= "table" then return end
  D.Union(D.Part(g, "feats"), part.f, function(e) return party(e.a) and tonumber(e.t) and soundFeat(e) end)
  D.Union(D.Part(g, "lvls"), part.l, function(e) return party(e.a) and tonumber(e.t) and soundLv(e.lv) end)
  D.Union(D.Part(g, "memorials"), part.mem, function(e) return party(e.a) and tonumber(e.t) and soundMemorial(e) end)
  D.Union(D.Part(g, "feed"), part.fd, function(e) return party(e.a) and tonumber(e.t) and whole(e.n, 1, 100) end)
  for _, pair in ipairs({ { "featsOut", part.x }, { "memorialsOut", part.memx } }) do
    local mine = D.Part(g, pair[1])
    for id, t in pairs(type(pair[2]) == "table" and pair[2] or {}) do
      if type(id) == "string" and tonumber(t) and (not mine[id] or t < mine[id]) then mine[id] = t end
    end
  end
end

---------------------------------------------------------------------------
-- Deeds
---------------------------------------------------------------------------
-- Every deed, newest first: { id, t, key (the player, or nil for the guild), text, kind ("feat" or "auto"), m }.
function Ch.Deeds(g, now)
  now = now or time()
  local list = {}
  local function add(id, t, key, text, kind, m) list[#list + 1] = { id = id, t = t, key = key, text = text, kind = kind or "auto", m = m } end
  if not g then return list end
  -- By hand.
  local out = g.featsOut or {}
  for id, e in pairs(g.feats or {}) do
    if not out[id] then add(id, e.t, P:Of(e.to, g), e.text, "feat", e.m) end
  end
  -- The first to each level.
  local first = {}
  for _, e in pairs(g.lvls or {}) do
    local f = first[e.lv]
    if not f or e.t < f.t or (e.t == f.t and e.a < f.a) then first[e.lv] = e end
  end
  for lv, e in pairs(first) do add("lvl:" .. lv, e.t, P:Of(e.a, g), L.CH_DEED_FIRST:format(lv)) end
  -- Champions of tournaments, and a new Guild Master from the crown's tournament.
  for id, c in pairs(g.cups or {}) do
    local champ = c.places and c.places[1] and c.places[1][1]
    if champ and not c.lead then add("cup:" .. id, c.te or c.t or 0, P:Of(champ, g), L.CH_DEED_CUP:format(c.name or "?")) end
  end
  for _, s in ipairs(ns.Council.Motions(g, now, "lead")) do
    if s.phase == "handed" and s.winner then
      add("gm:" .. s.id, s.mo.done or (s.cup and s.cup.te) or s.fought or s.passedAt or s.mo.t, P:Of(s.winner, g), L.CH_DEED_GM)
    end
  end
  -- Winners of guild games.
  for id, ga in pairs(g.games or {}) do
    if ga.st == "done" and ga.w then
      for i, w in ipairs(ga.w) do add("game:" .. id .. ":" .. i, ga.te or 0, P:Of(w, g), L.CH_DEED_GAME:format(ns.Games.KindName(ga.kind):lower())) end
    end
  end
  -- The crown changing hands.
  local s = ns.Crown.State(g, now)
  local reigns = {}
  for _, r in ipairs(s.reigns) do reigns[#reigns + 1] = r end
  if s.holder then reigns[#reigns + 1] = { key = s.holder, from = s.since } end
  for i, r in ipairs(reigns) do add("crown:" .. i .. ":" .. r.from, r.from, r.key, L.CH_DEED_CROWN) end
  -- Ten ladder duels won in a row.
  local duels = {}
  for c, e in pairs(g.duels or {}) do duels[#duels + 1] = { c = c, w = e.w, l = e.l, t = e.t or 0 } end
  table.sort(duels, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.c < b.c end)
  local run = {}
  for _, d in ipairs(duels) do
    local w, l = P:Of(d.w, g), P:Of(d.l, g)
    if w ~= l then
      run[w], run[l] = (run[w] or 0) + 1, 0
      if run[w] % Ch.STREAK == 0 then add("streak:" .. d.c, d.t, w, L.CH_DEED_STREAK:format(run[w])) end
    end
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id > b.id end)
  return list
end

---------------------------------------------------------------------------
-- The Hall of fame: the guild's records
---------------------------------------------------------------------------
local function top(counts)
  local best, n = nil, 0
  for key, v in pairs(counts) do
    if v > n or (v == n and best and key < best) then best, n = key, v end
  end
  return best, n
end

-- { { id, label, key, value (text) } }, the records that have a holder.
function Ch.Hall(g, now)
  now = now or time()
  local rows = {}
  local function row(id, label, key, value)
    if key then rows[#rows + 1] = { id = id, label = label, key = key, value = value } end
  end
  local function count(id, label, counts)
    local key, n = top(counts)
    if key and n > 0 then row(id, label, key, tostring(n)) end
  end
  local longest = ns.Crown.Longest(ns.Crown.State(g, now), now)
  if longest then
    local days = math.max(1, math.floor(longest.len / 86400 + 0.5))
    row("reign", L.CH_HALL_REIGN, longest.key, days == 1 and L.AR_DAY or L.CH_DAYS:format(days))
  end
  local ladder = ns.Duels.Ladder(g)
  if ladder[1] then row("rating", L.CH_HALL_RATING, ladder[1].key, tostring(ladder[1].r)) end
  local wins, champs, games, fish, streak = {}, {}, {}, {}, {}
  for _, e in ipairs(ladder) do wins[e.key] = e.w end
  count("duels", L.CH_HALL_DUELS, wins)
  for _, d in ipairs(Ch.Deeds(g, now)) do
    if d.id:sub(1, 4) == "cup:" then champs[d.key] = (champs[d.key] or 0) + 1 end
    if d.id:sub(1, 5) == "game:" then games[d.key] = (games[d.key] or 0) + 1 end
    if d.id:sub(1, 7) == "streak:" then streak[d.key] = math.max(streak[d.key] or 0, tonumber(d.text:match("%d+")) or 0) end
  end
  for _, e in pairs(g and g.feed or {}) do local k = P:Of(e.a, g) fish[k] = (fish[k] or 0) + e.n end
  count("cups", L.CH_HALL_CUPS, champs)
  count("games", L.CH_HALL_GAMES, games)
  count("streak", L.CH_HALL_STREAK, streak)
  local patrons = ns.Treasury.Patrons(g, now)
  table.sort(patrons, function(a, b) if a.ever ~= b.ever then return a.ever > b.ever end return a.key < b.key end)
  if patrons[1] and patrons[1].ever > 0 then
    row("patron", L.CH_HALL_PATRON, patrons[1].key, Pu:Format(patrons[1].ever, "gold"))
  end
  count("fish", L.CH_HALL_FISH, fish)
  return rows
end

-- Records that change hands (SPEC decision 75). Each screen looks before and after an op it hears fresh: a record with
-- a new holder plays on the alert line, and when it happened is kept here (GuildTogetherForeverDB.records[guild][id] = { key, t })
-- for the plaque's "since". A first holder is kept too, without the alert.
Ch.RECORD_ICON = { reign = "crown", rating = "duel", duels = "rosette", cups = "prize", games = "pl_games",
  streak = "laurel", patron = "chalice", fish = "fish" }
function Ch.Held(g)
  if not ns.db or not g or not g.id then return {} end
  ns.db.records = type(ns.db.records) == "table" and ns.db.records or {}
  ns.db.records[g.id] = type(ns.db.records[g.id]) == "table" and ns.db.records[g.id] or {}
  return ns.db.records[g.id]
end

-- Since when key holds record id, as far as this screen saw (nil: not seen change hands).
function Ch.Since(g, id, key)
  local e = Ch.Held(g)[id]
  return e and e.key == key and tonumber(e.t) or nil
end

local function holders(g)
  local out = {}
  for _, r in ipairs(Ch.Hall(g)) do out[r.id] = r end
  return out
end

-- Compares the records before (from Ch.Look) with now; t: when the op happened. Returns the records that changed hands.
function Ch.Changed(g, before, t)
  local held, out = Ch.Held(g), {}
  for id, r in pairs(holders(g)) do
    local was = before[id]
    if not was then
      held[id] = held[id] and held[id].key == r.key and held[id] or { key = r.key, t = t }
    elseif was.key ~= r.key then
      held[id] = { key = r.key, t = t }
      out[#out + 1] = { r = r, was = was }
    end
  end
  table.sort(out, function(a, b) return a.r.id < b.r.id end)
  return out
end

-- (Before an op heard fresh: the records as they stand.)
function Ch.Look(g)
  local ok, h = pcall(holders, g)
  return ok and h or nil
end

ns:On("OP_BEFORE", function(g, _, _, t)
  Ch.before = nil
  local An = ns.Announce
  if An and An.FRESH and math.abs(time() - t) < An.FRESH then Ch.before = Ch.Look(g) end
end)

ns:On("OP", function(g, _, _, t)
  local before = Ch.before
  Ch.before = nil
  if not before or not ns.db or not ns.db.guilds or ns.db.guilds[g.id] ~= g then return end
  local ok, changed = pcall(Ch.Changed, g, before, t)
  if not ok then return ns:LogError("records", tostring(changed)) end
  for _, x in ipairs(changed) do
    ns:Fire("ALERT", { text = L.AN_ALERT_RECORD:format(x.r.label), fanfare = true, icon = Ch.RECORD_ICON[x.r.id],
      sub = L.AN_ALERT_RECORD_SUB:format(name(x.r.key, g), x.r.value, name(x.was.key, g)) })
  end
end)

---------------------------------------------------------------------------
-- The mascot
---------------------------------------------------------------------------
-- { name, kind, level, fed (all), week (fish this week), mood, last }. Level n needs 5·n·(n-1) fish.
function Ch.Mascot(g, now)
  now = now or time()
  local m = (g and g.settings or D:Settings()).mascot
  local s = { name = m.name, kind = m.kind, fed = 0, week = 0, recent = 0, last = nil }
  local weekStart = Ch.WeekStart(now)
  for _, e in pairs(g and g.feed or {}) do
    s.fed = s.fed + e.n
    if e.t >= weekStart then s.week = s.week + e.n end
    if e.t >= now - 3 * 86400 then s.recent = s.recent + e.n end
    if not s.last or e.t > s.last then s.last = e.t end
  end
  s.level = math.floor((1 + math.sqrt(1 + 8 * s.fed / 10)) / 2)
  if not s.last or now - s.last > 7 * 86400 then s.mood = "sulking"
  elseif s.recent >= 10 then s.mood = "happy"
  elseif s.recent >= 1 then s.mood = "content"
  else s.mood = "hungry" end
  return s
end

-- Who fed the mascot most, all told: { { key, n }, ... }, most first (SPEC decision 75).
function Ch.Feeders(g)
  local by, out = {}, {}
  for _, e in pairs(g and g.feed or {}) do
    local k = P:Of(e.a, g)
    by[k] = (by[k] or 0) + e.n
  end
  for k, n in pairs(by) do out[#out + 1] = { key = k, n = n } end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
  return out
end

---------------------------------------------------------------------------
-- The weekly Gazette
---------------------------------------------------------------------------
function Ch.WeekStart(t) return Ch.MONDAY + math.floor((t - Ch.MONDAY) / Ch.WEEK) * Ch.WEEK end

-- The week's number in its year (1 to 53, from the week holding 1 January).
function Ch.WeekNumber(t)
  local start = Ch.WeekStart(t)
  local jan1 = start - (tonumber(date("!%j", start)) - 1) * 86400
  return math.floor((start - Ch.WeekStart(jan1)) / Ch.WEEK) + 1
end

-- The guild's name, from its id ("Guild name-Realm").
function Ch.GuildName(g)
  return g and g.id and (g.id:match("^(.+)%-[^%-]+$") or g.id) or L.CH_THE_GUILD
end

-- What news is worth: the headline is the biggest.
local WORTH = { gm = 6, crown = 5, cup = 4, game = 3, lvl = 3, streak = 2, feat = 2 }

-- The Gazette of the week holding t: { week, mast, headline, lines = { text }, n (stories), stories = { { kind, d } }
-- (biggest first), key (the headline's player, if one) }.
function Ch.Gazette(g, t)
  local from = Ch.WeekStart(t)
  local to = from + Ch.WEEK
  local guildName = Ch.GuildName(g)
  local z = { week = from, mast = L.CH_MAST:format(guildName, Ch.WeekNumber(from)), lines = {},
    name = L.CH_MAST_NAME:format(guildName), dateline = L.CH_DATELINE:format(Ch.WeekNumber(from), date(L.CH_DATE, from)) }
  local stories = {}
  for _, d in ipairs(Ch.Deeds(g, to)) do
    if d.t >= from and d.t < to then
      local kind = d.kind == "feat" and "feat" or d.id:match("^(%a+):")
      stories[#stories + 1] = { worth = WORTH[kind] or 1, t = d.t, kind = kind, d = d }
    end
  end
  table.sort(stories, function(a, b) if a.worth ~= b.worth then return a.worth > b.worth end return a.t > b.t end)
  local function story(x)
    local who = name(x.d.key, g)
    return L["CH_NEWS_" .. x.kind:upper()] and L["CH_NEWS_" .. x.kind:upper()]:format(who, x.d.text) or (who .. ": " .. x.d.text)
  end
  z.stories, z.key = stories, stories[1] and stories[1].d.key or nil
  if stories[1] then
    z.headline = story(stories[1]):upper()
  else
    z.headline = L.CH_QUIET:upper()
  end
  for i = 2, math.min(4, #stories) do z.lines[#z.lines + 1] = story(stories[i]) end
  -- The Stocks and the mascot.
  local sentences = 0
  for _, s in ipairs(ns.Stocks.List(g, to)) do
    if s.se.t >= from and s.se.t < to and s.st ~= "void" then sentences = sentences + 1 end
  end
  local dunce = ns.Stocks.Dunce(g, math.min(to - 1, time()))
  if dunce then z.lines[#z.lines + 1] = L.CH_NEWS_DUNCE:format(name(dunce, g)) end
  if sentences > 0 then z.lines[#z.lines + 1] = L.CH_NEWS_SENTENCES:format(sentences) end
  local fish = 0
  for _, e in pairs(g and g.feed or {}) do if e.t >= from and e.t < to then fish = fish + e.n end end
  if fish > 0 then z.lines[#z.lines + 1] = L.CH_NEWS_FED:format(Ch.Mascot(g).name, fish) end
  z.n = #stories
  return z
end

---------------------------------------------------------------------------
-- The Rolling Pin awards: last month's, from the numbers
---------------------------------------------------------------------------
Ch.AWARDS = { "tomato", "jail", "bag", "patron", "snake" }

local function monthOf(t) return date("!%Y-%m", t) end

-- The month before the one holding t ("2026-10").
function Ch.LastMonth(t)
  local y, m = monthOf(t):match("^(%d+)%-(%d+)$")
  y, m = tonumber(y), tonumber(m) - 1
  if m == 0 then y, m = y - 1, 12 end
  return ("%04d-%02d"):format(y, m)
end

-- The awards for a month ("2026-10"): { { id, key, n, text (the number shown) } }, only those with a winner.
function Ch.Awards(g, month)
  local counts = {}
  for _, id in ipairs(Ch.AWARDS) do counts[id] = {} end
  local function add(id, key, n) if key then counts[id][key] = (counts[id][key] or 0) + (n or 1) end end
  for _, se in pairs(g and g.sentences or {}) do
    if se.by and se.t and monthOf(se.t) == month then
      add("jail", P:Of(se.to, g))
      for who, n in pairs(se.tom or {}) do add("tomato", P:Of(who, g), n) end
    end
  end
  for _, e in pairs(g and g.duels or {}) do
    if e.t and monthOf(e.t) == month and e.l then add("bag", P:Of(e.l, g)) end
  end
  for _, part in ipairs({ g and g.debts or {}, g and g.marks or {} }) do
    for _, e in pairs(part) do
      if e.w == "deathroll" and e.t and monthOf(e.t) == month and e.f then add("snake", P:Of(e.f, g)) end
    end
  end
  local y, m = month:match("^(%d+)%-(%d+)$")
  local mid = time({ year = tonumber(y), month = tonumber(m), day = 15, hour = 12 })
  local patron = ns.Treasury.Patrons(g, mid)[1]
  local list = {}
  for _, id in ipairs(Ch.AWARDS) do
    if id == "patron" then
      if patron and patron.month >= Pu.GOLD then
        list[#list + 1] = { id = id, key = patron.key, n = patron.month, text = Pu:Format(patron.month, "gold") }
      end
    else
      local key, n = top(counts[id])
      if key and n > 0 then list[#list + 1] = { id = id, key = key, n = n, text = tostring(n) } end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Memorials
---------------------------------------------------------------------------
-- One line for a memorial: "Aldric, level 41 Hunter, fell in Feralas. "He said he could solo it.""
function Ch.MemorialLine(e)
  local who = ns.Display(e.name)
  local class = e.class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class]) or
    (e.class:sub(1, 1) .. e.class:sub(2):lower()))
  local line = who
  if e.lv and class then line = L.CH_MEM_LV_CLASS:format(who, e.lv, class)
  elseif e.lv then line = L.CH_MEM_LV:format(who, e.lv) end
  if e.where then line = L.CH_MEM_WHERE:format(line, e.where) else line = line .. "." end
  if e.text then line = line .. " " .. L.CH_MEM_TEXT:format(e.text) end
  return line
end

function Ch.Memorials(g)
  local list, out = {}, g and g.memorialsOut or {}
  for id, e in pairs(g and g.memorials or {}) do if not out[id] then list[#list + 1] = { id = id, e = e } end end
  table.sort(list, function(a, b) if a.e.t ~= b.e.t then return a.e.t > b.e.t end return a.id > b.id end)
  return list
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function sync(op) return ns.Sync:Do(op) end

function Ch.Write(to, text, marks)
  local full = to and ns.FullName(strtrim(to))
  text = Clean(text, Ch.TEXT_MAX)
  if not full or not text or ns.Roster:Rank(full) == nil then return false end
  return sync({ k = "feat", to = full, text = text, m = (marks or 0) > 0 and marks or nil })
end
function Ch.Strike(id) return sync({ k = "feat_del", id = id }) end

-- A memorial: the level and class from the roster when the member is still in it.
function Ch.Remember(who, where, text, lv)
  local full = who and ns.FullName(strtrim(who))
  if not full then return false end
  local class = ns.Roster:Class(full)
  return sync({ k = "memorial", name = full, lv = lv or ns.Roster:Level(full), class = class,
    where = Clean(where, Ch.WHERE_MAX), text = Clean(text, Ch.TEXT_MAX) })
end
function Ch.Forget(id) return sync({ k = "memorial_del", id = id }) end

---------------------------------------------------------------------------
-- This character's own addon: levels reached and fish caught
---------------------------------------------------------------------------
Ch.unfed, Ch.unfedAt = 0, 0

function Ch.Flush()
  if Ch.unfed <= 0 or not D:Current() then return false end
  local n = math.min(Ch.unfed, 100)
  if sync({ k = "feed", n = n }) then Ch.unfed = Ch.unfed - n return true end
  return false
end

ns:On("SEEN", function(what)
  if not D:Current() then return end
  if what == "fish" then
    Ch.unfed, Ch.unfedAt = Ch.unfed + 1, GetTime()
    if Ch.unfed >= Ch.FEED_EVERY then Ch.Flush() end
  elseif what == "ding" then
    local lv = UnitLevel("player")
    if lv and not (issecretvalue and issecretvalue(lv)) and soundLv(lv) then sync({ k = "lvl", lv = lv }) end
  end
end)

ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function()
      if Ch.unfed > 0 and GetTime() - Ch.unfedAt >= Ch.FEED_WAIT then Ch.Flush() end
    end)
  end
end)
