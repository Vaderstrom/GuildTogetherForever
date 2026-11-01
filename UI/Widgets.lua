-- Small builders on top of Blizzard's own templates, so Guild Together looks like the game (SPEC §2). Only our own
-- frames are made or changed here. Templates that may be missing in a client are tried first and replaced by a plain
-- frame if the game does not know them.
local _, ns = ...
local UI = {}
ns.UI = UI

-- CreateFrame with a template the client may not have: falls back to the next template, then to none.
function UI.Create(kind, parent, ...)
  for i = 1, select("#", ...) do
    local ok, f = pcall(CreateFrame, kind, nil, parent, (select(i, ...)))
    if ok and f then return f end
  end
  return CreateFrame(kind, nil, parent)
end

-- A font string in one of the game's font objects ("GameFontNormal" is gold, "GameFontHighlight" white).
function UI.Text(parent, font, justify, layer)
  local t = parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlight")
  t:SetJustifyH(justify or "LEFT")
  return t
end

-- Text that wraps at width.
function UI.Wrap(parent, font, width)
  local t = UI.Text(parent, font)
  t:SetWidth(width)
  t:SetWordWrap(true)
  t:SetJustifyV("TOP")
  return t
end

-- title and text may be functions (asked each time the tooltip shows); text may hold several lines.
function UI.Tooltip(frame, title, text)
  frame:HookScript("OnEnter", function(self)
    -- A player's name: their card first (frame.tipPlayer, SPEC decision 75), then the frame's own line.
    if self.tipPlayer then
      UI.PlayerTip(self, self.tipPlayer, { nil, type(text) == "function" and text() or text })
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
    local body = type(text) == "function" and text() or text
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The gear in front of Settings (SPEC §2) as text markup: the game's own gear picture, else the gear icon.
-- Returns the markup and which picture it is (for the self-test).
UI.GEAR_ATLASES = { "questlog-icon-setting", "GM-icon-settings" }
UI.GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
function UI.Gear(size)
  local info = C_Texture and C_Texture.GetAtlasInfo
  for _, atlas in ipairs(UI.GEAR_ATLASES) do
    if info and info(atlas) then return ("|A:%s:%d:%d|a"):format(atlas, size, size), atlas end
  end
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(UI.GEAR_ICON, size, size), UI.GEAR_ICON
end

---------------------------------------------------------------------------
-- The look (SPEC decision 49, docs/mockup/GuildPlus.html): dark glass and gold. Smoky panels with a fine edge and
-- rounded corners, gold headings, quiet rows that light up in gold, a solid gold main button and a gold-outline second
-- one, red numbers as small glowing pills. Our shapes are white (Media, tools/make-look.lua) and tinted here.
---------------------------------------------------------------------------
UI.LOOK = {
  gold = { 0.95, 0.79, 0.36 }, goldHi = { 1, 0.88, 0.54 }, goldLo = { 0.72, 0.53, 0.16 },
  ink = { 0.95, 0.93, 0.86 }, sub = { 0.64, 0.61, 0.55 }, dark = { 0.1, 0.07, 0.02 }, red = { 0.86, 0.2, 0.17 },
  -- Over the guild window the panels are nearly solid (WoW cannot blur what is behind a frame).
  glass = { 0.063, 0.071, 0.09, 0.97 }, edge = { 1, 1, 1, 0.08 },
}
UI.ROUND = 8  -- pixels of each corner of Media\Glass and Media\Edge

-- Copied from Journey Together (UI/Widgets.lua): a gradient on a texture, in every client.
function UI.SetGradient(tex, orientation, c1, c2)
  if CreateColor and pcall(tex.SetGradient, tex, orientation, CreateColor(c1[1], c1[2], c1[3], c1[4]),
    CreateColor(c2[1], c2[2], c2[3], c2[4])) then return end
  if tex.SetGradientAlpha then tex:SetGradientAlpha(orientation, c1[1], c1[2], c1[3], c1[4], c2[1], c2[2], c2[3], c2[4]) end
end

-- A rounded shape ("Glass", filled, or "Edge", its outline) that stretches without stretching its corners; where the
-- client cannot slice a texture, a plain square. c: { r, g, b, a }.
function UI.Round(tex, shape, c)
  if tex.SetTextureSliceMargins then
    tex:SetTexture(ns.MEDIA .. shape)
    local m = UI.ROUND
    tex:SetTextureSliceMargins(m, m, m, m)
    if tex.SetTextureSliceMode then tex:SetTextureSliceMode(0) end
  elseif shape == "Glass" then
    tex:SetColorTexture(1, 1, 1, 1)
  else
    tex:SetColorTexture(1, 1, 1, 0)
  end
  if c then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
  return tex
end

-- A panel of glass on frame: its fill and its edge (BACKGROUND layer). fill, edge: colours (default: the look's).
function UI.Glass(frame, fill, edge)
  local f = UI.Round(frame:CreateTexture(nil, "BACKGROUND", nil, -6), "Glass", fill or UI.LOOK.glass)
  f:SetAllPoints()
  local e = UI.Round(frame:CreateTexture(nil, "BACKGROUND", nil, -5), "Edge", edge or UI.LOOK.edge)
  e:SetAllPoints()
  return f, e
end

---------------------------------------------------------------------------
-- The guild's look (SPEC decision 68): the Guild Master's theme, the same for every member. The accent (gold, goldHi,
-- goldLo of UI.LOOK), the frame's leather (UI.LEATHER) and how dark the panels are (UI.SHADE, and UI.LOOK.glass) are
-- set before our frames are made, from the theme this character last had from its guild (GuildTogetherForeverCharDB.theme):
-- a change shows at each member's next reload. The crest and the plate's text change at once (UI/Frame.lua).
---------------------------------------------------------------------------
UI.ACCENT_ORDER = { "gold", "silver", "bronze", "crimson", "emerald", "azure", "violet" }
UI.ACCENTS = {
  gold = { { 0.95, 0.79, 0.36 }, { 1, 0.88, 0.54 }, { 0.72, 0.53, 0.16 } },
  silver = { { 0.82, 0.84, 0.88 }, { 0.95, 0.96, 1 }, { 0.55, 0.57, 0.62 } },
  bronze = { { 0.82, 0.56, 0.33 }, { 0.94, 0.72, 0.5 }, { 0.56, 0.36, 0.18 } },
  crimson = { { 0.9, 0.34, 0.3 }, { 1, 0.52, 0.47 }, { 0.62, 0.16, 0.13 } },
  emerald = { { 0.4, 0.85, 0.52 }, { 0.62, 1, 0.72 }, { 0.2, 0.55, 0.32 } },
  azure = { { 0.42, 0.7, 1 }, { 0.66, 0.85, 1 }, { 0.22, 0.43, 0.75 } },
  violet = { { 0.73, 0.52, 1 }, { 0.86, 0.73, 1 }, { 0.46, 0.29, 0.73 } },
}
UI.LEATHER_ORDER = { "brown", "black", "red" }
UI.LEATHERS = { brown = { 1, 1, 1 }, black = { 0.42, 0.42, 0.46 }, red = { 1, 0.52, 0.46 } }
UI.SHADE_ORDER = { "dark", "darker", "black" }
UI.SHADES = { dark = 1, darker = 0.65, black = 0.35 }
UI.LEATHER, UI.SHADE = UI.LEATHERS.brown, 1
local GLASS = { UI.LOOK.glass[1], UI.LOOK.glass[2], UI.LOOK.glass[3] }

-- Puts a theme ({ accent, leather, shade }, or nil for the first look) into the look. Only before frames are made.
function UI.ApplyTheme(t)
  t = type(t) == "table" and t or {}
  local a = UI.ACCENTS[t.accent] or UI.ACCENTS.gold
  for i = 1, 3 do UI.LOOK.gold[i], UI.LOOK.goldHi[i], UI.LOOK.goldLo[i] = a[1][i], a[2][i], a[3][i] end
  UI.LEATHER = UI.LEATHERS[t.leather] or UI.LEATHERS.brown
  UI.SHADE = UI.SHADES[t.shade] or 1
  for i = 1, 3 do UI.LOOK.glass[i] = GLASS[i] * UI.SHADE end
  UI.theme = { accent = UI.ACCENTS[t.accent] and t.accent or "gold", leather = UI.LEATHERS[t.leather] and t.leather or "brown",
    shade = UI.SHADES[t.shade] and t.shade or "dark" }
end

-- A colour { r, g, b, a } as dark as the panels are, or in the leather's tint.
function UI.Shade(c) return { c[1] * UI.SHADE, c[2] * UI.SHADE, c[3] * UI.SHADE, c[4] } end
function UI.Leather(c) local l = UI.LEATHER return { c[1] * l[1], c[2] * l[2], c[3] * l[3], c[4] } end

ns:On("DB_READY", function() UI.ApplyTheme(ns.char and ns.char.theme) end)

-- The guild's crest at size: the Guild Together shield (Media\<file>), or the guild's own tabard from the game (its
-- emblem on its background colour, in a ring) when the Guild Master picked it and the guild has one. crest.shield is
-- the shield's texture. Every crest changes at once with UI.RefreshCrests().
UI.crests = {}
local function tabardInfo()
  local get = C_GuildInfo and C_GuildInfo.GetGuildTabardInfo
  if not get then return nil end
  local ok, info = pcall(get, "player")
  if not ok or type(info) ~= "table" or not info.emblemFileID then return nil end
  return info
end
UI.TabardInfo = tabardInfo

function UI.GuildCrest(parent, size, file)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(size, size)
  c.shield = c:CreateTexture(nil, "ARTWORK")
  c.shield:SetTexture(ns.MEDIA .. (file or UI.EMBLEM))
  c.shield:SetAllPoints()
  c.disc = c:CreateTexture(nil, "BACKGROUND")
  c.disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  c.disc:SetPoint("CENTER")
  c.disc:SetSize(size * 0.82, size * 0.82)
  c.emblem = c:CreateTexture(nil, "ARTWORK")
  c.emblem:SetPoint("CENTER")
  c.emblem:SetSize(size * 0.62, size * 0.62)
  c.ring = c:CreateTexture(nil, "OVERLAY")
  c.ring:SetTexture(ns.MEDIA .. "Ring")
  c.ring:SetAllPoints()
  function c.Refresh(self)
    local s = ns.GuildData and ns.GuildData:Settings()
    -- (nil, never false: false would hide the shield and show an empty disc.)
    local info = s and s.theme and s.theme.crest == "tabard" and tabardInfo() or nil
    self.shield:SetShown(info == nil)
    self.disc:SetShown(info ~= nil)
    self.emblem:SetShown(info ~= nil)
    self.ring:SetShown(info ~= nil)
    if not info then return end
    local function rgb(col, r, g, b)
      if type(col) == "table" and col.GetRGB then return col:GetRGB() end
      return r, g, b
    end
    self.disc:SetVertexColor(rgb(info.backgroundColor, 0.2, 0.2, 0.3))
    -- The game paints a tabard's emblem from its sheet of emblems, as the guild window's own list does; where it
    -- cannot, the emblem's own file.
    local paint = SetLargeGuildTabardTextures
    if not (paint and pcall(paint, "player", self.emblem, self.disc, nil)) then
      self.emblem:SetTexture(info.emblemFileID)
      self.emblem:SetTexCoord(0, 1, 0, 1)
      self.emblem:SetVertexColor(rgb(info.emblemColor, 1, 1, 1))
    end
    -- (No emblem drawn: the shield, rather than an empty disc.)
    if not self.emblem:GetTexture() then
      self.shield:Show()
      self.disc:Hide()
      self.emblem:Hide()
      self.ring:Hide()
    end
  end
  c:Refresh()
  UI.crests[#UI.crests + 1] = c
  return c
end

function UI.RefreshCrests() for _, c in ipairs(UI.crests) do c:Refresh() end end
-- The game's tabard may come after our frames: the crests follow it.
ns:RegisterEvent("PLAYER_GUILD_UPDATE", function() UI.RefreshCrests() end)
ns:RegisterEvent("GUILD_ROSTER_UPDATE", function() UI.RefreshCrests() end)

-- A colour of the look on a font string.
function UI.Color(t, key)
  local c = UI.LOOK[key]
  t:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  return t
end

-- Our buttons, in the game's manner (SPEC decision 59, docs/mockup/Frame.html; decision 53 had them gold): the main one
-- red with a gold edge and gold letters, a second one (ghost = true) dark leather with a darker gold edge. Both light up
-- under the mouse, sink when pressed, and turn grey when disabled.
local RED_HI, RED_LO = { 0.64, 0.165, 0.1 }, { 0.3, 0.047, 0.024 }
local function paintButton(b)
  local L = UI.LOOK
  local on = not b.IsEnabled or b:IsEnabled() ~= false
  local lift = b.over and on and 1.18 or 1
  if b.ghost then
    UI.SetGradient(b.fill, "VERTICAL", { 0.086 * lift, 0.07 * lift, 0.047 * lift, 0.95 },
      { 0.165 * lift, 0.14 * lift, 0.1 * lift, 0.95 })
    local e = on and (b.over and L.gold or L.goldLo) or L.sub
    b.edge:SetVertexColor(e[1], e[2], e[3], on and 1 or 0.35)
    UI.Color(b.label, on and (b.over and "goldHi" or "gold") or "sub")
  else
    if on then
      UI.SetGradient(b.fill, "VERTICAL", { RED_LO[1] * lift, RED_LO[2] * lift, RED_LO[3] * lift, 1 },
        { RED_HI[1] * lift, RED_HI[2] * lift, RED_HI[3] * lift, 1 })
    else UI.SetGradient(b.fill, "VERTICAL", { 0.2, 0.2, 0.22, 1 }, { 0.3, 0.3, 0.32, 1 }) end
    local e = b.over and L.goldHi or L.gold
    b.edge:SetVertexColor(e[1], e[2], e[3], on and 1 or 0.25)
    UI.Color(b.label, on and "goldHi" or "sub")
  end
end

function UI.Button(parent, label, width, onClick, ghost)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 100, 22)
  b.ghost = ghost == true
  b.fill = UI.Round(b:CreateTexture(nil, "BACKGROUND"), "Glass")
  b.fill:SetAllPoints()
  b.edge = UI.Round(b:CreateTexture(nil, "BORDER"), "Edge")
  b.edge:SetAllPoints()
  b.label = UI.Text(b, "GameFontNormal", "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  if b.SetFontString then b:SetFontString(b.label) end
  b:SetText(label)
  b:SetScript("OnClick", function() onClick() end)
  b:SetScript("OnEnter", function(self) self.over = true; paintButton(self) end)
  b:SetScript("OnLeave", function(self) self.over = nil; paintButton(self) end)
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() ~= false then self.label:SetPoint("CENTER", 1, -1) end end)
  b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
  b:SetScript("OnEnable", paintButton)
  b:SetScript("OnDisable", paintButton)
  -- (A tooltip added later hooks OnEnter and OnLeave, after these.)
  b.SetGhost = function(self, on) self.ghost = on == true; paintButton(self) end
  paintButton(b)
  return b
end

-- A button's name inside a sentence, in gold ("Click Duel"), without its "...".
function UI.Key(label) return "|cffffd100" .. (label or ""):gsub("%.%.%.$", "") .. "|r" end

-- The action waiting for you (SPEC decision 47): the button glows softly, on and off.
function UI.Glow(b, on)
  if not on and not b.glow then return end
  if not b.glow then
    -- A soft gold light around the button, under it, so only its edge shows.
    local t = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(ns.MEDIA .. "Glow")
    t:SetBlendMode("ADD")
    t:SetVertexColor(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.9)
    t:SetPoint("TOPLEFT", -14, 12)
    t:SetPoint("BOTTOMRIGHT", 14, -12)
    t.pulse = t:CreateAnimationGroup()
    t.pulse:SetLooping("BOUNCE")
    local a = t.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(1)
    a:SetDuration(0.8)
    a:SetSmoothing("IN_OUT")
    b.glow = t
  end
  b.glow:SetShown(on == true)
  if on then b.glow.pulse:Play() else b.glow.pulse:Stop() end
end

-- A count of what waits for you, as a small red pill with a number on a tab's corner, softly glowing (SPEC decisions
-- 47 and 49).
function UI.Badge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(16, 16)
  f:SetFrameLevel(parent:GetFrameLevel() + 5)
  local glow = f:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture(ns.MEDIA .. "Glow")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(UI.LOOK.red[1], UI.LOOK.red[2], UI.LOOK.red[3], 0.8)
  glow:SetPoint("TOPLEFT", -8, 8)
  glow:SetPoint("BOTTOMRIGHT", 8, -8)
  local pill = UI.Round(f:CreateTexture(nil, "ARTWORK"), "Glass", UI.LOOK.red)
  pill:SetAllPoints()
  UI.Round(f:CreateTexture(nil, "ARTWORK", nil, 1), "Edge", { 1, 0.75, 0.7, 0.5 }):SetAllPoints()
  f.text = UI.Text(f, "GameFontHighlightSmall", "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  f.SetCount = function(self, n)
    local was = self.n or 0
    self.n = n or 0
    self.text:SetText(self.n > 9 and "9+" or tostring(self.n))
    -- Two letters make the pill wider.
    self:SetWidth(self.n > 9 and 22 or 16)
    self:SetShown(self.n > 0)
    -- One more: the pill pops (SPEC decision 53).
    if self.n > was and UI.Motion() and UI.Visuals then
      self.pop = self.pop or UI.Visuals.Pop(self)
      self.pop:Stop()
      self.pop:Play()
    end
  end
  f:SetCount(0)
  return f
end

---------------------------------------------------------------------------
-- Our glass controls (SPEC decision 53): a text field, a tick box, a radio button, a toggle, a stepper and a dropdown,
-- drawn with the look's shapes instead of the game's templates. A control is a well of darker glass with a fine
-- edge; the edge turns gold under the mouse, while typing, and when on. Each keeps what the pages use: Refresh(),
-- GetChecked() and SetChecked(), Click(), its label.
---------------------------------------------------------------------------
local WELL, EDGE = { 0, 0, 0, 0.45 }, { 1, 1, 1, 0.16 }

-- The well's fill and edge on frame (or on its box, a part of it), and how hot it looks: 0 quiet, 1 under the mouse,
-- 2 on (or typing).
local function well(frame, box)
  box = box or frame
  frame.fill = UI.Round(frame:CreateTexture(nil, "BACKGROUND"), "Glass", WELL)
  frame.fill:SetAllPoints(box)
  frame.edge = UI.Round(frame:CreateTexture(nil, "BORDER"), "Edge", EDGE)
  frame.edge:SetAllPoints(box)
end
local function heat(frame, n)
  local g = UI.LOOK.gold
  if n == 0 then frame.edge:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
  else frame.edge:SetVertexColor(g[1], g[2], g[3], n == 1 and 0.55 or 0.95) end
end

-- A label to the right of a small control.
local function sideLabel(c, label, font, gap)
  c.label = UI.Text(c, font or "GameFontHighlightSmall")
  c.label:SetPoint("LEFT", c, "RIGHT", gap or 2, 1)
  c.label:SetText(label or "")
end

-- A check button of ours: paint(self) shows its state; a click flips it, paints, then runs set.
local function switch(parent, w, h, paint, get, set)
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(w, h)
  c.Paint = paint
  c:SetScript("OnClick", function(self)
    self:Paint()
    set(self:GetChecked() and true or false)
  end)
  c:SetScript("OnEnter", function(self) self.over = true; self:Paint() end)
  c:SetScript("OnLeave", function(self) self.over = nil; self:Paint() end)
  c.Refresh = function(self)
    self:SetChecked(get())
    self:Paint()
  end
  return c
end

-- A tick box with its label to the right: a small glass square, a gold tick when on. get() -> bool; set(bool).
function UI.Check(parent, label, get, set, font)
  local c = switch(parent, 24, 24, function(self)
    local on = self:GetChecked()
    heat(self, on and 2 or (self.over and 1 or 0))
    self.tick:SetShown(on)
  end, get, set)
  local box = CreateFrame("Frame", nil, c)
  box:SetSize(16, 16)
  box:SetPoint("LEFT", 4, 0)
  well(c, box)
  c.tick = c:CreateTexture(nil, "ARTWORK")
  c.tick:SetTexture(ns.MEDIA .. "Tick")
  c.tick:SetVertexColor(UI.LOOK.goldHi[1], UI.LOOK.goldHi[2], UI.LOOK.goldHi[3], 1)
  c.tick:SetSize(18, 18)
  c.tick:SetPoint("CENTER", box, "CENTER", 1, 0)
  sideLabel(c, label, font, 0)
  c:Paint()
  return c
end

-- A round choice with its label: a dark disc in a thin ring (gold when picked), a gold dot when picked. get() -> bool;
-- pick() when clicked. (Round at any size: the rounded glass of other wells reads as a square this small.)
function UI.Radio(parent, label, get, pick)
  local r = switch(parent, 18, 18, function(self)
    local on = self:GetChecked()
    heat(self, on and 2 or (self.over and 1 or 0))
    self.dot:SetShown(on)
  end, get, function() end)
  r.edge = r:CreateTexture(nil, "BACKGROUND")
  r.edge:SetTexture(ns.MEDIA .. "Dot")
  r.edge:SetAllPoints()
  r.fill = r:CreateTexture(nil, "BORDER")
  r.fill:SetTexture(ns.MEDIA .. "Dot")
  r.fill:SetPoint("TOPLEFT", 1.5, -1.5)
  r.fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
  r.fill:SetVertexColor(0.035, 0.035, 0.045, 1)
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetTexture(ns.MEDIA .. "Dot")
  r.dot:SetVertexColor(UI.LOOK.goldHi[1], UI.LOOK.goldHi[2], UI.LOOK.goldHi[3], 1)
  r.dot:SetSize(8, 8)
  r.dot:SetPoint("CENTER")
  -- A radio stays as get() says; pick() decides (it may ask first).
  r:SetScript("OnClick", function(self)
    self:SetChecked(get())
    self:Paint()
    pick()
  end)
  sideLabel(r, label, nil, 3)
  r:Paint()
  return r
end

-- A switch for something on or off (a place, a feature, the tax): a glass pill whose knob slides right and turns gold
-- when on. The API of UI.Check.
function UI.Toggle(parent, label, get, set, font)
  local t = switch(parent, 30, 16, function(self)
    local on = self:GetChecked()
    local g = UI.LOOK.gold
    heat(self, on and 2 or (self.over and 1 or 0))
    if on then self.fill:SetVertexColor(g[1], g[2], g[3], 0.3) else self.fill:SetVertexColor(WELL[1], WELL[2], WELL[3], WELL[4]) end
    local k = on and UI.LOOK.goldHi or UI.LOOK.sub
    self.knob:SetVertexColor(k[1], k[2], k[3], 1)
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self, on and "RIGHT" or "LEFT", on and -8 or 8, 0)
  end, get, set)
  well(t)
  t.knob = t:CreateTexture(nil, "ARTWORK")
  t.knob:SetTexture(ns.MEDIA .. "Dot")
  t.knob:SetSize(12, 12)
  sideLabel(t, label, font, 6)
  t:Paint()
  return t
end

-- A one-line text field of glass (no set: a plain box for a form; the flow reads it).
function UI.Field(parent, width, maxLetters)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, 22)
  e:SetAutoFocus(false)
  e:SetMaxLetters(maxLetters or 40)
  e:SetFontObject("GameFontHighlight")
  e:SetTextInsets(7, 7, 0, 0)
  well(e)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) heat(self, 2) end)
  e:SetScript("OnEditFocusLost", function(self) heat(self, 0) end)
  e:SetScript("OnEnter", function(self) if not self:HasFocus() then heat(self, 1) end end)
  e:SetScript("OnLeave", function(self) if not self:HasFocus() then heat(self, 0) end end)
  return e
end

-- A text field for a setting. set(text) runs on Enter or when the field loses focus; get() fills it again.
function UI.Edit(parent, width, maxLetters, get, set)
  local e = UI.Field(parent, width, maxLetters)
  e.Refresh = function(self) if not self:HasFocus() then self:SetText(get() or "") end end
  e:SetScript("OnEscapePressed", function(self)
    self:SetText(get() or "")
    self:ClearFocus()
  end)
  e:HookScript("OnEditFocusLost", function(self)
    set(self:GetText())
    self:SetText(get() or "")
  end)
  return e
end

-- A number with a minus and a plus on either side (the field in the middle can be typed in too): set(text) as
-- UI.Edit, step: how much one press adds. Its width is the whole control's.
function UI.Stepper(parent, width, maxLetters, get, set, step)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width, 22)
  local e = UI.Edit(holder, width - 44, maxLetters, get, set)
  e:SetPoint("CENTER")
  e:SetJustifyH("CENTER")
  local function press(sign)
    local n = tonumber(get()) or 0
    set(tostring(n + sign * (step or 1)))
    e:SetText(get() or "")
  end
  holder.minus = UI.Button(holder, "-", 20, function() press(-1) end, true)
  holder.minus:SetPoint("LEFT")
  holder.plus = UI.Button(holder, "+", 20, function() press(1) end, true)
  holder.plus:SetPoint("RIGHT")
  holder.box = e
  holder.Refresh = function() e:Refresh() end
  return holder
end

-- The open dropdown's list (one for all of them): rows of glass over everything, closed by a pick or by a click
-- anywhere else.
local menu
local function closeMenu()
  if menu and menu:IsShown() then menu:Hide() end
end
local function openMenu(owner, list, value, pick)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    UI.Glass(menu, { 0.05, 0.055, 0.07, 0.98 }, { UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.6 })
    menu.rows = {}
    menu:SetScript("OnEvent", function(self)
      if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self)
      self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
      if self.owner then self.owner.open = nil; self.owner:Paint() end
      self.owner = nil
    end)
  end
  menu:Hide()
  menu.owner = owner
  local w = owner:GetWidth()
  for i, x in ipairs(list) do
    local r = menu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, menu)
      r:SetHeight(20)
      r.hi = r:CreateTexture(nil, "HIGHLIGHT")
      r.hi:SetAllPoints()
      r.hi:SetColorTexture(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.15)
      r.text = UI.Text(r, "GameFontHighlightSmall")
      r.text:SetPoint("LEFT", 9, 0)
      r.text:SetPoint("RIGHT", -9, 0)
      r.text:SetWordWrap(false)
      menu.rows[i] = r
    end
    r:SetWidth(w - 4)
    r:SetPoint("TOPLEFT", 2, -3 - (i - 1) * 20)
    r.text:SetText(x[2])
    UI.Color(r.text, x[1] == value and "goldHi" or "ink")
    r:SetScript("OnClick", function()
      menu:Hide()
      if x[1] ~= value then pick(x[1]) end
    end)
    r:Show()
  end
  for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
  menu:SetSize(w, #list * 20 + 6)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  menu:Show()
  owner.open = true
end
UI.CloseMenu = closeMenu

-- A dropdown: a glass field showing the choice, with a chevron; a click lists the choices under it.
-- d:Set(list, value, pick): list = { { value, text }, ... }; pick(value) runs when another is picked.
function UI.Dropdown(parent, width)
  local d = CreateFrame("Button", nil, parent)
  d:SetSize(width, 22)
  well(d)
  d.text = UI.Text(d, "GameFontHighlight")
  d.text:SetPoint("LEFT", 8, 0)
  d.text:SetPoint("RIGHT", -24, 0)
  d.text:SetWordWrap(false)
  d.text:SetJustifyH("LEFT")
  d.arrow = d:CreateTexture(nil, "ARTWORK")
  d.arrow:SetTexture(ns.MEDIA .. "Chevron")
  d.arrow:SetSize(12, 12)
  d.arrow:SetPoint("RIGHT", -8, 0)
  d.Paint = function(self)
    heat(self, self.open and 2 or (self.over and 1 or 0))
    local c = (self.over or self.open) and UI.LOOK.goldHi or UI.LOOK.gold
    self.arrow:SetVertexColor(c[1], c[2], c[3], 1)
  end
  d.Set = function(self, list, value, pick)
    self.list, self.value, self.pick = list, value, pick
    local shown = ""
    for _, x in ipairs(list) do if x[1] == value then shown = x[2] end end
    self.text:SetText(shown)
  end
  d:SetScript("OnClick", function(self)
    if self.open then return closeMenu() end
    openMenu(self, self.list or {}, self.value, function(v) if self.pick then self.pick(v) end end)
    self:Paint()
  end)
  d:SetScript("OnEnter", function(self) self.over = true; self:Paint() end)
  d:SetScript("OnLeave", function(self) self.over = nil; self:Paint() end)
  d:SetScript("OnHide", function(self) if self.open then closeMenu() end end)
  d:Paint()
  return d
end

-- The background of our part of the window: dark glass, lighter at the top, with a fine edge.
function UI.Inset(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = UI.Glass(f, { 1, 1, 1, 1 })
  UI.SetGradient(fill, "VERTICAL", { 0.035, 0.04, 0.05, 0.98 }, { 0.075, 0.08, 0.1, 0.98 })
  return f
end

---------------------------------------------------------------------------
-- What a pane shows, laid out top to bottom on every refresh (UI.PaneFlow). Each piece is
-- made once by its key and kind and reused; pieces not placed in a refresh are hidden. The features of a place share
-- one pane, so one key may come back as another kind of piece (a rule in the Gazette, a row in Records): that kind
-- gets a piece of its own, and the other waits, hidden, until its feature shows again.
--   local f = UI.PaneFlow(pane); f:Begin(); f:Text("who", "..."); f:Buttons("act", { { "Accept", fn } }); f:End()
---------------------------------------------------------------------------
local Flow = {}
Flow.__index = Flow
UI.Flow = Flow -- (UI/Visuals.lua adds the games' pictures)
UI.FLOW_GAP = 6

-- A flow in a pane's list (UI.Pane): its full width, from the top.
function UI.PaneFlow(pane)
  return setmetatable({ pane = pane, card = pane.child, width = pane.inner, top = 0, pad = 0, items = {}, used = {} }, Flow)
end

function Flow:Begin()
  self.y = self.top
  self.picked = nil
  wipe(self.used)
end

function Flow:piece(key, make, kind)
  kind = kind or "?"
  local it = self.items[key]
  if it and it.flowKind ~= kind then
    self.spare = self.spare or {}
    self.spare[it.flowKind .. "|" .. key] = it
    it:Hide()
    it = self.spare[kind .. "|" .. key]
    self.spare[kind .. "|" .. key] = nil
  end
  if not it then
    it = make()
    it.flowKind = kind
  end
  self.items[key] = it
  self.used[key] = true
  it:ClearAllPoints()
  it:Show()
  return it
end

function Flow:Space(h) self.y = self.y - (h or UI.FLOW_GAP) end

-- Text across the card (it wraps). font: default GameFontHighlightSmall.
function Flow:Text(key, text, font)
  font = font or "GameFontHighlightSmall"
  local t = self:piece(key, function() return UI.Wrap(self.card, font, self.width) end, "text:" .. font)
  t:SetText(text)
  if font == "GameFontDisableSmall" then UI.Ink(t) end
  t:SetPoint("TOPLEFT", self.pad, self.y)
  self.y = self.y - math.ceil(t:GetStringHeight() or 12) - UI.FLOW_GAP
  return t
end

-- A tick box with a label that wraps across the card. get() -> bool; set(bool); tip = { title, text } (each may be a
-- function). The piece is reused, so get, set and tip may change from one refresh to the next.
function Flow:Check(key, label, get, set, tip)
  local b = self:piece(key, function()
    local c
    c = UI.Check(self.card, "", function() return c.get() end, function(on) c.set(on) end)
    c.label:SetWidth(self.width - 34)
    c.label:SetWordWrap(true)
    c.label:SetJustifyH("LEFT")
    local function ask(x) if type(x) == "function" then return x() end return x end
    UI.Tooltip(c, function() return ask(c.tip and c.tip[1]) or c.label:GetText() end,
      function() return ask(c.tip and c.tip[2]) end)
    return c
  end, "check")
  b.get, b.set, b.tip = get, set, tip
  b.label:SetText(label)
  b:Refresh()
  b:SetPoint("TOPLEFT", self.pad, self.y)
  self.y = self.y - math.max(24, math.ceil(b.label:GetStringHeight() or 14) + 8)
  return b
end

-- A name on the left and a value on the right, on one line (red: the value in red, a balance below 0).
function Flow:Pair(key, left, right, red)
  local l = self:piece(key .. ".l", function() return UI.Text(self.card, "GameFontDisableSmall") end, "pair.l")
  local r = self:piece(key .. ".r", function() return UI.Text(self.card, "GameFontHighlightSmall", "RIGHT") end, "pair.r")
  l:SetText(left)
  r:SetText(right)
  UI.Ink(l)
  if red then r:SetTextColor(0.7, 0.08, 0.05) else r:SetTextColor(1, 1, 1) end
  l:SetPoint("TOPLEFT", self.pad, self.y)
  r:SetPoint("TOPRIGHT", -self.pad, self.y)
  self.y = self.y - 16
end

-- Red buttons side by side: list = { { label, onClick, width, next = true }, ... } (next: it glows, it waits for you;
-- list.quiet: all of them outlines, as tools under the main buttons); an optional note after them.
function Flow:Buttons(key, list, note)
  local x = self.pad
  for i, b in ipairs(list) do
    -- The first is the main button (gold), the others outlines.
    local ghost = i > 1 or list.quiet == true
    local btn = self:piece(key .. "." .. i, function()
      return UI.Button(self.card, "", 100, function() end, ghost)
    end, ghost and "button:ghost" or "button:main")
    btn:SetText(b[1])
    btn:SetWidth(b[3] or math.max(80, math.ceil((btn:GetTextWidth() or 60) + 24)))
    btn:SetScript("OnClick", function() b[2]() end)
    -- (off: greyed, as while you are not near the player it needs, SPEC decision 72.)
    btn:SetEnabled(b.off ~= true)
    -- A button that would run past the right edge starts a new line.
    if x > self.pad and x + btn:GetWidth() > self.pad + self.width then
      x = self.pad
      self.y = self.y - 22 - 4
    end
    btn:SetPoint("TOPLEFT", x, self.y)
    UI.Glow(btn, b.next and not b.off)
    x = x + (btn:GetWidth() or 100) + 6
  end
  if note then
    local t = self:piece(key .. ".note", function() return UI.Text(self.card, "GameFontDisableSmall") end, "note")
    UI.Ink(t):SetText(note)
    t:SetPoint("LEFT", self.card, "TOPLEFT", x + 2, self.y - 11)
  end
  self.y = self.y - 22 - UI.FLOW_GAP
end

-- A line of text with one small button at its right end (glowing when it waits for you: nxt).
function Flow:Line(key, text, label, onClick, sub, nxt)
  local t = self:piece(key .. ".t", function() return UI.Text(self.card, "GameFontHighlightSmall") end, "line.t")
  t:SetText(text)
  t:SetWordWrap(true)
  t:SetPoint("TOPLEFT", self.pad, self.y - 4)
  local h = 22
  if sub then
    local s = self:piece(key .. ".s", function() return UI.Text(self.card, "GameFontDisableSmall") end, "line.s")
    UI.Ink(s):SetText(sub)
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
    h = 30
  end
  if label then
    local b = self:piece(key .. ".b", function() return UI.Button(self.card, "", 90, function() end) end, "line.b")
    b:SetText(label)
    b:SetWidth(math.max(70, math.ceil((b:GetTextWidth() or 60) + 20)))
    b:SetScript("OnClick", function() onClick() end)
    b:SetPoint("TOPRIGHT", -self.pad, self.y)
    UI.Glow(b, nxt)
    t:SetPoint("RIGHT", b, "LEFT", -6, 0)
    t:SetWordWrap(false)
  end
  self.y = self.y - h - 2
end

-- A text box with its label above it (made once: what the player typed stays). Returns the box.
function Flow:Field(key, label, width, x, keepY)
  local l = self:piece(key .. ".l", function() return UI.Text(self.card, "GameFontHighlightSmall") end, "label")
  local e = self:piece(key, function() return UI.Field(self.card, width, 40) end, "field")
  l:SetText(label)
  l:SetPoint("TOPLEFT", x or self.pad, self.y)
  e:SetPoint("TOPLEFT", x or self.pad, self.y - 14)
  if not keepY then self.y = self.y - 42 end
  return e
end

-- A dropdown under a small label, as Flow:Field: list = { { value, text }, ... }; value: the one picked; pick(value)
-- when another is picked.
function Flow:Dropdown(key, label, list, value, pick, width, x, keepY)
  local l = self:piece(key .. ".l", function() return UI.Text(self.card, "GameFontHighlightSmall") end, "label")
  local d = self:piece(key, function() return UI.Dropdown(self.card, width or (self.width - 2 * self.pad)) end, "dropdown")
  d:Set(list, value, pick)
  l:SetText(label)
  l:SetPoint("TOPLEFT", x or self.pad, self.y)
  d:SetPoint("TOPLEFT", x or self.pad, self.y - 14)
  if not keepY then self.y = self.y - 42 end
  return d
end

-- Number boxes for rolls in a row: list = { { big, small, red }, ... }; wraps onto more rows.
function Flow:Chips(key, list)
  local w, h, gap = 46, 34, 4
  local perRow = math.max(1, math.floor((self.width + gap) / (w + gap)))
  for i, c in ipairs(list) do
    local chip = self:piece(key .. "." .. i, function()
      local f = UI.Create("Frame", self.card, "BackdropTemplate")
      f:SetSize(w, h)
      if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      end
      f.big = UI.Text(f, "GameFontNormalLarge", "CENTER")
      f.big:SetPoint("TOP", 0, -3)
      f.small = UI.Text(f, "GameFontDisableSmall", "CENTER")
      f.small:SetPoint("BOTTOM", 0, 3)
      f.small:SetWidth(w - 2)
      f.small:SetWordWrap(false)
      return f
    end, "chip")
    chip.big:SetText(c[1])
    chip.small:SetText(c[2])
    if chip.SetBackdropColor then
      if c[3] then chip:SetBackdropColor(0.29, 0.07, 0.05, 1); chip:SetBackdropBorderColor(0.75, 0.22, 0.17, 1)
      else chip:SetBackdropColor(0.1, 0.11, 0.14, 1); chip:SetBackdropBorderColor(0.23, 0.24, 0.27, 1) end
    end
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    chip:SetPoint("TOPLEFT", self.pad + col * (w + gap), self.y - row * (h + gap))
  end
  local rows = math.ceil(#list / perRow)
  self.y = self.y - rows * (h + gap) - UI.FLOW_GAP + gap
end

-- Squares in rows of cols across the card (a bingo card): list = { { text, on }, ... }; on squares are green.
function Flow:Grid(key, cols, list)
  local gap, h = 3, 36
  local w = math.floor((self.width - gap * (cols - 1)) / cols)
  for i, c in ipairs(list) do
    local sq = self:piece(key .. "." .. i, function()
      local f = UI.Create("Frame", self.card, "BackdropTemplate")
      if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      end
      f.text = UI.Text(f, "GameFontHighlightSmall", "CENTER")
      f.text:SetPoint("TOPLEFT", 2, -2)
      f.text:SetPoint("BOTTOMRIGHT", -2, 2)
      return f
    end, "square")
    sq:SetSize(w, h)
    sq.text:SetText(c[1])
    if sq.SetBackdropColor then
      if c[2] then sq:SetBackdropColor(0.07, 0.25, 0.08, 1); sq:SetBackdropBorderColor(0.18, 0.54, 0.23, 1)
      else sq:SetBackdropColor(0.08, 0.08, 0.11, 1); sq:SetBackdropBorderColor(0.16, 0.18, 0.21, 1) end
    end
    if c[2] then sq.text:SetTextColor(0.72, 1, 0.69) else sq.text:SetTextColor(0.81, 0.81, 0.81) end
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    sq:SetPoint("TOPLEFT", self.pad + col * (w + gap), self.y - row * (h + gap))
  end
  self.y = self.y - math.ceil(#list / cols) * (h + gap) - UI.FLOW_GAP + gap
end

-- Hides what this refresh did not place and sizes the card. Returns its height.
function Flow:End()
  for key, it in pairs(self.items) do if not self.used[key] then it:Hide() end end
  local h = -self.y + 4
  self.card:SetHeight(h)
  -- A row picked anew (by a click, or picked for you) is brought into sight when it lies outside it.
  local p = self.picked and self.items[self.picked]
  if p and self.picked ~= self.lastPick then self:Reveal(p.flowTop, UI.ROW_H) end
  self.lastPick = self.picked
  return h
end

-- Scrolls the pane, if need be, so that top .. top + h of the card is in sight.
function Flow:Reveal(top, h)
  local pane = self.pane
  local sf = pane and pane.scroll
  local v, room = sf and sf:GetVerticalScroll(), sf and sf:GetHeight()
  if not (top and v and room and room > 0 and pane.bar and pane.bar.To) then return end
  if top < v or top + h > v + room then pane.bar.To(top - math.max(0, (room - h) / 2)) end
end

---------------------------------------------------------------------------
-- The game's textures we still draw with, and the sizes of our parts (two 300-wide panes fill our part of the
-- window, as Perks and Rewards do).
---------------------------------------------------------------------------
UI.TEX = {
  -- The "i" on the Guild Rewards header, and the guild reputation bar's fill.
  help = { "Interface\\common\\help-i", 0, 1, 0, 1 },
  bar = { "Interface\\TargetingFrame\\UI-StatusBar", 0, 1, 0, 1 },
}
UI.STRIP_H, UI.ROW_H, UI.ROW_GAP, UI.FOOT_H = 22, 44, 3, 30
UI.TILE_H, UI.TILE_GAP = 58, 7 -- the features in the guild window, two to a line (SPEC decision 57)

-- Our icons (SPEC decision 53). Most are painted: a medallion in Media\Icons (the Horde's: IconsHorde, crimson discs),
-- an 8 x 8 atlas of 128-pixel cells, written "gp:<cell>" (cells 1 to 16 are Journey Together's own, but for cell 5,
-- Gambling's). One icon per feature, place, game and punishment, never one for two things (tests/test_hall.lua checks
-- it). The rest are the game's own (Interface\Icons), shown in the gold ring. The self-test checks each one loads.
local function gp(cell) return "gp:" .. cell end
UI.ICON = {
  -- The game's own: money, fish, items and the unknown.
  coin = "Interface\\Icons\\INV_Misc_Coin_01", coins = "Interface\\Icons\\INV_Misc_Coin_02",
  fish = "Interface\\Icons\\INV_Misc_Fish_02", bag = "Interface\\Icons\\INV_Misc_Bag_10",
  question = "Interface\\Icons\\INV_Misc_QuestionMark", tabard = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
  bones = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  -- The places along the top.
  pl_home = gp(14), pl_challenges = gp(17), pl_games = gp(18), pl_treasury = gp(19), pl_professions = gp(20),
  pl_punishments = gp(21), pl_council = gp(22), pl_manage = gp(13), pl_gambling = gp(5),
  -- (The Calendar's is our own single icon, art/prompts/icon-calendar.json, in cell 64.)
  pl_calendar = gp(64),
  -- The features, and what they hold.
  duel = gp(8), prize = gp(23), hood = gp(11), skull = gp(15), dice = gp(39), ticket = gp(40), rosette = gp(38),
  journey = gp(16), purse = gp(33), quill = gp(9), chalice = gp(34), vault = gp(7), marks = gp(35), tools = gp(36),
  parcel = gp(37), anvil = gp(20), shackles = gp(29), wanted = gp(30), basket = gp(31), throne = gp(25),
  scroll = gp(3), ballot = gp(26), scales = gp(10), flag = gp(27), chain = gp(28), paper = gp(41), book = gp(1),
  laurel = gp(44), boar = gp(42), candle = gp(43),
  -- The duel crown, the officers, a letter (the Calendar's events), and what is coming: the player card, seasons, your
  -- options and the welcome.
  crown = gp(24), officer = gp(6), mail = gp(12), portrait = gp(32), seasons = gp(45),
  options = gp(46), welcome = gp(47),
  -- The guild games, one each (Guild/Games.lua KINDS).
  bingo = gp(48), derby = gp(59), flash = gp(4), hunt = gp(2), fashion = gp(60), gnomes = gp(61), traitors = gp(62),
  santa = gp(63),
  -- The punishments, one each (Guild/Data.lua PUNISHMENTS).
  p_stocks = gp(49), p_dunce = gp(50), p_wheel = gp(51), p_service = gp(52), p_walk = gp(53), p_curse = gp(54),
  p_radio = gp(55), p_servant = gp(56), p_idol = gp(57), p_trial = gp(58),
}
-- The game's own sounds for our moments (SPEC decision 53): our pages opening, a place, a row picked, gold paid, a
-- fanfare (a champion, a crown, BINGO), an alert, the Gazette. Each only while the player has sounds on.
UI.SOUNDS = { open = "IG_CHARACTER_INFO_OPEN", place = "IG_CHARACTER_INFO_TAB", pick = "U_CHAT_SCROLL_BUTTON",
  pay = "LOOT_WINDOW_COIN_SOUND", fanfare = "LFG_REWARDS", alert = "RAID_WARNING", paper = "IG_SPELLBOOK_OPEN" }

function UI.Sound(kind)
  local S = ns.Settings
  if not S.data or S:Get("sounds") == false then return end
  local id = SOUNDKIT and SOUNDKIT[UI.SOUNDS[kind] or ""]
  if id and PlaySound then PlaySound(id) end
end

-- Short motion (a fade between places, the red pill's pop, bars growing in) follows the player's alerts choice: off,
-- the pages stay still.
function UI.Motion()
  local S = ns.Settings
  return not S.data or S:Get("alerts") ~= false
end

-- The Guild Together emblem (the Tabard): a guild shield with a gold cross, 256 and 64 pixels.
UI.EMBLEM, UI.EMBLEM_SMALL = "Emblem", "EmblemSmall"

-- The painted atlas for this player's side.
function UI.Atlas()
  return ns.MEDIA .. (UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "IconsHorde" or "Icons")
end

-- A painted icon's cell and its column and row in the atlas (from 0); nil for the game's icons.
function UI.Cell(path)
  local n = type(path) == "string" and tonumber(path:match("^gp:(%d+)$"))
  if not n then return nil end
  return n, (n - 1) % 8, math.floor((n - 1) / 8)
end

-- Any of our icons on a plain texture: the painted medallion, else the game's icon with its edge trimmed.
function UI.IconTex(tex, path)
  local n, col, row = UI.Cell(path)
  if n then
    tex:SetTexture(UI.Atlas())
    tex:SetTexCoord((col + 0.03) / 8, (col + 0.97) / 8, (row + 0.03) / 8, (row + 0.97) / 8)
  else
    tex:SetTexture(path or 134400)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  return tex
end

-- An icon inside a line of text, size pixels.
function UI.Inline(path, size)
  size = size or 14
  local n, col, row = UI.Cell(path)
  if not n then return ("|T%s:%d|t"):format(tostring(path), size) end
  return ("|T%s:%d:%d:0:0:1024:1024:%d:%d:%d:%d|t"):format(UI.Atlas(), size, size, col * 128 + 4, col * 128 + 124,
    row * 128 + 4, row * 128 + 124)
end

function UI.Tex(tex, key)
  local t = UI.TEX[key]
  tex:SetTexture(t[1])
  tex:SetTexCoord(t[2], t[3], t[4], t[5])
  return tex
end

-- Notes on the panes: a soft warm grey, quieter than the rows' names, easy to read on the dark glass.
UI.INK = { 0.78, 0.75, 0.68 }
function UI.Ink(t)
  t:SetTextColor(UI.INK[1], UI.INK[2], UI.INK[3])
  return t
end

-- A name as the game shows it: in its class colour, without the realm when it is ours.
-- (Each name it gives is remembered with its character, so a row or a bar showing it knows whose card to show.)
UI.whoOf = {}
function UI.Who(name)
  if not name then return "" end
  local class = ns.Roster:Class(name)
  local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  local shown = ns.Display(name)
  if color and color.WrapTextInColorCode then shown = color:WrapTextInColorCode(shown) end
  UI.whoOf[shown] = name
  return shown
end

-- The short card on a player's name (SPEC decision 75), as the game's own tooltips: the name in their class colour,
-- rank and level, online (as which character) or when last seen, alts, the duel ladder and the crown, Marks and a
-- sentence they serve. name: one of their characters. { title, { left, right, color }, ... } (the self-test reads it).
UI.TIP_ALTS = 2
local GREEN, GREY = { 0.25, 0.85, 0.25 }, { 0.62, 0.62, 0.62 }
function UI.PlayerSummary(name)
  local L, D, P, R = ns.L, ns.GuildData, ns.Players, ns.Roster
  local g, now = D:Current(), time()
  local key = P:Of(name, g) or name
  local main = P:Main(key, g) or name
  local out = { title = UI.Who(main) }
  local function add(l, r, color) out[#out + 1] = { l, r, color } end
  local rank, level = R:RankName(main) or R:RankName(name), R:Level(main) or R:Level(name)
  if rank then add(level and L.TIP_RANK_LEVEL:format(rank, level) or rank) end
  local on = (R:Online(name) and name) or P:Online(key, g) or (P:IsMe(key, g) and ns.Self()) or nil
  if on then
    add(on == main and L.TIP_ONLINE or L.CARD_ONLINE_AS:format(ns.Display(on)), nil, GREEN)
  else
    local seen = R:Seen(main) or R:Seen(name)
    add(seen and L.TIP_SEEN:format(ns.TimeAgo(seen)) or L.TIP_OFFLINE, nil, GREY)
  end
  local alts = {}
  for _, c in ipairs(P:Chars(key, g)) do if c ~= main then alts[#alts + 1] = ns.Display(c) end end
  table.sort(alts)
  if #alts > 0 then
    local shown = {}
    for i = 1, math.min(UI.TIP_ALTS, #alts) do shown[i] = alts[i] end
    if #alts > UI.TIP_ALTS then shown[#shown + 1] = L.CO_AND_MORE:format(#alts - UI.TIP_ALTS) end
    add(L.TIP_ALTS:format(table.concat(shown, ", ")))
  end
  if not g then return out end
  if D:PlaceOn("challenges") then
    local season = ns.Duels.Now(g, now)
    for i, x in ipairs(ns.Duels.Ladder(g, season.from, season.to)) do
      if x.key == key then add(L.CARD_LADDER, L.CARD_PLACE:format(i, x.r)) break end
    end
    if ns.Crown.State(g, now).holder == key then add(L.CARD_CROWN, L.CARD_CROWN_NOW) end
  end
  local marks = ns.Purse:Balance(g, key)
  if marks ~= 0 then add(D:Settings().many, UI.Money(marks, "marks")) end
  if D:PlaceOn("punishments") then
    local s = ns.Stocks.Of(g, key, now)[1]
    if s then add(L.TIP_SERVING:format(L["ACT_" .. s.pun:upper()] or s.pun)) end
  end
  return out
end

-- Shows that card for owner; extra = { title, text }: the line the frame had of its own, under the card.
function UI.PlayerTip(owner, name, extra)
  local L, card = ns.L, UI.PlayerSummary(name)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(card.title, 1, 1, 1)
  for _, l in ipairs(card) do
    local c = l[3] or { 0.86, 0.86, 0.86 }
    if l[2] then GameTooltip:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], 1, 0.82, 0)
    else GameTooltip:AddLine(l[1], c[1], c[2], c[3], true) end
  end
  if extra and (extra[1] or extra[2]) then
    GameTooltip:AddLine(" ")
    if extra[1] then GameTooltip:AddLine(extra[1], 1, 1, 1, true) end
    if extra[2] then GameTooltip:AddLine(extra[2], nil, nil, nil, true) end
  end
  GameTooltip:AddLine(L.TIP_CARD, GREY[1], GREY[2], GREY[3])
  GameTooltip:Show()
end

-- Gold with the game's coin pictures (an amount in copper); Marks by the name the Guild Master gave them.
function UI.Money(amt, purse)
  amt = tonumber(amt) or 0
  if purse ~= "gold" then return ns.Purse:Format(amt, purse) end
  local a = math.abs(amt)
  local g, s = math.floor(a / 10000), math.floor(a % 10000 / 100)
  local text = g > 0 and (g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t") or ""
  if s > 0 or g == 0 then
    text = text .. (text ~= "" and " " or "") .. s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
  end
  return amt < 0 and ("-" .. text) or text
end

-- The "i" of Guild Rewards: a small button whose tooltip holds what would otherwise be a paragraph on the page.
function UI.Help(parent, title, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  UI.Tex(b:CreateTexture(nil, "ARTWORK"), "help"):SetAllPoints()
  local hi = UI.Tex(b:CreateTexture(nil, "HIGHLIGHT"), "help")
  hi:SetAllPoints()
  hi:SetBlendMode("ADD")
  UI.Tooltip(b, title, text)
  return b
end

-- A heading: a small gold title on the left, a quiet line on the right, and a fine gold line running out under them.
function UI.Strip(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, UI.STRIP_H)
  local line = f:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT", 8, 1)
  line:SetPoint("BOTTOMRIGHT", -8, 1)
  line:SetHeight(1)
  line:SetColorTexture(1, 1, 1, 1)
  local g = UI.LOOK.gold
  UI.SetGradient(line, "HORIZONTAL", { g[1], g[2], g[3], 0.45 }, { g[1], g[2], g[3], 0 })
  f.title = UI.Color(UI.Text(f, "GameFontNormalSmall"), "gold")
  f.title:SetPoint("LEFT", 8, 0)
  f.right = UI.Color(UI.Text(f, "GameFontHighlightSmall", "RIGHT"), "sub")
  f.right:SetPoint("RIGHT", -8, 0)
  f.right:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  f.right:SetWordWrap(false)
  return f
end

-- Small tabs along a header strip, for the parts of a page or of a pane: list = { { id, label }, ... }; pick(id) runs
-- on a click. strip:Select(id) marks one (white, with a gold line under it); strip.buttons[id].
function UI.Tabs(parent, width, list, pick)
  local f = UI.Strip(parent, width)
  f.buttons = {}
  local x = 4
  for _, item in ipairs(list) do
    local b = CreateFrame("Button", nil, f)
    b.text = UI.Text(b, "GameFontNormalSmall", "CENTER")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText(item[2])
    b:SetSize(math.ceil((b.text:GetStringWidth() or 60) + 18), UI.STRIP_H)
    b:SetPoint("LEFT", x, 0)
    x = x + b:GetWidth() + 2
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetPoint("BOTTOMLEFT", 4, 1)
    hi:SetPoint("BOTTOMRIGHT", -4, 1)
    hi:SetHeight(2)
    hi:SetColorTexture(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.4)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 4, 1)
    b.line:SetPoint("BOTTOMRIGHT", -4, 1)
    b.line:SetHeight(2)
    b.line:SetColorTexture(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 1)
    b:SetScript("OnClick", function() pick(item[1]) end)
    f.buttons[item[1]] = b
  end
  f.used = x
  -- A tab whose label changes (the Marks' name): its text, and the tabs after it move along.
  function f.Relabel(self, id, label)
    local b = self.buttons[id]
    if not b or b.text:GetText() == label then return end
    b.text:SetText(label)
    b:SetWidth(math.ceil((b.text:GetStringWidth() or 60) + 18))
    local px = 4
    for _, item in ipairs(list) do
      local o = self.buttons[item[1]]
      o:ClearAllPoints()
      o:SetPoint("LEFT", px, 0)
      px = px + o:GetWidth() + 2
    end
  end
  function f.Select(self, id)
    self.current = id
    for bid, b in pairs(self.buttons) do
      b.line:SetShown(bid == id)
      UI.Color(b.text, bid == id and "goldHi" or "sub")
    end
  end
  return f
end

-- A pane: a panel of glass, an optional heading (opts.title) or small tabs (opts.tabs, opts.pick), a list that
-- scrolls with the game's thin scroll bar, and an optional bar for actions at the bottom (opts.foot).
-- Content goes in pane.child, pane.inner wide (UI.PaneFlow lays it out); actions go in pane.foot (UI.Foot).
function UI.Pane(parent, width, height, opts)
  opts = opts or {}
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(width, height)
  p.fill, p.edge = UI.Glass(p)
  local top, bottom = 0, 0
  if opts.tabs then
    p.strip = UI.Tabs(p, width, opts.tabs, opts.pick)
  elseif opts.title then
    p.strip = UI.Strip(p, width)
    p.strip.title:SetText(opts.title)
  end
  if p.strip then
    p.strip:SetPoint("TOPLEFT")
    top = UI.STRIP_H
  end
  if opts.foot then
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("BOTTOMLEFT")
    f:SetPoint("BOTTOMRIGHT")
    f:SetHeight(UI.FOOT_H)
    local shade = f:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", 1, 0)
    shade:SetPoint("BOTTOMRIGHT", -1, 1)
    shade:SetColorTexture(1, 1, 1, 1)
    UI.SetGradient(shade, "VERTICAL", { 0, 0, 0, 0.35 }, { 0, 0, 0, 0.1 })
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", 8, 0)
    line:SetPoint("TOPRIGHT", -8, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.07)
    f.note = UI.Text(f, "GameFontDisableSmall")
    f.note:SetWordWrap(false)
    f.buttons = {}
    p.foot = f
    bottom = UI.FOOT_H
  end
  local sf = CreateFrame("ScrollFrame", nil, p)
  sf:SetPoint("TOPLEFT", 6, -top - 5)
  sf:SetPoint("BOTTOMRIGHT", -16, bottom + 5)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(width - 22, 10)
  sf:SetScrollChild(child)
  p.bar = UI.ScrollBar(p, sf, child)
  p.scroll, p.child, p.inner = sf, child, width - 22
  return p
end

-- A thin gold scroll bar on the right of a scroll frame (SPEC decision 53): it shows only when there is more to see;
-- its thumb can be dragged, a click above or below it turns a page, and the wheel scrolls.
function UI.ScrollBar(parent, sf, child)
  local g = UI.LOOK.gold
  local bar = CreateFrame("Button", nil, parent)
  bar:SetWidth(8)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 5, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 5, 0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("TOP")
  track:SetPoint("BOTTOM")
  track:SetWidth(2)
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = CreateFrame("Button", nil, bar)
  thumb:SetWidth(8)
  thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
  thumb.tex:SetPoint("TOP")
  thumb.tex:SetPoint("BOTTOM")
  thumb.tex:SetWidth(3)
  thumb.tex:SetColorTexture(g[1], g[2], g[3], 1)
  bar.thumb = thumb
  local function range() return math.max(0, child:GetHeight() - sf:GetHeight()) end
  local function paint()
    thumb.tex:SetAlpha((thumb.drag or thumb.over) and 0.95 or 0.5)
    thumb.tex:SetWidth((thumb.drag or thumb.over) and 4 or 3)
  end
  local function place()
    local max, h = range(), sf:GetHeight()
    bar:SetShown(max > 0.5)
    if max <= 0.5 then return end
    local th = math.max(18, h * h / (h + max))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -((h - th) * sf:GetVerticalScroll() / max))
  end
  local function scrollTo(v)
    sf:SetVerticalScroll(ns.Clamp(v, 0, range()))
    place()
  end
  bar.Place, bar.To = place, scrollTo
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta) scrollTo(self:GetVerticalScroll() - delta * 30) end)
  sf:HookScript("OnScrollRangeChanged", place)
  sf:HookScript("OnVerticalScroll", place)
  sf:HookScript("OnSizeChanged", place)
  bar:SetScript("OnClick", function(self)
    local _, y = GetCursorPosition()
    y = y / self:GetEffectiveScale()
    local page = sf:GetHeight() - 20
    scrollTo(sf:GetVerticalScroll() + (y < thumb:GetBottom() and page or -page))
  end)
  thumb:SetScript("OnEnter", function() thumb.over = true; paint() end)
  thumb:SetScript("OnLeave", function() thumb.over = nil; paint() end)
  thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    self.drag = { y = y / self:GetEffectiveScale(), v = sf:GetVerticalScroll() }
    paint()
  end)
  thumb:SetScript("OnMouseUp", function(self) self.drag = nil; paint() end)
  thumb:SetScript("OnUpdate", function(self)
    if not self.drag then return end
    local _, y = GetCursorPosition()
    y = y / self:GetEffectiveScale()
    local room = sf:GetHeight() - self:GetHeight()
    if room > 0 then scrollTo(self.drag.v + (self.drag.y - y) * range() / room) end
  end)
  paint()
  place()
  return bar
end

-- The pane's actions along its bottom bar: list = { { label, onClick, next = true }, ... } (next: it glows), then a
-- quiet note. Buttons are made once by position and reused.
function UI.Foot(pane, list, note)
  local f = pane.foot
  local x = 6
  for i = 1, math.max(#list, #f.buttons) do
    local b, item = f.buttons[i], list[i]
    if item and not b then
      -- The first is the main button (gold); the others are outlines.
      b = UI.Button(f, "", 80, function() end, i > 1)
      f.buttons[i] = b
    end
    if b then
      b:SetShown(item ~= nil)
      UI.Glow(b, item ~= nil and item.next and not item.off)
      if item then
        b:SetText(item[1])
        b:SetEnabled(item.off ~= true)
        b:SetWidth(math.max(80, math.ceil((b:GetTextWidth() or 60) + 24)))
        b:SetScript("OnClick", function() item[2]() end)
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        x = x + b:GetWidth() + 6
      end
    end
  end
  f.note:ClearAllPoints()
  f.note:SetPoint("LEFT", x + 2, 0)
  f.note:SetPoint("RIGHT", -6, 0)
  f.note:SetText(note or "")
end

-- An icon in the look on tex (a ring texture over it: ring): the painted medallion (it has its own ring), else the
-- game's icon cut round inside the gold ring. size: the whole medallion's.
function UI.SetIcon(tex, ring, path, size)
  local painted = UI.Cell(path) ~= nil
  size = size or 34
  UI.IconTex(tex, path or UI.ICON.question)
  if painted then
    tex:SetSize(size, size)
  else
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetSize(math.floor(size * 0.76), math.floor(size * 0.76))
  end
  if ring then ring:SetShown(not painted) end
end

-- A player's own icon on tex (never a made-up face, the owner, 1 Nov 2026): their class's (the game's class circles),
-- else, for someone near you, their race and sex (the game's race icons), else a question mark. Returns its kind.
function UI.PlayerIcon(tex, name, class)
  class = class or (name and ns.Roster:Class(name))
  local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    tex:SetTexCoord(unpack(coords))
    return "class"
  end
  local race = name and UnitRace and select(2, pcall(UnitRace, name))
  local sex = name and UnitSex and select(2, pcall(UnitSex, name))
  local atlas = type(race) == "string" and GetRaceAtlas and select(2, pcall(GetRaceAtlas, race:lower(),
    sex == 3 and "female" or "male", false))
  if type(atlas) == "string" and tex.SetAtlas then
    tex:SetAtlas(atlas)
    return "race"
  end
  UI.IconTex(tex, UI.ICON.question)
  return "none"
end

-- A round icon in its ring on frame: the icon and ring textures, size pixels; the caller places the icon.
function UI.Medallion(frame, size)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(size, size)
  local mask = frame.CreateMaskTexture and frame:CreateMaskTexture()
  if mask and icon.AddMaskTexture then
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end
  local ring = frame:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(ns.MEDIA .. "Ring")
  ring:SetSize(size, size)
  ring:SetPoint("CENTER", icon, "CENTER")
  return icon, ring
end

-- A row: a medallion, a name, a small quiet line, a value (and a small line) on the right. Quiet glass that lights up
-- in gold under the mouse; picked, a gold edge. row:Set{ icon, name, sub, value, vsub, onClick, sel, dim, badge,
-- tip = { title, text } }.
local function rowSet(r, o)
  UI.SetIcon(r.icon, r.ring, o.icon, r.iconSize or 34)
  r.icon:SetDesaturated(o.dim == true)
  r.name:SetText(o.name or "")
  UI.Color(r.name, o.sel and "goldHi" or "ink")
  r.sub:SetText(o.sub or "")
  r.value:SetText(o.value or "")
  r.vsub:SetText(o.vsub or "")
  r.sel:SetShown(o.sel == true)
  r.selEdge:SetShown(o.sel == true)
  r.badge:SetCount(o.badge or 0)
  r:SetAlpha(o.dim and 0.7 or 1)
  r.onClick, r.tip = o.onClick, o.tip
  -- A player's row (its name from UI.Who, or o.player): their card on hover, the full one on right-click.
  r.player = o.player or (o.player ~= false and type(o.name) == "string" and UI.whoOf[o.name]) or nil
end

function UI.Row(parent, width)
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(width, UI.ROW_H)
  local g = UI.LOOK.gold
  UI.Round(r:CreateTexture(nil, "BACKGROUND"), "Glass", { 1, 1, 1, 0.035 }):SetAllPoints()
  UI.Round(r:CreateTexture(nil, "HIGHLIGHT"), "Glass", { g[1], g[2], g[3], 0.09 }):SetAllPoints()
  r.sel = UI.Round(r:CreateTexture(nil, "BORDER"), "Glass", { g[1], g[2], g[3], 0.13 })
  r.sel:SetAllPoints()
  r.selEdge = UI.Round(r:CreateTexture(nil, "BORDER", nil, 1), "Edge", { g[1], g[2], g[3], 0.6 })
  r.selEdge:SetAllPoints()
  r.icon, r.ring = UI.Medallion(r, 34)
  r.icon:SetPoint("CENTER", r, "LEFT", 22, 0)
  r.value = UI.Color(UI.Text(r, "GameFontHighlight", "RIGHT"), "gold")
  r.value:SetPoint("TOPRIGHT", -8, -8)
  r.vsub = UI.Color(UI.Text(r, "GameFontHighlightSmall", "RIGHT"), "sub")
  r.vsub:SetPoint("BOTTOMRIGHT", -8, 8)
  r.name = UI.Color(UI.Text(r, "GameFontHighlight"), "ink")
  r.name:SetPoint("TOPLEFT", 46, -8)
  r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
  r.name:SetWordWrap(false)
  r.sub = UI.Color(UI.Text(r, "GameFontHighlightSmall"), "sub")
  -- What waits there: a red number on the medallion's shoulder (o.badge), clear of the text.
  r.badge = UI.Badge(r)
  r.badge:SetPoint("CENTER", r.icon, "TOPRIGHT", -2, -2)
  r.sub:SetPoint("BOTTOMLEFT", 46, 8)
  r.sub:SetPoint("RIGHT", r.vsub, "LEFT", -6, 0)
  r.sub:SetWordWrap(false)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.player and ns.Card then ns.Card:Show(self.player) end
      return
    end
    if self.onClick then self.onClick() end
  end)
  r:SetScript("OnEnter", function(self)
    if self.player then return UI.PlayerTip(self, self.player, self.tip) end
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip[1], 1, 1, 1)
    if self.tip[2] then GameTooltip:AddLine(self.tip[2], nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.Set = rowSet
  return r
end

-- A feature in the guild window (SPEC decision 57): a row, larger, with a bigger medallion and name.
function UI.Tile(parent, width)
  local r = UI.Row(parent, width)
  r:SetHeight(UI.TILE_H)
  r.iconSize = 44
  r.ring:SetSize(44, 44)
  r.icon:SetPoint("CENTER", r, "LEFT", 28, 0)
  r.name:SetFontObject("GameFontNormalLarge")
  r.name:SetPoint("TOPLEFT", 58, -11)
  r.sub:SetFontObject("GameFontHighlight")
  r.sub:SetPoint("BOTTOMLEFT", 58, 11)
  return r
end

-- In a flow: a row, a header strip, a bar (as the guild reputation bar), and a quiet line for an empty list.
function Flow:Row(key, o)
  local r = self:piece(key, function() return UI.Row(self.card, self.width) end, "row")
  r:Set(o)
  r:SetPoint("TOPLEFT", self.pad, self.y)
  r.flowTop = -self.y
  if o.sel == true then self.picked = key end
  self.y = self.y - UI.ROW_H - UI.ROW_GAP
  return r
end

-- Tiles side by side, cols to a line (the features in the guild window): col is 1 .. cols; the flow moves down after
-- the last of a line (or the last tile, last = true).
function Flow:Tile(key, o, col, cols, last)
  local w = math.floor((self.width - UI.TILE_GAP * (cols - 1)) / cols)
  local r = self:piece(key, function() return UI.Tile(self.card, w) end, "tile")
  r:SetWidth(w)
  r:Set(o)
  r:SetPoint("TOPLEFT", self.pad + (col - 1) * (w + UI.TILE_GAP), self.y)
  r.flowTop = -self.y
  if o.sel == true then self.picked = key end
  if col == cols or last then self.y = self.y - UI.TILE_H - UI.TILE_GAP end
  return r
end

-- A slider (your options' Size): its name on the left, the value on the right (fmt(v) says it), the bar under them.
-- set(v) runs when the mouse lets go, so what it sizes does not move under the mouse while it drags.
function Flow:Slider(key, label, lo, hi, step, value, set, fmt)
  local s = self:piece(key, function()
    local f = CreateFrame("Frame", nil, self.card)
    f:SetSize(self.width - 2 * self.pad, 40)
    f.label = UI.Color(UI.Text(f, "GameFontHighlight"), "ink")
    f.label:SetPoint("TOPLEFT", 4, 0)
    f.value = UI.Color(UI.Text(f, "GameFontHighlight", "RIGHT"), "gold")
    f.value:SetPoint("TOPRIGHT", -4, 0)
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("HORIZONTAL")
    bar:SetPoint("TOPLEFT", 8, -18)
    bar:SetPoint("TOPRIGHT", -8, -18)
    bar:SetHeight(18)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    local g = UI.LOOK.gold
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(3)
    track:SetColorTexture(1, 1, 1, 0.14)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(10, 18)
    thumb:SetColorTexture(g[1], g[2], g[3], 1)
    bar:SetThumbTexture(thumb)
    local function round(v) return math.floor((v or 0) / f.step + 0.5) * f.step end
    bar:SetScript("OnValueChanged", function(_, v) f.value:SetText(f.fmt(round(v))) end)
    bar:SetScript("OnMouseUp", function() if f.set then f.set(round(bar:GetValue())) end end)
    f.bar = bar
    return f
  end, "slider")
  s.step, s.fmt, s.set = step, fmt or tostring, nil
  s.bar:SetMinMaxValues(lo, hi)
  s.bar:SetValueStep(step)
  s.bar:SetValue(value)
  s.label:SetText(label)
  s.value:SetText(s.fmt(value))
  s.set = set
  s:SetPoint("TOPLEFT", self.pad, self.y)
  self.y = self.y - 46
  return s
end

function Flow:Strip(key, title, right)
  local s = self:piece(key, function() return UI.Strip(self.card, self.width) end, "strip")
  s.title:SetText(title)
  s.right:SetText(right or "")
  -- A long title stops short of the right text (cut, so the self-test sees it) instead of running over it.
  s.title:SetWordWrap(false)
  s.title:SetWidth(math.max(20, math.min(s.title:GetStringWidth() + 2,
    self.width - 16 - (right and right ~= "" and s.right:GetStringWidth() + 8 or 0))))
  local gap = self.y < self.top and 6 or 0
  s:SetPoint("TOPLEFT", self.pad, self.y - gap)
  self.y = self.y - gap - UI.STRIP_H - 4
  return s
end

function Flow:Bar(key, frac, text)
  local b = self:piece(key, function()
    local f = CreateFrame("StatusBar", nil, self.card)
    f:SetSize(self.width - 8, 14)
    f:SetStatusBarTexture(UI.TEX.bar[1])
    f:SetStatusBarColor(UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3])
    f:SetMinMaxValues(0, 1)
    UI.Round(f:CreateTexture(nil, "BACKGROUND"), "Glass", { 0, 0, 0, 0.6 }):SetAllPoints()
    UI.Round(f:CreateTexture(nil, "OVERLAY"), "Edge", UI.LOOK.edge):SetAllPoints()
    f.text = UI.Text(f, "GameFontHighlightSmall", "CENTER")
    f.text:SetPoint("CENTER", 0, 1)
    return f
  end, "bar")
  -- It grows in to its new value (SPEC decision 53).
  local to = ns.Clamp(frac or 0, 0, 1)
  local at = b.cur or 0
  b.cur = to
  if not UI.Motion() or math.abs(to - at) < 0.01 then
    b:SetScript("OnUpdate", nil)
    b:SetValue(to)
  else
    b:SetValue(at)
    b:SetScript("OnUpdate", function(bar, elapsed)
      at = at + (to - at) * math.min(1, elapsed * 7)
      if math.abs(to - at) < 0.005 then at = to; bar:SetScript("OnUpdate", nil) end
      bar:SetValue(at)
    end)
  end
  b.text:SetText(text or "")
  b:SetPoint("TOPLEFT", self.pad + 4, self.y - 2)
  self.y = self.y - 22
  return b
end

-- An empty list, and what you can do about it (hint, optional; SPEC decision 47).
function Flow:Empty(key, text, hint)
  local t = self:piece(key, function()
    local s = UI.Wrap(self.card, "GameFontDisable", self.width - 20)
    s:SetJustifyH("CENTER")
    return s
  end, "empty")
  UI.Ink(t):SetText(text)
  t:SetPoint("TOPLEFT", self.pad + 10, self.y - 16)
  self.y = self.y - math.ceil(t:GetStringHeight() or 14) - 16
  local h = self:piece(key .. ".do", function()
    local s = UI.Wrap(self.card, "GameFontHighlightSmall", self.width - 40)
    s:SetJustifyH("CENTER")
    return s
  end, "empty.do")
  h:SetText(hint or "")
  h:SetShown(hint ~= nil)
  if hint then
    h:SetPoint("TOPLEFT", self.pad + 20, self.y - 6)
    self.y = self.y - math.ceil(h:GetStringHeight() or 12) - 10
  end
  self.y = self.y - 16
  return t
end
