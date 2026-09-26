-- The texts the game client itself shows, from /sdi dump and /sdi dump all (imported by
-- tools/import_dump.py into tests/fixtures/forever_client_texts.json). Forever's German client
-- has its own translation, not Wowhead's Classic German, and leaves some spells Forever changed
-- in English. None of the texts is written here.
--
--   lua tests/test_client_texts.lua [path/to/Parser.lua]
--
-- 1. Language: every German text of the corpus reads as German, and every English one that gives
--    a number reads as English on a German client too.
-- 2. Each client text the corpus also has in Forever's English gives the same kind of result as
--    that English: which parts are shown (damage, over time, heal, shield, per attack ...), the
--    weapon reader's kind, a chance, a reduction. The numbers themselves may differ: the client
--    shows the numbers of its own build. An English text with "?" for its numbers
--    (foreverchanges.pro's Contingency Plan) is no reference.
-- 3. SpellIDs.lua lists every spell id of the corpus, the ids /sdi dump all asks for.
-- 4. The same client in German and in English: where a spell's two texts state the same numbers,
--    the two readings are the same, number for number. Where they do not (a low rank whose
--    numbers grew with the character's level between the two dumps), the pair is counted, not
--    compared; on 2026-09-25 each of the 55 was looked at: 41 read the same anyway (the numbers
--    that differ are rank notes, counts, mana), 14 read their own text's grown numbers.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local parserPath = arg and arg[1] or "Parser.lua"
local ns = {}
T.loadAddonFile(parserPath, ns)
local P = ns.Parser

local corpus = json.decode(T.readFile("tests/fixtures/forever_spellbook_all.json"))
local client = json.decode(T.readFile("tests/fixtures/forever_client_texts.json"))

-- 1. Language
local german, english = 0, 0
for _, r in ipairs(corpus) do
  if r.de_description then
    T.check(P.TextLanguage(r.de_description, "de") == "de", ("%s %d: German text read as English"):format(r.expected_name, r.id))
    german = german + 1
  end
  for _, text in ipairs({ r.en_description or false, r.forever_en_description or false }) do
    if text and P.Read(text, "en").show then
      T.check(P.TextLanguage(text, "de") == "en", ("%s %d: English text with a number read as German on a German client"):format(
        r.expected_name, r.id))
      english = english + 1
    end
  end
end
T.check(P.TextLanguage("Converts 52 Health into 52 Mana for you.", "en") == "en", "an English client stays English")

-- 2. The client's texts against Forever's English
local byID = {}
for _, r in ipairs(corpus) do byID[r.id] = r end

-- what is shown, whichever reader found it
local PARTS = { "direct", "dot", "heal", "hot", "absorb", "healMaxHealth", "perAttack", "perBlock", "perStrike", "every",
  "perRage", "hits", "first" }
local function kind(e)
  local parts = { tostring(e.show) }
  if e.show == "parsed" or e.show == "special" then
    parts[1] = "number"
    for _, k in ipairs(PARTS) do if e[e.show][k] then parts[#parts + 1] = k end end
  end
  if e.show == "weapon" then parts[#parts + 1] = e.weapon.kind end
  if e.proc then parts[#parts + 1] = "chance" end
  if e.reduction then parts[#parts + 1] = "reduction " .. e.reduction.stat end
  return table.concat(parts, " ")
end

local compared, shown, englishOnGerman, noNumbers = 0, 0, 0, 0
for _, c in ipairs(client) do
  local e = P.Read(c.text, c.lang)
  if e.show then shown = shown + 1 end
  if c.lang == "de" and e.lang == "en" then englishOnGerman = englishOnGerman + 1 end
  local r = byID[c.id]
  if r and r.forever_en_description and r.forever_en_description:find(" %? ") then
    noNumbers = noNumbers + 1
  elseif r and r.forever_en_description then
    local want = kind(P.Read(r.forever_en_description, "en"))
    T.check(kind(e) == want, ("%s %d [%s client]: reads as %s, Forever's English as %s"):format(tostring(c.name), c.id, c.lang,
      kind(e), want))
    compared = compared + 1
  end
end
T.check(compared >= 20, ("enough client texts have a Forever English to compare with: %d"):format(compared))

-- 3. SpellIDs.lua
local ids = {}
T.loadAddonFile("SpellIDs.lua", ids)
local listed, count = {}, 0
for id in ids.AllSpellIDs:gmatch("%d+") do listed[tonumber(id)] = true; count = count + 1 end
local missing = 0
for _, r in ipairs(corpus) do if not listed[r.id] then missing = missing + 1 end end
T.eq(missing, 0, "SpellIDs.lua has every spell of the corpus (run tools/make_spell_ids.py)")
T.eq(count, #corpus, "and nothing else")

-- The numbers where the comparison above cannot see them, from patterns of the test's own:
-- each "A bis B" range of an English text on the German client is read as A to B, and a shield
-- whose English reference has no numbers (Contingency Plan) absorbs what its German says.
local ranges, shields = 0, 0
for _, c in ipairs(client) do
  local e = P.Read(c.text, c.lang)
  local v = (e.show == "parsed" or e.show == "special") and e[e.show] or nil
  if c.lang == "de" and e.lang == "en" then
    for a, b in c.text:gmatch("(%d+) bis (%d+)") do
      local found = false
      for _, slot in ipairs({ "direct", "heal" }) do
        if v and v[slot] and v[slot].min == tonumber(a) and v[slot].max == tonumber(b) then found = true end
      end
      T.check(found, ("%s %d: the range %s bis %s, got %s"):format(c.name, c.id, a, b, tostring(e.show)))
      ranges = ranges + 1
    end
  end
  local n = c.text:match("der (%d+) Schaden absorbiert")
  if n then
    T.check(v and v.absorb == tonumber(n), ("%s %d: absorbs %s"):format(c.name, c.id, n))
    shields = shields + 1
  end
end
T.check(ranges >= 6 and shields >= 5, ("ranges and shields checked: %d, %d"):format(ranges, shields))

-- Tranquility: the heal every 2 seconds over the whole channel. Heureka!'s "3
-- Schadensfähigkeiten" is a count of abilities, not damage.
local tranquility = 0
for _, c in ipairs(client) do
  local dur, every, n = c.text:match("(%d+) Sek%. lang alle (%d+) Sek%. (%d+) Gesundheit")
  if n then
    local v = P.Read(c.text, c.lang)
    local hot = v.show and v[v.show] and v[v.show].hot
    local want = tonumber(n) * tonumber(dur) / tonumber(every)
    T.check(hot and hot.total == want and hot.duration == tonumber(dur), ("%s %d: %d over %s sec"):format(c.name, c.id, want, dur))
    tranquility = tranquility + 1
  end
  if c.text:find("Schadensf\195\164higkeiten", 1, true) then
    T.eq(P.Read(c.text, c.lang).show, nil, c.name .. ": a count of abilities is no damage")
  end
end
T.check(tranquility >= 4, "the Tranquility ranks were checked: " .. tranquility)

-- Flametongue Totem: every rank is a bonus on each weapon hit, the later ones worded "Each main hand hit
-- causes N to N" / "Jeder Treffer der Haupthand fügt N bis N", never the totem's own damage
local flametongue = 0
for _, c in ipairs(client) do
  local lo, hi = c.text:match("[Ee]ach [a-z ]-hit causes +(%d+) to (%d+) additional")
  if not lo then lo, hi = c.text:match("Jeder Treffer [a-z ]-f9588gt (%d+) bis (%d+) zus") end
  if lo and (c.name:find("Flametongue", 1, true) or c.name:find("Flammenzunge", 1, true)) then
    local v = P.Read(c.text, c.lang)
    local w = v.show == "weapon" and v.weapon
    T.check(w and w.kind == "perhit" and w.min == tonumber(lo) and w.max == tonumber(hi),
      ("%s %d (%s): %s-%s on each hit"):format(c.name, c.id, c.lang, lo, hi))
    flametongue = flametongue + 1
  end
end
T.check(flametongue >= 8, "the Flametongue Totem ranks were checked: " .. flametongue)

-- An English text of the German client: its German numbers and units the English way
local dark
for _, c in ipairs(client) do if c.id == 1277327 and c.lang == "de" then dark = c.text end end
T.check(dark and P._englishNumbers(dark):find("Cannibalize 1290 of your own Health over 15 sec to gain 1320 Mana", 1, true),
  "Dunkles Opfer r4's 1.290, 1.320 and 15 Sek. read the English way")

-- 4. German against English, the same client
local function canon(v)
  if type(v) == "number" then return string.format("%.2f", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys, out = {}, {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
-- what the player sees; which reader found a number does not matter
local function seen(e)
  local label = (e.show == "parsed" or e.show == "special") and "number" or tostring(e.show)
  local v = e.show and e[e.show == "judgement" and "isJudgement" or e.show]
  return label .. " " .. canon(v) .. " " .. canon(e.reduction) .. " " .. canon(e.proc)
end
-- the numbers a text states, sorted, in the client's own number format
local function numbers(text, lang)
  local t = text
  if lang == "de" then
    t = t:gsub("(%d)%.(%d%d%d)", "%1%2"):gsub("(%d),(%d)", "%1.%2")
  else
    t = t:gsub("(%d),(%d%d%d)", "%1%2")
  end
  local list = {}
  for v in t:gmatch("%d+%.?%d*") do list[#list + 1] = tonumber(v) end
  table.sort(list)
  return canon(list)
end
local pairsByID = {}
for _, c in ipairs(client) do
  pairsByID[c.id] = pairsByID[c.id] or {}
  pairsByID[c.id][c.lang] = c
end
local sameNumbers, otherNumbers = 0, 0
for id, p in pairs(pairsByID) do
  if p.de and p.en then
    if numbers(p.de.text, "de") == numbers(p.en.text, "en") then
      local de, en = seen(P.Read(p.de.text, "de")), seen(P.Read(p.en.text, "en"))
      T.check(de == en, ("%s / %s %d: German reads %s, English %s"):format(p.de.name, p.en.name, id, de, en))
      sameNumbers = sameNumbers + 1
    else
      otherNumbers = otherNumbers + 1
    end
  end
end
T.check(sameNumbers >= 1400, ("most German and English pairs state the same numbers: %d, %d do not"):format(sameNumbers, otherNumbers))

print(("Client texts: %d (%d show a number, %d English on a German client), %d compared with Forever's English, %d not "
  .. "(its English has no numbers); German against English of the same client: %d pairs read the same, %d state other "
  .. "numbers; language checked on %d German and %d English corpus texts; SpellIDs.lua lists %d ids"):format(
  #client, shown, englishOnGerman, compared, noNumbers, sameNumbers, otherNumbers, german, english, count))
T.finish("test_client_texts")
