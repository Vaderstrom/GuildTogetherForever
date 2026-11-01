-- The guild's rules for punishments (SPEC decision 69): every punishment has a reason, unpaid tax or an incident;
-- three switches (the Guild Master's settings, settings.pun: tax punishments, incidents by the court or judged
-- directly, trial by combat); any member may opt out of punishment, and then the places that closes are theirs to look
-- at, not to take part in; and one text of the rules, written from the settings in force, for everyone to read.
--   optout { on }   a member opts out (true) or back in (false); kept per character, the last few, with their times
-- What an opted-out member may not do is checked on the op's own time (D:Allowed passes it), against the author's
-- own opt-outs, which reach every copy in the author's order: so every copy agrees. Whether the punished member had
-- opted out is checked when read (St.State), against the time of the sentence.
local _, ns = ...
local L, D, P = ns.L, ns.GuildData, ns.Players

local Ru = {}
ns.Rules = Ru

Ru.WAIT = 7 * 86400    -- after opting back in, a member waits this long before opting out again
Ru.KEEP = 10           -- opt-outs kept per character

---------------------------------------------------------------------------
-- Opting out
---------------------------------------------------------------------------
local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end

-- A player's switches in time order (from all their characters): { { on, t }, ... }.
local function history(g, key)
  local list = {}
  for name, h in pairs(g and g.optout or {}) do
    if P:Of(name, g) == key then
      for _, x in ipairs(h) do list[#list + 1] = x end
    end
  end
  table.sort(list, function(a, b) return a.t < b.t end)
  return list
end

-- Had the player opted out at time t (default now)? Never while the guild has no punishments (no setup yet, or a
-- Free guild: SPEC decision 70).
function Ru.OptedOut(g, key, t)
  local setup = Ru.Setup(g)
  if setup == nil or setup == "free" then return false end
  t = t or time()
  local on = false
  for _, x in ipairs(history(g, key)) do
    if x.t <= t then on = x.on end
  end
  return on
end

function Ru.Out(g, name, t) return name ~= nil and Ru.OptedOut(g, P:Of(name, g), t) end

-- When the player may opt out again (nil: now). Opting back in starts the wait.
function Ru.WaitUntil(g, key, now)
  now = now or time()
  local last
  for _, x in ipairs(history(g, key)) do
    if x.on == false then last = x.t end
  end
  if last and now - last < Ru.WAIT then return last + Ru.WAIT end
  return nil
end

D:Register("optout", {
  allowed = function(_, _, op) return type(op.on) == "boolean" end,
  apply = function(g, author, op, t)
    local key = P:Of(author, g)
    if Ru.OptedOut(g, key, t) == op.on then return false end
    if op.on and Ru.WaitUntil(g, key, t) then return false end
    local all = D.Part(g, "optout")
    all[author] = all[author] or {}
    local h = all[author]
    h[#h + 1] = { on = op.on, t = t }
    while #h > Ru.KEEP do table.remove(h, 1) end
    return true
  end,
  copy = function(g) return g.optout end,
  merge = function(g, part)
    for name, h in pairs(type(part) == "table" and part or {}) do
      if party(name) and type(h) == "table" then
        local all = D.Part(g, "optout")
        local mine = all[name] or {}
        local seen = {}
        for _, x in ipairs(mine) do seen[x.t] = true end
        for _, x in ipairs(h) do
          if type(x) == "table" and type(x.on) == "boolean" and tonumber(x.t) and not seen[x.t] then
            mine[#mine + 1] = { on = x.on, t = tonumber(x.t) }
          end
        end
        table.sort(mine, function(a, b) return a.t < b.t end)
        while #mine > Ru.KEEP do table.remove(mine, 1) end
        all[name] = mine
      end
    end
  end,
})

function Ru.SetOptOut(on) return ns.Sync:Do({ k = "optout", on = on and true or false }) end

---------------------------------------------------------------------------
-- The switches (settings.pun, in Guild/Data.lua)
---------------------------------------------------------------------------
-- The three switches in force (SPEC decisions 69 and 70): the Guild Master's; the first values of a setup the guild
-- voted in since; then the guild's votes on each (ptax, pcourt, ptrial in Guild/Council.lua): the newest wins, and in
-- a Democracy a vote wins over the Guild Master. { tax, incidents, trial, closed, t (when they last changed) }.
local VOTED = { tax = "ptax", incidents = "pcourt", trial = "ptrial" }
function Ru.Pun(g)
  local s = g and g.settings or D:Settings()
  local pun, out = s.pun, nil
  local at = pun.t or 0
  local Co = ns.Council
  local voted = Co and Co.SetupVoted and Co.SetupVoted(g)
  if voted and voted.changed and voted.changed > at and Ru.START[voted.setup] then
    local first = Ru.START[voted.setup]
    out = { tax = first.tax, incidents = first.incidents, trial = first.trial, closed = pun.closed, t = voted.changed }
    at = voted.changed
  end
  g = g or D:Current()
  local rules = Co and Co.Rules and g and Co.Rules(g) or {}
  local setup, _, changed = Ru.Setup(g)
  for key, r in pairs(VOTED) do
    local x = rules[r]
    if x and (x.t > at or (setup == "democracy" and x.t > (changed or 0))) then
      out = out or { tax = pun.tax, incidents = pun.incidents, trial = pun.trial, closed = pun.closed, t = pun.t }
      if key == "incidents" then out[key] = x.v and "court" or "direct" else out[key] = x.v end
      out.t = math.max(out.t or 0, x.t)
    end
  end
  return out or pun
end

-- Is the switch (tax, incidents or trial) set by a vote now (only another vote changes it in a Democracy)?
function Ru.SwitchVoted(g, key)
  g = g or D:Current()
  local x = ns.Council and g and ns.Council.Rules(g)[VOTED[key]]
  local _, _, changed = Ru.Setup(g)
  return x ~= nil and x.t > (changed or 0)
end
Ru.SWITCH_RULE = VOTED

-- Tax punishments can be given now: the switch, and a tax in force.
function Ru.TaxPunishments(g)
  local s = g and g.settings or D:Settings()
  return Ru.Pun(g).tax == true and s.tax.on == true
end
function Ru.Court(g) return Ru.Pun(g).incidents == "court" end
function Ru.Trial(g) return Ru.Pun(g).trial == true end

---------------------------------------------------------------------------
-- What opting out closes (SPEC decision 69)
---------------------------------------------------------------------------
-- The places a kind of op belongs to: its author takes part there. Kinds not listed are never closed (what the addon
-- shares by itself, paying a debt, opting out, the settings).
local PLACE = {
  match = "challenges", duel = "challenges", bet = "challenges", crown_ch = "challenges", crown_ok = "challenges",
  crown_no = "challenges", cup = "challenges", cup_join = "challenges", cup_go = "challenges", cup_duel = "challenges",
  cup_end = "challenges", cup_cancel = "challenges", asn = "challenges", asn_join = "challenges", asn_go = "challenges",
  asn_kill = "challenges",
  deathroll = "gambling", rolloff = "gambling", rolloff_join = "gambling", rolloff_go = "gambling",
  rolloff_roll = "gambling", rolloff_end = "gambling", raffle = "gambling", raffle_buy = "gambling",
  raffle_draw = "gambling",
  game = "games", game_join = "games", game_rep = "games", game_vote = "games", game_cal = "games",
  game_end = "games", game_off = "games",
  craft = "professions", craft_take = "professions", craft_got = "professions", craft_drop = "professions",
  req = "treasury", req_ans = "treasury", req_sent = "treasury", req_drop = "treasury", grant = "treasury",
  feat = "home", feat_del = "home", memorial = "home", memorial_del = "home",
  cal_add = "calendar", cal_edit = "calendar", cal_off = "calendar",
  stk = "punishments", bail = "punishments", spin = "punishments", reroll = "punishments", tribute = "punishments",
  bid = "punishments", hire = "punishments", order = "punishments", odone = "punishments", deed = "punishments",
}
Ru.PLACE = PLACE
-- Taking part in punishing (or judging): never for someone who opted out, whatever is ticked.
local PUNISHING = { sentence = true, tomato = true, pardon = true, trial = true, court = true, court_def = true,
  court_jury = true, court_vote = true, court_close = true, strike = true, strike_ok = true }
Ru.PUNISHING = PUNISHING
-- The places a guild's Guild Master may close to opted-out members while the tax is off (the Council's Leadership,
-- Guild rules and Votes stay open always).
Ru.CLOSABLE = { "challenges", "games", "gambling", "treasury", "professions", "punishments", "calendar", "home" }

-- Is place closed to a player who opted out? With the tax on, every place but the Council; with it off, what the
-- Guild Master ticked.
function Ru.Closed(g, place)
  local s = g and g.settings or D:Settings()
  if place == "council" or place == "manage" then return false end
  if s.tax.on then return true end
  return s.pun.closed[place] == true
end

-- May this player take part in place now (nil key: this character's player)?
function Ru.MayTakePart(g, key, place, t)
  key = key or P:Of(ns.Self(), g)
  return not (Ru.OptedOut(g, key, t) and Ru.Closed(g, place))
end

-- The op is refused because its author opted out (D:Allowed asks, with the op's time).
function Ru.Blocked(g, author, op, t)
  local k = type(op) == "table" and op.k
  if not k or not g or not g.optout then return false end
  if not PUNISHING[k] and not (PLACE[k] and Ru.Closed(g, PLACE[k])) and not k:match("^tr_") and not k:match("^santa_") then
    return false
  end
  if (k:match("^tr_") or k:match("^santa_")) and not Ru.Closed(g, "games") then return false end
  return Ru.OptedOut(g, P:Of(author, g), t)
end

---------------------------------------------------------------------------
-- Tax punishments: which period a punishment pays off
---------------------------------------------------------------------------
-- The player's unpaid tax periods, oldest first: { { key, per, amt, t }, ... } (the Treasury's tax debts still open).
function Ru.TaxOwed(g, key)
  local out = {}
  for _, d in ipairs(g and ns.Purse:Open(g) or {}) do
    if d.w == "tax" and d.to == ns.Purse.TREASURY and d.f == key then out[#out + 1] = d end
  end
  table.sort(out, function(a, b) if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end return a.key < b.key end)
  return out
end

-- The tax debts forgiven by tax punishments: { [debt key] = sentence id }. A sentence forgives the debt it names when
-- that debt is the punished player's tax, and only the earliest sentence naming it counts (one punishment a period).
function Ru.Forgiven(g)
  local out, at = {}, {}
  local whose = {}
  for _, fn in ipairs(ns.Purse.extraDebts or {}) do
    for _, e in ipairs(fn(g)) do if e.w == "tax" then whose[e.key] = P:Of(e.f, g) end end
  end
  for id, se in pairs(g and g.sentences or {}) do
    if se.r == "tax" and se.tx and se.by and whose[se.tx] == P:Of(se.to, g) and not Ru.OptedOut(g, whose[se.tx], se.t) then
      local cur = at[se.tx]
      if not cur or se.t < cur.t or (se.t == cur.t and id < cur.id) then at[se.tx] = { t = se.t, id = id } end
    end
  end
  for key, x in pairs(at) do out[key] = x.id end
  return out
end

---------------------------------------------------------------------------
-- The guild's setup (SPEC decision 70): settings.gov = { setup, elect, sits, judge, t }, picked by the Guild Master
-- the first time; t: when it last changed from one setup to another (what was running then is cancelled). In
-- Democracy, Warcouncil and Monarchy a passed vote of kind "setup" (Guild/Council.lua) changes it instead.
---------------------------------------------------------------------------
Ru.SETUPS = { "democracy", "warcouncil", "monarchy", "dictatorship", "free" }
-- The switches each setup starts with.
Ru.START = {
  democracy = { tax = true, incidents = "court", trial = true },
  warcouncil = { tax = true, incidents = "court", trial = true },
  monarchy = { tax = true, incidents = "court", trial = true },
  dictatorship = { tax = true, incidents = "direct", trial = true },
  free = { tax = false, incidents = "direct", trial = false },
}
-- Each setup's emblem (UI.ICON): its card in Guild settings, its moment on the alert line.
Ru.ICON = { democracy = "ballot", warcouncil = "officer", monarchy = "crown", dictatorship = "throne", free = "rosette" }
Ru.ELDERS = 5   -- the Warcouncil of elders: the Guild Master and the 5 in the guild longest (with Guild Together)

-- The setup in force: id (nil: none picked yet), its options { elect, sits, judge }, and when it last changed.
function Ru.Setup(g)
  local s = g and g.settings or D:Settings()
  local gov = s.gov or {}
  local voted = ns.Council and ns.Council.SetupVoted and ns.Council.SetupVoted(g)
  if voted then return voted.setup, voted, voted.changed end
  return gov.setup, gov, gov.t
end

-- Only the regular features work (no setup picked yet, or no Guild Master with Guild Together to pick one).
function Ru.Regular(g) return Ru.Setup(g) == nil end

local function rankOf(name)
  local rank = ns.Roster:Rank(name)
  if rank == nil then return nil end
  for _, r in ipairs(ns.Roster:Ranks()) do if r.index == rank then return r end end
  return { index = rank, name = "" }
end

-- An officer (or the Guild Master in charge).
function Ru.Officer(g, name)
  local r = rankOf(name)
  if not r then return false end
  if r.index == 0 then return D:InCharge(name, g) end
  return D.Officer(r, g and g.settings or D:Settings())
end

-- The elders: the Guild Master and the Ru.ELDERS players with Guild Together who have been in the guild the longest (as
-- Guild Together has seen them): { [player key] = true }.
function Ru.Elders(g)
  local list, seen, out = {}, {}, {}
  for name, rank in pairs(ns.Roster:All()) do
    local key = P:Of(name, g)
    if rank == 0 then out[key] = true end
    if rank ~= 0 and P:HasAddon(key) and not seen[key] then
      seen[key] = true
      list[#list + 1] = { key = key, t = P:Since(key, g) or math.huge }
    end
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)
  for i = 1, math.min(Ru.ELDERS, #list) do out[list[i].key] = true end
  return out
end

-- Is name on the Warcouncil (the officers, or the elders)?
function Ru.InCouncil(g, name)
  local _, opt = Ru.Setup(g)
  if opt.sits == "elders" then return Ru.Elders(g)[P:Of(name, g)] == true end
  return Ru.Officer(g, name)
end

-- Who votes on a rule or setup change, when it is not every member: the council's or the officers' characters.
function Ru.Voters(g)
  local setup = Ru.Setup(g)
  if setup ~= "warcouncil" and setup ~= "monarchy" then return nil end
  local list = {}
  for name in pairs(ns.Roster:All()) do
    local yes = setup == "warcouncil" and Ru.InCouncil(g, name) or (setup == "monarchy" and Ru.Officer(g, name))
    if yes then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- The duel crown's holder judges incidents (Dictatorship's option).
local function crowned(g, name)
  local s = ns.Crown and ns.Crown.State(g)
  return s ~= nil and s.holder ~= nil and s.holder == P:Of(name, g)
end
Ru.Crowned = crowned

local PUN = {}
for _, p in ipairs(D.PUNISHMENTS) do PUN[p] = true end
PUN.spin, PUN.pardon = true, true

-- May name do action under the setup (D:Can asks first)? true or false; nil: as their rank allows (SPEC §3.2).
function Ru.May(action, name, g)
  local setup, opt = Ru.Setup(g)
  local member = ns.Roster:Rank(name) ~= nil
  if not setup then
    -- Only the regular features until a setup is picked.
    if PUN[action] or action == "court" or action == "strike" or action == "confirm" or action == "motion"
      or action == "impeach" or action == "items" or action == "grant" then return false end
    return nil
  end
  if setup == "free" then
    if PUN[action] or action == "court" or action == "motion" then return false end
    if action == "strike" or action == "confirm" then return Ru.Officer(g, name) end
    if action == "impeach" then return member and ns.Roster:Rank(name) ~= 0 end
    return nil
  end
  if setup == "democracy" then
    if action == "strike" then return Ru.Officer(g, name) end
    if action == "confirm" then return member end
    if action == "impeach" then return member and ns.Roster:Rank(name) ~= 0 end
    return nil
  end
  if setup == "warcouncil" then
    if action == "strike" or action == "confirm" or action == "motion" or action == "impeach" or action == "court" then
      return Ru.InCouncil(g, name) and (action ~= "impeach" or ns.Roster:Rank(name) ~= 0)
    end
    return nil
  end
  if setup == "monarchy" then
    if action == "strike" or action == "confirm" then return Ru.Officer(g, name) end
    if action == "motion" or action == "impeach" then return Ru.Officer(g, name) and ns.Roster:Rank(name) ~= 0 end
    return nil
  end
  -- Dictatorship: no votes and no impeachment (Mak'gora, then rebellion); strikes need no second; the crown's holder
  -- may give strikes when they judge incidents.
  if action == "motion" or action == "impeach" then return false end
  if action == "strike" and opt.judge == "crown" and crowned(g, name) then return true end
  return nil
end

-- Does a strike count at once, with no second to confirm it (Dictatorship)?
function Ru.StrikeAtOnce(g) return Ru.Setup(g) == "dictatorship" end

-- Was something started at t cancelled by a later change of setup?
function Ru.Cancelled(g, t)
  local _, _, changed = Ru.Setup(g)
  return changed ~= nil and t ~= nil and t < changed
end

---------------------------------------------------------------------------
-- The rules, written out for everyone (SPEC decision 69): { { head, lines = { ... } }, ... }
---------------------------------------------------------------------------
-- What a setup says, line by line (the rules for everyone, and the picker in Guild settings): opt = { sits, judge }.
function Ru.SetupLines(id, opt)
  opt = opt or {}
  local up = id:upper()
  local lines = {}
  for i = 1, 5 do
    local key = "SETUP_" .. up .. "_" .. i
    local line = L[key]
    -- (A missing string reads as its key: Locales/enUS.lua.)
    if line == key then break end
    lines[#lines + 1] = line
  end
  if id == "democracy" and opt.elect then lines[#lines + 1] = L.SETUP_ELECT_LINE end
  if id == "warcouncil" then lines[#lines + 1] = opt.sits == "elders" and L.SETUP_SITS_ELDERS:format(Ru.ELDERS) or L.SETUP_SITS_OFFICERS end
  if id == "dictatorship" then lines[2] = opt.judge == "crown" and L.SETUP_JUDGE_CROWN or L.SETUP_JUDGE_RANKS end
  return lines
end

function Ru.Text(g)
  local s = g and g.settings or D:Settings()
  local pun = Ru.Pun(g)
  local out = {}
  local function part(head, lines) out[#out + 1] = { head = head, lines = lines } end
  local setup, opt, changed = Ru.Setup(g)
  if setup then
    local lines = Ru.SetupLines(setup, opt)
    table.insert(lines, 1, L.RU_SETUP_IS:format(L["SETUP_" .. setup:upper()]))
    part(L.RU_SETUP, lines)
  else
    part(L.RU_SETUP, { L.RU_SETUP_NONE })
  end
  if setup == "free" then
    part(L.RU_REASONS, { L.RU_FREE, L.RU_NEVER_GM })
    local last = math.max(pun.t or 0, changed or 0, (s.gov and s.gov.at) or 0)
    out.changed = last > 0 and last or nil
    return out
  end
  part(L.RU_REASONS, {
    Ru.TaxPunishments(g) and L.RU_TAX_ON or (s.tax.on and L.RU_TAX_SWITCH_OFF or L.RU_TAX_NONE),
    pun.incidents == "court" and L.RU_INC_COURT or L.RU_INC_DIRECT,
    pun.trial and L.RU_TRIAL_ON or L.RU_TRIAL_OFF,
    L.RU_NEVER_GM,
  })
  local closed = {}
  if s.tax.on then
    closed[1] = L.RU_OUT_TAX
  else
    for _, place in ipairs(Ru.CLOSABLE) do
      if pun.closed[place] then closed[#closed + 1] = L["PLACE_" .. place:upper()] end
    end
    closed = { #closed > 0 and L.RU_OUT_CLOSES:format(table.concat(closed, ", ")) or L.RU_OUT_NOTHING }
  end
  part(L.RU_OPTOUT, { L.RU_OUT_ANY, closed[1], L.RU_OUT_WAIT })
  out.closes = closed[1]
  local last = math.max(pun.t or 0, changed or 0, (s.gov and s.gov.at) or 0)
  out.changed = last > 0 and last or nil
  return out
end
