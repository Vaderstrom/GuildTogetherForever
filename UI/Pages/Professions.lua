-- Professions (SPEC §8b, decision 48). Two features: Crafters (find a recipe; the guild's crafters, a row per
-- profession; this character's own professions) and crafting requests. A click on a profession shows its crafters
-- beside the window; a recipe shows who can make it; a request shows what can be done with it (take it, hand it back,
-- got it, take it back); asking opens as a form there.
local _, ns = ...
local L, UI, D, Hall, Pu = ns.L, ns.UI, ns.GuildData, ns.Hall, ns.Purse
local P, Pr = ns.Players, ns.Professions

local REQUESTS_SHOWN, FOUND_SHOWN = 20, 30
-- Professions without recipes (Herbalism, Skinning, Fishing, Archaeology): nothing to open.
local NO_RECIPES = { ["182"] = true, ["393"] = true, ["356"] = true, ["794"] = true }

local function who(key)
  local main = P:Main(key)
  return main and UI.Who(main) or P:Name(key)
end
local function quiet(text) return "|cff9d9d9d" .. text .. "|r" end
local function skill(r, m) return L.PR_SKILL:format(r, m) end

-- A crafter: their main in class colour, and the character when it is an alt.
local function crafter(c)
  local main = P:Main(c.key)
  if main and main ~= c.char then return L.PR_ON:format(UI.Who(main), ns.Short(c.char)) end
  return UI.Who(c.char)
end

-- Opens the game's whisper box to a character.
local function whisper(name)
  local fn = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if fn then fn(ns.Display(name)) end
end

local function back(page) return { L.CANCEL, function() page.View(nil) end } end

---------------------------------------------------------------------------
-- Crafters: finding a recipe (above), the guild's crafters and yours
---------------------------------------------------------------------------
local function crafters(f, page)
  local g = D:Current()
  local profs = g and Pr.Crafters(g) or {}
  f:Strip("guild", L.PR_GUILD)
  for i, b in ipairs(profs) do
    local sel = page.view and page.view.kind == "prof" and page.view.prof == b.prof
    f:Row("p" .. i, { icon = b.i or UI.ICON.anvil, name = b.n,
      sub = #b.list == 1 and L.PR_CRAFTER or L.PR_CRAFTERS:format(#b.list), value = skill(b.best, b.max),
      vsub = L.PR_BEST, sel = sel, onClick = function() page.View({ kind = "prof", prof = b.prof }) end })
  end
  if #profs == 0 then f:Empty("noProf", L.PR_NONE) end
  f:Strip("mine", L.PR_YOURS)
  local mine = Pr.Mine()
  for i, x in ipairs(mine) do
    local sub
    if x.has then sub = L.PR_RECIPES_AT:format(ns.TimeAgo(x.rt))
    elseif not NO_RECIPES[x.prof] then sub = L.PR_OPEN_ONCE end
    f:Row("m" .. i, { icon = x.i or UI.ICON.anvil, name = x.n, sub = sub, value = skill(x.r, x.m) })
  end
  if #mine == 0 then f:Empty("noMine", L.PR_NO_MINE, L.PR_NO_MINE_DO) end
  local at = Pr.SharedAt(g)
  f:Text("shared", at and L.PR_SHARED:format(ns.TimeAgo(at)) or L.PR_NOT_SHARED, "GameFontDisableSmall")
end

---------------------------------------------------------------------------
-- Finding a recipe, and requests
---------------------------------------------------------------------------
local function find(f, page)
  local g = D:Current()
  local box = f:Field("q", L.PR_SEARCH, f.width - 12)
  if not box.watched then
    box.watched = true
    box:SetMaxLetters(60)
    box:HookScript("OnTextChanged", function(b, user)
      if user then page.query = b:GetText() Hall:Refresh() end
    end)
  end
  local q = strtrim(page.query or "")
  if #q < 2 then
    f:Text("hint", L.PR_SEARCH_HINT, "GameFontDisableSmall")
  else
    local found = g and Pr.Search(g, q, FOUND_SHOWN) or {}
    for i, r in ipairs(found) do
      f:Row("r" .. i, { icon = r.icon or UI.ICON.tools, name = r.name, sub = r.pn, value = tostring(r.n), vsub = L.PR_CAN_MAKE,
        onClick = function() page.View({ kind = "recipe", rid = r.rid, name = r.name, pn = r.pn }) end })
    end
    if #found == 0 then f:Empty("none", L.PR_NO_FOUND) end
  end
  crafters(f, page)
  return { { L.PR_ASK_DOTS, function() page.View({ kind = "ask" }) end } }
end

local function requestRow(s, sel, onClick)
  local rq = s.rq
  local state = L["PR_ST_" .. s.st:upper()]
  return { icon = rq.rid and Pr.RecipeIcon(rq.rid) or UI.ICON.anvil, name = rq.what .. " ×" .. rq.n,
    sub = who(P:Of(rq.by)) .. " · " .. ns.TimeAgo(rq.t), value = s.st == "open" and state or quiet(state),
    vsub = rq.tip and Pu:Format(Pu.Units(rq.tip, rq.p), rq.p) or nil, sel = sel, onClick = onClick,
    dim = s.st == "dropped" or s.st == "closed" }
end

local function requests(f, page)
  local g = D:Current()
  local shown = 0
  for i, s in ipairs(g and Pr.Requests(g) or {}) do
    if shown >= REQUESTS_SHOWN then break end
    local mine = P:IsMe(P:Of(s.rq.by))
    -- Finished requests of others fade after a week.
    if s.st == "open" or s.st == "taken" or mine or time() - s.rq.t < 7 * 86400 then
      shown = shown + 1
      f:Row("q" .. i, requestRow(s, false, function() page.View({ kind = "request", id = s.id }) end))
    end
  end
  if shown == 0 then f:Empty("none", L.PR_NO_REQ, L.PR_NO_REQ_DO:format(UI.Key(L.PR_ASK_DOTS))) end
  f:Text("note", L.PR_REQ_NOTE, "GameFontDisableSmall")
  return { { L.PR_ASK_DOTS, function() page.View({ kind = "ask" }) end } }
end

---------------------------------------------------------------------------
-- Beside the window: a profession, a recipe, a request, and asking
---------------------------------------------------------------------------
-- Rows of crafters, with Whisper for those online.
local function crafterRows(f, list, key)
  for i, c in ipairs(list) do
    local online = c.online
    if online == nil then online = c.char == ns.Self() or ns.Roster:Online(c.char) end
    f:Row(key .. i, { icon = UI.ICON.tools, name = crafter(c), sub = online and L.PR_ONLINE or L.PR_AS_OF:format(ns.TimeAgo(c.t)),
      value = skill(c.r, c.m), dim = not online })
    if online and c.char ~= ns.Self() then
      f:Buttons(key .. "w" .. i, { { L.PR_WHISPER, function() whisper(c.char) end } })
    end
  end
end

local function profView(f, page)
  local g = D:Current()
  local b = g and Pr.Profession(g, page.view.prof)
  if not b then return nil end
  f:Row("hero", { icon = b.i or UI.ICON.anvil, name = b.n, sub = #b.list == 1 and L.PR_CRAFTER or L.PR_CRAFTERS:format(#b.list),
    value = skill(b.best, b.max), vsub = L.PR_BEST, sel = true })
  crafterRows(f, b.list, "c")
  return { back(page) }
end

local function recipeView(f, page)
  local g, v = D:Current(), page.view
  local list = g and Pr.WhoKnows(g, v.rid) or {}
  f:Row("hero", { icon = Pr.RecipeIcon(v.rid) or UI.ICON.tools, name = v.name, sub = v.pn, sel = true })
  f:Strip("who", L.PR_WHO_KNOWS)
  crafterRows(f, list, "k")
  if #list == 0 then f:Empty("nobody", L.PR_NOBODY) end
  return { { L.PR_ASK_FOR_IT, function() page.View({ kind = "ask", rid = v.rid, name = v.name }) end }, back(page) }
end

local function requestView(f, page)
  local g = D:Current()
  local s = g and Pr.Request(g, page.view.id)
  if not s then return nil end
  local rq = s.rq
  f:Row("hero", requestRow(s, true))
  f:Text("line", L.PR_REQ_LINE:format(who(P:Of(rq.by)), rq.n, rq.what))
  f:Pair("mats", L.PR_MATS, rq.mats and L.PR_MATS_THEIRS or L.PR_MATS_CRAFTER)
  if rq.tip then f:Pair("tip", L.PR_TIP_LABEL, Pu:Format(Pu.Units(rq.tip, rq.p), rq.p)) end
  if s.maker then f:Pair("maker", L.PR_MAKER, crafter({ char = s.maker, key = P:Of(s.maker) })) end
  if rq.rid then f:Text("knows", L.PR_KNOWN_BY:format(#Pr.WhoKnows(g, rq.rid)), "GameFontDisableSmall") end
  local acts = {}
  local mine = P:IsMe(P:Of(rq.by))
  if s.st == "open" and not mine then acts[#acts + 1] = { L.PR_TAKE, function() Pr.Take(s.id, true) end } end
  if s.st == "taken" and s.maker == ns.Self() then acts[#acts + 1] = { L.PR_HAND_BACK, function() Pr.Take(s.id, false) end } end
  if s.st == "taken" and mine then acts[#acts + 1] = { L.PR_GOT, function() Pr.Got(s.id, s.maker) end } end
  if (s.st == "open" or s.st == "taken") and mine then acts[#acts + 1] = { L.PR_TAKE_BACK, function() Pr.Drop(s.id) end } end
  if not mine and (s.st == "open" or s.st == "taken") and P:Online(P:Of(rq.by)) then
    acts[#acts + 1] = { L.PR_WHISPER, function() whisper(P:Online(P:Of(rq.by))) end }
  end
  acts[#acts + 1] = back(page)
  return acts
end

-- What is asked for is always a recipe a crafter of the guild knows (decided 31 Oct 2026, asked for by the user: "there
-- needs to be an item a profession can craft"): picked from a search of the guild's shared recipes, or from Find a
-- recipe; never typed. RECIPES_SHOWN of the matches show.
local RECIPES_SHOWN = 6

local function pickRecipe(f, page)
  local g = D:Current()
  local box = f:Field("q", L.PR_ASK_FIND, f.width - 12)
  if not box.watched then
    box.watched = true
    box:SetMaxLetters(60)
    box:HookScript("OnTextChanged", function(b, user)
      if user then page.askQuery = b:GetText() Hall:Refresh() end
    end)
  end
  local q = strtrim(page.askQuery or "")
  if #q < 2 then
    f:Text("qHint", L.PR_ASK_FIND_HINT, "GameFontDisableSmall")
    return
  end
  local found = g and Pr.Search(g, q, RECIPES_SHOWN) or {}
  for i, r in ipairs(found) do
    f:Row("pr" .. i, { icon = r.icon or UI.ICON.tools, name = r.name, sub = r.pn, value = tostring(r.n), vsub = L.PR_CAN_MAKE,
      onClick = function()
        page.view.rid, page.view.name = r.rid, r.name
        Hall:Refresh()
      end })
  end
  if #found == 0 then f:Empty("qNone", L.PR_NO_FOUND) end
end

local function askForm(f, page)
  local v = page.view
  local g = D:Current()
  local purse = D:Settings().purse
  f:Strip("title", L.PR_ASK)
  if not v.rid then
    pickRecipe(f, page)
    return { back(page) }
  end
  -- The recipe picked, with how many crafters know it; a click picks another.
  f:Row("pick", { icon = Pr.RecipeIcon(v.rid) or UI.ICON.tools, name = v.name, sel = true,
    sub = L.PR_KNOWN_BY:format(g and #Pr.WhoKnows(g, v.rid) or 0), vsub = L.PR_ASK_OTHER,
    onClick = function() v.rid, v.name = nil, nil Hall:Refresh() end })
  local n = f:Field("n", L.PR_COUNT, 50)
  if n.forRid ~= v.rid then
    n.forRid = v.rid
    n:SetText("1")
  end
  local mats = f:piece("matsBox", function()
    return UI.Check(f.card, L.PR_MATS_MINE, function() return page.askMats == true end, function(on) page.askMats = on end)
  end, "mats")
  mats:SetPoint("TOPLEFT", f.pad, f.y)
  mats:Refresh()
  f:Space(28)
  local tip = f:Field("tipBox", L.PR_TIP:format(purse == "gold" and L.PR_GOLD or D:Settings().many), 90)
  f:Text("note", L.PR_REQ_NOTE, "GameFontDisableSmall")
  return { { L.PR_ASK, function()
    local tipText = strtrim(tip:GetText() or "")
    local tipN = tipText ~= "" and tonumber(tipText) or nil
    if tipText ~= "" and not tipN then ns:Print(L.PR_ASK_BAD, true) return end
    if not Pr.Ask(v.rid, v.name, tonumber(strtrim(n:GetText() or "")), page.askMats, tipN) then
      ns:Print(L.PR_ASK_BAD, true)
      return
    end
    tip:SetText("")
    n.forRid, page.askMats, page.askQuery = nil, nil, nil
    page.Pick("req")
  end }, back(page) }
end

-- The features' status and red number, on the left.
local status = {
  find = function()
    local g = D:Current()
    local n = g and #Pr.Crafters(g) or 0
    return n > 0 and L.FEAT_PROFS:format(n) or L.FEAT_NOTHING
  end,
  req = function()
    local g, n = D:Current(), 0
    for _, s in ipairs(g and Pr.Requests(g) or {}) do if s.st == "open" then n = n + 1 end end
    return n > 0 and L.FEAT_OPEN:format(n) or L.FEAT_NOTHING
  end,
}
local count = { req = function() return Pr.Waiting(D:Current()) end }

-- At a glance, with nothing picked (UI/Side.lua): the orders waiting for a crafter, and the guild's crafts.
local function glance(_, _, f)
  local g = D:Current()
  if not g then return false end
  local drew = false
  local open = {}
  for _, r in ipairs(Pr.Requests(g)) do if r.st == "open" and #open < 3 then open[#open + 1] = r end end
  if #open > 0 then
    f:Strip("gord", L.GL_ORDERS:format(Pr.Waiting(g)))
    for i, r in ipairs(open) do
      f:Row("gord" .. i, { icon = Pr.RecipeIcon(r.rq.rid) or UI.ICON.tools, name = r.rq.what, sub = who(P:Of(r.rq.by, g)) })
    end
    drew = true
  end
  local crafts = Pr.Crafters(g)
  if #crafts > 0 then
    f:Strip("gcr", L.GL_CRAFTS)
    for i, c in ipairs(crafts) do
      if i <= 5 then f:Pair("gcr" .. i, c.n or tostring(c.prof), L.GL_CRAFTERS:format(#(c.list or {}), c.best or 0)) end
    end
    drew = true
  end
  return drew
end

Hall:Register({
  glance = glance,
  id = "professions", label = L.PAGE_PROFESSIONS, sub = L.PAGE_PROFESSIONS_SUB, help = L.PR_HELP,
  status = function()
    local n = Pr.Waiting(D:Current())
    return n > 0 and (UI.Inline(UI.ICON.parcel) .. " " .. L.PR_WAITING:format(n)) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "find", L.PR_CRAFTERS_FEAT, icon = UI.ICON.tools }, { "req", L.PR_TAB_REQ, icon = UI.ICON.parcel } },
      parts = { find = find, req = requests },
      views = { prof = profView, recipe = recipeView, request = requestView, ask = askForm },
      status = status, count = count,
      save = "professionsTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})
