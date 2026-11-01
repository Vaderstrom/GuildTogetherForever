-- Flavour: what happens in Guild Together is heard in the game, not only seen on the pages.
--   Guild chat: a line for the big moments (a sentence, the Wheel, the crown, a champion, a winner, BINGO!), so the
--     whole guild hears it, members without the addon too. Each moment is announced once, by the addon of the player
--     whose op it is, and only when fresh (not the catch-up after a login). The Guild Master can switch it off
--     (settings.hush); never from the self-test's pretend guild.
--   Emotes: a click that throws a tomato, sentences, pardons or challenges also does the emote ("/e throws a rotten
--     tomato at ..."). The game wants a hardware event for emotes outdoors, so only ops made by a click have one
--     (made: E:Do, called from the button). Each player can switch them off (/gtf emotes).
--   Alerts: a big line on the screen of everyone with the addon (UI/Alerts.lua), fired here as ALERT. The big ones
--     name a medal (icon, a key of UI.ICON) that drops onto the line, or stamps down (how = "stamp"; SPEC decision 60).
-- Guild chat lines wait in a queue (one every few seconds) and are held during the game's messaging lockdown.
local _, ns = ...
local L, D, Pu = ns.L, ns.GuildData, ns.Purse
local P, St, Cr, Gm = ns.Players, ns.Stocks, ns.Crown, ns.Games
local Tr, Sa = ns.Traitors, ns.Santa
local Co, Ct = ns.Council, ns.Court

local An = { queue = {}, log = {} }
ns.Announce = An

An.FRESH = 60       -- seconds: older ops are catch-up, not news
An.GAP = 3          -- seconds between two guild chat lines
An.STALE = 300      -- a line still waiting after this long is dropped
An.QUEUE_MAX = 10
An.LOG_MAX = 50
An.LEN_MAX = 255    -- the game's limit for a chat line

local function who(name) return ns.Display(name) end
local function pun(p) return L["AN_PUN_" .. (p or ""):upper()] or p end
local function money(amt, purse) return Pu:Format(Pu.Units(amt, purse), purse) end
-- An event by its kind, inside a sentence: "the fishing contest".
local function kindOf(ga) return Gm.KindName(ga.kind):lower() end
local function list(names)
  local out = {}
  for i, n in ipairs(names) do out[i] = who(n) end
  return table.concat(out, ", ")
end

-- Chat lines may not hold the game's escape letter, and are cut to the game's limit.
function An.Clean(text)
  text = (text or ""):gsub("|", "")
  if #text > An.LEN_MAX then text = text:sub(1, An.LEN_MAX - 3) .. "..." end
  return text
end

local function quiet()
  return D.sandbox ~= nil or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
end

local function chat(text, kind)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    C_ChatInfo.SendChatMessage(text, kind)
  else
    SendChatMessage(text, kind)
  end
end

---------------------------------------------------------------------------
-- Guild chat
---------------------------------------------------------------------------
function An:Flush()
  self.timer = nil
  local now = GetTime()
  while self.queue[1] and now - self.queue[1].at > self.STALE do table.remove(self.queue, 1) end
  local line = self.queue[1]
  if not line then return end
  if not quiet() and IsInGuild() and not D:Settings().hush then
    table.remove(self.queue, 1)
    chat(line.text, "GUILD")
    self.last = now
  elseif D.sandbox or D:Settings().hush or not IsInGuild() then
    self.queue = {}
    return
  end
  -- More to say, or held by the lockdown: look again in a moment.
  if self.queue[1] then
    self.timer = true
    C_Timer.After(self.GAP, function() An:Flush() end)
  end
end

-- A line for guild chat (from this client's own op). Logged even when it is not sent, for the self-test.
function An:Say(text)
  text = An.Clean(L.AN_PREFIX .. text)
  self.log[#self.log + 1] = { kind = "GUILD", text = text, sent = not D.sandbox and not D:Settings().hush }
  while #self.log > self.LOG_MAX do table.remove(self.log, 1) end
  if D.sandbox or D:Settings().hush or #self.queue >= self.QUEUE_MAX then return end
  self.queue[#self.queue + 1] = { text = text, at = GetTime() }
  if self.timer then return end
  local wait = self.last and self.GAP - (GetTime() - self.last) or 0
  if wait > 0 then
    self.timer = true
    C_Timer.After(wait, function() An:Flush() end)
  else
    self:Flush()
  end
end

-- A whisper back to a member (the answer to their !vote), right now. Never from the pretend guild.
function An:Whisper(text, to)
  text = An.Clean(text)
  local send = not quiet()
  self.log[#self.log + 1] = { kind = "WHISPER", text = text, to = to, sent = send }
  while #self.log > self.LOG_MAX do table.remove(self.log, 1) end
  if not send then return end
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    C_ChatInfo.SendChatMessage(text, "WHISPER", nil, to)
  else
    SendChatMessage(text, "WHISPER", nil, to)
  end
end

-- An emote, right now (it needs the click's hardware event, so it never waits).
function An:Emote(text)
  text = An.Clean(text)
  local send = not quiet() and ns.Settings:Get("emotes") ~= false
  self.log[#self.log + 1] = { kind = "EMOTE", text = text, sent = send and true or false }
  while #self.log > self.LOG_MAX do table.remove(self.log, 1) end
  if send then chat(text, "EMOTE") end
end

---------------------------------------------------------------------------
-- What an op means
---------------------------------------------------------------------------
-- What to know before the op changes the copy, to tell what it changed.
local PHASE_OPS = { motion_sec = true, motion_cancel = true, imp_vote = true, mak_ok = true, mak_duel = true,
  rebel = true, rebel_sign = true }
function An.Before(g, a, op)
  local b = {}
  local se = op.id and g.sentences and g.sentences[op.id]
  if se and se.by then b.st = St.State(g, op.id, se).st end
  if op.k == "duel" or op.k == "crown_no" then b.crown = Cr.State(g).holder end
  if PHASE_OPS[op.k] then
    local s = Co.Motion(g, op.id)
    b.phase = s and s.phase
  end
  if op.k == "game_rep" and (op.sq or op.c or op.dead) then
    local ga = g.games and g.games[op.id]
    local key = P:Of(a, g)
    for _, e in ipairs(ga and Gm.Scores(g, ga, op.id) or {}) do
      if e.key == key then b.bingo, b.done, b.dead = e.bingo ~= nil, e.done, e.dead ~= nil end
    end
  end
  return b
end

-- A sentence's line: who, what, why. The stocks also say where they stand.
local function sentenced(g, se, s)
  local text
  if se.pun == "trial" then
    text = L.AN_TRIAL_ORDERED:format(who(se.to), who(se.by))
  else
    text = L.AN_SENTENCE:format(who(se.to), pun(se.pun))
    if se.len and St.TIMED[se.pun] and se.pun ~= "wheel" then text = text .. L.AN_MINUTES:format(se.len) end
    if se.why then text = text .. L.AN_WHY:format(se.why) end
    if s.pun == "stocks" then
      local spot = g.settings and g.settings.spot
      text = text .. (spot and spot.z and L.AN_STOCKS_AT:format(spot.z) or L.AN_STOCKS_ANY)
    end
  end
  return text
end

-- For op (by a, at t, its count n): the guild chat line, the alert { text, sub } and the emote (for a click), each
-- or nil. b: what An.Before saw.
function An.Describe(g, a, op, t, n, b)
  b = b or {}
  local k = op.k
  local say, alert, emote
  local id = op.id
  local se = id and g.sentences and g.sentences[id]
  if k == "sentence" then
    id = D.Key(a, n)
    se = g.sentences and g.sentences[id]
    local s = se and St.State(g, id, se, t)
    if not s or s.st == "void" or s.st == "done" then return end
    say = sentenced(g, se, s)
    alert = { text = L.AN_ALERT_SENTENCE:format(who(se.to)), sub = se.pun == "trial" and L.AN_PUN_TRIAL or pun(se.pun),
      icon = "p_" .. se.pun, how = "stamp" }
    if se.pun == "stocks" then emote = L.AN_EMOTE_STOCKS:format(who(se.to))
    elseif se.pun == "trial" then emote = L.AN_EMOTE_TRIAL_ORDER:format(who(se.to))
    else emote = L.AN_EMOTE_SENTENCE:format(who(se.to), pun(se.pun)) end
  elseif se and se.by then
    local s = St.State(g, id, se)
    local name = who(se.to)
    if k == "spin" or k == "reroll" then
      if s.st ~= "active" then return end
      say = (k == "spin" and L.AN_SPIN or L.AN_REROLL):format(name, pun(op.r))
      emote = k == "spin" and L.AN_EMOTE_SPIN:format(name) or L.AN_EMOTE_REROLL
    elseif k == "tomato" then
      emote = L.AN_EMOTE_TOMATO:format(name)
    elseif k == "pardon" and b.st ~= "done" and s.how == "pardoned" then
      say = L.AN_PARDON:format(who(a), name)
      emote = L.AN_EMOTE_PARDON:format(name)
    elseif k == "bail" and b.st ~= "done" and s.how == "bailed" then
      say = (se.pun == "radio" and L.AN_BROKE or L.AN_BAIL):format(name)
      emote = L.AN_EMOTE_BAIL
    elseif k == "trial" and b.st ~= "trial" and s.st == "trial" then
      say = L.AN_TRIAL:format(name, who(se.by))
      alert = { text = L.AN_ALERT_TRIAL, sub = L.AN_ALERT_VS:format(name, who(se.by)), icon = "p_trial", how = "stamp" }
      emote = L.AN_EMOTE_TRIAL:format(who(se.by))
    elseif k == "tribute" then
      say = (op.ok and L.AN_TRIBUTE_OK or L.AN_TRIBUTE_NO):format(name)
      emote = (op.ok and L.AN_EMOTE_TRIBUTE_OK or L.AN_EMOTE_TRIBUTE_NO):format(name)
    elseif b.st and b.st ~= "done" and s.st == "done" and (s.how == "served" or s.how == "deed") then
      say = L.AN_SERVED:format(name, pun(s.pun))
    end
  elseif k == "crown_ch" then
    local holder = Cr.State(g).holder
    if not holder or holder == P:Of(a, g) then return end
    say = L.AN_CROWN_CH:format(who(a), P:Name(holder, g))
    emote = L.AN_EMOTE_CROWN_CH:format(P:Name(holder, g))
  elseif k == "duel" or k == "crown_no" then
    local s = Cr.State(g)
    if s.holder and s.holder ~= b.crown then
      local loser = b.crown and P:Name(b.crown, g)
      if k == "crown_no" then say = L.AN_CROWN_YIELD:format(loser or "", who(s.name))
      elseif loser then say = L.AN_CROWN_TAKEN:format(who(s.name), loser)
      else say = L.AN_CROWN_FIRST:format(who(s.name)) end
      alert = { text = loser and L.AN_ALERT_FALLEN or L.AN_ALERT_CROWN, sub = L.AN_ALERT_CROWN_SUB:format(who(s.name)), icon = "crown",
        fanfare = true }
    elseif k == "duel" and op.cr and b.crown and s.holder == b.crown and P:Of(op.w, g) == b.crown then
      say = L.AN_CROWN_KEPT:format(who(op.w), who(op.l))
    elseif k == "duel" and g.sentences and g.sentences[op.c] then
      say = L.AN_TRIAL_WON:format(who(op.w), who(op.l))
    end
  elseif k == "cup_end" then
    local c = g.cups and g.cups[id]
    local first = op.places[1] and op.places[1][1]
    if not first then return end
    if c and c.lead then
      local s = Co.Motion(g, id)
      local gm = s and s.mo.gm
      if gm and P:Of(first, g) == P:Of(gm, g) then
        say = L.AN_CROWN_DEFENDED:format(who(first))
        alert = { text = L.AN_ALERT_CROWN_DEFENDED, sub = who(first), fanfare = true }
      else
        say = L.AN_CROWN_WON:format(who(first), who(gm or ""))
        alert = { text = L.AN_ALERT_CROWN_WON:format(who(first)), sub = L.AN_ALERT_CROWN_WON_SUB:format(who(gm or "")),
          fanfare = true }
      end
      return say, alert
    end
    say = L.AN_CUP:format(who(first), c and c.name or "")
    alert = { text = L.AN_ALERT_CHAMPION:format(who(first)), sub = c and c.name, fanfare = true, icon = "prize" }
  elseif k == "raffle_draw" then
    local ra = g.raffles and g.raffles[id]
    say = L.AN_RAFFLE:format(who(op.w), ra and ra.prize or "", op.roll)
  elseif k == "deathroll" then
    say = L.AN_DEATHROLL:format(who(op.l), who(op.w), money(op.amt, op.p))
  elseif k == "rolloff_end" then
    if op.amt > 0 then say = L.AN_ROLLOFF:format(who(op.hi), money(op.amt, op.p), who(op.lo)) end
  elseif k == "game" then
    id = D.Key(a, n)
    local ga = g.games and g.games[id]
    if not ga then return end
    local when = ga.at <= t + 60 and L.AN_NOW or date(L.GM_DATE, ga.at)
    if ga.kind == "santa" then
      say = L.AN_SANTA_OPEN:format(date(L.GM_DATE, ga.at))
    else
      say = L.AN_GAME:format(Gm.KindName(ga.kind), when)
      if (ga.prize or 0) > 0 then say = say .. L.AN_PRIZE:format(money(ga.prize, ga.p)) end
    end
  elseif k == "game_end" then
    local ga = g.games and g.games[id]
    -- The Traitors' end has its own line (tr_end).
    if not ga or ga.kind == "traitors" then return end
    if ga.kind == "flash" then
      say = L.AN_FLASH_DONE:format(#op.w)
    elseif #op.w > 0 then
      say = L.AN_GAME_WON:format(list(op.w), kindOf(ga))
      alert = { text = L.AN_ALERT_WINNER:format(list(op.w)), sub = Gm.KindName(ga.kind), fanfare = true }
    else
      say = L.AN_GAME_NONE:format(kindOf(ga))
    end
  elseif k == "game_rep" and (op.c or op.dead) and g.games and g.games[id] and g.games[id].kind == "gnomes" then
    local ga = g.games[id]
    local key = P:Of(a, g)
    for _, e in ipairs(Gm.Scores(g, ga, id)) do
      if e.key == key and e.done and not b.done then
        say = L.AN_GNOME_SAFE:format(who(a))
        alert = { text = L.AN_ALERT_GNOME_SAFE:format(who(a)), sub = Gm.KindName(ga.kind) }
      elseif e.key == key and e.dead and not b.dead then
        say = L.AN_GNOME_FELL:format(who(a), e.v, #(ga.clues or {}))
        alert = { text = L.AN_ALERT_GNOME_FELL:format(who(a)), sub = Gm.KindName(ga.kind) }
      end
    end
  elseif k == "charter" or k == "poll" or k:sub(1, 6) == "motion" or k == "lead_cup" or k:sub(1, 5) == "court"
    or k == "imp_vote" or k == "mak_ok" or k == "mak_duel"
    or k == "rebel" or k == "rebel_sign" or k == "elect_run" or k == "elect_done" then
    say, alert = An.Council(g, a, op, b)
  elseif k == "tax_run" then
    say = L.AN_TAX:format(ns.Treasury.PeriodName(op.per), #op.d)
  elseif k:sub(1, 3) == "tr_" then
    local ga = g.games and g.games[id]
    if not ga then return end
    say, alert, emote = An.Traitors(ga, id, op)
  elseif k:sub(1, 6) == "santa_" then
    local ga = g.games and g.games[id]
    if not ga then return end
    say, alert = An.Santa(ga, a, op)
  elseif k == "game_rep" and op.sq and not b.bingo then
    local ga = g.games and g.games[id]
    local key = P:Of(a, g)
    for _, e in ipairs(ga and Gm.Scores(g, ga, id) or {}) do
      if e.key == key and e.bingo then
        say = L.AN_BINGO:format(who(a))
        alert = { text = L.AN_ALERT_BINGO, sub = L.AN_ALERT_BINGO_SUB:format(who(a)), fanfare = true, icon = "bingo",
          how = "stamp" }
      end
    end
  end
  return say, alert, emote
end

-- The Traitors: the deal, nightfall, the murdered, the banished and their role, the end. The alert at nightfall
-- tells a traitor (on their own screen only) to choose.
function An.Traitors(ga, id, op)
  local k = op.k
  local say, alert, emote
  if k == "tr_go" then
    say = L.AN_TR_DEALT:format(op.n, #op.p)
    alert = { text = L.AN_ALERT_TR_DEALT, sub = L.AN_ALERT_TR_DEALT_SUB }
  elseif k == "tr_night" then
    say = L.AN_TR_NIGHT
    local mine = Tr.Role(id) == "traitor" and Tr.Alive(ga)[ns.Self()]
    alert = { text = L.AN_ALERT_TR_NIGHT, sub = mine and L.AN_ALERT_TR_CHOOSE or L.AN_ALERT_TR_SLEEP }
  elseif k == "tr_dawn" then
    if op.v == "" then
      say = L.AN_TR_NOBODY
      alert = { text = L.AN_ALERT_TR_MORNING, sub = L.AN_ALERT_TR_ALL_WOKE }
    else
      say = L.AN_TR_MURDERED:format(who(op.v))
      alert = { text = L.AN_ALERT_TR_MURDER, sub = L.AN_ALERT_TR_FOUND:format(who(op.v)) }
    end
  elseif k == "tr_ban" then
    if op.v == "" then
      say = L.AN_TR_NO_BANISH
    else
      local was = op.role == "traitor" and L.AN_TR_WAS_TRAITOR or L.AN_TR_WAS_FAITHFUL
      say = L.AN_TR_BANISHED:format(who(op.v), was)
      alert = { text = L.AN_ALERT_TR_BANISHED:format(who(op.v)), sub = was }
    end
  elseif k == "tr_vote" then
    emote = L.AN_EMOTE_TR_VOTE:format(who(op.on))
  elseif k == "tr_end" then
    local faithful = op.side == "faithful"
    say = faithful and L.AN_TR_FAITHFUL_WIN or L.AN_TR_TRAITORS_WIN:format(list(op.tr))
    alert = { text = faithful and L.TR_WON_FAITHFUL or L.TR_WON_TRAITORS, sub = L.TR_WERE:format(list(op.tr)) }
  end
  return say, alert, emote
end

-- The Council: a new charter, a poll, a rule change and its seconds, an impeachment and how it ends, a Mak'gora (the
-- answer, the duel, a rebellion), the crown tournament, a court case and its verdict, the Guild Master's election.
function An.Council(g, a, op, b)
  local k = op.k
  if k == "charter" then
    return L.AN_CHARTER:format(op.v)
  elseif k == "poll" then
    return L.AN_POLL:format(who(a), op.q)
  elseif k == "motion" then
    if op.kind == "lead" then
      return L.AN_IMPEACH:format(who(a), who(op.gm), op.why),
        { text = L.AN_ALERT_IMPEACH, sub = L.AN_ALERT_IMPEACH_SUB:format(who(a)) }
    elseif op.kind == "mak" then
      return L.AN_MAK:format(who(a), who(op.gm), op.why),
        { text = L.AN_ALERT_MAK, sub = L.AN_ALERT_MAK_SUB:format(who(a), who(op.gm)) }
    elseif op.kind == "rule" then
      return L.AN_RULE:format(who(a), op.why, op.sec, op.hrs)
    elseif op.kind == "setup" then
      return L.AN_SETUP:format(who(a), L["SETUP_" .. op.setup:upper()], op.why)
    end
    return L.AN_CROWN_OPEN:format(who(a)), { text = L.AN_ALERT_CROWN_OPEN, sub = L.AN_ALERT_CROWN_OPEN_SUB }
  elseif k == "motion_sec" then
    local s = Co.Motion(g, op.id)
    if not s or (s.kind ~= "rule" and s.kind ~= "setup") or b.phase ~= "motion" or s.phase ~= "vote" then return nil end
    if s.mo.vt then return L.AN_RULE_VOTE_SOME:format(s.mo.why, s.mo.days) end
    return L.AN_RULE_VOTE:format(s.mo.why, s.mo.days)
  elseif k == "motion_cancel" then
    local s = Co.Motion(g, op.id)
    if not s or b.phase ~= "vote" or s.phase ~= "cancelled" then return nil end
    return L.AN_IMP_CANCELLED:format(who(a))
  elseif k == "imp_vote" then
    -- The vote that decided it.
    local s = Co.Motion(g, op.id)
    if not s or b.phase ~= "vote" or s.phase == "vote" then return nil end
    if s.phase == "failed" then return L.AN_IMP_FAILED:format(who(s.mo.gm)) end
    if not s.winner then return nil end
    return L.AN_IMP_PASSED:format(who(s.winner), who(s.mo.gm)),
      { text = L.AN_ALERT_IMP_PASSED:format(who(s.winner)), sub = L.AN_ALERT_WAIT_HAND:format(who(s.mo.gm)) }
  elseif k == "mak_ok" then
    local s = Co.Motion(g, op.id)
    if not s or b.phase ~= "challenge" then return nil end
    if op.on then
      return L.AN_MAK_ACCEPTED:format(who(a), who(s.mo.a)),
        { text = L.AN_ALERT_MAK_ACCEPTED, sub = L.AN_ALERT_MAK_VS:format(who(s.mo.a), who(a)) }
    end
    -- (In a Dictatorship no vote: the challenger may declare a rebellion, SPEC decision 70.)
    if s.mo.dict then return L.AN_MAK_DECLINED_REBEL:format(who(a), who(s.mo.a)) end
    return L.AN_MAK_DECLINED:format(who(a))
  elseif k == "mak_duel" then
    local s = Co.Motion(g, op.id)
    if not s or b.phase ~= "duel" or not s.winner then return nil end
    if P:Of(s.winner, g) == P:Of(s.mo.gm, g) then
      return L.AN_MAK_GM_WON:format(who(s.winner)), { text = L.AN_ALERT_MAK_GM_WON, sub = who(s.winner) }
    end
    return L.AN_MAK_WON:format(who(s.winner), who(s.mo.gm)),
      { text = L.AN_ALERT_MAK_WON:format(who(s.winner)), sub = L.AN_ALERT_WAIT_HAND:format(who(s.mo.gm)) }
  elseif k == "lead_cup" then
    local s = Co.Motion(g, op.id)
    local gm = s and s.mo.gm or ""
    return L.AN_CROWN_SIGNUP:format(who(gm)), { text = L.AN_ALERT_CROWN_SIGNUP, sub = L.AN_ALERT_CROWN_SIGNUP_SUB:format(who(gm)) }
  elseif k == "court" then
    -- (Only a player with Guild Together can be charged: SPEC decision 56.)
    if not P:HasAddon(P:Of(op.to, g)) then return nil end
    return L.AN_COURT:format(who(op.to), op.why)
  elseif k == "court_close" then
    local s = Ct.Case(g, op.id)
    if not s or not s.verdict then return nil end
    local name = who(s.cs.to)
    if s.verdict == "guilty" then
      return L.AN_GUILTY:format(name, s.guilty, #s.jurors), { text = L.AN_ALERT_GUILTY, sub = name, icon = "scales", how = "stamp" }
    elseif s.verdict == "innocent" then
      return L.AN_INNOCENT:format(name, s.innocent, #s.jurors), { text = L.AN_ALERT_INNOCENT, sub = name, icon = "scales", how = "stamp" }
    end
    return L.AN_DISMISSED:format(name)
  elseif k == "rebel" then
    local s = Co.Motion(g, op.id)
    if not s or s.phase ~= "rebellion" or b.phase == "rebellion" then return nil end
    return L.AN_REBEL:format(who(a), who(s.mo.gm), s.need),
      { text = L.AN_ALERT_REBEL, sub = L.AN_ALERT_REBEL_SUB:format(who(a)) }
  elseif k == "rebel_sign" then
    -- The signature that was enough.
    local s = Co.Motion(g, op.id)
    if not s or b.phase ~= "rebellion" or s.phase ~= "duel" then return nil end
    return L.AN_REBEL_FORCED:format(who(s.mo.gm), who(s.mo.a))
  elseif k == "elect_run" then
    return L.AN_ELECT_STAND:format(who(a), op.line)
  elseif k == "elect_done" then
    return L.AN_ELECT_LEADS:format(who(a)), { text = L.AN_ALERT_ELECT, sub = who(a) }
  end
  return nil
end

-- Secret Santa: the draw, a gift arriving (said by its giftee), the reveal (on each screen: who your Santa was).
function An.Santa(ga, a, op)
  local k = op.k
  if k == "santa_go" then
    return L.AN_SA_DRAWN, { text = L.AN_ALERT_SA_DRAWN, sub = L.AN_ALERT_SA_DRAWN_SUB }
  elseif k == "santa_got" then
    return L.AN_SA_GOT:format(who(a))
  elseif k == "santa_end" then
    local mine
    for _, x in ipairs(op.pairs) do if x[2] == ns.Self() then mine = x[1] end end
    local got = Sa.Count(ga)
    return L.AN_SA_REVEALED:format(got, #(ga.pl or {})),
      { text = L.AN_ALERT_SA_REVEALED, sub = mine and L.AN_ALERT_SA_YOURS:format(who(mine)) or Gm.KindName(ga.kind) }
  end
  return nil
end

---------------------------------------------------------------------------
-- Listening to the sync engine (Guild/Sync.lua)
---------------------------------------------------------------------------
local function guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then ns:LogError("announce", tostring(err)) end
  end
end

-- Fresh ops are announced. The Herald's addon also describes older ones (the catch-up after a login) for Discord
-- (Guild/Herald.lua), without saying them in the game.
ns:On("OP_BEFORE", guard(function(g, a, op, t)
  An.before, An.fresh = nil, math.abs(time() - t) < An.FRESH
  if An.fresh or (ns.Herald and ns.Herald.Listening(g, t)) then An.before = An.Before(g, a, op) end
end))

-- The new Guild Master's addon tells the guild, once (Guild/Council.lua).
ns:On("NEW_GM", guard(function(name)
  An:Say(L.AN_NEW_GM:format(who(name)))
  ns:Fire("ALERT", { text = L.AN_ALERT_NEW_GM, sub = who(name), icon = "throne" })
end))

-- A new setup, or a rule changed by vote (Co:Moments, the 1 Nov review): on every member's alert line, with the
-- setup's scene; the Guild Master's addon says it in guild chat.
ns:On("SETUP_CHANGED", guard(function(g, id)
  local name = L["SETUP_" .. id:upper()]
  if D:InCharge() then An:Say(L.AN_SETUP_NOW:format(name)) end
  ns:Fire("ALERT", { text = L.AN_ALERT_SETUP, sub = L.AN_ALERT_SETUP_SUB:format(name), icon = ns.Rules.ICON[id],
    scene = { page = "council", draw = function(f) ns.Scenes.Setup(f, g, id) end } })
end))

ns:On("RULE_CHANGED", guard(function(_, s)
  local mo = s.mo
  local rule = L["CO_RULE_" .. tostring(mo.r):upper()]
  local value = Co.Describe and Co.Describe(mo.r, mo.v) or tostring(mo.v)
  if D:InCharge() then An:Say(L.AN_RULE_PASSED:format(rule, value)) end
  ns:Fire("ALERT", { text = L.AN_ALERT_RULE, sub = L.AN_ALERT_RULE_SUB:format(rule, value), icon = "ballot" })
end))

-- What every member is told on their own screen (Co:Watch, SPEC §7.5): a Guild Master online who does not hand over,
-- an officer demoted during an impeachment vote, a challenger removed during their Mak'gora.
ns:On("LEAD_WARNING", guard(function(what, a, b)
  local line
  if what == "gm" then line = L.AN_WARN_GM:format(who(a), who(b))
  elseif what == "demoted" then line = L.AN_WARN_DEMOTED:format(who(a))
  elseif what == "removed" then line = L.AN_WARN_REMOVED:format(who(a)) end
  if not line then return end
  ns:Print(line)
  ns:Fire("ALERT", { text = L.AN_ALERT_WARN, sub = line })
end))

ns:On("OP", guard(function(g, a, op, t, n, made)
  local b = An.before
  An.before = nil
  if not b or ns.db.guilds[g.id] ~= g then return end
  local say, alert, emote = An.Describe(g, a, op, t, n, b)
  if say then ns:Fire("NEWS", g, a, op, t, n, say) end
  if not An.fresh then return end
  if say and a == ns.Self() then An:Say(say) end
  if emote and made then An:Emote(emote) end
  if alert then
    -- Its scene under the line (UI/Alerts.lua, SPEC decision 63).
    if ns.Alerts and ns.Alerts.SceneFor then alert.scene = ns.Alerts.SceneFor(g, a, op, n) end
    ns:Fire("ALERT", alert)
  end
end))
