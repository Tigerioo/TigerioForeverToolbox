-- Highlight confirmed hostile quest nameplates without changing their health colors.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, enabled
local units, overlays, owners = {}, setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local elapsed, lastSuppressed = 0, nil

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

local function accessible(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    return call(canaccesstable, value) == true
end

local function identity()
    local guid = call(UnitGUID, "player")
    if type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function initialize()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not accessible(db) or not guid then return false end
    local ok, entry = pcall(function()
        if db.globalUI == nil then db.globalUI = {version = 1, characters = {}} end
        local data = db.globalUI
        if not accessible(data) or data.version ~= 1 or not accessible(data.characters) then return nil end
        if data.characters[guid] == nil then data.characters[guid] = {} end
        local record = data.characters[guid]
        if not accessible(record) or (record.questPlateColor ~= nil and type(record.questPlateColor) ~= "boolean") then return nil end
        return record
    end)
    if not ok or not entry then return false end
    character, enabled = entry, entry.questPlateColor ~= false
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    local ok, valid = pcall(function()
        return character and guid and accessible(db) and accessible(db.globalUI)
            and db.globalUI.version == 1 and accessible(db.globalUI.characters)
            and db.globalUI.characters[guid] == character
    end)
    return ok and valid == true
end

local function tigerActive()
    local check = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if call(check, "TigerUI") ~= true or not accessible(TigerUIDB) then return false end
    local ok, value = pcall(function() return TigerUIDB.questPlates end)
    return ok and readable(value) and value == true
end

local function hide(unit)
    local entry = units[unit]
    if not entry or not entry.bar then return end
    if owners[entry.bar] == unit then
        if entry.overlay then pcall(entry.overlay.Hide, entry.overlay) end
        owners[entry.bar] = nil
    end
    entry.bar, entry.overlay = nil, nil
end

local function refresh(unit)
    local entry = units[unit]
    if not entry then return end
    hide(unit)
    if not enabled or not current() or tigerActive() or not C_NamePlate or not C_QuestLog then return end
    if call(UnitExists, unit) ~= true or call(UnitIsPlayer, unit) ~= false
        or call(UnitCanAttack, "player", unit) ~= true
        or call(C_QuestLog.UnitIsRelatedToActiveQuest, unit) ~= true then return end
    local plate = call(C_NamePlate.GetNamePlateForUnit, unit)
    if not plate then return end
    local ok, bar, fill = pcall(function()
        if type(plate.IsForbidden) == "function" and plate:IsForbidden() then return nil end
        local container = plate.UnitFrame
        if not container then return nil end
        local candidate = container.healthBar or container.HealthBar
            or (container.HealthBarsContainer and container.HealthBarsContainer.healthBar)
        if not candidate or type(candidate.GetStatusBarTexture) ~= "function" then return nil end
        return candidate, candidate:GetStatusBarTexture()
    end)
    if not ok or not readable(bar) or not bar or not readable(fill) or not fill then return end
    local mark = overlays[bar]
    if not mark then
        local created, result = pcall(function()
            local texture = bar:CreateTexture(nil, "ARTWORK", nil, 7)
            texture:SetColorTexture(0.05, 0.8, 1, 0.8)
            texture:Hide()
            return texture
        end)
        if not created or not result then return end
        mark, overlays[bar] = result, result
    end
    local prior = owners[bar]
    if prior and prior ~= unit and units[prior] then units[prior].bar, units[prior].overlay = nil, nil end
    local shown = pcall(function() mark:ClearAllPoints(); mark:SetAllPoints(fill); mark:Show() end)
    if shown then entry.bar, entry.overlay, owners[bar] = bar, mark, unit
    else pcall(mark.Hide, mark); owners[bar] = nil end
end

local function refreshAll()
    for unit in pairs(units) do refresh(unit) end
end

local function discover()
    local list = call(C_NamePlate and C_NamePlate.GetNamePlates)
    if not accessible(list) then return end
    pcall(function()
        for _, plate in ipairs(list) do
            local unit = call(plate.GetUnit, plate) or plate.namePlateUnitToken
            if readable(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") then
                units[unit] = units[unit] or {}
            end
        end
    end)
end

function toolbox.getQuestPlateColorEnabled()
    if not current() then return nil, "任务怪着色暂不可用" end
    return enabled
end

function toolbox.setQuestPlateColorEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "任务怪着色暂不可用" end
    if type(InCombatLockdown) ~= "function" then return false, "战斗状态暂不可用" end
    local checked, locked = pcall(InCombatLockdown)
    if not checked or not readable(locked) or (locked ~= false and locked ~= nil) then return false, "请在脱战后调整" end
    local ok = pcall(function() character.questPlateColor = value end)
    if not ok then return false, "任务怪设置暂不可用" end
    enabled = value
    discover(); refreshAll()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do pcall(driver.RegisterEvent, driver, event) end

driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then initialize(); discover(); refreshAll()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if readable(unit) and type(unit) == "string" then hide(unit); units[unit] = nil end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not readable(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
        units[unit] = units[unit] or {}
        refresh(unit)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, function() if units[unit] then refresh(unit) end end)
        end
    else
        if not character then initialize() end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then discover() end
        refreshAll()
    end
    lastSuppressed = tigerActive()
end)

driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 then return end
    elapsed = 0
    local suppressed = tigerActive()
    if suppressed ~= lastSuppressed then lastSuppressed = suppressed; refreshAll() end
end)
