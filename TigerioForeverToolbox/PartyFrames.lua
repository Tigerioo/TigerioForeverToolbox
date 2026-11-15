-- Minimal secure party frames; the native raid frames are never touched.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
local character, root, buttons, hider, owned, pending, positionPending = nil, nil, {}, nil, nil, false, false
local moveHandle, unlocked, dragging = nil, false, false
local alignMoveHandle
local PANEL_WIDTH, ROW_HEIGHT, ROW_PITCH = 220, 57, 69
local DEBUFF_SIZE, DEBUFF_SPACING = 32, 4

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, result = pcall(issecretvalue, value)
    return ok and not result
end
local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, value2 = pcall(canaccesstable, value)
    return ok and readable(value2) and value2 == true
end
local function get(object, key)
    if not readable(object) or not object then return nil, false end
    local ok, value = pcall(function() return object[key] end)
    if ok and readable(value) then return value, true end
    return nil, false
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function finite(value)
    return readable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end
local function guid()
    local id = call(UnitGUID, "player")
    if readable(id) and type(id) == "string" and id:match("^Player%-") then return id end
end
local function initialize()
    character = nil
    local db, id = TigerioForeverToolboxDB, guid()
    if not tableOK(db) or not id then return false end
    local data, dataOK = get(db, "globalUI")
    if not dataOK then return false end
    if data == nil then data = {version = 1, characters = {}}; if not pcall(function() db.globalUI = data end) then return false end end
    local entries = get(data, "characters")
    if not tableOK(data) or get(data, "version") ~= 1 or not tableOK(entries) then return false end
    local entry, entryOK = get(entries, id)
    if not entryOK then return false end
    if entry == nil then entry = {}; if not pcall(function() entries[id] = entry end) then return false end end
    if not tableOK(entry) then return false end
    local value, settingOK = get(entry, "partyFrames")
    if not settingOK or (value ~= nil and type(value) ~= "boolean") then return false end
    character = entry
    return true
end
local function current()
    local db, id = TigerioForeverToolboxDB, guid()
    local data = get(db, "globalUI")
    local entries = get(data, "characters")
    return character and id and tableOK(db) and tableOK(data) and get(data, "version") == 1
        and tableOK(entries) and get(entries, id) == character
end
local function hudEnabled()
    local config = call(toolbox.getHUDConfig)
    return tableOK(config) and get(config, "enabled") == true
end
local function raid()
    if type(IsInRaid) ~= "function" then return nil end
    local value = call(IsInRaid)
    if not readable(value) or type(value) ~= "boolean" then return nil end
    return value
end
local function pvpInstance()
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inside, instanceType = pcall(IsInInstance)
    if not ok or not readable(inside) or not readable(instanceType) then return nil end
    if inside == false then return false end
    if inside ~= true or type(instanceType) ~= "string" then return nil end
    return instanceType == "arena" or instanceType == "pvp"
end
local function interfacesReady()
    return type(UnitExists) == "function" and type(UnitHealth) == "function"
        and type(UnitHealthMax) == "function" and type(UnitPowerType) == "function"
        and type(UnitPower) == "function" and type(UnitPowerMax) == "function"
        and (type(UnitFullName) == "function" or type(UnitName) == "function")
end
local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end

local function classColor(unit)
    local _, token = call(UnitClass, unit)
    local colors = RAID_CLASS_COLORS
    if readable(token) and type(token) == "string" and tableOK(colors) then
        local color = get(colors, token)
        local r, g, b = get(color, "r"), get(color, "g"), get(color, "b")
        if finite(r) and finite(g) and finite(b) then return r, g, b end
    end
    return 0.55, 0.55, 0.55
end
local function percent(label, unit, value, maximum)
    if finite(value) and finite(maximum) and maximum > 0 then
        label:SetText(string.format("%d%%", math.max(0, math.min(100, math.floor(value / maximum * 100 + 0.5)))))
        return
    end
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if curve and type(UnitHealthPercent) == "function" and type(label.SetFormattedText) == "function"
        and pcall(function() label:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve)) end) then return end
    label:SetText("—")
end

-- Let the client clamp and render predicted heals, including secret combat
-- values. Never perform Lua arithmetic or comparisons on a secret value.
local function clearPrediction(button)
    if not button.healPrediction then return end
    pcall(button.healPrediction.SetMinMaxValues, button.healPrediction, 0, 1)
    pcall(button.healPrediction.SetValue, button.healPrediction, 0)
    button.healPredictionText:SetText("")
end

local function updatePrediction(button, offline, dead)
    if not button.healPrediction or not button.healCalculator then return end
    if offline or (readable(dead) and dead == true) or type(UnitGetDetailedHealPrediction) ~= "function" then
        clearPrediction(button)
        return
    end
    local ok, amount = pcall(function()
        local calculator = button.healCalculator
        UnitGetDetailedHealPrediction(button.unitToken, "player", calculator)
        local _, mine = calculator:GetIncomingHeals()
        local maximum = calculator:GetMaximumHealth()
        button.healPrediction:SetMinMaxValues(0, maximum)
        button.healPrediction:SetValue(mine)
        return mine
    end)
    if not ok then clearPrediction(button); return end
    local calculator = button.healCalculator
    if type(calculator.GetTotalIncomingHealsFromHealer) == "function" then
        local gotRaw, raw = pcall(calculator.GetTotalIncomingHealsFromHealer, calculator)
        if gotRaw then amount = raw end
    end
    -- The raw estimate can be secret even while the status bar can render it.
    if finite(amount) and amount > 0 then
        button.healPredictionText:SetFormattedText("+%.0f", amount)
    else
        button.healPredictionText:SetText("")
    end
end

local function createPrediction(button, health)
    if type(CreateUnitHealPredictionCalculator) ~= "function" or type(UnitGetDetailedHealPrediction) ~= "function"
        or not Enum or not Enum.UnitIncomingHealClampMode
        or type(Enum.UnitIncomingHealClampMode.MissingHealth) ~= "number" then return end
    local ok, calculator = pcall(CreateUnitHealPredictionCalculator)
    if not ok or not calculator then return end
    local configured = pcall(function()
        calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
        calculator:SetIncomingHealOverflowPercent(1)
    end)
    if not configured then return end
    local built, bar, text = pcall(function()
        local clip = CreateFrame("Frame", nil, health)
        clip:SetAllPoints(health)
        clip:EnableMouse(false)
        if type(clip.SetClipsChildren) == "function" then clip:SetClipsChildren(true) end
        if type(clip.SetFrameLevel) == "function" and type(health.GetFrameLevel) == "function" then
            clip:SetFrameLevel(health:GetFrameLevel())
        end
        local prediction = CreateFrame("StatusBar", nil, clip)
        prediction:EnableMouse(false)
        prediction:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT")
        prediction:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT")
        prediction:SetWidth(PANEL_WIDTH - 10)
        prediction:SetStatusBarTexture(MEDIA .. "BarFill.tga")
        prediction:SetStatusBarColor(0.35, 1, 0.55, 0.65)
        if type(prediction.SetFrameLevel) == "function" and type(health.GetFrameLevel) == "function" then
            prediction:SetFrameLevel(health:GetFrameLevel())
        end
        prediction:SetMinMaxValues(0, 1)
        prediction:SetValue(0)
        local caption = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        caption:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", -5, 1)
        caption:SetTextColor(0.55, 1, 0.70, 1)
        caption:SetText("")
        return prediction, caption
    end)
    if built and bar and text then
        button.healPrediction, button.healPredictionText, button.healCalculator = bar, text, calculator
    end
end

local function clearDebuff(icon)
    icon:Hide()
    if icon.cooldown then
        pcall(icon.cooldown.Clear, icon.cooldown)
        icon.cooldown:Hide()
    end
end

local function updateDebuffTime(icon, unit, aura)
    local cooldown = icon.cooldown
    if not cooldown then return end
    local applied = false
    local id = get(aura, "auraInstanceID")
    if finite(id) and C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function"
        and type(cooldown.SetCooldownFromDurationObject) == "function" then
        local got, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
        if got then applied = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration) end
    end
    if not applied then
        local duration, expiration = get(aura, "duration"), get(aura, "expirationTime")
        if finite(duration) and duration > 0 and finite(expiration) and expiration > 0 then
            applied = pcall(cooldown.SetCooldown, cooldown, expiration - duration, duration)
        end
    end
    if applied then cooldown:Show() else pcall(cooldown.Clear, cooldown); cooldown:Hide() end
end

local function update(button)
    local unit = button.unitToken
    local exists = call(UnitExists, unit)
    if not readable(exists) or exists ~= true then
        button.nameLabel:SetText(""); button.healthText:SetText("")
        clearPrediction(button)
        for _, icon in ipairs(button.debuffs) do clearDebuff(icon) end
        return
    end
    local name, second = call(UnitFullName, unit)
    if readable(name) and (type(name) ~= "string" or name == "") then name, second = call(UnitName, unit) end
    if not readable(name) then
        if not pcall(button.nameLabel.SetText, button.nameLabel, name) then button.nameLabel:SetText("未知") end
    elseif type(name) == "string" and name ~= "" then
        if readable(second) and type(second) == "string" and second ~= "" then name = name .. " " .. second end
        button.nameLabel:SetText(name)
    else button.nameLabel:SetText("未知") end
    local health, maximum = call(UnitHealth, unit), call(UnitHealthMax, unit)
    local dead, connected = call(UnitIsDeadOrGhost, unit), call(UnitIsConnected, unit)
    local offline = readable(connected) and connected == false
    local r, g, b
    if offline then r, g, b = 0.45, 0.45, 0.45 else r, g, b = classColor(unit) end
    button.health:SetStatusBarColor(r, g, b, 1)
    if offline then
        -- Offline units can report zero health; fill the bar so grey remains visible.
        button.health:SetMinMaxValues(0, 1); button.health:SetValue(1)
    elseif not pcall(function() button.health:SetMinMaxValues(0, maximum); button.health:SetValue(health) end) then
        button.health:SetMinMaxValues(0, 1); button.health:SetValue(0)
    end
    if offline then button.healthText:SetText("离线")
    elseif readable(dead) and dead == true then button.healthText:SetText("死亡")
    else percent(button.healthText, unit, health, maximum) end
    updatePrediction(button, offline, dead)
    local powerType, token, ar, ag = call(UnitPowerType, unit)
    local power, powerMax = call(UnitPower, unit, powerType), call(UnitPowerMax, unit, powerType)
    local color = tableOK(PowerBarColor) and (get(PowerBarColor, token) or get(PowerBarColor, powerType))
    r, g, b = get(color, "r"), get(color, "g"), get(color, "b")
    if not finite(r) or not finite(g) or not finite(b) then r, g, b = 0.4, 0.4, 0.4 end
    button.power:SetStatusBarColor(r, g, b, 1)
    if not pcall(function() button.power:SetMinMaxValues(0, powerMax); button.power:SetValue(power) end) then
        button.power:SetMinMaxValues(0, 1); button.power:SetValue(0)
    end
    for i, icon in ipairs(button.debuffs) do
        local aura = C_UnitAuras and call(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        local texture = tableOK(aura) and get(aura, "icon")
        if readable(texture) and ((type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "")) then
            icon:SetTexture(texture); icon:Show(); updateDebuffTime(icon, unit, aura)
        else clearDebuff(icon) end
    end
end
local function refresh()
    for _, button in ipairs(buttons) do update(button) end
end
local function positionFractions()
    local x, y = 0.20, 0.25
    local position = get(character, "partyPosition")
    if tableOK(position) then
        local savedX, savedY = get(position, "x"), get(position, "y")
        if finite(savedX) and finite(savedY) and savedX >= 0 and savedX <= 1 and savedY >= 0 and savedY <= 1 then
            x, y = savedX, savedY
        end
    end
    return x, y
end
local function positionRoot(frame)
    local width, height = call(UIParent.GetWidth, UIParent), call(UIParent.GetHeight, UIParent)
    if not finite(width) or width <= 0 or not finite(height) or height <= 0 then return false end
    local x, y = positionFractions()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", width * x, -height * y)
    return true
end
local function create()
    if root then return true end
    if type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then return false end
    local parent = CreateFrame("Frame", "TigerioForeverToolboxParty", UIParent)
    parent:SetSize(PANEL_WIDTH, ROW_HEIGHT + ROW_PITCH * 4)
    if not positionRoot(parent) then parent:Hide(); return false end
    parent:EnableMouse(false)
    local made = {}
    local ok = pcall(function()
        for i = 1, 5 do
            local unit = i == 1 and "player" or "party" .. (i - 1)
            local b = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
            made[i] = b
            b.unitToken = unit
            b:SetSize(PANEL_WIDTH, ROW_HEIGHT); b:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_PITCH)
            b:EnableMouse(true)
            b:RegisterForClicks("AnyUp"); b:SetAttribute("unit", unit)
            b:SetAttribute("*type1", "target"); b:SetAttribute("*type2", "togglemenu")
            local back = b:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetTexture(MEDIA .. "BarPanel.tga")
            local health = CreateFrame("StatusBar", nil, b)
            health:SetPoint("TOPLEFT", 5, -4); health:SetPoint("BOTTOMRIGHT", -5, 11)
            health:EnableMouse(false); health:SetStatusBarTexture(MEDIA .. "BarFill.tga")
            local name = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            name:SetPoint("LEFT", 5, 0); name:SetWidth(140); name:SetJustifyH("LEFT")
            if type(name.SetWordWrap) == "function" then name:SetWordWrap(false) end
            if type(name.SetMaxLines) == "function" then name:SetMaxLines(1) end
            local text = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); text:SetPoint("RIGHT", -5, 0)
            createPrediction(b, health)
            local power = CreateFrame("StatusBar", nil, b)
            power:SetPoint("BOTTOMLEFT", 5, 4); power:SetPoint("BOTTOMRIGHT", -5, 4); power:SetHeight(6)
            power:EnableMouse(false); power:SetStatusBarTexture(MEDIA .. "BarFill.tga")
            b.health, b.power, b.nameLabel, b.healthText = health, power, name, text
            b.debuffs = {}
            for index = 1, 3 do
                local icon = b:CreateTexture(nil, "OVERLAY")
                icon:SetSize(DEBUFF_SIZE, DEBUFF_SIZE)
                icon:SetPoint("LEFT", b, "RIGHT", 3 + (index - 1) * (DEBUFF_SIZE + DEBUFF_SPACING), 0)
                local okCooldown, cooldown = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
                if okCooldown and cooldown then
                    cooldown:SetAllPoints(icon)
                    cooldown:EnableMouse(false)
                    if type(cooldown.SetDrawSwipe) == "function" then cooldown:SetDrawSwipe(false) end
                    if type(cooldown.SetDrawEdge) == "function" then cooldown:SetDrawEdge(false) end
                    if type(cooldown.SetHideCountdownNumbers) == "function" then cooldown:SetHideCountdownNumbers(false) end
                    cooldown:Hide()
                    icon.cooldown = cooldown
                end
                icon:Hide()
                b.debuffs[index] = icon
            end
            b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetUnit(unit); GameTooltip:Show() end end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            b:Hide()
        end
    end)
    if not ok then for _, b in ipairs(made) do pcall(b.Hide, b) end; pcall(parent.Hide, parent); return false end
    root, buttons = parent, made
    return true
end
local function restoreNative()
    if not owned then return true end
    local frame, original = owned.frame, owned.parent
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok or not readable(parent) then return false end
    if parent == hider then
        if not pcall(frame.SetParent, frame, original) then return false end
        local verified, actual = pcall(frame.GetParent, frame)
        if not verified or not readable(actual) or actual ~= original then return false end
    end
    owned = nil
    return true
end
local function concealNative()
    local frame = _G.PartyFrame
    if not frame or type(frame.GetParent) ~= "function" or type(frame.SetParent) ~= "function" then return false end
    local ok, parent, forbidden, alpha = pcall(function()
        return frame:GetParent(), type(frame.IsForbidden) == "function" and frame:IsForbidden(), frame:GetAlpha()
    end)
    if not ok or not readable(parent) or not readable(forbidden) or forbidden or not readable(alpha) or alpha ~= 1 then return false end
    if owned then return owned.frame == frame and parent == hider end
    if parent ~= UIParent then return false end
    if not hider then hider = CreateFrame("Frame", nil, UIParent); hider:Hide() end
    if not pcall(frame.SetParent, frame, hider) then return false end
    local verified, actual = pcall(frame.GetParent, frame)
    if not verified or not readable(actual) then owned = {frame=frame, parent=parent}; return false end
    if actual ~= hider then return false end
    owned = {frame=frame, parent=parent}
    return true
end
local active = false
local function closeMoveHandle()
    if moveHandle and unlocked then
        if dragging then moveHandle:StopMovingOrSizing(); dragging = false end
        unlocked = false; moveHandle:Hide()
    end
end
local function setting()
    local value, ok = get(character, "partyFrames")
    if not ok or (value ~= nil and type(value) ~= "boolean") then return nil end
    return value ~= false
end
local function deactivate()
    if active then
        for _, b in ipairs(buttons) do
            if not pcall(UnregisterStateDriver, b, "visibility") or not pcall(b.Hide, b) then return false end
        end
        active = false
    end
    return restoreNative()
end
local function synchronize()
    if combat() then pending = true; return false end
    pending = false
    if root and positionPending then
        positionPending = not positionRoot(root)
    end
    local inRaid, inPvp = raid(), pvpInstance()
    if not current() or setting() ~= true or not hudEnabled() or inRaid ~= false or inPvp ~= false or not interfacesReady() then
        closeMoveHandle()
        if not deactivate() then pending = true; return false end
        return true
    end
    if not create() or not concealNative() then deactivate(); pending = true; return false end
    if not active then
        local registered = {}
        for _, b in ipairs(buttons) do
            local condition = b.unitToken == "player" and "[group:raid] hide; [group:party] show; hide"
                or "[group:raid] hide; [@" .. b.unitToken .. ",exists] show; hide"
            local ok = pcall(RegisterStateDriver, b, "visibility", condition)
            if not ok then
                for _, done in ipairs(registered) do pcall(UnregisterStateDriver, done, "visibility"); pcall(done.Hide, done) end
                restoreNative(); pending = true; return false
            end
            registered[#registered+1] = b
        end
        active = true
    end
    refresh()
    return true
end
function toolbox.syncPartyFrames() return synchronize() end
function toolbox.getPartyFramesEnabled()
    if not current() then return nil, "小队框体不可用" end
    local value = setting()
    if value == nil then return nil, "小队框体不可用" end
    return value
end
function toolbox.setPartyFramesEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "小队框体不可用" end
    if combat() then return false, "请在脱战后调整" end
    local previous, settingOK = get(character, "partyFrames")
    if not settingOK or (previous ~= nil and type(previous) ~= "boolean") then return false, "小队框体不可用" end
    if not pcall(function() character.partyFrames = value end) then return false, "设置不可保存" end
    if not synchronize() then
        pcall(function() character.partyFrames = previous end); synchronize()
        return false, "小队框体暂不可用"
    end
    if not value then closeMoveHandle() end
    notify()
    return true
end

-- This separate handle can be dragged safely without moving protected unit
-- buttons mid-combat. The real frame is repositioned only on an out-of-combat drop.
alignMoveHandle = function()
    if not moveHandle or not root then return end
    local width, height = call(UIParent.GetWidth, UIParent), call(UIParent.GetHeight, UIParent)
    if not finite(width) or width <= 0 or not finite(height) or height <= 0 then return end
    local x, y = positionFractions()
    moveHandle:ClearAllPoints()
    moveHandle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", width * x, -height * y)
end
local function createMoveHandle()
    if moveHandle then return end
    local handle = CreateFrame("Button", nil, UIParent)
    handle:SetSize(PANEL_WIDTH, ROW_HEIGHT)
    handle:SetFrameStrata("DIALOG")
    handle:SetMovable(true); handle:SetClampedToScreen(true); handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local background = handle:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture(MEDIA .. "BarPanel.tga")
    for i = 1, 4 do
        local preview = handle:CreateTexture(nil, "BACKGROUND")
        preview:SetSize(PANEL_WIDTH, ROW_HEIGHT)
        preview:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, -ROW_PITCH * i)
        preview:SetTexture(MEDIA .. "BarPanel.tga")
        preview:SetAlpha(0.35)
    end
    local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText("拖动小队框体")
    handle:SetScript("OnDragStart", function(self)
        if combat() or not unlocked then return end
        dragging = true; self:StartMoving()
    end)
    handle:SetScript("OnDragStop", function(self)
        if not dragging then return end
        self:StopMovingOrSizing(); dragging = false
        if combat() or not unlocked or not current() or not root then alignMoveHandle(); return end
        local width, height = call(UIParent.GetWidth, UIParent), call(UIParent.GetHeight, UIParent)
        local left, top = call(self.GetLeft, self), call(self.GetTop, self)
        local uiLeft, uiTop = call(UIParent.GetLeft, UIParent), call(UIParent.GetTop, UIParent)
        if not finite(width) or width <= 0 or not finite(height) or height <= 0
            or not finite(left) or not finite(top) or not finite(uiLeft) or not finite(uiTop) then
            alignMoveHandle(); return
        end
        local x, y = (left - uiLeft) / width, (uiTop - top) / height
        if x < 0 or x > 1 or y < 0 or y > 1 then alignMoveHandle(); return end
        local previous, valid = get(character, "partyPosition")
        if not valid or (previous ~= nil and not tableOK(previous)) then alignMoveHandle(); return end
        local saved = pcall(function() character.partyPosition = {x = x, y = y} end)
        if not saved then alignMoveHandle(); return end
        local ok, positioned = pcall(positionRoot, root)
        if not ok or not positioned then
            pcall(function() character.partyPosition = previous end)
            pcall(positionRoot, root)
        end
        alignMoveHandle()
    end)
    handle:Hide()
    moveHandle = handle
end
function toolbox.getPartyFramesUnlocked() return unlocked end
function toolbox.setPartyFramesUnlocked(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if combat() then return false, "请在脱战后调整" end
    if not current() then return false, "小队框体不可用" end
    if value and (setting() ~= true or not hudEnabled()) then return false, "请先启用 HUD 和小队框体" end
    if value and (raid() ~= false or pvpInstance() ~= false) then return false, "团队或战场中无法调整小队框体" end
    if value and not create() then return false, "小队框体暂不可用" end
    createMoveHandle()
    if dragging then moveHandle:StopMovingOrSizing(); dragging = false end
    unlocked = value
    if value then alignMoveHandle(); moveHandle:Show() else moveHandle:Hide() end
    notify()
    return true
end

-- Some client events identify a party member by an alias such as "target".
-- Resolve only through the client's own unit identity check; inaccessible or
-- unknown identities do not trigger an inferred match.
local function isPartyEventUnit(unit)
    if not readable(unit) or type(unit) ~= "string" then return false end
    if unit == "player" or unit:match("^party[1-4]$") then return true end
    if type(UnitIsUnit) ~= "function" then return false end
    for _, button in ipairs(buttons) do
        local matches = call(UnitIsUnit, unit, button.unitToken)
        if readable(matches) and matches == true then return true end
    end
    return false
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "ADDON_LOADED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    "UNIT_NAME_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_AURA", "PLAYER_FLAGS_CHANGED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then initialize(); synchronize(); notify()
    elseif event == "PLAYER_REGEN_ENABLED" then if pending then synchronize() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if unlocked then closeMoveHandle(); notify() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if root then
            if combat() then positionPending = true; pending = true
            else
                positionPending = not positionRoot(root)
                if unlocked and alignMoveHandle then alignMoveHandle() end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "ADDON_LOADED" then
        synchronize()
        if combat() and active then refresh() end
    elseif isPartyEventUnit(unit) then refresh()
    elseif event == "PLAYER_FLAGS_CHANGED" then refresh() end
end)
