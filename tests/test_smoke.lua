-- Smoke test: loads the addon the way the client would (files in .toc order, one shared
-- namespace) against a stubbed game API, and drives it: login, button labels on several bars,
-- page changes, the tooltip hook, secret spell power, late spell text, /sdi.
--
--   lua tests/test_smoke.lua [addon folder]
--
-- The stubs only provide what is listed below; any other global the addon reads comes back nil
-- and is reported, so a missing stub cannot make a check pass by accident.

package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")
local root = (arg and arg[1]) or "."

---------------------------------------------------------------------------------------------
-- A value the client would mark secret: any comparison, maths or concatenation errors.
---------------------------------------------------------------------------------------------
local SECRET = setmetatable({}, {
  __lt = function() error("compared a secret value") end,
  __le = function() error("compared a secret value") end,
  __add = function() error("did maths on a secret value") end,
  __sub = function() error("did maths on a secret value") end,
  __mul = function() error("did maths on a secret value") end,
  __div = function() error("did maths on a secret value") end,
  __concat = function() error("concatenated a secret value") end,
  __index = function() error("indexed a secret value") end,
})
function issecretvalue(v) return rawequal(v, SECRET) end

---------------------------------------------------------------------------------------------
-- Game API stubs
---------------------------------------------------------------------------------------------
local KNOWN_EVENTS = {
  ADDON_LOADED = true, PLAYER_LOGIN = true, ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true,
  UPDATE_BONUS_ACTIONBAR = true, UPDATE_SHAPESHIFT_FORM = true, PLAYER_EQUIPMENT_CHANGED = true,
  PLAYER_REGEN_ENABLED = true, SPELLS_CHANGED = true, CHARACTER_POINTS_CHANGED = true,
  SPELL_TEXT_UPDATE = true, UNIT_AURA = true,
  -- PLAYER_TALENT_UPDATE is left out on purpose: registering it must not break loading
}

local eventFrames = {}

local function newFontString(parent, template)
  local fs = { parent = parent, template = template, points = {}, shown = true, text = nil }
  function fs:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function fs:ClearAllPoints() self.points = {} end
  function fs:SetJustifyH(j) self.justify = j end
  function fs:SetFont(file, size, flags) self.font = { file = file, size = size, flags = flags }; return true end
  -- Arial Narrow digits are about half as wide as the font size
  function fs:GetStringWidth() return #(self.text or "") * (self.font and self.font.size or 12) * 0.55 end
  function fs:SetText(t) self.text = t end
  function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  return fs
end

local function newFrame()
  local f = { events = {}, scripts = {}, fontStrings = {} }
  function f:RegisterEvent(e)
    if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = true
  end
  function f:RegisterUnitEvent(e, unit)
    if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = unit
  end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:GetHeight() return self.height or 36 end
  function f:GetWidth() return self.height or 36 end
  function f:CreateFontString(_, _, template)
    local fs = newFontString(self, template)
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  return f
end

function CreateFrame()
  local f = newFrame()
  eventFrames[#eventFrames + 1] = f
  return f
end

local function fire(event, ...)
  for _, f in ipairs(eventFrames) do
    if f.events[event] ~= nil and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush()
  while #timers > 0 do
    local fn = table.remove(timers, 1)
    fn()
  end
end

-- German client, like the owner's
function GetLocale() return "deDE" end

local descriptions = {
  [172] = "Verdirbt das Ziel und verursacht 18 Sek. lang 822 Punkt(e) Schattenschaden.",
  [686] = "Schleudert einen Schattenblitz auf den Feind, der 455 bis 507 Punkt(e) Schattenschaden verursacht.",
  [348] = "Verbrennt den Gegner und fügt ihm 279 Feuerschaden sowie im Verlauf von 15 Sek. insgesamt 510 zusätzlichen Feuerschaden zu.",
  [5138] = "Überträgt alle 1 Sekunden 140 Punkt(e) Mana vom Ziel auf den Zaubernden. Hält 5 Sek. lang an.",
  [689] = "Überträgt pro Sekunde 71 Punkt(e) Gesundheit vom Ziel auf den Zaubernden. Hält 5 Sek. lang an.",
  [755] = "Gibt dem Begleiter des Zaubernden 10 Sek. lang in jeder Sekunde 153 Punkt(e) Gesundheit, solange der Zaubernde seine Kräfte kanalisiert.",
  [999] = "", -- not loaded yet
  -- Curse of Weakness and the pet's Screech (Wowhead Classic, German), and a made-up damage spell
  -- whose reduction is too long to sit next to its damage
  [702] = "Der vom Ziel verursachte Schaden wird 2 Min. lang um 3 reduziert. Es kann immer nur jeweils ein Fluch pro Hexenmeister auf einem beliebigen Ziel aktiv sein.",
  [24579] = "Ein Ziel erleidet 26 bis 46 Schaden, zusätzlich erfahren alle feindlichen Ziele in Nahkampfreichweite eine Reduzierung ihrer Nahkampfangriffskraft um 100. Dieser Effekt hält 4 Sek. lang an.",
  [90001] = "Verursacht 120 Schattenschaden und verringert den vom Ziel verursachten Schaden um 12,5%.",
}
local castTimes = { [172] = 2000, [686] = 3000, [348] = 2000, [5138] = 0, [689] = 0, [755] = 0, [999] = 1500,
  [702] = 0, [24579] = 0, [90001] = 0 }

C_Spell = {
  GetSpellDescription = function(id) return descriptions[id] end,
  GetSpellInfo = function(id) return castTimes[id] and { castTime = castTimes[id], spellID = id } or nil end,
}

local spellPower = { [2] = 0, [3] = 50, [4] = 0, [5] = 0, [6] = 100, [7] = 0 }
function GetSpellBonusDamage(i) return spellPower[i] end
function GetSpellBonusHealing() return 0 end

local actions = {
  [1] = { "spell", 172 }, [2] = { "spell", 686 }, [3] = { "spell", 348 }, [4] = { "item", 6948 },
  [5] = { "spell", 5138 }, [6] = { "spell", 689 }, [7] = { "spell", 755 }, [8] = { "spell", 999 },
  [9] = { "spell", 702 }, [10] = { "spell", 24579 }, [11] = { "spell", 90001 },
  [61] = { "spell", 172 }, [73] = { "spell", 686 }, [130] = { "spell", SECRET },
}
function GetActionInfo(slot) local a = actions[slot]; if a then return a[1], a[2] end end
local counts = { [2] = 5, [3] = SECRET } -- a reagent count on Shadow Bolt's slot; a secret one on Immolate's
function GetActionCount(slot) return counts[slot] or 0 end

local BAR_NAMES = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
  "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
ActionButtonUtil = { ActionBarButtonNames = BAR_NAMES }
for barIndex, prefix in ipairs(BAR_NAMES) do
  for i = 1, 12 do
    local b = newFrame()
    b.action = (barIndex == 1) and i or (48 + barIndex * 12 + i - 12) -- bottom left = 61..72
    b.name = prefix .. i
    b.height = (barIndex == 1) and 36 or 30 -- the side bars are smaller
    _G[prefix .. i] = b
  end
end
ActionButton12.action = 130 -- holds a spell whose id reads as secret
MultiBar5Button1.action = SECRET

local postCalls = {}
Enum = { TooltipDataType = { Spell = 1, Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end }
NumberFontNormalSmall = {}
NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 14, "OUTLINE" end }

local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) messages[#messages + 1] = m end }
SlashCmdList = {}
local slashTable = SlashCmdList

---------------------------------------------------------------------------------------------
-- Watch globals: which ones the addon writes, and which ones it reads that are not stubbed
---------------------------------------------------------------------------------------------
local written, missing = {}, {}
setmetatable(_G, {
  __newindex = function(t, k, v) written[k] = true; rawset(t, k, v) end,
  __index = function(_, k) missing[k] = true; return nil end,
})

---------------------------------------------------------------------------------------------
-- Load in .toc order
---------------------------------------------------------------------------------------------
local toc = T.readFile(root .. "/SpellDamageInfo.toc")
local ns = {}
local loaded = {}
for line in toc:gmatch("[^\r\n]+") do
  if not line:match("^##") and line:match("%S") then
    T.loadAddonFile(root .. "/" .. line, ns)
    loaded[#loaded + 1] = line
  end
end
T.check(#loaded == 4, "toc lists four files")
T.check(ns.lang == "de", "German client detected")

local function label(button) return ns._labels[button] end
local function shown(button)
  local fs = label(button)
  return fs and fs.shown and fs.text or nil
end

fire("ADDON_LOADED", "SomethingElse")
T.check(rawget(_G, "SpellDamageInfoDB") == nil, "another addon's ADDON_LOADED leaves the settings alone")
fire("ADDON_LOADED", "SpellDamageInfo")
T.check(type(SpellDamageInfoDB) == "table" and SpellDamageInfoDB.estimate == true and SpellDamageInfoDB.button == "total"
  and SpellDamageInfoDB.tooltip == true, "defaults written into SpellDamageInfoDB")
T.eq(SpellDamageInfoDB.size, 100, "default number size 100%")
T.eq(SpellDamageInfoDB.position, "bottom", "default position")
T.eq(SpellDamageInfoDB.reduction, true, "reductions shown by default")

local ok, err = pcall(fire, "PLAYER_LOGIN")
T.check(ok, "PLAYER_LOGIN runs: " .. tostring(err))
flush()

T.check(#ns._buttons == 96, "found all 96 buttons on eight bars, got " .. #ns._buttons)
T.eq(shown(ActionButton1), "922", "Corruption 822 + 100 spell power x 1.0")
T.eq(shown(ActionButton2), "567", "Shadow Bolt avg 481 + 100 x 3/3.5")
T.eq(shown(ActionButton3), "831", "Immolate 279 + 510 + 50 x (0.2078 + 0.6364)")
T.eq(shown(ActionButton4), nil, "item: no number")
T.eq(shown(ActionButton5), nil, "Drain Mana: no number")
T.eq(shown(ActionButton6), "355", "Drain Life 71 x 5, no school so no estimate")
T.eq(shown(ActionButton7), "1530", "Health Funnel heal 153 x 10")
T.check(label(ActionButton7) and label(ActionButton7).color[2] == 1, "heals are green")
T.eq(shown(ActionButton8), nil, "spell text not loaded yet")
T.eq(shown(ActionButton12), nil, "secret spell id: no number, no error")
T.eq(shown(MultiBarBottomLeftButton1), "922", "second bar (slot 61)")
T.eq(shown(MultiBar5Button1), nil, "secret slot: no number, no error")
for button, fs in pairs(ns._labels) do
  T.check(#fs.points >= 1 and fs.points[1][2] == button, "label anchored to its button " .. tostring(button.name))
  T.check(fs.parent == button, "label is a child of its button")
end

-- Size and place of the number
local function font(button) local fs = label(button); return fs and fs.font or {} end
local function anchor(fs) return fs and fs.points[1] and fs.points[1][1] end
T.eq(font(ActionButton1).size, 16, "number is 0.45 of a 36 px button")
T.eq(font(ActionButton1).flags, "OUTLINE", "number has an outline")
T.eq(font(ActionButton1).file, "Fonts\\ARIALN.TTF", "number uses the game's number font")
T.eq(font(MultiBarBottomLeftButton1).size, 14, "number on a 30 px button is smaller (13.5 rounds to 14)")
T.eq(anchor(label(ActionButton1)), "BOTTOM", "bottom centre when the button shows no count")
T.eq(anchor(label(ActionButton2)), "BOTTOMLEFT", "bottom left when the count sits bottom right")
T.eq(anchor(label(ActionButton3)), "BOTTOM", "a secret count is not read")
for button, fs in pairs(ns._labels) do
  if fs.shown and fs.text then
    T.check(fs:GetStringWidth() <= button:GetWidth() - 2, "number fits its button: " .. tostring(button.name))
  end
end

-- Debuffs that lower the enemy's damage: "-N" in red
T.eq(shown(ActionButton9), "-3", "Curse of Weakness shows -3")
T.check(label(ActionButton9) ~= nil and label(ActionButton9).color[1] == 1 and label(ActionButton9).color[2] < 0.5, "reduction is red")
T.eq(shown(ActionButton10), "36", "Screech: its damage (26-46) stays the main number")
local side10 = ns._sideLabels[ActionButton10]
T.eq(side10 and side10.shown and side10.text, "-100", "Screech: the reduction sits next to it")
T.check(side10 and side10.color[1] == 1 and side10.color[2] < 0.5, "side reduction is red")
T.eq(side10 and anchor(side10), "TOPLEFT", "side reduction top left, away from hotkey and count")
T.eq(side10 and side10.font.size, 12, "side reduction is smaller (36 x 0.45 x 0.75)")
T.check(side10 and side10.parent == ActionButton10 and side10.points[1][2] == ActionButton10, "side label anchored to its button")
T.eq(shown(ActionButton11), "163", "damage 120 + 100 x 1.5/3.5 wins over a long reduction")
T.check(not (ns._sideLabels[ActionButton11] and ns._sideLabels[ActionButton11].shown), "-12,5% does not fit next to it")
T.eq(ns._sideLabels[ActionButton1], nil, "no side label where there is no reduction")

-- Tooltip
T.check(#postCalls == 1 and postCalls[1].kind == Enum.TooltipDataType.Spell, "one spell tooltip post-call")
local tip = { lines = {} }
function tip:AddLine(t) self.lines[#self.lines + 1] = t end
postCalls[1].fn(tip, { id = 172, type = 1 })
T.eq(tip.lines[1], "Schaden \195\188ber Zeit: 922 in 18 Sek. (inkl. +100 durch Zaubermacht, gesch\195\164tzt)", "tooltip line (German)")
tip.lines = {}
postCalls[1].fn(tip, { id = 348, type = 1 })
T.eq(tip.lines[1], "Schaden: 289 (inkl. +10 durch Zaubermacht, gesch\195\164tzt)", "Immolate direct line")
T.eq(tip.lines[2], "Schaden \195\188ber Zeit: 542 in 15 Sek. (inkl. +32 durch Zaubermacht, gesch\195\164tzt)", "Immolate DoT line")
tip.lines = {}
postCalls[1].fn(tip, { id = 702, type = 1 })
T.eq(tip.lines[1], "Schaden des Gegners: -3", "tooltip: Curse of Weakness")
tip.lines = {}
postCalls[1].fn(tip, { id = 24579, type = 1 })
T.eq(tip.lines[1], "Schaden: 26-46", "tooltip: Screech damage")
T.eq(tip.lines[2], "Angriffskraft des Gegners: -100", "tooltip: Screech reduction")
tip.lines = {}
postCalls[1].fn(tip, { id = 90001, type = 1 })
T.eq(tip.lines[2], "Schaden des Gegners: -12,5%", "tooltip: percent reduction in German")
tip.lines = {}
postCalls[1].fn(tip, { id = SECRET, type = 1 })
T.eq(#tip.lines, 0, "secret tooltip id: nothing added, no error")

-- Spell power turns secret in combat: keep the last readable value
spellPower[6] = SECRET
ok, err = pcall(function() fire("UNIT_AURA", "player"); flush() end)
T.check(ok, "secret spell power does not error: " .. tostring(err))
T.eq(shown(ActionButton1), "922", "secret spell power: last value kept")
spellPower[6] = 200
fire("PLAYER_REGEN_ENABLED")
flush()
T.eq(shown(ActionButton1), "1022", "spell power read again after combat")
spellPower[6] = 100
fire("PLAYER_EQUIPMENT_CHANGED")
flush()
T.eq(shown(ActionButton1), "922", "gear change updates")

-- /sdi
T.check(slashTable == rawget(_G, "SlashCmdList") and type(SlashCmdList.SPELLDAMAGEINFO) == "function", "slash command added as a key")
T.eq(SLASH_SPELLDAMAGEINFO1, "/sdi", "/sdi")
SlashCmdList.SPELLDAMAGEINFO("estimate off")
flush()
T.eq(shown(ActionButton1), "822", "estimate off: description only")
tip.lines = {}
postCalls[1].fn(tip, { id = 172, type = 1 })
T.eq(tip.lines[1], "Schaden \195\188ber Zeit: 822 in 18 Sek.", "estimate off: tooltip without estimate")
SlashCmdList.SPELLDAMAGEINFO("button direct")
flush()
T.eq(shown(ActionButton1), nil, "direct only: Corruption has no direct part")
T.eq(shown(ActionButton2), "481", "direct only: Shadow Bolt average")
SlashCmdList.SPELLDAMAGEINFO("button off")
flush()
T.eq(shown(ActionButton2), nil, "button off")
SlashCmdList.SPELLDAMAGEINFO("tooltip off")
tip.lines = {}
postCalls[1].fn(tip, { id = 172, type = 1 })
T.eq(#tip.lines, 0, "tooltip off")
SlashCmdList.SPELLDAMAGEINFO("button total")
SlashCmdList.SPELLDAMAGEINFO("estimate on")
SlashCmdList.SPELLDAMAGEINFO("tooltip")
flush()
T.eq(SpellDamageInfoDB.tooltip, true, "tooltip toggled back on")
T.eq(shown(ActionButton1), "922", "back to total with estimate")
local before = #messages
SlashCmdList.SPELLDAMAGEINFO("button sideways")
T.check(#messages == before + 1 and messages[#messages]:find("Unbekannte Option"), "bad option answered in German")
before = #messages
SlashCmdList.SPELLDAMAGEINFO("")
T.check(#messages == before + 8, "help prints eight lines")

-- Reduction, size and position settings
SlashCmdList.SPELLDAMAGEINFO("reduction off")
flush()
T.eq(shown(ActionButton9), nil, "reduction off: Curse of Weakness shows nothing")
T.eq(shown(ActionButton10), "36", "reduction off: Screech damage stays")
T.check(not (ns._sideLabels[ActionButton10] and ns._sideLabels[ActionButton10].shown), "reduction off: side label hidden")
tip.lines = {}
postCalls[1].fn(tip, { id = 702, type = 1 })
T.eq(#tip.lines, 0, "reduction off: no tooltip line")
SlashCmdList.SPELLDAMAGEINFO("reduction on")
SlashCmdList.SPELLDAMAGEINFO("size 150")
flush()
T.eq(SpellDamageInfoDB.size, 150, "size saved")
T.eq(font(ActionButton9).size, 24, "size 150%: 36 x 0.45 x 1.5")
T.eq(shown(ActionButton9), "-3", "reduction on again")
before = #messages
SlashCmdList.SPELLDAMAGEINFO("size 20")
T.eq(SpellDamageInfoDB.size, 150, "size below 50 refused")
T.check(messages[#messages]:find("Unbekannte Option"), "size below 50 answered")
SlashCmdList.SPELLDAMAGEINFO("size 200")
flush()
T.check(font(ActionButton1).size < 32, "size 200%: a wide number shrinks to fit (" .. tostring(font(ActionButton1).size) .. ")")
T.check(label(ActionButton1):GetStringWidth() <= 34, "size 200%: the number still fits the button")
SlashCmdList.SPELLDAMAGEINFO("position center")
flush()
T.eq(anchor(label(ActionButton1)), "CENTER", "position center")
T.eq(#label(ActionButton1).points, 1, "one anchor at a time")
SlashCmdList.SPELLDAMAGEINFO("position top")
flush()
T.eq(anchor(label(ActionButton1)), "TOPLEFT", "position top")
T.eq(anchor(ns._sideLabels[ActionButton10]), "BOTTOMLEFT", "position top: side reduction moves to the bottom")
SlashCmdList.SPELLDAMAGEINFO("position left")
T.eq(SpellDamageInfoDB.position, "top", "unknown position refused")
SlashCmdList.SPELLDAMAGEINFO("position bottom")
SlashCmdList.SPELLDAMAGEINFO("size 100")
flush()
T.eq(font(ActionButton1).size, 16, "back to the default size")

-- Bad saved values are repaired on load
SpellDamageInfoDB.size, SpellDamageInfoDB.position, SpellDamageInfoDB.reduction = 999, "left", "yes"
fire("ADDON_LOADED", "SpellDamageInfo")
T.eq(SpellDamageInfoDB.size, 200, "saved size above the range is clamped")
T.eq(SpellDamageInfoDB.position, "bottom", "saved unknown position reset")
T.eq(SpellDamageInfoDB.reduction, true, "saved non-boolean reduction reset")
SpellDamageInfoDB.size = "big"
fire("ADDON_LOADED", "SpellDamageInfo")
T.eq(SpellDamageInfoDB.size, 100, "saved size that is not a number reset")

-- Spell text arriving later
descriptions[999] = "Verursacht 100 bis 120 Punkt(e) Frostschaden."
fire("SPELL_TEXT_UPDATE", 999)
flush()
T.eq(shown(ActionButton8), "110", "late spell text shows up after SPELL_TEXT_UPDATE")

-- Slot and page changes
actions[1] = { "spell", 348 }
fire("ACTIONBAR_SLOT_CHANGED", 1)
flush()
T.eq(shown(ActionButton1), "831", "slot changed")
ActionButton1.action = 73
fire("UPDATE_BONUS_ACTIONBAR")
flush()
T.eq(shown(ActionButton1), "567", "bonus bar page")
ActionButton1.action = 200 -- empty slot
fire("ACTIONBAR_PAGE_CHANGED")
flush()
T.eq(shown(ActionButton1), nil, "empty slot hides the number")

-- Talents or new ranks re-read the text
descriptions[686] = "Schleudert einen Schattenblitz auf den Feind, der 500 bis 600 Punkt(e) Schattenschaden verursacht."
fire("SPELLS_CHANGED")
flush()
T.eq(shown(ActionButton2), "636", "SPELLS_CHANGED re-reads descriptions (550 + 85.7)")

-- Nothing of Blizzard's was replaced
local allowed = { SpellDamageInfoDB = true, SLASH_SPELLDAMAGEINFO1 = true }
for k in pairs(written) do
  T.check(allowed[k], "addon wrote global " .. tostring(k))
end

local names = {}
for k in pairs(missing) do names[#names + 1] = k end
table.sort(names)
print("Globals read that this test does not stub (feature checks): " .. (#names > 0 and table.concat(names, ", ") or "none"))
T.finish("test_smoke")
