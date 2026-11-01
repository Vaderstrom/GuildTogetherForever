-- Raffles (SPEC §8, Tavern): a rank that may start games (SPEC §3.2, tourney) opens one with a prize, a ticket price,
-- how many tickets there are and when the draw is. Tickets are paid to the Treasury in the purse (SPEC §4: money
-- for the guild). The draw is the host's /roll from 1 to the tickets sold, in front of everyone.
--   raffle       { prize, price, max, when, p }   opened (its key is the raffle's id)
--   raffle_buy   { id, n }                        tickets bought by the author
--   raffle_draw  { id, roll, w, tk, price, p }    the host's draw: tk = { { name, n }, ... } in ticket order, the
--                                                 tickets that count; each is charged now, w won
-- Tickets are charged at the draw, from the host's list, so every copy charges the same tickets whatever order the
-- buys reached it in. A buy after the draw does not count and costs nothing.
local _, ns = ...
local L, D, Pu = ns.L, ns.GuildData, ns.Purse
local RA = {}
ns.Raffle = RA

RA.PRIZE_MAX, RA.WHEN_MAX = 40, 24
RA.TICKETS_MAX = 1000   -- tickets in one raffle
RA.BUY_MAX = 20         -- tickets in one buy

local function party(v) return type(v) == "string" and v ~= "" and #v <= 64 end
local function whole(v, lo, hi) v = tonumber(v) return v ~= nil and v >= lo and v <= hi and v == math.floor(v) end
local function host(id) return D.KeyAuthor(id) end

-- Free text from players: no chat escapes or control letters, at most max bytes, trimmed. Nil if empty.
function RA.Clean(s, max)
  if type(s) ~= "string" then return nil end
  s = strtrim((s:gsub("[%z\1-\31|]", "")))
  if #s > max then s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
  s = strtrim(s)
  return s ~= "" and s or nil
end

local function get(g, id)
  local all = D.Part(g, "raffles")
  local ra = all[id]
  if not ra then
    ra = { b = {}, st = "open" }
    all[id] = ra
  end
  return ra
end

local function soundOpen(op)
  return RA.Clean(op.prize, RA.PRIZE_MAX) ~= nil and Pu.IsPurse(op.p) and Pu.ValidAmount(op.price, op.p)
    and whole(op.max, 0, RA.TICKETS_MAX)
end

D:Register("raffle", {
  allowed = function(g, author, op) return soundOpen(op) and D:Can("games", author, g) end,
  apply = function(g, author, op, t, n)
    local ra = get(g, D.Key(author, n))
    ra.h, ra.prize, ra.price, ra.max, ra.p, ra.t = author, RA.Clean(op.prize, RA.PRIZE_MAX), op.price, op.max, op.p, t
    ra.when = RA.Clean(op.when, RA.WHEN_MAX)
    return true
  end,
  copy = function(g) return g.raffles end,
  merge = function(g, part)
    if type(part) ~= "table" then return end
    for id, theirs in pairs(part) do
      if type(id) == "string" and host(id) and type(theirs) == "table" then
        local ra = get(g, id)
        if not ra.h and party(theirs.h) and soundOpen(theirs) then
          ra.h, ra.prize, ra.price, ra.max, ra.p, ra.t = theirs.h, RA.Clean(theirs.prize, RA.PRIZE_MAX), theirs.price,
            theirs.max, theirs.p, tonumber(theirs.t)
          ra.when = RA.Clean(theirs.when, RA.WHEN_MAX)
        end
        for name, b in pairs(type(theirs.b) == "table" and theirs.b or {}) do
          if party(name) and type(b) == "table" and whole(b.n, 1, RA.TICKETS_MAX) then
            local mine = ra.b[name]
            if not mine or b.n > mine.n then ra.b[name] = { n = b.n, t = tonumber(b.t) or 0 } end
          end
        end
        if theirs.st == "done" and ra.st ~= "done" and party(theirs.w) then
          ra.st, ra.w, ra.roll, ra.sold = "done", theirs.w, tonumber(theirs.roll), tonumber(theirs.sold)
        end
      end
    end
  end,
})

D:Register("raffle_buy", {
  allowed = function(_, _, op) return host(op.id) ~= nil and whole(op.n, 1, RA.BUY_MAX) end,
  apply = function(g, author, op, t)
    local ra = get(g, op.id)
    if ra.st == "done" then return false end
    local b = ra.b[author] or { n = 0, t = t }
    b.n = b.n + op.n
    ra.b[author] = b
    return true
  end,
})

D:Register("raffle_draw", {
  allowed = function(_, author, op)
    if host(op.id) ~= author or not party(op.w) or not Pu.IsPurse(op.p) or not Pu.ValidAmount(op.price, op.p)
      or type(op.tk) ~= "table" or #op.tk == 0 or #op.tk > RA.TICKETS_MAX then
      return false
    end
    local sold = 0
    for _, e in ipairs(op.tk) do
      if type(e) ~= "table" or not party(e[1]) or not whole(e[2], 1, RA.TICKETS_MAX) then return false end
      sold = sold + e[2]
    end
    return whole(op.roll, 1, sold)
  end,
  apply = function(g, author, op, t, n)
    local ra = get(g, op.id)
    local key = D.Key(author, n)
    local sold = 0
    for i, e in ipairs(op.tk) do
      Pu:Charge(g, key .. ":" .. i, e[1], Pu.TREASURY, op.price * e[2], op.p, "raffle", t)
      sold = sold + e[2]
    end
    ra.st, ra.w, ra.roll, ra.sold, ra.price, ra.p = "done", op.w, op.roll, sold, op.price, op.p
    ra.td = t   -- when it was drawn (its scene plays for whoever opens it soon after, SPEC decision 60)
    return true
  end,
})

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The tickets in order: the first buyer's first, by when they first bought, then by name.
function RA:Tickets(ra)
  local list = {}
  for name, b in pairs(ra.b) do list[#list + 1] = { name, b.n, b.t or 0 } end
  table.sort(list, function(a, b)
    if a[3] ~= b[3] then return a[3] < b[3] end
    return a[1] < b[1]
  end)
  local sold = 0
  for i, e in ipairs(list) do
    list[i] = { e[1], e[2] }
    sold = sold + e[2]
  end
  return list, sold
end

-- Who holds ticket number roll.
function RA.Holder(tickets, roll)
  local at = 0
  for _, e in ipairs(tickets) do
    at = at + e[2]
    if roll <= at then return e[1] end
  end
end

-- The raffles to show: open ones first (oldest first), then the newest finished one. { { id, ra }, ... }
function RA:List(g)
  g = g or D:Current()
  local open, lastDone, lastId = {}, nil, nil
  for id, ra in pairs(g and g.raffles or {}) do
    if ra.h then
      if ra.st ~= "done" then open[#open + 1] = { id = id, ra = ra }
      elseif not lastDone or (ra.t or 0) > (lastDone.t or 0) then lastDone, lastId = ra, id end
    end
  end
  table.sort(open, function(a, b)
    if (a.ra.t or 0) ~= (b.ra.t or 0) then return (a.ra.t or 0) < (b.ra.t or 0) end
    return a.id < b.id
  end)
  if lastDone then open[#open + 1] = { id = lastId, ra = lastDone } end
  return open
end

---------------------------------------------------------------------------
-- Doing
---------------------------------------------------------------------------
function RA:Start(prize, price, max, when)
  return ns.Sync:Do({ k = "raffle", prize = prize, price = tonumber(price), max = tonumber(max) or 0, when = when,
    p = D:Settings().purse })
end

-- A ticket is bought face to face with the host (SPEC decision 72).
function RA:Buy(id, n)
  local g = D:Current()
  local ra = g and g.raffles and g.raffles[id]
  if ra and ra.h and not ns.Looks.Need(ra.h) then return false end
  return ns.Sync:Do({ k = "raffle_buy", id = id, n = n or 1 })
end

-- The host draws: a /roll from 1 to the tickets sold; the roll the game reports picks the winner.
function RA:Draw(id)
  local g = D:Current()
  local ra = g and g.raffles and g.raffles[id]
  if not ra or ra.h ~= ns.Self() or ra.st == "done" then return false end
  local _, sold = self:Tickets(ra)
  if sold < 1 then return false end
  self.drawing = { id = id, sold = sold }
  ns.Dice:Roll(sold)
  return true
end

-- The host's roll for a draw.
function RA:Rolled(v, lo, hi)
  local d = self.drawing
  if not d or lo ~= 1 or hi ~= d.sold then return false end
  self.drawing = nil
  local g = D:Current()
  local ra = g and g.raffles and g.raffles[d.id]
  if not ra or ra.st == "done" then return false end
  local tickets, sold = self:Tickets(ra)
  if sold ~= d.sold then return false end
  local w = RA.Holder(tickets, v)
  local ok = ns.Sync:Do({ k = "raffle_draw", id = d.id, roll = v, w = w, tk = tickets, price = ra.price, p = ra.p })
  if ok then ns:Print(L.RA_WON:format(ns.Display(w), v, ra.prize or ""), true) end
  return ok
end

ns.Dice:Listen(function(name, v, lo, hi)
  if name == ns.Self() then RA:Rolled(v, lo, hi) end
end)
