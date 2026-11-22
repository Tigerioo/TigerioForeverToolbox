-- Character-local, online map time. Never infer time for an unknown map.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, guid, activeMap, lastTick
local loading, loggedIn, elapsed = false, false, 0

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

local function safeTable(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    return call(canaccesstable, value) == true
end

local function field(value, key)
    if not safeTable(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end

local function lookup(value, key)
    if not safeTable(value) then return nil, false end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result, true end
    return nil, false
end

local function validID(value)
    return finite(value) and value > 0 and value == math.floor(value)
end

local function playerGUID()
    local value = call(UnitGUID, "player")
    if type(value) == "string" and value:match("^Player%-") then return value end
end

local function initialize()
    local db, id = TigerioForeverToolboxDB, playerGUID()
    if not safeTable(db) or not id then return false end
    local root, rootReadable = lookup(db, "mapTime")
    if not rootReadable then return false end
    if root == nil then
        root = {version = 1, characters = {}}
        db.mapTime = root
    end
    if not safeTable(root) or field(root, "version") ~= 1 or not safeTable(field(root, "characters")) then return false end
    local characters = root.characters
    local data, dataReadable = lookup(characters, id)
    if not dataReadable then return false end
    if data == nil then
        data = {maps = {}, startedAt = call(time)}
        characters[id] = data
    end
    if not safeTable(data) or not safeTable(field(data, "maps")) then return false end
    character, guid = data, id
    return true
end

local function mapInfo(id)
    if not C_Map or not validID(id) then return nil end
    local info = call(C_Map.GetMapInfo, id)
    return safeTable(info) and info or nil
end

local function currentMap()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
    local id = call(C_Map.GetBestMapForUnit, "player")
    if not validID(id) then return nil end
    local info = mapInfo(id)
    if not info then return nil end
    local kinds = Enum and Enum.UIMapType or {}
    local zone, dungeon, micro = kinds.Zone or 3, kinds.Dungeon or 4, kinds.Micro or 5
    local seen = {}
    for _ = 1, 20 do
        if seen[id] then return nil end
        seen[id] = true
        local kind, parent = field(info, "mapType"), field(info, "parentMapID")
        if kind ~= micro and kind ~= dungeon then break end
        if not validID(parent) then break end
        local parentInfo = mapInfo(parent)
        if not parentInfo then break end
        local parentKind = field(parentInfo, "mapType")
        if kind == dungeon and parentKind ~= dungeon then break end
        id, info = parent, parentInfo
    end
    local kind = field(info, "mapType")
    if kind ~= zone and kind ~= dungeon and kind ~= micro then return nil end
    local name = field(info, "name")
    if type(name) ~= "string" or name == "" then name = "地图 " .. tostring(id) end
    return {id = id, name = name}
end

local function account(now)
    if not finite(now) then lastTick = nil; return end
    if lastTick and now >= lastTick and character and guid == playerGUID() and activeMap then
        local seconds = now - lastTick
        local maps = character.maps
        local key = tostring(activeMap.id)
        local entry, entryReadable = lookup(maps, key)
        if entryReadable and entry == nil then
            entry = {id = activeMap.id, name = activeMap.name, seconds = 0}
            maps[key] = entry
        end
        if safeTable(entry) and finite(field(entry, "seconds")) and entry.seconds >= 0 then
            entry.seconds = entry.seconds + seconds
            entry.name = activeMap.name
        end
    end
    lastTick = now
end

local function updateMap()
    local now = call(GetTime)
    account(now)
    activeMap = not loading and currentMap() or nil
end

function toolbox.getMapTimeStats()
    if not loggedIn or not character or guid ~= playerGUID() then return nil end
    if not loading then updateMap() end
    local result = {maps = {}, currentMapID = activeMap and activeMap.id or nil,
        startedAt = field(character, "startedAt"), loading = loading}
    for _, entry in pairs(character.maps) do
        local id, name, seconds = field(entry, "id"), field(entry, "name"), field(entry, "seconds")
        if validID(id) and type(name) == "string" and name ~= "" and finite(seconds) and seconds >= 0 then
            result.maps[#result.maps + 1] = {id = id, name = name, seconds = seconds}
        end
    end
    table.sort(result.maps, function(a, b)
        if a.seconds ~= b.seconds then return a.seconds > b.seconds end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return result
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        if initialize() and not loading then updateMap() end
    elseif not loggedIn then
        if event == "LOADING_SCREEN_ENABLED" then loading = true
        elseif event == "LOADING_SCREEN_DISABLED" then loading = false end
    elseif event == "PLAYER_LOGOUT" then
        account(call(GetTime))
        activeMap, lastTick, character, guid, loggedIn = nil, nil, nil, nil, false
    elseif event == "LOADING_SCREEN_ENABLED" then
        account(call(GetTime))
        activeMap, loading = nil, true
    elseif event == "LOADING_SCREEN_DISABLED" then
        loading = false
        updateMap()
    elseif not loading then
        if not character and not initialize() then return end
        updateMap()
    end
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not loggedIn or loading or not finite(delta) or delta < 0 then return end
    elapsed = elapsed + delta
    if elapsed >= 5 then
        elapsed = 0
        if character or initialize() then updateMap() end
    end
end)
