-- Getting started (SPEC decision 72), as Journey Together's Show me around (its UI/Walkthrough.lua): a tour of Guild Together
-- for your rank. A guide card beside the panel says what one part is for, with Back, Next and Skip the tour; that part
-- has a gold frame, and the rest of the bar and the panel is dimmed and cannot be clicked. The demo guild
-- (Dev/Demo.lua) fills the pages meanwhile: it is the self-test's pretend guild, so nothing is saved to your guild and
-- nothing is sent, and your own guild comes back after. The Guild Master's tour starts with a setup guide on their own
-- guild (the steps marked real: nothing is dimmed, so they can set it up as they go).
-- Offered once, the first time you open Guild Together; again from Getting started on Home and /gtf tour; and when your
-- rank goes up, a short tour of only what is new for you.
local _, ns = ...
local L, UI, Hall = ns.L, ns.UI, ns.Hall
local Tr = { on = false, i = 1, steps = {} }
ns.Tour = Tr

Tr.RANKS = { member = 1, officer = 2, gm = 3 }
Tr.DEMO_RANK = { member = 3, officer = 1, gm = 0 }   -- your rank in the demo guild, by the tour's (Dev/Sandbox.lua)
-- (330 wide: Skip the tour, Back and Next with room between them; at 300 Skip touched Back, the third check of
-- 1 November.)
Tr.CARD_W, Tr.GAP, Tr.EDGE = 330, 14, 5
local ALL = { member = true, officer = true, gm = true }
local LEAD = { officer = true, gm = true }
local GM = { gm = true }

local function pageFrame(id) return Hall.pages[id] and Hall.pages[id].frame end
local function mid(id) return function() local p = pageFrame(id) return p and p.right end end
local function feats() return Hall.G and Hall.G.chips and Hall.chipBox or Hall.rail end

-- The steps: the page and feature to show, what to frame (one frame, or two: from the first's top left to the
-- second's bottom right), which ranks see it, and what to set up first. real: on your own guild, before the demo
-- (the Guild Master's setup guide); first: the demo guild starts here. Texts: TOUR_<ID>_T and TOUR_<ID> (or
-- TOUR_<ID>_<RANK> for one rank).
Tr.STEPS = {
  { id = "SETUP", ranks = GM, real = true, page = "settings", feat = "setup", target = function() return pageFrame("settings") end },
  { id = "MARKS", ranks = GM, real = true, page = "settings", feat = "general", target = function() return pageFrame("settings") end },
  { id = "TAX", ranks = GM, real = true, page = "settings", feat = "tax", target = function() return pageFrame("settings") end },
  { id = "WHO", ranks = GM, real = true, page = "settings", feat = "who", target = function() return pageFrame("settings") end },
  { id = "FEATURES", ranks = GM, real = true, page = "settings", feat = "features",
    target = function() return pageFrame("settings") end },
  { id = "INTRO", ranks = ALL, first = true },
  { id = "BAR", ranks = ALL, page = "home", feat = "waiting", target = function() return Hall.bar end },
  { id = "FEATS", ranks = ALL, page = "home", feat = "waiting", target = feats },
  { id = "LIST", ranks = ALL, page = "home", feat = "waiting", target = mid("home") },
  { id = "CHALLENGES", ranks = ALL, page = "arena", feat = "duels", target = mid("arena") },
  { id = "SIDE", ranks = ALL, page = "arena", feat = "duels", target = function() return ns.Side.frame end,
    before = function(page)
      local g, name = ns.GuildData:Current(), ns.Peers and ns.Peers:Full("Korgath")
      if g and name then page.View({ kind = "player", key = ns.Players:Of(name, g) }) end
    end },
  { id = "GAMES", ranks = ALL, page = "games", feat = "game", target = mid("games") },
  { id = "GAMBLING", ranks = ALL, page = "tavern", feat = "deathroll", target = mid("tavern") },
  { id = "TREASURY", ranks = ALL, page = "treasury", feat = "debts", target = mid("treasury") },
  { id = "PROFESSIONS", ranks = ALL, page = "professions", feat = "find", target = mid("professions") },
  { id = "PUNISH", ranks = ALL, page = "stocks", feat = "serving", target = mid("stocks") },
  { id = "COUNCIL", ranks = ALL, page = "council", feat = "charter", target = mid("council") },
  { id = "CALENDAR", ranks = ALL, page = "calendar", feat = "events", target = mid("calendar") },
  { id = "OFFICERS", ranks = LEAD, page = "home", feat = "waiting", target = function() return Hall.bar end },
  { id = "OPTIONS", ranks = ALL, page = "home", feat = "options", target = mid("home") },
  { id = "DONE", ranks = ALL },
}
local UNCOUNTED = { INTRO = true, NEW = true, DONE = true }

-- Your rank for the tours: "gm", "officer" or "member" (nil outside a guild). Not from the pretend guild.
function Tr:MyRank()
  local D, R = ns.GuildData, ns.Roster
  if ns.Sandbox and ns.Sandbox.active then return nil end
  local r = R:Rank(ns.Self())
  if r == nil then return nil end
  if r == 0 then return "gm" end
  for _, x in ipairs(R:Ranks()) do
    if x.index == r and D.Officer(x, D:Settings()) then return "officer" end
  end
  return "member"
end

-- The steps of a tour: every step of that rank, or (since = an earlier rank) only what is new since that rank.
function Tr:Steps(rank, since)
  local out = {}
  for _, s in ipairs(self.STEPS) do
    local new = not since or not s.ranks[since] or s.id == "DONE"
    if s.ranks[rank] and new and not (since and s.id == "INTRO") then out[#out + 1] = s end
  end
  if since then
    -- The short tour: what is new opens it (and starts the demo guild when a step after it needs it).
    local at = 1
    while out[at] and out[at].real do at = at + 1 end
    table.insert(out, at, { id = "NEW", ranks = ALL, first = true })
  end
  return out
end

local function text(step, rank, part)
  local key = "TOUR_" .. step.id .. (part or "")
  local own = key .. "_" .. rank:upper()
  return rawget(L, own) or L[key]
end
Tr.Text = text

---------------------------------------------------------------------------
-- The card, the veil and the gold frame
---------------------------------------------------------------------------
local function build()
  if Tr.card then return end
  local parent = Hall.bar:GetParent()
  -- The veil: over the bar and the panel, dark around a window where the framed part is; it keeps them from clicks.
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", Hall.bar, "TOPLEFT")
  v:SetPoint("BOTTOMRIGHT", Hall.frame, "BOTTOMRIGHT")
  v:SetFrameStrata(Hall.frame:GetFrameStrata())
  v:SetFrameLevel(Hall.frame:GetFrameLevel() + 200)
  v:EnableMouse(true)
  v:EnableMouseWheel(true)
  v:SetScript("OnMouseWheel", function() end)
  v.parts = {}
  for i = 1, 4 do
    local t = v:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0, 0, 0, 0.6)
    v.parts[i] = t
  end
  v:Hide()
  Tr.veil = v
  -- The gold frame around the part, softly glowing.
  local gf = CreateFrame("Frame", nil, parent)
  gf:SetFrameStrata(Hall.frame:GetFrameStrata())
  gf:SetFrameLevel(v:GetFrameLevel() + 10)
  local gold = UI.LOOK.gold
  UI.Glass(gf, { 0, 0, 0, 0 }, { gold[1], gold[2], gold[3], 1 })
  gf.light = gf:CreateTexture(nil, "BACKGROUND")
  gf.light:SetTexture(ns.MEDIA .. "Glow")
  gf.light:SetBlendMode("ADD")
  gf.light:SetVertexColor(gold[1], gold[2], gold[3], 0.5)
  gf.light:SetPoint("TOPLEFT", -18, 18)
  gf.light:SetPoint("BOTTOMRIGHT", 18, -18)
  gf.breathe = UI.Visuals.Breathe(gf.light)
  gf:Hide()
  Tr.glow = gf
  -- The card.
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(Tr.CARD_W, 160)
  c:SetFrameStrata("FULLSCREEN_DIALOG")
  c:SetClampedToScreen(true)
  c:EnableMouse(true)
  UI.Glass(c, { 0.045, 0.04, 0.035, 0.99 }, { gold[1], gold[2], gold[3], 0.9 })
  c.kicker = UI.Color(UI.Text(c, "GameFontNormalSmall"), "gold")
  c.kicker:SetPoint("TOPLEFT", 14, -12)
  c.count = UI.Color(UI.Text(c, "GameFontNormalSmall", "RIGHT"), "gold")
  c.count:SetPoint("TOPRIGHT", -14, -12)
  -- Progress: a thin line, filled up to this step.
  c.track = c:CreateTexture(nil, "ARTWORK")
  c.track:SetColorTexture(gold[1], gold[2], gold[3], 0.25)
  c.track:SetPoint("TOPLEFT", 14, -28)
  c.track:SetPoint("TOPRIGHT", -14, -28)
  c.track:SetHeight(3)
  c.fill = c:CreateTexture(nil, "OVERLAY")
  c.fill:SetColorTexture(gold[1], gold[2], gold[3], 1)
  c.fill:SetPoint("TOPLEFT", c.track, "TOPLEFT")
  c.fill:SetHeight(3)
  c.title = UI.Color(UI.Wrap(c, "GameFontNormalLarge", Tr.CARD_W - 28), "goldHi")
  c.title:SetPoint("TOPLEFT", 14, -40)
  c.text = UI.Wrap(c, "GameFontHighlight", Tr.CARD_W - 28)
  c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -6)
  c.wait = UI.Ink(UI.Text(c, "GameFontDisableSmall"))
  c.next = UI.Button(c, L.TOUR_NEXT, 96, function() Tr:Next() end)
  c.back = UI.Button(c, L.TOUR_BACK, 80, function() Tr:Back() end, true)
  c.skip = UI.Button(c, L.TOUR_SKIP, 110, function() Tr:Stop() end, true)
  c:Hide()
  Tr.card = c
end

-- The veil around the gold frame (h), or over everything (h nil).
local function shade(h)
  local v = Tr.veil
  local p = v.parts
  for _, t in ipairs(p) do t:ClearAllPoints() end
  if not h then
    p[1]:SetAllPoints(v)
    for i = 2, 4 do p[i]:Hide() end
    p[1]:Show()
    v:Show()
    return
  end
  -- Above, below, left of and right of the frame.
  p[1]:SetPoint("TOPLEFT", v, "TOPLEFT"); p[1]:SetPoint("TOPRIGHT", v, "TOPRIGHT"); p[1]:SetPoint("BOTTOM", h, "TOP")
  p[2]:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT"); p[2]:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT"); p[2]:SetPoint("TOP", h, "BOTTOM")
  p[3]:SetPoint("LEFT", v, "LEFT"); p[3]:SetPoint("TOP", h, "TOP"); p[3]:SetPoint("BOTTOM", h, "BOTTOM"); p[3]:SetPoint("RIGHT", h, "LEFT")
  p[4]:SetPoint("RIGHT", v, "RIGHT"); p[4]:SetPoint("TOP", h, "TOP"); p[4]:SetPoint("BOTTOM", h, "BOTTOM"); p[4]:SetPoint("LEFT", h, "RIGHT")
  for _, t in ipairs(p) do t:Show() end
  v:Show()
end

-- The gold frame around first (to last's bottom right). False when there is nothing to frame.
local function frame(first, last)
  local gf = Tr.glow
  gf:ClearAllPoints()
  if not (first and first:IsVisible()) then
    gf:Hide()
    gf.breathe:Stop()
    return false
  end
  gf:SetPoint("TOPLEFT", first, "TOPLEFT", -Tr.EDGE, Tr.EDGE)
  gf:SetPoint("BOTTOMRIGHT", last or first, "BOTTOMRIGHT", Tr.EDGE, -Tr.EDGE)
  gf:Show()
  if UI.Motion() then gf.breathe:Play() end
  return true
end

-- The card left of the bar and the panel, level with the framed part (the scenes play on the right, UI/Side.lua);
-- clamped to the screen. Without a frame: over the middle of the panel.
local function place()
  local c, area = Tr.card, Tr.veil
  c:ClearAllPoints()
  local gf = Tr.glow
  if not gf:IsShown() then
    c:SetPoint("CENTER", Hall.frame, "CENTER", 0, 30)
    return
  end
  local top, at = area:GetTop(), gf:GetTop()
  local dy = (top and at) and math.max(0, top - at) or 0
  c:SetPoint("TOPRIGHT", area, "TOPLEFT", -Tr.GAP, -dy)
end

local function fill(step, n, of, rank)
  local c = Tr.card
  c.kicker:SetText(L["TOUR_" .. rank:upper()]:upper())
  c.count:SetText(n and L.TOUR_COUNT:format(n, of) or "")
  c.track:SetShown(n ~= nil)
  c.fill:SetShown(n ~= nil)
  if n then c.fill:SetWidth(math.max(3, (Tr.CARD_W - 28) * n / of)) end
  c.title:SetText(text(step, rank, "_T"))
  c.text:SetText(text(step, rank))
  local h = 40 + (c.title:GetStringHeight() or 16) + 6 + (c.text:GetStringHeight() or 30) + 14
  c.wait:ClearAllPoints()
  c.wait:SetPoint("TOPLEFT", 14, -h)
  if c.wait:IsShown() then h = h + 16 end
  c.next:ClearAllPoints()
  c.next:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -h)
  c.back:ClearAllPoints()
  c.back:SetPoint("RIGHT", c.next, "LEFT", -6, 0)
  c.skip:ClearAllPoints()
  c.skip:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -h)
  c:SetHeight(h + 22 + 14)
end

---------------------------------------------------------------------------
-- The demo guild (Dev/Demo.lua), filled in the background: its waits are timers here, as the self-test's are.
---------------------------------------------------------------------------
local Wait = {}
Wait.__index = Wait
function Wait:Wait(sec) coroutine.yield(sec or 0) end
function Wait:Until(fn, timeout)
  local waited = 0
  while not fn() and waited < (timeout or 5) do
    self:Wait(0.1)
    waited = waited + 0.1
  end
  return fn()
end

function Tr:Demo()
  local SB = ns.Sandbox
  if SB.active then
    -- (The self-test's demo guild, left open: the tour uses it and leaves it open.)
    self.ready, self.ownDemo = SB.demo == true, false
    if self.ready then self:AsRank() end
    return
  end
  self.ready, self.ownDemo, self.filling = false, true, true
  local co = coroutine.create(function() return ns.Demo.Fill(setmetatable({}, Wait)) end)
  local function go(arg)
    local ok, v = coroutine.resume(co, arg)
    if not ok then
      self.filling = false
      ns:Print(L.TOUR_DEMO_BAD:format(tostring(v)), true)
      self:Stop()
      return
    end
    if coroutine.status(co) ~= "dead" then
      C_Timer.After(type(v) == "number" and v or 0, function() go() end)
      return
    end
    self.filling = false
    -- Skipped while it filled: put your own guild back now.
    if not self.on then return ns.Demo.Off() end
    self:AsRank()
    self.ready = true
    if self.steps[self.i] and self.steps[self.i].first then self:Go(self.i) end
  end
  go()
end

-- You, in the demo guild, with the tour's rank (put back at the end).
function Tr:AsRank()
  local R = ns.Roster
  if not R.pretend then return end
  local me = ns.Self()
  if self.savedRank == nil then self.savedRank = R.pretend.ranks[me] or false end
  R.pretend.ranks[me] = self.DEMO_RANK[self.rank] or 3
  ns:Fire("ROSTER")
end

---------------------------------------------------------------------------
-- Running a tour
---------------------------------------------------------------------------
-- rank: the tour's rank (default: yours); since: only what is new since that rank (after a promotion). False when the
-- guild window is closed (the panel lives under it) or the self-test runs.
function Tr:Start(rank, since)
  if (ns.SelfTest and ns.SelfTest.running and not self.testing) or not Hall.frame then return false end
  if not Hall:IsOpen() and not Hall:Open("home") then
    ns:Print(L.TOUR_OPEN_FIRST, true)
    return false
  end
  rank = rank or self:MyRank() or "member"
  if Hall:IsFull() then Hall:Full(false) end
  -- The welcome card stands over Home's first list, not over whatever was open last (shot 13 of the third check of
  -- 1 November: Your options behind it).
  Hall:ShowFeature("home", "waiting")
  build()
  self.rank, self.since = rank, since
  self.steps = self:Steps(rank, since)
  self.offer, self.on, self.ready, self.savedRank = nil, true, false, nil
  self.card.next:SetText(L.TOUR_NEXT)
  self.card.back:SetText(L.TOUR_BACK)
  self:Go(1)
  return true
end

local function visible(id)
  for _, v in ipairs(Hall:Visible()) do if v == id then return true end end
  return false
end

function Tr:Go(i, dir)
  if not self.on then return end
  dir = dir or 1
  local step = self.steps[i]
  if not step then return self:Stop(true) end
  if step.first and not self.ready and not self.filling then self:Demo() end
  -- A page switched off in this guild: its step is skipped.
  if step.page and (step.real or self.ready) and not visible(step.page) then return self:Go(i + dir, dir) end
  self.i = i
  -- What the last step opened on a page goes.
  if self.viewed then
    self.viewed.view = nil
    self.viewed = nil
  end
  ns.Side.over = nil
  if step.page then
    Hall:ShowFeature(step.page, step.feat)
    local page = pageFrame(step.page)
    if step.before and page then
      step.before(page)
      self.viewed = page
    end
    Hall:Refresh()
  end
  local first, last
  if step.target and (step.real or self.ready) then first, last = step.target() end
  local framed = frame(first, last)
  if step.real then self.veil:Hide() else shade(framed and self.glow or nil) end
  local count, of = 0, 0
  for k, s in ipairs(self.steps) do
    if not UNCOUNTED[s.id] then
      of = of + 1
      if k <= i then count = count + 1 end
    end
  end
  local c = self.card
  -- The demo guild being filled: Next waits for it.
  local waiting = step.first and not self.ready
  c.wait:SetShown(step.first == true)
  c.wait:SetText(waiting and L.TOUR_LOADING or L.TOUR_READY)
  fill(step, not UNCOUNTED[step.id] and count or nil, of, self.rank)
  c.next:SetText(step.id == "DONE" and L.TOUR_FINISH or L.TOUR_NEXT)
  c.next:SetEnabled(not waiting)
  -- (No way back from the demo guild into the setup on your own guild.)
  c.back:SetShown(i > 1 and not step.first)
  c.skip:SetShown(step.id ~= "DONE")
  c:Show()
  place()
  -- Placed again once the frames have their final positions.
  C_Timer.After(0, function() if Tr.on then place() end end)
end

function Tr:Next()
  if self.offer then return self:Start(self.offer.rank, self.offer.since) end
  self:Go(self.i + 1, 1)
end

function Tr:Back()
  if self.offer then return self:Later() end
  self:Go(math.max(1, self.i - 1), -1)
end

-- Ends the tour (done = it went to the end): the demo guild goes, and your own guild shows again on Home.
function Tr:Stop(done)
  local was = self.on
  self.on, self.offer = false, nil
  if self.card then self.card:Hide() end
  if self.glow then
    self.glow:Hide()
    self.glow.breathe:Stop()
  end
  if self.veil then self.veil:Hide() end
  if self.viewed then
    self.viewed.view = nil
    self.viewed = nil
  end
  if not was then return end
  local R = ns.Roster
  if self.savedRank ~= nil and R.pretend then
    R.pretend.ranks[ns.Self()] = self.savedRank or nil
    ns:Fire("ROSTER")
  end
  self.savedRank = nil
  if self.ownDemo and not self.filling then ns.Demo.Off() end
  self.ownDemo = nil
  if ns.db then
    ns.db.tour = type(ns.db.tour) == "table" and ns.db.tour or {}
    ns.db.tour[self.rank or "member"] = done and "done" or "skipped"
  end
  if Hall:IsOpen() then Hall:ShowFeature("home", "waiting") end
end

---------------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------------
-- The card alone: "Show me around?" with Show me around / Later.
function Tr:Offer(rank, since)
  if self.on or not Hall:IsOpen() then return false end
  build()
  self.offer = { rank = rank, since = since }
  self.rank = rank
  local c = self.card
  c.wait:Hide()
  fill({ id = since and "OFFER_NEW" or "OFFER" }, nil, 1, rank)
  c.next:SetText(L.TOUR_START)
  c.next:SetEnabled(true)
  c.back:SetText(L.TOUR_LATER)
  c.back:Show()
  c.skip:Hide()
  self.glow:Hide()
  self.veil:Hide()
  c:Show()
  place()
  return true
end

function Tr:Later()
  local rank = self.offer and self.offer.rank or self.rank or "member"
  self.offer = nil
  if self.card then
    self.card:Hide()
    self.card.back:SetText(L.TOUR_BACK)
  end
  if ns.db then
    ns.db.tour = type(ns.db.tour) == "table" and ns.db.tour or {}
    ns.db.tour[rank] = ns.db.tour[rank] or "later"
  end
end

-- The first time you open Guild Together: once per rank (for the account: one player is one player).
function Tr:OfferOnce()
  local rank = self:MyRank()
  local seen = ns.db and type(ns.db.tour) == "table" and ns.db.tour or {}
  if not rank or next(seen) ~= nil then return false end
  return self:Offer(rank)
end

-- Your rank went up (a member made officer, an officer made Guild Master): a short tour of what is new, when a tour
-- of a lower rank was seen.
function Tr:CheckPromotion()
  local rank = self:MyRank()
  local seen = ns.db and type(ns.db.tour) == "table" and ns.db.tour
  if self.on or self.offer or not rank or not seen or seen[rank] then return false end
  local best
  for r in pairs(seen) do
    if self.RANKS[r] and self.RANKS[r] < self.RANKS[rank] and (not best or self.RANKS[r] > self.RANKS[best]) then best = r end
  end
  if not best then return false end
  seen[rank] = "offered"
  return self:Offer(rank, best)
end

-- The panel opened (UI/Hall.lua): a first tour, or the short one after a promotion. Never during the self-test or
-- while the pretend guild is open.
function Tr:Opened()
  if self.on or (ns.SelfTest and ns.SelfTest.running) or (ns.Sandbox and ns.Sandbox.active) then return end
  C_Timer.After(0.6, function()
    if Hall:IsOpen() and not (ns.Sandbox and ns.Sandbox.active) then
      if not self:OfferOnce() then self:CheckPromotion() end
    end
  end)
end

ns:On("ROSTER", function()
  if Tr.on or not Hall:IsOpen() then return end
  C_Timer.After(0.5, function() Tr:CheckPromotion() end)
end)
