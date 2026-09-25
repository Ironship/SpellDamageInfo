-- SpellDamageInfo: English and German strings, and number formatting.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.

local _, ns = ...
ns = ns or {}

local Locales = {}
ns.Locales = Locales

Locales.en = {
  lang = "en",
  thousands = ",",
  decimal = ".",
  DAMAGE = "Damage",
  DOT = "Damage over time",
  HEAL = "Healing",
  HOT = "Healing over time",
  OVER = "%s in %s sec",
  ESTIMATE = "incl. +%s from spell power, estimate",
  REDUCE_DAMAGE = "Enemy damage: %s",
  REDUCE_AP = "Enemy attack power: %s",
  PET = "pet",
  ON = "on",
  OFF = "off",
  HELP = {
    "SpellDamageInfo: damage and healing from each spell's description.",
    "/sdi estimate [on|off] - add an estimate for your spell power",
    "/sdi button total|direct|off - number on the action buttons",
    "/sdi tooltip [on|off] - lines in the spell tooltip",
    "/sdi reduction [on|off] - show by how much a debuff lowers the enemy's damage (red)",
    "/sdi size 50-200 - size of the button numbers in percent (100 = default)",
    "/sdi position bottom|center|top - where the number sits on the button",
    "/sdi status - show the settings",
  },
  STATUS = "estimate: %s, button: %s, tooltip: %s, reduction: %s, size: %d%%, position: %s",
  BAD_ARG = "Unknown option. Type /sdi for help.",
}

Locales.de = {
  lang = "de",
  thousands = ".",
  decimal = ",",
  DAMAGE = "Schaden",
  DOT = "Schaden \195\188ber Zeit",
  HEAL = "Heilung",
  HOT = "Heilung \195\188ber Zeit",
  OVER = "%s in %s Sek.",
  ESTIMATE = "inkl. +%s durch Zaubermacht, gesch\195\164tzt",
  REDUCE_DAMAGE = "Schaden des Gegners: %s",
  REDUCE_AP = "Angriffskraft des Gegners: %s",
  PET = "Begleiter",
  ON = "an",
  OFF = "aus",
  HELP = {
    "SpellDamageInfo: Schaden und Heilung aus der Zauberbeschreibung.",
    "/sdi estimate [on|off] - Sch\195\164tzung f\195\188r Eure Zaubermacht dazurechnen",
    "/sdi button total|direct|off - Zahl auf den Aktionstasten",
    "/sdi tooltip [on|off] - Zeilen im Zauber-Tooltip",
    "/sdi reduction [on|off] - zeigen, um wie viel ein Schw\195\164chungszauber den Schaden des Gegners senkt (rot)",
    "/sdi size 50-200 - Gr\195\182\195\159e der Zahlen auf den Tasten in Prozent (100 = Standard)",
    "/sdi position bottom|center|top - wo die Zahl auf der Taste steht",
    "/sdi status - Einstellungen anzeigen",
  },
  STATUS = "Sch\195\164tzung: %s, Tasten: %s, Tooltip: %s, Schw\195\164chung: %s, Gr\195\182\195\159e: %d%%, Position: %s",
  BAD_ARG = "Unbekannte Option. /sdi zeigt die Hilfe.",
}

local locale = (type(GetLocale) == "function") and GetLocale() or "enUS"
ns.L = (locale == "deDE") and Locales.de or Locales.en
ns.lang = (locale == "deDE") and "de" or ((type(locale) == "string" and locale:sub(1, 2) == "en") and "en" or nil)

local Format = {}
ns.Format = Format

local floor = math.floor

local function round(v) return floor(v + 0.5) end

-- 1305 -> "1,305" (en) / "1.305" (de)
function Format.Thousands(v, L)
  local s = tostring(round(v))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  local out = s
  while true do
    local changed
    out, changed = out:gsub("^(%d+)(%d%d%d)", "%1" .. L.thousands .. "%2")
    if changed == 0 then break end
  end
  return (neg and "-" or "") .. out
end

-- Durations: 15 -> "15", 7.1 -> "7.1" / "7,1"
function Format.Seconds(v, L)
  if v == floor(v) then return tostring(floor(v)) end
  local s = string.format("%.1f", v)
  return (s:gsub("%.", L.decimal))
end

-- Short text for an action button: up to 9999 as it is, then "12k".
function Format.Short(v)
  v = round(v)
  if v < 10000 then return tostring(v) end
  return tostring(floor(v / 1000 + 0.5)) .. "k"
end

local function rangeText(r, L)
  local lo, hi = round(r.min), round(r.max)
  if lo == hi then return Format.Thousands(lo, L) end
  return Format.Thousands(lo, L) .. "-" .. Format.Thousands(hi, L)
end

local function suffix(added, L)
  if added and added >= 0.5 then
    return " (" .. string.format(L.ESTIMATE, Format.Thousands(added, L)) .. ")"
  end
  return ""
end

local DAMAGE_COLOR = { 1, 0.82, 0.3 }
local HEAL_COLOR = { 0.4, 1, 0.4 }
local REDUCTION_COLOR = { 1, 0.25, 0.25 }

-- A reduction from Parser.ParseReduction as button text: "-3", "-146", "-10%", "-7.5%".
-- L (optional) gives the decimal mark.
function Format.ReductionText(r, L)
  if r.percent then
    local s
    if r.amount == floor(r.amount) then s = tostring(floor(r.amount)) else s = string.format("%.1f", r.amount) end
    if L then s = (s:gsub("%.", L.decimal)) end
    return "-" .. s .. "%"
  end
  return "-" .. Format.Short(r.amount)
end

-- The tooltip line for a reduction: { text, r, g, b }.
function Format.ReductionLine(r, L)
  local template = (r.stat == "attackpower") and L.REDUCE_AP or L.REDUCE_DAMAGE
  local amount = r.percent and Format.ReductionText(r, L) or ("-" .. Format.Thousands(r.amount, L))
  return { string.format(template, amount), REDUCTION_COLOR[1], REDUCTION_COLOR[2], REDUCTION_COLOR[3] }
end

-- Tooltip lines for a view from Estimate.Apply: a list of { text, r, g, b }.
function Format.TooltipLines(view, L)
  local lines = {}
  if not view then return lines end
  local function add(label, body, added, color)
    lines[#lines + 1] = { label .. ": " .. body .. suffix(added, L), color[1], color[2], color[3] }
  end
  local function periodic(p)
    return string.format(L.OVER, Format.Thousands(p.total, L), Format.Seconds(p.duration, L))
  end
  if view.direct then add(L.DAMAGE, rangeText(view.direct, L), view.direct.added, DAMAGE_COLOR) end
  if view.dot then add(L.DOT, periodic(view.dot), view.dot.added, DAMAGE_COLOR) end
  if view.heal then add(L.HEAL, rangeText(view.heal, L), view.heal.added, HEAL_COLOR) end
  if view.hot then add(L.HOT, periodic(view.hot), view.hot.added, HEAL_COLOR) end
  return lines
end

Format.DAMAGE_COLOR = DAMAGE_COLOR
Format.HEAL_COLOR = HEAL_COLOR
Format.REDUCTION_COLOR = REDUCTION_COLOR
