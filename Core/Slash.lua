-- /gtf commands. /gtf opens the Guild Together panel under the guild window (UI/Hall.lua).
local _, ns = ...
local L = ns.L

ns.COMMANDS = { { "/gtf", L.CMD_TOGGLE }, { "/gtf alerts", L.CMD_ALERTS }, { "/gtf emotes", L.CMD_EMOTES },
  { "/gtf full", L.CMD_FULL }, { "/gtf options", L.CMD_OPTIONS }, { "/gtf plain", L.CMD_PLAIN }, { "/gtf version", L.CMD_VERSION },
  { "/gtf tour", L.CMD_TOUR }, { "/gtf test", L.CMD_TEST }, { "/gtf scenes", L.CMD_SCENES } }

-- The other copy (the developer's, or the released one) answers /gtf while this one stays off (Core/Init.lua).
if ns.off then return end

SLASH_GUILDTOGETHERFOREVER1 = "/gtf"
SlashCmdList.GUILDTOGETHERFOREVER = function(msg)
  local cmd = (msg or ""):match("^%s*(%S*)"):lower()
  if cmd == "" then
    ns.Hall:Toggle()
  elseif cmd == "test" then
    if (msg or ""):lower():match("^%s*test%s+off") then
      ns:Print(ns.Demo.Off() and L.TEST_DEMO_OFF or L.TEST_DEMO_NONE, true)
    else
      ns.SelfTest:Run()
    end
  elseif cmd == "scenes" then
    ns.SelfTest:Showcase()
  elseif cmd == "brand" then
    -- The pictures for the README and CurseForge, from the demo guild (Dev/SelfTest.lua).
    ns.SelfTest:Brand()
  elseif cmd == "alerts" or cmd == "emotes" then
    local on = ns.Settings:Get(cmd) == false
    ns.Settings:Set(cmd, on)
    ns:Print(L["CMD_" .. cmd:upper() .. (on and "_ON" or "_OFF")], true)
  elseif cmd == "full" then
    -- The Guild Together screen (SPEC decision 64), or back to the guild window.
    ns.Hall:Go(function() ns.Hall:Full(not ns.Hall:IsFull()) end)
  elseif cmd == "tour" then
    -- Getting started (SPEC decision 72): the tour for your rank.
    ns.Tour:Start()
  elseif cmd == "options" then
    ns.Hall:Go(function() ns.Card:Options() end)
  elseif cmd == "plain" then
    -- The failsafe (SPEC decision 58): the game's own guild window again, for every character, after a reload.
    ns.Frame:SetDressed(false)
    ns:Print(L.PLAIN_DONE, true)
    ReloadUI()
  elseif cmd == "version" then
    ns:Print(L.VERSION:format(ns.VERSION or L.VERSION_DEV), true)
  else
    for _, c in ipairs(ns.COMMANDS) do ns:Print(c[1] .. "  -  " .. c[2], true) end
  end
end
