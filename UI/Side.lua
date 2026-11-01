-- What you picked (SPEC §2b; SPEC decision 59, docs/mockup/Frame.html): the right column of the panel under the guild
-- window (UI/Hall.lua), next to the feature's list. It shows what was picked on a page: its details, a
-- picture (UI/Visuals.lua) and its buttons (Accept the duel, /roll, Throw a tomato, Vote), at most one main button and
-- one more. A page offers it with def.side(page) -> { key, icon, title, sub, draw = function(flow), buttons = { {
-- label, onClick, next = true }, ... } } or nil; with nothing picked, the column says to pick a row on the left.
local _, ns = ...
local L, UI = ns.L, ns.UI
local Side = {}
ns.Side = Side

Side.HERO_H = 58   -- the heading: what you picked, with its medallion
Side.BUTTONS = 2   -- at most: one main button and one more
Side.ICON = 40     -- the heading's medallion
-- The scene's window beside the panel (SPEC decision 63): as wide as the screen leaves room for, up to SCENE_W, and
-- not narrower than SCENE_MIN (else the scene stays in the column); OUT from the panel's edge, past the frame.
Side.SCENE_W, Side.SCENE_MIN, Side.OUT, Side.PAD, Side.HEAD = 480, 240, 26, 8, 24

-- The column in body (the panel's), x from its left, w x h big.
function Side:Build(body, x, w, h)
  if self.frame then return end
  -- Nothing picked: a quiet medallion of the feature, and what to do.
  local idle = CreateFrame("Frame", nil, body)
  idle:SetPoint("TOPLEFT", x, 0)
  idle:SetSize(w, h)
  UI.Glass(idle)
  idle.icon = idle:CreateTexture(nil, "ARTWORK")
  idle.icon:SetSize(72, 72)
  idle.icon:SetPoint("CENTER", 0, 24)
  idle.icon:SetAlpha(0.3)
  idle.text = UI.Wrap(idle, "GameFontDisable", w - 60)
  idle.text:SetJustifyH("CENTER")
  idle.text:SetPoint("TOP", idle.icon, "BOTTOM", 0, -12)
  idle.text:SetText(L.BIG_IDLE)
  idle:Hide()
  self.idle = idle

  local s = CreateFrame("Frame", nil, body)
  s:SetPoint("TOPLEFT", x, 0)
  s:SetSize(w, h)
  s:SetFrameLevel(body:GetFrameLevel() + 10)
  s:EnableMouse(true)
  -- The heading: a medallion, the title and one line, on a card of its own.
  local hero = CreateFrame("Frame", nil, s)
  hero:SetPoint("TOPLEFT")
  hero:SetPoint("TOPRIGHT")
  hero:SetHeight(self.HERO_H - 6)
  UI.Glass(hero)
  local icon, ring = UI.Medallion(hero, self.ICON)
  icon:SetPoint("CENTER", hero, "LEFT", 10 + self.ICON / 2, 0)
  local title = UI.Color(UI.Text(hero, "GameFontNormalLarge"), "gold")
  title:SetPoint("TOPLEFT", hero, "TOPLEFT", 20 + self.ICON, -9)
  title:SetPoint("RIGHT", -34, 0)
  title:SetWordWrap(false)
  local sub = UI.Color(UI.Text(hero, "GameFontHighlightSmall"), "sub")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
  sub:SetPoint("RIGHT", -34, 0)
  sub:SetWordWrap(false)
  local close = UI.Create("Button", hero, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() Side:Dismiss() end)
  -- The body: a pane like the list's, with its scroll bar and its bar of buttons.
  local pane = UI.Pane(s, w, h - self.HERO_H, { foot = true })
  pane:SetPoint("TOPLEFT", 0, -self.HERO_H)
  s.icon, s.ring, s.title, s.sub, s.pane, s.close = icon, ring, title, sub, pane, close
  s.room = w - 20 - self.ICON - 34
  -- A flow of pieces per page, so one page's pieces never meet another's under the same key.
  s.flows = {}
  s:Hide()
  -- The scene's window goes when the column goes, and so does a moment over the chat.
  s:SetScript("OnHide", function()
    if Side.beside then Side.beside:Hide() end
    Side:EndMoment()
  end)
  self.frame = s
end

---------------------------------------------------------------------------
-- The scene's window beside the panel (SPEC decision 63): what you picked plays there large, on the side of the panel
-- the screen has room on (the right first; the left only with the window dressed, where nothing of the game's is).
-- Not in the Guild Together screen, where everything is large already.
---------------------------------------------------------------------------
function Side:Beside()
  local Hall = ns.Hall
  local p = Hall.frame
  if not p or not p:IsShown() or Hall:IsFull() then return nil end
  local k, u = p:GetEffectiveScale(), UIParent:GetEffectiveScale()
  local left, right, screen = p:GetLeft(), p:GetRight(), UIParent:GetRight()
  if not (left and right and screen and k and k > 0) then return nil end
  -- Room on each side, in the panel's own units (screen pixels divided by its scale).
  local room = { right = (screen * u - right * k) / k, left = (left * k - (UIParent:GetLeft() or 0) * u) / k }
  local extra = self.OUT + 2 * self.PAD + 8
  local at
  if room.right - extra >= self.SCENE_MIN then at = "right"
  elseif ns.Frame:Dressed() and room.left - extra >= self.SCENE_MIN then at = "left" end
  if not at then return nil end
  local w = math.min(self.SCENE_W, math.floor(room[at] - extra))
  local b = self.beside
  if not b then
    b = CreateFrame("Frame", nil, p)
    b:SetFrameLevel(p:GetFrameLevel() + 30)
    UI.Glass(b, nil, { UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.55 })
    b.title = UI.Color(UI.Text(b, "GameFontNormal"), "gold")
    b.title:SetPoint("TOPLEFT", self.PAD + 2, -6)
    b.title:SetPoint("RIGHT", -self.PAD, 0)
    b.title:SetWordWrap(false)
    b.host = UI.Stage.Host(b, w, "panel")
    b.host:SetPoint("TOPLEFT", self.PAD, -self.HEAD)
    b:Hide()
    self.beside = b
  end
  b.host:Fit(w)
  b:SetSize(w + 2 * self.PAD, b.host:GetHeight() + self.HEAD + self.PAD)
  b:ClearAllPoints()
  if at == "right" then b:SetPoint("TOPLEFT", p, "TOPRIGHT", self.OUT, 0)
  else b:SetPoint("TOPRIGHT", p, "TOPLEFT", -self.OUT, 0) end
  b.at = at
  return b
end

---------------------------------------------------------------------------
-- A moment over the guild chat (SPEC decision 76): while the guild window shows its Chat tab, a scene's moment (s:New)
-- plays large over the chat's messages, letting the mouse through, for a few seconds (longer while the moment holds,
-- S:Hold), then fades; the scene's last picture stays in the column. Our one frame over the window's middle (decision
-- 58 keeps the rest on its edges): it never takes a click and is gone after the moment. Not with Dress the guild
-- window off, nor in the Guild Together screen.
---------------------------------------------------------------------------
Side.CHAT_STAY, Side.CHAT_FADE, Side.CHAT_MIN = 3, 0.5, 200

-- The chat's messages, when the window shows them. (Dev/SelfTest.lua may lay a stand-in of ours there instead:
-- Side.pretendChat.)
function Side:ChatArea()
  local area = self.pretendChat
  if not area then
    local f = CommunitiesFrame
    if not f or not f:IsVisible() or not ns.Frame:Dressed() or ns.Hall:IsFull() then return nil end
    local chat = f.Chat
    area = type(chat) == "table" and (chat.MessageFrame or chat) or nil
  end
  if not (area and area.IsVisible and area:IsVisible()) or (area:GetWidth() or 0) < self.CHAT_MIN then return nil end
  return area
end

-- Our frame over the chat: a stage as large as the chat's messages allow, the scene's shape kept, and a flow of its
-- own in a pane nobody sees (the pick's drawing runs in it once more, its scene going to the stage).
local function chatFrame(self, area)
  local c = self.chat
  if not c then
    c = CreateFrame("Frame", nil, CommunitiesFrame)
    c:EnableMouse(false)
    c.host = UI.Stage.Host(c, UI.Stage.W, "chat")
    c.host:SetPoint("CENTER")
    c.pane = UI.Pane(c, 300, 200, {})
    c.pane:Hide()
    c.flow = UI.PaneFlow(c.pane)
    -- It stays its time, fades, and goes at once when the chat does (another tab of the window).
    c:SetScript("OnUpdate", function(frame)
      local left = (frame.ends or 0) - GetTime()
      if left <= 0 or not (frame.area and frame.area:IsVisible()) then frame:Hide() return end
      frame:SetAlpha(math.min(1, left / Side.CHAT_FADE))
    end)
    c:Hide()
    self.chat = c
  end
  c.area = area
  c:ClearAllPoints()
  c:SetAllPoints(area)
  local Sg = UI.Stage
  local w, h = area:GetWidth() or 0, area:GetHeight() or 0
  c.host:Fit(math.max(120, math.floor(math.min(w, h * Sg.W / Sg.H) - 8)))
  -- Over the chat and its scroll bar (and the rest of Blizzard's in the window), each layer of the stage above the last.
  local n = ns.Hall:Lift(c)
  local st = c.host.stage
  c.host:SetFrameLevel(n + 1)
  st:SetFrameLevel(n + 2)
  st.canvas:SetFrameLevel(n + 3)
  st.top:SetFrameLevel(n + 23)
  return c
end

-- Draws want's scene over the chat (area) once more: when a moment begins there (S:New), it shows for its time and
-- returns true; else it stays hidden and the column plays the scene as before. A refresh while a moment of the same
-- pick still plays leaves it to play.
function Side:Moment(want, area)
  local c = self.chat
  if c and c:IsShown() and c.key == want.key and c.area == area then return true end
  c = chatFrame(self, area)
  c.key = want.key
  -- (Shown but see-through while it draws: what moves on a hidden stage would not play.)
  c.ends = nil
  c:SetAlpha(0)
  c:Show()
  local st, fl = c.host.stage, c.flow
  local before = st.news or 0
  fl.into, fl.staged = c.host, nil
  fl:Begin()
  local ok, err = pcall(want.draw, fl)
  fl:End()
  fl.into = nil
  if not ok then ns:LogError("chat moment", tostring(want.key), tostring(err)) end
  if not (ok and fl.staged and (st.news or 0) > before) then
    c:Hide()
    return false
  end
  local held = st.holdUntil and st.holdUntil - GetTime() or 0
  local stay = math.max(self.CHAT_STAY, held + 1) + self.CHAT_FADE
  c.ends = GetTime() + stay
  c:SetAlpha(1)
  -- (Its end is timed too: OnUpdate only fades it.)
  c.token = (c.token or 0) + 1
  local token = c.token
  if C_Timer then C_Timer.After(stay, function() if c.token == token then c:Hide() end end) end
  self.moments = (self.moments or 0) + 1
  return true
end

-- The moment over the chat goes now (the column closed, the Guild Together screen opened).
function Side:EndMoment()
  if self.chat then self.chat:Hide() end
end

-- Something opened from anywhere (UI/Card.lua: the player card): fn() -> what to show, over what the page offers,
-- until it is closed or a row is picked (Hall clears it). The panel opens for it.
function Side:Over(fn)
  self.over = fn
  self.dismissed = nil
  ns.Hall:Reveal()
  ns.Hall:Refresh()
end

-- Closed by its button: it stays closed until something else is picked. What a row opened (a form, details) is
-- put away.
function Side:Dismiss()
  if self.over then
    self.over = nil
    if self.frame then self.frame:Hide() end
    return ns.Hall:Refresh()
  end
  if self.viewOf then
    self.viewOf.view = nil
    self.viewOf = nil
    if self.frame then self.frame:Hide() end
    return ns.Hall:Refresh()
  end
  self.dismissed = self.key
  if self.frame then self.frame:Hide() end
  ns.Hall:Refresh()
end

-- The quiet column, for a page with a list on the left (not one that fills the panel itself, Guild settings).
local function idle(def, feat)
  local on = def and def.frame and def.frame.right ~= nil
  Side.idle:SetShown(on)
  if on then UI.IconTex(Side.idle.icon, feat and feat.icon or UI.ICON.question) end
end

-- At a glance (the 1 Nov review): with nothing picked, the column shows what matters in the feature now, rather than
-- standing empty: the page's own glance (def.glance(page, part, flow) -> true when it drew something) and what waits
-- for you on the page; with neither, the quiet column. Its close button gives way to the quiet column too.
Side.GLANCE_WAITS = 5
local function glance(def, feat)
  local page = def and def.frame
  if not (page and page.right and page.split and feat) or def.noGlance then return nil end
  -- (Nothing of its own and nothing waiting: the quiet column, not an empty glance.)
  local waits = ns.Hall.todo and ns.Hall.todo[def.id] or {}
  if not def.glance and #waits == 0 then return nil end
  local part = page.part
  local status = page.split.status and page.split.status[part]
  local ok, sub = true, nil
  if status then ok, sub = pcall(status, page) end
  return { key = "glance:" .. def.id .. ":" .. tostring(part), icon = feat.icon, title = feat.label,
    sub = ok and type(sub) == "string" and sub or "", glance = true,
    draw = function(f)
      local any = false
      if def.glance then
        local okG, drew = pcall(def.glance, page, part, f)
        if not okG then ns:LogError("glance", def.id, tostring(drew)) end
        any = okG and drew == true
      end
      if #waits > 0 then
        f:Strip("gw", L.GLANCE_WAITS)
        for i, line in ipairs(waits) do
          if i <= Side.GLANCE_WAITS then f:Text("gw" .. i, "- " .. line) end
        end
        any = true
      end
      if not any then f:Empty("gq", L.GLANCE_QUIET, L.BIG_IDLE) end
    end }
end
Side.Glance = glance

-- What a row opened (Hall:ViewSide: a form or details, with its actions), else what the page picked (def.side), else
-- the feature at a glance: the column shows it (closed, it says to pick a row).
function Side:From(def, feat)
  if not self.frame then return end
  local want = self.over and self.over()
  if want then
    self.viewOf = nil
  else
    want = def and def.frame and ns.Hall:ViewSide(def)
    self.viewOf = want and want.view or nil
    if not want then want = def and def.side and def.frame and def.side(def.frame) end
    if not want then want = glance(def, feat) end
  end
  if not want then
    self.key = nil
    self.frame:Hide()
    return idle(def, feat)
  end
  if want.key ~= self.key then
    self.dismissed = nil
    self.frame.pane.scroll:SetVerticalScroll(0)
  end
  self.key = want.key
  if self.dismissed == want.key then
    self.frame:Hide()
    return idle(def, feat)
  end
  self.idle:Hide()
  local s = self.frame
  if want.player then
    -- (A player: their class's icon in the ring.)
    UI.SetIcon(s.icon, s.ring, UI.ICON.question, self.ICON)
    UI.PlayerIcon(s.icon, want.player)
    s.ring:Show()
  else
    UI.SetIcon(s.icon, s.ring, want.icon or UI.ICON.question, self.ICON)
  end
  -- A long title (a poll's question, up to 80 letters) steps down in size, and at the smallest takes two lines.
  local function wide(fs) return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() end
  s.title:SetFontObject("GameFontNormalLarge")
  s.title:SetWordWrap(false)
  s.title:SetText(want.title or "")
  if wide(s.title) > s.room then s.title:SetFontObject("GameFontNormal") end
  if wide(s.title) > s.room then
    s.title:SetFontObject("GameFontNormalSmall")
    s.title:SetWordWrap(true)
    s.title:SetMaxLines(2)
  end
  UI.Color(s.title, "gold")
  s.sub:SetText(want.sub or "")
  s:Show()
  local key = want.flow or (def and def.id) or "?"
  local f = s.flows[key]
  if not f then
    f = UI.PaneFlow(s.pane)
    s.flows[key] = f
  end
  if s.last and s.last ~= f then s.last:Begin(); s.last:End() end
  s.last = f
  -- A scene's moment plays over the guild chat while the window shows it (decision 76): the column keeps its last
  -- picture. Else the scene goes to the window beside the panel when the screen has room for it (Flow:Stage,
  -- UI/Stage.lua).
  local chat = self:ChatArea()
  if chat then self:Moment(want, chat) else self:EndMoment() end
  local beside = not chat and self:Beside() or nil
  f.into, f.staged = beside and beside.host or nil, nil
  f:Begin()
  local made = want.draw(f)
  f:End()
  f.into = nil
  if beside then
    beside.title:SetText(want.title or "")
    beside:SetShown(f.staged == true)
  elseif self.beside then
    self.beside:Hide()
  end
  -- Its buttons along the bottom (given, or what a form drew); without any, the bar goes and the body reaches down.
  local list, buttons = want.buttons or (type(made) == "table" and made) or {}, {}
  for i = 1, math.min(self.BUTTONS, #list) do buttons[i] = list[i] end
  s.pane.foot:SetShown(#buttons > 0)
  s.pane.scroll:SetPoint("BOTTOMRIGHT", -16, (#buttons > 0 and UI.FOOT_H or 0) + 5)
  UI.Foot(s.pane, buttons)
end

-- A row picked again: what it shows comes back, also after the close button.
function Side:Undismiss() self.dismissed = nil end

function Side:IsShown() return self.frame ~= nil and self.frame:IsShown() end
