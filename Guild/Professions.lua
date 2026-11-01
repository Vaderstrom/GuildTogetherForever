-- Professions (SPEC §8b): who in the guild can make what, and what the guild needs made.
--   pro         { c = { [prof] = { n, i, r, m, rc, rt } } }   the character's own addon: its professions (prof: the
--                                  profession's skill line, else its name), each with its name, icon, skill and most
--                                  skill, and the recipes (spell ids) known when its window was last opened (rt)
--   craft       { rid, what, n, mats, tip, p }   a member asks for something made: a recipe (rid) or a name, how many,
--                                  whether they bring the materials, and an optional tip in the purse p
--   craft_take  { id, on }         a crafter will make it (on), or hands it back; the first who took it makes it
--   craft_got   { id, to }         the member who asked: it came, from to (the tip is owed to them)
--   craft_drop  { id }             the member who asked takes the request back
-- g.crafts[char] = { t, p }: the newest share wins. g.crafting[key] = { by, t, rid, what, n, mats, tip, p,
-- tk = { [char] = { on, t } }, got = { to, t }, drop }.
local _, ns = ...
local L, D, R, P, Pu = ns.L, ns.GuildData, ns.Roster, ns.Players, ns.Purse
local Clean = ns.Raffle.Clean

local Pr = {}
ns.Professions = Pr

Pr.PROFS_MAX = 8            -- professions per character (two, the secondary ones, and room)
Pr.RECIPES_MAX = 2000       -- recipes shared per profession
Pr.WHAT_MAX, Pr.COUNT_MAX = 80, 200
Pr.OPEN_DAYS = 14           -- an open request closes by itself
Pr.SHARE_WAIT = 20          -- seconds after a change before sharing (skill-ups come in runs)
Pr.FRESH = 3600             -- a request this new tells the crafters who know it

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

---------------------------------------------------------------------------
-- Sharing a character's professions
---------------------------------------------------------------------------
local function soundProf(key, x)
  if type(key) ~= "string" or #key > 40 or type(x) ~= "table" then return false end
  if Clean(x.n, 40) == nil or not whole(x.r, 0, 1000) or not whole(x.m, 0, 1000) then return false end
  if x.i ~= nil and not whole(x.i, 1, 2 ^ 31) and not (type(x.i) == "string" and #x.i <= 120) then return false end
  if x.rt ~= nil and not tonumber(x.rt) then return false end
  if x.rc ~= nil then
    if type(x.rc) ~= "table" or #x.rc > Pr.RECIPES_MAX then return false end
    for _, id in ipairs(x.rc) do if not whole(id, 1, 2 ^ 31) then return false end end
  end
  return true
end

local function soundPro(c)
  if type(c) ~= "table" then return false end
  local n = 0
  for key, x in pairs(c) do
    n = n + 1
    if n > Pr.PROFS_MAX or not soundProf(key, x) then return false end
  end
  return true
end

local function takePro(c)
  local out = {}
  for key, x in pairs(c) do
    local rc
    if x.rc then
      rc = {}
      for i, id in ipairs(x.rc) do rc[i] = tonumber(id) end
    end
    out[key] = { n = Clean(x.n, 40), i = x.i, r = tonumber(x.r), m = tonumber(x.m), rc = rc, rt = tonumber(x.rt) }
  end
  return out
end

D:Register("pro", {
  allowed = function(_, _, op) return soundPro(op.c) end,
  apply = function(g, author, op, t)
    local crafts = D.Part(g, "crafts")
    local cur = crafts[author]
    if cur and cur.t >= t then return false end
    crafts[author] = { t = t, p = takePro(op.c) }
    return true
  end,
  -- All of Professions travels with this part.
  copy = function(g) return { crafts = g.crafts, req = g.crafting } end,
  merge = function(g, part) Pr.Merge(g, part) end,
})

---------------------------------------------------------------------------
-- Crafting requests
---------------------------------------------------------------------------
local function request(g, id)
  local all = D.Part(g, "crafting")
  all[id] = all[id] or {}
  return all[id]
end

local function soundAsk(op)
  -- Always a recipe (decided 31 Oct 2026): what a crafter of the guild can make, never free text.
  if not whole(op.rid, 1, 2 ^ 31) then return false end
  if Clean(op.what, Pr.WHAT_MAX) == nil or not whole(op.n, 1, Pr.COUNT_MAX) then return false end
  if op.tip ~= nil and not (Pu.IsPurse(op.p) and Pu.ValidAmount(op.tip, op.p)) then return false end
  return op.mats == nil or type(op.mats) == "boolean"
end

local function takeAsk(rq, author, op, t)
  rq.by, rq.t, rq.rid, rq.what, rq.n = author, t, tonumber(op.rid), Clean(op.what, Pr.WHAT_MAX), tonumber(op.n)
  rq.mats, rq.tip, rq.p = op.mats == true or nil, tonumber(op.tip), op.tip and op.p or nil
end

D:Register("craft", {
  allowed = function(_, _, op) return soundAsk(op) end,
  apply = function(g, author, op, t, n)
    takeAsk(request(g, D.Key(author, n)), author, op, t)
    return true
  end,
})

D:Register("craft_take", {
  allowed = function(_, author, op) return host(op.id) ~= nil and host(op.id) ~= author and type(op.on) == "boolean" end,
  apply = function(g, author, op, t)
    local rq = request(g, op.id)
    rq.tk = rq.tk or {}
    local cur = rq.tk[author]
    if cur and cur.t >= t then return false end
    rq.tk[author] = { on = op.on, t = t }
    return true
  end,
})

D:Register("craft_got", {
  allowed = function(_, author, op) return host(op.id) == author and party(op.to) and op.to ~= author end,
  apply = function(g, _, op, t, n)
    local rq = request(g, op.id)
    if rq.got or rq.drop then return false end
    rq.got = { to = op.to, t = t }
    -- The tip is owed to the crafter, in the purse it was offered in.
    if rq.tip and rq.p and rq.by then
      Pu:Charge(g, D.Key(host(op.id), n), rq.by, op.to, rq.tip, rq.p, "craft", t)
    end
    return true
  end,
})

D:Register("craft_drop", {
  allowed = function(_, author, op) return host(op.id) == author end,
  apply = function(g, _, op, t)
    local rq = request(g, op.id)
    if rq.got or (rq.drop and rq.drop <= t) then return false end
    rq.drop = t
    return true
  end,
})

-- Who makes it: the first who took it and has not handed it back.
local function maker(rq)
  local best, bt
  for name, x in pairs(rq.tk or {}) do
    if x.on and (not bt or x.t < bt or (x.t == bt and name < best)) then best, bt = name, x.t end
  end
  return best
end

-- A request as it stands: st "open", "taken", "got", "dropped" or "closed" (open too long); maker.
function Pr.Request(g, id, now)
  local rq = g.crafting and g.crafting[id]
  if not rq or not rq.by then return nil end
  local s = { id = id, rq = rq, maker = maker(rq) }
  if rq.got then s.st, s.maker = "got", rq.got.to
  elseif rq.drop then s.st = "dropped"
  elseif s.maker then s.st = "taken"
  elseif (now or time()) - rq.t > Pr.OPEN_DAYS * 86400 then s.st = "closed"
  else s.st = "open" end
  return s
end

-- Requests still to make: taken and open, newest first; done ones after (the last few).
local ORDER = { taken = 1, open = 1, got = 2, dropped = 3, closed = 3 }
function Pr.Requests(g, now)
  local list = {}
  for id in pairs(g and g.crafting or {}) do
    local s = Pr.Request(g, id, now)
    if s then list[#list + 1] = s end
  end
  table.sort(list, function(a, b)
    if ORDER[a.st] ~= ORDER[b.st] then return ORDER[a.st] < ORDER[b.st] end
    if a.rq.t ~= b.rq.t then return a.rq.t > b.rq.t end
    return a.id > b.id
  end)
  return list
end

-- How many requests wait for a crafter.
function Pr.Waiting(g, now)
  local n = 0
  for _, s in ipairs(Pr.Requests(g, now)) do if s.st == "open" then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- A whole copy
---------------------------------------------------------------------------
function Pr.Merge(g, part)
  if type(part) ~= "table" then return end
  for name, e in pairs(type(part.crafts) == "table" and part.crafts or {}) do
    if party(name) and type(e) == "table" and tonumber(e.t) and soundPro(e.p) then
      local crafts = D.Part(g, "crafts")
      if not crafts[name] or crafts[name].t < e.t then crafts[name] = { t = e.t, p = takePro(e.p) } end
    end
  end
  for id, e in pairs(type(part.req) == "table" and part.req or {}) do
    if type(id) == "string" and host(id) and type(e) == "table" then
      local rq = request(g, id)
      if not rq.by and party(e.by) and tonumber(e.t) and soundAsk(e) then takeAsk(rq, e.by, e, e.t) end
      for name, x in pairs(type(e.tk) == "table" and e.tk or {}) do
        if party(name) and type(x) == "table" and tonumber(x.t) and type(x.on) == "boolean" then
          rq.tk = rq.tk or {}
          if not rq.tk[name] or rq.tk[name].t < x.t then rq.tk[name] = { on = x.on, t = x.t } end
        end
      end
      -- The tip's debt travels in the purse's own part; only the request's state is put together here.
      local x = e.got
      if type(x) == "table" and party(x.to) and tonumber(x.t) and (not rq.got or x.t < rq.got.t) then
        rq.got = { to = x.to, t = x.t }
      end
      if tonumber(e.drop) and (not rq.drop or e.drop < rq.drop) then rq.drop = e.drop end
    end
  end
end

---------------------------------------------------------------------------
-- Reading: crafters and recipes
---------------------------------------------------------------------------
-- A recipe's name and icon in this client (recipes are spells).
function Pr.RecipeName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end
function Pr.RecipeIcon(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return GetSpellTexture and GetSpellTexture(id) or nil
end

-- Characters still in the guild (the roster), with their shares.
local function shares(g)
  local out = {}
  for name, e in pairs(g and g.crafts or {}) do
    if R:Rank(name) ~= nil and type(e.p) == "table" then out[name] = e end
  end
  return out
end

-- The guild's professions: { { prof, n, i, best, max, list = { { char, key, r, m, t, rc } } } }, the most crafters
-- first; each list best skill first. One player is one player: a player with two characters in a profession shows
-- with the better one.
function Pr.Crafters(g)
  local byProf = {}
  for char, e in pairs(shares(g)) do
    local key = P:Of(char, g)
    for prof, x in pairs(e.p) do
      local b = byProf[prof] or { prof = prof, n = x.n, i = x.i, players = {} }
      byProf[prof] = b
      local cur = b.players[key]
      if not cur or x.r > cur.r then
        b.players[key] = { char = char, key = key, r = x.r, m = x.m, t = e.t, rc = x.rc, rt = x.rt }
      end
    end
  end
  local out = {}
  for _, b in pairs(byProf) do
    b.list, b.best, b.max = {}, 0, 0
    for _, c in pairs(b.players) do
      b.list[#b.list + 1] = c
      if c.r > b.best then b.best, b.max = c.r, c.m end
    end
    b.players = nil
    table.sort(b.list, function(x, y)
      if x.r ~= y.r then return x.r > y.r end
      return x.char < y.char
    end)
    out[#out + 1] = b
  end
  table.sort(out, function(x, y)
    if #x.list ~= #y.list then return #x.list > #y.list end
    return x.n < y.n
  end)
  return out
end

-- One profession's crafters (Pr.Crafters' entry), or nil.
function Pr.Profession(g, prof)
  for _, b in ipairs(Pr.Crafters(g)) do if b.prof == prof then return b end end
end

-- Who knows a recipe: { { char, key, prof, pn, r, m, t, online } }, online first, then best skill.
function Pr.WhoKnows(g, rid)
  local out, seen = {}, {}
  for char, e in pairs(shares(g)) do
    for prof, x in pairs(e.p) do
      for _, id in ipairs(x.rc or {}) do
        if id == rid then
          local key = P:Of(char, g)
          local online = char == ns.Self() or R:Online(char)
          local cur = seen[key]
          if not cur or (online and not cur.online) then
            local row = { char = char, key = key, prof = prof, pn = x.n, r = x.r, m = x.m, t = e.t, online = online }
            if cur then out[cur.i] = row; row.i = cur.i else out[#out + 1] = row; row.i = #out end
            seen[key] = row
          end
          break
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    if a.r ~= b.r then return a.r > b.r end
    return a.char < b.char
  end)
  return out
end

-- Recipes whose name holds text (any case): { { rid, name, icon, prof, pn, n } }, by name; at most max.
function Pr.Search(g, text, max)
  text = strtrim(text or ""):lower()
  if #text < 2 then return {} end
  local found, out = {}, {}
  for char, e in pairs(shares(g)) do
    local key = P:Of(char, g)
    for prof, x in pairs(e.p) do
      for _, id in ipairs(x.rc or {}) do
        local f = found[id]
        if f == nil then
          local name = Pr.RecipeName(id)
          if name and not secret(name) and name:lower():find(text, 1, true) then
            f = { rid = id, name = name, icon = Pr.RecipeIcon(id), prof = prof, pn = x.n, n = 0, who = {} }
            out[#out + 1] = f
          else
            f = false
          end
          found[id] = f
        end
        if f and not f.who[key] then f.who[key], f.n = true, f.n + 1 end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.rid < b.rid
  end)
  for i = #out, (max or 30) + 1, -1 do out[i] = nil end
  for _, f in ipairs(out) do f.who = nil end
  return out
end

---------------------------------------------------------------------------
-- This character's own professions
---------------------------------------------------------------------------
local function store()
  if not ns.char then return {} end
  ns.char.crafts = ns.char.crafts or {}
  return ns.char.crafts
end

-- The professions the game lists for this character, with what was read of their recipes before.
function Pr.ReadMine()
  local out, old = {}, store()
  local function put(key, name, icon, rank, max)
    if secret(name) or secret(rank) or secret(max) then return end
    if type(name) ~= "string" or not tonumber(rank) or not tonumber(max) then return end
    local o = old[key]
    out[key] = { n = name, i = icon, r = tonumber(rank), m = tonumber(max), rc = o and o.rc, rt = o and o.rt }
  end
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 5 do
      local ix = list[i]
      if ix then
        local name, icon, rank, max, _, _, line = GetProfessionInfo(ix)
        if name then put(tostring(line or name), name, icon, rank, max) end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    -- The older skill list: the lines under the Professions and Secondary Skills headers.
    local header
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
      if isHeader then header = name
      elseif header ~= nil and (header == TRADE_SKILLS or header == SECONDARY_SKILLS) then put(name, name, nil, rank, max) end
    end
  end
  return out
end

-- Reads the recipes of the profession window that is open, when it is this character's own. Returns its key.
function Pr.ReadRecipes()
  local T = C_TradeSkillUI
  if not T or not T.GetAllRecipeIDs or not T.GetRecipeInfo or not T.GetBaseProfessionInfo then return nil end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return nil end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return nil end
  local info = T.GetBaseProfessionInfo()
  local line = info and info.professionID
  if not line or secret(line) then return nil end
  local ids = {}
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(id)
    if r and r.learned and #ids < Pr.RECIPES_MAX then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local key = tostring(line)
  local mine = store()
  mine[key] = mine[key] or { n = info.professionName, r = info.skillLevel or 0, m = info.maxSkillLevel or 0 }
  mine[key].rc, mine[key].rt = ids, time()
  return key
end

-- What would be shared, and a short signature of it (to share only what changed).
local function snapshot()
  local mine = Pr.ReadMine()
  local keys = {}
  for key in pairs(mine) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    local x = mine[key]
    parts[#parts + 1] = key .. "=" .. x.r .. "/" .. x.m .. ":" .. table.concat(x.rc or {}, ",")
  end
  return mine, table.concat(parts, ";")
end

-- Shares this character's professions with the guild when they changed since the last share (force: anyway).
function Pr.Share(force)
  local g = D:Current()
  if not g or not R:Ready() or not ns.char then return false end
  local mine, sig = snapshot()
  local cur = g.crafts and g.crafts[ns.Self()]
  -- What was last shared, per guild (the self-test's pretend guild is another).
  if type(ns.char.craftsSig) ~= "table" then ns.char.craftsSig = {} end
  if not force and sig == ns.char.craftsSig[g.id] and cur then return false end
  if next(mine) == nil and not cur then return false end
  local ok = ns.Sync:Do({ k = "pro", c = mine })
  if ok then ns.char.craftsSig[g.id] = sig end
  return ok
end

-- Shares a little later (skill-ups come one after another).
function Pr.Later()
  if Pr.pending or not C_Timer then return end
  Pr.pending = true
  C_Timer.After(Pr.SHARE_WAIT, function()
    Pr.pending = nil
    Pr.Share()
  end)
end

-- This character's professions as the page shows them: { { prof, n, i, r, m, rt } }, by name.
function Pr.Mine()
  local out = {}
  for prof, x in pairs(Pr.ReadMine()) do
    out[#out + 1] = { prof = prof, n = x.n, i = x.i, r = x.r, m = x.m, rt = x.rt, has = x.rc ~= nil }
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

-- When this character last shared (nil: never).
function Pr.SharedAt(g)
  local e = g and g.crafts and g.crafts[ns.Self()]
  return e and e.t
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
local function sync(op) return ns.Sync:Do(op) end

-- Asks for something made: a recipe (rid, its name in what) or a name; tip in the guild's purse (nil: none).
function Pr.Ask(rid, what, n, mats, tip)
  local p = D:Settings().purse
  local op = { k = "craft", rid = rid, what = Clean(what, Pr.WHAT_MAX), n = tonumber(n), mats = mats and true or nil }
  if tip and tip ~= 0 then op.tip, op.p = tonumber(tip), p end
  if not soundAsk(op) then return false end
  return sync(op)
end
function Pr.Take(id, on) return sync({ k = "craft_take", id = id, on = on and true or false }) end
function Pr.Got(id, to) return sync({ k = "craft_got", id = id, to = to }) end
function Pr.Drop(id) return sync({ k = "craft_drop", id = id }) end

-- Does one of this account's characters know a recipe (from what it shared)?
function Pr.IKnow(g, rid)
  for _, name in ipairs((P:MyChars())) do
    local e = g and g.crafts and g.crafts[name]
    for _, x in pairs(e and e.p or {}) do
      for _, id in ipairs(x.rc or {}) do if id == rid then return true end end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- A new request for a recipe one of my characters knows: a line in my chat.
ns:On("OP", function(g, a, op, t)
  if op.k ~= "craft" or not op.rid or g ~= D:Current() or P:IsMe(P:Of(a, g), g) then return end
  if time() - t > Pr.FRESH or not Pr.IKnow(g, op.rid) then return end
  ns:Print(L.PR_ASKED_CHAT:format(ns.Display(a), Clean(op.what, Pr.WHAT_MAX) or "?"))
end)

ns:On("ROSTER", function(first) if first then Pr.Share() end end)

local function listen(event, fn)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
  ns:RegisterEvent(event, fn)
end
-- The window sends this many times while it fills: read at most every few seconds.
local readAt = -100
listen("TRADE_SKILL_LIST_UPDATE", function()
  local now = GetTime()
  if now - readAt < 3 then return end
  if Pr.ReadRecipes() then readAt = now; Pr.Later() end
end)
listen("SKILL_LINES_CHANGED", function() Pr.Later() end)
