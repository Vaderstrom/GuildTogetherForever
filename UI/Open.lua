-- The key binding "Open Guild Together" (Bindings.xml, SPEC §2). Opening the guild window from addon code would
-- taint it (CLAUDE.md), so the key presses the game's own guild button through a secure button, and our tab opens
-- once the window shows (a second press closes the window, as the game's own key does). GTFOpenButton and the
-- BINDING_ texts are globals only because key bindings need them.
local _, ns = ...
local L = ns.L

BINDING_HEADER_GUILDTOGETHER = L.ADDON_NAME
_G["BINDING_NAME_CLICK GTFOpenButton:LeftButton"] = L.BINDING_OPEN

local function build()
  local guildButton = GuildMicroButton
  if not guildButton or ns.openButton then return end
  local b = CreateFrame("Button", "GTFOpenButton", UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "click")
  b:SetAttribute("clickbutton", guildButton)
  b:SetScript("PostClick", function() C_Timer.After(0, function() ns.Hall:Open() end) end)
  ns.openButton = b
end

ns:On("LOGIN", function() ns.Combat:AfterCombat(build) end)
