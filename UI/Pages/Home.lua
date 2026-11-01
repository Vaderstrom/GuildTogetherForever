-- Home (SPEC decisions 48, 57, docs/mockup/BigScreen.html): the first place along the top. Its features: Waiting for
-- you (each page's def.todo, with the welcome for a new member above it, SPEC decision 52), Going on now (each page's
-- def.now, newest first, then Start something: the big actions, each for those who may) and your options (last, after
-- the guild's story from UI/Pages/Chronicle.lua). A click goes to the place where it is.
local _, ns = ...
local L, UI, D, Hall = ns.L, ns.UI, ns.GuildData, ns.Hall

-- Goes to a page, and there to its feature (pick), what to show beside the window (page.View), or what open(page)
-- picks.
local function go(id, pick, view, open)
  -- With no feature named: the first of the page's features where something waits (its red number).
  local spec = not pick and Hall.pages[id] and Hall.pages[id].frame and Hall.pages[id].frame.split
  for _, t in ipairs(spec and spec.tabs or {}) do
    local n = spec.count and spec.count[t[1]]
    local ok, waits = pcall(n or function() return 0 end, Hall.pages[id].frame)
    if not pick and ok and (waits or 0) > 0 then pick = t[1] end
  end
  if pick then Hall:ShowFeature(id, pick) else Hall:Show(id) end
  local def = Hall.pages[id]
  if Hall.current ~= id or not def then return end
  if view and def.frame.View then def.frame.View(view) end
  if open then open(def.frame); Hall:Refresh() end
end

local function placeIcon(id) return Hall.PLACE[Hall.PLACE_OF[id]].icon end

-- What is going on now, from every page that is on (def.now): { { icon, name, sub, t, page, pick, view, open }, ...
-- }, newest first.
local function goingOn()
  local list = {}
  for _, id in ipairs(Hall:Visible()) do
    local def = Hall.pages[id]
    if def.now then
      local ok, rows = pcall(def.now)
      if not ok then ns:LogError("now", id, tostring(rows))
      elseif type(rows) == "table" then
        for _, r in ipairs(rows) do r.page = id; list[#list + 1] = r end
      end
    end
  end
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return list
end

-- Getting started (SPEC decisions 52 and 72): setup steps only, each ticking itself when done. A member accepts the
-- guild's rules and sets their options; the Guild Master picks the guild's setup, names the Marks, sets the tax (or
-- turns it off), says who may do what, and turns features on or off (each Guild settings feature looked at counts:
-- Settings marks it, ns.db.welcome["set:<feature>"]). Show me around starts the tour (UI/Tour.lua). The card goes
-- when all are done or it is hidden. Account-wide (ns.db.welcome): one player is one player.
local function welcomeSteps()
  local g = D:Current()
  if not g then return {} end
  local w = ns.db.welcome or {}
  local steps = {}
  local function add(id, icon, done, place, feat)
    steps[#steps + 1] = { id = id, icon = icon, name = L["WELCOME_" .. id:upper()], sub = L["WELCOME_" .. id:upper() .. "_SUB"],
      done = done, go = function() go(place, feat) end }
  end
  if D:InCharge() then
    local s = D:Settings()
    add("setup", UI.ICON.crown, ns.Rules.Setup(g) ~= nil, "settings", "setup")
    add("marks", UI.ICON.marks, w["set:general"] == true, "settings", "general")
    add("tax", UI.ICON.purse, w["set:tax"] == true or (s.tax and s.tax.on) == true, "settings", "tax")
    add("who", UI.ICON.officer, w["set:who"] == true, "settings", "who")
    add("features", UI.ICON.pl_manage, w["set:features"] == true, "settings", "features")
    return steps
  end
  if D:On("council:charter") and g.charter then
    add("rules", UI.ICON.scroll, ns.Council.Accepted(g, ns.Players:Of(ns.Self(), g)), "council", "charter")
  end
  add("options", UI.ICON.options, w.options == true, "home", "options")
  return steps
end

-- A Guild settings feature or your options looked at, for Getting started (not in the pretend guild).
function ns.Welcomed(id)
  if not ns.db or D.sandbox then return end
  ns.db.welcome = type(ns.db.welcome) == "table" and ns.db.welcome or {}
  ns.db.welcome[id] = true
end

local function welcome(f)
  local w = ns.db.welcome or {}
  if w.hidden then return end
  local steps, n = welcomeSteps(), 0
  for _, s in ipairs(steps) do if s.done then n = n + 1 end end
  if #steps == 0 or n == #steps then return end
  f:Strip("welHead", L.WELCOME_TITLE, ("%d/%d"):format(n, #steps))
  for i, s in ipairs(steps) do
    f:Row("wel" .. i, { icon = s.icon, name = s.name, sub = s.sub, dim = s.done, value = s.done and L.WELCOME_DONE or nil,
      onClick = function() s.go() end })
  end
  f:Buttons("welHide", { { L.TOUR_AGAIN, function() ns.Tour:Start() end }, { L.WELCOME_HIDE, function()
    ns.db.welcome = ns.db.welcome or {}
    ns.db.welcome.hidden = true
    Hall:Refresh()
  end } })
end

-- Waiting for you: one row a thing, under the place where it waits.
local function waitingList()
  local list = {}
  for _, id in ipairs(Hall:Visible()) do
    for _, line in ipairs(Hall:Todo(id)) do list[#list + 1] = { id = id, line = line } end
  end
  return list
end

local function waiting(f)
  local list = waitingList()
  for i, w in ipairs(list) do
    f:Row("w" .. i, { icon = placeIcon(w.id), name = w.line, sub = Hall.PLACE[Hall.PLACE_OF[w.id]].label,
      onClick = function() go(w.id) end })
  end
  if #list == 0 then f:Empty("noWait", L.HOME_NOTHING) end
end

-- The big actions: each only to those who may, and only while its place is on.
local function actions()
  local list = {}
  local function add(place, page, icon, name, sub, pick, view)
    if D:PlaceOn(place) and Hall.pages[page] then
      list[#list + 1] = { icon = icon, name = name, sub = sub, onClick = function() go(page, pick, view) end }
    end
  end
  add("challenges", "arena", UI.ICON.duel, L.HOME_DUEL, L.HOME_DUEL_SUB, "duels")
  add("gambling", "tavern", UI.ICON.skull, L.HOME_DEATHROLL, L.HOME_DEATHROLL_SUB, "deathroll")
  if D:Can("poll") then add("council", "council", UI.ICON.ballot, L.HOME_POLL, L.HOME_POLL_SUB, "votes", "poll") end
  local punish = false
  for _, pun in ipairs(D.PUNISHMENTS) do if D:Can(pun) then punish = true end end
  if punish then
    add("punishments", "stocks", UI.ICON.shackles, L.HOME_PUNISH, L.HOME_PUNISH_SUB, "serving", { kind = "form" })
  end
  return list
end

-- Going on now: everything, newest first; then Start something.
local function now(f)
  local list = goingOn()
  for i, r in ipairs(list) do
    f:Row("n" .. i, { icon = r.icon or placeIcon(r.page), name = r.name, sub = r.sub, value = r.value,
      onClick = function() go(r.page, r.pick, r.view, r.open) end })
  end
  if #list == 0 then f:Empty("noNow", L.HOME_QUIET, L.HOME_QUIET_DO) end
  local acts = actions()
  if #acts > 0 then f:Strip("actHead", L.HOME_START) end
  for i, a in ipairs(acts) do f:Row("a" .. i, a) end
end

local function count(n, one, many, none) return n == 0 and none or (n == 1 and one or many:format(n)) end

Hall:Register({
  id = "home", label = L.PAGE_HOME, sub = L.PAGE_HOME_SUB,
  -- (No glance: Home's lists are the guild at a glance already.)
  noGlance = true,
  -- Your options: a picture of your screen with the alert line where and how big you picked.
  side = function(page)
    if page.part ~= "options" then return nil end
    return { key = "opt:screen", icon = UI.ICON.options, title = L.OPT_PREVIEW, sub = L.OPT_PREVIEW_SUB,
      draw = function(f) ns.Alerts:Preview(f) end }
  end,
  help = L.HOME_HELP,
  -- Who wears the crown, when the Challenges are on.
  status = function()
    local arena = Hall.pages.arena
    return D:PlaceOn("challenges") and arena and arena.status and arena.status() or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "waiting", L.HOME_WAITING, icon = UI.ICON.welcome, always = true },
        { "now", L.HOME_NOW, icon = UI.ICON.seasons, always = true },
        { "options", L.OPT_TITLE, icon = UI.ICON.options, always = true, last = true } },
      parts = { waiting = waiting, now = now, options = function(f) return ns.Card.DrawOptions(f) end },
      -- The welcome, above what waits for you.
      lead = welcome, leadFor = { waiting = true },
      status = {
        waiting = function()
          return count(#waitingList(), L.HOME_WAITING_ONE, L.HOME_WAITING_N, L.HOME_WAITING_NONE)
        end,
        now = function()
          return count(#goingOn(), L.HOME_NOW_ONE, L.HOME_NOW_N, L.HOME_NOW_NONE)
        end,
        options = function() return L.OPT_ROW_SUB end,
      },
      count = { waiting = function() return #waitingList() end },
      save = "homeTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})
