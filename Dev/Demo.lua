-- The demo guild: after its checks, /gtf test fills a pretend guild that looks lived in, takes its pictures with it
-- (Dev/SelfTest.lua) and leaves it open to look around in, until /gtf test off or a /reload (Dev/Sandbox.lua).
-- Twenty members with classes; a cup half played, ladder duels and a deathroll; a fishing contest, hidden traitors, a
-- survival race, a treasure hunt, a transmog contest and a meet-up; members at the stocks; a rule change, a Mak'gora, a poll and the charter;
-- the tax, a vault visit and requests; deeds and the mascot; crafters and their requests; the officers' own events in
-- the Calendar.
-- It is made with the same calls and pretend members' ops as the self-test: nothing leaves the client, and nothing is
-- said in guild chat. Pretend places stand in for the hunt's clues and the run's checkpoints (they are never reached).
local _, ns = ...
local D, Pe, SB = ns.GuildData, ns.Peers, ns.Sandbox
local Demo = {}
ns.Demo = Demo

-- { name, rank, class }: ranks as Dev/Sandbox.lua's (1 Officer, 2 Veteran, 3 Member, 4 Trial).
Demo.MEMBERS = {
  { "Mirelle", 1, "PRIEST" }, { "Thandrel", 1, "MAGE" }, { "Korgath", 2, "WARRIOR" }, { "Brakka", 2, "SHAMAN" },
  { "Sylvaris", 2, "DRUID" }, { "Fenwick", 3, "PALADIN" }, { "Grimbold", 3, "WARRIOR" }, { "Vexa", 3, "WARLOCK" },
  { "Pipwick", 3, "MAGE" }, { "Durgan", 3, "HUNTER" }, { "Lunara", 3, "PRIEST" }, { "Tazzik", 3, "ROGUE" },
  { "Elowen", 3, "HUNTER" }, { "Hilda", 3, "SHAMAN" }, { "Bramwell", 3, "PALADIN" }, { "Odo", 4, "ROGUE" },
  { "Morvek", 4, "WARLOCK" }, { "Kessa", 4, "DRUID" }, { "Nyx", 4, "ROGUE" },
}
-- Who is offline once it is filled (they took part before), and who is far away (face to face, SPEC decision 72).
Demo.OFFLINE = { "Durgan", "Hilda", "Morvek" }
Demo.FAR = { "Tazzik", "Elowen", "Bramwell" }

local function g() return D:Current() end
local function full(name) return Pe:Full(name) end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Made-up places in Elwynn Forest (the hunt's clues, the run's checkpoints).
local function place(x, y, text) return { x = x, y = y, i = 0, z = "Elwynn Forest", text = text } end

local function newestGame(kind)
  for _, x in ipairs(ns.Games.List(g())) do if x.ga.kind == kind and not x.ga.st then return x.id end end
end

---------------------------------------------------------------------------
-- Each part (c: the self-test's check, so it can wait for the pretend members' addons)
---------------------------------------------------------------------------
local parts = {}

-- The guild's motto, beside its name in the window's title band (SPEC decisions 68 and 76).
parts[#parts + 1] = { "the guild's motto", function(c)
  ns.Sync:ChangeSettings(function(s) s.theme.motto = "Duel hard, pay your Marks" end)
  return c:Until(function() return D:Settings().theme.motto ~= nil end, 3)
end }

parts[#parts + 1] = { "ladder duels and the crown", function(c)
  local Du = ns.Duels
  for _, x in ipairs({ { "Korgath", "Odo" }, { "Brakka", "Pipwick" }, { "Sylvaris", "Grimbold" },
    { "Korgath", "Brakka" }, { "Thandrel", "Vexa" }, { "Tazzik", "Nyx" }, { "Korgath", "Sylvaris" } }) do
    local a, b = Pe:Get(x[1]), Pe:Get(x[2])
    local before = count(g().duels)
    a.duel:Challenge(b.name)
    c:Until(function() local ch = a.duel:Game() return ch and ch.st == "on" end, 3)
    Pe:Duel(a.name, b.name)
    c:Until(function() return count(g().duels) > before end, 3)
  end
  local real = Du.ch
  Du.ch = nil
  if Du:Challenge(full("Korgath")) then
    c:Until(function() local ch = Du:Game() return ch and ch.st == "on" end, 3)
    Pe:Duel(full("Korgath"), ns.Self())
  end
  Du.ch = real
  return #Du.Ladder(g()) >= 8
end }

-- Last season's ladder, for Records (SPEC decision 52): duels dated then, in the demo guild's own copy only.
parts[#parts + 1] = { "last season's ladder, in Records", function()
  local Du = ns.Duels
  local last = Du.Season(D:Settings().season, Du.Now(g()).from - 1)
  g().duels = g().duels or {}
  for i, x in ipairs({ { "Brakka", "Korgath" }, { "Brakka", "Sylvaris" }, { "Vexa", "Odo" }, { "Brakka", "Vexa" },
    { "Sylvaris", "Pipwick" }, { "Vexa", "Thandrel" } }) do
    g().duels["Demo/past." .. i] = { w = full(x[1]), l = full(x[2]), t = last.from + i * 86400 }
  end
  return #Du.Seasons(g()) > 0
end }

parts[#parts + 1] = { "a cup, half played", function(c)
  local Cu = ns.Cup
  if not Cu.Open("Midsummer Cup", "single", 1, 10, 50, "now") then return false end
  local _, id = Cu.Current(g())
  for _, n in ipairs({ "Korgath", "Brakka", "Sylvaris", "Thandrel", "Tazzik", "Grimbold", "Vexa", "Elowen" }) do
    Pe:Do(n, { k = "cup_join", id = id, on = true })
  end
  c:Until(function() return #Cu.Joined(g().cups[id]) == 8 end, 3)
  if not Cu.Go(id) then return false end
  c:Until(function() local cup = Pe:Get("Elowen").g.cups[id] return cup and cup.seeds ~= nil end, 3)
  -- The first round: the name first in order wins.
  local live = Cu.Live((Cu.Build(g().cups[id])))
  for _, mt in ipairs(live) do
    local w, l = mt.a, mt.b
    if l < w then w, l = l, w end
    Pe:Duel(w, l)
  end
  return c:Until(function() return count(g().cups[id].d) == #live end, 3)
end }

parts[#parts + 1] = { "a deathroll in the middle", function(c)
  local DR, me = ns.Deathroll, ns.Self()
  local real = DR.game
  DR.game = nil
  if not DR:Challenge(full("Brakka"), 10, "gold", 1000) then DR.game = real return false end
  c:Until(function() return DR:Turn() ~= nil end, 3)
  -- Three of our rolls (high ones), then it is left as it is: a game still on.
  local mine = 0
  for _ = 1, 30 do
    local game = DR:Game()
    if not game or game.st == "over" or mine >= 3 then break end
    local whose, max = DR:Turn()
    if whose == "me" then
      ns.Dice:Seen(me, math.max(2, math.floor(max * 0.7)), 1, max)
      mine = mine + 1
    end
    c:Wait(0.1)
  end
  return DR:Game() ~= nil
end }

parts[#parts + 1] = { "a fishing contest", function(c)
  local Gm = ns.Games
  if not Gm.Open("derby", time() - 1800, 120, 25) then return false end
  local id = newestGame("derby")
  c:Until(function() return Pe:Get("Odo").g.games and Pe:Get("Odo").g.games[id] ~= nil end, 3)
  Gm.Join(id, true)
  local catch = { Korgath = 14, Elowen = 11, Durgan = 9, Lunara = 6, Odo = 4, Pipwick = 2, Kessa = 1 }
  for n, fish in pairs(catch) do
    Pe:Do(n, { k = "game_join", id = id, on = true })
    Pe:Do(n, { k = "game_rep", id = id, n = fish })
  end
  return c:Until(function() return #Gm.Scores(g(), g().games[id], id) >= 7 end, 3)
end }

parts[#parts + 1] = { "hidden traitors, on its second day", function(c)
  local Gm, Tr = ns.Games, ns.Traitors
  if not Gm.Open("traitors", time(), nil, 0) then return false end
  local id = newestGame("traitors")
  local players = { "Mirelle", "Thandrel", "Korgath", "Sylvaris", "Vexa", "Pipwick", "Lunara", "Tazzik", "Bramwell" }
  for _, n in ipairs(players) do Pe:Do(n, { k = "game_join", id = id, on = true }) end
  c:Until(function() return count(Gm.Joined(g(), g().games[id])) == #players end, 3)
  if not Tr.Deal(id, 2) then return false end
  local deal = Tr.Store().deals[id]
  local traitors, faithful = {}, {}
  for _, n in ipairs(players) do
    local f = full(n)
    if deal[f] == "traitor" then traitors[#traitors + 1] = f else faithful[#faithful + 1] = f end
  end
  -- Night 1: a murder. The round table banishes one of the Faithful by mistake. Night 2: another murder.
  local function night(r, victim)
    Tr.Night(id)
    for _, t in ipairs(traitors) do Pe:FromPeer(Pe:Get(t), ns.Self(), "TRM", { id = id, r = r, v = victim }) end
    c:Until(function() return Tr.Picked(id, r) == #traitors end, 3)
    Tr.Morning(id)
  end
  night(1, faithful[1])
  for i, n in ipairs(players) do
    local f = full(n)
    if f ~= faithful[1] then
      Pe:Do(n, { k = "tr_vote", id = id, r = 1, on = i % 3 == 0 and traitors[1] or faithful[2] })
    end
  end
  c:Until(function() return (Tr.Tally(g().games[id], 1)[1] or {}).n ~= nil end, 3)
  c:Wait(0.3)
  Tr.Banish(id)
  night(2, faithful[3])
  local ga = g().games[id]
  return ga.dawn and ga.dawn[2] ~= nil and not ga.st
end }

parts[#parts + 1] = { "a survival race", function(c)
  local Gm = ns.Games
  local stops = { place(42.1, 65.8, "Goldshire"), place(34.6, 52.0, "Mirror Lake"), place(24.3, 74.6, "Westbrook"),
    place(83.1, 69.4, "Eastvale"), place(74.0, 51.7, "Tower of Azora") }
  if not Gm.Open("gnomes", time() - 600, 60, 10, { clues = stops, lv = 10 }) then return false end
  local id = newestGame("gnomes")
  local runs = { Pipwick = 4, Nyx = 3, Kessa = 2, Odo = 2, Morvek = 1 }
  for n, reached in pairs(runs) do
    Pe:Do(n, { k = "game_join", id = id, on = true, lv = 8 })
    for cp = 1, reached do Pe:Do(n, { k = "game_rep", id = id, c = cp }) end
  end
  Pe:Do("Odo", { k = "game_rep", id = id, dead = true })
  return c:Until(function() return #Gm.Scores(g(), g().games[id], id) == 5 end, 3)
end }

parts[#parts + 1] = { "a treasure hunt", function(c)
  local Gm = ns.Games
  local clues = { place(41.7, 89.2, "Where the Defias hide their wine"), place(48.5, 41.9, "Under Northshire's falls"),
    place(64.2, 56.5, "The tower on the lake"), place(79.8, 68.1, "The last farm before Redridge") }
  if not Gm.Open("hunt", time() - 3600, 240, 15, { clues = clues }) then return false end
  local id = newestGame("hunt")
  for n, found in pairs({ Lunara = { 1, 2 }, Pipwick = { 3 }, Elowen = {} }) do
    Pe:Do(n, { k = "game_join", id = id, on = true })
    for _, i in ipairs(found) do Pe:Do(n, { k = "game_rep", id = id, c = i }) end
  end
  return c:Until(function() return Gm.Finder(g().games[id], 3) ~= nil end, 3)
end }

parts[#parts + 1] = { "a transmog contest", function(c)
  local Gm = ns.Games
  if not Gm.Open("fashion", time() - 1200, 180, 0) then return false end
  local id = newestGame("fashion")
  local walk = { "Vexa", "Sylvaris", "Bramwell", "Lunara", "Tazzik" }
  for _, n in ipairs(walk) do Pe:Do(n, { k = "game_join", id = id, on = true }) end
  c:Until(function() return #Gm.Scores(g(), g().games[id], id) == #walk end, 3)
  local votes = { Mirelle = "Vexa", Thandrel = "Vexa", Korgath = "Sylvaris", Brakka = "Vexa", Grimbold = "Bramwell",
    Pipwick = "Sylvaris", Elowen = "Lunara", Odo = "Vexa", Kessa = "Sylvaris", Nyx = "Tazzik" }
  for n, on in pairs(votes) do Pe:Do(n, { k = "game_vote", id = id, on = full(on) }) end
  return c:Until(function() local s = Gm.Scores(g(), g().games[id], id)[1] return s and s.v == 4 end, 3)
end }

parts[#parts + 1] = { "a meet-up in ten minutes", function(c)
  local Gm = ns.Games
  local spot = ns.Punish.Here() or place(62.1, 75.3, nil)
  spot.text = nil
  if not Gm.Open("flash", time() + 600, nil, 0, { spot = spot }) then return false end
  local id = newestGame("flash")
  for _, n in ipairs({ "Mirelle", "Fenwick", "Hilda", "Odo", "Kessa", "Nyx" }) do
    Pe:Do(n, { k = "game_join", id = id, on = true })
  end
  return c:Until(function() return count(Gm.Joined(g(), g().games[id])) == 6 end, 3)
end }

parts[#parts + 1] = { "the stocks", function(c)
  local St = ns.Stocks
  c:Until(function() return St.Punishable(g(), ns.Players:Of(full("Pipwick"))) end, 3)
  St.Sentence(full("Korgath"), "stocks", 30, "Pulled the whole of Blackrock Depths")
  local s = St.List(g())[1]
  if not s then return false end
  St.Tomato(s.id)
  for n, times in pairs({ Mirelle = 3, Brakka = 5, Sylvaris = 2, Pipwick = 1, Odo = 4, Elowen = 2 }) do
    for _ = 1, times do Pe:Do(n, { k = "tomato", id = s.id }) end
  end
  St.Sentence(full("Grimbold"), "service", nil, "Ate the raid's fish feast", { q = 10 })
  local svc = St.List(g())[1]
  c:Until(function() local p = Pe:Get("Grimbold") return p.g.sentences and p.g.sentences[svc.id] ~= nil end, 3)
  Pe:Do("Grimbold", { k = "stk", id = svc.id, n = 4 })
  St.Sentence(full("Odo"), "dunce", nil, "Pulled with the boss still on cooldown")
  St.Sentence(full("Pipwick"), "curse", nil, "Called murlocs ugly", { c = "murloc" })
  return c:Until(function() return (g().sentences[s.id].tom or {})[full("Brakka")] == 5 end, 3)
end }

-- The rest of the punishments (every one has its scene): the Wheel, a walk of shame, the Jingle, a servant, tribute
-- and a trial by combat demanded. The Jingle and the Servant start switched off: they are switched on here.
parts[#parts + 1] = { "every other punishment", function(c)
  local St = ns.Stocks
  ns.Sync:ChangeSettings(function(s) s.off["p:radio"], s.off["p:servant"] = false, false end)
  c:Until(function() return D:On("p:radio") and D:On("p:servant") end, 3)
  c:Wait(0.6)
  St.Sentence(full("Tazzik"), "wheel", 10, "Stood in the fire, twice")
  St.Sentence(full("Sylvaris"), "walk", nil, "Lost the raid on the way", { z = { "Goldshire", "Stormwind City" } })
  St.Sentence(full("Lunara"), "radio", 30, "Sang in voice chat during the boss")
  St.Sentence(full("Bramwell"), "servant", nil, "Lazy on raid night")
  St.Sentence(full("Vexa"), "idol", nil, "Rude to the healers")
  St.Sentence(full("Elowen"), "dunce", nil, "Rolled need on everything")
  local trial
  for _, s in ipairs(St.List(g())) do if s.se.to == full("Elowen") then trial = s.id end end
  if trial then
    c:Until(function() local p = Pe:Get("Elowen") return p.g.sentences and p.g.sentences[trial] ~= nil end, 3)
    Pe:Do("Elowen", { k = "trial", id = trial })
  end
  local kinds = {}
  for _, s in ipairs(St.List(g())) do kinds[s.pun] = true end
  return kinds.walk and kinds.radio and kinds.servant and kinds.idol
end }

-- A high roll and a lottery under way (their scenes in Gambling).
parts[#parts + 1] = { "a high roll and a lottery", function(c)
  local RO, RA, me = ns.RollOff, ns.Raffle, ns.Self()
  if not RO:Start(100) then return false end
  local _, id = RO:Current()
  for _, n in ipairs({ "Mirelle", "Korgath", "Vexa" }) do Pe:Do(n, { k = "rolloff_join", id = id }) end
  RO:Join(id)
  c:Until(function() local ro = RO:Current() return ro and ro.j[full("Vexa")] ~= nil end, 3)
  RO:Go(id)
  c:Until(function() local ro = RO:Current() return ro and ro.st == "rolling" end, 3)
  ns.Dice:Seen(me, 64, 1, 100)
  Pe:Do("Mirelle", { k = "rolloff_roll", id = id, v = 88 })
  Pe:Do("Korgath", { k = "rolloff_roll", id = id, v = 23 })
  RA:Start("Swift Mistsaber", 2, 20, "Sun 20:00")
  local rid
  for _, item in ipairs(RA:List()) do if item.ra.prize == "Swift Mistsaber" then rid = item.id end end
  if rid then
    for n, k in pairs({ Fenwick = 2, Odo = 3, Lunara = 1, Brakka = 4 }) do Pe:Do(n, { k = "raffle_buy", id = rid, n = k }) end
  end
  return c:Until(function() return #RO:Rolls(RO:Current()) >= 3 end, 3) and rid ~= nil
end }

-- Bingo and a gift exchange (the two guild games the others leave out).
parts[#parts + 1] = { "bingo and a gift exchange", function(c)
  local Gm, Sa, me = ns.Games, ns.Santa, ns.Self()
  if not Gm.Open("bingo", time() - 900, 90, 5) then return false end
  local bid = newestGame("bingo")
  Gm.Join(bid, true)
  for _, n in ipairs({ "Hilda", "Bramwell", "Lunara" }) do Pe:Do(n, { k = "game_join", id = bid, on = true }) end
  local card = Gm.Card(bid, me) or {}
  for pos = 5, 7 do if card[pos] and card[pos] ~= "free" then ns.Seen.Fire(card[pos]) end end
  if not Gm.Open("santa", time(), nil, 0, { rv = time() + 3 * 86400 }) then return false end
  local sid = newestGame("santa")
  Gm.Join(sid, true)
  for _, n in ipairs({ "Mirelle", "Korgath", "Odo", "Elowen" }) do Pe:Do(n, { k = "game_join", id = sid, on = true }) end
  c:Until(function() return count(Gm.Joined(g(), g().games[sid])) == 5 end, 3)
  return Sa.Draw(sid) and true or false
end }

-- Assassins under way, with your secret target (shown on the PvP page when you show it).
parts[#parts + 1] = { "Assassins, with your target", function(c)
  local As = ns.Assassins
  if not As.Open() then return false end
  local _, id = As.Current(g())
  for _, n in ipairs({ "Mirelle", "Korgath", "Sylvaris", "Tazzik" }) do Pe:Do(n, { k = "asn_join", id = id, on = true }) end
  As.Join(id, true)
  c:Until(function() return #As.Joined(g().assassins[id]) == 5 end, 3)
  return As.Go(id) and As.Target(id) ~= nil
end }

local function motionOp(kind, extra)
  local op = { k = "motion", kind = kind, why = "", m = 20, gm = ns.Self() }
  for _, k in ipairs(D.NUMBER_KEYS) do if k ~= "jury" then op[k] = D:Number(k) end end
  for k, v in pairs(extra or {}) do op[k] = v end
  return op
end

parts[#parts + 1] = { "the setup: the guild votes on a Warcouncil of elders", function(c)
  local Co = ns.Council
  Pe:Do("Thandrel", motionOp("setup", { setup = "warcouncil", sits = "elders", why = "Let the old hands lead with you" }))
  c:Until(function() return Co.Motions(g(), nil, "setup")[1] ~= nil end, 3)
  local s = Co.Motions(g(), nil, "setup")[1]
  if not s then return false end
  for _, n in ipairs({ "Mirelle", "Korgath", "Lunara" }) do Pe:Do(n, { k = "motion_sec", id = s.id }) end
  for n, on in pairs({ Thandrel = true, Mirelle = true, Korgath = false, Lunara = true, Pipwick = false, Hilda = true }) do
    Pe:Do(n, { k = "motion_vote", id = s.id, on = on })
  end
  return c:Until(function() return Co.Motion(g(), s.id).cast >= 5 end, 3)
end }

parts[#parts + 1] = { "the Guild Master election (stand on the 1st to the 4th, vote on the 5th to the 7th)", function(c)
  local Co = ns.Council
  SB:Govern("democracy", Demo.MEMBERS, { elect = true })
  c:Until(function() return SB:Governed("democracy") and Co.Elects(g()) end, 4)
  local e = Co.Election(g(), Co.Month(Co.Now()))
  if e.phase ~= "stand" and e.phase ~= "vote" then return true end
  local m = Co.Month(Co.Now())
  if e.phase == "stand" then
    Pe:Do("Thandrel", { k = "elect_run", m = m, line = "Raids on time, loot by the rules" })
    Pe:Do("Korgath", { k = "elect_run", m = m, line = "More duels, fewer meetings" })
    return c:Until(function() return #Co.Election(g(), m).cands >= 3 end, 3)
  end
  -- (Only who stood on the 1st to the 4th is on the ballot: here, the sitting Guild Master.)
  for _, n in ipairs({ "Mirelle", "Brakka", "Odo" }) do
    Pe:Do(n, { k = "elect_vote", m = m, on = ns.Self() })
  end
  return true
end }

parts[#parts + 1] = { "the council: a poll, the charter, a rule change, a strike and a Mak'gora", function(c)
  local Co = ns.Council
  Co.WriteCharter({ "Be kind in guild chat.", "Loot by need, then greed. Ask if unsure.",
    "Tomatoes are thrown with love.", "Raid nights: Thursday and Sunday, 20:00 server time." })
  for _, n in ipairs({ "Mirelle", "Thandrel", "Korgath", "Fenwick", "Lunara", "Hilda", "Elowen" }) do
    Pe:Do(n, { k = "charter_ok", v = g().charter.v })
  end
  Pe:Do("Mirelle", { k = "poll", q = "Which night for the Molten Core run?", ch = { "Thursday", "Saturday", "Sunday" }, days = 3 })
  c:Until(function() return Co.Polls(g())[1] ~= nil end, 3)
  local poll = Co.Polls(g())[1]
  local votes = { Thandrel = 1, Korgath = 3, Brakka = 1, Sylvaris = 2, Fenwick = 1, Grimbold = 3, Vexa = 1, Pipwick = 2,
    Lunara = 1, Tazzik = 3, Elowen = 1, Bramwell = 2, Odo = 1, Kessa = 3 }
  for n, on in pairs(votes) do Pe:Do(n, { k = "poll_vote", id = poll.id, on = on }) end
  -- A rule change (fewer polls), seconded and being voted on.
  Pe:Do("Brakka", motionOp("rule", { r = "poll", v = { 1, 2 }, why = "Fewer polls, please" }))
  c:Until(function() return Co.Motions(g(), nil, "rule")[1] ~= nil end, 3)
  local rule = Co.Motions(g(), nil, "rule")[1].id
  for _, n in ipairs({ "Korgath", "Sylvaris", "Vexa" }) do Pe:Do(n, { k = "motion_sec", id = rule }) end
  for n, on in pairs({ Brakka = true, Korgath = true, Sylvaris = false, Vexa = true, Odo = false, Lunara = true }) do
    Pe:Do(n, { k = "motion_vote", id = rule, on = on })
  end
  Co.Strike(full("Nyx"), "No-show on raid night", 7)
  -- A Mak'gora: Brakka challenges you, and waits for your answer.
  local brakka = full("Brakka")
  Pe:Do("Brakka", { k = "player", id = "#b7a44a01", c = { brakka }, m = brakka })
  Pe:Do("Brakka", { k = "motion", kind = "mak", why = "Thursday raids, or we settle it with a duel", m = 19, gm = ns.Self() })
  return c:Until(function() return Co.Poll(g(), poll.id).rows[1].n >= 6 end, 3)
end }

parts[#parts + 1] = { "a court case, judged guilty", function(c)
  local Ct = ns.Court
  if not Ct.Charge(full("Grimbold"), "Ninja-looted the Tome of Polymorph", "dunce") then return false end
  local case
  c:Until(function() case = Ct.Cases(g())[1] return case ~= nil end, 3)
  if not case then return false end
  Pe:Do("Grimbold", { k = "court_def", id = case.id, text = "It was for my alt." })
  for _, x in ipairs({ { "Mirelle", true }, { "Thandrel", true }, { "Lunara", true }, { "Hilda", false } }) do
    Pe:Do(x[1], { k = "court_jury", id = case.id, on = true })
    Pe:Do(x[1], { k = "court_vote", id = case.id, guilty = x[2] })
  end
  c:Until(function() local s = Ct.Case(g(), case.id) return s and #s.jurors == 4 end, 3)
  return Ct.Close(case.id) and Ct.Case(g(), case.id).verdict == "guilty"
end }

parts[#parts + 1] = { "the treasury: the tax, a vault visit and requests", function(c)
  local Tx, Pu = ns.Treasury, ns.Purse
  ns.Sync:ChangeSettings(function(s) s.tax = { on = true, per = "month", lv = 1, amt = { [2] = 5, [3] = 10, [4] = 2 }, ex = {} } end)
  c:Until(function() return Pe:Get("Odo").g.settings.tax and Pe:Get("Odo").g.settings.tax.on end, 4)
  Tx.Charge()
  Tx.Visit({ { kind = "m", type = "deposit", name = full("Fenwick"), amount = 40 * Pu.GOLD, ago = 0 },
    { kind = "m", type = "deposit", name = full("Thandrel"), amount = 25 * Pu.GOLD, ago = 0 },
    { kind = "m", type = "deposit", name = full("Lunara"), amount = 10 * Pu.GOLD, ago = 0 },
    { kind = "i", type = "withdraw", name = full("Kessa"), id = 2589, nm = "Linen Cloth", count = 20, tab = 1, ago = 0 },
    { kind = "i", type = "deposit", name = full("Elowen"), id = 4234, nm = "Heavy Leather", count = 12, tab = 1, ago = 0 } })
  Pe:Do("Odo", { k = "req", item = "Major Healing Potion", iid = 13446, n = 5, why = "For Thursday's raid" })
  Pe:Do("Kessa", { k = "req", item = "Runecloth", iid = 14047, n = 40, why = "Leveling Tailoring" })
  return c:Until(function() return #Tx.Requests(g()) >= 2 end, 3)
end }

parts[#parts + 1] = { "the chronicle: deeds and the mascot", function(c)
  local Ch = ns.Chronicle
  Ch.Write(full("Korgath"), "Tanked Ragnaros with a fishing pole equipped", 0)
  Ch.Write(full("Lunara"), "Resurrected the whole raid after the wipe on Onyxia", 0)
  Ch.Write(full("Pipwick"), "Won the gnome run without a single death", 0)
  Pe:Do("Fenwick", { k = "lvl", lv = 60 })
  Pe:Do("Elowen", { k = "feed", n = 9 })
  Pe:Do("Odo", { k = "feed", n = 6 })
  return c:Until(function() return Ch.Mascot(g()).fed >= 15 end, 3)
end }

parts[#parts + 1] = { "professions: crafters and requests", function(c)
  local Pr = ns.Professions
  local REAPER, FLASK, HEALING, ROBE = 16994, 17635, 17556, 18458
  Pe:Do("Fenwick", { k = "pro", c = { ["164"] = { n = "Blacksmithing", i = 136241, r = 300, m = 300, rc = { REAPER }, rt = time() } } })
  Pe:Do("Sylvaris", { k = "pro", c = { ["171"] = { n = "Alchemy", i = 136240, r = 300, m = 300, rc = { FLASK, HEALING }, rt = time() } } })
  Pe:Do("Vexa", { k = "pro", c = { ["197"] = { n = "Tailoring", i = 136249, r = 295, m = 300, rc = { ROBE }, rt = time() } } })
  Pe:Do("Odo", { k = "craft", rid = HEALING, what = "Major Healing Potion", n = 5, tip = 2, p = "gold" })
  Pe:Do("Kessa", { k = "craft", rid = ROBE, what = "Robe of the Void", n = 1, tip = 10, p = "gold" })
  return c:Until(function() return count(g().crafting) >= 2 and #Pr.WhoKnows(g(), HEALING) > 0 end, 3)
end }

parts[#parts + 1] = { "the calendar: the officers' own events", function(c)
  local When = ns.Games.When
  Pe:Do("Mirelle", { k = "cal_add", name = "Raid night: Molten Core", at = When("Fri 20:00"),
    line = "Fire resistance gear and flasks. Meet at the Blackrock Mountain stone." })
  Pe:Do("Thandrel", { k = "cal_add", name = "Guild meeting", at = When("Sun 19:00"),
    line = "The new ranks and the tax, in the guild hall." })
  Pe:Do("Mirelle", { k = "cal_add", name = "Dungeon night", at = When("Tue 19:30"), line = "Stratholme and Scholomance." })
  return c:Until(function() return count(g().calendar) >= 3 end, 3)
end }

parts[#parts + 1] = { "the rules: a member who opted out of punishments", function(c)
  Pe:Do("Nyx", { k = "optout", on = true })
  return c:Until(function() return ns.Rules.Out(g(), full("Nyx")) end, 3)
end }

---------------------------------------------------------------------------
-- Filling
---------------------------------------------------------------------------
-- Starts the demo guild and fills it. Returns the parts that did not work (their names), so the self-test can say.
function Demo.Fill(c)
  SB:Start(Demo.MEMBERS)
  SB.demo = true
  local bad = {}
  for _, part in ipairs(parts) do
    -- Each part in a coroutine of its own: its waits (c:Until) are passed on to the self-test's step. (The game's Lua
    -- cannot wait inside a pcall: "attempt to yield across metamethod/C-call boundary".)
    local co = coroutine.create(part[2])
    local ok, done = coroutine.resume(co, c)
    while ok and coroutine.status(co) ~= "dead" do
      ok, done = coroutine.resume(co, coroutine.yield(done))
    end
    if not ok or not done then bad[#bad + 1] = part[1] .. (ok and "" or (": " .. tostring(done))) end
  end
  for _, n in ipairs(Demo.OFFLINE) do Pe:SetOnline(n, false) end
  for _, n in ipairs(Demo.FAR) do SB:Near(n, false) end
  ns:Fire("ROSTER")
  return bad
end

-- What a page can show on the panel's right, for the pictures: { { page, part, pick = function(page) } }.
function Demo.Picks()
  local out = {}
  -- The scenes that are not a list's row (SPEC decision 60): the duels, the high roll, the lottery and the Council's.
  for _, x in ipairs({ { "arena", "duels" }, { "tavern", "rolloff" }, { "tavern", "raffles" }, { "council", "charter" },
    { "council", "court" } }) do
    out[#out + 1] = { page = x[1], part = x[2], what = x[2] .. "'s scene", pick = function() end }
  end
  for _, kind in ipairs({ "derby", "traitors", "gnomes", "hunt", "fashion", "flash" }) do
    local id = newestGame(kind)
    if id then
      out[#out + 1] = { page = "games", part = "game", what = kind, pick = function(page) page.sel = id end }
    end
  end
  for _, s in ipairs(ns.Stocks.List(g())) do
    if ns.Stocks.Open(s) then
      out[#out + 1] = { page = "stocks", part = "serving", what = s.pun,
        pick = function(page) page.View({ kind = "sentence", id = s.id }) end }
    end
  end
  out[#out + 1] = { page = "arena", part = "assassins", what = "your secret target", pick = function(page) page.asShow = true end }
  -- Forms and details on the panel's right (SPEC decisions 48, 59).
  local function view(page, part, what, v) out[#out + 1] = { page = page, part = part, what = what, pick = function(p) p.View(v) end } end
  view("arena", "duels", "a player to challenge", { kind = "player", key = ns.Players:Of(full("Korgath"), g()) })
  view("arena", "cup", "start a tournament", { kind = "newcup" })
  view("games", "game", "start a game", { kind = "start" })
  view("tavern", "raffles", "start a raffle", { kind = "newraffle" })
  local rq = ns.Treasury.Requests(g())[1]
  if rq then view("treasury", "req", "an item request", { kind = "request", id = rq.id }) end
  view("council", "votes", "open a poll", { kind = "poll" })
  local today = ns.Agenda.DayStart(time())
  view("calendar", "events", "today", { kind = "day", at = today, key = "day:" .. today })
  view("calendar", "events", "add an event", { kind = "add" })
  view("stocks", "serving", "hand out a punishment", { kind = "form" })
  -- A player card over Home, and your options, Home's last feature (SPEC decisions 52, 57).
  out[#out + 1] = { page = "home", what = "a player card", pick = function() ns.Card:Show(full("Korgath")) end }
  out[#out + 1] = { page = "home", what = "your options", pick = function() ns.Card:Options() end }
  return out
end

-- /gtf test off: the demo guild is closed, and the real guild is back.
function Demo.Off()
  if not SB.active or not SB.demo then return false end
  SB:Stop()
  return true
end
