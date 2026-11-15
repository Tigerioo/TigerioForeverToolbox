-- Focus unit frame: protected unit clicks and position changes are set out of combat.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
local driver = CreateFrame("Frame")
local data, frame, handle, hider, nativeOwned, nativeDisowned
local unlocked, dragging, pending, creating = false, false, false, false
local visibilityRegistered, visibilityHooked = false, false

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end
local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end
local function init()
    local db, guid = TigerioForeverToolboxDB, call(UnitGUID, "player")
    if type(db) ~= "table" or not readable(guid) or type(guid) ~= "string" or not guid:match("^Player%-") then return false end
    if db.focusFrame == nil then db.focusFrame = {version = 1, characters = {}} end
    local root = db.focusFrame
    if type(root) ~= "table" or root.version ~= 1 or type(root.characters) ~= "table" then return false end
    if root.characters[guid] == nil then root.characters[guid] = {} end
    local entry = root.characters[guid]
    if type(entry) ~= "table" or (entry.enabled ~= nil and type(entry.enabled) ~= "boolean") then return false end
    data = entry
    return true
end
local function hudEnabled()
    local config = call(toolbox.getHUDConfig)
    return readable(config) and type(config) == "table" and config.enabled == true
end
local function isEnabled() return data and data.enabled ~= false end
local function rootPosition()
    local x, y = 0.64, 0.35
    if type(data) == "table" and type(data.position) == "table" then
        local px, py = data.position.x, data.position.y
        if finite(px) and finite(py) and px >= 0 and px <= 1 and py >= 0 and py <= 1 then x, y = px, py end
    end
    return x, y
end
local function setPosition(target)
    local width, height = call(UIParent.GetWidth, UIParent), call(UIParent.GetHeight, UIParent)
    if not finite(width) or width <= 0 or not finite(height) or height <= 0 then return false end
    local x, y = rootPosition()
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", UIParent, "TOPLEFT", width * x, -height * y)
    return true
end
local function closeHandle()
    if handle and unlocked then
        if dragging then handle:StopMovingOrSizing(); dragging = false end
        unlocked = false; handle:Hide(); notify()
    end
end

-- Change only the original Blizzard parent; never take over another addon's frame.
local function nativeFrame(replace)
    if combat() then pending = true; return false end
    local native = _G.FocusFrame
    if not replace then
        if nativeOwned then
            local saved = nativeOwned
            local checked, current = pcall(saved.frame.GetParent, saved.frame)
            if not checked or not readable(current) then return false end
            if current == hider then
                if not pcall(saved.frame.SetParent, saved.frame, saved.parent) then return false end
                if call(saved.frame.GetParent, saved.frame) ~= saved.parent then return false end
            end
            nativeOwned = nil
        end
        nativeDisowned = nil
        return true
    end
    if not native then return true end
    local ok, parent, forbidden = pcall(function()
        return native:GetParent(), type(native.IsForbidden) == "function" and native:IsForbidden()
    end)
    if not ok or not readable(parent) or not readable(forbidden) or forbidden then return false end
    if nativeOwned then
        if nativeOwned.frame == native and parent == hider then return true end
        nativeOwned = nil; nativeDisowned = native
        return false
    end
    if nativeDisowned == native or parent ~= UIParent then return false end
    if not hider then
        hider = CreateFrame("Frame", nil, UIParent)
        hider:Hide()
    end
    local moved = pcall(native.SetParent, native, hider)
    local checked, actual = pcall(native.GetParent, native)
    if checked and readable(actual) and actual == hider then
        nativeOwned = {frame = native, parent = parent}
        return true
    end
    -- A successful mutation with unverifiable parent must remain recoverable.
    if moved and (not checked or not readable(actual)) then nativeOwned = {frame = native, parent = parent} end
    return false
end

local function text(parent, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetShadowColor(0, 0, 0, 1); label:SetShadowOffset(1, -1)
    return label
end
local function create()
    if frame then return true end
    if combat() then return false end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(286, 48)
    panel:SetClampedToScreen(true)
    if not setPosition(panel) then return false end
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture(MEDIA .. "BarPanel.tga")
    local bar = CreateFrame("StatusBar", nil, panel)
    bar:SetSize(276, 40); bar:SetPoint("LEFT", panel, "LEFT", 5, 0)
    bar:SetStatusBarTexture(MEDIA .. "BarFill.tga")
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local textLayer = bar
    if type(CreateUnitHealPredictionCalculator) == "function"
        and type(UnitGetDetailedHealPrediction) == "function"
        and Enum and Enum.UnitIncomingHealClampMode
        and type(Enum.UnitIncomingHealClampMode.MissingHealth) == "number" then
        local prediction, layer
        local ok = pcall(function()
            local calculator = CreateUnitHealPredictionCalculator()
            calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
            calculator:SetIncomingHealOverflowPercent(1)
            local filled = bar:GetStatusBarTexture()
            if not filled then error("health texture unavailable") end
            prediction = CreateFrame("StatusBar", nil, bar)
            prediction:EnableMouse(false)
            prediction:SetPoint("TOPLEFT", filled, "TOPRIGHT")
            prediction:SetPoint("BOTTOMLEFT", filled, "BOTTOMRIGHT")
            prediction:SetWidth(276); prediction:SetStatusBarTexture(MEDIA .. "BarFill.tga")
            prediction:SetStatusBarColor(0.35, 1, 0.55, 0.65)
            prediction:SetMinMaxValues(0, 1); prediction:SetValue(0)
            layer = CreateFrame("Frame", nil, bar)
            layer:EnableMouse(false); layer:SetAllPoints(bar)
            layer:SetFrameLevel(prediction:GetFrameLevel() + 1)
            bar.healPrediction, bar.healCalculator = prediction, calculator
        end)
        if ok then textLayer = layer elseif prediction then pcall(prediction.Hide, prediction) end
    end
    local name = text(textLayer, "GameFontHighlightSmall")
    name:SetPoint("RIGHT", bar, "RIGHT", -8, 0); name:SetWidth(96); name:SetJustifyH("RIGHT")
    if type(name.SetWordWrap) == "function" then name:SetWordWrap(false) end
    if type(name.SetMaxLines) == "function" then name:SetMaxLines(1) end
    local health = text(textLayer, "GameFontHighlightSmall")
    health:SetPoint("LEFT", bar, "LEFT", 10, 0)
    local level = text(textLayer, "GameFontNormalSmall")
    level:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -5, -1)
    if bar.healPrediction then
        local amount = text(textLayer, "GameFontHighlightSmall")
        amount:SetPoint("CENTER", bar, "CENTER", 0, 0); amount:SetWidth(80)
        amount:SetTextColor(0.72, 1, 0.75, 1); amount:SetText("")
        bar.healAmount = amount
    end
    local button = CreateFrame("Button", nil, panel, "SecureUnitButtonTemplate")
    button:SetAllPoints(panel); button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetAttribute("*type1", "target"); button:SetAttribute("*type2", "togglemenu")
    button:SetAttribute("unit", "focus")
    if type(RegisterUnitWatch) ~= "function" then panel:Hide(); return false end
    RegisterUnitWatch(button)
    panel.bar, panel.name, panel.health, panel.level = bar, name, health, level
    if type(toolbox.attachFocusDetails) ~= "function" then panel:Hide(); return false end
    local detailsOK, detailsReady = pcall(toolbox.attachFocusDetails, panel)
    if not detailsOK or detailsReady ~= true then panel:Hide(); return false end
    panel:Hide(); frame = panel
    return true
end

local function update()
    if not frame or not frame:IsShown() then return end
    local exists = call(UnitExists, "focus")
    if not readable(exists) or exists ~= true then
        frame.bar:SetMinMaxValues(0, 1); frame.bar:SetValue(0)
        frame.name:SetText(""); frame.health:SetText(""); frame.level:SetText("")
        if frame.bar.healPrediction then pcall(frame.bar.healPrediction.SetValue, frame.bar.healPrediction, 0) end
        if frame.bar.healAmount then frame.bar.healAmount:SetText("") end
        return
    end
    local name, second = call(UnitFullName, "focus")
    if readable(name) and (type(name) ~= "string" or name == "") then name, second = call(UnitName, "focus") end
    if not readable(name) then
        if not pcall(frame.name.SetText, frame.name, name) then frame.name:SetText("未知") end
    elseif type(name) == "string" and name ~= "" then
        if readable(second) and type(second) == "string" and second ~= "" then name = name .. " " .. second end
        frame.name:SetText(name)
    else frame.name:SetText("未知") end
    local level, cap = call(UnitLevel, "focus"), call(GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer)
    frame.level:SetText(finite(level) and finite(cap) and level > 0 and level < cap and tostring(level) or "")
    local isPlayer = call(UnitIsPlayer, "focus")
    local colored = false
    if readable(isPlayer) and isPlayer == true then
        local _, class = call(UnitClass, "focus")
        local color = readable(class) and type(class) == "string" and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[class]
        if type(color) == "table" and finite(color.r) and finite(color.g) and finite(color.b) then
            frame.bar:SetStatusBarColor(color.r, color.g, color.b, 1); colored = true
        else
            local fallback = {
                WARRIOR = {0.78, 0.61, 0.43}, PALADIN = {0.96, 0.55, 0.73},
                HUNTER = {0.67, 0.83, 0.45}, ROGUE = {1, 0.96, 0.41},
                PRIEST = {1, 1, 1}, DEATHKNIGHT = {0.77, 0.12, 0.23},
                SHAMAN = {0, 0.44, 0.87}, MAGE = {0.25, 0.78, 0.92},
                WARLOCK = {0.53, 0.53, 0.93}, MONK = {0, 1, 0.59},
                DRUID = {1, 0.49, 0.04}, DEMONHUNTER = {0.64, 0.19, 0.79}, EVOKER = {0.20, 0.58, 0.50},
            }
            local c = readable(class) and type(class) == "string" and fallback[class]
            if c then frame.bar:SetStatusBarColor(c[1], c[2], c[3], 1); colored = true end
        end
    elseif readable(isPlayer) and type(UnitSelectionColor) == "function" then
        local ok, r, g, b = pcall(UnitSelectionColor, "focus")
        if ok and pcall(frame.bar.SetStatusBarColor, frame.bar, r, g, b, 1) then colored = true end
    end
    if not colored and readable(isPlayer) and isPlayer ~= true and type(FACTION_BAR_COLORS) == "table" then
        local reaction = call(UnitReaction, "focus", "player")
        if finite(reaction) and reaction == math.floor(reaction) then
            local ok, r, g, b = pcall(function()
                local c = FACTION_BAR_COLORS[reaction]
                if c then return c.r, c.g, c.b end
            end)
            if ok and finite(r) and finite(g) and finite(b) then
                frame.bar:SetStatusBarColor(r, g, b, 1); colored = true
            end
        end
    end
    if not colored then frame.bar:SetStatusBarColor(0.55, 0.55, 0.55, 1) end
    local current, maximum = call(UnitHealth, "focus"), call(UnitHealthMax, "focus")
    if not pcall(function() frame.bar:SetMinMaxValues(0, maximum); frame.bar:SetValue(current) end) then
        frame.bar:SetMinMaxValues(0, 1); frame.bar:SetValue(0)
    end
    local prediction, calculator = frame.bar.healPrediction, frame.bar.healCalculator
    if prediction and calculator then
        local ok, own, predictedMax, raw = pcall(function()
            UnitGetDetailedHealPrediction("focus", "player", calculator)
            local _, fromPlayer = calculator:GetIncomingHeals()
            local amount
            if type(calculator.GetTotalIncomingHealsFromHealer) == "function" then
                amount = calculator:GetTotalIncomingHealsFromHealer()
            end
            return fromPlayer, calculator:GetMaximumHealth(), amount
        end)
        if not ok or not pcall(function() prediction:SetMinMaxValues(0, predictedMax); prediction:SetValue(own) end) then
            pcall(prediction.SetValue, prediction, 0)
            if frame.bar.healAmount then frame.bar.healAmount:SetText("") end
        elseif frame.bar.healAmount then
            if finite(raw) and raw > 0 then frame.bar.healAmount:SetText("+" .. tostring(math.floor(raw + 0.5)))
            else frame.bar.healAmount:SetText("") end
        end
    end
    if finite(current) and finite(maximum) and maximum > 0 then
        frame.health:SetText(string.format("%d%%", math.max(0, math.min(100, math.floor(current / maximum * 100 + 0.5)))))
    else
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if not curve or type(UnitHealthPercent) ~= "function" or not pcall(function()
            frame.health:SetFormattedText("%.0f%%", UnitHealthPercent("focus", true, curve))
        end) then frame.health:SetText("—") end
    end
end

-- The panel owns protected unit buttons. A secure state driver must control
-- focus visibility so focus changes also work during combat lockdown.
local function stopVisibility()
    if not visibilityRegistered then return true end
    if type(UnregisterStateDriver) ~= "function" then return false end
    if not pcall(UnregisterStateDriver, frame, "visibility") then return false end
    visibilityRegistered = false
    return true
end

local function startVisibility()
    if visibilityRegistered then return true end
    if type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then return false end
    if not visibilityHooked then
        if type(frame.HookScript) ~= "function" or not pcall(frame.HookScript, frame, "OnShow", update) then return false end
        visibilityHooked = true
    end
    if not pcall(RegisterStateDriver, frame, "visibility", "[@focus,exists] show; hide") then return false end
    visibilityRegistered = true
    return true
end

local function sync()
    if not data then return false end
    if combat() then pending = true; return false end
    -- Detail setup may load Blizzard_AuraContainer and synchronously emit
    -- ADDON_LOADED while the frame is still being constructed.
    if creating then pending = true; return false end
    pending = false
    local shouldShow = isEnabled() and hudEnabled()
    if not shouldShow then
        closeHandle()
        if not stopVisibility() then pending = true; return false end
        if frame then frame:Hide() end
        if not nativeFrame(false) then pending = true; return false end
        return true
    end
    creating = true
    local built, ready = pcall(create)
    creating = false
    if not built or not ready then pending = true; return false end
    if not setPosition(frame) then pending = true; return false end
    if not nativeFrame(true) then
        if not stopVisibility() then pending = true; return false end
        frame:Hide(); closeHandle(); pending = true
        return false
    end
    if not startVisibility() then
        frame:Hide(); closeHandle(); nativeFrame(false); pending = true
        return false
    end
    pending = false
    update()
    return true
end
function toolbox.syncFocusFrame() return sync() end
function toolbox.getFocusFrameOptions()
    if not data then return nil, "焦点框体不可用" end
    return {enabled = isEnabled(), unlocked = unlocked}
end
function toolbox.setFocusFrameEnabled(value)
    if type(value) ~= "boolean" or not data then return false, "焦点框体不可用" end
    if combat() then return false, "请在脱战后调整" end
    local previous = data.enabled
    data.enabled = value
    if not sync() then data.enabled = previous; sync(); return false, "焦点框体暂不可用" end
    notify(); return true
end

local function alignHandle()
    if handle then setPosition(handle) end
end
local function createHandle()
    if handle then return end
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(286, 48); button:SetFrameStrata("DIALOG"); button:SetMovable(true)
    button:SetClampedToScreen(true); button:EnableMouse(true); button:RegisterForDrag("LeftButton")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(MEDIA .. "BarPanel.tga")
    local caption = text(button, "GameFontNormal")
    caption:SetPoint("CENTER"); caption:SetText("拖动焦点框体")
    button:SetScript("OnDragStart", function(self)
        if not combat() and unlocked then dragging = true; self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        if not dragging then return end
        self:StopMovingOrSizing(); dragging = false
        if combat() or not unlocked or not data or not frame then alignHandle(); return end
        local width, height = call(UIParent.GetWidth, UIParent), call(UIParent.GetHeight, UIParent)
        local left, top = call(self.GetLeft, self), call(self.GetTop, self)
        local uiLeft, uiTop = call(UIParent.GetLeft, UIParent), call(UIParent.GetTop, UIParent)
        if not finite(width) or width <= 0 or not finite(height) or height <= 0
            or not finite(left) or not finite(top) or not finite(uiLeft) or not finite(uiTop) then alignHandle(); return end
        local x, y = (left - uiLeft) / width, (uiTop - top) / height
        if x < 0 or x > 1 or y < 0 or y > 1 then alignHandle(); return end
        local previous = data.position
        data.position = {x = x, y = y}
        local ok, applied = pcall(setPosition, frame)
        if not ok or not applied then data.position = previous; pcall(setPosition, frame) end
        alignHandle()
    end)
    button:Hide(); handle = button
end
function toolbox.setFocusFrameUnlocked(value)
    if type(value) ~= "boolean" or not data then return false, "焦点框体不可用" end
    if combat() then return false, "请在脱战后调整" end
    if value and (not isEnabled() or not hudEnabled()) then return false, "请先启用 HUD 和焦点框体" end
    -- The independent handle remains available even when no focus is selected.
    if value and (not sync() or not frame or not visibilityRegistered) then return false, "焦点框体暂不可用" end
    createHandle()
    if dragging then handle:StopMovingOrSizing(); dragging = false end
    unlocked = value
    if value then alignHandle(); handle:Show() else handle:Hide() end
    notify(); return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "ADDON_LOADED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
    "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if init() then sync(); notify() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        closeHandle()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then sync() end
        update(); notify()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if combat() then pending = true
        elseif frame then setPosition(frame); if unlocked then alignHandle() end end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED" then
        sync(); update()
    elseif event == "PLAYER_FOCUS_CHANGED" or (readable(unit) and unit == "focus") then
        update()
    elseif (event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        and readable(unit) and type(unit) == "string" then
        local same = call(UnitIsUnit, unit, "focus")
        if readable(same) and same == true then update() end
    end
end)
