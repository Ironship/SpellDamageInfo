-- Parser test over every English and German description in tests/fixtures/spells.json.
--
--   lua tests/test_parser.lua [path/to/Parser.lua]
--
-- The expected numbers are worked out here from each text with patterns written for that
-- spell's own wording (or, for the modern Retail rows, written down by hand from the text).
-- They never come from the parser. A row whose wording should give no number (per-combo-point
-- tables, weapon-damage attacks, talents, mana drains, ambiguous texts) expects nil.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local parserPath = arg and arg[1] or "Parser.lua"
local ns = {}
T.loadAddonFile(parserPath, ns)
local Parse = ns.Parser.Parse

local rows = json.decode(T.readFile("tests/fixtures/spells.json"))
local n = tonumber

---------------------------------------------------------------------------------------------
-- Expectation helpers
---------------------------------------------------------------------------------------------

local function must(...)
  for i = 1, select("#", ...) do
    if select(i, ...) == nil then error("expectation pattern did not match", 2) end
  end
  return ...
end

local function D(lo, hi) return { min = n(lo), max = n(hi or lo) } end
local function O(total, dur) return { total = n(total), duration = n(dur) } end

-- nil with the reason category, for the report
local function NIL(reason) return { none = reason } end

local function dotOnly(school) return function(total, dur) return { dot = O(total, dur), school = school } end end

---------------------------------------------------------------------------------------------
-- Classic wordings (Wowhead Classic Era, Classic item spells, Cataclysm), one extractor per spell
---------------------------------------------------------------------------------------------

local F = {}

F["Corruption"] = {
  en = function(s) local a, d = must(s:match("causing (%d+) Shadow damage over (%d+) sec")); return dotOnly("shadow")(a, d) end,
  de = function(s) local d, a = must(s:match("(%d+) Sek%. lang (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
F["Curse of Agony"] = {
  en = F["Corruption"].en,
  de = function(s) local d, a = must(s:match("fügt (%d+) Sek%. lang (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
F["Immolate"] = {
  en = function(s)
    local a, t, d = must(s:match("for %[(%d+) %* %(%(%(1%)%)%)%] Fire damage and then an additional (%d+) Fire damage over (%d+) sec"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local a, d, t = must(s:match("ihm %[(%d+) %* %(%(%(1%)%)%)%] Feuerschaden sowie im Verlauf von (%d+) Sek%. insgesamt (%d+) zusätzlichen Feuerschaden"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
}
F["Siphon Life"] = { -- a health drain: damage, but the text names no school
  en = function(s)
    local a, i, l = must(s:match("Transfers (%d+) health from the target to the caster every (%d+) sec%..-Lasts (%d+) sec"))
    return { dot = O(n(a) * n(l) / n(i), l) }
  end,
  de = function(s)
    local i, a, l = must(s:match("alle (%d+) Sek%. (%d+) Punkt%(e%) Gesundheit vom Ziel auf den Zaubernden%. Hält (%d+) Sek%. lang an"))
    return { dot = O(n(a) * n(l) / n(i), l) }
  end,
}
F["Curse of Doom"] = { -- one hit after a minute: counted as over-time damage lasting 60 sec
  en = function(s) local a = must(s:match("causing (%d+) Shadow damage after 1 min")); return dotOnly("shadow")(a, 60) end,
  de = function(s) local a = must(s:match("nach 1 Min%. (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, 60) end,
}
F["Drain Life"] = {
  en = function(s)
    local a, l = must(s:match("Transfers (%d+) health every second from the target to the caster%..-Lasts (%d+) sec"))
    return { dot = O(n(a) * n(l), l) }
  end,
  de = function(s)
    local a, l = must(s:match("pro Sekunde (%d+) Punkt%(e%) Gesundheit vom Ziel auf den Zaubernden%. Hält (%d+) Sek"))
    return { dot = O(n(a) * n(l), l) }
  end,
}
F["Drain Soul"] = {
  en = F["Corruption"].en,
  de = function(s) local d, a = must(s:match("verursacht (%d+) Sek%. lang (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
F["Drain Mana"] = { en = function() return NIL("mana") end, de = function() return NIL("mana") end }
F["Health Funnel"] = {
  en = function(s)
    local a, d = must(s:match("Gives (%d+) health to the caster's pet every second for (%d+) sec"))
    return { hot = O(n(a) * n(d), d) }
  end,
  de = function(s)
    local d, a = must(s:match("(%d+) Sek%. lang in jeder Sekunde (%d+) Punkt%(e%) Gesundheit"))
    return { hot = O(n(a) * n(d), d) }
  end,
}
F["Rain of Fire"] = {
  en = function(s) local a, d = must(s:match("for (%d+) Fire damage over (%d+) sec")); return dotOnly("fire")(a, d) end,
  de = function(s) local d, a = must(s:match("der (%d+) Sek%. lang Feinde im Wirkungsbereich mit (%d+) Punkt%(en%) Feuerschaden")); return dotOnly("fire")(a, d) end,
}
F["Hellfire"] = { -- the damage to the caster himself is not the spell's damage
  en = function(s)
    local a, i, l = must(s:match("and (%d+) Fire damage to all nearby enemies every (%d+) sec%..-Lasts (%d+) sec"))
    return dotOnly("fire")(n(a) * n(l) / n(i), l)
  end,
  de = function(s)
    local i, a, l = must(s:match("sowie alle (%d+) Sek%. allen in der Nähe befindlichen Feinden (%d+) Punkt%(e%) Feuerschaden zu%. Hält (%d+) Sek"))
    return dotOnly("fire")(n(a) * n(l) / n(i), l)
  end,
}
F["Shadow Word: Pain"] = {
  en = function(s) local a, d = must(s:match("causes (%d+) Shadow damage over (%d+) sec")); return dotOnly("shadow")(a, d) end,
  de = function(s) local d, a = must(s:match("das (%d+) Sek%. lang (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
F["Devouring Plague"] = {
  en = F["Shadow Word: Pain"].en,
  de = function(s) local d, a = must(s:match("so (%d+) Sek%. lang (%d+) Punkt%(e%) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
F["Holy Fire"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("cause (%d+) to (%d+) Holy damage and an additional (%d+) Holy damage over (%d+) sec"))
    return { direct = D(lo, hi), dot = O(t, d), school = "holy" }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("(%d+) bis (%d+) Punkt%(e%) Heiligschaden sowie (%d+) Sek%. lang zusätzlich (%d+) Punkt%(e%) Heiligschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "holy" }
  end,
}
F["Renew"] = {
  en = function(s) local a, d = must(s:match("Heals the target of (%d+) damage over (%d+) sec")); return { hot = O(a, d) } end,
  de = function(s) local d, a = must(s:match("Heilt das Ziel (%d+) Sek%. lang um (%d+) Schadenspunkt")); return { hot = O(a, d) } end,
}
F["Mind Flay"] = {
  en = F["Corruption"].en,
  de = function(s) local a, d = must(s:match("diesem (%d+) Schattenschaden im Verlauf von (%d+) Sek")); return dotOnly("shadow")(a, d) end,
}
F["Starshards"] = {
  en = function(s) local a, d = must(s:match("causing (%d+) Arcane damage over (%d+) sec")); return dotOnly("arcane")(a, d) end,
  de = function(s) local d, a = must(s:match("verursacht (%d+) Sek%. lang (%d+) Punkt%(e%) Arkanschaden")); return dotOnly("arcane")(a, d) end,
}
F["Moonfire"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("for (%d+) to (%d+) Arcane damage and then an additional (%d+) Arcane damage over (%d+) sec"))
    return { direct = D(lo, hi), dot = O(t, d), school = "arcane" }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("(%d+) bis (%d+) Punkt%(e%) Arkanschaden sowie (%d+) Sek%. lang (%d+) Punkt%(e%) zusätzlichen Arkanschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "arcane" }
  end,
}
F["Insect Swarm"] = {
  en = function(s) local a, d = must(s:match("causing (%d+) Nature damage over (%d+) sec")); return dotOnly("nature")(a, d) end,
  de = function(s) local d, a = must(s:match("über (%d+) Sek%. (%d+) Naturschaden")); return dotOnly("nature")(a, d) end,
}
F["Rake"] = {
  en = function(s)
    local a, t, d = must(s:match("for (%d+) damage and an additional (%d+) damage over (%d+) sec"))
    return { direct = D(a), dot = O(t, d), school = "physical" }
  end,
  de = function(s)
    local a, t, d = must(s:match("fügt (%d+) Punkt%(e%) Schaden sowie (%d+) Punkt%(e%) zusätzlichen Schaden im Verlauf von (%d+) Sek"))
    return { direct = D(a), dot = O(t, d), school = "physical" }
  end,
}
F["Rip"] = { en = function() return NIL("finisher") end, de = function() return NIL("finisher") end }
F["Rupture"] = F["Rip"]
F["Eviscerate"] = F["Rip"]
F["Rejuvenation"] = {
  en = function(s) local a, d = must(s:match("Heals the target for (%d+) over (%d+) sec")); return { hot = O(a, d) } end,
  de = function(s) local d, a = must(s:match("Heilt beim Ziel (%d+) Sek%. lang (%d+) Punkt%(e%) Schaden")); return { hot = O(a, d) } end,
}
F["Regrowth"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("for (%d+) to (%d+) and another (%d+) over (%d+) sec"))
    return { heal = D(lo, hi), hot = O(t, d) }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("um (%d+) bis (%d+) und über (%d+) Sek%. um weitere (%d+)"))
    return { heal = D(lo, hi), hot = O(t, d) }
  end,
}
F["Hurricane"] = {
  en = function(s)
    local a, i, l = must(s:match("causing (%d+) Nature damage to enemies every (%d+) sec.-Lasts (%d+) sec"))
    return dotOnly("nature")(n(a) * n(l) / n(i), l)
  end,
  de = function(s)
    local i, a, l = must(s:match("alle (%d+) Sek%. (%d+) Naturschaden.-Hält (%d+) Sek"))
    return dotOnly("nature")(n(a) * n(l) / n(i), l)
  end,
}
F["Serpent Sting"] = {
  en = F["Insect Swarm"].en,
  de = function(s) local d, a = must(s:match("verursacht (%d+) Sek%. lang (%d+) Naturschaden")); return dotOnly("nature")(a, d) end,
}
F["Immolation Trap"] = {
  en = F["Rain of Fire"].en,
  de = function(s) local d, a = must(s:match("die (%d+) Sek%. lang dem ersten sich nähernden Feind (%d+) Punkt%(e%) Feuerschaden")); return dotOnly("fire")(a, d) end,
}
F["Explosive Trap"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("causing (%d+) to (%d+) Fire damage and (%d+) additional Fire damage over (%d+) sec"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("verursacht (%d+) bis (%d+) Feuerschaden und verbrennt (%d+) Sek%. lang .- (%d+) zusätzlichen Feuerschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
}
F["Volley"] = {
  en = function(s)
    local a, d = must(s:match("causing (%d+) Arcane damage to enemy targets within 8 yards every second for (%d+) sec"))
    return dotOnly("arcane")(n(a) * n(d), d)
  end,
  de = function(s)
    local d, a = must(s:match("(%d+) Sek%. lang pro Sekunde (%d+) Punkt%(e%) Arkanschaden"))
    return dotOnly("arcane")(n(a) * n(d), d)
  end,
}
F["Wyvern Sting"] = {
  en = function(s) local a, d = must(s:match("causes (%d+) Nature damage over (%d+) sec")); return dotOnly("nature")(a, d) end,
  de = function(s)
    local a, d = s:match("Stich (%d+) Naturschaden im Verlauf von (%d+) Sek")
    if not a then d, a = must(s:match("Stich (%d+) Sek%. lang (%d+) Naturschaden")) end
    return dotOnly("nature")(a, d)
  end,
}
F["Garrote"] = {
  en = function(s) local a, d = must(s:match("causing (%d+) damage over (%d+) sec")); return dotOnly("physical")(a, d) end,
  de = function(s) local d, a = must(s:match("verursacht (%d+) Sek%. lang (%d+) Schaden")); return dotOnly("physical")(a, d) end,
}
F["Deadly Poison"] = {
  en = function(s) local a, d = must(s:match("poisoning the enemy for (%d+) Nature damage over (%d+) sec")); return dotOnly("nature")(a, d) end,
  de = function(s)
    local d, a = s:match("(%d+) Sek%. lang für (%d+) Punkt%(e%) Naturschaden")
    if not d then d, a = must(s:match("(%d+) Sek%. lang zu vergiften und ihm (%d+) Punkt%(e%) Naturschaden")) end
    return dotOnly("nature")(a, d)
  end,
}
F["Instant Poison"] = {
  en = function(s) local lo, hi = must(s:match("inflicts (%d+) to (%d+) Nature damage")); return { direct = D(lo, hi), school = "nature" } end,
  de = function(s) local lo, hi = must(s:match("unmittelbar (%d+) bis (%d+) Punkt%(e%) Naturschaden")); return { direct = D(lo, hi), school = "nature" } end,
}
F["Mind-numbing Poison"] = { en = function() return NIL("no-number") end, de = function() return NIL("no-number") end }
F["Sinister Strike"] = { en = function() return NIL("weapon") end, de = function() return NIL("weapon") end }
F["Rend"] = {
  en = function(s) local a, d = must(s:match("bleed for (%d+) damage over (%d+) sec")); return dotOnly("physical")(a, d) end,
  de = function(s) local d, a = must(s:match("(%d+) Sek%. lang bluten und fügt damit (%d+) Punkt%(e%) Schaden")); return dotOnly("physical")(a, d) end,
}
F["Fireball"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("causes (%d+) to (%d+) Fire damage and an additional (%d+) Fire damage over (%d+) sec"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("(%d+) bis (%d+) Punkt%(e%) Feuerschaden sowie (%d+) Sek%. lang (%d+) Punkt%(e%) zusätzlichen Feuerschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
}
F["Pyroblast"] = {
  en = F["Fireball"].en,
  de = function(s)
    local lo, hi, d, t = must(s:match("(%d+) bis (%d+) Punkt%(e%) Feuerschaden sowie zusätzlich (%d+) Sek%. lang (%d+) Punkt%(e%) zusätzlichen Feuerschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
}
F["Blizzard"] = {
  en = function(s)
    local x, y, d = must(s:match("%[(%d+) %* (%d+) %* %(1%)%] Frost damage over (%d+) sec"))
    return dotOnly("frost")(n(x) * n(y), d)
  end,
  de = function(s)
    local d, x, y = must(s:match("(%d+) Sek%. lang insgesamt %[(%d+) %* (%d+) %* %(1%)%] Frostschaden"))
    return dotOnly("frost")(n(x) * n(y), d)
  end,
}
F["Flamestrike"] = {
  en = function(s)
    local lo, hi, t, d = must(s:match("for (%d+) to (%d+) Fire damage and an additional (%d+) Fire damage over (%d+) sec"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local lo, hi, d, t = must(s:match("zunächst (%d+) bis (%d+) Punkt%(e%) Feuerschaden und zusätzlich (%d+) Sek%. lang (%d+) Punkt%(e%) Feuerschaden"))
    return { direct = D(lo, hi), dot = O(t, d), school = "fire" }
  end,
}
F["Arcane Missiles"] = {
  en = function(s)
    local a, d = must(s:match("causing (%d+) Arcane damage each second for (%d+) sec"))
    return dotOnly("arcane")(n(a) * n(d), d)
  end,
  de = F["Volley"].de,
}
F["Flame Shock"] = {
  en = function(s)
    local a, t, d = must(s:match("causing (%d+) Fire damage immediately and (%d+) Fire damage over (%d+) sec"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local a, d, t = must(s:match("unmittelbar (%d+) .-Feuerschaden sowie (%d+) Sek%. lang (%d+) .-Feuerschaden"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
}
F["Consecration"] = {
  en = function(s) local a, d = must(s:match("doing (%d+) Holy damage over (%d+) sec")); return dotOnly("holy")(a, d) end,
  de = function(s) local d, a = must(s:match("fügt (%d+) Sek%. lang Feinden, die das Gebiet betreten, (%d+) Punkt%(e%) Heiligschaden")); return dotOnly("holy")(a, d) end,
}
-- Debuffs that lower the enemy's damage: no damage of their own (test_reduction.lua checks the
-- reduction). The pet's Screech also hits once.
local noDamage = { en = function() return NIL("no-number") end, de = function() return NIL("no-number") end }
F["Curse of Weakness"] = noDamage
F["Demoralizing Shout"] = noDamage
F["Demoralizing Roar"] = noDamage
F["Hex of Weakness"] = noDamage
F["Screech"] = {
  en = function(s) local lo, hi = must(s:match("for (%d+) to (%d+) damage")); return { direct = D(lo, hi), school = "physical" } end,
  de = function(s) local lo, hi = must(s:match("erleidet (%d+) bis (%d+) Schaden")); return { direct = D(lo, hi), school = "physical" } end,
}

-- Cataclysm wordings
local CATA = {}
CATA["Bane of Agony"] = {
  en = F["Corruption"].en,
  de = function(s) local d, a = must(s:match("im Verlauf von (%d+) Sek%. (%d+) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
CATA["Bane of Doom"] = {
  en = function(s)
    local a, i = must(s:match("causing (%d+) Shadow damage every (%d+) sec.-Lasts for 1 min"))
    return dotOnly("shadow")(n(a) * 60 / n(i), 60)
  end,
  de = function(s)
    local i, a = must(s:match("alle (%d+) Sek%. (%d+) Schattenschaden.-Hält 1 Min%. lang an"))
    return dotOnly("shadow")(n(a) * 60 / n(i), 60)
  end,
}
CATA["Immolate"] = {
  en = function(s)
    local a, t, d = must(s:match("for (%d+) Fire damage and then an additional (%d+) Fire damage over (%d+) sec"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
  de = function(s)
    local a, d, t = must(s:match("Verursacht (%d+) Feuerschaden und fügt zusätzlich im Verlauf von (%d+) Sek%. insgesamt (%d+) Feuerschaden"))
    return { direct = D(a), dot = O(t, d), school = "fire" }
  end,
}
CATA["Corruption"] = {
  en = F["Corruption"].en,
  de = function(s) local d, a = must(s:match("(%d+) Sek%. lang insgesamt (%d+) Schattenschaden")); return dotOnly("shadow")(a, d) end,
}
CATA["Frostfire Bolt"] = { -- the bracketed glyph text is optional, only the bolt counts
  en = function(s) local a = must(s:match("causing (%d+) Frostfire damage and %[")); return { direct = D(a), school = "frostfire" } end,
  de = function(s) local a = must(s:match("sofort (%d+) Frostfeuerschaden verursacht %[")); return { direct = D(a), school = "frostfire" } end,
}

---------------------------------------------------------------------------------------------
-- Modern Retail wordings (static-eu): written down from each text by hand
---------------------------------------------------------------------------------------------

local function both(en, de) return { en = en, de = de or en } end
local R = {
  [172] = both({ direct = D(153), dot = O(1132, 14), school = "shadow" }, { direct = D(152), dot = O(1132, 14), school = "shadow" }),
  [980] = both({ dot = O(2854, 18), school = "shadow" }),
  [348] = both({ direct = D(362), dot = O(1493, 18), school = "fire" }, { direct = D(357), dot = O(1493, 18), school = "fire" }),
  [603] = both({ direct = D(396), dot = O(1105, 20), school = "shadow" }),
  [5740] = both({ dot = O(1814, 7.1), school = "fire" }),
  [589] = both({ direct = D(64), dot = O(424, 16), school = "shadow" }, { direct = D(63), dot = O(424, 16), school = "shadow" }),
  [14914] = both({ direct = D(1149), dot = O(421, 7), school = "holy" }, { direct = D(1186), dot = O(421, 7), school = "holy" }),
  [139] = both({ hot = O(1528, 15) }),
  [15407] = both({ dot = O(3151, 4), school = "shadow" }),
  [8921] = both({ direct = D(80), dot = O(705, 18), school = "arcane" }, { direct = D(82), dot = O(705, 18), school = "arcane" }),
  [1822] = both({ direct = D(10), dot = O(57, 15), school = "physical" }),
  [1079] = both(NIL("finisher")),
  [774] = both({ hot = O(1925, 12) }),
  [8936] = both({ heal = D(2082), hot = O(287, 6) }, { heal = D(2018), hot = O(287, 6) }),
  [1943] = both(NIL("finisher")),
  [703] = both({ dot = O(159, 18), school = "physical" }),
  [2098] = both(NIL("finisher")),
  [2823] = both({ direct = D(2), dot = O(27, 12), school = "nature" }),
  [2818] = both({ direct = D(2), dot = O(27, 12), school = "nature" }),
  [8679] = both({ direct = D(1), school = "nature" }),
  [1752] = both({ direct = D(31), school = "physical" }, { direct = D(30), school = "physical" }),
  [772] = both({ direct = D(44), dot = O(74, 15), school = "physical" }, { direct = D(42), dot = O(74, 15), school = "physical" }),
  [133] = both({ direct = D(1647), school = "fire" }, { direct = D(1630), school = "fire" }),
  [11366] = both({ direct = D(2677), school = "fire" }, { direct = D(2736), school = "fire" }),
  [2120] = both({ direct = D(1465), school = "fire" }, { direct = D(1446), school = "fire" }),
  [5143] = both({ dot = O(2232, 2.2), school = "arcane" }, { dot = O(2189, 2.2), school = "arcane" }),
  [26573] = both({ dot = O(26, 12), school = "holy" }),
  [28829] = both(NIL("no-number")),
  [146739] = both({ direct = D(152), dot = O(1132, 14), school = "shadow" }, { direct = D(154), dot = O(1132, 14), school = "shadow" }),
  [193541] = both({ direct = D(357), dot = O(1493, 18), school = "fire" }, { direct = D(356), dot = O(1493, 18), school = "fire" }),
  [63106] = both({ dot = O(351, 15), school = "shadow" }),
  [452999] = both(NIL("no-number")),
  [234153] = both({ dot = O(1425, 4.5), school = "shadow" }),
  [198590] = both({ dot = O(2117, 4.5), school = "shadow" }),
  [388667] = both({ dot = O(2117, 4.5), school = "shadow" }),
  [1214467] = both({ dot = O(1814, 7.1), school = "fire" }),
  [164812] = both({ direct = D(81), dot = O(705, 18), school = "arcane" }, { direct = D(79), dot = O(705, 18), school = "arcane" }),
  [326646] = both(NIL("no-number")),
  [28716] = both(NIL("no-number")),
  [28744] = both(NIL("no-number")),
  [390563] = both(NIL("no-number")),
  [271788] = both({ direct = D(10), dot = O(48, 18), school = "nature" }),
  [260243] = both({ dot = O(795, 6), school = "physical" }, { dot = O(769, 6), school = "physical" }),
  [1249804] = both(NIL("no-number")),
  [196819] = both(NIL("finisher")),
  [113780] = both({ direct = D(2), school = "nature" }),
  [315584] = both({ direct = D(2), school = "nature" }),
  [193315] = both({ direct = D(42), school = "physical" }, { direct = D(43), school = "physical" }),
  [394062] = both({ direct = D(14), dot = O(41, 15), school = "physical" }, { direct = D(13), dot = O(41, 15), school = "physical" }),
  [1261060] = both({ dot = O(50, 6), school = "physical" }),
  [343194] = both(NIL("no-number")),
  [321711] = both({ dot = O(87, 6), school = "fire" }),
  [190356] = both({ dot = O(1684, 10.7), school = "frost" }, { dot = O(1616, 10.7), school = "frost" }),
  [1248829] = both({ dot = O(1681, 10.7), school = "frost" }, { dot = O(1638, 10.7), school = "frost" }),
  [1254851] = both({ direct = D(1467), school = "fire" }, { direct = D(1457), school = "fire" }),
  -- two separate hits (the shock and the eruption when dispelled): ambiguous, so nil
  [470411] = both(NIL("ambiguous")),
  -- "every 0.9 sec" with no duration anywhere: the total is unknown
  [81297] = both(NIL("ambiguous")),
  [327980] = both(NIL("no-number")),
  [460551] = both({ dot = O(1531, 20), school = "shadow" }),
  [431044] = both({ direct = D(1087), dot = O(102, 8), school = "frostfire" }, { direct = D(1117), dot = O(102, 8), school = "frostfire" }),
}

local function expectationFor(row, lang)
  local text = row[lang .. "_description"]
  if row.namespace == "static-eu" then
    local r = R[row.id]
    if not r then error("no expectation for static-eu:" .. row.id) end
    return r[lang]
  end
  local base = (row.en_name or ""):gsub(" [IVX]+$", "")
  local family = (row.namespace == "wowhead-cata") and CATA[base] or F[base]
  if not family then error("no extractor for " .. row.namespace .. ":" .. tostring(row.en_name)) end
  return family[lang](text)
end

---------------------------------------------------------------------------------------------
-- Comparison
---------------------------------------------------------------------------------------------

local function close(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6 end

local function describe(r)
  if not r then return "nil" end
  local p = {}
  if r.direct then p[#p + 1] = ("direct %s-%s"):format(r.direct.min, r.direct.max) end
  if r.dot then p[#p + 1] = ("dot %s/%ss"):format(r.dot.total, r.dot.duration) end
  if r.heal then p[#p + 1] = ("heal %s-%s"):format(r.heal.min, r.heal.max) end
  if r.hot then p[#p + 1] = ("hot %s/%ss"):format(r.hot.total, r.hot.duration) end
  p[#p + 1] = "school " .. tostring(r.school)
  return table.concat(p, ", ")
end

local function same(got, want)
  if want.none then return got == nil end
  if got == nil then return false end
  for _, k in ipairs({ "direct", "heal" }) do
    local g, w = got[k], want[k]
    if (g == nil) ~= (w == nil) then return false end
    if w and not (close(g.min, w.min) and close(g.max, w.max)) then return false end
  end
  for _, k in ipairs({ "dot", "hot" }) do
    local g, w = got[k], want[k]
    if (g == nil) ~= (w == nil) then return false end
    if w and not (close(g.total, w.total) and close(g.duration, w.duration)) then return false end
  end
  return got.school == want.school
end

---------------------------------------------------------------------------------------------
-- Run over the fixtures
---------------------------------------------------------------------------------------------

local stats = { texts = 0, empty = 0, wantNumbers = 0, gotNumbers = 0, wantNil = 0, gotNil = 0, nilReasons = {} }

for _, row in ipairs(rows) do
  for _, lang in ipairs({ "en", "de" }) do
    local text = row[lang .. "_description"]
    if type(text) ~= "string" or text:match("^%s*$") then
      stats.empty = stats.empty + 1
    else
      stats.texts = stats.texts + 1
      local okExp, want = pcall(expectationFor, row, lang)
      if not okExp then error(("%s:%s %s [%s]: %s"):format(row.namespace, row.id, tostring(row.en_name), lang, want)) end
      local got = Parse(text, lang)
      local ok = same(got, want)
      if want.none then
        stats.wantNil = stats.wantNil + 1
        if ok then
          stats.gotNil = stats.gotNil + 1
          stats.nilReasons[want.none] = (stats.nilReasons[want.none] or 0) + 1
        end
      else
        stats.wantNumbers = stats.wantNumbers + 1
        if ok then stats.gotNumbers = stats.gotNumbers + 1 end
      end
      T.check(ok, ("%s:%s %s [%s]: got %s, want %s"):format(row.namespace, row.id, row.en_name, lang,
        describe(got), want.none and ("nil (" .. want.none .. ")") or describe(want)))
    end
  end
end

---------------------------------------------------------------------------------------------
-- Wordings not in the fixtures (written for this test): number formats, edge cases, and the
-- Forever warlock texts read from the game's English spellbook.
---------------------------------------------------------------------------------------------

local extra = {
  { "de", "Schleudert einen Schattenblitz auf den Feind, der 13 bis 18 Punkt(e) Schattenschaden verursacht.", { direct = D(13, 18), school = "shadow" } },
  { "de", "Verursacht 1.234 bis 1.300 Schattenschaden.", { direct = D(1234, 1300), school = "shadow" } },
  { "en", "Causes 1,234 to 1,300 Shadow damage.", { direct = D(1234, 1300), school = "shadow" } },
  { "de", "Verursacht im Verlauf von 7,5 Sek. 2.500 Feuerschaden.", { dot = O(2500, 7.5), school = "fire" } },
  { "en", "Deals 2,500 Fire damage over 7.5 sec.", { dot = O(2500, 7.5), school = "fire" } },
  { "de", "Verursacht 12.345.678 Schattenschaden.", { direct = D(12345678), school = "shadow" } },
  { "en", "Burns the enemy for 158 Fire damage and then an additional 275 Fire damage over 15 sec.", { direct = D(158), dot = O(275, 15), school = "fire" } },
  { "en", "Sends a shadowy bolt at the enemy, causing 253 to 283 Shadow damage.", { direct = D(253, 283), school = "shadow" } },
  { "en", "Transfers 51 health every 1 second from the target to the caster. Lasts 5 sec.", { dot = O(255, 5) } },
  { "en", "Tears the target apart from within, dealing 36 Shadow damage every 1 sec and increasing the damage they take from your other Shadow damage over time effects by 10%. Lasts 6 sec.", { dot = O(216, 6), school = "shadow" } },
  { "en", "Causes the enemy target to run in horror for 3 sec and causes 454 Shadow damage. The caster gains 100% of the damage caused in health.", { direct = D(454), school = "shadow" } },
  { "de", "Lässt das feindliche Ziel 3 Sek. lang vor Entsetzen fliehen und verursacht 476 Punkt(e) Schattenschaden.", { direct = D(476), school = "shadow" } },
  { "en", "Afflicts the target with impending doom, causing 1742 Shadow damage after 1 min.", { dot = O(1742, 60), school = "shadow" } },
  { "en", "Heals a friendly target for 42 to 51.", { heal = D(42, 51) } },
  { "de", "Heilt ein befreundetes Ziel um 42 bis 51 Punkt(e).", { heal = D(42, 51) } },
  { "en", "Absorbs 920 shadow damage. Lasts 30 sec.", NIL("absorb") },
  { "de", "Absorbiert 920 Punkt(e) Schattenschaden. Hält 30 Sek. lang an.", NIL("absorb") },
  { "en", "Draws on the soul of the party member to shield them, absorbing 48 damage. Lasts 30 sec.", NIL("absorb") },
  { "en", "Increases your Shadow damage by 15%.", NIL("no-number") },
  { "en", "Transfers 42 Mana every 1 sec from the target to the caster. Lasts 5 sec.", NIL("mana") },
  { "en", "", NIL("empty") },
  { "de", "Verursacht |cffffffff120|r Feuerschaden.", { direct = D(120), school = "fire" } },
  -- Mana Burn: 0.5 damage per point of mana is not the spell's damage.
  { "en", "Destroy 99 mana from a target. For each mana destroyed in this way, the target takes 0.5 Shadow damage.", NIL("per-unit") },
  { "de", "Vernichtet 99 Punkt(e) Mana des Ziels. Für jeden auf diese Weise vernichteten Manapunkt erleidet das Ziel 0,5 Punkt(e) Schattenschaden.", NIL("per-unit") },
  -- Chain Heal: "Heals 3 total targets" is a count, not a second heal.
  { "en", "Heals the friendly target for 332 to 381, then jumps to heal additional nearby targets. Each jump reduces the effectiveness of the heal by 50%. Heals 3 total targets.", { heal = D(332, 381) } },
  { "de", "Heilt das befreundete Ziel um 332 bis 381 und springt dann auf weitere Ziele in der Nähe über. Jeder Sprung verringert die Wirksamkeit der Heilung um 50%. Heilt insgesamt 3 Ziele.", { heal = D(332, 381) } },
}
for i, case in ipairs(extra) do
  local got = Parse(case[2], case[1])
  T.check(same(got, case[3]), ("extra %d [%s] %q: got %s, want %s"):format(i, case[1], case[2], describe(got),
    case[3].none and "nil" or describe(case[3])))
end

-- Language detection when no language is given
T.check(same(Parse("Verdirbt das Ziel und verursacht 18 Sek. lang 822 Punkt(e) Schattenschaden."), { dot = O(822, 18), school = "shadow" }), "detects German")
T.check(same(Parse("Corrupts the target, causing 1,132 Shadow damage over 14 sec."), { dot = O(1132, 14), school = "shadow" }), "detects English")

-- The formula evaluator only does arithmetic
T.eq(ns.Parser._evalArithmetic("26 * 8 * (1)"), 208, "formula 26*8*(1)")
T.eq(ns.Parser._evalArithmetic("((553 + 703) / 2) * 0.03"), 18.84, "formula with brackets")
T.eq(ns.Parser._evalArithmetic("2 +"), nil, "broken formula")

print(("Fixture texts: %d (%d rows x 2 languages, %d empty skipped)"):format(stats.texts, #rows, stats.empty))
print(("  stating a damage/heal number the parser should read: %d, read correctly: %d"):format(stats.wantNumbers, stats.gotNumbers))
local reasons = {}
for k, v in pairs(stats.nilReasons) do reasons[#reasons + 1] = k .. " " .. v end
table.sort(reasons)
print(("  expected nil: %d, correctly nil: %d (%s)"):format(stats.wantNil, stats.gotNil, table.concat(reasons, ", ")))
T.finish("test_parser")
