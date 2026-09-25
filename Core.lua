-- SpellDamageInfo: action button numbers, tooltip lines, settings and /sdi.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- Everything here stays out of Blizzard's way: the numbers are FontStrings of our own on the
-- action buttons, tooltip lines are added through the tooltip post-call hook, and no Blizzard
-- global or function is replaced. Values the client may hand out as secret (WoW: Forever hides
-- spell power in combat) are checked with issecretvalue before any comparison or maths.

local ADDON, ns = ...
local L, Parser, Estimate, Format = ns.L, ns.Parser, ns.Estimate, ns.Format

local DEFAULTS = { estimate = true, button = "total", tooltip = true }
local BUTTON_MODES = { total = true, direct = true, off = true }

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

local parsedCache = {} -- [spellID] = parsed table, or false when the text has no numbers we read

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

local function getParsed(spellID)
  local cached = parsedCache[spellID]
  if cached ~= nil then return cached or nil end
  local text = getDescription(spellID)
  if not text then return nil end -- not loaded yet; SPELL_TEXT_UPDATE will ask again
  local parsed = Parser.Parse(text, ns.lang)
  parsedCache[spellID] = parsed or false
  return parsed
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

-- What to show for a spell: the view from Estimate.Apply, or nil.
function ns.Compute(spellID)
  local parsed = getParsed(spellID)
  if not parsed then return nil end
  if not db.estimate then return Estimate.Apply(parsed, nil, nil, nil) end
  local castTime = getCastTime(spellID)
  return Estimate.Apply(parsed, castTime, Estimate.DamageBonus(parsed.school, bonus.damage), bonus.heal)
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
local labels = {}  -- [button] = our FontString

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

local function getLabel(button)
  local fs = labels[button]
  if not fs then
    local template = NumberFontNormalSmall and "NumberFontNormalSmall" or "GameFontHighlightSmall"
    fs = button:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
    fs:SetJustifyH("CENTER")
    labels[button] = fs
  end
  return fs
end

local function spellOnSlot(slot)
  if isSecret(slot) or type(slot) ~= "number" or type(GetActionInfo) ~= "function" then return nil end
  local ok, kind, id = pcall(GetActionInfo, slot)
  if not ok or isSecret(kind) or isSecret(id) then return nil end
  if kind == "spell" and type(id) == "number" then return id end
  return nil
end

local function updateButton(button)
  local value, kind
  if db.button ~= "off" then
    local spellID = spellOnSlot(button.action)
    if spellID then value, kind = Estimate.ButtonValue(ns.Compute(spellID), db.button) end
  end
  local fs = labels[button]
  if not value or value < 0.5 then
    if fs then fs:SetText(""); fs:Hide() end
    return
  end
  fs = fs or getLabel(button)
  local color = (kind == "heal") and Format.HEAL_COLOR or Format.DAMAGE_COLOR
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetText(Format.Short(value))
  fs:Show()
end

local function updateAllButtons()
  for _, b in ipairs(buttons) do updateButton(b) end
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

---------------------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------------------

local function addTooltipLines(tooltip, spellID)
  if not db.tooltip or isSecret(spellID) or type(spellID) ~= "number" then return end
  local lines = Format.TooltipLines(ns.Compute(spellID), L)
  for _, line in ipairs(lines) do tooltip:AddLine(line[1], line[2], line[3], line[4]) end
end
ns.AddTooltipLines = addTooltipLines

local function hookTooltips()
  if type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and type(Enum) == "table" and type(Enum.TooltipDataType) == "table" and Enum.TooltipDataType.Spell then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
      if type(data) == "table" then addTooltipLines(tooltip, data.id) end
    end)
  elseif GameTooltip and type(GameTooltip.HookScript) == "function" then
    GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
      local _, spellID = tooltip:GetSpell()
      addTooltipLines(tooltip, spellID)
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

local function slash(msg)
  msg = type(msg) == "string" and msg:lower() or ""
  local cmd, arg = msg:match("^%s*(%S*)%s*(%S*)")
  if cmd == "" or cmd == "help" or cmd == "hilfe" then
    for _, line in ipairs(L.HELP) do say(line) end
    return
  end
  if cmd == "estimate" or cmd == "tooltip" then
    local v = toggleArg(arg, db[cmd])
    if v == nil then say(L.BAD_ARG) return end
    db[cmd] = v
  elseif cmd == "button" then
    if not BUTTON_MODES[arg] then say(L.BAD_ARG) return end
    db.button = arg
  elseif cmd ~= "status" then
    say(L.BAD_ARG)
    return
  end
  say(string.format(L.STATUS, onOff(db.estimate), db.button, onOff(db.tooltip)))
  requestUpdate()
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
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")

local UPDATE_EVENTS = {
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED",
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
    if arg1 == ADDON then loadSettings() end
  elseif event == "PLAYER_LOGIN" then
    collectButtons()
    hookTooltips()
    for _, e in ipairs(UPDATE_EVENTS) do register(e) end
    for _, e in ipairs(RESET_EVENTS) do register(e) end
    register("SPELL_TEXT_UPDATE")
    if type(frame.RegisterUnitEvent) == "function" then
      pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
    else
      register("UNIT_AURA")
    end
    readBonus()
    requestUpdate()
  elseif event == "SPELL_TEXT_UPDATE" then
    if not isSecret(arg1) and type(arg1) == "number" then parsedCache[arg1] = nil end
    requestUpdate()
  elseif event == "UNIT_AURA" then
    if not isSecret(arg1) and arg1 == "player" then requestUpdate() end
  else
    if isReset[event] then clearCache() end
    requestUpdate()
  end
end)

-- For the tests.
ns._buttons, ns._labels, ns._bonus = buttons, labels, bonus
ns._settings = function() return db end
