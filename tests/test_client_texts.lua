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
--    that English: what is shown, the weapon reader's kind, a chance, a reduction. The numbers
--    themselves may differ: the client shows the numbers of its own build.
-- 3. SpellIDs.lua lists every spell id of the corpus, the ids /sdi dump all asks for.

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

local function kind(e)
  local parts = { tostring(e.show) }
  if e.show == "weapon" then parts[#parts + 1] = e.weapon.kind end
  if e.proc then parts[#parts + 1] = "chance" end
  if e.reduction then parts[#parts + 1] = "reduction " .. e.reduction.stat end
  return table.concat(parts, " ")
end

local compared, shown, englishOnGerman = 0, 0, 0
for _, c in ipairs(client) do
  local e = P.Read(c.text, c.lang)
  if e.show then shown = shown + 1 end
  if c.lang == "de" and e.lang == "en" then englishOnGerman = englishOnGerman + 1 end
  local r = byID[c.id]
  if r and r.forever_en_description then
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

print(("Client texts: %d (%d show a number, %d English on a German client), %d compared with Forever's English; "
  .. "language checked on %d German and %d English corpus texts; SpellIDs.lua lists %d ids"):format(#client, shown,
  englishOnGerman, compared, german, english, count))
T.finish("test_client_texts")
