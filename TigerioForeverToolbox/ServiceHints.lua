-- Service labels come only from the current target's client-provided title.
-- No NPC database or data from another addon is bundled.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local label = CreateFrame("Frame", nil, UIParent)
label:SetSize(160, 20)
label:SetPoint("TOP", TargetFrame or UIParent, "BOTTOM", 0, -4)
local text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
text:SetAllPoints()
label:Hide()

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

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function tigerUIHandlesServices()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(isLoaded) ~= "function" then return false end
    local ok, loaded = pcall(isLoaded, "TigerUI")
    if not ok or not readable(loaded) or not loaded then return false end
    return type(TigerUIDB) == "table" and readable(TigerUIDB.npcServiceIcons)
        and not not TigerUIDB.npcServiceIcons
end

local currentService

-- The HUD uses this to show the same verified service near its target details.
function toolbox.getTargetService()
    return currentService
end

local function hudOwnsLabel()
    if type(toolbox.onTargetServiceChanged) ~= "function" then return false end
    local hud = _G.TigerioForeverToolboxHUD
    if not hud then return false end
    local ok, shown = pcall(function() return hud:IsShown() end)
    return ok and readable(shown) and shown == true
end

local function findService()
    if tigerUIHandlesServices() or not C_TooltipInfo or not C_TooltipInfo.GetUnit then return end
    local exists, player, friendly = UnitExists("target"), UnitIsPlayer("target"), UnitIsFriend("player", "target")
    if not readable(exists) or not readable(player) or not readable(friendly)
        or not exists or player or not friendly then return end
    local ok, info = pcall(C_TooltipInfo.GetUnit, "target")
    if not ok or not readable(info) or type(info) ~= "table"
        or (canaccesstable and not canaccesstable(info)) then return end
    local lines = info.lines
    if not readable(lines) or type(lines) ~= "table"
        or (canaccesstable and not canaccesstable(lines)) then return end
    local line = lines[2]
    if not readable(line) or type(line) ~= "table"
        or (canaccesstable and not canaccesstable(line)) then return end
    local kind, title = line.type, line.leftText
    if not readable(kind) or not readable(title) or type(title) ~= "string" then return end
    local types = Enum and Enum.TooltipDataLineType
    if types and (kind == types.QuestTitle or kind == types.QuestObjective
        or kind == types.QuestPlayer or kind == types.UnitLevel) then return end
    title = title:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    title = title:gsub("^%s*<", ""):gsub(">%s*$", ""):match("^%s*(.-)%s*$")
    return titles[title]
end

local function refresh()
    label:Hide()
    local service = findService()
    if service then
        text:SetText("服务：" .. service)
        if not hudOwnsLabel() then label:Show() end
    end
    if currentService ~= service then
        currentService = service
        if type(toolbox.onTargetServiceChanged) == "function" then
            pcall(toolbox.onTargetServiceChanged)
        end
    end
end

local suppressed, hudSuppressed, elapsed = nil, nil, 0
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("UNIT_NAME_UPDATE")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_NAME_UPDATE" and unit ~= "target" then return end
    if event == "ADDON_LOADED" and unit ~= "TigerUI" then return end
    suppressed = tigerUIHandlesServices()
    hudSuppressed = hudOwnsLabel()
    refresh()
end)
-- Settings can be toggled in TigerUI without an addon or target event.
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 then return end
    elapsed = 0
    local current = tigerUIHandlesServices()
    local hudCurrent = hudOwnsLabel()
    if current ~= suppressed or hudCurrent ~= hudSuppressed then
        suppressed, hudSuppressed = current, hudCurrent
        refresh()
    end
end)
