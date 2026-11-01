-- Addon messages between players (docs/ARCHITECTURE.md §2). Two ways: to the whole guild (target "GUILD", the guild
-- addon channel) and whispers to one player (a character outside the guild, SPEC §10b).
-- A message is "TAG:<serialized data>". Long ones are split into "~id:i:n:part" and put together again.
-- Sending goes through a queue with a throttle (a burst of 10, then 1 per second) and waits while the game does not
-- allow addon messages (Midnight rules): in dungeons, raids, battlegrounds and arenas, during a boss encounter, and
-- whenever the game reports a lockdown. Nothing is dropped for that: it is sent when it is allowed again.
-- Copied from Journey Together Forever (Core/Comm.lua, 29 Oct 2026); the guild channel is new here.
local _, ns = ...
local C = { PREFIX = "GTF", handlers = {}, queue = {}, tokens = 10, buffers = {}, recent = {}, fullName = {}, seq = 0,
  heard = {} }
ns.Comm = C
ns.PREFIX = C.PREFIX
C.GUILD = "GUILD"

local BURST, RATE, MAX, CHUNK = 10, 1, 250, 230
local LOCK_WAIT = 5 -- after a lockdown result, try again this many seconds later

-- Results of SendAddonMessage (Enum.SendAddonMessageResult; 11 and 12 since 11.1 / 12.0).
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11
local OFFLINE = RESULT.TargetOffline or 12
-- The game's throttle (too many messages): wait a moment and send it then.
local THROTTLED = { [RESULT.AddonMessageThrottle or 3] = true, [RESULT.ChannelThrottle or 8] = true }
local THROTTLE_WAIT = 1.5

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- fn(sender, data, channel): channel is "GUILD" or "WHISPER".
function C:On(tag, fn) self.handlers[tag] = fn end

-- Addon messages are not allowed now: wait.
function C:Held()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return true end
  if self.encounter or (self.lockedUntil and GetTime() < self.lockedUntil) then return true end
  local inside, kind = IsInInstance()
  return inside and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena") or false
end

-- target: C.GUILD for the whole guild, or a player's "Name-Realm" for a whisper.
-- urgent: goes first in the queue (short messages someone waits for).
-- replace: an older message with this tag to the same target that has not started going out is dropped (a newer
-- copy makes the queued one useless).
function C:Send(target, tag, data, urgent, replace)
  if not target then return end
  if ns.Dev and ns.Dev.Intercept and ns.Dev:Intercept(target, tag, data) then return end
  if target == C.GUILD and not IsInGuild() then return end
  if replace then self:DropTag(target, tag) end
  local body = tag .. ":" .. ns.Serialize.Encode(data)
  if #body <= MAX then
    table.insert(self.queue, urgent and 1 or #self.queue + 1, { target = target, msg = body, tries = 0, tag = tag })
    return
  end
  self.seq = self.seq % 4095 + 1
  local n = math.ceil(#body / CHUNK)
  for i = 1, n do
    local part = ("~%x:%d:%d:"):format(self.seq, i, n) .. body:sub((i - 1) * CHUNK + 1, i * CHUNK)
    self.queue[#self.queue + 1] = { target = target, msg = part, tries = 0, tag = tag, seq = self.seq, part = i }
  end
end

-- Drops queued messages with this tag to target, unless their first part has already gone out (the receiver would
-- wait for the rest of a message that never comes).
function C:DropTag(target, tag)
  local started = {}
  for _, item in ipairs(self.queue) do
    if item.target == target and item.tag == tag and item.seq and item.part ~= 1 then started[item.seq] = true end
  end
  for _, item in ipairs(self.queue) do
    if item.target == target and item.tag == tag and item.seq and item.part == 1 then started[item.seq] = nil end
  end
  for i = #self.queue, 1, -1 do
    local item = self.queue[i]
    if item.target == target and item.tag == tag and not (item.seq and started[item.seq]) then table.remove(self.queue, i) end
  end
end

-- How many messages wait, and to whom.
function C:Pending()
  local by = {}
  for _, item in ipairs(self.queue) do by[item.target] = (by[item.target] or 0) + 1 end
  return #self.queue, by
end

function C:Pump(dt)
  self.tokens = math.min(BURST, self.tokens + dt * RATE)
  if self.waitUntil and GetTime() < self.waitUntil then return end
  while self.tokens >= 1 and #self.queue > 0 and not self:Held() do
    local item = table.remove(self.queue, 1)
    local guild = item.target == C.GUILD
    if not guild then
      local now = GetTime()
      self.recent[item.target] = now
      self.recent[ns.Short(item.target)] = now
      self.fullName[ns.Short(item.target)] = item.target
    end
    local result = C_ChatInfo.SendAddonMessage(self.PREFIX, item.msg, guild and "GUILD" or "WHISPER", not guild and item.target or nil)
    if result == LOCKDOWN then
      -- Not allowed right now: keep it (and everything after it) and try again a little later.
      table.insert(self.queue, 1, item)
      self.lockedUntil = GetTime() + LOCK_WAIT
      break
    elseif THROTTLED[result] then
      table.insert(self.queue, 1, item)
      self.waitUntil = GetTime() + THROTTLE_WAIT
      break
    elseif result == OFFLINE and not guild then
      -- The game says the player is offline: no use trying again, or sending the rest of what was for them.
      self:DropFor(item.target)
      ns:Fire("OFFLINE", item.target)
    else
      local failed = result == false or (type(result) == "number" and result ~= 0)
      if failed and item.tries < 3 then
        item.tries = item.tries + 1
        table.insert(self.queue, 1, item)
        break
      end
    end
    self.tokens = self.tokens - 1
  end
end

-- Forgets the queued messages to one player.
function C:DropFor(target)
  for i = #self.queue, 1, -1 do if self.queue[i].target == target then table.remove(self.queue, i) end end
end

function C:Receive(prefix, msg, channel, sender)
  -- During a lockdown the game hides incoming text and sender (secret values): such a message cannot be read.
  if secret(prefix) or secret(msg) or secret(sender) or secret(channel) then return end
  if prefix ~= self.PREFIX or (channel ~= "WHISPER" and channel ~= "GUILD") or type(msg) ~= "string" or not sender then return end
  sender = ns.FullName(sender)
  -- The game echoes our own guild messages back to us.
  if channel == "GUILD" and sender == ns.Self() then return end
  if msg:sub(1, 1) == "~" then
    local id, i, n, part = msg:match("^~(%x+):(%d+):(%d+):(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not id or not i or not n or i < 1 or i > n then return end
    local key = sender .. ":" .. id
    local buf = self.buffers[key]
    -- A message is given up when no part came for a minute.
    if not buf or GetTime() - buf.time > 60 or buf.n ~= n then buf = { parts = {}, got = 0, n = n }; self.buffers[key] = buf end
    buf.time = GetTime()
    if not buf.parts[i] then buf.parts[i] = part; buf.got = buf.got + 1 end
    if buf.got < n then return end
    self.buffers[key] = nil
    msg = table.concat(buf.parts)
  end
  local tag, payload = msg:match("^(%u+):(.*)$")
  local fn = tag and self.handlers[tag]
  if not fn then return end
  local data, ok = ns.Serialize.Decode(payload)
  if not ok then return end
  -- Who has the addon: everyone heard from this session.
  self.heard[sender] = GetTime()
  fn(sender, data, channel)
end

-- Developer tools: a pretend player's message goes through the same path as a real one.
function C:Inject(sender, tag, data, channel)
  self:Receive(self.PREFIX, tag .. ":" .. ns.Serialize.Encode(data), channel or "GUILD", sender)
end

-- Whispers to players who are offline make the game say "No player named X is currently playing."
-- Hide that line for names the addon whispered in the last 10 seconds, and tell the addon that player is offline.
local function hideOffline(_, _, msg)
  local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
  if not fmt or secret(msg) or type(msg) ~= "string" then return false end
  local now = GetTime()
  for name, t in pairs(C.recent) do
    if now - t < 10 and msg == fmt:format(name) then
      ns:Fire("OFFLINE", C.fullName[name] or ns.FullName(name))
      return true
    end
  end
  return false
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX) end
local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter and not ns.off then addFilter("CHAT_MSG_SYSTEM", hideOffline) end

ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender) C:Receive(prefix, msg, channel, sender) end)
-- A boss encounter (also out in the world): addon messages wait until it ends.
ns:RegisterEvent("ENCOUNTER_START", function() C.encounter = true end)
ns:RegisterEvent("ENCOUNTER_END", function() C.encounter = false end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() C.encounter = false end)
ns:On("LOGIN", function() C_Timer.NewTicker(0.2, function() C:Pump(0.2) end) end)
