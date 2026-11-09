-- Virtual collection only. No game item, trade, chat or external action is created.
local ADDON, toolbox = ...
local driver = CreateFrame("Frame")
local state, stateError
local trackingIssue = false
local seen, recent, recentIndex, recentCount = {}, {}, 1, 0
local MAX_SEEN = 4096
local MAX_INTEGER = 9007199254740991
local DRAW_COST = 20
local validTiers = {common = true, rare = true, epic = true, legendary = true}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function integer(value, max)
    return type(value) == "number" and value >= 0 and value <= (max or MAX_INTEGER)
        and value == math.floor(value)
end

local function validID(id)
    return (type(id) == "number" and integer(id) and id > 0)
        or (type(id) == "string" and #id > 0 and #id <= 128)
end

local function changed()
    if type(toolbox.onLuckChanged) == "function" then pcall(toolbox.onLuckChanged) end
end

local function validate(data)
    if type(data) ~= "table" or data.version ~= 1 or type(data.collection) ~= "table"
        or not integer(data.shards) or not integer(data.rolls) or not integer(data.kills)
        or not integer(data.epicDry, 10) or not integer(data.legendaryDry, 50)
        or (data.lastID ~= nil and not validID(data.lastID)) then return false end
    for id, count in pairs(data.collection) do
        if type(id) ~= "string" or not validID(id) or not integer(count) or count == 0 then return false end
    end
    return true
end

local function initialize()
    if TigerioForeverToolboxDB == nil then TigerioForeverToolboxDB = {} end
    if type(TigerioForeverToolboxDB) ~= "table" then
        state, stateError = nil, "工具箱数据不可用，收藏功能已暂停。"
        return
    end
    if TigerioForeverToolboxDB.luck == nil then
        TigerioForeverToolboxDB.luck = {
            version = 1, shards = 0, rolls = 0, kills = 0,
            epicDry = 0, legendaryDry = 0, collection = {},
        }
    end
    local saved = TigerioForeverToolboxDB.luck
    if not validate(saved) then
        state, stateError = nil, "收藏数据异常或版本不兼容，已暂停且未更改数据。"
        return
    end
    state, stateError = saved, nil
end

local function currentState()
    if not state or not validate(state) then return nil, stateError or "收藏数据不可用，已暂停。" end
    if type(TigerioForeverToolboxDB) ~= "table" or TigerioForeverToolboxDB.luck ~= state then
        return nil, "收藏数据已变化，请重新加载界面。"
    end
    return state
end

local function randomInt(max)
    if type(math.random) ~= "function" then return nil end
    local ok, value = pcall(math.random, max)
    if not ok or not integer(value, max) or value < 1 then return nil end
    return value
end

local function catalogPools()
    if type(toolbox.luckCatalog) ~= "table" then return nil end
    local pools = {common = {}, rare = {}, epic = {}, legendary = {}}
    local ids = {}
    for _, entry in ipairs(toolbox.luckCatalog) do
        if type(entry) ~= "table" or not validID(entry.id) or type(entry.name) ~= "string"
            or entry.name == "" or not validTiers[entry.tier] then return nil end
        local key = tostring(entry.id)
        if ids[key] then return nil end
        ids[key] = true
        pools[entry.tier][#pools[entry.tier] + 1] = entry
    end
    for tier in pairs(validTiers) do if #pools[tier] == 0 then return nil end end
    return pools
end

-- Callers receive a snapshot and cannot accidentally mutate the stored collection.
function toolbox.luckState()
    local saved, err = currentState()
    if not saved then return nil, err end
    local collection = {}
    for id, count in pairs(saved.collection) do collection[tostring(id)] = count end
    return {
        shards = saved.shards, rolls = saved.rolls, kills = saved.kills,
        epicDry = saved.epicDry, legendaryDry = saved.legendaryDry,
        collection = collection, lastID = saved.lastID,
        trackingAvailable = driver.trackingAvailable, trackingIssue = trackingIssue,
    }
end

function toolbox.luckDraw()
    local saved, err = currentState()
    if not saved then return false, err end
    if saved.shards < DRAW_COST then return false, "碎片不足，需要 20 个碎片。" end
    if saved.rolls >= MAX_INTEGER then return false, "抽取次数已达记录上限。" end
    local pools = catalogPools()
    if not pools then return false, "收藏图鉴不可用或数据异常，未消耗碎片。" end

    local tier
    if saved.legendaryDry >= 50 then
        tier = "legendary"
    elseif saved.epicDry >= 10 then
        local value = randomInt(5)
        if not value then return false, "随机数不可用，未消耗碎片。" end
        tier = value == 5 and "legendary" or "epic"
    else
        local value = randomInt(100)
        if not value then return false, "随机数不可用，未消耗碎片。" end
        if value <= 70 then tier = "common"
        elseif value <= 95 then tier = "rare"
        elseif value <= 99 then tier = "epic"
        else tier = "legendary" end
    end
    local choice = randomInt(#pools[tier])
    if not choice then return false, "随机数不可用，未消耗碎片。" end
    local entry = pools[tier][choice]
    local key = tostring(entry.id)
    local previous = saved.collection[key] or 0
    if not integer(previous) or previous >= MAX_INTEGER then return false, "收藏次数异常，未消耗碎片。" end

    -- All validation and random choices precede this update.
    saved.shards = saved.shards - DRAW_COST
    saved.rolls = saved.rolls + 1
    saved.collection[key] = previous + 1
    saved.lastID = key
    saved.epicDry = (tier == "epic" or tier == "legendary") and 0 or math.min(10, saved.epicDry + 1)
    saved.legendaryDry = tier == "legendary" and 0 or math.min(50, saved.legendaryDry + 1)
    changed()
    return true, {id = entry.id, name = entry.name, tier = tier, isNew = previous == 0,
        count = previous + 1}
end

local function unitGUID(unit)
    if type(UnitGUID) ~= "function" then return nil, false end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not readable(guid) then return nil, false end
    if guid ~= nil and type(guid) ~= "string" then return nil, false end
    return guid, true
end

local function remember(guid)
    if seen[guid] then return false end
    if recentCount == MAX_SEEN then
        seen[recent[recentIndex]] = nil
    else
        recentCount = recentCount + 1
    end
    recent[recentIndex], seen[guid] = guid, true
    recentIndex = recentIndex % MAX_SEEN + 1
    return true
end

local function recordKill(attacker, target)
    local saved = currentState()
    if not saved then return end
    if not readable(attacker) or not readable(target) then trackingIssue = true; changed(); return end
    if type(attacker) ~= "string" or type(target) ~= "string" then trackingIssue = true; changed(); return end
    if not target:match("^Creature%-") then return end
    local player, playerOK = unitGUID("player")
    local pet, petOK = unitGUID("pet")
    if not playerOK or not player then trackingIssue = true; changed(); return end
    if attacker ~= player then
        if not petOK then trackingIssue = true; changed(); return end
        if not pet or attacker ~= pet then return end
    end
    if not remember(target) or saved.kills >= MAX_INTEGER then return end
    local roll = randomInt(100)
    if not roll then trackingIssue = true; changed(); return end
    local fragments = 0
    if roll <= 25 then
        fragments = randomInt(2)
        if not fragments then trackingIssue = true; changed(); return end
    end
    if saved.shards > MAX_INTEGER - fragments then trackingIssue = true; changed(); return end
    local wasReady = saved.shards >= DRAW_COST
    saved.kills = saved.kills + 1
    saved.shards = saved.shards + fragments
    if not wasReady and saved.shards >= DRAW_COST and type(print) == "function" then
        print("|cffffd100升级工具箱|r 碎片已足够，可以打开虚拟收藏图鉴抽取一次。")
    end
    changed()
end

local ok, registered = pcall(driver.RegisterEvent, driver, "PARTY_KILL")
driver.trackingAvailable = ok and registered ~= false
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(_, event, first, second)
    if event == "ADDON_LOADED" and first == ADDON then
        initialize()
        changed()
    elseif event == "PLAYER_LOGIN" then
        if not state then initialize() end
        changed()
    elseif event == "PARTY_KILL" then
        local success = pcall(recordKill, first, second)
        if not success then trackingIssue = true; changed() end
    end
end)
