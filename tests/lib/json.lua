-- Minimal JSON decoder for the test fixtures (objects, arrays, strings, numbers, true/false/null).
-- Test-only helper; not part of the addon.

local json = {}

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

function json.decode(s)
  local pos = 1
  local value

  local function fail(msg) error(("json: %s at %d"):format(msg, pos)) end
  local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end

  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if map[e] then
          out[#out + 1] = map[e]; pos = pos + 2
        elseif e == "u" then
          local cp = tonumber(s:sub(pos + 2, pos + 5), 16)
          pos = pos + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16)
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            pos = pos + 6
          end
          out[#out + 1] = utf8char(cp)
        else
          fail("bad escape")
        end
      else
        local e = s:find('["\\]', pos) or (#s + 1)
        out[#out + 1] = s:sub(pos, e - 1)
        pos = e
      end
    end
    return table.concat(out)
  end

  value = function()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local t = {}
      ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws()
        local k = str()
        ws()
        if s:sub(pos, pos) ~= ":" then fail("expected :") end
        pos = pos + 1
        t[k] = value()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then fail("expected , or }") end
      end
    elseif c == "[" then
      pos = pos + 1
      local t = {}
      ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then fail("expected , or ]") end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("unexpected character") end
      pos = pos + #num
      return tonumber(num)
    end
  end

  local v = value()
  return v
end

return json
