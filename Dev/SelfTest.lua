-- /gtf test: checks in the game, by itself, what one client can check (docs/ROADMAP.md in-game checks), and the
-- paths that normally need several players with a pretend guild (Dev/Sandbox.lua, Dev/Peers.lua). Nothing is sent to
-- other players except two tiny test messages (a whisper to yourself, one guild addon message nobody shows).
-- Run it with the guild window open on your guild to include the window checks.
-- The report goes to GuildTogetherForeverDB.selftest; it reaches the disk with the next /reload or logout.
local _, ns = ...
local L = ns.L
local D, R, Hall, SB, Pe = ns.GuildData, ns.Roster, ns.Hall, ns.Sandbox, ns.Peers
local P = ns.Players
local ST = {}
ns.SelfTest = ST

local function report() return ns.db.selftest end
-- In the game (not the unit-test harness): taint and drawn positions can be read.
local function inGame() return issecurevariable ~= nil end
local function windowOpen() return Hall.frame ~= nil and Hall:GuildShown() end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Checks inside a step: each records its own line; a step fails when any check failed.
---------------------------------------------------------------------------
local Check = {}
Check.__index = Check
function Check:That(cond, what)
  self.lines[#self.lines + 1] = (cond and "ok: " or "FAIL: ") .. what
  if not cond then self.bad = true end
  return cond
end
function Check:Eq(got, want, what) return self:That(got == want, ("%s (got %s, want %s)"):format(what, tostring(got), tostring(want))) end
function Check:Note(text) self.lines[#self.lines + 1] = "note: " .. text end
function Check:Skip(why) self.skip = why end
-- Keeps Guild Together's chat lines out of the chat for the rest of the step (the third check of 1 November: the face to
-- face step said "go near" four times); they come back when the step ends.
function Check:Hush()
  if self.realPrint then return end
  self.realPrint = ns.Print
  ns.Print = function() end
end
-- Lets time pass (the step goes on in a later frame).
function Check:Wait(sec) coroutine.yield(sec or 0) end
-- Waits until fn() is true, at most timeout seconds. Returns fn().
function Check:Until(fn, timeout)
  local waited = 0
  while not fn() and waited < (timeout or 5) do
    self:Wait(0.1)
    waited = waited + 0.1
  end
  return fn()
end

local steps = {}
ST.steps = steps
local function step(name, fn) steps[#steps + 1] = { name = name, fn = fn } end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
step("the game: version, guild and functions", function(c)
  local env = report().env
  local version, build, _, toc = GetBuildInfo()
  env.addon, env.client, env.toc, env.forever = ns.VERSION or "dev", tostring(version) .. "." .. tostring(build), toc, ns.IsForever()
  env.guild, env.rank = ns.Guild()
  env.trial = ns.Trial and ns.Trial() or false
  local apis = {
    SendAddonMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage, InChatMessagingLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown,
    GetGuildRosterInfo = GetGuildRosterInfo, GuildControlGetRankName = GuildControlGetRankName, GetGuildClubId = C_Club and C_Club.GetGuildClubId,
    hooksecurefunc = hooksecurefunc, issecretvalue = issecretvalue, GuildMicroButton = GuildMicroButton,
  }
  env.apis = {}
  for k, v in pairs(apis) do env.apis[k] = v ~= nil end
  c:That(apis.SendAddonMessage ~= nil, "addon messages can be sent")
  c:That(apis.GetGuildRosterInfo ~= nil and apis.GuildControlGetRankName ~= nil, "the guild roster and rank names can be read")
  c:That(apis.hooksecurefunc ~= nil, "Blizzard functions can be observed")
  local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
  if registered then c:That(registered(ns.PREFIX), "the GTF prefix is registered") end
  c:Note(("client %s (interface %s, %s), Guild Together %s"):format(env.client, tostring(toc), env.forever and "Forever" or "retail", env.addon))
  if env.trial then c:Note("a trial or veteran account: Forever does not send its addon messages") end
end)

step("art: every header picture loads", function(c)
  if not inGame() then c:Skip("pictures are only checked in the game") return end
  local t = UIParent:CreateTexture()
  local missing = {}
  -- Each place's header painting, Alliance and Horde (UI/Hall.lua), the emblem, the icon atlases and the shapes.
  local names = { "Emblem", "EmblemSmall", "Icons", "IconsHorde", "Glass", "Edge", "Glow", "Ring", "Dot", "Tick",
    "Chevron", "WindowFrame" }
  for _, pl in ipairs(Hall.PLACES) do
    local name = pl.id:sub(1, 1):upper() .. pl.id:sub(2)
    names[#names + 1] = "Head" .. name
    names[#names + 1] = "Horde" .. name
  end
  for _, name in ipairs(names) do
    if t:SetTexture(ns.MEDIA .. name) == false then missing[#missing + 1] = name end
  end
  t:Hide()
  c:Note("the Settings gear: " .. select(2, ns.UI.Gear(14)))
  c:That(#missing == 0, #missing == 0 and ("our " .. #names .. " pictures load")
    or ("missing: " .. table.concat(missing, ", ")))
end)

-- The guild window's own textures our panes are drawn with, and the icons of our rows (UI/Widgets.lua).
local function hasFile(t, path)
  if GetFileIDFromPath and GetFileIDFromPath(path) == nil then return false end
  return t:SetTexture(path) ~= false
end
step("art: the guild window's textures and our icons load", function(c)
  if not inGame() then c:Skip("pictures are only checked in the game") return end
  local t = UIParent:CreateTexture()
  local missing, n = {}, 0
  for key, tex in pairs(ns.UI.TEX) do
    n = n + 1
    if not hasFile(t, tex[1]) then missing[#missing + 1] = key .. " (" .. tex[1] .. ")" end
  end
  -- (The painted ones are cells of the atlas, checked above.)
  for key, path in pairs(ns.UI.ICON) do
    if not ns.UI.Cell(path) then
      n = n + 1
      if not hasFile(t, path) then missing[#missing + 1] = key .. " (" .. path .. ")" end
    end
  end
  -- The games' pictures (UI/Visuals.lua).
  for set, list in pairs({ picture = ns.UI.Visuals.TEX }) do
    for key, path in pairs(list) do
      n = n + 1
      if not hasFile(t, path) then missing[#missing + 1] = set .. " " .. key .. " (" .. path .. ")" end
    end
  end
  t:Hide()
  table.sort(missing)
  c:That(#missing == 0, #missing == 0 and (n .. " textures and icons load") or ("missing: " .. table.concat(missing, ", ")))
end)

-- Which of the game's templates this client has. Our controls are our own (SPEC decision 53); these few remain.
ST.TEMPLATES = {
  { "Frame", "BackdropTemplate" }, { "Cooldown", "CooldownFrameTemplate" }, { "Button", "SecureActionButtonTemplate" } }
step("templates: the game's controls we use", function(c)
  -- (Probed once per session: frames cannot be removed again.)
  if not ST.probed then
    local has, missing = {}, {}
    for _, t in ipairs(ST.TEMPLATES) do
      local ok, f = pcall(CreateFrame, t[1], nil, UIParent, t[2])
      if ok and f then f:Hide(); has[#has + 1] = t[2] else missing[#missing + 1] = t[2] end
    end
    ST.probed = { has = has, missing = missing }
  end
  local has, missing = ST.probed.has, ST.probed.missing
  report().templates = ST.probed
  c:That(#missing == 0, #missing == 0 and "all " .. #has .. " exist" or ("missing: " .. table.concat(missing, ", ")))
end)

step("roster: ranks and members", function(c)
  if not ns.Guild() then c:Skip("not in a guild") return end
  R:Ask()
  c:Until(function() return R.ready end, 5)
  c:That(R.ready, "the roster has arrived")
  local total, _, online = GetNumGuildMembers()
  local listed = count(R.ranks)
  report().env.roster = { total = total, online = online, listed = listed }
  c:That(R:Rank(ns.Self()) ~= nil, "my own rank is known")
  c:That(#R:Ranks() >= 1, #R:Ranks() .. " ranks below the Guild Master")
  -- Ops from members who have logged off are checked by their rank: they must be in the roster too.
  c:That(listed >= (total or 0), ("the roster lists offline members too (%d of %d listed, %s online)"):format(listed, total or 0, tostring(online)))
end)

-- Two test messages, both only to this client: a whisper to myself, and one guild message (the game echoes it).
ST.pings = nil
ns.Comm:On("PING", function(sender) if ST.pings and sender == ns.Self() then ST.pings.WHISPER = true end end)
ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
  if not ST.pings or (issecretvalue and (issecretvalue(prefix) or issecretvalue(msg) or issecretvalue(sender))) then return end
  if prefix == ns.PREFIX and channel == "GUILD" and type(msg) == "string" and msg:sub(1, 5) == "PING:" and ns.FullName(sender) == ns.Self() then
    ST.pings.GUILD = true
  end
end)
step("addon messages: sent and received", function(c)
  if ns.Comm:Held() then c:Skip("addon messages are held right now (instance, encounter or lockdown)") return end
  ST.pings = {}
  ns.Comm:Send(ns.Self(), "PING", { t = time() })
  local guild = IsInGuild()
  if guild then ns.Comm:Send(ns.Comm.GUILD, "PING", { t = time() }) end
  c:Until(function() return ST.pings.WHISPER and (not guild or ST.pings.GUILD) end, 8)
  c:That(ST.pings.WHISPER, "a whisper to myself arrives")
  if guild then c:That(ST.pings.GUILD, "a guild addon message goes out and comes back") end
  -- While the game holds addon messages (a dungeon, a boss, a lockdown), ours wait in the queue, and go after.
  ST.pings = {}
  local C = ns.Comm
  C.lockedUntil = GetTime() + 2
  C:Send(ns.Self(), "PING", { t = time() })
  c:Wait(1)
  local _, by = C:Pending()
  c:That((by[ns.Self()] or 0) > 0 and not ST.pings.WHISPER, "a message waits while messages are held")
  c:That(c:Until(function() return ST.pings.WHISPER end, 8), "and goes once they are allowed again")
  ST.pings = nil
end)

step("key binding: Open Guild Together", function(c)
  local b = ns.openButton
  if not GuildMicroButton then c:That(false, "the game has no GuildMicroButton: the key cannot open the window") return end
  c:That(b ~= nil, "the secure open button exists")
  if not b then return end
  c:Eq(b:GetAttribute("type"), "click", "it clicks")
  c:That(b:GetAttribute("clickbutton") == GuildMicroButton, "the game's guild button")
  local key = GetBindingKey and GetBindingKey("CLICK GTFOpenButton:LeftButton")
  c:Note(key and ("bound to " .. key) or "no key set (Key Bindings, AddOns, Guild Together)")
end)

---------------------------------------------------------------------------
-- The guild window (needs the window open on the guild)
---------------------------------------------------------------------------
-- Blizzard fields that our code tainted: the window's own and its child frames' (one level down).
function ST:Tainted()
  if not issecurevariable or not CommunitiesFrame then return nil end
  local bad, seen = {}, {}
  local function scan(t, path, depth)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(k) == "string" then
        local secure, by = issecurevariable(t, k)
        if not secure and by == ns.ADDON then bad[#bad + 1] = path .. k end
        if depth > 0 and type(v) == "table" and type(rawget(v, 0)) == "userdata" then scan(v, path .. k .. ".", depth - 1) end
      end
    end
  end
  scan(CommunitiesFrame, "CommunitiesFrame.", 1)
  local secure, by = issecurevariable("CommunitiesFrame")
  if not secure and by == ns.ADDON then bad[#bad + 1] = "CommunitiesFrame" end
  return bad
end

local function noTaint(c, when)
  local bad = ST:Tainted()
  if not bad then c:Note("taint is only checked in the game") return end
  c:That(#bad == 0, #bad == 0 and ("nothing in the guild window is tainted by us " .. when)
    or ("tainted by us " .. when .. ": " .. table.concat(bad, ", ", 1, math.min(#bad, 8))))
end

local function rect(f)
  if not f or not f.GetLeft or not f:GetLeft() then return nil end
  local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return { left = math.floor(f:GetLeft() * s + 0.5), right = math.floor(f:GetRight() * s + 0.5),
    top = math.floor(f:GetTop() * s + 0.5), bottom = math.floor(f:GetBottom() * s + 0.5) }
end

-- Without a guild: the window open on a community of your own will do (Hall.practice), with the pretend guild's data.
local function practiceReady()
  local f = CommunitiesFrame
  return Hall.frame ~= nil and not ns.Guild() and f ~= nil and f:IsShown() and f.GetSelectedClubId ~= nil
    and f:GetSelectedClubId() ~= nil
end

-- The one frame (SPEC decisions 58 and 59): the window in the middle, scaled with the bar and the panel to fit between
-- the screen's top and the action bars; the bar joined under it, the panel under the bar (or beside a plain window).
step("window: the bar, the panel and the one frame", function(c)
  if not windowOpen() and practiceReady() then
    Hall.practice = true
    SB:Start()
    Hall:Place()
    c:Note("not in a guild: checked on the community that is open, with the pretend guild")
  end
  if not windowOpen() then
    c:Skip("open the guild window on your guild (without a guild: on a community of yours) and run /gtf test again for the window checks")
    return
  end
  local Fr = ns.Frame
  Hall:Close()
  noTaint(c, "before")
  c:That(Hall.bar:IsShown(), "the Guild Together bar shows under the window")
  if Fr:Dressed() then
    c:That(Fr.built == true, "the one frame is drawn around the window and the bar")
    c:Note(("the window dressed: %d of %d of its parts found (border, portrait, title, background)"):format(Fr.found or 0,
      #Fr.HIDE + 1))
    local s = Fr:Scale()
    c:That(math.abs((CommunitiesFrame:GetScale() or 1) - s) < 0.01,
      ("the column is scaled to fit the screen: %d%%"):format(s * 100 + 0.5))
  else
    c:Note("Dress the guild window is off: the game's own window, the panel beside it")
  end
  Hall.tab:Click()
  c:That(Hall:IsOpen(), "a click on Guild Together opens the panel")
  -- The guild's name once, in the window's title band: not again in the bar (the third check of 1 November).
  local named = false
  for _, r in ipairs({ Hall.tab:GetRegions() }) do
    if r.GetText and ns.Guild() and r:GetText() == ns.Guild() then named = true end
  end
  c:That(not named, "the bar does not repeat the guild's name")
  -- The crests: the shield, or the guild's own tabard with its emblem drawn (never an empty disc).
  local empty, crests = 0, 0
  for _, cr in ipairs(ns.UI.crests or {}) do
    crests = crests + 1
    local tabard = cr.disc:IsShown() and cr.emblem:IsShown() and cr.emblem:GetTexture() ~= nil
    if not (tabard or (cr.shield:IsShown() and not cr.disc:IsShown())) then empty = empty + 1 end
  end
  c:Eq(empty, 0, "every crest (" .. crests .. ") shows the shield or the tabard's emblem")
  if Fr.crest then
    Hall:Raise()
    local top = Hall:BlizzardTop()
    local name = top.frame and top.frame.GetDebugName and top.frame:GetDebugName() or "the window"
    c:That(Hall:Above(Fr.crest, top) and Hall:Above(Fr.title, top),
      ("the crest and the guild's name lie above Blizzard's frames (ours %s %d; Blizzard's highest %s %d: %s)"):format(
        tostring(Fr.crest:GetFrameStrata()), Fr.crest:GetFrameLevel(), tostring(Hall.STRATA[top.s]), top.level,
        tostring(name)))
  end
  for _, id in ipairs(Hall:Visible()) do
    Hall:Show(id)
    c:That(Hall.current == id and Hall.pages[id].frame:IsShown() and Hall.title:GetText() == Hall.PLACE[Hall.place].label,
      "page " .. id .. " shows, under its place's name")
  end
  c:Wait(0.2)
  if inGame() then
    local w, bar, panel, screen = rect(CommunitiesFrame), rect(Hall.bar), rect(Hall.frame), rect(UIParent)
    report().geometry = { window = w, bar = bar, panel = panel, screen = screen, scale = CommunitiesFrame:GetScale(),
      list = rect(CommunitiesFrame.CommunitiesList), memberList = rect(CommunitiesFrame.MemberList) }
    if w and bar then
      c:That(math.abs(bar.top - w.bottom) <= 1 and math.abs(bar.left - w.left) <= 1, "the bar is joined under the window")
    end
    if Fr:Dressed() and w and bar and panel and screen then
      local s = Fr:Scale()
      c:That(math.abs(panel.top - bar.bottom) <= 1, "the panel is under the bar")
      local sx = Fr:Spot(s)
      c:That(math.abs((w.left + w.right) / 2 - (screen.left + screen.right) / 2 - sx) <= 1.5,
        not Fr:Moved() and "the frame is in the middle (the window half the side tabs' rail left of it)"
          or ("the window is where you moved it (" .. math.floor(sx + 0.5) .. " from the middle)"))
      c:That(w.top <= screen.top - Fr.EDGE - Fr.CREST * s + 1, "room above it for the crest")
      c:That(panel.bottom - Fr.RIM * s >= screen.bottom + Fr.BARS - 1, "the column ends above the action bars")
    elseif w and panel then
      c:That(panel.left >= w.right, "the panel is beside the window")
      if screen then c:That(panel.right <= screen.right + 1, "and on the screen") end
    end
    -- The places in the bar, next to one another.
    local tabs, last = {}, nil
    for _, id in ipairs(Hall:Places()) do
      local r = rect(Hall.tabs[id])
      tabs[id] = r
      if r and last then c:That(r.left >= last.right - 1, "the " .. id .. " place is clear of the one before") end
      if r and bar then c:That(r.left >= bar.left - 1 and r.right <= bar.right + 1, "the " .. id .. " place lies in the bar") end
      last = r
    end
    report().geometry.tabs = tabs
    c:Note("sizes saved in the report (geometry)")
  end
  noTaint(c, "after opening the panel")
  Hall:Close()
  c:That(not Hall:IsOpen(), "it closes again")
  noTaint(c, "after closing it")
end)

---------------------------------------------------------------------------
-- The pretend guild: settings and sync between several addons
---------------------------------------------------------------------------
local function peersHave(fn)
  for _, p in ipairs(Pe:Online()) do if not fn(p) then return false end end
  return true
end
local function g() return D:Current() end

-- A picture now (the game's Screenshot()), listed in the report (shots), in the game with the guild window open; else
-- nothing. scene: a moment plays first (it waits for it, played again: UI.Stage.replay).
ST.SHOT_GAP = 1.2       -- the file name counts seconds: one picture per second at most
ST.SCENE_WAIT = 2.6     -- a scene's moment plays before its picture
local function shot(c, what, scene)
  if not inGame() or not Screenshot or not windowOpen() then return end
  local r = report()
  r.shots = r.shots or {}
  if scene then
    ns.UI.Stage.replay = true
    wipe(ns.UI.Stage.played)
    Hall:Refresh()
  end
  c:Wait(scene and ST.SCENE_WAIT or 0.4)
  -- (A moment that holds, the court's calls one after another, is waited out: the fourth check of 1 November.)
  if scene then c:Until(function() return not ns.UI.Stage.Busy() end, 8) end
  Screenshot()
  r.shots[#r.shots + 1] = { what = what, t = time() }
  c:Wait(ST.SHOT_GAP)
  if scene then ns.UI.Stage.replay = nil end
end
ST.Shot = shot

-- A feature of a page in the panel, to look at (and take a picture of).
local function look(pid, fid)
  if not windowOpen() or InCombatLockdown() then return false end
  ns.Side.over = nil
  Hall:Open(pid)
  if fid then Hall:ShowFeature(pid, fid) end
  Hall:Refresh()
  return true
end

step("pretend guild: starts apart from the real one", function(c)
  -- (Already running when the window checks practised on a community.)
  local real = not SB.active and D:Id() or nil
  SB:Start()
  c:That(D:Id() ~= real and D:Id() == SB.id, "this client now uses the pretend guild " .. SB.id)
  c:That(R:IsGM(ns.Self()), "with me as its Guild Master")
  c:Eq(#Pe:Online(), 4, "four pretend members online")
  c:Eq(#R:Ranks(), 4, "four ranks below the Guild Master")
end)

step("settings: the Guild Master's page", function(c)
  if not windowOpen() then
    c:Note("the guild window is closed: the page is skipped, the settings are changed directly")
    ns.Sync:ChangeSettings(function(s) s.perms.dunce = { Officer = true }; s.purse = "marks"; s.many = "Selftest Coins" end)
  else
    Hall:Open("settings")
    c:Eq(Hall.current, "settings", "the gear opens Settings")
    local page = Hall.pages.settings.frame
    page.Pick("who")
    local rows = page.ranksFlow.items
    c:Eq(rows.r1 and rows.r1.name:GetText(), "Officer", "the ranks: the first below the Guild Master")
    c:That(rows.r4 and rows.r4:IsShown() and not (rows.r5 and rows.r5:IsShown()), "a row per rank")
    c:That(rows.r1.sel:IsShown(), "the first rank is picked")
    local dunce = page.powersFlow.items["a.dunce"]
    c:That(dunce ~= nil and dunce:IsShown(), "its powers, the Clown Hat among them")
    c:That(Hall.tabs.manage:IsShown(), "Guild settings is in the bar")
    if inGame() then
      -- Each group of settings is a tab of its own; the ones with few settings show without scrolling.
      for _, id in ipairs({ "general", "tax", "council", "disc" }) do
        local grp = page.groups[id]
        for _, pane in ipairs({ grp.left, grp.right }) do
          c:That(pane.child:GetHeight() <= pane.scroll:GetHeight() + 1, ("%s fits without scrolling (%d of %d high)")
            :format(pane.strip.title:GetText(), pane.child:GetHeight(), pane.scroll:GetHeight()))
        end
      end
    end
    dunce:GetScript("OnEnter")(dunce)
    c:That(GameTooltip:IsShown(), "pointing at a power shows its tooltip")
    dunce:GetScript("OnLeave")(dunce)
    dunce:Click()
    c:That(D:Settings().perms.dunce and D:Settings().perms.dunce.Officer, "ticking the Clown Hat for Officer")
    rows.r3:Click()
    c:That(rows.r3.sel:IsShown() and not page.powersFlow.items["a.dunce"]:GetChecked(),
      "Member has not got it: each rank on its own")
    page.Pick("general")
    page.marks:Click()
    c:That(Hall.question:IsShown(), "switching the purse asks first")
    Hall.question.yes:Click()
    c:Eq(D:Settings().purse, "marks", "the purse is Marks")
    page.many:SetText("Selftest Coins")
    page.many:GetScript("OnEditFocusLost")(page.many)
    c:Eq(D:Settings().many, "Selftest Coins", "the Marks are renamed")
    page.Pick("features")
    page.pages[2]:Click()
    local games = false
    for _, id in ipairs(Hall:Visible()) do if id == "games" then games = true end end
    c:That(not games, "a place turned off leaves the tabs")
    page.pages[2]:Click()
    -- One feature (SPEC decision 52): the Lottery leaves Games, and comes back.
    local lottery
    for _, b in ipairs(page.switches) do if b.name() == L.TV_RAFFLES then lottery = b end end
    c:That(lottery ~= nil, "the Lottery can be switched off")
    if lottery then
      lottery:Click()
      local shown = false
      for _, x in ipairs(Hall:Features("games")) do if x.id == "raffles" then shown = true end end
      c:That(not shown and not D:On("tavern:raffles"), "a feature turned off leaves its place")
      lottery:Click()
      c:That(D:On("tavern:raffles"), "and comes back")
    end
  end
  c:That(c:Until(function()
    return peersHave(function(p) return p.g.settings.many == "Selftest Coins" and p.g.settings.perms.dunce ~= nil end)
  end, 5), "every pretend member has the new settings")
  c:Eq(g().sv, 1, "sent as one op")
end)

step("sync: each addon checks the author's rank", function(c)
  c:Eq(Pe:Do("Mirelle", { k = "settings", s = { purse = "gold" }, sv = 9 }), false, "an officer's own addon refuses to change the settings")
  local before = g().seen[Pe:Get("Mirelle").name] or 0
  Pe:Forge("Mirelle", { k = "settings", s = { purse = "gold" }, sv = 9 })
  c:Until(function() return (g().seen[Pe:Get("Mirelle").name] or 0) > before end, 3)
  c:Eq(D:Settings().purse, "marks", "a changed addon's settings are ignored")
  c:That((g().seen[Pe:Get("Mirelle").name] or 0) > before, "and counted as seen")
  Pe:Do("Fenwick", { k = "probe", action = "dunce" })
  Pe:Do("Mirelle", { k = "probe", action = "dunce" })
  c:Until(function() return g().probes and g().probes[Pe:Get("Mirelle").name] end, 3)
  local probes = g().probes or {}
  c:Eq(probes[Pe:Get("Mirelle").name], 1, "an officer may hand out the Dunce Cap (ticked)")
  c:Eq(probes[Pe:Get("Fenwick").name], nil, "a member may not")
end)

step("sync: a member who was offline catches up", function(c)
  Pe:SetOnline("Odo", false)
  ns.Sync:ChangeSettings(function(s) s.one = "Selftest Coin" end)
  c:Until(function() return Pe:Get("Fenwick").g.settings.one == "Selftest Coin" end, 3)
  c:That(Pe:Get("Odo").g.settings.one ~= "Selftest Coin", "Odo missed it while offline")
  Pe:SetOnline("Odo", true)
  Pe:Get("Odo").engine:Hello()
  c:That(c:Until(function() return Pe:Get("Odo").g.settings.one == "Selftest Coin" end, 5), "Odo has it after logging in")
end)

step("sync: a lost op is asked for", function(c)
  local name = Pe:Get("Mirelle").name
  local before = g().seen[name] or 0
  Pe:Do("Mirelle", { k = "probe", action = "dunce" }, true)
  Pe:Do("Mirelle", { k = "probe", action = "dunce" })
  c:That(c:Until(function() return (g().seen[name] or 0) == before + 2 end, 4), "both ops taken, in order")
  c:Eq((g().probes or {})[name], 3, "every one of Mirelle's ops counted once")
end)

step("sync: at login, ask the member who can give the most", function(c)
  local k = Pe:Get("Mirelle")
  local before = g().seen[k.name] or 0
  -- Mirelle made two changes nobody heard.
  Pe:Do("Mirelle", { k = "probe", action = "dunce" }, true)
  Pe:Do("Mirelle", { k = "probe", action = "dunce" }, true)
  local asked = k.got.OPQ or 0
  ns.Sync:Hello()
  c:That(c:Until(function() return (g().seen[k.name] or 0) == before + 2 end, 5), "Mirelle's two ops arrived")
  c:Eq((k.got.OPQ or 0) - asked, 1, "Mirelle was asked once")
end)

step("sync: a whole copy when the log does not reach back", function(c)
  local m, o = Pe:Get("Mirelle"), Pe:Get("Odo")
  m.engine.LOG_MAX = 1
  Pe:SetOnline("Odo", false)
  ns.Sync:ChangeSettings(function(s) s.one = "Copy Coin" end)
  c:Wait(1)
  ns.Sync:ChangeSettings(function(s) s.many = "Copy Coins" end)
  c:Until(function() return m.g.settings.many == "Copy Coins" end, 4)
  Pe:SetOnline("Odo", true)
  local copies = o.got.COPY or 0
  o.engine:Ask(m.name, o.g)
  c:That(c:Until(function() return o.g.settings.many == "Copy Coins" end, 4), "Odo has the settings")
  c:Eq((o.got.COPY or 0) - copies, 1, "from a whole copy")
  c:Eq(o.g.seen[ns.Self()], g().seen[ns.Self()], "and counts the same ops as everyone")
  m.engine.LOG_MAX = nil
end)

step("sync: a new Guild Master takes over the settings", function(c)
  local m = Pe:Get("Mirelle")
  SB:SetRank(ns.Self(), 1)
  SB:SetRank("Mirelle", 0)
  c:That(c:Until(function() return g().sa == m.name end, 4), "the new Guild Master published them as theirs")
  c:Eq(D:Settings().many, "Copy Coins", "the same settings")
  if windowOpen() then
    Hall:Open()
    local gear = false
    for _, id in ipairs(Hall:Visible()) do if id == "settings" then gear = true end end
    c:That(not gear, "Manage left my tabs")
  end
  SB:SetRank("Mirelle", 1)
  SB:SetRank(ns.Self(), 0)
  c:That(c:Until(function() return g().sa == ns.Self() end, 4), "and back to me")
end)

---------------------------------------------------------------------------
-- The Tavern and the purse with the pretend members (G2)
---------------------------------------------------------------------------
-- An entry in a copy's ledger: why ("deathroll", "rolloff", "raffle"), from and to (characters), in either purse.
local function entry(gd, why, from, to)
  for _, part in ipairs({ gd.debts or {}, gd.marks or {} }) do
    for _, e in pairs(part) do
      if e.w == why and e.f == from and e.to == to then return e end
    end
  end
end

step("tavern: a deathroll with a pretend member", function(c)
  local DR, k, me = ns.Deathroll, Pe:Get("Korgath"), ns.Self()
  -- A real game in hand waits (and comes back afterwards); the pretend one must not reach a real player.
  local real = DR.game
  DR.game = nil
  c:That(DR:Challenge(k.name, 5, "gold", 500), "Korgath is challenged: 5 g, from 500")
  c:That(c:Until(function() return DR:Turn() ~= nil end, 3), "his addon accepted")
  -- Our rolls are the game's in a real game; here they are pretend, and always 2, so Korgath is the one to roll 1.
  for _ = 1, 60 do
    local game = DR:Game()
    if not game or game.st == "over" then break end
    local whose, max = DR:Turn()
    if whose == "me" then ns.Dice:Seen(me, math.min(2, max), 1, max) end
    c:Wait(0.1)
  end
  local game = DR:Game()
  c:That(game ~= nil and game.st == "over", "the game ended")
  c:Eq(game and game.loser, "them", "Korgath rolled 1")
  c:That(c:Until(function() return entry(g(), "deathroll", k.name, me) ~= nil end, 3), "his addon wrote the debt, and it reached us")
  c:That(entry(Pe:Get("Fenwick").g, "deathroll", k.name, me) ~= nil, "and every pretend member")
  c:Eq(ns.Purse:Owed(g(), ns.Players:Of(k.name), ns.Players:Of(me)), 5 * ns.Purse.GOLD, "Korgath owes 5 g")
  if real and real.st ~= "over" then DR.game = real end
end)

step("purse: gold that reaches us pays the debt", function(c)
  local k, me, Pu = Pe:Get("Korgath"), ns.Self(), ns.Purse
  local function owed(gd) return Pu:Owed(gd, P:Of(k.name, gd), P:Of(me, gd)) end
  -- In the game this comes from a trade or a letter (Guild/Payments.lua); here the gold "arrives" directly.
  c:Eq(Pu:Arrived(k.name, 3 * Pu.GOLD, "trade"), 3 * Pu.GOLD, "3 g from Korgath by trade")
  c:Eq(owed(g()), 2 * Pu.GOLD, "2 g left")
  c:That(c:Until(function() return owed(k.g) == 2 * Pu.GOLD end, 3), "Korgath's addon agrees")
  c:Eq(Pu:Arrived(Pe:Get("Odo").name, 5 * Pu.GOLD, "mail"), 0, "gold from someone who owes nothing pays nothing")
  c:Eq(Pe:Do("Korgath", { k = "pay", f = k.name, to = me, amt = 2 * Pu.GOLD, how = "hand" }), false,
    "Korgath cannot mark his own debt paid")
end)

step("tavern: a roll-off with pretend members", function(c)
  local RO, me = ns.RollOff, ns.Self()
  local m, o = Pe:Get("Mirelle"), Pe:Get("Odo")
  c:That(RO:Start(100), "opened, /roll 100")
  local _, id = RO:Current()
  Pe:Do("Mirelle", { k = "rolloff_join", id = id })
  Pe:Do("Odo", { k = "rolloff_join", id = id })
  RO:Join(id)
  c:Until(function() local ro = RO:Current() return ro.j[m.name] and ro.j[o.name] end, 3)
  RO:Go(id)
  c:Until(function() return (m.g.rolloffs or {})[id] and m.g.rolloffs[id].st == "rolling" end, 3)
  ns.Dice:Seen(me, 70, 1, 100)
  Pe:Do("Mirelle", { k = "rolloff_roll", id = id, v = 90 })
  Pe:Do("Odo", { k = "rolloff_roll", id = id, v = 10 })
  c:That(c:Until(function() return #RO:Rolls(RO:Current()) == 3 end, 3), "three rolls: mine (70), Mirelle's (90), Odo's (10)")
  c:That(RO:Finish(id), "finished")
  local ro = RO:Current()
  c:Eq(ro.amt, 80, "Odo pays Mirelle 90 - 10")
  c:That(c:Until(function() return entry(Pe:Get("Fenwick").g, "rolloff", o.name, m.name) ~= nil end, 3),
    "every pretend member has it in the ledger")
end)

step("tavern: a raffle with pretend members", function(c)
  local RA, Pu = ns.Raffle, ns.Purse
  local f, o = Pe:Get("Fenwick"), Pe:Get("Odo")
  c:That(RA:Start("Selftest Nightsaber", 2, 10, "now"), "opened: 2 a ticket, 10 tickets")
  local id
  for _, item in ipairs(RA:List()) do if item.ra.prize == "Selftest Nightsaber" and item.ra.st ~= "done" then id = item.id end end
  Pe:Do("Fenwick", { k = "raffle_buy", id = id, n = 2 })
  c:Wait(1.1)
  Pe:Do("Odo", { k = "raffle_buy", id = id, n = 1 })
  c:That(c:Until(function() return select(2, RA:Tickets(g().raffles[id])) == 3 end, 3), "three tickets sold")
  c:That(RA:Draw(id), "drawn: a roll from 1 to 3")
  ns.Dice:Seen(ns.Self(), 3, 1, 3)
  local ra = g().raffles[id]
  c:Eq(ra.st, "done", "the raffle is done")
  c:Eq(ra.w, o.name, "ticket 3 is Odo's (Fenwick bought 1 and 2 first)")
  c:That(c:Until(function() return entry(f.g, "raffle", f.name, Pu.TREASURY) ~= nil end, 3),
    "Fenwick's tickets are charged to the Treasury, on every copy")
end)

---------------------------------------------------------------------------
-- The Arena with the pretend members (G3). Duels are pretend too: the game's duel message is handed to every addon.
---------------------------------------------------------------------------
step("arena: a ladder duel with a pretend member, and wagers on it", function(c)
  local Du, me = ns.Duels, ns.Self()
  local k, m, f = Pe:Get("Korgath"), Pe:Get("Mirelle"), Pe:Get("Fenwick")
  -- A real challenge in hand waits (and comes back afterwards).
  local real = Du.ch
  Du.ch = nil
  c:That(Du:Challenge(k.name), "Korgath is challenged")
  c:That(c:Until(function() local ch = Du:Game() return ch and ch.st == "on" end, 3), "his addon accepted")
  local list = {}
  c:That(c:Until(function() list = Du.Matches(m.g) return #list == 1 end, 3), "the guild knows the match is on")
  local id = list[1] and list[1].id
  c:That(Pe:Do("Mirelle", { k = "bet", m = id, on = me, amt = 5, p = "gold" }), "Mirelle bets 5 g on you")
  c:That(Pe:Do("Fenwick", { k = "bet", m = id, on = k.name, amt = 5, p = "gold" }), "Fenwick bets 5 g on Korgath")
  c:Until(function() return k.g.bets and k.g.bets[id] and k.g.bets[id][f.name] ~= nil end, 3)
  Pe:Duel(me, k.name)
  c:That(c:Until(function() return g().duels and g().duels[id] ~= nil end, 3), "Korgath's addon wrote the duel")
  local ladder = Du.Ladder(g())
  c:Eq(ladder[1] and ladder[1].r, 1516, "you are first on the ladder, 1516")
  c:Eq(ns.Crown.State(g()).name, me, "and wear the empty crown")
  c:That(c:Until(function() return entry(Pe:Get("Odo").g, "wager", f.name, m.name) ~= nil end, 3),
    "Fenwick owes Mirelle his bet, on every copy")
  Du.ch = real
end)

step("arena: crown challenges with pretend members", function(c)
  local Cr, me = ns.Crown, ns.Self()
  local m, o = Pe:Get("Mirelle"), Pe:Get("Odo")
  c:That(Pe:Do("Odo", { k = "crown_ch" }), "Odo challenges you for the crown")
  local wait = {}
  c:That(c:Until(function() wait = Cr.Waiting(g(), Cr.State(g())) return #wait == 1 end, 3), "it waits for your answer")
  c:That(Cr.Accept(wait[1] and wait[1].id), "accepted")
  c:That(c:Until(function() return Cr.MatchWith(o.g, me, o.name) ~= nil end, 3), "Odo's addon knows it is on")
  Pe:Duel(me, o.name)
  c:That(c:Until(function() return #Cr.Accepted(g(), Cr.State(g())) == 0 end, 3), "Odo lost: the challenge is done")
  c:Eq(Cr.State(g()).name, me, "you keep the crown")
  -- Mirelle tries next, and wins: our own addon writes the loss.
  Pe:Do("Mirelle", { k = "crown_ch" })
  c:Until(function() wait = Cr.Waiting(g(), Cr.State(g())) return #wait == 1 end, 3)
  Cr.Accept(wait[1] and wait[1].id)
  c:Until(function() return Cr.MatchWith(m.g, me, m.name) ~= nil end, 3)
  Pe:Duel(m.name, me)
  c:That(c:Until(function() return Cr.State(Pe:Get("Fenwick").g).name == m.name end, 3),
    "Mirelle wears the crown, on every copy")
end)

step("arena: a challenge declined, and one called off before the duel", function(c)
  local Du, me = ns.Duels, ns.Self()
  local k = Pe:Get("Korgath")
  local real = Du.ch
  Du.ch = nil
  c:That(k.duel:Challenge(me), "Korgath challenges you")
  c:That(c:Until(function() local ch = Du:Game() return ch and ch.st == "incoming" end, 3), "it waits for your answer")
  local matches = count(g().matches)
  c:That(Du:CallOff(), "you decline")
  c:That(c:Until(function() return k.duel:Game() == nil end, 3), "Korgath's addon knows")
  c:Eq(count(g().matches), matches, "no match is on")
  local duels = count(g().duels)
  Pe:Duel(me, k.name)
  c:Wait(0.5)
  c:Eq(count(g().duels), duels, "so a duel between you does not count")
  c:That(Du:Challenge(k.name), "you challenge Korgath")
  c:That(c:Until(function() local ch = Du:Game() return ch and ch.st == "on" end, 3), "his addon accepts")
  c:That(Du:CallOff(), "you call it off before the duel")
  c:That(c:Until(function() return k.duel:Game() == nil end, 3), "called off on his side too")
  c:That(not Du:Busy(), "you are free to challenge again")
  Du.ch = real
end)

step("arena: a tournament with pretend members", function(c)
  local Cu, Pu = ns.Cup, ns.Purse
  local names = { "Fenwick", "Korgath", "Mirelle", "Odo" }
  c:That(Cu.Open("Selftest Cup", "single", 1, 10, 20, "now"), "opened: 10 g entry, a 20 g prize")
  local _, id = Cu.Current(g())
  for _, n in ipairs(names) do Pe:Do(n, { k = "cup_join", id = id, on = true }) end
  c:That(c:Until(function() return #Cu.Joined(g().cups[id]) == 4 end, 3), "four signed up")
  c:That(Cu.Go(id), "sign-up closed, seeds drawn")
  -- Every match: the name first in order wins; the loser's addon writes it.
  for _ = 1, 3 do
    c:Until(function() local cup = Pe:Get("Odo").g.cups[id] return cup and cup.seeds ~= nil end, 3)
    local live = Cu.Live((Cu.Build(g().cups[id])))
    if #live == 0 then break end
    local before = 0
    for _ in pairs(g().cups[id].d) do before = before + 1 end
    for _, mt in ipairs(live) do
      local w, l = mt.a, mt.b
      if l < w then w, l = l, w end
      Pe:Duel(w, l)
    end
    c:Until(function()
      local n = 0
      for _ in pairs(g().cups[id].d) do n = n + 1 end
      return n == before + #live
    end, 3)
  end
  local B = Cu.Build(g().cups[id])
  c:Eq(B and B.champion, Pe:Get("Fenwick").name, "Fenwick wins it")
  c:That(Cu.Finish(id), "the pot is shared")
  local f, o = Pe:Get("Fenwick"), Pe:Get("Odo")
  c:That(c:Until(function() return entry(o.g, "cup", o.name, f.name) ~= nil end, 3), "Odo pays Fenwick his share, on every copy")
  c:That(entry(g(), "cup", Pu.TREASURY, f.name) ~= nil, "and the Treasury owes Fenwick 60% of its prize")
end)

step("arena: Assassins with pretend members", function(c)
  local As, me = ns.Assassins, ns.Self()
  c:That(As.Open(), "sign-up opened")
  local _, id = As.Current(g())
  for _, n in ipairs({ "Mirelle", "Korgath", "Odo" }) do Pe:Do(n, { k = "asn_join", id = id, on = true }) end
  As.Join(id, true)
  c:That(c:Until(function() return #As.Joined(g().assassins[id]) == 4 end, 3), "four signed up")
  c:That(As.Go(id), "the hunt is on; the targets are dealt")
  local target = As.Target(id)
  c:That(target ~= nil and target ~= me, "you have a secret target")
  Pe:Duel(me, target)
  c:That(c:Until(function() return #As.Standing(Pe:Get("Mirelle").g.assassins[id] or {}) == 3 end, 3),
    "you beat your target: one out, on every copy")
  c:That(c:Until(function() return As.Target(id) ~= nil end, 8), "and you have your next target")
  c:That(As.Target(id) ~= target, "not the one you beat")
end)

---------------------------------------------------------------------------
-- The Stocks with the pretend members (G4). Their own addons' checks (the clock at the stocks, fish, zones) are
-- pretend too: they report as a real prisoner's addon would.
---------------------------------------------------------------------------
local function newest(gd) return ns.Stocks.List(gd)[1] end

-- The Guild Master is never punished (SPEC decision 56): to be sentenced, you step down and Mirelle leads the pretend
-- guild for a while, as in "sync: a new Guild Master takes over the settings".
local function stepDown(c)
  SB:SetRank(ns.Self(), 1)
  SB:SetRank("Mirelle", 0)
  c:Until(function() return g().sa == Pe:Full("Mirelle") end, 4)
end
local function leadAgain(c)
  SB:SetRank("Mirelle", 1)
  SB:SetRank(ns.Self(), 0)
  c:Until(function() return g().sa == ns.Self() end, 4)
end

step("stocks: a pretend member sentenced, tomatoes, the wheel and bail", function(c)
  local St, Pu = ns.Stocks, ns.Purse
  local k = Pe:Get("Korgath")
  c:That(not St.Punishable(g(), P:Of(ns.Self())), "you lead the guild: you cannot be punished")
  c:That(c:Until(function() return St.Punishable(g(), P:Of(k.name)) end, 3), "Korgath has Guild Together: he can be")
  c:That(St.Sentence(k.name, "stocks", 5, "Selftest: pulled the whole room"), "sentenced to the stocks")
  local s = newest(g())
  c:Eq(s and s.st, "active", "the sentence runs")
  c:That(St.Tomato(s.id), "a tomato thrown")
  c:Eq(g().sentences[s.id].tom[ns.Self()], 1, "and counted")
  c:That(c:Until(function() return k.g.sentences and k.g.sentences[s.id] ~= nil end, 3), "Korgath's addon has it")
  c:That(Pe:Do("Korgath", { k = "stk", id = s.id, s = 300 }), "their addon reports five minutes at the stocks")
  c:That(c:Until(function() return St.State(g(), s.id, g().sentences[s.id]).how == "served" end, 3), "served")
  c:That(St.Sentence(k.name, "wheel", 10, "Selftest: stood in fire"), "sentenced to the wheel")
  local w = newest(g())
  c:Eq(w and w.st, "spin", "it waits for a spin")
  c:That(St.Spin(w.id), "spun")
  w = St.State(g(), w.id, g().sentences[w.id])
  c:That(w.st == "active" and w.pun ~= "wheel", "it landed on " .. tostring(w.pun))
  local purse = D:Settings().purse
  local amt = St.Bail("wheel", purse)
  c:That(Pe:Do("Korgath", { k = "bail", id = w.id, amt = amt, p = purse }), "Korgath pays bail")
  c:That(c:Until(function() return St.State(g(), w.id, g().sentences[w.id]).how == "bailed" end, 3), "bailed out")
  c:That(entry(g(), "bail", k.name, Pu.TREASURY) ~= nil, "the bail is owed to the Treasury")
end)

step("stocks: my own sentence, its clock, the banner and the chat filter", function(c)
  local St, Pn, me = ns.Stocks, ns.Punish, ns.Self()
  ns.Sync:ChangeSettings(function(s) s.perms.stocks = { Officer = true } end)
  c:That(c:Until(function() return D:Can("stocks", Pe:Get("Mirelle").name, Pe:Get("Mirelle").g) end, 3),
    "officers may use the stocks")
  stepDown(c)
  c:That(c:Until(function() return St.Punishable(Pe:Get("Mirelle").g, P:Of(me)) end, 3), "stepped down, you can be punished")
  c:That(Pe:Do("Mirelle", { k = "sentence", to = me, pun = "stocks", len = 5, why = "Selftest" }), "Mirelle sentences you")
  c:That(c:Until(function() return #St.Of(g(), P:Of(me)) == 1 end, 3), "you are in the stocks")
  local s = St.Of(g(), P:Of(me))[1]
  local before = s and Pn.Served(s) or 0
  Pn:Tick()
  c:That(s and Pn.Served(s) > before, "the clock runs (no stocks placed: anywhere counts)")
  if ns.Banner.frame then
    ns.Banner:Refresh()
    c:That(ns.Banner.frame:IsShown(), "the banner shows your sentence")
  end
  local _, text = Pn.Filter(nil, "CHAT_MSG_GUILD", "Hello", me)
  c:That(type(text) == "string" and text:find(L.TAG_STOCKS, 1, true) ~= nil, "your guild chat is tagged: " .. tostring(text))
  c:That(s and St.PayBail(s), "you pay bail")
  c:Eq(#St.Of(g(), P:Of(me)), 0, "and are free")
  if ns.Banner.frame then
    ns.Banner:Refresh()
    c:That(not ns.Banner.frame:IsShown(), "the banner is gone")
  end
  leadAgain(c)
end)

step("stocks: trial by combat with a pretend member, who wins and goes free", function(c)
  local St, me = ns.Stocks, ns.Self()
  local k = Pe:Get("Korgath")
  c:That(St.Sentence(k.name, "stocks", 30, "Selftest: looted the chest"), "Korgath is sentenced")
  local id = newest(g()).id
  c:That(c:Until(function() return k.g.sentences and k.g.sentences[id] ~= nil end, 3), "their addon has it")
  c:That(Pe:Do("Korgath", { k = "trial", id = id }), "Korgath demands trial by combat")
  c:That(c:Until(function() return St.MatchWith(g(), me, k.name) ~= nil end, 3), "the trial waits for the duel")
  c:Until(function() return St.MatchWith(k.g, me, k.name) ~= nil end, 3)
  Pe:Duel(k.name, me)
  c:That(c:Until(function() return g().duels and g().duels[id] ~= nil end, 3), "your addon wrote your loss")
  local s = St.State(g(), id, g().sentences[id])
  c:Eq(s.winner, k.name, "Korgath won the trial")
  c:That(c:Until(function() return k.g.duels and k.g.duels[id] ~= nil end, 3), "their addon knows")
  stepDown(c)
  -- Korgath, who won, goes free; he cannot punish you back (decision 69).
  c:Eq(s.how, "trial", "the duel ended his sentence: he goes free")
  Pe:Do("Korgath", { k = "sentence", to = me, pun = "dunce", why = "Selftest: lost the trial", tr = id })
  c:Wait(1)
  c:That(St.Dunce(g()) ~= P:Of(me), "his punishment back at you does nothing")
  leadAgain(c)
end)

local function stateOf(id, now) return ns.Stocks.State(g(), id, g().sentences[id], now) end

step("stocks: the Radio, a curse in guild chat, community service and the walk of shame", function(c)
  local St, Pn, me = ns.Stocks, ns.Punish, ns.Self()
  local k = Pe:Get("Korgath")
  -- The Radio on your own screen, and the buyout.
  -- The Jingle and the Servant start switched off (SPEC decision 52).
  ns.Sync:ChangeSettings(function(s)
    s.perms.radio = { Officer = true }
    s.off["p:radio"], s.off["p:servant"] = false, false
  end)
  c:Until(function() return D:Can("radio", Pe:Full("Mirelle"), Pe:Get("Mirelle").g) end, 3)
  stepDown(c)
  c:Until(function() return St.Punishable(Pe:Get("Mirelle").g, P:Of(me)) end, 3)
  c:That(Pe:Do("Mirelle", { k = "sentence", to = me, pun = "radio", len = 10, why = "Selftest: sang in raid" }),
    "Mirelle puts you on the Radio")
  c:That(c:Until(function() return #St.Of(g(), P:Of(me)) == 1 end, 3), "the sentence reached you")
  local r = St.Of(g(), P:Of(me))[1]
  Pn.radio = nil
  Pn:Tick()
  c:That(r and Pn.radio and Pn.radio[r.id] ~= nil, "the jingle plays on your screen")
  c:That(r and St.PayBail(r), "you buy it out")
  c:That(St.Broke(g(), P:Of(me)), "and earn the Broke badge")
  leadAgain(c)
  -- A curse: Korgath's guild chat in Murloc-speak, on your screen only.
  c:That(St.Sentence(k.name, "curse", nil, "Selftest: murloc lover", { c = "murloc" }), "Korgath is cursed")
  local _, text = Pn.Filter(nil, "CHAT_MSG_GUILD", "hello there friend", k.name)
  c:That(type(text) == "string" and text:find("Mrgl", 1, true) ~= nil, "his guild chat reads: " .. tostring(text))
  local _, plain = Pn.Filter(nil, "CHAT_MSG_GUILD", "hello there friend", Pe:Full("Fenwick"))
  c:Eq(plain, nil, "Fenwick talks plainly")
  -- Community service: Korgath's addon counts the fish he catches.
  c:That(St.Sentence(k.name, "service", nil, "Selftest: ate the fish feast", { q = 3 }), "Korgath must catch 3 fish")
  local id = newest(g()).id
  c:Until(function() return k.g.sentences and k.g.sentences[id] ~= nil end, 3)
  c:That(Pe:Do("Korgath", { k = "stk", id = id, n = 3 }), "his addon reports 3 fish")
  c:That(c:Until(function() return stateOf(id).how == "served" end, 3), "served")
  -- The walk of shame: his addon reports each zone reached with no gear on.
  c:That(not St.Sentence(k.name, "walk", nil, "Selftest", { z = {} }), "a walk needs zones")
  c:That(St.Sentence(k.name, "walk", nil, "Selftest: lost the raid", { z = { "Goldshire", "Stormwind City" } }),
    "Korgath walks Goldshire to Stormwind City")
  id = newest(g()).id
  c:Until(function() return k.g.sentences and k.g.sentences[id] ~= nil end, 3)
  Pe:Do("Korgath", { k = "stk", id = id, i = 1 })
  c:That(c:Until(function() return stateOf(id).i == 1 end, 3), "Goldshire reached")
  Pe:Do("Korgath", { k = "stk", id = id, i = 2 })
  c:That(c:Until(function() return stateOf(id).how == "served" end, 3), "the whole route: served")
  c:Note("what the prisoner's own addon checks (fish caught, no gear on, the zone) is in the unit tests")
end)

step("stocks: tribute and the Cursed Idol, and a servant for an hour", function(c)
  local St, Pu, me = ns.Stocks, ns.Purse, ns.Self()
  local k = Pe:Get("Korgath")
  c:That(St.Sentence(k.name, "idol", nil, "Selftest: was rude"), "Korgath owes the Guild Master tribute")
  local id = newest(g()).id
  c:Eq(stateOf(id).st, "tribute", "it waits for the tribute")
  c:That(not Pe:Do("Mirelle", { k = "tribute", id = id, ok = true }), "only the Guild Master judges it")
  c:That(St.Tribute(id, false, "Selftest: a soggy hat"), "you scorn it")
  local s = stateOf(id)
  c:That(s.st == "active" and s.idol, "Korgath carries the Cursed Idol")
  c:That(c:Until(function() return k.g.sentences and k.g.sentences[id] ~= nil end, 3), "his addon has it")
  Pe:Do("Korgath", { k = "deed", id = id })
  c:Wait(0.5)
  c:Eq(stateOf(id).st, "active", "a good deed for himself does not count")
  Pe:Do("Mirelle", { k = "deed", id = id })
  c:That(c:Until(function() return stateOf(id).how == "deed" end, 3), "Mirelle confirms his good deed: the Idol passes on")
  c:Note("a tribute handed over by trade is a check by hand")
  -- A servant for an hour: the auction runs ten minutes (read ten minutes on), then the hour of orders.
  c:That(St.Sentence(k.name, "servant", nil, "Selftest: lazy"), "Korgath's service is auctioned")
  id = newest(g()).id
  Pe:Do("Mirelle", { k = "bid", id = id, amt = 5, p = D:Settings().purse })
  c:That(St.Bid(id, 8), "you bid 8")
  Pe:Do("Korgath", { k = "bid", id = id, amt = 50, p = D:Settings().purse })
  c:That(c:Until(function() local x = stateOf(id) return x.master == me and x.price == 8 end, 3),
    "you lead with 8; Korgath's own bid does not count")
  s = stateOf(id, time() + 601)
  c:That(not s.auction and s.st == "active", "ten minutes on, the hour begins")
  c:That(St.Hire(s), "you pay")
  c:That(entry(g(), "servant", me, Pu.TREASURY) ~= nil, "the price is owed to the Treasury")
  c:That(St.Order(id, "Selftest: fetch me a fish"), "you give an order")
  local key
  c:That(c:Until(function()
    local o = k.g.sentences and k.g.sentences[id] and k.g.sentences[id].orders
    key = o and next(o)
    return key ~= nil
  end, 3), "Korgath's addon sees it")
  Pe:Do("Korgath", { k = "odone", id = id, o = key })
  c:That(c:Until(function() return (g().sentences[id].odone or {})[key] ~= nil end, 3), "done, for everyone to see")
end)

---------------------------------------------------------------------------
-- Games with the pretend members (G5). Their addons' sightings are pretend: they report as a real addon would.
-- Nothing goes into the game's calendar here (it would be a real event): that stays a check by hand.
---------------------------------------------------------------------------
local function game(kind) for _, x in ipairs(ns.Games.List(g())) do if x.ga.kind == kind and not x.ga.st then return x.id, x.ga end end end

step("games: a fishing contest with pretend members", function(c)
  local Gm, Pu, me = ns.Games, ns.Purse, ns.Self()
  local k = Pe:Get("Korgath")
  c:That(Gm.Open("derby", time(), 30, 5), "a fishing contest opened, with a prize of 5")
  local id = game("derby")
  c:That(c:Until(function() return k.g.games and k.g.games[id] ~= nil end, 3), "the pretend members have it")
  c:That(Gm.Join(id, true), "you join")
  Pe:Do("Korgath", { k = "game_join", id = id, on = true })
  Pe:Do("Odo", { k = "game_join", id = id, on = true })
  ns.Seen.Fire("fish")
  c:That(Pe:Do("Korgath", { k = "game_rep", id = id, n = 3 }), "Korgath's addon reports 3 fish")
  Pe:Do("Odo", { k = "game_rep", id = id, n = 1 })
  c:That(c:Until(function() return #Gm.Scores(g(), g().games[id], id) == 3 end, 3), "three anglers on the board")
  local top = Gm.Scores(g(), g().games[id], id)
  c:Eq(top[1] and top[1].name, k.name, "Korgath leads")
  local mine
  for _, e in ipairs(top) do if e.name == me then mine = e.v end end
  c:Eq(mine, 1, "your own catch counted")
  c:That(Gm.Finish(id), "you end it")
  c:That(entry(g(), "game", Pu.TREASURY, k.name) ~= nil, "the Treasury owes Korgath the prize")
  c:That(c:Until(function() return k.g.games[id].st == "done" end, 3), "every copy has the end")
end)

step("games: bingo and a meet-up", function(c)
  local Gm, me = ns.Games, ns.Self()
  c:That(Gm.Open("bingo", time(), 60, 0), "bingo opened")
  local id = game("bingo")
  c:That(Gm.Join(id, true), "you join and get a card")
  local card = Gm.Card(id, me)
  c:Eq(#card, Gm.SIZE * Gm.SIZE, "a 4 by 4 card")
  for pos = 5, 8 do if card[pos] ~= "free" then ns.Seen.Fire(card[pos]) end end
  local s = Gm.Scores(g(), g().games[id], id)[1]
  c:That(s and s.name == me and s.bingo ~= nil, "your second row is full: BINGO")
  Gm.Cancel(id)
  local here = ns.Punish.Here()
  if not here then c:Note("the game does not tell your position here (an instance?): the meet-up is skipped") return end
  c:That(Gm.Open("flash", time(), nil, 0, { spot = here }), "a meet-up where you stand, starting now")
  local fid = game("flash")
  Gm.there[fid] = nil
  Gm:Tick()
  Pe:Do("Mirelle", { k = "game_rep", id = fid, here = true })
  c:That(c:Until(function() return #Gm.Winners(g(), g().games[fid], fid) == 2 end, 3), "you and Mirelle were there")
  Gm.Cancel(fid)
  c:Note(ns.Calendar.On() and "the game's calendar is on (adding an event is a check by hand)" or "the game's calendar is off here")
end)

step("games: a treasure hunt and a transmog contest", function(c)
  local Gm = ns.Games
  local here = ns.Punish.Here()
  if here then
    here.text = "Selftest: right where you stand"
    c:That(Gm.Open("hunt", time(), 60, 0, { clues = { here } }), "a hunt with one clue where you stand")
    local id = game("hunt")
    c:That(Gm.Claim(id, 1), "claimed: your addon finds you at the place")
    c:Eq(Gm.Finder(g().games[id], 1), ns.Self(), "first found by you")
    Gm.Cancel(id)
  else
    c:Note("the game does not tell your position here: the hunt is skipped")
  end
  c:That(Gm.Open("fashion", time(), 60, 0), "a transmog contest")
  local id = game("fashion")
  local k, o = Pe:Get("Korgath"), Pe:Get("Odo")
  c:That(c:Until(function() return k.g.games and k.g.games[id] ~= nil end, 3), "the pretend members have it")
  Pe:Do("Korgath", { k = "game_join", id = id, on = true })
  Pe:Do("Odo", { k = "game_join", id = id, on = true })
  c:Until(function() return #Gm.Scores(g(), g().games[id], id) == 2 end, 3)
  c:That(Gm.Vote(id, k.name), "you vote for Korgath")
  Pe:Do("Mirelle", { k = "game_vote", id = id, on = k.name })
  Pe:Do("Odo", { k = "game_vote", id = id, on = o.name })
  c:That(c:Until(function() local s = Gm.Scores(g(), g().games[id], id)[1] return s and s.v == 2 end, 3),
    "Korgath has two votes; Odo's vote for Odo does not count")
  c:Eq(Gm.Winners(g(), g().games[id], id)[1], k.name, "Korgath wins")
  Gm.Cancel(id)
end)

step("games: hidden traitors, run by you, with pretend members", function(c)
  local Gm, Tr = ns.Games, ns.Traitors
  c:That(Gm.Open("traitors", time(), nil, 0), "Hidden traitors opened; you run it")
  local id = game("traitors")
  local players = { "Mirelle", "Korgath", "Fenwick", "Odo" }
  for _, n in ipairs(players) do Pe:Do(n, { k = "game_join", id = id, on = true }) end
  c:Until(function() local n = 0 for _ in pairs(Gm.Joined(g(), g().games[id])) do n = n + 1 end return n == 4 end, 3)
  c:That(Tr.Deal(id, 1), "the roles are dealt: one traitor among four")
  local deal = Tr.Store().deals[id]
  local traitor, faithful
  for _, n in ipairs(players) do
    local full = Pe:Get(n).name
    if deal[full] == "traitor" then traitor = full elseif not faithful then faithful = full end
  end
  c:That(traitor ~= nil and Tr.Role(id) == nil, "your addon holds the roles; you have none")
  c:That(Tr.Night(id), "night falls")
  Pe:FromPeer(Pe:Get(traitor), ns.Self(), "TRM", { id = id, r = 1, v = faithful })
  c:That(c:Until(function() return Tr.Picked(id, 1) == 1 end, 3), "the traitor's pick is whispered to you")
  c:That(Tr.Morning(id), "morning")
  c:Eq(g().games[id].dawn[1].v, faithful, "their victim was murdered")
  for _, n in ipairs(players) do
    local full = Pe:Get(n).name
    if full ~= traitor and full ~= faithful then Pe:Do(n, { k = "tr_vote", id = id, r = 1, on = traitor }) end
  end
  c:Until(function() return (Tr.Tally(g().games[id], 1)[1] or {}).n == 2 end, 3)
  c:That(Tr.Banish(id), "the round table banishes")
  local ga = g().games[id]
  c:That(ga.ban[1].v == traitor and ga.ban[1].role == "traitor", "the traitor is banished and revealed")
  c:Eq(ga.side, "faithful", "the Faithful win")
  c:Eq(ga.st, "done", "and the game is over")
end)

step("games: a survival race and a gift exchange with pretend members", function(c)
  local Gm, Sa, me = ns.Games, ns.Santa, ns.Self()
  local here = ns.Punish.Here()
  if here then
    local lv = tonumber(UnitLevel("player")) or 1
    c:That(Gm.Open("gnomes", time(), 30, 0, { clues = { here, here }, lv = lv }),
      "a survival race whose start and finish are where you stand")
    local id = game("gnomes")
    c:That(Gm.Join(id, true), "you run")
    Pe:Do("Korgath", { k = "game_join", id = id, on = true, lv = 1 })
    Gm:Tick()
    Gm:Tick()
    local mine = Gm.Run(g().games[id], Gm.Merged(g(), g().games[id], P:Of(me)))
    c:Eq(mine, 2, "your addon saw you pass both checkpoints")
    Pe:Do("Korgath", { k = "game_rep", id = id, dead = true })
    c:That(c:Until(function()
      local s = Gm.Scores(g(), g().games[id], id)
      return #s == 2 and s[1].done and s[2].dead ~= nil
    end, 3), "you survived; Korgath fell")
    Gm.Cancel(id)
  else
    c:Note("the game does not tell your position here: the survival race is skipped")
  end
  c:That(Gm.Open("santa", time(), nil, 0, { rv = time() + 86400 }), "a gift exchange opened")
  local id = game("santa")
  Gm.Join(id, true)
  for _, n in ipairs({ "Mirelle", "Korgath", "Odo" }) do Pe:Do(n, { k = "game_join", id = id, on = true }) end
  c:Until(function() local n = 0 for _ in pairs(Gm.Joined(g(), g().games[id])) do n = n + 1 end return n == 4 end, 3)
  c:That(Sa.Draw(id), "pairs drawn")
  local to = Sa.Giftee(id)
  c:That(to ~= nil and to ~= me, "you give to: " .. tostring(to and ns.Display(to)))
  local ring, santa = Sa.Store().rings[id], nil
  for i, n in ipairs(ring) do if ring[i % #ring + 1] == me then santa = n end end
  Sa:Letter(santa)
  Pe:FromPeer(Pe:Get(santa), me, "SSY", { id = id })
  c:That(c:Until(function() local ga = g().games[id] return ga.got and ga.got[me] ~= nil end, 3),
    "a letter from your secret giver: their addon says yes, and your gift counts")
  c:That(Sa.Reveal(id), "revealed")
  c:Eq(#(g().games[id].pairs or {}), 4, "every pair shown")
end)

step("games: one called off, one left, and one whose time ran out", function(c)
  local Gm, me = ns.Games, ns.Self()
  local o = Pe:Get("Odo")
  -- Opens a game and gives its id: the one that was not there before.
  local function opened(...)
    local had = {}
    for gid in pairs(g().games or {}) do had[gid] = true end
    if not Gm.Open(...) then return nil end
    for gid in pairs(g().games or {}) do if not had[gid] then return gid end end
  end
  local id = opened("bingo", time(), 60, 0)
  c:That(id ~= nil, "a bingo game")
  c:That(c:Until(function() return o.g.games and o.g.games[id] ~= nil end, 3), "the pretend members have it")
  c:That(Gm.Cancel(id), "you call it off")
  c:That(c:Until(function() return Gm.State(o.g.games[id]) == "off" end, 3), "called off on every copy: nobody wins")
  local lid = opened("derby", time(), 60, 0)
  c:That(lid ~= nil, "a fishing contest")
  local key = P:Of(me, g())
  c:That(Gm.Join(lid, true) and Gm.IsIn(g(), g().games[lid], key), "you join")
  c:That(Gm.Join(lid, false) and not Gm.IsIn(g(), g().games[lid], key), "and leave again")
  c:That(c:Until(function()
    local his = o.g.games and o.g.games[lid]
    return his ~= nil and his.j ~= nil and his.j[me] ~= nil and not Gm.IsIn(o.g, his, key)
  end, 3), "on every copy")
  Gm.Cancel(lid)
  local tid = opened("derby", time() - 3600, 30, 0)
  c:That(tid ~= nil, "a fishing contest that ended half an hour ago")
  c:Eq(Gm.State(g().games[tid]), "over", "time is up: it waits for the host")
  c:That(Gm.Finish(tid), "you end it")
  c:That(c:Until(function() local his = o.g.games[tid] return his ~= nil and Gm.State(his) == "done" end, 3),
    "done, on every copy")
end)

---------------------------------------------------------------------------
-- Council (G6). Time cannot be moved on in the game: the pretend members make their ops now, and the phases that
-- take days (the vote's end, the hand-over's week) are read at a later time.
---------------------------------------------------------------------------
local function motionOp(kind, extra)
  local op = { k = "motion", kind = kind, why = "Selftest motion", m = 5, gm = ns.Self() }
  for _, k in ipairs(D.NUMBER_KEYS) do if k ~= "jury" then op[k] = D:Number(k) end end
  for k, v in pairs(extra or {}) do op[k] = v end
  return op
end

local function newestMotion(kind)
  local s = ns.Council.Motions(g(), nil, kind)[1]
  return s and s.id
end

step("council: impeachment by the officers, the lockout and the hand-over, with pretend members", function(c)
  local Co, me = ns.Council, ns.Self()
  local K = Pe:Full("Korgath")
  c:That(not Co.Impeach("Selftest"), "you, the Guild Master, may not impeach yourself")
  -- A Monarchy: the officers impeach (SPEC decision 70). Mirelle is the one officer.
  SB:Govern("monarchy")
  c:That(c:Until(function() return SB:Governed("monarchy") end, 4), "the pretend guild is a Monarchy")
  c:That(not D:Can("impeach", Pe:Full("Fenwick")), "in a Monarchy a member who is no officer may not impeach")
  Pe:Do("Mirelle", { k = "motion", kind = "lead", why = "Selftest impeachment", gm = me, vt = Co.Officers(g()) })
  c:That(c:Until(function() return newestMotion("lead") ~= nil end, 3), "Mirelle starts an impeachment")
  local id = newestMotion("lead")
  local s = Co.Motion(g(), id)
  c:That(s.phase == "vote" and s.n == 1 and s.need == 1, "the officer votes" .. (s.phase == "vote" and "" or (" (" .. tostring(s.phase) .. ")")))
  if look("council", "impeach") then
    shot(c, "leadership: an impeachment, the officers vote", true)
    Hall:Close()
  end
  c:That(not Co.Challenge("Selftest"), "nothing else starts meanwhile")
  c:That(Co.Say(id, "Selftest: raid night is Thursday."), "your answer")
  Pe:Do("Fenwick", { k = "imp_vote", id = id, on = true, c = K })
  Pe:Do("Mirelle", { k = "imp_vote", id = id, on = true, c = K })
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "handover" end, 3), "Mirelle votes yes, for Korgath: it passed")
  c:Eq(Co.Motion(g(), id).yes, 1, "Fenwick's vote does not count (no officer)")
  c:Eq(Co.Motion(g(), id).winner, K, "Korgath should be Guild Master")
  if windowOpen() and not InCombatLockdown() then
    Hall:Open("council")
    local council = Hall.pages.council and Hall.pages.council.frame
    if council and council.Pick then council.Pick("impeach") end
    local hand = Co.HandButton()
    c:That(hand ~= nil and hand:IsShown(), "your page shows the Hand over button")
    local tracker = council and council.rightFlow.items.steps
    c:That(tracker ~= nil and tracker.items ~= nil and #tracker.items >= 2 and tracker.items[1]:IsShown(),
      "its steps as a tracker of icons")
    c:Eq(hand and hand:GetAttribute("macrotext"), "", "in the pretend guild it does nothing (do not press it anyway)")
    shot(c, "leadership: an impeachment won, waiting for the hand-over", true)
    Hall:Close()
    c:That(c:Until(function() return not hand:IsShown() end, 2), "it hides with the page")
  else
    c:Note("open the guild window (out of combat) to check the Hand over button")
  end
  -- Until the guild is handed to Korgath, you can give out, start and change nothing (and every addon refuses it).
  c:That(not D:InCharge(me) and not D:Can("sentence", me), "you are locked out until you hand over")
  c:That(not ns.Sync:ChangeSettings(function(x) x.many = "Locked" end), "your settings cannot be changed")
  c:That(not Co.WriteCharter({ "Selftest: locked" }), "nor the charter")
  c:Eq(Co.Motion(g(), id, time() + 30 * 86400).phase, "handover", "a month on, it still waits: no time limit")
  -- The wrong hand-over: Mirelle gets the rank. She is locked out too.
  SB:SetRank(me, 1)
  SB:SetRank("Mirelle", 0)
  c:That(not D:InCharge(Pe:Full("Mirelle")), "Mirelle holds the rank, but Korgath is the rightful Guild Master")
  -- The game hands over to Korgath; his addon writes it down.
  SB:SetRank("Mirelle", 1)
  SB:SetRank("Korgath", 0)
  c:Eq(Co.Motion(g(), id).phase, "handed", "Korgath is the new Guild Master")
  Pe:Do("Korgath", { k = "lead_done", id = id })
  c:That(c:Until(function() return g().motions[id].done ~= nil end, 3), "Korgath's addon writes the hand-over down")
  -- He gives it back: it stays handed, and you are in charge again.
  SB:SetRank("Korgath", 2)
  SB:SetRank(me, 0)
  c:Eq(Co.Motion(g(), id).phase, "handed", "still handed")
  c:That(D:InCharge(me), "you are in charge again")
  SB:Govern("democracy")
  c:That(c:Until(function() return SB:Governed("democracy") end, 4), "and a Democracy again")
end)

step("council: Mak'gora, with pretend members", function(c)
  local Co, me = ns.Council, ns.Self()
  local K = Pe:Full("Korgath")
  -- Korgath's addon tells the guild his characters: his first day here is today, the guild's first day.
  Pe:Do("Korgath", { k = "player", id = "#5e1f7e57", c = { K }, m = K })
  c:That(c:Until(function() return Co.MayStart(g(), "mak", K) end, 3), "Korgath may challenge (here since the first day)")
  Pe:Do("Korgath", { k = "motion", kind = "mak", why = "Selftest Mak'gora", m = 3, gm = me })
  c:That(c:Until(function() return Co.Motions(g(), nil, "mak")[1] ~= nil end, 3), "Korgath challenges you to Mak'gora")
  local id = Co.Motions(g(), nil, "mak")[1].id
  c:Eq(Co.Motion(g(), id).phase, "challenge", "it waits for your answer")
  c:That(Co.Protected(g(), K), "Korgath gets no strikes during it")
  c:Eq(Co.Motion(g(), id, time() + 7 * 86400 + 60).phase, "vote", "no answer in 7 days would start the guild's vote")
  c:That(Co.Answer(id, true), "you accept")
  c:That(c:Until(function() return Co.Motion(Pe:Get("Korgath").g, id).phase == "duel" end, 3), "the duel is due (Korgath's addon has your answer)")
  if look("council", "impeach") then
    shot(c, "leadership: a Mak'gora, the duel due", true)
    Hall:Close()
  end
  -- You win the duel: Korgath's addon (the loser's) writes it.
  Pe:Duel(me, "Korgath")
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "kept" end, 3), "you won: you stay Guild Master")
  local ok, why = Co.MayStart(g(), "mak", K)
  c:That(not ok and why == "again", "Korgath waits 30 days to challenge again" .. (why ~= "again" and (" (" .. tostring(why) .. ")") or ""))
  c:That(D:InCharge(me), "and you are in charge")
end)

step("council: the Guild Master tournament, opened and defended, with a pretend member", function(c)
  local Co, Cu, me = ns.Council, ns.Cup, ns.Self()
  local K = Pe:Full("Korgath")
  c:That(Co.OpenCrown(), "you open the Guild Master tournament")
  local id
  c:That(c:Until(function()
    local s = Co.Motions(g(), nil, "crown")[1]
    id = s and s.id
    return id ~= nil
  end, 3), "it is under way")
  if not id then return end
  Co:Tick()
  c:That(c:Until(function() local s = Co.Motion(g(), id) return s.phase == "signup" and s.cup ~= nil end, 3),
    "its sign-up opens: you run it, and stand in it as the Guild Master")
  if look("council", "impeach") then
    shot(c, "leadership: the Guild Master tournament, its sign-up", true)
    Hall:Close()
  end
  Pe:Do("Korgath", { k = "cup_join", id = id, on = true })
  c:That(c:Until(function() return #Cu.Joined(g().cups[id]) == 2 end, 3), "Korgath signs up")
  Co:Tick(Co.Now() + Co.SIGNUP + 60)
  c:That(c:Until(function()
    local his = Pe:Get("Korgath").g.cups
    return g().cups[id].seeds ~= nil and his and his[id] and his[id].seeds ~= nil
  end, 3), "three days on, the sign-up closes and the bracket is drawn")
  if look("council", "impeach") then
    shot(c, "leadership: the Guild Master tournament, its bracket", true)
    Hall:Close()
  end
  -- Best of three: you win each duel; Korgath's addon (the loser's) writes it.
  for _ = 1, 3 do
    if #Cu.Live((Cu.Build(g().cups[id]))) == 0 then break end
    local before = count(g().cups[id].d)
    Pe:Duel(me, K)
    c:Until(function() return count(g().cups[id].d) > before end, 3)
  end
  Co:Tick()
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "kept" end, 3), "you beat Korgath: you stay Guild Master")
  c:That(D:InCharge(me), "and you are in charge")
end)

step("council: rules by vote, the charter, a poll, strikes and the court", function(c)
  local Co, Ct, DAY = ns.Council, ns.Court, 86400
  -- A rule change: only officers may open polls, by the guild's vote.
  Pe:Do("Fenwick", motionOp("rule", { r = "poll", v = { 1 }, why = "Selftest: fewer polls" }))
  c:That(c:Until(function() return newestMotion("rule") ~= nil end, 3), "Fenwick proposes a rule change")
  local id = newestMotion("rule")
  for _, n in ipairs({ "Mirelle", "Korgath", "Odo" }) do Pe:Do(n, { k = "motion_sec", id = id }) end
  for _, n in ipairs({ "Fenwick", "Mirelle", "Korgath" }) do Pe:Do(n, { k = "motion_vote", id = id, on = true }) end
  c:That(c:Until(function() return Co.Motion(g(), id).yes == 3 end, 3), "seconded and voted")
  local later = time() + 3 * DAY + 60
  c:Eq(Co.Motion(g(), id, later).phase, "passed", "it passes when the vote ends")
  local rule = Co.Rules(g(), later).poll
  c:That(rule ~= nil and rule.v[1] == 1 and #rule.v == 1, "then officers and above only may open polls")
  -- The charter.
  c:That(Co.WriteCharter({ "Selftest: be kind in guild chat.", "Tomatoes are thrown with love." }), "you write the charter")
  Pe:Do("Mirelle", { k = "charter_ok", v = g().charter.v })
  c:That(c:Until(function() local _, yes = Co.Charter(g()) return yes == 1 end, 3), "Mirelle accepts it")
  -- A poll: Odo (a trial) asks; votes from pretend members and a whisper.
  Pe:Do("Odo", { k = "poll", q = "Selftest: next event?", ch = { "Gnomes", "Fashion" }, days = 1 })
  c:That(c:Until(function() return Co.Polls(g())[1] ~= nil end, 3), "Odo opens a poll")
  local poll = Co.Polls(g())[1]
  Pe:Do("Mirelle", { k = "poll_vote", id = poll.id, on = 1 })
  c:That(Co.Vote(poll.id, 2), "you vote")
  local answer = Co.Whispered("!vote 1", Pe:Full("Korgath"))
  c:That(answer ~= nil and answer:find(L.CO_WHISPER_TAKEN:sub(1, 12), 1, true) ~= nil, "a whispered !vote 1 counts")
  c:That(c:Until(function() local s = Co.Poll(g(), poll.id) return s.rows[1].n == 2 and s.rows[2].n == 1 end, 3), "2 to 1")
  -- Strikes: confirming needs a second member of a rank that may.
  ns.Sync:ChangeSettings(function(s) s.perms.confirm = { Officer = true } end)
  c:That(c:Until(function() return peersHave(function(p) return p.g.settings.perms.confirm ~= nil end) end, 4),
    "officers may confirm strikes")
  c:That(Co.Strike(Pe:Full("Odo"), "Selftest: no-show", 7), "you give Odo a strike")
  local strike = Co.Strikes(g())[1]
  Pe:Do("Mirelle", { k = "strike_ok", id = strike.id })
  c:That(c:Until(function() return Co.Strikes(g())[1].st == "ok" end, 3), "Mirelle confirms it")
  -- The court: Fenwick is charged; three jurors; guilty; you give the sentence.
  c:That(Ct.Charge(Pe:Full("Fenwick"), "Selftest: ninja-looted the hat", "dunce"), "you charge Fenwick")
  local case = Ct.Cases(g())[1].id
  Pe:Do("Fenwick", { k = "court_def", id = case, text = "It matched my outfit." })
  for _, x in ipairs({ { "Mirelle", true }, { "Korgath", true }, { "Odo", false } }) do
    Pe:Do(x[1], { k = "court_jury", id = case, on = true })
    Pe:Do(x[1], { k = "court_vote", id = case, guilty = x[2] })
  end
  c:That(c:Until(function() local s = Ct.Case(g(), case) return #s.jurors == 3 and s.guilty == 2 and s.defence end, 3),
    "a defence and three jurors: 2 guilty, 1 not")
  c:That(Ct.Case(g(), case).calls == nil, "before the verdict only the counts: nobody's vote shows")
  if look("council", "court") then shot(c, "the court in session: the judge on the bench, the jury seated", true) end
  c:That(Ct.Close(case), "you close the case")
  local calls = Ct.Case(g(), case).calls or {}
  c:That(count(calls) == 3 and calls[Pe:Get("Odo").name] == "innocent", "the verdict in: who voted what (Odo: not guilty)")
  if look("council", "court") then
    shot(c, "the court: each juror's call, then a guilty verdict", true)
    Hall:Close()
  end
  c:Eq(Ct.Case(g(), case).verdict, "guilty", "guilty (2 of 3 is 65% or more)")
  c:That(Ct.Sentence(case), "you give the Dunce Cap")
  c:That(Ct.Case(g(), case).sentence ~= nil, "Fenwick is sentenced")
end)

step("council: the Guild Master election, from last month's vote, and its hand-over, with pretend members", function(c)
  local Co, me = ns.Council, ns.Self()
  local K = Pe:Full("Korgath")
  -- A Democracy that elects its Guild Master (SPEC decision 70).
  SB:Govern("democracy", nil, { elect = true })
  c:That(c:Until(function() return SB:Governed("democracy") and Co.Elects(g()) end, 4), "the pretend guild elects its Guild Master")
  -- Last month's election, written into every copy as it would have arrived then: Korgath stood; Mirelle and
  -- Fenwick voted for him, Odo for you.
  local m = Co.LastMonth(Co.Now())
  local function at(d) return Co.UTC(m, d) + 12 * 3600 end
  local function elect(gd)
    gd.elections = gd.elections or {}
    gd.elections[m] = { gm = me, run = { [K] = { line = "Selftest: raids on time", t = at(2) } },
      v = { [Pe:Full("Mirelle")] = { on = K, t = at(5) }, [Pe:Full("Fenwick")] = { on = K, t = at(6) },
        [Pe:Full("Odo")] = { on = me, t = at(5) } } }
  end
  elect(g())
  for _, p in pairs(Pe.list) do elect(p.g) end
  Co.ver = Co.ver + 1
  local s = Co.Election(g(), m)
  c:Eq(s.phase, "handover", "Korgath won, 2 votes to 1")
  c:Eq(s.winner, K, "Korgath should lead")
  c:That(not D:InCharge(me), "you are locked out until you hand over")
  if windowOpen() and not InCombatLockdown() then
    Hall:Open("council")
    local council = Hall.pages.council and Hall.pages.council.frame
    if council and council.Pick then council.Pick("elect") end
    local hand = Co.HandButton()
    c:That(hand ~= nil and hand:IsShown(), "the Election shows the Hand over button")
    c:Eq(hand and hand:GetAttribute("macrotext"), "", "in the pretend guild it does nothing (do not press it anyway)")
    shot(c, "the election: won, waiting for the hand-over", true)
    Hall:Close()
  else
    c:Note("open the guild window (out of combat) to check the Hand over button")
  end
  -- The game hands over to Korgath; his addon writes it down.
  SB:SetRank(me, 1)
  SB:SetRank("Korgath", 0)
  c:Eq(Co.Election(g(), m).phase, "handed", "Korgath leads the guild")
  Pe:Do("Korgath", { k = "elect_done", m = m })
  c:That(c:Until(function() return g().elections[m].done ~= nil end, 3), "Korgath's addon writes it down")
  -- He gives it back: it stays handed, and you are in charge again.
  SB:SetRank("Korgath", 2)
  SB:SetRank(me, 0)
  c:Eq(Co.Election(g(), m).phase, "handed", "still handed")
  c:That(D:InCharge(me), "you are in charge again")
  SB:Govern("democracy")
  c:That(c:Until(function() return SB:Governed("democracy") and not Co.Elects(g()) end, 4), "and a Democracy without the election")
end)

step("council: a strike taken back in a Monarchy, with pretend members", function(c)
  local Co = ns.Council
  SB:Govern("monarchy")
  c:That(c:Until(function() return SB:Governed("monarchy") end, 4), "the pretend guild is a Monarchy")
  Pe:Do("Mirelle", { k = "strike", to = Pe:Full("Odo"), why = "Selftest: late to raid", days = 7 })
  local id
  c:That(c:Until(function()
    for _, e in ipairs(Co.Strikes(g())) do if e.why == "Selftest: late to raid" then id = e.id end end
    return id ~= nil
  end, 3), "Mirelle, an officer, gives Odo a strike")
  if not id then return end
  c:That(Co.TakeBack(id), "you take it back")
  local st
  for _, e in ipairs(Co.Strikes(g())) do if e.id == id then st = e.st end end
  c:Eq(st, "taken", "it no longer counts")
  SB:Govern("democracy")
  c:That(c:Until(function() return SB:Governed("democracy") end, 4), "and a Democracy again")
end)

step("council: a rebellion in a Dictatorship, with pretend members", function(c)
  local Co, me = ns.Council, ns.Self()
  local M = Pe:Full("Mirelle")
  SB:Govern("dictatorship")
  c:That(c:Until(function() return SB:Governed("dictatorship") end, 4), "the pretend guild is a Dictatorship")
  -- Mirelle's addon tells the guild her characters: her first day here is the guild's first day.
  Pe:Do("Mirelle", { k = "player", id = "#4d1e11e0", c = { M }, m = M })
  c:That(c:Until(function() return Co.MayStart(g(), "mak", M) end, 3), "Mirelle may challenge")
  Pe:Do("Mirelle", { k = "motion", kind = "mak", why = "Selftest rebellion", m = 5, gm = me })
  local id
  c:That(c:Until(function()
    local s = Co.Motions(g(), nil, "mak")[1]
    id = s and s.mo.a == M and s.phase == "challenge" and s.id or nil
    return id ~= nil
  end, 3), "Mirelle challenges you to Mak'gora")
  if not id then return end
  c:That(Co.Answer(id, false), "you decline")
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "declined" end, 3), "no guild vote: Mirelle may declare a rebellion")
  Pe:Do("Mirelle", { k = "rebel", id = id, m = 5 })
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "rebellion" end, 3), "she declares it")
  if look("council", "impeach") then
    shot(c, "leadership: a rebellion, members sign", true)
    Hall:Close()
  end
  local s = Co.Motion(g(), id)
  c:That(s.need == 2 and s.signed == 1, "a third of five: 2 signatures, hers the first")
  Pe:Do("Fenwick", { k = "rebel_sign", id = id })
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "duel" end, 3), "Fenwick signs: you must fight her")
  if look("council", "impeach") then
    shot(c, "leadership: a rebellion, the duel forced", true)
    Hall:Close()
  end
  Pe:Duel(me, "Mirelle")
  c:That(c:Until(function() return Co.Motion(g(), id).phase == "kept" end, 3), "you win the duel: you stay Guild Master")
  SB:Govern("democracy")
  c:That(c:Until(function() return SB:Governed("democracy") end, 4), "and a Democracy again")
end)

---------------------------------------------------------------------------
-- The Treasury (G7)
---------------------------------------------------------------------------
step("treasury: the tax, a vault visit, Patrons, an item request and a prize by mail", function(c)
  local Tx, Pu = ns.Treasury, ns.Purse
  local function taxOwed(gd, name)
    local sum = 0
    for _, d in ipairs(Pu:Open(gd)) do if d.w == "tax" and d.f == P:Of(Pe:Full(name), gd) then sum = sum + d.amt end end
    return sum
  end
  -- The tax: 10 g for members, 2 g for trials.
  ns.Sync:ChangeSettings(function(s) s.tax = { on = true, per = "month", lv = 1, amt = { [3] = 10, [4] = 2 }, ex = {} } end)
  c:That(c:Until(function() return peersHave(function(p) return p.g.settings.tax.on end) end, 4), "a guild tax is set")
  -- (Your addon may already have charged it by itself, as it checks every minute.)
  c:That(Tx.Charge() or Tx.Status(g()).n > 0, "this month's tax is charged")
  c:Eq(taxOwed(g(), "Fenwick"), 10 * Pu.GOLD, "Fenwick owes 10 g")
  c:That(c:Until(function() return taxOwed(Pe:Get("Fenwick").g, "Odo") == 2 * Pu.GOLD end, 3), "and Fenwick's addon knows Odo owes 2 g")
  c:Eq(taxOwed(g(), "Korgath"), 0, "Korgath's rank pays none")
  -- A visit to the vault (in the game, its log; here lines made up): Fenwick put in 12 g, Odo took 2 Linen Cloth.
  local n = Tx.Visit({ { kind = "m", type = "deposit", name = Pe:Full("Fenwick"), amount = 12 * Pu.GOLD, ago = 0 },
    { kind = "i", type = "withdraw", name = Pe:Full("Odo"), id = 2589, nm = "Linen Cloth", count = 2, tab = 1, ago = 0 } })
  c:Eq(n, 2, "two new lines for the long ledger")
  c:Eq(taxOwed(g(), "Fenwick"), 0, "Fenwick's deposit paid his tax")
  c:That(c:Until(function() return #Tx.Ledger(Pe:Get("Mirelle").g) == 2 end, 3), "Mirelle's ledger has them too")
  c:Eq(Tx.Visit({ { kind = "m", type = "deposit", name = Pe:Full("Fenwick"), amount = 12 * Pu.GOLD, ago = 0 } }), 0,
    "the same line again adds nothing")
  -- Patrons.
  c:Eq(Tx.Patron(g()), P:Of(Pe:Full("Fenwick")), "Fenwick is Patron of the month")
  local tags = ns.Punish.Look(g(), P:Of(Pe:Full("Fenwick"))).tags
  c:Eq(tags[#tags], L.TAG_PATRON, "and wears [Patron] in guild chat")
  -- An item request from Odo, approved, and "mailed" (no letter leaves the pretend guild).
  local was = Tx.atMailbox
  Pe:Do("Odo", { k = "req", item = "Linen Cloth", iid = 2589, n = 2, why = "Selftest: bandages" })
  c:That(c:Until(function() return Tx.Requests(g())[1] ~= nil end, 3), "Odo asks the vault for 2 Linen Cloth")
  local id = Tx.Requests(g())[1].id
  c:Eq(Pe:Do("Fenwick", { k = "req_ans", id = id, ok = true }), false, "Fenwick (a member) may not approve it")
  c:That(Tx.Answer(id, true), "you approve it")
  Tx.atMailbox = true
  c:That(Tx.MailItem(id), "Mail it")
  c:That(c:Until(function() local s = Tx.Request(Pe:Get("Odo").g, id) return s and s.st == "sent" end, 3), "Odo sees it mailed")
  -- A prize: the Treasury pays Korgath 5 g by mail.
  c:That(Tx.MailGold(P:Of(Pe:Full("Korgath")), 5 * Pu.GOLD), "you mail Korgath a 5 g prize")
  c:That(c:Until(function()
    for _, e in pairs(Pe:Get("Korgath").g.pays or {}) do if e.f == Pu.TREASURY and e.how == "mail" then return true end end
    return false
  end, 3), "Korgath's addon records it")
  Tx.atMailbox = was
  ns.Sync:ChangeSettings(function(s) s.tax.on = false end)
end)

---------------------------------------------------------------------------
-- The Chronicle and the Herald (G8)
---------------------------------------------------------------------------
step("pages: a feature at a glance, with nothing picked", function(c)
  if not windowOpen() or InCombatLockdown() then c:Skip("the guild window is closed: the glance is not drawn") return end
  Hall:Open("home")
  Hall:ShowFeature("home", "now")
  Hall:Refresh()
  c:That(not tostring(ns.Side.key):find("^glance:"), "Home has no glance: its lists are the guild at a glance")
  Hall:Open("treasury")
  Hall:ShowFeature("treasury", "debts")
  Hall:Refresh()
  local Side = ns.Side
  c:That(Side:IsShown() and tostring(Side.key):find("^glance:treasury") ~= nil,
    "with nothing picked, the right column shows the Treasury at a glance (" .. tostring(Side.key) .. ")")
  local f = Side.frame.flows.treasury
  if g().settings.tax.on then
    c:That(f ~= nil and f.items.gtaxbar ~= nil and f.items.gtaxbar:IsShown(), "this period's tax, as a bar")
  else
    local drew = false
    for key, it in pairs(f and f.items or {}) do if key:match("^g") and it:IsShown() then drew = true end end
    c:That(drew, "what matters there (the tax is off: no tax bar)")
  end
  -- The rules' picture plays beside the panel; the column under it says who accepted (it was bare: shot 117 of the
  -- third check of 1 November).
  if g().charter then
    Hall:Open("council")
    Hall:ShowFeature("council", "charter")
    Hall:Refresh()
    local cf = Side.frame.flows.council
    c:That(Side.key == "rules" and cf ~= nil and cf.items.accepted ~= nil and cf.items.accepted:IsShown(),
      "the rules: who accepted, under their picture")
  end
  Hall:Close()
end)

step("chronicle: deeds, a memorial, the mascot, the Gazette and the Herald's posts", function(c)
  local Ch, He = ns.Chronicle, ns.Herald
  local function has(gd, pattern)
    for _, d in ipairs(Ch.Deeds(gd)) do if d.text:find(pattern, 1, true) then return d end end
    return nil
  end
  c:That(Ch.Write(Pe:Full("Korgath"), "Selftest: slew Hogger alone", 0), "you write a deed for Korgath")
  c:That(c:Until(function() return has(Pe:Get("Fenwick").g, "Hogger") ~= nil end, 3), "Fenwick's addon has it")
  Pe:Do("Fenwick", { k = "lvl", lv = 60 })
  c:That(c:Until(function() local d = has(g(), L.CH_DEED_FIRST:format(60)) return d and d.key == P:Of(Pe:Full("Fenwick")) end, 3),
    "Fenwick is first to level 60")
  Pe:Do("Odo", { k = "feed", n = 12 })
  c:That(c:Until(function() return Ch.Mascot(g()).fed >= 12 end, 3), "Odo's catch feeds the mascot")
  c:Eq(Ch.Mascot(g()).mood, "happy", "and it is happy")
  c:That(Ch.Remember(Pe:Full("Odo"), "Selftest: Feralas", "He said he could solo it."), "you remember Odo")
  c:That(c:Until(function() return #Ch.Memorials(Pe:Get("Mirelle").g) == 1 end, 3), "Mirelle's addon has the memorial")
  local z = Ch.Gazette(g(), time())
  c:That(z.headline ~= L.CH_QUIET:upper(), "this week's Gazette leads with: " .. z.headline)
  c:That(#Ch.Hall(g()) > 0, "the Hall of fame has records")
  -- The Rolling Pin awards are given for last month; this month's are worked out the same way.
  local aw = {}
  for _, x in ipairs(Ch.Awards(g(), date("!%Y-%m", time()))) do aw[x.id] = x end
  c:That(aw.jail and aw.tomato and aw.bag, "this month's awards so far: Jailbird, Golden Tomato and Punching Bag")
  -- You are the pretend guild's Guild Master, so its Herald; its posts are made but never written to the outbox.
  c:Eq(He.Herald(g()), ns.Self(), "you are the Herald")
  local group = He.Build(g())
  local fame = false
  for _, x in ipairs(group.news) do if x.kind == "fame" and x.text:find("Hogger", 1, true) then fame = true end end
  c:That(fame, "the deed is a post for #hall-of-fame")
  c:That(not He.Write(), "nothing from the pretend guild goes into the outbox")
end)

---------------------------------------------------------------------------
-- Professions (G9)
---------------------------------------------------------------------------
step("professions: yours, a pretend crafter's recipes, the search and a request with a tip", function(c)
  local Pr, Pu = ns.Professions, ns.Purse
  -- What this client can read of professions (⚠ in Forever): the game's functions, and this character's own.
  local T = C_TradeSkillUI
  c:Note(("profession functions: GetProfessions %s, the skill list %s, recipes %s, recipe names %s"):format(
    tostring(GetProfessions ~= nil), tostring(GetSkillLineInfo ~= nil), tostring(T ~= nil and T.GetAllRecipeIDs ~= nil),
    tostring((C_Spell and C_Spell.GetSpellName) ~= nil or GetSpellInfo ~= nil)))
  local names = {}
  for _, x in ipairs(Pr.Mine()) do
    names[#names + 1] = ("%s %d/%d%s"):format(x.n, x.r, x.m, x.has and " (recipes read)" or "")
  end
  c:Note(#names > 0 and ("your professions: " .. table.concat(names, ", ")) or "this character has no professions")
  -- A pretend blacksmith shares a real recipe (Arcanite Reaper), so this client can name it.
  local REAPER = 16994
  Pe:Do("Fenwick", { k = "pro", c = { ["164"] = { n = "Blacksmithing", i = 136241, r = 300, m = 300, rc = { REAPER }, rt = time() } } })
  c:That(c:Until(function() return (g().crafts or {})[Pe:Full("Fenwick")] ~= nil end, 3), "Fenwick's Blacksmithing reached you")
  local name = Pr.RecipeName(REAPER)
  if name then
    local found = Pr.Search(g(), name:sub(1, 6))
    c:That(found[1] ~= nil and found[1].rid == REAPER, "the search finds " .. name)
  else
    c:Note("this client has no name for spell " .. REAPER .. ": the search was not tried")
  end
  c:Eq((Pr.WhoKnows(g(), REAPER)[1] or {}).char, Pe:Full("Fenwick"), "Fenwick can make it")
  -- Odo asks for it with a 3 g tip, Fenwick takes it, and Odo got it.
  Pe:Do("Odo", { k = "craft", rid = REAPER, what = "Selftest: Arcanite Reaper", n = 1, tip = 3, p = "gold" })
  local id
  c:That(c:Until(function()
    for k, rq in pairs(g().crafting or {}) do if rq.by == Pe:Full("Odo") then id = k end end
    return id ~= nil
  end, 3), "Odo's request reached you")
  if not id then return end
  Pe:Do("Fenwick", { k = "craft_take", id = id, on = true })
  c:That(c:Until(function() local s = Pr.Request(g(), id) return s and s.st == "taken" end, 3), "Fenwick took it")
  Pe:Do("Odo", { k = "craft_got", id = id, to = Pe:Full("Fenwick") })
  c:That(c:Until(function() local s = Pr.Request(g(), id) return s and s.st == "got" end, 3), "Odo got it")
  local owed = 0
  for _, d in ipairs(Pu:Open(g())) do if d.w == "craft" and d.to == P:Of(Pe:Full("Fenwick")) then owed = owed + d.amt end end
  c:Eq(owed, 3 * Pu.GOLD, "Odo owes Fenwick the 3 g tip")
  -- A request of my own, taken back.
  local ok, mine = Pr.Ask(REAPER, "Selftest: Arcanite Reaper", 2, true, nil)
  c:That(ok, "you ask for 2 Arcanite Reapers")
  c:That(c:Until(function() local s = Pr.Request(Pe:Get("Mirelle").g, mine) return s and s.st == "open" end, 3),
    "Mirelle's addon has it")
  c:That(Pr.Drop(mine), "you take it back")
  c:Eq(Pr.Request(g(), mine).st, "dropped", "taken back")
end)

-- The Calendar (SPEC decision 61): what the game's calendar gives this client, an officer's own event changed and
-- removed, a member's refused, and the page's two views.
step("calendar: the game's guild events, an officer's own event, Month and Agenda", function(c)
  local Ag, Cal = ns.Agenda, ns.Calendar
  local now = time()
  local function find(name)
    for _, e in ipairs(Ag.List(g(), Ag.DayStart(now), now + 40 * Ag.DAY, now)) do
      if e.name == name then return e end
    end
  end
  -- (⚠ In Forever: whether the calendar is on, and what it lists.)
  local games = 0
  for _, e in ipairs(Ag.List(g(), Ag.DayStart(now) - 31 * Ag.DAY, now + 62 * Ag.DAY, now)) do
    if e.game then games = games + 1 end
  end
  c:Note(("the game's calendar: %s; its month info: %s; the guild's events in it, near now: %d"):format(
    Cal.On() and "on" or "off", tostring(C_Calendar ~= nil and C_Calendar.GetMonthInfo ~= nil), games))
  -- Mirelle, an officer, adds one; it reaches you; she changes it.
  Pe:Do("Mirelle", { k = "cal_add", name = "Selftest: Raid night", at = now + Ag.DAY, line = "Bring flasks" })
  c:That(c:Until(function() return find("Selftest: Raid night") ~= nil end, 3), "Mirelle's event reached you")
  local e = find("Selftest: Raid night")
  if not e then return end
  Pe:Do("Mirelle", { k = "cal_edit", id = e.own, name = "Selftest: Raid night, moved", at = now + 2 * Ag.DAY,
    line = "Bring flasks" })
  c:That(c:Until(function() return find("Selftest: Raid night, moved") ~= nil end, 3), "she moved it")
  -- Fenwick, a member, may not add one.
  Pe:Do("Fenwick", { k = "cal_add", name = "Selftest: Fenwick's party", at = now + Ag.DAY })
  c:That(not c:Until(function() return find("Selftest: Fenwick's party") ~= nil end, 1), "a member's event is refused")
  -- Removed: by you when you lead the guild, else by Mirelle.
  if D:InCharge() then c:That(Ag.Remove(e.own), "you remove it, as Guild Master")
  else Pe:Do("Mirelle", { k = "cal_off", id = e.own }) end
  c:That(c:Until(function() return find("Selftest: Raid night, moved") == nil end, 3), "it is gone")
  -- The page: Month, then Agenda, then back to what you had.
  if not windowOpen() then return c:Note("the guild window is closed: the page was not looked at") end
  local was = ns.char.calView
  Hall:Show("calendar")
  local page = Hall.pages.calendar.frame
  c:That(Hall.current == "calendar" and page.rightFlow.items.switch ~= nil, "the Calendar opens, with the switch")
  page.rightFlow.items.switch.buttons.month:Click()
  c:That(page.rightFlow.items.nav ~= nil and page.rightFlow.items.nav:IsShown(), "Month: the month's days")
  page.rightFlow.items.switch.buttons.agenda:Click()
  c:Eq(ns.char.calView, "agenda", "Agenda, kept for this character")
  ns.char.calView = was
  Hall:Refresh()
end)

-- The punishment rules (SPEC decision 69): a pretend member opts out and cannot be punished; the rules are written out.
step("rules: opting out, punishments by reason, and the rules for everyone", function(c)
  local Ru, St = ns.Rules, ns.Stocks
  local k = Pe:Get("Korgath")
  c:That(Pe:Do("Korgath", { k = "optout", on = true }), "Korgath opts out of punishments")
  c:That(c:Until(function() return Ru.Out(g(), k.name) end, 3), "your addon knows")
  St.Sentence(k.name, "dunce", nil, "Selftest: pulled the boss")
  c:Wait(0.5)
  local s = St.List(g())[1]
  c:That(s and s.se.to == k.name and s.st == "void", "a punishment for him does nothing")
  local text = Ru.Text(g())
  c:That(#text >= 2 and #text[1].lines >= 3, "the rules are written out (" .. #text[1].lines .. " lines on why)")
  c:Note("the rules now: " .. table.concat(text[1].lines, " | "))
  Pe:Do("Korgath", { k = "optout", on = false })
  c:That(c:Until(function() return not Ru.Out(g(), k.name) end, 3), "Korgath is back in")
end)

step("rules: the guild's setup, a vote on it, and a Warcouncil, with pretend members", function(c)
  local Ru, Co = ns.Rules, ns.Council
  c:Eq(Ru.Setup(g()), "democracy", "the pretend guild is a Democracy")
  c:Eq(Ru.Text(g())[1].lines[1], L.RU_SETUP_IS:format(L.SETUP_DEMOCRACY), "the rules for everyone start with it")
  -- A guild vote on a Monarchy: Fenwick puts it, three second it, four vote yes.
  Pe:Do("Fenwick", motionOp("setup", { setup = "monarchy", why = "Selftest: a king for us" }))
  c:That(c:Until(function() return newestMotion("setup") ~= nil end, 3), "Fenwick puts a Monarchy to the vote")
  local id = newestMotion("setup")
  if not id then return end
  for _, n in ipairs({ "Mirelle", "Korgath", "Odo" }) do Pe:Do(n, { k = "motion_sec", id = id }) end
  for _, n in ipairs({ "Fenwick", "Mirelle", "Korgath", "Odo" }) do Pe:Do(n, { k = "motion_vote", id = id, on = true }) end
  c:That(c:Until(function() return Co.Motion(g(), id).yes == 4 end, 3), "seconded and voted")
  c:Eq(Ru.Setup(g()), "democracy", "while the guild votes, nothing changes")
  c:Eq(Co.Motion(g(), id, time() + 3 * 86400 + 60).phase, "passed", "it passes when the vote ends")
  if windowOpen() and not InCombatLockdown() then
    Hall:Open("settings")
    Hall:ShowFeature("settings", "setup")
    local page = Hall.pages.settings.frame
    c:That(page.setupRadios and page.setupRadios.democracy:GetChecked(), "Guild settings shows the Democracy")
    c:That(page.setupRadios.democracy.tag:IsShown() and not page.setupRadios.monarchy.tag:IsShown(),
      "on its card, In force")
    shot(c, "Guild settings: the guild's setup, as cards")
    page.setupRadios.warcouncil:Click()
    local b = page.setupRight.foot.buttons[1]
    c:Eq(b and b:IsShown() and b:GetText(), L.SET_SETUP_VOTE, "in a Democracy a change goes to the vote")
    page.setupPick = nil
    -- The vote on it as a ballot card: yes and no as bars.
    Hall:ShowFeature("council", "votes")
    Hall:Refresh()
    local bars = false
    for key, it in pairs(Hall.pages.council.frame.rightFlow.items) do
      if key:match("^rc%d+v$") and it:IsShown() then bars = true end
    end
    c:That(bars, "the vote shows as a ballot card, yes and no as bars")
    shot(c, "the Council's Votes: a change of setup as a ballot card")
    Hall:Close()
  else
    c:Note("open the guild window (out of combat) to check the setup in Guild settings")
  end
  -- A Warcouncil of the officers: you and Mirelle. Only the council files motions and votes. The new setup is a
  -- moment: on the alert line, and said in guild chat by your addon (never sent from the pretend guild).
  Co:Moments(g())
  -- (The log keeps its last lines only: empty it, so what comes is all new.)
  for i = #ns.Alerts.log, 1, -1 do ns.Alerts.log[i] = nil end
  SB:Govern("warcouncil")
  c:That(c:Until(function() return SB:Governed("warcouncil") end, 4), "the pretend guild is a Warcouncil")
  Co:Moments(g())
  local shown = false
  for _, a in ipairs(ns.Alerts.log) do
    if a.sub == L.AN_ALERT_SETUP_SUB:format(L.SETUP_WARCOUNCIL) then shown = true end
  end
  c:That(shown, "the new setup plays on the alert line")
  local said = false
  for _, x in ipairs(ns.Announce.log) do
    if x.text:find(L.AN_SETUP_NOW:format(L.SETUP_WARCOUNCIL):sub(1, 30), 1, true) then said = true end
  end
  c:That(said, "and your addon says it in guild chat")
  local voters = Ru.Voters(g()) or {}
  c:Eq(#voters, 2, "the council: you and Mirelle")
  c:That(not D:Can("motion", Pe:Full("Fenwick")), "Fenwick is not on it: no motions")
  c:That(Co.Propose("ptrial", false, "Selftest: no duels"), "you put Trial by combat off to the council")
  local rid = newestMotion("rule")
  c:That(rid ~= nil and Co.Veto(rid), "and veto it, as the Guild Master")
  c:That(rid ~= nil and c:Until(function() return Co.Motion(g(), rid).phase == "vetoed" end, 3), "vetoed")
  SB:Govern("democracy")
  c:That(c:Until(function() return SB:Governed("democracy") end, 4), "and a Democracy again")
end)

step("one player: a pretend member's alt is the same player", function(c)
  local Pu, Du, me = ns.Purse, ns.Duels, ns.Self()
  local k = Pe:Get("Korgath")
  local alt = Pe:Full("Korgoth")
  local owed = Pu:Owed(g(), P:Of(k.name), P:Of(me))
  c:That(Pe:Do("Korgath", { k = "player", id = k.id, m = k.name, c = { alt, k.name } }), "Korgath's addon names his alt")
  c:That(c:Until(function() return P:Of(alt) == P:Of(k.name) end, 3), "Korgoth is Korgath")
  c:Eq(P:Name(P:Of(alt)), k.name, "shown by his main's name")
  c:Eq(Pu:Owed(g(), P:Of(alt), P:Of(me)), owed, "the alt owes what Korgath owes")
  c:That(ns.Stocks.Punishable(g(), P:Of(alt)), "and can be punished too")
  local rated
  for _, e in ipairs(Du.Ladder(g())) do if e.key == P:Of(alt) then rated = e.r end end
  c:That(rated ~= nil, "with Korgath's ladder rating: " .. tostring(rated))
end)

step("you: a player card, your options and the right-click menu", function(c)
  local k = Pe:Get("Korgath")
  c:That(ns.Card.hooked == true or not (Menu and Menu.ModifyMenu), "our buttons are in the game's player menus")
  -- The menu's buttons, as the game would add them (the real menu opens only with a right-click).
  local items = {}
  local root = { CreateDivider = function() end, CreateTitle = function(_, t) items[#items + 1] = t end,
    CreateButton = function(_, t) items[#items + 1] = t return { SetEnabled = function() end } end }
  ns.Card.Fill(root, { name = k.name })
  c:Eq(table.concat(items, ", "), table.concat({ ns.Guild() or L.ADDON_NAME, L.AR_CHALLENGE, L.CARD_MENU_DEATHROLL, L.CARD_MENU }, ", "),
    "a right-click on Korgath")
  if not windowOpen() then c:Skip("the guild window is closed: the cards are not opened") return end
  Hall:Open("home")
  ns.Card:Show(k.name)
  c:That(ns.Side:IsShown() and ns.Side.frame.title:GetText() == ns.Display(k.name),
    "Korgath's player card in the panel, beside the list")
  ns.Side:Dismiss()
  c:That(ns.Side.over == nil, "closed again")
  ns.Card:Options()
  c:Eq(Hall.current .. ":" .. Hall.pages.home.frame.part, "home:options", "your options: Home's last feature")
  c:That(Hall.pages.home.frame.rightFlow.items.dress ~= nil, "with Dress the guild window")
  c:That(Hall.pages.home.frame.rightFlow.items["tourAgain.1"] ~= nil, "and Show me around (the tour again)")
  -- Beside them, a picture of your screen with the alert line where and how big you picked (the 1 Nov check).
  c:Eq(ns.Side.key, "opt:screen", "beside your options, a picture of your screen")
  local pf = ns.Side.frame.flows.home
  local pv = pf and pf.items.alertPreview
  c:That(pv ~= nil and pv:IsShown() and pv.line:IsShown(), "with the alert line on it")
  Hall:Close()
end)

step("flavour: guild chat lines, emotes and alerts (nothing is said from the pretend guild)", function(c)
  local An, Al, St = ns.Announce, ns.Alerts, ns.Stocks
  local k = Pe:Get("Korgath")
  -- (The log keeps its last lines only: once full, its length no longer grows, so start it empty.)
  for i = #An.log, 1, -1 do An.log[i] = nil end
  for i = #Al.log, 1, -1 do Al.log[i] = nil end
  local from, alerts = 0, 0
  c:That(St.Sentence(k.name, "dunce", nil, "Selftest: rolled need"), "Korgath sentenced to the Dunce Cap")
  local line, emote
  for i = from + 1, #An.log do
    local x = An.log[i]
    if x.kind == "GUILD" and x.text:find(L.AN_PUN_DUNCE, 1, true) then line = x end
    if x.kind == "EMOTE" then emote = x end
  end
  c:That(line ~= nil, "the guild chat line: " .. (line and line.text or "none"))
  c:That(emote ~= nil, "the emote: " .. (emote and emote.text or "none"))
  c:That(line and not line.sent and emote and not emote.sent and #An.queue == 0, "neither is sent from the pretend guild")
  c:That(#Al.log > alerts, "an alert for the sentence")
  c:That(Al.frame ~= nil, "the alert frame is built")
  Al:Push({ text = ns.Guild() or L.ADDON_NAME, sub = "Self-test: alerts show here", test = true })
  c:That(Al.cur ~= nil, "an alert shows on your screen")
  local here = ns.Punish.Here()
  if here then
    c:That(ns.Games.Open("flash", time() + 5, 1, 0, { spot = here }), "a meet-up in 5 seconds")
    local id = game("flash")
    Al.shown[id] = nil
    Al:Tick()
    c:Eq(Al.log[#Al.log].text, "5", "its countdown starts")
    ns.Games.Cancel(id)
  end
end)

step("seasons, Monday's Gazette and sounds", function(c)
  local Du, Al = ns.Duels, ns.Alerts
  local s = Du.Now(g())
  c:That(s.from <= time() and time() < s.to, "this season of the duel ladder: " .. Du.SeasonName(s))
  c:Eq(Du.SeasonName(Du.Season("month", 1790812800 + 86400)), L.AR_SEASON_MONTH:format(L["TS_MONTH_" .. 10], 2026),
    "1 October 2026 is in October")
  if not inGame() then c:Note("the sounds and the toast are checked in the game") return end
  local missing = {}
  for kind, name in pairs(ns.UI.SOUNDS) do
    if not (SOUNDKIT and SOUNDKIT[name]) then missing[#missing + 1] = kind .. " (" .. name .. ")" end
  end
  c:That(#missing == 0, #missing == 0 and "the game has each of our sounds" or ("no sound for: " .. table.concat(missing, ", ")))
  Al:ShowToast(ns.Chronicle.Gazette(g(), time()))
  c:That(Al.toast and Al.toast:IsShown(), "the Gazette's toast shows (it goes by itself)")
end)

step("manage: a feature switched off hides for everyone, and comes back", function(c)
  local key = "games:game"
  ns.Sync:ChangeSettings(function(s) s.off = s.off or {}; s.off[key] = true end)
  c:That(not D:On(key), "you switch off Guild games")
  c:That(c:Until(function() return peersHave(function(p) return not D:On(key, p.g) end) end, 3), "off in every pretend member's addon")
  local function listed()
    for _, x in ipairs(Hall:Features("games")) do if x.page == "games" and x.id == "game" then return true end end
    return false
  end
  if Hall.frame then c:That(not listed(), "Games no longer lists it") end
  ns.Sync:ChangeSettings(function(s) s.off[key] = nil end)
  c:That(D:On(key), "you switch it on again")
  c:That(c:Until(function() return peersHave(function(p) return D:On(key, p.g) end) end, 3), "on again for everyone")
end)

---------------------------------------------------------------------------
-- Scenes and shared looks (SPEC decision 60, UI/Stage.lua, UI/Scenes.lua, Guild/Looks.lua)
---------------------------------------------------------------------------
-- Real characters only (SPEC decision 63, as Journey Together): our own model is kept, a pretend member never near is
-- a class crest.
step("scenes: real characters for those near you, a class crest for the rest", function(c)
  local Lk, k = ns.Looks, Pe:Get("Korgath")
  local mine = Lk:Model(ns.Self(), "panel")
  c:That(mine ~= nil and mine.isModel, "our own model is kept for the scenes")
  c:That(Lk:Model(k.name, "panel") == nil, "a guildmate who has not been near: no model")
  c:Note(("guildmates whose models are kept this session: %d"):format((function()
    local n = 0
    for name, m in pairs(Lk.frames.panel) do if m.loaded and name ~= ns.Self() then n = n + 1 end end
    return n
  end)()))
end)

-- A flow of our own, off the screen, for drawing scenes.
local function sceneFlow()
  local holder = ST.sceneHolder or CreateFrame("Frame", nil, UIParent)
  ST.sceneHolder = holder
  holder:SetSize(360, 600)
  holder:ClearAllPoints()
  holder:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 50, -50)
  holder:Show()
  local f = setmetatable({ card = holder, width = 360, top = 0, pad = 0, items = {}, used = {} }, ns.UI.Flow)
  return f, holder
end

step("scenes: every activity's scene, honest dice, the Wheel and moments that play once", function(c)
  local Sg, Sc, St = ns.UI.Stage, ns.Scenes, ns.Stocks
  local me = ns.Self()
  local k, fw = Pe:Get("Korgath"), Pe:Get("Fenwick")
  local f, holder = sceneFlow()
  local function draw(name, fn)
    f:Begin()
    local ok, err = pcall(fn)
    c:That(ok, ok and (name .. " draws") or (name .. ": " .. tostring(err)))
    return f.items.stage
  end
  -- The deathroll: the die shows "?" until the game gives the roll, then exactly that number; a moment plays once.
  local dr = { id = "st-dr", opp = k.name, s = 500, st = "playing", rolls = {} }
  local s = draw("the deathroll", function() Sc.Deathroll(f, dr) end)
  c:That(s ~= nil and s.cast.me ~= nil and s.cast.op ~= nil, "a stage with both players on it")
  c:That(s and s.cast.me.isModel and not s.cast.op.isModel, "you as your character, Korgath (not near) as his crest")
  c:Eq(s and s.cast.op.iconKind, "class", "his class's icon, never a made-up face")
  -- A pulse never grows a texture (a growing texture filled the whole scene in the game: the curse's glow).
  local probe = UIParent:CreateTexture()
  local grows = false
  for _, a in ipairs({ ns.UI.Visuals.Pulse(probe, 1.2):GetAnimations() }) do
    if a.GetObjectType and a:GetObjectType() == "Scale" then grows = true end
  end
  c:That(not grows, "a texture's pulse breathes in alpha: it never grows")
  c:Eq(s and s.props["die.n"]:GetText(), "?", "no roll yet: the die shows ?")
  dr.rolls[1] = { who = "me", v = 312 }
  draw("the deathroll's first roll", function() Sc.Deathroll(f, dr) end)
  c:Eq(s and s.props["die.n"]:GetText(), "312", "it lands on the game's roll")
  c:That(s and not s:New("roll1"), "and that moment does not play again")
  dr.rolls[2], dr.st, dr.loser = { who = "them", v = 1 }, "over", "them"
  draw("the deathroll's last roll", function() Sc.Deathroll(f, dr) end)
  c:That(s and s.props["die.red"]:IsShown(), "a 1 is red")
  -- Every other scene, with the pretend guild's data where it has some, and made-up states where it has not.
  local gg = g()
  draw("the high roll", function()
    Sc.HighRoll(f, { st = "done", h = k.name, max = 100, j = { [k.name] = 1, [fw.name] = 2 }, r = { [k.name] = 64, [fw.name] = 12 },
      hi = k.name, lo = fw.name, amt = 52, p = "gold", te = time() }, "st-ro")
  end)
  local drawn = draw("the lottery", function()
    Sc.Lottery(f, { st = "done", h = fw.name, w = k.name, roll = 5, sold = 8, td = time() }, "st-ra")
  end)
  -- Where a prop stands in the scene (x, y from its top left).
  local function at(p) local _, _, _, x, y = p:GetPoint(1) return x, -y end
  if drawn and drawn.props.die and drawn.props["drum.rim"] then
    local rim, die = drawn.props["drum.rim"], drawn.props.die
    local _, ry = at(rim)
    local _, dy = at(die)
    c:That(dy + die:GetHeight() / 2 <= ry - rim:GetHeight() / 2, "the die clears the drum's rim")
  end
  -- The lottery's drum (the second check of 1 November): a ticket in it for each one sold.
  local drum = draw("the lottery's drum", function()
    Sc.Lottery(f, { st = "open", h = fw.name, prize = "Pet", price = 1,
      b = { [k.name] = { n = 2, t = 1 }, [me] = { n = 1, t = 2 } } }, "st-ra2")
  end)
  c:That(drum and drum.props.drum:IsShown() and drum.props.t3 and drum.props.t3:IsShown()
    and not (drum.props.t4 and drum.props.t4:IsShown()), "the drum holds the three tickets sold")
  c:Eq(drum and drum.props.sold:GetText(), L.STAGE_DRUM:format(3), "and says how many")
  -- A round drum with the tickets inside its wheel (the third check of 1 November: a box that read as a screen).
  if drum and drum.props.drum then
    local d = drum.props.drum
    local cx, cy = at(d)
    local r, inside = d:GetWidth() / 2, math.abs(d:GetWidth() - d:GetHeight()) < 0.5
    for i = 1, 3 do
      local t = drum.props["t" .. i]
      local tx, ty = 0, 0
      if t then tx, ty = at(t) end
      if not t or (tx - cx) ^ 2 + (ty - cy) ^ 2 > (r - 10) ^ 2 then inside = false end
    end
    c:That(inside, "a round drum, every ticket inside it")
  end
  -- An impeachment while its voters vote: a seal on the scroll for each vote, a ring for each to come.
  local seals = draw("an impeachment's votes", function()
    Sc.Lead(f, g(), { id = "st-imp", phase = "vote", cast = 2, n = 4, mo = { kind = "lead", gm = me, a = k.name } })
  end)
  c:That(seals and seals.props.seal4 and seals.props.seal4:IsShown() and not (seals.props.seal5 and seals.props.seal5:IsShown()),
    "a place for each of the four voters")
  c:Eq(seals and seals.props.count:GetText(), L.STAGE_SEALS:format(2, 4), "two seals down")
  -- A tournament's sign-up: the entrants at the arena's gate.
  local gate = draw("a tournament's sign-up", function()
    Sc.Cup(f, g(), { st = "open", j = { [k.name] = { on = true, t = 1 }, [fw.name] = { on = true, t = 2 } } }, "st-cupopen")
  end)
  c:That(gate and gate.cast.e2 ~= nil and gate.props.arch:IsShown(), "both entrants at the arena's gate")
  -- A bracket: its rounds named, each player with their class icon.
  f:Begin()
  local br = f:Bracket("br", { { col = 1, a = k.name, b = fw.name, w = k.name }, { col = 1, a = me, b = Pe:Get("Odo").name, w = me },
    { col = 2, a = k.name, b = me, live = true } }, nil)
  c:Eq(br.heads[1]:GetText() .. "/" .. br.heads[2]:GetText(), L.BR_SEMI .. "/" .. L.BR_FINAL, "a bracket's rounds named")
  c:That(br.boxes[1].ia:IsShown() and br.boxes[1].ib:IsShown(), "each player with their class icon")
  br:Hide()
  draw("the duels", function() if Sc.HasDuels(gg) then Sc.Duels(f, gg) end end)
  draw("the duel crown", function() Sc.Crown(f, { holder = P:Of(k.name, gg), name = k.name, since = time() }) end)
  local cup, cid = ns.Cup.Current(gg)
  if cup then draw("a tournament", function() Sc.Cup(f, gg, cup, cid) end) end
  draw("Secret target", function() Sc.Target(f, "st-as", k.name) end)
  for _, pun in ipairs(D.PUNISHMENTS) do
    local se = { pun = pun, t = time(), by = me, to = k.name, tom = { [me] = 2 }, z = { "Elwynn Forest", "Westfall" } }
    local st = { id = "st-" .. pun, se = se, pun = pun, key = P:Of(k.name, gg), st = "active", n = 3, i = 1,
      auction = pun == "servant", master = pun == "servant" and fw.name or nil, price = 12 }
    if pun == "wheel" then st.pun, st.spun = "dunce", { r = "dunce", t = time() } end
    if pun == "trial" then st.st, st.trial = "trial", true end
    draw("the punishment " .. pun, function() Sc.Sentence(f, gg, st) end)
  end
  draw("a pardon", function()
    Sc.Sentence(f, gg, { id = "st-free", se = { pun = "stocks", t = time() - 60, by = me, to = k.name }, pun = "stocks",
      key = P:Of(k.name, gg), st = "done", how = "pardoned", ends = time() })
  end)
  -- The Wheel stands with the result under its pointer: the medallion of "dunce" (second) at the top.
  local w = f.items.stage and f.items.stage.props.wheel
  if w then
    ns.UI.Visuals.WheelRest(w, St.WHEEL, 2)
    c:That(math.abs(w.items[2].dx) < 0.5 and w.items[2].dy > 0, "the Wheel stops with the result under the pointer")
  end
  for _, x in ipairs(ns.Games.List(gg)) do
    draw("the game " .. x.ga.kind, function() Sc.Game(f, gg, x.ga, x.id, P:Of(me, gg)) end)
  end
  draw("a vote", function() Sc.Vote(f, { id = "st-poll" }, 1) end)
  for _, ms in ipairs(ns.Council.Motions(gg, nil, "lead")) do
    draw("leadership: " .. ms.mo.kind, function() if ms.cup then Sc.Cup(f, gg, ms.cup, ms.id) else Sc.Lead(f, gg, ms) end end)
  end
  for _, cs in ipairs(ns.Court.Cases(gg)) do draw("the court", function() Sc.Court(f, cs) end) end
  local rules = draw("the rules", function() Sc.Rules(f, gg) end)
  if gg.charter and rules then
    c:That(tostring(rules.props.text:GetText()):find("^1%. ") ~= nil, "the rules written on the parchment")
  end
  -- The character moves the scenes use, on our own model (only the game can tell).
  local own = ns.Looks:Model(ns.Self(), "panel")
  if inGame() and own and own.HasAnimation then
    local m, missing = own, {}
    for move, id in pairs(Sg.MOVES) do if not m:HasAnimation(id) then missing[#missing + 1] = move end end
    table.sort(missing)
    c:Note(#missing == 0 and "our model has every move" or ("moves our model lacks (or not loaded yet): " .. table.concat(missing, ", ")))
  end
  -- The places' backdrops (Media\Stage<Place>, Alliance and Horde).
  if inGame() then
    local t, missing = UIParent:CreateTexture(), {}
    for _, name in pairs(Sg.PLACES) do
      for _, side in ipairs({ "", "Horde" }) do
        if t:SetTexture(ns.MEDIA .. "Stage" .. side .. name) == false then missing[#missing + 1] = "Stage" .. side .. name end
      end
    end
    t:Hide()
    c:That(#missing == 0, #missing == 0 and "every place's backdrop loads" or ("missing: " .. table.concat(missing, ", ")))
  end
  if f.items.stage then f.items.stage:Hide() end
  holder:Hide()
  c:That(own == nil or own.stage == nil, "our model went back off the stage")
end)

step("scenes: the alert line's medals and the Wheel", function(c)
  local Al = ns.Alerts
  if not Al.frame then c:Skip("the alert line is made after login, out of combat") return end
  Al:Push({ text = L.AN_ALERT_CROWN, sub = "", icon = "crown", test = true, now = true })
  c:That(Al.frame.medal:IsShown() and not Al.frame.crest:IsShown(), "a crown alert shows the crown")
  Al:Push({ text = L.AL_WHEEL:format(ns.Display(ns.Self())), sub = "", test = true, now = true,
    wheel = { slices = ns.Stocks.WHEEL, r = "curse" } })
  local w = Al.frame.wheel
  c:That(w:IsShown(), "the Wheel turns on the alert line")
  local at = 3
  c:That(w.items[at] and math.abs(w.items[at].dx) < 0.5 and w.items[at].dy > 0, "it lands on the real result")
  c:That(not Al.frame.scene:IsShown(), "the Wheel is the moment: no scene under it")
  -- A moment with its scene under the line (SPEC decision 63): a deathroll's roll, played large, for a few seconds.
  local k = Pe:Get("Korgath")
  local dr = { id = "st-toast", opp = k.name, st = "playing", s = 500, rolls = { { who = "me", v = 312 } } }
  if Hall.frame then Hall:Close() end
  Al:Push({ text = L.TV_DEATHROLL, sub = L.AL_DR_YOU:format(312), test = true, now = true, quiet = true,
    scene = { page = "tavern", draw = function(f) ns.Scenes.Deathroll(f, dr) end } })
  c:That(Al.frame.scene:IsShown(), "a deathroll's roll plays its scene under the line")
  c:That(Al.frame.scene.stage.cast.me ~= nil and Al.frame.scene.stage.cast.op ~= nil, "with both players on its stage")
  c:That(math.abs(Al.frame.scene:GetWidth() - Al.SCENE_W) < 0.5, "large (" .. Al.frame.scene:GetWidth() .. " wide)")
  c:That(Al.frame.scene.rim ~= nil and Al.frame.scene.rim:IsShown(), "framed as the game's banners: a gold edge and its corners")
  -- Never over the guild window (asked for on 1 Nov 2026) nor our bar and panel under it (its crest sat on the bar:
  -- the third check of 1 November), with the panel closed and open; and where and how big the player picks.
  if windowOpen() and inGame() then
    local function clear()
      Al:Place()
      local a, ok = rect(Al.frame), true
      for _, fr in ipairs({ CommunitiesFrame, Hall.bar, Hall.frame }) do
        local b = fr and fr:IsVisible() and rect(fr)
        if b and a and not (a.right <= b.left + 1 or a.left >= b.right - 1 or a.top <= b.bottom + 1
          or a.bottom >= b.top - 1) then ok = false end
      end
      return a ~= nil and ok
    end
    c:That(clear(), "the alert line keeps off the guild window and the bar")
    Hall:Open("home")
    c:That(clear(), "and off the panel when it is open")
    Hall:Close()
    Al:Place()
  end
  local S = ns.Settings
  local spot, size = S:Get("alertSpot"), S:Get("alertSize")
  S:Set("alertSpot", "bottom")
  S:Set("alertSize", "large")
  Al:Place()
  local p = Al.frame:GetPoint(1)
  c:That(p == "BOTTOM" and math.abs(Al.frame:GetScale() - Al.SIZES.large) < 0.01, "above the action bars, large, when picked")
  S:Set("alertSpot", spot)
  S:Set("alertSize", size)
  Al:Place()
  c:Wait(3)
  Al.queue, Al.cur = {}, nil
  Al.frame:Hide()
end)

-- P19 (SPEC decision 75): a player's card on their name, the records as a trophy wall and one changing hands, the
-- mascot alive and named on its page by the Guild Master, the Gazette as a front page, and a deed as it will read.
step("chronicle: a player's card, the trophy wall, a record changing hands, the mascot, the front page and a deed's preview", function(c)
  local UI, Ch, Side = ns.UI, ns.Chronicle, ns.Side
  local k = Pe:Get("Korgath")
  -- A player's name: the pointer on it shows their card; a right-click opens the whole one.
  local card = UI.PlayerSummary(k.name)
  c:That(card.title == UI.Who(k.name) and #card >= 2, ("Korgath's card on his name (%d lines)"):format(#card))
  local f = sceneFlow()
  f:Begin()
  f:Row("who", { name = UI.Who(k.name), sub = "" })
  f:Row("what", { name = L.CH_THE_GUILD, sub = "" })
  c:Eq(f.items.who and f.items.who.player, k.name, "a row with his name knows whose card it shows")
  c:That(f.items.what ~= nil and f.items.what.player == nil, "a row without a player's name shows none")
  -- The fish record: Mirelle (Fenwick, when she has it) catches more than its holder, and it changes hands.
  local function fishRow()
    for _, r in ipairs(Ch.Hall(g())) do if r.id == "fish" then return r end end
    return nil
  end
  local was = fishRow()
  local who = (was and was.key == P:Of(Pe:Full("Mirelle"))) and "Fenwick" or "Mirelle"
  local key = P:Of(Pe:Full(who))
  for i = #ns.Alerts.log, 1, -1 do ns.Alerts.log[i] = nil end
  local need = (tonumber(was and was.value) or 0) + 1
  while need > 0 do
    local n = math.min(100, need)
    Pe:Do(who, { k = "feed", n = n })
    need = need - n
  end
  c:That(c:Until(function() local r = fishRow() return r ~= nil and r.key == key end, 3), who .. " holds the fish record")
  if was then
    local heard = false
    for _, a in ipairs(ns.Alerts.log) do
      if a.text == L.AN_ALERT_RECORD:format(L.CH_HALL_FISH) then heard = true end
    end
    c:That(heard, "a record changing hands plays on the alert line")
  end
  c:That(Ch.Since(g(), "fish", key) ~= nil, "and its plaque knows since when")
  if not windowOpen() or InCombatLockdown() then c:Skip("the guild window is closed: the pages are not drawn") return end
  Hall:Open("chronicle")
  local page = Hall.pages.chronicle.frame
  -- The records as a trophy wall: a plaque each, its holder's card on it.
  Hall:ShowFeature("chronicle", "hall")
  Hall:Refresh()
  local wall = page.rightFlow.items.plaques
  local first = wall and wall.plaques and wall.plaques[1]
  c:That(first ~= nil and first:IsShown() and first.tipPlayer ~= nil, "the records as a trophy wall, a plaque each")
  local since = false
  for _, p in ipairs(wall and wall.plaques or {}) do
    if p:IsShown() and p.label:GetText() == L.CH_HALL_FISH then since = (p.sub:GetText() or "") ~= "" end
  end
  c:That(since, "the fish record's plaque says since when")
  if first and first.tipPlayer then
    UI.PlayerTip(first, first.tipPlayer, { first.tipTitle, first.tipText })
    shot(c, "a player's card on their name (a record's plaque)")
    GameTooltip:Hide()
  end
  -- The mascot: the pet itself on the square, beside its list, with its level, its mood and who feeds it.
  Hall:ShowFeature("chronicle", "mascot")
  Hall:Refresh()
  c:Eq(Side.key, "mascot", "beside the mascot's list: the pet itself")
  local pf = Side.frame.flows.chronicle
  c:That(pf ~= nil and pf.items.lv ~= nil and pf.items.lv:IsShown(), "with its level and the fish to the next")
  local b = Side.beside
  local st = (b and b:IsShown() and b.host.stage) or (pf and pf.items.stage)
  c:That(st ~= nil and st.props.pet ~= nil and st.props.bowl ~= nil, "the pet and its bowl on the square")
  shot(c, "the mascot, alive", true)
  local m = Ch.Mascot(g())
  local drawn = ns.Scenes.petDrawn[m.kind]
  if inGame() then
    c:Note(("the %s: %s"):format(m.kind, drawn == true and "the game drew its creature"
      or (drawn == false and "no creature drew: its medallion shows" or "still loading")))
  end
  -- The Guild Master names it here, as in Guild settings.
  local foot = Side.frame.pane.foot.buttons[1]
  c:Eq(foot and foot:IsShown() and foot:GetText(), L.CH_NAME_PET_DOTS, "the Guild Master names the pet on its page")
  local old, oldKind = m.name, m.kind
  if foot then foot:Click() end
  local vf = Side.frame.flows["chronicle:view"]
  local box = vf and vf.items.name
  c:Eq(box and box:GetText(), old, "the form has its name")
  if box then
    box:SetText("Selftest Snout")
    local save = Side.frame.pane.foot.buttons[1]
    if save then save:Click() end
    c:That(c:Until(function() return Ch.Mascot(g()).name == "Selftest Snout" end, 3), "renamed: Selftest Snout")
    ns.Sync:ChangeSettings(function(x)
      x.mascot.name = old
      x.mascot.kind = oldKind
    end)
    c:Until(function() return Ch.Mascot(g()).name == old end, 3)
  end
  page.View(nil)
  -- The Gazette: its front page in the right column, the week's stories in the list.
  Hall:ShowFeature("chronicle", "gazette")
  Hall:Refresh()
  c:That(tostring(Side.key):find("^gazette:") ~= nil, "the Gazette's front page beside its list (" .. tostring(Side.key) .. ")")
  local paper = Side.frame.flows.chronicle
  c:That(paper ~= nil and paper.items.hl ~= nil and paper.items.hl:IsShown(), "with this week's headline")
  c:That(page.rightFlow.items.st1 ~= nil and page.rightFlow.items.st1:IsShown(), "and the week's stories, biggest first")
  shot(c, "the Gazette as a front page", true)
  -- A deed as it will read in Deeds, while it is written.
  Hall:ShowFeature("chronicle", "deeds")
  page.View({ kind = "deed" })
  local df = Side.frame.flows["chronicle:view"]
  if df and df.items.who and df.items.what then
    df.items.who:SetText(k.name)
    df.items.what:SetText("Selftest: carried the bags")
    Hall:Refresh()
    local row = df.items.preview
    c:That(row ~= nil and row:IsShown() and row.sub:GetText() == "Selftest: carried the bags",
      "the deed as it will read, as you type")
    c:That(row ~= nil and row.player == k.name, "with Korgath's name on it")
    shot(c, "a deed as it will read")
    df.items.who:SetText("")
    df.items.what:SetText("")
  else
    c:That(false, "the deed form opens")
  end
  page.View(nil)
  Hall:Close()
end)

-- Fewer clicks, the game's calendar and scenes with a cast (SPEC decision 74). Nothing goes into the real calendar from
-- the pretend guild: Ag.PutInGame only sends what it would have done.
step("fewer clicks: features on the pointer, the gear for everyone, into the game's calendar, lines under names, seats and the court's calls", function(c)
  local Sc, Sg, Ag = ns.Scenes, ns.UI.Stage, ns.Agenda
  local me = ns.Self()
  local k, fw, odo = Pe:Get("Korgath"), Pe:Get("Fenwick"), Pe:Get("Odo")
  -- The scenes, off screen: what each player does under their name, and where they sit.
  local f = sceneFlow()
  local function draw(name, fn)
    f:Begin()
    local ok, err = pcall(fn)
    c:That(ok, ok and (name .. " draws") or (name .. ": " .. tostring(err)))
    return f.items.stage
  end
  local function said(s, role)
    local _, line = Sg.Tag(s and s.cast[role])
    return line and line:IsShown() and line:GetText() or nil
  end
  local function move(s, role) return s and s.cast[role] and s.cast[role].move end
  local missing = {}
  for _, mv in ipairs({ "sit", "stool", "chair", "bench" }) do if not Sg.MOVES[mv] then missing[#missing + 1] = mv end end
  c:That(#missing == 0, "the game's own sitting moves: on the ground, a stool, a chair and the high bench")
  local dr = draw("the deathroll", function()
    Sc.Deathroll(f, { id = "st18-dr", opp = k.name, s = 500, st = "playing", rolls = { { who = "me", v = 312 }, { who = "them", v = 64 } } })
  end)
  c:Eq(said(dr, "me"), L.STAGE_ROLLED:format(312), "under your name: what you rolled")
  c:Eq(said(dr, "op"), L.STAGE_ROLLED:format(64), "under Korgath's: his roll")
  c:That(move(dr, "me") == "stool" and dr.props["stool.me.seat"] ~= nil, "both on stools at the table")
  local myName, myLine = Sg.Tag(dr and dr.cast.me)
  c:That(myName ~= nil and myName:IsShown() and myName:GetText() == ns.Short(me) and myLine ~= nil and myLine:IsShown(),
    "you " .. (dr and dr.cast.me and dr.cast.me.isModel and "as your character" or "as your crest") .. ", with your name and line")
  local ro = draw("the high roll", function()
    Sc.HighRoll(f, { st = "rolling", h = k.name, max = 100, j = { [k.name] = 1, [fw.name] = 2 }, r = { [k.name] = 64 } }, "st18-ro")
  end)
  local kRole
  for role, m in pairs(ro and ro.cast or {}) do if m.who == k.name then kRole = role end end
  c:Eq(kRole and said(ro, kRole), L.STAGE_ROLLED:format(64), "the high roll: \"rolled 64\" under Korgath")
  -- The Stocks: the punished, a line under them; guildmates on the ground at the front, watching.
  local gg = g()
  local stocks = draw("the Stocks", function()
    Sc.Sentence(f, gg, { id = "st18-stocks", se = { pun = "stocks", t = time() - 30, by = me, to = k.name, tom = {} },
      pun = "stocks", key = P:Of(k.name, gg), st = "active" })
  end)
  c:Eq(said(stocks, "who"), L.STAGE_IN_STOCKS, "\"in the Stocks\" under Korgath")
  local watching = 0
  for i = 1, Sc.WATCHERS do if move(stocks, "w" .. i) == "sit" then watching = watching + 1 end end
  c:That(watching > 0, ("%d guildmates sit on the ground and watch"):format(watching))
  -- A council vote: the voters seated at the long table; you stand by the box until you vote.
  local vote = draw("a vote at the table", function()
    Sc.Vote(f, { id = "st18-poll", voters = { { name = k.name, t = 1 }, { name = fw.name, t = 2 } } }, nil)
  end)
  c:That(move(vote, "v1") == "chair" and move(vote, "v2") == "chair" and vote.props.table ~= nil, "two voters at the table")
  c:That(vote and vote.cast.me ~= nil and move(vote, "me") ~= "chair", "and you standing by the box")
  -- The court: in session, the judge on the high bench and the jury seated; at the verdict each juror's call.
  local case = { id = "st18-court", cs = { h = me, to = k.name, t = time() - 60 }, jurors = { fw.name, odo.name },
    guilty = 1, innocent = 1 }
  local court = draw("the court in session", function() Sc.Court(f, case) end)
  c:That(move(court, "judge") == "bench" and move(court, "j1") == "chair" and move(court, "j2") == "chair",
    "the judge on the high bench, the jury on theirs")
  c:That(said(court, "j1") == nil, "no juror's vote shows before the verdict")
  -- (Closed an hour ago: its moment does not play here, so the last picture shows at once.)
  case.id, case.cs.closed, case.verdict = "st18-court2", time() - 3600, "guilty"
  case.calls = { [fw.name] = "guilty", [odo.name] = "innocent" }
  court = draw("the court's verdict", function() Sc.Court(f, case) end)
  c:Eq(said(court, "j1"), L.STAGE_GUILTY_CALL, "Fenwick stands and calls \"Guilty!\"")
  c:Eq(said(court, "j2"), L.STAGE_NOT_GUILTY_CALL, "Odo \"Not guilty!\"")
  c:That(move(court, "j1") == "stand" and said(court, "judge") == L.STAGE_GUILTY_CALL, "then the judge calls the verdict")
  if gg.charter then
    local was = (gg.charterOk or {})[me]
    gg.charterOk = gg.charterOk or {}
    gg.charterOk[me] = gg.charter.v or 0
    local rules = draw("the rules accepted", function() Sc.Rules(f, gg) end)
    c:Eq(said(rules, "me"), L.STAGE_ACCEPTED_LINE, "\"accepted the rules\" under you")
    gg.charterOk[me] = was
  end
  -- Into the game's calendar: Mirelle, an officer, opens a fishing contest for tomorrow; it waits for you, the Guild
  -- Master, whose rank may make guild events.
  local now = time()
  local function waiting(key)
    for _, x in ipairs(Ag.ToGame(g())) do if not key or x.e.key == key then return x end end
  end
  Pe:Do("Mirelle", { k = "game", kind = "derby", at = now + 86400, len = 30, prize = 0, p = D:Settings().purse })
  local derby
  c:Until(function()
    for id, ga in pairs(g().games or {}) do
      if ga.kind == "derby" and ga.at == now + 86400 then derby = id end
    end
    return derby ~= nil
  end, 3)
  local x = derby and waiting("game:" .. derby)
  c:That(x ~= nil and x.what == "add", "Mirelle's contest waits for the game's calendar")
  if windowOpen() and not InCombatLockdown() then
    Hall:Open("home")
    Hall:Badges()
    c:That(Hall.tabs.calendar.badge.n > 0, "with a red number on the Calendar")
    -- Pointing at a place: its features in a small list under it, each with its status and red number.
    c:That(Hall:ShowFly(Hall.tabs.calendar, true), "pointing at the Calendar lists its features")
    local fly, row = Hall.fly, nil
    for _, r in ipairs(fly.rows) do if r:IsShown() and r.feat and r.feat.id == "togame" then row = r end end
    c:That(row ~= nil and row.badge.n >= 1, "For the game's calendar, with its red number")
    shot(c, "pointing at a place: its features, one waiting for the game's calendar")
    if row then row:Click() end
    local page = Hall.pages.calendar.frame
    c:Eq(page.part, "togame", "one click opens it")
    c:That(not fly:IsShown(), "and the list closes")
    local at = 1
    for i, w in ipairs(Ag.ToGame(g())) do if derby and w.e.key == "game:" .. derby then at = i end end
    local put = page.rightFlow.items["tgb" .. at .. ".1"]
    c:That(put ~= nil and put:IsShown(), "the contest, with Put it in")
    shot(c, "for the game's calendar: one click puts it in")
    if put then put:Click() end
  elseif x then
    Ag.PutInGame(x)
  end
  c:That(c:Until(function() return derby ~= nil and not waiting("game:" .. derby) end, 3), "in the calendar: it waits no more")
  local cur = derby and (g().calin or {})["game:" .. derby]
  c:That(cur ~= nil and cur.by == me, "the guild knows you put it in, so it shows once")
  -- Called off: out of the calendar, by you, who put it in.
  if derby then Pe:Do("Mirelle", { k = "game_off", id = derby }) end
  c:That(c:Until(function() local w = derby and waiting("game:" .. derby) return w ~= nil and w.what == "out" end, 3),
    "Mirelle calls it off: it waits for you to take it out")
  local out = derby and waiting("game:" .. derby)
  if out then Ag.PutInGame(out) end
  c:That(c:Until(function() return derby ~= nil and not waiting("game:" .. derby) end, 3), "taken out")
  if not windowOpen() or InCombatLockdown() then c:Skip("the guild window is closed: the bar was not looked at") return end
  -- The gear: Guild settings for the Guild Master, with Your options first; a member's opens Your options.
  c:Eq(Hall.tabs.manage:GetText(), L.PLACE_MANAGE_SHORT, "your gear: Guild settings")
  local feats = Hall:Features("manage")
  c:Eq(feats[1] and feats[1].id, "mine", "Your options first in it")
  Hall:ShowFeature("settings", "mine")
  local set = Hall.pages.settings.frame
  c:That(set.part == "mine" and set.mineFlow.items.alerts ~= nil and set.mineFlow.items.alerts:IsShown(),
    "the same options as Home's")
  shot(c, "Guild settings: Your options first")
  SB:SetRank(me, 3)
  c:Wait(0.3)
  Hall:Place()
  c:That(Hall.tabs.manage:IsShown() and Hall.tabs.manage:GetText() == L.OPT_TITLE, "as a member: the gear says Options")
  Hall:Close()
  Hall.tabs.manage:Click()
  c:That(Hall:IsOpen() and Hall.current == "home" and Hall.pages.home.frame.part == "options", "and opens Your options")
  shot(c, "a member's gear: Your options")
  SB:SetRank(me, 0)
  c:Wait(0.3)
  Hall:Place()
  c:That(D:InCharge(), "the Guild Master again")
  Hall:Close()
end)

-- The side tabs in a rail, the guild's name in the title band and a scene's moment over the guild chat (SPEC decision
-- 76). The Chat tab is the player's to click (ours would taint the window): with it open, the moment plays over the
-- real chat; else over a stand-in of ours where the chat would be.
step("the frame: the side tabs in a rail, the guild's name in the title band, a moment over the guild chat", function(c)
  if not windowOpen() or InCombatLockdown() then c:Skip("the guild window is closed") return end
  local Fr, Side, Sc, Sg = ns.Frame, ns.Side, ns.Scenes, ns.UI.Stage
  if not Fr:Dressed() then c:Skip("Dress the guild window is off: the game's own window, no rail or band") return end
  Hall:Open("home")
  Hall:Place()
  -- The rail: the frame's right side, with the side tabs inside it and their art in the guild's metal.
  c:That(Fr.rail ~= nil and Fr.rail:IsShown(), "the side tabs' rail beside the window")
  c:That((Fr.tinted or 0) > 0, ("the side tabs' art in the guild's metal (%d textures)"):format(Fr.tinted or 0))
  if inGame() then
    local rail, bar, panel, w = rect(Fr.rail), rect(Hall.bar), rect(Hall.frame), rect(CommunitiesFrame)
    c:That(rail and bar and panel and math.abs(rail.right - bar.right) <= 1 and math.abs(rail.right - panel.right) <= 1,
      "the frame's right edge runs straight down to the panel")
    local out, shown = {}, 0
    for _, key in ipairs(Fr.TABS) do
      local tab = CommunitiesFrame[key]
      local r = tab and tab:IsShown() and rect(tab)
      if r then
        shown = shown + 1
        if not (rail and w and r.left >= w.right - 2 and r.right <= rail.right + 1) then out[#out + 1] = key end
      end
    end
    c:That(#out == 0, #out == 0 and ("the %d side tabs shown sit inside the rail"):format(shown)
      or ("outside the rail: " .. table.concat(out, ", ")))
  end
  -- The title band: the guild's name, then its motto after a thin gold line; dragging the name moves the frame.
  local t = Fr.title
  c:Eq(t.name:GetText(), ns.Guild() or "", "the guild's name in the title band")
  local motto = D:Settings().theme.motto
  c:That(t.motto:IsShown() == (motto ~= nil and motto ~= ""),
    motto and ("its motto after it: " .. motto) or "no motto written: nothing after the name")
  c:That(t:GetScript("OnDragStart") ~= nil and t:IsMouseEnabled(), "dragging the name moves the frame")
  if inGame() then
    local band, w = rect(t), rect(CommunitiesFrame)
    c:That(band and w and band.top <= w.top + 1 and band.bottom >= w.top - (Fr.BAND + 4) * Fr:Scale(), "inside the title band")
  end
  shot(c, "the frame: the side tabs in a rail, the guild's name and motto in the title band")
  -- A moment over the guild chat: Korgath's roll in a deathroll, new on this screen.
  local stand
  if Side:ChatArea() then
    c:Note("the Chat tab is open: the moment plays over the guild chat")
  else
    stand = ST.chatStand or CreateFrame("Frame", nil, CommunitiesFrame)
    ST.chatStand = stand
    stand:SetSize(420, 300)
    stand:ClearAllPoints()
    stand:SetPoint("CENTER", CommunitiesFrame, "CENTER", 0, -10)
    stand:Show()
    Side.pretendChat = stand
    c:Note("the Chat tab is not open: the moment plays over a stand-in where the chat would be (open the Chat tab before /gtf test to see it over the real chat)")
  end
  local k = Pe:Get("Korgath")
  local dr = { id = "st20-dr", opp = k.name, s = 500, st = "playing",
    rolls = { { who = "me", v = 312 }, { who = "them", v = 64 } } }
  local before = Side.moments or 0
  Sg.replay = true
  wipe(Sg.played)
  Side:Over(function()
    return { key = "st20:moment", icon = ns.UI.ICON.dice, title = L.TV_DEATHROLL,
      draw = function(fl) Sc.Deathroll(fl, dr) end }
  end)
  local ch = Side.chat
  c:That((Side.moments or 0) > before and ch ~= nil and ch:IsShown(), "the roll plays large over the guild chat")
  c:That(ch ~= nil and not ch:IsMouseEnabled(), "letting the mouse through")
  local takes = 0
  for _, m in pairs(ch and ch.host.stage.cast or {}) do if m:IsMouseEnabled() then takes = takes + 1 end end
  c:Eq(takes, 0, "its characters too")
  c:That(ch ~= nil and Hall:Above(ch), "over the chat's messages and its scroll bar")
  local col = Side.frame.last and Side.frame.last.items.stage
  c:That(col ~= nil and col:IsShown(), "the column keeps the scene's picture")
  c:That(not (Side.beside and Side.beside:IsShown()), "and no window beside the panel")
  c:Wait(1.2)
  shot(c, "a moment over the guild chat: the roll plays large, the column keeps the picture")
  c:That(c:Until(function() return not ch:IsShown() end, Side.CHAT_STAY + 3), "then it fades, and the chat is back")
  Sg.replay = nil
  Side.pretendChat = nil
  if stand then stand:Hide() end
  Side.over = nil
  Hall:Close()
end)

-- The Guild Together screen (SPEC decision 64): Guild Together alone across the screen, every place in it, and back under the
-- guild window.
-- Face to face (SPEC decision 72): a game between players starts only while the other one is near you. The pretend
-- members stand near you; SB:Near sends one away and back.
step("face to face: a deathroll, a high roll, a ticket, Bingo and a transmog vote need the player near", function(c)
  local DR, RO, RA, Gm, Lk = ns.Deathroll, ns.RollOff, ns.Raffle, ns.Games, ns.Looks
  local k, mi, fw = Pe:Get("Korgath"), Pe:Get("Mirelle"), Pe:Get("Fenwick")
  c:Hush()
  c:That(Lk.Near(k.name), "the pretend members stand near you")
  SB:Near("Korgath", false)
  c:That(not Lk.Near(k.name), "Korgath walked away")
  local real = DR.game
  DR.game = nil
  local ok, why = DR:Challenge(k.name, 5, "gold", 500)
  c:That(not ok and why == "far", "no deathroll challenge while he is far away")
  if windowOpen() and not InCombatLockdown() then
    Hall:Open("tavern")
    Hall:ShowFeature("tavern", "deathroll")
    local page = Hall.pages.tavern.frame
    page.View({ kind = "challenge", key = k.name })
    local fl = ns.Side.frame.flows["tavern:view"]
    c:That(fl ~= nil and fl.items.far ~= nil and fl.items.far:IsShown(), "the challenge says who to go near")
    local send = ns.Side.frame.pane.foot.buttons[1]
    c:That(send ~= nil and send:IsShown() and not send:IsEnabled(), "and its Send is greyed")
    shot(c, "face to face: a deathroll challenge, Korgath far away")
    SB:Near("Korgath", true)
    Hall:Refresh()
    c:That(send ~= nil and send:IsEnabled(), "near again: Send can be pressed")
    page.View(nil)
  else
    SB:Near("Korgath", true)
  end
  c:That(DR:Challenge(k.name, 5, "gold", 500), "near: the challenge goes")
  c:Until(function() local dg = DR:Game() return dg and dg.st == "playing" end, 3)
  DR:CallOff()
  DR.game = real
  -- A high roll, a lottery ticket, Bingo and a transmog vote: near the host, Mirelle.
  Pe:Do("Mirelle", { k = "rolloff", max = 50, p = "gold" })
  local roId
  c:Until(function()
    local ro, id = RO:Current()
    roId = id
    return ro ~= nil and ro.h == mi.name and ro.max == 50
  end, 3)
  SB:Near("Mirelle", false)
  c:That(roId ~= nil and not RO:Join(roId), "no joining a high roll far from its host")
  SB:Near("Mirelle", true)
  c:That(roId ~= nil and RO:Join(roId), "near the host: joined")
  Pe:Do("Mirelle", { k = "raffle", prize = "Face to face", price = 1, max = 0, p = "gold" })
  local raId
  c:Until(function()
    for _, x in ipairs(RA:List()) do if x.ra.prize == "Face to face" then raId = x.id end end
    return raId ~= nil
  end, 3)
  SB:Near("Mirelle", false)
  c:That(raId ~= nil and not RA:Buy(raId, 1), "no ticket far from the host")
  SB:Near("Mirelle", true)
  c:That(raId ~= nil and RA:Buy(raId, 1), "a ticket bought face to face")
  local function hosted(kind)
    for _, x in ipairs(Gm.List(g())) do if x.ga.kind == kind and x.ga.h == mi.name and not x.ga.st then return x.id end end
  end
  Pe:Do("Mirelle", { k = "game", kind = "bingo", at = time() - 60, len = 60, prize = 0, p = "gold" })
  Pe:Do("Mirelle", { k = "game", kind = "fashion", at = time() - 60, len = 60, prize = 0, p = "gold" })
  c:Until(function() return hosted("bingo") ~= nil and hosted("fashion") ~= nil end, 3)
  local bid, fid = hosted("bingo"), hosted("fashion")
  if fid then Pe:Do("Fenwick", { k = "game_join", id = fid, on = true }) end
  c:Until(function() return fid ~= nil and Gm.IsIn(g(), g().games[fid], P:Of(fw.name, g())) end, 3)
  SB:Near("Mirelle", false)
  c:That(bid ~= nil and not Gm.Join(bid, true), "no Bingo card far from the host")
  c:That(fid ~= nil and not Gm.Vote(fid, fw.name), "no transmog vote far from the show")
  SB:Near("Mirelle", true)
  c:That(bid ~= nil and Gm.Join(bid, true), "Bingo joined face to face")
  c:That(fid ~= nil and Gm.Vote(fid, fw.name), "a vote at the show")
  -- Put away again by their host.
  if bid then Pe:Do("Mirelle", { k = "game_off", id = bid }) end
  if fid then Pe:Do("Mirelle", { k = "game_off", id = fid }) end
  if roId then Pe:Do("Mirelle", { k = "rolloff_end", id = roId, p = "gold", amt = 0, max = 50 }) end
end)

step("screen: the Guild Together screen, and back to the guild window", function(c)
  if not windowOpen() then c:Skip("the guild window is closed") return end
  Hall:Open()
  c:That(Hall:Full(true), "the Guild Together screen opens")
  local full = Hall.full
  c:That(full ~= nil and full:IsShown() and Hall.bar:GetParent() == full.host and Hall.frame:GetParent() == full.host,
    "the bar and the panel are on it")
  c:Note(("scaled to %d%% of the screen's units"):format(full.host:GetScale() * 100 + 0.5))
  local Fr = ns.Frame
  if Fr.crest then
    c:That(not Fr.crest:IsShown() and not Fr.title:IsShown(),
      "the window's crest and name stay under it (they drew over the screen's heading)")
  end
  if inGame() then
    local r, scr = rect(full.host), rect(UIParent)
    c:That(r and scr and r.left >= scr.left and r.right <= scr.right and r.top <= scr.top and r.bottom >= scr.bottom,
      "inside the screen")
  end
  for _, id in ipairs(Hall:Places()) do
    Hall:OpenPlace(id)
    c:That(Hall:IsFull() and Hall:IsOpen() and Hall.place == id, "the place " .. id .. " opens in it")
    c:Wait(0)
  end
  -- A scene there fills the right column's width (the second check of 1 November).
  local pane = ns.Side.frame and ns.Side.frame.pane
  if pane then
    local sf = ns.UI.PaneFlow(pane)
    sf:Begin()
    local st = sf:Stage("fullcheck", "tavern")
    c:That(st:GetWidth() >= sf.width * 0.95, ("a scene fills the right column (%d of %d wide)"):format(st:GetWidth(), sf.width))
    st:Hide()
  end
  c:That(Hall:Full(false), "back to the guild window")
  c:That(Hall.bar:GetParent() == CommunitiesFrame and not full:IsShown(), "the bar is under the window again")
  if Fr.crest then c:That(Fr.crest:IsShown() and Fr.title:IsShown(), "with the crest and the guild's name") end
  if inGame() then
    local w, bar = rect(CommunitiesFrame), rect(Hall.bar)
    c:That(w and bar and math.abs(bar.top - w.bottom) <= 1, "joined to it")
  end
  noTaint(c, "after the Guild Together screen")
  Hall:Close()
end)

step("pretend guild: removed again", function(c)
  local id = SB.id
  SB:Stop()
  c:That(D:Id() ~= id, "back to the real guild")
  c:That(ns.db.guilds[id] == nil, "the pretend guild's data is gone")
  c:That(R.pretend == nil, "the real roster again")
  if windowOpen() then Hall:Open(); Hall:Close() end
end)

-- The demo guild (Dev/Demo.lua): the last steps check and photograph the pages with it, and it stays open afterwards.
step("demo guild: twenty members, and every page in use", function(c)
  local bad = ns.Demo.Fill(c)
  c:That(SB.active and SB.demo, "the demo guild is open: " .. #ns.Demo.MEMBERS .. " members and you, its Guild Master")
  c:That(#bad == 0, #bad == 0 and "duels, a cup, a deathroll, six games, the stocks, the council, the treasury, deeds and crafters"
    or ("did not work: " .. table.concat(bad, " | ")))
end)

---------------------------------------------------------------------------
-- Every page as players see it (the demo guild): every place along the top, every feature, the rows that open
-- something and the forms a "..." button opens, as the Guild Master, an officer and a member. Checks that nothing
-- errors, that what a row opens shows beside the window with at most two buttons, that what waits for you (a glowing
-- button) and the row picked are in sight without scrolling, and that no text is a missing string.
---------------------------------------------------------------------------
ST.WALK_ROWS = 8 -- rows clicked per feature (the first ones, by key)

-- In sight: the frame lies inside its pane's visible part (positions are only known in the game).
local function inSight(frame, scroll)
  local fb, ft, sb, st = frame:GetBottom(), frame:GetTop(), scroll:GetBottom(), scroll:GetTop()
  if not (fb and ft and sb and st) then return true end
  return fb >= sb - 2 and ft <= st + 2
end

-- Shown texts that are still a locale key (a string missing from Locales/enUS.lua).
local function keysShown(frame, out)
  if not frame or not frame.IsVisible or not frame:IsVisible() then return end
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsVisible() then
      local t = r:GetText()
      for key in (type(t) == "string" and t or ""):gmatch("%f[%w_]%u[%u%d]*_[%u%d_]*[%u%d]%f[^%w_]") do
        out[#out + 1] = key
      end
    end
  end
  for _, child in ipairs({ frame:GetChildren() }) do keysShown(child, out) end
end

-- The flows a page draws in (UI.PaneFlow).
local function flowsOf(page)
  local list = {}
  for _, v in pairs(page) do
    if type(v) == "table" and getmetatable(v) == ns.UI.Flow and v.pane then list[#list + 1] = v end
  end
  return list
end

-- What waits for you (a glowing button) and the row picked must be in sight without scrolling (SPEC decision 52).
local function lookAt(flows, where, bad)
  for _, f in ipairs(flows) do
    local scroll = f.pane.scroll
    local waiting, seen = nil, false
    for key, it in pairs(f.items) do
      if scroll and it:IsVisible() then
        local glowing = it.glow ~= nil and it.glow:IsShown()
        local picked = it.flowKind == "row" and it.sel ~= nil and it.sel:IsShown()
        if picked and not inSight(it, scroll) then
          bad[#bad + 1] = ("%s: the row picked (%s) is below the fold"):format(where, key)
        elseif glowing and not picked then
          if inSight(it, scroll) then seen = true elseif not waiting then waiting = key end
        end
      end
    end
    if waiting and not seen then
      bad[#bad + 1] = ("%s: nothing that waits for you is in sight (%s is below the fold)"):format(where, waiting)
    end
  end
end

-- The stops of a place: its features, else its page and the page's own tabs (Manage).
local function stopsOf(place)
  local stops = {}
  for _, x in ipairs(Hall:Features(place)) do stops[#stops + 1] = { page = x.page, id = x.id } end
  if #stops > 0 then return stops end
  for _, pid in ipairs(Hall:Visible(place)) do
    local page = Hall.pages[pid].frame
    if page.parts and page.Pick then
      for _, part in ipairs(page.parts) do stops[#stops + 1] = { page = pid, part = part } end
    else
      stops[#stops + 1] = { page = pid }
    end
  end
  return stops
end

-- hook(kind, where): after each feature ("feature"), row ("row") and form ("form") shown (the tour's pictures).
function ST:Walk(c, rowsMax, hook)
  local bad, t = {}, { places = 0, features = 0, rows = 0, forms = 0 }
  local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then bad[#bad + 1] = where .. ": " .. tostring(err) end
    return ok
  end
  local function check(where, page)
    lookAt(flowsOf(page), where, bad)
    local s = ns.Side.frame
    if ns.Side:IsShown() then
      local n = 0
      for _, b in ipairs(s.pane.foot.buttons) do if b:IsShown() then n = n + 1 end end
      if n > ns.Side.BUTTONS then bad[#bad + 1] = where .. ": " .. n .. " buttons beside the window" end
      if s.last then lookAt({ s.last }, where .. " (beside the window)", bad) end
    end
    local keys = {}
    keysShown(Hall.frame, keys)
    if #keys > 0 then bad[#bad + 1] = where .. ": missing text: " .. table.concat(keys, ", ") end
  end
  for _, place in ipairs(Hall:Places()) do
    t.places = t.places + 1
    for _, stop in ipairs(stopsOf(place)) do
      local where = place .. "/" .. (stop.id or stop.part or stop.page)
      local page = Hall.pages[stop.page].frame
      local function show()
        ns.Side.over = nil
        page.view = nil
        if stop.id then Hall:ShowFeature(stop.page, stop.id)
        else
          Hall:Show(stop.page)
          if stop.part then page.Pick(stop.part) end
        end
      end
      if try(where, show) then
        t.features = t.features + 1
        check(where, page)
        if hook then hook("feature", where) end
        -- Each row that opens something, in turn (the welcome's steps are left alone: they are the player's own).
        local rows = {}
        for _, f in ipairs(flowsOf(page)) do
          for key, it in pairs(f.items) do
            if it.flowKind == "row" and it:IsVisible() and it.onClick and not key:match("^wel") then
              rows[#rows + 1] = { f = f, key = key }
            end
          end
        end
        table.sort(rows, function(a, b) return a.key < b.key end)
        for i = 1, math.min(#rows, rowsMax) do
          local r = rows[i]
          local here = where .. " > " .. r.key
          if try(here, show) then
            local it = r.f.items[r.key]
            -- As a player would: scroll to the row, then click it.
            if it then r.f:Reveal(it.flowTop, ns.UI.ROW_H) end
            if it and it:IsVisible() and it.onClick and try(here, it.onClick) then
              t.rows = t.rows + 1
              check(here, Hall.pages[Hall.current].frame)
              if hook then hook("row", here) end
            end
          end
          -- (A frame between clicks: a row can draw a scene with characters, and the game stops a script that runs
          -- too long.)
          c:Wait(0)
        end
        -- Each form a "..." button opens (Start a game..., Write a deed...): beside the window.
        local panes = {}
        for _, f in ipairs(flowsOf(page)) do panes[f.pane] = true end
        for pane in pairs(panes) do
          try(where, show)
          for _, b in ipairs(pane.foot and pane.foot.buttons or {}) do
            local label = b:IsVisible() and b:GetText()
            if type(label) == "string" and label:sub(-3) == "..." then
              local here = where .. " > " .. label
              if try(here, show) and try(here, b:GetScript("OnClick"), b) then
                t.forms = t.forms + 1
                if not ns.Side:IsShown() then bad[#bad + 1] = here .. ": the form did not open beside the window" end
                check(here, Hall.pages[Hall.current].frame)
                if hook then hook("form", here) end
              end
              c:Wait(0)
            end
          end
        end
        ns.Side.over = nil
        if ns.Side.viewOf then ns.Side:Dismiss() end
      end
      c:Wait(0)
    end
  end
  return bad, t
end

step("pages: every place, feature, row and form, as the Guild Master, an officer and a member", function(c)
  if not windowOpen() then c:Skip("the guild window is closed") return end
  if not SB.active then c:Skip("it walks the demo guild") return end
  Hall:Open()
  local me = ns.Self()
  local last = ns.db.errors and ns.db.errors[1]
  local function walk(label, rank)
    if rank then
      SB:SetRank(me, rank)
      c:Wait(0.3)
    end
    local bad, t = ST:Walk(c, ST.WALK_ROWS)
    -- The gear is everyone's (SPEC decision 74): Guild settings for the Guild Master, Your options for the rest.
    local manage, settings = false, false
    for _, p in ipairs(Hall:Places()) do if p == "manage" then manage = true end end
    for _, id in ipairs(Hall:Visible()) do if id == "settings" then settings = true end end
    c:That(manage and settings == D:InCharge(), label .. ": the gear shows, with " ..
      (settings and "Guild settings" or "Your options") .. " (" .. tostring(Hall.tabs.manage:GetText()) .. ")")
    c:That(#bad == 0, ("%s: %d places, %d features, %d rows and %d forms opened%s"):format(label, t.places, t.features,
      t.rows, t.forms, #bad == 0 and ", all fine" or (": " .. table.concat(bad, " | ", 1, math.min(#bad, 10)))))
  end
  walk("as the Guild Master")
  walk("as an officer", 1)
  walk("as a member", 3)
  SB:SetRank(me, 0)
  c:Wait(0.3)
  c:That(D:InCharge(), "the Guild Master again")
  local new = {}
  for _, e in ipairs(ns.db.errors or {}) do
    if e == last then break end
    new[#new + 1] = tostring(e.kind) .. ": " .. tostring(e.msg)
  end
  c:That(#new == 0, #new == 0 and "no error was logged on the way" or ("errors logged: " .. table.concat(new, " | ", 1, math.min(#new, 5))))
  ns.Side.over = nil
  Hall:Close()
end)

-- Text that does not fit: every shown text of every page and each of its tabs, by the game's own measure. A row's
-- lines may end in "..." (the whole line is in its tooltip or on the right when clicked), and so may names in a
-- game's picture (frame.short, UI/Visuals.lua); anything else may not.
local function cutTexts(frame, out, inRow)
  if not frame or not frame.IsVisible or not frame:IsVisible() then return end
  local row = inRow or frame.Set ~= nil and frame.icon ~= nil or frame.short == true
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsVisible() and r.IsTruncated and r:IsTruncated() then
      out[#out + 1] = { text = r:GetText() or "?", row = row }
    end
  end
  for _, child in ipairs({ frame:GetChildren() }) do cutTexts(child, out, row) end
end

step("pages: no text cut off", function(c)
  if not windowOpen() then c:Skip("the guild window is closed") return end
  Hall:Open()
  local cut, rows, seen = {}, 0, {}
  for _, id in ipairs(Hall:Visible()) do
    Hall:Show(id)
    local page = Hall.pages[id].frame
    local parts = page.parts or { false }
    local was = page.part
    for _, part in ipairs(parts) do
      if part then Hall:ShowFeature(id, part) end
      local out = {}
      cutTexts(Hall.frame, out)
      for _, x in ipairs(out) do
        local where = id .. (part and ("/" .. part) or "") .. ": " .. x.text
        if x.row then rows = rows + 1
        elseif not seen[where] then seen[where] = true; cut[#cut + 1] = where end
      end
      c:Wait(0)
    end
    if was and page.Pick then Hall:ShowFeature(id, was) end
  end
  Hall:Close()
  if rows > 0 then c:Note(rows .. " lines in rows end in \"...\" (their tooltip or the right pane shows them whole)") end
  c:That(#cut == 0, #cut == 0 and "every title, label and button fits"
    or ("cut off: " .. table.concat(cut, " | ", 1, math.min(#cut, 12))))
end)

-- The scenes where players see them (SPEC decisions 59, 60, 63): each feature of each page, and each game and sentence
-- of the demo guild, opened in the panel as a player would. With room on the screen, a scene plays in the window
-- beside the panel: on the screen, clear of the panel. Else it lies inside the right column, centred, at most
-- UI.Stage.ROOM of its height, with room under it for what it shows. (Screen positions only in the game.)
step("scenes: beside the panel or in its right column, with the details in sight", function(c)
  if not windowOpen() then c:Skip("the guild window is closed") return end
  local Sg, Side = ns.UI.Stage, ns.Side
  Hall:Open()
  local seen, bad, beside = {}, {}, 0
  local function check(what)
    Hall:Refresh()
    local s = Side.frame
    local b = Side.beside
    if s and s:IsShown() and b and b:IsShown() then
      local ok = b.host:GetWidth() >= Side.SCENE_MIN
      if ok and inGame() then
        local r, p, scr = rect(b), rect(Hall.frame), rect(UIParent)
        ok = r ~= nil and p ~= nil and scr ~= nil and r.left >= scr.left and r.right <= scr.right
          and r.bottom >= scr.bottom and (r.left >= p.right or r.right <= p.left)
      end
      seen[#seen + 1] = what
      beside = beside + 1
      if not ok then bad[#bad + 1] = what .. " (beside the panel)" end
      return
    end
    local f = s and s:IsShown() and s.last
    local st = f and f.used.stage and f.items.stage
    if not st or not st:IsShown() then return end
    local paneH, w, h = s.pane:GetHeight(), st:GetWidth(), st:GetHeight()
    local _, _, _, x = st:GetPoint(1)
    local room = paneH - (s.pane.foot:IsShown() and ns.UI.FOOT_H or 0) - h
    local ok = h <= paneH * Sg.ROOM + 1 and w <= f.width + 1 and math.abs((x or 0) - (f.pad + (f.width - w) / 2)) <= 1
      and room >= 40
    if ok and inGame() then
      local r, p = rect(st), rect(s.pane)
      ok = r ~= nil and p ~= nil and r.left >= p.left - 1 and r.right <= p.right + 1 and r.top <= p.top + 1
        and r.bottom >= p.bottom - 1
    end
    seen[#seen + 1] = what
    if not ok then bad[#bad + 1] = ("%s (%d x %d, %d under it)"):format(what, w, h, room) end
  end
  for _, id in ipairs(Hall:Visible()) do
    Hall:Show(id)
    local page = Hall.pages[id].frame
    local was = page.part
    for _, part in ipairs(page.parts or {}) do
      Hall:ShowFeature(id, part)
      check(id .. "/" .. part)
      c:Wait(0)
    end
    if was and page.Pick then Hall:ShowFeature(id, was) end
  end
  for _, x in ipairs(SB.demo and ns.Demo.Picks() or {}) do
    Side.over = nil
    Hall:Show(x.page)
    if x.part then Hall:ShowFeature(x.page, x.part) end
    x.pick(Hall.pages[x.page].frame)
    check(x.page .. ": " .. x.what)
    c:Wait(0)
  end
  Side.over = nil
  Hall:Close()
  c:Note(("%d scenes looked at, %d of them beside the panel: %s"):format(#seen, beside, table.concat(seen, ", ")))
  c:That(#seen >= 5, "scenes were found in the panel")
  c:That(#bad == 0, #bad == 0 and "each fits: beside the panel on the screen, or in the right column with the details in sight"
    or ("too big or out of place: " .. table.concat(bad, " | ")))
end)

-- The moments on the alert line (UI/Alerts.lua), each as it would come: with its scene where it has one. For the
-- tour and /gtf scenes: { { what, alert } }.
function ST:Toasts()
  local Sc, gg = ns.Scenes, g()
  local list = {}
  local function toast(what, a) list[#list + 1] = { what = what, alert = a } end
  for _, s in ipairs(ns.Stocks.List(gg)) do
    if ns.Stocks.Open(s) then
      toast("a sentence", { text = L.AN_ALERT_SENTENCE:format(ns.Display(s.se.to)), sub = L["ACT_" .. s.pun:upper()],
        scene = { page = "stocks", draw = function(f) Sc.Sentence(f, gg, s) end } })
      break
    end
  end
  toast("the crown", { text = L.AN_ALERT_CROWN, sub = "", icon = "crown",
    scene = { page = "arena", draw = function(f) Sc.Crown(f, ns.Crown.State(gg)) end } })
  local k = Pe:Get("Korgath")
  local dr = { id = "show-dr", opp = k and k.name or ns.Self(), st = "playing", s = 500, rolls = { { who = "me", v = 312 } } }
  toast("a deathroll's roll", { text = L.TV_DEATHROLL, sub = L.AL_DR_YOU:format(312), quiet = true,
    scene = { page = "tavern", draw = function(f) Sc.Deathroll(f, dr) end } })
  toast("the Wheel", { text = L.AL_WHEEL:format(ns.Display(ns.Self())), sub = "",
    wheel = { slices = ns.Stocks.WHEEL, r = ns.Stocks.WHEEL[2] } })
  local setup = ns.Rules.Setup(gg) or "democracy"
  toast("a new setup", { text = L.AN_ALERT_SETUP, sub = L.AN_ALERT_SETUP_SUB:format(L["SETUP_" .. setup:upper()]),
    icon = ns.Rules.ICON[setup], scene = { page = "council", draw = function(f) Sc.Setup(f, gg, setup) end } })
  toast("a guilty verdict", { text = L.AN_ALERT_GUILTY, sub = ns.Display(k and k.name or ns.Self()), icon = "scales",
    how = "stamp" })
  toast("a Mak'gora", { text = L.AN_ALERT_MAK, sub = L.AN_ALERT_MAK_SUB:format(ns.Display(k and k.name or "?"),
    ns.Display(ns.Self())), icon = "duel" })
  toast("a rebellion", { text = L.AN_ALERT_REBEL, sub = L.AN_ALERT_REBEL_SUB:format(ns.Display(k and k.name or "?")),
    icon = "flag" })
  toast("a new Guild Master", { text = L.AN_ALERT_NEW_GM, sub = ns.Display(ns.Self()), icon = "throne" })
  toast("a new record", { text = L.AN_ALERT_RECORD:format(L.CH_HALL_RATING), icon = "duel", fanfare = true,
    sub = L.AN_ALERT_RECORD_SUB:format(ns.Display(ns.Self()), "1612", ns.Display(k and k.name or "?")) })
  return list
end

-- The tour (asked for by the user, 1 Nov 2026: "a printscreen of each and every feature and section, and also every
-- animation"), as the demo guild's Guild Master (Guild settings is there too): the window; every place's features,
-- each row that opens something new (every row with a scene, after its moment), every form (ST:Walk); the demo
-- guild's games and sentences with their scenes; the moments on the alert line; the Guild Together screen. The pictures go
-- to the game's Screenshots folder; the report lists them in order (shots), with those the council steps took.
ST.TOUR_ROWS = 2        -- rows without a scene: the first that open something new, per feature
ST.TOUR_WALK = 40       -- rows looked at per feature
-- Getting started (SPEC decision 72): the tour for each rank on the demo guild, a picture of each step of the member's
-- tour (and of the Guild Master's setup guide and the officers' step), and the short tour after a promotion.
step("getting started: the tour as a member, an officer and the Guild Master", function(c)
  if not windowOpen() or InCombatLockdown() then c:Skip("the guild window is closed: the tour lives under it") return end
  if not SB.demo then c:Skip("the demo guild is not open") return end
  local Tr = ns.Tour
  local seen = ns.db.tour
  Tr.testing = true
  for _, rank in ipairs({ "member", "officer", "gm" }) do
    c:That(Tr:Start(rank), rank .. ": the tour starts")
    -- Its welcome stands over Home's first list (it stood over Your options: the third check of 1 November).
    local first, home = Tr.steps[Tr.i], Hall.pages.home.frame
    if first and not first.page then
      c:That(Hall.current == "home" and home and home.part == "waiting", rank .. ": the welcome stands over Home's first list")
    end
    c:Until(function() return Tr.ready end, 2)
    local n, bad = 0, {}
    while Tr.on and n < 40 do
      n = n + 1
      local st = Tr.steps[Tr.i]
      if not Tr.card:IsShown() then bad[#bad + 1] = st.id .. " (no card)" end
      if st.target and not Tr.glow:IsShown() then bad[#bad + 1] = st.id end
      -- Skip the tour and Back apart (they touched: the third check of 1 November).
      local cd = Tr.card
      if inGame() and cd.skip:IsShown() and cd.back:IsShown() and (cd.skip:GetRight() or 0) > (cd.back:GetLeft() or 0) - 4 then
        bad[#bad + 1] = st.id .. " (Skip touches Back)"
      end
      if rank == "member" or st.real or st.id == "OFFICERS" then shot(c, ("tour: %s, %s"):format(rank, st.id:lower()))
      else c:Wait(0) end
      Tr:Next()
    end
    c:That(not Tr.on, ("%s: the tour ends after %d steps"):format(rank, n))
    c:That(#bad == 0, #bad == 0 and (rank .. ": every step framed") or (rank .. ": not framed: " .. table.concat(bad, ", ")))
    c:Eq(R.pretend and R.pretend.ranks[ns.Self()], 0, rank .. ": you are the demo's Guild Master again")
    c:That(SB.active and SB.demo, rank .. ": the demo guild stays open")
  end
  Tr.testing = nil
  ns.db.tour = seen
  local ids = {}
  for _, x in ipairs(Tr:Steps("officer", "member")) do ids[#ids + 1] = x.id end
  c:Eq(table.concat(ids, ","), "NEW,OFFICERS,DONE", "made an officer: a short tour of only what is new")
end)

step("pictures: the tour of every feature, form and scene", function(c)
  if not inGame() or not Screenshot then c:Skip("pictures are only taken in the game") return end
  if not windowOpen() then c:Skip("the guild window is closed") return end
  local first = #(report().shots or {}) + 1
  Hall:Close()
  shot(c, "the guild window with the bar")
  Hall:Open()
  -- Every feature, the rows that open something new, every form.
  local seen = {}
  ST:Walk(c, ST.TOUR_WALK, function(kind, where)
    local Side = ns.Side
    local beside = Side.beside ~= nil and Side.beside:IsShown()
    if kind == "row" then
      local title = Side:IsShown() and Side.frame.title:GetText() or nil
      local feat = where:match("^(.-) > ") or where
      local s = seen[feat] or { n = 0 }
      seen[feat] = s
      if not title or s[title] then return end
      if not beside and s.n >= ST.TOUR_ROWS then return end
      s[title] = true
      s.n = s.n + 1
      shot(c, "row: " .. where .. " (" .. title .. ")", beside)
    else
      shot(c, kind .. ": " .. where, beside)
    end
  end)
  -- The demo guild's games and sentences with their scenes, and what a row does not open (a target shown, a card).
  for _, x in ipairs(SB.demo and ns.Demo.Picks() or {}) do
    ns.Side.over = nil
    Hall:Show(x.page)
    local page = Hall.pages[x.page].frame
    if x.part then Hall:ShowFeature(x.page, x.part) end
    x.pick(page)
    Hall:Refresh()
    shot(c, "panel: " .. x.page .. ", " .. x.what, ns.Side.beside ~= nil and ns.Side.beside:IsShown())
  end
  ns.Side.over = nil
  -- Manage once more, pointing at a power (its tooltip).
  local settings = Hall.pages.settings
  if settings and settings.frame:IsShown() then settings.frame.Pick("who") end
  local power = settings and settings.frame:IsShown() and settings.frame.powersFlow.items["a.dunce"]
  if power then
    power:GetScript("OnEnter")(power)
    shot(c, "manage, a power's tooltip")
    power:GetScript("OnLeave")(power)
  end
  -- The Guild Together screen, on Home and on a page with a scene.
  if Hall.Full then
    look("home")
    Hall:Full(true)
    shot(c, "the Guild Together screen: Home")
    look("arena", "duels")
    shot(c, "the Guild Together screen: a scene", true)
    Hall:Full(false)
  end
  -- The moments on the alert line, each played to its end.
  Hall:Close()
  local Al = ns.Alerts
  for _, x in ipairs(ST:Toasts()) do
    x.alert.test, x.alert.now = true, true
    ns.UI.Stage.replay = true
    wipe(ns.UI.Stage.played)
    Al:Push(x.alert)
    c:Wait(x.alert.wheel and (ns.Scenes.SPIN + 0.6) or ST.SCENE_WAIT)
    Screenshot()
    local r = report()
    r.shots[#r.shots + 1] = { what = "alert line: " .. x.what, t = time() }
    c:Wait(ST.SHOT_GAP)
  end
  ns.UI.Stage.replay = nil
  Al.queue, Al.cur = {}, nil
  if Al.frame then Al.frame:Hide() end
  c:Note(#report().shots - first + 1 .. " pictures in the tour (" .. #report().shots .. " in all), in the Screenshots folder, listed in the report (shots)")
end)



---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------
local function add(s, c)
  if c.realPrint then ns.Print, c.realPrint = c.realPrint, nil end
  local r = report()
  local status = c.skip and "skip" or (c.bad and "fail" or "ok")
  if c.skip then c.lines[#c.lines + 1] = "skipped: " .. c.skip end
  r.steps[#r.steps + 1] = { name = s.name, status = status, detail = table.concat(c.lines, "\n") }
  if status == "ok" then r.passed = r.passed + 1 elseif status == "fail" then r.failed = r.failed + 1 else r.skipped = r.skipped + 1 end
end

---------------------------------------------------------------------------
-- /gtf scenes (asked for by the user, 31 Oct 2026: "the test goes rapid fast"): the demo guild's scenes, slowly,
-- to watch: each game and sentence in the panel with its scene beside it, then moments under the alert line (a
-- sentence, the crown, a deathroll's roll, the Wheel), SHOW seconds each, every moment played again, and a picture
-- of each in the Screenshots folder (listed in the report, showcase).
---------------------------------------------------------------------------
ST.SHOW = 5

function ST:Showcase()
  if not (SB.active and SB.demo) then ns:Print(L.SHOW_NEED_DEMO, true) return end
  if not windowOpen() then ns:Print(L.SHOW_NEED_WINDOW, true) return end
  if self.showing then return end
  local Al = ns.Alerts
  local list = {}
  for _, x in ipairs(ns.Demo.Picks()) do list[#list + 1] = x end
  for _, x in ipairs(self:Toasts()) do
    list[#list + 1] = { what = L.SHOW_TOAST:format(x.what), toast = function()
      x.alert.test, x.alert.now = true, true
      Al:Push(x.alert)
    end }
  end
  local shots = {}
  report().showcase = shots
  self.showing = true
  ns.UI.Stage.replay = true
  local i = 0
  local function show()
    i = i + 1
    local x = list[i]
    if not x then
      self.showing, ns.UI.Stage.replay = nil, nil
      Hall:Close()
      ns:Print(L.SHOW_DONE:format(#shots), true)
      return
    end
    wipe(ns.UI.Stage.played)
    ns.Side.over = nil
    if x.toast then
      Hall:Close()
      x.toast()
    else
      Hall:Open()
      Hall:Show(x.page)
      if x.part then Hall:ShowFeature(x.page, x.part) end
      x.pick(Hall.pages[x.page].frame)
      Hall:Refresh()
    end
    ns:Print(L.SHOW_NOW:format(i, #list, x.what or x.page), true)
    C_Timer.After(self.SHOW - 1, function()
      if Screenshot then
        Screenshot()
        shots[#shots + 1] = { what = x.page and (x.page .. ": " .. tostring(x.what)) or x.what, t = time() }
      end
    end)
    C_Timer.After(self.SHOW, show)
  end
  show()
end

---------------------------------------------------------------------------
-- /gtf brand (asked for by the owner, 1 Nov 2026, for the first public beta): the pictures for the README and the
-- CurseForge gallery, from the demo guild: one of each place, a few of its best features, and a moment under the
-- alert line. They are taken in the Guild Together screen with the game's interface hidden (UIParent faded out, as
-- Journey's /jtf brand does), and no real player but you shows: the pretend members without their realm, "Guild Together"
-- where the guild's name would be, and neither the game calendar's guild events nor your own professions. The run is
-- listed in GuildTogetherForeverDB.brand ({ started, shots = { { file, kind, t, crop } }, problems }); after a /reload,
-- tools/brand-shots.lua and tools/crop-shots.ps1 cut the pictures into .github/screenshots (docs/ARCHITECTURE.md §5).
---------------------------------------------------------------------------
-- file: the picture's name; page and feat: what the panel shows; row: the first row clicked (its picture on the
-- right); toast: the moment on the alert line (ST:Toasts).
ST.BRAND = {
  { file = "home", page = "home", feat = "waiting" },
  { file = "weekly-news", page = "chronicle", feat = "gazette" },
  { file = "mascot", page = "chronicle", feat = "mascot" },
  { file = "duels", page = "arena", feat = "duels" },
  { file = "tournament", page = "arena", feat = "cup" },
  { file = "games", page = "games", feat = "game" },
  { file = "deathroll", page = "tavern", feat = "deathroll" },
  { file = "treasury", page = "treasury", feat = "debts" },
  { file = "professions", page = "professions", feat = "find" },
  { file = "punishments", page = "stocks", feat = "serving", row = true },
  { file = "court", page = "council", feat = "court" },
  { file = "polls", page = "council", feat = "votes" },
  { file = "calendar", page = "calendar", feat = "events" },
  { file = "guild-settings", page = "settings", feat = "setup" },
  { file = "alert", toast = "the crown" },
}
ST.BRAND_PAD = { screen = 4, alert = 28 }   -- room around a picture past its frame, in UIParent's units
-- Your options for the run, put back after: the moments and their scenes on, the alert line in the middle at its
-- normal size (at the top it would keep clear of the hidden guild window, made smaller).
ST.BRAND_LOOK = { alerts = true, alertScenes = true, alertSpot = "middle", alertSize = "normal" }

-- A part of the screen in the screenshot's pixels, from UIParent's units (left, bottom, right, top) with room around
-- it: { x, y (from the top), w, h, sw, sh (the screen's size) }. (Copied from Journey Together's Dev/Tour.lua.)
function ST:PixelRect(l, b, r, t, pad)
  local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
  local sw, sh
  if GetPhysicalScreenSize then sw, sh = GetPhysicalScreenSize() end
  if not sw or not sh or sh <= 0 then sw, sh = uw, uh end
  local k, fl = sh / uh, math.floor
  pad = pad or 0
  l, b = math.max(0, l - pad), math.max(0, b - pad)
  r, t = math.min(uw, r + pad), math.min(uh, t + pad)
  return { x = fl(l * k + 0.5), y = fl((uh - t) * k + 0.5), w = fl((r - l) * k + 0.5), h = fl((t - b) * k + 0.5), sw = sw, sh = sh }
end

-- A shown frame's rectangle in UIParent's units, grown by edge (in its own units): left, bottom, right, top. (After
-- Journey Together's.)
local function uiRect(f, edge)
  if not f or not f.IsShown or not f:IsShown() then return nil end
  local l, b = f:GetLeft(), f:GetBottom()
  if not l or not b then return nil end
  local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local e = edge or 0
  return (l - e) * s, (b - e) * s, (l + f:GetWidth() + e) * s, (b + f:GetHeight() + e) * s
end

-- What a brand picture keeps: the Guild Together screen with its leather, or the alert line with its scene.
function ST:BrandCrop(kind)
  local l, b, r, t
  local function grow(f, edge)
    local fl, fb, fr, ft = uiRect(f, edge)
    if not fl then return end
    if not l then l, b, r, t = fl, fb, fr, ft
    else l, b, r, t = math.min(l, fl), math.min(b, fb), math.max(r, fr), math.max(t, ft) end
  end
  if kind == "alert" then
    local f = ns.Alerts.frame
    grow(f)
    if f then grow(f.scene, 3) end
  else
    grow(Hall.full and Hall.full.host, ns.Frame.RIM)
  end
  if not l then return nil end
  return self:PixelRect(l, b, r, t, self.BRAND_PAD[kind])
end

-- Our own frame on the hidden screen, or not.
local function keep(f, on) if f and f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(on) end end

-- The run's lens: no real player but you, the moments as the pictures want them and the game's interface hidden;
-- off: all put back.
function ST:BrandLens(on)
  local saved = self.brandSaved
  if on and not saved then
    saved = { display = ns.Display, guildName = ns.Chronicle.GuildName, list = ns.Agenda.List, settings = {} }
    self.brandSaved = saved
    local realDisplay, realList, tail = saved.display, saved.list, "%-" .. Pe.REALM .. "$"
    ns.Display = function(name)
      if type(name) == "string" then name = name:gsub(tail, "") end
      return realDisplay(name)
    end
    ns.Chronicle.GuildName = function() return L.ADDON_NAME end
    ns.Agenda.List = function(...)
      local out = {}
      for _, e in ipairs(realList(...)) do
        if not (type(e.key) == "string" and e.key:match("^gamecal:")) then out[#out + 1] = e end
      end
      return out
    end
    local gg, me = D:Current(), ns.Self()
    if gg and gg.crafts and gg.crafts[me] then saved.crafts, gg.crafts[me] = gg.crafts[me], nil end
    for k, v in pairs(self.BRAND_LOOK) do
      saved.settings[k] = { ns.Settings:Get(k) }
      ns.Settings:Set(k, v)
    end
    saved.alpha = UIParent:GetAlpha() or 1
    UIParent:SetAlpha(0)
  elseif not on and saved then
    self.brandSaved = nil
    ns.Display, ns.Chronicle.GuildName, ns.Agenda.List = saved.display, saved.guildName, saved.list
    local gg = D:Current()
    if saved.crafts and gg then
      gg.crafts = gg.crafts or {}
      gg.crafts[ns.Self()] = saved.crafts
    end
    for k, v in pairs(saved.settings) do ns.Settings:Set(k, v[1]) end
    keep(Hall.full, false)
    keep(ns.Alerts.frame, false)
    UIParent:SetAlpha(saved.alpha)
  end
end

function ST:Brand()
  if not (SB.active and SB.demo) then ns:Print(L.BRAND_NEED_DEMO, true) return end
  if not windowOpen() then ns:Print(L.SHOW_NEED_WINDOW, true) return end
  if InCombatLockdown() then ns:Print(L.TEST_COMBAT, true) return end
  if self.running or self.showing or self.branding then return end
  local Al, Sg = ns.Alerts, ns.UI.Stage
  local r = { started = time(), shots = {}, problems = {} }
  ns.db.brand = r
  self.branding = true
  ns:Print(L.BRAND_START:format(#self.BRAND), true)
  local toasts = {}
  for _, x in ipairs(self:Toasts()) do toasts[x.what] = x.alert end
  local i = 0
  local nextShot
  local function finish()
    self:BrandLens(false)
    Sg.replay = nil
    ns.Side.over = nil
    Al.queue, Al.cur = {}, nil
    if Al.frame then Al.frame:Hide() end
    Hall:Full(false)
    Hall:Close()
    self.branding = nil
    ns:Print(L.BRAND_DONE:format(#r.shots), true)
  end
  local function problem(b, err)
    r.problems[#r.problems + 1] = { id = b.file, err = tostring(err) }
    ns:LogError("brand", b.file, tostring(err))
  end
  -- The picture, once its moment has played (a court's calls hold it: waited out, as the self-test's own pictures).
  local function take(b, kind, waited)
    if Sg.Busy() and waited < 8 then return C_Timer.After(0.25, function() take(b, kind, waited + 0.25) end) end
    local ok, err = pcall(function()
      local crop = self:BrandCrop(kind)
      if Screenshot then Screenshot() end
      r.shots[#r.shots + 1] = { file = b.file, kind = kind, t = time(), crop = crop }
    end)
    if not ok then problem(b, err) end
    C_Timer.After(self.SHOT_GAP, nextShot)
  end
  nextShot = function()
    i = i + 1
    local b = self.BRAND[i]
    if not b then return finish() end
    if InCombatLockdown() then
      problem(b, "combat: the run stopped")
      return finish()
    end
    local kind = b.toast and "alert" or "screen"
    local ok, err = pcall(function()
      wipe(Sg.played)
      ns.Side.over = nil
      if b.toast then
        Hall:Full(false)
        Hall:Close()
        local a = assert(toasts[b.toast], "no such moment: " .. b.toast)
        a.test, a.now = true, true
        Al:Push(a)
        keep(Al.frame, true)
      else
        if not Hall:IsFull() then assert(Hall:Full(true), "the Guild Together screen did not open") end
        keep(Hall.full, true)
        Hall.full.name:SetText(L.ADDON_NAME)
        Hall:ShowFeature(b.page, b.feat)
        if b.row then
          local top
          for _, fl in ipairs(flowsOf(Hall.pages[b.page].frame)) do
            for _, it in pairs(fl.items) do
              if it.flowKind == "row" and it:IsVisible() and it.onClick and (not top or it.flowTop < top.flowTop) then top = it end
            end
          end
          if top then top.onClick() end
        end
        Hall:Refresh()
      end
    end)
    if not ok then
      problem(b, err)
      return C_Timer.After(0, nextShot)
    end
    C_Timer.After(self.SCENE_WAIT, function() take(b, kind, 0) end)
  end
  self:BrandLens(true)
  Sg.replay = true
  nextShot()
end

-- With a guild and the window closed, it waits for the player to open the window (addon code may not: that taints
-- it), so the window checks run too; after WAIT_WINDOW seconds it starts without them.
ST.WAIT_WINDOW = 20
function ST:Run(waited)
  if self.running and not waited then ns:Print(L.TEST_RUNNING, true) return end
  if ns.Combat:InCombat() then self.running = false ns:Print(L.TEST_COMBAT, true) return end
  if SB.demo then SB:Stop() end
  if not waited and ns.Guild() and Hall.frame and not windowOpen() then
    self.running = true
    ns:Print(L.TEST_OPEN_WINDOW:format(self.WAIT_WINDOW), true)
    local left = self.WAIT_WINDOW
    local function poll()
      left = left - 0.5
      if windowOpen() or left <= 0 then return ST:Run(true) end
      C_Timer.After(0.5, poll)
    end
    C_Timer.After(0.5, poll)
    return
  end
  self.running = true
  ns.db.selftest = { started = time(), passed = 0, failed = 0, skipped = 0, steps = {}, env = {} }
  ns:Print(L.TEST_START:format(#steps), true)
  local i = 0
  local nextStep
  -- Each step is a coroutine, so it can wait (c:Wait) while messages travel. During combat it pauses.
  local function run(s)
    local c = setmetatable({ lines = {} }, Check)
    local co = coroutine.create(function() s.fn(c) end)
    local function resume()
      if ns.Combat:InCombat() then return C_Timer.After(1, resume) end
      local ok, wait = coroutine.resume(co)
      if not ok then
        c.bad = true
        local err = tostring(wait) .. "\n" .. (debugstack and debugstack(co, 1, 8, 0) or "")
        c.lines[#c.lines + 1] = "ERROR: " .. err
        ns:LogError("selftest", s.name, err)
      elseif coroutine.status(co) ~= "dead" then
        return C_Timer.After(tonumber(wait) or 0, resume)
      end
      add(s, c)
      C_Timer.After(0, nextStep)
    end
    resume()
  end
  nextStep = function()
    i = i + 1
    local s = steps[i]
    if not s then return ST:Finish() end
    run(s)
  end
  nextStep()
end

function ST:Finish()
  -- The demo guild stays open to look around in (not when practising on a community: our tab is not there then).
  if SB.active and (not SB.demo or Hall.practice) then SB:Stop() end
  if Hall.practice then
    Hall.practice = nil
    Hall:Close()
    Hall:Place()
  end
  ST.pings = nil
  self.running = false
  local r = report()
  r.finished = time()
  ns:Print(L.TEST_DONE:format(r.passed, r.failed, r.skipped), true)
  for _, s in ipairs(r.steps) do
    if s.status ~= "ok" then
      local line = s.detail:match("FAIL: [^\n]*") or s.detail:match("ERROR: [^\n]*") or s.detail:match("skipped: [^\n]*") or ""
      ns:Print(L.TEST_LINE:format(s.status == "skip" and L.TEST_SKIPPED or L.TEST_FAILED, s.name, line), true)
    end
  end
  if SB.demo then ns:Print(L.TEST_DEMO, true) end
  ns:Fire("SELFTEST_DONE")
end
