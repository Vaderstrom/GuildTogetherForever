-- Real characters in the scenes (SPEC decisions 60 and 63, as Journey Together's UI/Models.lua does): WoW draws a
-- player only from a unit the game has for them: yourself always, a guildmate in your group, your target or focus,
-- the one under the mouse, or a friendly nameplate. There is no stand-in body: retail cannot dress a race's model as
-- another player (no SetCustomRace; Journey's probes and our self-test, 31 Oct 2026), so nothing about a player's look
-- is shared. Instead each guildmate's model is loaded the first time the game has them near and kept for the rest of
-- the session (until /reload or logout): one for the panel's scenes, one for the alert line's and one for a moment over
-- the guild chat (SPEC decision 76). A guildmate not seen yet shows as their class crest (UI/Stage.lua). When each was
-- last near you is kept (GuildTogetherForeverDB.near).
local _, ns = ...
local Lk = { frames = { panel = {}, toast = {}, chat = {} }, TICK = 10, NEAR = { "target", "focus", "mouseover" },
  FRESH = 300 }   -- seconds before a kept model is loaded again from the unit (new gear), when it is not on a stage
ns.Looks = Lk

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A unit the game has for this character now (us, our group, the target, focus, the mouse, a name plate), or nil.
function Lk.Unit(name)
  if type(name) ~= "string" then return nil end
  if name == ns.Self() then return "player" end
  if not UnitExists or not UnitIsPlayer then return nil end
  local function is(unit)
    if not UnitExists(unit) then return false end
    local p = UnitIsPlayer(unit)
    if secret(p) or not p then return false end
    local n, realm = UnitName(unit)
    if not n or secret(n) or secret(realm) then return false end
    return ns.FullName(realm and realm ~= "" and (n .. "-" .. realm) or n) == name
  end
  local group, n = IsInRaid and IsInRaid() and "raid" or "party", GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, n do if is(group .. i) then return group .. i end end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local u = plate.namePlateUnitToken
      if u and is(u) then return u end
    end
  end
  for _, u in ipairs(Lk.NEAR) do if is(u) then return u end end
  return nil
end

-- Can the game draw this unit now: online and in sight?
local function drawable(unit)
  if unit == "player" then return true end
  local seen = UnitIsVisible and UnitIsVisible(unit)
  local online = UnitIsConnected and UnitIsConnected(unit)
  if secret(seen) or secret(online) then return false end
  return (seen and online) and true or false
end

function Lk.DrawableUnit(name)
  local unit = Lk.Unit(name)
  return unit and drawable(unit) and unit or nil
end

-- Face to face (SPEC decision 72): is this character near you now, shown to you by the game: in your group and in
-- sight, your target or focus, or on a name plate? (Not the one under the mouse: it is gone by the time you click a
-- button.) You are always near yourself. The self-test's pretend guild and the tests say for theirs: Lk.pretend[name].
Lk.SHOWN = { "target", "focus" }
function Lk.Near(name)
  if type(name) ~= "string" then return false end
  if name == ns.Self() then return true end
  if Lk.pretend then
    local v = Lk.pretend[name]
    if v ~= nil then return v == true end
  end
  if not UnitExists or not UnitIsPlayer then return false end
  local function is(unit)
    if not UnitExists(unit) then return false end
    local p = UnitIsPlayer(unit)
    if secret(p) or not p then return false end
    local n, realm = UnitName(unit)
    if not n or secret(n) or secret(realm) then return false end
    return ns.FullName(realm and realm ~= "" and (n .. "-" .. realm) or n) == name and drawable(unit)
  end
  for _, u in ipairs(Lk.SHOWN) do if is(u) then return true end end
  local group, n = IsInRaid and IsInRaid() and "raid" or "party", GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, n do if is(group .. i) then return true end end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local u = plate.namePlateUnitToken
      if u and is(u) then return true end
    end
  end
  return false
end

-- Is any of these characters near you?
function Lk.NearAny(...)
  for i = 1, select("#", ...) do if Lk.Near((select(i, ...))) then return true end end
  return false
end

-- Before a game's step that needs you face to face with one of these: true, or it says in chat who to go near.
function Lk.Need(...)
  if Lk.NearAny(...) then return true end
  ns:Print(ns.L.NEAR_NEED:format(ns.Display((select(1, ...)))), true)
  return false
end

-- Who is near now, as a string to compare: the pages draw again when it changes ("NEAR").
local function nearKey()
  local list = {}
  local function add(unit)
    if not UnitExists or not UnitExists(unit) then return end
    local n, realm = UnitName(unit)
    if n and not secret(n) and not secret(realm) and drawable(unit) then list[#list + 1] = n .. "-" .. (realm or "") end
  end
  for _, u in ipairs(Lk.SHOWN) do add(u) end
  local group, n = IsInRaid and IsInRaid() and "raid" or "party", GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, n do add(group .. i) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      if plate.namePlateUnitToken then add(plate.namePlateUnitToken) end
    end
  end
  table.sort(list)
  return table.concat(list, ",")
end
function Lk:CheckNear()
  local k = nearKey()
  if k ~= self.nearNow then
    self.nearNow = k
    ns:Fire("NEAR")
  end
end

-- When a guildmate was last near you (drawn by the game), or nil. Kept across sessions, for the account.
function Lk:LastNear(name) return ns.db and type(ns.db.near) == "table" and ns.db.near[name] or nil end

local function near(name)
  if name == ns.Self() or not ns.db then return end
  ns.db.near = type(ns.db.near) == "table" and ns.db.near or {}
  ns.db.near[name] = time()
end

-- The kept model of a player for a kind of stage ("panel", "toast" or "chat"), loaded now when the game has them near;
-- nil when there is none (never near this session, or in combat with none made yet). UI/Stage.lua sets Lk.onNew to
-- frame a new one.
function Lk:Model(name, kind)
  local list = self.frames[kind or "panel"]
  if not list or type(name) ~= "string" then return nil end
  local m = list[name]
  local unit = self.DrawableUnit(name)
  if not m then
    if not unit or InCombatLockdown() then return nil end
    m = CreateFrame("PlayerModel", nil, UIParent)
    m:Hide()
    m.isModel, m.name = true, name
    if self.onNew then self.onNew(m) end
    list[name] = m
  end
  -- (Not again while it plays on a stage: that would start its move over.)
  if unit and (not m.loaded or (not m:IsShown() and time() - (m.at or 0) > self.FRESH)) then
    m:SetUnit(unit)
    m.loaded, m.at = true, time()
    near(name)
  end
  return m.loaded and m or nil
end

-- The guildmates the game has near now get their models, for every kind of stage (out of combat: frames are made).
function Lk:Seen()
  if InCombatLockdown() or not ns.Roster or not ns.Roster:Ready() then return 0 end
  local all, n = ns.Roster:All(), 0
  local function try(name)
    if name and all[name] and not (self.frames.panel[name] and self.frames.panel[name].loaded) then
      if self:Model(name, "panel") then n = n + 1 end
      self:Model(name, "toast")
      self:Model(name, "chat")
    end
  end
  try(ns.Self())
  local function nameOf(unit)
    if not UnitExists or not UnitExists(unit) then return nil end
    local n2, realm = UnitName(unit)
    if not n2 or secret(n2) or secret(realm) then return nil end
    return ns.FullName(realm and realm ~= "" and (n2 .. "-" .. realm) or n2)
  end
  local group, count = IsInRaid and IsInRaid() and "raid" or "party", GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, count do try(nameOf(group .. i)) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      if plate.namePlateUnitToken then try(nameOf(plate.namePlateUnitToken)) end
    end
  end
  for _, u in ipairs(self.NEAR) do try(nameOf(u)) end
  return n
end

-- Looked for when the game shows someone new (at most once a second), and every TICK seconds.
local function soon()
  if Lk.waiting or not C_Timer then return end
  Lk.waiting = true
  C_Timer.After(1, function()
    Lk.waiting = nil
    Lk:Seen()
    Lk:CheckNear()
  end)
end
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE" }) do
  if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
    ns:RegisterEvent(event, soon)
  end
end
ns:On("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Lk.TICK, function() Lk:Seen() Lk:CheckNear() end) end
  soon()
end)
