-- SpellDamageInfo: reads a spell's damage and healing out of its description text.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- Parse(text, lang) returns a table or nil:
--   direct = { min = n, max = n }         instant damage
--   dot    = { total = n, duration = s }  damage over time (total over the whole duration)
--   heal   = { min = n, max = n }         instant healing
--   hot    = { total = n, duration = s }  healing over time
--   school = "shadow" | "fire" | "nature" | "frost" | "arcane" | "holy" | "frostfire" | "physical" | "volcanic" | nil
-- It returns nil (plus a short reason) for any wording it does not understand, and never guesses.
-- ParseReduction(text, lang) reads how much a debuff lowers the enemy's damage or attack power.
-- English and German wordings are understood; lang is "en", "de" or nil (detect from the text).
-- Pure Lua 5.1, no game API, so it can be tested outside the game.

local _, ns = ...
ns = ns or {}

local Parser = {}
ns.Parser = Parser

local find, sub, gsub, match, gmatch = string.find, string.sub, string.gsub, string.match, string.gmatch
local tonumber, floor = tonumber, math.floor

-- Lower case by hand: string.lower and the %a/%d classes follow the process's C locale, and
-- under a code-page locale they would treat the bytes of UTF-8 letters as letters too.
local function asciiLower(c) return string.char(c:byte() + 32) end
-- Capital umlauts (UTF-8) to lower case.
local UMLAUT_LOWER = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }

local SCHOOL_EN = {
  shadow = "shadow", fire = "fire", nature = "nature", frost = "frost", arcane = "arcane",
  holy = "holy", frostfire = "frostfire", physical = "physical", bleed = "physical", volcanic = "volcanic",
}
local SCHOOL_DE = {
  schatten = "shadow", feuer = "fire", natur = "nature", frost = "frost", arkan = "arcane",
  heilig = "holy", frostfeuer = "frostfire", vulkan = "volcanic", blutungs = "physical", [""] = "physical",
}

-- Words that may sit between an amount and its damage word.
local FILLERS_EN = { "additional ", "extra " }
local FILLERS_DE = {
  "punkt(e) ", "punkt(en) ", "punkte ", "punkt ",
  "zus\195\164tzlichen ", "zus\195\164tzliche ", "zus\195\164tzlich ",
  "insgesamt ", "k\195\182rperlichen ", "weitere ",
}

-- A number as it looks after normalisation (thousand separators removed, "." as decimal point).
local NUM = "[0-9]+%.?[0-9]*"

local function detectLanguage(t)
  if find(t, "sek%.") or find(t, "schaden") or find(t, "punkt%(e%)") or find(t, "heilt ")
    or find(t, " und ") or find(t, "gesundheit") then
    return "de"
  end
  return "en"
end

-- Wowhead-style formulas such as "[11 * (((1)))]" or "[26 * 8 * (1)]". The game prints the
-- result, so evaluate plain arithmetic (numbers, + - * / and brackets) and nothing else.
local function evalArithmetic(expr)
  local pos = 1
  local parseSum
  local function skip() pos = (find(expr, "[^ ]", pos)) or (#expr + 1) end
  local function parseAtom()
    skip()
    local c = sub(expr, pos, pos)
    if c == "(" then
      pos = pos + 1
      local v = parseSum()
      skip()
      if v == nil or sub(expr, pos, pos) ~= ")" then return nil end
      pos = pos + 1
      return v
    elseif c == "-" then
      pos = pos + 1
      local v = parseAtom()
      return v and -v
    end
    local s, e = find(expr, "^[0-9]+%.?[0-9]*", pos)
    if not s then return nil end
    pos = e + 1
    return tonumber(sub(expr, s, e))
  end
  local function parseProduct()
    local v = parseAtom()
    while v do
      skip()
      local c = sub(expr, pos, pos)
      if c ~= "*" and c ~= "/" then break end
      pos = pos + 1
      local r = parseAtom()
      if not r then return nil end
      if c == "*" then v = v * r elseif r == 0 then return nil else v = v / r end
    end
    return v
  end
  parseSum = function()
    local v = parseProduct()
    while v do
      skip()
      local c = sub(expr, pos, pos)
      if c ~= "+" and c ~= "-" then break end
      pos = pos + 1
      local r = parseProduct()
      if not r then return nil end
      if c == "+" then v = v + r else v = v - r end
    end
    return v
  end
  local v = parseSum()
  skip()
  if v == nil or pos <= #expr then return nil end
  return v
end

local function formatNumber(v)
  if v == floor(v) then return tostring(floor(v)) end
  return (gsub(string.format("%.2f", v), "0+$", ""))
end

local function replaceFormulas(t)
  local n
  repeat
    t, n = gsub(t, "%[([0-9 %.%+%-%*/%(%)]+)%]", function(expr)
      local v = evalArithmetic(expr)
      if v then return formatNumber(v) end
    end)
  until n == 0
  -- Whatever is still in brackets holds words (optional glyph or talent text); it is not
  -- part of the spell's own numbers.
  local prev
  repeat
    prev = t
    t = gsub(t, "%b[]", " ")
  until t == prev
  return t
end

local function normaliseNumbers(t, lang)
  local prev
  if lang == "de" then
    repeat prev = t; t = gsub(t, "([0-9])%.([0-9][0-9][0-9])", "%1%2") until t == prev
    t = gsub(t, "([0-9]),([0-9])", "%1.%2")
  else
    repeat prev = t; t = gsub(t, "([0-9]),([0-9][0-9][0-9])", "%1%2") until t == prev
  end
  return t
end

local UNIT_SECONDS = { sec = 1, sek = 1, min = 60, hour = 3600, stunde = 3600 }

-- "12 sec", "8 secs", "1 min", "30 minutes", "1 hour" / "12 Sek.", "8 Sekunden", "1 Min.", "1 Stunde"
local function unitSeconds(word)
  if not word then return nil end
  if sub(word, 1, 3) == "sec" or sub(word, 1, 3) == "sek" then return 1 end
  if sub(word, 1, 3) == "min" then return 60 end
  if sub(word, 1, 4) == "hour" or sub(word, 1, 6) == "stunde" then return 3600 end
  return nil
end

-- Take "lasts N sec" / "Hält N Sek. lang an" out of the text: it is the duration of the whole
-- effect, used by "every N sec" amounts anywhere in the description.
local function extractLasts(t, lang)
  local values = {}
  local function take(num, unit)
    local u = unitSeconds(unit)
    if u then values[#values + 1] = tonumber(num) * u end
    return " "
  end
  if lang == "de" then
    t = gsub(t, "h\195\164lt (" .. NUM .. ") ([a-z]+)%.? lang an", take)
  else
    t = gsub(t, "lasts for (" .. NUM .. ") ([a-z]+)", take)
    t = gsub(t, "lasts (" .. NUM .. ") ([a-z]+)", take)
  end
  local lasts
  for _, v in ipairs(values) do
    if lasts and lasts ~= v then return t, nil, true end
    lasts = v
  end
  return t, lasts, false
end

local function splitSentences(t, lang)
  if lang == "de" then
    -- "12 Sek. lang" and "1 Min. Kann" do not end a sentence.
    t = gsub(t, "([0-9]) sek%.", "%1 sek")
    t = gsub(t, "([0-9]) min%.", "%1 min")
  end
  local out = {}
  for s in gmatch(t .. " ", "(.-)%. ") do out[#out + 1] = s end
  local rest = match(t .. " ", ".*%. (.*)$")
  if rest and find(rest, "[^ ]") then out[#out + 1] = rest end
  if #out == 0 then out[1] = t end
  return out
end

local function splitClauses(s, lang)
  if lang == "de" then
    s = gsub(s, " und ", "\1")
    s = gsub(s, " sowie ", "\1")
  else
    s = gsub(s, ", and ", "\1")
    s = gsub(s, " and ", "\1")
  end
  local out = {}
  for c in gmatch(s .. "\1", "([^\1]*)\1") do out[#out + 1] = " " .. c .. " " end
  return out
end

-- Remove the "every N sec" part of a clause and return its interval in seconds.
local function takeInterval(c, lang)
  local interval
  local function num(n, unit)
    local u = unitSeconds(unit)
    if u and not interval then interval = tonumber(n) * u end
    return " # "
  end
  local function one() if not interval then interval = 1 end return " # " end
  if lang == "de" then
    c = gsub(c, "alle (" .. NUM .. ") ([a-z]+)", num)
    c = gsub(c, "pro sekunde", one)
    c = gsub(c, "in jeder sekunde", one)
    c = gsub(c, "jede sekunde", one)
  else
    c = gsub(c, "every (" .. NUM .. ") ([a-z]+)", num)
    c = gsub(c, "every second", one)
    c = gsub(c, "each second", one)
    c = gsub(c, "per second", one)
  end
  return c, interval
end

-- Remove the durations of a clause ("over 12 sec", "12 Sek. lang", "after 1 min") and list them.
local function takeDurations(c)
  local list = {}
  c = gsub(c, "(" .. NUM .. ") ?([a-z]+)", function(n, unit)
    local u = unitSeconds(unit)
    if not u then return nil end
    list[#list + 1] = tonumber(n) * u
    return " # "
  end)
  return c, list
end

local function stripFillers(s, fillers)
  local again = true
  while again do
    again = false
    s = gsub(s, "^ +", "")
    for _, f in ipairs(fillers) do
      if sub(s, 1, #f) == f then
        s = sub(s, #f + 1)
        again = true
      end
    end
  end
  return s
end

local HEAL_WORDS_EN = { "^ *heals ", " heals ", " healing ", " heal " }
local HEAL_WORDS_DE = { " heilt ", " geheilt ", " heilen " }

local function isHealClause(c, lang)
  local words = (lang == "de") and HEAL_WORDS_DE or HEAL_WORDS_EN
  for _, w in ipairs(words) do
    if find(c, w) then return true end
  end
  return false
end

local function hasDamageWord(c, lang)
  if lang == "de" then return find(c, "schaden") ~= nil end
  return find(c, "damage") ~= nil
end

-- What the words right after an amount say it is: damage of a school, a health drain,
-- health given, or nothing we understand.
local function classifyAfter(after, lang, sentence)
  if lang == "de" then
    local s = stripFillers(after, FILLERS_DE)
    local prefix = match(s, "^([a-z]*)schaden")
    if prefix and SCHOOL_DE[prefix] then return "damage", SCHOOL_DE[prefix] end
    if sub(s, 1, 10) == "gesundheit" then
      if find(sentence, "\195\188bertr\195\164gt") then return "drain", nil end
      if find(sentence, "gibt ") then return "giveheal", nil end
    end
  else
    local s = stripFillers(after, FILLERS_EN)
    if sub(s, 1, 6) == "damage" then return "damage", "physical" end
    local word = match(s, "^([a-z]+) damage")
    if word and SCHOOL_EN[word] then return "damage", SCHOOL_EN[word] end
    if sub(s, 1, 6) == "health" then
      if find(sentence, "transfers ") then return "drain", nil end
      if find(sentence, "gives ") then return "giveheal", nil end
    end
  end
  return nil
end

local function healAmountOK(before, after, lang)
  if lang == "de" then
    if find(before, " um $") or find(before, " weitere $") then return true end
    local s = stripFillers(after, FILLERS_DE)
    return sub(s, 1, 7) == "schaden" or sub(s, 1, 10) == "gesundheit"
      or find(after, "^ *punkt") ~= nil
  end
  -- A count, not an amount: "Heals 3 total targets."
  local word = match(after, "^ *([a-z]+)")
  if word == "total" or word == "target" or word == "targets" or word == "times" or word == "charges" then
    return false
  end
  if find(before, " for $") or find(before, " of $") or find(before, " another $") or find(before, "heals $") then
    return true
  end
  local s = stripFillers(after, FILLERS_EN)
  return sub(s, 1, 6) == "damage" or sub(s, 1, 6) == "health"
end

-- Find the amounts in one clause. Each is { kind = "damage"|"heal"|"drain", min, max, school }.
local function findAmounts(c, lang, healMode, sentence)
  local amounts = {}
  local rangeWord = (lang == "de") and "bis" or "to"
  local pos = 1
  while true do
    local s, e = find(c, NUM, pos)
    if not s then break end
    local prevChar = sub(c, s - 1, s - 1)
    local valueMin = tonumber(sub(c, s, e))
    local valueMax = valueMin
    local stop = e
    -- "9 to 12" / "9 bis 12"
    local rs, re = find(c, "^ +" .. rangeWord .. " +" .. NUM, e + 1)
    if rs then
      local second = match(sub(c, rs, re), "(" .. NUM .. ")$")
      valueMax = tonumber(second)
      stop = re
    end
    pos = stop + 1
    if not match(prevChar, "[a-z0-9%-]") and valueMin and valueMax then
      local before = sub(c, 1, s - 1)
      local after = sub(c, stop + 1)
      if healMode then
        if healAmountOK(before, after, lang) then
          amounts[#amounts + 1] = { kind = "heal", min = valueMin, max = valueMax }
        end
      else
        local kind, school = classifyAfter(after, lang, sentence)
        if kind == "damage" or kind == "drain" then
          amounts[#amounts + 1] = { kind = kind, min = valueMin, max = valueMax, school = school }
        elseif kind == "giveheal" then
          amounts[#amounts + 1] = { kind = "heal", min = valueMin, max = valueMax }
        end
      end
    end
  end
  return amounts
end

-- German sometimes puts a DoT's duration in the clause before its amount:
-- "lässt es 9 Sek. lang bluten und fügt damit 15 Punkt(e) Schaden zu".
local DE_DOT_VERBS = { "blut", "vergift", "brenn" }

local function hasDotVerb(c)
  for _, v in ipairs(DE_DOT_VERBS) do
    if find(c, v) then return true end
  end
  return false
end

-- Clauses whose amounts are not the spell's damage or healing: self-damage, absorbs, and
-- amounts per unit of something else ("for each mana destroyed, the target takes 0.5 Shadow
-- damage" / "Für jeden ... Manapunkt ... 0,5 Punkt(e) Schattenschaden").
local function ignoredClause(c, lang)
  if lang == "de" then
    return find(c, " selbst ") or find(c, "absorb") or find(c, "f\195\188r jede")
  end
  return find(c, "himself") or find(c, "herself") or find(c, "yourself") or find(c, "absorb")
    or find(c, "for each ")
end

-- Plain lower-case text with numbers in one format ("1.132" / "1,132" -> "1132", "7,1" -> "7.1"),
-- and the language.
local function prepare(text, lang)
  local t = gsub(text, "[\r\n\t]+", " ")
  t = gsub(t, "\194\160", " ") -- no-break space
  t = gsub(t, "|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "")
  t = gsub(t, "|r", "")
  t = replaceFormulas(t)
  t = gsub(t, "[A-Z]", asciiLower)
  t = gsub(t, "\195[\132\150\156]", UMLAUT_LOWER)
  if lang ~= "de" and lang ~= "en" then lang = detectLanguage(t) end
  return normaliseNumbers(t, lang), lang
end

---------------------------------------------------------------------------------------------
-- Weapon and attack power abilities (new in 0.5.0)
---------------------------------------------------------------------------------------------

-- "weapon damage plus N" (EN) or "Waffenschaden plus N" (DE). Returns the bonus N.
-- Also handles "% weapon damage plus N" and ranged weapon damage.
local function tryWeaponDamage(t, lang)
  if lang == "de" then
    -- "waffenschaden plus N" - basic
    local bonus = match(t, "waffenschaden plus (" .. NUM .. ")")
    if bonus then return { weapon_damage = tonumber(bonus) } end
  else
    -- "weapon damage plus N" - basic
    local bonus = match(t, "weapon damage plus (" .. NUM .. ")")
    if bonus then return { weapon_damage = tonumber(bonus) } end
    -- "ranged weapon damage plus N"
    bonus = match(t, "ranged weapon damage plus (" .. NUM .. ")")
    if bonus then return { weapon_damage = tonumber(bonus), ranged = true } end
  end
  return nil
end

-- "increases melee damage by N" (EN) or "den Nahkampfschaden um N... erhöht" (DE).
-- Also handles "increases the druid's next attack by N damage" and ranged equivalents.
-- Returns the bonus damage N.
local function tryNextAttack(t, lang)
  if lang == "de" then
    -- "den nahkampfschaden um N punkt(e) erh\195\164ht" (ä = \195\164)
    local bonus = match(t, "den nahkampfschaden um (" .. NUM .. ")")
    if bonus then return { next_attack_bonus = tonumber(bonus) } end
    -- Also match "angriffsschaden" variant used by druids in bear form (Maul/Zermalmen)
    bonus = match(t, "den %w+angriffsschaden um (" .. NUM .. ")")
    if bonus then return { next_attack_bonus = tonumber(bonus) } end
  else
    -- "increases melee damage by N"
    local bonus = match(t, "increases melee damage by (" .. NUM .. ")")
    if bonus then return { next_attack_bonus = tonumber(bonus) } end
    -- "increases ranged damage by N"
    bonus = match(t, "increases ranged damage by (" .. NUM .. ")")
    if bonus then return { next_attack_bonus = tonumber(bonus), ranged = true } end
    -- "increases the druid's next attack by N damage" or similar
    bonus = match(t, "next attack by (" .. NUM .. ")")
    if bonus then return { next_attack_bonus = tonumber(bonus) } end
  end
  return nil
end

-- "increasing ... attack power ... by N" (EN) or "die ... angriffskraft ... um N erhöht" (DE).
-- Returns the AP buff amount N. Ignore "for X min" or other conditions.
local function tryAPBuff(t, lang)
  if lang == "de" then
    -- "die nahkampfangriffskraft ... um N erh\195\164ht" or "die distanzangriffskraft ... um N erh\195\164ht"
    -- Match any text (including digits like "20 metern") between keyword and "um N"
    local buff = match(t, "nahkampfangriffskraft [^e]* um (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff) } end
    buff = match(t, "distanzangriffskraft [^e]* um (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff) } end
  else
    -- "increasing melee attack power by N" (simple)
    local buff = match(t, "increasing melee attack power by (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff) } end
    -- "increasing the melee attack power ... by N"
    buff = match(t, "increasing the melee attack power .* by (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff) } end
    -- "increasing ranged attack power by N" (simple)
    buff = match(t, "increasing ranged attack power by (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff), ranged = true } end
    -- "increasing the ranged attack power ... by N"
    buff = match(t, "increasing the ranged attack power .* by (" .. NUM .. ")")
    if buff then return { ap_buff = tonumber(buff), ranged = true } end
  end
  return nil
end

-- "granting each melee attack an additional N to M ... damage" (EN) or
-- "jedem Nahkampfangriff zusätzlichen Heiligschaden in Höhe von N - M" (DE).
-- Returns the damage range per hit and school. Ignore "chance to heal/restore" seals.
local function tryImbue(t, lang)
  if lang == "de" then
    -- "jedem nahkampfangriff zus\195\164tzlichen SCHOOL schaden in h\195\182he von N - M verleiht"
    -- (ä = \195\164, ö = \195\182)
    -- But skip "chance to heal" type seals
    if find(t, "chance") or find(t, "chance") or find(t, "wahrscheinlichkeit") then return nil end
    local s, e, prefix, lo, hi
    local pattern = "jedem nahkampfangriff zus\195\164tzlichen ([a-z]+)schaden in h\195\182he von (" .. NUM .. ") %- (" .. NUM .. ")"
    s, e, prefix, lo, hi = find(t, pattern)
    if s then
      local school = SCHOOL_DE[prefix or ""]
      return { imbue_seal = { min = tonumber(lo), max = tonumber(hi), school = school } }
    end
  else
    -- Skip "chance to heal" type seals
    if find(t, "chance") then return nil end
    -- "granting each melee attack an additional N to M ... damage"
    local lo, hi, after = match(t, "granting each melee attack an additional (" .. NUM .. ") to (" .. NUM .. ") (%a+) damage")
    if lo and hi then
      local school = SCHOOL_EN[after or "physical"]
      return { imbue_seal = { min = tonumber(lo), max = tonumber(hi), school = school } }
    end
  end
  return nil
end

-- Try to parse a weapon or attack power ability. Returns parsed result or nil.
local function tryWeaponAbility(t, lang)
  -- Try each category in order
  local result = tryWeaponDamage(t, lang) or tryNextAttack(t, lang) or tryAPBuff(t, lang) or tryImbue(t, lang)
  return result
end

function Parser.Parse(text, lang)
  if type(text) ~= "string" or text == "" then return nil, "empty" end
  local t
  t, lang = prepare(text, lang)
  t = gsub(t, NUM .. " ?%%", " pct ")

  -- Per-combo-point tables: weapon abilities may also say "weapon damage" but that's OK.
  if find(t, "[^0-9]1 points? *:") or find(" " .. t, "[^0-9]1 punkte? *:") then return nil, "finisher" end

  -- Try weapon/attack power abilities first.
  local weaponResult = tryWeaponAbility(t, lang)
  if weaponResult then return weaponResult end

  local lasts, lastsAmbiguous
  t, lasts, lastsAmbiguous = extractLasts(t, lang)

  local result = {}
  local found = false
  local function put(slot, value)
    if result[slot] then return false end
    result[slot] = value
    found = true
    return true
  end

  for _, sentence in ipairs(splitSentences(t, lang)) do
    local clauses = {}
    local prevHeal = false
    for i, raw in ipairs(splitClauses(sentence, lang)) do
      local c, interval = takeInterval(raw, lang)
      local durations
      c, durations = takeDurations(c)
      local heal = isHealClause(c, lang) or (prevHeal and not hasDamageWord(c, lang))
      prevHeal = heal
      local amounts = {}
      if not ignoredClause(c, lang) then amounts = findAmounts(c, lang, heal, sentence) end
      clauses[i] = { text = c, raw = raw, interval = interval, durations = durations, amounts = amounts }
    end
    if lang == "de" then
      for i = 1, #clauses - 1 do
        local a, b = clauses[i], clauses[i + 1]
        if #a.amounts == 0 and #a.durations == 1 and not a.interval and hasDotVerb(a.raw)
          and #b.amounts > 0 and #b.durations == 0 and not b.interval then
          b.durations = { a.durations[1] }
        end
      end
    end
    for _, cl in ipairs(clauses) do
      if #cl.amounts > 0 then
        local periodic, duration, ticks
        if cl.interval then
          duration = (#cl.durations == 1 and cl.durations[1]) or (#cl.durations == 0 and lasts) or nil
          if not duration then
            return nil, lastsAmbiguous and "lasts-ambiguous" or "interval-without-duration"
          end
          ticks = floor(duration / cl.interval + 0.5)
          if ticks < 1 then return nil, "interval" end
          periodic = true
        elseif #cl.durations == 1 then
          if #cl.amounts > 1 then return nil, "two-amounts-one-duration" end
          duration = cl.durations[1]
          ticks = 1
          periodic = true
        elseif #cl.durations > 1 then
          return nil, "several-durations"
        end
        for _, a in ipairs(cl.amounts) do
          local isHeal = (a.kind == "heal")
          if periodic then
            if a.min ~= a.max then return nil, "periodic-range" end
            local slot = isHeal and "hot" or "dot"
            if not put(slot, { total = a.min * ticks, duration = duration }) then return nil, "second-" .. slot end
          else
            local slot = isHeal and "heal" or "direct"
            if not put(slot, { min = a.min, max = a.max }) then return nil, "second-" .. slot end
          end
          if not isHeal and result.school == nil and a.kind == "damage" then result.school = a.school end
        end
      end
    end
  end

  if not found then return nil, "no-amount" end
  return result
end

---------------------------------------------------------------------------------------------
-- Debuffs that lower the enemy's damage or attack power
---------------------------------------------------------------------------------------------

local REDUCE_VERBS = {
  en = { "reduc", "lower", "decreas" },
  de = { "verringer", "reduzier", "senk", "vermindert" },
}
-- The enemy has to be named somewhere in the sentence.
local ENEMY_WORDS = {
  en = { "target", "enem" },
  de = { "ziel", "feind", "gegner" },
}
-- Damage the caster or the party takes, or the caster's own damage: not an enemy debuff.
local SELF_WORDS = {
  en = { "take", "your ", "yourself" },
  de = { "erlitten", " euer", " eure" },
}

local function hasAny(s, words)
  for _, w in ipairs(words) do
    if find(s, w, 1, true) then return true end
  end
  return false
end

-- One clause: "Damage caused by the target is reduced by 3", "reduces the melee attack power
-- of all enemies within 10 yards by 45" / "der vom Ziel verursachte Schaden wird ... um 3
-- reduziert", "verringert ... die Nahkampfangriffskraft ... um 45".
local function reductionInClause(c, lang)
  if not hasAny(c, REDUCE_VERBS[lang]) or hasAny(c, SELF_WORDS[lang]) then return nil end
  local ap = (lang == "de") and find(c, "angriffskraft", 1, true) or find(c, "attack power", 1, true)
  -- German: the word "Schaden" itself, not a school's damage such as "Frostfeuerschaden"
  local dmg = (lang == "de") and find(" " .. c, " schaden", 1, true) or find(c, "damage", 1, true)
  if not ap and not dmg then return nil end
  local by = (lang == "de") and "um " or "by "
  local s, e, num
  local from = 1
  repeat -- the first "by N" / "um N" that starts a word ("nearby 3" does not)
    s, e, num = find(c, by .. "(" .. NUM .. ")", from)
    if not s then return nil end
    from = e + 1
    local prev = sub(c, s - 1, s - 1)
  until prev == "" or prev == " "
  local rest = sub(c, e + 1)
  local percent = find(rest, "^ ?%%") ~= nil
  if not percent then
    local word = match(rest, "^ ?([a-z]+)")
    -- "by 3 sec" is a duration; "by 10 yards" a distance
    if unitSeconds(word) or word == "yard" or word == "yards" or word == "meter" or word == "metern" then return nil end
  end
  local amount = tonumber(num)
  if not amount or amount <= 0 then return nil end
  return { amount = amount, percent = percent, stat = ap and "attackpower" or "damage" }
end

-- ParseReduction(text, lang) returns { amount = n, percent = true|false, stat = "damage" |
-- "attackpower" } for a spell that lowers the enemy's damage or attack power, or nil.
function Parser.ParseReduction(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  local found
  for _, sentence in ipairs(splitSentences(t, lang)) do
    if hasAny(sentence, ENEMY_WORDS[lang]) then
      for _, clause in ipairs(splitClauses(sentence, lang)) do
        -- a comma separates what the spell does to whom: "..., die Bewegungsgeschwindigkeit um
        -- 50% verringert"
        for c in gmatch(clause, "[^,]+") do
          local r = reductionInClause(c, lang)
          if r then
            if found and (found.amount ~= r.amount or found.percent ~= r.percent) then return nil end
            found = found or r
          end
        end
      end
    end
  end
  return found
end

-- Exposed for the tests.
Parser._evalArithmetic = evalArithmetic

return Parser
