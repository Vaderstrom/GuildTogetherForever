-- The prisoner's banner (SPEC §6): their sentence, the time left, and Pay bail, at the top of the screen while a
-- sentence runs. And the tomato: a red splat on the prisoner's screen when someone throws one. Both are small frames
-- of our own, made out of combat at login; neither is a page.
local _, ns = ...
local L, UI, D, Pu = ns.L, ns.UI, ns.GuildData, ns.Purse
local P, St = ns.Players, ns.Stocks

local B = {}
ns.Banner = B

function B:Build()
  if self.frame then return end
  local f = UI.Create("Frame", UIParent, "BackdropTemplate")
  f:SetSize(440, 58)
  f:SetPoint("TOP", 0, -110)
  f:SetFrameStrata("MEDIUM")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.2, 0.05, 0.04, 0.9)
    f:SetBackdropBorderColor(0.75, 0.22, 0.17, 1)
  end
  f.title = UI.Text(f, "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -8)
  f.title:SetPoint("RIGHT", -130, 0)
  f.sub = UI.Text(f, "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.sub:SetPoint("RIGHT", -130, 0)
  f.sub:SetWordWrap(false)
  f.bail = UI.Button(f, "", 116, function() if B.s then St.PayBail(B.s) end end)
  f.bail:SetPoint("RIGHT", -8, 0)
  f:Hide()
  self.frame = f

  local splat = UI.Create("Frame", UIParent)
  splat:SetAllPoints(UIParent)
  splat:SetFrameStrata("HIGH")
  splat.tex = splat:CreateTexture(nil, "OVERLAY")
  splat.tex:SetAllPoints()
  splat.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
  splat.tex:SetVertexColor(0.9, 0.1, 0.05)
  splat.text = UI.Text(splat, "GameFontNormalHuge", "CENTER")
  splat.text:SetPoint("CENTER", 0, 120)
  splat:Hide()
  splat:SetScript("OnUpdate", function(s)
    local d = GetTime() - (s.at or 0)
    local a = 1 - d / 1.5
    if a <= 0 then s:Hide() else s:SetAlpha(d < 0 and 0 or math.min(1, a)) end
  end)
  self.splat = splat
  -- The tomato itself, flying in from a side of the screen before the splash (SPEC decision 60).
  local tomato = UI.Create("Frame", UIParent)
  tomato:SetSize(40, 40)
  tomato:SetPoint("CENTER", 0, 120)
  tomato:SetFrameStrata("HIGH")
  tomato.tex = tomato:CreateTexture(nil, "OVERLAY")
  tomato.tex:SetAllPoints()
  tomato.tex:SetTexture(ns.MEDIA .. "Dot")
  tomato.tex:SetVertexColor(0.85, 0.16, 0.08)
  tomato.tex:SetAlpha(0)
  self.tomato = tomato
end
B.FLIGHT = 0.45   -- seconds the tomato flies before it splats

function B:Refresh()
  local f = self.frame
  if not f then return end
  local g = D:Current()
  local mine = g and St.Of(g, P:Of(ns.Self(), g)) or {}
  local s = mine[1]
  self.s = s
  if not s then f:Hide() return end
  f.title:SetText(L.ST_YOU_IN:format(L["ACT_" .. s.pun:upper()]))
  local sub = St.Describe(s)
  if s.pun == "stocks" and s.st == "active" and ns.Punish.at == false then sub = sub .. " · " .. L.ST_GO_BACK_SHORT end
  f.sub:SetText(sub)
  local purse = D:Settings().purse
  local amt = s.st == "active" and St.Bail(s.se.pun, purse)
  if amt then
    local money = Pu:Format(Pu.Units(amt, purse), purse)
    f.bail:SetText((s.pun == "radio" and L.ST_BUYOUT or L.ST_BAIL):format(money))
    f.bail:Show()
  else
    f.bail:Hide()
  end
  f:Show()
end

function B:Splat(by)
  local s = self.splat
  if not s then return end
  s.text:SetText(L.ST_SPLAT:format(ns.Display(by)))
  s.at = GetTime()
  if UI.Motion() and self.tomato then
    s.at = s.at + self.FLIGHT
    local side = math.random(0, 1) == 0 and -1 or 1
    UI.Visuals.Fly(self.tomato.tex, side * 520, -160, 140, self.FLIGHT, 0, side * -400, true)
    UI.Visuals.Burst(self.tomato, 20, 20, { 0.85, 0.16, 0.08 }, 10, self.FLIGHT)
  end
  s:SetAlpha(s.at > GetTime() and 0 or 1)
  s:Show()
end

ns:On("LOGIN", function()
  ns.Combat:AfterCombat(function()
    B:Build()
    B:Refresh()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() B:Refresh() end) end
  end)
end)
for _, e in ipairs({ "GUILD_DATA", "STOCKS", "GUILD_CHANGED" }) do ns:On(e, function() B:Refresh() end) end

-- A tomato thrown at us (Guild/Stocks.lua fires it for the main copy only, when it is new).
ns:On("TOMATO", function(id, by)
  local g = D:Current()
  local se = g and g.sentences and g.sentences[id]
  if se and P:IsMe(P:Of(se.to, g), g) then B:Splat(by) end
end)
