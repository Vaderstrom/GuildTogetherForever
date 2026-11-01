-- Compact serializer for addon messages. Copied from Journey Together Forever (Core/Serialize.lua, 29 Oct 2026).
-- Values: nil, booleans, numbers, strings and tables (any depth).
--   n = nil, t/f = true/false, d<number>; = number, s<text>; = string, { key value ... } = table
-- Strings escape "\" ";" "|" and control bytes, so a message never contains "|" (chat escapes) or "\0".
local _, ns = ...
local S = {}
ns.Serialize = S

local function escape(s)
  return (s:gsub("[%z\1-\31\\;|]", function(c)
    if c == "\\" then return "\\\\" elseif c == ";" then return "\\s" elseif c == "|" then return "\\p" end
    return "\\c" .. string.char(c:byte() + 64)
  end))
end

local PLAIN = { ["\\"] = "\\", s = ";", p = "|" }
local function unescape(s)
  if not s:find("\\", 1, true) then return s end
  local out, i = {}, 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch ~= "\\" then out[#out + 1] = ch; i = i + 1
    else
      local a = s:sub(i + 1, i + 1)
      if a == "c" then out[#out + 1] = string.char(s:byte(i + 2) - 64); i = i + 3
      else out[#out + 1] = PLAIN[a] or a; i = i + 2 end
    end
  end
  return table.concat(out)
end

local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end

local function encode(v, out)
  local t = type(v)
  if v == nil then out[#out + 1] = "n"
  elseif t == "boolean" then out[#out + 1] = v and "t" or "f"
  elseif t == "number" then out[#out + 1] = "d" .. string.format("%.14g", v) .. ";"
  elseif t == "string" then out[#out + 1] = "s" .. escape(v) .. ";"
  elseif t == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, keyOrder)
    for _, k in ipairs(keys) do encode(k, out); encode(v[k], out) end
    out[#out + 1] = "}"
  else
    error("cannot serialize a " .. t)
  end
end

function S.Encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

-- Reads one value at position i. Returns value, next position (or nil on bad input).
local function decode(s, i)
  local c = s:sub(i, i)
  if c == "n" then return nil, i + 1
  elseif c == "t" then return true, i + 1
  elseif c == "f" then return false, i + 1
  elseif c == "d" then
    local j = s:find(";", i, true)
    if not j then return nil, nil end
    local n = tonumber(s:sub(i + 1, j - 1))
    if not n then return nil, nil end
    return n, j + 1
  elseif c == "s" then
    -- Find the first ";" not escaped (escapes are always two bytes: "\" and one more).
    local j = i + 1
    while true do
      local ch = s:sub(j, j)
      if ch == "" then return nil, nil end
      if ch == "\\" then j = j + 2
      elseif ch == ";" then break
      else j = j + 1 end
    end
    return unescape(s:sub(i + 1, j - 1)), j + 1
  elseif c == "{" then
    local t = {}
    i = i + 1
    while true do
      if s:sub(i, i) == "}" then return t, i + 1 end
      if i > #s then return nil, nil end
      local k
      k, i = decode(s, i)
      if not i or k == nil then return nil, nil end
      local v
      v, i = decode(s, i)
      if not i then return nil, nil end
      t[k] = v
    end
  end
  return nil, nil
end

-- Returns the value, or nil and false when the text is not valid.
function S.Decode(s)
  if type(s) ~= "string" or s == "" then return nil, false end
  local ok, v, i = pcall(decode, s, 1)
  if not ok or not i or i ~= #s + 1 then return nil, false end
  return v, true
end
