-- The scenes (SPEC decision 60 and its table): one short scene for each activity, on a stage (UI/Stage.lua) at the
-- top of the picture the panel shows, above the pictures that were there before (the ladder, the bars, the
-- bracket, the track). Each draws its last picture on every refresh, and plays a moment once on this screen. They
-- read the guild's data as the pages do; a page's picture calls its scene.
local _, ns = ...
local L, UI, D = ns.L, ns.UI, ns.GuildData
local V, Sg = UI.Visuals, UI.Stage
local P = ns.Players
local Sc = {}
ns.Scenes = Sc

local GOLD, RED, GREEN, WHITE = V.GOLD, { 0.95, 0.3, 0.2 }, { 0.45, 0.9, 0.45 }, { 1, 0.97, 0.85 }
local PURPLE = { 0.62, 0.36, 0.94 }
local SEAT, SEAT_DARK = { 0.4, 0.26, 0.13 }, { 0.22, 0.14, 0.07 }
local GAVEL = UI.ICON.scales   -- the court's scales, a painted medallion
local MID = Sg.W / 2

-- The character a player is shown as: ours now, else the one online, else their main.
local function char(key)
  if type(key) ~= "string" then return nil end
  if P:IsMe(key) then return ns.Self() end
  return P:Online(key) or P:Main(key) or key
end
Sc.Char = char

-- A player's class colour (for a ticket, a seal), gold when it is not known.
local function classColor(name)
  local class = type(name) == "string" and ns.Roster:Class(name)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and { c.r, c.g, c.b } or GOLD
end

-- A medal (an icon in its ring) on the stage.
local function medal(s, role, icon, x, y, size)
  return s:Tex(role, x, y, { icon = icon, size = size or 30 })
end

-- A seat under a seated character (SPEC decision 74), behind them: a stool, a chair, the jury's bench (w: its width).
local function seat(s, role, x, size, floor, w)
  size, floor = size or 1, floor or Sg.FLOOR
  local h = math.floor(20 * size + 0.5)
  s:Tex(role .. ".seat", x, floor - h, { w = w or 30 * size, h = math.max(3, 5 * size), color = SEAT, under = true })
  s:Tex(role .. ".leg", x, floor - h / 2, { w = math.max(2, 4 * size), h = h, color = SEAT_DARK, under = true })
end

-- A few guildmates sit on the ground at the front and watch (SPEC decision 74): those in first (a duel's bettors),
-- then guildmates online, never one in the scene already (cast: its names). xs: where they sit (default the front
-- corners, the third beside the first with its name a line lower), as many as it has room for.
Sc.WATCHERS = 3
local WATCH_X = { 24, 296, 74 }
local function watchers(s, first, cast, xs)
  xs = xs or WATCH_X
  local most = math.min(Sc.WATCHERS, #xs)
  local skip, list = {}, {}
  for _, n in pairs(cast) do if type(n) == "string" then skip[P:Of(n)] = true end end
  local function add(name)
    if #list >= most or type(name) ~= "string" then return end
    local key = P:Of(name)
    if skip[key] then return end
    skip[key] = true
    list[#list + 1] = name
  end
  for _, n in ipairs(first or {}) do add(n) end
  local online = {}
  for name in pairs(ns.Roster:All() or {}) do
    if ns.Roster:Online(name) then online[#online + 1] = name end
  end
  table.sort(online)
  for _, n in ipairs(online) do add(n) end
  for i, name in ipairs(list) do
    local x = xs[i]
    s:Actor("w" .. i, name, x, x < MID and 1 or -1, { size = 0.6, floor = Sg.FLOOR + 8, move = "sit", layer = 8,
      low = i == 3 })
  end
  for i = #list + 1, Sc.WATCHERS do s:Leave("w" .. i) end
  return list
end
Sc.Watchers = watchers

-- The bettors on a match (their names, sorted): they watch first.
local function bettors(g, m)
  local list = {}
  for name in pairs(g and g.bets and g.bets[m] or {}) do list[#list + 1] = name end
  table.sort(list)
  return list
end

-- Two players face to face who run in from the sides (duel, trial by combat, Mak'gora): returns both. play: the
-- moment they meet. stillA, stillB: the moves they keep (nil: they stand ready). first: who watches first.
local function faceOff(s, a, b, play, stillA, stillB, first)
  local A = s:Actor("a", a, 122, 1, { move = not play and (stillA or "ready") or nil })
  local B = s:Actor("b", b, 198, -1, { move = not play and (stillB or stillA or "ready") or nil })
  if play then
    s:Run(A, 30, 0.6, 0, "ready")
    s:Run(B, 290, 0.6, 0, "ready")
  end
  watchers(s, first, { a, b })
  return A, B
end

---------------------------------------------------------------------------
-- Gambling: at the guild hall's hearth
---------------------------------------------------------------------------
-- The deathroll in hand (Guild/Deathroll.lua's game): the two on stools at the table (SPEC decision 74), each with
-- their last roll under their name; the roller throws, the die lands on the roll; a 1 fells them.
function Sc.Deathroll(f, game)
  local s = f:Stage("stage", "tavern")
  s:Scene("dr:" .. tostring(game.id))
  local rolls = game.rolls or {}
  local n, last = #rolls, rolls[#rolls]
  local play = last ~= nil and s:New("roll" .. n)
  local over = game.st == "over"
  local function still(mine)
    if play then return nil end
    if not over then return "stool" end
    return ((game.loser == "me") == mine) and "dead" or "cheer"
  end
  local said = {}
  for _, r in ipairs(rolls) do said[r.who == "me" and "me" or "op"] = L.STAGE_ROLLED:format(r.v) end
  seat(s, "stool.me", 82)
  seat(s, "stool.op", 238)
  local me = s:Actor("me", ns.Self(), 82, 1, { move = still(true), line = said.me })
  local op = s:Actor("op", game.opp, 238, -1, { move = still(false), live = true, line = said.op })
  s:Tex("table", MID, 152, { w = 120, h = 8, color = { 0.34, 0.22, 0.12 } })
  local face, num = s:Die("die", MID, 134, last and last.v or nil)
  -- Our own roll is on its way (Guild/Dice.lua): the die rattles until the game says the number.
  V.Rattle(face, ns.Dice:Waiting())
  if play then
    local roller = last.who == "me" and me or op
    if n == 1 then s:Do(roller == me and op or me, "stool") end
    s:Do(roller, "throw", 0, "stool")
    s:Say(roller, said[roller == me and "me" or "op"], nil, 1.1)
    V.Fly(face, last.who == "me" and -72 or 72, 30, 26, 0.4)
    s:Roll(face, num, 0.4)
    if last.v == 1 then
      V.Jolt(face, 4, 1.15)
      V.Burst(s.top, MID, 134, RED, 10, 1.1)
      s:Do(roller, "death", 1.15)
      s:Do(roller == me and op or me, "cheer", 1.25)
    end
  end
  s:Done()
end

-- The high roll (Guild/RollOff.lua): the players on stools (SPEC decision 74), a die over each as their roll is seen
-- and the roll under their name; the highest is crowned.
function Sc.HighRoll(f, ro, id)
  local RO = ns.RollOff
  local s = f:Stage("stage", "tavern")
  s:Scene("ro:" .. tostring(id))
  local rolled = {}
  for _, r in ipairs(RO:Rolls(ro)) do rolled[r.name] = r.v end
  local joined = RO:Joined(ro)
  local n = math.min(#joined, 5)
  local done = ro.st == "done" and ro.hi ~= nil
  local fin = done and s:New("end", ro.te)
  local at = {}
  for i = 1, n do
    local name = joined[i]
    local x = 32 + (i - 0.5) * (256 / n)
    local v = rolled[name]
    local play = v ~= nil and s:New("roll:" .. name)
    local still = not play and "stool" or nil
    if done and not fin then still = name == ro.hi and "cheer" or (name == ro.lo and "cry" or "stool") end
    seat(s, "stool" .. i, x, 0.82)
    local line = v and L.STAGE_ROLLED:format(v) or nil
    local a = s:Actor("p" .. i, name, x, x < MID and 1 or -1, { size = 0.82, move = still, live = true, line = line })
    local hx, hy = s:Head(a)
    local face, num = s:Die("d" .. i, x, hy - 24, v)
    if play then
      s:Do(a, "throw", 0, "stool")
      s:Roll(face, num, 0.25)
      s:Say(a, line, nil, 0.95)
    end
    at[name] = { a = a, x = hx, y = hy }
  end
  local hi, lo = done and at[ro.hi], done and at[ro.lo]
  if hi then
    local crown = medal(s, "crown", UI.ICON.crown, hi.x, hi.y + 4, 22)
    if fin then
      V.Drop(crown, 50, 0.5, 0.1)
      V.Burst(s.top, hi.x, hi.y, GOLD, 10, 0.55)
      s:Do(hi.a, "cheer", 0.6)
      if lo then s:Do(lo.a, "cry", 0.6) end
    end
    if lo and (ro.amt or 0) > 0 then
      local coin = s:Tex("coin", hi.x, hi.y + 30, { icon = UI.ICON.coin, size = 14, alpha = 0 })
      if fin then V.Fly(coin, lo.x - hi.x, 0, 34, 0.55, 0.9, 0, true) end
    end
  end
  s:Done()
end

-- A lottery (Guild/Raffle.lua): the host beside the drum, with a ticket in it for each one sold in the buyer's class
-- colour, the newest dropping in (the second check of 1 November). At the draw the host throws, the die lands on the
-- number, and that ticket flies out of the drum to the winner, where it turns to their name.
Sc.DRUM_SHOWN = 14
local DRUM_X, DRUM_Y, DRUM_R = 156, 108, 44
local WOOD, WOOD_DARK = { 0.42, 0.27, 0.13 }, { 0.24, 0.15, 0.08 }
function Sc.Lottery(f, ra, id)
  local s = f:Stage("stage", "tavern")
  s:Scene("ra:" .. tostring(id))
  local drawn = ra.st == "done" and ra.w ~= nil
  local play = drawn and s:New("draw", ra.td)
  local host = s:Actor("host", ra.h, 52, 1)
  -- The drum, round (it was a box that read as a screen: the third check of 1 November): a wooden wheel on an
  -- A-frame, dark inside behind its gold spokes, a gold rim, the crank on its side.
  for i, side in ipairs({ -1, 1 }) do
    local leg = s:Tex("leg" .. i, DRUM_X + side * 22, 150, { w = 7, h = 48, color = WOOD_DARK, under = true })
    if leg.SetRotation then leg:SetRotation(side * 0.38) end
  end
  s:Tex("foot", DRUM_X, 172, { w = 74, h = 5, color = WOOD_DARK, under = true })
  s:Tex("drum", DRUM_X, DRUM_Y, { file = "Dot", size = 2 * DRUM_R, color = WOOD })
  s:Tex("drum.in", DRUM_X, DRUM_Y, { file = "Dot", size = 2 * DRUM_R - 14, color = { 0.09, 0.06, 0.035, 0.96 }, sub = 1 })
  local spokes = {}
  for i, turn in ipairs({ 0.785, -0.785 }) do
    local sp = s:Tex("spoke" .. i, DRUM_X, DRUM_Y, { w = 2 * DRUM_R - 16, h = 2, color = { GOLD[1], GOLD[2], GOLD[3], 0.45 }, sub = 4 })
    if sp.SetRotation then sp:SetRotation(turn) end
    spokes[i] = sp
  end
  s:Tex("drum.rim", DRUM_X, DRUM_Y, { file = "Ring", size = 2 * DRUM_R + 6, color = GOLD, sub = 5 })
  s:Tex("hub", DRUM_X, DRUM_Y, { file = "Dot", size = 9, color = GOLD, sub = 6 })
  s:Tex("crank", DRUM_X + DRUM_R + 9, DRUM_Y, { w = 18, h = 4, color = WOOD_DARK, sub = 2 })
  s:Tex("knob", DRUM_X + DRUM_R + 18, DRUM_Y, { file = "Dot", size = 9, color = GOLD, sub = 3 })
  local tickets, sold = {}, ra.sold or 0
  if type(ra.b) == "table" then tickets, sold = ns.Raffle:Tickets(ra) end
  local cards = {}
  for _, e in ipairs(tickets) do
    for _ = 1, e[2] do if #cards < Sc.DRUM_SHOWN then cards[#cards + 1] = e[1] end end
  end
  local fresh = not drawn and sold > 0 and s:New("sold" .. sold)
  for i, name in ipairs(cards) do
    -- Spread inside the wheel (the golden angle, out from the middle), the same place each time.
    local a, r = i * 2.4, 9 + (i * 7) % 21
    local x, y = DRUM_X + r * math.cos(a), DRUM_Y + r * math.sin(a)
    local t = s:Tex("t" .. i, x, y, { w = 14, h = 9, color = classColor(name), sub = 3 })
    if t.SetRotation then t:SetRotation(a) end
    if fresh and i == #cards then V.Drop(t, 40, 0.45) end
  end
  s:Text("sold", L.STAGE_DRUM:format(sold), DRUM_X, 22, "GameFontNormal")
  if drawn then
    -- The wheel turns while the die is in the air.
    if play then
      for _, sp in ipairs(spokes) do V.Rattle(sp, true) end
      s:After(0.9, function() for _, sp in ipairs(spokes) do V.Rattle(sp, false) end end)
    end
    local face, num = s:Die("die", DRUM_X, 46, ra.roll)
    local win = s:Actor("win", ra.w, 262, -1, { move = not play and "cheer" or nil })
    local hx, hy = s:Head(win)
    local ty = hy - 22
    local card = s:Tex("ticket", hx, ty, { round = true, w = 96, h = 24, color = { 0.18, 0.13, 0.06, 0.92 } })
    local no = s:Text("ticket.no", L.STAGE_TICKET:format(ra.roll or 0), hx, ty, "GameFontNormal", { alpha = 0 })
    local who = s:Text("ticket.who", ns.Display(ra.w), hx, ty, "GameFontNormal")
    if play then
      s:Do(host, "throw")
      s:Roll(face, num, 0.2)
      -- The winning ticket flies out of the drum.
      local fly = s:Tex("fly", hx, ty, { w = 18, h = 12, color = classColor(ra.w), sub = 4, alpha = 0 })
      local dx, dy = Sg.Offset(DRUM_X, DRUM_Y, hx, ty)
      V.Fly(fly, dx, dy, 30, 0.5, 1.0, 20, true)
      V.Reveal(card, 1.5, 0.2)
      V.Flip(no, who, 1.6, 0.35)
      V.Burst(s.top, hx, ty, GOLD, 10, 1.85)
      s:Do(win, "cheer", 1.9)
    end
  end
  s:Done()
end

---------------------------------------------------------------------------
-- PvP Challenges: in the duelling ring
---------------------------------------------------------------------------
-- Rating points a duel moved (Elo, as Guild/Duels.lua): from the ratings before it, this season.
local function gain(g, w, l, t)
  local Du = ns.Duels
  local season = Du.Now(g, t)
  if not season or t < season.from then return nil end
  local r = {}
  for _, e in ipairs(Du.Ladder(g, season.from, t)) do r[e.key] = e.r end
  local rw, rl = r[P:Of(w, g)] or Du.START, r[P:Of(l, g)] or Du.START
  return math.floor(Du.K * (1 - 1 / (1 + 10 ^ ((rl - rw) / 400))) + 0.5)
end

-- The newest duel that ended within RECENT, and its id.
local function lastDuel(g, now)
  local best, id
  for c, e in pairs(g and g.duels or {}) do
    if e.t and now - e.t <= Sg.RECENT and (not best or e.t > best.t) then best, id = e, c end
  end
  return best, id
end

-- The pot of a match in the purse, and my bet on it.
local function pot(g, m)
  local purse = D:Settings().purse
  local total = 0
  for _, v in pairs(ns.Duels.Pot(g, m)[purse] or {}) do total = total + v end
  return total, g.bets and g.bets[m] and g.bets[m][ns.Self()]
end

local function money(amt, p) return ns.Purse:Format(ns.Purse.Units(amt, p), p) end

-- Is there a duels scene to show: a duel that just ended, your accepted duel, or a holder of the duel crown?
function Sc.HasDuels(g)
  local ch = ns.Duels:Game()
  return lastDuel(g, time()) ~= nil or (ch ~= nil and ch.st == "on") or ns.Crown.State(g).holder ~= nil
end

-- Duels: the duel that just ended (the winner cheers, the loser kneels, the points over them), else your accepted
-- duel (both stand ready), else the duel crown on its holder. Bets: a coin into the pot, and the pot to the winner.
function Sc.Duels(f, g)
  local now = time()
  local Du, Cr = ns.Duels, ns.Crown
  local cr = Cr.State(g, now)
  local e, id = lastDuel(g, now)
  local ch = Du:Game()
  if cr.holder and cr.since and now - cr.since <= Sg.RECENT and (not e or cr.since >= e.t) then
    return Sc.Crown(f, cr)
  end
  if e then
    local s = f:Stage("stage", "ring")
    s:Scene("du:" .. id)
    local play = s:New("end", e.t)
    local W, Lo = faceOff(s, e.w, e.l, false, "cheer", "kneel", bettors(g, id))
    local pts = gain(g, e.w, e.l, e.t)
    local wx, wy = s:Head(W)
    local lx, ly = s:Head(Lo)
    if play then
      -- The last blow, then the winner cheers and the loser kneels.
      s:Do(W, "attack", 0, "cheer")
      s:Do(Lo, "wound", 0.3, "kneel")
      V.Burst(s.top, MID, 110, WHITE, 8, 0.3)
    end
    if pts then
      local up = s:Text("up", "+" .. pts, wx, wy - 14, "GameFontNormalLarge")
      local dn = s:Text("dn", "-" .. pts, lx, ly - 14, "GameFontHighlightLarge", { color = { 0.6, 0.6, 0.6 } })
      if play then
        V.PopIn(up, 0.9)
        V.Drop(dn, -14, 0.4, 1.0)
        V.Burst(s.top, wx, wy - 14, GOLD, 10, 0.9)
      end
    end
    local total = pot(g, id)
    if total > 0 then
      medal(s, "pot", UI.ICON.coins, MID, 150, 22)
      for i = 1, 3 do
        local c = s:Tex("coin" .. i, wx, wy + 20, { icon = UI.ICON.coin, size = 12, alpha = 0 })
        local dx, dy = Sg.Offset(MID, 150, wx, wy + 20)
        if play then V.Fly(c, dx, dy, 30 + i * 8, 0.45 + i * 0.08, 0.5, 0, true) end
      end
    end
    return s:Done()
  end
  if ch and ch.st == "on" then
    local s = f:Stage("stage", "ring")
    s:Scene("ch:" .. tostring(ch.id))
    local on = s:New("on")
    local A, B = faceOff(s, ns.Self(), ch.opp, on, "ready", nil, bettors(g, ch.id))
    if on then
      -- They trade blows once they meet.
      s:Do(A, "attack", 0.75, "ready")
      s:Do(B, "wound", 0.95, "ready")
      s:Do(B, "attack", 1.5, "ready")
      s:Do(A, "wound", 1.7, "ready")
      V.Burst(s.top, MID, 110, WHITE, 8, 0.95)
      V.Burst(s.top, MID, 110, WHITE, 8, 1.7)
      V.Burst(s.top, MID, 110, GOLD, 6, 1.7)
    end
    local total, bet = pot(g, ch.id)
    if total > 0 then
      local coins = medal(s, "pot", UI.ICON.coins, MID, 150, 22)
      local n = s:Text("pot.n", money(total, D:Settings().purse), MID, 128, "GameFontHighlight")
      if bet and s:New("bet:" .. tostring(bet.t) .. ":" .. tostring(bet.amt)) then
        local coin = s:Tex("coin", MID, 150, { icon = UI.ICON.coin, size = 14, alpha = 0 })
        local dx, dy = Sg.Offset((bet.on == ns.Self() and A or B).x, 110, MID, 150)
        V.Fly(coin, dx, dy, 30, 0.5, 0, 0, true)
        V.PopIn(n, 0.5, 1.5)
        V.Jolt(coins, 2, 0.5)
      end
    end
    return s:Done()
  end
  if cr.holder then return Sc.Crown(f, cr) end
end

-- The duel crown on its holder (Guild/Crown.lua's state): it drops onto their head when it is new.
function Sc.Crown(f, cr)
  local s = f:Stage("stage", "ring")
  s:Scene("cr:" .. tostring(cr.holder) .. ":" .. tostring(cr.since))
  local play = s:New("took", cr.since)
  local a = s:Actor("holder", cr.name or char(cr.holder), MID, 1)
  local hx, hy = s:Head(a)
  local crown = medal(s, "crown", UI.ICON.crown, hx, hy + 2, 28)
  if play then
    V.Drop(crown, 70, 0.5, 0.3)
    V.Burst(s.top, hx, hy, GOLD, 10, 0.75)
    s:Do(a, "roar", 0.8)
  end
  s:Done()
end

-- A tournament (Guild/Cup.lua): the newest winner runs up and waves; the champion wears the crown.
-- A cup's sign-up (the second check of 1 November): the entrants gathered at the arena's gate under its banner; the
-- newest runs in and waves.
Sc.GATE_SHOWN = 5
local function signUp(f, c, cid)
  local list = ns.Cup.Joined(c)
  local s = f:Stage("stage", "ring")
  s:Scene("cupopen:" .. tostring(cid))
  local wood = { 0.3, 0.21, 0.12 }
  s:Tex("post.l", MID - 78, 104, { w = 12, h = 120, color = wood })
  s:Tex("post.r", MID + 78, 104, { w = 12, h = 120, color = wood })
  s:Tex("arch", MID, 46, { w = 170, h = 16, color = { 0.38, 0.27, 0.15 } })
  medal(s, "banner", UI.ICON.prize, MID, 26, 30)
  s:Text("count", L.STAGE_SIGNED:format(#list), MID, 64, "GameFontNormal")
  local n = math.min(#list, Sc.GATE_SHOWN)
  local fresh = #list > 0 and s:New("joined" .. #list)
  for i = 1, n do
    local name = list[#list - n + i]
    local x = 44 + (i - 0.5) * (232 / n)
    local a = s:Actor("e" .. i, name, x, x < MID and 1 or -1, { size = 0.72, move = (fresh and i == n) and nil or "ready" })
    if fresh and i == n then s:Run(a, 330, 0.7, 0, "wave") end
  end
  watchers(s, nil, list, { 18, 302 })
  s:Done()
end

function Sc.Cup(f, g, c, cid)
  if c.st == "open" then return signUp(f, c, cid) end
  local B = ns.Cup.Build(c)
  if not B then return end
  local newest, nt
  for _, m in ipairs(B.matches) do
    local d = m.w and g.duels and g.duels[ns.Cup.MatchId(cid, m.key)]
    local t = d and d.t or 0
    if m.w and type(m.w) == "string" and (not newest or t > nt) then newest, nt = m, t end
  end
  if not newest and not B.champion then return end
  local s = f:Stage("stage", "ring")
  local who = B.champion or newest.w
  s:Scene("cup:" .. tostring(cid) .. ":" .. tostring(who))
  local play = s:New("won", nt ~= 0 and nt or nil)
  local a = s:Actor("winner", who, 200, -1, { move = not play and (B.champion and "cheer" or "wave") or nil })
  if B.champion then
    local hx, hy = s:Head(a)
    local crown = medal(s, "crown", UI.ICON.crown, hx, hy + 2, 26)
    if play then V.Drop(crown, 60, 0.5, 0.7) end
  end
  if play then
    s:Run(a, 300, 0.6, 0, B.champion and "cheer" or "wave")
  end
  watchers(s, nil, { who })
  s:Done()
end

-- Your secret target, while you show it: a poster with their portrait. When you beat one, the cross, then the next.
function Sc.Target(f, id, target)
  if not target then return end
  local s = f:Stage("stage", "ring")
  s:Scene("as:" .. tostring(id))
  -- (The name once, on the poster, inside it: it was cut at its foot and said twice, the third check of 1 November.)
  s:Tex("poster", MID, 90, { round = true, w = 120, h = 158, color = { 0.9, 0.84, 0.68 }, under = true })
  s:Text("poster.title", L.STAGE_TARGET, MID, 26, "GameFontNormal", { color = { 0.3, 0.17, 0.07 } })
  local a = s:Actor("target", target, MID, 1, { size = 0.9, floor = 134, bare = true })
  local name = s:Text("poster.name", ns.Display(target), MID, 150, "GameFontNormal", { color = { 0.3, 0.17, 0.07 } })
  local before = s.lastTarget
  s.lastTarget = target
  if before and before ~= target and s:New("next:" .. target) then
    local x = s:Text("cross", "X", MID, 88, "GameFontNormalHuge", { alpha = 0, color = RED })
    V.Flash(x, 1, 0.08, 0.5, 0.2)
    V.Reveal(a, 0.8, 0.3)
    V.PopIn(name, 0.8)
  end
  s:Done()
end

---------------------------------------------------------------------------
-- Punishments: in the town square (fishing at the pier, a gift in the council hall, a trial in the ring)
---------------------------------------------------------------------------
Sc.SPIN = 3.2              -- seconds the Wheel turns (as UI/Alerts.lua's)
Sc.spins = {}              -- sentence id -> when its Wheel began to turn on this screen
local TOMATO = { 0.85, 0.16, 0.08 }

local function wheelIndex(r)
  for i, p in ipairs(ns.Stocks.WHEEL) do if p == r then return i end end
  return 1
end

-- The Wheel standing in the square, or turning onto spun.r: the punished player begs, then sobs.
local function wheel(f, s, spun)
  local st = f:Stage("stage", "square")
  st:Scene("wheel:" .. s.id)
  local list = ns.Stocks.WHEEL
  local r = spun and wheelIndex(spun.r) or 1
  local w = st:Prop("wheel", function(top) return V.Wheel(top, 128) end)
  st:At(w, 100, 96)
  local a = st:Actor("who", char(s.key), 240, -1, { move = spun and "cry" or "beg" })
  local label = st:Text("landed", spun and L["ACT_" .. spun.r:upper()] or "", 240, 26, "GameFontNormalLarge")
  local began = Sc.spins[s.id .. ":" .. tostring(spun and spun.t)]
  if spun and began and st:New("spin:" .. tostring(spun.t), spun.t) then
    V.WheelSpin(w, list, r, Sc.SPIN)
    V.PopIn(label, Sc.SPIN)
    V.Burst(st.top, 100, 96 - 128 * 0.33, GOLD, 10, Sc.SPIN)
    st:Do(a, "beg")
    st:Do(a, "cry", Sc.SPIN + 0.1)
  elseif not began or GetTime() - began > Sc.SPIN + 1.5 then
    V.WheelRest(w, list, r)
  end
  st:Done()
end

-- A sentence (Guild/Stocks.lua's state, s) as its punishment's scene. The punishment's medal stamps down when it
-- starts; a pardon or bail drops the shackles.
function Sc.Sentence(f, g, s)
  local se, me = s.se, ns.Self()
  -- The Wheel: standing while it waits for its spin; turning when the spin (or reroll) is new here, for as long as it
  -- turns, then the scene of where it landed.
  if se.pun == "wheel" then
    local x = s.spun
    if not x then return wheel(f, s, nil) end
    local k = s.id .. ":" .. tostring(x.t)
    if not Sc.spins[k] and math.abs(time() - (x.t or 0)) < 60 and UI.Motion() then Sc.spins[k] = GetTime() end
    local began = Sc.spins[k]
    if began and GetTime() - began <= Sc.SPIN + 1.5 then return wheel(f, s, x) end
  end
  local pun = s.pun
  local trial = pun == "trial" or s.trial or s.how == "trial"
  local place = trial and "ring" or (pun == "service" and "pier" or (pun == "idol" and not s.idol and "council" or "square"))
  local st = f:Stage("stage", place)
  st:Scene("pun:" .. s.id .. ":" .. pun)
  local key = char(s.key)
  local freed = s.st == "done" and (s.how == "pardoned" or s.how == "bailed")
  local endPlay = freed and st:New("free", s.ends)
  local start = st:New("start", se.t)
  local stamp = medal(st, "pun", UI.ICON["p_" .. pun] or UI.ICON.question, 26, 26, 30)
  if start then V.Stamp(stamp, 0.1) end

  if trial then
    local play = st:New("trial", se.t)
    local stillA, stillB = "ready", "ready"
    if s.how == "trial" and s.winner then
      local won = P:Of(s.winner, g) == s.key
      stillA, stillB = won and "cheer" or "kneel", won and "kneel" or "cheer"
    end
    faceOff(st, key, se.by, play, stillA, stillB)
    return st:Done()
  end

  if freed then
    local a = st:Actor("who", key, MID, 1, { move = not endPlay and "cheer" or nil })
    local sh = medal(st, "shackles", UI.ICON.shackles, MID + 14, 164, 24)
    sh:SetAlpha(0)
    if endPlay then
      V.Fly(sh, 0, 52, 4, 0.5, 0.25, 70, true)
      st:Do(a, "cheer", 0.6)
    end
    return st:Done()
  end

  if pun == "stocks" then
    local a = st:Actor("who", key, 230, -1, { move = "shy", line = L.STAGE_IN_STOCKS })
    local hx, hy = st:Head(a)
    local total, mine = 0, 0
    for name, n in pairs(se.tom or {}) do
      total = total + n
      if name == me then mine = n end
    end
    local count = st:Text("count", L.ST_TOMATOES:format(total), hx, hy - 16, "GameFontHighlight")
    local thrower = not P:IsMe(s.key, g) and st:Actor("me", me, 74, 1) or nil
    watchers(st, nil, { key, me }, { 22, 298, 150 })
    if total > 0 and st:New("tom" .. total) then
      local byMe = st.myTom ~= nil and mine > st.myTom and thrower ~= nil
      local tom = st:Tex("tomato", hx, hy + 10, { file = "Dot", size = 13, color = TOMATO, alpha = 0 })
      local splat = st:Tex("splat", hx, hy + 10, { file = "Glow", size = 44, color = TOMATO, alpha = 0, blend = "ADD" })
      local dx, dy = Sg.Offset(byMe and 84 or 0, 110, hx, hy + 10)
      if byMe then st:Do(thrower, "throw") end
      V.Fly(tom, dx, dy, 46, 0.5, 0.15, 400, true)
      V.Flash(splat, 0.95, 0.04, 0.1, 0.45, 0.65)
      V.Burst(st.top, hx, hy + 10, TOMATO, 9, 0.65)
      st:Do(a, "wound", 0.65, "shy")
      V.PopIn(count, 0.7, 1.4)
    end
    st.myTom = mine
  elseif pun == "dunce" then
    local a = st:Actor("who", key, MID, 1, { move = "shy" })
    local hx, hy = st:Head(a)
    local hat = medal(st, "hat", UI.ICON.p_dunce, hx, hy, 30)
    local tag = st:Text("tag", L.STAGE_CLOWN, hx, hy - 26, "GameFontNormal", { color = { 1, 0.48, 0.75 } })
    if start then
      V.Drop(hat, 70, 0.5, 0.3)
      V.Wobble(hat, 0.82)
      V.PopIn(tag, 1.3)
    end
  elseif pun == "service" then
    local a = st:Actor("who", key, 86, 1)
    st:Tex("line", 150, 128, { w = 1, h = 70, color = { 0.85, 0.85, 0.85, 0.5 } })
    local n = s.n or 0
    local count = st:Text("count", L.ST_FISH:format(n, se.q or ns.Stocks.QUOTA), 240, 30, "GameFontHighlight")
    if n > 0 and st:New("fish" .. n) then
      local fish = st:Tex("fish", 240, 50, { icon = UI.ICON.fish, size = 22, alpha = 0 })
      local dx, dy = Sg.Offset(150, 162, 240, 50)
      V.Fly(fish, dx, dy, 30, 0.55, 0, -200, true)
      V.Burst(st.top, 150, 162, { 0.55, 0.8, 1 }, 6, 0)
      V.PopIn(count, 0.55, 1.4)
      st:Do(a, "cheer", 0.5)
      st:Do(a, "stand", 1.9)
    end
  elseif pun == "walk" then
    local a = st:Actor("who", key, 226, 1, { bare = true, move = "shy" })
    local count = st:Text("count", L.STAGE_ZONES:format(s.i or 0, #(se.z or {})), 226, 30, "GameFontHighlight")
    if (s.i or 0) > 0 and st:New("zone" .. s.i) then
      st:Run(a, 40, 1, 0, "shy")
      V.Stamp(count, 1)
    end
  elseif pun == "curse" then
    local glow = st:Tex("glow", MID, 120, { file = "Glow", w = 110, h = 130, color = { 0.3, 0.85, 0.35 }, blend = "ADD" })
    local a = st:Actor("who", key, MID, 1, { move = "talk" })
    local hx, hy = st:Head(a)
    st.pulse = st.pulse or V.Pulse(glow, 1.12)
    V.Play(st.pulse, UI.Motion())
    for i, word in ipairs({ L.STAGE_MRGL1, L.STAGE_MRGL2, L.STAGE_MRGL3 }) do
      local b = st:Text("mrgl" .. i, word, hx + (i - 2) * 26, hy - 10, "GameFontHighlightSmall", { alpha = 0, color = GREEN })
      if not b.floating and UI.Motion() then b.floating = V.Float(b, 48, 1.5, (i - 1) * 0.5) end
    end
  elseif pun == "radio" then
    medal(st, "jingle", UI.ICON.p_radio, 250, 70, 30)
    st:Actor("who", key, 130, 1, { move = "dance" })
    for i = 1, 2 do
      local r = st:Tex("ring" .. i, 250, 70, { file = "Ring", size = 30, color = GOLD, alpha = 0 })
      if not r.rippling and UI.Motion() then r.rippling = V.Ripple(r, 2.4, 1.2, (i - 1) * 0.6) end
    end
  elseif pun == "servant" then
    local a = st:Actor("who", key, 110, 1)
    local purse = D:Settings().purse
    if s.master then
      local b = st:Actor("master", s.master, 236, -1, { move = s.auction and "point" or nil })
      local bx, by = st:Head(b)
      local price = st:Text("price", ns.Purse:Format(ns.Purse.Units(s.price or 0, purse), purse), bx, by - 16)
      if s.auction and st:New("bid:" .. tostring(s.price)) then
        V.PopIn(price, 0)
        st:Do(b, "point")
      end
      if not s.auction then
        local gavel = st:Tex("gavel", 60, 34, { icon = GAVEL, size = 30 })
        local sold = st:Text("sold", L.STAGE_SOLD, MID, 52, "GameFontNormalHuge", { color = RED })
        if st:New("sold", (se.t or 0) + ns.Stocks.AUCTION) then
          V.Strike(gavel, 0.1)
          V.Stamp(sold, 0.45)
          st:Do(a, "bow", 0.8)
        end
      end
    end
  elseif pun == "idol" then
    if not s.idol then
      st:Actor("who", key, 120, 1, { move = "kneel" })
      local gm = ns.Council.GM()
      if gm then st:Actor("gm", gm, 236, -1) end
      medal(st, "gift", UI.ICON.parcel, 146, 140, 24)
    else
      local a = st:Actor("who", key, MID, 1)
      local hx, hy = st:Head(a)
      local glow = st:Tex("idol.glow", hx, hy - 12, { file = "Glow", size = 60, color = PURPLE, blend = "ADD" })
      local idol = medal(st, "idol", UI.ICON.p_idol, hx, hy - 12, 30)
      st.idolPulse = st.idolPulse or V.Pulse(glow, 1.25)
      V.Play(st.idolPulse, UI.Motion())
      if se.trib and st:New("scorned", se.trib.t) then
        V.Drop(idol, 60, 0.5, 0.2)
        st:Do(a, "cry", 0.7)
      end
    end
  end
  st:Done()
end

---------------------------------------------------------------------------
-- Games: at the guild fair (fishing at the pier, Hidden traitors round the council table, the gift exchange at the
-- hearth)
---------------------------------------------------------------------------
local function spread(n, i, left, right) return left + (i - 0.5) * ((right - left) / math.max(1, n)) end
local PLACE = { derby = "pier", traitors = "council", santa = "tavern" }

-- The game's scores (Guild/Games.lua), the first max.
local function top(g, ga, id, max)
  local list = {}
  for i, e in ipairs(ns.Games.Scores(g, ga, id)) do
    if i > max then break end
    list[i] = e
  end
  return list
end

local function bingo(st, g, ga, id, me)
  local mine
  for _, e in ipairs(ns.Games.Scores(g, ga, id)) do if e.key == me then mine = e end end
  if not mine then return end
  local a = st:Actor("me", char(me), 200, -1, { move = mine.bingo and "cheer" or nil })
  local hx, hy = st:Head(a)
  local count = st:Text("count", L.GM_SQUARES:format(mine.v, ns.Games.SIZE * ns.Games.SIZE), hx, hy - 16, "GameFontHighlight")
  medal(st, "card", UI.ICON.bingo, 80, 100, 56)
  local big = st:Text("bingo", mine.bingo and L.AN_ALERT_BINGO or "", 90, 40, "GameFontNormalHuge")
  if mine.bingo and st:New("bingo", mine.t ~= math.huge and mine.t or nil) then
    V.Stamp(big, 0.1)
    V.Burst(st.top, 90, 40, GOLD, 10, 0.4)
    st:Do(a, "cheer", 0.3)
  elseif mine.v > 0 and st:New("sq" .. mine.v) then
    V.PopIn(count, 0)
    st:Do(a, "cheer", 0)
    st:Do(a, "stand", 1.4)
  end
end

local function derby(st, g, ga, id, me)
  local list = top(g, ga, id, 1)
  local lead = list[1]
  if not lead then return end
  local a = st:Actor("lead", lead.name, 86, 1)
  st:Tex("line", 150, 128, { w = 1, h = 70, color = { 0.85, 0.85, 0.85, 0.5 } })
  local count = st:Text("count", L.GM_FISH:format(lead.v), 86, 40, "GameFontHighlight")
  local total = 0
  for _, e in ipairs(ns.Games.Scores(g, ga, id)) do total = total + (e.v or 0) end
  if total > 0 and st:New("fish" .. total) then
    local fish = st:Tex("fish", 240, 60, { icon = UI.ICON.fish, size = 22, alpha = 0 })
    local dx, dy = Sg.Offset(150, 162, 240, 60)
    V.Fly(fish, dx, dy, 34, 0.55, 0, -200, true)
    V.Burst(st.top, 150, 162, { 0.55, 0.8, 1 }, 6, 0)
    V.PopIn(count, 0.55, 1.4)
    if lead.key == me then st:Do(a, "cheer", 0.5); st:Do(a, "stand", 1.9) end
  end
end

local function flash(st, g, ga, id)
  local list = top(g, ga, id, 6)
  local on = time() >= (ga.at or 0)
  local go = on and st:New("go", ga.at)
  local big = st:Text("go", on and L.AL_FLASH_GO or "", MID, 34, "GameFontNormalHuge")
  if go then
    V.Stamp(big, 0.1)
    V.Burst(st.top, MID, 34, GOLD, 10, 0.4)
  end
  for i, e in ipairs(list) do
    local x = spread(#list, i, 30, 290)
    local a = st:Actor("p" .. i, e.name, x, x < MID and 1 or -1, { size = 0.82, move = on and not go and "dance" or nil })
    if st:New("here:" .. e.key) then st:Run(a, x < MID and 10 or 310, 0.7, 0, on and "dance" or "wave") end
    if go then st:Do(a, "dance", 0.4) end
  end
end

local function hunt(st, g, ga)
  local clues = ga.clues or {}
  local found, last = 0, nil
  for i = 1, #clues do
    local who = ns.Games.Finder(ga, i)
    if who then found, last = found + 1, who end
  end
  for i = 1, #clues do
    local x = spread(#clues, i, 40, 280)
    local m = medal(st, "clue" .. i, ns.Games.Finder(ga, i) and UI.ICON.hunt or UI.ICON.question, x, 34, 26)
    m:SetDesaturated(ns.Games.Finder(ga, i) == nil)
  end
  if not last then return end
  local x = spread(#clues, found, 40, 280)
  local a = st:Actor("finder", last, x, 1, { move = "kneel" })
  local check = st:Tex("check", x, 34, { path = V.TEX.check, size = 16 })
  if st:New("clue" .. found) then
    st:Run(a, 0, 0.8, 0, "loot")
    V.Stamp(check, 1.0)
    if P:IsMe(P:Of(last, g), g) then V.Burst(st.top, x, 34, GOLD, 8, 1.0) end
  end
end

local function fashion(st, g, ga, id)
  local list = top(g, ga, id, 4)
  -- (Behind the entrants and under their names: it once hid them, the third check of 1 November.)
  st:Tex("catwalk", MID, 176, { w = 280, h = 6, color = { 0.4, 0.1, 0.1 }, under = true })
  st.votes = st.votes or {}
  local total = 0
  for _, e in ipairs(list) do total = total + (e.v or 0) end
  local play = total > 0 and st:New("votes" .. total)
  local flashTex = st:Tex("flash", MID, Sg.H / 2, { w = Sg.W, h = Sg.H, color = { 1, 1, 1 }, alpha = 0 })
  if play then V.Flash(flashTex, 0.85, 0.02, 0.05, 0.3) end
  for i, e in ipairs(list) do
    local x = spread(#list, i, 40, 280)
    local a = st:Actor("e" .. i, e.name, x, x < MID and 1 or -1, { size = 0.9 })
    local hx, hy = st:Head(a)
    local v = e.v or 0
    local n = st:Text("v" .. i, (v == 1 and L.GM_VOTES_ONE or L.GM_VOTES):format(v), hx, hy - 14,
      i == 1 and "GameFontNormal" or "GameFontHighlight")
    if play and (e.v or 0) > (st.votes[e.key] or 0) then
      V.PopIn(n, 0.1)
      st:Do(a, "roar", 0.1)
    end
    st.votes[e.key] = e.v or 0
  end
end

local function gnomes(st, g, ga, id)
  local list = top(g, ga, id, 4)
  local stops = math.max(1, #(ga.clues or {}))
  st.at = st.at or {}
  for i, e in ipairs(list) do
    local floor = 96 + i * 18
    st:Tex("lane" .. i, MID, floor + 1, { w = 270, h = 2, color = { 0, 0, 0, 0.6 } })
    local x = 30 + 250 * math.min(e.v or 0, stops) / stops
    local still = e.dead and "dead" or (e.done and "cheer" or "run")
    local a = st:Actor("r" .. i, e.name, x, 1, { size = 0.55, floor = floor, layer = i })
    local was = st.at[e.key]
    if e.dead and st:New("fell:" .. e.key) then
      local red = st:Tex("red" .. i, MID, floor - 10, { w = Sg.W, h = 22, color = { 0.8, 0.12, 0.08 }, alpha = 0 })
      V.Flash(red, 0.55, 0.04, 0.05, 0.35)
      st:Do(a, "death")
    elseif was and was < x and st:New("at:" .. e.key .. ":" .. tostring(e.v)) then
      st:Run(a, was, 0.5, 0, e.done and "cheer" or "run")
    elseif a and a.move ~= still then
      st:Do(a, still)
    end
    st.at[e.key] = x
  end
end

local function traitors(st, g, ga)
  local Tr = ns.Traitors
  local phase, r = Tr.Phase(ga)
  local names = {}
  for _, n in ipairs(ga.pl or {}) do names[#names + 1] = n end
  if #names == 0 then for _, n in pairs(ns.Games.Joined(g, ga)) do names[#names + 1] = n end end
  table.sort(names)
  local _, out = Tr.Alive(ga)
  local how = {}
  for _, x in ipairs(out) do how[x.name] = x end
  local n = math.min(#names, 7)
  local dawn = r > 0 and ga.dawn and ga.dawn[r]
  local fell = dawn and st:New("dawn" .. r)
  local banned = r > 0 and ga.ban and ga.ban[r]
  local ban = banned and st:New("ban" .. r)
  for i = 1, n do
    local name = names[i]
    local x = spread(n, i, 22, 298)
    local o = how[name]
    local still = o and (o.how == "murdered" and "dead" or "shy") or nil
    if fell and dawn.v == name then still = nil end
    -- (Seven in a row: every other name a line lower, so they do not run together.)
    local a = st:Actor("p" .. i, name, x, x < MID and 1 or -1, { size = 0.7, move = still, low = n > 5 and i % 2 == 0 })
    if fell and dawn.v == name then st:Do(a, "death", 1.2) end
    if o and o.how == "banished" then
      local hx, hy = st:Head(a)
      local before = st:Text("tag" .. i, ns.Display(name), hx, hy - 12, "GameFontHighlightSmall", { alpha = 0 })
      local role = o.role == "traitor" and L.STAGE_TRAITOR or L.STAGE_FAITHFUL
      local after = st:Text("role" .. i, role, hx, hy - 12, "GameFontNormalSmall",
        { color = o.role == "traitor" and RED or GREEN })
      if ban and banned.v == name then V.Flip(before, after, 0.3, 0.3) end
    end
  end
  local veil = st:Tex("veil", MID, Sg.H / 2, { w = Sg.W, h = Sg.H, color = { 0.02, 0.03, 0.1 }, alpha = phase == "night" and 0.75 or 0 })
  local night = st:Text("night", phase == "night" and L.AN_ALERT_TR_NIGHT or "", MID, 40, "GameFontNormalLarge")
  if phase == "night" and st:New("night" .. r) then
    V.Reveal(veil, 0, 1.5)
    V.PopIn(night, 0.8)
  elseif fell then
    V.Flash(veil, 0.75, 0.01, 0.2, 0.9)
  end
end

local function santa(st, g, ga)
  local players = {}
  for _, n in ipairs(ga.pl or {}) do players[#players + 1] = n end
  if #players == 0 then for _, n in pairs(ns.Games.Joined(g, ga)) do players[#players + 1] = n end end
  table.sort(players)
  local n = math.min(#players, 6)
  local drawn = ga.pl ~= nil and st:New("drawn", ga.go)
  for i = 1, n do
    local box = medal(st, "box" .. i, UI.ICON.parcel, spread(n, i, 30, 290), 34, 26)
    if drawn then V.Drop(box, 18, 0.3, (i - 1) * 0.15) end
  end
  if not ga.pairs then return end
  local giver
  for _, x in ipairs(ga.pairs) do if P:IsMe(P:Of(x[2], g), g) then giver = x[1] end end
  if not giver then return end
  local reveal = st:New("reveal", ga.te)
  local a = st:Actor("giver", giver, MID, 1, { move = not reveal and "wave" or nil })
  local hx, hy = st:Head(a)
  local q = st:Text("from.q", "?", hx, hy - 16, "GameFontNormalLarge", { alpha = 0 })
  local from = st:Text("from", L.STAGE_FROM:format(ns.Display(giver)), hx, hy - 16, "GameFontNormal")
  if reveal then
    V.Reveal(a, 0.6, 0.4)
    V.Flip(q, from, 0.5, 0.4)
    V.Burst(st.top, hx, hy - 16, GOLD, 10, 0.75)
    st:Do(a, "wave", 0.9)
  end
end

local GAMES = { bingo = bingo, derby = derby, flash = flash, hunt = hunt, fashion = fashion, gnomes = gnomes,
  traitors = traitors, santa = santa }

-- A guild game's scene, at the top of the game picked in the panel. me: this player's key.
function Sc.Game(f, g, ga, id, me)
  local draw = GAMES[ga.kind]
  if not draw then return end
  local st = f:Stage("stage", PLACE[ga.kind] or "fair")
  st:Scene("game:" .. tostring(id))
  draw(st, g, ga, id, me)
  st:Done()
end

---------------------------------------------------------------------------
-- Council: in the council hall (Mak'gora in the duelling ring)
---------------------------------------------------------------------------
-- A poll or a rule vote (SPEC decision 74): the voters sit at a long table, the ballot box at its end; the newest
-- stands to cast, and their ballot drops in. You sit last once you have voted; before, you stand by the box.
-- s: Guild/Council.lua's poll or motion (s.voters: { { name, t } }, oldest first); mine: your vote.
Sc.TABLE_SHOWN = 6
local BOX_X, BOX_Y = 294, 140
function Sc.Vote(f, s, mine)
  local st = f:Stage("stage", "council")
  st:Scene("vote:" .. tostring(s.id))
  local me = ns.Self()
  -- The seats in the order they voted, the newest last; you among them once you have voted (as you, whichever
  -- character it was), the oldest giving up their seat when the table is full.
  local names, mineAt = {}, nil
  for _, v in ipairs(s.voters or {}) do
    if P:IsMe(P:Of(v.name)) then mineAt = #names + 1 names[mineAt] = me else names[#names + 1] = v.name end
  end
  local voted = mine ~= nil
  if voted and not mineAt then names[#names + 1] = me mineAt = #names end
  while #names > Sc.TABLE_SHOWN do
    table.remove(names, (mineAt == 1) and 2 or 1)
    if mineAt and mineAt > 1 then mineAt = mineAt - 1 end
  end
  local cast = #(s.voters or {})
  -- Who stands to cast: you when your vote is new here, else the newest voter.
  local mineNew = voted and st:New("vote:" .. tostring(mine))
  local otherNew = cast > 0 and st:New("cast" .. cast)
  local standing = (mineNew and mineAt) or (otherNew and #names) or nil
  -- The table, behind them.
  st:Tex("table", 130, 124, { w = 216, h = 7, color = SEAT, under = true })
  st:Tex("table.l", 30, 146, { w = 5, h = 44, color = SEAT_DARK, under = true })
  st:Tex("table.r", 230, 146, { w = 5, h = 44, color = SEAT_DARK, under = true })
  local box = medal(st, "box", UI.ICON.ballot, BOX_X, BOX_Y, 30)
  local ballot = st:Tex("ballot", BOX_X, BOX_Y - 6, { w = 12, h = 15, color = { 0.94, 0.9, 0.8 }, alpha = 0 })
  local n, caster = #names, nil
  for i, name in ipairs(names) do
    local x = 40 + (i - 0.5) * (190 / math.max(1, n))
    seat(st, "chair" .. i, x, 0.72)
    local a = st:Actor("v" .. i, name, x, 1, { size = 0.72, move = i ~= standing and "chair" or nil,
      low = n > 4 and i % 2 == 0 })
    if i == standing then caster = a end
  end
  for i = n + 1, Sc.TABLE_SHOWN do st:Leave("v" .. i) end
  if not voted then
    st:Actor("me", me, 262, 1, { size = 0.8 })
  else
    st:Leave("me")
  end
  if caster then
    st:Do(caster, "stand")
    st:Do(caster, "point", 0.25, "chair")
    local hx = caster.x
    local dx, dy = Sg.Offset(hx + 12, 120, BOX_X, BOX_Y - 6)
    V.Fly(ballot, dx, dy, 24, 0.55, 0.55, -40, true)
    V.Jolt(box, 2, 1.1)
  end
  st:Done()
end

-- The Mak'gora's title over the ring, by where it stands: challenged, on, the Guild Master stands, or its winner.
local function makTitle(s)
  if s.phase == "kept" then return L.AN_ALERT_MAK_GM_WON end
  if (s.phase == "handover" or s.phase == "handed") and s.winner then return L.AN_ALERT_MAK_WON:format(ns.Short(s.winner)) end
  if s.phase == "duel" or s.forced then return L.AN_ALERT_MAK_ACCEPTED end
  return L.AN_ALERT_MAK
end
Sc.MakTitle = makTitle

-- Leadership (Guild/Council.lua's motion s): the Mak'gora's two in the ring, the impeachment's winner on the throne.
function Sc.Lead(f, g, s)
  local mo = s.mo
  if mo.kind == "mak" then
    local st = f:Stage("stage", "ring")
    st:Scene("mak:" .. tostring(s.id))
    local play = (s.phase == "duel" or s.forced) and st:New("duel")
    local stillA, stillB = "ready", "ready"
    if s.phase == "kept" or s.phase == "handover" or s.phase == "handed" then
      local challengerWon = s.winner and P:Of(s.winner, g) == P:Of(mo.a, g)
      stillA, stillB = challengerWon and "cheer" or "kneel", challengerWon and "kneel" or "cheer"
    end
    local A, B = faceOff(st, mo.a, mo.gm, play, stillA, stillB)
    st:Text("title", makTitle(s), MID, 22, "GameFontNormalLarge")
    if play then
      st:Do(A, "roar", 0.7)
      st:Do(B, "roar", 0.8)
    end
    return st:Done()
  end
  if mo.kind == "lead" and s.phase == "vote" then return Sc.Seals(f, s) end
  if mo.kind ~= "lead" or not s.winner then return end
  local st = f:Stage("stage", "council")
  st:Scene("imp:" .. tostring(s.id))
  local play = st:New("passed")
  local throne = medal(st, "throne", UI.ICON.throne, MID, 64, 46)
  local a = st:Actor("winner", s.winner, MID, 1, { move = not play and "cheer" or nil })
  local others = {}
  for _, c in ipairs(s.cands or {}) do if c.name ~= s.winner and #others < 2 then others[#others + 1] = c.name end end
  for i, name in ipairs(others) do
    st:Actor("o" .. i, name, i == 1 and 64 or 256, i == 1 and 1 or -1, { size = 0.85, move = "applaud" })
  end
  if play then
    V.Drop(throne, 60, 0.5, 0.2)
    V.Burst(st.top, MID, 64, GOLD, 10, 0.7)
    st:Do(a, "cheer", 0.7)
  end
  st:Done()
end

-- An impeachment while its voters vote (the second check of 1 November): the scroll between the Guild Master and the
-- one who started it, a wax seal on it for each vote cast and an empty ring for each still to come; a new vote's seal
-- comes down.
Sc.SEALS_SHOWN = 8
function Sc.Seals(f, s)
  local mo = s.mo
  local st = f:Stage("stage", "council")
  st:Scene("impvote:" .. tostring(s.id))
  st:Tex("scroll", MID, 96, { round = true, w = 132, h = 116, color = { 0.92, 0.87, 0.74 } })
  for i = 1, 4 do st:Tex("line" .. i, MID, 52 + i * 12, { w = 92 - (i % 2) * 22, h = 3, color = { 0.6, 0.52, 0.36 }, sub = 1 }) end
  local cast, voters = s.cast or 0, math.max(s.n or 0, s.cast or 0)
  local shown = math.min(voters, Sc.SEALS_SHOWN)
  local fresh = cast > 0 and st:New("cast" .. cast)
  for i = 1, shown do
    local x = MID - (shown - 1) * 8 + (i - 1) * 16
    local sealed = i <= cast
    local t = st:Tex("seal" .. i, x, 132, { file = "Dot", size = 14, sub = 2,
      color = sealed and { 0.66, 0.1, 0.07 } or { 0.6, 0.52, 0.36, 0.4 } })
    if fresh and i == math.min(cast, shown) then V.Stamp(t, 0.2) end
  end
  st:Text("count", L.STAGE_SEALS:format(cast, voters), MID, 18, "GameFontNormal")
  st:Actor("gm", mo.gm, 44, 1, { size = 0.85 })
  local by = st:Actor("by", mo.a, 276, -1, { size = 0.85, move = not fresh and "point" or nil })
  if fresh then st:Do(by, "point", 0.1) end
  st:Done()
end

-- The guild court (Guild/Court.lua's case s; SPEC decision 74): the judge (who runs the case) on the high bench, the
-- jury seated on a bench in front (up to Sc.JURY_SHOWN), the accused standing. At the verdict the jurors stand in
-- turn, each calling "Guilty!" or "Not guilty!" on their line (who voted what shows only then), then the gavel comes
-- down and the judge calls the verdict over the accused.
Sc.JURY_SHOWN, Sc.CALL_GAP = 8, 0.5
local JUDGE_X, JUDGE_FLOOR = 150, 104
function Sc.Court(f, s)
  if s.verdict == "dismissed" then return end
  local cs = s.cs
  local st = f:Stage("stage", "council")
  st:Scene("court:" .. tostring(s.id))
  local closed = s.verdict ~= nil
  local play = closed and st:New("verdict", tonumber(cs.closed))
  local guilty = s.verdict == "guilty"
  local calls = s.calls or {}
  local jurors = {}
  for _, name in ipairs(s.jurors or {}) do
    if #jurors < Sc.JURY_SHOWN then jurors[#jurors + 1] = name end
  end
  local n, at = #jurors, 0.3
  local ends = at + n * Sc.CALL_GAP
  if play then st:Hold(ends + 1.4) end
  local busy = play or st:Held()
  -- The judge's high bench and its back, behind them; the gavel beside.
  st:Tex("dais", JUDGE_X, JUDGE_FLOOR + 7, { w = 112, h = 14, color = SEAT, under = true })
  st:Tex("back", JUDGE_X, JUDGE_FLOOR - 40, { w = 34, h = 58, color = SEAT_DARK, under = true })
  local judgeCall = closed and (guilty and L.STAGE_GUILTY_CALL or L.STAGE_NOT_GUILTY_CALL) or L.STAGE_JUDGE
  local judge = st:Actor("judge", cs.h, JUDGE_X, 1, { size = 0.72, floor = JUDGE_FLOOR, move = "bench",
    line = judgeCall, lineColor = closed and (guilty and RED or GREEN) or nil })
  local gavel = st:Tex("gavel", JUDGE_X + 44, JUDGE_FLOOR - 20, { icon = GAVEL, size = 26 })
  -- The jury's bench, in front.
  if n > 0 then st:Tex("bench", 106, Sg.FLOOR - 14, { w = 196, h = 5, color = SEAT, under = true }) end
  for i, name in ipairs(jurors) do
    local x = 20 + (i - 0.5) * (176 / n)
    local call = closed and calls[name] or nil
    local text = call and (call == "guilty" and L.STAGE_GUILTY_CALL or L.STAGE_NOT_GUILTY_CALL) or nil
    local a = st:Actor("j" .. i, name, x, 1, { size = 0.56, move = not busy and (call and "stand" or "chair") or nil,
      low = n > 4 and i % 2 == 0, line = text, lineColor = call == "guilty" and RED or GREEN })
    if play then
      st:Do(a, "chair")
      if call then
        local d = at + (i - 1) * Sc.CALL_GAP
        st:Do(a, "stand", d)
        st:Do(a, "point", d + 0.05, "stand")
        st:Say(a, text, call == "guilty" and RED or GREEN, d + 0.15)
      end
    end
  end
  for i = n + 1, Sc.JURY_SHOWN do st:Leave("j" .. i) end
  local still = closed and (guilty and "cry" or "cheer") or "stand"
  local a = st:Actor("accused", cs.to, 282, -1, { size = 0.82, move = not busy and still or nil, line = L.STAGE_ACCUSED })
  local verdict = st:Text("verdict", closed and (guilty and L.AN_ALERT_GUILTY or L.AN_ALERT_INNOCENT) or "", MID, 22,
    "GameFontNormalHuge", { color = guilty and RED or GREEN })
  if play then
    st:Do(a, "stand")
    st:Do(judge, "bench")
    V.Strike(gavel, ends)
    V.Burst(st.top, JUDGE_X + 44, JUDGE_FLOOR - 20, WHITE, 6, ends + 0.3)
    st:Say(judge, judgeCall, guilty and RED or GREEN, ends + 0.3)
    V.Stamp(verdict, ends + 0.4)
    st:Do(a, still, ends + 0.7)
  end
  st:Done()
end

-- The guild rules: when you accept them, you bow and the seal comes down on them.
-- The guild's new setup (the 1 Nov review): its emblem drops in beside the Guild Master, who cheers; a burst of gold.
function Sc.Setup(f, _, id)
  if not id then return end
  local st = f:Stage("stage", "council")
  st:Scene("setup:" .. tostring(id))
  local play = st:New("set")
  local gm = ns.Council.GM()
  local a = gm and st:Actor("gm", gm, 120, 1, { move = not play and "cheer" or nil })
  local m = medal(st, "emblem", UI.ICON[ns.Rules.ICON[id]] or UI.ICON.crown, 236, 78, 46)
  st:Text("name", L["SETUP_" .. id:upper()], 236, 126, "GameFontNormal")
  if play then
    V.Drop(m, 60, 0.5, 0.2)
    V.Burst(st.top, 236, 78, GOLD, 10, 0.7)
    if a then st:Do(a, "cheer", 0.6) end
  end
  st:Done()
end

-- The rules (the second check of 1 November): the first of them written on the parchment, and along its foot a wax seal
-- in each member's class colour for everyone who accepted this version ("7 of 20"). When you accept, you bow and
-- your seal comes down.
Sc.RULES_SHOWN, Sc.RULE_SEALS = 4, 10
function Sc.Rules(f, g)
  local c = g and g.charter
  if not c then return end
  local _, yes, all = ns.Council.Charter(g)
  local me = ns.Self()
  local ok = ((g.charterOk or {})[me] or 0) >= (c.v or 0)
  local st = f:Stage("stage", "council")
  st:Scene("rules:" .. tostring(c.v))
  st:Tex("paper", 108, 92, { round = true, w = 156, h = 150, color = { 0.92, 0.87, 0.74 } })
  local lines = {}
  for i, line in ipairs(c.lines or {}) do
    if i > Sc.RULES_SHOWN then break end
    lines[#lines + 1] = L.STAGE_RULE:format(i, line)
  end
  local text = st:Prop("text", function(over)
    local t = UI.Text(over, "GameFontBlackSmall", "LEFT")
    t:SetWidth(132)
    t:SetHeight(92)
    t:SetJustifyV("TOP")
    t:SetWordWrap(true)
    return t
  end)
  text:SetText(table.concat(lines, "\n"))
  st:At(text, 42, 24, "TOPLEFT")
  -- The seals: those who accepted, in their class colours (yours last, so it is the one that comes down).
  local names = {}
  for name, v in pairs(g.charterOk or {}) do
    if v >= (c.v or 0) and name ~= me then names[#names + 1] = name end
  end
  table.sort(names)
  if ok then names[#names + 1] = me end
  local shown = math.min(#names, Sc.RULE_SEALS)
  for i = 1, shown do
    local name = names[#names - shown + i]
    local x = 108 - (shown - 1) * 7 + (i - 1) * 14
    local seal = st:Tex("seal" .. i, x, 142, { file = "Dot", size = 12, color = classColor(name), sub = 2 })
    if name == me and st:New("ok") then V.Stamp(seal, 0.6) end
  end
  st:Text("count", L.STAGE_ACCEPTED:format(yes, all), 108, 162, "GameFontNormalSmall")
  local a = st:Actor("me", me, 248, -1, { line = ok and L.STAGE_ACCEPTED_LINE or nil })
  if ok and st:New("bow") then
    st:Do(a, "bow")
    st:Say(a, L.STAGE_ACCEPTED_LINE, nil, 0.9)
    V.Burst(st.top, 108, 142, GOLD, 8, 0.9)
  end
  st:Done()
end

---------------------------------------------------------------------------
-- The guild mascot (SPEC decision 75): the pet itself, the game's own creature of its kind, on the square
---------------------------------------------------------------------------
-- Creatures of each kind the game knows, two each: the second when the first does not draw.
Sc.PET = { boar = { 3098, 113 }, wolf = { 299, 69 }, murloc = { 46, 285 }, owl = { 1995, 1996 },
  raptor = { 3123, 3122 }, turtle = { 2408, 4142 } }
-- Its moves (the game's animation numbers): standing, eating, roaring at a new level, lying down when it sulks.
Sc.PET_MOVES = { stand = 0, eat = 61, roar = 55, sleep = 100 }
Sc.PET_WAIT = 2          -- seconds a creature has to draw before the next is tried
Sc.petDrawn = {}         -- kind -> true when the game drew it, false when neither did (the self-test reads it)
local PET_X, PET_W, PET_H = 140, 150, 128

local function petMove(m, move)
  if m.move == move then return end
  m.move = move
  local id = Sc.PET_MOVES[move] or 0
  if m.HasAnimation and not m:HasAnimation(id) then id = 0 end
  if m.SetAnimation then m:SetAnimation(id) end
end

-- Puts the creature of kind on model m, the first of its kind that draws; done(true or false).
local function petLoad(m, kind, done)
  local list, i = Sc.PET[kind] or Sc.PET.boar, 0
  local token = (m.loadToken or 0) + 1
  m.loadToken = token
  local function try()
    i = i + 1
    local id = list[i]
    if not id then return done(false) end
    m.drawn = nil
    if m.ClearModel then m:ClearModel() end
    m:SetCreature(id)
    C_Timer.After(Sc.PET_WAIT, function()
      if m.loadToken ~= token then return end
      local file = m.GetModelFileID and m:GetModelFileID()
      if m.drawn or (type(file) == "number" and file > 0) then done(true) else try() end
    end)
  end
  try()
end

function Sc.Mascot(f, m)
  local st = f:Stage("stage", "square")
  st:Scene("mascot")
  local floor = Sg.FLOOR
  local rest = m.mood == "sulking" and "sleep" or "stand"
  -- Its bowl, with this week's fish in it (up to five).
  st:Tex("bowl", PET_X + 92, floor - 4, { file = "Dot", w = 46, h = 14, color = { 0.42, 0.27, 0.13 } })
  for i = 1, 5 do
    local t = st:Tex("fish" .. i, PET_X + 76 + (i - 1) * 8, floor - 10 - (i % 2) * 3, { icon = UI.ICON.fish, size = 14, sub = 2 })
    t:SetShown(i <= m.week)
  end
  -- Hungry: it thinks of a fish; sulking: it sleeps.
  st:Tex("want", PET_X + 40, floor - 112, { icon = UI.ICON.fish, size = 20, alpha = 0.85 }):SetShown(m.mood == "hungry")
  st:Text("zzz", L.STAGE_ZZZ, PET_X + 44, floor - 96, "GameFontNormal"):SetShown(m.mood == "sulking")
  st:Text("name", m.name, PET_X, floor + 8, "GameFontNormal")
  -- The creature, or its medallion where the game cannot draw it.
  local still = st:Tex("medal", PET_X, floor - 44, { icon = UI.ICON.boar, size = 64 })
  local pet = st:Prop("pet", function(over)
    local mdl = CreateFrame("PlayerModel", nil, over)
    mdl:SetSize(PET_W, PET_H)
    mdl:SetScript("OnModelLoaded", function(self) self.drawn = true end)
    return mdl
  end)
  st:At(pet, PET_X, floor + 2, "BOTTOM")
  -- The moments: a new level (it roars), fish since you last looked (it eats).
  local up = m.level > 1 and st:New("lv" .. m.level, m.last) and "roar"
  local fed = m.fed > 0 and st:New("fed" .. m.fed, m.last) and "eat"
  local moment = up or fed
  local function show()
    pet:SetAlpha(pet.ok and 1 or 0)
    still:SetAlpha(pet.ok == false and 1 or 0)
    if not pet.ok then return end
    if pet.SetFacing then pet:SetFacing(m.mood == "sulking" and 2.4 or 0.6) end
    local now = pet.pending or moment
    pet.pending = nil
    if now then
      pet.move = nil
      petMove(pet, now)
      if now == "roar" then V.Burst(st.top, PET_X, floor - 70, GOLD, 12, 0.1) end
      st:After(now == "roar" and 1.8 or 2.6, function() petMove(pet, rest) end)
    else
      petMove(pet, rest)
    end
  end
  if pet.kind ~= m.kind then
    pet.kind, pet.ok, pet.move, pet.pending = m.kind, nil, nil, moment
    petLoad(pet, m.kind, function(ok)
      pet.ok = ok
      Sc.petDrawn[m.kind] = ok
      show()
    end)
    pet:SetAlpha(0)
    still:SetAlpha(0)
  else
    show()
  end
  st:Done()
end
