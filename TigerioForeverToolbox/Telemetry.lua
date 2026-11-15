-- Account-local telemetry. SavedVariables are written by the client on logout/reload.
-- Missing or restricted values stay missing; old calendar data is not rewritten.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, guid, sessionID, sequence, pendingSnapshot, retryElapsed, waitingForItemData
local loginSeen, initRetryElapsed, initFailures, initWarned = false, 0, 0, false
local equipment, pendingSlots, seenLines, requestedItems = {}, {}, {}, {}
local slots = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end
local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function now()
    local value = call(time)
    return finite(value) and value > 0 and math.floor(value) or nil
end
local function nonempty(value)
    return readable(value) and type(value) == "string" and value ~= "" and value or nil
end
local function markPartial()
    if character then character.data_incomplete = true end
end

-- Session and counter are part of the saved event ID, so later imports can
-- upsert the same saved event without conflating two legitimate acquisitions.
local function nextID()
    sequence = sequence + 1
    return guid .. ":" .. sessionID .. ":" .. tostring(sequence)
end
local function append(kind, source, timestamp, fields, id)
    if not character or not finite(timestamp) then markPartial(); return nil end
    local event = fields or {}
    event.id, event.type, event.ts, event.source = id or nextID(), kind, timestamp, source
    character.events[#character.events + 1] = event
    if not finite(character.updated_at) or timestamp > character.updated_at then character.updated_at = timestamp end
    return event
end

local function itemLevel(link)
    if type(link) ~= "string" or not C_Item then return nil end
    local value = call(C_Item.GetDetailedItemLevelInfo, link)
    if finite(value) and value > 0 then return value end
end
local function requestItem(id)
    if not finite(id) or requestedItems[id] or not C_Item or type(C_Item.RequestLoadItemDataByID) ~= "function" then return end
    requestedItems[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
end
local function readSlot(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if not ok or not readable(id) or (id ~= nil and (not finite(id) or id <= 0)) then return nil end
    local result = {item_id = id}
    if id ~= nil and type(GetInventoryItemLink) == "function" then
        local link = call(GetInventoryItemLink, "player", slot)
        if type(link) == "string" then result.item_link = link; result.item_level = itemLevel(link) end
    end
    return result
end
local function averageEquipped()
    if type(GetAverageItemLevel) ~= "function" then return nil end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if ok and finite(equipped) and equipped > 0 then return equipped end
end
local function snapshot(timestamp)
    if not character then return false end
    local items, complete = {}, true
    waitingForItemData = false
    for _, slot in ipairs(slots) do
        local item = readSlot(slot)
        if not item then complete = false
        elseif item.item_id then
            items[slot] = item
            if not item.item_link or not item.item_level then
                complete, waitingForItemData = false, true
                requestItem(item.item_id)
            end
        end
    end
    local average = averageEquipped()
    local event = append("gear_snapshot", "equipped_api", timestamp,
        {slots = items, snapshot_complete = complete, average_item_level = average,
            average_item_level_kind = average and "equipped_raw" or nil})
    return event ~= nil and complete
end
local function establishBaseline()
    for _, slot in ipairs(slots) do equipment[slot] = readSlot(slot) end
end
local function equipmentChanged(slot, timestamp)
    if not finite(slot) or slot ~= math.floor(slot) then return end
    local old, current = equipment[slot], readSlot(slot)
    if not current then markPartial(); return end
    if not old then
        -- A first readable value is a baseline, not evidence of a change.
        markPartial()
    elseif old.item_id ~= current.item_id
        or (old.item_link and current.item_link and old.item_link ~= current.item_link) then
        append("gear_equipped", "equipment_changed", timestamp, {
            slot = slot, old_item_id = old.item_id, old_item_link = old.item_link,
            item_id = current.item_id, item_link = current.item_link,
            old_empty = old.item_id == nil, empty = current.item_id == nil,
        })
    end
    equipment[slot] = current
end

-- Compile the client's localized self-only loot formats, including positional
-- placeholders. No bag-diff inference and no other-player messages are counted.
local function formatPattern(fmt)
    if not nonempty(fmt) then return nil end
    local parts, kinds, index = {}, {}, 1
    while index <= #fmt do
        local rest = fmt:sub(index)
        local pos, kind = rest:match("^%%(%d+)%$([sd])")
        local length
        if pos then length = #pos + 3 else kind = rest:match("^%%([sd])"); length = 2 end
        if kind then
            parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
            kinds[#kinds + 1] = kind
            index = index + length
        elseif rest:sub(1, 2) == "%%" then
            parts[#parts + 1] = "%%"; index = index + 2
        else
            parts[#parts + 1] = rest:sub(1, 1):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            index = index + 1
        end
    end
    return "^" .. table.concat(parts) .. "$", kinds
end
local lootFormats = {
    {"LOOT_ITEM_SELF_MULTIPLE", "loot_chat_self"}, {"LOOT_ITEM_SELF", "loot_chat_self"},
    {"LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed_chat_self"}, {"LOOT_ITEM_PUSHED_SELF", "pushed_chat_self"},
    {"LOOT_ITEM_CREATED_SELF_MULTIPLE", "created_chat_self"}, {"LOOT_ITEM_CREATED_SELF", "created_chat_self"},
}
local function parseReceipt(message)
    if not nonempty(message) then return nil end
    for _, entry in ipairs(lootFormats) do
        local pattern, kinds = formatPattern(_G[entry[1]])
        if pattern then
            local captures = {message:match(pattern)}
            if #captures > 0 then
                local link, quantity
                for i, value in ipairs(captures) do
                    if kinds[i] == "s" and value:match("|Hitem:%d+") then link = value end
                    if kinds[i] == "d" then quantity = tonumber(value) end
                end
                local id = link and tonumber(link:match("|Hitem:(%d+)"))
                if id and finite(id) and id > 0 and (quantity == nil or quantity > 0) then
                    return id, link, quantity or 1, entry[2]
                end
            end
        end
    end
end
local function classifyReceipt(item)
    if not C_Item or type(C_Item.GetItemInfo) ~= "function" then return nil end
    local ok, name, link, quality, _, _, _, _, _, equipLoc, _, _, classID = pcall(C_Item.GetItemInfo, item.item_link)
    if not ok or not nonempty(name) or not readable(equipLoc) or type(equipLoc) ~= "string"
        or not finite(classID) then return nil end
    if (classID == 2 or classID == 4) and equipLoc ~= "" then
        local fields = {item_id = item.item_id, item_link = nonempty(link) or item.item_link,
            quantity = item.quantity, item_name = name, item_level = itemLevel(item.item_link)}
        if finite(quality) then fields.quality = quality end
        append("equipment_acquired", item.source, item.ts, fields, item.id)
    end
    return true
end
local function processPending()
    if not character then return end
    local list = character.pending_loot
    for i = #list, 1, -1 do
        local item = list[i]
        if type(item) ~= "table" then markPartial()
        elseif classifyReceipt(item) then table.remove(list, i)
        else requestItem(item.item_id) end
    end
    character.pending_loot_count = #list
end
local function receipt(message, lineID)
    if not character then return end
    local id, link, count, source = parseReceipt(message)
    if not id then return end
    if finite(lineID) and lineID > 0 then
        if seenLines[lineID] then return end
        seenLines[lineID] = true
    end
    local timestamp = now()
    if not timestamp then markPartial(); return end
    local item = {id = nextID(), ts = timestamp, item_id = id, item_link = link, quantity = count, source = source}
    if not classifyReceipt(item) then
        character.pending_loot[#character.pending_loot + 1] = item
        character.pending_loot_count = #character.pending_loot
        requestItem(id)
    end
end

local function initialize()
    local db = TigerioForeverToolboxDB
    local playerGUID = call(UnitGUID, "player")
    local timestamp = now()
    if type(db) ~= "table" or type(playerGUID) ~= "string" or not playerGUID:match("^Player%-") or not timestamp then return false end
    if db.telemetry == nil then db.telemetry = {version = 1, characters = {}} end
    local root = db.telemetry
    if type(root) ~= "table" or root.version ~= 1 or type(root.characters) ~= "table" then return false end
    local existing = root.characters[playerGUID]
    if existing ~= nil and type(existing) ~= "table" then return false end
    if existing == nil then existing = {events = {}, pending_loot = {}, started_at = timestamp}; root.characters[playerGUID] = existing end
    if type(existing.events) ~= "table" or (existing.pending_loot ~= nil and type(existing.pending_loot) ~= "table") then return false end
    if existing.pending_loot == nil then existing.pending_loot = {} end
    local _, class = nil, nil
    if type(UnitClass) == "function" then local ok, a, b = pcall(UnitClass, "player"); if ok then class = b end end
    local name = call(UnitName, "player")
    local realm = call(GetRealmName)
    local level = call(UnitLevel, "player")
    if nonempty(name) then existing.name = name end
    if nonempty(realm) then existing.realm = realm end
    if nonempty(class) then existing.class = class end
    if finite(level) and level > 0 then existing.level, existing.level_observed_at = level, timestamp end
    existing.guid = playerGUID
    existing.updated_at = timestamp
    existing.acquisition_coverage = "partial_self_loot_chat"
    if not finite(existing.started_at) then existing.started_at = timestamp end
    character, guid = existing, playerGUID
    local uptime = call(GetTime)
    local random = type(math.random) == "function" and call(math.random, 1, 2147483647) or nil
    sessionID = tostring(timestamp) .. "-" .. tostring(finite(uptime) and math.floor(uptime * 1000) or 0)
        .. "-" .. tostring(finite(random) and random or 0)
    sequence = 0
    establishBaseline()
    pendingSnapshot, retryElapsed = true, 0
    processPending()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "CHAT_MSG_LOOT",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "PLAYER_LOGOUT"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then loginSeen = true; initialize(); return end
    if event == "PLAYER_ENTERING_WORLD" and loginSeen and not character then initialize(); return end
    if not character then return end
    if event == "PLAYER_LEVEL_UP" then
        local level = ...
        if finite(level) and level > 0 and level == math.floor(level) then
            local previous, timestamp = character.level, now()
            local fields = {level = level}
            if finite(previous) and previous > 0 and previous < level then
                fields.from_level = previous
                if finite(character.level_observed_at) then fields.from_level_observed_at = character.level_observed_at end
            end
            append("level_up", "PLAYER_LEVEL_UP", timestamp, fields)
            character.level = level
            character.level_observed_at = timestamp
        else markPartial() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        equipmentChanged(slot, now())
        if finite(slot) and slot > 0 and slot == math.floor(slot) then pendingSlots[slot] = true end
        pendingSnapshot, retryElapsed = true, 0
    elseif event == "CHAT_MSG_LOOT" then
        local args = {...}
        receipt(args[1], args[11])
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        processPending()
        if waitingForItemData then pendingSnapshot, retryElapsed = true, 0 end
    elseif event == "PLAYER_LOGOUT" then
        processPending()
        if pendingSnapshot then snapshot(now()); pendingSnapshot = false end
    end
end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not finite(elapsed) then return end
    if not character then
        if not loginSeen then return end
        initRetryElapsed = initRetryElapsed + elapsed
        if initRetryElapsed >= 5 then
            initRetryElapsed = 0
            if not initialize() then
                initFailures = initFailures + 1
                if initFailures >= 3 and not initWarned then
                    initWarned = true
                    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
                        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "升级工具：统计采集暂不可用，正在自动重试。")
                    end
                end
            end
        end
        return
    end
    if not pendingSnapshot then return end
    retryElapsed = (retryElapsed or 0) + elapsed
    if retryElapsed < 1 then return end
    retryElapsed = 0
    for slot in pairs(pendingSlots) do
        equipmentChanged(slot, now())
        pendingSlots[slot] = nil
    end
    -- An incomplete snapshot is preserved as evidence rather than guessed.
    -- Retry only on a subsequent item-data event, not every frame forever.
    snapshot(now())
    pendingSnapshot = false
end)
