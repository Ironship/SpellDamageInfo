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
  function fs:SetJustifyH() end
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
}
local castTimes = { [172] = 2000, [686] = 3000, [348] = 2000, [5138] = 0, [689] = 0, [755] = 0, [999] = 1500 }

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
  [61] = { "spell", 172 }, [73] = { "spell", 686 }, [130] = { "spell", SECRET },
}
function GetActionInfo(slot) local a = actions[slot]; if a then return a[1], a[2] end end

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
    _G[prefix .. i] = b
  end
end
ActionButton12.action = 130 -- holds a spell whose id reads as secret
MultiBar5Button1.action = SECRET

local postCalls = {}
Enum = { TooltipDataType = { Spell = 1, Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end }
NumberFontNormalSmall = {}

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
T.check(#messages == before + 5, "help prints five lines")

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
