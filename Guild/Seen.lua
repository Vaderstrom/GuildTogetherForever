-- What this character's own addon sees happen to it (SPEC §8, Games): Guild bingo's squares and the Fishing derby's
-- catch. Each fires ns:Fire("SEEN", what). Nothing here is sent anywhere; the games decide what to report.
--   ding    a level gained              fish    a catch (the loot window says it is fishing loot)
--   duel    a duel won                  boss    a dungeon or raid boss downed (ENCOUNTER_END, success)
--   die     dead                        quest   a quest turned in
--   inn     resting at an inn or city   hearth  the Hearthstone used
--   trade   a trade with a guildie      tomato  a tomato thrown at someone in the Stocks
--   skill   a profession skill up       flight  on a flight path
--   repair  gear repaired at a vendor   group   joined a group
--   loot    an item of rare quality (blue) or better looted
local _, ns = ...

local Se = { HEARTHSTONE = 8690 }
ns.Seen = Se

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function seen(what) ns:Fire("SEEN", what) end
Se.Fire = seen

local function on(event, what, check)
  ns:RegisterEvent(event, function(_, ...) if not check or check(...) then seen(what) end end)
end

on("PLAYER_LEVEL_UP", "ding")
on("LOOT_OPENED", "fish", function() return IsFishingLoot ~= nil and IsFishingLoot() == true end)
on("ENCOUNTER_END", "boss", function(_, _, _, _, success) return not secret(success) and success == 1 end)
on("PLAYER_DEAD", "die")
on("QUEST_TURNED_IN", "quest")
on("PLAYER_UPDATE_RESTING", "inn", function() return IsResting ~= nil and IsResting() == true end)
on("UNIT_SPELLCAST_SUCCEEDED", "hearth", function(unit, _, spell)
  return unit == "player" and not secret(spell) and spell == Se.HEARTHSTONE
end)
on("CHAT_MSG_SKILL", "skill")
on("GROUP_JOINED", "group")
ns:RegisterEvent("PLAYER_CONTROL_LOST", function()
  if C_Timer and UnitOnTaxi then C_Timer.After(1, function() if UnitOnTaxi("player") then seen("flight") end end) end
end)

-- Loot of rare quality or better: the game's "You receive loot: [item]" line, by the item's colour.
local RARE = { "|cff0070dd", "|cffa335ee", "|cffff8000" }
local function mine(msg)
  for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
    local head = type(fmt) == "string" and fmt:match("^(.-)%%") or nil
    if head and head ~= "" and msg:sub(1, #head) == head then return true end
  end
  return false
end
on("CHAT_MSG_LOOT", "loot", function(msg)
  if type(msg) ~= "string" or secret(msg) or not mine(msg) then return false end
  for _, c in ipairs(RARE) do if msg:find(c, 1, true) then return true end end
  return false
end)

ns:On("TRADE_DONE", function(t) if t and t.with and ns.Roster:Rank(t.with) ~= nil then seen("trade") end end)
ns:On("TOMATO", function(_, by) if by == ns.Self() then seen("tomato") end end)
ns.Duels.Listen(function(w) if w == ns.Self() then seen("duel") end end)

-- Repairs: observed when the game's repair function runs (never replaced).
ns:On("LOGIN", function()
  if Se.hooked or not hooksecurefunc or not RepairAllItems then return end
  Se.hooked = true
  hooksecurefunc("RepairAllItems", function() seen("repair") end)
end)
