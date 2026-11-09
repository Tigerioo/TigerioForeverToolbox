-- Account-wide, locally observed five-player party history.
local ADDON, toolbox = ...
local driver = CreateFrame("Frame")
local state, stateError, observerID
local live = {}
local pendingEnd = false
local resumed = false

local function readable(v)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, v)
    return ok and not secret
end

local function str(v)
    if readable(v) and type(v) == "string" and v ~= "" then return v end
end

local function num(v)
    if readable(v) and type(v) == "number" and v > 0 and v == math.floor(v) then return v end
end

local function bool(v)
    if readable(v) and type(v) == "boolean" then return v end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function field(t, k)
    local ok, value = pcall(function() return t[k] end)
    if ok and readable(value) then return value end
end

local function now()
    return num(call(time))
end

local function changed()
    if type(toolbox.onCompanionsChanged) == "function" then pcall(toolbox.onCompanionsChanged) end
end

local function initialize()
    if TigerioForeverToolboxDB == nil then TigerioForeverToolboxDB = {} end
    if type(TigerioForeverToolboxDB) ~= "table" then
        state, stateError = nil, "工具箱数据不可用，同行记录已暂停。"
        return
    end
    if TigerioForeverToolboxDB.companions == nil then
        TigerioForeverToolboxDB.companions = {version = 1, players = {}, sessions = {}}
    end
    local data = TigerioForeverToolboxDB.companions
    if type(data) ~= "table" or data.version ~= 1 or type(data.players) ~= "table" or type(data.sessions) ~= "table" then
        state, stateError = nil, "同行记录数据异常或版本不兼容，已暂停且未更改数据。"
        return
    end
    state, stateError = data, nil
end

local function currentState()
    if not state or type(TigerioForeverToolboxDB) ~= "table" or TigerioForeverToolboxDB.companions ~= state then
        return nil, stateError or "同行记录数据不可用，请重新加载界面。"
    end
    return state
end

local function playerIdentity(unit)
    local guid = str(call(UnitGUID, unit))
    if not guid or not guid:match("^Player%-") then return end
    local name, realm = call(UnitFullName, unit)
    name, realm = str(name), str(realm)
    -- Forever may return a surname as the second part, not a realm.
    if name and realm then name = name .. " " .. realm end
    local className = str(call(UnitClass, unit))
    return guid, name, nil, className
end

local function location()
    return str(call(GetRealZoneText)) or str(call(GetZoneText))
end

-- nil means the client cannot currently establish the group state.
local function groupState()
    local raid = bool(call(IsInRaid))
    local inGroup = bool(call(IsInGroup))
    local inside, kind = call(IsInInstance)
    inside, kind = bool(inside), str(kind)
    if raid == nil or inGroup == nil or inside == nil then return nil end
    if raid or (inside and (kind == "pvp" or kind == "arena")) then return false end
    if inside and not kind then return nil end
    if not inGroup then return false end
    local count = num(call(GetNumGroupMembers))
    if not count then return nil end
    if count > 5 then return false end
    if count < 2 then return nil end
    return true, count
end

local function readParty(count)
    local members, complete = {}, true
    for i = 1, count - 1 do
        local unit = "party" .. i
        local guid, name, realm, className = playerIdentity(unit)
        if guid and guid ~= observerID then
            local connected = bool(call(UnitIsConnected, unit))
            local level = connected == true and num(call(UnitLevel, unit)) or nil
            members[guid] = {name = name, realm = realm, className = className, level = level, connected = connected}
        else
            complete = false
        end
    end
    return members, complete
end

local function validRecord(record)
    return type(record) == "table" and type(record.history) == "table"
        and type(record.groupCount) == "number" and record.groupCount >= 0
end

local function addEncounter(data, session, guid, member, stamp, zone, observer)
    local record = data.players[guid]
    if record == nil then
        record = {id = guid, groupCount = 0, history = {}}
        data.players[guid] = record
    end
    if not validRecord(record) then return end -- Never repair or overwrite a malformed record.
    record.name = member.name or record.name
    record.realm = member.realm or record.realm
    record.className = member.className or record.className
    record.firstMet = record.firstMet or stamp
    record.lastMet = stamp or record.lastMet
    record.lastLocation = zone
    record.lastLocationAt = zone and stamp or nil
    record.lastLevel = member.level
    record.lastLevelAt = member.level and stamp or nil
    record.groupCount = record.groupCount + 1
    record.history[#record.history + 1] = {time = stamp, location = zone, locationAt = zone and stamp or nil,
        level = member.level, levelAt = member.level and stamp or nil, observer = observer}
    session.members[guid] = #record.history
end

local function refresh()
    local data = currentState()
    if not data then return end
    observerID = str(call(UnitGUID, "player"))
    if not observerID or not observerID:match("^Player%-") then live = {}; changed(); return end
    local active, count = groupState()
    if active == nil then live = {}; changed(); return end
    if active == false then
        live = {}
        -- A second observation avoids treating loading transitions as a disband.
        if not pendingEnd and C_Timer and type(C_Timer.After) == "function" then
            pendingEnd = true
            C_Timer.After(2, function()
                pendingEnd = false
                local current = currentState()
                if current and observerID and groupState() == false then
                    current.sessions[observerID] = nil
                    resumed = true
                    changed()
                end
            end)
        end
        changed()
        return
    end
    local members, complete = readParty(count)
    live = members
    local session = data.sessions[observerID]
    if session ~= nil and (type(session) ~= "table" or type(session.members) ~= "table") then
        stateError = "同行会话数据异常，已暂停且未更改数据。"
        state = nil
        return
    end
    -- After reload, resume only when at least one previously observed peer matches.
    -- If the roster is incomplete, wait instead of manufacturing a new encounter.
    if session and not resumed then
        local overlap, hasSaved = false, false
        for guid in pairs(session.members) do
            hasSaved = true
            if members[guid] then overlap = true end
        end
        if not overlap and hasSaved then
            if not complete then changed(); return end
            session = nil
        end
    end
    resumed = true
    if not session then
        session = {members = {}}
        data.sessions[observerID] = session
    end
    local stamp, zone = now(), location()
    local _, observer = playerIdentity("player")
    for guid, member in pairs(members) do
        if not session.members[guid] then
            addEncounter(data, session, guid, member, stamp, zone, observer)
        else
            local record = data.players[guid]
            if validRecord(record) then
                record.name = member.name or record.name
                record.realm = member.realm or record.realm
                record.className = member.className or record.className
                if stamp then record.lastMet = stamp end
                -- A unit's level or zone can be unavailable on the initial roster event.
                -- Preserve the first reliable sample and its actual observation time.
                local index = session.members[guid]
                local encounter = type(index) == "number" and record.history[index] or nil
                if type(encounter) == "table" then
                    if encounter.level == nil and member.level then
                        encounter.level, encounter.levelAt = member.level, stamp
                        if index == #record.history then record.lastLevel, record.lastLevelAt = member.level, stamp end
                    end
                    if encounter.location == nil and zone then
                        encounter.location, encounter.locationAt = zone, stamp
                        if index == #record.history then record.lastLocation, record.lastLocationAt = zone, stamp end
                    end
                end
            end
        end
    end
    changed()
end

local function friendSnapshot()
    local result = {}
    if not C_FriendList then return result end
    local count = call(C_FriendList.GetNumFriends)
    if not readable(count) or type(count) ~= "number" or count < 0 then return result end
    for i = 1, count do
        local info = call(C_FriendList.GetFriendInfoByIndex, i)
        local accessible = readable(info) and type(info) == "table"
        if accessible and type(canaccesstable) == "function" then
            local ok, value = pcall(canaccesstable, info)
            accessible = ok and value == true
        end
        if accessible then
            local guid = str(field(info, "guid"))
            local connected = bool(field(info, "connected"))
            if guid and connected ~= nil then
                result[guid] = {connected = connected, level = connected and num(field(info, "level")) or nil}
            end
        end
    end
    return result
end

function toolbox.companionList()
    local data, err = currentState()
    if not data then return nil, err end
    local friends, result, stamp = friendSnapshot(), {}, now()
    for guid, record in pairs(data.players) do
        if type(guid) == "string" and validRecord(record) then
            local source, status, currentLevel
            local current = live[guid]
            if current and current.connected ~= nil then
                source, status = "party", current.connected and "online" or "offline"
                if current.connected then currentLevel = current.level end
            elseif friends[guid] then
                source, status = "friend", friends[guid].connected and "online" or "offline"
                currentLevel = friends[guid].level
            else
                status = "unknown"
            end
            local history = {}
            for _, item in ipairs(record.history) do
                if type(item) == "table" then
                    history[#history + 1] = {time = item.time, location = item.location, level = item.level,
                        observer = item.observer, endedAt = item.endedAt,
                        levelAt = item.levelAt, locationAt = item.locationAt}
                end
            end
            result[#result + 1] = {id = guid, name = record.name, realm = record.realm, className = record.className,
                lastLocation = record.lastLocation, lastLocationAt = record.lastLocationAt,
                lastLevel = record.lastLevel, lastLevelAt = record.lastLevelAt,
                currentLevel = currentLevel, currentLevelAt = currentLevel and stamp or nil,
                status = status, statusSource = source, lastMet = record.lastMet,
                groupCount = record.groupCount, history = history}
        end
    end
    table.sort(result, function(a, b) return (a.lastMet or 0) > (b.lastMet or 0) end)
    return result
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("UNIT_NAME_UPDATE")
driver:RegisterEvent("UNIT_LEVEL")
driver:RegisterEvent("UNIT_CONNECTION")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("ZONE_CHANGED")
driver:RegisterEvent("FRIENDLIST_UPDATE")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == ADDON then initialize() end
    elseif event == "PLAYER_LOGOUT" then
        live = {} -- Session membership remains as a reconciliation hint, not elapsed time.
    elseif event == "FRIENDLIST_UPDATE" then
        changed()
    else
        refresh()
    end
end)
