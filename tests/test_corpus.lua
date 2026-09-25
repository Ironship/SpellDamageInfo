-- Parser.Read over tests/fixtures/forever_spellbook_all.json: every rank of every ability of all
-- nine classes (1519 spells; Classic's English and German from Wowhead, Forever's own English
-- from foreverchanges.pro). None of the texts is written here.
--
--   lua tests/test_corpus.lua [path/to/Parser.lua]
--
-- 1. What the player sees must not depend on the game's language: for every spell with both
--    texts, German gives the same decision and the same numbers as English. A handful of rows
--    are known to differ in Wowhead's own data, and are listed with the reason.
-- 2. The new readers carry the numbers the English text states, worked out here with patterns
--    of the test's own: shields, seals' Judgements, finishers.
-- 3. A summary of what is shown, per class, over Forever's English.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local parserPath = arg and arg[1] or "Parser.lua"
local ns = {}
T.loadAddonFile(parserPath, ns)
local P = ns.Parser

local rows = json.decode(T.readFile("tests/fixtures/forever_spellbook_all.json"))
local n = tonumber

-- A result as text, numbers rounded to two decimals, keys sorted: two results are the same when
-- their texts are.
local function canon(v)
  if type(v) == "number" then return string.format("%.2f", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys, out = {}, {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function shown(e)
  if not e.show then return "nothing" end
  return e.show .. " " .. canon(e[e.show == "judgement" and "isJudgement" or e.show])
end

-- Wowhead's German differs from its English here, not the parser:
local KNOWN = {
  [11275] = "Rupture r6: the German says 6 seconds for one point, the English 8",
  [19506] = "Trueshot Aura: the German keeps 'attack power' only inside talent-text brackets",
  [20905] = "Trueshot Aura, as above",
  [20906] = "Trueshot Aura, as above",
}

-- 1. German agrees with English
local both, agree, known = 0, 0, 0
for _, r in ipairs(rows) do
  if r.en_description and r.de_description then
    both = both + 1
    local en, de = P.Read(r.en_description, "en"), P.Read(r.de_description, "de")
    local same = shown(en) == shown(de) and canon(en.reduction) == canon(de.reduction)
    if KNOWN[r.id] then
      known = known + 1
      T.check(not same, ("%s %d is listed as differing in Wowhead's data but now agrees: %s"):format(r.expected_name, r.id, KNOWN[r.id]))
    else
      T.check(same, ("%s %d r%s: English shows %s / %s, German %s / %s"):format(r.expected_name, r.id, tostring(r.rank),
        shown(en), canon(en.reduction), shown(de), canon(de.reduction)))
      if same then agree = agree + 1 end
    end
  end
end

-- 2. The new readers against the English text's own numbers
local function strip(text) return (text:gsub("%b[]", "")):gsub(",(%d%d%d)", "%1"):lower() end
local checked = { absorb = 0, judgement = 0, finisher = 0 }
local SHIELDS = { ["Power Word: Shield"] = true, ["Ice Barrier"] = true, ["Mana Shield"] = true, ["Fire Ward"] = true,
  ["Frost Ward"] = true, ["Shadow Ward"] = true }
for _, r in ipairs(rows) do
  for _, text in ipairs({ r.en_description or false, r.forever_en_description or false }) do
    if text then
      local t = strip(text)
      local e = P.Read(text, "en")
      if SHIELDS[r.expected_name] then
        local want = n(t:match("absorbing (%d+)") or t:match("absorbs (%d+)"))
        T.check(e.show == "special" and e.special.absorb == want, ("%s %d: absorbs %s, got %s"):format(r.expected_name, r.id,
          tostring(want), canon(e.special)))
        checked.absorb = checked.absorb + 1
      end
      local judge = t:match("unleashing this seal's energy.*")
      if judge then
        T.check(e.isSeal, ("%s %d: a seal"):format(r.expected_name, r.id))
        local lo, hi = judge:match("(%d+%.?%d*) to (%d+%.?%d*) holy damage")
        if lo then
          T.check(e.judgement and e.judgement.direct.min == n(lo) and e.judgement.direct.max == n(hi),
            ("%s %d: Judgement %s-%s, got %s"):format(r.expected_name, r.id, lo, hi, canon(e.judgement)))
        else
          T.check(not e.judgement, ("%s %d: a Judgement with no damage, got %s"):format(r.expected_name, r.id, canon(e.judgement)))
        end
        checked.judgement = checked.judgement + 1
      end
      if t:find("finishing move", 1, true) and t:find("5 points:", 1, true) then
        local lo, hi = t:match("5 points: *(%d+)%-(%d+) damage")
        local total, dur = t:match("5 points: *(%d+) damage over (%d+) sec")
        local f = e.finisher
        if lo then
          T.check(f and f.top == 5 and f.points[5].min == n(lo) and f.points[5].max == n(hi),
            ("%s %d: 5 points %s-%s, got %s"):format(r.expected_name, r.id, lo, hi, canon(f)))
          checked.finisher = checked.finisher + 1
        elseif total then
          T.check(f and f.top == 5 and f.points[5].total == n(total) and f.points[5].duration == n(dur),
            ("%s %d: 5 points %s over %s, got %s"):format(r.expected_name, r.id, total, dur, canon(f)))
          checked.finisher = checked.finisher + 1
        end
      end
    end
  end
end
T.check(checked.absorb >= 30 and checked.judgement >= 40 and checked.finisher >= 40,
  ("enough of each family was checked: %d shields, %d seals, %d finishers"):format(checked.absorb, checked.judgement, checked.finisher))

-- Judgement itself is recognised in both languages and in Forever's text
for _, r in ipairs(rows) do
  if r.expected_name == "Judgement" then
    for _, pair in ipairs({ { r.en_description, "en" }, { r.de_description, "de" }, { r.forever_en_description, "en" } }) do
      if pair[1] then T.check(P.Read(pair[1], pair[2]).show == "judgement", "Judgement " .. pair[2] .. " is Judgement") end
    end
  end
end

-- 3. What is shown, per class, over Forever's English
local perClass, order = {}, {}
for _, r in ipairs(rows) do
  local text = r.forever_en_description or r.en_description
  if text then
    local c = perClass[r.class]
    if not c then c = { shown = 0, reduction = 0, none = 0, total = 0 }; perClass[r.class] = c; order[#order + 1] = r.class end
    local e = P.Read(text, "en")
    c.total = c.total + 1
    if e.show then c.shown = c.shown + 1 elseif e.reduction then c.reduction = c.reduction + 1 else c.none = c.none + 1 end
  end
end
for _, cls in ipairs(order) do
  local c = perClass[cls]
  print(("  %-8s %4d ranks: %4d with a number, %3d a reduction, %4d nothing (utility, chance, seals)"):format(cls, c.total, c.shown, c.reduction, c.none))
end
print(("Corpus: %d spells; %d with both languages, German agreeing with English in %d, %d known Wowhead differences; "
  .. "checked %d shields, %d seals, %d finishers"):format(#rows, both, agree, known, checked.absorb, checked.judgement, checked.finisher))
T.finish("test_corpus")
