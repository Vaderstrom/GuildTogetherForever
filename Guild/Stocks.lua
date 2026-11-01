-- The Stocks (SPEC §6): playful punishments, for every player with Guild Together but the Guild Master (decision 56). Who
-- may hand out each one is set per rank (SPEC §3.2). Every sentence has a reason, a length or a task, and ends by itself; bail (in the purse, to the Treasury) or
-- a pardon ends it early. A sentence belongs to the player, so it follows them to an alt (SPEC §1).
--   sentence  { to, pun, len, why, z, q, c, tr, r, tx }   r: the reason, "tax" or "inc" (an incident; SPEC decision 69);
--                                     tx: for tax, the debt of the period it pays off (Guild/Rules.lua)
--                                     len: minutes (Stocks, Radio, and the Wheel's result); z: the Walk
--                                     of shame's zones; q: Community service's fish; c: the curse ("murloc" or
--                                     "praise"); tr: a trial by combat's id, when its winner picks the sentence;
--                                     ct: a guild court's case, when the court sentences by itself (its runner) or
--                                     a member allowed to give the punishment confirms the verdict (Guild/Court.lua)
--   stk       { id, s, n, i }         the prisoner's own addon: seconds served at the stocks, fish caught, zones reached
--   bail      { id, amt, p }          the prisoner pays bail (or the Radio's buyout) to the Treasury
--   pardon    { id }                  a rank that may pardon
--   tomato    { id }                  thrown at a prisoner in the Stocks
--   spin      { id, r }               the Wheel is spun (a rank that may spin): r, where it landed
--   reroll    { id, r, amt, p }       the prisoner buys one reroll
--   trial     { id }                  the accused demands trial by combat (the sentence is replaced by the duel's)
--   tribute   { id, ok, item }        the Guild Master accepts or scorns a tribute
--   deed      { id }                  a member confirms the Idol's carrier did them a good deed
--   bid       { id, amt, p }          a bid for a servant's hour;  hire { id, amt, p }: the winning bidder pays
--   order     { id, text }            the servant's master gives an order;  odone { id, o }: the servant did it
-- Which sentences are running, and how each ended, is worked out when read, so the order ops arrive in never matters.
local _, ns = ...
local D, Pu = ns.GuildData, ns.Purse
local P, R = ns.Players, ns.Roster

local St = {}
ns.Stocks = St

St.BAIL = { stocks = 20, dunce = 5, wheel = 10, service = 10, walk = 15, curse = 5, radio = 5 }  -- in gold (Marks: × 10)
St.WHEEL = { "stocks", "dunce", "curse", "radio", "service", "walk" }   -- decided 29 Oct 2026
St.TIMED = { stocks = true, radio = true, wheel = true }
St.LEN_MIN, St.LEN_MAX = 5, 240
St.WHY_MAX, St.ORDER_MAX = 80, 80
St.DAY = 86400
St.LAPSE = 7 * 86400   -- a sentence that waits on the prisoner (the stocks, a task, a tribute) lapses after a week
St.AUCTION, St.SERVE = 600, 3600
St.QUOTA, St.QUOTA_MAX = 50, 500   -- fish, when the Wheel lands on Community service without a quota
St.ZONES_MAX, St.ZONE_LEN = 4, 40
St.CURSES = { "murloc", "praise" }

local isPun, onWheel, isCurse = {}, {}, {}
for _, p in ipairs(D.PUNISHMENTS) do isPun[p] = true end
for _, p in ipairs(St.WHEEL) do onWheel[p] = true end
for _, c in ipairs(St.CURSES) do isCurse[c] = true end

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local Clean = ns.Raffle.Clean

-- Bail for a punishment in a purse (nil: no bail).
function St.Bail(pun, purse)
  local gold = St.BAIL[pun]
  if not gold then return nil end
  return purse == "gold" and gold or gold * 10
end

local function get(g, id)
  local all = D.Part(g, "sentences")
  all[id] = all[id] or {}
  return all[id]
end

local function sub(se, name)
  se[name] = se[name] or {}
  return se[name]
end

-- The earliest time per author (ends, deeds): each author's first stays.
local function first(map, author, t) if not map[author] or t < map[author] then map[author] = t end end

local function soundSentence(op)
  if not isPun[op.pun] or not party(op.to) then return false end
  if op.why ~= nil and type(op.why) ~= "string" then return false end
  if St.TIMED[op.pun] and not whole(op.len, St.LEN_MIN, St.LEN_MAX) then return false end
  if (op.pun == "service" or op.q ~= nil) and not whole(op.q, 1, St.QUOTA_MAX) then return false end
  if op.pun == "curse" and not isCurse[op.c] then return false end
  -- The Wheel may carry a route and a quota too, for when it lands on the Walk of shame or Community service.
  if op.pun == "walk" or op.z ~= nil then
    if type(op.z) ~= "table" or #op.z < 1 or #op.z > St.ZONES_MAX then return false end
    for _, z in ipairs(op.z) do if not Clean(z, St.ZONE_LEN) then return false end end
  end
  if op.r ~= nil and op.r ~= "tax" and op.r ~= "inc" then return false end
  if op.r == "tax" and type(op.tx) ~= "string" then return false end
  return (op.tr == nil or type(op.tr) == "string") and (op.ct == nil or type(op.ct) == "string")
end
St.SoundSentence = soundSentence

local function take(se, author, op, t)
  se.by, se.to, se.pun, se.t = author, op.to, op.pun, t
  se.len, se.q, se.c, se.tr, se.ct = tonumber(op.len), tonumber(op.q), op.c, op.tr, op.ct
  se.r, se.tx = op.r, op.r == "tax" and op.tx or nil
  se.why = Clean(op.why, St.WHY_MAX)
  if op.z then
    se.z = {}
    for i, z in ipairs(op.z) do se.z[i] = Clean(z, St.ZONE_LEN) end
  end
  -- Where the sentencer stood: the stocks, while the Guild Master has not set them (decided 29 Oct 2026).
  local sp = op.sp
  if type(sp) == "table" and tonumber(sp.x) and tonumber(sp.y) and tonumber(sp.i) then
    se.sp = { x = tonumber(sp.x), y = tonumber(sp.y), i = tonumber(sp.i), z = Clean(sp.z, St.ZONE_LEN) }
  end
end

---------------------------------------------------------------------------
-- Kinds of op
---------------------------------------------------------------------------
D:Register("sentence", {
  -- Every punishment has a reason (SPEC decision 69): a trial's winner punishing (tr), a court's verdict (ct), unpaid
  -- tax (r "tax", while tax punishments are on), or an incident judged directly (r "inc", when the guild's rules say
  -- incidents are not for the court).
  allowed = function(g, author, op)
    local Ru = ns.Rules
    if not soundSentence(op) or op.to == author then return false end
    -- No punishments at all before a setup is picked, nor in a Free guild (SPEC decision 70).
    local setup, opt = Ru.Setup(g)
    if setup == nil or setup == "free" then return false end
    if op.tr ~= nil then return Ru.Trial(g) end
    if op.ct ~= nil then return (host(op.ct) == author and D:CourtSentences(g)) or D:Can(op.pun, author, g) end
    if op.pun == "trial" and not Ru.Trial(g) then return false end
    if op.r == "tax" then return D:Can(op.pun, author, g) and Ru.TaxPunishments(g) end
    -- An incident judged directly (no reason given: an incident, as sentences were before reasons). In a
    -- Dictatorship whose incidents the duel crown's holder judges, only they may.
    if Ru.Court(g) then return false end
    if setup == "dictatorship" and opt.judge == "crown" then return Ru.Crowned(g, author) and D:On("p:" .. op.pun, g) end
    return D:Can(op.pun, author, g)
  end,
  apply = function(g, author, op, t, n)
    take(get(g, D.Key(author, n)), author, op, t)
    return true
  end,
  copy = function(g) return g.sentences end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, e in pairs(part) do
      if type(id) == "string" and host(id) and type(e) == "table" then
        local se = get(g, id)
        if not se.by and party(e.by) and tonumber(e.t) and soundSentence(e) then take(se, e.by, e, e.t) end
        for _, f in ipairs({ "bail", "pardon", "trial", "deed" }) do
          for name, t in pairs(type(e[f]) == "table" and e[f] or {}) do
            if party(name) and tonumber(t) then first(sub(se, f), name, t) end
          end
        end
        for name, x in pairs(type(e.pr) == "table" and e.pr or {}) do
          if party(name) and type(x) == "table" then
            local mine = sub(sub(se, "pr"), name)
            for _, k in ipairs({ "s", "n", "i" }) do
              if tonumber(x[k]) then mine[k] = math.max(mine[k] or 0, x[k]) end
            end
          end
        end
        for name, n in pairs(type(e.tom) == "table" and e.tom or {}) do
          if party(name) and tonumber(n) then sub(se, "tom")[name] = math.max(se.tom[name] or 0, n) end
        end
        for name, x in pairs(type(e.bids) == "table" and e.bids or {}) do
          local cur = sub(se, "bids")[name]
          if party(name) and type(x) == "table" and tonumber(x.amt) and tonumber(x.t) and (not cur or x.amt > cur.amt) then
            se.bids[name] = { amt = x.amt, t = x.t }
          end
        end
        for key, x in pairs(type(e.orders) == "table" and e.orders or {}) do
          if type(key) == "string" and type(x) == "table" and party(x.by) and type(x.text) == "string" then
            sub(se, "orders")[key] = se.orders[key] or { by = x.by, text = x.text:sub(1, St.ORDER_MAX), t = tonumber(x.t) or 0 }
          end
        end
        for key, t in pairs(type(e.odone) == "table" and e.odone or {}) do
          if type(key) == "string" and tonumber(t) then first(sub(se, "odone"), key, t) end
        end
        for _, f in ipairs({ "spin", "reroll" }) do
          local x = e[f]
          if type(x) == "table" and onWheel[x.r] and party(x.by) and tonumber(x.t) and (not se[f] or x.t < se[f].t) then
            se[f] = { r = x.r, by = x.by, t = x.t }
          end
        end
        if not se.trib and type(e.trib) == "table" and tonumber(e.trib.t) then
          se.trib = { ok = e.trib.ok == true, item = type(e.trib.item) == "string" and e.trib.item:sub(1, 60) or nil, t = e.trib.t }
        end
        if not se.hire and type(e.hire) == "table" and party(e.hire.by) and tonumber(e.hire.t) then
          se.hire = { by = e.hire.by, amt = tonumber(e.hire.amt), t = e.hire.t }
        end
      end
    end
  end,
})

local function onSentence(kind, def)
  local allowed = def.allowed
  def.allowed = function(g, author, op) return host(op.id) ~= nil and allowed(g, author, op) end
  D:Register(kind, def)
end

onSentence("stk", {
  allowed = function(_, _, op)
    return (op.s == nil or whole(op.s, 0, 1e6)) and (op.n == nil or whole(op.n, 0, 1e6)) and (op.i == nil or whole(op.i, 0, 10))
  end,
  apply = function(g, author, op)
    local mine = sub(sub(get(g, op.id), "pr"), author)
    for _, k in ipairs({ "s", "n", "i" }) do
      if op[k] then mine[k] = math.max(mine[k] or 0, op[k]) end
    end
    return true
  end,
})

-- Ends kept per author (the earliest), checked when read: bail and trial count only from the prisoner.
for _, kind in ipairs({ "pardon", "trial", "deed" }) do
  onSentence(kind, {
    allowed = function(g, author)
      if kind == "pardon" then return D:Can("pardon", author, g) end
      -- Trial by combat only while the guild's rules allow it (SPEC decision 69).
      if kind == "trial" then return ns.Rules.Trial(g) end
      return true
    end,
    apply = function(g, author, op, t)
      first(sub(get(g, op.id), kind), author, t)
      return true
    end,
  })
end

-- Paid to the Treasury when made (the amount travels with the op, so every copy charges the same).
local function pays(op) return Pu.IsPurse(op.p) and Pu.ValidAmount(op.amt, op.p) end

onSentence("bail", {
  allowed = function(_, _, op) return pays(op) end,
  apply = function(g, author, op, t, n)
    first(sub(get(g, op.id), "bail"), author, t)
    Pu:Charge(g, D.Key(author, n), author, Pu.TREASURY, op.amt, op.p, "bail", t)
    return true
  end,
})

onSentence("tomato", {
  allowed = function() return true end,
  apply = function(g, author, op, t)
    local se = get(g, op.id)
    sub(se, "tom")[author] = (se.tom[author] or 0) + 1
    if ns.db.guilds[g.id] == g and math.abs(time() - t) < 60 then ns:Fire("TOMATO", op.id, author) end
    return true
  end,
})

onSentence("spin", {
  allowed = function(g, author, op) return onWheel[op.r] and D:Can("spin", author, g) end,
  apply = function(g, author, op, t)
    local se = get(g, op.id)
    if se.spin and se.spin.t <= t then return false end
    se.spin = { r = op.r, by = author, t = t }
    if ns.db.guilds[g.id] == g and math.abs(time() - t) < 60 then ns:Fire("WHEEL", op.id, op.r) end
    return true
  end,
})

onSentence("reroll", {
  allowed = function(_, _, op) return onWheel[op.r] and pays(op) end,
  apply = function(g, author, op, t, n)
    local se = get(g, op.id)
    if se.reroll then return false end
    se.reroll = { r = op.r, by = author, t = t }
    Pu:Charge(g, D.Key(author, n), author, Pu.TREASURY, op.amt, op.p, "bail", t)
    if ns.db.guilds[g.id] == g and math.abs(time() - t) < 60 then ns:Fire("WHEEL", op.id, op.r) end
    return true
  end,
})

onSentence("tribute", {
  allowed = function(g, author, op) return D:InCharge(author, g) and type(op.ok) == "boolean" end,
  apply = function(g, _, op, t)
    local se = get(g, op.id)
    if se.trib then return false end
    se.trib = { ok = op.ok, item = type(op.item) == "string" and op.item:sub(1, 60) or nil, t = t }
    return true
  end,
})

onSentence("bid", {
  allowed = function(_, _, op) return pays(op) end,
  apply = function(g, author, op, t)
    local bids = sub(get(g, op.id), "bids")
    if bids[author] and bids[author].amt >= op.amt then return false end
    bids[author] = { amt = op.amt, t = t }
    return true
  end,
})

onSentence("hire", {
  allowed = function(_, _, op) return pays(op) end,
  apply = function(g, author, op, t, n)
    local se = get(g, op.id)
    if se.hire then return false end
    se.hire = { by = author, amt = op.amt, t = t }
    Pu:Charge(g, D.Key(author, n), author, Pu.TREASURY, op.amt, op.p, "servant", t)
    return true
  end,
})

onSentence("order", {
  allowed = function(_, _, op) return Clean(op.text, St.ORDER_MAX) ~= nil end,
  apply = function(g, author, op, t, n)
    sub(get(g, op.id), "orders")[D.Key(author, n)] = { by = author, text = Clean(op.text, St.ORDER_MAX), t = t }
    return true
  end,
})

onSentence("odone", {
  allowed = function(_, _, op) return type(op.o) == "string" end,
  apply = function(g, _, op, t)
    first(sub(get(g, op.id), "odone"), op.o, t)
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- May the player be punished? Only a player with Guild Together (nothing keeps score of a member without it), and never
-- the Guild Master: none of their characters holds rank 0 now (SPEC decision 56).
function St.Punishable(g, key)
  if not P:HasAddon(key) then return false end
  for _, name in ipairs(P:Chars(key, g)) do if R:Rank(name) == 0 then return false end end
  return true
end

local function byPrisoner(map, key, g)
  local best
  for name, t in pairs(map or {}) do
    if P:Of(name, g) == key and (not best or t < best) then best = t end
  end
  return best
end

local function most(pr, key, g, k)
  local v = 0
  for name, x in pairs(pr or {}) do if P:Of(name, g) == key and x[k] then v = math.max(v, x[k]) end end
  return v
end

-- The servant's auction: the highest bid in time (ties: the earlier), from anyone but the servant.
function St.Winner(g, se, key)
  local best, by
  local close = se.t + St.AUCTION
  for name, x in pairs(se.bids or {}) do
    if P:Of(name, g) ~= key and x.t <= close and (not best or x.amt > best.amt or (x.amt == best.amt and x.t < best.t)) then
      best, by = x, name
    end
  end
  return by, best and best.amt
end

-- The state of a sentence now: { id, se, key (the prisoner), pun (the Wheel's result for the Wheel), st, how, start,
-- ends (time), left (seconds), served/n/i (progress) }. st: "active", "spin" (the Wheel waits for a spin), "tribute"
-- (waits for the tribute), "trial" (waits for the duel), "done" or "void" (a player who may not be punished, or a bad verdict).
function St.State(g, id, se, now)
  now = now or time()
  local s = { id = id, se = se, pun = se.pun, start = se.t }
  if not se.by or not se.pun then s.st = "void" return s end
  local key = P:Of(se.to, g)
  s.key = key
  if not St.Punishable(g, key) then s.st, s.how = "void", "free" return s end
  -- A player who had opted out of punishment is not punished (SPEC decision 69): as of the sentence, or of the court
  -- case or the first sentence it comes from (a case or a sentence already running stays).
  local Ru = ns.Rules
  local at = se.t
  if se.ct and g.cases and g.cases[se.ct] and g.cases[se.ct].t then at = g.cases[se.ct].t end
  local orig = se.tr and g.sentences and g.sentences[se.tr]
  if orig and orig.t then at = orig.t end
  if Ru.OptedOut(g, key, at) then s.st, s.how = "void", "optout" return s end
  -- A tax punishment counts only for a period the player owed, once (Guild/Rules.lua).
  if se.r == "tax" and Ru.Forgiven(g)[se.tx] ~= id then s.st, s.how = "void", "notax" return s end
  if se.tr then
    local d = g.duels and g.duels[se.tr]
    if not d or P:Of(d.w, g) ~= P:Of(se.by, g) or P:Of(d.l, g) ~= key then s.st = "void" return s end
    -- Only the one who gave the first punishment, winning the trial, punishes: never the other way round.
    if not orig or P:Of(orig.by, g) ~= P:Of(se.by, g) then s.st = "void" return s end
  end
  local function over(how, t) s.st, s.how, s.ends = "done", how, t return s end
  -- A trial by combat: ordered, or demanded by the accused. It waits for the duel between the two.
  local demanded = se.pun ~= "trial" and byPrisoner(se.trial, key, g)
  local pardon
  for _, t in pairs(se.pardon or {}) do if not pardon or t < pardon then pardon = t end end
  local bail = St.BAIL[se.pun] and byPrisoner(se.bail, key, g)
  local early = math.min(pardon or math.huge, bail or math.huge, demanded or math.huge)
  if se.pun == "trial" or demanded == early and demanded then
    local d = g.duels and g.duels[id]
    if pardon and pardon <= early then return over("pardoned", pardon) end
    if d then s.winner = d.w return over("trial", d.t) end
    s.st, s.trial = "trial", true
    return s
  end
  if early < math.huge then return over(pardon == early and "pardoned" or "bailed", early) end
  local pun, start = se.pun, se.t
  if pun == "wheel" then
    local x = se.reroll and byPrisoner({ [se.reroll.by] = se.reroll.t }, key, g) and se.reroll or se.spin
    if not x then s.st = "spin" return s end
    pun, start = x.r, x.t
    s.pun, s.start, s.spun = pun, start, x
  end
  if pun == "stocks" then
    s.served = most(se.pr, key, g, "s")
    s.left = math.max(0, (se.len or 0) * 60 - s.served)
    if s.left <= 0 then return over("served", now) end
    if now >= start + St.LAPSE then return over("lapsed", start + St.LAPSE) end
  elseif pun == "dunce" then
    if now >= start + St.DAY then return over("served", start + St.DAY) end
    for other, o in pairs(g.sentences or {}) do
      if other ~= id and o.pun == "dunce" and o.t and o.t > start and P:Of(o.to, g) ~= key and St.Punishable(g, P:Of(o.to, g)) then
        return over("passed", o.t)
      end
    end
    s.left = start + St.DAY - now
  elseif pun == "curse" then
    if now >= start + St.DAY then return over("served", start + St.DAY) end
    s.left = start + St.DAY - now
  elseif pun == "radio" then
    local len = (se.len or St.LEN_MIN) * 60
    if now >= start + len then return over("served", start + len) end
    s.left = start + len - now
  elseif pun == "service" then
    s.n = most(se.pr, key, g, "n")
    if s.n >= (se.q or St.QUOTA) then return over("served", now) end
    if now >= start + St.LAPSE then return over("lapsed", start + St.LAPSE) end
  elseif pun == "walk" then
    s.i = most(se.pr, key, g, "i")
    if s.i >= #(se.z or {}) then return over("served", now) end
    if now >= start + St.LAPSE then return over("lapsed", start + St.LAPSE) end
  elseif pun == "servant" then
    local close = start + St.AUCTION
    s.master, s.price = St.Winner(g, se, key)
    if now < close then
      s.auction, s.left, s.st = true, close - now, "active"
      return s
    end
    if not s.master then return over("unsold", close) end
    if now >= close + St.SERVE then return over("served", close + St.SERVE) end
    s.left = close + St.SERVE - now
  elseif pun == "idol" then
    if not se.trib then
      if now >= start + St.LAPSE then return over("lapsed", start + St.LAPSE) end
      s.st = "tribute"
      return s
    end
    if se.trib.ok then return over("accepted", se.trib.t) end
    s.idol = true
    for name, t in pairs(se.deed or {}) do
      if P:Of(name, g) ~= key then return over("deed", t) end
    end
  end
  s.st = "active"
  return s
end

-- Every sentence with its state, newest first.
function St.List(g, now)
  local list = {}
  for id, se in pairs(g and g.sentences or {}) do
    if se.by then list[#list + 1] = St.State(g, id, se, now) end
  end
  table.sort(list, function(a, b) if a.se.t ~= b.se.t then return a.se.t > b.se.t end return a.id > b.id end)
  return list
end

local OPEN = { active = true, spin = true, tribute = true, trial = true }
-- A change of setup cancels what was still running then (SPEC decision 70): it stays cancelled after.
local rawState = St.State
function St.State(g, id, se, now)
  local s = rawState(g, id, se, now)
  if s.st ~= "void" and ns.Rules.Cancelled(g, se.t) then
    local _, _, changed = ns.Rules.Setup(g)
    if OPEN[rawState(g, id, se, changed).st] then s.st, s.how = "void", "setup" end
  end
  return s
end
function St.Open(s) return OPEN[s.st] == true end

-- The open sentences of a player.
function St.Of(g, key, now)
  local out = {}
  for _, s in ipairs(St.List(g, now)) do if s.key == key and St.Open(s) then out[#out + 1] = s end end
  return out
end

-- The player who wears the Dunce Cap now, or nil.
function St.Dunce(g, now)
  for _, s in ipairs(St.List(g, now)) do if s.pun == "dunce" and s.st == "active" then return s.key end end
  return nil
end

-- Bought out of the Radio: the "Broke" badge (SPEC §6).
function St.Broke(g, key)
  for _, se in pairs(g and g.sentences or {}) do
    if se.pun == "radio" and se.bail and byPrisoner(se.bail, key, g) and P:Of(se.to, g) == key then return true end
  end
  return false
end

-- Results the Wheel landed on in the last day (retired for a while, SPEC §6).
function St.Retired(g, now)
  now = now or time()
  local out = {}
  for _, se in pairs(g and g.sentences or {}) do
    for _, f in ipairs({ "spin", "reroll" }) do
      if se[f] and now - se[f].t < St.DAY then out[se[f].r] = true end
    end
  end
  return out
end

-- Where the Wheel may land now for sentence se (all of it when everything is retired). The Walk of shame only when
-- the sentencer gave a route.
function St.Slices(g, now, but, se)
  local retired, out = St.Retired(g, now), {}
  local function can(p) return p ~= but and D:On("p:" .. p, g) and (p ~= "walk" or (se and se.z and #se.z > 0)) end
  for _, p in ipairs(St.WHEEL) do if not retired[p] and can(p) then out[#out + 1] = p end end
  if #out == 0 then for _, p in ipairs(St.WHEEL) do if can(p) then out[#out + 1] = p end end end
  return out
end

-- The trial a duel between characters a and b counts for (Guild/Duels.lua): { id }, or nil.
function St.MatchWith(g, a, b)
  local pa, pb = P:Of(a, g), P:Of(b, g)
  for _, s in ipairs(St.List(g)) do
    if s.st == "trial" then
      local accuser = P:Of(s.se.by, g)
      if (pa == s.key and pb == accuser) or (pb == s.key and pa == accuser) then return { id = s.id } end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function purse() return D:Settings().purse end

function St.Sentence(to, pun, len, why, extra)
  local op = { k = "sentence", to = to, pun = pun, len = len, why = why }
  for k, v in pairs(extra or {}) do op[k] = v end
  -- (Without a reason given, an incident: SPEC decision 69.)
  if op.r == nil and op.ct == nil and op.tr == nil then op.r = "inc" end
  return ns.Sync:Do(op)
end

function St.PayBail(s)
  local amt = St.Bail(s.se.pun, purse())
  return amt ~= nil and ns.Sync:Do({ k = "bail", id = s.id, amt = amt, p = purse() })
end

function St.Pardon(id) return ns.Sync:Do({ k = "pardon", id = id }) end
function St.Tomato(id) return ns.Sync:Do({ k = "tomato", id = id }) end
function St.Trial(id) return ns.Sync:Do({ k = "trial", id = id }) end
function St.Deed(id) return ns.Sync:Do({ k = "deed", id = id }) end
function St.Tribute(id, ok, item) return ns.Sync:Do({ k = "tribute", id = id, ok = ok, item = item }) end
function St.Bid(id, amt) return ns.Sync:Do({ k = "bid", id = id, amt = amt, p = purse() }) end
function St.Order(id, text) return ns.Sync:Do({ k = "order", id = id, text = text }) end
function St.OrderDone(id, o) return ns.Sync:Do({ k = "odone", id = id, o = o }) end

function St.Spin(id)
  local g = D:Current()
  local slices = St.Slices(g, nil, nil, g and g.sentences and g.sentences[id])
  return ns.Sync:Do({ k = "spin", id = id, r = slices[math.random(1, #slices)] })
end

function St.Reroll(s)
  local slices = St.Slices(D:Current(), nil, s.pun, s.se)
  return ns.Sync:Do({ k = "reroll", id = s.id, r = slices[math.random(1, #slices)], amt = St.Bail("wheel", purse()), p = purse() })
end

-- The winning bidder pays for the servant's hour once the auction is over.
function St.Hire(s) return ns.Sync:Do({ k = "hire", id = s.id, amt = s.price, p = purse() }) end
