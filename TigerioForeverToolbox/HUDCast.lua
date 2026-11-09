-- Player and target casting and channel progress for the standalone HUD.
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

local function castingInfo(fn, unit, isChannel)
    if type(fn) ~= "function" then return nil end
    local ok, name, displayName, icon, startMS, endMS, _, _, _, empowered = pcall(fn, unit)
    if not ok then return nil end
    -- A protected name can still be displayed by native controls; it must not
    -- be compared or converted in Lua. No name means no active cast.
    if readable(name) and (type(name) ~= "string" or name == "") then return nil end
    return {name = name, displayName = displayName, icon = icon, startMS = startMS, endMS = endMS,
        empowered = isChannel and readable(empowered) and empowered == true}
end

local function visibleText(label, info)
    local value = info.displayName
    if readable(value) and (type(value) ~= "string" or value == "") then value = info.name end
    local ok = pcall(label.SetText, label, value)
    if not ok then label:SetText("") end
end

local function nativeDuration(bar, unit, isChannel, empowered)
    if type(bar.SetTimerDuration) ~= "function" then return false end
    local fn = empowered and UnitEmpoweredChannelDuration or (isChannel and UnitChannelDuration or UnitCastingDuration)
    if type(fn) ~= "function" then return false end
    if isChannel and not empowered then
        local directions = Enum and Enum.StatusBarTimerDirection
        local interpolation = Enum and Enum.StatusBarInterpolation
        if not directions or not interpolation or directions.RemainingTime == nil or interpolation.Immediate == nil then return false end
        return pcall(function() bar:SetTimerDuration(fn(unit), interpolation.Immediate, directions.RemainingTime) end)
    end
    return pcall(function() bar:SetTimerDuration(fn(unit)) end)
end

local function fallbackDuration(bar, info, isChannel)
    if not finite(info.startMS) or not finite(info.endMS) or info.endMS <= info.startMS or type(GetTime) ~= "function" then
        return false
    end
    local startTime, endTime = info.startMS / 1000, info.endMS / 1000
    local ok = pcall(function()
        bar:SetMinMaxValues(0, endTime - startTime)
        local function update(self)
            local now = GetTime()
            if not finite(now) then self:SetScript("OnUpdate", nil); return end
            local value = isChannel and (endTime - now) or (now - startTime)
            self:SetValue(math.max(0, math.min(endTime - startTime, value)))
        end
        update(bar)
        bar:SetScript("OnUpdate", update)
    end)
    return ok
end

local function createCastFrame(hud, unit, x, y, width)
    local frame = CreateFrame("Frame", nil, hud)
    frame:SetAlpha(0)
    frame:SetSize(width, 23)
    frame:SetPoint("TOPLEFT", hud, "TOPLEFT", x, -y)
    frame:EnableMouse(false)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture(MEDIA .. "BarPanel.tga")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("LEFT", frame, "LEFT", 3, 0)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -2)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 2)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(MEDIA .. "BarFill.tga")
    bar:SetStatusBarColor(0.82, 0.59, 0.25, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("CENTER")
    name:SetWidth(width - 36)
    if type(name.SetWordWrap) == "function" then name:SetWordWrap(false) end
    if type(name.SetMaxLines) == "function" then name:SetMaxLines(1) end
    frame:SetAlpha(0)
    frame.bar, frame.icon, frame.spellName = bar, icon, name

    local function update()
        -- The target may disappear while events are still in flight. Never
        -- retain the previous target's cast when its identity is unavailable.
        if unit == "target" then
            local ok, exists = pcall(function() return UnitExists("target") end)
            if not ok or not readable(exists) or not exists then
                bar:SetScript("OnUpdate", nil)
                frame:SetAlpha(0)
                return
            end
        end
        local info = castingInfo(UnitCastingInfo, unit)
        local channel = false
        if not info then info, channel = castingInfo(UnitChannelInfo, unit, true), true end
        bar:SetScript("OnUpdate", nil)
        if not info then frame:SetAlpha(0); return end
        frame:SetAlpha(1)
        visibleText(name, info)
        -- Use a neutral placeholder if icon data is unavailable, without
        -- testing or formatting a possibly protected texture identifier.
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if not readable(info.icon) or type(info.icon) == "number" or type(info.icon) == "string" then
            pcall(icon.SetTexture, icon, info.icon)
        end
        if not nativeDuration(bar, unit, channel, info.empowered) and not fallbackDuration(bar, info, channel and not info.empowered) then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
        end
    end

    return frame, update
end

function toolbox.attachHUDCast(hud)
    if not hud then return false, "HUD 不可用" end
    if hud.tftCast then return true end
    if type(UnitCastingInfo) ~= "function" or type(UnitChannelInfo) ~= "function" then
        return false, "施法信息接口不可用"
    end
    local frame, update = createCastFrame(hud, "player", 15, 116, 286)
    local events = CreateFrame("Frame")
    local registered = {}
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
        "UNIT_SPELLCAST_EMPOWER_STOP"}) do
        local ok, result = pcall(events.RegisterEvent, events, event)
        registered[event] = ok and readable(result) and result ~= false
    end
    if not registered.UNIT_SPELLCAST_START or not registered.UNIT_SPELLCAST_STOP
        or not registered.UNIT_SPELLCAST_CHANNEL_START or not registered.UNIT_SPELLCAST_CHANNEL_STOP then
        return false, "施法事件不可用"
    end
    local targetFrame, updateTarget
    local targetEventOK, targetEventResult = pcall(events.RegisterEvent, events, "PLAYER_TARGET_CHANGED")
    if targetEventOK and readable(targetEventResult) and targetEventResult ~= false then
        -- Mirror the player cast bar directly under the target health panel.
        local ok, target, targetUpdate = pcall(createCastFrame, hud, "target", 419, 116, 286)
        if ok and target and type(targetUpdate) == "function" then
            targetFrame, updateTarget = target, targetUpdate
            hud.tftTargetCast = targetFrame
        end
    end
    if not targetFrame then hud.tftTargetCastUnavailable = true end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            update()
            if updateTarget then updateTarget() end
        elseif event == "PLAYER_TARGET_CHANGED" then
            if targetFrame then
                targetFrame:SetAlpha(0)
                targetFrame.bar:SetScript("OnUpdate", nil)
                updateTarget()
            end
        elseif readable(unit) and unit == "player" then
            update()
        elseif readable(unit) and unit == "target" and updateTarget then
            updateTarget()
        else
            return
        end
        -- Unit cast data may settle on the next frame after a stop/start.
        if C_Timer and type(C_Timer.After) == "function" then
            if event == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(0, update)
                if updateTarget then C_Timer.After(0, updateTarget) end
            elseif event == "PLAYER_TARGET_CHANGED" or unit == "target" then
                if updateTarget then C_Timer.After(0, updateTarget) end
            else
                C_Timer.After(0, update)
            end
        end
    end)
    if type(hud.HookScript) == "function" then hud:HookScript("OnShow", function()
        update()
        if updateTarget then updateTarget() end
    end) end
    frame.events = events
    hud.tftCast = frame
    update()
    if updateTarget then updateTarget() end
    return true
end
