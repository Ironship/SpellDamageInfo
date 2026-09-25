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
  SPELL_TEXT_UPDATE = true, UNIT_AURA = true, PET_BAR_UPDATE = true, UNIT_PET = true,
  UNIT_ATTACK_POWER = true, UNIT_RANGED_ATTACK_POWER = true, UNIT_DAMAGE = true, UNIT_ATTACK_SPEED = true,
  UNIT_RANGEDDAMAGE = true, UNIT_MAXHEALTH = true, UNIT_SPELLCAST_SUCCEEDED = true,
  -- PLAYER_TALENT_UPDATE and PET_BAR_UPDATE_USABLE are left out on purpose: registering an
  -- event the client does not know must not break loading
}

local eventFrames = {}

-- Widgets. Only the methods listed here exist: calling any other method (a capitalised key)
-- errors, so the addon cannot use a widget API this stub does not model.
local function strict(obj, kind)
  return setmetatable(obj, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then error(kind .. " has no method " .. k .. " in this stub", 2) end
    return nil
  end })
end

-- What every region (texture, font string, frame) has.
local function addRegion(r, parent)
  r.parent, r.points, r.shown, r.alpha = parent, {}, true, 1
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints(target) self.points = { { "ALL", target or self.parent } } end
  function r:SetSize(w, h) self.width, self.height = w, h end
  function r:SetWidth(w) self.width = w end
  function r:SetHeight(h) self.height = h end
  function r:GetHeight() return self.height or 36 end
  function r:GetWidth() return self.width or self.height or 36 end
  function r:SetAlpha(a) self.alpha = a end
  function r:GetAlpha() return self.alpha end
  function r:GetParent() return self.parent end
  function r:IsShown() return self.shown end
  function r:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
  end
  function r:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function r:SetShown(v) if v then self:Show() else self:Hide() end end
  return r
end

local function newTexture(parent, layer)
  local t = addRegion({ layer = layer }, parent)
  function t:SetTexture(file) self.file = file end
  function t:SetColorTexture(r, g, b, a) self.rgba = { r, g, b, a } end
  function t:SetTexCoord(...) self.coords = { ... } end
  function t:SetVertexColor(...) self.vertex = { ... } end
  return strict(t, "Texture")
end

local function newFontString(parent, template)
  local fs = addRegion({ template = template, text = nil }, parent)
  function fs:SetJustifyH(j) self.justify = j end
  function fs:SetFont(file, size, flags) self.font = { file = file, size = size, flags = flags }; return true end
  -- Arial Narrow digits are about half as wide as the font size
  function fs:GetStringWidth() return #(self.text or "") * (self.font and self.font.size or 12) * 0.55 end
  function fs:SetText(t) self.text = t end
  function fs:GetText() return self.text end
  function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
  return strict(fs, "FontString")
end

local function newFrame(kind, parent, template)
  local f = addRegion({ kind = kind or "Frame", template = template, events = {}, scripts = {}, fontStrings = {},
    textures = {}, strata = "MEDIUM", level = 1, scale = 1, mouse = false }, parent)
  function f:RegisterEvent(e)
    if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = true
  end
  function f:RegisterUnitEvent(e, unit)
    if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = unit
  end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:GetScript(name) return self.scripts[name] end
  function f:HookScript(name, fn) self.scripts[name] = fn end
  function f:GetID() return self.id or 0 end
  function f:CreateFontString(_, _, template)
    local fs = newFontString(self, template)
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  function f:CreateTexture(_, layer)
    local t = newTexture(self, layer)
    self.textures[#self.textures + 1] = t
    return t
  end
  function f:EnableMouse(v) self.mouse = v end
  function f:EnableMouseWheel(v) self.wheel = v end
  function f:IsMouseOver() return false end
  function f:SetMovable(v) self.movable = v end
  function f:RegisterForDrag(...) self.drag = { ... } end
  function f:StartMoving() self.moving = true end
  function f:StopMovingOrSizing() self.moving = false end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:SetToplevel(v) self.toplevel = v end
  function f:SetClampedToScreen(v) self.clamped = v end
  function f:SetScale(s) self.scale = s end
  function f:GetScale() return self.scale end
  if template == "BackdropTemplate" then
    function f:SetBackdrop(b) self.backdrop = b end
    function f:SetBackdropColor(...) self.backdropColor = { ... } end
    function f:SetBackdropBorderColor(...) self.backdropBorder = { ... } end
  end
  if kind == "Button" or kind == "CheckButton" then
    f.enabled = true
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text end
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f:IsEnabled() return self.enabled end
    -- a click as the client does it: a check button flips first, then OnClick runs
    function f:Click()
      if not self.enabled then return end
      if self.kind == "CheckButton" then self.checked = not self.checked end
      if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
    end
  end
  if kind == "CheckButton" then
    function f:SetNormalTexture(file) self.normal = file end
    function f:SetPushedTexture(file) self.pushed = file end
    function f:SetHighlightTexture(file) self.highlight = file end
    function f:SetCheckedTexture(file) self.checkedTexture = file end
    function f:SetChecked(v) self.checked = v and true or false end
    function f:GetChecked() return self.checked end
  end
  if kind == "Slider" then
    f.thumb = newTexture(f, "OVERLAY")
    function f:SetOrientation(o) self.orientation = o end
    function f:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function f:GetMinMaxValues() return self.min, self.max end
    function f:SetValueStep(s) self.step = s end
    function f:SetObeyStepOnDrag(v) self.obeyStep = v end
    function f:SetThumbTexture(file) self.thumb.file = file end
    function f:GetThumbTexture() return self.thumb end
    function f:GetValue() return self.value end
    -- clamps to the range and runs OnValueChanged when the value changes, as the client does
    function f:SetValue(v)
      if self.min and v < self.min then v = self.min end
      if self.max and v > self.max then v = self.max end
      if v == self.value then return end
      self.value = v
      if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
    end
  end
  return strict(f, kind or "Frame")
end

local namedFrames = {}
function CreateFrame(kind, name, parent, template)
  local f = newFrame(kind, parent, template)
  if template == "UIPanelCloseButton" then f.scripts.OnClick = function(self) self.parent:Hide() end end
  if name then
    namedFrames[name] = f
    rawset(_G, name, f) -- the client makes a named frame a global; the addon itself does not write it
  end
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

-- CVar stubs for textLocale testing
local cvarValues = { textLocale = "deDE" }
function GetCVar(key) return cvarValues[key] end
C_CVar = { GetCVar = function(key) return cvarValues[key] end }

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
  -- the Imp's Firebolt, rank 1, as the owner's German Forever client shows it
  [3110] = "F\195\188gt dem Ziel 3 bis 6 Feuerschaden zu.",
  [7799] = "F\195\188gt dem Ziel 7 bis 10 Feuerschaden zu.", -- rank 2, after the pet levels
}
-- Four weapon abilities as the German client shows them, read from the weapon fixture (Wowhead
-- Classic German): Heldenhafter Stoß r9 (next attack +157), Waffe des Felsbeißers r7 (+653
-- attack power), Klaue r5 (115 on top of the normal hit), Gezielter Schuss r6 (ranged +600).
local json = require("json")
local weaponRows = json.decode(T.readFile("tests/fixtures/attack_power_weapon_damage.json"))
local function weaponText(id)
  for _, r in ipairs(weaponRows) do if r.id == id then return r.de_description end end
  error("weapon fixture has no spell " .. id)
end
for _, id in ipairs({ 25286, 16316, 9850, 20904 }) do descriptions[id] = weaponText(id) end

-- The player's weapons: a 2.6 sec melee weapon hitting for 100-140, a 3.0 sec bow for 150-170.
local weapon = { lo = 100, hi = 140, speed = 2.6, rSpeed = 3.0, rLo = 150, rHi = 170 }
function UnitDamage(unit) if unit == "player" then return weapon.lo, weapon.hi end end
function UnitAttackSpeed(unit) if unit == "player" then return weapon.speed end end
function UnitRangedDamage(unit) if unit == "player" then return weapon.rSpeed, weapon.rLo, weapon.rHi end end
function GetBuildInfo() return "1.60.1", "70009", "Sep 23 2026", 16001 end
local spellNames = { [5138] = "Mana entziehen", [20293] = "Siegel der Rechtschaffenheit", [20920] = "Siegel des Befehls" }

-- The rest of the German texts this test uses, from the whole-spellbook fixture (Wowhead Classic
-- German, every rank of every class): two seals and Judgement, a shield, Lay on Hands, two totems,
-- Execute, Eviscerate, Bloodthirst, Hammer of the Righteous and the strength and agility totems.
local allRows = json.decode(T.readFile("tests/fixtures/forever_spellbook_all.json"))
local function germanText(id)
  for _, r in ipairs(allRows) do if r.id == id and r.de_description then return r.de_description end end
  error("the whole-spellbook fixture has no German text for spell " .. id)
end
for _, id in ipairs({ 20293, 20920, 20271, 10901, 10310, 10438, 10463, 20662, 31016, 23894, 407632, 25361, 25359 }) do
  descriptions[id] = germanText(id)
end

-- Attack power 1000 + 200 - 50, a warrior with 3000 health in no form.
function UnitAttackPower(unit) if unit == "player" then return 1000, 200, -50 end end
function UnitClass(unit) if unit == "player" then return "Krieger", "WARRIOR", 1 end end
function UnitHealthMax(unit) if unit == "player" then return 3000 end end
function GetShapeshiftFormID() return nil end
-- The player's buffs, by spell id; SECRET stands for a client that hides them.
local playerBuffs = {}
C_UnitAuras = { GetBuffDataByIndex = function(unit, i)
  if playerBuffs == SECRET then return SECRET end
  local id = playerBuffs[i]
  if id then return { spellId = id } end
end }
local clock = 1000
function GetTime() return clock end
-- The spellbook, for /sdi dump: three entries, the last one's text not loaded yet.
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function(i) if i == 1 then return { itemIndexOffset = 0, numSpellBookItems = 3 } end end,
  GetSpellBookItemInfo = function(i) local ids = { 172, 20293, 999 }; if ids[i] then return { spellID = ids[i] } end end,
}

local castTimes = { [172] = 2000, [686] = 3000, [348] = 2000, [5138] = 0, [689] = 0, [755] = 0, [999] = 1500,
  [702] = 0, [24579] = 0, [90001] = 0, [3110] = 2000, [7799] = 2000 }

C_Spell = {
  GetSpellDescription = function(id) return descriptions[id] end,
  GetSpellInfo = function(id) return castTimes[id] and { castTime = castTimes[id], spellID = id } or nil end,
  GetSpellName = function(id) return spellNames[id] end,
}

local spellPower = { [2] = 0, [3] = 50, [4] = 0, [5] = 0, [6] = 100, [7] = 0 }
function GetSpellBonusDamage(i) return spellPower[i] end
function GetSpellBonusHealing() return 0 end

local actions = {
  [1] = { "spell", 172 }, [2] = { "spell", 686 }, [3] = { "spell", 348 }, [4] = { "item", 6948 },
  [5] = { "spell", 5138 }, [6] = { "spell", 689 }, [7] = { "spell", 755 }, [8] = { "spell", 999 },
  [9] = { "spell", 702 }, [10] = { "spell", 24579 }, [11] = { "spell", 90001 },
  [61] = { "spell", 172 }, [73] = { "spell", 686 }, [130] = { "spell", SECRET },
  [62] = { "spell", 25286 }, [63] = { "spell", 16316 }, [64] = { "spell", 9850 }, [65] = { "spell", 20904 },
  [66] = { "spell", 20293 }, [67] = { "spell", 20920 }, [68] = { "spell", 20271 }, [69] = { "spell", 10901 },
  [70] = { "spell", 10310 }, [71] = { "spell", 10438 }, [72] = { "spell", 10463 }, [74] = { "spell", 20662 },
  [75] = { "spell", 31016 }, [76] = { "spell", 23894 }, [77] = { "spell", 407632 }, [78] = { "spell", 25361 },
  [79] = { "spell", 25359 },
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

-- The pet bar as Forever has it: PetActionButton1..10, also listed in PetActionBar.actionButtons.
-- GetPetActionInfo(slot): name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID
NUM_PET_ACTION_SLOTS = 10
PetActionBar = newFrame()
PetActionBar.actionButtons = {}
for i = 1, 10 do
  local b = newFrame()
  b.id, b.name, b.height = i, "PetActionButton" .. i, 30
  _G["PetActionButton" .. i] = b
  PetActionBar.actionButtons[i] = b
end
local petActions = {
  [1] = { "PET_ACTION_ATTACK", 132152, true, false, false, false, nil }, -- a command
  [2] = nil,                                                           -- empty slot
  [3] = { "Feuerblitz", 135809, false, false, true, true, 3110 },
  [4] = { "Feuerblitz", 135809, false, false, true, true, SECRET },    -- secret spell id
  [5] = { "Blutpakt", 136168, SECRET, false, false, false, 6307 },     -- secret token flag
  [6] = { "Feuerschild", 135806, false, false, false, false, 2947 },   -- no description text
  [7] = { "PET_MODE_DEFENSIVE", 132110, true, true, false, false, 3110 }, -- a token carrying an id
}
function GetPetActionInfo(slot)
  local a = petActions[slot]
  if a then return a[1], a[2], a[3], a[4], a[5], a[6], a[7] end
end

-- GameTooltip for the pet action hooks. dataDriven: SetPetAction runs the PetAction post-call
-- itself, as on clients that build tooltips from data; otherwise it only fills the tooltip.
local postCalls = {}
local function runPostCalls(kind, tooltip, data)
  for _, p in ipairs(postCalls) do if p.kind == kind then p.fn(tooltip, data) end end
end
GameTooltip = { lines = {}, scripts = {}, shows = 0, dataDriven = true }
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:Show() self.shows = self.shows + 1 end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:HookScript(name, fn) self.scripts[name] = fn end
function GameTooltip:SetPetAction(slot)
  self.lines = { "blizzard text" }
  if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
  if self.dataDriven then runPostCalls(Enum.TooltipDataType.PetAction, self, { id = slot, type = 11 }) end
  return true
end
function hooksecurefunc(t, key, fn)
  local orig = t[key]
  t[key] = function(...)
    local r = orig(...)
    fn(...)
    return r
  end
end

Enum = { TooltipDataType = { Spell = 1, Item = 0, PetAction = 11 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end }
NumberFontNormalSmall = {}
NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 14, "OUTLINE" end }

local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) messages[#messages + 1] = m end }
SlashCmdList = {}
local slashTable = SlashCmdList

-- What the options window uses: tooltips on its rows, UIParent, Escape closing, combat state,
-- and Blizzard's options (Settings on current clients, InterfaceOptions_AddCategory on old ones).
function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor; self.lines = {} end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:Hide() self.hidden = true end
UIParent = newFrame("Frame")
UISpecialFrames = {}
local inCombat = false
function InCombatLockdown() return inCombat end
local hiddenPanels = {}
function HideUIPanel(frame) hiddenPanels[#hiddenPanels + 1] = frame; frame:Hide() end
SettingsPanel = newFrame("Frame")
SettingsPanel:Hide()
local registered = { canvas = {}, addon = {}, interface = {} }
local SettingsStub = {
  RegisterCanvasLayoutCategory = function(panel, name)
    local category = { panel = panel, name = name }
    registered.canvas[#registered.canvas + 1] = category
    return category
  end,
  RegisterAddOnCategory = function(category) registered.addon[#registered.addon + 1] = category end,
}
Settings = SettingsStub
local function interfaceAddCategory(panel) registered.interface[#registered.interface + 1] = panel end

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
T.check(#loaded == 5, "toc lists five files")
T.eq(loaded[5], "Options.lua", "Options.lua loads after Core.lua")
T.check(ns.DescriptionLang() == nil and ns.InterfaceLang() == nil, "languages not decided yet at file load")

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
T.eq(SpellDamageInfoDB.interfaceLang, "auto", "default interface language is auto")
T.eq(ns.DescriptionLang(), "de", "German client: description language is German")
T.check(ns.L.DAMAGE == "Schaden", "interface language auto (German): strings are German")

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

-- Pet bar: the description's numbers, no spell power estimate (fire power is 50, which would
-- make Firebolt 4.5 + 50 x 2/3.5 = 33)
T.eq(#(ns._petButtons or {}), 10, "found the ten pet buttons once, though PetActionBar lists them too")
T.eq(shown(PetActionButton3), "5", "Imp's Firebolt: 3-6 fire, average 4.5, no estimate")
T.check(label(PetActionButton3) ~= nil and label(PetActionButton3).color[1] == 1 and label(PetActionButton3).color[2] > 0.5,
  "pet damage in the damage colour")
T.eq(font(PetActionButton3).size, 14, "pet button number sized like the other 30 px buttons")
T.eq(anchor(label(PetActionButton3)), "BOTTOM", "pet number bottom centre")
T.check(label(PetActionButton3) ~= nil and label(PetActionButton3).parent == PetActionButton3
  and label(PetActionButton3).points[1][2] == PetActionButton3, "pet label is a child of its button and anchored to it")
T.eq(shown(PetActionButton1), nil, "Attack command: no number")
T.eq(shown(PetActionButton2), nil, "empty pet slot: no number")
T.eq(shown(PetActionButton4), nil, "secret pet spell id: no number, no error")
T.eq(shown(PetActionButton5), nil, "secret token flag: no number, no error")
T.eq(shown(PetActionButton6), nil, "pet spell without text: no number")
T.eq(shown(PetActionButton7), nil, "a stance token is skipped even when it carries a spell id")
T.eq(ns._labels[PetActionButton1], nil, "no label made on a command slot")

-- Tooltip
T.check(#postCalls == 2 and postCalls[1].kind == Enum.TooltipDataType.Spell
  and postCalls[2].kind == Enum.TooltipDataType.PetAction, "spell and pet action tooltip post-calls")
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

-- Pet action tooltip, built from data: the post-call adds the line, the hook does not repeat it
local PET_LINE = "Schaden: 3-6 (Begleiter)"
GameTooltip.owner = PetActionButton3
ok, err = pcall(GameTooltip.SetPetAction, GameTooltip, 3)
T.check(ok, "SetPetAction runs: " .. tostring(err))
T.eq(GameTooltip.lines[2], PET_LINE, "pet tooltip: Firebolt 3-6, no estimate, says pet")
T.eq(#GameTooltip.lines, 2, "pet tooltip: the line is added once")
-- the tooltip refreshing (post-call alone) and then shown again
runPostCalls(Enum.TooltipDataType.PetAction, GameTooltip, { id = 3, type = 11 })
T.eq(#GameTooltip.lines, 3, "a refresh adds the line to the refreshed text")
GameTooltip:SetPetAction(3)
T.eq(#GameTooltip.lines, 2, "shown again after a refresh: still once")
-- a refresh, then the tooltip of a pet bar the addon does not know: the refresh's mark must not
-- stop the hook
runPostCalls(Enum.TooltipDataType.PetAction, GameTooltip, { id = 3, type = 11 })
GameTooltip.owner = nil
GameTooltip:SetPetAction(3)
T.eq(GameTooltip.lines[2], PET_LINE, "unknown owner after a refresh: the hook adds the line")
T.eq(#GameTooltip.lines, 2, "unknown owner after a refresh: once")
GameTooltip.owner = PetActionButton3
-- a client that fills the tooltip without the data post-call: the SetPetAction hook adds it
GameTooltip.dataDriven = false
local shows = GameTooltip.shows
GameTooltip:SetPetAction(3)
T.eq(GameTooltip.lines[2], PET_LINE, "SetPetAction hook: pet line")
T.eq(#GameTooltip.lines, 2, "SetPetAction hook: once")
T.eq(GameTooltip.shows, shows + 1, "SetPetAction hook resizes the tooltip")
GameTooltip.owner = nil -- a pet bar of another addon: the slot from the call is enough
GameTooltip:SetPetAction(3)
T.eq(GameTooltip.lines[2], PET_LINE, "SetPetAction hook works without a known owner")
for _, slot in ipairs({ 1, 2, 4, 5, 7, SECRET }) do
  ok, err = pcall(GameTooltip.SetPetAction, GameTooltip, slot)
  T.check(ok and #GameTooltip.lines == 1, "pet slot " .. (rawequal(slot, SECRET) and "secret" or tostring(slot))
    .. ": nothing added, no error " .. tostring(err))
end
GameTooltip.dataDriven = true
-- a client that reports a pet spell as a Spell tooltip: still the pet's line, without estimate
tip = { lines = {}, GetOwner = function() return PetActionButton3 end }
function tip:AddLine(t) self.lines[#self.lines + 1] = t end
postCalls[1].fn(tip, { id = 3110, type = 1 })
T.eq(tip.lines[1], PET_LINE, "Spell tooltip on a pet button: pet line")
T.eq(#tip.lines, 1, "Spell tooltip on a pet button: one line")
tip = { lines = {} }
function tip:AddLine(t) self.lines[#self.lines + 1] = t end

-- Weapon abilities and attack power: blue, from the weapon's average hit and speed
local WEAPON = ns.Format.WEAPON_COLOR
local function weaponColoured(button)
  local fs = label(button)
  return fs and fs.color[1] == WEAPON[1] and fs.color[2] == WEAPON[2] and fs.color[3] == WEAPON[3]
end
T.eq(shown(MultiBarBottomLeftButton2), "277", "Heldenhafter Stoß: average hit 120 + 157")
T.check(weaponColoured(MultiBarBottomLeftButton2), "weapon numbers are blue")
T.eq(shown(MultiBarBottomLeftButton3), "+121", "Waffe des Felsbeißers: 653 / 14 x 2.6 per hit")
T.check(weaponColoured(MultiBarBottomLeftButton3), "attack power gain is blue")
T.eq(shown(MultiBarBottomLeftButton4), "235", "Klaue: the normal hit 120 + 115, not the 115 alone")
T.eq(shown(MultiBarBottomLeftButton5), "760", "Gezielter Schuss: ranged hit 160 + 600")
tip.lines = {}
postCalls[1].fn(tip, { id = 25286, type = 1 })
T.eq(tip.lines[1], "Möglicher Schaden: etwa 277 (Waffentreffer 120 + 157, geschätzt)", "weapon tooltip line")
tip.lines = {}
postCalls[1].fn(tip, { id = 16316, type = 1 })
T.eq(tip.lines[1], "Angriffskraft +653: etwa +121 Schaden pro Treffer (Waffe 2,6 Sek.), geschätzt",
  "attack power tooltip line")
tip.lines = {}
postCalls[1].fn(tip, { id = 20904, type = 1 })
T.eq(tip.lines[1], "Möglicher Schaden: etwa 760 (Distanztreffer 160 + 600, geschätzt)", "ranged tooltip line")

-- In combat the weapon's numbers turn secret: the last ones read stay in use
weapon.lo, weapon.hi, weapon.speed = SECRET, SECRET, SECRET
weapon.rSpeed, weapon.rLo, weapon.rHi = SECRET, SECRET, SECRET
ok, err = pcall(function() fire("UNIT_ATTACK_POWER", "player"); flush() end)
T.check(ok, "secret weapon numbers do not error: " .. tostring(err))
T.eq(shown(MultiBarBottomLeftButton2), "277", "secret weapon numbers: last hit kept")
T.eq(shown(MultiBarBottomLeftButton3), "+121", "secret weapon numbers: last speed kept")
T.eq(shown(MultiBarBottomLeftButton5), "760", "secret weapon numbers: last ranged hit kept")
weapon.lo, weapon.hi, weapon.speed = 130, 170, 2.6
weapon.rSpeed, weapon.rLo, weapon.rHi = 3.0, 150, 170
fire("UNIT_DAMAGE", "player")
flush()
T.eq(shown(MultiBarBottomLeftButton2), "307", "a better weapon: 150 + 157")
weapon.lo, weapon.hi = 100, 140
fire("PLAYER_EQUIPMENT_CHANGED")
flush()
T.eq(shown(MultiBarBottomLeftButton2), "277", "and back")

-- The setting: off hides them all, and Klaue does not fall back to its 115 on its own
SlashCmdList.SPELLDAMAGEINFO("weapon off")
flush()
T.eq(shown(MultiBarBottomLeftButton2), nil, "weapon off: Heldenhafter Stoß shows nothing")
T.eq(shown(MultiBarBottomLeftButton4), nil, "weapon off: Klaue shows nothing")
T.check(messages[#messages]:find("Waffe: aus", 1, true), "status says the weapon numbers are off")
SlashCmdList.SPELLDAMAGEINFO("weapon")
flush()
T.eq(SpellDamageInfoDB.weapon, true, "/sdi weapon toggles it back on")
T.eq(shown(MultiBarBottomLeftButton2), "277", "weapon on again")

-- The arithmetic, on its own
local V = ns.WeaponView
local stats = { melee = 100, meleeSpeed = 2, ranged = 50, rangedSpeed = 3 }
T.eq(V({ kind = "weapon", pct = 225, bonus = 180 }, stats).value, 405, "225% of 100 + 180")
T.eq(V({ kind = "weapon", pct = 50, bonus = 80, bonusMax = 100 }, stats).value, 140, "50% of 100 + 80..100 averaged")
T.eq(V({ kind = "next", bonus = 600, ranged = true }, stats).value, 650, "ranged hit 50 + 600")
T.eq(V({ kind = "ap", amount = 140 }, stats).gain, 20, "140 attack power on a 2 sec weapon: +20 per hit")
T.eq(V({ kind = "ap", amount = 140, ranged = true }, stats).gain, 30, "140 ranged attack power on a 3 sec bow: +30")
T.eq(V({ kind = "next", bonus = 10 }, {}), nil, "no weapon numbers yet: nothing")

-- Spells on the bars that give no number are listed once, for /sdi misses
local function listed(id)
  local count = 0
  for _, m in ipairs(SpellDamageInfoDB.misses) do if m.id == id then count = count + 1 end end
  return count
end
T.eq(listed(5138), 1, "Drain Mana, on the bar with no number, is listed once")
T.eq(listed(172), 0, "a spell with a number is not listed")
T.eq(listed(25286), 0, "a weapon ability is not listed")
local miss
for _, m in ipairs(SpellDamageInfoDB.misses) do if m.id == 5138 then miss = m end end
T.check(miss and miss.name == "Mana entziehen" and miss.text == descriptions[5138] and miss.lang == "de"
  and miss.build == "70009", "the entry holds the name, the text, the language and the build")
local missBefore = #messages
SlashCmdList.SPELLDAMAGEINFO("misses")
T.check(messages[missBefore + 1] and messages[missBefore + 1]:find("ergeben keine Zahl", 1, true), "/sdi misses: header")
T.check(#messages > missBefore + 1 and messages[#messages]:find("5138 Mana entziehen: ", 1, true), "/sdi misses lists them")
SlashCmdList.SPELLDAMAGEINFO("misses clear")
T.eq(#SpellDamageInfoDB.misses, 0, "/sdi misses clear empties the list")
fire("ACTIONBAR_SLOT_CHANGED")
flush()
T.eq(listed(5138), 1, "listed again after a clear, once")
-- capped
for id = 800001, 800300 do
  ns._parsedCache[id] = { parsed = false, reduction = false, weapon = false, text = "-" }
  ns._noteMiss(id)
end
T.eq(#SpellDamageInfoDB.misses, 200, "the list stops at 200")
SlashCmdList.SPELLDAMAGEINFO("misses clear")
for id = 800001, 800300 do ns._parsedCache[id] = nil end

-- Seals and Judgement. The seal's own button: what every hit gains; its Judgement's number is not
-- put on it. Judgement's button: the active seal's Judgement, nothing without a seal.
local function tipFor(id) tip.lines = {}; postCalls[1].fn(tip, { id = id, type = 1 }); return tip.lines end
local function hasLine(lines, text) for _, l in ipairs(lines) do if l == text then return true end end return false end
T.eq(shown(MultiBarBottomLeftButton6), "+49", "Siegel der Rechtschaffenheit: 22-75 on every hit, 48.5 on average")
T.check(weaponColoured(MultiBarBottomLeftButton6), "a seal's gain per hit is blue")
T.check(hasLine(tipFor(20293), "Richturteil: 170-187 Schaden"), "the seal's tooltip says what its Judgement does")
T.eq(shown(MultiBarBottomLeftButton7), nil, "Siegel des Befehls: a chance per hit is no number, and its Judgement is not put here")
T.eq(shown(MultiBarBottomLeftButton8), nil, "Richturteil without a seal: nothing")
T.check(hasLine(tipFor(20271), "Kein Siegel aktiv: der Schaden des Richturteils kommt vom Siegel."), "and the tooltip says why")
playerBuffs = { 999999, 20293 }
fire("UNIT_AURA", "player")
flush()
T.eq(shown(MultiBarBottomLeftButton8), "179", "Richturteil under Siegel der Rechtschaffenheit: 170-187")
local jt = tipFor(20271)
T.check(hasLine(jt, "Schaden: 170-187") and hasLine(jt, "Aus Siegel der Rechtschaffenheit"), "Judgement's tooltip names the seal")
playerBuffs = { 20920 }
fire("UNIT_AURA", "player")
flush()
T.eq(shown(MultiBarBottomLeftButton8), "178", "Richturteil under Siegel des Befehls: 169-186, not the stunned 339-373")
-- a client that hides the buffs: the last seal cast stands in for its 30 seconds
playerBuffs = SECRET
fire("UNIT_AURA", "player")
flush()
T.eq(shown(MultiBarBottomLeftButton8), nil, "secret buffs and no seal cast: nothing")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-GUID", 20293)
flush()
T.eq(shown(MultiBarBottomLeftButton8), "179", "secret buffs: the seal just cast")
clock = clock + 31
fire("UNIT_AURA", "player")
flush()
T.eq(shown(MultiBarBottomLeftButton8), nil, "and not after it would have run out")
playerBuffs = {}
fire("UNIT_AURA", "player")
flush()

-- A shield, Lay on Hands, two totems, Execute, a finisher
T.eq(shown(MultiBarBottomLeftButton9), "942", "Machtwort: Schild absorbs 942")
T.check(label(MultiBarBottomLeftButton9).color[1] == ns.Format.ABSORB_COLOR[1]
  and label(MultiBarBottomLeftButton9).color[3] == ns.Format.ABSORB_COLOR[3], "a shield has its own colour")
T.eq(tipFor(10901)[1], "Absorbiert: 942", "shield tooltip")
T.eq(shown(MultiBarBottomLeftButton10), "3000", "Handauflegung heals for the paladin's maximum health, not the 550 mana")
T.eq(tipFor(10310)[1], "Heilung: 3.000 (Eure maximale Gesundheit)", "Lay on Hands tooltip")
T.eq(shown(MultiBarBottomLeftButton11), "47", "Totem der Verbrennung: 40-54 per attack")
T.eq(tipFor(10438)[1], "Schaden: 40-54 pro Angriff", "totem attack tooltip")
T.eq(shown(MultiBarBottomLeftButton12), "14", "Totem des heilenden Flusses: 14 per pulse")
T.eq(tipFor(10463)[1], "Heilung: 14 alle 2 Sek.", "totem pulse tooltip")
T.eq(shown(MultiBarBottomRightButton2), "600", "Hinrichten: 600")
T.check(hasLine(tipFor(20662), "Plus 15 für jeden zusätzlichen Wutpunkt"), "and what each extra rage point adds")
T.eq(shown(MultiBarBottomRightButton3), "958", "Ausweiden at 5 combo points: 904-1012")
T.check(hasLine(tipFor(31016), "Bei 5 Combopunkten, ohne Angriffskraft; 1-4: 224-332 / 394-502 / 564-672 / 734-842"),
  "the finisher's tooltip gives the other points")

-- From attack power and the weapon's damage per second, and a strength totem
T.eq(shown(MultiBarBottomRightButton4), "518", "Blutdurst: 45% of 1150 attack power")
T.eq(tipFor(23894)[1], "Möglicher Schaden: etwa 518 (45 % der Angriffskraft 1.150, geschätzt)", "Bloodthirst tooltip")
T.eq(shown(MultiBarBottomRightButton5), "185", "Hammer der Rechtschaffenen: 4 x (120 / 2.6)")
T.eq(shown(MultiBarBottomRightButton6), "+29", "Totem der Erdstärke for a warrior: 77 x 2 attack power on a 2.6 sec weapon")
T.eq(tipFor(25361)[1], "Stärke +77 (154 Angriffskraft): etwa +29 Schaden pro Treffer (Waffe 2,6 Sek.), geschätzt",
  "strength totem tooltip")
T.eq(shown(MultiBarBottomRightButton7), nil, "Totem der luftgleichen Anmut gives a warrior no attack power")

-- Retail's descriptions already hold the player's stats: no estimate, no weapon arithmetic
local buildInfo = GetBuildInfo
GetBuildInfo = function() return "12.1.0", "69814", "Sep 1 2026", 120100 end
-- a different client: the texts are read again (a real client never changes in a session)
fire("SPELLS_CHANGED")
flush()
T.eq(shown(ActionButton1), "822", "Retail: Corruption without the spell power estimate")
T.eq(shown(MultiBarBottomLeftButton2), nil, "Retail: no weapon arithmetic on Heroic Strike")
GetBuildInfo = buildInfo
fire("SPELLS_CHANGED")
flush()
T.eq(shown(ActionButton1), "922", "back on Forever: the estimate again")

-- /sdi dump
local dumpBefore = #messages
SlashCmdList.SPELLDAMAGEINFO("dump")
local dump = SpellDamageInfoDB.dump
T.check(dump and #dump.spells == 2 and dump.missing == 1, "/sdi dump writes the two loaded spells and counts the third")
T.check(dump and dump.spells[2].id == 20293 and dump.spells[2].text == descriptions[20293]
  and dump.spells[2].reads:find("weapon", 1, true) and dump.spells[2].reads:find("seal", 1, true),
  "each with its text and what the addon reads from it")
T.check(dump and dump.lang == "de" and dump.build == "1.60.1.70009" and dump.class == "WARRIOR", "and the client it came from")
T.check(#messages == dumpBefore + 1 and messages[#messages]:find("2 Zauber", 1, true), "/sdi dump says how many")

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

-- /sdi: language
local langBefore = #messages
SlashCmdList.SPELLDAMAGEINFO("lang en")
flush()
T.eq(SpellDamageInfoDB.interfaceLang, "en", "/sdi lang en: setting changed")
T.check(ns.L.DAMAGE == "Damage", "/sdi lang en: interface strings are English")
T.check(messages[#messages]:find("language:"), "/sdi lang: status line shows language")
T.check(messages[#messages]:find("English"), "/sdi lang en: status shows English")
SlashCmdList.SPELLDAMAGEINFO("lang de")
flush()
T.eq(SpellDamageInfoDB.interfaceLang, "de", "/sdi lang de: setting changed")
T.check(ns.L.DAMAGE == "Schaden", "/sdi lang de: interface strings are German")
T.check(messages[#messages]:find("Deutsch"), "/sdi lang de: status shows Deutsch")
SlashCmdList.SPELLDAMAGEINFO("lang auto")
flush()
T.eq(SpellDamageInfoDB.interfaceLang, "auto", "/sdi lang auto: setting changed")
T.check(ns.L.DAMAGE == "Schaden", "/sdi lang auto (German client): interface strings are German")
T.check(messages[#messages]:find("Auto"), "/sdi lang auto: status shows Auto")
local langBefore2 = #messages
SlashCmdList.SPELLDAMAGEINFO("lang invalid")
T.check(#messages == langBefore2 + 1 and messages[#messages]:find("Unbekannte Option"), "bad lang option answered in German")

-- /sdi: other commands still work with language changed
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
SlashCmdList.SPELLDAMAGEINFO("help")
T.check(#messages == before + 14, "/sdi help prints fourteen lines")
T.check(messages[before + 2] and messages[before + 2]:find("^|cff66ccffSpellDamageInfo|r: /sdi %- "), "help names bare /sdi first")

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

---------------------------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------------------------
local DE = ns.Locales.de

-- Options > AddOns: registered at login through Settings, and through InterfaceOptions_AddCategory
-- where Settings does not exist
T.eq(#registered.canvas, 1, "options page registered as a canvas category at login")
T.check(registered.canvas[1] and registered.canvas[1].name == "SpellDamageInfo"
  and registered.canvas[1].panel == ns._optionsPanel, "canvas category holds our page")
T.check(registered.addon[1] ~= nil and registered.addon[1] == registered.canvas[1], "category added to AddOns")
T.eq(#registered.interface, 0, "no fallback registration while Settings exists")
rawset(_G, "Settings", nil)
rawset(_G, "InterfaceOptions_AddCategory", interfaceAddCategory)
T.eq(ns.RegisterOptions(), "interface", "without Settings: InterfaceOptions_AddCategory")
T.eq(#registered.interface, 1, "fallback registered once")
T.check(registered.interface[1] == ns._optionsPanel and ns._optionsPanel.name == "SpellDamageInfo", "fallback page named")
T.eq(#registered.canvas, 1, "fallback path does not touch Settings")
rawset(_G, "InterfaceOptions_AddCategory", nil)
T.eq(ns.RegisterOptions(), nil, "neither API: nothing registered, no error")
rawset(_G, "Settings", SettingsStub)
T.eq(ns.RegisterOptions(), "settings", "Settings path again")
T.eq(ns._optionsPanel.fontStrings[2].text, DE.OPT_PANEL_TEXT, "page text in German")
T.eq(ns._optionsOpenButton.text, DE.OPT_OPEN, "page button in German")

-- /sdi opens and closes the window
T.eq(ns._optionsWindow(), nil, "window built only when first opened")
SlashCmdList.SPELLDAMAGEINFO("")
local win = ns._optionsWindow()
T.check(win ~= nil and win.shown, "/sdi opens the window")
T.check(win.parent == UIParent and win.strata == "DIALOG" and win.movable and win.scripts.OnDragStart ~= nil,
  "window: child of UIParent, dialog strata, movable")
T.check(#win.points >= 1, "window is anchored")
T.eq(rawget(_G, "SpellDamageInfoOptions"), win, "window named for Escape")
T.eq(UISpecialFrames[#UISpecialFrames], "SpellDamageInfoOptions", "Escape closes it")
SlashCmdList.SPELLDAMAGEINFO("")
T.check(not win.shown, "/sdi again closes it")
SlashCmdList.SPELLDAMAGEINFO("options")
T.check(win.shown, "/sdi options opens it")

-- Every control, localized, with a tooltip
local rows = win.rows
local KEYS = { button = DE.OPT_BUTTON, size = DE.OPT_SIZE, position = DE.OPT_POSITION, estimate = DE.OPT_ESTIMATE,
  tooltip = DE.OPT_TOOLTIP, reduction = DE.OPT_REDUCTION, interfaceLang = DE.OPT_LANGUAGE }
for key, text in pairs(KEYS) do
  local row = rows[key]
  T.check(row ~= nil and row.widget ~= nil, "control for " .. key)
  if row then
    T.eq(row.label.text, text, "label for " .. key .. " in German")
    T.check(#row.points >= 1, "row anchored: " .. key)
    row.scripts.OnEnter(row)
    T.check(GameTooltip.lines[1] == text and type(GameTooltip.lines[2]) == "string" and #GameTooltip.lines[2] > 20,
      "tooltip for " .. key)
    row.scripts.OnLeave(row)
  end
end
T.eq(rows.estimate.widget.kind, "CheckButton", "estimate is a check box")
T.eq(rows.size.widget.kind, "Slider", "size is a slider")
T.eq(rows.button.widget.kind, "Button", "button mode is a choice")
T.eq(rows.interfaceLang.widget.kind, "Button", "language is a choice")
T.eq(win.reset.text, DE.OPT_RESET, "reset button in German")
T.eq(rows.button.text.text, DE.OPT_BUTTON_TOTAL, "choice shows the current mode")
T.eq(rows.position.text.text, DE.OPT_POS_BOTTOM, "choice shows the current position")
T.eq(rows.size.widget.value, 100, "slider at the current size")
T.eq(rows.interfaceLang.text.text, DE.LANG_AUTO, "language choice shows auto")
T.check(rows.estimate.widget.checked and rows.tooltip.widget.checked and rows.reduction.widget.checked, "boxes checked")

-- The preview: five mock buttons of our own, drawn like the real ones
local mocks = win.mocks
T.eq(#mocks, 5, "five mock buttons")
local isReal = {}
for _, b in ipairs(ns._buttons) do isReal[b] = true end
for _, b in ipairs(ns._petButtons) do isReal[b] = true end
for i, m in ipairs(mocks) do
  T.check(not isReal[m] and rawget(m, "action") == nil, "mock " .. i .. " is not an action button")
  T.check(m.main.parent == m and m.textures[1] and m.textures[1].file and m.textures[1].file:find("^Interface\\Icons\\"),
    "mock " .. i .. " has a spell icon and its own label")
end
local function mockText(i) local fs = mocks[i].main; return fs.shown and fs.text or nil end
local function mockSide(i) local fs = mocks[i].side; return fs.shown and fs.text or nil end
-- ActionButton3 holds Immolate with 50 fire spell power and no count: what the first mock shows
local function sameAsBar(what)
  local real, mock = label(ActionButton3), mocks[1].main
  T.eq(mockText(1), shown(ActionButton3), what .. ": preview text as on the bar")
  if real and real.shown and mock.shown then
    T.eq(mock.font.size, real.font.size, what .. ": preview font size as on the bar")
    T.eq(anchor(mock), anchor(real), what .. ": preview anchor as on the bar")
    T.eq(mock.justify, real.justify, what .. ": preview justify as on the bar")
  end
end
T.eq(mockText(1), "831", "preview: Immolate with the estimate")
sameAsBar("defaults")
T.eq(mockText(2), "36", "preview: Screech damage")
T.eq(mockSide(2), "-100", "preview: Screech reduction next to it")
T.check(mocks[2].side.color[1] == 1 and mocks[2].side.color[2] < 0.5, "preview: reduction label is red")
T.eq(mockSide(2), ns._sideLabels[ActionButton10].text, "preview reduction as on the bar")
T.eq(mocks[2].side.font.size, ns._sideLabels[ActionButton10].font.size, "preview reduction size as on the bar")
T.eq(mockText(3), "-3", "preview: Curse of Weakness")
T.check(mocks[3].main.color[1] == 1 and mocks[3].main.color[2] < 0.5, "preview: a lone reduction is red")
T.eq(mockText(4), "277", "preview: Heroic Strike on the sample weapon, 120 + 157")
T.eq(mockText(5), "+103", "preview: Rockbiter's 554 attack power on a 2.6 sec weapon")
T.check(mocks[4].main.color[3] == 1 and mocks[4].main.color[1] < 0.5, "preview: weapon numbers are blue")

-- Each control writes its setting, refreshes the real buttons and the preview
-- flushed first, so the queue is empty before the click (dropping a queued refresh instead
-- would leave Core waiting for it forever)
local function clicked(widget) flush(); widget:Click() end
local function queued() return #timers > 0 end

clicked(rows.estimate.widget)
T.eq(SpellDamageInfoDB.estimate, false, "estimate box: setting off")
T.check(queued(), "estimate box: refresh queued")
T.eq(mockText(1), "789", "estimate box: preview without the estimate")
flush()
T.eq(shown(ActionButton3), "789", "estimate box: bar without the estimate")
sameAsBar("estimate off")
clicked(rows.estimate.widget)
flush()
T.eq(SpellDamageInfoDB.estimate, true, "estimate box: on again")
T.eq(shown(ActionButton3), "831", "estimate box: bar with the estimate again")

clicked(rows.tooltip.widget)
T.eq(SpellDamageInfoDB.tooltip, false, "tooltip box: setting off")
T.check(queued(), "tooltip box: refresh queued")
flush()
tip.lines = {}
postCalls[1].fn(tip, { id = 172, type = 1 })
T.eq(#tip.lines, 0, "tooltip box: no tooltip lines")
clicked(rows.tooltip.widget)
flush()
tip.lines = {}
postCalls[1].fn(tip, { id = 172, type = 1 })
T.eq(#tip.lines, 1, "tooltip box: lines back")

clicked(rows.reduction.widget)
T.eq(SpellDamageInfoDB.reduction, false, "reduction box: setting off")
T.check(queued(), "reduction box: refresh queued")
T.eq(mockText(3), nil, "reduction box: preview Curse of Weakness empty")
T.eq(mockSide(2), nil, "reduction box: preview side label gone")
T.eq(mockText(2), "36", "reduction box: preview damage stays")
flush()
T.eq(shown(ActionButton9), nil, "reduction box: bar Curse of Weakness empty")
clicked(rows.reduction.widget)
flush()
T.eq(SpellDamageInfoDB.reduction, true, "reduction box: on again")
T.eq(mockText(3), "-3", "reduction box: preview back")

-- the button mode menu
local function pick(row, index)
  flush()
  row.widget:Click()
  local menu = ns._optionsMenu()
  T.check(menu and menu.shown and menu.owner == row.widget, "menu opens under its control")
  local b = menu and menu.buttons[index]
  if b then b:Click() end
  T.check(menu and not menu.shown, "menu closes after a pick")
end
pick(rows.button, 2)
T.eq(SpellDamageInfoDB.button, "direct", "button menu: direct")
T.check(queued(), "button menu: refresh queued")
T.eq(rows.button.text.text, DE.OPT_BUTTON_DIRECT, "button menu: shows the pick")
T.eq(mockText(1), "289", "button menu: preview Immolate direct part")
flush()
sameAsBar("direct")
pick(rows.button, 3)
T.eq(SpellDamageInfoDB.button, "off", "button menu: off")
T.eq(mockText(1), nil, "button off: preview empty")
T.eq(mockText(3), nil, "button off: no reduction either, as on the bar")
T.check(win.offNote.shown, "button off: the preview says so")
T.check(rows.size.alpha < 1 and rows.position.alpha < 1 and rows.size.widget.mouse == false, "button off: size and position greyed")
T.check(rows.estimate.alpha == 1, "button off: the other settings stay")
flush()
T.eq(shown(ActionButton3), nil, "button off: bar empty")
pick(rows.button, 1)
T.eq(SpellDamageInfoDB.button, "total", "button menu: total")
T.check(not win.offNote.shown and rows.size.alpha == 1, "button total: note gone, size enabled")
flush()

-- the size slider
local bar = rows.size.widget
flush()
bar:SetValue(150)
T.eq(SpellDamageInfoDB.size, 150, "slider: size 150")
T.check(queued(), "slider: refresh queued")
T.eq(rows.size.fontStrings[2].text, "150%", "slider: value shown")
flush()
sameAsBar("size 150")
T.check(mocks[1].main.font.size < 24, "size 150: the preview number shrank to fit, as on the bar")
T.eq(mocks[3].main.font.size, 24, "size 150: short text at 36 x 0.45 x 1.5")
bar.scripts.OnMouseWheel(bar, 1)
T.eq(SpellDamageInfoDB.size, 155, "slider: mouse wheel up one step")
bar:SetValue(137)
T.eq(SpellDamageInfoDB.size, 135, "slider: snaps to its step")
bar:SetValue(20)
T.eq(SpellDamageInfoDB.size, 50, "slider: kept in range")
flush()
sameAsBar("size 50")
SlashCmdList.SPELLDAMAGEINFO("size 123")
T.eq(bar.value, 123, "/sdi size moves the open window's slider")
T.eq(rows.size.fontStrings[2].text, "123%", "/sdi size: the exact value shown")

-- the position menu
pick(rows.position, 2)
T.eq(SpellDamageInfoDB.position, "center", "position menu: center")
T.eq(anchor(mocks[1].main), "CENTER", "position center: preview")
flush()
sameAsBar("center")
pick(rows.position, 3)
T.eq(SpellDamageInfoDB.position, "top", "position menu: top")
T.eq(anchor(mocks[1].main), "TOPLEFT", "position top: preview")
T.eq(anchor(mocks[2].side), "BOTTOMLEFT", "position top: preview reduction moves to the bottom")
flush()
sameAsBar("top")
T.eq(anchor(ns._sideLabels[ActionButton10]), anchor(mocks[2].side), "position top: reduction as on the bar")
SlashCmdList.SPELLDAMAGEINFO("position bottom")
T.eq(rows.position.text.text, DE.OPT_POS_BOTTOM, "/sdi position updates the open window")
T.eq(anchor(mocks[1].main), "BOTTOM", "/sdi position updates the preview")

-- Language menu
pick(rows.interfaceLang, 2)
T.eq(SpellDamageInfoDB.interfaceLang, "en", "language menu: English")
T.check(ns.L.DAMAGE == "Damage", "language menu: interface strings are English")
T.eq(rows.interfaceLang.text.text, ns.Locales.en.LANG_EN, "language menu: shows English")
pick(rows.interfaceLang, 3)
T.eq(SpellDamageInfoDB.interfaceLang, "de", "language menu: Deutsch")
T.check(ns.L.DAMAGE == "Schaden", "language menu: interface strings are German")
T.eq(rows.interfaceLang.text.text, ns.Locales.de.LANG_DE, "language menu: shows Deutsch")
pick(rows.interfaceLang, 1)
T.eq(SpellDamageInfoDB.interfaceLang, "auto", "language menu: auto")
T.check(ns.L.DAMAGE == "Schaden", "language menu: auto on German client: interface strings are German")
T.eq(rows.interfaceLang.text.text, DE.LANG_AUTO, "language menu: shows auto")

-- Reset to defaults
SpellDamageInfoDB.estimate, SpellDamageInfoDB.button, SpellDamageInfoDB.tooltip = false, "direct", false
SpellDamageInfoDB.reduction, SpellDamageInfoDB.size, SpellDamageInfoDB.position = false, 180, "top"
SpellDamageInfoDB.interfaceLang = "en"
before = #messages
clicked(win.reset)
for k, v in pairs(ns.DEFAULTS) do T.eq(SpellDamageInfoDB[k], v, "reset: " .. k) end
T.check(queued(), "reset: refresh queued")
T.check(#messages == before + 1 and messages[#messages]:find(DE.OPT_RESET_DONE, 1, true), "reset: says so")
T.check(rows.estimate.widget.checked and rows.tooltip.widget.checked and rows.reduction.widget.checked, "reset: boxes checked")
T.eq(rows.button.text.text, DE.OPT_BUTTON_TOTAL, "reset: button menu shows total")
T.eq(bar.value, 100, "reset: slider back")
T.eq(rows.interfaceLang.text.text, DE.LANG_AUTO, "reset: language back to auto")
T.check(ns.L.DAMAGE == "Schaden", "reset: interface strings back to German (auto)")
T.eq(mockText(1), "831", "reset: preview back")
flush()
sameAsBar("reset")

-- Opening from Options > AddOns: Blizzard's panel closes out of combat; in combat it is left
-- alone and the window opens above it
win:Hide()
SettingsPanel:Show()
hiddenPanels = {}
ns._optionsOpenButton:Click()
T.check(hiddenPanels[1] == SettingsPanel and not SettingsPanel.shown, "page button closes Blizzard's options")
T.check(win.shown and win.strata == "DIALOG", "page button opens the window")
win:Hide()
SettingsPanel:Show()
hiddenPanels = {}
inCombat = true
ns._optionsOpenButton:Click()
T.eq(#hiddenPanels, 0, "in combat: Blizzard's options are left alone")
T.check(win.shown and win.strata == "FULLSCREEN_DIALOG", "in combat: the window opens above them")
rows.button.widget:Click()
T.eq(ns._optionsMenu().strata, "TOOLTIP", "in combat: the menu opens above the window")
ns._optionsMenu().buttons[2]:Click()
T.eq(SpellDamageInfoDB.button, "direct", "in combat: the controls work")
clicked(rows.estimate.widget)
T.eq(SpellDamageInfoDB.estimate, false, "in combat: check boxes work")
flush()
T.eq(shown(ActionButton3), "279", "in combat: the bar follows (direct, no estimate)")
T.eq(mockText(1), "279", "in combat: the preview follows")
clicked(win.reset)
flush()
inCombat = false
SettingsPanel:Hide()

-- The close button hides the window and any open menu
rows.position.widget:Click()
T.check(ns._optionsMenu().shown, "menu open")
local closeButton
for _, f in ipairs(eventFrames) do
  if f.template == "UIPanelCloseButton" and f.parent == win then closeButton = f end
end
T.check(closeButton ~= nil and #closeButton.points >= 1, "close button placed")
if closeButton then closeButton:Click() end
T.check(not win.shown, "close button hides the window")
T.check(not ns._optionsMenu().shown, "closing the window closes the menu")

-- Bad saved values are repaired on load
SpellDamageInfoDB.size, SpellDamageInfoDB.position, SpellDamageInfoDB.reduction = 999, "left", "yes"
SpellDamageInfoDB.interfaceLang = "invalid"
fire("ADDON_LOADED", "SpellDamageInfo")
T.eq(SpellDamageInfoDB.size, 200, "saved size above the range is clamped")
T.eq(SpellDamageInfoDB.position, "bottom", "saved unknown position reset")
T.eq(SpellDamageInfoDB.reduction, true, "saved non-boolean reduction reset")
T.eq(SpellDamageInfoDB.interfaceLang, "auto", "saved invalid language reset to auto")
SpellDamageInfoDB.size = "big"
fire("ADDON_LOADED", "SpellDamageInfo")
T.eq(SpellDamageInfoDB.size, 100, "saved size that is not a number reset")

-- Language: GetLocale enUS but textLocale deDE should parse German
cvarValues.textLocale = "deDE"
local savedDescLang = ns.DescriptionLang()
rawset(_G, "GetLocale", function() return "enUS" end)
ns.DecideLangsAtLoad()
T.eq(ns.DescriptionLang(), "de", "textLocale deDE wins over GetLocale enUS: description lang is German")
rawset(_G, "GetLocale", function() return "deDE" end)
ns.DecideLangsAtLoad()
T.eq(ns.DescriptionLang(), "de", "GetLocale deDE: description lang is German")

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

-- Pet bar changes: a new rank, a dismissed pet, a new summon, the bar being shown
petActions[3] = { "Feuerblitz", 135809, false, false, true, true, 7799 }
fire("PET_BAR_UPDATE")
flush()
T.eq(shown(PetActionButton3), "9", "PET_BAR_UPDATE: Firebolt rank 2 (7-10)")
petActions[3] = nil
fire("UNIT_PET", "target")
flush()
T.eq(shown(PetActionButton3), "9", "UNIT_PET for another unit is ignored")
fire("UNIT_PET", "player")
flush()
T.eq(shown(PetActionButton3), nil, "UNIT_PET: pet dismissed, number gone")
petActions[3] = { "Feuerblitz", 135809, false, false, true, true, 3110 }
T.check(type(PetActionBar.scripts.OnShow) == "function", "hooked the pet bar's OnShow")
if type(PetActionBar.scripts.OnShow) == "function" then PetActionBar.scripts.OnShow(PetActionBar) end
flush()
T.eq(shown(PetActionButton3), "5", "pet bar shown: numbers updated")
SlashCmdList.SPELLDAMAGEINFO("button off")
flush()
T.eq(shown(PetActionButton3), nil, "button off hides the pet number too")
SlashCmdList.SPELLDAMAGEINFO("button total")
flush()

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
