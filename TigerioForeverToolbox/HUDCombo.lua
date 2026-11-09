-- Target-bound combo points for the standalone HUD.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
local MAX_SLOTS, DEFAULT_SLOTS = 8, 5

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function slotCount()
    local maximum = call(GetMaxComboPoints, "player")
    if not readable(maximum) or type(maximum) ~= "number" or maximum < 1 or maximum > MAX_SLOTS then
        local powerType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
        maximum = call(UnitPowerMax, "player", powerType)
    end
    if not readable(maximum) or type(maximum) ~= "number" or maximum < 1 or maximum > MAX_SLOTS
        or maximum ~= math.floor(maximum) then return DEFAULT_SLOTS end
    return maximum
end

local function createSlot(parent, index, count)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(36, 36)
    slot:SetPoint("CENTER", parent, "CENTER", (index - (count + 1) / 2) * 46.5, 0)
    slot:EnableMouse(false)
    local empty = slot:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints()
    empty:SetTexture(MEDIA .. "OrbFill.tga")
    empty:SetVertexColor(0.16, 0.12, 0.08, 0.9)
    local bar = CreateFrame("StatusBar", nil, slot)
    bar:SetAllPoints()
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(MEDIA .. "OrbFill.tga")
    bar:SetStatusBarColor(0.95, 0.67, 0.24, 1)
    bar:SetMinMaxValues(index - 1, index)
    bar:SetValue(0)
    local rimFrame = CreateFrame("Frame", nil, slot)
    rimFrame:SetAllPoints()
    rimFrame:EnableMouse(false)
    if type(rimFrame.SetFrameLevel) == "function" and type(bar.GetFrameLevel) == "function" then
        rimFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
    end
    local rim = rimFrame:CreateTexture(nil, "OVERLAY")
    rim:SetAllPoints()
    rim:SetTexture(MEDIA .. "OrbRing.tga")
    return bar
end

function toolbox.attachHUDCombo(hud)
    if not hud or type(GetComboPoints) ~= "function" then return false end
    if hud.combo then return true end
    local container = CreateFrame("Frame", nil, hud)
    container:SetSize(390, 36)
    -- Above the HUD's unlock handle, so it remains usable while positioning.
    container:SetPoint("BOTTOM", hud, "TOP", 0, 30)
    container:EnableMouse(false)
    container:SetAlpha(0)
    local rows = {}
    for count = 1, MAX_SLOTS do
        local row = CreateFrame("Frame", nil, container)
        row:SetAllPoints()
        row:EnableMouse(false)
        row:SetAlpha(0)
        local bars = {}
        for i = 1, count do bars[i] = createSlot(row, i, count) end
        rows[count] = {frame = row, bars = bars}
    end
    hud.combo = container
    container.rows = rows
    local currentRow
    local function update()
        local _, class = call(UnitClass, "player")
        if not readable(class) or (class ~= "ROGUE" and class ~= "DRUID") then container:SetAlpha(0); return end
        if class == "DRUID" then
            local _, token = call(UnitPowerType, "player")
            if not readable(token) or token ~= "ENERGY" then container:SetAlpha(0); return end
        end
        local exists = call(UnitExists, "target")
        if not readable(exists) or exists ~= true then container:SetAlpha(0); return end
        local ok, points = pcall(GetComboPoints, "player", "target")
        if not ok or (readable(points) and (type(points) ~= "number" or points < 0)) then
            container:SetAlpha(0); return
        end
        local count = slotCount()
        local row = rows[count]
        for _, bar in ipairs(row.bars) do
            -- StatusBar accepts secret values without comparing them in Lua.
            if not pcall(bar.SetValue, bar, points) then container:SetAlpha(0); return end
        end
        if currentRow ~= count then
            if currentRow then rows[currentRow].frame:SetAlpha(0) end
            row.frame:SetAlpha(1)
            currentRow = count
        end
        container:SetAlpha(1)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED",
        "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event:match("^UNIT_") and readable(unit) and unit ~= "player" and unit ~= "target" then return end
        update()
    end)
    container.events = events
    update()
    return true
end
