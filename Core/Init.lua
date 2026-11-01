-- Guild Together: start-up, saved data, events and chat output.
-- Copied from Journey Together Forever (Core/Init.lua, 29 Oct 2026).
local ADDON, ns = ...
local L = ns.L
ns.ADDON = ADDON
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- The developer's copy (29 Oct 2026, as Journey's): the folder GuildTogetherForever-Dev with its own TOC sits next to
-- the released addon, so either can be turned off in the AddOns list. It keeps its own saved data (the two would
-- otherwise share one table and write over each other). With both turned on, the second one to load stays off: it
-- never sends, draws, filters chat or answers /gtf, and says so once.
ns.DEV = ADDON:find("%-Dev$") ~= nil
local DB_NAME = ns.DEV and "GuildTogetherForeverDevDB" or "GuildTogetherForeverDB"
local CHAR_NAME = ns.DEV and "GuildTogetherForeverDevCharDB" or "GuildTogetherForeverCharDB"
local OTHER = ns.DEV and "GuildTogetherForever" or "GuildTogetherForever-Dev"
local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
if isLoaded and isLoaded(OTHER) then ns.off = OTHER end

-- Game events. Modules call ns:RegisterEvent(event, fn); fn gets (event, ...).
local frame = CreateFrame("Frame")
local handlers = {}
function ns:RegisterEvent(event, fn)
  if not handlers[event] then handlers[event] = {}; frame:RegisterEvent(event) end
  table.insert(handlers[event], fn)
end
-- Errors in our handlers are written to the error log (GuildTogetherForeverDB.errors, read after a /reload), then
-- shown as usual.
ns.ERRORS_MAX = 40
function ns:LogError(kind, msg, stack)
  if not ns.db then return end
  ns.db.errors = type(ns.db.errors) == "table" and ns.db.errors or {}
  table.insert(ns.db.errors, 1, { t = time(), kind = kind, msg = tostring(msg), stack = stack, ver = ns.VERSION })
  while #ns.db.errors > ns.ERRORS_MAX do table.remove(ns.db.errors) end
end

local function trace(err)
  return { msg = err, stack = debugstack and debugstack(2, 12, 0) or (debug and debug.traceback and debug.traceback()) }
end

frame:SetScript("OnEvent", function(_, event, ...)
  if ns.off then
    if event == "PLAYER_LOGIN" then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.ADDON_NAME .. "|r: " .. L.TWO_COPIES:format(ADDON, ns.off)) end
    return
  end
  local n, args = select("#", ...), { ... }
  for _, fn in ipairs(handlers[event]) do
    local ok, e = xpcall(function() fn(event, unpack(args, 1, n)) end, trace)
    if not ok then
      ns:LogError(event, e.msg, e.stack)
      if geterrorhandler then geterrorhandler()(e.msg) else error(e.msg, 0) end
    end
  end
end)

-- A protected action blocked or forbidden for this addon (for example a guild hand-over without a click).
local function blocked(event, addon, fn)
  if addon == ADDON then ns:LogError(event, tostring(fn), debugstack and debugstack(2, 8, 0) or nil) end
end
ns:RegisterEvent("ADDON_ACTION_BLOCKED", blocked)
ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", blocked)

-- Chat output. The setting "Chat messages" decides what is shown: all, important only, or nothing.
function ns:Print(msg, important)
  local mode = ns.Settings and ns.char and ns.Settings:Get("chat") or "all"
  if mode == "off" or (mode == "important" and not important) then return end
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.ADDON_NAME .. "|r: " .. tostring(msg))
end

-- Developer output: always printed.
function ns:Debug(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff8a98c0Guild Together debug|r: " .. tostring(msg))
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  -- Account-wide: every character on the account (a player's main and alts, SPEC §1) and each guild's data.
  -- (GuildTogetherForeverDB, or the developer's copy's GuildTogetherForeverDevDB.)
  _G[DB_NAME] = _G[DB_NAME] or { schema = 1, characters = {}, guilds = {} }
  -- Per character: personal settings.
  _G[CHAR_NAME] = _G[CHAR_NAME] or { schema = 1 }
  ns.db, ns.char = _G[DB_NAME], _G[CHAR_NAME]
  if type(ns.db.characters) ~= "table" then ns.db.characters = {} end
  if type(ns.db.guilds) ~= "table" then ns.db.guilds = {} end
  -- This copy's version (from the TOC; the packager fills it in), shared with the other players.
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  ns.VERSION = meta and meta(ADDON, "Version") or nil
  -- A copy straight from the repository still has the packager's placeholder: a development copy.
  if ns.VERSION and ns.VERSION:find("@", 1, true) then ns.VERSION = nil end
  ns.Settings:Init(ns.char)
  ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
  ns:Fire("LOGIN")
  ns:Print(L.LOADED)
end)
