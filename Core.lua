-- SpellDamageInfo: action button numbers, tooltip lines, settings and /sdi.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- Everything here stays out of Blizzard's way: the numbers are FontStrings of our own on the
-- action buttons, tooltip lines are added through the tooltip post-call hook, and no Blizzard
-- global or function is replaced. Values the client may hand out as secret (WoW: Forever hides
-- spell power in combat) are checked with issecretvalue before any comparison or maths.

local ADDON, ns = ...
local L, Parser, Estimate, Format = ns.L, ns.Parser, ns.Estimate, ns.Format

local DEFAULTS = {
  estimate = true, button = "total", tooltip = true,
  reduction = true,     -- show by how much a debuff lowers the enemy's damage, in red
  size = 100,           -- button number size in percent of the default (SIZE_MIN..SIZE_MAX)
  position = "bottom",  -- where the number sits on the button: bottom, center or top
  interfaceLang = "auto",  -- interface language: "auto", "en", "de"
}
local BUTTON_MODES = { total = true, direct = true, off = true }
local POSITIONS = { bottom = true, center = true, top = true }
local SIZE_MIN, SIZE_MAX = 50, 200

local db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(issecretvalue, v)
  return ok and secret == true
end

local function say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSpellDamageInfo|r: " .. msg) end
end

---------------------------------------------------------------------------------------------
-- Spell data
---------------------------------------------------------------------------------------------

-- [spellID] = { parsed = table or false, reduction = table or false }
local parsedCache = {}

local function clearCache()
  for k in pairs(parsedCache) do parsedCache[k] = nil end
end

local function getDescription(spellID)
  local fn = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
  if type(fn) ~= "function" then return nil end
  local ok, text = pcall(fn, spellID)
  if not ok or isSecret(text) or type(text) ~= "string" or text == "" then return nil end
  return text
end

local loadRequested = {} -- [spellID] = true once the client was asked to load the spell's text

local function requestLoad(spellID)
  if loadRequested[spellID] then return end
  loadRequested[spellID] = true
  if C_Spell and type(C_Spell.RequestLoadSpellData) == "function" then
    pcall(C_Spell.RequestLoadSpellData, spellID)
  end
end

local function getEntry(spellID)
  local entry = parsedCache[spellID]
  if entry then return entry end
  local text = getDescription(spellID)
  if not text then -- not loaded yet; SPELL_TEXT_UPDATE will ask again
    requestLoad(spellID)
    return nil
  end
  entry = {
    parsed = Parser.Parse(text, ns.DescriptionLang()) or false,
    reduction = Parser.ParseReduction(text, ns.DescriptionLang()) or false,
  }
  parsedCache[spellID] = entry
  return entry
end

local function getParsed(spellID)
  local entry = getEntry(spellID)
  return entry and entry.parsed or nil
end

-- Cast time in seconds, or nil when the client does not say.
local function getCastTime(spellID)
  if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(info) == "table" then
      local ms = info.castTime
      if not isSecret(ms) and type(ms) == "number" then return ms / 1000 end
    end
  end
  if type(GetSpellInfo) == "function" then
    local ok, _, _, _, ms = pcall(GetSpellInfo, spellID)
    if ok and not isSecret(ms) and type(ms) == "number" then return ms / 1000 end
  end
  return nil
end

-- Last readable spell power by school index (2..7) and for healing. In combat the client may
-- return secret values; then the last value read out of combat stays in use.
local bonus = { damage = {}, heal = nil }

local function readBonus()
  if type(GetSpellBonusDamage) == "function" then
    for i = 2, 7 do
      local ok, v = pcall(GetSpellBonusDamage, i)
      if ok and not isSecret(v) and type(v) == "number" then bonus.damage[i] = v end
    end
  end
  if type(GetSpellBonusHealing) == "function" then
    local ok, v = pcall(GetSpellBonusHealing)
    if ok and not isSecret(v) and type(v) == "number" then bonus.heal = v end
  end
end

-- What to show for a spell: the view from Estimate.Apply, or nil. A pet's spell gets the
-- description's numbers only: the pet has its own spell power, and the player's would be wrong.
function ns.Compute(spellID, pet)
  local parsed = getParsed(spellID)
  if not parsed then return nil end
  if pet or not db.estimate then return Estimate.Apply(parsed, nil, nil, nil) end
  local castTime = getCastTime(spellID)
  return Estimate.Apply(parsed, castTime, Estimate.DamageBonus(parsed.school, bonus.damage), bonus.heal)
end

-- How much the spell lowers the enemy's damage or attack power (from Parser.ParseReduction), or nil.
function ns.Reduction(spellID)
  local entry = getEntry(spellID)
  return entry and entry.reduction or nil
end

---------------------------------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------------------------------

-- Blizzard's action bars on Classic Era and Forever (ActionButtonUtil lists them where it
-- exists); BonusActionButton is the old stance/stealth bar of earlier Classic clients.
local BAR_PREFIXES = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
  "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "BonusActionButton",
}

local buttons = {} -- list of Blizzard action buttons
local labels = {}  -- [button] = our FontString for the main number
local sideLabels = {} -- [button] = our smaller FontString for a reduction next to a damage number

local function collectButtons()
  local prefixes, seenPrefix = {}, {}
  local function addPrefix(p)
    if type(p) == "string" and not seenPrefix[p] then
      seenPrefix[p] = true
      prefixes[#prefixes + 1] = p
    end
  end
  if type(ActionButtonUtil) == "table" and type(ActionButtonUtil.ActionBarButtonNames) == "table" then
    for _, p in ipairs(ActionButtonUtil.ActionBarButtonNames) do addPrefix(p) end
  end
  for _, p in ipairs(BAR_PREFIXES) do addPrefix(p) end

  local seen = {}
  for _, b in ipairs(buttons) do seen[b] = true end
  for _, prefix in ipairs(prefixes) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if type(b) == "table" and not seen[b] and type(b.CreateFontString) == "function" then
        seen[b] = true
        buttons[#buttons + 1] = b
      end
    end
  end
end

-- The pet bar: PetActionButton1..10 on Classic Era and Forever (Forever's bar frame is
-- PetActionBar, as on Retail, and lists its buttons in actionButtons). [button] = pet action slot.
local petButtons = {}
local petSlots = {}

local function readID(button)
  if type(button.GetID) ~= "function" then return nil end
  local ok, id = pcall(button.GetID, button)
  if ok and not isSecret(id) and type(id) == "number" and id >= 1 then return id end
  return nil
end

local function collectPetButtons()
  local main = {}
  for _, b in ipairs(buttons) do main[b] = true end
  local function add(b, slot)
    if type(b) == "table" and not petSlots[b] and not main[b] and type(b.CreateFontString) == "function" and slot then
      petSlots[b] = slot
      petButtons[#petButtons + 1] = b
    end
  end
  local n = NUM_PET_ACTION_SLOTS
  if isSecret(n) or type(n) ~= "number" or n < 1 or n > 20 then n = 10 end
  for i = 1, n do
    local b = _G["PetActionButton" .. i]
    if type(b) == "table" then add(b, readID(b) or i) end
  end
  for _, bar in ipairs({ PetActionBar, PetActionBarFrame }) do
    if type(bar) == "table" and type(bar.actionButtons) == "table" then
      for i, b in ipairs(bar.actionButtons) do
        if type(b) == "table" then add(b, readID(b) or i) end
      end
    end
  end
end

-- The number is sized from the button: FONT_SHARE of its height at size 100%, with an outline.
local FONT_SHARE = 0.45
local SIDE_SHARE = 0.75 -- the reduction next to a damage number, relative to the main number
local SIDE_MAX_CHARS = 4 -- "-146", "-10%": longer ones are left out, the damage number wins
local MIN_FONT = 6

local function readNumber(obj, method)
  if type(obj[method]) ~= "function" then return nil end
  local ok, v = pcall(obj[method], obj)
  if ok and not isSecret(v) and type(v) == "number" and v > 0 then return v end
  return nil
end

local function fontFile()
  local obj = NumberFontNormal or NumberFontNormalSmall
  if type(obj) == "table" and type(obj.GetFont) == "function" then
    local ok, file = pcall(obj.GetFont, obj)
    if ok and not isSecret(file) and type(file) == "string" and file ~= "" then return file end
  end
  return "Fonts\\ARIALN.TTF"
end

-- Font size in points for a button: its height (Blizzard buttons are 36, some bars are
-- smaller or scaled), the share, and the size setting.
local function fontSize(button, share)
  local h = readNumber(button, "GetHeight") or 36
  local size = math.floor(h * FONT_SHARE * share * db.size / 100 + 0.5)
  if size < MIN_FONT then size = MIN_FONT end
  return size
end

local fontSizes = {} -- [our FontString] = its current size

local function setFont(fs, size)
  fontSizes[fs] = size
  pcall(fs.SetFont, fs, fontFile(), size, "OUTLINE")
end

-- Shrink the text until it fits inside the button.
local function fitWidth(fs, button)
  local w = readNumber(button, "GetWidth")
  if not w or type(fs.GetStringWidth) ~= "function" then return end
  local size = fontSizes[fs]
  for _ = 1, 10 do
    local sw = readNumber(fs, "GetStringWidth")
    if not sw or sw <= w - 2 or size <= MIN_FONT then return end
    size = math.max(MIN_FONT, math.min(size - 1, math.floor(size * (w - 2) / sw)))
    setFont(fs, size)
  end
end

-- Does the button show a count (reagents, charges) in its bottom right corner?
local function hasCount(slot)
  if type(GetActionCount) ~= "function" or isSecret(slot) or type(slot) ~= "number" then return false end
  local ok, n = pcall(GetActionCount, slot)
  return ok and not isSecret(n) and type(n) == "number" and n > 0
end

-- Hotkey text is top right and the count bottom right, so the number stays away from the right
-- edge when the count is shown.
local function placeMain(fs, button, countShown)
  fs:ClearAllPoints()
  if db.position == "center" then
    fs:SetPoint("CENTER", button, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
  elseif db.position == "top" then
    fs:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    fs:SetJustifyH("LEFT")
  elseif countShown then
    fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    fs:SetJustifyH("LEFT")
  else
    fs:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    fs:SetJustifyH("CENTER")
  end
end

local function placeSide(fs, button)
  fs:ClearAllPoints()
  if db.position == "top" then
    fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
  else
    fs:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  end
  fs:SetJustifyH("LEFT")
end

local function newLabel(button)
  local template = NumberFontNormal and "NumberFontNormal" or "GameFontHighlight"
  return button:CreateFontString(nil, "OVERLAY", template)
end

local function getLabel(button)
  local fs = labels[button]
  if not fs then
    fs = newLabel(button)
    labels[button] = fs
  end
  return fs
end

local function getSideLabel(button)
  local fs = sideLabels[button]
  if not fs then
    fs = newLabel(button)
    sideLabels[button] = fs
  end
  return fs
end

local function hide(fs)
  if fs then fs:SetText(""); fs:Hide() end
end

local function spellOnSlot(slot)
  if isSecret(slot) or type(slot) ~= "number" or type(GetActionInfo) ~= "function" then return nil end
  local ok, kind, id = pcall(GetActionInfo, slot)
  if not ok or isSecret(kind) or isSecret(id) then return nil end
  if kind == "spell" and type(id) == "number" then return id end
  return nil
end

-- The spell on a pet action slot, or nil for an empty slot, a command (Attack, Follow, Stay and
-- the stances are tokens) or anything the client hides. GetPetActionInfo returns name, texture,
-- isToken, isActive, autoCastAllowed, autoCastEnabled, spellID.
local function petSpellOnSlot(slot)
  if isSecret(slot) or type(slot) ~= "number" or type(GetPetActionInfo) ~= "function" then return nil end
  local ok, name, _, isToken, _, _, _, spellID = pcall(GetPetActionInfo, slot)
  if not ok or isSecret(name) or name == nil or isSecret(isToken) or isToken then return nil end
  if isSecret(spellID) or type(spellID) ~= "number" or spellID <= 0 then return nil end
  return spellID
end
ns.PetSpellOnSlot = petSpellOnSlot

-- The text on a button for a view from ns.Compute and a reduction from ns.Reduction (either may
-- be nil), under the current settings: main text, its colour, and the smaller reduction text
-- next to it (or nil). The options window's preview draws its sample spells through this too.
local function buttonText(view, reduction)
  if db.button == "off" then return nil end
  if not db.reduction then reduction = nil end
  local value, kind = Estimate.ButtonValue(view, db.button)
  if value and value < 0.5 then value = nil end

  local mainText, mainColor, sideText
  if value then
    mainText = Format.Short(value)
    mainColor = (kind == "heal") and Format.HEAL_COLOR or Format.DAMAGE_COLOR
    if reduction then
      local t = Format.ReductionText(reduction, ns.L)
      if #t <= SIDE_MAX_CHARS then sideText = t end
    end
  elseif reduction then
    mainText = Format.ReductionText(reduction, ns.L)
    mainColor = Format.REDUCTION_COLOR
  end
  return mainText, mainColor, sideText
end
ns.ButtonText = buttonText

-- Draws the text from buttonText on a button: fs is the main FontString, side the reduction's
-- (may be nil when there is no sideText). countShown: the button shows a count bottom right.
local function drawNumber(button, fs, side, mainText, mainColor, sideText, countShown)
  if not mainText then
    hide(fs)
    hide(side)
    return
  end
  placeMain(fs, button, countShown)
  setFont(fs, fontSize(button, 1))
  fs:SetTextColor(mainColor[1], mainColor[2], mainColor[3])
  fs:SetText(mainText)
  fitWidth(fs, button)
  fs:Show()

  if sideText and side then
    placeSide(side, button)
    setFont(side, fontSize(button, SIDE_SHARE))
    local c = Format.REDUCTION_COLOR
    side:SetTextColor(c[1], c[2], c[3])
    side:SetText(sideText)
    side:Show()
  else
    hide(side)
  end
end
ns.DrawNumber = drawNumber
ns.NewLabel = newLabel

local function updateButton(button, pet)
  local view, reduction
  if db.button ~= "off" then
    local spellID
    if pet then spellID = petSpellOnSlot(petSlots[button]) else spellID = spellOnSlot(button.action) end
    if spellID then
      view = ns.Compute(spellID, pet)
      if db.reduction then reduction = ns.Reduction(spellID) end
    end
  end
  local mainText, mainColor, sideText = buttonText(view, reduction)
  if not mainText then
    hide(labels[button])
    hide(sideLabels[button])
    return
  end
  local side = sideText and getSideLabel(button) or sideLabels[button]
  drawNumber(button, getLabel(button), side, mainText, mainColor, sideText, not pet and hasCount(button.action))
end

local function updateAllButtons()
  for _, b in ipairs(buttons) do updateButton(b, false) end
  for _, b in ipairs(petButtons) do updateButton(b, true) end
end

local pending = false
local function requestUpdate()
  if pending then return end
  pending = true
  local function run()
    pending = false
    readBonus()
    updateAllButtons()
  end
  -- A short delay lets Blizzard's own handlers set button.action after a page change first.
  if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0.1, run) else run() end
end
ns.Refresh = requestUpdate

---------------------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------------------

-- Adds our lines; returns how many. A pet's spell says so at the end of each line.
local function addTooltipLines(tooltip, spellID, pet)
  if not db.tooltip or isSecret(spellID) or type(spellID) ~= "number" then return 0 end
  local lines = Format.TooltipLines(ns.Compute(spellID, pet), L)
  if db.reduction then
    local reduction = ns.Reduction(spellID)
    if reduction then lines[#lines + 1] = Format.ReductionLine(reduction, L) end
  end
  for _, line in ipairs(lines) do
    local text = pet and (line[1] .. " (" .. L.PET .. ")") or line[1]
    tooltip:AddLine(text, line[2], line[3], line[4])
  end
  return #lines
end
ns.AddTooltipLines = addTooltipLines

-- The pet action slot of the button a tooltip belongs to, or nil.
local function ownerPetSlot(tooltip)
  if type(tooltip.GetOwner) ~= "function" then return nil end
  local ok, owner = pcall(tooltip.GetOwner, tooltip)
  if ok and type(owner) == "table" then return petSlots[owner] end
  return nil
end

-- A pet action tooltip can reach us twice: through a tooltip data post-call (on clients that
-- build tooltips from data, and again when the tooltip refreshes) and through the SetPetAction
-- hook right after it. The post-call marks the tooltip so the hook does not add the lines again.
local petLinesDone = {} -- [tooltip] = true

local function addPetLines(tooltip, slot)
  return addTooltipLines(tooltip, petSpellOnSlot(slot), true)
end

local function hookTooltips()
  local postCalls = type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and type(Enum) == "table" and type(Enum.TooltipDataType) == "table"
  if postCalls and Enum.TooltipDataType.Spell then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
      local slot = ownerPetSlot(tooltip)
      if slot then
        addPetLines(tooltip, slot)
        petLinesDone[tooltip] = true
      elseif type(data) == "table" then
        addTooltipLines(tooltip, data.id, false)
      end
    end)
  elseif GameTooltip and type(GameTooltip.HookScript) == "function" then
    GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
      if ownerPetSlot(tooltip) then return end -- the SetPetAction hook below handles it
      local _, spellID = tooltip:GetSpell()
      addTooltipLines(tooltip, spellID, false)
    end)
  end
  if postCalls and Enum.TooltipDataType.PetAction and Enum.TooltipDataType.PetAction ~= Enum.TooltipDataType.Spell then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.PetAction, function(tooltip)
      local slot = ownerPetSlot(tooltip)
      if slot then
        addPetLines(tooltip, slot)
        petLinesDone[tooltip] = true
      end
    end)
  end
  if type(hooksecurefunc) == "function" and GameTooltip and type(GameTooltip.SetPetAction) == "function" then
    if type(GameTooltip.HookScript) == "function" then
      -- SetPetAction clears the tooltip before the post-calls run, so a mark left by an earlier
      -- tooltip is gone by then
      pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tooltip) petLinesDone[tooltip] = nil end)
    end
    hooksecurefunc(GameTooltip, "SetPetAction", function(tooltip, slot)
      if petLinesDone[tooltip] then
        petLinesDone[tooltip] = nil
        return
      end
      if addPetLines(tooltip, slot) > 0 and type(tooltip.Show) == "function" then tooltip:Show() end
    end)
  end
end

---------------------------------------------------------------------------------------------
-- Settings and /sdi
---------------------------------------------------------------------------------------------

local function onOff(v) return v and L.ON or L.OFF end

local function toggleArg(arg, current)
  if arg == "on" or arg == "an" then return true end
  if arg == "off" or arg == "aus" then return false end
  if arg == nil or arg == "" then return not current end
  return nil
end

-- Is value valid for setting key? Used by the options window; the slash handler checks its own.
local function validSetting(key, value)
  if key == "button" then return BUTTON_MODES[value] == true end
  if key == "position" then return POSITIONS[value] == true end
  if key == "size" then return type(value) == "number" and value >= SIZE_MIN and value <= SIZE_MAX end
  if key == "estimate" or key == "tooltip" or key == "reduction" then return type(value) == "boolean" end
  if key == "interfaceLang" then return value == "auto" or value == "en" or value == "de" end
  return false
end

-- Settings changed from outside the options window (/sdi): the window, when open, shows them.
local function settingsChanged()
  if type(ns.OptionsChanged) == "function" then ns.OptionsChanged() end
end

-- For Options.lua: the live settings table (loadSettings replaces it), a checked write, and
-- a reset. Both writes refresh the buttons.
ns.DEFAULTS, ns.SIZE_MIN, ns.SIZE_MAX = DEFAULTS, SIZE_MIN, SIZE_MAX
function ns.GetSettings() return db end

function ns.SetSetting(key, value)
  if not validSetting(key, value) then return false end
  if key == "size" then value = math.floor(value + 0.5) end
  db[key] = value
  requestUpdate()
  return true
end

function ns.ResetSettings()
  for k, v in pairs(DEFAULTS) do db[k] = v end
  requestUpdate()
end

local function langLabel(lang)
  if lang == "en" then return L.LANG_EN end
  if lang == "de" then return L.LANG_DE end
  return L.LANG_AUTO
end

local function slash(msg)
  msg = type(msg) == "string" and msg:lower() or ""
  local cmd, arg = msg:match("^%s*(%S*)%s*(%S*)")
  if (cmd == "" or cmd == "options" or cmd == "config") and type(ns.OpenOptions) == "function" then
    ns.OpenOptions()
    return
  end
  if cmd == "" or cmd == "help" or cmd == "hilfe" then
    for _, line in ipairs(L.HELP) do say(line) end
    return
  end
  if cmd == "estimate" or cmd == "tooltip" or cmd == "reduction" then
    local v = toggleArg(arg, db[cmd])
    if v == nil then say(L.BAD_ARG) return end
    db[cmd] = v
  elseif cmd == "button" then
    if not BUTTON_MODES[arg] then say(L.BAD_ARG) return end
    db.button = arg
  elseif cmd == "size" then
    local v = tonumber(arg)
    if not v or v < SIZE_MIN or v > SIZE_MAX then say(L.BAD_ARG) return end
    db.size = math.floor(v + 0.5)
  elseif cmd == "position" then
    if not POSITIONS[arg] then say(L.BAD_ARG) return end
    db.position = arg
  elseif cmd == "lang" then
    if not (arg == "auto" or arg == "en" or arg == "de") then say(L.BAD_ARG) return end
    db.interfaceLang = arg
    ns.SetInterfaceAndRefreshL(arg)
  elseif cmd ~= "status" then
    say(L.BAD_ARG)
    return
  end
  say(string.format(L.STATUS, onOff(db.estimate), db.button, onOff(db.tooltip), onOff(db.reduction), db.size,
    db.position, langLabel(db.interfaceLang)))
  requestUpdate()
  settingsChanged()
end

SLASH_SPELLDAMAGEINFO1 = "/sdi"
if type(SlashCmdList) == "table" then SlashCmdList["SPELLDAMAGEINFO"] = slash end

local function loadSettings()
  if type(SpellDamageInfoDB) ~= "table" then SpellDamageInfoDB = {} end
  db = SpellDamageInfoDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  if not BUTTON_MODES[db.button] then db.button = DEFAULTS.button end
  if type(db.estimate) ~= "boolean" then db.estimate = DEFAULTS.estimate end
  if type(db.tooltip) ~= "boolean" then db.tooltip = DEFAULTS.tooltip end
  if type(db.reduction) ~= "boolean" then db.reduction = DEFAULTS.reduction end
  if not POSITIONS[db.position] then db.position = DEFAULTS.position end
  if db.interfaceLang ~= "auto" and db.interfaceLang ~= "en" and db.interfaceLang ~= "de" then
    db.interfaceLang = DEFAULTS.interfaceLang
  end
  if type(db.size) ~= "number" or db.size ~= db.size then
    db.size = DEFAULTS.size
  elseif db.size < SIZE_MIN then
    db.size = SIZE_MIN
  elseif db.size > SIZE_MAX then
    db.size = SIZE_MAX
  end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")

local UPDATE_EVENTS = {
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PET_BAR_UPDATE", "PET_BAR_UPDATE_USABLE",
}
local RESET_EVENTS = { "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }

local function register(event)
  pcall(frame.RegisterEvent, frame, event) -- an event this client does not know is skipped
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local isReset = {}
for _, e in ipairs(RESET_EVENTS) do isReset[e] = true end

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      ns.DecideLangsAtLoad()
      loadSettings()
      ns.InitInterfaceL(db.interfaceLang)
    end
  elseif event == "PLAYER_LOGIN" then
    collectButtons()
    collectPetButtons()
    hookTooltips()
    for _, e in ipairs(UPDATE_EVENTS) do register(e) end
    for _, e in ipairs(RESET_EVENTS) do register(e) end
    register("SPELL_TEXT_UPDATE")
    for _, e in ipairs({ "UNIT_AURA", "UNIT_PET" }) do
      if type(frame.RegisterUnitEvent) == "function" then
        pcall(frame.RegisterUnitEvent, frame, e, "player")
      else
        register(e)
      end
    end
    for _, bar in ipairs({ PetActionBar, PetActionBarFrame }) do
      if type(bar) == "table" and type(bar.HookScript) == "function" then
        pcall(bar.HookScript, bar, "OnShow", requestUpdate)
      end
    end
    readBonus()
    requestUpdate()
  elseif event == "SPELL_TEXT_UPDATE" then
    if not isSecret(arg1) and type(arg1) == "number" then parsedCache[arg1] = nil end
    requestUpdate()
  elseif event == "UNIT_AURA" or event == "UNIT_PET" then
    if not isSecret(arg1) and arg1 == "player" then requestUpdate() end
  elseif event == "PET_BAR_UPDATE" then
    collectPetButtons()
    requestUpdate()
  else
    if isReset[event] then clearCache() end
    requestUpdate()
  end
end)

-- For the tests.
ns._buttons, ns._labels, ns._sideLabels, ns._bonus = buttons, labels, sideLabels, bonus
ns._petButtons, ns._petSlots = petButtons, petSlots
ns._settings = function() return db end
