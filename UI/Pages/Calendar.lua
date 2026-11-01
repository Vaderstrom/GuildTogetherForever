-- The Calendar place (SPEC decision 61): every kind of event in one place (Guild/Agenda.lua gathers them). One
-- feature, with a switch at the top of its list: Month (a grid of days, each with a mark per event; a day picked lists
-- its events on the right) or Agenda (the coming events, grouped by day). The switch is kept per character. An event
-- picked shows on the right with where it lives; officers (a rank that may add calendar events) add their own.
-- For the game's calendar (SPEC decision 74): what waits for you to put into the game's calendar, move or take out
-- there, one click each (shown while something waits).
local _, ns = ...
local L, UI, D, Hall = ns.L, ns.UI, ns.GuildData, ns.Hall
local Ag, Gm = ns.Agenda, ns.Games

local AGENDA_DAYS = 60     -- days ahead in the agenda
local AGENDA_SHOWN = 40    -- rows at most
local DAY_MARKS = 3        -- marks in a day of the month
local CELL_H, CELL_GAP = 28, 2

local function g() return D:Current() end
local function view() return ns.char and ns.char.calView == "agenda" and "agenda" or "month" end

-- "Sat 7 Nov"; "20:00".
local function dayName(t)
  local d = date("*t", t)
  return L.CA_DAY:format(L.GM_DAYS[d.wday]:sub(1, 3), d.day, L.GM_MONTHS[d.month]:sub(1, 3))
end
local function longDay(t)
  local d = date("*t", t)
  return L.CA_LONG_DAY:format(L.GM_DAYS[d.wday], d.day, L.GM_MONTHS[d.month])
end
local function clock(t) return date("%H:%M", t) end
-- Today, Tomorrow, or the day.
local function dayLabel(t, now)
  local today = Ag.DayStart(now)
  if t == today then return L.CA_TODAY end
  if t == Ag.NextDay(today) then return L.CA_TOMORROW end
  return dayName(t)
end

-- Where an event lives: its place's name, when that page shows.
local function where(e)
  local pl = e.page and Hall.PLACE_OF[e.page]
  if not pl or not Hall.pages[e.page] or not Hall.pages[e.page].frame then return nil end
  for _, id in ipairs(Hall:Visible()) do if id == e.page then return Hall.PLACE[pl].label end end
  return nil
end

-- Goes to where an event lives (as Home does for what waits).
local function visit(e)
  if e.pick then Hall:ShowFeature(e.page, e.pick) else Hall:Show(e.page) end
  local def = Hall.pages[e.page]
  if Hall.current ~= e.page or not def then return end
  if e.open then e.open(def.frame) Hall:Refresh() end
end

local function sub(e, withDay)
  local when = (withDay and (dayName(Ag.DayStart(e.at)) .. " ") or "") .. clock(e.at)
  return e.sub and e.sub ~= "" and L.CA_SUB:format(when, e.sub) or when
end

local function row(e, page, now, withDay)
  local sel = page.view and page.view.kind == "event" and page.view.key == e.key
  return { icon = UI.ICON[e.icon] or UI.ICON.question, name = e.name, sub = sub(e, withDay), sel = sel,
    value = e.mine and L.CA_YOURS or nil, dim = Ag.Over(e, now),
    onClick = function() page.View({ kind = "event", key = e.key, at = e.at }) end }
end

---------------------------------------------------------------------------
-- The list: the switch, then the month or the agenda
---------------------------------------------------------------------------
local function switch(f, page)
  local s = f:piece("switch", function()
    return UI.Tabs(f.card, f.width, { { "month", L.CA_MONTH }, { "agenda", L.CA_AGENDA } }, function(id)
      if ns.char then ns.char.calView = id end
      page.View(nil)
    end)
  end, "switch")
  s:SetPoint("TOPLEFT", f.pad, f.y)
  s:Select(view())
  f.y = f.y - UI.STRIP_H - 6
end

-- The month shown: page.month = { y, m } (this month at first).
local function shown(page, now)
  if not page.month then
    local d = date("*t", now)
    page.month = { y = d.year, m = d.month }
  end
  return page.month.y, page.month.m
end

local function move(page, by)
  local y, m = page.month.y, page.month.m + by
  if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
  page.month = { y = y, m = m }
  page.View(nil)
end

local function nav(f, page, y, m)
  local n = f:piece("nav", function()
    local fr = CreateFrame("Frame", nil, f.card)
    fr:SetSize(f.width, 22)
    fr.label = UI.Color(UI.Text(fr, "GameFontNormal", "CENTER"), "goldHi")
    fr.label:SetPoint("CENTER")
    local function arrow(text, point, by)
      local b = UI.Button(fr, text, 28, function() move(page, by) end, true)
      b:SetPoint(point)
      return b
    end
    fr.prev, fr.next = arrow("<", "LEFT", -1), arrow(">", "RIGHT", 1)
    return fr
  end, "nav")
  n.label:SetText(L.CA_MONTH_YEAR:format(L.GM_MONTHS[m], y))
  n:SetPoint("TOPLEFT", f.pad, f.y)
  f.y = f.y - 26
end

-- A day of the grid: its number, a mark per event (gold: yours), today ringed, the picked day lit.
local function cell(parent, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, CELL_H)
  local gd = UI.LOOK.gold
  b.bg = UI.Round(b:CreateTexture(nil, "BACKGROUND"), "Glass", { 1, 1, 1, 0.035 })
  b.bg:SetAllPoints()
  UI.Round(b:CreateTexture(nil, "HIGHLIGHT"), "Glass", { gd[1], gd[2], gd[3], 0.12 }):SetAllPoints()
  b.edge = UI.Round(b:CreateTexture(nil, "BORDER"), "Edge", { gd[1], gd[2], gd[3], 0.7 })
  b.edge:SetAllPoints()
  b.num = UI.Text(b, "GameFontHighlightSmall", "CENTER")
  b.num:SetPoint("TOP", 0, -3)
  b.marks = {}
  for i = 1, DAY_MARKS do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(5, 5)
    t:SetTexture(ns.MEDIA .. "Dot")
    t:SetPoint("BOTTOM", (i - (DAY_MARKS + 1) / 2) * 7, 4)
    b.marks[i] = t
  end
  b.more = UI.Color(UI.Text(b, "GameFontDisableSmall"), "sub")
  b.more:SetPoint("BOTTOMRIGHT", -2, 1)
  b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
  return b
end

local function month(f, page, now)
  local y, m = shown(page, now)
  nav(f, page, y, m)
  local first = time({ year = y, month = m, day = 1, hour = 0 })
  local last = time({ year = y, month = m + 1, day = 1, hour = 0 })
  local list = Ag.List(g(), first, last, now)
  -- The events of each day (by its first second), in time order.
  local by = {}
  for _, e in ipairs(list) do
    if e.at >= first then
      local k = Ag.DayStart(e.at)
      by[k] = by[k] or {}
      table.insert(by[k], e)
    end
  end
  local w = math.floor((f.width - 6 * CELL_GAP) / 7)
  -- The days of the week across the top, Monday first.
  for i = 1, 7 do
    local t = f:piece("wd" .. i, function() return UI.Color(UI.Text(f.card, "GameFontDisableSmall", "CENTER"), "sub") end, "wd")
    t:SetWidth(w)
    t:SetText(L.CA_WEEKDAYS[i])
    t:SetPoint("TOPLEFT", f.pad + (i - 1) * (w + CELL_GAP), f.y)
  end
  f.y = f.y - 14
  local lead = (date("*t", first).wday + 5) % 7  -- days before the 1st, in a week that starts on Monday
  local days = date("*t", last - 3600).day
  local today = Ag.DayStart(now)
  local picked = page.view and page.view.kind == "day" and page.view.at
  for d = 1, 42 do
    local c = f:piece("c" .. d, function() return cell(f.card, w) end, "cell")
    local n = d - lead
    local col, r = (d - 1) % 7, math.floor((d - 1) / 7)
    c:SetPoint("TOPLEFT", f.pad + col * (w + CELL_GAP), f.y - r * (CELL_H + CELL_GAP))
    if n < 1 or n > days then
      c:Hide()
    else
      local t = time({ year = y, month = m, day = n, hour = 0 })
      local evs = by[t] or {}
      c.num:SetText(n)
      UI.Color(c.num, t == today and "goldHi" or (t < today and "sub" or "ink"))
      c.edge:SetShown(t == picked)
      c.bg:SetVertexColor(1, 1, 1, t == today and 0.09 or 0.035)
      for i, mark in ipairs(c.marks) do
        local e = evs[i]
        mark:SetShown(e ~= nil)
        if e then
          local col2 = e.mine and UI.LOOK.goldHi or (e.game and UI.LOOK.sub or UI.LOOK.goldLo)
          mark:SetVertexColor(col2[1], col2[2], col2[3], 1)
        end
      end
      c.more:SetText(#evs > DAY_MARKS and "+" or "")
      c.onClick = function() page.View({ kind = "day", at = t, key = "day:" .. t }) end
    end
  end
  f.y = f.y - 6 * (CELL_H + CELL_GAP) - 4
  local Cal = ns.Calendar
  if not Cal.On() then
    f:Text("gameNote", L.CA_GAME_OFF, "GameFontDisableSmall")
  elseif not Ag.GameMonths()[y * 12 + m] then
    f:Text("gameNote", L.CA_GAME_FAR, "GameFontDisableSmall")
  end
end

local function agenda(f, page, now)
  local today = Ag.DayStart(now)
  local list = Ag.List(g(), today, today + (AGENDA_DAYS + 1) * Ag.DAY, now)
  local shownN, day = 0, nil
  -- Going on now first (started, not over yet); then each day from today.
  local going = {}
  for _, e in ipairs(list) do
    if e.at < now and not Ag.Over(e, now) and not e.due then going[#going + 1] = e end
  end
  if #going > 0 then
    f:Strip("now", L.CA_NOW)
    for i, e in ipairs(going) do f:Row("n" .. i, row(e, page, now, true)) end
  end
  for i, e in ipairs(list) do
    if shownN >= AGENDA_SHOWN then break end
    if e.at >= now or (e.due and not Ag.Over(e, now)) then
      local k = Ag.DayStart(e.at)
      if k ~= day then
        day = k
        f:Strip("d" .. k, dayLabel(k, now))
      end
      f:Row("e" .. i, row(e, page, now))
      shownN = shownN + 1
    end
  end
  if shownN == 0 and #going == 0 then
    f:Empty("none", L.CA_NONE, D:Can("cal") and L.CA_NONE_DO:format(UI.Key(L.CA_ADD_DOTS)) or nil)
  end
  if not ns.Calendar.On() then f:Text("gameNote", L.CA_GAME_OFF, "GameFontDisableSmall") end
end

local function events(f, page)
  local now = time()
  switch(f, page)
  if view() == "agenda" then agenda(f, page, now) else month(f, page, now) end
  if D:Can("cal") then return { { L.CA_ADD_DOTS, function() page.View({ kind = "add" }) end } } end
end

---------------------------------------------------------------------------
-- On the right: a day, an event, and adding or changing one
---------------------------------------------------------------------------
local function back(page) return { L.CANCEL, function() page.View(nil) end } end

local function dayView(f, page)
  local now, t = time(), tonumber(page.view.at)
  if not t then return nil end
  local list = Ag.List(g(), t, Ag.NextDay(t), now)
  local n = 0
  for i, e in ipairs(list) do
    if e.at >= t then
      n = n + 1
      f:Row("e" .. i, row(e, page, now))
    end
  end
  if n == 0 then f:Empty("none", L.CA_DAY_NONE) end
  local acts = {}
  if D:Can("cal") and Ag.NextDay(t) > now then
    acts[1] = { L.CA_ADD_DAY, function() page.View({ kind = "add", at = t }) end }
  end
  return acts
end

-- The event picked, found again among those of its day (it may have changed or gone).
local function find(page)
  local v = page.view
  local t = Ag.DayStart(v.at or time())
  for _, e in ipairs(Ag.List(g(), t, Ag.NextDay(t), time())) do
    if e.key == v.key then return e end
  end
  return nil
end

local function eventView(f, page)
  local e = find(page)
  if not e then return nil end
  local now, gd = time(), g()
  f:Row("hero", { icon = UI.ICON[e.icon] or UI.ICON.question, name = e.name, sub = e.sub, sel = true,
    value = e.mine and L.CA_YOURS or nil })
  f:Pair("when", e.due and L.CA_DUE or L.CA_WHEN, longDay(Ag.DayStart(e.at)) .. " " .. clock(e.at))
  if e.ends then
    local same = Ag.DayStart(e.ends) == Ag.DayStart(e.at)
    f:Pair("ends", L.CA_ENDS, same and clock(e.ends) or (dayName(Ag.DayStart(e.ends)) .. " " .. clock(e.ends)))
  elseif e.going then
    f:Pair("ends", L.CA_ENDS, L.CA_UNTIL_CLOSED)
  end
  local place = where(e)
  if place then f:Pair("where", L.CA_WHERE, place) end
  local acts = {}
  if e.own then
    local own = Ag.Own(gd, e.own)
    f:Pair("by", L.CA_BY, UI.Who(own.by))
    if own.line then f:Text("line", own.line) end
    if Ag.MayChange(gd, e.own) then
      acts[#acts + 1] = { L.CA_CHANGE, function() page.View({ kind = "add", id = e.own, key = "change:" .. e.own }) end }
      acts[#acts + 1] = { L.CA_REMOVE, function()
        if Ag.Remove(e.own) then page.View(nil) end
      end }
    end
  elseif e.game then
    if e.game.by then f:Pair("by", L.CA_BY, ns.Display(e.game.by)) end
    f:Text("game", L.CA_GAME_NOTE, "GameFontDisableSmall")
  end
  if Ag.Over(e, now) then f:Text("over", e.due and L.CA_PASSED or L.CA_OVER, "GameFontDisableSmall") end
  if place then acts[#acts + 1] = { L.CA_OPEN:format(place), function() visit(e) end } end
  if #acts < 2 then acts[#acts + 1] = back(page) end
  return acts
end

-- "24 Dec 20:00", for the box (Games.When reads it back).
local function whenText(t)
  local d = date("*t", t)
  return ("%d %s %s"):format(d.day, L.GM_MONTHS[d.month]:sub(1, 3), clock(t))
end

local function addForm(f, page)
  local v, gd = page.view, g()
  local own = v.id and Ag.Own(gd, v.id)
  if v.id and not (own and Ag.MayChange(gd, v.id)) then return nil end
  if not v.id and not D:Can("cal") then return nil end
  -- Put into the game's calendar by you: it opens there now, so Save moves it at once (SPEC decision 74).
  if own then
    local cur = gd.calin and gd.calin["own:" .. v.id]
    if cur and not cur.out and cur.by == ns.Self() then Ag.Ready({ what = "move", e = { key = "own:" .. v.id }, cur = cur }) end
  end
  f:Strip("title", own and L.CA_CHANGE_HEAD or L.CA_ADD_HEAD)
  local w = f.width
  local name = f:Field("name", L.CA_NAME, w - 4)
  name:SetMaxLetters(Ag.NAME_MAX)
  local at = f:Field("at", L.CA_AT, w - 4)
  at:SetMaxLetters(24)
  local line = f:Field("line", L.CA_LINE, w - 4)
  line:SetMaxLetters(Ag.LINE_MAX)
  -- Filled once for each event (or each day picked), so what is typed stays.
  local fill = v.id or ("new:" .. tostring(v.at))
  if name.fill ~= fill then
    name.fill = fill
    name:SetText(own and own.name or "")
    at:SetText(own and whenText(own.at) or (v.at and whenText(v.at + 20 * 3600) or ""))
    line:SetText(own and own.line or "")
  end
  f:Text("hint", L.CA_AT_HINT, "GameFontDisableSmall")
  return { { own and L.CA_SAVE or L.CA_ADD, function()
    local n, l = Ag.Clean(name:GetText(), Ag.NAME_MAX), Ag.Clean(line:GetText(), Ag.LINE_MAX)
    local t = Gm.When(at:GetText())
    if not n or not t or strtrim(at:GetText() or "") == "" then ns:Print(L.CA_BAD, true) return end
    local ok
    if own then ok = Ag.Change(v.id, n, t, l) else ok = Ag.Add(n, t, l) end
    if not ok then ns:Print(L.CA_BAD, true) return end
    name.fill = nil
    local d = date("*t", t)
    page.month = { y = d.year, m = d.month }
    page.View({ kind = "day", at = Ag.DayStart(t), key = "day:" .. Ag.DayStart(t) })
  end }, back(page) }
end

---------------------------------------------------------------------------
-- For the game's calendar
---------------------------------------------------------------------------
local function toGame(f)
  local now, gd = time(), g()
  local list = Ag.ToGame(gd, now)
  for i, x in ipairs(list) do
    local e = x.e
    local when = dayName(Ag.DayStart(e.at)) .. " " .. clock(e.at)
    local why
    if x.what == "add" then why = e.by and L.CA_TG_BY:format(ns.Display(e.by)) or L.CA_TG_GUILD
    elseif x.what == "move" then why = L.CA_TG_MOVED:format(dayName(Ag.DayStart(x.cur.at)) .. " " .. clock(x.cur.at))
    else why = L.CA_TG_OFF end
    f:Row("tg" .. i, { icon = UI.ICON[e.icon] or UI.ICON.mail, name = e.title, sub = L.CA_SUB:format(when, why),
      value = L["CA_TG_" .. x.what:upper()] })
    f:Buttons("tgb" .. i, { { L["CA_TG_DO_" .. x.what:upper()], function()
      Ag.PutInGame(x)
      Hall:Refresh()
    end } })
    -- (The calendar opens an event to move ahead of the click, so one click saves it.)
    if x.what == "move" then Ag.Ready(x) end
  end
  if #list == 0 then f:Empty("tgNone", L.CA_TG_NONE) end
  f:Text("tgNote", L.CA_TG_NOTE, "GameFontDisableSmall")
  return {}
end

local heads = {
  day = function(page)
    return UI.ICON.mail, longDay(page.view.at), L.PAGE_CALENDAR
  end,
  event = function(page)
    local e = find(page)
    return e and UI.ICON[e.icon] or nil, e and e.name or nil, e and dayLabel(Ag.DayStart(e.at), time()) or nil
  end,
  add = function(page)
    return UI.ICON.mail, page.view.id and L.CA_CHANGE_HEAD or L.CA_ADD_HEAD, L.PAGE_CALENDAR
  end,
}

-- The feature's status: how many events this week; its red number: yours that start today.
local status = {
  events = function()
    local now = time()
    local n = 0
    for _, e in ipairs(Ag.List(g(), now, now + 7 * Ag.DAY, now)) do if not e.due then n = n + 1 end end
    return n > 0 and L.CA_WEEK_N:format(n) or L.FEAT_NOTHING
  end,
}
local count = { events = function() return Ag.Today(g()) end, togame = function() return #Ag.ToGame(g()) end }
status.togame = function()
  local n = #Ag.ToGame(g())
  return n == 1 and L.CA_TG_ONE or L.CA_TG_N:format(n)
end

Hall:Register({
  id = "calendar", label = L.PAGE_CALENDAR, sub = L.PAGE_CALENDAR_SUB, help = L.CA_HELP,
  -- What waits for the game's calendar counts on the place (SPEC decision 74).
  todo = function()
    local n = #Ag.ToGame(g())
    return n > 0 and { n == 1 and L.CA_TG_TODO_ONE or L.CA_TG_TODO:format(n) } or {}
  end,
  status = function()
    local n = Ag.Today(g())
    return n > 0 and (UI.Inline(UI.ICON.mail) .. " " .. L.CA_TODAY_N:format(n)) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "events", L.CA_FEAT, icon = UI.ICON.mail },
        { "togame", L.CA_TG_FEAT, icon = UI.ICON.officer, always = true,
          on = function() return #Ag.ToGame(g()) > 0 end } },
      parts = { events = events, togame = toGame },
      views = { day = dayView, event = eventView, add = addForm },
      heads = heads,
      status = status, count = count,
      save = "calendarTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})

-- The game's calendar loads in the background: show its events once they come.
local function listen(event, fn)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
  ns:RegisterEvent(event, fn)
end
listen("CALENDAR_UPDATE_EVENT_LIST", function()
  if Hall.current == "calendar" and Hall:IsOpen() then Hall:Refresh() end
end)
