-- Focus cast and aura details use the same visual language as the target HUD.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, accessible = pcall(canaccesstable, value)
    return ok and readable(accessible) and accessible == true
end

local function cooldown(parent, image)
    local frame = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    frame:SetAllPoints(image)
    frame:EnableMouse(false)
    if type(frame.SetDrawSwipe) == "function" then frame:SetDrawSwipe(false) end
    if type(frame.SetDrawEdge) == "function" then frame:SetDrawEdge(false) end
    if type(frame.SetHideCountdownNumbers) == "function" then frame:SetHideCountdownNumbers(false) end
    return frame
end

local function clearCooldown(frame)
    if type(frame.Clear) == "function" then pcall(frame.Clear, frame)
    elseif type(frame.SetCooldown) == "function" then pcall(frame.SetCooldown, frame, 0, 0) end
end

local function setCooldown(frame, aura)
    clearCooldown(frame)
    local id = field(aura, "auraInstanceID")
    if finite(id) and C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function"
        and type(frame.SetCooldownFromDurationObject) == "function" then
        local ok, duration = pcall(C_UnitAuras.GetAuraDuration, "focus", id)
        if ok and (not readable(duration) or duration ~= nil)
            and pcall(frame.SetCooldownFromDurationObject, frame, duration) then return end
    end
    local duration, expires = field(aura, "duration"), field(aura, "expirationTime")
    if finite(duration) and duration > 0 and finite(expires) and expires > 0
        and type(frame.SetCooldown) == "function" then
        pcall(frame.SetCooldown, frame, expires - duration, duration)
    end
end

local function focusExists()
    local ok, exists = pcall(UnitExists, "focus")
    return ok and readable(exists) and exists == true
end

local function castInfo(fn, channel)
    if type(fn) ~= "function" then return nil end
    local ok, name, displayName, icon, startMS, endMS, _, _, _, empowered = pcall(fn, "focus")
    if not ok or (readable(name) and (type(name) ~= "string" or name == "")) then return nil end
    return {name = name, displayName = displayName, icon = icon, startMS = startMS, endMS = endMS,
        empowered = channel and readable(empowered) and empowered == true}
end

local function nativeCastDuration(bar, isChannel, empowered)
    if type(bar.SetTimerDuration) ~= "function" then return false end
    local fn = empowered and UnitEmpoweredChannelDuration or (isChannel and UnitChannelDuration or UnitCastingDuration)
    if type(fn) ~= "function" then return false end
    if isChannel and not empowered then
        local directions, interpolation = Enum and Enum.StatusBarTimerDirection, Enum and Enum.StatusBarInterpolation
        if not directions or not interpolation or directions.RemainingTime == nil or interpolation.Immediate == nil then return false end
        return pcall(function() bar:SetTimerDuration(fn("focus"), interpolation.Immediate, directions.RemainingTime) end)
    end
    return pcall(function() bar:SetTimerDuration(fn("focus")) end)
end

local function fallbackCastDuration(bar, info, isChannel)
    if not finite(info.startMS) or not finite(info.endMS) or info.endMS <= info.startMS
        or type(GetTime) ~= "function" then return false end
    local startTime, endTime = info.startMS / 1000, info.endMS / 1000
    return pcall(function()
        bar:SetMinMaxValues(0, endTime - startTime)
        local function update(self)
            local now = GetTime()
            if not finite(now) then self:SetScript("OnUpdate", nil); return end
            local value = isChannel and endTime - now or now - startTime
            self:SetValue(math.max(0, math.min(endTime - startTime, value)))
        end
        update(bar)
        bar:SetScript("OnUpdate", update)
    end)
end

function toolbox.attachFocusDetails(panel)
    if not panel then return false, "焦点框体不可用" end
    if panel.tftFocusDetails then return true end
    local state = CreateFrame("Frame", nil, panel)
    state:SetAllPoints(panel)
    state:EnableMouse(false)

    local cast = CreateFrame("Frame", nil, state)
    cast:SetSize(286, 23)
    cast:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -2)
    cast:EnableMouse(false)
    local background = cast:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture(MEDIA .. "BarPanel.tga")
    local icon = cast:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19); icon:SetPoint("LEFT", cast, "LEFT", 3, 0)
    local bar = CreateFrame("StatusBar", nil, cast)
    bar:SetPoint("TOPLEFT", cast, "TOPLEFT", 24, -2)
    bar:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -3, 2)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(MEDIA .. "BarFill.tga"); bar:SetStatusBarColor(0.82, 0.59, 0.25, 1)
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local spellName = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellName:SetPoint("CENTER"); spellName:SetWidth(250)
    if type(spellName.SetWordWrap) == "function" then spellName:SetWordWrap(false) end
    if type(spellName.SetMaxLines) == "function" then spellName:SetMaxLines(1) end
    cast:SetAlpha(0)

    local function updateCast()
        bar:SetScript("OnUpdate", nil)
        if not focusExists() then cast:SetAlpha(0); return end
        local info, channel = castInfo(UnitCastingInfo, false), false
        if not info then info, channel = castInfo(UnitChannelInfo, true), true end
        if not info then cast:SetAlpha(0); return end
        cast:SetAlpha(1)
        local value = info.displayName
        if readable(value) and (type(value) ~= "string" or value == "") then value = info.name end
        if not pcall(spellName.SetText, spellName, value) then spellName:SetText("") end
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if not readable(info.icon) or type(info.icon) == "number" or type(info.icon) == "string" then
            pcall(icon.SetTexture, icon, info.icon)
        end
        if not nativeCastDuration(bar, channel, info.empowered)
            and not fallbackCastDuration(bar, info, channel and not info.empowered) then
            bar:SetMinMaxValues(0, 1); bar:SetValue(0)
        end
    end

    -- Prefer Blizzard's aura container for protected combat aura data. The
    -- hand-built fallback only uses values the client allows Lua to read.
    local groups = {
        {filter = "HARMFUL", key = "debuffs", size = 32, spacing = 4, slots = {}},
        {filter = "HELPFUL", key = "buffs", size = 32, spacing = 4, slots = {}},
    }
    for _, group in ipairs(groups) do
        for i = 1, 4 do
            local border = state:CreateTexture(nil, "OVERLAY")
            border:SetSize(group.size, group.size)
            if group.key == "debuffs" then
                border:SetPoint("LEFT", panel, "RIGHT", 8 + (i - 1) * (group.size + group.spacing), 0)
            else
                border:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", (i - 1) * (group.size + group.spacing), 3)
            end
            border:SetTexture(MEDIA .. "SlotFrame.tga")
            local image = state:CreateTexture(nil, "ARTWORK")
            image:SetPoint("TOPLEFT", border, "TOPLEFT", 3, -3)
            image:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -3, 3)
            image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local cd = cooldown(state, image)
            border:Hide(); image:Hide(); cd:Hide()
            group.slots[i] = {border = border, image = image, cooldown = cd}
        end
    end
    local containers, attempted = {}, false
    local function setupAuras()
        if attempted or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return end
        attempted = true
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" and type(C_AddOns.LoadAddOn) == "function" then
            local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_AuraContainer")
            if ok and not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
        end
        for _, group in ipairs(groups) do
            local holder = CreateFrame("Frame", nil, state)
            holder:SetAllPoints(state); holder:Hide()
            local ok, container = pcall(function()
                local frame = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
                assert(type(frame.AddAuraGroup) == "function" and type(frame.SetUnit) == "function" and type(frame.SetEnabled) == "function")
                if group.key == "debuffs" then frame:SetPoint("LEFT", panel, "RIGHT", 8, 0)
                else frame:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 3) end
                frame:SetFlowLayoutAnchorPoint("TOPLEFT"); frame:SetFlowLayoutGrowthDirection(1, -1)
                frame:SetFlowLayoutMaximumLineSize(4 * group.size + 3 * group.spacing)
                local initialized = false
                frame:AddAuraGroup(group.key, group.filter, {
                    maxFrameCount = 4,
                    layout = {elementWidth = group.size, elementHeight = group.size, elementSpacing = group.spacing},
                    initializeFrame = function(button)
                        button:SetSize(group.size, group.size); button:EnableMouse(false)
                        local image = button:CreateTexture(nil, "ARTWORK")
                        image:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
                        image:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
                        image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        local border = button:CreateTexture(nil, "OVERLAY")
                        border:SetAllPoints(button); border:SetTexture(MEDIA .. "SlotFrame.tga")
                        button:SetIcon(image)
                        local durationCooldown
                        if type(button.SetDurationCooldown) == "function" then
                            durationCooldown = cooldown(button, image)
                            pcall(button.SetDurationCooldown, button, durationCooldown)
                        end
                        if group.key == "buffs" and type(button.SetDurationText) == "function" then
                            -- The native aura container drives the timer itself, even
                            -- when combat makes the aura duration secret to Lua.
                            local textLayer = CreateFrame("Frame", nil, button)
                            textLayer:SetAllPoints(button); textLayer:EnableMouse(false)
                            if durationCooldown then textLayer:SetFrameLevel(durationCooldown:GetFrameLevel() + 1) end
                            local durationText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                            durationText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
                            local ok = pcall(button.SetDurationText, button, durationText, {})
                            if ok and durationCooldown and type(durationCooldown.SetHideCountdownNumbers) == "function" then
                                durationCooldown:SetHideCountdownNumbers(true)
                            elseif not ok then
                                durationText:Hide()
                            end
                        end
                        initialized = true
                    end,
                })
                assert(initialized)
                frame:SetUnit("focus"); frame:SetEnabled(true)
                return frame
            end)
            if ok and container then containers[group.key] = container; holder:Show() end
        end
    end
    local function updateAuras()
        local exists = focusExists()
        for _, group in ipairs(groups) do
            for _, slot in ipairs(group.slots) do
                slot.image:Hide(); slot.border:Hide(); clearCooldown(slot.cooldown); slot.cooldown:Hide()
            end
            if exists and not containers[group.key] and C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
                for i, slot in ipairs(group.slots) do
                    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "focus", i, group.filter)
                    if not ok or not tableOK(aura) then break end
                    local texture = field(aura, "icon")
                    if (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
                        slot.image:SetTexture(texture); slot.image:Show(); slot.border:Show()
                        setCooldown(slot.cooldown, aura); slot.cooldown:Show()
                    end
                end
            end
        end
    end

    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED", "UNIT_AURA",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP"}) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event, unit)
        if not panel:IsShown() then return end
        if event == "PLAYER_REGEN_ENABLED" then setupAuras() end
        if event == "PLAYER_FOCUS_CHANGED" then
            for _, container in pairs(containers) do pcall(container.UpdateAllAuras, container) end
        end
        if event:match("^UNIT_") and (not readable(unit) or unit ~= "focus") then return end
        if event == "UNIT_AURA" then updateAuras(); return end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_REGEN_ENABLED" then updateAuras() end
        updateCast()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() if panel:IsShown() then updateCast() end end)
        end
    end)
    if type(panel.HookScript) == "function" then panel:HookScript("OnShow", function()
        setupAuras(); updateAuras(); updateCast()
    end) end
    state.events, state.cast, state.groups = events, cast, groups
    panel.tftFocusDetails = state
    setupAuras(); updateAuras(); updateCast()
    return true
end
