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
    "/sdi - open the settings window (also in Options > AddOns)",
    "/sdi help - this list",
    "/sdi estimate [on|off] - add an estimate for your spell power",
    "/sdi button total|direct|off - number on the action buttons",
    "/sdi tooltip [on|off] - lines in the spell tooltip",
    "/sdi reduction [on|off] - show by how much a debuff lowers the enemy's damage (red)",
    "/sdi size 50-200 - size of the button numbers in percent (100 = default)",
    "/sdi position bottom|center|top - where the number sits on the button",
    "/sdi lang auto|en|de - addon interface language",
    "/sdi weapon [on|off] - potential damage of weapon abilities and attack power buffs (blue)",
    "/sdi misses [clear] - spells on your bars that give no number",
    "/sdi status - show the settings",
  },
  STATUS = "estimate: %s, button: %s, tooltip: %s, reduction: %s, weapon: %s, size: %d%%, position: %s, language: %s",
  BAD_ARG = "Unknown option. Type /sdi help for the commands.",
  WEAPON_LINE = "Potential damage: about %s (%s, estimate)",
  WEAPON_HIT = "weapon hit %s",
  WEAPON_HIT_RANGED = "ranged hit %s",
  WEAPON_PCT = "%s%% of %s",
  WEAPON_PLUS = "%s + %s",
  AP_LINE = "Attack power +%s%s: about +%s damage per hit (%s %s sec), estimate",
  AP_PLUS_AGILITY = " plus Agility",
  AP_WEAPON = "weapon",
  AP_RANGED = "ranged weapon",
  MISSES_NONE = "No spells without a number recorded.",
  MISSES_HEAD = "%d spells on your bars give no number:",
  MISSES_CLEARED = "List of spells without a number cleared.",
  LANG_AUTO = "Auto (game)",
  LANG_EN = "English",
  LANG_DE = "Deutsch",
  -- options window
  OPT_LANGUAGE = "Language",
  OPT_LANGUAGE_TIP = "Addon interface language: Auto follows the game language, or choose English or German.",
  OPT_PREVIEW = "Live preview",
  OPT_PREVIEW_HINT = "Sample spells with 50 spell power and a 2.6 sec weapon hitting for 120, drawn by the same code as the numbers on your action bars.",
  OPT_PREVIEW_OFF = "No numbers on the buttons.",
  OPT_SAMPLE_1 = "Immolate",
  OPT_SAMPLE_2 = "Screech",
  OPT_SAMPLE_3 = "Curse of Weakness",
  OPT_SAMPLE_4 = "Heroic Strike",
  OPT_SAMPLE_5 = "Rockbiter Weapon",
  OPT_BUTTON = "Number on buttons",
  OPT_BUTTON_TIP = "What the number on your action buttons shows: all the damage or healing (direct and over time), the direct part only, or nothing.",
  OPT_BUTTON_TOTAL = "Total",
  OPT_BUTTON_DIRECT = "Direct only",
  OPT_BUTTON_OFF = "Off",
  OPT_SIZE = "Number size",
  OPT_SIZE_TIP = "Size of the button numbers in percent of the default. A number too wide for its button is made smaller until it fits.",
  OPT_POSITION = "Number position",
  OPT_POSITION_TIP = "Where the number sits on the button. A reduction next to a damage number takes the opposite corner.",
  OPT_POS_BOTTOM = "Bottom",
  OPT_POS_CENTER = "Center",
  OPT_POS_TOP = "Top",
  OPT_ESTIMATE = "Spell power estimate",
  OPT_ESTIMATE_TIP = "Adds your spell power by the Classic coefficient rules; the tooltip says how much of the number is estimated. Pet spells never get it.",
  OPT_TOOLTIP = "Lines in the spell tooltip",
  OPT_TOOLTIP_TIP = "Adds the damage and healing to the spell's tooltip.",
  OPT_REDUCTION = "Enemy damage reductions in red",
  OPT_REDUCTION_TIP = "Shows in red, on the button and in the tooltip, by how much a debuff such as Curse of Weakness lowers the enemy's damage or attack power.",
  OPT_WEAPON = "Weapon abilities and attack power",
  OPT_WEAPON_TIP = "Shows in blue what an ability that hits with your weapon, or a spell that raises attack power, is worth per hit: estimated from your weapon's average hit and speed, read out of combat.",
  OPT_RESET = "Reset to defaults",
  OPT_RESET_DONE = "Settings reset to defaults.",
  OPT_LANG_CHANGED = "Addon interface language changed. Type /reload to update the settings window's labels.",
  OPT_OPEN = "Open SpellDamageInfo settings",
  OPT_PANEL_TEXT = "The settings have their own window with a live preview. You can also type /sdi.",
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
    "/sdi - Einstellungsfenster \195\182ffnen (auch unter Optionen > AddOns)",
    "/sdi help - diese Liste",
    "/sdi estimate [on|off] - Sch\195\164tzung f\195\188r Eure Zaubermacht dazurechnen",
    "/sdi button total|direct|off - Zahl auf den Aktionstasten",
    "/sdi tooltip [on|off] - Zeilen im Zauber-Tooltip",
    "/sdi reduction [on|off] - zeigen, um wie viel ein Schw\195\164chungszauber den Schaden des Gegners senkt (rot)",
    "/sdi size 50-200 - Gr\195\182\195\159e der Zahlen auf den Tasten in Prozent (100 = Standard)",
    "/sdi position bottom|center|top - wo die Zahl auf der Taste steht",
    "/sdi lang auto|en|de - Sprache der Addon-Oberfl\195\164che",
    "/sdi weapon [on|off] - m\195\182glicher Schaden von Waffenf\195\164higkeiten und Angriffskraft-Buffs (blau)",
    "/sdi misses [clear] - Zauber auf Euren Leisten, die keine Zahl ergeben",
    "/sdi status - Einstellungen anzeigen",
  },
  STATUS = "Sch\195\164tzung: %s, Tasten: %s, Tooltip: %s, Schw\195\164chung: %s, Waffe: %s, Gr\195\182\195\159e: %d%%, Position: %s, Sprache: %s",
  BAD_ARG = "Unbekannte Option. /sdi help zeigt die Befehle.",
  WEAPON_LINE = "M\195\182glicher Schaden: etwa %s (%s, gesch\195\164tzt)",
  WEAPON_HIT = "Waffentreffer %s",
  WEAPON_HIT_RANGED = "Distanztreffer %s",
  WEAPON_PCT = "%s %% von %s",
  WEAPON_PLUS = "%s + %s",
  AP_LINE = "Angriffskraft +%s%s: etwa +%s Schaden pro Treffer (%s %s Sek.), gesch\195\164tzt",
  AP_PLUS_AGILITY = " plus Beweglichkeit",
  AP_WEAPON = "Waffe",
  AP_RANGED = "Distanzwaffe",
  MISSES_NONE = "Keine Zauber ohne Zahl erfasst.",
  MISSES_HEAD = "%d Zauber auf Euren Leisten ergeben keine Zahl:",
  MISSES_CLEARED = "Liste der Zauber ohne Zahl geleert.",
  LANG_AUTO = "Auto (Spiel)",
  LANG_EN = "English",
  LANG_DE = "Deutsch",
  -- options window
  OPT_LANGUAGE = "Sprache",
  OPT_LANGUAGE_TIP = "Sprache der Addon-Oberfl\195\164che: Auto folgt der Spielsprache, oder w\195\164hlt English oder Deutsch.",
  OPT_PREVIEW = "Vorschau",
  OPT_PREVIEW_HINT = "Beispielzauber mit 50 Zaubermacht und einer 2,6-Sek.-Waffe mit 120 Schaden pro Treffer, gezeichnet vom selben Code wie die Zahlen auf Euren Aktionsleisten.",
  OPT_PREVIEW_OFF = "Keine Zahlen auf den Tasten.",
  OPT_SAMPLE_1 = "Feuerbrand",
  OPT_SAMPLE_2 = "Kreischen",
  OPT_SAMPLE_3 = "Fluch der Schw\195\164che",
  OPT_SAMPLE_4 = "Heldenhafter Sto\195\159",
  OPT_SAMPLE_5 = "Waffe des Felsbei\195\159ers",
  OPT_BUTTON = "Zahl auf den Tasten",
  OPT_BUTTON_TIP = "Was die Zahl auf den Aktionstasten zeigt: den ganzen Schaden oder die ganze Heilung (direkt und \195\188ber Zeit), nur den direkten Teil oder nichts.",
  OPT_BUTTON_TOTAL = "Gesamt",
  OPT_BUTTON_DIRECT = "Nur direkt",
  OPT_BUTTON_OFF = "Aus",
  OPT_SIZE = "Gr\195\182\195\159e der Zahl",
  OPT_SIZE_TIP = "Gr\195\182\195\159e der Zahlen in Prozent der Standardgr\195\182\195\159e. Eine Zahl, die zu breit f\195\188r ihre Taste ist, wird verkleinert, bis sie passt.",
  OPT_POSITION = "Position der Zahl",
  OPT_POSITION_TIP = "Wo die Zahl auf der Taste steht. Eine Schw\195\164chung neben einer Schadenszahl nimmt die gegen\195\188berliegende Ecke.",
  OPT_POS_BOTTOM = "Unten",
  OPT_POS_CENTER = "Mitte",
  OPT_POS_TOP = "Oben",
  OPT_ESTIMATE = "Zaubermacht sch\195\164tzen",
  OPT_ESTIMATE_TIP = "Rechnet Eure Zaubermacht nach den Classic-Koeffizienten dazu; der Tooltip sagt, wie viel davon gesch\195\164tzt ist. Begleiterzauber bekommen keine Sch\195\164tzung.",
  OPT_TOOLTIP = "Zeilen im Zauber-Tooltip",
  OPT_TOOLTIP_TIP = "F\195\188gt dem Zauber-Tooltip Schaden und Heilung hinzu.",
  OPT_REDUCTION = "Schw\195\164chung des Gegners in Rot",
  OPT_REDUCTION_TIP = "Zeigt in Rot, auf der Taste und im Tooltip, um wie viel ein Schw\195\164chungszauber wie Fluch der Schw\195\164che den Schaden oder die Angriffskraft des Gegners senkt.",
  OPT_WEAPON = "Waffenf\195\164higkeiten und Angriffskraft",
  OPT_WEAPON_TIP = "Zeigt in Blau, was eine F\195\164higkeit mit Eurer Waffe oder ein Zauber, der die Angriffskraft erh\195\182ht, pro Treffer ausmacht: gesch\195\164tzt aus dem durchschnittlichen Treffer und dem Tempo Eurer Waffe, au\195\159erhalb des Kampfes gelesen.",
  OPT_RESET = "Standard wiederherstellen",
  OPT_RESET_DONE = "Einstellungen auf Standard zur\195\188ckgesetzt.",
  OPT_LANG_CHANGED = "Sprache der Addon-Oberfl\195\164che ge\195\164ndert. Gebt /reload ein, um die Beschriftungen des Einstellungsfensters zu aktualisieren.",
  OPT_OPEN = "SpellDamageInfo-Einstellungen \195\182ffnen",
  OPT_PANEL_TEXT = "Die Einstellungen haben ein eigenes Fenster mit Vorschau. Ihr k\195\182nnt auch /sdi eingeben.",
}

-- Interface language: what the addon's own UI shows (labels, chat lines, number formatting).
-- Stored in SavedVariables; "auto" means follow GetLocale(). Not decided until ADDON_LOADED.
local interfaceLang = nil
ns.InterfaceLang = function() return interfaceLang end

-- Description language: what the parser reads. Decided at login from textLocale CVar if it is
-- "deDE", else from GetLocale(), and cannot be changed (the player would only see spell descriptions
-- in one language anyway). Core.lua passes it to Parser.Parse and Parser.ParseReduction.
local descriptionLang = nil
ns.DescriptionLang = function() return descriptionLang end

-- Locale table that code captured at file load uses (e.g. "local L = ns.L" in Core.lua).
-- When the interface language changes, this table's contents are replaced to apply the switch
-- live wherever code reads L.KEY when it runs, "local L = ns.L" included, since that is this
-- same table. Only text already set into a widget waits for the window to be rebuilt (/reload).
local L = {}
ns.L = L

-- Returns the locale string ("deDE", "enUS", etc.) for the description language.
local function getDescriptionLocale()
  local locale = nil
  if type(C_CVar) == "table" and type(C_CVar.GetCVar) == "function" then
    local ok, result = pcall(C_CVar.GetCVar, "textLocale")
    if ok and result == "deDE" then locale = "deDE" end
  end
  if not locale and type(GetCVar) == "function" then
    local ok, result = pcall(GetCVar, "textLocale")
    if ok and result == "deDE" then locale = "deDE" end
  end
  if not locale and type(GetLocale) == "function" then
    locale = GetLocale()
  end
  return locale or "enUS"
end

-- Decide the description language at addon load, and set up ns.L with the interface strings.
function ns.DecideLangsAtLoad()
  local descLocale = getDescriptionLocale()
  descriptionLang = (descLocale == "deDE") and "de" or "en"
end

-- Set the interface language and refresh ns.L. "auto" -> follow GetLocale().
function ns.SetInterfaceAndRefreshL(lang)
  interfaceLang = lang or "auto"
  local locale = (interfaceLang == "auto") and ((type(GetLocale) == "function") and GetLocale() or "enUS") or "en"
  if interfaceLang == "de" or interfaceLang == "auto" and locale == "deDE" then
    for k, v in pairs(Locales.de) do L[k] = v end
  else
    for k, v in pairs(Locales.en) do L[k] = v end
  end
end

-- Init: called at ADDON_LOADED to set up the interface language from SavedVariables.
function ns.InitInterfaceL(savedLang)
  ns.SetInterfaceAndRefreshL(savedLang or "auto")
end

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
-- Potential damage from the weapon and attack power: its own colour, because it is an estimate
-- from the weapon's numbers rather than a figure the spell itself states.
local WEAPON_COLOR = { 0.45, 0.85, 1 }
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
-- The tooltip line for a weapon view from ns.WeaponView: { text, r, g, b }.
--   "Potential damage: about 412 (225% of weapon hit 103 + 180, estimate)"
--   "Attack power +554: about +103 damage per hit (weapon 2.6 sec), estimate"
function Format.WeaponLine(w, L)
  local c = WEAPON_COLOR
  if w.gain then
    local text = string.format(L.AP_LINE, Format.Thousands(w.amount, L), w.plusAgility and L.AP_PLUS_AGILITY or "",
      Format.Thousands(w.gain, L), w.ranged and L.AP_RANGED or L.AP_WEAPON, Format.Seconds(w.speed, L))
    return { text, c[1], c[2], c[3] }
  end
  local body = string.format(w.ranged and L.WEAPON_HIT_RANGED or L.WEAPON_HIT, Format.Thousands(w.hit, L))
  if w.pct ~= 100 then body = string.format(L.WEAPON_PCT, Format.Thousands(w.pct, L), body) end
  if w.bonusMax then
    body = string.format(L.WEAPON_PLUS, body, Format.Thousands(w.bonus, L) .. "-" .. Format.Thousands(w.bonusMax, L))
  elseif w.bonus > 0 then
    body = string.format(L.WEAPON_PLUS, body, Format.Thousands(w.bonus, L))
  end
  return { string.format(L.WEAPON_LINE, Format.Thousands(w.value, L), body), c[1], c[2], c[3] }
end

function Format.TooltipLines(view, L)
  local lines = {}
  if not view then return lines end
  if view.weapon then
    lines[1] = Format.WeaponLine(view.weapon, L)
    return lines
  end
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
Format.WEAPON_COLOR = WEAPON_COLOR
