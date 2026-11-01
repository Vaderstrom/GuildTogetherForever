-- Small helpers shared by every module. Copied from Journey Together Forever (Core/Util.lua, 29 Oct 2026), without
-- what only Journey needs.
local _, ns = ...
local L = ns.L

-- "#C08A2E" or "C08A2E" -> 0.75, 0.54, 0.18
function ns.Hex(hex)
  hex = hex:gsub("^#", "")
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function ns.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Messages between modules: ns:On("SETTING", fn), ns:Fire("SETTING", key, value).
local listeners = {}
function ns:On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

function ns:Fire(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do fn(...) end
end

---------------------------------------------------------------------------
-- Names. Characters are stored as "Name-Realm" and shown as "Name".
---------------------------------------------------------------------------
function ns.Realm()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
  return r
end

function ns.FullName(name)
  if not name or name == "" then return nil end
  name = strtrim(name)
  if name:find("-", 1, true) then return name end
  return name .. "-" .. ns.Realm()
end

-- The character being played.
function ns.Self() return ns.FullName(UnitName("player")) end

function ns.Short(name) return name and (Ambiguate(name, "short")) or "" end

-- "Name" for this realm, "Name-Realm" for another.
function ns.Display(name) return name and (Ambiguate(name, "none")) or "" end

-- The realm of "Name-Realm" (nil for a bare name).
function ns.RealmOf(name) return type(name) == "string" and name:match("%-(.+)$") or nil end

-- Can addon whispers reach this character? They reach your own realm and the realms connected to it. The game lists
-- those (GetAutoCompleteRealms; empty when the realm has no partners). Without that list: yes.
local function realmKey(r) return (r or ""):gsub("[%s%-]", ""):lower() end
function ns.Reachable(name)
  local realm = ns.RealmOf(name)
  if not realm or realmKey(realm) == realmKey(ns.Realm()) then return true end
  local list = GetAutoCompleteRealms and GetAutoCompleteRealms()
  if type(list) ~= "table" then return true end
  for _, r in ipairs(list) do
    if realmKey(r) == realmKey(realm) then return true end
  end
  return false
end

-- The guild of the character being played: its name and the player's rank index (0 = Guild Master), or nil.
function ns.Guild()
  if not IsInGuild() then return nil end
  local name, _, rank = GetGuildInfo("player")
  if not name then return nil end
  return name, rank
end

-- WoW Forever, or retail (where we test until Forever is out)? The game's project ID says it (Forever:
-- WOW_PROJECT_CAMELOT); without it, Forever's interface numbers are the ones below 100000.
function ns.IsForever()
  if WOW_PROJECT_ID and WOW_PROJECT_CAMELOT then return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT end
  return (select(4, GetBuildInfo()) or 0) < 100000
end

-- Trial accounts and accounts without game time cannot send addon messages (Forever, and retail from 12.1.7). They
-- take part like members without the addon (SPEC §10).
function ns.Trial()
  return (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) or false
end

---------------------------------------------------------------------------
-- Time: "just now", "10 min ago", "3 hours ago", "yesterday", "2 days ago".
---------------------------------------------------------------------------
function ns.TimeAgo(t)
  local d = math.max(0, time() - (t or 0))
  if d < 60 then return L.TIME_JUST_NOW end
  if d < 3600 then return L.TIME_MIN:format(math.floor(d / 60)) end
  if d < 86400 then
    local h = math.floor(d / 3600)
    return h == 1 and L.TIME_HOUR or L.TIME_HOURS:format(h)
  end
  if d < 2 * 86400 then return L.TIME_YESTERDAY end
  return L.TIME_DAYS:format(math.floor(d / 86400))
end

-- Time left, short: "20 min", "1 hour", "5 hours", "1 day", "3 days" (seconds).
function ns.TimeLeft(d)
  d = math.max(0, d or 0)
  if d < 3600 then return L.LEFT_MIN:format(math.max(1, math.floor(d / 60))) end
  if d < 86400 then
    local h = math.floor(d / 3600)
    return h == 1 and L.LEFT_HOUR or L.LEFT_HOURS:format(h)
  end
  local n = math.floor(d / 86400)
  return n == 1 and L.LEFT_DAY or L.LEFT_DAYS:format(n)
end

---------------------------------------------------------------------------
-- Addon versions: "v1.2.3" or "1.2.3-beta" -> { 1, 2, 3 }; nil for a development copy ("@project-version@").
---------------------------------------------------------------------------
function ns.ParseVersion(v)
  if type(v) ~= "string" then return nil end
  local a, b, c = v:match("^v?(%d+)%.(%d+)%.?(%d*)")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

-- Is version a newer than b? False when either is unknown.
function ns.NewerVersion(a, b)
  local x, y = ns.ParseVersion(a), ns.ParseVersion(b)
  if not x or not y then return false end
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] > y[i] end
  end
  return false
end

-- Class colours, as the game shows them on dark backgrounds. nil for an unknown class.
local CLS = { WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF", SHAMAN = "0070DD",
  MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A" }
function ns.ClassHex(token) return token and CLS[token] or nil end
