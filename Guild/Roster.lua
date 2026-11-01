-- The game's guild roster, read only: who is in the guild, their rank and who is online (SPEC §1, Ranks and
-- Authority). Guild Together never changes ranks. Rank index 0 is the Guild Master.
local _, ns = ...
local R = { ranks = {}, online = {}, levels = {}, classes = {}, seen = {}, ready = false }
ns.Roster = R

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Reads the roster again. ready: the game has sent it (it is empty until then).
function R:Refresh()
  wipe(self.ranks)
  wipe(self.online)
  wipe(self.levels)
  wipe(self.classes)
  wipe(self.seen)
  local n = IsInGuild() and GetNumGuildMembers() or 0
  if secret(n) then return end
  for i = 1, n do
    local name, _, rank, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
    if name and not secret(name) and not secret(rank) then
      local full = ns.FullName(name)
      self.ranks[full] = rank
      self.online[full] = online and true or nil
      if not secret(level) then self.levels[full] = tonumber(level) end
      if type(class) == "string" and not secret(class) then self.classes[full] = class end
      -- When an offline member was last online (the game says years, months, days and hours ago).
      if not online and GetGuildRosterLastOnline then
        local y, mo, d, h = GetGuildRosterLastOnline(i)
        if y and not secret(y) and not secret(mo) and not secret(d) and not secret(h) then
          self.seen[full] = time() - ((((tonumber(y) or 0) * 12 + (tonumber(mo) or 0)) * 30 + (tonumber(d) or 0)) * 24
            + (tonumber(h) or 0)) * 3600
        end
      end
    end
  end
  local was = self.ready
  self.ready = n > 0
  ns:Fire("ROSTER", not was and self.ready)
end

-- The self-test's pretend guild (Dev/Sandbox.lua) replaces the roster while it runs:
-- R.pretend = { ranks = { ["Name-Realm"] = index }, names = { "Guild Master", "Officer", ... }, classes = { [name] = "MAGE" } }.
function R:Ready() return self.pretend ~= nil or self.ready end

-- A character's rank index, or nil when they are not in the roster (or it has not arrived yet). This character's
-- own rank comes from the game directly.
function R:Rank(name)
  if self.pretend then return self.pretend.ranks[name] end
  if name == ns.Self() then
    local _, rank = ns.Guild()
    if rank ~= nil then return rank end
  end
  return self.ranks[name]
end

function R:IsGM(name) return self:Rank(name) == 0 end

-- A member's level from the roster (in the pretend guild: the cap, so everyone pays the tax).
function R:Level(name)
  if self.pretend then return self.pretend.ranks[name] ~= nil and 60 or nil end
  return self.levels[name]
end

-- A member's class token ("HUNTER") from the roster, or nil.
function R:Class(name)
  if self.pretend then return self.pretend.classes and self.pretend.classes[name] end
  return self.classes[name]
end

-- Every member in the roster: { [name] = rank }.
function R:All() return self.pretend and self.pretend.ranks or self.ranks end

-- Is this member online now? (In the pretend guild: the pretend member's own switch, Dev/Peers.lua.)
function R:Online(name)
  if self.pretend then
    local p = ns.Peers and ns.Peers:Get(name)
    return p ~= nil and p.online
  end
  return self.online[name] == true
end

-- When an offline member was last online (a time()), or nil (online, unknown, or the pretend guild).
function R:Seen(name)
  if self.pretend then return nil end
  return self.seen[name]
end

-- A character's rank's name ("Officer"), or nil.
function R:RankName(name)
  local i = self:Rank(name)
  if i == nil then return nil end
  if self.pretend then return self.pretend.names and self.pretend.names[i + 1] end
  return GuildControlGetRankName and GuildControlGetRankName(i + 1) or nil
end

-- The guild's ranks below the Guild Master: { { index = 1, name = "Officer" }, ... }.
function R:Ranks()
  local list = {}
  if self.pretend then
    for i = 2, #self.pretend.names do list[#list + 1] = { index = i - 1, name = self.pretend.names[i] } end
    return list
  end
  local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
  for i = 2, n do list[#list + 1] = { index = i - 1, name = GuildControlGetRankName(i) or "" } end
  return list
end

-- The ranks the game lets read officer chat (decision 50): { [name] = true }, or nil when the game cannot tell.
function R:OfficerRanks()
  local flags = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
  local set = {}
  if self.pretend then
    set[self.pretend.names[2] or ""] = true
    return set
  end
  if not flags then return nil end
  for _, r in ipairs(self:Ranks()) do
    local f = flags(r.index + 1)
    if type(f) ~= "table" then return nil end
    if f[3] == true then set[r.name] = true end
  end
  return set
end

function R:Ask()
  if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

ns:On("LOGIN", function()
  R:Ask()
  R:Refresh()
end)
ns:RegisterEvent("GUILD_ROSTER_UPDATE", function() R:Refresh() end)
ns:RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit)
  if unit ~= nil and unit ~= "player" then return end
  R:Ask()
  R:Refresh()
  ns:Fire("GUILD_CHANGED")
end)
