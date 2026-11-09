-- Read only from the installed QuestieDB public contract. No database is bundled.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local index, scanning, provider, failure
local PAGE_SIZE = 100

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

local function available()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not call(loaded, "QuestieDB") then return nil, "未加载 QuestieDB；请启用兼容版本后重新查询。" end
    local db = LibQuestieDB
    if type(db) ~= "table" or not call(db.RequireContract, 4) or type(db.Quest) ~= "table"
        or type(db.Quest.GetAllIds) ~= "function" or type(db.Quest.zoneOrSort) ~= "function" then
        return nil, "QuestieDB 查询接口不可用或版本不兼容（需要契约 4）。"
    end
    return db
end

local function beginIndex(db)
    if scanning or (index and provider == db) then return end
    provider, index, failure = db, nil, nil
    scanning = coroutine.create(function()
        local ids = call(db.Quest.GetAllIds)
        if type(ids) ~= "table" then error("任务 ID 列表不可用") end
        local zones = {}
        for i, id in ipairs(ids) do
            local zone = call(db.Quest.zoneOrSort, id)
            if type(id) == "number" and type(zone) == "number" then
                if not zones[zone] then zones[zone] = {} end
                zones[zone][#zones[zone] + 1] = id
            end
            if i % PAGE_SIZE == 0 then coroutine.yield() end
        end
        index = zones
    end)
    driver:Show()
end

local function questState(id)
    local q = C_QuestLog
    if type(q) ~= "table" then return "状态未知" end
    local done = call(q.IsQuestFlaggedCompleted, id)
    if done == true then return "已交付" end
    local active = call(q.IsOnQuest, id)
    if active == true then
        if call(q.IsComplete, id) == true then return "已完成目标，待交付" end
        return "进行中"
    end
    if done == false and active == false then return "未接取或未记录" end
    return "状态未知"
end

local function title(db, id)
    return call(db.Quest.name, id) or ("任务 #" .. tostring(id))
end

local function prerequisiteLines(db, id)
    local lines, visited, count = {}, {}, 0
    local function walk(current, depth)
        if depth > 3 or count >= 18 then
            lines[#lines + 1] = string.rep("  ", depth) .. "…更多前置请查看 Questie"
            return
        end
        if visited[current] then
            lines[#lines + 1] = string.rep("  ", depth) .. "（前置链存在重复或循环）"
            return
        end
        visited[current] = true
        local groups = {
            {"前置组：全部需要（部分互斥任务可能可替代）", call(db.Quest.preQuestGroup, current)},
            {"前置任务：以下任选其一", call(db.Quest.preQuestSingle, current)},
        }
        for _, group in ipairs(groups) do
            if type(group[2]) == "table" and #group[2] > 0 then
                lines[#lines + 1] = string.rep("  ", depth) .. group[1]
                for _, raw in ipairs(group[2]) do
                    if count >= 18 then lines[#lines + 1] = "  …更多前置请查看 Questie"; break end
                    if type(raw) == "number" and raw ~= 0 then
                        local previous = math.abs(raw)
                        count = count + 1
                        local strict = raw < 0 and "（必须此任务）" or ""
                        lines[#lines + 1] = string.rep("  ", depth + 1) .. title(db, previous)
                            .. " #" .. previous .. strict .. " [" .. questState(previous) .. "]"
                        walk(previous, depth + 1)
                    end
                end
            end
        end
        visited[current] = nil
    end
    walk(id, 0)
    if #lines == 0 then lines[1] = "数据库未列出前置任务；不代表一定没有其他条件。" end
    return lines
end

local function location(db, id)
    local start = call(db.Quest.startedBy, id)
    if type(start) ~= "table" then return "接取来源：未知" end
    local results = {}
    local categories = {{db.Npc, "NPC", start[1]}, {db.Object, "物体", start[2]}, {db.Item, "物品", start[3]}}
    for _, category in ipairs(categories) do
        if type(category[3]) == "table" then
            for _, sourceID in ipairs(category[3]) do
                if #results >= 4 then break end
                local entity = category[1]
                local name = type(entity) == "table" and call(entity.name, sourceID)
                results[#results + 1] = category[2] .. "：" .. (name or ("#" .. tostring(sourceID)))
            end
        end
    end
    return #results > 0 and ("接取来源：" .. table.concat(results, "；")) or "接取来源：数据库未列出"
end

-- Exact mask checks preserve race bits beyond 32-bit bitwise operations.
local function matches(mask, flag)
    if type(mask) ~= "number" or mask == 0 then return true end
    if type(flag) ~= "number" or flag <= 0 then return nil end
    return mask % (2 * flag) >= flag
end

local function raceAndClass(db, id)
    local raceMask, classMask = call(db.Quest.requiredRaces, id), call(db.Quest.requiredClasses, id)
    local raceID, classID
    if type(UnitRace) == "function" then local ok, _, _, v = pcall(UnitRace, "player"); if ok and readable(v) then raceID = v end end
    if type(UnitClass) == "function" then local ok, _, _, v = pcall(UnitClass, "player"); if ok and readable(v) then classID = v end end
    local flags = type(db.Enum) == "table" and db.Enum.raceMaskById
    local raceFlag = type(flags) == "table" and flags[raceID]
    local classFlag = type(classID) == "number" and classID > 0 and 2 ^ (classID - 1) or nil
    local race, class = matches(raceMask, raceFlag), matches(classMask, classFlag)
    if race == false or class == false then return false end
    if race == nil or class == nil then return true, "阵营/种族或职业限制未知" end
    return true, "符合已知种族及职业限制"
end

local function relatedAreas(db, zoneID)
    local areas = {[zoneID] = true}
    local support = type(db.Support) == "table" and call(db.Support.Get, "ZoneDB")
    local dungeons = type(support) == "table" and type(support.private) == "table" and support.private.dungeons
    local entry = type(dungeons) == "table" and dungeons[zoneID]
    if type(entry) == "table" and type(entry[2]) == "table" then
        for _, alternative in ipairs(entry[2]) do if type(alternative) == "number" then areas[alternative] = true end end
    end
    return areas
end

function toolbox.questieDungeonQuests(dungeon)
    local db, err = available()
    if not db then return nil, err end
    if type(dungeon) ~= "table" or type(dungeon.zoneID) ~= "number" then return nil, "此副本缺少可查询的区域编号。" end
    if provider ~= db then index, scanning, failure = nil, nil, nil end
    if failure then return nil, failure end
    if not index then beginIndex(db); return nil, "正在分批建立副本任务索引，请稍候刷新。" end
    local seen, results = {}, {}
    for area in pairs(relatedAreas(db, dungeon.zoneID)) do
        for _, id in ipairs(index[area] or {}) do
            if not seen[id] then
                seen[id] = true
                local allowed, restriction = raceAndClass(db, id)
                if allowed then
                    local lines = {"任务状态：" .. questState(id), restriction, location(db, id)}
                    local required = call(db.Quest.requiredLevel, id)
                    if type(required) == "number" and required > 0 then lines[#lines + 1] = "最低等级：" .. required end
                    for _, line in ipairs(prerequisiteLines(db, id)) do lines[#lines + 1] = line end
                    lines[#lines + 1] = "按任务归属区域查询，跨区及职业任务可能遗漏；其他条件请在 Questie 核对。"
                    results[#results + 1] = {title = title(db, id), faction = restriction,
                        details = table.concat(lines, "\n"), questID = id}
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.title < b.title end)
    return results
end

driver:Hide()
driver:SetScript("OnUpdate", function()
    if not scanning then driver:Hide(); return end
    local ok, err = coroutine.resume(scanning)
    if not ok then failure = "QuestieDB 索引失败：" .. tostring(err); scanning = nil
    elseif coroutine.status(scanning) == "dead" then scanning = nil end
    if not scanning then
        driver:Hide()
        if type(toolbox.onDungeonQuestIndexReady) == "function" then pcall(toolbox.onDungeonQuestIndexReady) end
    end
end)
