-- Council (SPEC §7, decision 48): leadership, the charter, polls, the court, strikes and the Guild Master's election, each
-- with its state on the left. What you can start there (a poll, a charge, a strike...) opens beside the window, for the
-- ranks that may; the Guild Master edits the charter in place.
-- The hand-over is the game's own /gleader on a secure button (SPEC §7.5 step 4): only the Guild Master's press does
-- it, and it is placed and set only out of combat.
local _, ns = ...
local L, UI, D, Hall, R = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Roster
local P, Co, Ct, Cu, St = ns.Players, ns.Council, ns.Court, ns.Cup, ns.Stocks

local SECTIONS = { "impeach", "charter", "votes", "court", "strikes", "elect" }
local ICONS = { impeach = "throne", charter = "scroll", votes = "ballot", court = "scales", strikes = "flag", elect = "crown" }
-- The guild's say over its Guild Master (Leadership, and Votes, where a rule change wins over the settings): the Guild
-- Master cannot switch them off (SPEC decision 52).
local ALWAYS = { impeach = true, votes = true, elect = true }
-- Who accepted the rules, at most this many tiles in the right column.
local CHARTER_TILES = 12

local function name(n) return ns.Display(n) end
local function num(box) return tonumber(strtrim(box:GetText() or "")) end
local function text(box) return strtrim(box:GetText() or "") end
local function g() return D:Current() end

local function left(sec)
  sec = math.max(0, math.floor(sec))
  if sec >= 2 * 86400 then return L.AR_DAYS:format(math.floor(sec / 86400)) end
  if sec >= 2 * 3600 then return L.ST_HOURS:format(math.floor(sec / 3600)) end
  return L.ST_MIN:format(math.max(1, math.ceil(sec / 60)))
end

local function pct(a, b) return b > 0 and math.floor(a * 100 / b + 0.5) or 0 end

-- A member of the guild from what was typed: their name, with or without the realm.
local function member(typed)
  typed = strtrim(typed or ""):lower()
  if typed == "" then return nil end
  for full in pairs(R.pretend and R.pretend.ranks or R.ranks) do
    if full:lower() == typed or Ambiguate(full, "short"):lower() == typed then return full end
  end
  return nil
end

local function rankName(i)
  if i == 0 then return L.GUILD_MASTER end
  for _, r in ipairs(R:Ranks()) do if r.index == i then return r.name end end
  return tostring(i)
end

-- A rule's value in words: "Officer and above", a number, on or off.
function Co.Describe(r, v)
  local kind = Co.RULES[r]
  if kind == "ranks" then
    local top = 0
    for _, i in ipairs(v) do top = math.max(top, i) end
    if top == 0 then return L.CO_GM_ONLY end
    return L.CO_AND_ABOVE:format(rankName(top))
  elseif kind == "flag" then
    if r == "pcourt" then return v and L.CO_PCOURT_ON or L.CO_PCOURT_OFF end
    return v and L.CO_ON or L.CO_OFF
  end
  return tostring(v)
end

-- A setup with its option, in words: "Warcouncil · The officers sit on it".
local function setupWords(id, opt)
  local line = L["SETUP_" .. id:upper()]
  if id == "democracy" and opt.elect then
    line = line .. " · " .. L.SETUP_OPT_ELECT
  elseif id == "warcouncil" then
    line = line .. " · " .. (opt.sits == "elders" and L.SETUP_OPT_ELDERS:format(ns.Rules.ELDERS) or L.SETUP_OPT_OFFICERS)
  elseif id == "dictatorship" then
    line = line .. " · " .. (opt.judge == "crown" and L.SETUP_OPT_CROWN or L.SETUP_OPT_RANKS)
  end
  return line
end

local function ruleName(r) return L["CO_RULE_" .. r:upper()] end

---------------------------------------------------------------------------
-- The hand-over button (secure)
---------------------------------------------------------------------------
local hand
local function buildHand()
  if hand then return end
  hand = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
  hand:RegisterForClicks("AnyUp", "AnyDown")
  hand:SetAttribute("type", "macro")
  hand:SetSize(200, 22)
  hand:SetFrameStrata("DIALOG")
  hand:Hide()
end
ns:On("LOGIN", function() ns.Combat:AfterCombat(buildHand) end)

local function hideHand()
  if hand and hand:IsShown() then ns.Combat:AfterCombat(function() hand:Hide() end) end
end

-- The button, for the self-test.
function Co.HandButton() return hand end

-- Puts the button over the placeholder: only out of combat (else a line says to wait). In the self-test's pretend
-- guild it does nothing when pressed: a pretend winner's name could be a real member of the real guild.
local function showHand(anchor, winner)
  if not hand or InCombatLockdown() then return false end
  hand:SetAttribute("macrotext", D.sandbox and "" or ("/gleader " .. Ambiguate(winner, "none")))
  hand:SetText(L.CO_HAND_OVER:format(name(winner)))
  UI.Glow(hand, true)
  hand:ClearAllPoints()
  hand:SetPoint("TOPLEFT", anchor, "TOPLEFT")
  hand:Show()
  return true
end

---------------------------------------------------------------------------
-- Leadership (SPEC §7.5, decision 46): an impeachment by the officers, a Mak'gora or the crown, then the hand-over
---------------------------------------------------------------------------
local STEPS = {
  lead = { "vote", "handover" },
  mak = { "challenge", "vote", "duel", "handover" },
  rebel = { "challenge", "rebellion", "duel", "handover" },
  crown = { "signup", "tourney", "handover" },
}

-- Each step's medallion in the tracker.
local STEP_ICON = { challenge = "wanted", vote = "ballot", rebellion = "flag", duel = "duel", handover = "throne",
  signup = "scroll", tourney = "prize" }

-- The steps as a tracker of lit icons (the 1 Nov review). (A Dictatorship's Mak'gora: the rebellion's steps; a
-- declined one waits at the rebellion.)
local function steps(f, key, mo, phase)
  local kind = (mo.kind == "mak" and mo.dict) and "rebel" or mo.kind
  if phase == "declined" then phase = "rebellion" end
  local list, at = STEPS[kind] or {}, 0
  for i, st in ipairs(list) do if st == phase then at = i end end
  if Co.DONE[phase] then at = #list + 1 end
  local out = {}
  for i, st in ipairs(list) do
    out[i] = { label = L["CO_STEP_" .. st:upper()], icon = STEP_ICON[st],
      state = i < at and "done" or (i == at and "now" or "next") }
  end
  f:Steps(key, out)
end

-- The step a leadership motion is at, in a word (the left menu).
local function stepWord(s) return L["CO_STEP_" .. s.phase:upper()] or L.CO_STATE_QUIET end

local function cupBlock(f, s, me)
  local c = s.cup
  local isHost = c and c.h == me
  if s.phase == "signup" then
    if not c then
      f:Text("cw", L.CO_CUP_SOON, "GameFontDisableSmall")
      return
    end
    local joined = Cu.Joined(c)
    local list = {}
    for i, n in ipairs(joined) do list[i] = UI.Who(n) end
    f:Text("cj", L.CO_CUP_SIGNUP:format(#joined, left(c.t + Co.SIGNUP - Co.Now())))
    if #list > 0 then f:Text("cl", table.concat(list, ", "), "GameFontDisableSmall") end
    local mine = c.j[me] and c.j[me].on
    local buttons = { { mine and L.CO_WITHDRAW or L.CO_SIGN_UP, function() Cu.Join(s.id, not mine) end } }
    if isHost and #joined >= 2 then buttons[#buttons + 1] = { L.CO_CUP_GO, function() Cu.Go(s.id) end } end
    f:Buttons("cb", buttons)
    return
  end
  local B = Cu.Build(c)
  local live = Cu.Live(B)
  f:Text("ct", L.CO_CUP_LIVE:format(L["AR_FMT_" .. c.fmt] or c.fmt, c.bo))
  for i, m in ipairs(live) do
    if i > 6 then break end
    local line = L.CO_MATCH:format(UI.Who(m.a), UI.Who(m.b))
    if isHost then
      f:Line("m" .. i, line, L.CO_WALKOVER, function()
        Hall:Confirm(L.CO_WALKOVER_ASK:format(name(m.a), name(m.b)), name(m.a), function() Cu.Walkover(s.id, m, m.a) end)
      end)
    else
      f:Text("m" .. i, line)
    end
  end
  if #live == 0 then f:Text("none", L.CO_CUP_DECIDED, "GameFontDisableSmall") end
end

-- The officers' vote: the tally, who leads, each officer's state, and your own vote (yes with a name, or no).
local function impeachBlock(f, page, s, now, me)
  local gg = g()
  f:Bar("bar", s.n > 0 and s.yes / s.n or 0, L.CO_IMP_TALLY:format(s.yes, s.no, s.need, s.n))
  for i, c in ipairs(s.cands or {}) do
    if i > 4 then break end
    f:Pair("cand" .. i, UI.Who(c.name), L.CO_IMP_VOTES:format(c.n))
  end
  if s.phase ~= "vote" then return end
  f:Pair("left", L.CO_VOTE_LEFT, left(s.ve - now))
  local mine, isVoter = P:Of(me, gg), false
  for _, n in ipairs(s.voters) do if P:Of(n, gg) == mine then isVoter = true end end
  if not isVoter then
    f:Text("who", L.CO_IMP_NOT_VOTER:format(#s.voters), "GameFontDisableSmall")
    return
  end
  if s.mine ~= nil then
    f:Text("mine", s.mine and L.CO_IMP_YOU_YES:format(UI.Who(s.mineC)) or L.CO_IMP_YOU_NO:format(UI.Who(s.mo.gm)))
  end
  -- Yes needs a name: typed, or a click on a member who leads.
  page.candBox = f:Field("cand", L.CO_IMP_WHO, f.width - 12)
  page.candBox:SetMaxLetters(48)
  f:Buttons("vote", {
    { L.CO_IMP_YES, function()
      local c = member(text(page.candBox))
      if not c or not Co.Candidate(c) then return ns:Print(L.CO_IMP_BAD_NAME, true) end
      if Co.ImpVote(s.id, true, c) then page.candBox:SetText("") end
    end, next = s.mine == nil },
    { L.CO_IMP_NO, function() Co.ImpVote(s.id, false) end, next = s.mine == nil },
  }, L.CO_IMP_CHANGE)
end

-- Mak'gora: the Guild Master's answer, the guild's vote, the duel.
local function makBlock(f, s, now, me)
  local gg, mo = g(), s.mo
  local isGM = P:Of(me, gg) == P:Of(mo.gm, gg) and R:Rank(me) == 0
  if s.phase == "challenge" then
    f:Pair("left", L.CO_MAK_ANSWER_LEFT, left(s.deadline - now))
    if isGM then
      f:Text("ask", L.CO_MAK_ASK, "GameFontNormal")
      f:Buttons("answer", { { L.CO_MAK_ACCEPT, function() Co.Answer(s.id, true) end, next = true },
        { L.CO_MAK_DECLINE, function()
          Hall:Confirm(mo.dict and L.CO_MAK_DECLINE_ASK_REBEL or L.CO_MAK_DECLINE_ASK, L.CO_MAK_DECLINE,
            function() Co.Answer(s.id, false) end)
        end, next = true } })
    else
      f:Text("wait", L.CO_MAK_WAIT:format(name(mo.gm)), "GameFontDisableSmall")
    end
  elseif s.phase == "vote" or (s.phase == "failed" and s.vs) then
    f:Text("q", L.CO_MAK_FORCE:format(UI.Who(mo.gm), UI.Who(mo.a)), "GameFontNormal")
    f:Bar("bar", s.cast > 0 and s.yes / s.cast or 0, L.CO_YES_NO_N:format(s.yes, pct(s.yes, s.cast), s.no))
    f:Pair("cast", L.CO_CAST, L.CO_CAST_OF:format(s.cast, mo.m, pct(s.cast, mo.m)))
    if s.phase == "vote" then
      f:Pair("left", L.CO_VOTE_LEFT, left(s.ve - now))
      local key = P:Of(me, gg)
      if key ~= P:Of(mo.gm, gg) and key ~= P:Of(mo.a, gg) then
        if s.mine ~= nil then
          f:Buttons("act", { { s.mine and L.CO_NO or L.CO_YES, function() Co.VoteMotion(s.id, not s.mine) end } },
            L.CO_YOU_VOTED:format(s.mine and L.CO_YES or L.CO_NO))
        else
          f:Buttons("act", { { L.CO_YES, function() Co.VoteMotion(s.id, true) end, next = true },
            { L.CO_NO, function() Co.VoteMotion(s.id, false) end, next = true } })
        end
      end
    end
  end
  -- A rebellion (a Dictatorship, SPEC decision 70): the challenger declares it, members sign it.
  local key = P:Of(me, gg)
  if s.phase == "declined" then
    f:Text("declined", L.CO_REBEL_DECLINED:format(UI.Who(mo.gm)), "GameFontNormal")
    f:Pair("left", L.CO_REBEL_DECLARE_LEFT, left(s.deadline - now))
    if key == P:Of(mo.a, gg) then
      f:Buttons("rebel", { { L.CO_REBEL_DECLARE, function()
        Hall:Confirm(L.CO_REBEL_ASK, L.CO_REBEL_DECLARE, function() Co.Rebel(s.id) end)
      end, next = true } })
    else
      f:Text("rwait", L.CO_REBEL_WAIT:format(name(mo.a)), "GameFontDisableSmall")
    end
  end
  if s.rb then
    f:Bar("rbar", math.min(1, (s.signed or 0) / s.need), L.CO_REBEL_SIGNED:format(s.signed or 0, s.need))
    local names = {}
    for i, n in ipairs(s.signers or {}) do if i <= 8 then names[#names + 1] = name(n) end end
    if #(s.signers or {}) > 8 then names[#names + 1] = L.CO_AND_MORE:format(#s.signers - 8) end
    f:Text("signers", table.concat(names, ", "), "GameFontDisableSmall")
    if s.phase == "rebellion" then
      f:Pair("left", L.CO_REBEL_SIGN_LEFT, left(s.deadline - now))
      if s.mine then
        f:Text("signed", L.CO_REBEL_YOU, "GameFontDisableSmall")
      elseif key ~= P:Of(mo.gm, gg) then
        f:Buttons("sign", { { L.CO_REBEL_SIGN, function() Co.Sign(s.id) end, next = true } })
      end
    end
  end
  if s.phase == "duel" then
    local said = (s.rebel and L.CO_REBEL_FORCED) or (s.forced and L.CO_MAK_FORCED) or L.CO_MAK_ACCEPTED
    f:Text("duel", said:format(UI.Who(mo.gm), UI.Who(mo.a)), "GameFontNormal")
    f:Pair("left", L.CO_MAK_FIGHT_LEFT, left(s.deadline - now))
    f:Text("how", L.CO_MAK_HOW_DUEL:format(name(mo.a)), "GameFontDisableSmall")
  end
end

local WAY_ICON = { lead = "ballot", mak = "axes", crown = "crown", elect = "throne" }

local function leadership(f, page)
  local gg, me, now = g(), ns.Self(), Co.Now()
  local open = Co.Lead(gg, now)
  local s = open or Co.Motions(gg, now, "lead")[1]
  local gm = Co.GM()
  local showing = false
  if not s or (not open and now - s.mo.t > 30 * 86400) then
    f:Row("lead", { icon = UI.ICON.throne, name = gm and UI.Who(gm) or L.CO_NO_GM, sub = L.GUILD_MASTER })
    -- The three ways to a new Guild Master, a line each (a click explains the laws).
    f:Text("idle", L.CO_IDLE, "GameFontDisableSmall")
    local setup, ways = ns.Rules.Setup(gg), {}
    if setup ~= "dictatorship" then ways[#ways + 1] = "lead" end
    ways[#ways + 1] = "mak"
    ways[#ways + 1] = "crown"
    if Co.Elects(gg) then ways[#ways + 1] = "elect" end
    for _, k in ipairs(ways) do
      local sub = (k == "mak" and setup == "dictatorship") and L.CO_WAY_MAK_REBEL or L["CO_WAY_" .. k:upper()]
      f:Row("way" .. k, { icon = UI.ICON[WAY_ICON[k]], name = L["CO_KIND_" .. k:upper()], sub = sub,
        onClick = function() page.View({ kind = "how" }) end })
    end
  else
    local mo = s.mo
    f:Strip("kind", L["CO_KIND_" .. mo.kind:upper()])
    steps(f, "steps", mo, s.phase)
    if mo.kind == "crown" then
      f:Text("why", L.CO_CROWN_OPENED:format(UI.Who(mo.a)))
    elseif mo.kind == "lead" then
      f:Text("why", L.CO_IMP_BY:format(UI.Who(mo.a), mo.why or ""))
    else
      f:Text("why", L.CO_MAK_BY:format(UI.Who(mo.a), UI.Who(mo.gm), mo.why or ""))
    end
    if mo.say then f:Text("say", L.CO_STATEMENT:format(name(mo.say.a), mo.say.text), "GameFontDisableSmall") end
    if mo.kind == "lead" then
      impeachBlock(f, page, s, now, me)
    elseif mo.kind == "mak" then
      makBlock(f, s, now, me)
    elseif s.phase == "signup" or s.phase == "tourney" then
      f:Text("passed", L.CO_CROWN_TOURNEY:format(UI.Who(mo.gm)))
      cupBlock(f, s, me)
    end
    if s.phase == "handover" then
      f:Text("won", L["CO_WON_" .. mo.kind:upper()]:format(UI.Who(s.winner)), "GameFontNormal")
      local holder = gm or mo.gm
      f:Text("locked", L.CO_LOCKED:format(UI.Who(holder), UI.Who(s.winner)))
      if R:Rank(me) == 0 then
        f:Text("only", L.CO_ONLY_YOU, "GameFontDisableSmall")
        local spot = f:piece("hand", function() local fr = CreateFrame("Frame", nil, f.card) fr:SetSize(200, 22) return fr end, "hand")
        spot:SetPoint("TOPLEFT", f.pad, f.y)
        f:Space(28)
        showing = showHand(spot, s.winner)
        if not showing then f:Text("combat", L.CO_HAND_COMBAT, "GameFontDisableSmall") end
      else
        f:Text("wait", L.CO_WAIT_HAND:format(name(holder)), "GameFontDisableSmall")
      end
    elseif s.phase == "handed" then
      f:Text("done", L.CO_HANDED:format(UI.Who(s.winner)), "GameFontNormal")
    elseif s.phase == "kept" then
      f:Text("done", L.CO_KEPT:format(UI.Who(mo.gm)), "GameFontNormal")
    elseif s.phase == "failed" then
      local said = (s.rebel and L.CO_REBEL_FAILED) or (mo.kind == "mak" and L.CO_MAK_FAILED) or L.CO_IMP_FAILED
      f:Text("done", said:format(UI.Who(mo.gm)), "GameFontNormal")
    elseif s.phase == "cancelled" then
      f:Text("done", L.CO_IMP_CANCELLED:format(UI.Who(mo.a)), "GameFontNormal")
    end
    -- The Guild Master answers with a statement while it is open.
    if R:Rank(me) == 0 and open == s and (s.phase == "vote" or s.phase == "challenge" or s.phase == "duel") then
      page.sayBox = f:Field("sayBox", L.CO_STATEMENT_LABEL, f.width - 90)
      page.sayBox:SetMaxLetters(Co.SAY_MAX)
      f:Buttons("sayGo", { { L.CO_POST, function()
        if text(page.sayBox) ~= "" and Co.Say(s.id, text(page.sayBox)) then page.sayBox:SetText("") end
      end } })
    end
  end
  if not showing then hideHand() end
  local foot = {}
  if open and open.kind == "lead" and open.phase == "vote" and open.mo.a == me then
    foot[#foot + 1] = { L.CO_IMP_CANCEL, function()
      Hall:Confirm(L.CO_IMP_CANCEL_ASK, L.CO_IMP_CANCEL, function() Co.Cancel(open.id) end)
    end }
  elseif not open then
    if D:InCharge(me) then
      foot[#foot + 1] = { L.CO_OPEN_CROWN, function()
        Hall:Confirm(L.CO_OPEN_CROWN_ASK, L.CO_OPEN_CROWN, function() Co.OpenCrown() end)
      end }
    elseif R:Rank(me) ~= nil and R:Rank(me) ~= 0 then
      if D:Can("impeach") then foot[#foot + 1] = { L.CO_IMP_DOTS, function() page.View({ kind = "impeach" }) end } end
      foot[#foot + 1] = { L.CO_MAK_DOTS, function() page.View({ kind = "mak" }) end }
    end
  end
  foot[#foot + 1] = { L.CO_HOW_DOTS, function() page.View({ kind = "how" }) end }
  return foot
end

-- The laws (SPEC §7.5), in short.
local function leadHow(f, page)
  f:Strip("how", L.CO_HOW)
  for i = 1, 8 do if L["CO_LAW_" .. i] then f:Text("h" .. i, L["CO_LAW_" .. i]) end end
  f:Text("note", L.CO_HOW_NOTE, "GameFontDisableSmall")
  return { { L.CANCEL, function() page.View(nil) end } }
end

-- Why a leadership motion cannot start now, in words (Co.MayStart's reason).
local function notNow(why)
  return why and L["CO_NOT_" .. why:upper()] or nil
end

-- Starting an impeachment (an officer) or a Mak'gora (a member): a reason, then a confirmation.
local function startForm(kind)
  return function(f, page)
    local gg, me = g(), ns.Self()
    f:Strip("start", L["CO_KIND_" .. kind:upper()])
    f:Text("law", kind == "lead" and L.CO_LAW_1 or L.CO_LAW_2)
    local ok, why = Co.MayStart(gg, kind, me)
    if kind == "lead" and not D:Can("impeach") then ok, why = false, "rank" end
    if not ok then
      f:Text("no", notNow(why), "GameFontNormal")
      return { { L.CANCEL, function() page.View(nil) end } }
    end
    if kind == "lead" then f:Text("voters", L.CO_IMP_VOTERS:format(#Co.Officers(gg)), "GameFontDisableSmall") end
    page.whyBox = f:Field("why", L.CO_REASON, f.width - 12)
    page.whyBox:SetMaxLetters(Co.WHY_MAX)
    local label = kind == "lead" and L.CO_IMP_START or L.CO_MAK_START
    return { { label, function()
      local reason = text(page.whyBox)
      if reason == "" then return ns:Print(L.CO_NEED_REASON, true) end
      local ask = kind == "lead" and L.CO_IMP_ASK or L.CO_MAK_START_ASK:format(name(Co.GM() or "?"))
      Hall:Confirm(ask, label, function()
        local done = kind == "lead" and Co.Impeach(reason) or (kind == "mak" and Co.Challenge(reason))
        if done then page.whyBox:SetText("") page.View(nil) end
      end)
    end }, { L.CANCEL, function() page.View(nil) end } }
  end
end

---------------------------------------------------------------------------
-- The charter
---------------------------------------------------------------------------
local function charter(f, page)
  local gg, me = g(), ns.Self()
  local c, yes, total = Co.Charter(gg)
  f:Strip("ver", c and L.CO_CHARTER_V:format(c.v) or L.CO_CHARTER)
  if page.editing then
    local box = f:piece("edit", function()
      local e = UI.Create("EditBox", f.card)
      e:SetMultiLine(true)
      e:SetAutoFocus(false)
      e:SetFontObject("GameFontHighlightSmall")
      e:SetMaxLetters(Co.LINES_MAX * (Co.LINE_MAX + 1))
      e:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
      return e
    end, "editbox")
    box:SetSize(f.width, 200)
    box:SetPoint("TOPLEFT", f.pad, f.y)
    if not page.editFilled then
      box:SetText(c and table.concat(c.lines, "\n") or "")
      page.editFilled = true
    end
    page.charterBox = box
    f:Space(206)
    f:Text("hint", L.CO_CHARTER_HINT:format(Co.LINES_MAX), "GameFontDisableSmall")
    return {
      { L.CO_SAVE, function()
        local lines = {}
        for line in (box:GetText() or ""):gmatch("[^\n]+") do
          line = strtrim(line)
          if line ~= "" and #lines < Co.LINES_MAX then lines[#lines + 1] = line end
        end
        if #lines == 0 then return ns:Print(L.CO_CHARTER_EMPTY, true) end
        if Co.WriteCharter(lines) then page.editing, page.editFilled = nil, nil; Hall:Refresh() end
      end },
      { L.CANCEL, function() page.editing, page.editFilled = nil, nil; Hall:Refresh() end },
    }
  end
  if c then
    for i, line in ipairs(c.lines) do f:Text("l" .. i, L.CO_LINE:format(i, line)) end
    f:Strip("acc", L.CO_ACCEPTED)
    f:Bar("accBar", total > 0 and yes / total or 0, L.CO_ACCEPTED_N:format(yes, total))
  else
    f:Empty("none", L.CO_NO_CHARTER, D:InCharge(me) and L.CO_NO_CHARTER_DO:format(UI.Key(L.CO_WRITE_CHARTER))
      or L.CO_NO_CHARTER_WAIT)
  end
  f:Text("rules", L.CO_CHARTER_RULES, "GameFontDisableSmall")
  -- And how punishments work, as in force now (SPEC decision 69; the same text as under Punishments).
  if not page.editing and Hall.PunishmentRules then Hall.PunishmentRules(f, gg) end
  local foot = {}
  if c and Co.Accepted(gg, P:Of(me, gg)) then
    f:Text("mine", L.CO_YOU_ACCEPTED, "GameFontDisableSmall")
  elseif c then
    f:Text("acceptNote", L.CO_ACCEPT_NOTE, "GameFontDisableSmall")
    foot[#foot + 1] = { L.CO_ACCEPT, function() Co.Accept() end, next = true }
  end
  if D:InCharge(me) then
    foot[#foot + 1] = { c and L.CO_EDIT_CHARTER or L.CO_WRITE_CHARTER, function() page.editing = true; Hall:Refresh() end }
  end
  return foot
end

---------------------------------------------------------------------------
-- Votes: polls and rule changes
---------------------------------------------------------------------------
-- A vote on the guild's rules: a rule change or a change of setup (SPEC decision 70), with who votes when not
-- everyone (the council, the officers), and the Guild Master's veto in a Warcouncil.
local function motionBlock(f, key, s, now)
  local mo = s.mo
  local title = mo.kind == "setup" and L.CO_SETUP_LINE:format(setupWords(mo.setup, mo))
    or L.CO_RULE_LINE:format(ruleName(mo.r), Co.Describe(mo.r, mo.v))
  f:Text(key .. "t", title, "GameFontNormal")
  f:Text(key .. "w", L.CO_RULE_WHY:format(name(mo.a), mo.why or ""), "GameFontDisableSmall")
  local gg = g()
  local open = s.phase == "motion" or s.phase == "vote"
  if mo.vt and s.phase == "motion" then
    local names = {}
    for i, n in ipairs(mo.vt) do if i <= 8 then names[#names + 1] = name(n) end end
    if #mo.vt > 8 then names[#names + 1] = L.CO_AND_MORE:format(#mo.vt - 8) end
    f:Text(key .. "o", L.CO_VOTERS_SOME:format(table.concat(names, ", ")), "GameFontDisableSmall")
  end
  local mayVote = Co.Votes(gg, mo)
  if s.phase == "motion" then
    local mine, seconded = P:Of(ns.Self(), gg), false
    for _, n in ipairs(s.seconds) do if P:Of(n, gg) == mine then seconded = true end end
    local label = L.CO_SECONDS_OF:format(#s.seconds, s.need, left(s.deadline - now))
    if mayVote and mine ~= P:Of(mo.a, gg) and not seconded then
      f:Line(key .. "s", label, L.CO_SECOND, function() Co.Second(s.id) end)
    else
      f:Text(key .. "s", label)
    end
  elseif s.phase == "vote" then
    -- A ballot card (the 1 Nov review): yes and no as bars, the time left, and who has voted (the council or the
    -- officers as crests, greyed until they vote; else how many members have).
    f:Bars(key .. "v", { { label = L.CO_YES, v = s.yes, text = tostring(s.yes), me = s.mine == true },
      { label = L.CO_NO, v = s.no, text = tostring(s.no), me = s.mine == false } }, UI.ICON.ballot)
    f:Pair(key .. "l", L.CO_VOTE_LEFT, left(s.ve - now))
    if mo.vt then
      local voted, tiles = Co.VotedKeys(gg, s), {}
      local seen = {}
      for _, n in ipairs(mo.vt) do
        local k = P:Of(n, gg)
        if not seen[k] and #tiles < 9 then
          seen[k] = true
          tiles[#tiles + 1] = { name = n, dim = not voted[k], sub = voted[k] and L.CO_TILE_VOTED or L.CO_TILE_WAITS,
            me = k == P:Of(ns.Self(), gg) }
        end
      end
      f:Tiles(key .. "t", tiles, 3)
    else
      f:Pair(key .. "c", L.CO_CAST, L.CO_CAST_OF:format(s.cast, mo.m, pct(s.cast, mo.m)))
    end
    if mayVote then
      local note = s.mine ~= nil and L.CO_YOU_VOTED:format(s.mine and L.CO_YES or L.CO_NO) or nil
      f:Buttons(key .. "b", { { L.CO_YES, function() Co.VoteMotion(s.id, true) end, next = s.mine == nil },
        { L.CO_NO, function() Co.VoteMotion(s.id, false) end, next = s.mine == nil } }, note)
    else
      f:Text(key .. "b", L.CO_NOT_YOUR_VOTE, "GameFontDisableSmall")
    end
  else
    local word = mo.kind == "setup" and L["CO_SETUP_" .. s.phase:upper()] or L["CO_RULE_" .. s.phase:upper()]
    f:Text(key .. "r", word or "", "GameFontDisableSmall")
  end
  -- The Guild Master leads a Warcouncil and may veto its votes.
  if open and D:InCharge() and ns.Rules.Setup(gg) == "warcouncil" then
    f:Buttons(key .. "x", { { L.CO_VETO, function()
      Hall:Confirm(L.CO_VETO_ASK, L.CO_VETO, function() Co.Veto(s.id) end)
    end } })
  end
end

-- Does a rule change wait for this player: a vote not cast yet, or a second they may give?
local function waitsFor(s)
  local gg = g()
  if not Co.Votes(gg, s.mo) then return false end
  if s.phase == "vote" then return s.mine == nil end
  if s.phase ~= "motion" then return false end
  local me = P:Of(ns.Self(), gg)
  if me == P:Of(s.mo.a, gg) then return false end
  for _, n in ipairs(s.seconds) do if P:Of(n, gg) == me then return false end end
  return true
end

local function votes(f, page)
  local gg, now = g(), Co.Now()
  local shown = 0
  -- Rule changes the guild is voting on, and those it decided lately; the ones that wait for you come first, above
  -- the polls, so their buttons are in sight (SPEC decision 52).
  local list, rules = {}, 0
  for _, s in ipairs(Co.Motions(gg, now, "rule")) do
    if #list < 3 and (s.phase == "motion" or s.phase == "vote" or now - (s.ve or s.mo.t) < 7 * 86400) then
      list[#list + 1] = s
    end
  end
  for _, s in ipairs(list) do
    if waitsFor(s) then
      rules = rules + 1
      if rules == 1 then f:Strip("rh", L.CO_RULE_CHANGES) end
      motionBlock(f, "rc" .. rules, s, now)
    end
  end
  local first = rules
  for i, s in ipairs(Co.Polls(gg, now)) do
    if i > 4 then break end
    shown = shown + 1
    local po = s.po
    local tags = {}
    if po.sec then tags[#tags + 1] = L.CO_SECRET end
    if po.wt then tags[#tags + 1] = L.CO_WEIGHTED end
    f:Strip("q" .. i, L.CO_POLL_HEAD:format(po.q), #tags > 0 and table.concat(tags, ", ") or nil)
    for j, row in ipairs(s.rows) do
      f:Pair("r" .. i .. "." .. j, L.CO_CHOICE:format(j, row.label), tostring(row.n), false)
      -- Who chose it, on a line of its own under the choice (not secret polls).
      if not po.sec and #row.who > 0 then
        local out = {}
        for x, n in ipairs(row.who) do if x <= 6 then out[#out + 1] = name(n) end end
        if #row.who > 6 then out[#out + 1] = L.CO_AND_MORE:format(#row.who - 6) end
        f:Text("w" .. i .. "." .. j, "|cff9d9d9d" .. table.concat(out, ", ") .. "|r", "GameFontDisableSmall")
      end
    end
    if s.open then
      local buttons = {}
      for j in ipairs(s.rows) do
        buttons[#buttons + 1] = { L.CO_VOTE_N:format(j), function() Co.Vote(s.id, j) end, 60, next = s.mine == nil }
      end
      f:Buttons("b" .. i, buttons, s.mine and L.CO_YOU_VOTED:format(s.rows[s.mine].label) or left(s.ends - now))
    else
      f:Text("c" .. i, L.CO_POLL_CLOSED:format(s.cast), "GameFontDisableSmall")
    end
  end
  for _, s in ipairs(list) do
    if not waitsFor(s) then
      rules = rules + 1
      if rules == first + 1 then f:Strip(first == 0 and "rh" or "rh2", L.CO_RULE_CHANGES) end
      motionBlock(f, "rc" .. rules, s, now)
    end
  end
  if shown == 0 and rules == 0 then
    f:Empty("none", L.CO_NO_POLLS, D:Can("poll") and L.CO_NO_POLLS_DO:format(UI.Key(L.CO_NEW_POLL_DOTS)) or nil)
  end
  f:Text("whisper", L.CO_WHISPER_HINT, "GameFontDisableSmall")
  local foot = {}
  if D:Can("poll") then foot[#foot + 1] = { L.CO_NEW_POLL_DOTS, function() page.View({ kind = "poll" }) end } end
  if Co.MayPropose(gg, ns.Self(), "rule") or Co.MayPropose(gg, ns.Self(), "setup") then
    foot[#foot + 1] = { L.CO_PROPOSE_DOTS, function() page.View({ kind = "rule" }) end }
  end
  return foot
end

local function pollForm(f, page)
  if not D:Can("poll") then return nil end
  f:Strip("title", L.CO_NEW_POLL)
  page.qBox = f:Field("q", L.CO_QUESTION, f.width - 12)
  page.qBox:SetMaxLetters(Co.Q_MAX)
  page.chBox = f:Field("ch", L.CO_CHOICES, f.width - 12)
  page.chBox:SetMaxLetters(Co.CHOICES_MAX * (Co.CHOICE_MAX + 1))
  page.daysBox = f:Field("days", L.CO_DAYS, 40)
  local sec = f:piece("sec", function() return UI.Check(f.card, L.CO_SECRET_LABEL, function() return page.pollSecret end, function(on) page.pollSecret = on end) end, "secret")
  sec:SetPoint("TOPLEFT", f.pad - 4, f.y)
  f:Space(22)
  local wt = f:piece("wt", function() return UI.Check(f.card, L.CO_WEIGHTED_LABEL, function() return page.pollWeighted end, function(on) page.pollWeighted = on end) end, "weighted")
  wt:SetPoint("TOPLEFT", f.pad - 4, f.y)
  f:Space(24)
  return { { L.CO_OPEN_POLL, function()
    local q = text(page.qBox)
    if q == "" then return ns:Print(L.CO_NEED_QUESTION, true) end
    local ch
    local typed = text(page.chBox)
    if typed ~= "" then
      ch = {}
      for c in typed:gmatch("[^,]+") do
        c = strtrim(c)
        if c ~= "" then ch[#ch + 1] = c end
      end
      if #ch < 2 or #ch > Co.CHOICES_MAX then return ns:Print(L.CO_BAD_CHOICES:format(Co.CHOICES_MAX), true) end
    end
    local days = num(page.daysBox) or 3
    if days < 1 or days > 7 or days ~= math.floor(days) then return ns:Print(L.CO_BAD_DAYS, true) end
    if Co.OpenPoll(q, ch, page.pollSecret, page.pollWeighted, days) then
      page.qBox:SetText(""); page.chBox:SetText(""); page.daysBox:SetText("")
      page.View(nil)
    end
  end }, { L.CANCEL, function() page.View(nil) end } }
end

-- A change of setup put to the vote (SPEC decision 70): the setup, its option, what it means and the reason.
local function setupForm(f, page)
  local Ru = ns.Rules
  local cur, opt = Ru.Setup(g())
  page.setupTo = page.setupTo or (cur == "democracy" and "monarchy" or "democracy")
  page.setupOpt = page.setupOpt or { sits = opt.sits or "officers", judge = opt.judge or "ranks", elect = opt.elect == true }
  local id, o = page.setupTo, page.setupOpt
  local list = {}
  for _, x in ipairs(Ru.SETUPS) do list[#list + 1] = { x, L["SETUP_" .. x:upper()] } end
  f:Dropdown("sto", L.CO_SETUP_TO, list, id, function(v) page.setupTo = v Hall:Refresh() end)
  if id == "democracy" then
    f:Dropdown("sopt", L.CO_SETUP_OPTION, { { false, L.SETUP_OPT_KEEPS }, { true, L.SETUP_OPT_ELECT } }, o.elect == true,
      function(v) o.elect = v Hall:Refresh() end)
  elseif id == "warcouncil" then
    f:Dropdown("sopt", L.CO_SETUP_OPTION, { { "officers", L.SETUP_OPT_OFFICERS },
      { "elders", L.SETUP_OPT_ELDERS:format(Ru.ELDERS) } }, o.sits, function(v) o.sits = v Hall:Refresh() end)
  elseif id == "dictatorship" then
    f:Dropdown("sopt", L.CO_SETUP_OPTION, { { "ranks", L.SETUP_OPT_RANKS }, { "crown", L.SETUP_OPT_CROWN } }, o.judge,
      function(v) o.judge = v Hall:Refresh() end)
  end
  for i, line in ipairs(Ru.SetupLines(id, o)) do f:Text("sl" .. i, "- " .. line, "GameFontDisableSmall") end
  page.ruleWhy = f:Field("rwhy", L.CO_REASON, f.width - 12)
  page.ruleWhy:SetMaxLetters(Co.WHY_MAX)
  return { { L.CO_PROPOSE_GO, function()
    local why = text(page.ruleWhy)
    if why == "" then return ns:Print(L.CO_NEED_REASON, true) end
    if Co.ProposeSetup(id, o, why) then page.ruleWhy:SetText("") page.View(nil)
    else ns:Print(L.SET_SETUP_VOTE_BUSY, true) end
  end }, { L.CANCEL, function() page.View(nil) end } }
end

-- A rule change: pick the rule, then its new value (or the guild's setup, where it goes to the vote).
local function ruleForm(f, page)
  local gg, me = g(), ns.Self()
  local rulesOk, setupOk = Co.MayPropose(gg, me, "rule"), Co.MayPropose(gg, me, "setup")
  if not rulesOk and not setupOk then return nil end
  f:Strip("title", L.CO_PROPOSE)
  local list = {}
  if setupOk then list[#list + 1] = "setup" end
  if rulesOk then
    for _, r in ipairs(Co.PERM_RULES) do list[#list + 1] = r end
    for _, k in ipairs(D.NUMBER_KEYS) do list[#list + 1] = k end
    list[#list + 1] = "sentence"
    -- The punishment switches, where the guild has punishments.
    local setup = ns.Rules.Setup(gg)
    if setup and setup ~= "free" then
      for _, r in ipairs(Co.PUN_RULES) do list[#list + 1] = r end
    end
  end
  local known = false
  for _, x in ipairs(list) do if x == page.rule then known = true end end
  if not known then page.rule = list[1] end
  local r = page.rule
  local rules = {}
  for i, x in ipairs(list) do rules[i] = { x, ruleName(x) } end
  f:Dropdown("rpick", L.CO_RULE_PICK, rules, r, function(v)
    page.rule, page.ruleValue = v, nil
    Hall:Refresh()
  end)
  if r == "setup" then return setupForm(f, page) end
  local kind = Co.RULES[r]
  f:Text("rnow", L.CO_RULE_NOW:format(Co.Describe(r, Co.Current(g(), r))), "GameFontDisableSmall")
  local value
  if kind == "ranks" then
    -- From the Guild Master only down to the lowest rank, one step a click.
    local ranks = R:Ranks()
    page.ruleValue = page.ruleValue or 0
    local function upTo(n)
      local v = {}
      for i = 1, n do v[#v + 1] = i end
      return v
    end
    value = upTo(page.ruleValue)
    local choices = {}
    for n = 0, #ranks do choices[#choices + 1] = { n, Co.Describe(r, upTo(n)) } end
    f:Dropdown("rval", L.CO_RULE_TO, choices, page.ruleValue, function(v) page.ruleValue = v; Hall:Refresh() end)
  elseif kind == "flag" then
    if page.ruleValue == nil then page.ruleValue = not Co.Current(g(), r) end
    value = page.ruleValue
    f:Dropdown("rval", L.CO_RULE_TO, { { true, Co.Describe(r, true) }, { false, Co.Describe(r, false) } }, value,
      function(v) page.ruleValue = v; Hall:Refresh() end)
  else
    local x = D.NUMBERS[r]
    page.ruleBox = f:Field("rnum", L.CO_RULE_NUMBER:format(x[2], x[3]), 50)
  end
  page.ruleWhy = f:Field("rwhy", L.CO_REASON, f.width - 12)
  page.ruleWhy:SetMaxLetters(Co.WHY_MAX)
  return { { L.CO_PROPOSE_GO, function()
    local why = text(page.ruleWhy)
    if why == "" then return ns:Print(L.CO_NEED_REASON, true) end
    local v = value
    if kind == "number" then
      local x = D.NUMBERS[r]
      v = num(page.ruleBox)
      if not v or v < x[2] or v > x[3] or v ~= math.floor(v) then return ns:Print(L.CO_BAD_NUMBER:format(x[2], x[3]), true) end
    end
    if Co.Propose(r, v, why) then page.ruleWhy:SetText("") page.View(nil) end
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- The court
---------------------------------------------------------------------------
local function pun(p) return L["AN_PUN_" .. p:upper()] or p end

local function court(f, page)
  local gg, me = g(), ns.Self()
  local list = Ct.Cases(gg)
  if #list == 0 then
    f:Empty("none", L.CO_NO_CASES, D:Can("court") and L.CO_NO_CASES_DO:format(UI.Key(L.CO_CHARGE_DOTS)) or L.CO_NO_CASES_JURY)
  end
  local mine = P:Of(me, gg)
  for i, s in ipairs(list) do
    if i > 3 then break end
    local cs = s.cs
    local key = "c" .. i
    local sentence = pun(cs.pun) .. ((cs.len and St.TIMED[cs.pun]) and L.AN_MINUTES:format(cs.len) or "")
    f:Row(key .. "h", { icon = UI.ICON.scales, name = L.CO_CASE:format(UI.Who(cs.to)), sub = cs.why, value = sentence,
      dim = cs.closed == true })
    f:Text(key .. "w", L.CO_CHARGE:format(cs.why, name(cs.h)))
    f:Text(key .. "d", s.defence and L.CO_DEFENCE:format(s.defence) or L.CO_NO_DEFENCE, "GameFontDisableSmall")
    f:Pair(key .. "j", L.CO_JURY, L.CO_JURY_N:format(#s.jurors, s.guilty, s.innocent))
    if not cs.closed then
      local buttons = {}
      if s.key == mine then
        page["def" .. i] = f:Field(key .. "def", L.CO_YOUR_DEFENCE, f.width - 90)
        page["def" .. i]:SetMaxLetters(Ct.DEF_MAX)
        buttons[#buttons + 1] = { L.CO_POST, function()
          local t = text(page["def" .. i])
          if t ~= "" and Ct.Defend(s.id, t) then page["def" .. i]:SetText("") end
        end, next = not s.defence }
      elseif cs.h ~= me and P:Of(cs.h, gg) ~= mine then
        buttons[#buttons + 1] = { s.onJury and L.CO_LEAVE_JURY or L.CO_JOIN_JURY, function() Ct.Jury(s.id, not s.onJury) end }
        if s.onJury then
          buttons[#buttons + 1] = { L.CO_GUILTY, function() Ct.Vote(s.id, true) end, next = s.mine == nil }
          buttons[#buttons + 1] = { L.CO_NOT_GUILTY, function() Ct.Vote(s.id, false) end, next = s.mine == nil }
        end
      end
      if cs.h == me then
        buttons[#buttons + 1] = { L.CO_CLOSE_CASE, function()
          Hall:Confirm(L.CO_CLOSE_ASK:format(#s.jurors, s.guilty, s.innocent), L.CO_CLOSE_CASE, function() Ct.Close(s.id) end)
        end }
      end
      local note = s.mine ~= nil and (s.mine and L.CO_YOU_GUILTY or L.CO_YOU_NOT_GUILTY) or nil
      if #buttons > 0 then f:Buttons(key .. "b", buttons, note) end
    else
      f:Text(key .. "v", L["CO_VERDICT_" .. s.verdict:upper()], "GameFontNormal")
      -- Who voted what, now the verdict is in (SPEC decision 74).
      local said = { guilty = {}, innocent = {} }
      for _, juror in ipairs(s.jurors) do
        local call = s.calls and s.calls[juror]
        if call then said[call][#said[call] + 1] = ns.Short(juror) end
      end
      if #said.guilty > 0 then f:Text(key .. "cg", L.CO_CALLED_GUILTY:format(table.concat(said.guilty, ", ")), "GameFontDisableSmall") end
      if #said.innocent > 0 then
        f:Text(key .. "ci", L.CO_CALLED_NOT:format(table.concat(said.innocent, ", ")), "GameFontDisableSmall")
      end
      if s.verdict == "guilty" then
        if s.sentence then
          f:Text(key .. "x", L.CO_SENTENCED, "GameFontDisableSmall")
        elseif not St.Punishable(gg, s.key) then
          f:Text(key .. "x", L.CO_NOT_PUNISHABLE, "GameFontDisableSmall")
        elseif Ct.MaySentence(gg, s) then
          f:Buttons(key .. "x", { { L.CO_GIVE_SENTENCE, function() Ct.Sentence(s.id) end } })
        else
          f:Text(key .. "x", L.CO_AWAITS_SENTENCE, "GameFontDisableSmall")
        end
      end
    end
  end
  f:Text("v", D:CourtSentences() and L.CO_COURT_SENTENCES or L.CO_COURT_PROPOSES, "GameFontDisableSmall")
  f:Text("j", L.CO_JURY_RULE:format(D:Number("jury"), Ct.JURY_MIN), "GameFontDisableSmall")
  if D:Can("court") then return { { L.CO_CHARGE_DOTS, function() page.View({ kind = "charge" }) end } } end
  return {}
end

local function chargeForm(f, page)
  if not D:Can("court") then return nil end
  f:Strip("title", L.CO_CHARGE_HEAD)
  page.accBox = f:Field("acc", L.CO_ACCUSED, f.width - 12)
  page.chargeBox = f:Field("chg", L.CO_CHARGE_LABEL, f.width - 12)
  page.chargeBox:SetMaxLetters(Ct.WHY_MAX)
  page.courtPun = page.courtPun or Ct.PUNS[1]
  local puns = {}
  for i, p in ipairs(Ct.PUNS) do puns[i] = { p, pun(p) } end
  f:Dropdown("pun", L.CO_SENTENCE_IF, puns, page.courtPun, function(v) page.courtPun = v; Hall:Refresh() end)
  f:Text("v", D:CourtSentences() and L.CO_COURT_SENTENCES or L.CO_COURT_PROPOSES, "GameFontDisableSmall")
  return { { L.CO_BRING_CHARGE, function()
    local who = member(text(page.accBox))
    if not who then return ns:Print(L.CO_NO_SUCH_MEMBER, true) end
    if not P:HasAddon(P:Of(who)) then return ns:Print(L.CO_NO_ADDON:format(ns.Display(who)), true) end
    local why = text(page.chargeBox)
    if why == "" then return ns:Print(L.CO_NEED_REASON, true) end
    if Ct.Charge(who, why, page.courtPun) then page.accBox:SetText(""); page.chargeBox:SetText(""); page.View(nil) end
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- Strikes
---------------------------------------------------------------------------
local function strikes(f, page)
  local gg, me, now = g(), ns.Self(), Co.Now()
  local list = Co.Strikes(gg, now)
  local sees, mine = Co.SeesStrikes(me, gg), P:Of(me, gg)
  local shown = 0
  for _, e in ipairs(list) do
    if e.st ~= "over" and e.st ~= "taken" and (sees or e.key == mine) and shown < 12 then
      shown = shown + 1
      local sub = (e.st == "ok" and L.CO_CONFIRMED_BY:format(name(e.ok)) or L.CO_NEEDS_SECOND) .. " · " .. L.CO_EXPIRES:format(left(e.ends - now))
      f:Row("s" .. shown, { icon = UI.ICON.flag, name = UI.Who(e.to), sub = e.why, value = name(e.by), vsub = L.CO_EXPIRES:format(left(e.ends - now)),
        dim = e.st == "wait", tip = { L.CO_STRIKE_LINE:format(name(e.to), e.why, name(e.by)), sub } })
      local buttons = {}
      if e.st == "wait" and D:Can("confirm") and e.by ~= me and e.key ~= mine then
        buttons[#buttons + 1] = { L.CO_CONFIRM, function() Co.Confirm(e.id) end }
      end
      -- (A Monarchy's Guild Master may take a strike back: SPEC decision 70.)
      if D:InCharge() and ns.Rules.Setup(gg) == "monarchy" then
        buttons[#buttons + 1] = { L.CO_TAKE_BACK, function()
          Hall:Confirm(L.CO_TAKE_BACK_ASK:format(name(e.to)), L.CO_TAKE_BACK, function() Co.TakeBack(e.id) end)
        end }
      end
      if #buttons > 0 then f:Buttons("sb" .. shown, buttons) end
    end
  end
  if shown == 0 then
    f:Empty("none", L.CO_NO_STRIKES, D:Can("strike") and L.CO_NO_STRIKES_GIVE:format(UI.Key(L.CO_STRIKE_DOTS))
      or L.CO_NO_STRIKES_ABOUT)
  end
  f:Text("ladder", L.CO_LADDER:format(D:Settings().ladder or ""), "GameFontDisableSmall")
  f:Text("note", L.CO_STRIKES_NOTE, "GameFontDisableSmall")
  if D:Can("strike") then return { { L.CO_STRIKE_DOTS, function() page.View({ kind = "strike" }) end } } end
  return {}
end

local function strikeForm(f, page)
  if not D:Can("strike") then return nil end
  f:Strip("title", L.CO_GIVE_STRIKE)
  page.stWho = f:Field("who", L.CO_MEMBER, f.width - 12)
  page.stWhy = f:Field("why", L.CO_REASON, f.width - 12)
  page.stWhy:SetMaxLetters(Co.WHY_MAX)
  page.stDays = f:Field("days", L.CO_STRIKE_DAYS:format(Co.STRIKE_DAYS), 40)
  f:Text("note", L.CO_STRIKES_NOTE, "GameFontDisableSmall")
  return { { L.CO_GIVE, function()
    local who = member(text(page.stWho))
    if not who then return ns:Print(L.CO_NO_SUCH_MEMBER, true) end
    if not P:HasAddon(P:Of(who)) then return ns:Print(L.CO_NO_ADDON:format(ns.Display(who)), true) end
    local why = text(page.stWhy)
    if why == "" then return ns:Print(L.CO_NEED_REASON, true) end
    local days = num(page.stDays) or Co.STRIKE_DAYS
    if days < 1 or days > Co.STRIKE_DAYS_MAX or days ~= math.floor(days) then
      return ns:Print(L.CO_BAD_STRIKE_DAYS:format(Co.STRIKE_DAYS_MAX), true)
    end
    if Co.Strike(who, why, days) then page.stWho:SetText(""); page.stWhy:SetText(""); page.stDays:SetText(""); page.View(nil) end
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- The Guild Master's election (SPEC decision 70): a Democracy's, each month. Members stand on the 1st to the 4th, every
-- member votes on the 5th to the 7th, and the winner leads after the hand-over (the same secure button).
---------------------------------------------------------------------------
local function elect(f, page)
  local gg, me, now = g(), ns.Self(), Co.Now()
  local gm = Co.GM()
  f:Row("now", { icon = UI.ICON.crown, name = gm and UI.Who(gm) or L.CO_NO_GM, sub = L.GUILD_MASTER })
  local e = Co.Election(gg, Co.Month(now), now)
  local said = L["CO_ELECT_" .. e.phase:upper()]
  f:Text("ph", said:format(UI.Who(e.winner or gm or "")), "GameFontNormal")
  -- This month's ballot, as it stands or as it ended.
  local m = Co.Month(now)
  f:Strip("ballot", L.CO_ELECT_BALLOT:format(L["TS_MONTH_" .. tonumber(m:sub(6, 7))]))
  local mine = P:Of(me, gg)
  local standing = false
  for i, c in ipairs(e.cands) do
    if P:Of(c.name, gg) == mine then standing = true end
    local label = L.CO_CANDIDATE:format(UI.Who(c.name), c.line)
    local tally = e.phase ~= "stand" and L.CO_VOTES_N:format(c.n) or nil
    if tally and e.winner == c.name and e.phase ~= "vote" then tally = L.CO_ELECT_WON_TAG:format(tally) end
    if e.phase == "vote" then
      f:Line("c" .. i, label, e.mine == c.name and L.CO_VOTED or L.CO_VOTE, function() Co.VoteElect(c.name) end, tally,
        e.mine == nil)
    else
      f:Line("c" .. i, label, nil, nil, tally)
    end
  end
  -- Between elections: when the next one opens.
  if e.phase ~= "stand" and e.phase ~= "vote" then
    local mo = tonumber(Co.Month(now):sub(6, 7)) % 12 + 1
    f:Pair("next", L.CO_ELECT_NEXT, L.CO_ELECT_NEXT_DAY:format(L["TS_MONTH_" .. mo]))
  end
  local foot = {}
  if e.phase == "stand" and not standing and Co.MayStand(me) then
    page.campaign = f:Field("line", L.CO_CAMPAIGN, f.width - 12)
    page.campaign:SetMaxLetters(Co.CAMPAIGN_MAX)
    foot[#foot + 1] = { L.CO_STAND, function()
      local line = text(page.campaign)
      if line == "" then return ns:Print(L.CO_NEED_CAMPAIGN, true) end
      if Co.Stand(line) then page.campaign:SetText("") end
    end }
  end
  -- A winner who waits for the hand-over (this month's, or last month's).
  local showing = false
  for _, s in ipairs(Co.Elections(gg, now)) do
    if s.phase == "handover" and not showing then
      f:Text("won", L.CO_ELECT_WON:format(UI.Who(s.winner)), "GameFontNormal")
      f:Text("locked", L.CO_LOCKED:format(UI.Who(gm or s.gm), UI.Who(s.winner)))
      if R:Rank(me) == 0 then
        f:Text("only", L.CO_ONLY_YOU, "GameFontDisableSmall")
        local spot = f:piece("hand", function() local fr = CreateFrame("Frame", nil, f.card) fr:SetSize(200, 22) return fr end, "hand")
        spot:SetPoint("TOPLEFT", f.pad, f.y)
        f:Space(28)
        showing = showHand(spot, s.winner)
        if not showing then f:Text("combat", L.CO_HAND_COMBAT, "GameFontDisableSmall") end
        showing = true
      else
        f:Text("wait", L.CO_WAIT_HAND:format(name(gm or s.gm)), "GameFontDisableSmall")
      end
    end
  end
  if not showing then hideHand() end
  f:Text("how", L.CO_ELECT_HOW, "GameFontDisableSmall")
  f:Text("whisper", L.CO_WHISPER_HINT, "GameFontDisableSmall")
  return foot
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local PARTS = { impeach = leadership, charter = charter, votes = votes, court = court, strikes = strikes, elect = elect }
local VIEWS = { how = leadHow, impeach = startForm("lead"), mak = startForm("mak"), poll = pollForm, rule = ruleForm, charge = chargeForm, strike = strikeForm }

-- Where each part stands, in a few words, for its row on the left.
local function state(id, gg, now)
  if id == "impeach" then
    -- What runs, and how long is left for its step: "Mak'gora · 6 days left" (SPEC decision 51).
    local s = Co.Lead(gg, now)
    if not s then return L.CO_STATE_QUIET, false end
    local kind = L["CO_KIND_" .. s.mo.kind:upper()]
    if s.deadline and s.deadline > now then return L.FEAT_LEFT:format(kind, ns.TimeLeft(s.deadline - now)), true end
    return L.FEAT_KIND_STEP:format(kind, stepWord(s)), true
  elseif id == "charter" then
    local c, yes, total = Co.Charter(gg)
    return c and L.FEAT_ACCEPTED:format(yes, total) or L.FEAT_NO_RULES, false
  elseif id == "votes" then
    local n = 0
    for _, s in ipairs(Co.Polls(gg, now)) do if s.open then n = n + 1 end end
    for _, s in ipairs(Co.Motions(gg, now, "rule")) do if s.phase == "motion" or s.phase == "vote" then n = n + 1 end end
    return n > 0 and L.CO_STATE_OPEN:format(n) or L.CO_STATE_QUIET, n > 0
  elseif id == "court" then
    local n = 0
    for _, s in ipairs(Ct.Cases(gg)) do if not s.cs.closed then n = n + 1 end end
    return n > 0 and L.CO_STATE_OPEN:format(n) or L.CO_STATE_QUIET, n > 0
  elseif id == "strikes" then
    local n = 0
    for _, e in ipairs(Co.Strikes(gg, now)) do if e.st ~= "over" and e.st ~= "taken" then n = n + 1 end end
    return n > 0 and L.CO_STATE_STRIKES:format(n) or L.CO_STATE_QUIET, false
  end
  -- The election.
  for _, s in ipairs(Co.Elections(gg, now)) do
    if s.phase == "handover" then return L.FEAT_KIND_STEP:format(L.CO_KIND_ELECT, L.CO_STEP_HANDOVER), true end
  end
  local e = Co.Election(gg, Co.Month(now), now)
  if e.phase == "stand" then return L.CO_STATE_STAND, true end
  if e.phase == "vote" then return L.CO_STATE_VOTING, true end
  local y, mo = Co.Month(now):match("^(%d+)%-(%d+)$")
  y, mo = tonumber(y), tonumber(mo) + 1
  if mo > 12 then y, mo = y + 1, 1 end
  local opens = Co.UTC(("%04d-%02d"):format(y, mo), 1)
  return L.CO_STATE_OPENS:format(ns.TimeLeft(opens - now)), false
end

---------------------------------------------------------------------------
-- What waits for you here (SPEC decision 47): votes you have not cast, answers only you can give; and how many in
-- each part.
---------------------------------------------------------------------------
local function waiting()
  local gg, me, now = g(), ns.Self(), Co.Now()
  local key, out, by = P:Of(me, gg), {}, {}
  local function add(line, part)
    if not ALWAYS[part] and not D:On("council:" .. part) then return end
    out[#out + 1] = line; by[part] = (by[part] or 0) + 1
  end
  for _, s in ipairs(Co.Polls(gg, now)) do if s.open and s.mine == nil then add(L.TODO_POLL:format(s.po.q), "votes") end end
  for _, s in ipairs(Co.Motions(gg, now)) do
    local mo = s.mo
    if (s.kind == "rule" or s.kind == "setup") and s.phase == "vote" and s.mine == nil and Co.Votes(gg, mo) then
      add(s.kind == "setup" and L.TODO_SETUP or L.TODO_RULE, "votes")
    elseif s.kind == "lead" and s.phase == "vote" and s.mine == nil then
      for _, n in ipairs(s.voters or {}) do if P:Of(n, gg) == key then add(L.TODO_IMPEACH, "impeach") break end end
    elseif s.kind == "mak" and s.phase == "challenge" and R:Rank(me) == 0 and key == P:Of(mo.gm, gg) then
      add(L.TODO_MAK_ANSWER:format(name(mo.a)), "impeach")
    elseif s.kind == "mak" and s.phase == "vote" and s.mine == nil and key ~= P:Of(mo.gm, gg) and key ~= P:Of(mo.a, gg) then
      add(L.TODO_MAK_VOTE, "impeach")
    elseif s.kind == "mak" and s.phase == "declined" and key == P:Of(mo.a, gg) then
      add(L.TODO_REBEL_DECLARE, "impeach")
    elseif s.kind == "mak" and s.phase == "rebellion" and not s.mine and key ~= P:Of(mo.gm, gg) then
      add(L.TODO_REBEL_SIGN:format(name(mo.a)), "impeach")
    elseif s.phase == "handover" and R:Rank(me) == 0 then
      add(L.TODO_HAND:format(name(s.winner)), "impeach")
    end
  end
  if Co.Charter(gg) and not Co.Accepted(gg, key) then add(L.TODO_CHARTER, "charter") end
  for _, s in ipairs(Ct.Cases(gg)) do
    if not s.cs.closed then
      if s.key == key and not s.defence then add(L.TODO_DEFENCE, "court")
      elseif s.onJury and s.mine == nil then add(L.TODO_JURY:format(name(s.cs.to)), "court") end
    end
  end
  if Co.Elects(gg) then
    local e = Co.Election(gg, Co.Month(now), now)
    if e.phase == "vote" and e.mine == nil then add(L.TODO_ELECT, "elect") end
    for _, s in ipairs(Co.Elections(gg, now)) do
      if s.phase == "handover" and R:Rank(me) == 0 then add(L.TODO_HAND:format(name(s.winner)), "elect") end
    end
  end
  return out, by
end

-- Each feature's state under its name on the left, and what waits for you there as its red number.
local STATUS, COUNT, TABS = {}, {}, {}
for i, id in ipairs(SECTIONS) do
  STATUS[id] = function() return (state(id, g(), Co.Now())) end
  COUNT[id] = function()
    local _, by = waiting()
    return by[id] or 0
  end
  TABS[i] = { id, L["CO_SEC_" .. id:upper()], icon = UI.ICON[ICONS[id]], always = ALWAYS[id] }
  -- (The election shows only where the guild elects its Guild Master.)
  if id == "elect" then TABS[i].on = function() return g() ~= nil and Co.Elects(g()) end end
end

---------------------------------------------------------------------------
-- The side window (UI/Side.lua): the leadership motion (the officers' votes, the Mak'gora, the crown's cup) or the
-- newest poll, as a picture
---------------------------------------------------------------------------
local LEAD_SHOWN = 7 * 86400
local function yesNo(f, s)
  f:Bars("yesno", { { label = L.CO_YES, v = s.yes, text = pct(s.yes, s.cast) .. "%" },
    { label = L.CO_NO, v = s.no, text = pct(s.no, s.cast) .. "%" } }, UI.ICON.ballot)
  f:Pair("cast", L.CO_CAST, L.CO_CAST_OF:format(s.cast, s.mo.m, pct(s.cast, s.mo.m)))
end

local function leadPicture(f, s, now)
  local mo = s.mo
  -- Its scene first (UI/Scenes.lua, SPEC decision 60): the Mak'gora's two, the impeachment's winner, the cup's.
  if s.cup then ns.Scenes.Cup(f, g(), s.cup, s.id) else ns.Scenes.Lead(f, g(), s) end
  steps(f, "steps", mo, s.phase)
  if mo.kind == "lead" then
    -- A bar for each member the officers named, and one for no.
    f:Strip("vote", L.CO_IMP_TALLY:format(s.yes, s.no, s.need, s.n))
    local bars = {}
    for i, c in ipairs(s.cands or {}) do
      if i <= 5 then bars[i] = { label = UI.Who(c.name), v = c.n, text = tostring(c.n), me = c.name == s.winner } end
    end
    bars[#bars + 1] = { label = L.CO_NO, v = s.no, text = tostring(s.no) }
    f:Bars("cands", bars, UI.ICON.throne)
    if s.phase == "vote" then f:Pair("left", L.CO_VOTE_LEFT, left(s.ve - now)) end
  elseif mo.kind == "mak" then
    f:Tiles("duelists", { { name = mo.a }, { name = mo.gm } }, 2)
    if s.vs and (s.phase == "vote" or s.phase == "failed" or s.forced) then
      f:Strip("vote", L.CO_MAK_FORCE:format(UI.Who(mo.gm), UI.Who(mo.a)))
      yesNo(f, s)
    end
    if s.phase == "challenge" then f:Pair("left", L.CO_MAK_ANSWER_LEFT, left(s.deadline - now))
    elseif s.phase == "duel" then f:Pair("left", L.CO_MAK_FIGHT_LEFT, left(s.deadline - now)) end
  elseif s.cup then
    f:Strip("bracket", L.SIDE_BRACKET)
    if s.cup.st == "open" then
      local list = {}
      for i, n in ipairs(ns.Cup.Joined(s.cup)) do list[i] = { name = n, me = n == ns.Self() } end
      if #list == 0 then f:Empty("nobody", L.SIDE_NOBODY_YET) else f:Tiles("signed", list, 3) end
    elseif not f:Cup("cup", s.cup, ns.Self()) then
      f:Empty("nobracket", L.SIDE_NO_BRACKET)
    end
  end
  if s.phase == "handover" then
    f:Text("won", L["CO_WON_" .. mo.kind:upper()]:format(UI.Who(s.winner)), "GameFontNormal")
    f:Text("locked", L.CO_LOCKED:format(UI.Who(Co.GM() or mo.gm), UI.Who(s.winner)))
  elseif s.phase == "handed" then
    f:Text("done", L.CO_HANDED:format(UI.Who(s.winner)), "GameFontNormal")
  elseif s.phase == "kept" then
    f:Text("done", L.CO_KEPT:format(UI.Who(mo.gm)), "GameFontNormal")
  end
end

local function sidePicture(page)
  local gg, now = g(), Co.Now()
  if not gg then return nil end
  if page.part == "impeach" then
    local s = Co.Lead(gg, now) or Co.Motions(gg, now, "lead")[1]
    if not s or (not Co.Lead(gg, now) and now - s.mo.t > LEAD_SHOWN) then return nil end
    return { key = "lead:" .. s.id, icon = UI.ICON.throne, title = L["CO_KIND_" .. s.mo.kind:upper()],
      sub = L.SIDE_LEAD_SUB:format(UI.Who(s.mo.gm)), draw = function(f) leadPicture(f, s, now) end }
  elseif page.part == "votes" then
    local s = Co.Polls(gg, now)[1]
    if not s or not s.open then return nil end
    return { key = "poll:" .. s.id, icon = UI.ICON.ballot, title = s.po.q, sub = L.SIDE_POLL_SUB:format(s.cast, left(s.ends - now)),
      draw = function(f)
        ns.Scenes.Vote(f, s, s.mine)
        local bars = {}
        for j, row in ipairs(s.rows) do
          bars[j] = { label = L.CO_CHOICE:format(j, row.label), v = row.n, text = tostring(row.n), me = s.mine == j }
        end
        f:Strip("choices", L.SIDE_CHOICES)
        f:Bars("bars", bars, UI.ICON.ballot)
        f:Text("whisper", L.CO_WHISPER_HINT, "GameFontDisableSmall")
      end }
  -- The court's verdict and the rules accepted as their scenes (UI/Scenes.lua, SPEC decision 60).
  elseif page.part == "court" then
    local s = Ct.Cases(gg)[1]
    if not s or s.verdict == "dismissed" or (s.verdict and now - (tonumber(s.cs.closed) or 0) > LEAD_SHOWN) then return nil end
    return { key = "court:" .. s.id, icon = UI.ICON.scales, title = L.CO_SEC_COURT, sub = UI.Who(s.cs.to),
      draw = function(f) ns.Scenes.Court(f, s) end }
  elseif page.part == "charter" then
    if not gg.charter then return nil end
    return { key = "rules", icon = UI.ICON.scroll, title = L.CO_SEC_CHARTER, sub = "",
      draw = function(f)
        ns.Scenes.Rules(f, gg)
        -- Who accepted, in words too: the picture plays beside the panel, and the pane was left bare (shot 117 of
        -- the third check of 1 November).
        local _, yes, all = Co.Charter(gg)
        f:Strip("accepted", L.CO_ACCEPTED, L.CO_ACCEPTED_N:format(yes, all))
        local list, who, me = {}, Co.AcceptedBy(gg), ns.Self()
        for i, n in ipairs(who) do
          if i > CHARTER_TILES then break end
          list[i] = { name = n, me = n == me }
        end
        if #list == 0 then f:Empty("nobody", L.SIDE_NOBODY_YET) else f:Tiles("who", list, 3) end
        if #who > CHARTER_TILES then f:Text("more", L.CO_AND_MORE:format(#who - CHARTER_TILES), "GameFontDisableSmall") end
      end }
  end
  return nil
end

Hall:Register({
  id = "council", label = L.PAGE_COUNCIL, sub = L.PAGE_COUNCIL_SUB,
  side = sidePicture,
  todo = function() return (waiting()) end,
  -- Going on now, for Home: the polls open for votes.
  now = function()
    local out = {}
    for _, s in ipairs(Co.Polls(g(), Co.Now())) do
      if s.open then out[#out + 1] = { icon = UI.ICON.ballot, name = s.q, sub = L.NOW_POLL_SUB, t = s.po.t, pick = "votes" } end
    end
    return out
  end,
  build = function(page)
    Hall:Split(page, { tabs = TABS, parts = PARTS, views = VIEWS, status = STATUS, count = COUNT, save = "councilTab" })
    -- For the self-test's pictures: each view in turn.
    page.viewKinds = { "how", "impeach", "mak", "poll", "rule", "charge", "strike" }
    -- Another feature drops the charter being edited.
    local pick = page.PickQuiet
    page.PickQuiet = function(id)
      if id ~= page.part then page.editing, page.editFilled = nil, nil end
      pick(id)
    end
    page.Pick = function(id) page.PickQuiet(id) Hall:Refresh() end
    -- Another page, or the window closing (our frame hides with it), hides the hand-over button.
    page:HookScript("OnHide", hideHand)
    if Hall.frame then Hall.frame:HookScript("OnHide", hideHand) end
  end,
  refresh = function(page)
    if not g() then return end
    Hall:DrawRight(page)
    -- (Leadership and the Election show the hand-over button themselves.)
    if page.part ~= "impeach" and page.part ~= "elect" then hideHand() end
  end,
})
