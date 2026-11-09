-- A small target hint based only on information exposed by the game client.
local driver = CreateFrame("Frame")
local announced = {}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function tigerUIShowsQuestPlates()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(isLoaded) ~= "function" then return false end
    local ok, loaded = pcall(isLoaded, "TigerUI")
    if not ok or not readable(loaded) or not loaded then return false end
    return type(TigerUIDB) == "table" and TigerUIDB.questPlates == true
end

local function checkTarget()
    if tigerUIShowsQuestPlates() or not C_QuestLog
        or type(C_QuestLog.UnitIsRelatedToActiveQuest) ~= "function" then return end
    local exists, player, hostile = UnitExists("target"), UnitIsPlayer("target"), UnitCanAttack("player", "target")
    if not readable(exists) or not readable(player) or not readable(hostile)
        or not exists or player or not hostile then return end

    local guid = UnitGUID("target")
    if not readable(guid) or type(guid) ~= "string" or announced[guid] then return end
    local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, "target")
    if not ok or not readable(related) or not related then return end
    announced[guid] = true
    print("|cffffd27f升级工具箱|r 当前目标与进行中的任务有关。")
end

driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:SetScript("OnEvent", checkTarget)
