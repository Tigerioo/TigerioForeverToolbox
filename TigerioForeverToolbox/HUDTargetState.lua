-- Lightweight target details; all unit data remains client-provided.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
-- Match the party debuff icons and center them on the 48-pixel health panels.
local DEBUFF_SIZE, DEBUFF_SPACING, DEBUFF_COUNT = 32, 4, 4
local DEBUFF_TOP_OFFSET = (DEBUFF_SIZE - 48) / 2

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil, nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil, nil end
    return a, b
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, result = pcall(canaccesstable, value)
    return ok and readable(result) and result == true
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function createAuraCooldown(parent, relative)
    local cooldown = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cooldown:SetAllPoints(relative)
    if type(cooldown.SetDrawEdge) == "function" then cooldown:SetDrawEdge(false) end
    if type(cooldown.SetDrawSwipe) == "function" then cooldown:SetDrawSwipe(false) end
    if type(cooldown.SetHideCountdownNumbers) == "function" then cooldown:SetHideCountdownNumbers(false) end
    cooldown:EnableMouse(false)
    return cooldown
end

local function clearAuraCooldown(cooldown)
    if type(cooldown.Clear) == "function" then pcall(cooldown.Clear, cooldown)
    elseif type(cooldown.SetCooldown) == "function" then pcall(cooldown.SetCooldown, cooldown, 0, 0) end
end

local function updateAuraCooldown(cooldown, unit, aura)
    clearAuraCooldown(cooldown)
    local id = field(aura, "auraInstanceID")
    if finite(id) and C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function"
        and type(cooldown.SetCooldownFromDurationObject) == "function" then
        local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
        if ok and (not readable(duration) or duration ~= nil)
            and pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration) then return end
    end
    local duration, expires = field(aura, "duration"), field(aura, "expirationTime")
    if finite(duration) and duration > 0 and finite(expires) and expires > 0
        and type(cooldown.SetCooldown) == "function" then
        pcall(cooldown.SetCooldown, cooldown, expires - duration, duration)
    end
end

function toolbox.attachHUDTargetState(hud)
    if not hud or not hud.target or not hud.player then return false, "单位框不可用" end
    if hud.targetState then return true end
    if type(UnitExists) ~= "function" or type(UnitLevel) ~= "function"
        or (type(UnitFullName) ~= "function" and type(UnitName) ~= "function") then
        return false, "目标信息接口不可用"
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE", "UNIT_LEVEL"}) do
        local ok, result = pcall(events.RegisterEvent, events, event)
        if not ok or result == false then
            if type(events.UnregisterAllEvents) == "function" then pcall(events.UnregisterAllEvents, events) end
            return false, "目标信息事件不可用"
        end
    end
    local auraEventsAvailable = false
    for _, event in ipairs({"UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_AURA", "PLAYER_REGEN_ENABLED"}) do
        local ok, result = pcall(events.RegisterEvent, events, event)
        if event == "UNIT_AURA" then auraEventsAvailable = ok and result ~= false end
    end
    local state = CreateFrame("Frame", nil, hud)
    state:SetAllPoints(hud)
    state:EnableMouse(false)
    local text = state:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", hud.target, "BOTTOMLEFT", 0, -4)
    text:SetWidth(280)
    text:SetJustifyH("LEFT")
    if type(text.SetWordWrap) == "function" then text:SetWordWrap(false) end
    if type(text.SetMaxLines) == "function" then text:SetMaxLines(1) end
    text:SetText("")
    state.text = text
    local targetPanel = hud.target:GetParent()
    if not targetPanel then return false, "目标框不可用" end
    local icons = {}
    for i = 1, 4 do
        local image = state:CreateTexture(nil, "ARTWORK")
        image:SetSize(14, 14)
        image:SetPoint("TOPLEFT", targetPanel, "BOTTOMLEFT", 2 + (i - 1) * 20, -2)
        local border = state:CreateTexture(nil, "OVERLAY")
        border:SetSize(18, 18)
        border:SetPoint("TOPLEFT", targetPanel, "BOTTOMLEFT", (i - 1) * 20, 0)
        border:SetTexture(MEDIA .. "SlotFrame.tga")
        image:Hide()
        border:Hide()
        icons[i] = {image = image, border = border}
    end
    state.icons = icons
    local debuffs = {player = {}, target = {}}
    for _, unit in ipairs({"player", "target"}) do
        for i = 1, DEBUFF_COUNT do
            local border = state:CreateTexture(nil, "OVERLAY")
            border:SetSize(DEBUFF_SIZE, DEBUFF_SIZE)
            local side = unit == "player" and "TOPRIGHT" or "TOPLEFT"
            local relative = unit == "player" and "TOPLEFT" or "TOPRIGHT"
            local offset = 8 + (i - 1) * (DEBUFF_SIZE + DEBUFF_SPACING)
            border:SetPoint(side, hud[unit], relative, unit == "player" and -offset or offset, DEBUFF_TOP_OFFSET)
            border:SetTexture(MEDIA .. "SlotFrame.tga")
            local image = state:CreateTexture(nil, "ARTWORK")
            image:SetPoint("TOPLEFT", border, "TOPLEFT", 3, -3)
            image:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -3, 3)
            if type(image.SetTexCoord) == "function" then image:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            local cooldown = createAuraCooldown(state, image)
            image:Hide()
            border:Hide()
            cooldown:Hide()
            debuffs[unit][i] = {image = image, border = border, cooldown = cooldown}
        end
    end
    state.debuffs = debuffs
    local targetAuraContainer
    local targetAuraSetupAttempted = false
    local function setupTargetAuraContainer()
        if targetAuraSetupAttempted or targetAuraContainer then return end
        if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
        targetAuraSetupAttempted = true
        -- This Blizzard module may not be loaded yet on older clients. Failure
        -- is harmless: creating the template below will fall back if unavailable.
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function"
            and type(C_AddOns.LoadAddOn) == "function" then
            local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_AuraContainer")
            if ok and not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
        end
        -- Build behind a hidden parent so a failed setup cannot overlap the fallback.
        local holder = CreateFrame("Frame", nil, state)
        holder:Hide()
        holder:SetAllPoints(state)
        local initialized = false
        local ok, container = pcall(function()
            local frame = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
            assert(type(frame.AddAuraGroup) == "function" and type(frame.SetUnit) == "function"
                and type(frame.SetEnabled) == "function")
            frame:SetPoint("TOPLEFT", hud.target, "TOPRIGHT", 8, DEBUFF_TOP_OFFSET)
            frame:SetFlowLayoutAnchorPoint("TOPLEFT")
            frame:SetFlowLayoutGrowthDirection(1, -1)
            frame:SetFlowLayoutMaximumLineSize(DEBUFF_COUNT * DEBUFF_SIZE + (DEBUFF_COUNT - 1) * DEBUFF_SPACING)
            frame:AddAuraGroup("debuffs", "HARMFUL", {
                maxFrameCount = DEBUFF_COUNT,
                layout = {elementWidth = DEBUFF_SIZE, elementHeight = DEBUFF_SIZE, elementSpacing = DEBUFF_SPACING},
                initializeFrame = function(button)
                    button:SetSize(DEBUFF_SIZE, DEBUFF_SIZE)
                    button:EnableMouse(false)
                    local image = button:CreateTexture(nil, "ARTWORK")
                    image:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
                    image:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
                    image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local border = button:CreateTexture(nil, "OVERLAY")
                    border:SetAllPoints(button)
                    border:SetTexture(MEDIA .. "SlotFrame.tga")
                    button:SetIcon(image)
                    if type(button.SetDurationCooldown) == "function" then
                        -- A timer incompatibility must not disable the target aura container.
                        pcall(function()
                            local cooldown = createAuraCooldown(button, image)
                            button:SetDurationCooldown(cooldown)
                        end)
                    end
                    initialized = true
                end,
            })
            assert(initialized)
            frame:SetUnit("target")
            frame:SetEnabled(true)
            return frame
        end)
        if ok then
            targetAuraContainer = container
            for _, icon in ipairs(debuffs.target) do
                icon.image:Hide(); icon.border:Hide(); clearAuraCooldown(icon.cooldown); icon.cooldown:Hide()
            end
            holder:Show()
        end
    end
    local auraStatus = state:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    auraStatus:SetPoint("LEFT", targetPanel, "BOTTOMLEFT", 80, -9)
    auraStatus:SetText("")
    state.auraStatus = auraStatus

    local function clearAuras()
        for _, icon in ipairs(icons) do icon.image:Hide(); icon.border:Hide() end
        auraStatus:SetText("")
    end

    local function updateDebuffs(unit)
        local slots = debuffs[unit]
        for _, icon in ipairs(slots) do
            icon.image:Hide(); icon.border:Hide(); clearAuraCooldown(icon.cooldown); icon.cooldown:Hide()
        end
        if unit == "target" and targetAuraContainer then return end
        local exists = call(UnitExists, unit)
        if not readable(exists) or exists ~= true or not auraEventsAvailable
            or not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then return end
        for index = 1, #slots do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL")
            if not ok or not readable(aura) or aura == nil or not tableOK(aura) then break end
            local texture = field(aura, "icon")
            if (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
                slots[index].image:SetTexture(texture)
                slots[index].image:Show()
                slots[index].border:Show()
                updateAuraCooldown(slots[index].cooldown, unit, aura)
                slots[index].cooldown:Show()
            end
        end
    end

    local function updateAuras()
        clearAuras()
        if not auraEventsAvailable or not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then
            auraStatus:SetText("状态未知")
            return
        end
        local count, limited = 0, false
        for _, filter in ipairs({"HELPFUL"}) do
            for index = 1, 4 do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", index, filter)
                if not ok or not readable(aura) then limited = true; break end
                if aura == nil then break end
                if not tableOK(aura) then limited = true; break end
                local texture = field(aura, "icon")
                if (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
                    count = count + 1
                    icons[count].image:SetTexture(texture)
                    icons[count].image:Show()
                    icons[count].border:Show()
                else
                    limited = true
                end
            end
        end
        if limited then auraStatus:SetText(count == 0 and "状态未知" or "部分未知") end
    end

    local function update()
        local exists = call(UnitExists, "target")
        if not readable(exists) or exists ~= true then
            text:SetText("")
            clearAuras()
            updateDebuffs("target")
            return
        end
        updateAuras()
        updateDebuffs("target")
    end

    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then setupTargetAuraContainer() end
        -- The unit token stays "target" across target changes; ask the client
        -- container to rebuild rather than reading or hiding its restricted frames.
        if event == "PLAYER_TARGET_CHANGED" and targetAuraContainer then
            pcall(targetAuraContainer.UpdateAllAuras, targetAuraContainer)
        end
        if event == "UNIT_AURA" and readable(unit) and unit == "player" then
            updateDebuffs("player")
            return
        end
        if event:match("^UNIT_") and (not readable(unit) or unit ~= "target") then return end
        update()
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then updateDebuffs("player") end
    end)
    hud.targetState = state
    toolbox.onTargetServiceChanged = update
    setupTargetAuraContainer()
    update()
    updateDebuffs("player")
    return true
end
