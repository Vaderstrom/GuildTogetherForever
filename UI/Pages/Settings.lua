-- Manage, the gear at the end of the places (SPEC §3, decision 50): the Guild Master's setup only. The purse and the
-- name of the Marks, the places and features (decision 52), and who may do what per rank. Only the Guild Master sees
-- it. Changes show at once and go out to the guild a moment after the last one (Guild/Sync.lua, ChangeSettings).
-- The Council's numbers and the strike ladder (SPEC §7). A rule the guild changed by vote shows its voted value
-- and cannot be ticked here (decided 29 Oct 2026: only another vote changes it).
-- The guild tax (SPEC §8, decided 29 Oct 2026: the Guild Master sets it, not a vote): on or off, each week or month,
-- from a level, gold per rank, and members let off by name.
-- The Chronicle and Discord (SPEC §3.3, §9.2): the mascot's name and kind, and the Herald, whose addon writes the
-- posts for Addon Webhooks for Discord (decided 29 Oct 2026; the app's flows pick the channels, not Settings).
-- Layout (decided 29 Oct 2026, asked for by the user: "group settings that make sense together"; SPEC decision 57):
-- each group of settings is a feature in the guild window, and fills the panel with its own panes.
local _, ns = ...
local L, UI, D, Hall = ns.L, ns.UI, ns.GuildData, ns.Hall

local PAGE_ROW = 22
-- (Your options first: the Guild Master's own, as a member's gear opens them; SPEC decision 74.)
local GROUPS = { "mine", "setup", "general", "features", "who", "tax", "council", "rules", "disc", "theme" }

local function settings() return D:Settings() end
local function change(fn) ns.Sync:ChangeSettings(fn) end

-- The purse: asks first, and says that open bets stay in the purse they were made in (SPEC §3.1).
local function pickPurse(purse)
  if settings().purse == purse then return end
  local text = purse == "marks" and L.PURSE_ASK_MARKS:format(settings().many) or L.PURSE_ASK_GOLD
  Hall:Confirm(text, L.PURSE_SWITCH, function() change(function(s) s.purse = purse end) end)
end

-- A label with a number to its right, on one line of a pane, with a minus and a plus (the Council's numbers, the tax
-- per rank).
local function labelled(c, w, y, text, boxW, maxLetters, get, set)
  local t = UI.Text(c, "GameFontHighlightSmall")
  t:SetPoint("TOPLEFT", 4, y - 5)
  t:SetWidth(w - boxW - 62)
  t:SetWordWrap(false)
  t:SetText(text)
  local e = UI.Stepper(c, boxW + 44, maxLetters, get, set)
  e:SetPoint("TOPRIGHT", c, "TOPLEFT", w - 4, y)
  return t, e
end

-- A switch whose label wraps across the pane.
local function wideCheck(c, w, label, get, set)
  local b = UI.Toggle(c, label, get, set)
  b.label:SetWidth(w - 44)
  b.label:SetWordWrap(true)
  b.label:SetJustifyH("LEFT")
  b.label:ClearAllPoints()
  b.label:SetPoint("TOPLEFT", b, "TOPRIGHT", 6, 0)
  return b
end

---------------------------------------------------------------------------
-- The currency
---------------------------------------------------------------------------
local function buildGeneral(page, left)
  local c, w = left.child, left.inner
  local y = -2
  page.gold = UI.Radio(c, L.PURSE_GOLD, function() return settings().purse == "gold" end, function() pickPurse("gold") end)
  page.gold:SetPoint("TOPLEFT", 4, y)
  page.marks = UI.Radio(c, L.PURSE_MARKS, function() return settings().purse == "marks" end, function() pickPurse("marks") end)
  page.marks:SetPoint("TOPLEFT", 4 + math.floor(w / 2), y)
  y = y - 26
  local half = math.floor((w - 8) / 2)
  local function name(key, label, x)
    local t = UI.Text(c, "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", x, y)
    t:SetText(label)
    local e = UI.Edit(c, half - 10, D.NAME_MAX, function() return settings()[key] end, function(text)
      local clean = D.CleanName(text)
      if clean and clean ~= settings()[key] then change(function(s) s[key] = clean end) end
    end)
    e:SetPoint("TOPLEFT", x + 6, y - 14)
    return e
  end
  page.one = name("one", L.SET_NAME_ONE, 4)
  page.many = name("many", L.SET_NAME_MANY, 4 + half + 8)
  y = y - 44
  page.purseNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.purseNote:SetPoint("TOPLEFT", 4, y)
  page.purseNoteY = y
  page.announce = wideCheck(c, w, L.SET_ANNOUNCE, function() return not settings().hush end, function(on)
    change(function(s) s.hush = not on end)
  end)
  -- The duel ladder's seasons (SPEC decision 52).
  page.seasonLabel = UI.Text(c, "GameFontNormalSmall")
  page.seasonLabel:SetText(L.SET_SEASON)
  page.season = UI.Dropdown(c, 240)
end

local function layoutGeneral(page)
  local s = settings()
  page.purseNote:SetText(s.purse == "gold" and L.PURSE_NOTE_GOLD or L.PURSE_NOTE_MARKS:format(s.many))
  local y = page.purseNoteY - math.ceil(page.purseNote:GetStringHeight() or 24) - 10
  page.announce:ClearAllPoints()
  page.announce:SetPoint("TOPLEFT", 4, y)
  y = y - math.max(24, math.ceil(page.announce.label:GetStringHeight() or 24) + 6)
  page.seasonLabel:ClearAllPoints()
  page.seasonLabel:SetPoint("TOPLEFT", 4, y)
  page.season:ClearAllPoints()
  page.season:SetPoint("TOPLEFT", 10, y - 14)
  page.season:Set({ { "month", L.SET_SEASON_MONTH }, { "season", L.SET_SEASON_SEASON } }, s.season or "month",
    function(v) if v ~= settings().season then change(function(x) x.season = v end) end end)
  y = y - 44
  page.groups.general.left.child:SetHeight(-y + 4)
end

---------------------------------------------------------------------------
-- The guild's look (SPEC decision 68), for every member: the accent colour, the frame's leather and how dark the
-- panels are on the left (each member sees them after a reload); the crest and what the plate over the window says
-- on the right (at once).
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- The punishment rules (SPEC decision 69): the three switches on the left; what opting out closes while the tax is
-- off on the right. Each change dates the rules (pun.t), which the rules for everyone show.
---------------------------------------------------------------------------
-- A switch changes at once, or goes to the vote: always in a Warcouncil (the council decides), and in a Democracy once
-- the guild has voted on it (a vote wins). SPEC decision 70.
local function setSwitch(key, value)
  local Ru = ns.Rules
  local setup = Ru.Setup()
  if setup == "warcouncil" or (setup == "democracy" and Ru.SwitchVoted(nil, key)) then
    local v = value
    if key == "incidents" then v = value == "court" end
    if ns.Council.Propose(Ru.SWITCH_RULE[key], v, L.SET_RULE_WHY) then ns:Print(L.SET_RULE_VOTE_SENT) end
    return
  end
  change(function(s) s.pun[key] = value s.pun.t = time() end)
end

local function buildRules(page, left, right)
  local c, w = left.child, left.inner
  local function set(fn) change(function(s) fn(s.pun) s.pun.t = time() end) end
  local pun = function() return ns.Rules.Pun() end
  page.ruleChecks, page.ruleSwitches = {}, {}
  local y = -2
  for _, x in ipairs({
    { L.SET_RULE_TAX, function() return pun().tax end, function(on) setSwitch("tax", on) end },
    { L.SET_RULE_COURT, function() return pun().incidents == "court" end,
      function(on) setSwitch("incidents", on and "court" or "direct") end },
    { L.SET_RULE_TRIAL, function() return pun().trial end, function(on) setSwitch("trial", on) end },
  }) do
    local b = wideCheck(c, w, x[1], x[2], x[3])
    b:SetPoint("TOPLEFT", 4, y)
    page.ruleChecks[#page.ruleChecks + 1] = b
    page.ruleSwitches[#page.ruleSwitches + 1] = b
    y = y - 40
  end
  page.switchNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.switchNote:SetPoint("TOPLEFT", 4, y - 4)
  c:SetHeight(-y + 60)
  c, w = right.child, right.inner
  y = -2
  for _, place in ipairs(ns.Rules.CLOSABLE) do
    local b = wideCheck(c, w, L["PLACE_" .. place:upper()], function() return settings().pun.closed[place] == true end,
      function(on) set(function(p) p.closed[place] = on or nil end) end)
    b:SetPoint("TOPLEFT", 4, y)
    page.ruleChecks[#page.ruleChecks + 1] = b
    y = y - 24
  end
  page.rulesNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.rulesNote:SetPoint("TOPLEFT", 4, y - 4)
  page.rulesNote:SetText(L.SET_RULES_NOTE)
  c:SetHeight(-y + 60)
end

local function layoutRules(page)
  local setup = ns.Rules.Setup()
  local none = setup == nil or setup == "free"
  for _, b in ipairs(page.ruleSwitches) do b:SetShown(not none) end
  local note = setup == nil and L.SET_RULES_NO_SETUP or (setup == "free" and L.RU_FREE)
    or (setup == "warcouncil" and L.SET_RULES_BY_COUNCIL) or (setup == "democracy" and L.SET_RULES_BY_GUILD) or ""
  page.switchNote:ClearAllPoints()
  page.switchNote:SetPoint("TOPLEFT", 4, none and -2 or -124)
  page.switchNote:SetText(note)
end

---------------------------------------------------------------------------
-- The guild's setup (SPEC decision 70): the five on the left, with each one's option; what the one picked here means
-- on the right, and the button that sets it. The first time, and later in a Monarchy, a Dictatorship or a Free guild,
-- it is set at once (a change cancels what is running); in a Democracy or a Warcouncil it goes to the vote.
---------------------------------------------------------------------------
local function pickOf(page)
  local Ru = ns.Rules
  local cur, opt = Ru.Setup()
  local p = page.setupPick
  -- (Started again from the setup in force whenever it or its option changes, by a vote or here.)
  local now = tostring(cur) .. ":" .. tostring(opt.elect == true) .. ":" .. tostring(opt.sits) .. ":" .. tostring(opt.judge)
  if not p or p.now ~= now then
    p = { id = cur, now = now, sits = opt.sits or "officers", judge = opt.judge or "ranks", elect = opt.elect == true }
    page.setupPick = p
  end
  return p, cur, opt
end

local function setupChanges(p, cur, opt)
  if p.id == nil then return false end
  if p.id ~= cur then return true end
  if p.id == "democracy" then return p.elect ~= (opt.elect == true) end
  if p.id == "warcouncil" then return p.sits ~= (opt.sits or "officers") end
  if p.id == "dictatorship" then return p.judge ~= (opt.judge or "ranks") end
  return false
end

local function pickSetup(page)
  local Ru = ns.Rules
  local p, cur, opt = pickOf(page)
  if not setupChanges(p, cur, opt) then return end
  local name = L["SETUP_" .. p.id:upper()]
  local function set()
    local _, _, was = Ru.Setup()
    change(function(s)
      local now = time()
      s.gov = { setup = p.id, sits = p.sits, judge = p.judge, elect = p.elect or nil, at = now,
        t = (cur and cur ~= p.id) and now or was }
      if cur ~= p.id then
        local first = Ru.START[p.id]
        s.pun.tax, s.pun.incidents, s.pun.trial, s.pun.t = first.tax, first.incidents, first.trial, now
      end
    end)
  end
  if not cur then
    Hall:Confirm(L.SET_SETUP_ASK_FIRST:format(name), L.SET_SETUP_PICK, set)
  elseif cur == p.id and cur ~= "democracy" and cur ~= "warcouncil" then
    Hall:Confirm(L.SET_SETUP_ASK_OPTION, L.SET_SETUP_CHANGE, set)
  elseif cur == "democracy" or cur == "warcouncil" then
    Hall:Confirm(L.SET_SETUP_ASK_VOTE:format(name, cur == "democracy" and L.SET_SETUP_THE_GUILD or L.SET_SETUP_THE_COUNCIL),
      L.SET_SETUP_VOTE, function()
        local ok = ns.Council.ProposeSetup(p.id, { sits = p.sits, judge = p.judge, elect = p.elect }, L.SET_SETUP_WHY:format(name))
        ns:Print(ok and L.SET_SETUP_VOTE_SENT or L.SET_SETUP_VOTE_BUSY, not ok)
      end)
  else
    Hall:Confirm(L.SET_SETUP_ASK_NOW:format(name), L.SET_SETUP_CHANGE, set)
  end
end

-- A setup's card (the 1 Nov review): its emblem and name, and what it says of the rules, incidents and overthrow;
-- "In force" on the one the guild has, a gold edge on the one picked here (and under the mouse, a lighter one).
local CARD_H, CARD_GAP = 100, 8
local function setupCard(page, c, id)
  local up = id:upper()
  local b = CreateFrame("CheckButton", nil, c)
  b.fillTex, b.edgeTex = UI.Glass(b)
  b.icon, b.ring = UI.Medallion(b, 30)
  b.icon:SetPoint("TOPLEFT", 10, -10)
  UI.SetIcon(b.icon, b.ring, UI.ICON[ns.Rules.ICON[id]] or UI.ICON.question, 30)
  b.name = UI.Color(UI.Text(b, "GameFontNormal"), "gold")
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.name:SetText(L["SETUP_" .. up])
  b.tag = UI.Color(UI.Text(b, "GameFontHighlightSmall", "RIGHT"), "goldHi")
  b.tag:SetPoint("TOPRIGHT", -8, -8)
  b.tag:SetText(L.SET_SETUP_IN_FORCE)
  b.facts = {}
  for i = 1, 3 do
    local t = UI.Text(b, "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 12, -46 - (i - 1) * 16)
    t:SetPoint("RIGHT", -8, 0)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    t:SetText(L["SETUP_" .. up .. "_CARD" .. i])
    b.facts[i] = t
  end
  b.Paint = function(self)
    local g, e = UI.LOOK.gold, UI.LOOK.edge
    if self:GetChecked() then self.edgeTex:SetVertexColor(g[1], g[2], g[3], 0.95)
    elseif self.over then self.edgeTex:SetVertexColor(g[1], g[2], g[3], 0.5)
    else self.edgeTex:SetVertexColor(e[1], e[2], e[3], e[4] or 1) end
  end
  b.Refresh = function(self)
    self:SetChecked(pickOf(page).id == id)
    self:Paint()
  end
  b:SetScript("OnClick", function()
    pickOf(page).id = id
    Hall:Refresh()
  end)
  b:HookScript("OnEnter", function(self) self.over = true self:Paint() end)
  b:HookScript("OnLeave", function(self) self.over = false self:Paint() end)
  UI.Tooltip(b, L["SETUP_" .. up], L["SETUP_" .. up .. "_SUB"])
  return b
end

local function buildSetup(page, pane)
  local c, w = pane.child, pane.inner
  page.setupRadios = {}
  for _, id in ipairs(ns.Rules.SETUPS) do page.setupRadios[id] = setupCard(page, c, id) end
  -- The picked setup's option, under the cards: who sits on the Warcouncil, who judges in a Dictatorship, whether a
  -- Democracy elects its Guild Master.
  local function opt(key, value, label)
    local r = UI.Radio(c, label, function() return pickOf(page)[key] == value end, function()
      pickOf(page)[key] = value
      Hall:Refresh()
    end)
    -- (A long option wraps under itself rather than being cut off.)
    r.label:SetWidth(w - 40)
    r.label:SetWordWrap(true)
    r.label:SetJustifyH("LEFT")
    return r
  end
  page.setupOpts = {
    democracy = { opt("elect", false, L.SETUP_OPT_KEEPS), opt("elect", true, L.SETUP_OPT_ELECT) },
    warcouncil = { opt("sits", "officers", L.SETUP_OPT_OFFICERS), opt("sits", "elders", L.SETUP_OPT_ELDERS:format(ns.Rules.ELDERS)) },
    dictatorship = { opt("judge", "ranks", L.SETUP_OPT_RANKS), opt("judge", "crown", L.SETUP_OPT_CROWN) },
  }
  page.setupNow = UI.Color(UI.Text(c, "GameFontNormal"), "gold")
  page.setupText = UI.Ink(UI.Wrap(c, "GameFontHighlightSmall", w - 8))
  page.setupNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.setupRight = pane
end

local function layoutSetup(page)
  local Ru = ns.Rules
  local p, cur, opt = pickOf(page)
  local pane = page.groups.setup.left
  local c, w = pane.child, pane.inner
  -- The cards, three across where there is room (else two).
  local cols = w >= 520 and 3 or 2
  local cw = math.floor((w - 8 - CARD_GAP * (cols - 1)) / cols)
  for i, id in ipairs(Ru.SETUPS) do
    local b = page.setupRadios[id]
    b:SetSize(cw, CARD_H)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4 + ((i - 1) % cols) * (cw + CARD_GAP), -4 - math.floor((i - 1) / cols) * (CARD_H + CARD_GAP))
    b.tag:SetShown(cur == id)
    b:Refresh()
  end
  local y = -4 - math.ceil(#Ru.SETUPS / cols) * (CARD_H + CARD_GAP) - 2
  for oid, list in pairs(page.setupOpts) do
    for _, b in ipairs(list) do
      b:SetShown(p.id == oid)
      if p.id == oid then
        b:Refresh()
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 8, y)
        y = y - math.max(22, math.ceil(b.label:GetStringHeight() or 12) + 8)
      end
    end
  end
  -- What the picked one means, and what pressing does.
  page.setupNow:ClearAllPoints()
  page.setupNow:SetPoint("TOPLEFT", 4, y - 4)
  page.setupNow:SetText(p.id and L.SET_SETUP_MEANS_OF:format(L["SETUP_" .. p.id:upper()]) or L.SET_SETUP_NONE)
  y = y - 26
  local lines = {}
  if p.id then
    for _, line in ipairs(Ru.SetupLines(p.id, p)) do lines[#lines + 1] = "- " .. line end
  else
    lines[1] = L.SET_SETUP_HELP
  end
  page.setupText:ClearAllPoints()
  page.setupText:SetPoint("TOPLEFT", 4, y)
  page.setupText:SetText(table.concat(lines, "\n"))
  y = y - math.ceil(page.setupText:GetStringHeight() or 60) - 10
  local changes = setupChanges(p, cur, opt)
  local vote = cur == "democracy" or cur == "warcouncil"
  local note = not cur and L.SET_SETUP_NOTE_FIRST or (vote and L.SET_SETUP_NOTE_VOTE) or L.SET_SETUP_NOTE_NOW
  page.setupNote:ClearAllPoints()
  page.setupNote:SetPoint("TOPLEFT", 4, y)
  page.setupNote:SetText(note)
  y = y - math.ceil(page.setupNote:GetStringHeight() or 40) - 8
  c:SetHeight(-y + 4)
  local foot = {}
  if changes then
    local label = not cur and L.SET_SETUP_PICK or (vote and L.SET_SETUP_VOTE) or L.SET_SETUP_CHANGE
    foot[1] = { label, function() pickSetup(page) end, next = not cur }
  end
  UI.Foot(page.setupRight, foot)
end

local function buildTheme(page, left, right)
  local c, w = left.child, left.inner
  local function drop(key, label, y)
    local t = UI.Text(c, "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", 4, y)
    t:SetText(label)
    local d = UI.Dropdown(c, w - 20)
    d:SetPoint("TOPLEFT", 10, y - 14)
    page.themeDrops = page.themeDrops or {}
    page.themeDrops[key] = d
  end
  drop("accent", L.SET_ACCENT, -2)
  drop("leather", L.SET_LEATHER, -48)
  drop("shade", L.SET_SHADE, -94)
  page.themeNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.themeNote:SetPoint("TOPLEFT", 4, -140)
  page.themeNote:SetText(L.SET_THEME_NOTE)
  page.themeReload = UI.Button(c, L.OPT_RELOAD, 140, function() ReloadUI() end, true)
  page.themeReload:SetPoint("TOPLEFT", 4, -176)
  c:SetHeight(210)

  c, w = right.child, right.inner
  local y = -2
  local t = UI.Text(c, "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", 4, y)
  t:SetText(L.SET_CREST)
  local th = function() return settings().theme end
  local function set(key, v) if th()[key] ~= v then change(function(s) s.theme[key] = v end) end end
  page.crestShield = UI.Radio(c, L.CREST_SHIELD, function() return th().crest == "shield" end, function() set("crest", "shield") end)
  page.crestShield:SetPoint("TOPLEFT", 4, y - 16)
  page.crestTabard = UI.Radio(c, L.CREST_TABARD, function() return th().crest == "tabard" end, function() set("crest", "tabard") end)
  page.crestTabard:SetPoint("TOPLEFT", 4 + math.floor(w / 2), y - 16)
  page.crestNote = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  page.crestNote:SetPoint("TOPLEFT", 4, y - 40)
  y = y - 72
  t = UI.Text(c, "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", 4, y)
  t:SetText(L.SET_MOTTO)
  page.motto = UI.Edit(c, w - 14, D.MOTTO_MAX, function() return th().motto end, function(text)
    local clean = ns.Agenda.Clean(text, D.MOTTO_MAX)
    if clean ~= th().motto then change(function(s) s.theme.motto = clean end) end
  end)
  page.motto:SetPoint("TOPLEFT", 10, y - 18)
  c:SetHeight(-(y - 48))
end

local function layoutTheme(page)
  local th = settings().theme
  local function list(key, prefix)
    local out = {}
    for i, v in ipairs(D.THEME[key]) do out[i] = { v, L[prefix .. v:upper()] } end
    return out
  end
  for key, prefix in pairs({ accent = "ACCENT_", leather = "LEATHER_", shade = "SHADE_" }) do
    page.themeDrops[key]:Set(list(key, prefix), th[key], function(v)
      if v ~= settings().theme[key] then change(function(x) x.theme[key] = v end) end
    end)
  end
  -- The reload button shows when the colours picked are not the ones this screen was made with.
  local now = UI.theme or {}
  page.themeReload:SetShown(now.accent ~= th.accent or now.leather ~= th.leather or now.shade ~= th.shade)
  page.crestNote:SetText(UI.TabardInfo() and L.CREST_TABARD_NOTE or L.CREST_NO_TABARD)
  for _, b in ipairs({ page.crestShield, page.crestTabard, page.motto }) do b:Refresh() end
end

---------------------------------------------------------------------------
-- Who may do what (SPEC §3.2, decision 50): the guild's ranks on the left; the picked rank's powers on the right,
-- grouped by place, a tick box each. Each rank is ticked on its own.
---------------------------------------------------------------------------
local function powerName(action)
  return action == "grant" and L.ACT_GRANT:format(settings().many) or L["ACT_" .. action:upper()]
end

-- A power's tooltip: what it does, and which ranks may (and the guild's vote, when it decided).
local function powerTip(action)
  return function() return powerName(action) end, function()
    local who, perm = { L.GUILD_MASTER }, D:Ranks(action)
    for _, rank in ipairs(ns.Roster:Ranks()) do if perm[rank.index] then who[#who + 1] = rank.name end end
    local allowed = "|cff9d9d9d" .. L.SET_ALLOWED:format(table.concat(who, ", ")) .. "|r"
    local g = D:Current()
    if g and D.Rule(g, action) ~= nil then
      allowed = allowed .. "\n|cffff8040" .. L.SET_VOTED:format(ns.Council.Describe(action, ns.Council.Current(g, action))) .. "|r"
    end
    local desc = L["ACT_" .. action:upper() .. "_DESC"]
    return desc and (desc .. "\n" .. allowed) or allowed
  end
end

local function buildWho(page, left, right)
  page.ranksFlow, page.powersFlow = UI.PaneFlow(left), UI.PaneFlow(right)
  page.powersPane = right
  local help = UI.Help(right.strip, L.SET_WHO, L.SET_WHO_NOTE)
  help:SetPoint("RIGHT", -8, 0)
end

-- The picked rank (by name): the one picked before while the guild still has it, else the first below the Guild Master.
local function pickedRank(page)
  local ranks = ns.Roster:Ranks()
  for _, r in ipairs(ranks) do if r.name == page.rank then return r end end
  page.rank = ranks[1] and ranks[1].name
  return ranks[1]
end

local function layoutWho(page)
  local s, g = settings(), D:Current()
  local ranks, picked = ns.Roster:Ranks(), pickedRank(page)
  local known = s.known
  local f = page.ranksFlow
  f:Begin()
  f:Row("gm", { icon = UI.ICON.throne, name = L.GUILD_MASTER, sub = L.SET_RANK_GM, dim = true })
  for i, r in ipairs(ranks) do
    local n = 0
    for _, a in ipairs(D.ACTIONS) do if D:Ranks(a)[r.index] then n = n + 1 end end
    f:Row("r" .. i, { icon = D.Officer(r, s) and UI.ICON.officer or UI.ICON.tabard, name = r.name,
      sub = D.Officer(r, s) and L.SET_RANK_OFFICER or L.SET_RANK_MEMBER,
      value = L.SET_RANK_POWERS:format(n), vsub = known and not known[r.name] and L.SET_RANK_NEW or nil,
      sel = picked ~= nil and r.name == picked.name,
      onClick = function() page.rank = r.name; Hall:Refresh() end })
  end
  f:End()
  page.powersPane.strip.title:SetText(picked and L.SET_POWERS:format(picked.name) or L.SET_WHO)
  f = page.powersFlow
  f:Begin()
  if not picked then
    f:Empty("none", L.SET_NO_RANKS)
  else
    for _, grp in ipairs(D.POWERS) do
      f:Strip("p." .. grp.place, L["PLACE_" .. grp.place:upper()])
      for _, a in ipairs(grp) do
        local voted = g ~= nil and D.Rule(g, a) ~= nil
        f:Check("a." .. a, voted and (powerName(a) .. " " .. L.SET_VOTED_TAG) or powerName(a),
          function() return D:Ranks(a)[picked.index] == true end,
          function(on)
            if voted then return Hall:Refresh() end
            D:Tick(a, picked.name, on)
          end, { powerTip(a) })
      end
    end
  end
  f:End()
end


---------------------------------------------------------------------------
-- The guild tax: how and from when on the left, gold per rank on the right
---------------------------------------------------------------------------
local function buildTax(page, left, right)
  local c, w = left.child, left.inner
  local y = -2
  page.taxOn = UI.Toggle(c, L.SET_TAX_ON, function() return settings().tax.on end, function(on)
    change(function(s) s.tax.on = on end)
  end, "GameFontHighlight")
  page.taxOn:SetPoint("TOPLEFT", 4, y - 4)
  y = y - 28
  page.taxWeek = UI.Radio(c, L.SET_TAX_WEEK, function() return settings().tax.per == "week" end, function()
    change(function(s) s.tax.per = "week" end)
  end)
  page.taxWeek:SetPoint("TOPLEFT", 4, y)
  page.taxMonth = UI.Radio(c, L.SET_TAX_MONTH, function() return settings().tax.per == "month" end, function()
    change(function(s) s.tax.per = "month" end)
  end)
  page.taxMonth:SetPoint("TOPLEFT", 4 + math.floor(w / 2), y)
  y = y - 28
  local _, lv = labelled(c, w, y, L.SET_TAX_LEVEL, 40, 2, function() return tostring(settings().tax.lv) end, function(typed)
    local v = tonumber(typed)
    if v and v == math.floor(v) and v >= 1 and v <= D.LEVEL_MAX and v ~= settings().tax.lv then
      change(function(s) s.tax.lv = v end)
    end
  end)
  page.taxLevel = lv
  y = y - 30
  local ex = UI.Text(c, "GameFontNormalSmall")
  ex:SetPoint("TOPLEFT", 4, y)
  ex:SetText(L.SET_TAX_EXEMPT)
  page.taxEx = UI.Edit(c, w - 14, 255, function()
    local list = {}
    for n in pairs(settings().tax.ex) do list[#list + 1] = ns.Display(n) end
    table.sort(list)
    return table.concat(list, ", ")
  end, function(typed)
    local exempt, n = {}, 0
    for part in (typed or ""):gmatch("[^,%s]+") do
      local full = ns.FullName(part)
      if full and n < D.EXEMPT_MAX and not exempt[full] then exempt[full], n = true, n + 1 end
    end
    change(function(s) s.tax.ex = exempt end)
  end)
  page.taxEx:SetPoint("TOPLEFT", 10, y - 14)
  y = y - 44
  local note = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  note:SetPoint("TOPLEFT", 4, y)
  note:SetText(L.SET_TAX_NOTE)
  y = y - math.ceil(note:GetStringHeight() or 36) - 6
  c:SetHeight(-y + 4)

  -- Gold per rank: a line for every possible rank, shown for the guild's (layoutTax).
  c, w = right.child, right.inner
  page.taxRows = {}
  for r = 0, D.RANK_MAX do
    local row = { rank = r }
    row.label, row.edit = labelled(c, w, 0, "", 56, 5, function()
      local a = settings().tax.amt[r]
      return a and tostring(a) or ""
    end, function(typed)
      typed = strtrim(typed or "")
      local v = tonumber(typed)
      if typed == "" or v == 0 then
        if settings().tax.amt[r] then change(function(s) s.tax.amt[r] = nil end) end
      elseif v and v == math.floor(v) and v >= 1 and v <= D.TAX_MAX and v ~= settings().tax.amt[r] then
        change(function(s) s.tax.amt[r] = v end)
      end
    end)
    page.taxRows[#page.taxRows + 1] = row
  end
end

-- The rank lines for the guild's ranks (the Guild Master's first).
local function layoutTax(page)
  local names = { [0] = L.GUILD_MASTER }
  for _, rank in ipairs(ns.Roster:Ranks()) do names[rank.index] = rank.name end
  local y, c, w = -2, page.groups.tax.right.child, page.groups.tax.right.inner
  for _, row in ipairs(page.taxRows) do
    local name = names[row.rank]
    row.label:SetShown(name ~= nil)
    row.edit:SetShown(name ~= nil)
    if name then
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", 4, y - 5)
      row.label:SetText(name)
      row.edit:ClearAllPoints()
      row.edit:SetPoint("TOPRIGHT", c, "TOPLEFT", w - 4, y)
      row.edit:Refresh()
      y = y - 26
    end
  end
  c:SetHeight(-y + 4)
  page.taxEx:Refresh()
end

---------------------------------------------------------------------------
-- The Council: its numbers, and the strike ladder
---------------------------------------------------------------------------
local function buildCouncil(page, left, right)
  local c, w = left.child, left.inner
  local y = -2
  page.numbers = {}
  for _, k in ipairs(D.NUMBER_KEYS) do
    local _, e = labelled(c, w, y, L["SET_CN_" .. k:upper()], 44, 3, function() return tostring(D:Number(k)) end, function(typed)
      local v, r = tonumber(typed), D.NUMBERS[k]
      if D.Rule(D:Current() or {}, k) ~= nil then return end
      if v and v == math.floor(v) and v >= r[2] and v <= r[3] and v ~= settings().cn[k] then
        change(function(s) s.cn[k] = v end)
      end
    end)
    page.numbers[#page.numbers + 1] = e
    y = y - 28
  end
  -- The court's switch (SPEC §7.3): does a guilty verdict sentence by itself? A vote of the guild can decide it.
  page.court = wideCheck(c, w, L.SET_COURT, function() return D:CourtSentences() end, function(on)
    local g = D:Current()
    if g and D.Rule(g, "sentence") ~= nil then return Hall:Refresh() end
    change(function(s) s.court = on end)
  end)
  page.court:SetPoint("TOPLEFT", 4, y - 2)
  y = y - 40
  local note = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  note:SetPoint("TOPLEFT", 4, y - 4)
  note:SetText(L.SET_COUNCIL_NOTE)
  y = y - math.ceil(note:GetStringHeight() or 36) - 10
  c:SetHeight(-y + 4)

  c, w = right.child, right.inner
  page.ladder = UI.Edit(c, w - 14, D.LADDER_MAX, function() return settings().ladder end, function(typed)
    local clean = ns.Raffle.Clean(typed, D.LADDER_MAX)
    if clean and clean ~= settings().ladder then change(function(s) s.ladder = clean end) end
  end)
  page.ladder:SetPoint("TOPLEFT", 10, -4)
end

---------------------------------------------------------------------------
-- The Chronicle and Discord: the mascot on the left, the Herald on the right
---------------------------------------------------------------------------
local function buildDiscord(page, left, right)
  local c, w = left.child, left.inner
  page.mascotName = UI.Edit(c, w - 14, D.MASCOT_NAME_MAX, function() return settings().mascot.name end, function(typed)
    local clean = ns.Raffle.Clean(typed, D.MASCOT_NAME_MAX)
    if clean and clean ~= settings().mascot.name then change(function(s) s.mascot.name = clean end) end
  end)
  page.mascotName:SetPoint("TOPLEFT", 10, -4)
  page.mascotKind = UI.Dropdown(c, w - 14)
  page.mascotKind:SetPoint("TOPLEFT", 10, -34)

  c, w = right.child, right.inner
  page.herald = UI.Edit(c, w - 14, 64, function()
    local g = D:Current()
    local h = g and ns.Herald.Herald(g)
    return h and ns.Display(h) or ""
  end, function(typed)
    typed = strtrim(typed or "")
    local full = typed ~= "" and ns.FullName(typed) or nil
    if not full then
      if settings().herald then change(function(s) s.herald = nil end) end
      return
    end
    if ns.Roster:Rank(full) == nil or not D:Can("herald", full) then ns:Print(L.SET_HERALD_BAD, true) return end
    if full ~= settings().herald then change(function(s) s.herald = full end) end
  end)
  page.herald:SetPoint("TOPLEFT", 10, -4)
  local note = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  note:SetPoint("TOPLEFT", 4, -34)
  note:SetText(L.SET_DISCORD_NOTE)
  c:SetHeight(math.ceil(note:GetStringHeight() or 60) + 40)
  UI.Foot(right, { { L.SET_POST_NOW, function() ns.Herald.PostNow() end } })
  UI.Tooltip(right.foot.buttons[1], L.SET_POST_NOW, L.SET_POST_NOW_TIP)
end

---------------------------------------------------------------------------
-- Places and features (SPEC decision 52): each place with its features, then the punishments and the guild games.
-- What is off hides for everyone. Built at the first refresh: the other pages (and their features) exist by then.
---------------------------------------------------------------------------
local SWITCH_PLACES = { "home", "challenges", "games", "gambling", "treasury", "professions", "punishments", "council" }

-- Tick boxes two to a line, under y; one whose name does not fit half a line takes a whole one (not cut off). list =
-- { { key, label = fn }, ... }. Returns the y under them.
local function switchGrid(page, c, w, y, list)
  local colW = math.floor((w - 18) / 2)
  local row, col = 0, 0
  for _, x in ipairs(list) do
    local key = x.key
    local b = UI.Toggle(c, x.label(), function() return D:On(key) end, function(on)
      change(function(s) s.off[key] = not on end)
    end)
    b.label:SetWordWrap(false)
    b.label:SetJustifyH("LEFT")
    local tw = b.label.GetUnboundedStringWidth and b.label:GetUnboundedStringWidth() or b.label:GetStringWidth()
    local wide = (tw or 0) > colW - 42
    if wide and col == 1 then row, col = row + 1, 0 end
    b.label:SetWidth((wide and (w - 18) or colW) - 42)
    b:SetPoint("TOPLEFT", 18 + col * colW, y - 3 - row * PAGE_ROW)
    if wide or col == 1 then row, col = row + 1, 0 else col = 1 end
    b.name = x.label
    page.switches[#page.switches + 1] = b
  end
  if col == 1 then row = row + 1 end
  return y - row * PAGE_ROW
end

local function buildSwitches(page)
  local grp = page.groups.features
  page.switches = {}
  local c, w = grp.left.child, grp.left.inner
  local note = UI.Ink(UI.Wrap(c, "GameFontDisableSmall", w - 8))
  note:SetPoint("TOPLEFT", 4, -2)
  note:SetText(L.SET_PAGES_NOTE)
  local y = -2 - math.ceil(note:GetStringHeight() or 24) - 8
  local switchable = {}
  for _, id in ipairs(D.PLACES) do switchable[id] = true end
  for _, id in ipairs(SWITCH_PLACES) do
    if switchable[id] then
      local b = UI.Toggle(c, L["PLACE_" .. id:upper()], function() return not settings().off[id] end, function(on)
        change(function(s) s.off[id] = (not on) or nil end)
      end, "GameFontNormal")
      b:SetPoint("TOPLEFT", 4, y - 3)
      page.pages[#page.pages + 1] = b
    else
      local t = UI.Color(UI.Text(c, "GameFontNormal"), "gold")
      t:SetPoint("TOPLEFT", 6, y - 5)
      t:SetText(L["PLACE_" .. id:upper()])
    end
    y = switchGrid(page, c, w, y - PAGE_ROW, ns.Hall:Switches(id)) - 4
  end
  c:SetHeight(-y + 4)

  c, w = grp.right.child, grp.right.inner
  y = -2
  local function head(text)
    local t = UI.Color(UI.Text(c, "GameFontNormal"), "gold")
    t:SetPoint("TOPLEFT", 6, y - 5)
    t:SetText(text)
    y = y - PAGE_ROW
  end
  local puns, games = {}, {}
  for i, p in ipairs(D.PUNISHMENTS) do puns[i] = { key = "p:" .. p, label = function() return L["ACT_" .. p:upper()] end } end
  for i, k in ipairs(ns.Games.KINDS) do games[i] = { key = "g:" .. k, label = function() return L["GM_" .. k:upper()] end } end
  head(L.PLACE_PUNISHMENTS)
  y = switchGrid(page, c, w, y, puns) - 6
  head(L.GM_GUILD_GAMES)
  y = switchGrid(page, c, w, y, games)
  c:SetHeight(-y + 4)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
-- How many features the Guild Master has switched off (Places and features).
local function switchedOff()
  local n = 0
  for _, pl in ipairs(Hall.PLACES) do
    for _, x in ipairs(Hall:Switches(pl.id)) do if not D:On(x.key) then n = n + 1 end end
  end
  return n
end

Hall:Register({
  id = "settings", label = L.PAGE_SETTINGS, sub = L.PAGE_SETTINGS_SUB,
  gear = true,
  -- The guild's setup, until picked (SPEC decision 70); new or renamed ranks in the game (SPEC §3.2): the Guild
  -- Master checks who may do what.
  todo = function()
    local out = {}
    if D:InCharge() and ns.Rules.Setup() == nil then out[#out + 1] = L.SET_SETUP_TODO end
    if D:InCharge() and D:NewRanks() > 0 then out[#out + 1] = L.SET_RANKS_CHANGED end
    return out
  end,
  build = function(page)
    local L_W, top = Hall.LIST_W, 0
    page.groups = {}
    -- Each group is its own frame holding its panes, so the panes of the others hide with it.
    local function group(id, ...)
      local f = CreateFrame("Frame", nil, page.body)
      f:SetAllPoints()
      local holder = { body = f }
      local a, b = Hall:Panes(holder, top, ...)
      page.groups[id] = { frame = f, left = a, right = b }
      return a, b
    end
    local mine = group("mine", { 0, { title = L.OPT_TITLE } })
    page.mineFlow = UI.PaneFlow(mine)
    buildSetup(page, group("setup", { 0, { title = L.SET_SETUP, foot = true } }))
    buildGeneral(page, group("general", { 0, { title = L.SET_PURSE } }))
    group("features", { L_W, { title = L.SET_PAGES } }, { 0, { title = L.SET_MORE_SWITCHES } })
    page.pages = {}
    buildWho(page, group("who", { L_W, { title = L.SET_RANKS } }, { 0, { title = L.SET_WHO } }))
    buildTax(page, group("tax", { L_W, { title = L.SET_TAX } }, { 0, { title = L.SET_TAX_AMT } }))
    buildCouncil(page, group("council", { L_W, { title = L.SET_COUNCIL } }, { 0, { title = L.SET_LADDER } }))
    buildDiscord(page, group("disc", { L_W, { title = L.SET_MASCOT } }, { 0, { title = L.SET_HERALD, foot = true } }))
    buildTheme(page, group("theme", { L_W, { title = L.SET_THEME_COLOURS } }, { 0, { title = L.SET_THEME_MARKS } }))
    buildRules(page, group("rules", { L_W, { title = L.SET_RULES_SWITCHES } }, { 0, { title = L.SET_RULES_CLOSED } }))
    -- Each group is a feature in the guild window (they cannot be switched off), with what it says now.
    local labels = { mine = L.OPT_TITLE, setup = L.SET_TAB_SETUP, general = L.SET_TAB_GENERAL, features = L.SET_TAB_FEATURES, who = L.SET_WHO, tax = L.SET_TAX,
      council = L.SET_COUNCIL, disc = L.SET_DISCORD, theme = L.SET_TAB_THEME, rules = L.SET_TAB_RULES }
    local icons = { mine = UI.ICON.options, setup = UI.ICON.crown, general = UI.ICON.marks, features = UI.ICON.pl_manage, who = UI.ICON.officer, tax = UI.ICON.purse,
      council = UI.ICON.ballot, disc = UI.ICON.mail, theme = UI.ICON.flag, rules = UI.ICON.scales }
    local tabs = {}
    for _, id in ipairs(GROUPS) do tabs[#tabs + 1] = { id, labels[id], icon = icons[id], always = true } end
    Hall:Split(page, {
      tabs = tabs, parts = {}, own = true, save = "setGroup",
      status = {
        mine = function() return L.OPT_ROW_SUB end,
        setup = function()
          local cur = ns.Rules.Setup()
          return cur and L["SETUP_" .. cur:upper()] or L.SET_SETUP_NOT_YET
        end,
        general = function() return settings().purse == "marks" and settings().many or L.PURSE_GOLD end,
        features = function()
          local n = switchedOff()
          return n == 0 and L.SET_ALL_ON or L.SET_OFF_N:format(n)
        end,
        who = function() return D:NewRanks() > 0 and L.SET_RANKS_NEW or nil end,
        tax = function() return settings().tax.on and L.SET_TAX_IS_ON or L.SET_TAX_IS_OFF end,
        theme = function() return L["ACCENT_" .. settings().theme.accent:upper()] end,
      },
      count = {
        who = function() return D:NewRanks() end,
        setup = function() return (D:InCharge() and ns.Rules.Setup() == nil) and 1 or 0 end,
      },
    })
  end,
  refresh = function(page)
    local s = settings()
    for gid, grp in pairs(page.groups) do grp.frame:SetShown(gid == page.part) end
    if page.part == "mine" then
      page.mineFlow:Begin()
      ns.Card.DrawOptions(page.mineFlow)
      page.mineFlow:End()
    end
    if not page.switches then buildSwitches(page) end
    if page.part == "who" and page:IsVisible() then D:SeenRanks() end
    if page:IsVisible() and D:InCharge() then ns.Welcomed("set:" .. tostring(page.part)) end
    page.gold:Refresh()
    page.marks:Refresh()
    page.one:Refresh()
    page.many:Refresh()
    for _, b in ipairs(page.pages) do b:Refresh() end
    for _, b in ipairs(page.switches) do
      b:Refresh()
      b.label:SetText(b.name())
    end
    page.court:Refresh()
    page.announce:Refresh()
    for _, e in ipairs(page.numbers) do e:Refresh() end
    page.ladder:Refresh()
    page.mascotName:Refresh()
    local kinds = {}
    for i, k in ipairs(D.MASCOTS) do kinds[i] = { k, L["CH_KIND_" .. k:upper()] } end
    page.mascotKind:Set(kinds, s.mascot.kind, function(v) change(function(x) x.mascot.kind = v end) end)
    page.herald:Refresh()
    page.taxOn:Refresh()
    page.taxWeek:Refresh()
    page.taxMonth:Refresh()
    page.taxLevel:Refresh()
    layoutGeneral(page)
    layoutTax(page)
    layoutWho(page)
    layoutTheme(page)
    layoutSetup(page)
    layoutRules(page)
    for _, b in ipairs(page.ruleChecks) do b:Refresh() end
  end,
})
