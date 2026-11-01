-- Personal settings (per character). The Guild Master's settings for the guild (SPEC §3) are guild data, not these.
-- Shape copied from Journey Together Forever (Core/Settings.lua, 29 Oct 2026).
local _, ns = ...
local S = {}
ns.Settings = S

S.DEFAULTS = {
  chat = "all", -- chat messages: "all", "important" or "off"
  alerts = true, -- big lines on the screen for the guild's big moments (UI/Alerts.lua)
  emotes = true, -- an emote with a click that throws a tomato, sentences or challenges (Guild/Announce.lua)
  sounds = true, -- the game's sounds for our big moments (UI/Alerts.lua)
}

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      fill(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

-- Fills in missing settings, so saved data from older versions keeps working.
function S:Init(char)
  if type(char.settings) ~= "table" then char.settings = {} end
  fill(char.settings, self.DEFAULTS)
  self.data = char.settings
end

function S:Get(key) return self.data[key] end

function S:Set(key, value)
  self.data[key] = value
  ns:Fire("SETTING", key, value)
end
