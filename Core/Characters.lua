-- The account's characters (SPEC §1, Player): every character that logs in is remembered in the account-wide saved
-- data, with its guild. A player's main and alts come from this list, so one player stays one player across their
-- characters (SPEC §10b). Data from other characters is as fresh as their last login.
local _, ns = ...
local CH = {}
ns.Characters = CH

-- Writes this character's entry: name, class, level, guild and when it was last played. level: from
-- PLAYER_LEVEL_UP, which comes before UnitLevel has the new level.
function CH:Update(level)
  local me = ns.Self()
  if not me or not ns.db then return end
  local _, class = UnitClass("player")
  local guild, rank = ns.Guild()
  local e = ns.db.characters[me] or {}
  e.name, e.class, e.level, e.guild, e.rank, e.seen = me, class, level or UnitLevel("player"), guild, rank, time()
  ns.db.characters[me] = e
end

-- This account's other characters, newest first.
function CH:Alts()
  local me, list = ns.Self(), {}
  for name, e in pairs(ns.db.characters) do
    if name ~= me and type(e) == "table" then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
  return list
end

ns:On("LOGIN", function() CH:Update() end)
ns:RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit) if unit == nil or unit == "player" then CH:Update() end end)
ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level) CH:Update(level) end)
