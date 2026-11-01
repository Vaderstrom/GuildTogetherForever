-- The Hall of Fame (SPEC §8, decision 48), in Home: the guild's story. Five features: this week's Gazette with
-- last month's Rolling Pin awards, the latest deeds (written by ranks that may edit them), the Hall of fame, the guild
-- mascot and the memorials. Writing a deed or a memorial opens beside the window.
local _, ns = ...
local L, UI, D, Hall = ns.L, ns.UI, ns.GuildData, ns.Hall
local P, Ch, Tx = ns.Players, ns.Chronicle, ns.Treasury

local DEEDS_SHOWN, MEMORIALS_SHOWN, SEASONS_SHOWN = 20, 12, 4
-- The Gazette's type: the game's book and quest letters (Morpheus), else its large font.
local SERIF = "Fonts\\MORPHEUS.TTF"

local function name(key) return P:Name(key) end
local function who(key)
  local main = P:Main(key)
  return main and UI.Who(main) or P:Name(key)
end
local function num(box) return tonumber(strtrim(box:GetText() or "")) end
local function text(box) return strtrim(box:GetText() or "") end

---------------------------------------------------------------------------
-- The Gazette and the awards
---------------------------------------------------------------------------
-- A gold rule across the card: double (a thick line over a thin one) under and over the masthead, else a hairline;
-- short: a few pixels in the middle, under the headline.
local function rule(f, key, kind)
  local r = f:piece(key, function()
    local fr = CreateFrame("Frame", nil, f.card)
    local g = UI.LOOK.gold
    fr.a = fr:CreateTexture(nil, "ARTWORK")
    fr.a:SetPoint("TOPLEFT")
    fr.a:SetPoint("TOPRIGHT")
    fr.b = fr:CreateTexture(nil, "ARTWORK")
    fr.b:SetPoint("BOTTOMLEFT")
    fr.b:SetPoint("BOTTOMRIGHT")
    fr.b:SetHeight(1)
    fr.a:SetColorTexture(g[1], g[2], g[3], kind == "double" and 0.9 or (kind == "short" and 0.8 or 0.18))
    fr.b:SetColorTexture(g[1], g[2], g[3], 0.55)
    fr.a:SetHeight(kind == "double" and 2 or 1)
    fr.b:SetShown(kind == "double")
    fr:SetHeight(kind == "double" and 5 or 1)
    return fr
  end, "rule:" .. (kind or "hair"))
  local w = key:find("^short") and 40 or f.width
  r:SetSize(w, r:GetHeight())
  r:SetPoint("TOPLEFT", f.card, "TOPLEFT", f.pad + math.floor((f.width - w) / 2), f.y)
  f.y = f.y - r:GetHeight() - 6
end

-- Newspaper type, centred: the masthead and the headline.
local function serif(f, key, words, size, color)
  local t = f:piece(key, function()
    local s = UI.Wrap(f.card, "GameFontNormalLarge", f.width)
    if not s:SetFont(SERIF, size, "") then s:SetFontObject("GameFontNormalLarge") end
    s:SetJustifyH("CENTER")
    s:SetShadowOffset(1, -1)
    return s
  end, "serif:" .. size)
  t:SetWidth(f.width)
  t:SetText(words)
  UI.Color(t, color)
  t:SetPoint("TOPLEFT", f.card, "TOPLEFT", f.pad, f.y)
  f.y = f.y - math.ceil(t:GetStringHeight() or size) - 4
end

-- The Gazette (SPEC decision 53): a newspaper on the glass. Its masthead between gold rules, the week, a photograph of
-- the headline's player, the headline in the game's book letters, then the other stories, a hairline between them.
-- This week's so far, or last week's from Monday's toast (page.gazWeek, UI/Alerts.lua). Since decision 75 it is the
-- front page in the right column; the list beside it has the week's stories and the awards.
local STORY_ICON = { gm = "throne", crown = "crown", cup = "prize", game = "rosette", lvl = "laurel", streak = "duel",
  feat = "book" }
local STORIES_SHOWN = 8

-- The headline's player as a photograph on the page: a small scene of their own, kept in the column.
local function photo(f, key, g)
  local main = key and P:Main(key, g)
  if not main then return end
  local into = f.into
  f.into = nil
  local st = f:Stage("photo", "square")
  f.into = into
  st:Scene("photo:" .. main)
  st:Actor("lead", main, UI.Stage.W / 2, 1, { move = "cheer" })
  st:Done()
end

local function frontPage(f, page, g)
  local z = Ch.Gazette(g, page.gazWeek or time())
  rule(f, "r1", "double")
  serif(f, "mast", z.name, 24, "goldHi")
  rule(f, "r2")
  local stories = z.n == 1 and L.CH_STORY or (z.n > 1 and L.CH_STORIES:format(z.n) or nil)
  local d = f:Text("date", (z.dateline .. (stories and (" · " .. stories) or "")):upper(), "GameFontDisableSmall")
  d:SetJustifyH("CENTER")
  rule(f, "r3", "double")
  f:Space(4)
  photo(f, z.key, g)
  serif(f, "hl", z.headline, 18, "ink")
  rule(f, "short", "short")
  for i, line in ipairs(z.lines) do
    if i > 1 then rule(f, "h" .. i) end
    f:Text("l" .. i, line, "GameFontHighlight")
  end
  if #z.lines == 0 then f:Text("none", L.CH_GAZ_EMPTY, "GameFontDisableSmall"):SetJustifyH("CENTER") end
  rule(f, "r4")
  f:Text("gazNote", L.CH_GAZ_NOTE, "GameFontDisableSmall")
  return {}
end

-- The list: the week's stories, biggest first, and last month's Rolling Pin awards.
local function gazette(f, page)
  local g = D:Current()
  local z = Ch.Gazette(g, page.gazWeek or time())
  f:Strip("week", z.dateline)
  for i, x in ipairs(z.stories) do
    if i > STORIES_SHOWN then break end
    f:Row("st" .. i, { icon = UI.ICON[STORY_ICON[x.kind] or "book"], name = x.d.key and who(x.d.key) or L.CH_THE_GUILD,
      sub = x.d.text, vsub = ns.TimeAgo(x.d.t), sel = i == 1 })
  end
  if #z.stories == 0 then f:Empty("none", L.CH_GAZ_NONE) end
  if page.gazWeek then
    f:Buttons("gazNow", { quiet = true, { L.CH_GAZ_THIS_WEEK, function() page.gazWeek = nil Hall:Refresh() end } })
  end
  f:Space(10)
  -- Last month's Rolling Pin awards.
  local month = Ch.LastMonth(time())
  f:Strip("awards", L.CH_AWARDS_TITLE:format(Tx.PeriodName(month)))
  local list = g and Ch.Awards(g, month) or {}
  for i, x in ipairs(list) do
    f:Row("a" .. i, { icon = UI.ICON.laurel, name = who(x.key), sub = L["CH_AWARD_" .. x.id:upper()], value = x.text })
  end
  if #list == 0 then f:Empty("noAwards", L.CH_AWARDS_NONE) end
  f:Text("awNote", L.CH_AWARDS_NOTE, "GameFontDisableSmall")
  return {}
end

---------------------------------------------------------------------------
-- Deeds, and writing one
---------------------------------------------------------------------------
local function deeds(f, page)
  local g = D:Current()
  local list = g and Ch.Deeds(g) or {}
  local may = D:Can("deeds")
  for i, d in ipairs(list) do
    if i > DEEDS_SHOWN then break end
    local sub = ns.TimeAgo(d.t) .. ((d.m and d.m > 0) and (" · " .. L.CH_MARKS:format(d.m, D:Settings().many)) or "")
    f:Row("d" .. i, { icon = UI.ICON.book,
      name = d.key and who(d.key) or L.CH_THE_GUILD, sub = d.text, vsub = sub,
      tip = { L.CH_DEED_LINE:format(d.key and name(d.key) or L.CH_THE_GUILD, d.text), sub } })
    if d.kind == "feat" and may then f:Buttons("x" .. i, { { L.CH_STRIKE, function() Ch.Strike(d.id) end } }) end
  end
  if #list == 0 then f:Empty("none", L.CH_NO_DEEDS) end
  f:Text("note", L.CH_DEEDS_NOTE, "GameFontDisableSmall")
  if may then return { { L.CH_WRITE_DOTS, function() page.View({ kind = "deed" }) end } } end
  return {}
end

local function deedForm(f, page)
  if not D:Can("deeds") then return nil end
  f:Strip("title", L.CH_WRITE)
  local half = math.floor((f.width - 12) / 2)
  local whoBox = f:Field("who", L.TR_GRANT_WHO, half - 10, nil, true)
  local marks = f:Field("m", L.CH_MARKS_FIELD:format(D:Settings().many), half - 10, half + 12)
  local what = f:Field("what", L.CH_DEED_FIELD, f.width - 12)
  what:SetMaxLetters(Ch.TEXT_MAX)
  -- How it will read in Deeds, as you type (SPEC decision 75).
  for _, box in ipairs({ whoBox, marks, what }) do
    if not box.preview then
      box.preview = true
      box:HookScript("OnTextChanged", function(_, user) if user then Hall:Refresh() end end)
    end
  end
  local typed, earns = text(whoBox), num(marks) or 0
  local full = typed ~= "" and ns.FullName(typed) or nil
  local known = full ~= nil and ns.Roster:Rank(full) ~= nil
  f:Strip("previewHead", L.CH_PREVIEW)
  f:Row("preview", { icon = UI.ICON.book, name = known and UI.Who(full) or (typed ~= "" and typed or L.CH_PREVIEW_WHO),
    sub = text(what) ~= "" and text(what) or L.CH_PREVIEW_WHAT, dim = not known,
    vsub = L.TIME_JUST_NOW .. (earns > 0 and (" · " .. L.CH_MARKS:format(earns, D:Settings().many)) or "") })
  f:Text("note", L.CH_DEEDS_NOTE, "GameFontDisableSmall")
  return { { L.CH_WRITE, function()
    local m = num(marks) or 0
    if m < 0 or m > Ch.MARKS_MAX or m ~= math.floor(m) or not Ch.Write(text(whoBox), text(what), m) then
      ns:Print(L.CH_WRITE_BAD, true)
      return
    end
    what:SetText("")
    marks:SetText("")
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

---------------------------------------------------------------------------
-- The Hall of fame
---------------------------------------------------------------------------
-- The records as a trophy wall (SPEC decision 75): a plaque each, since when its holder has it when this screen saw it.
local function hall(f)
  local g = D:Current()
  local rows = g and Ch.Hall(g) or {}
  local list = {}
  for i, r in ipairs(rows) do
    local since = Ch.Since(g, r.id, r.key)
    list[i] = { icon = UI.ICON[Ch.RECORD_ICON[r.id] or "laurel"], label = r.label, name = P:Main(r.key, g) or r.key,
      value = r.value, sub = since and L.CH_SINCE:format(ns.TimeAgo(since)) or nil, me = P:IsMe(r.key, g) }
  end
  if #list > 0 then f:Plaques("plaques", list, 2) end
  -- Past seasons of the duel ladder, each with its top three (SPEC decision 52).
  local seasons = g and ns.Duels.Seasons(g, time(), SEASONS_SHOWN) or {}
  if #seasons > 0 then f:Strip("seasons", L.CH_SEASONS) end
  for i, x in ipairs(seasons) do
    local places = {}
    for n, e in ipairs(x.top) do places[#places + 1] = L.CH_SEASON_PLACE:format(n, name(e.key), e.r) end
    local title = ns.Duels.SeasonName(x.season)
    f:Row("s" .. i, { icon = UI.ICON.seasons, name = title, sub = table.concat(places, "  "), value = who(x.top[1].key),
      tip = { title, table.concat(places, "\n") } })
  end
  if #rows == 0 and #seasons == 0 then f:Empty("none", L.CH_HALL_NONE) end
  local herald = g and ns.Herald.Herald(g)
  if herald then f:Text("herald", L.CH_HERALD_NOTE:format(ns.Display(herald)), "GameFontDisableSmall") end
  return {}
end

---------------------------------------------------------------------------
-- The mascot
---------------------------------------------------------------------------
local function mascot(f)
  local m = Ch.Mascot(D:Current())
  f:Row("head", { icon = UI.ICON.boar, name = L.CH_MASCOT_TITLE:format(m.name, L["CH_KIND_" .. m.kind:upper()]),
    sub = L.CH_MASCOT_LINE:format(m.level, L["CH_MOOD_" .. m.mood:upper()]), value = tostring(m.fed), vsub = L.CH_MASCOT_FED })
  f:Text("week", L.CH_MASCOT_WEEK:format(m.week))
  if Ch.unfed > 0 then f:Pair("mine", L.CH_MASCOT_MINE, tostring(Ch.unfed)) end
  f:Text("note", L.CH_MASCOT_NOTE, "GameFontDisableSmall")
  return {}
end

-- Beside the list (SPEC decision 75): the pet itself on the square, its level and the fish to the next, its mood, this
-- week's fish and who feeds it most; the Guild Master names it here too.
local FEEDERS_SHOWN = 3
local function petColumn(f, page, g, m)
  ns.Scenes.Mascot(f, m)
  local lo, hi = 5 * m.level * (m.level - 1), 5 * (m.level + 1) * m.level
  f:Strip("lvHead", L.CH_PET_LEVEL:format(m.level), L.CH_PET_NEXT:format(hi - m.fed, m.level + 1))
  f:Bar("lv", (m.fed - lo) / math.max(1, hi - lo), ("%d / %d"):format(m.fed, hi))
  f:Pair("mood", L.CH_PET_MOOD, L["CH_MOOD_" .. m.mood:upper()])
  f:Pair("week", L.CH_PET_WEEK, tostring(m.week))
  local feeders, list = Ch.Feeders(g), {}
  for i = 1, math.min(FEEDERS_SHOWN, #feeders) do
    local e = feeders[i]
    list[i] = { name = P:Main(e.key, g) or e.key, sub = L.CH_PET_FISH:format(e.n), me = P:IsMe(e.key, g) }
  end
  if #list > 0 then
    f:Strip("feeders", L.CH_PET_FEEDERS)
    f:Tiles("feedTiles", list, FEEDERS_SHOWN)
  end
  if D:InCharge() then return { { L.CH_NAME_PET_DOTS, function() page.View({ kind = "petname" }) end } } end
  return {}
end

-- Naming the pet (the Guild Master, as in Guild settings): its name and its kind.
local function petForm(f, page)
  if not D:InCharge() then return nil end
  local m = Ch.Mascot(D:Current())
  f:Strip("title", L.CH_NAME_PET)
  local box = f:Field("name", L.CH_PET_NAME_FIELD:format(D.MASCOT_NAME_MAX), f.width - 12)
  box:SetMaxLetters(D.MASCOT_NAME_MAX)
  if not page.petFilled then
    box:SetText(m.name)
    page.petFilled = true
  end
  page.petKind = page.petKind or m.kind
  local kinds = {}
  for i, k in ipairs(D.MASCOTS) do kinds[i] = { k, L["CH_KIND_" .. k:upper()] } end
  f:Dropdown("kind", L.CH_PET_KIND_FIELD, kinds, page.petKind, function(v) page.petKind = v end)
  local function done()
    page.petFilled, page.petKind = nil, nil
    page.View(nil)
  end
  return { { L.CH_PET_SAVE, function()
    local clean = ns.Raffle.Clean(text(box), D.MASCOT_NAME_MAX)
    if not clean then
      ns:Print(L.CH_PET_BAD:format(D.MASCOT_NAME_MAX), true)
      return
    end
    local kind = page.petKind
    ns.Sync:ChangeSettings(function(x)
      x.mascot.name = clean
      x.mascot.kind = kind
    end)
    done()
  end }, { L.CANCEL, done } }
end

---------------------------------------------------------------------------
-- The memorials, and remembering someone
---------------------------------------------------------------------------
local function memorials(f, page)
  local g = D:Current()
  local list = g and Ch.Memorials(g) or {}
  local may = D:Can("deeds")
  for i, x in ipairs(list) do
    if i > MEMORIALS_SHOWN then break end
    f:Row("m" .. i, { icon = UI.ICON.candle, name = ns.Display(x.e.name), sub = Ch.MemorialLine(x.e), dim = true,
      tip = { ns.Display(x.e.name), Ch.MemorialLine(x.e) } })
    if may then f:Buttons("x" .. i, { { L.CH_FORGET, function() Ch.Forget(x.id) end } }) end
  end
  if #list == 0 then f:Empty("none", L.CH_NO_MEMORIALS, may and L.CH_NO_MEMORIALS_DO:format(UI.Key(L.CH_REMEMBER_DOTS)) or nil) end
  f:Text("note", L.CH_MEM_NOTE, "GameFontDisableSmall")
  if may then return { { L.CH_REMEMBER_DOTS, function() page.View({ kind = "memorial" }) end } } end
  return {}
end

local function memorialForm(f, page)
  if not D:Can("deeds") then return nil end
  f:Strip("title", L.CH_MEMORY)
  local half = math.floor((f.width - 12) / 2)
  local whoBox = f:Field("who", L.TR_GRANT_WHO, half - 10, nil, true)
  local lv = f:Field("lv", L.CH_MEM_LEVEL, half - 10, half + 12)
  local where = f:Field("where", L.CH_MEM_WHERE_FIELD, f.width - 12)
  where:SetMaxLetters(Ch.WHERE_MAX)
  local words = f:Field("words", L.CH_MEM_WORDS, f.width - 12)
  words:SetMaxLetters(Ch.TEXT_MAX)
  return { { L.CH_REMEMBER, function()
    local level = num(lv)
    if text(whoBox) == "" or (level and (level < 1 or level > D.LEVEL_MAX or level ~= math.floor(level)))
      or not Ch.Remember(text(whoBox), text(where), text(words), level) then
      ns:Print(L.CH_MEM_BAD, true)
      return
    end
    for _, b in ipairs({ whoBox, lv, where, words }) do b:SetText("") end
    page.View(nil)
  end }, { L.CANCEL, function() page.View(nil) end } }
end

-- What the right column shows with nothing opened: the Gazette's front page, or the pet beside its list.
local function sidePicture(page)
  local g = D:Current()
  if page.part == "gazette" and g then
    local z = Ch.Gazette(g, page.gazWeek or time())
    return { key = "gazette:" .. z.week, icon = UI.ICON.paper, title = L.CH_GAZETTE, sub = z.dateline,
      draw = function(f) return frontPage(f, page, g) end }
  end
  if page.part == "mascot" and g then
    local m = Ch.Mascot(g)
    return { key = "mascot", icon = UI.ICON.boar, title = m.name, sub = L["CH_KIND_" .. m.kind:upper()],
      draw = function(f) return petColumn(f, page, g, m) end }
  end
  return nil
end

-- The features' status, on the left.
local status = {
  gazette = function()
    local n = #Ch.Gazette(D:Current(), time()).lines
    return n > 0 and L.FEAT_STORIES:format(n) or L.FEAT_NOTHING
  end,
  deeds = function()
    local g = D:Current()
    local d = g and Ch.Deeds(g)[1]
    return d and ns.TimeAgo(d.t) or L.FEAT_NOTHING
  end,
  mascot = function()
    local m = Ch.Mascot(D:Current())
    return m and m.name or ""
  end,
}

Hall:Register({
  id = "chronicle", label = L.PAGE_CHRONICLE, sub = L.PAGE_CHRONICLE_SUB,
  side = sidePicture,
  help = L.CH_GAZ_NOTE .. "\n\n" .. L.CH_AWARDS_NOTE,
  status = function()
    local m = Ch.Mascot(D:Current())
    return m and m.name and (UI.Inline(UI.ICON.boar) .. " " .. m.name) or ""
  end,
  build = function(page)
    Hall:Split(page, {
      tabs = { { "gazette", L.CH_GAZETTE, icon = UI.ICON.paper }, { "deeds", L.CH_TAB_DEEDS, icon = UI.ICON.book },
        { "hall", L.CH_HALL, icon = UI.ICON.laurel }, { "mascot", L.CH_TAB_MASCOT, icon = UI.ICON.boar },
        { "memory", L.CH_TAB_MEMORY, icon = UI.ICON.candle } },
      parts = { gazette = gazette, deeds = deeds, hall = hall, mascot = mascot, memory = memorials },
      views = { deed = deedForm, memorial = memorialForm, petname = petForm },
      status = status,
      save = "chronicleTab",
    })
  end,
  refresh = function(page)
    Hall:DrawRight(page)
  end,
})
