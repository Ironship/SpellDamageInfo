-- Parser.ParseWeapon over tests/fixtures/attack_power_weapon_damage.json: every rank of every
-- weapon and attack power ability of all nine classes, in Classic's English and German
-- (Wowhead) and Forever's own English (foreverchanges.pro). None of the texts is written here.
--
--   lua tests/test_weapon.lua [path/to/Parser.lua]
--
-- Three kinds of check:
--   * German agrees with English, rank by rank: the two texts describe the same spell id with
--     the same numbers, so the parser must read the same thing from both. This is what makes
--     the German patterns trustworthy without a German expectation written down by hand.
--   * The English results carry the numbers the text states, worked out here with patterns of
--     the test's own for each ability family (never from the parser).
--   * What must stay nil stays nil: chance effects other than Windfury's extra attacks and Seal of
--     Command's hit, finishers, and every row of tests/fixtures/spells.json except the weapon
--     attacks it already marked as such.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local parserPath = arg and arg[1] or "Parser.lua"
local ns = {}
T.loadAddonFile(parserPath, ns)
local PW = ns.Parser.ParseWeapon

local rows = json.decode(T.readFile("tests/fixtures/attack_power_weapon_damage.json"))
local spells = json.decode(T.readFile("tests/fixtures/spells.json"))
local n = tonumber

local function describe(r)
  if r == nil then return "nil" end
  local parts = { tostring(r.kind) }
  for _, k in ipairs({ "pct", "bonus", "bonusMax", "amount", "min", "max", "school", "times", "stat", "attacks", "faster", "bySpeed" }) do
    if r[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(r[k]) end
  end
  if r.ranged then parts[#parts + 1] = "ranged" end
  if r.plusAgility then parts[#parts + 1] = "+agility" end
  return table.concat(parts, " ")
end

local function same(a, b)
  if a == nil or b == nil then return a == b end
  for _, k in ipairs({ "kind", "pct", "bonus", "bonusMax", "amount", "min", "max", "school", "times", "stat", "attacks", "faster", "bySpeed" }) do
    if a[k] ~= b[k] then return false end
  end
  return (a.ranged and true or false) == (b.ranged and true or false)
    and (a.plusAgility and true or false) == (b.plusAgility and true or false)
end

local function nums(text)
  local out = {}
  for v in text:gsub(",(%d%d%d)", "%1"):gmatch("%d+%.?%d*") do out[#out + 1] = n(v) end
  return out
end

-- The English expectation for an ability, from the text's own numbers. Square brackets are
-- Wowhead's annotations (Season of Discovery overrides on Trueshot Aura, talent text), which the
-- game does not show and the parser drops; so does the expectation.
-- A bracket of plain arithmetic is a number the game prints worked out ("[26 * 8]"); the test
-- works it out with Lua itself, not with the parser's evaluator. Any other bracket is dropped.
local function brackets(text)
  text = text:gsub("%[([%d%s%.%+%-%*/%(%)]+)%]", function(expr)
    local f = (loadstring or load)("return " .. expr)
    local ok, v = pcall(f)
    if ok and type(v) == "number" then return tostring(math.floor(v * 100 + 0.5) / 100) end
  end)
  return (text:gsub("%b[]", ""))
end

-- The seals and imbues whose text says slower weapons do more per swing
local function slower(t) return t:find("slower weapons cause more", 1, true) and true or nil end

local function expectEN(name, text)
  local t = brackets(text):lower()
  if name == "Heroic Strike" or name == "Raptor Strike" and t:find("increases melee damage") then
    return { kind = "next", bonus = n(t:match("melee damage by (%d+)")) }
  end
  if name == "Maul" then return { kind = "next", bonus = n(t:match("next attack by (%d+)")) } end
  if name == "Aimed Shot" or name == "Sniper Shot" then
    return { kind = "next", bonus = n(t:match("ranged damage by (%d+)")), ranged = true }
  end
  if name == "Overpower" or name == "Mortal Strike" or name == "Cleave" or name == "Slam"
    or name == "Raptor Strike" or name == "Mongoose Bite" then
    local b = t:match("weapon damage plus (%d+)")
    if b then return { kind = "weapon", pct = 100, bonus = n(b) } end
    return nil -- Classic's Mongoose Bite: flat damage, Parse() reads it
  end
  if name == "Whirlwind" then return { kind = "weapon", pct = 100, bonus = 0 } end
  if name == "Mutilate" then
    local p, b = t:match("(%d+)%% weapon damage plus an additional ([%d%.]+) with each weapon")
    return { kind = "both", pct = n(p), bonus = n(b) }
  end
  if name == "Seal of Righteousness" then
    local lo, hi = t:match("each melee attack an additional ([%d%.]+) to ([%d%.]+) holy damage")
    return { kind = "perhit", min = n(lo), max = n(hi), school = "holy", bySpeed = slower(t) }
  end
  if name == "Flametongue Weapon" then
    local lo, hi = t:match("each hit causes ([%d%.]+) to ([%d%.]+) additional fire damage")
    return { kind = "perhit", min = n(lo), max = n(hi), school = "fire", bySpeed = slower(t) }
  end
  -- chance effects, per trigger
  if name == "Windfury Weapon" then
    local a, b = t:match("(%d+) extra attacks? with (%d+) extra melee attack power")
    return { kind = "extra", attacks = n(a), amount = n(b) }
  end
  if name == "Seal of the Crusader" then
    -- Classic's no-break space after the full stop, replaced before string.lower (which a code-page
    -- locale lets change its first byte)
    local raw = (brackets(text):gsub("\194\160", " ")):lower()
    local a, p = raw:match("granting (%d+) melee attack power%.%s+the paladin also attacks (%d+)%% faster")
    return { kind = "ap", amount = n(a), faster = n(p) }
  end
  if name == "Seal of Command" then
    return { kind = "weapon", pct = n(t:match("holy damage equal to (%d+)%% of normal weapon damage")), bonus = 0, school = "holy" }
  end
  if name == "Seal of Fury" then
    local a = t:match("melee attacks to deal an additional ([%d%.]+) holy damage")
    return { kind = "perhit", min = n(a), max = n(a), school = "holy" }
  end
  if name == "Sinister Strike" then
    return { kind = "weapon", pct = 100, bonus = n(t:match("causes (%d+) damage in addition")) }
  end
  if name == "Ambush" or name == "Backstab" or name == "Counterattack" then
    local p, b = t:match("(%d+)%% weapon damage plus (%d+)")
    if p then return { kind = "weapon", pct = n(p), bonus = n(b) } end
    return nil -- Classic's Counterattack: flat damage
  end
  if name == "Holy Strike" then
    local p, a, b = t:match("(%d+)%% weapon damage plus an additional (%d+) to (%d+)")
    return { kind = "weapon", pct = n(p), bonus = n(a), bonusMax = n(b) }
  end
  if name == "Shred" or name == "Ravage" then
    local p, b = t:match("(%d+)%% damage plus (%d+)")
    return { kind = "weapon", pct = n(p), bonus = n(b) }
  end
  if name == "Claw" or name == "Primal Bite" then
    local p, b = t:match("(%d+)%% normal damage plus (%d+)")
    if p then return { kind = "weapon", pct = n(p), bonus = n(b) } end
    b = t:match("causing (%d+) additional damage")
    if b then return { kind = "weapon", pct = 100, bonus = n(b) } end
    p = t:match("(%d+)%% normal damage")
    if p then return { kind = "weapon", pct = n(p), bonus = 0 } end
  end
  if name == "Battle Shout" or name == "Blessing of Might" or name == "Greater Blessing of Might"
    or name == "Rockbiter Weapon" or name == "Bear Form" or name == "Dire Bear Form" or name == "Cat Form"
    or name == "Aspect of the Hawk" or name == "Aspect of the Beast" or name == "Hunter's Mark" or name == "Trueshot Aura" then
    local a = t:match("attack power[^%.]- by (%d+)")
    if not a then return nil end -- Classic's Aspect of the Beast raises no attack power
    return { kind = "ap", amount = n(a), ranged = t:find("ranged attack power", 1, true) ~= nil,
      plusAgility = t:find("plus agility", 1, true) ~= nil }
  end
  return nil
end

-- Nothing here is read as a weapon ability.
local NEVER = {}
-- The imbues and seals read here: what every hit gains, or what one trigger of a chance is worth.
-- Every other one is a chance Parse reads (poisons, Frostbrand), a heal (Seal of Light), or no
-- damage.
local PER_HIT = { ["Seal of Righteousness"] = true, ["Flametongue Weapon"] = true, ["Seal of Fury"] = true,
  ["Windfury Weapon"] = true, ["Seal of Command"] = true, ["Seal of the Crusader"] = true }
-- German texts that lost the words the English still has: Wowhead's German Trueshot Aura keeps
-- "attack power" only inside brackets that hold talent text, which the parser drops.
local GERMAN_SILENT = { ["Trueshot Aura"] = true }

local counts = { rows = #rows, en = 0, de = 0, fv = 0, agree = 0 }
for _, row in ipairs(rows) do
  local name, id = row.expected_name, row.id
  local en, de, fv = row.en_description, row.de_description, row.forever_en_description
  local label = ("%s %s r%s"):format(name, tostring(id), tostring(row.rank))
  local gotEN = en and PW(en, "en") or nil
  if en then
    local want
    if (row.category == "imbue_seal" and not PER_HIT[name]) or row.category == "finisher_ap" or NEVER[name] then
      want = nil
    else
      want = expectEN(name, en)
    end
    T.check(same(gotEN, want), label .. " [en]: got " .. describe(gotEN) .. ", want " .. describe(want))
    if gotEN then counts.en = counts.en + 1 end
  end
  if de and de ~= "" and en then
    local gotDE = PW(de, "de")
    if GERMAN_SILENT[name] then
      T.check(gotDE == nil, label .. " [de]: expected nil, got " .. describe(gotDE))
    else
      T.check(same(gotDE, gotEN), label .. " [de]: got " .. describe(gotDE) .. ", English gives " .. describe(gotEN))
      if gotDE then counts.de = counts.de + 1 end
      counts.agree = counts.agree + 1
    end
  end
  if fv then
    local gotFV = PW(fv, "en")
    local want
    if (row.category == "imbue_seal" and not PER_HIT[name]) or row.category == "finisher_ap" or NEVER[name] then
      want = nil
    else
      want = expectEN(name, fv)
    end
    T.check(same(gotFV, want), label .. " [forever]: got " .. describe(gotFV) .. ", want " .. describe(want))
    if gotFV then counts.fv = counts.fv + 1 end
  end
end

-- A few by hand, so a family that the expectations above got wrong in the same way as the
-- parser cannot hide: the numbers are read off the texts in the fixture.
local function row(id)
  for _, r in ipairs(rows) do if r.id == id then return r end end
  error("fixture has no spell " .. id)
end
local HAND = {
  { 25286, "en", { kind = "next", bonus = 157 } },                                -- Heroic Strike r9
  { 25286, "de", { kind = "next", bonus = 157 } },                                -- Heldenhafter Stoß
  { 25289, "de", { kind = "ap", amount = 232 } },                                 -- Schlachtruf r7
  { 16316, "de", { kind = "ap", amount = 653 } },                                 -- Waffe des Felsbeißers r7
  { 16316, "forever", { kind = "ap", amount = 554 } },                            -- Forever's Rockbiter
  { 16362, "de", { kind = "extra", attacks = 2, amount = 333 } },                -- Waffe des Windzorns r4
  { 20920, "de", { kind = "weapon", pct = 70, bonus = 0, school = "holy" } },    -- Siegel des Befehls r5
}
for _, h in ipairs(HAND) do
  local r = row(h[1])
  local text = h[2] == "forever" and r.forever_en_description or r[h[2] .. "_description"]
  local got = PW(text, h[2] == "de" and "de" or "en")
  T.check(same(got, h[3]), ("by hand %d [%s]: got %s, want %s"):format(h[1], h[2], describe(got), describe(h[3])))
end

-- spells.json: only the weapon attacks it already set aside as such answer here.
local answered, stray = 0, 0
for _, s in ipairs(spells) do
  for _, lang in ipairs({ "en", "de" }) do
    local text = s[lang .. "_description"]
    if type(text) == "string" and text ~= "" then
      local got = PW(text, lang)
      if got then
        if s.en_name == "Sinister Strike" and got.kind == "weapon" and got.pct == 100 then
          answered = answered + 1
        else
          stray = stray + 1
          T.check(false, ("spells.json %s [%s] should not be a weapon ability: %s"):format(tostring(s.en_name), lang, describe(got)))
        end
      end
    end
  end
end
T.eq(answered, 16, "spells.json: the 16 Sinister Strike texts are read as weapon attacks")

-- Edge cases written for this test (not game text): nothing, a reduction, a heal.
T.eq(PW(nil), nil, "nil text")
T.eq(PW(""), nil, "empty text")
T.eq(PW("Reduces the melee attack power of all enemies within 10 yards by 45 for 30 sec.", "en"), nil,
  "a reduction of attack power is ParseReduction's")
T.eq(PW("Heals a friendly target for 50 to 60.", "en"), nil, "a heal")

print(("Weapon fixture: %d rows; English gives a result for %d, German for %d (agreeing with English in %d rows), Forever's English for %d"):format(
  counts.rows, counts.en, counts.de, counts.agree, counts.fv))
T.finish("test_weapon")
