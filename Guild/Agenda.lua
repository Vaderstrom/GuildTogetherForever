-- The Calendar place (SPEC decision 61): every kind of event in one place. Guild Together's own (everything a feature gives
-- a time), the guild's events in the game's calendar (read only: members sign up there) and the officers' own events.
-- Ops (the officers' own events, the one place where an event has a name of its own):
--   cal_add  { name, at, line }        a rank that may add calendar events (SPEC §3.2, cal) adds one (its key is its id)
--   cal_edit { id, name, at, line }    whoever added it (any of their characters) or the Guild Master changes it
--   cal_off  { id }                    the same remove it
-- The newest change wins (its time, then the author whose name sorts first), so every copy shows the same.
local _, ns = ...
local L, D, P = ns.L, ns.GuildData, ns.Players

local Ag = {}
ns.Agenda = Ag

Ag.NAME_MAX, Ag.LINE_MAX = 40, 120   -- letters
Ag.AHEAD = 366 * 86400               -- an event at most a year ahead
Ag.DAY = 86400

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function host(id) return D.KeyAuthor(id) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Free text counted in letters (UTF-8, so å, ä and ö count once): no chat escapes or control letters, trimmed. Nil if
-- empty.
function Ag.Clean(s, max)
  if type(s) ~= "string" then return nil end
  s = strtrim((s:gsub("[%z\1-\31|]", "")))
  local out, n = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    if n > max then break end
    out[#out + 1] = ch
  end
  s = strtrim(table.concat(out))
  return s ~= "" and s or nil
end

-- A sound event: a name, a whole time and maybe a line; with t, at most a year after t (now and a day, for clocks
-- that differ).
local function sound(op, t)
  local at = tonumber(op.at)
  return Ag.Clean(op.name, Ag.NAME_MAX) ~= nil and at ~= nil and at == math.floor(at)
    and (not t or at <= t + Ag.AHEAD) and (op.line == nil or Ag.Clean(op.line, Ag.LINE_MAX) ~= nil)
end

-- May author change or remove the event with key id: the player who added it, or the Guild Master in charge.
local function owner(g, author, id)
  local by = host(id)
  if not by then return false end
  return P:Of(author, g) == P:Of(by, g) or D:InCharge(author, g)
end

local function event(g, id)
  local all = D.Part(g, "calendar")
  all[id] = all[id] or {}
  return all[id]
end

local function newer(cur, t, a) return not cur or t > cur.t or (t == cur.t and a < cur.a) end

D:Register("cal_add", {
  allowed = function(g, author, op) return D:Can("cal", author, g) and sound(op, time() + Ag.DAY) end,
  apply = function(g, author, op, t, n)
    local e = event(g, D.Key(author, n))
    if e.by then return false end
    e.by, e.t, e.name, e.at, e.line = author, t, Ag.Clean(op.name, Ag.NAME_MAX), tonumber(op.at), Ag.Clean(op.line, Ag.LINE_MAX)
    return true
  end,
  copy = function(g) return g.calendar end,
  merge = function(g, part) Ag.Merge(g, part) end,
})

D:Register("cal_edit", {
  allowed = function(g, author, op) return type(op.id) == "string" and owner(g, author, op.id) and sound(op, time() + Ag.DAY) end,
  apply = function(g, author, op, t)
    local e = event(g, op.id)
    if not newer(e.ed, t, author) then return false end
    e.ed = { t = t, a = author, name = Ag.Clean(op.name, Ag.NAME_MAX), at = tonumber(op.at),
      line = Ag.Clean(op.line, Ag.LINE_MAX) }
    return true
  end,
})

D:Register("cal_off", {
  allowed = function(g, author, op) return type(op.id) == "string" and owner(g, author, op.id) end,
  apply = function(g, _, op, t)
    local e = event(g, op.id)
    if e.off and e.off <= t then return false end
    e.off = t
    return true
  end,
})

-- A whole copy's events put together with ours.
function Ag.Merge(g, part)
  for id, x in pairs(type(part) == "table" and part or {}) do
    if type(id) == "string" and host(id) and type(x) == "table" then
      local e = event(g, id)
      if not e.by and party(x.by) and x.by == host(id) and tonumber(x.t) and sound(x) then
        e.by, e.t, e.name, e.at, e.line = x.by, x.t, Ag.Clean(x.name, Ag.NAME_MAX), tonumber(x.at), Ag.Clean(x.line, Ag.LINE_MAX)
      end
      local ed = x.ed
      if type(ed) == "table" and party(ed.a) and tonumber(ed.t) and sound(ed) and newer(e.ed, ed.t, ed.a) then
        e.ed = { t = ed.t, a = ed.a, name = Ag.Clean(ed.name, Ag.NAME_MAX), at = tonumber(ed.at),
          line = Ag.Clean(ed.line, Ag.LINE_MAX) }
      end
      if tonumber(x.off) and (not e.off or x.off < e.off) then e.off = x.off end
    end
  end
end

-- An own event as it stands: { id, by, name, at, line } (the newest change), or nil when removed or not heard of.
function Ag.Own(g, id)
  local e = g and g.calendar and g.calendar[id]
  if not e or not e.by or e.off then return nil end
  local cur = e.ed or e
  return { id = id, by = e.by, name = cur.name, at = cur.at, line = cur.line, t = e.t }
end

-- May this character change or remove the own event?
function Ag.MayChange(g, id) return owner(g, ns.Self(), id) end

local function sync(op) return ns.Sync:Do(op) end
function Ag.Add(name, at, line) return sync({ k = "cal_add", name = name, at = at, line = line }) end
function Ag.Change(id, name, at, line) return sync({ k = "cal_edit", id = id, name = name, at = at, line = line }) end
function Ag.Remove(id) return sync({ k = "cal_off", id = id }) end

---------------------------------------------------------------------------
-- Reading: every event, from each feature that has a time
---------------------------------------------------------------------------
-- An event: { key, icon, name, sub, at, ends (or nil), mine (you take part), due (a deadline, not something to go
-- to), going (on until someone ends it: a court case), page / pick / open (where it lives: UI/Pages/Calendar.lua goes
-- there), own (an own event's id), game (the game's calendar event: { by, kind }) }. icon is a name in UI.ICON.
local SOURCES = {}

local function on(place) return D:PlaceOn(place) end

SOURCES.games = function(g, add, now)
  if not on("games") then return end
  local Gm, me = ns.Games, P:Of(ns.Self(), g)
  for id, ga in pairs(g.games or {}) do
    local st = ga.kind and Gm.State(ga, now)
    local at = ga.kind == "santa" and ga.rv or ga.at
    if st and st ~= "off" and at then
      local ends = Gm.Ends(ga)
      add({ key = "game:" .. id, icon = ga.kind, name = Gm.KindName(ga.kind), sub = L.CA_HOST:format(ns.Display(ga.h or "?")),
        at = at, ends = ends ~= math.huge and ends > at and ends or nil, mine = Gm.IsIn(g, ga, me) or P:Of(ga.h, g) == me,
        page = "games", open = function(page) page.sel, page.part, page.view = id, "game", nil end })
    end
  end
end

-- A time the host wrote ("Sat 20:00"), read from when they wrote it.
local function when(text, from)
  if type(text) ~= "string" or strtrim(text) == "" then return nil end
  return ns.Games.When(text, from)
end

SOURCES.cups = function(g, add)
  if not on("challenges") then return end
  local me = P:Of(ns.Self(), g)
  for id, c in pairs(g.cups or {}) do
    local at = c.h and not c.lead and c.st ~= "cancelled" and when(c.when, c.t)
    if at then
      local mine = P:Of(c.h, g) == me
      for _, name in ipairs(ns.Cup.Joined(c)) do if P:Of(name, g) == me then mine = true end end
      add({ key = "cup:" .. id, icon = "prize", name = c.name or L.CA_CUP, sub = L.CA_CUP, at = at, mine = mine,
        page = "arena", pick = "cup" })
    end
  end
end

SOURCES.crown = function(g, add, now)
  if not (on("challenges") and D:On("arena:duels")) then return end
  local Cr, me = ns.Crown, P:Of(ns.Self(), g)
  local s = Cr.State(g, now)
  if not s.holder then return end
  local holder = P:Name(s.holder, g)
  for _, x in ipairs(Cr.Waiting(g, s, now)) do
    add({ key = "crown:" .. x.id, icon = "crown", name = L.CA_CROWN_ANSWER, due = true,
      sub = L.CA_VS:format(ns.Display(x.c), ns.Display(holder)), at = x.t + Cr.DAY,
      mine = s.holder == me or P:Of(x.c, g) == me, page = "arena", pick = "duels" })
  end
  for _, x in ipairs(Cr.Accepted(g, s, now)) do
    add({ key = "crownduel:" .. x.id, icon = "crown", name = L.CA_CROWN_DUEL, due = true,
      sub = L.CA_VS:format(ns.Display(x.c), ns.Display(holder)), at = x.t + Cr.PLAY,
      mine = s.holder == me or P:Of(x.c, g) == me, page = "arena", pick = "duels" })
  end
end

SOURCES.raffles = function(g, add)
  if not (on("gambling") and D:On("tavern:raffles")) then return end
  for id, ra in pairs(g.raffles or {}) do
    local at = ra.h and ra.st ~= "done" and when(ra.when, ra.t)
    if at then
      local mine = false
      for name in pairs(ra.b or {}) do if P:IsMe(P:Of(name, g), g) then mine = true end end
      add({ key = "raffle:" .. id, icon = "ticket", name = L.CA_DRAW, sub = ra.prize, at = at, mine = mine,
        page = "tavern", pick = "raffles" })
    end
  end
end

SOURCES.council = function(g, add)
  local Co = ns.Council
  local now = Co.Now()
  local me = P:Of(ns.Self(), g)
  for _, s in ipairs(Co.Polls(g, now)) do
    add({ key = "poll:" .. s.id, icon = "ballot", name = L.CA_POLL, sub = s.q, at = s.ends, due = true,
      mine = s.mine ~= nil or P:Of(s.po.h, g) == me, page = "council", pick = "votes" })
  end
  for _, s in ipairs(Co.Motions(g, now, "rule")) do
    local at = s.phase == "motion" and s.deadline or s.ve
    if at then
      add({ key = "motion:" .. s.id, icon = "ballot", name = s.phase == "motion" and L.CA_SECONDS or L.CA_MOTION,
        sub = s.mo.why, at = at, due = true, mine = s.mine ~= nil or P:Of(s.mo.a, g) == me, page = "council", pick = "votes" })
    end
  end
  local lead = Co.Lead(g, now)
  if lead then
    local at, name
    if lead.kind == "lead" and lead.phase == "vote" then at, name = lead.ve, L.CA_IMPEACH
    elseif lead.kind == "mak" and lead.phase == "challenge" then at, name = lead.deadline, L.CA_MAK_ANSWER
    elseif lead.kind == "mak" and lead.phase == "vote" then at, name = lead.ve, L.CA_MAK_VOTE
    elseif lead.kind == "mak" and lead.phase == "duel" then at, name = lead.deadline, L.CA_MAK_DUEL
    elseif lead.kind == "crown" and lead.phase == "signup" and lead.cup then at, name = lead.cup.t + Co.SIGNUP, L.CA_GM_CUP end
    if at then
      add({ key = "lead:" .. lead.id, icon = "throne", name = name, at = at, due = true, mine = false,
        page = "council", pick = "impeach" })
    end
  end
  if D:On("council:court") then
    for _, s in ipairs(ns.Court.Cases(g)) do
      if not s.cs.closed then
        add({ key = "court:" .. s.id, icon = "scales", name = L.CA_COURT, sub = ns.Display(s.cs.to), at = s.cs.t, going = true,
          mine = s.onJury or s.key == me or P:Of(s.cs.h, g) == me, page = "council", pick = "court" })
      end
    end
  end
end

-- The Guild Master's election of each month (SPEC decision 70): standing from the 1st, voting from the 5th (the
-- guild's months are counted in UTC, as Guild/Council.lua does).
local function utc(y, m, d)
  local t = time({ year = y, month = m, day = d, hour = 0 })
  local u, l = date("!*t", t), date("*t", t)
  u.isdst, l.isdst = nil, nil
  return t + (time(l) - time(u))
end
Ag.UTC = utc

SOURCES.elect = function(g, add, _, from, to)
  local Co = ns.Council
  if not Co.Elects(g) then return end
  local d = date("!*t", from)
  local y, m = d.year, d.month
  while true do
    local start = utc(y, m, 1)
    if start >= to then break end
    local key = ("%04d-%02d"):format(y, m)
    local e = Co.Election(g, key, Co.Now())
    local stood = false
    for _, c in ipairs(e.cands) do if not c.sitting and P:IsMe(P:Of(c.name, g), g) then stood = true end end
    add({ key = "stand:" .. key, icon = "crown", name = L.CA_STAND, at = start, ends = utc(y, m, Co.STAND_DAYS + 1),
      mine = stood, page = "council", pick = "elect" })
    add({ key = "elect:" .. key, icon = "crown", name = L.CA_ELECT, at = utc(y, m, Co.STAND_DAYS + 1),
      ends = utc(y, m, Co.VOTE_DAYS + 1), mine = e.mine ~= nil, page = "council", pick = "elect" })
    m = m + 1
    if m > 12 then y, m = y + 1, 1 end
  end
end

-- The guild tax's days (SPEC §8): the first of each month, or each Monday (UTC, as Guild/Treasury.lua counts them).
SOURCES.tax = function(g, add, _, from, to)
  local tax = on("treasury") and g.settings.tax
  if not (tax and tax.on) then return end
  local Tx = ns.Treasury
  local days = {}
  if tax.per == "week" then
    local k = math.ceil((from - Tx.MONDAY) / Tx.WEEK)
    for t = Tx.MONDAY + k * Tx.WEEK, to - 1, Tx.WEEK do days[#days + 1] = t end
  else
    local d = date("!*t", from)
    local y, m = d.year, d.month
    while true do
      local t = utc(y, m, 1)
      if t >= to then break end
      if t >= from then days[#days + 1] = t end
      m = m + 1
      if m > 12 then y, m = y + 1, 1 end
    end
  end
  for _, t in ipairs(days) do
    add({ key = "tax:" .. t, icon = "purse", name = L.CA_TAX, sub = Tx.PeriodName(Tx.Period(tax.per, t)), at = t,
      mine = false, page = "treasury", pick = "debts" })
  end
end

SOURCES.gatherings = function(_, add)
  local Ga = ns.Gatherings
  if not Ga.Available() then return end
  local api = JourneyTogetherForeverAPI
  local ok, list = pcall(api.Gatherings)
  if not ok or type(list) ~= "table" then return end
  local me = ns.Self()
  for _, x in ipairs(list) do
    if type(x) == "table" and type(x.id) == "string" and tonumber(x.at) and type(x.what) == "string" and not x.cancelled then
      local mine = x.by == me
      for _, name in ipairs(type(x.members) == "table" and x.members or {}) do if name == me then mine = true end end
      add({ key = "journey:" .. x.id, icon = "journey", name = x.what, sub = L.CA_JOURNEY, at = tonumber(x.at), mine = mine,
        page = "games", pick = "journey" })
    end
  end
end

SOURCES.own = function(g, add)
  for id in pairs(g.calendar or {}) do
    local e = Ag.Own(g, id)
    if e then
      add({ key = "own:" .. id, icon = "mail", name = e.name, sub = e.line, at = e.at, own = id,
        mine = P:IsMe(P:Of(e.by, g), g) })
    end
  end
end

---------------------------------------------------------------------------
-- The game's calendar: the guild's events, read only (SPEC decision 61)
---------------------------------------------------------------------------
local GUILD_TYPES = { GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true }

-- Our time for the calendar's realm time { year, month, monthDay, hour, minute } (Cal.Fields the other way round).
local function fromRealm(f)
  if type(f) ~= "table" then return nil end
  for _, k in ipairs({ "year", "month", "monthDay", "hour", "minute" }) do
    if secret(f[k]) or not tonumber(f[k]) then return nil end
  end
  local back = ns.Calendar.Fields(time())
  local offset = time({ year = back.year, month = back.month, day = back.day, hour = back.hour, min = back.min }) - time()
  offset = math.floor(offset / 900 + 0.5) * 900
  return time({ year = f.year, month = f.month, day = f.monthDay, hour = f.hour, min = f.minute }) - offset
end
Ag.FromRealm = fromRealm

-- Did this character say yes (or sign up) in the game's calendar?
local function going(status)
  local E = Enum and Enum.CalendarStatus
  if not E or secret(status) then return false end
  return status == E.Available or status == E.Confirmed or status == E.Signedup or status == E.Tentative
end

-- The guild's events in the game's calendar between from and to. The calendar has the months around the one it
-- shows (C_Calendar.GetMonthInfo(0)); Guild Together never moves it, so a month further away has none (Ag.GameMonths).
local function gameEvents(add, from, to)
  local Cal = ns.Calendar
  if not Cal.On() or not C_Calendar.GetNumDayEvents or not C_Calendar.GetMonthInfo then return end
  Cal.Load()
  local ok, cur = pcall(C_Calendar.GetMonthInfo, 0)
  if not ok or type(cur) ~= "table" or not tonumber(cur.year) or secret(cur.year) then return end
  for offset = -1, 1 do
    local okM, mi = pcall(C_Calendar.GetMonthInfo, offset)
    if okM and type(mi) == "table" and tonumber(mi.numDays) and not secret(mi.numDays) then
      for day = 1, mi.numDays do
        local n = C_Calendar.GetNumDayEvents(offset, day) or 0
        if secret(n) then n = 0 end
        for i = 1, n do
          local e = C_Calendar.GetDayEvent(offset, day, i)
          local kind = type(e) == "table" and e.calendarType
          local seq = type(e) == "table" and e.sequenceType
          if kind and not secret(kind) and GUILD_TYPES[kind] and not secret(seq) and seq ~= "ONGOING" and seq ~= "END"
            and type(e.title) == "string" and not secret(e.title) then
            local at = fromRealm(e.startTime)
            if at and at >= from and at < to then
              local ends = fromRealm(e.endTime)
              local by = type(e.invitedBy) == "string" and not secret(e.invitedBy) and e.invitedBy ~= "" and e.invitedBy or nil
              add({ key = ("gamecal:%d:%s"):format(at, e.title), icon = "tabard", name = e.title, sub = L.CA_GAME_CAL,
                at = at, ends = ends and ends > at and ends or nil, mine = going(e.inviteStatus),
                game = { by = by, kind = kind } })
            end
          end
        end
      end
    end
  end
end

-- The months the game's calendar has events for: { [year * 12 + month] = true }.
function Ag.GameMonths()
  local out = {}
  local Cal = ns.Calendar
  if not Cal.On() or not C_Calendar.GetMonthInfo then return out end
  for offset = -1, 1 do
    local ok, mi = pcall(C_Calendar.GetMonthInfo, offset)
    if ok and type(mi) == "table" and tonumber(mi.year) and not secret(mi.year) then out[mi.year * 12 + mi.month] = true end
  end
  return out
end

-- Every event that starts in from .. to (or is going on then: started before, ends after from), soonest first.
function Ag.List(g, from, to, now)
  now = now or time()
  local list, seen = {}, {}
  local function add(e)
    if not e.at then return end
    -- One that started before from shows while it is still going on (it ends after from, or nobody has ended it).
    if (e.at >= from and e.at < to) or (e.at < from and (e.going or (e.ends and e.ends >= from))) then
      list[#list + 1] = e
      -- (The game's copy of an event Guild Together put into the calendar is not shown twice.)
      seen[ns.Calendar.Short(e.name or "") .. "@" .. math.floor(e.at / 60)] = true
    end
  end
  if g then
    for _, name in ipairs({ "games", "cups", "crown", "raffles", "council", "elect", "tax", "gatherings", "own" }) do
      local ok, err = pcall(SOURCES[name], g, add, now, from, to)
      if not ok then ns:LogError("calendar", name, tostring(err)) end
    end
  end
  local ours = #list
  local ok, err = pcall(gameEvents, function(e)
    if e.at >= from and e.at < to and not seen[ns.Calendar.Short(e.name) .. "@" .. math.floor(e.at / 60)] then
      list[#list + 1] = e
    end
  end, from, to)
  if not ok then ns:LogError("calendar", "game", tostring(err)) end
  Ag.fromGame = #list - ours
  table.sort(list, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.key < b.key
  end)
  return list
end

-- The start of the day t falls in (the computer's clock).
function Ag.DayStart(t)
  local d = date("*t", t)
  return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end
function Ag.NextDay(t)
  local d = date("*t", t)
  return time({ year = d.year, month = d.month, day = d.day + 1, hour = 0 })
end

-- Is the event over (ended, or a deadline passed)?
function Ag.Over(e, now) return not e.going and (e.ends or e.at) < (now or time()) end

-- The red number: the events you take part in that start today and are not over (not deadlines).
function Ag.Today(g, now)
  now = now or time()
  local n = 0
  for _, e in ipairs(Ag.List(g, Ag.DayStart(now), Ag.NextDay(now), now)) do
    if e.mine and not e.due and e.at >= Ag.DayStart(now) and not Ag.Over(e, now) then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- Into the game's calendar (SPEC decision 74): Guild Together's events with a time go into the game's calendar as guild
-- events. The click that makes one puts it in when the maker's rank may make guild events; else it waits, with a red
-- number, for one who may, and one click puts it in. Moving or calling one off changes it there too, by whoever put
-- it in (the game lets its maker change it). Ops:
--   cal_in  { key, at, title }   the author put Guild Together's event key into the game's calendar, at at, as title
--   cal_out { key }              the author took it out again (it was called off)
---------------------------------------------------------------------------
local Cal = ns.Calendar
local function inGame(g) return D.Part(g, "calin") end
-- May this character make guild events? (In the self-test's pretend guild, its rank's power to add calendar events:
-- nothing from it ever reaches the game's calendar, Ag.PutInGame.)
local function mayGuild() if D.sandbox then return D:Can("cal") end return Cal.Guild() end

D:Register("cal_in", {
  allowed = function(_, _, op)
    return type(op.key) == "string" and #op.key <= 80 and tonumber(op.at) ~= nil and type(op.title) == "string"
      and #op.title <= 64
  end,
  apply = function(g, author, op, t)
    local all = inGame(g)
    local cur = all[op.key]
    if cur and cur.t > t then return false end
    all[op.key] = { by = author, at = tonumber(op.at), title = op.title, t = t }
    return true
  end,
  copy = function(g) return g.calin end,
  merge = function(g, part)
    local all = inGame(g)
    for key, x in pairs(type(part) == "table" and part or {}) do
      if type(key) == "string" and type(x) == "table" and party(x.by) and tonumber(x.at) and tonumber(x.t)
        and type(x.title) == "string" and (not all[key] or tonumber(x.t) > all[key].t) then
        all[key] = { by = x.by, at = tonumber(x.at), title = x.title, t = tonumber(x.t), out = tonumber(x.out) }
      end
    end
  end,
})

D:Register("cal_out", {
  allowed = function(_, _, op) return type(op.key) == "string" end,
  apply = function(g, _, op, t)
    local cur = inGame(g)[op.key]
    if not cur or cur.t > t or cur.out then return false end
    cur.out = t
    return true
  end,
})

-- Guild Together's events that go into the game's calendar: { { key, icon, title, desc, at, by (who made it; nil: nobody,
-- the election's days), off (called off), was (put in before decision 74) } }. Titled as the Calendar place names
-- them, so it shows each once.
function Ag.ForGame(g, now)
  now = now or time()
  local out = {}
  if not g then return out end
  local function add(key, icon, title, desc, at, by, off, was)
    if at and title then
      out[#out + 1] = { key = key, icon = icon, title = title, desc = desc or L.CAL_DESC, at = at, by = by, off = off,
        was = was }
    end
  end
  local Gm = ns.Games
  if on("games") then
    for id, ga in pairs(g.games or {}) do
      if ga.kind and ga.h then
        add("game:" .. id, ga.kind, Gm.KindName(ga.kind), L["GM_ABOUT_" .. ga.kind:upper()],
          ga.kind == "santa" and ga.rv or ga.at, ga.h, Gm.State(ga, now) == "off", ga.cal ~= nil)
      end
    end
  end
  if on("challenges") then
    for id, c in pairs(g.cups or {}) do
      if c.h and not c.lead then add("cup:" .. id, "prize", c.name or L.CA_CUP, nil, when(c.when, c.t), c.h, c.st == "cancelled") end
    end
    local lead = ns.Council.Lead(g, now)
    if lead and lead.kind == "crown" and lead.phase == "signup" and lead.cup then
      add("gmcup:" .. lead.id, "throne", L.CA_GM_CUP, nil, lead.cup.t + ns.Council.SIGNUP, lead.mo.a, false)
    end
  end
  if on("gambling") and D:On("tavern:raffles") then
    for id, ra in pairs(g.raffles or {}) do
      if ra.h then add("raffle:" .. id, "ticket", L.CA_DRAW, nil, when(ra.when, ra.t), ra.h, false) end
    end
  end
  for id, e in pairs(g.calendar or {}) do
    if e.by then
      local cur = e.ed or e
      add("own:" .. id, "mail", cur.name, cur.line, cur.at, e.by, e.off ~= nil)
    end
  end
  -- The Guild Master's election: this month's days and next month's.
  local Co = ns.Council
  if Co.Elects(g) then
    local d = date("!*t", now)
    local y, m = d.year, d.month
    for _ = 1, 2 do
      local key = ("%04d-%02d"):format(y, m)
      add("stand:" .. key, "crown", L.CA_STAND, nil, utc(y, m, 1), nil, false)
      add("elect:" .. key, "crown", L.CA_ELECT, nil, utc(y, m, Co.STAND_DAYS + 1), nil, false)
      m = m + 1
      if m > 12 then y, m = y + 1, 1 end
    end
  end
  table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.key < b.key end)
  return out
end

-- What waits for this character: { { e (from Ag.ForGame), what = "add" | "move" | "out", cur (what is in the
-- calendar) } }. To put in: any rank that may make guild events. To move or take out: who put it in.
function Ag.ToGame(g, now)
  now = now or time()
  local list = {}
  if not g or not Cal.On() then return list end
  local guild, me, all = mayGuild(), ns.Self(), g.calin or {}
  for _, e in ipairs(Ag.ForGame(g, now)) do
    local cur = all[e.key]
    if cur and cur.out then cur = nil end
    local mine = cur and cur.by == me
    if e.off then
      if mine and cur.at > now then list[#list + 1] = { e = e, what = "out", cur = cur } end
    elseif e.at > now + 60 and e.at <= now + Ag.AHEAD then
      if not cur and not e.was then
        if guild then list[#list + 1] = { e = e, what = "add" } end
      elseif mine and (cur.at ~= e.at or cur.title ~= Cal.Short(e.title)) then
        list[#list + 1] = { e = e, what = "move", cur = cur }
      end
    end
  end
  return list
end

-- The game's calendar opens our event ahead of the click that moves it (it loads it, then CALENDAR_OPEN_EVENT), so
-- that click can save it at once.
function Ag.Ready(x)
  if not x or x.what ~= "move" or D.sandbox or Ag.opening == x.e.key or Cal.opening then return end
  local day, i = Cal.Find(x.cur.title, x.cur.at)
  if not day then return end
  Ag.opening = x.e.key
  Cal.Open(day, i)
end

local function later(op) C_Timer.After(0, function() ns.Sync:Do(op) end) end

-- Does what x (from Ag.ToGame) waits for, in the game's calendar. Call it from a click only. (The op that says so
-- follows a moment later: never one op in the middle of another.)
function Ag.PutInGame(x)
  local e = x.e
  local title = Cal.Short(e.title)
  -- The pretend guild only says so: the game's calendar is left alone.
  if D.sandbox then
    if x.what == "out" then later({ k = "cal_out", key = e.key })
    elseif mayGuild() then later({ k = "cal_in", key = e.key, at = e.at, title = title }) end
    return true
  end
  local function add()
    local ok, why = Cal.Add({ title = e.title, desc = e.desc, at = e.at, guild = true })
    if not ok then ns:Print(why, true) return false end
    later({ k = "cal_in", key = e.key, at = e.at, title = title })
    ns:Print(L.CAL_PUT:format(title), true)
    return true
  end
  if x.what == "add" then
    if not Cal.Guild() then return false end
    return add()
  elseif x.what == "move" then
    if Cal.opened and Ag.opening == e.key then
      Cal.Move(e.at, e.title)
      Ag.opening = nil
      later({ k = "cal_in", key = e.key, at = e.at, title = title })
      ns:Print(L.CAL_MOVED:format(title), true)
      return true
    end
    local day, i = Cal.Find(x.cur.title, x.cur.at)
    -- Gone from the calendar (taken out by hand): in afresh.
    if not day then return add() end
    Ag.opening = e.key
    Cal.Open(day, i)
    ns:Print(L.CAL_PRESS_AGAIN, true)
    return true
  end
  local day, i = Cal.Find(x.cur.title, x.cur.at)
  if day then Cal.Remove(day, i) end
  later({ k = "cal_out", key = e.key })
  ns:Print(L.CAL_OUT:format(x.cur.title), true)
  return true
end

-- The click that makes, moves or calls off one of ours does the same in the game's calendar (never in the pretend
-- guild or the tour's sample guild, and only from a click: the game needs one).
local GONE = { game_off = "game", cup_cancel = "cup", cal_off = "own" }
ns:On("OP", function(g, a, op, t, n, made)
  if not made or D.sandbox or not ns.db or ns.db.guilds[g.id] ~= g or not Cal.InClick() then return end
  local ok, err = pcall(function()
    local key
    if GONE[op.k] then key = GONE[op.k] .. ":" .. tostring(op.id)
    elseif op.k == "cal_edit" then key = "own:" .. tostring(op.id) end
    local id = ":" .. D.Key(a, n)
    for _, x in ipairs(Ag.ToGame(g, t)) do
      local k = x.e.key
      if (key and k == key and x.what ~= "add") or (not key and x.what == "add" and k:sub(-#id) == id) then
        Ag.PutInGame(x)
      end
    end
  end)
  if not ok then ns:LogError("calendar", "game", tostring(err)) end
end)
