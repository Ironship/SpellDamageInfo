-- Reduction test: debuffs that lower the enemy's damage or attack power (Curse of Weakness,
-- Demoralizing Shout and Roar, Hex of Weakness, the pet's Screech), over every English and
-- German description in tests/fixtures/spells.json.
--
--   lua tests/test_reduction.lua [path/to/Parser.lua] [path/to/Locale.lua]
--
-- The expected amounts are read here from each text with a pattern written for that spell's own
-- wording; they never come from the parser. Every other fixture text must give no reduction.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local parserPath = arg and arg[1] or "Parser.lua"
local localePath = arg and arg[2] or "Locale.lua"
local ns = {}
T.loadAddonFile(localePath, ns)
T.loadAddonFile(parserPath, ns)
local ParseReduction = ns.Parser.ParseReduction
T.check(type(ParseReduction) == "function", "Parser.ParseReduction exists")
if type(ParseReduction) ~= "function" then T.finish("test_reduction") end

local rows = json.decode(T.readFile("tests/fixtures/spells.json"))

local function must(v)
  if v == nil then error("expectation pattern did not match", 2) end
  return v
end

local function flat(stat) return function(n) return { amount = tonumber(n), percent = false, stat = stat } end end
local DMG, AP = flat("damage"), flat("attackpower")

-- One pattern per spell and language, taken from the texts themselves.
local WANT = {
  ["Curse of Weakness"] = {
    en = function(s) return DMG(must(s:match("^Damage caused by the target is reduced by (%d+) for 2 min%."))) end,
    de = function(s) return DMG(must(s:match("^Der vom Ziel verursachte Schaden wird 2 Min%. lang um (%d+) reduziert%."))) end,
  },
  ["Demoralizing Shout"] = {
    en = function(s) return AP(must(s:match("^Reduces the melee attack power of all enemies within 10 yards by (%d+) for 30 sec%."))) end,
    de = function(s) return AP(must(s:match("^Verringert 30 Sek%. lang die Nahkampfangriffskraft von Feinden innerhalb eines Radius von 10 Metern um (%d+)%."))) end,
  },
  ["Demoralizing Roar"] = {
    en = function(s) return AP(must(s:match("decreasing nearby enemies' melee attack power by (%d+)%."))) end,
    de = function(s) return AP(must(s:match("verringert damit die Nahkampfangriffskraft von in der Nähe befindlichen Feinden um (%d+) Punkt%(e%)%."))) end,
  },
  ["Hex of Weakness"] = { -- the second number (healing -20%) is not damage
    en = function(s) return DMG(must(s:match("reducing damage caused by (%d+) and reducing the effectiveness of any healing by 20%%"))) end,
    de = function(s) return DMG(must(s:match("verringert den verursachten Schaden um (%d+) sowie die Wirksamkeit jeglicher Heilung um 20%%"))) end,
  },
  ["Screech"] = { -- the hit (7 to 9 damage) is not the reduction
    en = function(s) return AP(must(s:match("attack power of all enemies in melee range by (%d+)%."))) end,
    de = function(s) return AP(must(s:match("Nahkampfreichweite eine Reduzierung ihrer [%a]*[Aa]ngriffskraft um (%d+)%."))) end,
  },
}

local function describe(r)
  if not r then return "nil" end
  return ("%s%s %s"):format(tostring(r.amount), r.percent and "%" or "", tostring(r.stat))
end

local function same(got, want)
  if want == nil then return got == nil end
  return got ~= nil and got.amount == want.amount and got.percent == want.percent and got.stat == want.stat
end

local counts = { texts = 0, want = 0, got = 0, none = 0 }
local seenFamily = {}
for _, row in ipairs(rows) do
  for _, lang in ipairs({ "en", "de" }) do
    local text = row[lang .. "_description"]
    if type(text) == "string" and text:match("%S") then
      counts.texts = counts.texts + 1
      local family = row.namespace == "wowhead-classic" and WANT[row.expected_name]
      local want = family and family[lang](text) or nil
      local got = ParseReduction(text, lang)
      if want then
        counts.want = counts.want + 1
        seenFamily[row.expected_name .. " " .. lang] = true
      else
        counts.none = counts.none + 1
      end
      if T.check(same(got, want), ("%s %s %s [%s] %q: got %s, want %s"):format(row.namespace, tostring(row.id),
        tostring(row.en_name), lang, text, describe(got), describe(want))) and want then
        counts.got = counts.got + 1
      end
    end
  end
end
for name in pairs(WANT) do
  for _, lang in ipairs({ "en", "de" }) do
    T.check(seenFamily[name .. " " .. lang], "fixtures hold " .. name .. " in " .. lang)
  end
end

-- Wordings not in the fixtures: other phrasings, percentages, and texts that must stay nil.
local P = function(n, stat) return { amount = n, percent = true, stat = stat or "damage" } end
local extra = {
  { "en", "Target's physical damage dealt is reduced by 3 for 2 min.", DMG(3) },
  { "de", "Der vom Ziel verursachte körperliche Schaden wird 2 Min. lang um 3 verringert.", DMG(3) },
  { "en", "Reduces the damage dealt by the target by 10% for 10 sec.", P(10) },
  { "de", "Verringert den vom Ziel verursachten Schaden 10 Sek. lang um 10%.", P(10) },
  { "de", "Verringert den vom Ziel verursachten Schaden um 7,5%.", P(7.5) },
  { "en", "Lowers the attack power of all enemies within 8 yards by 1,250 for 30 sec.", AP(1250) },
  { "de", "Verringert die Angriffskraft aller Feinde im Umkreis von 8 Metern 30 Sek. lang um 1.250.", AP(1250) },
  { "en", "Deals 120 Shadow damage to the target and reduces its damage dealt by 5%.", P(5) },
  { "en", "Reduces all damage taken by 10%.", nil },
  { "en", "Deals 120 Shadow damage to the target, reducing its movement speed by 50% for 8 sec.", nil },
  { "de", "Verringert den erlittenen Schaden des Ziels um 10%.", nil },
  { "en", "Reduces the cooldown of your Fear by 2 sec.", nil },
  { "en", "Reduces the target's movement speed by 50% for 8 sec.", nil },
  { "en", "Deals 1,531 Shadow damage to enemies within 10 yds of its target after 20 sec. Damage is reduced beyond 8 targets.", nil },
  { "de", "Fügt Zielen über 8 Ziele hinaus verringerten Schaden zu.", nil },
  { "en", "Increases the damage the target takes by 10.", nil },
  { "en", "Reduces your damage by 10% and the target's healing.", nil },
  { "en", "Reduces the damage of the target's next attack by 3 sec.", nil },
  { "en", "", nil },
}
for i, case in ipairs(extra) do
  local got = ParseReduction(case[2], case[1])
  T.check(same(got, case[3]), ("extra %d [%s] %q: got %s, want %s"):format(i, case[1], case[2], describe(got), describe(case[3])))
end

-- Language detection when none is given
T.check(same(ParseReduction("Der vom Ziel verursachte Schaden wird 2 Min. lang um 31 reduziert."), DMG(31)), "detects German")
T.check(same(ParseReduction("Damage caused by the target is reduced by 31 for 2 min."), DMG(31)), "detects English")

-- The button text: "-N" / "-N%", red
local F = ns.Format
T.eq(F.ReductionText({ amount = 3, percent = false }), "-3", "flat reduction")
T.eq(F.ReductionText({ amount = 146, percent = false }), "-146", "flat reduction, three digits")
T.eq(F.ReductionText({ amount = 10, percent = true }), "-10%", "percent reduction")
T.eq(F.ReductionText({ amount = 7.5, percent = true }), "-7.5%", "percent with a decimal")
T.eq(F.ReductionText({ amount = 12500, percent = false }), "-13k", "large flat reduction")
T.check(F.REDUCTION_COLOR[1] == 1 and F.REDUCTION_COLOR[2] < 0.5 and F.REDUCTION_COLOR[3] < 0.5, "reduction colour is red")

print(("Fixture texts: %d; with a reduction: %d, read correctly: %d; without: %d"):format(counts.texts, counts.want,
  counts.got, counts.none))
T.finish("test_reduction")
