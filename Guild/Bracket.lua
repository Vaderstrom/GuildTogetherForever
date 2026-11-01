-- Copied from Journey Together Forever (Rules/Tournament.lua), unchanged but for this note: the structure of a
-- tournament for the purse (Guild/Cup.lua, SPEC §5, §12).
-- The Guild Master tournament's structure (SPEC §4.10, the mockup's singleElim / seedPositions / roundName):
-- from the seeds and the results so far, every match of the format, who is in it, and who won. No frames, no
-- messages: Fellowship/Tourney.lua keeps the state and the page draws what this returns.
--   A participant is a name, false (a bye / nobody: the other one goes through) or nil (not decided yet).
--   Each match has a key (stable, used for results), a stage, a column (for drawing) and a slot: the tournament's
--   round in which it is played. Slot by slot, a round lasts the rule's round length.
-- Formats: "single" (bracket, byes to the top seeds), "double" (winners and losers brackets, then a grand final),
-- "groups" (groups of about 4 play everyone in the group, the top 2 go to a knockout), "rr" (round robin).
local _, ns = ...
local L = ns.L
local T = {}
ns.Tournament = T

local function nextPow2(n) local p = 1; while p < n do p = p * 2 end return p end
local function log2(n) return math.floor(math.log(n) / math.log(2) + 0.5) end
T.NextPow2, T.Log2 = nextPow2, log2

-- Standard seeding: 1 meets 16, 8 meets 9 and so on, so the top seeds meet last.
function T.SeedPositions(size)
  local pos = { 1 }
  while #pos < size do
    local m, nxt = #pos * 2 + 1, {}
    for _, x in ipairs(pos) do nxt[#nxt + 1] = x; nxt[#nxt + 1] = m - x end
    pos = nxt
  end
  return pos
end

function T.RoundName(left, idx)
  if left == 1 then return L.T_FINAL end
  if left == 2 then return L.T_SEMIS end
  if left == 4 then return L.T_QUARTERS end
  if left == 8 then return L.T_R16 end
  if left == 16 then return L.T_R32 end
  return L.T_ROUND_N:format(idx)
end

-- Seeds: by level, highest first (ties by name), or "random" (fixed by the tournament's id, the same everywhere).
function T.Seed(names, mode, levelOf, salt)
  local list = {}
  for _, n in ipairs(names) do list[#list + 1] = n end
  local function hash(s)
    local x = 7
    for i = 1, #s do x = (x * 31 + s:byte(i)) % 99991 end
    for i = 1, #(salt or "") do x = (x * 17 + salt:byte(i)) % 99991 end
    return x
  end
  table.sort(list, function(a, b)
    if mode == "random" then
      local ha, hb = hash(a), hash(b)
      if ha ~= hb then return ha < hb end
      return a < b
    end
    local la, lb = levelOf(a), levelOf(b)
    if la ~= lb then return la > lb end
    return a < b
  end)
  return list
end

---------------------------------------------------------------------------
-- Building the matches
---------------------------------------------------------------------------
-- A builder keeps the matches and resolves who is in each one from its sources:
--   { seed = i }, { win = key }, { lose = key }, { place = { group, place } }.
local function builder(seeds, results)
  local B = { matches = {}, byKey = {}, groups = {} }
  local winner, loser
  local function resolve(src)
    if src.seed then return seeds[src.seed] or false end
    if src.win then return winner(src.win) end
    if src.lose then return loser(src.lose) end
    if src.place then return B.Standing(src.place[1], src.place[2]) end
    return false
  end
  function winner(key)
    local m = B.byKey[key]
    local a, b = resolve(m.sa), resolve(m.sb)
    if a == false and b == false then return false end
    if a == false then return b end
    if b == false then return a end
    if a == nil or b == nil then return nil end
    local w = results[key]
    if w == a or w == b then return w end
    return nil
  end
  function loser(key)
    local m = B.byKey[key]
    local a, b = resolve(m.sa), resolve(m.sb)
    if a == false or b == false then return false end
    local w = winner(key)
    if w == nil then return nil end
    return w == a and b or a
  end
  function B.Add(key, stage, col, slot, label, sa, sb)
    local m = { key = key, stage = stage, col = col, slot = slot, label = label, sa = sa, sb = sb }
    B.matches[#B.matches + 1] = m
    B.byKey[key] = m
    return m
  end
  -- Wins of each name in a group (when every match of the group is decided: its standing).
  function B.GroupTable(g)
    local names, wins, losses, done = B.groups[g], {}, {}, true
    for _, n in ipairs(names) do wins[n], losses[n] = 0, 0 end
    for _, m in ipairs(B.matches) do
      if m.stage == "g" .. g then
        local w = winner(m.key)
        if w == nil then done = false
        elseif w then
          wins[w] = wins[w] + 1
          local l = loser(m.key)
          if l then losses[l] = losses[l] + 1 end
        end
      end
    end
    local order = {}
    for _, n in ipairs(names) do order[#order + 1] = n end
    local seedOf = {}
    for i, n in ipairs(seeds) do seedOf[n] = i end
    table.sort(order, function(a, b)
      if wins[a] ~= wins[b] then return wins[a] > wins[b] end
      return seedOf[a] < seedOf[b]
    end)
    return order, wins, losses, done
  end
  function B.Standing(g, place)
    if not B.groups[g] then return false end
    local order, _, _, done = B.GroupTable(g)
    if not done then return nil end
    return order[place] or false
  end
  B.Winner, B.Loser, B.Resolve = winner, loser, resolve
  return B
end

-- Single elimination among the sources (in seed order), from slot `first`. Returns the final's key.
local function knockout(B, stage, entrants, first)
  local size = nextPow2(math.max(2, #entrants))
  local pos = T.SeedPositions(size)
  local cur = {}
  for i, p in ipairs(pos) do cur[i] = entrants[p] or { seed = 0 } end
  local r, finalKey = 1, nil
  while #cur > 1 do
    local nxt = {}
    for i = 1, #cur, 2 do
      local key = stage .. r .. ":" .. ((i + 1) / 2)
      B.Add(key, stage, r, first + r - 1, T.RoundName(#cur / 2, r), cur[i], cur[i + 1])
      nxt[#nxt + 1] = { win = key }
      finalKey = key
    end
    cur, r = nxt, r + 1
  end
  return finalKey, r - 1
end

-- Round robin pairs by the circle method: rounds = { { {i, j}, ... } } (i or j 0 = rests).
local function circle(n)
  local list = {}
  for i = 1, n do list[i] = i end
  if n % 2 == 1 then list[#list + 1] = 0 end
  local m, rounds = #list, {}
  for _ = 1, m - 1 do
    local ps = {}
    for i = 1, m / 2 do ps[#ps + 1] = { list[i], list[m - i + 1] } end
    rounds[#rounds + 1] = ps
    table.insert(list, 2, table.remove(list))
  end
  return rounds
end

-- The whole tournament: { matches, champion, slots, groups, Winner, Loser, Resolve, GroupTable }.
-- results[key] = the winner's name.
function T.Build(format, seeds, results)
  results = results or {}
  local B = builder(seeds, results)
  local n = #seeds
  local champion
  local entrants = {}
  for i = 1, n do entrants[i] = { seed = i } end
  if n < 2 then
    B.champion, B.slots = seeds[1], 0
    return B
  end
  if format == "single" or format == "double" then
    local finalKey, k = knockout(B, "wb", entrants, 1)
    if format == "single" then
      champion = B.Winner(finalKey)
      B.slots = k
    else
      -- Winners round r is played in slot 2r-2 (round 1 in slot 1); losers round 1 in slot 2, losers round 2j in
      -- slot 2j+1 and 2j+1 in slot 2j+2; the grand final last. Losers' brackets halve every second round.
      for _, m in ipairs(B.matches) do if m.col > 1 then m.slot = 2 * m.col - 2 end end
      local size = nextPow2(n)
      local lb = {}
      if k >= 2 then
        -- Losers round 1: the losers of winners round 1, in pairs.
        for i = 1, size / 4 do
          local key = "lb1:" .. i
          B.Add(key, "lb", 1, 2, L.T_LOSERS_N:format(1), { lose = "wb1:" .. (2 * i - 1) }, { lose = "wb1:" .. (2 * i) })
          lb[i] = { win = key }
        end
        for j = 1, k - 1 do
          -- Even round: losers bracket winners against the losers of winners round j + 1.
          local lbRound = 2 * j
          local count = #lb
          local nxt = {}
          for i = 1, count do
            local key = "lb" .. lbRound .. ":" .. i
            local label = (j == k - 1) and L.T_LOSERS_FINAL or L.T_LOSERS_N:format(lbRound)
            -- Pair with winners round j+1's losers in reverse order, so a rematch comes as late as it can.
            B.Add(key, "lb", lbRound, 2 * j + 1, label, lb[i], { lose = "wb" .. (j + 1) .. ":" .. (count - i + 1) })
            nxt[i] = { win = key }
          end
          lb = nxt
          if j < k - 1 then
            lbRound = lbRound + 1
            local paired = {}
            for i = 1, #lb, 2 do
              local key = "lb" .. lbRound .. ":" .. ((i + 1) / 2)
              B.Add(key, "lb", lbRound, 2 * j + 2, L.T_LOSERS_N:format(lbRound), lb[i], lb[i + 1])
              paired[#paired + 1] = { win = key }
            end
            lb = paired
          end
        end
      else
        lb = { { lose = finalKey } }
      end
      local gfSlot = 2 * k
      B.Add("gf", "gf", 1, gfSlot, L.T_GRAND_FINAL, { win = finalKey }, lb[1])
      champion = B.Winner("gf")
      B.slots = gfSlot
    end
  elseif format == "groups" then
    local gCount = n <= 5 and 1 or math.ceil(n / 4)
    for g = 1, gCount do B.groups[g] = {} end
    for i, name in ipairs(seeds) do
      local row = math.floor((i - 1) / gCount)
      local g = (row % 2 == 0) and ((i - 1) % gCount + 1) or (gCount - (i - 1) % gCount)
      table.insert(B.groups[g], name)
    end
    local maxRounds = 0
    local seedOf = {}
    for i, name in ipairs(seeds) do seedOf[name] = i end
    for g, names in ipairs(B.groups) do
      local rounds = circle(#names)
      maxRounds = math.max(maxRounds, #rounds)
      for r, ps in ipairs(rounds) do
        for i, p in ipairs(ps) do
          if p[1] > 0 and p[2] > 0 then
            B.Add("g" .. g .. "r" .. r .. ":" .. i, "g" .. g, r, r, L.T_ROUND_N:format(r),
              { seed = seedOf[names[p[1]]] }, { seed = seedOf[names[p[2]]] })
          end
        end
      end
    end
    -- Knockout: group winners first, then runners-up.
    local adv = {}
    for g = 1, gCount do adv[#adv + 1] = { place = { g, 1 } } end
    for g = 1, gCount do adv[#adv + 1] = { place = { g, 2 } } end
    local finalKey, k = knockout(B, "ko", adv, maxRounds + 1)
    champion = B.Winner(finalKey)
    B.slots = maxRounds + k
  else
    local rounds = circle(n)
    for r, ps in ipairs(rounds) do
      for i, p in ipairs(ps) do
        if p[1] > 0 and p[2] > 0 then
          B.Add("rr" .. r .. ":" .. i, "rr", r, r, L.T_ROUND_N:format(r), { seed = p[1] }, { seed = p[2] })
        end
      end
    end
    B.groups[1] = {}
    for i, name in ipairs(seeds) do B.groups[1][i] = name end
    for _, m in ipairs(B.matches) do m.stage = "g1" end
    local order, _, _, done = B.GroupTable(1)
    for _, m in ipairs(B.matches) do m.stage = "rr" end
    champion = done and order[1] or nil
    B.rrRounds = rounds
    B.slots = #rounds
  end
  B.champion = champion
  -- Who is in each match now.
  for _, m in ipairs(B.matches) do
    m.a, m.b = B.Resolve(m.sa), B.Resolve(m.sb)
    m.w = B.Winner(m.key)
  end
  return B
end

-- The round being played: the lowest slot with a match whose two players are known and that has no winner.
function T.CurrentSlot(B)
  local slot
  for _, m in ipairs(B.matches) do
    if type(m.a) == "string" and type(m.b) == "string" and m.w == nil and (not slot or m.slot < slot) then slot = m.slot end
  end
  return slot
end

-- Matches being played in slot.
function T.Live(B, slot)
  local list = {}
  for _, m in ipairs(B.matches) do
    if m.slot == slot and type(m.a) == "string" and type(m.b) == "string" and m.w == nil then list[#list + 1] = m end
  end
  return list
end

-- Rounds the tournament takes with n entrants (for the Rules page's check; the same schedule as Build).
function T.Rounds(format, n)
  n = math.max(2, n)
  local k = log2(nextPow2(n))
  if format == "single" then return k end
  if format == "double" then return 2 * k end
  if format == "groups" then
    local gCount = n <= 5 and 1 or math.ceil(n / 4)
    local size = math.ceil(n / gCount)
    return (size % 2 == 0 and size - 1 or size) + log2(nextPow2(math.max(2, gCount * 2)))
  end
  return n % 2 == 0 and n - 1 or n
end
