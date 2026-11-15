-- A secure, compact unit frame attached to the target health bar.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"

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

local function update(panel)
    local unit, bar = "targettarget", panel.bar
    local exists = call(UnitExists, unit)
    if readable(exists) and not exists then return end

    local name, second = call(UnitFullName, unit)
    if readable(name) and (type(name) ~= "string" or name == "") then name, second = call(UnitName, unit) end
    if not readable(name) then
        if not pcall(panel.name.SetText, panel.name, name) then panel.name:SetText("") end
    elseif type(name) == "string" and name ~= "" then
        local self = call(UnitIsUnit, unit, "player")
        local surname = call(GetCVarBool, "UnitSurnameOwn")
        if not (readable(self) and self == true and readable(surname) and surname == false)
            and readable(second) and type(second) == "string" and second ~= "" then
            name = name .. " " .. second
        end
        panel.name:SetText(name)
    else panel.name:SetText("") end

    local isPlayer = call(UnitIsPlayer, unit)
    local colored = false
    if readable(isPlayer) and isPlayer == true then
        local _, class = call(UnitClass, unit)
        local color = readable(class) and type(class) == "string" and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[class]
        if type(color) == "table" and finite(color.r) and finite(color.g) and finite(color.b) then
            bar:SetStatusBarColor(color.r, color.g, color.b, 1); colored = true
        end
    elseif readable(isPlayer) and type(UnitSelectionColor) == "function" then
        local ok, r, g, b = pcall(UnitSelectionColor, unit)
        if ok and pcall(bar.SetStatusBarColor, bar, r, g, b, 1) then colored = true end
    end
    if not colored then bar:SetStatusBarColor(0.55, 0.55, 0.55, 1) end

    local current, maximum = call(UnitHealth, unit), call(UnitHealthMax, unit)
    if not pcall(function() bar:SetMinMaxValues(0, maximum); bar:SetValue(current) end) then
        bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    end
    if finite(current) and finite(maximum) and maximum > 0 then
        panel.health:SetText(string.format("%d%%", math.max(0, math.min(100, math.floor(current / maximum * 100 + 0.5)))))
    else
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if not curve or type(UnitHealthPercent) ~= "function" or not pcall(function()
            panel.health:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
        end) then panel.health:SetText("") end
    end
end

function toolbox.attachTargetOfTarget(hud)
    if not hud or not hud.target or hud.targetOfTarget or type(RegisterUnitWatch) ~= "function" then return false end
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return false end

    local panel = CreateFrame("Button", nil, hud, "SecureUnitButtonTemplate")
    panel:SetSize(160, 30)
    -- The target cast bar occupies the space immediately below the main bar.
    panel:SetPoint("TOPRIGHT", hud.target, "BOTTOMRIGHT", 0, -56)
    panel:SetAttribute("unit", "targettarget")
    panel:SetAttribute("*type1", "target")
    panel:SetAttribute("*type2", "togglemenu")
    panel:RegisterForClicks("AnyUp")

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture(MEDIA .. "BarPanel.tga")
    local bar = CreateFrame("StatusBar", nil, panel)
    bar:SetSize(150, 22); bar:SetPoint("LEFT", panel, "LEFT", 5, 0)
    bar:SetStatusBarTexture(MEDIA .. "BarFill.tga")
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    panel.bar = bar
    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("RIGHT", bar, "RIGHT", -7, 0); name:SetWidth(95); name:SetJustifyH("RIGHT")
    if type(name.SetWordWrap) == "function" then name:SetWordWrap(false) end
    if type(name.SetMaxLines) == "function" then name:SetMaxLines(1) end
    name:SetShadowColor(0, 0, 0, 1); name:SetShadowOffset(1, -1)
    panel.name = name
    local health = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    health:SetPoint("LEFT", bar, "LEFT", 7, 0)
    health:SetShadowColor(0, 0, 0, 1); health:SetShadowOffset(1, -1)
    panel.health = health

    panel:HookScript("OnShow", function() update(panel) end)
    if not pcall(RegisterUnitWatch, panel) then panel:Hide(); return false end
    hud.targetOfTarget = panel

    -- Target-of-target health/name changes can lack reliable unit events.
    local events = CreateFrame("Frame", nil, hud)
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED"
            or (readable(unit) and ((event == "UNIT_TARGET" and unit == "target") or unit == "targettarget")) then
            update(panel)
        end
    end)
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.4 then
            elapsed = 0
            if panel:IsVisible() then update(panel) end
        end
    end)
    update(panel)
    return true
end
