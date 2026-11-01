-- Journey Together Forever's Gatherings in the guild calendar (SPEC §9.1). Journey offers one read-only door
-- (docs/ARCHITECTURE.md §4e, built in Journey's own repository):
--   JourneyTogetherForeverAPI.Gatherings()  -> { { id, what, at, by, members = { "Name-Realm", ... }, cancelled }, ... }
--                                              the player's fellowship's Gatherings (at: time(); by: the organizer)
--   JourneyTogetherForeverAPI.OnChange(fn)     fn() runs when they change
-- Guild Together writes nothing to Journey. When the player organizes a Gathering and fellowship members are in this
-- guild, one press puts it into the game's calendar as a player event inviting them. A moved or called-off Gathering
-- offers one press to move or remove that event. If the calendar is off, the Games page lists the Gatherings.
local _, ns = ...
local L = ns.L

local Ga = {}
ns.Gatherings = Ga

local function api()
  local a = JourneyTogetherForeverAPI
  return type(a) == "table" and type(a.Gatherings) == "function" and a or nil
end

function Ga.Available() return api() ~= nil end

-- What this account put into the calendar: { [id] = { at, title } }.
local function added()
  ns.db.gathered = type(ns.db.gathered) == "table" and ns.db.gathered or {}
  return ns.db.gathered
end

-- The fellowship's members in this guild (not me).
function Ga.InGuild(x)
  local out, me = {}, ns.Self()
  for _, name in ipairs(type(x.members) == "table" and x.members or {}) do
    if type(name) == "string" and name ~= me and ns.Roster:Rank(name) ~= nil then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- The Gatherings, soonest first, each with st: "new" (not in the calendar), "added", "moved", "cancelled"
-- (added, then called off) and mine (this character organizes it).
function Ga.List()
  local a = api()
  if not a then return {} end
  local ok, list = pcall(a.Gatherings)
  if not ok or type(list) ~= "table" then return {} end
  local out, mine = {}, added()
  for _, x in ipairs(list) do
    if type(x) == "table" and type(x.id) == "string" and tonumber(x.at) and type(x.what) == "string" then
      local e = { id = x.id, what = x.what, at = tonumber(x.at), by = x.by, cancelled = x.cancelled == true,
        members = Ga.InGuild(x), mine = x.by == ns.Self() }
      local was = mine[x.id]
      if was and e.cancelled then e.st = "cancelled"
      elseif was and was.at ~= e.at then e.st = "moved"
      elseif was then e.st = "added"
      elseif not e.cancelled then e.st = "new" end
      if e.st then out[#out + 1] = e end
    end
  end
  table.sort(out, function(p, q) if p.at ~= q.at then return p.at < q.at end return p.id < q.id end)
  return out
end

local function title(e) return e.what end

-- One press (from a click): into the calendar, moved, or removed.
function Ga.Add(e)
  local ok, why = ns.Calendar.Add({ title = title(e), desc = L.GA_DESC, at = e.at, guild = false, invite = e.members })
  if not ok then ns:Print(why, true) return false end
  added()[e.id] = { at = e.at, title = title(e) }
  ns:Print(L.GA_ADDED:format(#e.members), true)
  ns:Fire("GATHERINGS")
  return true
end

-- Moving takes two presses: the first opens the event in the calendar, the second saves the new time.
function Ga.Change(e)
  local was = added()[e.id]
  if not was then return false end
  local Cal = ns.Calendar
  if e.st == "cancelled" then
    local day, i = Cal.Find(was.title, was.at)
    if day then Cal.Remove(day, i) end
    added()[e.id] = nil
    ns:Print(day and L.GA_REMOVED or L.GA_GONE, true)
    ns:Fire("GATHERINGS")
    return true
  end
  if Cal.opened and Ga.opening == e.id then
    Cal.Move(e.at)
    was.at = e.at
    Ga.opening = nil
    ns:Print(L.GA_MOVED, true)
    ns:Fire("GATHERINGS")
    return true
  end
  local day, i = Cal.Find(was.title, was.at)
  if not day then
    -- Not found (removed by hand): add it afresh.
    added()[e.id] = nil
    return Ga.Add(e)
  end
  Ga.opening = e.id
  Cal.Open(day, i)
  ns:Print(L.GA_PRESS_AGAIN, true)
  return true
end

ns:On("LOGIN", function()
  local a = api()
  if a and type(a.OnChange) == "function" then pcall(a.OnChange, function() ns:Fire("GATHERINGS") end) end
end)
ns:On("CALENDAR_READY", function() ns:Fire("GATHERINGS") end)
