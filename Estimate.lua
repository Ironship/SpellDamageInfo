-- SpellDamageInfo: the optional spell-power estimate (Classic rules) and the button value.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
-- Pure Lua 5.1, no game API.

local _, ns = ...
ns = ns or {}

local Estimate = {}
ns.Estimate = Estimate

-- Index of each school for GetSpellBonusDamage(school).
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }
Estimate.SCHOOL_INDEX = SCHOOL_INDEX

-- The spell-power bonus that applies to a school, from a table of GetSpellBonusDamage values
-- by index. Frostfire takes the higher of Frost and Fire. Physical damage (attack power) and
-- unknown schools get none.
function Estimate.DamageBonus(school, bonusByIndex)
  if not school or not bonusByIndex then return nil end
  if school == "frostfire" then
    local fire, frost = bonusByIndex[3], bonusByIndex[5]
    if fire and frost then return (fire > frost) and fire or frost end
    return fire or frost
  end
  local index = SCHOOL_INDEX[school]
  return index and bonusByIndex[index] or nil
end

-- Classic spell coefficients.
--   direct: cast time / 3.5, cast times under 1.5 sec (instants) count as 1.5, capped at 3.5 sec
--   over time: duration / 15, capped at 1
--   both in one spell: the two are split so the over-time part gets
--   b / (a + b) of the whole, i.e. direct a*a/(a+b), over time b*b/(a+b)
-- castTime and duration are in seconds. Returns the direct and over-time coefficients (or nil).
function Estimate.Coefficients(castTime, hasDirect, dotDuration)
  local a, b
  if hasDirect then
    local ct = castTime or 0
    if ct < 1.5 then ct = 1.5 end
    if ct > 3.5 then ct = 3.5 end
    a = ct / 3.5
  end
  if dotDuration and dotDuration > 0 then
    b = dotDuration / 15
    if b > 1 then b = 1 end
  end
  if a and b then
    return a * a / (a + b), b * b / (a + b)
  end
  return a, b
end

local function copyRange(r, add)
  return { min = r.min + add, max = r.max + add, added = add }
end

local function copyPeriodic(p, add)
  return { total = p.total + add, duration = p.duration, added = add }
end

-- Numbers to show for a parsed description. castTime (seconds) may be nil when unknown; then
-- a part that needs it gets no estimate. damageBonus / healBonus nil or 0 means no estimate.
function Estimate.Apply(parsed, castTime, damageBonus, healBonus)
  if not parsed then return nil end
  local view = { school = parsed.school, estimated = false }

  local function pair(directPart, periodicPart, bonus, directKey, periodicKey)
    local usable = type(bonus) == "number" and bonus > 0
    if directPart and castTime == nil then usable = false end
    local cDirect, cPeriodic
    if usable then
      cDirect, cPeriodic = Estimate.Coefficients(castTime, directPart ~= nil, periodicPart and periodicPart.duration)
    end
    if directPart then
      local add = (usable and cDirect) and bonus * cDirect or 0
      view[directKey] = copyRange(directPart, add)
      if add > 0 then view.estimated = true end
    end
    if periodicPart then
      local add = (usable and cPeriodic) and bonus * cPeriodic or 0
      view[periodicKey] = copyPeriodic(periodicPart, add)
      if add > 0 then view.estimated = true end
    end
  end

  pair(parsed.direct, parsed.dot, damageBonus, "direct", "dot")
  pair(parsed.heal, parsed.hot, healBonus, "heal", "hot")
  return view
end

-- The number for an action button. mode: "total" (average direct + everything over time),
-- "direct" (average direct only) or "off". Damage wins over healing when a spell has both.
-- Returns value, "damage" | "heal"; or nil.
function Estimate.ButtonValue(view, mode)
  if not view or mode == "off" then return nil end
  local function avg(r) return (r.min + r.max) / 2 end
  if mode == "direct" then
    if view.direct then return avg(view.direct), "damage" end
    if view.heal then return avg(view.heal), "heal" end
    return nil
  end
  if view.direct or view.dot then
    local v = 0
    if view.direct then v = v + avg(view.direct) end
    if view.dot then v = v + view.dot.total end
    return v, "damage"
  end
  if view.heal or view.hot then
    local v = 0
    if view.heal then v = v + avg(view.heal) end
    if view.hot then v = v + view.hot.total end
    return v, "heal"
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Weapon and attack power ability estimates (new in 0.5.0)
---------------------------------------------------------------------------------------------

-- Estimates damage from a weapon ability given player stats. Returns { direct = { min, max }, weapon_ability = true }
-- weaponDamage, attackPower, weaponSpeed: player stats (cached out-of-combat)
-- bonus: from parsed result (e.g., weapon_damage = 35 from "weapon damage plus 35")
function Estimate.WeaponDamage(weaponDamage, attackPower, weaponSpeed, bonus)
  if not weaponDamage or not weaponSpeed or not bonus then return nil end
  -- Formula: weapon_avg_dmg + (AP/14) * speed + bonus
  local apFactor = (attackPower or 0) / 14
  local totalDamage = weaponDamage + apFactor * weaponSpeed + bonus
  return { direct = { min = totalDamage, max = totalDamage }, weapon_ability = true }
end

-- Estimates damage from an attack power buff. Returns a small note about AP value.
-- apAmount: from parsed result (e.g., ap_buff = 20 from "increases attack power by 20")
function Estimate.APBuff(apAmount)
  if not apAmount then return nil end
  -- Just show the AP amount as flat damage (approximately ap/14 damage per hit)
  local estimatedDamage = apAmount / 14
  return { direct = { min = estimatedDamage, max = estimatedDamage }, weapon_ability = true, ap_bonus_amount = apAmount }
end

-- Estimates damage from a next attack bonus. Returns direct damage.
-- bonus: from parsed result (e.g., next_attack_bonus = 157 from "increases melee damage by 157")
function Estimate.NextAttackBonus(bonus)
  if not bonus then return nil end
  return { direct = { min = bonus, max = bonus }, weapon_ability = true }
end

-- Estimates damage from an imbue or seal. Returns direct damage range.
-- min, max: from parsed result
function Estimate.ImbueDamage(min, max)
  if not min or not max then return nil end
  return { direct = { min = min, max = max }, weapon_ability = true }
end

return Estimate
