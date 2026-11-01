-- The stage (SPEC decision 60, docs/mockup/Motion.html): the panel's picture of an activity as a small scene in
-- the place where it happens. Behind, the place's painting (Media\Stage<Place>, the Horde's StageHorde<Place>, cut
-- from the header art by tools/convert-art.ps1 and darker towards the floor); in front, the players as their 3D
-- characters (the real models the game has drawn this session, kept by Guild/Looks.lua; a class crest for a player not
-- seen yet) doing the game's own character moves; over them the props (a die, a crown, a tomato) and small glass panels with
-- the numbers. Everything is placed in the scene's own units, 320 x 184 like the mockup, from its top left, and the
-- scene is scaled to the card's width (at most Sg.ROOM of the pane's height).
-- A scene is drawn on every refresh as its last picture. A moment (s:New) plays once on this screen: when it happens
-- while the scene shows, or the first time the scene opens within 10 minutes of it; never with motion off.
--   local s = f:Stage("stage", "tavern"); s:Scene("dr:" .. id); local a = s:Actor("me", ns.Self(), 80, 1)
--   if s:New("roll" .. n, t) then s:Do(a, "throw") end; s:Done()
local _, ns = ...
local L, UI = ns.L, ns.UI
local V, Flow = UI.Visuals, UI.Flow
local Sg = { played = {} }
UI.Stage = Sg

Sg.W, Sg.H, Sg.FLOOR = 320, 184, 168
Sg.ROOM = 0.6           -- of the pane's height, at most
Sg.ROOM_FULL = 0.86     -- on the Guild Together screen: the scene fills the column's width (the second check of 1 Nov)
Sg.ACTOR_W, Sg.ACTOR_H = 66, 104
Sg.RECENT = 600         -- a moment this many seconds old still plays the first time its scene opens
Sg.OPENING = 0.5        -- a refresh this soon after the scene opened is still its opening
Sg.TURN = 0.7           -- radians a character is turned towards the side it faces
Sg.PLACES = { tavern = "Tavern", ring = "Ring", square = "Square", fair = "Fair", pier = "Pier", council = "Council" }
-- The game's own character moves (its animation numbers; the self-test checks the models have each). Sitting (SPEC
-- decision 74): on the ground, on a stool (low), at a table (a chair) and on the court's high bench.
Sg.MOVES = { stand = 0, death = 1, dead = 6, run = 5, wound = 9, attack = 17, ready = 26, loot = 50, throw = 53,
  roar = 55, talk = 60, bow = 66, wave = 67, cheer = 68, dance = 69, kneel = 75, cry = 77, beg = 79, applaud = 80,
  flex = 82, shy = 83, point = 84, sit = 97, stool = 102, chair = 103, bench = 104 }
-- Moves that play once, and how long: then the character stands, or does Sg.AFTER's move.
Sg.ONCE = { death = 1.3, wound = 0.5, attack = 0.7, throw = 0.8, loot = 1.2, bow = 1.5, roar = 1.6, point = 1.4 }
Sg.AFTER = { death = "dead" }
-- With motion off, the last picture: the move a character ends in.
Sg.STILL = { death = "dead", run = "stand", attack = "ready", wound = "ready", throw = "stand" }
-- The line under a name (what that player does): soft grey unless a scene gives its own colour.
Sg.LINE = { 0.78, 0.74, 0.66 }
Sg.TAG_W = Sg.ACTOR_W + 40

---------------------------------------------------------------------------
-- The characters
---------------------------------------------------------------------------
-- A character's whole body in its frame (a little room around it, so a tall race keeps its head and feet).
local function frameModel(m)
  if m.SetPortraitZoom then m:SetPortraitZoom(0) end
  if m.SetCamDistanceScale then m:SetCamDistanceScale(1.25) end
  if m.SetPosition then m:SetPosition(0, 0, 0) end
  if m.SetFacing then m:SetFacing(m.facing or 0) end
  if m.SetAnimation then m:SetAnimation(Sg.MOVES[m.move or "stand"] or 0) end
end

-- A character's name and, under it, the line saying what they do (SPEC decision 74): text that may be cut (the whole
-- name is in the tooltip).
local function tagTexts(parent)
  local name = UI.Text(parent, "GameFontHighlightSmall", "CENTER")
  name:SetWidth(Sg.TAG_W)
  name:SetWordWrap(false)
  local line = UI.Text(parent, "GameFontHighlightSmall", "CENTER")
  line:SetWidth(Sg.TAG_W)
  line:SetWordWrap(false)
  line:Hide()
  return name, line
end

-- A model kept for a player (Guild/Looks.lua) is framed like this when it is made. Its name and line are on a frame
-- of its own over it (the character draws over its own texts).
ns.Looks.onNew = function(m)
  m:SetSize(Sg.ACTOR_W, Sg.ACTOR_H)
  pcall(m.SetScript, m, "OnModelLoaded", frameModel)
  m:EnableMouse(true)
  UI.Tooltip(m, function() return m.who and ns.Display(m.who) or "" end, function() return m.note end)
  m.tag = CreateFrame("Frame", nil, m)
  m.tag:SetAllPoints()
  m.tag.short = true
  m.tag.name, m.tag.line = tagTexts(m.tag)
end

-- The name and line of character m (a model or a crest).
function Sg.Tag(m)
  if not m then return nil end
  if m.isModel then return m.tag and m.tag.name, m.tag and m.tag.line end
  return m.name, m.line
end

-- Plays a move on character m now. Moves that play once go back to standing (or lie dead) after their time. A
-- crest (a player not seen yet) only dims when it falls.
local function act(m, move, after)
  m.move = move
  m.token = (m.token or 0) + 1
  if not m.SetAnimation then
    m:SetAlpha((move == "death" or move == "dead") and 0.4 or 1)
    return
  end
  m:SetAnimation(Sg.MOVES[move] or 0)
  local once = Sg.ONCE[move]
  if once and C_Timer then
    local token = m.token
    C_Timer.After(once, function()
      if m.token == token then act(m, after or Sg.AFTER[move] or "stand") end
    end)
  end
end

-- What pointing at a character says: drawn as the game showed them (and when that was), or not seen yet.
local function lookNote(name, model)
  if model then
    local t = ns.Looks:LastNear(name)
    return t and name ~= ns.Self() and L.STAGE_LOOK_SEEN:format(ns.TimeAgo(t)) or L.STAGE_LOOK_REAL
  end
  return L.STAGE_LOOK_NONE
end

-- A player not seen yet this session: their class crest in a soft glow of their class colour, their name under it.
local function crest(canvas)
  local t = CreateFrame("Frame", nil, canvas)
  t:SetSize(Sg.ACTOR_W, Sg.ACTOR_H)
  t.glow = t:CreateTexture(nil, "BACKGROUND")
  t.glow:SetTexture(ns.MEDIA .. "Glow")
  t.glow:SetBlendMode("ADD")
  t.glow:SetSize(84, 84)
  t.glow:SetPoint("CENTER", t, "BOTTOM", 0, 44)
  t.icon, t.ring = UI.Medallion(t, 46)
  t.icon:SetPoint("CENTER", t, "BOTTOM", 0, 44)
  t.name, t.line = tagTexts(t)
  t.name:SetPoint("TOP", t, "BOTTOM", 0, 14)
  t:EnableMouse(true)
  UI.Tooltip(t, function() return t.who and ns.Display(t.who) or "" end, function() return t.note end)
  function t.Set(self, name, class)
    self.who = name
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    self.glow:SetVertexColor(c and c.r or 0.8, c and c.g or 0.7, c and c.b or 0.4, 0.55)
    self.iconKind = UI.PlayerIcon(self.icon, name, class)
    self.name:SetText(ns.Short(name))
    if c then self.name:SetTextColor(c.r, c.g, c.b) end
  end
  return t
end

---------------------------------------------------------------------------
-- The stage
---------------------------------------------------------------------------
local S = {}

local function newStage(parent)
  local s = CreateFrame("Frame", nil, parent)
  if s.SetClipsChildren then s:SetClipsChildren(true) end
  s.canvas = CreateFrame("Frame", nil, s)
  s.canvas:SetSize(Sg.W, Sg.H)
  s.canvas:SetPoint("TOPLEFT")
  s.bg = s.canvas:CreateTexture(nil, "BACKGROUND")
  s.bg:SetAllPoints()
  -- The paintings are 2:1, the scene a little narrower: the sides are cut.
  s.bg:SetTexCoord(0.065, 0.935, 0, 1)
  s.top = CreateFrame("Frame", nil, s.canvas)
  s.top:SetAllPoints()
  s.top:SetFrameLevel(s.canvas:GetFrameLevel() + 20)
  s.edge = UI.Round(s.top:CreateTexture(nil, "OVERLAY", nil, 7), "Edge", { 1, 0.85, 0.5, 0.35 })
  s.edge:SetAllPoints()
  s.cast, s.props, s.used, s.token = {}, {}, {}, 0
  for k, fn in pairs(S) do s[k] = fn end
  s:SetScript("OnHide", function(self) self:Release() end)
  return s
end

-- The place's painting behind a stage, Alliance or Horde; the stage made ready for this drawing.
local function dress(s, place)
  local side = UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "Horde" or ""
  s.bg:SetTexture(ns.MEDIA .. "Stage" .. side .. (Sg.PLACES[place] or "Tavern"))
  s.place = place
  wipe(s.used)
  return s
end

---------------------------------------------------------------------------
-- A stage of its own, larger, outside the flow (SPEC decision 63): the window beside the panel (UI/Side.lua) and the
-- toast under the alert line (UI/Alerts.lua). A flow with .into set draws its scene there: Flow:Stage gives that
-- stage, takes no room in the flow, and marks the flow .staged.
---------------------------------------------------------------------------
function Sg.Host(parent, w, kind)
  local host = CreateFrame("Frame", nil, parent)
  host.stage = newStage(host)
  -- Whose kept models it borrows (Guild/Looks.lua): the panel's, the toast's or the chat's. Over the guild chat
  -- (UI/Side.lua) nothing on it takes the mouse.
  host.stage.kind = kind or "panel"
  host.stage.quiet = kind == "chat"
  host.stage:SetPoint("TOPLEFT")
  function host.Fit(self, width)
    local scale = width / Sg.W
    self.stage:SetSize(math.floor(width + 0.5), math.floor(Sg.H * scale + 0.5))
    self.stage.canvas:SetScale(math.max(0.01, scale))
    self:SetSize(self.stage:GetWidth(), self.stage:GetHeight())
  end
  function host.Stage(self, place) return dress(self.stage, place) end
  host:Fit(w)
  return host
end

-- A stage across the flow's width, in place's painting (Sg.PLACES).
function Flow:Stage(key, place)
  if self.into then
    self.staged = true
    return self.into:Stage(place)
  end
  local s = self:piece(key, function() return newStage(self.card) end, "stage")
  local w = self.width
  -- At most Sg.ROOM of the pane's height (the panel's right column is short, decision 59), so what is under the scene
  -- stays in sight; narrower than the card, it is centred.
  local scale = w / Sg.W
  local room = self.pane and self.pane:GetHeight()
  local share = ns.Hall and ns.Hall:IsFull() and Sg.ROOM_FULL or Sg.ROOM
  if room and room > 0 then scale = math.min(scale, room * share / Sg.H) end
  local sw, h = math.floor(Sg.W * scale + 0.5), math.floor(Sg.H * scale + 0.5)
  s:SetSize(sw, h)
  s:SetPoint("TOPLEFT", self.pad + math.floor((w - sw) / 2), self.y)
  s.canvas:SetScale(math.max(0.01, scale))
  self.y = self.y - h - UI.FLOW_GAP
  return dress(s, place)
end

-- Which scene this is (an activity and its id). Another one clears the stage.
function S:Scene(key)
  if self.scene == key then return end
  self.scene = key
  self.opened, self.holdUntil = GetTime(), nil
  self.token = self.token + 1
  self:Release()
  for _, p in pairs(self.props) do p:Hide() end
end

-- Lets the characters go: a player's kept model goes back off the stage (still loaded), a crest hides.
local function letGo(s, role)
  local m = s.cast[role]
  s.cast[role] = nil
  if not m then return end
  m.token = (m.token or 0) + 1
  m:Hide()
  if m.isModel then
    if m.stage == s then
      m:ClearAllPoints()
      m:SetParent(UIParent)
      m.stage = nil
    end
  end
end

function S:Release()
  for role in pairs(self.cast) do letGo(self, role) end
end

-- The character in role leaves the scene (a watcher who went offline).
function S:Leave(role) letGo(self, role) end

-- A moment that takes a while (the court's calls, one juror after another): for sec seconds a refresh leaves the
-- characters to it (s:Held). Sg.Busy: some stage is in such a moment (the self-test's pictures wait for its end).
function S:Hold(sec)
  self.holdUntil = GetTime() + sec
  Sg.heldUntil = math.max(Sg.heldUntil or 0, self.holdUntil)
end
function S:Held() return self.holdUntil ~= nil and GetTime() < self.holdUntil end
function Sg.Busy() return Sg.heldUntil ~= nil and GetTime() < Sg.heldUntil end

-- Is this moment new here, so it plays now? key names it within the scene; t: when it happened (nil: unknown, then
-- it plays only while the scene shows). Each moment is asked about once on this screen.
function S:New(key, t)
  key = tostring(self.scene) .. "|" .. key
  if Sg.played[key] then return false end
  Sg.played[key] = true
  if not UI.Motion() then return false end
  -- (Sg.replay: the showcase plays every moment again, however old: Dev/SelfTest.lua.)
  if GetTime() - (self.opened or 0) < Sg.OPENING and not Sg.replay then
    if not t or time() - t > Sg.RECENT then return false end
  end
  self.token = self.token + 1
  -- (Counted: a moment over the guild chat shows only when one began on its stage, UI/Side.lua.)
  self.news = (self.news or 0) + 1
  return true
end

-- Runs fn after sec seconds, unless the scene changed or a newer moment began.
function S:After(sec, fn)
  if not sec or sec <= 0 or not C_Timer then fn() return end
  local token = self.token
  C_Timer.After(sec, function()
    if self.token == token and self:IsVisible() then fn() end
  end)
end

-- A character on the floor at x (the middle of their feet), facing right (face 1) or left (-1). name: "Name-Realm".
-- o: size (1 = full), floor (y of their feet), class (for the crest), move (the move they keep doing), layer, live
-- (a face-to-face game's player: their character only while near you, SPEC decision 72), low (a crest's name a line
-- lower: every other one in a crowded row), bare (without the name: a poster says it), line and lineColor (what they
-- do, under the name: S:Say). The player's real model when the game has had them near this session
-- (Guild/Looks.lua), else their class crest; both with their name.
function S:Actor(role, name, x, face, o)
  o = o or {}
  local model = not (o.live and not ns.Looks.Near(name)) and ns.Looks:Model(name, self.kind or "panel") or nil
  local m = self.cast[role]
  -- Another player in this role, or their model loaded meanwhile: the old one goes.
  if m and (m.who ~= name or (model and m ~= model)) then letGo(self, role) m = nil end
  if not m then
    if model then
      -- (A model on another stage of the same kind comes over: it can be in one place at a time.)
      local was = model.stage
      if was and was ~= self then
        for r, x2 in pairs(was.cast) do if x2 == model then was.cast[r] = nil end end
      end
      m = model
      m.stage = self
      m:SetParent(self.canvas)
      m.move = nil
    else
      self.crests = self.crests or {}
      m = self.crests[role] or crest(self.canvas)
      self.crests[role] = m
      m:Set(name, o.class or ns.Roster:Class(name))
    end
    m.who = name
    self.cast[role] = m
    m.note = lookNote(name, model)
    if model then frameModel(m) end
  end
  m:SetFrameLevel(self.canvas:GetFrameLevel() + 2 + (o.layer or 0))
  local size = o.size or 1
  m:SetSize(Sg.ACTOR_W * size, Sg.ACTOR_H * size)
  local nm = Sg.Tag(m)
  if m.isModel and m.tag then
    m.tag:SetFrameLevel(m:GetFrameLevel() + 1)
    local class = ns.Roster:Class(name)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    nm:SetText(ns.Short(name))
    if c then nm:SetTextColor(c.r, c.g, c.b) else nm:SetTextColor(1, 1, 1) end
  end
  if nm then
    nm:ClearAllPoints()
    nm:SetPoint("TOP", m, "BOTTOM", 0, o.low and 3 or 14)
    nm:SetShown(not o.bare)
  end
  m.bare = o.bare
  self:Say(m, o.line, o.lineColor)
  m.x, m.floor, m.size = x, o.floor or Sg.FLOOR, size
  m:ClearAllPoints()
  m:SetPoint("BOTTOM", self.canvas, "TOPLEFT", x, -m.floor - 2)
  m.facing = (face or 1) * Sg.TURN
  if m.SetFacing then m:SetFacing(m.facing) end
  m:SetAlpha(1)
  m:Show()
  if self.quiet and m.EnableMouse then m:EnableMouse(false) end
  if o.move and m.move ~= o.move then self:Do(m, o.move) end
  return m
end

-- What character m does, on the line under their name (SPEC decision 74): "rolled 64", "Guilty!". color: { r, g, b }
-- (default Sg.LINE); delay: it pops in then (a moment), else it shows at once. nil text: no line.
function S:Say(m, text, color, delay)
  local nm, line = Sg.Tag(m)
  if not line then return end
  m.said = text
  line:SetText(text or "")
  local c = color or Sg.LINE
  line:SetTextColor(c[1], c[2], c[3])
  line:ClearAllPoints()
  if m.bare or not nm then line:SetPoint("TOP", m, "BOTTOM", 0, 14)
  else line:SetPoint("TOP", nm, "BOTTOM", 0, -1) end
  line:SetShown(text ~= nil and text ~= "")
  if delay and text and UI.Motion() then V.PopIn(line, delay) end
end

-- Character m does move after delay seconds (0: now). With motion off, only where it ends (Sg.STILL).
function S:Do(m, move, delay, after)
  if not m then return end
  if not UI.Motion() then
    act(m, Sg.STILL[move] or move)
    return
  end
  self:After(delay or 0, function() act(m, move, after) end)
end

-- Character m runs to where they stand (s:Actor's x) from x = from, over dur seconds, from delay; then does arrive
-- (default: stand). The run only brings them there: their place does not change.
function S:Run(m, from, dur, delay, arrive)
  if not m then return end
  if not UI.Motion() or from == m.x then
    act(m, Sg.STILL[arrive or "stand"] or arrive or "stand")
    return
  end
  V.Glide(m, from - m.x, 0, dur, delay, false, "NONE")
  self:Do(m, "run", delay)
  self:Do(m, arrive or "stand", (delay or 0) + dur)
end

-- A scene's move from a point to another, in the game's directions: scene y grows downwards, the game's upwards.
function Sg.Offset(fromX, fromY, toX, toY) return fromX - toX, toY - fromY end

-- Where the top of character m's head is, in scene units (for a crown, a hat, a number over them).
function S:Head(m)
  if not m then return Sg.W / 2, Sg.FLOOR - 90 end
  return m.x, m.floor - Sg.ACTOR_H * m.size * 0.84
end

---------------------------------------------------------------------------
-- Props: made once on this stage by role, over the characters; hidden when not drawn in a refresh (s:Done)
---------------------------------------------------------------------------
local function prop(s, role, make)
  local p = s.props[role]
  if not p then
    p = make()
    s.props[role] = p
  end
  s.used[role] = true
  p:Show()
  return p
end

-- A prop of the scene's own making (make(top) returns a region or frame on s.top), kept by role like the others.
function S:Prop(role, make) return prop(self, role, function() return make(self.top) end) end

-- Puts region r at x, y of the scene (its point, default CENTER).
function S:At(r, x, y, point)
  r:ClearAllPoints()
  r:SetPoint(point or "CENTER", self.canvas, "TOPLEFT", x, -y)
  return r
end

-- A texture: an icon (UI.ICON path), a file of ours (Media), or a colour. o: size, alpha (0 for a prop that only
-- shows while it moves), color { r, g, b, a }, blend, sub (its sublevel), under (behind the characters: a poster
-- with a player on it).
function S:Tex(role, x, y, o)
  o = o or {}
  local t = prop(self, role, function()
    return (o.under and self.canvas or self.top):CreateTexture(nil, o.under and "BORDER" or "ARTWORK", nil, o.sub)
  end)
  -- A prop kept by role may have been a rounded one before (its corners sliced): plain again unless round.
  if not o.round and t.ClearTextureSlice then t:ClearTextureSlice() end
  if o.icon then UI.IconTex(t, o.icon)
  elseif o.file then t:SetTexture(ns.MEDIA .. o.file); t:SetTexCoord(0, 1, 0, 1)
  elseif o.path then t:SetTexture(o.path); t:SetTexCoord(0, 1, 0, 1)
  elseif o.round then UI.Round(t, "Glass", o.color)
  else t:SetColorTexture(1, 1, 1, 1) end
  if o.color and not o.round then t:SetVertexColor(o.color[1], o.color[2], o.color[3], o.color[4] or 1) end
  if o.blend then t:SetBlendMode(o.blend) end
  t:SetSize(o.w or o.size or 24, o.h or o.size or 24)
  t:SetAlpha(o.alpha or 1)
  return self:At(t, x, y, o.point)
end

-- A line of text. font: a game font object (default GameFontNormalLarge, gold).
function S:Text(role, text, x, y, font, o)
  o = o or {}
  local t = prop(self, role, function() return UI.Text(self.top, font or "GameFontNormalLarge", "CENTER") end)
  t:SetFontObject(font or "GameFontNormalLarge")
  t:SetText(text or "")
  if o.color then t:SetTextColor(o.color[1], o.color[2], o.color[3]) end
  t:SetAlpha(o.alpha or 1)
  return self:At(t, x, y, o.point)
end

-- A small glass panel (numbers, a ladder, a bracket), from its top left.
function S:Panel(role, x, y, w, h)
  local p = prop(self, role, function()
    local f = CreateFrame("Frame", nil, self.top)
    UI.Glass(f, { 0.03, 0.035, 0.05, 0.82 }, { 1, 0.85, 0.5, 0.32 })
    return f
  end)
  p:SetSize(w, h)
  return self:At(p, x, y, "TOPLEFT")
end

-- A die at x, y showing n ("?" while it is not known). The face looks the same for every number; the number, and the
-- red glow of a 1, are separate, so they show only when the die lands (S:Roll).
function S:Die(role, x, y, n)
  local glow = self:Tex(role .. ".red", x, y, { file = "Glow", size = 64, color = { 0.95, 0.2, 0.1 }, blend = "ADD" })
  glow:SetShown(n == 1)
  local face = self:Tex(role, x, y, { round = true, size = 26, color = { 0.98, 0.95, 0.88 }, sub = 1 })
  local t = self:Text(role .. ".n", n and tostring(n) or "?", x, y + 1, "GameFontNormal")
  if n == 1 then t:SetTextColor(0.85, 0.1, 0.05) else t:SetTextColor(0.16, 0.11, 0.04) end
  face.num, face.red = t, glow
  return face, t
end

-- A die's throw: it tumbles (from delay) and its number shows when it lands.
function S:Roll(face, num, delay)
  V.Tumble(face, 0.68, delay)
  V.PopIn(num, (delay or 0) + 0.68, 1.6)
  if face.red and face.red:IsShown() then V.PopIn(face.red, (delay or 0) + 0.68, 0.3) end
end

-- Hides the props this refresh did not draw. Each scene ends with it.
function S:Done()
  for role, p in pairs(self.props) do
    if not self.used[role] then p:Hide() end
  end
end
