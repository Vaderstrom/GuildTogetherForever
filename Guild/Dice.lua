-- The game's own /roll results (SPEC §8: only these count; typed text cannot fake them). The game says
-- "Name rolls 37 (1-100)" as a system message (RANDOM_ROLL_RESULT) to the roller, their group and players nearby.
-- Each game listens with Dice:Listen(fn(name, value, min, max)); name is "Name-Realm".
local _, ns = ...
local L = ns.L
local Di = { listeners = {} }
ns.Dice = Di

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The game's sentence as a pattern: "%s rolls %d (%d-%d)" -> "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$".
function Di.Pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
  return "^" .. p .. "$"
end

function Di:Parse(msg)
  if type(msg) ~= "string" or secret(msg) then return nil end
  self.pattern = self.pattern or Di.Pattern(RANDOM_ROLL_RESULT)
  if not self.pattern then return nil end
  local name, v, lo, hi = msg:match(self.pattern)
  v, lo, hi = tonumber(v), tonumber(lo), tonumber(hi)
  if not name or not v or not lo or not hi then return nil end
  return ns.FullName(name), v, lo, hi
end

function Di:Listen(fn) self.listeners[#self.listeners + 1] = fn end

-- A roll was seen (from the game, or the self-test's pretend roll).
function Di:Seen(name, v, lo, hi)
  if name == ns.Self() then self.thrown = nil end
  for _, fn in ipairs(self.listeners) do fn(name, v, lo, hi) end
end

-- Is our own roll on its way: asked for less than WAIT seconds ago, and not seen yet? A die rattles meanwhile (SPEC
-- decision 60: it never shows a number the game has not given).
Di.WAIT = 3
function Di:Waiting() return self.thrown ~= nil and GetTime() - self.thrown < self.WAIT end

-- Rolls 1 to max for this character, as /roll would. False when the game has no roll for addons (then the player
-- types /roll max). Silent during the self-test's pretend guild: its rolls are pretend too.
function Di:Roll(max)
  if self.silent then return true end
  if type(RandomRoll) == "function" then
    self.thrown = GetTime()
    RandomRoll(1, max)
    ns:Fire("DICE")
    if C_Timer then C_Timer.After(self.WAIT, function() ns:Fire("DICE") end) end
    return true
  end
  ns:Print(L.ROLL_TYPE:format(max), true)
  return false
end

ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
  local name, v, lo, hi = Di:Parse(msg)
  if name then Di:Seen(name, v, lo, hi) end
end)
