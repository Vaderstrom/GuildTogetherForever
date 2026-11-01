-- The one frame (SPEC decisions 58 and 59, docs/mockup/Frame.html): the game's guild window moved to the middle at the
-- top of the screen and scaled, with our bar and panel under it (UI/Hall.lua), so the whole column fits above the
-- action bars. The window's own border, portrait and title are hidden under Journey Together's leather and gold frame
-- (Media\WindowFrame, cut as in Journey's UI.DialogFrame), with the Guild Together crest over the top-left corner and the
-- guild's name and motto in the window's title band beside it (SPEC decision 76). The frame is a rail wider on the
-- right, where the window's side tabs (Chat, Roster, Guild Benefits, Guild Info) sit on dark leather, their own art
-- tinted in the guild's metal. A gold line with a diamond joins the window to the bar, and the bar to the panel.
-- With Dress the guild window off (GuildTogetherForeverDB.plain: read once, so the switch reloads) none of this happens, and the
-- game's window keeps its own look, place and size.
-- Only what decision 58 allows is done to Blizzard's frames: ClearAllPoints, SetPoint and SetScale on the window right
-- after the game places it and while the player drags it by its crest or name (decision 62; never in combat), and
-- SetAlpha and SetVertexColor on textures. The rest is our own frames, which let the mouse through (but the crest and
-- the name, which take it to be dragged).
local _, ns = ...
local UI = ns.UI
local Fr = {}
ns.Frame = Fr

Fr.CF_W, Fr.CF_H = 814, 426     -- the game's guild window (never resized)
Fr.BAR_H, Fr.PANEL_H = 64, 360  -- our bar and panel under it
Fr.RIM = 16    -- the frame's leather outside the column
Fr.CREST = 26  -- room above the column for the crest
Fr.EDGE = 8    -- kept free above that on the screen
Fr.BARS = 80   -- kept free under the column for the action bars
-- Media\WindowFrame (Journey's): nine pieces cut at 40/256 of it, drawn 48 big with 16 outside, so its leather (the
-- outer 18) lies outside the column and its gold corners reach in.
Fr.CUT, Fr.CORNER = 40 / 256, 48
Fr.CREST_SIZE, Fr.CREST_X, Fr.CREST_Y = 108, -12, 20  -- the crest's middle, from the window's top-left
Fr.BAND = 21   -- the window's title band, when it has no Bg to end at (the frame template's Bg starts 21 down)
-- The guild's name in the title band (SPEC decision 76): from the window's left, past the crest; its motto after a
-- thin gold line, as the panel's heading has its place's line; TITLE_END kept free for the window's buttons.
Fr.TITLE_X, Fr.TITLE_GAP, Fr.TITLE_END = 50, 10, 80
-- The side tabs' rail (SPEC decision 76): the frame, the bar and the panel are this much wider than the window. The
-- game puts its tabs (32 wide) just past the window's right edge.
Fr.RAIL = 44
Fr.TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
Fr.TAB_DIM = 0.62  -- a tab's art in the guild's metal, this much darker but the open one
-- Plain (off): the game puts the window at the left of the screen; our panel goes past its tabs.
Fr.PLAIN_LEFT, Fr.BESIDE = 16, 52
-- The window's own parts our frame takes the place of, by their keys on CommunitiesFrame: every texture and text in
-- them goes to alpha 0. Its background is darkened to the panel's. A part a client does not have is skipped (the
-- self-test says how many it found).
Fr.HIDE = { "NineSlice", "PortraitContainer", "PortraitOverlay", "TopTileStreaks", "TitleContainer" }
Fr.DARK = { Bg = { 0.32, 0.3, 0.28 } }

local function cf() return CommunitiesFrame end

-- Dressed: Guild Together moves, scales and dresses the window (decided once, at login).
function Fr:Dressed()
  if self.on == nil then self.on = not (ns.db and ns.db.plain == true) end
  return self.on
end

-- The switch (Your options, /gtf plain): kept for the account; it takes effect after a reload.
function Fr:SetDressed(on)
  if not ns.db then return end
  ns.db.plain = (not on) or nil
end

function Fr:WantDressed() return not (ns.db and ns.db.plain == true) end

-- The column's width: the window's, with the rail of side tabs beside it when dressed (the bar and the panel too).
function Fr:W() return self.CF_W + (self:Dressed() and self.RAIL or 0) end

-- The column's scale: its top EDGE under the screen's top (with the crest above it) and BARS free at the bottom,
-- never above 100%. At 768 tall that is 76%.
function Fr:Scale()
  local h = UIParent and UIParent:GetHeight() or 768
  local need = self.CREST + self.CF_H + self.BAR_H + self.PANEL_H + self.RIM
  return math.min(1, (h - self.EDGE - self.BARS) / need)
end

-- Where the column stands (SPEC decision 62), in screen units: x, the window's middle from the screen's middle; y,
-- the window's top under the screen's top. In the middle at the top until the player drags it (GuildTogetherForeverDB.spot, for
-- the account), and always kept on the screen: the crest under its top, the whole column (with the panel) above the
-- action bars, the frame inside its sides. The middle is the frame's, rail and all: the window a little left of it.
function Fr:Spot(s, x, y)
  s = s or self:Scale()
  local spot = ns.db and ns.db.spot
  local rail = self:W() - self.CF_W
  local mid = -rail / 2 * s
  x = x or (spot and tonumber(spot.x)) or mid
  y = y or (spot and tonumber(spot.y)) or 0
  local w, h = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local left = -(w / 2 - (self.CF_W / 2 + self.RIM) * s)
  local right = w / 2 - (self.CF_W / 2 + self.RIM + rail) * s
  local top = self.EDGE + self.CREST * s
  local low = math.max(top, h - self.BARS - (self.CF_H + self.BAR_H + self.PANEL_H + self.RIM) * s)
  if right < left then x = mid else x = math.max(left, math.min(right, x)) end
  return x, math.max(top, math.min(low, y))
end

-- Has the player moved it from the middle?
function Fr:Moved() return ns.db ~= nil and ns.db.spot ~= nil end

-- Back to the middle at the top (Your options).
function Fr:Center()
  if ns.db then ns.db.spot = nil end
  self:Place()
end

local function put(f, s, x, y)
  f:ClearAllPoints()
  -- (Offsets are in the window's own units: divided by its scale to stay the same on the screen.)
  f:SetPoint("TOP", UIParent, "TOP", x / s, -y / s)
end

-- Moves and scales the window, right after the game placed it; in combat, once combat ends.
function Fr:Place()
  local f = cf()
  if not f or not self:Dressed() then return end
  if ns.Combat:InCombat() then
    if not self.waiting then
      self.waiting = true
      ns.Combat:AfterCombat(function() self.waiting = nil; self:Place() end)
    end
    return
  end
  local s = self:Scale()
  f:SetScale(s)
  put(f, s, self:Spot(s))
  self.placed = (self.placed or 0) + 1
end

-- Dragging the crest or the name moves the column (never in combat): the window follows the cursor, kept on the
-- screen, and the spot is kept when it is let go.
local function cursor()
  local x, y = GetCursorPosition()
  local k = UIParent:GetEffectiveScale() or 1
  return x / k, y / k
end

function Fr:DragStart()
  local f = cf()
  if not f or not self.built or ns.Combat:InCombat() then return end
  local s = self:Scale()
  local x, y = self:Spot(s)
  local cx, cy = cursor()
  self.drag = { s = s, x = x, y = y, cx = cx, cy = cy }
  self.crest:SetScript("OnUpdate", function() Fr:DragMove() end)
end

function Fr:DragMove()
  local d, f = self.drag, cf()
  if not d or not f then return end
  if ns.Combat:InCombat() then return self:DragStop() end
  local cx, cy = cursor()
  d.nx, d.ny = self:Spot(d.s, d.x + (cx - d.cx), d.y - (cy - d.cy))
  put(f, d.s, d.nx, d.ny)
end

function Fr:DragStop()
  local d = self.drag
  if not d then return end
  self.drag = nil
  self.crest:SetScript("OnUpdate", nil)
  if d.nx and ns.db then ns.db.spot = { x = math.floor(d.nx + 0.5), y = math.floor(d.ny + 0.5) } end
end

-- The crest and the name take the mouse to be dragged, and say so.
local function handle(frame)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() Fr:DragStart() end)
  frame:SetScript("OnDragStop", function() Fr:DragStop() end)
  UI.Tooltip(frame, function() return ns.Guild() or ns.L.ADDON_NAME end, ns.L.MOVE_TIP)
end

-- Every texture and text of a part (and of its frames, all the way down) at alpha 0.
local function fade(part, n)
  if type(part) ~= "table" then return n end
  local kind = part.GetObjectType and part:GetObjectType()
  if kind == "Texture" or kind == "FontString" then
    part:SetAlpha(0)
    return n + 1
  end
  if part.GetRegions then
    for _, r in ipairs({ part:GetRegions() }) do
      local k = r.GetObjectType and r:GetObjectType()
      if k == "Texture" or k == "FontString" then r:SetAlpha(0); n = n + 1 end
    end
  end
  if part.GetChildren then
    for _, child in ipairs({ part:GetChildren() }) do n = fade(child, n) end
  end
  return n
end

-- Dresses the window once: its parts hidden, its background darkened. Returns how many parts it found.
function Fr:Dress()
  local f = cf()
  if not f or not self:Dressed() or self.dressed then return self.found or 0 end
  self.dressed = true
  local found = 0
  for _, key in ipairs(self.HIDE) do
    local part = f[key]
    if type(part) == "table" then
      local ok = pcall(fade, part, 0)
      if ok then found = found + 1 end
    end
  end
  for key, c in pairs(self.DARK) do
    local t = f[key]
    if type(t) == "table" and t.SetVertexColor then
      t:SetVertexColor(c[1] * UI.SHADE, c[2] * UI.SHADE, c[3] * UI.SHADE)
      found = found + 1
    end
  end
  self.found = found
  return found
end

---------------------------------------------------------------------------
-- The frame: our own textures around the column, letting the mouse through.
---------------------------------------------------------------------------
local function cut(t, col, row)
  local c = { { 0, Fr.CUT }, { Fr.CUT, 1 - Fr.CUT }, { 1 - Fr.CUT, 1 } }
  t:SetTexture(ns.MEDIA .. "WindowFrame")
  t:SetTexCoord(c[col][1], c[col][2], c[row][1], c[row][2])
  -- In the guild's leather (SPEC decision 68).
  t:SetVertexColor(UI.LEATHER[1], UI.LEATHER[2], UI.LEATHER[3])
  return t
end

local function quiet(parent, level)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(parent)
  f:SetFrameLevel(level)
  f:EnableMouse(false)
  return f
end

-- A gold line across the column with a diamond in its middle (where the window meets the bar, and the bar the panel).
local function ornament(parent)
  local g = UI.LOOK.gold
  local o = CreateFrame("Frame", nil, parent)
  o:SetSize(Fr:W(), 12)
  o:EnableMouse(false)
  local left = o:CreateTexture(nil, "OVERLAY")
  left:SetColorTexture(1, 1, 1, 1)
  left:SetPoint("LEFT", 30, 0)
  left:SetPoint("RIGHT", o, "CENTER", 0, 0)
  left:SetHeight(2)
  UI.SetGradient(left, "HORIZONTAL", { g[1], g[2], g[3], 0 }, { 1, 0.88, 0.54, 1 })
  local right = o:CreateTexture(nil, "OVERLAY")
  right:SetColorTexture(1, 1, 1, 1)
  right:SetPoint("LEFT", o, "CENTER", 0, 0)
  right:SetPoint("RIGHT", -30, 0)
  right:SetHeight(2)
  UI.SetGradient(right, "HORIZONTAL", { 1, 0.88, 0.54, 1 }, { g[1], g[2], g[3], 0 })
  local gem = o:CreateTexture(nil, "OVERLAY", nil, 1)
  gem:SetColorTexture(g[1], g[2], g[3], 1)
  gem:SetSize(8, 8)
  gem:SetPoint("CENTER")
  if gem.SetRotation then gem:SetRotation(math.rad(45)) end
  return o
end

-- Builds the frame around the window and our bar (and the panel, when it shows): bar and panel are Hall's.
function Fr:Build(bar, panel)
  local f = cf()
  if self.built or not f or not self:Dressed() then return end
  self.built = true
  self.bar, self.panel = bar, panel
  local k, o, rail = self.CORNER, self.RIM, self:W() - self.CF_W
  -- Around the window: just over its own level, so its buttons (the close button) stay on top.
  local hi = quiet(f, f:GetFrameLevel() + 1)
  -- The window's title band, under its buttons, down to where its background begins: its own border and title were
  -- in it (now at alpha 0), so the world showed through. Dark, as the background.
  local band = hi:CreateTexture(nil, "BACKGROUND")
  band:SetColorTexture(1, 1, 1, 1)
  band:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  band:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  if type(f.Bg) == "table" and f.Bg.GetTop then band:SetPoint("BOTTOM", f.Bg, "TOP", 0, 0)
  else band:SetHeight(self.BAND) end
  UI.SetGradient(band, "VERTICAL", UI.Shade({ 0.06, 0.05, 0.035, 1 }), UI.Shade({ 0.1, 0.085, 0.06, 1 }))
  self.band = band
  local tl = cut(hi:CreateTexture(nil, "OVERLAY"), 1, 1)
  tl:SetSize(k, k)
  tl:SetPoint("TOPLEFT", f, "TOPLEFT", -o, o)
  local tr = cut(hi:CreateTexture(nil, "OVERLAY"), 3, 1)
  tr:SetSize(k, k)
  tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", o + rail, o)
  local top = cut(hi:CreateTexture(nil, "OVERLAY"), 2, 1)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local l1 = cut(hi:CreateTexture(nil, "OVERLAY"), 1, 2)
  l1:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  l1:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", k - o, 0)
  local r1 = cut(hi:CreateTexture(nil, "OVERLAY"), 3, 2)
  r1:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
  r1:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", o - k + rail, 0)
  -- Around the bar and the panel: over them.
  local lo = quiet(f, panel:GetFrameLevel() + 100)
  local bl = cut(lo:CreateTexture(nil, "OVERLAY"), 1, 3)
  bl:SetSize(k, k)
  local br = cut(lo:CreateTexture(nil, "OVERLAY"), 3, 3)
  br:SetSize(k, k)
  local bottom = cut(lo:CreateTexture(nil, "OVERLAY"), 2, 3)
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local l2 = cut(lo:CreateTexture(nil, "OVERLAY"), 1, 2)
  l2:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -o, 0)
  l2:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local r2 = cut(lo:CreateTexture(nil, "OVERLAY"), 3, 2)
  r2:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", o + rail, 0)
  r2:SetPoint("BOTTOMLEFT", br, "TOPLEFT")
  self.hi, self.lo, self.bl, self.br = hi, lo, bl, br
  -- The side tabs' rail (SPEC decision 76): dark leather from the window's right edge to the frame's, under the game's
  -- tabs (which draw far above it), with a thin gold line where it meets the window.
  local r = CreateFrame("Frame", nil, f)
  r:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
  r:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
  r:SetWidth(rail)
  r:SetFrameLevel(f:GetFrameLevel())
  r:EnableMouse(false)
  local leather = r:CreateTexture(nil, "BACKGROUND")
  leather:SetAllPoints()
  leather:SetColorTexture(1, 1, 1, 1)
  UI.SetGradient(leather, "HORIZONTAL", UI.Leather({ 0.05, 0.04, 0.025, 0.98 }), UI.Leather({ 0.12, 0.095, 0.06, 0.98 }))
  local seam = r:CreateTexture(nil, "BORDER")
  seam:SetColorTexture(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.45)
  seam:SetPoint("TOPLEFT")
  seam:SetPoint("BOTTOMLEFT")
  seam:SetWidth(1)
  self.rail = r
  -- The lines between window and bar, and bar and panel.
  self.line1 = ornament(lo)
  self.line1:SetPoint("CENTER", f, "BOTTOM", rail / 2, 0)
  self.line2 = ornament(lo)
  self.line2:SetPoint("CENTER", bar, "BOTTOM", 0, 0)
  -- The crest over the top-left corner, in a soft gold light, and the guild's name beside it: above everything of the
  -- window's (Hall:Raise).
  local crest = CreateFrame("Frame", nil, f)
  crest:SetSize(self.CREST_SIZE, self.CREST_SIZE)
  crest:SetPoint("CENTER", f, "TOPLEFT", self.CREST_X, self.CREST_Y)
  local glow = crest:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture(ns.MEDIA .. "Glow")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.3)
  glow:SetPoint("TOPLEFT", -26, 26)
  glow:SetPoint("BOTTOMRIGHT", 26, -26)
  -- The shield, or the guild's own tabard (the Guild Master's choice, SPEC decision 68).
  crest.mark = UI.GuildCrest(crest, self.CREST_SIZE, UI.EMBLEM)
  crest.mark:SetPoint("CENTER")
  crest.icon = crest.mark.shield
  self.crest = crest
  -- The guild's name in the title band, in gold, and the motto after a thin gold line (SPEC decision 76).
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", self.TITLE_X, 0)
  title:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", self.TITLE_X, 0)
  title.name = UI.Color(UI.Text(title, "GameFontNormalLarge"), "goldHi")
  title.name:SetPoint("LEFT", 0, 0)
  title.name:SetWordWrap(false)
  title.rule = title:CreateTexture(nil, "ARTWORK")
  title.rule:SetColorTexture(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.35)
  title.rule:SetSize(1, 14)
  title.rule:SetPoint("LEFT", title.name, "RIGHT", self.TITLE_GAP, 0)
  title.motto = UI.Ink(UI.Text(title, "GameFontHighlightSmall"))
  title.motto:SetPoint("LEFT", title.rule, "RIGHT", self.TITLE_GAP, 0)
  title.motto:SetWordWrap(false)
  self.title = title
  handle(crest)
  handle(title)
  self:Name()
  self:Fit(false, false)
end

-- The same leather and gold around any frame of ours (the Guild Together screen, SPEC decision 64): nine pieces on a frame
-- over it at level (default: 100 above), letting the mouse through.
function Fr:Rim(frame, level)
  local k, o = self.CORNER, self.RIM
  local r = quiet(frame, level or frame:GetFrameLevel() + 100)
  local function piece(col, row) return cut(r:CreateTexture(nil, "OVERLAY"), col, row) end
  local tl, tr, bl, br = piece(1, 1), piece(3, 1), piece(1, 3), piece(3, 3)
  for _, t in ipairs({ tl, tr, bl, br }) do t:SetSize(k, k) end
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
  local top, bottom, left, right = piece(2, 1), piece(2, 3), piece(1, 2), piece(3, 2)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  return r
end

-- The guild's name in the title band, and the motto the Guild Master wrote after it (SPEC decisions 68 and 76), cut
-- short before the window's buttons; what takes the mouse to drag fits them.
function Fr:Name()
  local t = self.title
  if not t then return end
  local motto = ns.GuildData:Settings().theme.motto or ""
  t.name:SetText(ns.Guild() or "")
  t.motto:SetText(motto)
  t.rule:SetShown(motto ~= "")
  t.motto:SetShown(motto ~= "")
  local nw = math.ceil(t.name:GetStringWidth() or 100)
  local room = math.max(40, self.CF_W - self.TITLE_X - self.TITLE_END - nw - 2 * self.TITLE_GAP)
  t.motto:SetWidth(room)
  local mw = motto ~= "" and 2 * self.TITLE_GAP + 1 + math.min(room, math.ceil(t.motto:GetStringWidth() or 0)) or 0
  t:SetWidth(math.max(60, nw + mw))
end

-- The side tabs in the rail (SPEC decision 76): the art of each (its book tab) tinted in the guild's metal, darker but
-- the open one's; their icon and lights stay as they are, and the game places and shows them. Again whenever the
-- window changes (Hall:Place). Returns how many textures it tinted.
function Fr:Tabs()
  local f = cf()
  if not f or not self.built then return 0 end
  local g, n = UI.LOOK.gold, 0
  for _, key in ipairs(self.TABS) do
    local tab = f[key]
    if type(tab) == "table" and tab.GetRegions then
      local keep = {}
      if tab.Icon then keep[tab.Icon] = true end
      if tab.IconOverlay then keep[tab.IconOverlay] = true end
      for _, get in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetCheckedTexture", "GetPushedTexture",
        "GetDisabledTexture" }) do
        local t = tab[get] and tab[get](tab)
        if t then keep[t] = true end
      end
      local k = tab.GetChecked and tab:GetChecked() and 1 or self.TAB_DIM
      for _, r in ipairs({ tab:GetRegions() }) do
        if not keep[r] and r.GetObjectType and r:GetObjectType() == "Texture" then
          r:SetVertexColor(g[1] * k, g[2] * k, g[3] * k)
          n = n + 1
        end
      end
    end
  end
  self.tinted = n
  return n
end

-- The frame's bottom: under the panel when it shows, else under the bar, else (a community picked) under the window.
function Fr:Fit(barShown, panelShown)
  if not self.built then return end
  local f = cf()
  local under = (panelShown and self.panel) or (barShown and self.bar) or f
  local o = self.RIM
  self.bl:ClearAllPoints()
  self.bl:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT", -o, -o)
  self.br:ClearAllPoints()
  -- (The bar and the panel take the rail's width; the window alone ends at its own edge, the rail past it.)
  self.br:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", o + (under == f and self:W() - self.CF_W or 0), -o)
  self.line1:SetShown(barShown == true)
  self.line2:SetShown(barShown == true and panelShown == true)
end

-- The crest and the name draw over everything of the window's (from Hall:BlizzardTop: its strata, when higher than
-- theirs, and a level above it).
function Fr:Raise(strata, level)
  if not self.built then return end
  for _, f in ipairs({ self.crest, self.title }) do
    if strata then f:SetFrameStrata(strata) end
    f:SetFrameLevel(level)
  end
end

-- The guild's look as it comes from the Guild Master (SPEC decision 68): kept for this character, so its next reload
-- is in it; the crest and the name change at once, and the rest is said to need a reload, once.
function Fr:Theme()
  local g = ns.GuildData:Current()
  if not g or not ns.char then return end
  local th = g.settings.theme
  ns.char.theme = { accent = th.accent, leather = th.leather, shade = th.shade }
  self:Name()
  UI.RefreshCrests()
  local now = UI.theme
  local differs = now and (now.accent ~= th.accent or now.leather ~= th.leather or now.shade ~= th.shade)
  if differs and not self.toldTheme then
    self.toldTheme = true
    ns:Print(ns.L.THEME_RELOAD, true)
  end
  return differs
end

ns:On("GUILD_CHANGED", function() Fr:Name() end)
ns:On("ROSTER", function() Fr:Theme() end)
ns:On("GUILD_SETTINGS", function() Fr:Theme() end)
