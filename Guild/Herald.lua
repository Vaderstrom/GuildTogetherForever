-- Discord through the Herald (SPEC §9.2). Decided 29 Oct 2026: Guild Together is a plugin of Addon Webhooks for
-- Discord, the app Journey Together posts with (its docs/PLUGINS.md, contract 1). WoW addons cannot reach the
-- network: the Herald's addon writes ready-made posts into GuildTogetherForeverDB.webhooks on logout and /reload, and
-- the app (on the Herald's computer) posts them. The app's flows decide which kinds go to which channel
-- (Webhooks/webhooks.json names the kinds). Only the Herald's addon writes the guild's group, so everything is posted
-- once.
--   News of the guild's moments: the guild chat lines of Guild/Announce.lua, kept while the Herald's addon applies
--   ops (fresh or caught up after a login), in the Herald's account-wide saved data (ns.db.news[guild id]).
--   The Chronicle's: deeds, memorials, finished weeks' Gazettes and last month's Rolling Pin awards (Guild/Chronicle.lua).
local _, ns = ...
local L, D, R, P = ns.L, ns.GuildData, ns.Roster, ns.Players

local He = {}
ns.Herald = He

He.FORMAT = 1
He.KEEP = 40              -- news items in the outbox, newest first
He.AGE = 14 * 86400       -- older moments are not news
He.KINDS = { "stocks", "arena", "fame", "tavern", "games", "council" }

-- Which kind of post each op's guild chat line is (a tomato is not news).
local KIND = { sentence = "stocks", spin = "stocks", reroll = "stocks", pardon = "stocks", bail = "stocks",
  trial = "stocks", tribute = "stocks",
  crown_ch = "arena", crown_no = "arena", duel = "arena", cup_end = "arena", lead_cup = "arena",
  raffle_draw = "tavern", deathroll = "tavern", rolloff_end = "tavern",
  game = "games", game_end = "games", game_rep = "games",
  charter = "council", poll = "council", court = "council", court_close = "council", elect_done = "council",
  imp_vote = "council", mak_ok = "council", mak_duel = "council",
  tax_run = "council" }

function He.Kind(k)
  if KIND[k] then return KIND[k] end
  if k:sub(1, 6) == "motion" then return "council" end
  if k:sub(1, 3) == "tr_" or k:sub(1, 6) == "santa_" then return "games" end
  return nil
end

-- The Herald: the character the Guild Master chose, while their rank may be Herald; else the Guild Master.
function He.Herald(g)
  local h = g and g.settings and g.settings.herald
  if h and R:Rank(h) ~= nil and D:Can("herald", h, g) then return h end
  for name, rank in pairs(R:All()) do if rank == 0 then return name end end
  return nil
end

-- Is one of this account's characters the Herald?
function He.IsMe(g)
  local h = He.Herald(g)
  return h ~= nil and P:IsMe(P:Of(h, g), g)
end

-- Does this addon keep the news of an op made at time t?
function He.Listening(g, t)
  return ns.db.guilds[g.id] == g and not D.sandbox and time() - t < He.AGE and He.IsMe(g)
end

local function store(g)
  ns.db.news = type(ns.db.news) == "table" and ns.db.news or {}
  ns.db.news[g.id] = type(ns.db.news[g.id]) == "table" and ns.db.news[g.id] or {}
  return ns.db.news[g.id]
end

-- Keeps one moment (the op's key is its id, so it is kept once).
function He.Note(g, a, op, t, n, text)
  local kind = He.Kind(op.k)
  if not kind or not He.Listening(g, t) then return end
  local list, id = store(g), D.Key(a, n)
  for _, x in ipairs(list) do if x.id == id then return end end
  list[#list + 1] = { id = id, kind = kind, time = t, text = text }
  table.sort(list, function(x, y) if x.time ~= y.time then return x.time > y.time end return x.id > y.id end)
  while #list > He.KEEP do table.remove(list) end
end

ns:On("NEWS", function(g, a, op, t, n, text) He.Note(g, a, op, t, n, text) end)

---------------------------------------------------------------------------
-- The outbox
---------------------------------------------------------------------------
-- The guild's group: { name, sub, saved, by, news }.
function He.Build(g, now)
  now = now or time()
  local Ch, Tx = ns.Chronicle, ns.Treasury
  local news = {}
  for _, x in ipairs(store(g)) do news[#news + 1] = { id = x.id, kind = x.kind, time = x.time, text = x.text } end
  local since = now - 30 * 86400
  for _, d in ipairs(Ch.Deeds(g, now)) do
    if d.t >= since and d.t <= now then
      news[#news + 1] = { id = "deed:" .. d.id, kind = "fame", time = d.t,
        text = L.HE_DEED:format(P:Name(d.key, g), d.text), name = d.text }
    end
  end
  for _, m in ipairs(Ch.Memorials(g)) do
    if m.e.t >= since then
      news[#news + 1] = { id = "memorial:" .. m.id, kind = "fame", time = m.e.t, text = Ch.MemorialLine(m.e), name = ns.Display(m.e.name) }
    end
  end
  -- The last two finished weeks' Gazettes.
  local week = Ch.WeekStart(now)
  for i = 1, 2 do
    local z = Ch.Gazette(g, week - i * Ch.WEEK)
    if z.n > 0 or #z.lines > 0 then
      local text = z.mast .. "\n" .. z.headline .. (#z.lines > 0 and ("\n" .. table.concat(z.lines, " ")) or "")
      news[#news + 1] = { id = "gazette:" .. z.week, kind = "fame", time = z.week + Ch.WEEK, text = text, name = z.mast }
    end
  end
  -- Last month's Rolling Pin awards.
  local month = Ch.LastMonth(now)
  local awards = Ch.Awards(g, month)
  if #awards > 0 then
    local lines = { L.HE_AWARDS:format(Tx.PeriodName(month)) }
    for _, x in ipairs(awards) do lines[#lines + 1] = L.CH_AWARD_LINE:format(L["CH_AWARD_" .. x.id:upper()], P:Name(x.key, g), x.text) end
    -- Given at the start of this month (UTC).
    local d = date("!*t", now)
    news[#news + 1] = { id = "awards:" .. month, kind = "fame", time = now - ((d.day - 1) * 86400 + d.hour * 3600 + d.min * 60 + d.sec),
      text = table.concat(lines, "\n"), name = lines[1] }
  end
  table.sort(news, function(x, y) if x.time ~= y.time then return x.time > y.time end return x.id > y.id end)
  while #news > He.KEEP do table.remove(news) end
  local members = 0
  for _ in pairs(R:All()) do members = members + 1 end
  return { name = Ch.GuildName(g), sub = L.HE_SUB:format(ns.Display(He.Herald(g) or ""), members), saved = now,
    by = ns.Self(), news = news }
end

-- Writes (or, when this account is not the Herald, removes) the guild's group in the outbox.
function He.Write(now)
  local g = D:Current()
  if not g or D.sandbox then return false end
  local db = ns.db
  if type(db) ~= "table" then return false end
  local out = db.webhooks
  if type(out) ~= "table" or out.format ~= He.FORMAT or type(out.groups) ~= "table" then
    out = { format = He.FORMAT, groups = {} }
    db.webhooks = out
  end
  if He.IsMe(g) then
    out.groups[g.id] = He.Build(g, now)
    return true
  end
  out.groups[g.id] = nil
  return false
end

ns:RegisterEvent("PLAYER_LOGOUT", function() He.Write() end)

-- Post to Discord now: the outbox is written when the interface reloads.
function He.PostNow()
  if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
end
