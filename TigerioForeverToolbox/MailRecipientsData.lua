-- Account-local mail recipient data. Never derives a realm from a surname.
local ADDON, toolbox = ...
local driver = CreateFrame("Frame")
local state, stateError, friendsReady

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end
local function text(value)
    if readable(value) and type(value) == "string" and value ~= "" then return value end
end
local function positive(value)
    if readable(value) and type(value) == "number" and value == math.floor(value) and value > 0 and value <= 1000 then return value end
end
local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, access = pcall(canaccesstable, value)
    return ok and readable(access) and access == true
end
local function field(value, key)
    if not tableOK(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function changed()
    if type(toolbox.onMailRecipientsChanged) == "function" then pcall(toolbox.onMailRecipientsChanged) end
end

local classes = {
    WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true, DEATHKNIGHT=true,
    SHAMAN=true, MAGE=true, WARLOCK=true, MONK=true, DRUID=true, DEMONHUNTER=true, EVOKER=true,
}
local classCN = {
    ["战士"]="WARRIOR", ["圣骑士"]="PALADIN", ["猎人"]="HUNTER", ["潜行者"]="ROGUE",
    ["盗贼"]="ROGUE", ["牧师"]="PRIEST", ["死亡骑士"]="DEATHKNIGHT", ["萨满祭司"]="SHAMAN",
    ["萨满"]="SHAMAN", ["法师"]="MAGE", ["术士"]="WARLOCK", ["武僧"]="MONK",
    ["德鲁伊"]="DRUID", ["恶魔猎手"]="DEMONHUNTER", ["唤魔师"]="EVOKER",
}
local function classToken(value)
    value = text(value)
    if not value then return nil end
    local upper = value:upper()
    if classes[upper] then return upper end
    if classCN[value] then return classCN[value] end
    for _, names in ipairs({LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}}) do
        if tableOK(names) then
            for token, localized in pairs(names) do
                if classes[token] and readable(localized) and localized == value then return token end
            end
        end
    end
end

local function initialize()
    local db = TigerioForeverToolboxDB
    if not tableOK(db) then state, stateError = nil, "角色数据暂不可用"; return false end
    if db.mailRecipients == nil then db.mailRecipients = {version = 1, characters = {}, manual = {}, nextID = 0} end
    local root = db.mailRecipients
    if not tableOK(root) or root.version ~= 1 or not tableOK(root.characters) or not tableOK(root.manual)
        or (root.nextID ~= nil and (not readable(root.nextID) or type(root.nextID) ~= "number" or root.nextID < 0 or root.nextID ~= math.floor(root.nextID))) then
        state, stateError = nil, "收件人数据不可用"; return false
    end
    state, stateError = root, nil
    return true
end
local function current()
    if not state and not initialize() then return nil, stateError end
    if not tableOK(TigerioForeverToolboxDB) or TigerioForeverToolboxDB.mailRecipients ~= state then
        return nil, "收件人数据不可用"
    end
    return state
end
local function capturePlayer()
    local root = current()
    if not root then return end
    local guid = text(call(UnitGUID, "player"))
    if not guid or not guid:match("^Player%-") then return end
    local function invalidate()
        local saved = root.characters[guid]
        if tableOK(saved) then saved.recipientVerified = false end
    end
    local base, second = call(UnitFullName, "player")
    if not readable(second) then invalidate(); return end
    base, second = text(base), text(second)
    local full = text(call(GetUnitName, "player"))
    local realm = text(call(GetRealmName))
    if not base or not realm then invalidate(); return end
    local saved = root.characters[guid]
    if saved ~= nil and not tableOK(saved) then return end
    if saved == nil then saved = {}; root.characters[guid] = saved end
    -- Keep the client's original string only when it agrees with both
    -- readable name parts; never synthesize a mail address from those parts.
    local validFull = full and not full:find("[%c|]")
    if validFull then
        if second then
            local firstStart, firstEnd = full:find(base, 1, true)
            local secondStart = firstEnd and full:find(second, firstEnd + 1, true)
            validFull = firstStart == 1 and secondStart ~= nil
        else
            validFull = full == base
        end
    end
    saved.name = validFull and full or base
    saved.realm = realm
    local _, class = call(UnitClass, "player")
    saved.classToken = classToken(class) or saved.classToken
    saved.level = positive(call(UnitLevel, "player")) or saved.level
    local seen = call(time)
    if readable(seen) and type(seen) == "number" and seen > 0 and seen < math.huge then saved.lastSeen = seen end
    -- If native name APIs disagree, keep the old recipient but do not offer it.
    if validFull then
        saved.recipient, saved.recipientVerified = full, true
    else
        -- Keep earlier data, but do not offer it until a complete name can be
        -- confirmed again; a transient API failure must not erase history.
        saved.recipientVerified = false
    end
end

local function ordered(list)
    table.sort(list, function(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then return an < bn end
        return a.identity < b.identity
    end)
    return list
end
local function sameRealm(left, right)
    return text(left) and text(right) and left:lower() == right:lower()
end
local function markAmbiguous(list)
    local counts = {}
    for _, entry in ipairs(list) do
        if entry.recipient and not entry.manual then
            local key = entry.recipient:lower()
            counts[key] = (counts[key] or 0) + 1
        end
    end
    for _, entry in ipairs(list) do
        if entry.recipient and not entry.manual and counts[entry.recipient:lower()] > 1 then entry.selectable = false end
    end
end

local function characters()
    local root, err = current()
    if not root then return nil, err end
    local db, byGUID, list = TigerioForeverToolboxDB, {}, {}
    -- Only merge existing records by GUID; original data remains untouched.
    local historical = {field(db, "characters")}
    local telemetry = field(db, "telemetry")
    historical[2] = field(telemetry, "characters")
    for i = 1, 2 do
        local records = historical[i]
        if tableOK(records) then
            for guid, record in pairs(records) do
                if text(guid) and guid:match("^Player%-") and tableOK(record) then
                    local entry = byGUID[guid] or {identity = guid, name = text(field(record, "name")) or "未知", selectable = false, levelSource = "unknown"}
                    entry.name = text(field(record, "name")) or entry.name
                    entry.realm = text(field(record, "realm")) or entry.realm
                    entry.classToken = classToken(field(record, "class")) or entry.classToken
                    local level = positive(field(record, "level"))
                    if level then entry.level, entry.levelSource = level, "last" end
                    byGUID[guid] = entry
                end
            end
        end
    end
    for guid, saved in pairs(root.characters) do
        if text(guid) and guid:match("^Player%-") and tableOK(saved) then
            local entry = byGUID[guid] or {identity = guid, levelSource = "unknown"}
            entry.name = text(field(saved, "name")) or entry.name or "未知"
            entry.realm = text(field(saved, "realm")) or entry.realm
            entry.classToken = classToken(field(saved, "classToken")) or entry.classToken
            local level = positive(field(saved, "level"))
            if level then entry.level, entry.levelSource = level, "last" end
            local recipient = text(field(saved, "recipient"))
            entry.recipient = recipient
            entry.selectable = recipient ~= nil and field(saved, "recipientVerified") == true
                and not not sameRealm(entry.realm, call(GetRealmName))
            byGUID[guid] = entry
        end
    end
    local player = text(call(UnitGUID, "player"))
    for guid, entry in pairs(byGUID) do if guid ~= player then list[#list + 1] = entry end end
    for id, record in pairs(root.manual) do
        if text(id) and tableOK(record) then
            local name = text(field(record, "name"))
            if name then
                local level = positive(field(record, "level"))
                list[#list + 1] = {identity = id, name = name, recipient = name, selectable = true, manual = true,
                    classToken = classToken(field(record, "classToken")), level = level, levelSource = level and "last" or "unknown"}
            end
        end
    end
    markAmbiguous(list)
    return ordered(list)
end

local function friends()
    local api = C_FriendList
    if type(api) ~= "table" or type(api.GetNumFriends) ~= "function" or type(api.GetFriendInfoByIndex) ~= "function" then
        return nil, "好友列表暂不可用"
    end
    local ok, count = pcall(api.GetNumFriends)
    if not ok or not readable(count) or type(count) ~= "number" or count < 0 or count > 10000 or count ~= math.floor(count) then
        return nil, "好友列表暂不可用"
    end
    if count == 0 and not friendsReady then return nil, "好友列表尚未就绪" end
    if count > 0 then friendsReady = true end
    local list = {}
    for i = 1, count do
        local success, info = pcall(api.GetFriendInfoByIndex, i)
        if not success or not tableOK(info) then return nil, "好友列表尚未就绪" end
        local name, id = text(field(info, "name")), text(field(info, "guid"))
        if not name then return nil, "好友列表尚未就绪" end
        local connected = field(info, "connected")
        local online
        if type(connected) == "boolean" then online = connected end
        local level = online == true and positive(field(info, "level")) or nil
        list[#list + 1] = {identity = id or ("friend:" .. i .. ":" .. name), name = name, recipient = name,
            selectable = true, classToken = classToken(field(info, "className")),
            level = level, levelSource = level and "current" or "unknown", online = online}
    end
    markAmbiguous(list)
    return ordered(list)
end

function toolbox.getMailRecipients(group)
    if group == "characters" then return characters() end
    if group == "friends" then return friends() end
    return nil, "无效的收件人分类"
end
function toolbox.requestMailFriendsRefresh()
    if type(C_FriendList) ~= "table" or type(C_FriendList.ShowFriends) ~= "function" then return false end
    return pcall(C_FriendList.ShowFriends)
end
function toolbox.addManualMailRecipient(name, class, level)
    if not readable(name) or type(name) ~= "string" then return false, "请输入收件人姓名" end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 240 or name:find("[%c|]") then return false, "收件人姓名无效" end
    if class ~= nil and class ~= "" and not classToken(class) then return false, "职业无效" end
    if level ~= nil and not positive(level) then return false, "等级无效" end
    local root, err = current()
    if not root then return false, err end
    for _, record in pairs(root.manual) do
        if tableOK(record) and field(record, "name") == name then return false, "收件人已存在" end
    end
    local nextID = (root.nextID or 0) + 1
    local id = "manual:" .. tostring(nextID)
    if root.manual[id] ~= nil then return false, "收件人数据不可用" end
    root.manual[id] = {name = name, classToken = classToken(class), level = level}
    root.nextID = nextID
    changed()
    return true
end
function toolbox.removeManualMailRecipient(identity)
    local root, err = current()
    if not root then return false, err end
    if not text(identity) or not identity:match("^manual:%d+$") or root.manual[identity] == nil then return false, "未找到收件人" end
    root.manual[identity] = nil
    changed()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "UNIT_NAME_UPDATE", "FRIENDLIST_UPDATE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP"
        or (event == "UNIT_NAME_UPDATE" and readable(unit) and unit == "player") then capturePlayer() end
    if event == "FRIENDLIST_UPDATE" then friendsReady = true end
    changed()
end)
