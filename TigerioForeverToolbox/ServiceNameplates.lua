-- Identify only explicit service titles provided by the client. No NPC database.
local driver = CreateFrame("Frame")
local active, labels = {}, {}
local elapsed, lastSuppressed = 0, nil

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function accessible(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, result = pcall(canaccesstable, value)
    return ok and readable(result) and result == true
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end

local function tigerActive()
    local loaded = call(C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded, "TigerUI")
    if not loaded or not accessible(TigerUIDB) then return false end
    return field(TigerUIDB, "npcServiceIcons") == true
end

local titles = {
    ["innkeeper"] = "旅店", ["旅店老板"] = "旅店", ["旅店店主"] = "旅店", ["旅館老闆"] = "旅店",
    ["banker"] = "银行", ["银行家"] = "银行", ["银行职员"] = "银行", ["銀行職員"] = "银行",
    ["flight master"] = "飞行", ["飞行管理员"] = "飞行", ["飛行管理員"] = "飞行",
    ["auctioneer"] = "拍卖", ["拍卖师"] = "拍卖", ["拍賣師"] = "拍卖",
    ["stable master"] = "兽栏", ["兽栏管理员"] = "兽栏", ["獸欄管理員"] = "兽栏",
    ["merchant"] = "商人", ["vendor"] = "商人", ["商人"] = "商人", ["商贩"] = "商人", ["商販"] = "商人",
    ["trainer"] = "训练师", ["训练师"] = "训练师", ["訓練師"] = "训练师",
    ["repair"] = "修理", ["修理"] = "修理", ["维修"] = "修理", ["維修"] = "修理",
}

local function serviceFor(unit)
    if not call(UnitExists, unit) or call(UnitIsPlayer, unit) ~= false
        or not call(UnitIsFriend, "player", unit) then return end
    local info = call(C_TooltipInfo and C_TooltipInfo.GetUnit, unit)
    if not accessible(info) then return end
    local lines = field(info, "lines")
    if not accessible(lines) then return end
    local line = field(lines, 2)
    if not accessible(line) then return end
    local kind, title = field(line, "type"), field(line, "leftText")
    if type(title) ~= "string" or kind == nil then return end
    local types = Enum and Enum.TooltipDataLineType
    if types and (kind == types.QuestTitle or kind == types.QuestObjective
        or kind == types.QuestPlayer or kind == types.UnitLevel) then return end
    title = title:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    title = title:gsub("^%s*<", ""):gsub(">%s*$", ""):match("^%s*(.-)%s*$")
    return titles[title]
end

local function hide(unit)
    local frame = labels[unit]
    if frame then pcall(frame.Hide, frame) end
end

local function inCombat()
    return call(InCombatLockdown) == true
end

local function refresh(unit)
    hide(unit)
    if not active[unit] or tigerActive() then return end
    -- The existing target-frame label handles the selected NPC.
    if call(UnitIsUnit, unit, "target") == true then return end
    local service = serviceFor(unit)
    if not service then return end
    local plate = call(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
    if not plate then return end
    if type(plate.IsForbidden) == "function" and call(plate.IsForbidden, plate) ~= false then return end
    local frame = labels[unit]
    -- Avoid creating or reanchoring UI during combat; removed units are hidden immediately.
    if inCombat() then return end
    if not frame then
        local ok, created = pcall(CreateFrame, "Frame", nil, UIParent)
        if not ok or not created then return end
        frame = created
        local okText, label = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalSmall")
        if not okText or not label then return end
        frame.text = label
        frame:SetSize(52, 16)
        label:SetAllPoints()
        labels[unit] = frame
    end
    local ok = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", plate, "LEFT", -5, 0)
        frame.text:SetText(service)
        frame:Show()
    end)
    if not ok then hide(unit) end
end

local function refreshAll()
    for unit in pairs(active) do refresh(unit) end
end

local function isNameplate(unit)
    return readable(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function discover()
    local plates = call(C_NamePlate and C_NamePlate.GetNamePlates)
    if not accessible(plates) then return end
    for _, plate in ipairs(plates) do
        local ok, unit = pcall(function()
            if type(plate.GetUnit) == "function" then return plate:GetUnit() end
            return plate.namePlateUnitToken
        end)
        if ok and isNameplate(unit) then active[unit] = true end
    end
end

for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE",
    "UNIT_FACTION", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if isNameplate(unit) then active[unit] = nil; hide(unit) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if isNameplate(unit) then active[unit] = true; refresh(unit) end
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_FACTION" then
        if isNameplate(unit) and active[unit] then refresh(unit) end
    elseif event == "ADDON_LOADED" then
        if readable(unit) and unit == "TigerUI" then refreshAll() end
    else
        if event == "PLAYER_ENTERING_WORLD" then discover() end
        refreshAll()
    end
end)
-- TigerUI permits changing its setting without emitting an event.
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 then return end
    elapsed = 0
    local suppressed = tigerActive()
    if lastSuppressed ~= suppressed then lastSuppressed = suppressed; refreshAll() end
end)
