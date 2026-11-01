-- Pictures for the games (SPEC §6b, decided 30 Oct 2026: lively): a race track for the gnome run, bars for a
-- leaderboard, a board of tiles for the Traitors, a trail of clues for the scavenger hunt, the cup's bracket, the
-- deathroll's ladder and the flash mob's clock. They are flow pieces like those in UI/Widgets.lua: made once by key,
-- reused, placed down the card. The motion is the game's own animations (AnimationGroup), which only run while the
-- page shows. A name that does not fit ends in "..." (frame.short: the self-test allows it); its tooltip shows it whole.
local _, ns = ...
local L, UI = ns.L, ns.UI
local Flow = UI.Flow
local V = {}
UI.Visuals = V

-- The game's own textures (the self-test checks each one loads).
V.TEX = {
  spark = "Interface\\Cooldown\\star4",
  check = "Interface\\RaidFrame\\ReadyCheck-Ready",
  white = "Interface\\Buttons\\WHITE8X8",
}
V.GOLD, V.BLUE, V.GREEN = { 1, 0.82, 0 }, { 0.26, 0.42, 1 }, { 0.3, 0.75, 0.3 }
V.RED, V.ORANGE, V.GREY = { 0.75, 0.16, 0.12 }, { 0.8, 0.45, 0.1 }, { 0.42, 0.42, 0.42 }

---------------------------------------------------------------------------
-- Motion
---------------------------------------------------------------------------
local function scale(a, from, to)
  if a.SetScaleFrom then a:SetScaleFrom(from, from); a:SetScaleTo(to, to) else a:SetScale(to / from, to / from) end
end

-- A gentle hop, over and over (a runner on the move, the leader's fish).
function V.Bounce(r, dy)
  local ag = r:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Translation")
  a:SetOffset(0, dy or 3)
  a:SetDuration(0.35)
  a:SetSmoothing("OUT")
  return ag
end

-- A shiver now and then (a skull: someone fell).
function V.Shake(r)
  local ag = r:CreateAnimationGroup()
  ag:SetLooping("REPEAT")
  for i, dx in ipairs({ -2, 4, -4, 4, -2 }) do
    local a = ag:CreateAnimation("Translation")
    a:SetOffset(dx, 0)
    a:SetDuration(0.05)
    a:SetOrder(i)
  end
  local rest = ag:CreateAnimation("Alpha")
  rest:SetFromAlpha(1)
  rest:SetToAlpha(1)
  rest:SetDuration(1.4)
  rest:SetOrder(6)
  return ag
end

-- A slow glow in and out, over and over (a live match): its alpha only, so its size never changes.
function V.Breathe(r)
  local ag = r:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0.35)
  a:SetDuration(0.8)
  a:SetSmoothing("IN_OUT")
  return ag
end

-- Bigger and back, over and over (the clue to find next, a match being played). A texture breathes in alpha instead:
-- a growing texture filled the whole scene in the game (the 1 Nov checks).
function V.Pulse(r, to)
  if r.GetObjectType and r:GetObjectType() == "Texture" then return V.Breathe(r) end
  local ag = r:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Scale")
  scale(a, 1, to or 1.15)
  a:SetDuration(0.6)
  a:SetSmoothing("IN_OUT")
  return ag
end

-- Grows in once (a number that just went up).
function V.Pop(r)
  local ag = r:CreateAnimationGroup()
  local a = ag:CreateAnimation("Scale")
  scale(a, 1.6, 1)
  a:SetDuration(0.3)
  a:SetSmoothing("OUT")
  return ag
end

-- A twinkling star (a winner): it turns and fades in and out.
function V.Sparkle(parent, size)
  local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
  t:SetTexture(V.TEX.spark)
  t:SetBlendMode("ADD")
  t:SetSize(size or 26, size or 26)
  t:SetVertexColor(1, 0.9, 0.5)
  t.spin = t:CreateAnimationGroup()
  t.spin:SetLooping("REPEAT")
  local turn = t.spin:CreateAnimation("Rotation")
  turn:SetDegrees(-360)
  turn:SetDuration(3)
  t.twinkle = t:CreateAnimationGroup()
  t.twinkle:SetLooping("BOUNCE")
  local fade = t.twinkle:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.25)
  fade:SetDuration(0.9)
  fade:SetSmoothing("IN_OUT")
  t:Hide()
  return t
end

-- Plays an animation (or stops it): on is true or false.
function V.Play(ag, on)
  if not ag then return end
  if on then
    if not ag:IsPlaying() then ag:Play() end
  elseif ag:IsPlaying() then
    ag:Stop()
  end
end

local function spark(t, on)
  t:SetShown(on)
  V.Play(t.spin, on)
  V.Play(t.twinkle, on)
end
V.Spark = spark

---------------------------------------------------------------------------
-- Moments (SPEC decision 60): motion that plays once when something happens. A region always holds its last
-- picture; a moment only brings it there (from above, along a throw, out of nothing), so the picture is right
-- whether the motion plays or not (UI.Motion(), the Alerts switch). Each waits hidden for delay seconds first. Their
-- AnimationGroups are made once per region and set again each time. A prop that only shows while it moves (a
-- tomato, a coin) has alpha 0 at rest; its moment shows it while it moves.
---------------------------------------------------------------------------
local function moment(r, name, build)
  r.moments = r.moments or {}
  local m = r.moments[name]
  if not m then
    m = { ag = r:CreateAnimationGroup() }
    build(m, m.ag)
    r.moments[name] = m
  end
  m.ag:Stop()
  return m
end
local function anim(ag, kind, order, dur, smooth)
  local a = ag:CreateAnimation(kind)
  a:SetOrder(order)
  a:SetDuration(dur or 0.3)
  if smooth then a:SetSmoothing(smooth) end
  return a
end
local function fade(a, from, to) a:SetFromAlpha(from); a:SetToAlpha(to); return a end
local function scale2(a, fx, fy, tx, ty)
  if a.SetScaleFrom then a:SetScaleFrom(fx, fy); a:SetScaleTo(tx, ty) else a:SetScale(tx / fx, ty / fy) end
end
-- The wait before a moment: hidden (or shown, for a prop that only shows while it moves).
local function wait(m, ag, delay, alpha)
  m.wait = m.wait or fade(anim(ag, "Alpha", 1, 0.01), 0, 0)
  m.wait:SetFromAlpha(alpha or 0)
  m.wait:SetToAlpha(alpha or 0)
  m.wait:SetDuration(math.max(0.01, delay or 0))
end

-- Falls from h above onto its place, with a small bounce.
function V.Drop(r, h, dur, delay)
  h, dur = h or 40, dur or 0.45
  local m = moment(r, "drop", function(m, ag)
    m.up = anim(ag, "Translation", 1, 0.01)
    m.fall = anim(ag, "Translation", 2, 0.3, "IN")
    m.show = fade(anim(ag, "Alpha", 2, 0.12), 0, 1)
    m.hop = anim(ag, "Translation", 3, 0.08, "OUT")
    m.land = anim(ag, "Translation", 4, 0.08, "IN")
  end)
  wait(m, m.ag, delay)
  m.up:SetOffset(0, h)
  m.fall:SetOffset(0, -h)
  m.fall:SetDuration(dur * 0.7)
  m.hop:SetOffset(0, 5)
  m.hop:SetDuration(dur * 0.15)
  m.land:SetOffset(0, -5)
  m.land:SetDuration(dur * 0.15)
  m.ag:Play()
end

-- Comes down from big onto its place, like a stamp.
function V.Stamp(r, delay)
  local m = moment(r, "stamp", function(m, ag)
    m.size = anim(ag, "Scale", 2, 0.3, "IN")
    scale2(m.size, 2.3, 2.3, 1, 1)
    m.show = fade(anim(ag, "Alpha", 2, 0.2), 0, 1)
  end)
  wait(m, m.ag, delay)
  m.ag:Play()
end

-- Grows out of nothing, a little too far, then settles.
function V.PopIn(r, delay, from)
  local m = moment(r, "popin", function(m, ag)
    m.size = anim(ag, "Scale", 2, 0.24, "OUT")
    m.show = fade(anim(ag, "Alpha", 2, 0.16), 0, 1)
    -- (A finished step's change stays while the group plays: the settle shrinks the 1.08 back to 1.)
    m.settle = anim(ag, "Scale", 3, 0.1, "IN_OUT")
    scale2(m.settle, 1, 1, 1 / 1.08, 1 / 1.08)
  end)
  wait(m, m.ag, delay)
  scale2(m.size, from or 0.2, from or 0.2, 1.08, 1.08)
  m.ag:Play()
end

-- Hidden until delay, then fades in (to the alpha it has).
function V.Reveal(r, delay, dur)
  local m = moment(r, "reveal", function(m, ag) m.show = fade(anim(ag, "Alpha", 2, 0.2), 0, 1) end)
  wait(m, m.ag, delay)
  m.show:SetToAlpha(r:GetAlpha())
  m.show:SetDuration(dur or 0.2)
  m.ag:Play()
end

-- Moves to its place from dx, dy away: a name sliding into the next round (fadeIn: it fades in on the way, and is
-- hidden while it waits), or a character running (it waits where it starts). smooth: default "OUT".
function V.Glide(r, dx, dy, dur, delay, fadeIn, smooth)
  local m = moment(r, "glide", function(m, ag)
    m.away = anim(ag, "Translation", 1, 0.01)
    m.back = anim(ag, "Translation", 2, 0.4, "OUT")
    m.show = fade(anim(ag, "Alpha", 2, 0.25), 0, 1)
  end)
  wait(m, m.ag, delay, fadeIn and 0 or 1)
  m.away:SetOffset(dx, dy or 0)
  m.back:SetOffset(-dx, -(dy or 0))
  m.back:SetDuration(dur or 0.4)
  m.back:SetSmoothing(smooth or "OUT")
  m.show:SetFromAlpha(fadeIn and 0 or 1)
  m.ag:Play()
end

-- Flies to its place along an arc from dx, dy away, lift above the higher end; a texture also turns (spin degrees).
-- transient: a prop with alpha 0 at rest, shown only while it flies.
V.ARC = 8
function V.Fly(r, dx, dy, lift, dur, delay, spin, transient)
  dur = dur or 0.5
  -- Each segment of the arc is one order; its turn and its alpha go with it (an order waits for all of the one before).
  local m = moment(r, "fly", function(m, ag)
    m.away = anim(ag, "Translation", 1, 0.01)
    m.segs, m.turns, m.shows = {}, {}, {}
    local tex = r.GetObjectType and r:GetObjectType() == "Texture"
    for i = 1, V.ARC do
      m.segs[i] = anim(ag, "Translation", 1 + i, 0.05)
      m.shows[i] = fade(anim(ag, "Alpha", 1 + i, 0.05), 1, 1)
      if tex then m.turns[i] = anim(ag, "Rotation", 1 + i, 0.05) end
    end
  end)
  wait(m, m.ag, delay, 0)
  -- A parabola from (dx, dy) to (0, 0) whose top is lift above the higher end.
  local top = math.max(dy, 0) + (lift or 40)
  local function at(t) return dx * (1 - t), dy * (1 - t) * (1 - t) + 2 * top * (1 - t) * t end
  local px, py = dx, dy
  m.away:SetOffset(dx, dy)
  local hold = transient and 1 or r:GetAlpha()
  for i = 1, V.ARC do
    local x, y = at(i / V.ARC)
    m.segs[i]:SetOffset(x - px, y - py)
    m.segs[i]:SetDuration(dur / V.ARC)
    m.shows[i]:SetFromAlpha(hold)
    m.shows[i]:SetToAlpha(hold)
    m.shows[i]:SetDuration(dur / V.ARC)
    if m.turns[i] then
      m.turns[i]:SetDegrees((spin or 0) / V.ARC)
      m.turns[i]:SetDuration(dur / V.ARC)
    end
    px, py = x, y
  end
  m.ag:Play()
end

-- A die tumbling onto its place: up, turning twice, down, a small hop. The number on it is shown by V.Reveal.
function V.Tumble(tex, dur, delay)
  dur = dur or 0.68
  -- Four steps (up, down, a hop up, down), each turning its share of two whole turns.
  local steps = { { 26, 0.32, "OUT", -270 }, { -26, 0.3, "IN", -250 }, { 8, 0.19, "OUT", -110 }, { -8, 0.19, "IN", -90 } }
  local m = moment(tex, "tumble", function(m, ag)
    m.moves, m.turns = {}, {}
    for i, s in ipairs(steps) do
      m.moves[i] = anim(ag, "Translation", 1 + i, 0.1, s[3])
      m.turns[i] = anim(ag, "Rotation", 1 + i, 0.1)
      m.turns[i]:SetDegrees(s[4])
    end
  end)
  wait(m, m.ag, delay, 1)
  for i, s in ipairs(steps) do
    m.moves[i]:SetOffset(0, s[1])
    m.moves[i]:SetDuration(dur * s[2])
    m.turns[i]:SetDuration(dur * s[2])
  end
  m.ag:Play()
end

-- A die rattling in the hand while its roll is on its way (on: true or false).
function V.Rattle(tex, on)
  if not tex.rattle then
    tex.rattle = tex:CreateAnimationGroup()
    tex.rattle:SetLooping("REPEAT")
    local a = tex.rattle:CreateAnimation("Rotation")
    a:SetDegrees(-360)
    a:SetDuration(0.45)
  end
  V.Play(tex.rattle, on and UI.Motion())
end

-- One shake from side to side (a hit, a red die, a scorned gift).
function V.Jolt(r, amp, delay)
  local m = moment(r, "jolt", function(m, ag)
    m.steps = {}
    for i = 1, 6 do m.steps[i] = anim(ag, "Translation", 1 + i, 0.05) end
  end)
  wait(m, m.ag, delay, 1)
  amp = amp or 3
  local path = { -amp, 2 * amp + 1, -2 * amp - 2, 2 * amp + 1, -amp - 0.5, 0 }
  local at = 0
  for i, x in ipairs(path) do
    m.steps[i]:SetOffset(x - at, 0)
    at = x
  end
  m.ag:Play()
end

-- A card turning over: before shrinks away sideways, then after grows back. Two regions at the same place: before
-- has alpha 0 at rest (only seen while it turns), after is the picture that stays. before shows lead seconds before
-- the turn (it stays hidden until then).
function V.Flip(before, after, delay, lead)
  local m1 = moment(before, "flipout", function(m, ag)
    m.hold = fade(anim(ag, "Alpha", 2, 0.01), 1, 1)
    m.show = fade(anim(ag, "Alpha", 3, 0.17), 1, 1)
    m.thin = anim(ag, "Scale", 3, 0.17, "IN")
    scale2(m.thin, 1, 1, 0.02, 1)
  end)
  lead = math.min(lead or 0, delay or 0)
  wait(m1, m1.ag, (delay or 0) - lead)
  m1.hold:SetDuration(math.max(0.01, lead))
  local m2 = moment(after, "flipin", function(m, ag)
    m.wide = anim(ag, "Scale", 2, 0.23, "OUT")
    scale2(m.wide, 0.02, 1, 1, 1)
  end)
  wait(m2, m2.ag, (delay or 0) + 0.17)
  m1.ag:Play()
  m2.ag:Play()
end

-- A texture rocking from side to side (a hat landing), from its bottom.
function V.Wobble(tex, delay)
  local m = moment(tex, "wobble", function(m, ag)
    m.turns = {}
    for i, d in ipairs({ 12, -22, 16, -9, 3 }) do
      local a = anim(ag, "Rotation", 1 + i, 0.12, "IN_OUT")
      a:SetDegrees(d)
      a:SetOrigin("BOTTOM", 0, 0)
      m.turns[i] = a
    end
  end)
  wait(m, m.ag, delay, 1)
  m.ag:Play()
end

-- A gavel: lifted, struck down, back.
function V.Strike(tex, delay)
  local m = moment(tex, "strike", function(m, ag)
    m.lift = anim(ag, "Rotation", 2, 0.18, "OUT")
    m.lift:SetDegrees(48)
    m.lift:SetOrigin("BOTTOMRIGHT", 0, 0)
    m.hit = anim(ag, "Rotation", 3, 0.1, "IN")
    m.hit:SetDegrees(-60)
    m.hit:SetOrigin("BOTTOMRIGHT", 0, 0)
    m.back = anim(ag, "Rotation", 4, 0.12, "OUT")
    m.back:SetDegrees(12)
    m.back:SetOrigin("BOTTOMRIGHT", 0, 0)
  end)
  wait(m, m.ag, delay, 1)
  m.ag:Play()
end

-- Fades in, holds and fades out (a night's veil, a camera's flash, the red of a fall). The region has alpha 0 at rest.
function V.Flash(r, peak, up, hold, down, delay)
  local m = moment(r, "flash", function(m, ag)
    m.up = fade(anim(ag, "Alpha", 2, 0.1), 0, 1)
    m.hold = fade(anim(ag, "Alpha", 3, 0.1), 1, 1)
    m.down = fade(anim(ag, "Alpha", 4, 0.3), 1, 0)
  end)
  wait(m, m.ag, delay)
  m.up:SetToAlpha(peak or 1)
  m.up:SetDuration(up or 0.05)
  m.hold:SetFromAlpha(peak or 1)
  m.hold:SetToAlpha(peak or 1)
  m.hold:SetDuration(math.max(0.01, hold or 0))
  m.down:SetFromAlpha(peak or 1)
  m.down:SetDuration(down or 0.3)
  m.ag:Play()
end

-- Floats up and fades, over and over while shown (bubbles, notes). The region has alpha 0 at rest. V.Play(ag, false)
-- stops it.
function V.Float(r, rise, dur, delay)
  local m = moment(r, "float", function(m, ag)
    ag:SetLooping("REPEAT")
    m.up = anim(ag, "Translation", 2, 1.5)
    m.inn = fade(anim(ag, "Alpha", 2, 0.3), 0, 1)
    m.out = fade(anim(ag, "Alpha", 2, 0.5), 1, 0)
  end)
  wait(m, m.ag, delay)
  dur = dur or 1.5
  m.up:SetOffset(0, rise or 50)
  m.up:SetDuration(dur)
  m.inn:SetDuration(dur * 0.2)
  m.out:SetStartDelay(dur * 0.5)
  m.out:SetDuration(dur * 0.5)
  m.ag:Play()
  return m.ag
end

-- A ring growing out and fading (sound, a pulse), from delay, over and over while shown. Alpha 0 at rest.
function V.Ripple(r, to, dur, delay)
  local m = moment(r, "ripple", function(m, ag)
    ag:SetLooping("REPEAT")
    m.size = anim(ag, "Scale", 2, 1.2, "OUT")
    m.out = fade(anim(ag, "Alpha", 2, 1.2), 0.9, 0)
  end)
  wait(m, m.ag, delay)
  scale2(m.size, 1, 1, to or 2.4, to or 2.4)
  m.size:SetDuration(dur or 1.2)
  m.out:SetDuration(dur or 1.2)
  m.ag:Play()
  return m.ag
end

-- Sparks flying out from x, y on frame (a win, a splat, a clash), from delay. color: { r, g, b }. Each frame keeps a
-- ring of BITS sparks, so a few bursts in one moment each have their own.
V.BITS, V.BURST_MAX = 30, 12
function V.Burst(frame, x, y, color, n, delay)
  frame.bits = frame.bits or {}
  n = math.min(n or 8, V.BURST_MAX)
  local first = frame.bitAt or 0
  frame.bitAt = (first + n) % V.BITS
  for i = 1, n do
    local k = (first + i - 1) % V.BITS + 1
    local b = frame.bits[k]
    if not b then
      b = frame:CreateTexture(nil, "OVERLAY", nil, 7)
      b:SetTexture(ns.MEDIA .. "Dot")
      b:SetBlendMode("ADD")
      b:SetSize(5, 5)
      b:SetAlpha(0)
      frame.bits[k] = b
    end
    b:ClearAllPoints()
    b:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    local c = color or V.GOLD
    b:SetVertexColor(c[1], c[2], c[3])
    local m = moment(b, "burst", function(m, ag)
      m.out = anim(ag, "Translation", 2, 0.65, "OUT")
      m.fade = fade(anim(ag, "Alpha", 2, 0.65, "IN"), 1, 0)
      m.size = anim(ag, "Scale", 2, 0.65)
      scale2(m.size, 1, 1, 0.3, 0.3)
    end)
    wait(m, m.ag, delay)
    local a = (i / n) * math.pi * 2 + math.random() * 0.4
    local r = 16 + math.random() * 16
    m.out:SetOffset(math.cos(a) * r, math.sin(a) * r - 6)
    m.ag:Play()
  end
end

---------------------------------------------------------------------------
-- The Wheel of Punishment as a wheel (SPEC decision 60): the punishments' medallions round a hub, pegs between them,
-- and a gold pointer at the top. W:Rest(list, r) shows it standing on r; W:Spin(list, r, dur) turns it, fast then
-- slower, the pointer flicking over each peg, and stops with r under the pointer. The result is laid out under the
-- pointer first; the turn starts from a random angle and ends on whole turns, so the wheel never stops anywhere
-- else.
---------------------------------------------------------------------------
V.WHEEL_TURNS = 4
function V.Wheel(parent, size)
  local w = CreateFrame("Frame", nil, parent)
  w:SetSize(size, size)
  w.size = size
  w.disc = w:CreateTexture(nil, "BACKGROUND")
  w.disc:SetTexture(ns.MEDIA .. "Dot")
  w.disc:SetVertexColor(0.07, 0.06, 0.05, 0.92)
  w.disc:SetAllPoints()
  w.rim = w:CreateTexture(nil, "BORDER")
  w.rim:SetTexture(ns.MEDIA .. "Ring")
  w.rim:SetVertexColor(V.GOLD[1], V.GOLD[2], V.GOLD[3])
  w.rim:SetPoint("TOPLEFT", -3, 3)
  w.rim:SetPoint("BOTTOMRIGHT", 3, -3)
  w.hub = w:CreateTexture(nil, "OVERLAY")
  w.hub:SetTexture(ns.MEDIA .. UI.EMBLEM_SMALL)
  w.hub:SetSize(size * 0.24, size * 0.24)
  w.hub:SetPoint("CENTER")
  w.pointer = w:CreateTexture(nil, "OVERLAY", nil, 7)
  w.pointer:SetTexture(ns.MEDIA .. "Chevron")
  w.pointer:SetVertexColor(V.GOLD[1], V.GOLD[2], V.GOLD[3])
  w.pointer:SetSize(18, 18)
  w.pointer:SetPoint("BOTTOM", w, "TOP", 0, -8)
  w.items, w.pegs = {}, {}
  return w
end

-- Places the medallions with slice r at the top (index in list).
local function layWheel(w, list, r)
  local n = #list
  local R = w.size * 0.33
  for i = 1, math.max(n, #w.items) do
    local t, p = w.items[i], w.pegs[i]
    if i > n then
      if t then t:Hide() end
      if p then p:Hide() end
    else
      if not t then
        t = w:CreateTexture(nil, "ARTWORK")
        t:SetSize(w.size * 0.26, w.size * 0.26)
        w.items[i] = t
        p = w:CreateTexture(nil, "ARTWORK", nil, 1)
        p:SetTexture(ns.MEDIA .. "Dot")
        p:SetVertexColor(1, 0.88, 0.54)
        p:SetSize(6, 6)
        w.pegs[i] = p
      end
      UI.IconTex(t, UI.ICON["p_" .. list[i]] or UI.ICON.question)
      local a = (i - r) / n * 2 * math.pi
      t.dx, t.dy = math.sin(a) * R, math.cos(a) * R
      t:ClearAllPoints()
      t:SetPoint("CENTER", w, "CENTER", t.dx, t.dy)
      t:Show()
      local pa = a + math.pi / n
      p.dx, p.dy = math.sin(pa) * (w.size * 0.47), math.cos(pa) * (w.size * 0.47)
      p:ClearAllPoints()
      p:SetPoint("CENTER", w, "CENTER", p.dx, p.dy)
      p:Show()
    end
  end
end

function V.WheelRest(w, list, r)
  layWheel(w, list, r)
  for _, t in ipairs(w.items) do if t.turn then t.turn.ag:Stop() end end
  for _, t in ipairs(w.pegs) do if t.turn then t.turn.ag:Stop() end end
end

-- Turns the wheel for dur seconds and lands on r. WoW's "OUT" smoothing slows as 1 - (1 - t)^2.
function V.WheelSpin(w, list, r, dur)
  layWheel(w, list, r)
  dur = dur or 3.2
  local n = #list
  local start = math.random(1, 2 * n - 1) * 180 / n + 7
  local total = V.WHEEL_TURNS * 360 + start
  local function turn(t)
    local m = moment(t, "wheel", function(m, ag)
      m.from = anim(ag, "Rotation", 1, 0.01)
      m.go = anim(ag, "Rotation", 2, 3.2, "OUT")
    end)
    -- Around the wheel's centre: the origin is the centre, as an offset from the texture's own centre.
    m.from:SetOrigin("CENTER", -t.dx, -t.dy)
    m.go:SetOrigin("CENTER", -t.dx, -t.dy)
    m.from:SetDegrees(start)
    m.go:SetDegrees(-total)
    m.go:SetDuration(dur)
    m.ag:Play()
    t.turn = m
  end
  for i = 1, n do
    turn(w.items[i])
    turn(w.pegs[i])
  end
  -- The pointer flicks each time a peg passes under it.
  local p = w.pointer
  p.flicks = p.flicks or {}
  local k = 0
  for passed = 180 / n, total, 360 / n do
    local at = 1 - math.sqrt(math.max(0, 1 - passed / total))
    k = k + 1
    local m = p.flicks[k]
    if not m then
      m = { ag = p:CreateAnimationGroup() }
      m.kick = anim(m.ag, "Rotation", 1, 0.05, "OUT")
      m.kick:SetDegrees(22)
      m.kick:SetOrigin("TOP", 0, 0)
      m.back = anim(m.ag, "Rotation", 2, 0.08, "IN")
      m.back:SetDegrees(-22)
      m.back:SetOrigin("TOP", 0, 0)
      p.flicks[k] = m
    end
    m.ag:Stop()
    m.kick:SetStartDelay(at * dur)
    m.ag:Play()
  end
  for i = k + 1, #p.flicks do p.flicks[i].ag:Stop() end
end

-- A texture in one colour (a bar, a line, a dot).
local function solid(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  t:SetTexture(V.TEX.white)
  return t
end
local function paint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end

-- A one-line text that ends in "..." when too long.
local function line(parent, font, width, justify)
  local t = UI.Text(parent, font or "GameFontHighlightSmall", justify)
  t:SetWordWrap(false)
  if width then t:SetWidth(width) end
  return t
end

-- A tooltip that reads frame.tipTitle and frame.tipText when it shows.
local function tip(frame)
  frame:EnableMouse(true)
  UI.Tooltip(frame, function() return frame.tipTitle or "" end, function() return frame.tipText end)
  -- A player's: right-click opens their card (SPEC decision 75).
  frame:HookScript("OnMouseUp", function(self, button)
    if button == "RightButton" and self.tipPlayer and ns.Card then ns.Card:Show(self.tipPlayer) end
  end)
end

-- Grows (or shrinks) a texture's width to w over a moment.
local function grow(t, w)
  w = math.max(1, w)
  local from = t.cur or 1
  t.cur = w
  local holder = t.holder
  if not holder or not holder.SetScript or math.abs(from - w) < 1 then t:SetWidth(w) return end
  local at = from
  t:SetWidth(at)
  holder:SetScript("OnUpdate", function(self, elapsed)
    at = at + (w - at) * math.min(1, elapsed * 7)
    if math.abs(w - at) < 0.5 then at = w; self:SetScript("OnUpdate", nil) end
    t:SetWidth(at)
  end)
end

local function box(f, key, height, kind)
  local b = f:piece(key, function()
    local frame = CreateFrame("Frame", nil, f.card)
    frame.short = true
    return frame
  end, "box:" .. kind)
  b:SetSize(f.width, height)
  b:SetPoint("TOPLEFT", f.pad, f.y)
  f.y = f.y - height - UI.FLOW_GAP
  return b
end

local function short(name)
  if name == false then return L.VI_BYE end
  if type(name) ~= "string" then return "?" end
  local class = ns.Roster:Class(name)
  local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  local s = ns.Short(name)
  if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(s) end
  return s
end
V.Short = short

---------------------------------------------------------------------------
-- The gnome run: a lane per runner along the checkpoints. A runner hops while running, sparkles at the finish and
-- is a shaking skull where they fell.
--   f:Track(key, stops, runners): runners = { { name, at (checkpoints reached), done, dead, me } }
---------------------------------------------------------------------------
V.LANE_H, V.LANES = 20, 8
local function newLane(parent)
  local l = CreateFrame("Frame", nil, parent)
  l.name = line(l, "GameFontHighlightSmall", 60)
  l.name:SetPoint("LEFT", 2, 0)
  l.track = solid(l, "BORDER")
  l.dots = {}
  l.runner = l:CreateTexture(nil, "OVERLAY")
  l.runner:SetSize(16, 16)
  l.runner:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  l.hop = V.Bounce(l.runner, 3)
  l.shake = V.Shake(l.runner)
  l.spark = V.Sparkle(l, 26)
  l.value = line(l, "GameFontHighlightSmall", 30, "RIGHT")
  l.value:SetPoint("RIGHT", -2, 0)
  l.check = l:CreateTexture(nil, "OVERLAY")
  l.check:SetTexture(V.TEX.check)
  l.check:SetSize(14, 14)
  l.check:SetPoint("RIGHT", -8, 0)
  tip(l)
  return l
end

function Flow:Track(key, stops, runners)
  local n = math.min(#runners, V.LANES)
  local b = box(self, key, n * V.LANE_H + 2, "track")
  b.lanes = b.lanes or {}
  local x0, x1 = 68, self.width - 40
  stops = math.max(1, stops)
  for i = 1, math.max(n, #b.lanes) do
    local l = b.lanes[i]
    if i > n then
      if l then l:Hide() end
    else
      if not l then l = newLane(b); b.lanes[i] = l end
      local r = runners[i]
      l:Show()
      l:SetPoint("TOPLEFT", 0, -(i - 1) * V.LANE_H)
      l:SetSize(self.width, V.LANE_H)
      l.name:SetText(short(r.name))
      if r.me then l.name:SetFontObject("GameFontNormalSmall") else l.name:SetFontObject("GameFontHighlightSmall") end
      l.track:SetPoint("LEFT", x0, 0)
      l.track:SetSize(x1 - x0, 2)
      paint(l.track, { 0, 0, 0 }, 0.55)
      for j = 0, stops do
        local d = l.dots[j]
        if not d then d = solid(l, "ARTWORK"); l.dots[j] = d end
        d:Show()
        local size = j == stops and 9 or 6
        d:SetSize(size, size)
        d:SetPoint("CENTER", l, "LEFT", x0 + (x1 - x0) * j / stops, 0)
        if j <= (r.at or 0) then paint(d, V.GOLD)
        elseif j == stops then paint(d, { 0.9, 0.9, 0.9 })
        else paint(d, { 0.15, 0.15, 0.15 }) end
      end
      for j = stops + 1, #l.dots do l.dots[j]:Hide() end
      local x = x0 + (x1 - x0) * math.min(r.at or 0, stops) / stops
      l.runner:ClearAllPoints()
      l.runner:SetPoint("CENTER", l, "LEFT", x, 2)
      UI.IconTex(l.runner, r.dead and UI.ICON.bones or UI.ICON.gnomes)
      V.Play(l.hop, not r.dead and not r.done)
      V.Play(l.shake, r.dead ~= nil and r.dead ~= false)
      l.spark:ClearAllPoints()
      l.spark:SetPoint("CENTER", l.runner, "CENTER")
      spark(l.spark, r.done == true)
      l.check:SetShown(r.done == true)
      l.value:SetShown(not r.done)
      l.value:SetText(("%d/%d"):format(r.at or 0, stops))
      if r.dead then l.value:SetTextColor(1, 0.35, 0.3) else l.value:SetTextColor(1, 1, 1) end
      l.tipTitle, l.tipText, l.tipPlayer = ns.Display(r.name), r.tip, r.name
    end
  end
  return b
end

---------------------------------------------------------------------------
-- A leaderboard: a bar per player, the longest the leader's, gold, with a sparkle and its icon hopping at the end.
-- A bar grows when its number does.
--   f:Bars(key, list, icon): list = { { name, v, text, me, label } } in the order shown (label: shown instead of a
--   name, as a vote's choice)
---------------------------------------------------------------------------
V.BAR_H, V.BARS = 18, 8
local function newBar(parent)
  local r = CreateFrame("Frame", nil, parent)
  r.name = line(r, "GameFontHighlightSmall", 74)
  r.name:SetPoint("LEFT", 2, 0)
  r.bg = solid(r, "BORDER")
  r.fill = r:CreateTexture(nil, "ARTWORK")
  r.fill:SetTexture(UI.TEX.bar[1])
  r.fill.holder = r
  r.value = line(r, "GameFontHighlightSmall", 60, "RIGHT")
  r.value:SetPoint("RIGHT", -2, 0)
  r.icon = r:CreateTexture(nil, "OVERLAY")
  r.icon:SetSize(16, 16)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.icon:SetPoint("CENTER", r.fill, "RIGHT", 0, 1)
  r.hop = V.Bounce(r.icon, 3)
  r.spark = V.Sparkle(r, 24)
  r.spark:SetPoint("CENTER", r.fill, "RIGHT")
  tip(r)
  return r
end

function Flow:Bars(key, list, icon)
  local n = math.min(#list, V.BARS)
  local b = box(self, key, n * V.BAR_H + 2, "bars")
  b.rows = b.rows or {}
  local max, tops = 0, 0
  for i = 1, n do max = math.max(max, list[i].v or 0) end
  for i = 1, n do if (list[i].v or 0) == max then tops = tops + 1 end end
  local x0, x1 = 80, self.width - 66
  for i = 1, math.max(n, #b.rows) do
    local r = b.rows[i]
    if i > n then
      if r then r:Hide() end
    else
      if not r then r = newBar(b); b.rows[i] = r end
      local e = list[i]
      r:Show()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * V.BAR_H)
      r:SetSize(self.width, V.BAR_H)
      r.name:SetText(e.label or short(e.name))
      if e.me then r.name:SetFontObject("GameFontNormalSmall") else r.name:SetFontObject("GameFontHighlightSmall") end
      r.bg:SetPoint("LEFT", x0, 0)
      r.bg:SetSize(x1 - x0, 10)
      paint(r.bg, { 0, 0, 0 }, 0.6)
      r.fill:SetPoint("LEFT", x0, 0)
      r.fill:SetHeight(10)
      -- The leader: the one highest number (a tie has none).
      local lead = max > 0 and tops == 1 and (e.v or 0) == max
      paint(r.fill, lead and V.GOLD or (e.me and V.GREEN or V.BLUE))
      grow(r.fill, max > 0 and (x1 - x0) * (e.v or 0) / max or 1)
      r.value:SetText(e.text or tostring(e.v or 0))
      r.icon:SetShown(icon ~= nil and (e.v or 0) > 0)
      if icon then UI.IconTex(r.icon, icon) end
      V.Play(r.hop, lead and icon ~= nil)
      spark(r.spark, lead)
      r.tipTitle, r.tipText = e.label or ns.Display(e.name), e.text
      r.tipPlayer = e.name or UI.whoOf[e.label or ""]
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The Traitors' board: a tile per player. Out: murdered (dark red, a skull; the latest one shakes) or banished (dim,
-- the border shows what they were: red a traitor, green a faithful). Your own tile has a gold border.
--   f:Tiles(key, list, cols): list = { { name, out = "murdered"|"banished"|nil, role, sub, me, fresh } }
---------------------------------------------------------------------------
V.TILE_H = 32
local function newTile(parent)
  local t = UI.Create("Frame", parent, "BackdropTemplate")
  if t.SetBackdrop then
    t:SetBackdrop({ bgFile = V.TEX.white, edgeFile = V.TEX.white, edgeSize = 1 })
  end
  t.name = line(t, "GameFontHighlightSmall")
  t.name:SetPoint("TOPLEFT", 4, -4)
  t.name:SetPoint("TOPRIGHT", -4, -4)
  t.name:SetJustifyH("CENTER")
  t.sub = line(t, "GameFontDisableSmall")
  t.sub:SetPoint("BOTTOMLEFT", 3, 3)
  t.sub:SetPoint("BOTTOMRIGHT", -3, 3)
  t.sub:SetJustifyH("CENTER")
  t.skull = t:CreateTexture(nil, "OVERLAY")
  UI.IconTex(t.skull, UI.ICON.bones)
  t.skull:SetSize(18, 18)
  t.skull:SetPoint("CENTER", t, "TOPRIGHT", -4, -4)
  t.shake = V.Shake(t.skull)
  tip(t)
  return t
end

function Flow:Tiles(key, list, cols)
  cols = cols or 3
  local gap = 4
  local rows = math.ceil(#list / cols)
  local b = box(self, key, rows * (V.TILE_H + gap) - gap + 2, "tiles")
  b.tiles = b.tiles or {}
  local w = math.floor((self.width - gap * (cols - 1)) / cols)
  for i = 1, math.max(#list, #b.tiles) do
    local t = b.tiles[i]
    if i > #list then
      if t then t:Hide() end
    else
      if not t then t = newTile(b); b.tiles[i] = t end
      local e = list[i]
      t:Show()
      t:SetSize(w, V.TILE_H)
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      t:SetPoint("TOPLEFT", col * (w + gap), -row * (V.TILE_H + gap))
      t.name:SetText(short(e.name))
      UI.Ink(t.sub):SetText(e.sub or "")
      local bg, edge, alpha = { 0.1, 0.11, 0.14 }, { 0.3, 0.3, 0.33 }, 1
      if e.out == "murdered" then bg, edge = { 0.29, 0.07, 0.05 }, { 0.5, 0.12, 0.1 }
      elseif e.out == "banished" then
        bg, edge, alpha = { 0.06, 0.06, 0.07 }, e.role == "traitor" and { 0.9, 0.2, 0.15 } or { 0.2, 0.7, 0.25 }, 0.75
      end
      if e.me then edge = V.GOLD end
      if e.dim then alpha = 0.45 end
      if t.SetBackdropColor then
        t:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        t:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
      end
      t:SetAlpha(alpha)
      if e.out then t.name:SetTextColor(0.6, 0.6, 0.6) else t.name:SetTextColor(1, 1, 1) end
      t.skull:SetShown(e.out == "murdered")
      V.Play(t.shake, e.out == "murdered" and e.fresh == true)
      t.tipTitle, t.tipText, t.tipPlayer = ns.Display(e.name), e.tip or e.sub, e.name
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The records as a trophy wall (SPEC decision 75): a plaque each, its medallion at the top, the record in small gold
-- letters, the holder in their class colour, the value, and since when (yours with a gold edge).
--   f:Plaques(key, list, cols): list = { { icon, label, name = "Name-Realm", value, sub, me } }
---------------------------------------------------------------------------
V.PLAQUE_H = 96
local function newPlaque(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.fill, p.edge = UI.Glass(p, { 0.13, 0.09, 0.05, 0.95 })
  p.icon, p.ring = UI.Medallion(p, 30)
  p.icon:SetPoint("TOP", 0, -6)
  p.label = UI.Color(line(p, "GameFontNormalSmall", nil, "CENTER"), "gold")
  p.label:SetPoint("TOPLEFT", 4, -40)
  p.label:SetPoint("TOPRIGHT", -4, -40)
  p.name = line(p, "GameFontHighlight", nil, "CENTER")
  p.name:SetPoint("TOPLEFT", p.label, "BOTTOMLEFT", 0, -3)
  p.name:SetPoint("TOPRIGHT", p.label, "BOTTOMRIGHT", 0, -3)
  p.value = UI.Color(line(p, "GameFontHighlightSmall", nil, "CENTER"), "goldHi")
  p.value:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -2)
  p.value:SetPoint("TOPRIGHT", p.name, "BOTTOMRIGHT", 0, -2)
  p.sub = line(p, "GameFontDisableSmall", nil, "CENTER")
  p.sub:SetPoint("BOTTOMLEFT", 3, 4)
  p.sub:SetPoint("BOTTOMRIGHT", -3, 4)
  tip(p)
  return p
end

function Flow:Plaques(key, list, cols)
  cols = cols or 2
  local gap = 6
  local rows = math.ceil(#list / cols)
  local b = box(self, key, rows * (V.PLAQUE_H + gap) - gap + 2, "plaques")
  b.plaques = b.plaques or {}
  local w = math.floor((self.width - gap * (cols - 1)) / cols)
  for i = 1, math.max(#list, #b.plaques) do
    local p = b.plaques[i]
    if i > #list then
      if p then p:Hide() end
    else
      if not p then p = newPlaque(b); b.plaques[i] = p end
      local e = list[i]
      p:Show()
      p:SetSize(w, V.PLAQUE_H)
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", col * (w + gap), -row * (V.PLAQUE_H + gap))
      UI.SetIcon(p.icon, p.ring, e.icon or UI.ICON.laurel, 30)
      p.label:SetText(e.label or "")
      p.name:SetText(UI.Who(e.name))
      p.value:SetText(e.value or "")
      p.sub:SetText(e.sub or "")
      local g = UI.LOOK.gold
      p.edge:SetVertexColor(g[1], g[2], g[3], e.me and 1 or 0.45)
      p.tipTitle, p.tipText, p.tipPlayer = e.label, e.value, e.name
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The scavenger hunt: the clues as a trail of stops. A found clue shows who found it (yours sparkle); the first one
-- nobody has found pulses.
--   f:Trail(key, list): list = { { found = "Name-Realm" or nil, mine, text } }
---------------------------------------------------------------------------
V.STOP, V.STOPS_ROW = 28, 6
local function newStop(parent)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(V.STOP, V.STOP)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetAllPoints()
  s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  s.pulse = V.Pulse(s.icon, 1.18)
  s.check = s:CreateTexture(nil, "OVERLAY")
  s.check:SetTexture(V.TEX.check)
  s.check:SetSize(14, 14)
  s.check:SetPoint("BOTTOMRIGHT", 4, -4)
  s.n = UI.Text(s, "NumberFontNormalSmall", "LEFT")
  s.n:SetPoint("TOPLEFT", 1, -1)
  s.who = line(s, "GameFontHighlightSmall", 46, "CENTER")
  s.who:SetPoint("TOP", s, "BOTTOM", 0, -2)
  s.spark = V.Sparkle(s, 30)
  s.spark:SetPoint("CENTER")
  tip(s)
  return s
end

function Flow:Trail(key, list)
  local per = math.min(#list, V.STOPS_ROW)
  local rows = math.ceil(#list / math.max(1, per))
  local rowH = V.STOP + 20
  local b = box(self, key, rows * rowH, "trail")
  b.stops, b.links = b.stops or {}, b.links or {}
  local step = per > 1 and math.floor((self.width - 24 - V.STOP) / (per - 1)) or 0
  local nextUp
  for i, e in ipairs(list) do if not e.found and not nextUp then nextUp = i end end
  for i = 1, math.max(#list, #b.stops) do
    local s, link = b.stops[i], b.links[i]
    if i > #list then
      if s then s:Hide() end
      if link then link:Hide() end
    else
      if not s then s = newStop(b); b.stops[i] = s end
      if not link then link = solid(b, "BORDER"); b.links[i] = link end
      local e = list[i]
      local col, row = (i - 1) % per, math.floor((i - 1) / per)
      local x, y = 12 + col * step, -row * rowH
      s:Show()
      s:SetPoint("TOPLEFT", x, y)
      UI.IconTex(s.icon, e.found and UI.ICON.hunt or UI.ICON.question)
      s.icon:SetDesaturated(not e.found)
      s.icon:SetAlpha(e.found and 1 or 0.8)
      s.check:SetShown(e.found ~= nil)
      s.n:SetText(i)
      s.who:SetText(e.found and short(e.found) or "")
      if e.mine then s.who:SetFontObject("GameFontNormalSmall") else s.who:SetFontObject("GameFontHighlightSmall") end
      V.Play(s.pulse, i == nextUp)
      spark(s.spark, e.mine == true)
      s.tipTitle = L.GM_CLUE:format(i, e.text or "")
      s.tipText = e.found and L.GM_FOUND_BY:format(ns.Display(e.found)) or L.GM_NOT_FOUND
      -- The path to the next stop on the same row.
      local nxt = list[i + 1] and (i % per ~= 0)
      link:SetShown(nxt and true or false)
      if nxt then
        link:ClearAllPoints()
        link:SetPoint("LEFT", b, "TOPLEFT", x + V.STOP + 2, y - V.STOP / 2)
        link:SetSize(math.max(1, step - V.STOP - 4), 3)
        paint(link, e.found and list[i + 1].found and V.GOLD or { 0.1, 0.08, 0.05 }, e.found and 1 or 0.6)
      end
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The cup's bracket: a column per round under its name (Final, Semi-finals, ...), each match a box with the players'
-- class icons (the winner in gold, a match being played pulses), lines to the next round (gold where a winner went
-- on: the second check of 1 November), and the champion's crown. At most the last four rounds.
--   f:Bracket(key, matches, champion): matches = { { col, a, b, w, wa, wb, live, mine, label } } of one knockout
---------------------------------------------------------------------------
V.MATCH_H, V.COLS, V.ROUND_H, V.SIDE_ICON = 30, 4, 14, 12
local function newMatch(parent)
  local m = UI.Create("Frame", parent, "BackdropTemplate")
  if m.SetBackdrop then
    m:SetBackdrop({ bgFile = V.TEX.white, edgeFile = V.TEX.white, edgeSize = 1 })
  end
  -- Its own dark fill, and a glow while the match is live, sized with the box (Flow:Bracket) and breathing in alpha
  -- (a growing pulse on it once covered the whole pane in the game).
  m.bg = solid(m, "BACKGROUND", -8)
  m.bg:SetAllPoints()
  paint(m.bg, { 0.08, 0.08, 0.1 }, 1)
  m.glow = solid(m, "BACKGROUND", -7)
  m.glow:SetPoint("CENTER")
  m.glow:SetBlendMode("ADD")
  m.glowing = V.Breathe(m.glow)
  m.ia = m:CreateTexture(nil, "ARTWORK")
  m.ia:SetSize(V.SIDE_ICON, V.SIDE_ICON)
  m.ia:SetPoint("TOPLEFT", 2, -2)
  m.ib = m:CreateTexture(nil, "ARTWORK")
  m.ib:SetSize(V.SIDE_ICON, V.SIDE_ICON)
  m.ib:SetPoint("BOTTOMLEFT", 2, 2)
  m.a = line(m, "GameFontHighlightSmall")
  m.a:SetPoint("TOPLEFT", V.SIDE_ICON + 4, -2)
  m.b = line(m, "GameFontHighlightSmall")
  m.b:SetPoint("BOTTOMLEFT", V.SIDE_ICON + 4, 2)
  m.wa = line(m, "GameFontHighlightSmall", 12, "RIGHT")
  m.wa:SetPoint("TOPRIGHT", -2, -2)
  m.wb = line(m, "GameFontHighlightSmall", 12, "RIGHT")
  m.wb:SetPoint("BOTTOMRIGHT", -2, 2)
  tip(m)
  return m
end

-- A decided match's names lose their class colour: gold and grey say who went on.
local function sideText(t, name, w)
  local decided = w ~= nil and type(name) == "string"
  t:SetText(decided and ns.Short(name) or short(name))
  if not decided then t:SetTextColor(1, 1, 1)
  elseif w == name then t:SetTextColor(V.GOLD[1], V.GOLD[2], V.GOLD[3])
  else t:SetTextColor(0.5, 0.5, 0.5) end
end
local function whole(name) return type(name) == "string" and ns.Display(name) or short(name) end

-- A player's class icon beside their name; none while the place waits for a winner.
local function sideIcon(t, name, w)
  t:SetShown(type(name) == "string")
  if type(name) ~= "string" then return end
  ns.UI.PlayerIcon(t, name)
  t:SetAlpha((w ~= nil and w ~= name) and 0.45 or 1)
end

-- A round's name, counted back from the last: Final, Semi-finals, Quarter-finals, else Round n.
function V.RoundName(col, last)
  local back = last - col
  if back == 0 then return L.BR_FINAL elseif back == 1 then return L.BR_SEMI elseif back == 2 then return L.BR_QUARTER end
  return L.BR_ROUND:format(col)
end

function Flow:Bracket(key, matches, champion)
  local last = 0
  for _, m in ipairs(matches) do last = math.max(last, m.col) end
  local first = math.max(1, last - V.COLS + 1)
  local byCol = {}
  for _, m in ipairs(matches) do
    if m.col >= first then
      byCol[m.col] = byCol[m.col] or {}
      local list = byCol[m.col]
      list[#list + 1] = m
    end
  end
  local cols, gap, vgap = last - first + 1, 10, 6
  local w = math.floor((self.width - gap * (cols - 1)) / math.max(1, cols))
  local count = byCol[first] and #byCol[first] or 0
  local b = box(self, key, math.max(V.MATCH_H, count * (V.MATCH_H + vgap) - vgap) + 4 + V.ROUND_H, "bracket")
  b.boxes, b.lines, b.heads = b.boxes or {}, b.lines or {}, b.heads or {}
  for c = first, last do
    local i = c - first + 1
    local h = b.heads[i]
    if not h then
      h = UI.Color(UI.Text(b, "GameFontNormalSmall", "CENTER"), "gold")
      b.heads[i] = h
    end
    h:Show()
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", (c - first) * (w + gap), 0)
    h:SetWidth(w)
    h:SetText(V.RoundName(c, last))
  end
  for i = cols + 1, #b.heads do b.heads[i]:Hide() end
  if not b.crown then
    b.crown = b:CreateTexture(nil, "OVERLAY")
    UI.IconTex(b.crown, UI.ICON.crown)
    b.crown:SetSize(18, 18)
    b.crown.hop = V.Bounce(b.crown, 3)
    b.crownSpark = V.Sparkle(b, 30)
    b.crownSpark:SetPoint("CENTER", b.crown)
  end
  -- Where each box goes: the first column one under another, each later box between the two it comes from.
  local ys, used, nl = {}, 0, 0
  for c = first, last do
    ys[c] = {}
    for j, _ in ipairs(byCol[c] or {}) do
      local prev = ys[c - 1]
      if c > first and prev and prev[2 * j - 1] and prev[2 * j] then ys[c][j] = (prev[2 * j - 1] + prev[2 * j]) / 2
      else ys[c][j] = V.ROUND_H + (j - 1) * (V.MATCH_H + vgap) end
    end
  end
  local function lineAt(x, y, lw, lh, won)
    nl = nl + 1
    local t = b.lines[nl]
    if not t then t = solid(b, "BORDER"); b.lines[nl] = t end
    t:Show()
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", x, y)
    t:SetSize(math.max(1, lw), math.max(1, lh) + (won and 1 or 0))
    if won then paint(t, V.GOLD, 1) else paint(t, { 0.62, 0.5, 0.3 }, 0.9) end
  end
  local final
  for c = first, last do
    local x = (c - first) * (w + gap)
    for j, m in ipairs(byCol[c] or {}) do
      used = used + 1
      local mb = b.boxes[used]
      if not mb then mb = newMatch(b); b.boxes[used] = mb end
      local y = -ys[c][j]
      mb:Show()
      mb:SetSize(w, V.MATCH_H)
      mb:SetPoint("TOPLEFT", x, y)
      mb.glow:SetSize(w + 4, V.MATCH_H + 4)
      mb.a:SetWidth(w - 18)
      mb.b:SetWidth(w - 18)
      sideText(mb.a, m.a, m.w)
      sideText(mb.b, m.b, m.w)
      sideIcon(mb.ia, m.a, m.w)
      sideIcon(mb.ib, m.b, m.w)
      -- A winner who just came into this box slides in from the round before (SPEC decision 60).
      for _, side in ipairs({ "a", "b" }) do
        local name = m[side]
        local was = mb["was" .. side]
        if c > first and type(name) == "string" and was ~= nil and was ~= name and UI.Motion() then
          V.Glide(mb[side], -(gap + 24), 0, 0.4, 0, true)
        end
        mb["was" .. side] = name or false
      end
      mb.wa:SetText((m.wa or 0) > 0 and m.wa or "")
      mb.wb:SetText((m.wb or 0) > 0 and m.wb or "")
      local edge = m.mine and { 0.4, 0.7, 1 } or (m.live and V.GOLD or { 0.3, 0.3, 0.33 })
      if mb.SetBackdropColor then
        mb:SetBackdropColor(0.08, 0.08, 0.1, 1)
        mb:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
      end
      mb.glow:SetShown(m.live == true)
      paint(mb.glow, V.GOLD, 0.25)
      V.Play(mb.glowing, m.live == true)
      mb.tipTitle = m.label
      mb.tipText = L.AR_VS:format(whole(m.a), whole(m.b))
      -- Lines from the two boxes before it.
      local prev = ys[c - 1]
      if c > first and prev and prev[2 * j] then
        local px = x - gap
        local y1, y2 = -prev[2 * j - 1] - V.MATCH_H / 2, -prev[2 * j] - V.MATCH_H / 2
        local before = byCol[c - 1] or {}
        local wonA = before[2 * j - 1] and type(before[2 * j - 1].w) == "string"
        local wonB = before[2 * j] and type(before[2 * j].w) == "string"
        lineAt(px, y1, gap / 2, 1, wonA)
        lineAt(px, y2, gap / 2, 1, wonB)
        lineAt(px + gap / 2, y1, 1, y1 - y2 + 1)
        lineAt(px + gap / 2, y - V.MATCH_H / 2, gap / 2, 1, wonA and wonB)
      end
      if c == last then final = mb end
    end
  end
  for i = used + 1, #b.boxes do b.boxes[i]:Hide() end
  for i = nl + 1, #b.lines do b.lines[i]:Hide() end
  local crowned = champion ~= nil and final ~= nil
  b.crown:SetShown(crowned)
  if crowned then
    b.crown:ClearAllPoints()
    -- (At the final's right end: its round's name is over the middle.)
    b.crown:SetPoint("BOTTOMRIGHT", final, "TOPRIGHT", -2, 1)
  end
  V.Play(b.crown.hop, crowned)
  spark(b.crownSpark, crowned)
  return b
end

-- A cup's bracket (Guild/Cup.lua): its knockout (a double knockout's winners' side, the groups' knockout), with your
-- own matches in blue. Nil when the cup has no knockout (a round robin) or has not started.
function Flow:Cup(key, c, me)
  local B, wins = ns.Cup.Build(c)
  if not B then return nil end
  local live = {}
  for _, m in ipairs(ns.Cup.Live(B)) do live[m.key] = true end
  local list = {}
  for _, m in ipairs(B.matches) do
    if m.stage == "wb" or m.stage == "ko" then
      local w = wins and wins[m.key] or {}
      list[#list + 1] = { col = m.col, a = m.a, b = m.b, w = m.w, label = m.label, live = live[m.key] == true,
        wa = type(m.a) == "string" and w[m.a] or 0, wb = type(m.b) == "string" and w[m.b] or 0,
        mine = me ~= nil and (m.a == me or m.b == me) }
    end
  end
  if #list == 0 then return nil end
  return self:Bracket(key, list, B.champion)
end

---------------------------------------------------------------------------
-- A process's steps as a tracker, as the game's quest objectives (the Council's leadership: Challenge, Vote, Duel,
-- Hand-over): a small medallion each, the current one lit in gold, those done dimmed with a tick, those to come grey,
-- joined by a line.
--   f:Steps(key, list): list = { { label, icon (a UI.ICON name), state = "done" | "now" | "next" } }
---------------------------------------------------------------------------
V.STEPS_ICON = 24
local function newStepItem(b)
  local it = CreateFrame("Frame", nil, b)
  it.glow = it:CreateTexture(nil, "BACKGROUND")
  it.glow:SetTexture(ns.MEDIA .. "Glow")
  it.glow:SetBlendMode("ADD")
  it.glow:SetSize(V.STEPS_ICON * 2.2, V.STEPS_ICON * 2.2)
  it.icon, it.ring = UI.Medallion(it, V.STEPS_ICON)
  it.icon:SetPoint("TOP", 0, -2)
  it.glow:SetPoint("CENTER", it.icon)
  it.tick = it:CreateTexture(nil, "OVERLAY", nil, 2)
  it.tick:SetTexture(V.TEX.check)
  it.tick:SetSize(12, 12)
  it.tick:SetPoint("BOTTOMRIGHT", it.icon, "BOTTOMRIGHT", 4, -3)
  it.label = UI.Text(it, "GameFontHighlightSmall", "CENTER")
  it.label:SetPoint("TOP", it.icon, "BOTTOM", 0, -3)
  it.label:SetPoint("LEFT", 1, 0)
  it.label:SetPoint("RIGHT", -1, 0)
  it.label:SetWordWrap(false)
  it.line = solid(b, "BORDER")
  return it
end

function Flow:Steps(key, list)
  local n = #list
  local b = box(self, key, V.STEPS_ICON + 22, "steps")
  b.items = b.items or {}
  local w = math.floor(self.width / math.max(1, n))
  for i = 1, math.max(n, #b.items) do
    local it = b.items[i]
    if i > n then
      if it then it:Hide(); it.line:Hide() end
    else
      if not it then it = newStepItem(b); b.items[i] = it end
      local e = list[i]
      it:Show()
      it:SetSize(w, V.STEPS_ICON + 20)
      it:ClearAllPoints()
      it:SetPoint("TOPLEFT", (i - 1) * w, 0)
      UI.SetIcon(it.icon, it.ring, UI.ICON[e.icon] or UI.ICON.question, V.STEPS_ICON)
      if it.icon.SetDesaturated then it.icon:SetDesaturated(e.state == "next") end
      it.icon:SetAlpha(e.state == "now" and 1 or 0.55)
      it.ring:SetAlpha(e.state == "next" and 0.5 or 1)
      it.tick:SetShown(e.state == "done")
      it.glow:SetShown(e.state == "now")
      paint(it.glow, V.GOLD, 0.55)
      it.label:SetText(e.label or "")
      if e.state == "now" then UI.Color(it.label, "goldHi")
      elseif e.state == "done" then UI.Color(it.label, "sub")
      else it.label:SetTextColor(0.45, 0.45, 0.48) end
      it.tipTitle = e.label
      if i > 1 then
        local prev = b.items[i - 1]
        it.line:Show()
        it.line:ClearAllPoints()
        it.line:SetPoint("LEFT", prev.icon, "RIGHT", 5, 0)
        it.line:SetPoint("RIGHT", it.icon, "LEFT", -5, 0)
        it.line:SetHeight(1)
        paint(it.line, e.state == "next" and { 0.35, 0.35, 0.38 } or V.GOLD, 0.7)
      else
        it.line:Hide()
      end
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The deathroll as a ladder going down: a step per roll, as long as its number (on a log scale from the start), the
-- newest growing in; the roll of 1 is red with a shaking skull.
--   f:Ladder(key, start, rolls): rolls = { { v, who, mine } }
---------------------------------------------------------------------------
V.STEP_H = 17
local function newStep(parent)
  local s = CreateFrame("Frame", nil, parent)
  s.who = line(s, "GameFontHighlightSmall", 52)
  s.who:SetPoint("LEFT", 2, 0)
  s.bar = s:CreateTexture(nil, "ARTWORK")
  s.bar:SetTexture(UI.TEX.bar[1])
  s.bar.holder = s
  s.v = UI.Text(s, "GameFontHighlightSmall", "RIGHT")
  s.v:SetPoint("RIGHT", s.bar, "RIGHT", -3, 0)
  s.skull = s:CreateTexture(nil, "OVERLAY")
  UI.IconTex(s.skull, UI.ICON.skull)
  s.skull:SetSize(18, 18)
  s.skull:SetPoint("LEFT", s.bar, "RIGHT", 4, 0)
  s.shake = V.Shake(s.skull)
  return s
end

function Flow:Ladder(key, start, rolls)
  local steps = { { v = start, who = L.DR_START_CHIP, start = true } }
  for _, r in ipairs(rolls) do steps[#steps + 1] = r end
  local b = box(self, key, #steps * V.STEP_H + 2, "ladder")
  b.steps = b.steps or {}
  local x0, room = 58, self.width - 58 - 26
  local top = math.log(math.max(2, start))
  for i = 1, math.max(#steps, #b.steps) do
    local s = b.steps[i]
    if i > #steps then
      if s then s:Hide() end
    else
      if not s then s = newStep(b); b.steps[i] = s end
      local e = steps[i]
      s:Show()
      s:SetPoint("TOPLEFT", 0, -(i - 1) * V.STEP_H)
      s:SetSize(self.width, V.STEP_H - 2)
      UI.Ink(s.who):SetText(e.who or "")
      if e.mine then s.who:SetTextColor(0.55, 0.75, 1) end
      s.bar:SetPoint("LEFT", x0, 0)
      s.bar:SetHeight(V.STEP_H - 3)
      local dead = e.v == 1
      paint(s.bar, dead and V.RED or (e.start and V.GREY or (e.mine and V.BLUE or V.ORANGE)))
      -- Only the newest step grows in (the others stand as they were).
      local width = math.max(26, room * math.log(math.max(1, e.v)) / top)
      if i == #steps and i > 1 then
        s.bar.cur = s.bar.cur or 1
        grow(s.bar, width)
      else
        s.bar.cur = width
        s.bar:SetWidth(width)
      end
      s.v:SetText(e.v)
      s.skull:SetShown(dead)
      V.Play(s.shake, dead)
    end
  end
  return b
end

---------------------------------------------------------------------------
-- The flash mob's clock: counts down to the start, then to the end, its watch sweeping round; and how many are
-- there (the number pops when it goes up). It counts by itself while the page shows.
--   f:Countdown(key, at, ends, count)
---------------------------------------------------------------------------
local function clock(sec)
  sec = math.max(0, math.floor(sec))
  if sec >= 3600 then return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60) end
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
V.Clock = clock

local function tick(b)
  local now = time()
  local phase = now < b.at and "soon" or (now <= b.ends and "on" or "over")
  if phase == "soon" then
    b.label:SetText(L.VI_STARTS_IN)
    b.time:SetText(clock(b.at - now))
  elseif phase == "on" then
    b.label:SetText(L.VI_ENDS_IN)
    b.time:SetText(clock(b.ends - now))
  else
    b.label:SetText("")
    b.time:SetText(L.VI_TIME_UP)
  end
  if phase ~= b.phase then
    b.phase = phase
    b.watch:SetDesaturated(phase == "over")
    if b.sweep then
      if phase == "on" and GetTime then
        b.sweep:SetCooldown(GetTime() - (now - b.at), math.max(1, b.ends - b.at))
      elseif b.sweep.Clear then
        b.sweep:Clear()
      end
    end
  end
  V.Play(b.hurry, phase == "soon" and b.at - now <= 60)
end

function Flow:Countdown(key, at, ends, count)
  local b = box(self, key, 50, "countdown")
  if not b.watch then
    b.watch = b:CreateTexture(nil, "ARTWORK")
    UI.IconTex(b.watch, UI.ICON.flash)
    b.watch:SetSize(44, 44)
    b.watch:SetPoint("LEFT", 2, 0)
    b.hurry = V.Pulse(b.watch, 1.12)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if ok and cd then
      cd:SetAllPoints(b.watch)
      if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
      if cd.SetDrawEdge then cd:SetDrawEdge(true) end
      b.sweep = cd
    end
    b.label = UI.Ink(line(b, "GameFontDisableSmall", 130))
    b.label:SetPoint("TOPLEFT", 56, -6)
    b.time = line(b, "GameFontNormalHuge", 130)
    b.time:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -3)
    b.count = UI.Text(b, "GameFontHighlightHuge", "RIGHT")
    b.count:SetPoint("TOPRIGHT", -6, -4)
    b.pop = V.Pop(b.count)
    b.there = UI.Ink(UI.Text(b, "GameFontDisableSmall", "RIGHT"))
    b.there:SetPoint("TOPRIGHT", b.count, "BOTTOMRIGHT", 0, -2)
    b.since = 0
    b:SetScript("OnUpdate", function(frame, elapsed)
      frame.since = frame.since + elapsed
      if frame.since < 0.25 then return end
      frame.since = 0
      tick(frame)
    end)
  end
  if b.at ~= at or b.ends ~= ends then b.phase = nil end
  b.at, b.ends = at, ends
  b.count:SetText(count or 0)
  UI.Ink(b.there):SetText(L.VI_THERE)
  if (count or 0) > (b.lastCount or count or 0) then V.Play(b.pop, true) end
  b.lastCount = count or 0
  tick(b)
  return b
end
