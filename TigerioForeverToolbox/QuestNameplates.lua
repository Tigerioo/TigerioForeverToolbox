-- Mark only hostile nameplates the client confirms belong to an active quest.
-- This does not bundle quest data or modify another addon's settings.
local driver = CreateFrame("Frame")
local units, labels = {}, setmetatable({}, {__mode = "k"})
local lastSuppressed, elapsed

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end

local function tigerActive()
    local check = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if call(check, "TigerUI") ~= true then return false end
    if type(TigerUIDB) ~= "table" then return false end
    local ok, enabled = pcall(function() return TigerUIDB.questPlates end)
    return ok and readable(enabled) and enabled == true
end

local function hide(unit)
    local entry = units[unit]
    if entry and entry.label then pcall(entry.label.Hide, entry.label) end
end

local function marker(plate)
    local label = labels[plate]
    if label then return label end
    local ok, result = pcall(function()
        local created = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        created:SetPoint("BOTTOM", plate, "TOP", 0, 3)
        created:SetText("|cffffd27f任务|r")
        created:Hide()
        return created
    end)
    if ok and result then labels[plate] = result; return result end
end

local function refresh(unit)
    hide(unit)
    if tigerActive() or not C_NamePlate or not C_QuestLog then return end
    if call(UnitExists, unit) ~= true or call(UnitIsPlayer, unit) ~= false
        or call(UnitCanAttack, "player", unit) ~= true then return end
    if call(C_QuestLog.UnitIsRelatedToActiveQuest, unit) ~= true then return end
    local plate = call(C_NamePlate.GetNamePlateForUnit, unit)
    if not plate or not readable(plate) then return end
    local ok, forbidden = pcall(function() return plate.IsForbidden and plate:IsForbidden() end)
    if not ok or not readable(forbidden) or forbidden then return end
    local label = marker(plate)
    if not label then return end
    units[unit].label = label
    pcall(label.Show, label)
end

local function refreshAll()
    for unit in pairs(units) do refresh(unit) end
end

local function discover()
    if not C_NamePlate then return end
    local list = call(C_NamePlate.GetNamePlates)
    if type(list) ~= "table" then return end
    if type(canaccesstable) == "function" and call(canaccesstable, list) ~= true then return end
    pcall(function()
        for _, plate in ipairs(list) do
            local unit = call(plate.GetUnit, plate) or plate.namePlateUnitToken
            if readable(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") then
                units[unit] = units[unit] or {}
            end
        end
    end)
end

driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if readable(unit) and type(unit) == "string" then hide(unit); units[unit] = nil end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not readable(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
        units[unit] = units[unit] or {}
        refresh(unit)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, function() if units[unit] then refresh(unit) end end)
        end
    else
        if event == "PLAYER_ENTERING_WORLD" then discover() end
        refreshAll()
    end
    lastSuppressed = tigerActive()
end)
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = (elapsed or 0) + delta
    if elapsed < 0.5 then return end
    elapsed = 0
    local suppressed = tigerActive()
    if suppressed ~= lastSuppressed then lastSuppressed = suppressed; refreshAll() end
end)
