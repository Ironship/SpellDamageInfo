-- SpellCoefficients.lua against the client's own spell tables, and the estimate that uses it.
--
--   lua tests/test_coefficients.lua [addon folder]
--
-- 1. For the spells the checks below name, the table's shares are worked out again from the raw
--    SpellEffect, SpellMisc and SpellDuration rows of both builds (tests/fixtures/coefficient_rows.json,
--    written by tools/make_coefficients.py from wago.tools' CSVs): per tick x ticks for an aura,
--    the triggered spell for a channel, a proc or a weapon imbue.
-- 2. The shares the client tables give, as read from those CSVs, for the spells in question.
-- 3. The estimate follows the table: Forever's own texts at 300 spell power.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local json = require("json")

local root = (arg and arg[1]) or "."
local ns = {}
T.loadAddonFile(root .. "/Locale.lua", ns)
T.loadAddonFile(root .. "/SpellCoefficients.lua", ns)
T.loadAddonFile(root .. "/Parser.lua", ns)
T.loadAddonFile(root .. "/Estimate.lua", ns)
local C, E, P = ns.SpellCoefficients, ns.Estimate, ns.Parser

local function near(got, want, label)
  return T.check(got ~= nil and math.abs(got - want) < 1e-6, ("%s: got %s, want %s"):format(label, tostring(got), tostring(want)))
end

---------------------------------------------------------------------------------------------
-- 1. The shares again, from the raw rows
---------------------------------------------------------------------------------------------
local rows = json.decode(T.readFile(root .. "/tests/fixtures/coefficient_rows.json"))
T.eq(rows.forever.build, "1.60.1.70009", "Forever's build")
T.check(rows.era.build:match("^1%.15%.") ~= nil, "a Classic Era build: " .. tostring(rows.era.build))

local set = function(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local DIRECT_DAMAGE, AURA_EFFECTS = set({ 2, 9, 62 }), set({ 6, 27, 35, 65 })
local PERIODIC_DAMAGE, PER_STRIKE, SUMMONS = set({ 3, 53 }), set({ 15, 43 }), set({ 28, 104, 320 })

local function shares(spells, id)
  local s = spells[tostring(id)]
  if not s then return nil end
  local out, summons = {}, false
  local function add(k, v) out[k] = (out[k] or 0) + v end
  for _, e in ipairs(s.effects) do
    local ticks = (s.duration > 0 and e.period > 0) and math.floor(s.duration / e.period) or 0
    if DIRECT_DAMAGE[e.effect] then
      add("d", e.coef)
    elseif e.effect == 10 then
      add("h", e.coef)
    elseif AURA_EFFECTS[e.effect] then
      if PERIODIC_DAMAGE[e.aura] and not (e.effect == 6 and e.target == 1) then
        add("o", e.coef * ticks)
      elseif e.aura == 8 then
        add("ho", e.coef * ticks)
      elseif e.aura == 23 and e.trigger > 0 then
        local t = shares(spells, e.trigger) or {}
        if t.d then add("o", t.d * ticks) end
        if t.h then add("ho", t.h * ticks) end
      elseif e.aura == 42 and e.trigger > 0 then
        local t = shares(spells, e.trigger) or {}
        if e.coef ~= 0 then add("d", e.coef) elseif t.d then add("d", t.d) end
        if t.h then add("h", t.h) end
      elseif PER_STRIKE[e.aura] then
        add("d", e.coef)
      end
    elseif SUMMONS[e.effect] then
      summons = true
    else
      for _, spell in ipairs(e.enchantSpells) do
        local t = shares(spells, spell) or {}
        if t.d then add("d", t.d) end
      end
    end
  end
  if next(out) == nil and summons then return false end
  return out
end

local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

local checked = 0
for _, client in ipairs({ "forever", "era" }) do
  for id in pairs(rows[client].spells) do
    local entry = C[client][tonumber(id)]
    local want = shares(rows[client].spells, tonumber(id))
    -- triggered spells (the missile, the pulse) are in the rows but not in SpellIDs.lua
    if entry ~= nil then
      checked = checked + 1
      if want == false or entry == false then
        T.eq(entry, want, client .. " " .. id .. ": a totem or trap")
      else
        for _, k in ipairs({ "d", "o", "h", "ho" }) do
          local w = want[k] and round3(want[k]) or nil
          T.check(entry[k] == w or (entry[k] and w and math.abs(entry[k] - w) < 1e-9),
            ("%s %s %s: table %s, rows %s"):format(client, id, k, tostring(entry[k]), tostring(w)))
        end
      end
    end
  end
end
T.check(checked >= 60, "spells checked against their rows: " .. checked)

---------------------------------------------------------------------------------------------
-- 2. What the client tables give (SpellEffect.EffectBonusCoefficient, per tick x ticks)
---------------------------------------------------------------------------------------------
local F, R = C.forever, C.era
-- area spells: a third of the cast time share
near(F[10202].d, 0.143, "Forever Arcane Explosion r6: 1.5 / 3.5 / 3")
near(R[10202].d, 0.143, "Era Arcane Explosion r6")
near(F[25316].h, 0.286, "Prayer of Healing r5: 3 / 3.5 / 3")
near(F[10318].d, 0.19, "Holy Wrath r2")
near(F[27801].d, 0.107, "Holy Nova r6")
near(F[9863].ho, 0.335, "Tranquility r4: 0.067 x 5")
near(F[11684].o, 0.33, "Hellfire r3: its tick spell 0.022 x 15, not the burn on the warlock")
near(R[10187].o, 0.336, "Era Blizzard r6: 0.042 x 8")
T.eq(F[10187], nil, "Forever's Blizzard casts its ticks from an area trigger the tables do not link: the rules")
-- channels
near(F[25345].o, 1.43, "Forever Arcane Missiles r8: its missile 0.286 x 5 = 5 / 3.5")
near(R[25345].o, 1.2, "Era Arcane Missiles r8: 0.24 x 5")
near(F[18807].o, 0.501, "Forever Mind Flay r6: 0.167 x 3")
near(R[18807].o, 0.45, "Era Mind Flay r6: 0.15 x 3")
near(F[19305].o, 1.002, "Starshards: 0.167 x 6")
-- the direct part the full share, not the hybrid split
near(F[25306].d, 1, "Fireball r12 direct")
near(F[25306].o, 0, "Fireball r12 over time: nothing")
near(F[18809].d, 1, "Pyroblast r8 direct")
near(F[18809].o, 0.6, "Pyroblast r8 over time: 0.15 x 4")
near(F[401502].d, 0.814, "Forever's Frostfire Bolt direct")
near(F[401502].o, 0, "Forever's Frostfire Bolt over time")
-- over time: Forever uncapped, Era capped
near(F[10894].o, 1.2, "Forever SW:P r8: 0.2 x 6")
near(R[10894].o, 1.002, "Era SW:P r8: 0.167 x 6")
near(F[25311].o, 1.2, "Forever Corruption r7")
near(F[11713].o, 1.596, "Forever Bane of Agony: 0.133 x 12")
near(R[11713].o, 0.996, "Era Curse of Agony: 0.083 x 12")
near(F[603].o, 4, "Forever Bane of Doom: 4 on its one tick")
near(R[603].o, 1, "Era Curse of Doom")
near(F[19280].o, 0.8, "Forever Devouring Plague r6: 0.1 x 8")
near(R[19280].o, 0.504, "Era Devouring Plague r6: 0.063 x 8")
-- the leech and slow penalties the tables already hold
near(F[17926].d, 0.214, "Death Coil r3")
near(F[25304].d, 0.814, "Frostbolt r11")
near(F[11700].o, 0.5, "Drain Life r6: 0.1 x 5")
near(F[18881].o, 0.5, "Siphon Life r4: 0.05 x 10")
-- Classic Era's penalty for spells learned before level 20 is in Era's own table; Forever has none
near(R[585].d, 0.123, "Era Smite r1: 1.5 / 3.5 x (1 - 19 x 0.0375)")
near(F[585].d, 0.429, "Forever Smite r1")
near(R[2050].h, 0.123, "Era Lesser Heal r1")
near(R[139].ho, 0.55, "Era Renew r1, learned at 8: 0.11 x 5")
near(F[139].ho, 1, "Forever Renew r1: 0.2 x 5")
near(R[774].ho, 0.32, "Era Rejuvenation r1, learned at 4: 0.08 x 4")
-- hunter spells: none on Forever
near(F[14287].d, 0, "Forever Arcane Shot r8: no spell power")
near(R[14287].d, 0.429, "Era Arcane Shot r8")
near(F[25295].o, 0, "Forever Serpent Sting r9: no spell power")
near(R[25295].o, 1, "Era Serpent Sting r9: 0.2 x 5")
-- per strike, per block, and what the tables leave at nothing
near(F[20928].d, 0.08, "Forever Holy Shield r3, per block")
near(R[20928].d, 0.05, "Era Holy Shield r3, per block")
near(F[9910].d, 0, "Thorns r6")
near(F[10301].d, 0, "Retribution Aura r5")
near(F[10876].d, 0, "Mana Burn r5")
near(F[11695].ho, 0, "Health Funnel 11695: the warlock's own health, nothing added")
-- a weapon imbue's proc and a totem
near(F[16356].d, 0.1, "Frostbrand Weapon r5: Frostbrand Attack 0.1 per proc")
T.eq(F[10463], false, "Healing Stream Totem: its pulse is the totem's own spell")
T.eq(F[10438], false, "Searing Totem")
T.eq(R[10587], false, "Magma Totem on Era")
T.eq(F[14305], false, "Immolation Trap: the trap's own spell")

---------------------------------------------------------------------------------------------
-- 3. The estimate follows the table (Forever's English texts, 300 spell power)
---------------------------------------------------------------------------------------------
local texts = {}
for _, r in ipairs(json.decode(T.readFile(root .. "/tests/fixtures/forever_client_texts.json"))) do
  if r.lang == "en" then texts[r.id] = r.text end
end
local function applyFor(id, castTime, client)
  local parsed = P.Parse(texts[id], "en")
  return E.Apply(parsed, castTime, 300, 300, C[client or "forever"][id])
end

local v = applyFor(10202, 0)
near(v.direct.added, 300 * 0.143, "Arcane Explosion +42.9, not the single-target +128.6")
v = applyFor(25345, 0)
near(v.dot.added, 300 * 1.43, "Arcane Missiles +429 over the channel, not duration / 15")
v = applyFor(25306, 3.5)
near(v.direct.added, 300, "Fireball's direct part the full share")
T.eq(v.dot.added, 0, "Fireball's burn: nothing")
v = applyFor(25306, 3.0)
near(v.direct.added, 300, "Fireball: a shorter cast after talents or haste does not lower it")
v = applyFor(18809, 6)
near(v.direct.added, 300, "Pyroblast direct")
near(v.dot.added, 180, "Pyroblast over time: 0.6")
v = applyFor(14287, 0)
T.eq(v.direct.added, 0, "Forever Arcane Shot: no spell power")
T.eq(v.estimated, false, "Forever Arcane Shot: not marked as estimate")
v = applyFor(14287, 0, "era")
near(v.direct.added, 300 * 0.429, "Era Arcane Shot: the table's 0.429")
v = applyFor(10894, 0)
near(v.dot.added, 360, "Forever SW:P: 1.2, past the Classic cap")
v = applyFor(585, 1.5, "era")
near(v.direct.added, 300 * 0.123, "Era Smite r1: the level penalty")
v = applyFor(25345, nil)
near(v.dot.added, 300 * 1.43, "the table needs no cast time")
-- a part the tables do not link gets nothing: Forever's Flamestrike burns from an area trigger
v = applyFor(10216, 3)
near(v.direct.added, 300 * 0.157, "Flamestrike r6 direct")
T.eq(v.dot.added, 0, "Flamestrike's burn on Forever: not in the tables, no estimate")
-- no entry: the rules, as before
v = E.Apply(P.Parse(texts[10894], "en"), 0, 300, nil, nil)
near(v.dot.added, 300, "without an entry: duration / 15, capped")

T.finish("test_coefficients")
