-- Guild Together in the game's guild window (SPEC §2, SPEC decision 59, docs/mockup/Frame.html, CLAUDE.md "The guild window").
-- * The bar, joined under the window on every tab of it while it shows our guild: Guild Together and how many things wait
--   for you, then the places (Home, PvP Challenges, Games, Gambling, Treasury, Professions, Punishments, Council and,
--   for the Guild Master, Guild settings), each a medallion with its name and its red number (SPEC decision 47).
-- * The panel, under the bar while a place is open: the place's painting and name; its features on the left, each with
--   a status and a red number (Hall:Features); the picked feature's list in the middle (the page's pane, Hall:Split);
--   what a row opens on the right (UI/Side.lua, Hall:ViewSide). A feature may sit in another place than its page.
-- * The window is moved to the middle and scaled so the column fits the screen, inside one frame (UI/Frame.lua, SPEC
--   decision 58). With Dress the guild window off, the panel opens beside the window instead, and narrower.
-- * The bar and the panel are our own frames, children of the window, so they hide and scale with it. Blizzard's
--   frames are only read, moved and dressed (UI/Frame.lua); SetDisplayMode and ShowUIPanel are never called (that
--   taints the window and breaks guild notes).
-- * Frames are made out of combat only: all of them when the guild window's code loads (or after combat).
local _, ns = ...
local L, UI = ns.L, ns.UI
local Hall = { pages = {}, order = {} }
ns.Hall = Hall

-- The bar (its height is UI/Frame.lua's BAR_H): the Guild Together block on its left, then the places' medallions.
Hall.ME_W, Hall.BAR_ICON, Hall.ME_CREST = 124, 36, 34
-- The panel: its header (with the place's medallion), then the features in a column on the left (RAIL_W; each
-- FEAT_H high with a FEAT_ICON medallion) or, in a panel narrower than CHIPS_AT, as chips along its top (CHIPS_H).
-- The body is padded by PAD; the list takes LIST_FR of it, what you picked the rest after GAP.
Hall.HEAD_H, Hall.CREST = 50, 36
Hall.RAIL_W, Hall.FEAT_H, Hall.FEAT_ICON = 170, 42, 30
Hall.CHIPS_H, Hall.CHIPS_AT, Hall.CHIP_H = 60, 700, 26
Hall.PAD, Hall.GAP, Hall.LIST_FR = 8, 6, 0.44
Hall.LIST_W = 273  -- the list's width (Hall:Geometry sets it when the frames are made)
-- The places in the bar, and the pages each holds. The Guild Master can switch off the places in
-- ns.GuildData.PLACES; Home, the Council (impeachment is always there) and Manage stay.
-- (Page ids stay as they were built: home is Waiting for you, Going on now and your options, arena the duels and the
-- crown, tavern the dice (Gambling), games the events, stocks the punishments, chronicle the guild's story, settings
-- Guild settings.)
Hall.PLACES = {
  { id = "home", label = L.PLACE_HOME, icon = UI.ICON.pl_home, pages = { "home", "chronicle" } },
  { id = "challenges", label = L.PLACE_CHALLENGES, icon = UI.ICON.pl_challenges, pages = { "arena" } },
  { id = "games", label = L.PLACE_GAMES, icon = UI.ICON.pl_games, pages = { "games" } },
  { id = "gambling", label = L.PLACE_GAMBLING, icon = UI.ICON.pl_gambling, pages = { "tavern" } },
  { id = "treasury", label = L.PLACE_TREASURY, icon = UI.ICON.pl_treasury, pages = { "treasury" } },
  { id = "professions", label = L.PLACE_PROFESSIONS, icon = UI.ICON.pl_professions, pages = { "professions" } },
  { id = "punishments", label = L.PLACE_PUNISHMENTS, icon = UI.ICON.pl_punishments, pages = { "stocks" } },
  { id = "council", label = L.PLACE_COUNCIL, icon = UI.ICON.pl_council, pages = { "council" } },
  { id = "calendar", label = L.PLACE_CALENDAR, icon = UI.ICON.pl_calendar, pages = { "calendar" } },
  { id = "manage", label = L.PLACE_MANAGE, icon = UI.ICON.pl_manage, pages = { "settings" }, gear = true },
}
Hall.PLACE_OF, Hall.PLACE = {}, {}
for _, pl in ipairs(Hall.PLACES) do
  Hall.PLACE[pl.id] = pl
  for _, id in ipairs(pl.pages) do Hall.PLACE_OF[id] = pl.id end
end

---------------------------------------------------------------------------
-- Pages: Hall:Register{ id, label, sub, build = function(page), refresh = function(page) }.
-- build gets page.body (Hall:BodySize() big: the panel's middle and right) once, when the frames are made; refresh runs
-- each time it shows.
---------------------------------------------------------------------------
function Hall:Register(def)
  if not self.pages[def.id] then self.order[#self.order + 1] = def.id end
  self.pages[def.id] = def
end

function Hall:BodySize()
  local g = self.G or self:Geometry()
  return g.bodyW, g.bodyH
end

-- Panes side by side across the body (UI.Pane): Hall:Panes(page, top, { Hall.LIST_W, opts }, { 0, opts }) -> pane1,
-- pane2. A width of 0 takes what is left; top: room kept above them.
function Hall:Panes(page, top, ...)
  local w, h = self:BodySize()
  local gap, fixed, n = 6, 0, select("#", ...)
  for i = 1, n do fixed = fixed + (select(i, ...)[1] or 0) end
  local x, panes = 0, {}
  for i = 1, n do
    local spec = select(i, ...)
    local pw = spec[1] > 0 and spec[1] or (w - fixed - gap * (n - 1))
    local p = UI.Pane(page.body, pw, h - (top or 0), spec[2])
    p:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -(top or 0))
    x = x + pw + gap
    panes[i] = p
  end
  return unpack(panes)
end

-- A page of features (SPEC decisions 48, 59): Hall draws the features in the panel's left column; the page has one
-- pane in the middle for the picked feature's list. spec = {
--   tabs = { { id, label, icon = ..., place = ... }, ... }  the features (place: when it sits in another place; the
--                                                         label may be a function, for a name that changes; on: a
--                                                         function, false hides it while it has nothing to do;
--                                                         always: the Guild Master cannot switch it off; last:
--                                                         after the place's other features),
--   parts = { [id] = fn(flow, page) -> actions, note },     each feature's list, with the pane's actions,
--   lead = fn(flow, page) -> actions, note,                 drawn above the list of the first feature (leadFor: which),
--   status = { [id] = fn(page) -> "a few words" },           under the feature's name on the left,
--   count = { [id] = fn(page) -> n },                        its red number,
--   views = { [kind] = fn(flow, page) -> actions },          what a row opens: in the panel's right column,
--   heads = { [kind] = fn(page) -> icon, title, sub },       its heading there (else the feature's),
--   save = key in ns.char for the feature,
--   own = true: no list; the page shows each feature in frames of its own across the middle and right (Guild
--                settings) }.
-- A view returns nil when it is gone. Actions: { { label, onClick, next = true }, ... }.
function Hall:Split(page, spec)
  page.split = spec
  local _, h = self:BodySize()
  if not spec.own then
    page.right = UI.Pane(page.body, self.LIST_W, h, { foot = true })
    page.right:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, 0)
    page.leadFlow, page.rightFlow = UI.PaneFlow(page.right), UI.PaneFlow(page.right)
  end
  page.parts = {}
  local known = {}
  for i, t in ipairs(spec.tabs) do page.parts[i], known[t[1]] = t[1], true end
  -- (A row picked puts away a card opened over the page, UI/Card.lua.)
  local function pick(id)
    if id ~= page.part and page.right then page.right.scroll:SetVerticalScroll(0) end
    page.part, page.view = id, nil
    ns.Side.over = nil
    if ns.char then ns.char[spec.save] = id end
  end
  page.View = function(view)
    page.view = view
    ns.Side.over = nil
    Hall:Refresh()
  end
  page.Pick = function(id) pick(id) Hall:Refresh() end
  page.PickQuiet = pick
  local saved = ns.char and ns.char[spec.save]
  pick(known[saved] and saved or page.parts[1])
end

function Hall:DrawRight(page)
  local spec, lf, f = page.split, page.leadFlow, page.rightFlow
  local foot, note = {}, nil
  lf:Begin()
  local leadFor = spec.leadFor or { [spec.tabs[1][1] ] = true }
  if spec.lead and leadFor[page.part] then
    local list
    list, note = spec.lead(lf, page)
    for _, b in ipairs(list or {}) do foot[#foot + 1] = b end
  end
  lf:End()
  f.top = lf.y
  f:Begin()
  local list, partNote = spec.parts[page.part](f, page)
  for _, b in ipairs(list or {}) do foot[#foot + 1] = b end
  UI.Foot(page.right, foot, note or partNote)
  return f:End()
end

-- A feature's name (its tab's label, or what the label function says now).
function Hall.Label(t) return type(t[2]) == "function" and t[2]() or t[2] end

-- A feature shows (SPEC decision 52): the Guild Master has not switched it off ("page:feature" in Manage), and it has
-- something to do (t.on).
function Hall.FeatureOn(pid, t)
  if t.on and not t.on() then return false end
  return t.always or ns.GuildData:On(pid .. ":" .. t[1])
end

-- The features of a place, in order: { { page, id, label, icon, place }, ... } (of the places that are on; those marked
-- last after the others).
function Hall:Features(place)
  local list, after = {}, {}
  if not ns.GuildData:PlaceOn(place) and place ~= "council" and place ~= "home" then return list end
  -- The place's own pages in their order (Home's before the guild's story), then any other page's.
  local order = {}
  for _, pid in ipairs(self.PLACE[place] and self.PLACE[place].pages or {}) do
    if self.pages[pid] then order[#order + 1] = pid end
  end
  for _, pid in ipairs(self.order) do if self.PLACE_OF[pid] ~= place then order[#order + 1] = pid end end
  for _, pid in ipairs(order) do
    local def = self.pages[pid]
    local spec = def.frame and def.frame.split
    local home = self.PLACE_OF[pid]
    if spec and (home ~= "manage" or ns.GuildData:InCharge()) then
      for _, t in ipairs(spec.tabs) do
        local at = t.place or home
        if at == place and (home == place or ns.GuildData:PlaceOn(home) or not t.place) and Hall.FeatureOn(pid, t) then
          local into = t.last and after or list
          into[#into + 1] = { page = pid, id = t[1], label = Hall.Label(t), icon = t.icon or self.PLACE[at].icon,
            place = at }
        end
      end
    end
  end
  for _, x in ipairs(after) do list[#list + 1] = x end
  return list
end

-- Every feature of a place the Guild Master can switch off (Manage): { { key = "page:feature", label = fn }, ... }.
function Hall:Switches(place)
  local list = {}
  for _, pid in ipairs(self.order) do
    local def = self.pages[pid]
    local spec = def.frame and def.frame.split
    local home = self.PLACE_OF[pid]
    for _, t in ipairs(spec and home ~= "manage" and spec.tabs or {}) do
      if (t.place or home) == place and not t.always then
        list[#list + 1] = { key = pid .. ":" .. t[1], label = function() return Hall.Label(t) end }
      end
    end
  end
  return list
end

-- The feature a page shows now (its part), and the place it sits in.
function Hall:Feature(pid)
  local def = self.pages[pid]
  local page = def and def.frame
  local spec = page and page.split
  if not spec then return nil end
  for _, t in ipairs(spec.tabs) do
    if t[1] == page.part then
      return { page = pid, id = t[1], label = Hall.Label(t), icon = t.icon, place = t.place or self.PLACE_OF[pid],
        on = Hall.FeatureOn(pid, t) }
    end
  end
end

-- Shows a feature: its page, with the feature picked, in the panel (opened if it was closed).
function Hall:ShowFeature(pid, fid)
  local def = self.pages[pid]
  if def and def.frame and def.frame.split then def.frame.PickQuiet(fid) end
  if not self:IsOpen() then return self:Open(pid) end
  return self:Show(pid)
end

-- A feature's status (its few words) and its red number, as the page tells them now.
function Hall:FeatureState(pid, fid)
  local page = self.pages[pid].frame
  local spec = page.split
  local status = spec.status and spec.status[fid]
  local count = spec.count and spec.count[fid]
  local ok, sub = true, nil
  if status then ok, sub = pcall(status, page) end
  local okN, n = true, 0
  if count then okN, n = pcall(count, page) end
  return ok and sub or nil, okN and n or 0
end

-- What a row opened (page.view), for the panel's right column: { key, icon, title, sub, draw, view = page }.
function Hall:ViewSide(def)
  local page = def.frame
  local spec, view = page and page.split, page and page.view
  local fn = spec and spec.views and view and spec.views[view.kind]
  if not fn then return nil end
  local feat = self:Feature(def.id)
  local key = view.key or view.id or view.rid or view.name or ""
  local icon, title, sub
  if spec.heads and spec.heads[view.kind] then icon, title, sub = spec.heads[view.kind](page) end
  return { key = "view:" .. def.id .. ":" .. view.kind .. ":" .. tostring(key), view = page, flow = def.id .. ":view",
    icon = icon or (feat and feat.icon) or self.PLACE[self.place or "home"].icon, title = title or (feat and feat.label or def.label),
    sub = sub or def.label, draw = function(f)
      local foot = fn(f, page)
      if not foot then
        page.view = nil
        C_Timer.After(0, function() Hall:Refresh() end)
      end
      return foot
    end }
end

-- The pages a player sees, place by place (only one place's with place): those of the places that are on, and Settings
-- for the Guild Master.
function Hall:Visible(place)
  local list = {}
  for _, pl in ipairs(self.PLACES) do
    if (not place or pl.id == place) and ns.GuildData:PlaceOn(pl.id) then
      for _, id in ipairs(pl.pages) do
        local on = id ~= "settings" or ns.GuildData:InCharge()
        if self.pages[id] and on then list[#list + 1] = id end
      end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function cf() return CommunitiesFrame end

-- The guild window shows our guild (not a community) and is not minimized.
-- Hall.practice (the self-test, for a character without a guild): any community that is open will do, so the window
-- checks can run on a community of your own with the pretend guild's data (Dev/SelfTest.lua).
function Hall:GuildShown()
  local f = cf()
  if not f or not f:IsShown() then return false end
  local modes = COMMUNITIES_FRAME_DISPLAY_MODES
  if modes and f.GetDisplayMode and f:GetDisplayMode() == modes.MINIMIZED then return false end
  local selected = f.GetSelectedClubId and f:GetSelectedClubId()
  if not ns.Guild() then return self.practice == true and selected ~= nil end
  local guildClub = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
  return guildClub == nil or selected == nil or selected == guildClub
end

-- The panel's size and how it is laid out (SPEC decision 59). Under the bar: 814 x 360, the features in a column on its
-- left. Beside a plain window (Dress the guild window off): as wide as the screen allows past the window's tabs (up
-- to 814) and as tall as the window and the bar, with the features as chips along its top when it is narrower than
-- CHIPS_AT. Worked out once, when the frames are made.
function Hall:Geometry()
  local Fr = ns.Frame
  local g = { dressed = Fr:Dressed() }
  if g.dressed then
    g.w, g.h = Fr:W(), Fr.PANEL_H
  else
    local screen = UIParent and UIParent:GetWidth() or 1366
    g.w = ns.Clamp(math.floor(screen - Fr.PLAIN_LEFT - Fr.CF_W - Fr.BESIDE - 16), 420, Fr.CF_W)
    g.h = Fr.CF_H + Fr.BAR_H
  end
  g.chips = g.w < self.CHIPS_AT
  g.railW = g.chips and 0 or self.RAIL_W
  g.top = self.HEAD_H + (g.chips and self.CHIPS_H or 0)
  g.bodyW = g.w - g.railW - 2 * self.PAD
  g.bodyH = g.h - g.top - 2 * self.PAD
  g.listW = math.floor((g.bodyW - self.GAP) * (g.chips and 0.5 or self.LIST_FR))
  return g
end

function Hall:Build()
  local f = cf()
  if self.frame or not f then return end
  local g = self:Geometry()
  self.G, self.LIST_W = g, g.listW
  -- The window shows: Guild Together puts it in the middle (UI/Frame.lua), and opens our panel if /gtf asked for it while
  -- the window was closed. (A frame of our own that is always shown with the window.)
  local watch = CreateFrame("Frame", nil, f)
  watch:SetSize(1, 1)
  watch:SetPoint("TOPLEFT")
  watch:SetScript("OnShow", function()
    C_Timer.After(0, function()
      ns.Frame:Place()
      Hall:Raise()
    end)
    if Hall.pending then
      local after = Hall.pending
      Hall.pending = nil
      C_Timer.After(0, function()
        Hall:Place()
        if Hall:GuildShown() and Hall:Open() and type(after) == "function" then after() end
      end)
    end
  end)
  self.watch = watch
  self:BuildBar(f)
  local o = self:BuildPanel(f, g)

  -- A question over the panel (our own, not Blizzard's StaticPopup).
  local q = CreateFrame("Frame", nil, o)
  q:SetSize(320, 110)
  q:SetPoint("CENTER", self.body, "CENTER", 0, 10)
  q:SetFrameLevel(o:GetFrameLevel() + 60)
  q:EnableMouse(true)
  UI.Glass(q, { 0.05, 0.055, 0.07, 0.99 }, { 0.95, 0.79, 0.36, 0.5 })
  q.text = UI.Wrap(q, "GameFontHighlight", 288)
  q.text:SetJustifyH("CENTER")
  q.text:SetPoint("TOP", 0, -18)
  q.yes = UI.Button(q, "", 120, function() q:Hide(); if q.fn then q.fn() end end)
  q.yes:SetPoint("BOTTOMRIGHT", q, "BOTTOM", -4, 14)
  q.no = UI.Button(q, L.CANCEL, 120, function() q:Hide() end, true)
  q.no:SetPoint("BOTTOMLEFT", q, "BOTTOM", 4, 14)
  q:Hide()
  self.question = q

  -- The pages, in the panel's body (the middle and right).
  for _, id in ipairs(self.order) do
    local def = self.pages[id]
    local page = CreateFrame("Frame", nil, self.body)
    page:SetPoint("TOPLEFT")
    page:SetSize(g.bodyW, g.bodyH)
    page.body = page
    page:Hide()
    def.frame = page
    def.build(page)
  end
  -- What you picked, on the right (UI/Side.lua).
  ns.Side:Build(self.body, g.listW + self.GAP, g.bodyW - g.listW - self.GAP, g.bodyH)
  -- The one frame around the window, the bar and the panel, and the window dressed (UI/Frame.lua).
  ns.Frame:Build(self.bar, o)
  ns.Frame:Dress()
  self:Place()
end

-- The bar under the window (SPEC decision 59): Guild Together and what waits for you on the left, then the places.
function Hall:BuildBar(f)
  local Fr = ns.Frame
  local gold = UI.LOOK.gold
  local bar = CreateFrame("Frame", nil, f)
  bar:SetSize(Fr:W(), Fr.BAR_H)
  bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
  bar:SetFrameLevel(f:GetFrameLevel() + 5)
  bar:EnableMouse(true)
  -- Dark leather brown, a little gold light from above.
  local fill = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
  fill:SetAllPoints()
  fill:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(fill, "VERTICAL", UI.Leather({ 0.07, 0.055, 0.035, 0.98 }), UI.Leather({ 0.145, 0.118, 0.078, 0.98 }))
  local light = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
  light:SetTexture(ns.MEDIA .. "Glow")
  light:SetBlendMode("ADD")
  light:SetVertexColor(gold[1], gold[2], gold[3], 0.1)
  light:SetPoint("TOP", 0, 30)
  light:SetSize(620, 90)
  -- Under a plain window it stands alone: an edge of its own.
  if not Fr:Dressed() then
    UI.Round(bar:CreateTexture(nil, "BORDER"), "Edge", { UI.LOOK.goldLo[1], UI.LOOK.goldLo[2], UI.LOOK.goldLo[3], 0.9 })
      :SetAllPoints()
  end
  self.bar = bar

  -- Guild Together and what waits for you: opens the panel where you were, or closes it.
  local tab = CreateFrame("CheckButton", nil, bar)
  tab:SetSize(self.ME_W, Fr.BAR_H)
  tab:SetPoint("LEFT")
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(gold[1], gold[2], gold[3], 0.06)
  local on = tab:CreateTexture(nil, "ARTWORK", nil, -1)
  on:SetAllPoints()
  on:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(on, "VERTICAL", { gold[1], gold[2], gold[3], 0.02 }, { gold[1], gold[2], gold[3], 0.12 })
  if tab.SetCheckedTexture then tab:SetCheckedTexture(on) end
  -- The guild's crest: the shield, or its own tabard (SPEC decision 68). Not the guild's name: the window's plate
  -- above already says it (the third check of 1 November); the Guild Together screen says it in its heading.
  tab.mark = UI.GuildCrest(tab, self.ME_CREST, UI.EMBLEM_SMALL)
  tab.mark:SetPoint("LEFT", 12, 0)
  tab.icon = tab.mark.shield
  local textW = self.ME_W - 12 - self.ME_CREST - 14
  tab.none = UI.Color(UI.Wrap(tab, "GameFontHighlight", textW), "sub")
  tab.none:SetPoint("LEFT", tab.mark, "RIGHT", 8, 0)
  tab.none:SetText(L.BAR_NONE)
  -- The count: "3 wait for you", the number in red (badge.n, as on the places).
  local badge = CreateFrame("Frame", nil, tab)
  badge:SetSize(textW, 32)
  badge:SetPoint("LEFT", tab.mark, "RIGHT", 8, 0)
  badge.text = UI.Color(UI.Wrap(badge, "GameFontHighlight", textW), "sub")
  badge.text:SetPoint("LEFT")
  badge.SetCount = function(b, n)
    b.n = n or 0
    local num = "|cffff7a6a" .. (b.n > 99 and "99+" or tostring(b.n)) .. "|r"
    b.text:SetText((b.n == 1 and L.BAR_WAITS_ONE or L.BAR_WAITS):format(num))
    b:SetShown(b.n > 0)
    tab.none:SetShown(b.n == 0)
  end
  badge:SetCount(0)
  tab.badge = badge
  local div = tab:CreateTexture(nil, "BORDER")
  div:SetColorTexture(gold[1], gold[2], gold[3], 0.3)
  div:SetWidth(1)
  div:SetPoint("TOPRIGHT", 0, -8)
  div:SetPoint("BOTTOMRIGHT", 0, 8)
  UI.Tooltip(tab, function() return ns.Guild() or L.ADDON_NAME end, function()
    local waiting = {}
    for _, id in ipairs(Hall:Visible()) do
      for _, line in ipairs(Hall.todo and Hall.todo[id] or {}) do waiting[#waiting + 1] = line end
    end
    return L.SIDE_TAB_TIP .. Hall:Waiting(waiting)
  end)
  tab:SetScript("OnClick", function()
    UI.Sound("place")
    if Hall:IsOpen() then Hall:Close() else Hall:Open() end
  end)
  self.tab = tab

  self.tabs = {}
  for _, pl in ipairs(self.PLACES) do self.tabs[pl.id] = self:PlaceButton(bar, pl) end
  self:BuildFly(bar)
end

-- A place in the bar: its medallion and short name, its red number. Pointing at it lights it and, a moment later, shows
-- its features (Hall:ShowFly); the open one glows, with a gold arrow pointing down at the panel. Clicking the open one
-- again closes the panel. The gear is everyone's (SPEC decision 74): a member's opens Your options.
function Hall:PlaceButton(bar, pl)
  local gold = UI.LOOK.gold
  local b = CreateFrame("Button", nil, bar)
  b:SetHeight(ns.Frame.BAR_H)
  b.id = pl.id
  b.light = b:CreateTexture(nil, "BACKGROUND")
  b.light:SetTexture(ns.MEDIA .. "Glow")
  b.light:SetBlendMode("ADD")
  b.light:SetVertexColor(gold[1], gold[2], gold[3], 0.55)
  b.light:SetSize(64, 64)
  b.light:SetPoint("CENTER", b, "TOP", 0, -23)
  b.light:SetAlpha(0)
  b.icon, b.ring = UI.Medallion(b, self.BAR_ICON)
  b.icon:SetPoint("CENTER", b, "TOP", 0, -23)
  UI.SetIcon(b.icon, b.ring, pl.icon, self.BAR_ICON)
  b.label = UI.Color(UI.Text(b, "GameFontNormalSmall", "CENTER"), "sub")
  b.label:SetPoint("TOP", 0, -45)
  b.label:SetPoint("LEFT", 2, 0)
  b.label:SetPoint("RIGHT", -2, 0)
  b.label:SetWordWrap(false)
  if b.SetFontString then b:SetFontString(b.label) end
  b:SetText(L["PLACE_" .. pl.id:upper() .. "_SHORT"])
  b.chev = b:CreateTexture(nil, "OVERLAY")
  b.chev:SetTexture(ns.MEDIA .. "Chevron")
  b.chev:SetVertexColor(1, 0.88, 0.54)
  b.chev:SetSize(14, 8)
  b.chev:SetPoint("CENTER", b, "BOTTOM", 0, 4)
  b.chev:Hide()
  b.badge = UI.Badge(b)
  b.badge:SetScale(0.85)
  b.badge:SetPoint("CENTER", b.icon, "TOPRIGHT", -2, -2)
  b.Select = function(btn, sel)
    btn.on = sel
    btn.light:SetAlpha(sel and 1 or 0)
    btn.chev:SetShown(sel)
    UI.Color(btn.label, sel and "goldHi" or "sub")
  end
  b:SetScript("OnEnter", function(btn)
    Hall:Pointed(btn)
    if btn.on then return end
    btn.light:SetAlpha(0.5)
    UI.Color(btn.label, "ink")
  end)
  b:SetScript("OnLeave", function(btn)
    if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
    if btn.on then return end
    btn.light:SetAlpha(0)
    UI.Color(btn.label, "sub")
  end)
  b:SetScript("OnClick", function()
    UI.Sound("place")
    if Hall.fly then Hall.fly:Hide() end
    -- A member's gear: Your options (Home's last feature); again, it closes them.
    if pl.gear and not ns.GuildData:InCharge() then
      local home = Hall.pages.home and Hall.pages.home.frame
      if Hall:IsOpen() and Hall.current == "home" and home and home.part == "options" then
        if not Hall:IsFull() then Hall:Close() end
      else
        Hall:ShowFeature("home", "options")
      end
      return
    end
    -- (In the Guild Together screen the panel stays: the open place again does nothing.)
    if Hall:IsOpen() and Hall.place == pl.id then
      if not Hall:IsFull() then Hall:Close() end
    else
      Hall:OpenPlace(pl.id)
    end
  end)
  return b
end

-- The places a player sees, evenly across the bar after the Guild Together block (Guild settings last).
function Hall:LayoutBar()
  for _, pl in ipairs(self.PLACES) do self.tabs[pl.id]:Hide() end
  local list = self:Places()
  if #list == 0 then return end
  local w = math.floor((ns.Frame:W() - self.ME_W - 8) / #list)
  self.tabs.manage:SetText(ns.GuildData:InCharge() and L.PLACE_MANAGE_SHORT or L.OPT_TITLE)
  for i, id in ipairs(list) do
    local b = self.tabs[id]
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.bar, "TOPLEFT", self.ME_W + 4 + (i - 1) * w, 0)
    b:Show()
  end
end

-- The panel: under the bar, or beside a plain window (Hall:Geometry). Its header shows the place; under it the
-- features (a column on the left, or chips along the top) and the body for the pages.
function Hall:BuildPanel(f, g)
  local Fr = ns.Frame
  local gold = UI.LOOK.gold
  local o = CreateFrame("Frame", nil, f)
  o:SetSize(g.w, g.h)
  if g.dressed then o:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, 0)
  else o:SetPoint("TOPLEFT", f, "TOPRIGHT", Fr.BESIDE, 0) end
  o:SetFrameLevel(f:GetFrameLevel() + 6)
  o:EnableMouse(true)
  o:EnableMouseWheel(true)
  o:SetScript("OnMouseWheel", function() end)
  local fill = UI.Glass(o, { 1, 1, 1, 1 }, { gold[1], gold[2], gold[3], g.dressed and 0 or 0.45 })
  UI.SetGradient(fill, "VERTICAL", UI.Shade({ 0.04, 0.04, 0.047, 0.98 }), UI.Shade({ 0.078, 0.075, 0.09, 0.98 }))
  -- Closing the window closes the panel; it stays closed when the window opens again.
  o:SetScript("OnHide", function(frame)
    C_Timer.After(0, function() if not f:IsShown() then frame:Hide() end end)
    Hall:Check(false)
  end)
  o:Hide()
  self.frame = o
  -- It drops in when it opens and when the place changes (played backwards: from 10 above, faded, to its place).
  self.drop = o:CreateAnimationGroup()
  local fade = self.drop:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0)
  fade:SetDuration(0.28)
  fade:SetSmoothing("IN")
  local move = self.drop:CreateAnimation("Translation")
  move:SetOffset(0, 10)
  move:SetDuration(0.28)
  move:SetSmoothing("IN")

  -- The header: the place's painting, its medallion (Home: the emblem), name and line; its state on the right, how
  -- fresh the guild's data is, the page's "i" and a close button.
  local head = CreateFrame("Frame", nil, o)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(self.HEAD_H)
  self.art = head:CreateTexture(nil, "ARTWORK")
  self.art:SetAllPoints()
  local split = math.floor(g.w * 0.55)
  local shade1 = head:CreateTexture(nil, "ARTWORK", nil, 1)
  shade1:SetColorTexture(1, 1, 1, 1)
  shade1:SetPoint("TOPLEFT")
  shade1:SetPoint("BOTTOMLEFT")
  shade1:SetWidth(split)
  UI.SetGradient(shade1, "HORIZONTAL", { 0.03, 0.027, 0.02, 0.95 }, { 0.03, 0.027, 0.02, 0.6 })
  local shade2 = head:CreateTexture(nil, "ARTWORK", nil, 1)
  shade2:SetColorTexture(1, 1, 1, 1)
  shade2:SetPoint("TOPLEFT", shade1, "TOPRIGHT")
  shade2:SetPoint("BOTTOMRIGHT")
  UI.SetGradient(shade2, "HORIZONTAL", { 0.03, 0.027, 0.02, 0.6 }, { 0.03, 0.027, 0.02, 0.15 })
  local low = head:CreateTexture(nil, "ARTWORK", nil, 2)
  low:SetColorTexture(1, 1, 1, 1)
  low:SetPoint("BOTTOMLEFT")
  low:SetPoint("BOTTOMRIGHT")
  low:SetHeight(math.floor(self.HEAD_H * 0.4))
  UI.SetGradient(low, "VERTICAL", { 0, 0, 0, 0.6 }, { 0, 0, 0, 0 })
  local rule = head:CreateTexture(nil, "ARTWORK", nil, 3)
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)
  rule:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(rule, "HORIZONTAL", { 0.88, 0.71, 0.33, 0.9 }, { 0.72, 0.53, 0.16, 0 })
  self.crest = head:CreateTexture(nil, "ARTWORK", nil, 4)
  self.crest:SetSize(self.CREST, self.CREST)
  self.crest:SetPoint("LEFT", 16, 0)
  self.title = UI.Color(UI.Text(head, "GameFontNormalHuge"), "goldHi")
  self.title:SetPoint("LEFT", self.crest, "RIGHT", 11, 0)
  local sep = head:CreateTexture(nil, "ARTWORK", nil, 4)
  sep:SetColorTexture(gold[1], gold[2], gold[3], 0.35)
  sep:SetSize(1, 16)
  sep:SetPoint("LEFT", self.title, "RIGHT", 11, 0)
  self.sub = UI.Ink(UI.Text(head, "GameFontHighlight"))
  self.sub:SetPoint("LEFT", sep, "RIGHT", 11, 0)
  self.sub:SetWordWrap(false)
  local close = UI.Create("Button", head, "UIPanelCloseButton")
  close:SetSize(26, 26)
  close:SetPoint("RIGHT", -10, 0)
  close:SetScript("OnClick", function() UI.Sound("place") Hall:Close() end)
  self.help = UI.Help(head, function() local d = self.pages[self.current] return d and d.label or "" end,
    function() local d = self.pages[self.current] return d and d.help end)
  self.help:SetPoint("RIGHT", close, "LEFT", -6, 0)
  -- Into the Guild Together screen and back (SPEC decision 64).
  local big = CreateFrame("Button", nil, head)
  big:SetSize(24, 24)
  big:SetPoint("RIGHT", self.help, "LEFT", -6, 0)
  big:SetScript("OnClick", function() UI.Sound("place") Hall:Full(not Hall:IsFull()) end)
  UI.Tooltip(big, function() return Hall:IsFull() and L.FULL_OFF or L.FULL_ON end,
    function() return not Hall:IsFull() and L.FULL_ON_TIP or nil end)
  self.bigBtn = big
  self:FullButton()
  self.status = UI.Color(UI.Text(head, "GameFontNormal", "RIGHT"), "gold")
  self.status:SetPoint("TOPRIGHT", big, "TOPLEFT", -10, 4)
  self.status:SetWordWrap(false)
  -- How fresh the guild's data is (CLAUDE.md: data from others is as fresh as their last sync).
  self.fresh = UI.Text(head, "GameFontDisableSmall", "RIGHT")
  self.fresh:SetPoint("TOPRIGHT", self.status, "BOTTOMRIGHT", 0, -3)
  self.sub:SetPoint("RIGHT", self.status, "LEFT", -12, 0)
  self.head = head

  -- The features: a column on the left, or chips along the top of a narrow panel.
  if g.chips then
    local chips = CreateFrame("Frame", nil, o)
    chips:SetPoint("TOPLEFT", self.PAD, -(self.HEAD_H + 6))
    chips:SetSize(g.w - 2 * self.PAD, self.CHIPS_H - 10)
    local line = o:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -g.top)
    line:SetPoint("TOPRIGHT", 0, -g.top)
    self.chipBox = chips
  else
    local rail = UI.Pane(o, g.railW, g.h - self.HEAD_H, {})
    rail:SetPoint("TOPLEFT", 0, -self.HEAD_H)
    rail.edge:Hide()
    rail.fill:SetVertexColor(0, 0, 0, 0.3)
    local line = rail:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.72, 0.53, 0.16, 0.25)
    line:SetWidth(1)
    line:SetPoint("TOPRIGHT")
    line:SetPoint("BOTTOMRIGHT")
    self.rail = rail
  end
  self.feats = {}

  local body = CreateFrame("Frame", nil, o)
  body:SetPoint("TOPLEFT", g.railW + self.PAD, -(g.top + self.PAD))
  body:SetSize(g.bodyW, g.bodyH)
  self.body = body
  return o
end

-- A feature on the left (or a chip): its medallion, name and status (a chip: no status), its red number; the picked
-- one in gold, with a gold mark on its left.
local function featButton(parent, w, chip)
  local gold = UI.LOOK.gold
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, chip and Hall.CHIP_H - 2 or Hall.FEAT_H)
  UI.Round(b:CreateTexture(nil, "HIGHLIGHT"), "Glass", { gold[1], gold[2], gold[3], 0.08 }):SetAllPoints()
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(b.sel, "HORIZONTAL", { gold[1], gold[2], gold[3], 0.2 }, { gold[1], gold[2], gold[3], 0.03 })
  b.selEdge = UI.Round(b:CreateTexture(nil, "BORDER"), "Edge", { gold[1], gold[2], gold[3], 0.6 })
  b.selEdge:SetAllPoints()
  b.mark = b:CreateTexture(nil, "BORDER", nil, 1)
  b.mark:SetColorTexture(gold[1], gold[2], gold[3], 1)
  b.mark:SetWidth(3)
  b.mark:SetPoint("TOPLEFT", 0, -3)
  b.mark:SetPoint("BOTTOMLEFT", 0, 3)
  b.iconSize = chip and 20 or Hall.FEAT_ICON
  b.icon, b.ring = UI.Medallion(b, b.iconSize)
  b.icon:SetPoint("CENTER", b, "LEFT", 5 + b.iconSize / 2, 0)
  local x = b.iconSize + 11
  b.name = UI.Color(UI.Text(b, chip and "GameFontHighlightSmall" or "GameFontHighlight"), "ink")
  b.name:SetWordWrap(false)
  if chip then
    b.name:SetPoint("LEFT", x - 2, 0)
    b.name:SetPoint("RIGHT", -4, 0)
  else
    b.name:SetPoint("TOPLEFT", x, -7)
    b.name:SetPoint("RIGHT", -6, 0)
    b.sub = UI.Color(UI.Text(b, "GameFontHighlightSmall"), "sub")
    b.sub:SetPoint("BOTTOMLEFT", x, 7)
    b.sub:SetPoint("RIGHT", -6, 0)
    b.sub:SetWordWrap(false)
  end
  b.badge = UI.Badge(b)
  b.badge:SetScale(0.85)
  b.badge:SetPoint("CENTER", b.icon, "TOPRIGHT", -1, -1)
  b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
  -- A long name or status is cut: pointing at it shows both whole (short: the self-test lets it be cut).
  UI.Tooltip(b, function() return b.tip and b.tip[1] or "" end, function() return b.tip and b.tip[2] end)
  b.short = true
  return b
end

-- The features of the open place, on the left (or as chips), the picked one marked.
function Hall:DrawFeatures()
  local g = self.G
  local list = self:Features(self.place)
  local parent = g.chips and self.chipBox or self.rail.child
  local perLine = g.chips and math.max(1, math.ceil(#list / 2)) or 1
  local w = g.chips and math.floor((self.chipBox:GetWidth() - 3 * (perLine - 1)) / perLine) or self.rail.inner
  for i, x in ipairs(list) do
    local b = self.feats[i] or featButton(parent, w, g.chips)
    self.feats[i] = b
    b:SetWidth(w)
    local page = self.pages[x.page].frame
    local sub, n = self:FeatureState(x.page, x.id)
    local sel = x.page == self.current and x.id == page.part
    UI.SetIcon(b.icon, b.ring, x.icon, b.iconSize)
    b.name:SetText(x.label)
    UI.Color(b.name, sel and "goldHi" or "ink")
    if b.sub then b.sub:SetText(sub or "") end
    b.sel:SetShown(sel)
    b.selEdge:SetShown(sel)
    b.mark:SetShown(sel)
    b.badge:SetCount(n)
    b.tip, b.feat, b.on = { x.label, sub }, x, sel
    b.onClick = function()
      UI.Sound("pick")
      Hall:ShowFeature(x.page, x.id)
    end
    b:ClearAllPoints()
    if g.chips then
      b:SetPoint("TOPLEFT", ((i - 1) % perLine) * (w + 3), -math.floor((i - 1) / perLine) * self.CHIP_H)
    else
      b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * (self.FEAT_H + 3))
    end
    b:Show()
  end
  for i = #list + 1, #self.feats do self.feats[i]:Hide() end
  if self.rail then self.rail.child:SetHeight(8 + #list * (self.FEAT_H + 3)) end
end

-- Pointing at a place (SPEC decision 74): its features in a small list under it, each with its status and red number;
-- a click opens one. It comes a moment after the pointer stops on the place, and goes a moment after the pointer
-- leaves both. A place without features (a member's gear) says what it is in a tooltip instead.
Hall.FLY_W, Hall.FLY_DELAY, Hall.FLY_STAY = 236, 0.25, 0.2
function Hall:BuildFly(bar)
  local gold = UI.LOOK.gold
  local fly = CreateFrame("Frame", nil, bar)
  fly:SetFrameStrata("DIALOG")
  fly:SetFrameLevel(bar:GetFrameLevel() + 100)
  fly:SetWidth(self.FLY_W)
  fly:EnableMouse(true)
  UI.Glass(fly, { 0.035, 0.033, 0.04, 0.97 }, { gold[1], gold[2], gold[3], 0.6 })
  fly.title = UI.Color(UI.Text(fly, "GameFontNormal"), "goldHi")
  fly.title:SetPoint("TOPLEFT", 10, -9)
  fly.sub = UI.Color(UI.Wrap(fly, "GameFontHighlightSmall", self.FLY_W - 20), "sub")
  fly.sub:SetPoint("TOPLEFT", fly.title, "BOTTOMLEFT", 0, -3)
  fly.rows = {}
  fly:Hide()
  fly:SetScript("OnHide", function(f) f.hold = nil end)
  fly:SetScript("OnUpdate", function(f, elapsed)
    if f.hold or (f.owner and (f:IsMouseOver() or f.owner:IsMouseOver())) then f.away = 0 return end
    f.away = (f.away or 0) + elapsed
    if f.away > Hall.FLY_STAY then f:Hide() end
  end)
  self.fly = fly
end

-- The pointer came onto place button b.
function Hall:Pointed(b)
  if self.fly and self.fly:IsShown() and self.fly.owner ~= b then self.fly:Hide() end
  if #self:Features(b.id) == 0 then
    local mine = b.id == "manage" and not ns.GuildData:InCharge()
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText(mine and L.OPT_TITLE or self.PLACE[b.id].label, 1, 1, 1)
    GameTooltip:AddLine(mine and L.OPT_ROW_SUB or L["PLACE_" .. b.id:upper() .. "_SUB"], nil, nil, nil, true)
    GameTooltip:Show()
    return
  end
  C_Timer.After(self.FLY_DELAY, function() if b:IsMouseOver() then Hall:ShowFly(b) end end)
end

-- Shows place button b's features under it. Returns true when it shows.
-- hold: it stays without the mouse over it, until it hides (the self-test's picture of it).
function Hall:ShowFly(b, hold)
  local fly = self.fly
  if not fly or (ns.Tour and ns.Tour.on) then return false end
  local list = self:Features(b.id)
  if #list == 0 then return false end
  if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
  fly.owner, fly.away, fly.hold = b, 0, hold == true
  fly.title:SetText(self.PLACE[b.id].label)
  fly.sub:SetText(L["PLACE_" .. b.id:upper() .. "_SUB"] or "")
  local y = -math.ceil(9 + (fly.title:GetStringHeight() or 12) + 3 + (fly.sub:GetStringHeight() or 10) + 8)
  local w = self.FLY_W - 8
  for i, x in ipairs(list) do
    local r = fly.rows[i] or featButton(fly, w)
    fly.rows[i] = r
    local sub, n = self:FeatureState(x.page, x.id)
    local page = self.pages[x.page].frame
    local sel = self:IsOpen() and x.page == self.current and x.id == page.part
    UI.SetIcon(r.icon, r.ring, x.icon, r.iconSize)
    r.name:SetText(x.label)
    UI.Color(r.name, sel and "goldHi" or "ink")
    r.sub:SetText(sub or "")
    r.sel:SetShown(sel)
    r.selEdge:SetShown(sel)
    r.mark:SetShown(sel)
    r.badge:SetCount(n)
    r.tip, r.feat = { x.label, sub }, x
    r.onClick = function()
      UI.Sound("pick")
      fly:Hide()
      Hall:ShowFeature(x.page, x.id)
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, y)
    r:Show()
    y = y - self.FEAT_H - 2
  end
  for i = #list + 1, #fly.rows do fly.rows[i]:Hide() end
  fly:SetHeight(-y + 4)
  -- Under the place; near the bar's right end it opens leftwards, so it stays over the panel.
  fly:ClearAllPoints()
  local right, bar = b:GetRight(), self.bar:GetRight()
  if right and bar and right + self.FLY_W / 2 > bar then fly:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
  else fly:SetPoint("TOP", b, "BOTTOM", 0, -2) end
  fly:Show()
  return true
end

-- Where the bar shows: under the window while it shows our guild (not a community, not minimized). The frame's bottom
-- follows (UI/Frame.lua).
function Hall:Place()
  local f = cf()
  if not f or not self.bar then return end
  local ok = self:GuildShown()
  self.bar:SetShown(ok)
  if ok then self:LayoutBar()
  elseif self.frame then self.frame:Hide() end
  self:Fit()
  ns.Frame:Tabs()
  self:BadgesSoon()
end

-- The places a player sees, in order (Manage last): a place of features only while one of them is on; the gear always.
function Hall:Places()
  local list = {}
  for _, pl in ipairs(self.PLACES) do
    local some = false
    for _, id in ipairs(self:Visible(pl.id)) do
      if not self.pages[id].frame or not self.pages[id].frame.split then some = true end
    end
    if some or #self:Features(pl.id) > 0 or pl.gear then list[#list + 1] = pl.id end
  end
  return list
end

---------------------------------------------------------------------------
-- Opening and pages
---------------------------------------------------------------------------
function Hall:IsOpen() return self.frame ~= nil and self.frame:IsShown() end

-- Frame strata, lowest first: a frame in a higher strata draws over any level in a lower one.
Hall.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local STRATUM = {}
for i, s in ipairs(Hall.STRATA) do STRATUM[s] = i end
local function stratum(f) return STRATUM[f:GetFrameStrata() or "MEDIUM"] or STRATUM.MEDIUM end

-- The shown frame that draws highest among a frame's children, all the way down (our own frames left out).
local function highest(frame, skip, top)
  for _, child in ipairs({ frame:GetChildren() }) do
    if not skip[child] and child:IsShown() then
      local s, l = stratum(child), child:GetFrameLevel()
      if s > top.s or (s == top.s and l > top.level) then top.s, top.level, top.frame = s, l, child end
      highest(child, skip, top)
    end
  end
  return top
end

-- Blizzard's frames in the window draw far above the window itself (levels past 1500 in 12.1.5, the chat's scroll
-- bar deep down): the crest and the name, which lie over the window's corner and title band, go above all of them,
-- and so does a scene's moment over the chat (UI/Side.lua). Returns { s = strata index, level, frame } of the
-- highest one.
function Hall:BlizzardTop()
  local Fr, Side = ns.Frame, ns.Side
  local skip = {}
  -- (Some are not made: the Guild Together screen until it is first opened, the frame with Dress off.)
  local ours = { self.frame, self.bar, self.watch, self.full, Fr.hi, Fr.lo, Fr.crest, Fr.title, Fr.rail, Side and Side.chat }
  for _, o in pairs(ours) do skip[o] = true end
  local f = cf()
  return highest(f, skip, { s = stratum(f), level = f:GetFrameLevel() })
end

-- True when frame draws above everything of Blizzard's in the window.
function Hall:Above(frame, top)
  top = top or self:BlizzardTop()
  local s = stratum(frame)
  return s > top.s or (s == top.s and frame:GetFrameLevel() > top.level)
end

function Hall:Raise()
  local Fr = ns.Frame
  if not self.frame or not Fr.crest then return end
  local top = self:BlizzardTop()
  Fr:Raise(stratum(Fr.crest) < top.s and self.STRATA[top.s] or nil, math.min(top.level + 1, 9000))
end

-- A frame of ours over everything of Blizzard's in the window: its strata when higher, and the level above. Returns
-- that level.
function Hall:Lift(frame)
  local top = self:BlizzardTop()
  if stratum(frame) < top.s then frame:SetFrameStrata(self.STRATA[top.s]) end
  local level = math.min(top.level + 1, 9000)
  frame:SetFrameLevel(level)
  return level
end

-- The panel drops in (unless motion is off).
function Hall:Drop()
  if not self.drop or not UI.Motion() then return end
  self.drop:Stop()
  self.drop:Play(true)
end

-- Opens the panel under the bar (the window must be open, showing the guild), at the page looked at last.
function Hall:Open(page)
  if not self.frame or not self:GuildShown() then return false end
  self:Raise()
  if not self.frame:IsShown() then
    UI.Sound("open")
    self.frame:Show()
    self:Drop()
  end
  self:Check(true)
  self:Fit()
  self:Show(page or (ns.char and ns.char.page))
  -- Getting started: the tour, offered the first time and after a promotion (UI/Tour.lua).
  if ns.Tour then ns.Tour:Opened() end
  return true
end

-- Something opened from elsewhere (the player card, UI/Card.lua) shows in the panel: it opens if it was closed.
function Hall:Reveal()
  if not self:IsOpen() then self:Open(self.current) end
end

-- A place: the feature that was open there last, else its first feature (or page).
function Hall:OpenPlace(place)
  ns.Side.over = nil
  -- The Guild Master picks the guild's setup the first time they open Guild Together (SPEC decision 70): until then,
  -- each session's first place opens on it.
  local D = ns.GuildData
  if not self.setupAsked and D:Current() and D:InCharge() and ns.Rules.Setup() == nil then
    self.setupAsked = true
    if self.pages.settings and self:Open("settings") then
      self:ShowFeature("settings", "setup")
      return true
    end
  end
  local last = ns.char and ns.char.placeFeat and ns.char.placeFeat[place]
  local feats = self:Features(place)
  local pick = feats[1]
  for _, x in ipairs(feats) do
    if last and x.page == last[1] and x.id == last[2] then pick = x end
  end
  if pick then
    if not self:Open(pick.page) then return false end
    self:ShowFeature(pick.page, pick.id)
    return true
  end
  return self:Open(self:Visible(place)[1])
end

-- Asks before doing fn: text, and a button labelled yes (and Cancel).
function Hall:Confirm(text, yes, fn)
  local q = self.question
  if not q then return end
  q.text:SetText(text)
  q.yes:SetText(yes)
  q.fn = fn
  q:Show()
end

-- The Guild Together block in the bar looks pressed while the panel shows; the open place glows.
function Hall:Check(on)
  if self.tab then self.tab:SetChecked(on) end
  for pl, b in pairs(self.tabs or {}) do b:Select(on and pl == self.place) end
end

function Hall:Close()
  if self:IsFull() then self:Full(false) end
  if self.frame then self.frame:Hide() end
  self:Check(false)
  self:Fit()
end

-- The one frame's bottom follows the bar and the panel; in the Guild Together screen they are not under the window.
function Hall:Fit()
  if self:IsFull() then return ns.Frame:Fit(false, false) end
  ns.Frame:Fit(self.bar ~= nil and self.bar:IsShown(), self:IsOpen())
end

---------------------------------------------------------------------------
-- The Guild Together screen (SPEC decision 64): Guild Together alone across the screen, over the guild window. The bar and the
-- panel (our own frames) move onto a screen of our own and are scaled up to fill it; back under the window when it is
-- left. That screen is a child of the window, so Escape (which closes the window) closes it too, and the next time
-- the window opens it is the window again.
---------------------------------------------------------------------------
Hall.FULL_HEAD, Hall.FULL_PAD = 56, 28

function Hall:IsFull() return self.isFull == true end

function Hall:BuildFull()
  if self.full or InCombatLockdown() then return self.full end
  local f, Fr, gold = cf(), ns.Frame, UI.LOOK.gold
  local full = CreateFrame("Frame", nil, f)
  -- Its own scale (the screen's), not the window's.
  if full.SetIgnoreParentScale then full:SetIgnoreParentScale(true) end
  full:SetFrameStrata("DIALOG")
  full:SetAllPoints(UIParent)
  full:EnableMouse(true)
  full:EnableMouseWheel(true)
  full:SetScript("OnMouseWheel", function() end)
  local shade = full:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(shade, "VERTICAL", { 0.015, 0.012, 0.01, 0.97 }, { 0.055, 0.045, 0.03, 0.95 })
  local glow = full:CreateTexture(nil, "BACKGROUND", nil, 1)
  glow:SetTexture(ns.MEDIA .. "Glow")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(gold[1], gold[2], gold[3], 0.08)
  glow:SetPoint("TOP", 0, 120)
  glow:SetSize(1600, 560)
  local host = CreateFrame("Frame", nil, full)
  host:SetPoint("CENTER")
  -- Its heading: the crest, the guild's name, and the way back to the window.
  local head = CreateFrame("Frame", nil, host)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(self.FULL_HEAD)
  local fill = head:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(fill, "VERTICAL", UI.Leather({ 0.07, 0.055, 0.035, 0.98 }), UI.Leather({ 0.145, 0.118, 0.078, 0.98 }))
  local crest = UI.GuildCrest(head, 40, UI.EMBLEM_SMALL)
  crest:SetPoint("LEFT", 14, 0)
  full.name = UI.Color(UI.Text(head, "GameFontNormalHuge"), "goldHi")
  full.name:SetPoint("LEFT", crest, "RIGHT", 10, 0)
  full.back = UI.Button(head, L.FULL_OFF, 190, function() UI.Sound("place") Hall:Full(false) end, true)
  full.back:SetPoint("RIGHT", -14, 0)
  Fr:Rim(host)
  -- The window closed under it (Escape): back to the window for next time.
  full:SetScript("OnHide", function()
    C_Timer.After(0, function() if Hall.isFull and not full:IsVisible() then Hall:Full(false) end end)
  end)
  full:Hide()
  full.host = host
  self.full = full
  return full
end

-- Into the Guild Together screen (on) or back to the window. Returns true when it is where it was asked to be.
function Hall:Full(on)
  local f = cf()
  if not f or not self.frame then return false end
  on = on == true
  if on == self:IsFull() then return true end
  local Fr, g = ns.Frame, self.G
  if on then
    if not self:IsOpen() and not self:Open() then return false end
    local full = self:BuildFull()
    if not full then ns:Print(L.FULL_COMBAT, true) return false end
    self.isFull = true
    local host = full.host
    local w, h = math.max(Fr:W(), g.w), self.FULL_HEAD + Fr.BAR_H + g.h
    host:SetSize(w, h)
    self.bar:SetParent(host)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOP", host, "TOP", 0, -self.FULL_HEAD)
    self.bar:SetFrameLevel(host:GetFrameLevel() + 5)
    self.frame:SetParent(host)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOP", self.bar, "BOTTOM", 0, 0)
    self.frame:SetFrameLevel(host:GetFrameLevel() + 6)
    full:SetScale(UIParent:GetEffectiveScale())
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local edge = 2 * (self.FULL_PAD + Fr.RIM)
    host:SetScale(math.max(0.5, math.min((sw - edge) / w, (sh - edge) / h)))
    full.name:SetText(ns.Guild() or L.ADDON_NAME)
    -- The window's crest and name stay with the window, under this screen (they drew over its heading: the third
    -- check of 1 November); so does a moment over its chat.
    if Fr.crest then Fr.crest:Hide() Fr.title:Hide() end
    ns.Side:EndMoment()
    full:Show()
  else
    self.isFull = false
    if Fr.crest then Fr.crest:Show() Fr.title:Show() end
    self.bar:SetParent(f)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
    self.bar:SetFrameLevel(f:GetFrameLevel() + 5)
    self.frame:SetParent(f)
    self.frame:ClearAllPoints()
    if g.dressed then self.frame:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, 0)
    else self.frame:SetPoint("TOPLEFT", f, "TOPRIGHT", Fr.BESIDE, 0) end
    self.frame:SetFrameLevel(f:GetFrameLevel() + 6)
    if self.full then self.full:Hide() end
  end
  self:FullButton()
  self:Fit()
  if self:IsOpen() then self:Refresh() end
  return true
end

-- The header's button: into the Guild Together screen, or back.
function Hall:FullButton()
  local b = self.bigBtn
  if not b then return end
  local full = self:IsFull()
  local atlas = full and "RedButton-Condense" or "RedButton-Expand"
  local ok = b.SetNormalAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
  if ok then
    b:SetNormalAtlas(atlas)
    b:SetPushedAtlas(atlas .. "-Pressed")
    b:SetHighlightAtlas("RedButton-Highlight", "ADD")
  else
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-" .. (full and "Smaller" or "Bigger") .. "Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-" .. (full and "Smaller" or "Bigger") .. "Button-Down")
  end
end

-- The header of a place (SPEC decision 53): its painting, Alliance or Horde (Media\Head<Place>, Horde<Place>: 16:1, a
-- band from the middle fills the header; a narrow panel shows the middle of its width), and its medallion; Home's is
-- the emblem.
function Hall:Paint(place)
  local name = place:sub(1, 1):upper() .. place:sub(2)
  local horde = UnitFactionGroup("player") == "Horde"
  self.art:SetTexture(ns.MEDIA .. (horde and "Horde" or "Head") .. name)
  local ratio = (self.G.w / self.HEAD_H) / 16
  if ratio >= 1 then
    local frac = 1 / ratio / 2
    self.art:SetTexCoord(0, 1, 0.5 - frac, 0.5 + frac)
  else
    self.art:SetTexCoord(0.5 - ratio / 2, 0.5 + ratio / 2, 0, 1)
  end
  if place == "home" then
    self.crest:SetTexture(ns.MEDIA .. UI.EMBLEM_SMALL)
    self.crest:SetTexCoord(0, 1, 0, 1)
  else
    UI.IconTex(self.crest, self.PLACE[place].icon)
  end
end

-- Shows a page (one the player sees; else the first).
function Hall:Show(id)
  if not self.frame then return end
  local visible = self:Visible()
  local ok = false
  for _, v in ipairs(visible) do if v == id then ok = true end end
  if not ok then id = visible[1] end
  if id ~= self.current then self.question:Hide() end
  self.current = id
  local feat = id and self:Feature(id)
  local before = self.place
  self.place = feat and feat.place or (id and self.PLACE_OF[id])
  if before and before ~= self.place and self:IsOpen() then self:Drop() end
  if ns.char and id then
    ns.char.page = id
    if feat then
      ns.char.placeFeat = ns.char.placeFeat or {}
      ns.char.placeFeat[self.place] = { id, feat.id }
    end
  end
  self:LayoutBar()
  self:Check(self:IsOpen())
  for pid, def in pairs(self.pages) do def.frame:SetShown(pid == id) end
  local def = id and self.pages[id]
  if not def then return end
  self:Paint(self.place)
  -- The place's name, and its line.
  self.title:SetText(self.PLACE[self.place].label)
  self.sub:SetText(L["PLACE_" .. self.place:upper() .. "_SUB"] or def.sub or "")
  self:Refresh()
end

---------------------------------------------------------------------------
-- What waits for you (SPEC decision 47): each page's def.todo() -> { "a line", ... }, counted on its place in the bar
-- and on the Guild Together block, and listed in their tooltips and on Home; the features count theirs (spec.count). Only
-- our own frames change, so it may run in combat.
---------------------------------------------------------------------------
function Hall:Todo(id)
  local def = self.pages[id]
  if not def or not def.todo or not ns.GuildData:Current() then return {} end
  local ok, list = pcall(def.todo)
  if not ok then ns:LogError("todo", id, tostring(list)) return {} end
  return type(list) == "table" and list or {}
end

function Hall:Badges()
  if not self.tab then return end
  self.todo = {}
  local total = 0
  for _, pl in ipairs(self.PLACES) do
    local n = 0
    for _, id in ipairs(self:Visible(pl.id)) do
      local list = self:Todo(id)
      self.todo[id] = list
      n = n + #list
    end
    self.tabs[pl.id].badge:SetCount(n)
    total = total + n
  end
  self.tab.badge:SetCount(total)
end

-- Soon, once: many ops can arrive in one go (a catch-up after login).
function Hall:BadgesSoon()
  if self.badgesDue then return end
  self.badgesDue = true
  C_Timer.After(0.3, function() self.badgesDue = nil; self:Badges() end)
end

-- The lines under a tooltip: "Waiting for you:" and each thing (none: nothing).
function Hall:Waiting(list)
  if not list or #list == 0 then return "" end
  return "\n\n" .. L.TODO_HEAD .. "\n- " .. table.concat(list, "\n- ")
end

function Hall:Refresh()
  self:BadgesSoon()
  if not self:IsOpen() then return end
  local def = self.current and self.pages[self.current]
  -- A feature picked that sits in another place (the deathroll, in Challenges): that place shows.
  local feat = def and def.frame.split and self:Feature(self.current)
  if feat and feat.place ~= self.place then return self:Show(self.current) end
  -- A feature switched off (or with nothing left to do) while it was open: the place's first, else Home.
  if feat and not feat.on then
    local first = self:Features(self.place)[1]
    if not first then return self:OpenPlace("home") end
    return self:ShowFeature(first.page, first.id)
  end
  if def and def.refresh then def.refresh(def.frame) end
  if def and def.frame.split then self:DrawFeatures() end
  ns.Side:From(def, feat or (def and self:Feature(def.id)))
  self.status:SetText(def and def.status and def.status() or "")
  self.help:SetShown(def ~= nil and def.help ~= nil)
  local g = ns.GuildData:Current()
  local heard = g and g.heard
  self.fresh:SetText(heard and L.FRESH:format(ns.TimeAgo(heard)) or L.FRESH_NONE)
end

-- Does fn in our panel: now when it can open, else the next time the guild window opens (addon code may not open it:
-- that taints it).
function Hall:Go(fn)
  if self:IsOpen() or self:Open() then return fn() end
  if not ns.Guild() then return ns:Print(L.NO_GUILD, true) end
  self.pending = fn
  ns:Print(L.OPEN_HINT, true)
end

-- /gtf: our panel, now if the guild window is open; else the next time it opens.
function Hall:Toggle()
  if not ns.Guild() then
    ns:Print(L.NO_GUILD, true)
    return
  end
  if self:IsOpen() then return self:Close() end
  if self:Open() then return end
  self.pending = true
  ns:Print(L.OPEN_HINT, true)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local hooked = false
local function attach()
  if hooked or not cf() then return end
  ns.Combat:AfterCombat(function()
    if hooked then return end
    hooked = true
    Hall:Build()
    hooksecurefunc(CommunitiesFrame, "UpdateCommunitiesTabs", function() Hall:Place() end)
    -- A Blizzard tab was clicked (or the window changed mode): the bar stays; minimized, it goes.
    hooksecurefunc(CommunitiesFrame, "SetDisplayMode", function() Hall:Place() end)
    if CommunitiesFrame.SelectClub then hooksecurefunc(CommunitiesFrame, "SelectClub", function() Hall:Place() end) end
    -- The game placed its windows: ours goes to the middle again (SPEC decision 58).
    if ns.Frame:Dressed() and UpdateUIPanelPositions then
      hooksecurefunc("UpdateUIPanelPositions", function() ns.Frame:Place() end)
    end
    if CommunitiesFrame:IsShown() then ns.Frame:Place() end
    -- What waits for you changes with time too (a turn to roll, a vote that opened): looked at again while the window
    -- is open. (Once per two seconds of real time, also when a ticker catches up after a jump.)
    local last = 0
    C_Timer.NewTicker(2, function()
      if not CommunitiesFrame:IsShown() or GetTime() - last < 1.5 then return end
      last = GetTime()
      Hall:Badges()
    end)
  end)
end

ns:RegisterEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_Communities" then attach() end end)
ns:On("LOGIN", function()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
  if loaded then attach() end
end)
-- Places switched on or off, or a new rank: the places in the bar follow.
local function again()
  Hall:Place()
  if Hall:IsOpen() then Hall:Show(Hall.current) end
end
ns:On("GUILD_SETTINGS", again)
ns:On("GUILD_DATA", function() Hall:Refresh() end)
ns:On("NEAR", function() if Hall:IsOpen() then Hall:Refresh() end end)
ns:On("ROSTER", again)
ns:On("GUILD_CHANGED", function() Hall:Place() end)
