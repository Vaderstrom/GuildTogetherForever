-- The game's calendar (SPEC §8 Games, §9.1 Gatherings, decision 74). Guild Together's events with a time go into the
-- game's calendar, and members answer there. Creating an event needs a press (a hardware event), so Cal.Add is only
-- ever called from a button's click, and never in combat.
-- * Guild Together's events (Guild/Agenda.lua): guild sign-up events, by a rank that may make guild events.
-- * A Gathering: a player event inviting the fellowship's members in this guild.
-- The calendar keeps realm time; our times are the computer's clock (time()). Cal.Fields converts.
local _, ns = ...
local L = ns.L

local Cal = { TITLE_MAX = 31, DESC_MAX = 255 }
ns.Calendar = Cal

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Is the game's calendar there? Forever's servers may switch it off (Enum.GameRule.IngameCalendarDisabled).
function Cal.On()
  if not C_Calendar or not C_Calendar.AddEvent then return false end
  local rule = Enum and Enum.GameRule and Enum.GameRule.IngameCalendarDisabled
  if rule and C_GameRules and C_GameRules.IsGameRuleActive then
    local ok, off = pcall(C_GameRules.IsGameRuleActive, rule)
    if ok and off == true then return false end
  end
  return true
end

-- The calendar's realm time for our time at: { year, month, day, hour, min }.
function Cal.Fields(at)
  local offset = 0
  local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
  if type(now) == "table" and not secret(now.year) and tonumber(now.year) then
    local realm = time({ year = now.year, month = now.month, day = now.monthDay, hour = now.hour, min = now.minute })
    if realm then offset = math.floor((realm - time()) / 900 + 0.5) * 900 end
  end
  local d = date("*t", at + offset)
  return { year = d.year, month = d.month, day = d.day, hour = d.hour, min = d.min }
end

-- May this character make guild events? (Guild Control's "Edit guild events".)
function Cal.Guild()
  if not IsInGuild or not IsInGuild() then return false end
  if CanEditGuildEvent then
    local ok, can = pcall(CanEditGuildEvent)
    return ok and can == true
  end
  return false
end

local function short(s, max)
  s = tostring(s or "")
  if #s > max then s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
  return s
end
-- A title as the calendar keeps it (cut to its length).
function Cal.Short(s) return short(s, Cal.TITLE_MAX) end

-- Makes the event: def = { title, desc, at, guild (true: a guild sign-up event when allowed), invite = { names } }.
-- Returns true, or false and why. Call it from a click only.
function Cal.Add(def)
  if not Cal.On() then return false, L.CAL_OFF end
  if InCombatLockdown and InCombatLockdown() then return false, L.CAL_COMBAT end
  if C_Calendar.CanAddEvent and not C_Calendar.CanAddEvent() then return false, L.CAL_CANT end
  local guild = def.guild and Cal.Guild()
  C_Calendar.CloseEvent()
  if guild then C_Calendar.CreateGuildSignUpEvent() else C_Calendar.CreatePlayerEvent() end
  local f = Cal.Fields(def.at)
  C_Calendar.EventSetTitle(short(def.title, Cal.TITLE_MAX))
  C_Calendar.EventSetDescription(short(def.desc, Cal.DESC_MAX))
  if Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other and C_Calendar.EventSetType then
    C_Calendar.EventSetType(Enum.CalendarEventType.Other)
  end
  C_Calendar.EventSetDate(f.month, f.day, f.year)
  C_Calendar.EventSetTime(f.hour, f.min)
  if not guild then
    local me = ns.Self()
    for _, name in ipairs(def.invite or {}) do
      if name ~= me then C_Calendar.EventInvite(Ambiguate(name, "none")) end
    end
  end
  C_Calendar.AddEvent()
  return true, guild and "guild" or "player"
end

---------------------------------------------------------------------------
-- Finding an event we made, to move or remove it (a Gathering that moved or was called off)
---------------------------------------------------------------------------
-- The day and index of our event titled title at time at, in the month the calendar shows for it; nil if not found.
-- (Ours: we made it, or may change it as the guild's events' moderator.)
local MINE = { CREATOR = true, MODERATOR = true }
function Cal.Find(title, at)
  if not Cal.On() or not C_Calendar.GetNumDayEvents then return nil end
  local f = Cal.Fields(at)
  C_Calendar.SetAbsMonth(f.month, f.year)
  title = short(title, Cal.TITLE_MAX)
  for i = 1, C_Calendar.GetNumDayEvents(0, f.day) or 0 do
    local e = C_Calendar.GetDayEvent(0, f.day, i)
    if type(e) == "table" and e.title == title and (e.modStatus == nil or MINE[e.modStatus]) then return f.day, i end
  end
  return nil
end

-- Is a click of the player's running now (a button's OnClick)? Making or changing an event needs one.
function Cal.InClick()
  if not GetMouseButtonClicked then return false end
  local b = GetMouseButtonClicked()
  return type(b) == "string" and b ~= ""
end

-- Opens our event so a second press can change it (the calendar loads it, then CALENDAR_OPEN_EVENT).
function Cal.Open(day, i)
  Cal.opened = nil
  Cal.opening = { day = day, i = i }
  C_Calendar.OpenEvent(0, day, i)
end

ns:RegisterEvent("CALENDAR_OPEN_EVENT", function()
  if Cal.opening then
    Cal.opened, Cal.opening = Cal.opening, nil
    ns:Fire("CALENDAR_READY")
  end
end)

-- With the event open (Cal.opened): moves it to at (and names it title, when given). Call it from a click only.
function Cal.Move(at, title)
  if not Cal.opened then return false end
  Cal.opened = nil
  local f = Cal.Fields(at)
  if title then C_Calendar.EventSetTitle(short(title, Cal.TITLE_MAX)) end
  C_Calendar.EventSetDate(f.month, f.day, f.year)
  C_Calendar.EventSetTime(f.hour, f.min)
  C_Calendar.UpdateEvent()
  C_Calendar.CloseEvent()
  return true
end

-- Removes our event (day and index from Cal.Find). Call it from a click only.
function Cal.Remove(day, i)
  if not C_Calendar.ContextMenuSelectEvent or not C_Calendar.ContextMenuEventRemove then return false end
  C_Calendar.ContextMenuSelectEvent(0, day, i)
  C_Calendar.ContextMenuEventRemove()
  return true
end

-- The calendar's data loads in the background: ask for it once the guild window shows our Games page.
function Cal.Load()
  if Cal.On() and C_Calendar.OpenCalendar and not Cal.loaded then
    Cal.loaded = true
    C_Calendar.OpenCalendar()
  end
end
