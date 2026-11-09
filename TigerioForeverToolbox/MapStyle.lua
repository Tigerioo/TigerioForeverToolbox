-- Style the original minimap without moving controls or changing other addons.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, dataError, overlay, overlayMap, pending = nil, nil, nil, nil, false
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\OrbRing.tga"
local borders = {}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, accessible = pcall(canaccesstable, value)
    return ok and readable(accessible) and accessible == true
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if not ok or not readable(result) then return nil, false end
    return result, true
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    return value ~= nil and value ~= false
end

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, "player")
    if ok and readable(value) and type(value) == "string" and value:match("^Player%-") then return value end
end

local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end

local function initialize()
    character, dataError = nil, nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then dataError = "角色数据暂不可用"; return false end
    local data, ok = field(db, "globalUI")
    if not ok then dataError = "界面设置数据不可用"; return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.globalUI = data end) then dataError = "界面设置数据不可用"; return false end
    end
    if not tableOK(data) then dataError = "界面设置数据不可用"; return false end
    local version, versionOK = field(data, "version")
    local characters, charactersOK = field(data, "characters")
    if not versionOK or version ~= 1 or not charactersOK or not tableOK(characters) then
        dataError = "界面设置数据不可用"; return false
    end
    local entry, entryOK = field(characters, guid)
    if not entryOK then dataError = "小地图设置数据不可用"; return false end
    if entry == nil then
        entry = {}
        if not pcall(function() characters[guid] = entry end) then dataError = "小地图设置数据不可用"; return false end
    end
    if not tableOK(entry) then dataError = "小地图设置数据不可用"; return false end
    local setting, settingOK = field(entry, "mapStyle")
    if not settingOK or (setting ~= nil and type(setting) ~= "boolean") then
        dataError = "小地图设置数据不可用"; return false
    end
    character = entry
    return true
end

local function currentData()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not character or not guid or not tableOK(db) then
        return nil, dataError or "小地图设置暂不可用"
    end
    local data, dataOK = field(db, "globalUI")
    if not dataOK or not tableOK(data) then return nil, "小地图设置暂不可用" end
    local version, versionOK = field(data, "version")
    local characters, charactersOK = field(data, "characters")
    if not versionOK or version ~= 1 or not charactersOK or not tableOK(characters) then
        return nil, "小地图设置暂不可用"
    end
    local entry, entryOK = field(characters, guid)
    if not entryOK or entry ~= character then return nil, "小地图设置暂不可用" end
    local setting, settingOK = field(entry, "mapStyle")
    if not settingOK or (setting ~= nil and type(setting) ~= "boolean") then
        return nil, "小地图设置数据不可用"
    end
    return entry
end

local function enabled(entry)
    return entry.mapStyle ~= false
end

local function mapUsable(map)
    if not readable(map) or not map then return false end
    local ok, usable = pcall(function()
        if type(map.IsForbidden) == "function" and map:IsForbidden() then return false end
        if type(map.IsObjectType) == "function" and not map:IsObjectType("Minimap") then return false end
        return type(map.GetFrameLevel) == "function"
    end)
    return ok and readable(usable) and usable == true
end

local function restoreBorders()
    for texture, original in pairs(borders) do
        local ok, alpha = pcall(texture.GetAlpha, texture)
        if ok and readable(alpha) and alpha == 0 then
            pcall(texture.SetAlpha, texture, original)
        end
        borders[texture] = nil
    end
end

local function hideBorders()
    for _, name in ipairs({"MinimapCompassTexture", "MinimapCompassTextureUnderlay"}) do
        local texture = _G[name]
        if texture then
            local ok, alpha = pcall(texture.GetAlpha, texture)
            if not ok or not readable(alpha) or type(alpha) ~= "number" then
                restoreBorders()
                return false
            end
            if alpha ~= 0 then
                borders[texture] = alpha
                if not pcall(texture.SetAlpha, texture, 0) then
                    restoreBorders()
                    return false
                end
            end
        end
    end
    return true
end

local function applyStyle(wantEnabled)
    if combat() then pending = true; return false, "脱战后生效" end
    if not wantEnabled then
        restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        if overlay then
            local ok = pcall(overlay.Hide, overlay)
            if not ok then pending = true; return false, "小地图样式暂无法关闭" end
        end
        pending = false
        return true
    end
    local map = _G.Minimap
    if not mapUsable(map) then
        if overlay then pcall(overlay.Hide, overlay) end
        restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        pending = true
        return false, "小地图暂不可用"
    end
    if overlay and overlayMap ~= map then
        local ok = pcall(overlay.Hide, overlay)
        if not ok then pending = true; return false, "小地图样式暂不可用" end
        restoreBorders()
        overlay, overlayMap = nil, nil
    end
    if not overlay then
        local candidate
        local created, frame = pcall(function()
            local f = CreateFrame("Frame", nil, map)
            candidate = f
            f:Hide()
            f:EnableMouse(false)
            f:SetAllPoints(map)
            f:SetFrameLevel(map:GetFrameLevel() + 5)
            local ring = f:CreateTexture(nil, "OVERLAY")
            -- Expand the rim outwards without resizing or moving the map.
            ring:SetPoint("TOPLEFT", f, "TOPLEFT", -8, 8)
            ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 8, -8)
            ring:SetTexture(MEDIA)
            return f
        end)
        if not created or not frame then
            if candidate then pcall(candidate.Hide, candidate) end
            pending = true
            return false, "小地图样式暂不可用"
        end
        overlay, overlayMap = frame, map
    end
    if not hideBorders() then
        pcall(overlay.Hide, overlay)
        pending = true
        return false, "小地图边框暂不可用"
    end
    local ok = pcall(overlay.Show, overlay)
    if not ok then restoreBorders(); pending = true; return false, "小地图样式暂不可用" end
    if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(true) end
    pending = false
    return true
end

function toolbox.getMapStyleEnabled()
    local entry, err = currentData()
    if not entry then return nil, err end
    return enabled(entry)
end

function toolbox.setMapStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if combat() then return false, "请在脱战后调整小地图" end
    local entry, err = currentData()
    if not entry then return false, err end
    local ok, why = applyStyle(value)
    if not ok then return false, why end
    local saved = pcall(function() entry.mapStyle = value end)
    if not saved then
        applyStyle(enabled(entry))
        return false, "小地图设置暂不可保存"
    end
    notify()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if initialize() then applyStyle(enabled(character)) end
        notify()
    elseif character and (pending or event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED") then
        local entry = currentData()
        if entry then applyStyle(enabled(entry)) end
    end
end)
