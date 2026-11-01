-- Alerts: a big line across the middle of the screen, like a raid warning, for the guild's big moments (from
-- Guild/Announce.lua's ALERT): a sentence, the crown falling, a champion, a winner, BINGO! Also:
--   the Wheel of Punishment: when it is spun, it turns on every screen with the addon at once, slows and lands;
--   games starting: the flash mob counts down from 10 for everyone, and a game you joined says when it begins;
--   Monday's Gazette (SPEC decision 52): at the first login of a week, a toast with last week's paper.
-- Each player can switch alerts off (/gtf alerts); then the Wheel's result is a chat line instead. A small frame of
-- our own, made out of combat at login; never shown from the self-test's pretend guild.
local _, ns = ...
local L, UI, D = ns.L, ns.UI, ns.GuildData
local St, Gm = ns.Stocks, ns.Games

local Al = { queue = {}, log = {}, shown = {} }
ns.Alerts = Al

Al.HOLD = 4          -- seconds an alert stays
Al.FADE = 0.6
Al.SPIN = 3.2        -- seconds the Wheel turns before it lands
Al.QUEUE_MAX = 6
Al.LOG_MAX = 50
Al.COUNT = 10        -- the flash mob's countdown, in seconds
Al.WARN = 60         -- and its warning, a minute before
Al.SCENE_W = 448     -- the moment's scene under the line (SPEC decision 63), and how much longer the line stays for it
Al.SCENE_HOLD = 2
Al.W, Al.H = 760, 124 -- the line's size at normal size

local function on() return ns.Settings:Get("alerts") ~= false end

-- Where the alert line shows and how big (Your options, asked for by the owner on 1 Nov 2026): at the top (aside from
-- the guild window when it is open there), in the middle, or above the action bars; small, normal or large.
Al.SPOTS = { "top", "middle", "bottom" }
Al.SIZES = { small = 0.8, normal = 1, large = 1.25 }
Al.SIZE_ORDER = { "small", "normal", "large" }
local function scenesOn() return ns.Settings:Get("alertScenes") ~= false end

Al.FLOOR = 120       -- at the top, the line and its scene stay this far above the screen's bottom (the action bars)
Al.MIN_K = 0.6       -- and beside the guild window they may shrink to this, to keep clear of it

-- Where the alert line goes now, in UIParent's units from its bottom left: the middle of its top edge (cx, top), its
-- scale k, the guild window's rect when it is open ({ l, r, t, b }: the window with our bar and panel under it) and the
-- spot. At the top, when the window is open under it: beside it if the line fits on a side, else under the column if
-- the line and its scene fit there, else beside it made smaller. It never sits on the column (its crest sat on our bar:
-- shot 173 of the third check of 1 November). For Al:Place and the picture in Your options (Al:Preview).
function Al:Where()
  local S = ns.Settings
  local spot = S:Get("alertSpot") or "top"
  local k = self.SIZES[S:Get("alertSize") or "normal"] or 1
  local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  local Hall, us = ns.Hall, UIParent:GetEffectiveScale()
  local win
  for _, fr in ipairs({ CommunitiesFrame, Hall and Hall.bar, Hall and Hall.frame }) do
    if fr and fr:IsVisible() and fr:GetLeft() and fr:GetTop() then
      local cs = fr:GetEffectiveScale() / us
      local l, r, t, b = fr:GetLeft() * cs, fr:GetRight() * cs, fr:GetTop() * cs, fr:GetBottom() * cs
      if not win then win = { l = l, r = r, t = t, b = b }
      else win.l, win.r, win.t, win.b = math.min(win.l, l), math.max(win.r, r), math.max(win.t, t), math.min(win.b, b) end
    end
  end
  local mid = W / 2
  if spot == "middle" then return mid, H / 2 + 120 + self.H * k / 2, k, win, spot end
  if spot == "bottom" then return mid, 230 + self.H * k, k, win, spot end
  local need = self.W * k
  if win and win.l < mid + need / 2 and win.r > mid - need / 2 then
    local right, left = W - win.r - 20, win.l - 20
    if right >= need then return win.r + (W - win.r) / 2, H - 126, k, win, spot end
    if left >= need then return win.l / 2, H - 126, k, win, spot end
    local tall = self.H + (scenesOn() and 14 + self.SCENE_W * UI.Stage.H / UI.Stage.W or 0)
    if win.b - 20 - tall * k >= self.FLOOR then return mid, win.b - 20, k, win, spot end
    local small = math.max(self.MIN_K, math.min(k, math.max(right, left) / self.W))
    if right >= left then return win.r + (W - win.r) / 2, H - 126, small, win, spot end
    return win.l / 2, H - 126, small, win, spot
  end
  return mid, H - 126, k, win, spot
end

function Al:Place()
  local f = self.frame
  if not f then return end
  local cx, top, k, _, spot = self:Where()
  f:SetScale(k)
  f:ClearAllPoints()
  if spot == "middle" then f:SetPoint("CENTER", UIParent, "CENTER", 0, 120 / k)
  elseif spot == "bottom" then f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230 / k)
  else f:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx / k, top / k) end
end

-- Your options' picture of your screen (the second check of 1 November): the guild window where it is, and the alert
-- line where and how big you picked, with its scene under it while scenes are on. f: a flow (Home's side column).
local function rect(parent, fill, edge, label)
  local r = CreateFrame("Frame", nil, parent)
  UI.Glass(r, fill, edge)
  r.label = UI.Text(r, "GameFontDisableSmall", "CENTER")
  r.label:SetPoint("CENTER")
  r.label:SetText(label)
  return r
end
function Al:Preview(f)
  local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  if W <= 0 or H <= 0 then return end
  local pw = f.width
  local s = pw / W
  local b = f:piece("alertPreview", function()
    local p = CreateFrame("Frame", nil, f.card)
    UI.Glass(p, { 0.02, 0.025, 0.035, 0.95 }, { UI.LOOK.gold[1], UI.LOOK.gold[2], UI.LOOK.gold[3], 0.45 })
    p.win = rect(p, { 0.16, 0.14, 0.11, 0.95 }, { 0.6, 0.55, 0.45, 0.6 }, L.OPT_PREVIEW_WINDOW)
    p.scene = rect(p, { 0.3, 0.22, 0.1, 0.55 }, { 1, 0.85, 0.5, 0.3 }, "")
    p.line = rect(p, { 0.1, 0.08, 0.05, 0.95 }, { 1, 0.82, 0.3, 1 }, L.OPT_PREVIEW_ALERT)
    UI.Color(p.line.label, "gold")
    p.scene:SetFrameLevel(p:GetFrameLevel() + 2)
    p.line:SetFrameLevel(p:GetFrameLevel() + 3)
    return p
  end, "alertPreview")
  local ph = math.floor(H * s + 0.5)
  b:SetSize(pw, ph)
  b:SetPoint("TOPLEFT", f.pad, f.y)
  f.y = f.y - ph - UI.FLOW_GAP
  local function put(r, l, top, w, h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", b, "BOTTOMLEFT", l * s, top * s)
    r:SetSize(math.max(2, w * s), math.max(2, h * s))
    r:Show()
  end
  local cx, top, k, win = self:Where()
  if win then put(b.win, win.l, win.t, win.r - win.l, win.t - win.b) else b.win:Hide() end
  put(b.line, cx - self.W * k / 2, top, self.W * k, self.H * k)
  if scenesOn() then
    local sw = self.SCENE_W * k
    put(b.scene, cx - sw / 2, top - self.H * k + 14 * k, sw, sw * UI.Stage.H / UI.Stage.W)
  else
    b.scene:Hide()
  end
  f:Text("previewNote", L.OPT_PREVIEW_NOTE, "GameFontDisableSmall")
end

-- A champion, a crown or BINGO! gets a fanfare; anything else the raid warning's sound.
local function sound(a) UI.Sound(a and a.fanfare and "fanfare" or "alert") end

function Al:Build()
  if self.frame then return end
  local f = UI.Create("Frame", UIParent)
  f:SetSize(self.W, self.H)
  f:SetPoint("TOP", 0, -126)
  f:SetFrameStrata("HIGH")
  -- The Guild Together emblem over the line (SPEC decision 53).
  f.crest = f:CreateTexture(nil, "ARTWORK")
  f.crest:SetTexture(ns.MEDIA .. UI.EMBLEM_SMALL)
  f.crest:SetSize(40, 40)
  f.crest:SetPoint("TOP", 0, 0)
  f.text = UI.Text(f, "GameFontNormalHuge", "CENTER")
  f.text:SetPoint("TOP", f.crest, "BOTTOM", 0, -4)
  f.text:SetWidth(760)
  f.text:SetTextColor(1, 0.82, 0)
  f.sub = UI.Text(f, "GameFontHighlightLarge", "CENTER")
  f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -6)
  f.sub:SetWidth(760)
  -- A big moment's medal, over the line where the emblem is (SPEC decision 60): it drops in, or stamps down.
  f.medal = f:CreateTexture(nil, "ARTWORK", nil, 2)
  f.medal:SetSize(48, 48)
  f.medal:SetPoint("CENTER", f.crest, "CENTER")
  f.medal:Hide()
  -- The Wheel of punishment, under the line, turning on every screen at once.
  f.wheel = UI.Visuals.Wheel(f, 132)
  f.wheel:SetPoint("TOP", f.sub, "BOTTOM", 0, -16)
  f.wheel:Hide()
  -- A moment's scene, large, under the line (SPEC decision 63): a click opens the activity in the panel.
  f.scene = UI.Stage.Host(f, self.SCENE_W, "toast")
  f.scene:SetPoint("TOP", f.sub, "BOTTOM", 0, -14)
  f.scene:EnableMouse(true)
  f.scene:SetScript("OnMouseUp", function()
    local a = Al.cur
    if a and a.scene and a.scene.go then ns.Hall:Go(a.scene.go) end
  end)
  UI.Tooltip(f.scene, function() return Al.cur and Al.cur.text or "" end, L.AL_SCENE_OPEN)
  -- Framed like the game's own banners (SPEC decision 75): a gold edge, a gold diamond at each corner.
  local rim = CreateFrame("Frame", nil, f.scene)
  rim:SetPoint("TOPLEFT", -3, 3)
  rim:SetPoint("BOTTOMRIGHT", 3, -3)
  rim:SetFrameLevel(f.scene:GetFrameLevel() + 20)
  local gold = UI.LOOK.gold
  UI.Round(rim:CreateTexture(nil, "OVERLAY"), "Edge", { gold[1], gold[2], gold[3], 0.9 }):SetAllPoints()
  rim.gems = {}
  for i, at in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local gem = rim:CreateTexture(nil, "OVERLAY", nil, 1)
    gem:SetColorTexture(gold[1], gold[2], gold[3], 1)
    gem:SetSize(9, 9)
    gem:SetPoint("CENTER", rim, at)
    if gem.SetRotation then gem:SetRotation(math.rad(45)) end
    rim.gems[i] = gem
  end
  f.scene.rim = rim
  f.scene:Hide()
  f:SetScript("OnUpdate", function() Al:Step(GetTime()) end)
  f:Hide()
  self.frame = f
end

local function wheelAt(list, r)
  for i, p in ipairs(list) do if p == r then return i end end
  return 1
end

-- How an alert comes in: its medal drops or stamps down; the meet-up's numbers zoom in; the Wheel starts turning
-- (and lands on the real result). With motion off, it is simply there.
function Al:Arrive(a)
  local f, V = self.frame, UI.Visuals
  local icon = a.icon and UI.ICON[a.icon]
  f.medal:SetShown(icon ~= nil)
  f.crest:SetShown(icon == nil)
  if icon then UI.IconTex(f.medal, icon) end
  f.wheel:SetShown(a.wheel ~= nil)
  local at = a.wheel and wheelAt(a.wheel.slices, a.wheel.r)
  if not UI.Motion() then
    if a.wheel then V.WheelRest(f.wheel, a.wheel.slices, at) end
    return
  end
  if icon and a.how == "stamp" then V.Stamp(f.medal, 0.05)
  elseif icon then V.Drop(f.medal, 60, 0.5, 0.05) end
  if a.now and tonumber(a.text) then V.PopIn(f.text, 0, 2.6)
  elseif a.now then V.Stamp(f.text, 0) end
  if a.wheel then V.WheelSpin(f.wheel, a.wheel.slices, at, self.SPIN) end
end

-- The moment's scene under the line (SPEC decision 63): drawn by the activity's scene (UI/Scenes.lua) into the line's
-- own stage through a flow of its own off the screen; not when the panel shows that activity already (it plays there),
-- nor with the Wheel (the Wheel is the moment).
function Al:SceneFlow()
  if not self.flow then
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(UI.Stage.W, 600)
    holder:Hide()
    self.flow = setmetatable({ card = holder, width = UI.Stage.W, top = 0, pad = 0, items = {}, used = {} }, UI.Flow)
  end
  return self.flow
end

function Al:Scene(a)
  local f, sc = self.frame, a.scene
  local show = false
  if sc and sc.draw and not a.wheel and scenesOn() and not (ns.Hall:IsOpen() and ns.Hall.current == sc.page) then
    local fl = self:SceneFlow()
    fl.into, fl.staged = f.scene, nil
    fl:Begin()
    local ok, err = pcall(sc.draw, fl)
    fl:End()
    fl.into = nil
    if not ok then ns:LogError("alert scene", sc.page, tostring(err)) end
    show = ok and fl.staged == true
  end
  f.scene:SetShown(show)
  -- It drops in from above under the line (and goes with the line's fade).
  if show then
    a.len = a.len + self.SCENE_HOLD
    if UI.Motion() then UI.Visuals.Drop(f.scene, 24, 0.4) end
  end
  return show
end

-- An alert: { text, sub, wheel = { slices, r }, now = true (shown at once, for the countdown), test = true (the
-- self-test's own, shown anyway), quiet = true (no sound), scene = { page, draw = fn(flow), go = fn() } (its scene
-- under the line, and what a click on it opens) }.
function Al:Push(a)
  self.log[#self.log + 1] = { text = a.text, sub = a.sub, wheel = a.wheel and a.wheel.r or nil }
  while #self.log > self.LOG_MAX do table.remove(self.log, 1) end
  -- (Never from the self-test's pretend guild while it runs; its demo guild, left open to look around in, shows them.)
  local demo = ns.Sandbox and ns.Sandbox.demo and not (ns.SelfTest and ns.SelfTest.running) and not (ns.Tour and ns.Tour.on)
  if not a.test and ((D.sandbox and not demo) or not on()) then return end
  if a.now then
    self.queue = {}
    self.cur = nil
  elseif #self.queue >= self.QUEUE_MAX then
    return
  end
  self.queue[#self.queue + 1] = a
  self:Step(GetTime())
end

-- The Wheel's name for where it may land.
local function slice(p) return L["ACT_" .. p:upper()] end

-- Moves the alert on: the next one when this one is done, the Wheel's turning, the fade.
function Al:Step(now)
  local f = self.frame
  if not f then return end
  local a = self.cur
  if a and now - a.start > a.len then
    a, self.cur = nil, nil
  end
  if not a then
    a = table.remove(self.queue, 1)
    if not a then f:Hide() return end
    a.start = now
    a.len = (a.wheel and self.SPIN or 0) + self.HOLD
    self.cur = a
    if not a.wheel and not a.quiet then sound(a) end
    f.text:SetText(a.text)
    f.sub:SetText(a.sub or "")
    f:SetAlpha(1)
    self:Place()
    f:Show()
    self:Arrive(a)
    self:Scene(a)
  end
  local t = now - a.start
  if a.wheel then
    if t < self.SPIN then
      -- The wheel turns (Al:Arrive): the line under it waits for where it lands.
      f.sub:SetText("")
    elseif not a.landed then
      a.landed = true
      f.sub:SetText(L.AL_WHEEL_LANDED:format(slice(a.wheel.r)))
      sound()
    end
  end
  f:SetAlpha(t > a.len - self.FADE and math.max(0, (a.len - t) / self.FADE) or 1)
end

ns:On("ALERT", function(a) Al:Push(a) end)

---------------------------------------------------------------------------
-- Which scene a big moment plays under the line (SPEC decision 63), from the op that made it (Guild/Announce.lua):
-- { page, draw, go } or nil. Read when it shows, so it draws the guild's data as it is then.
---------------------------------------------------------------------------
local SENTENCE = { trial = true, pardon = true, bail = true, tribute = true }
local function show(page, pick, fn)
  return function()
    ns.Hall:ShowFeature(page, pick)
    local def = ns.Hall.pages[page]
    if fn and def and def.frame then fn(def.frame) ns.Hall:Refresh() end
  end
end

function Al.SceneFor(g, a, op, n)
  local Sc, k = ns.Scenes, op.k
  if not Sc then return nil end
  local sid = (k == "sentence" and D.Key(a, n)) or (SENTENCE[k] and op.id)
    or (k == "duel" and op.c and g.sentences and g.sentences[op.c] and op.c)
  if sid then
    return { page = "stocks", go = show("stocks", "serving", function(p) p.View({ kind = "sentence", id = sid }) end),
      draw = function(f)
        for _, s in ipairs(St.List(g)) do if s.id == sid then Sc.Sentence(f, g, s) end end
      end }
  end
  if k == "crown_no" or (k == "duel" and op.cr) then
    return { page = "arena", go = show("arena", "duels"), draw = function(f) Sc.Crown(f, ns.Crown.State(g)) end }
  end
  if k == "cup_end" and g.cups and g.cups[op.id] then
    local c = g.cups[op.id]
    return { page = c.lead and "council" or "arena", go = c.lead and show("council", "impeach") or show("arena", "cup"),
      draw = function(f) Sc.Cup(f, g, c, op.id) end }
  end
  if k == "raffle_draw" and g.raffles and g.raffles[op.id] then
    return { page = "tavern", go = show("tavern", "raffles"), draw = function(f) Sc.Lottery(f, g.raffles[op.id], op.id) end }
  end
  local gid = (k == "game_end" or k == "game_rep" or k:sub(1, 3) == "tr_" or k:sub(1, 6) == "santa_") and op.id
  local ga = gid and g.games and g.games[gid]
  if ga then
    return { page = "games", go = show("games", "game", function(p) p.sel = gid end),
      draw = function(f) Sc.Game(f, g, ga, gid, ns.Players:Of(ns.Self(), g)) end }
  end
  return nil
end

-- Your own deathroll: each roll of it plays under the line while the panel is not on the deathroll (SPEC decision 63).
-- (A game first seen with rolls in it, after a reload, waits for its next roll.)
Al.rolls = {}
ns:On("TAVERN", function()
  local game = ns.Deathroll and ns.Deathroll:Game()
  if not game or not game.id or (game.st ~= "playing" and game.st ~= "over") then return end
  local n = #(game.rolls or {})
  local seen = Al.rolls[game.id]
  Al.rolls[game.id] = n
  if seen == nil or n <= seen then return end
  local last = game.rolls[n]
  Al:Push({ text = L.TV_DEATHROLL, now = true, quiet = true,
    sub = last.who == "me" and L.AL_DR_YOU:format(last.v) or L.AL_DR_ROLL:format(ns.Short(game.opp), last.v),
    scene = { page = "tavern", go = show("tavern", "deathroll"), draw = function(f) ns.Scenes.Deathroll(f, game) end } })
end)

---------------------------------------------------------------------------
-- Monday's Gazette: at the first login of a week, a toast with last week's paper (its masthead, headline and first
-- story); a click opens it in the Hall of Fame. Once a week for the account, only after a week with news, and not
-- with alerts off or from the self-test's pretend guild.
---------------------------------------------------------------------------
Al.TOAST_HOLD = 12      -- seconds the toast stays
Al.TOAST_DELAY = 6      -- after login

function Al:BuildToast()
  if self.toast then return end
  local t = UI.Create("Button", UIParent)
  t:SetSize(400, 92)
  t:SetPoint("BOTTOM", 0, 190)
  t:SetFrameStrata("HIGH")
  UI.Glass(t, { 0.05, 0.055, 0.07, 0.97 }, { 0.95, 0.79, 0.36, 0.6 })
  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(56, 56)
  t.icon:SetPoint("LEFT", 14, 0)
  UI.IconTex(t.icon, UI.ICON.paper)
  t.mast = UI.Color(UI.Text(t, "GameFontNormalLarge"), "goldHi")
  if not t.mast:SetFont("Fonts\\MORPHEUS.TTF", 18, "") then t.mast:SetFontObject("GameFontNormalLarge") end
  t.mast:SetPoint("TOPLEFT", 82, -12)
  t.mast:SetPoint("RIGHT", -30, 0)
  t.mast:SetWordWrap(false)
  t.head = UI.Wrap(t, "GameFontHighlight", 290)
  t.head:SetPoint("TOPLEFT", t.mast, "BOTTOMLEFT", 0, -4)
  t.head:SetMaxLines(2)
  t.hint = UI.Ink(UI.Text(t, "GameFontDisableSmall"))
  t.hint:SetPoint("BOTTOMLEFT", 82, 9)
  t.hint:SetText(L.TOAST_READ)
  local close = UI.Create("Button", t, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() t:Hide() end)
  t:SetScript("OnClick", function()
    t:Hide()
    Al:ReadGazette()
  end)
  -- It fades in and out (with motion on), and holds while the mouse is over it. It keeps clear of the guild window as
  -- that opens and closes.
  t:SetScript("OnUpdate", function(frame)
    if GetTime() - (frame.placed or 0) > 0.5 then self:PlaceToast() end
    if frame:IsMouseOver() then frame.start = GetTime() - self.FADE end
    local at = GetTime() - frame.start
    if at > self.TOAST_HOLD then frame:Hide() return end
    if not UI.Motion() then frame:SetAlpha(1) return end
    frame:SetAlpha(math.min(1, at / self.FADE, (self.TOAST_HOLD - at) / self.FADE))
  end)
  t:Hide()
  self.toast = t
end

-- The toast's spot: over the action bars in the middle, unless the guild window, the bar or the panel are there (the
-- fourth check of 1 November: it lay over the panel); then beside them, on the side with room (the right first).
Al.TOAST_Y = 190
function Al:PlaceToast()
  local t = self.toast
  if not t then return end
  t.placed = GetTime()
  local _, _, _, win = self:Where()
  local W, tw, th = UIParent:GetWidth() or 0, t:GetWidth(), t:GetHeight()
  local x = W / 2
  if win and win.b < self.TOAST_Y + th and win.t > self.TOAST_Y and win.l < x + tw / 2 and win.r > x - tw / 2 then
    if W - win.r - 20 >= tw then x = win.r + (W - win.r) / 2
    elseif win.l - 20 >= tw then x = win.l / 2 end
  end
  t:ClearAllPoints()
  t:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, self.TOAST_Y)
  t.x = x
end

-- The toast with a Gazette (Ch.Gazette's).
function Al:ShowToast(z)
  self:BuildToast()
  local t = self.toast
  t.week = z.week
  t.mast:SetText(L.TOAST_MAST:format(z.name, ns.Chronicle.WeekNumber(z.week)))
  t.head:SetText(z.headline)
  t.start = GetTime()
  t:SetAlpha(UI.Motion() and 0 or 1)
  self:PlaceToast()
  t:Show()
  UI.Sound("paper")
end

-- At the first login of a week: last week's paper, when it had news. Returns true when it showed.
function Al:Gazette(now)
  local g = D:Current()
  if not g or D.sandbox or not on() then return false end
  now = now or time()
  local week = ns.Chronicle.WeekStart(now)
  if ns.db.gazette == week then return false end
  ns.db.gazette = week
  local z = ns.Chronicle.Gazette(g, week - 1)
  if (z.n or 0) == 0 then return false end
  self:ShowToast(z)
  return true
end

-- Opens the paper of the toast in the Hall of Fame.
function Al:ReadGazette()
  local week = self.toast and self.toast.week
  ns.Hall:Go(function()
    local def = ns.Hall.pages.chronicle
    if not def then return end
    def.frame.gazWeek = week
    ns.Hall:ShowFeature("chronicle", "gazette")
  end)
end

ns:On("LOGIN", function()
  C_Timer.After(Al.TOAST_DELAY, function()
    if not InCombatLockdown() then Al:BuildToast() end
    if Al.toast then Al:Gazette() end
  end)
end)

-- The Wheel spun (Guild/Stocks.lua fires it for the main copy, when it is new).
ns:On("WHEEL", function(id, r)
  local g = D:Current()
  local se = g and g.sentences and g.sentences[id]
  if not on() then ns:Print(L.ST_WHEEL_LANDED:format(slice(r)), true) return end
  local slices = {}
  for _, p in ipairs(St.WHEEL) do slices[#slices + 1] = p end
  Al:Push({ text = L.AL_WHEEL:format(se and ns.Display(se.to) or ""), sub = "", wheel = { slices = slices, r = r } })
end)

-- Games starting: the flash mob's countdown (for everyone), and the start of a game this player joined.
function Al:Tick(now)
  local g = D:Current()
  if not g then return end
  now = now or time()
  local me = ns.Players:Of(ns.Self(), g)
  for _, item in ipairs(Gm.List(g, now)) do
    local ga, id = item.ga, item.id
    local d = (ga.at or 0) - now
    local seen = self.shown[id] or {}
    self.shown[id] = seen
    -- (A game that is over or called off has nothing to say.)
    if ga.st == nil and ga.kind == "flash" then
      local where = ga.spot and ga.spot.z and L.AL_FLASH_WHERE:format(ga.spot.z) or Gm.KindName(ga.kind)
      if d <= self.WARN and d > self.COUNT and not seen.warn then
        seen.warn = true
        self:Push({ text = L.AL_FLASH_SOON, sub = where })
      elseif d >= 1 and d <= self.COUNT and not seen[d] then
        seen[d] = true
        self:Push({ text = tostring(d), sub = where, now = true })
      elseif d <= 0 and d > -self.COUNT and not seen.go then
        seen.go = true
        self:Push({ text = L.AL_FLASH_GO, sub = where, now = true })
      end
    elseif ga.st == nil and d <= 0 and d > -60 and not seen.go and Gm.IsIn(g, ga, me) then
      seen.go = true
      self:Push({ text = L.AL_GAME_BEGINS:format(Gm.KindName(ga.kind)) })
    end
  end
end

ns:On("LOGIN", function()
  ns.Combat:AfterCombat(function()
    Al:Build()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() Al:Tick() end) end
  end)
end)
