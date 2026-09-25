-- Coefficient maths, the button value, number formatting and the tooltip lines.
--
--   lua tests/test_estimate.lua [addon folder]
--
-- Reference coefficients are worked out by hand from the Classic rules:
--   direct a = max(1.5, min(cast, 3.5)) / 3.5, over time b = min(duration / 15, 1),
--   both in one spell: direct a*a/(a+b), over time b*b/(a+b).

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")

local root = (arg and arg[1]) or "."
local ns = {}
T.loadAddonFile(root .. "/Locale.lua", ns)
T.loadAddonFile(root .. "/Estimate.lua", ns)
local E, Format, Locales = ns.Estimate, ns.Format, ns.Locales

local function near(got, want, label)
  return T.check(got ~= nil and math.abs(got - want) < 1e-5, ("%s: got %s, want %s"):format(label, tostring(got), tostring(want)))
end

-- Direct only
near((E.Coefficients(0, true, nil)), 1.5 / 3.5, "instant counts as 1.5 sec")
near((E.Coefficients(1.0, true, nil)), 0.428571, "1 sec cast counts as 1.5 sec")
near((E.Coefficients(2.5, true, nil)), 0.714286, "2.5 sec cast")
near((E.Coefficients(3.0, true, nil)), 0.857143, "3 sec cast")
near((E.Coefficients(5.0, true, nil)), 1.0, "cast time capped at 3.5 sec")

-- Over time only
local _, c = E.Coefficients(nil, false, 18)
near(c, 1.0, "18 sec DoT capped at 1")
_, c = E.Coefficients(nil, false, 12)
near(c, 0.8, "12 sec DoT")
_, c = E.Coefficients(nil, false, 6)
near(c, 0.4, "6 sec DoT")

-- Both parts
local d, o = E.Coefficients(2.0, true, 15)
near(d, 0.207792, "Immolate direct part")
near(o, 0.636364, "Immolate over-time part")
d, o = E.Coefficients(3.5, true, 8)
near(d, 0.652174, "Fireball direct part")
near(o, 0.185507, "Fireball over-time part")
d, o = E.Coefficients(0, true, 12)
near(d, 0.149502, "Moonfire direct part")
near(o, 0.520930, "Moonfire over-time part")

-- School bonus lookup
local bonus = { [2] = 10, [3] = 50, [4] = 11, [5] = 70, [6] = 100, [7] = 12 }
T.eq(E.DamageBonus("shadow", bonus), 100, "shadow uses index 6")
T.eq(E.DamageBonus("fire", bonus), 50, "fire uses index 3")
T.eq(E.DamageBonus("frostfire", bonus), 70, "frostfire takes the higher of fire and frost")
T.eq(E.DamageBonus("physical", bonus), nil, "no spell power for physical")
T.eq(E.DamageBonus(nil, bonus), nil, "no spell power for an unknown school")

-- Apply
local v = E.Apply({ direct = { min = 253, max = 283 }, school = "shadow" }, 3.0, 100, nil)
near(v.direct.min, 253 + 85.714286, "Shadow Bolt min with 100 spell power")
near(v.direct.max, 283 + 85.714286, "Shadow Bolt max with 100 spell power")
near(v.direct.added, 85.714286, "Shadow Bolt added")
T.eq(v.estimated, true, "marked as estimate")

v = E.Apply({ direct = { min = 11, max = 11 }, dot = { total = 20, duration = 15 }, school = "fire" }, 2.0, 100, nil)
near(v.direct.min, 11 + 20.779221, "Immolate direct with 100 spell power")
near(v.dot.total, 20 + 63.636364, "Immolate DoT with 100 spell power")

v = E.Apply({ dot = { total = 822, duration = 18 }, school = "shadow" }, nil, 100, nil)
near(v.dot.total, 922, "Corruption needs no cast time")

v = E.Apply({ direct = { min = 253, max = 283 }, school = "shadow" }, nil, 100, nil)
T.eq(v.direct.min, 253, "unknown cast time: no estimate for a direct part")
T.eq(v.estimated, false, "not marked as estimate")

v = E.Apply({ heal = { min = 93, max = 107 }, hot = { total = 98, duration = 21 } }, 2.0, 100, 200)
d, o = E.Coefficients(2.0, true, 21)
near(v.heal.min, 93 + 200 * d, "Regrowth uses the healing bonus")
near(v.hot.total, 98 + 200 * o, "Regrowth HoT uses the healing bonus")

v = E.Apply({ dot = { total = 50, duration = 5 } }, 0, nil, nil)
T.eq(v.dot.total, 50, "drain without a school: description only")

-- Button value
T.eq(E.ButtonValue(E.Apply({ direct = { min = 11, max = 11 }, dot = { total = 20, duration = 15 }, school = "fire" }), "total"), 31, "total = direct + DoT")
T.eq(E.ButtonValue(E.Apply({ direct = { min = 13, max = 18 }, school = "shadow" }), "total"), 15.5, "total uses the average hit")
T.eq(E.ButtonValue(E.Apply({ direct = { min = 11, max = 11 }, dot = { total = 20, duration = 15 } }), "direct"), 11, "direct only")
T.eq(E.ButtonValue(E.Apply({ dot = { total = 20, duration = 15 } }), "direct"), nil, "direct only, spell without a direct part")
T.eq(E.ButtonValue(E.Apply({ dot = { total = 20, duration = 15 } }), "off"), nil, "off")
local hv, kind = E.ButtonValue(E.Apply({ heal = { min = 93, max = 107 }, hot = { total = 98, duration = 21 } }), "total")
T.eq(hv, 198, "heal total")
T.eq(kind, "heal", "heal kind")

-- Formatting
local en, de = Locales.en, Locales.de
T.eq(Format.Thousands(1305, en), "1,305", "thousands en")
T.eq(Format.Thousands(1305, de), "1.305", "thousands de")
T.eq(Format.Thousands(12345678, de), "12.345.678", "thousands de, long")
T.eq(Format.Thousands(999.6, en), "1,000", "rounds")
T.eq(Format.Seconds(7.1, de), "7,1", "decimal comma")
T.eq(Format.Seconds(15, en), "15", "whole seconds")
T.eq(Format.Short(922), "922", "short")
T.eq(Format.Short(9999.4), "9999", "short, four digits")
T.eq(Format.Short(12345), "12k", "short, thousands")

-- Tooltip lines
local lines = Format.TooltipLines(E.Apply({ direct = { min = 245, max = 280 }, school = "shadow" }, 3.0, 49, nil), en)
T.eq(lines[1][1], "Damage: 287-322 (incl. +42 from spell power, estimate)", "tooltip en direct with estimate")
lines = Format.TooltipLines(E.Apply({ dot = { total = 822, duration = 18 }, school = "shadow" }, nil, 100, nil), de)
T.eq(lines[1][1], "Schaden \195\188ber Zeit: 922 in 18 Sek. (inkl. +100 durch Zaubermacht, gesch\195\164tzt)", "tooltip de DoT with estimate")
lines = Format.TooltipLines(E.Apply({ direct = { min = 11, max = 11 }, dot = { total = 1493, duration = 7.5 }, school = "fire" }), de)
T.eq(lines[1][1], "Schaden: 11", "tooltip de direct")
T.eq(lines[2][1], "Schaden \195\188ber Zeit: 1.493 in 7,5 Sek.", "tooltip de DoT, no estimate")
lines = Format.TooltipLines(E.Apply({ heal = { min = 93, max = 107 }, hot = { total = 98, duration = 21 } }), en)
T.eq(lines[1][1], "Healing: 93-107", "tooltip en heal")
T.eq(lines[2][1], "Healing over time: 98 in 21 sec", "tooltip en HoT")

T.finish("test_estimate")
