-- Combat: no frames are created while in combat. Work that creates frames is queued and run when combat ends.
-- Toasts and chat messages are not held back: they show during combat too.
-- Copied from Journey Together Forever (Core/Combat.lua, 29 Oct 2026).
local _, ns = ...
local C = { real = false, simulated = false, after = {} }
ns.Combat = C

-- InCombatLockdown() also covers a /reload during combat, before PLAYER_REGEN_DISABLED has been seen.
function C:InCombat() return self.real or self.simulated or InCombatLockdown() end

-- Runs fn now, or when combat ends.
function C:AfterCombat(fn)
  if self:InCombat() then table.insert(self.after, fn) else fn() end
end

local function changed()
  if not C:InCombat() then
    local list = C.after
    C.after = {}
    for _, fn in ipairs(list) do fn() end
  end
  ns:Fire("COMBAT", C:InCombat())
end

function C:SetReal(on) self.real = on and true or false; changed() end
function C:SetSimulated(on) self.simulated = on and true or false; changed() end

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() C:SetReal(true) end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() C:SetReal(false) end)
