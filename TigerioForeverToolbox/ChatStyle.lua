-- Decorate existing Blizzard chat windows without changing their configuration.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, enabled, pending, elapsed = nil, false, false, 0
local decorations = {}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, result = pcall(canaccesstable, value)
    return ok and readable(result) and result == true
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    return value ~= nil and value ~= false
end

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and readable(guid) and type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function init()
    character = nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then return false end
    if db.globalUI == nil then db.globalUI = {version = 1, characters = {}} end
    local data = db.globalUI
    if not tableOK(data) or data.version ~= 1 or not tableOK(data.characters) then return false end
    local entry = data.characters[guid]
    if entry == nil then entry = {}; data.characters[guid] = entry end
    if not tableOK(entry) or (entry.chatStyle ~= nil and type(entry.chatStyle) ~= "boolean") then return false end
    character, enabled = entry, entry.chatStyle ~= false
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    return character and guid and tableOK(db) and tableOK(db.globalUI)
        and db.globalUI.version == 1 and tableOK(db.globalUI.characters)
        and db.globalUI.characters[guid] == character
end

local function safeFrame(frame)
    if not readable(frame) or not frame then return false end
    local ok, forbidden = pcall(function()
        return type(frame.IsForbidden) == "function" and frame:IsForbidden()
    end)
    return ok and readable(forbidden) and not forbidden
end

local function setPieces(pieces, show)
    local success = true
    for _, texture in ipairs(pieces) do
        local ok = pcall(show and texture.Show or texture.Hide, texture)
        if not ok then success = false end
    end
    return success
end

local function decorate(frame, kind)
    if not safeFrame(frame) then return end
    local previous = decorations[frame]
    if previous then setPieces(previous, true); return end
    local pieces = {}
    local ok = pcall(function()
        local background = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
        pieces[#pieces + 1] = background
        background:SetAllPoints(frame)
        if kind == "edit" then
            background:SetColorTexture(0.035, 0.027, 0.020, 0.82)
        elseif kind == "tab" then
            background:SetColorTexture(0.035, 0.027, 0.020, 0.55)
        else
            background:SetColorTexture(0.035, 0.027, 0.020, 0.62)
        end
        for i = 1, 4 do
            local edge = frame:CreateTexture(nil, "BORDER", nil, 7)
            pieces[#pieces + 1] = edge
            edge:SetColorTexture(0.60, 0.43, 0.23, 0.88)
            if i == 1 then
                edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                edge:SetHeight(1)
            elseif i == 2 then
                edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                edge:SetHeight(1)
            elseif i == 3 then
                edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                edge:SetWidth(1)
            else
                edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                edge:SetWidth(1)
            end
        end
    end)
    if ok and #pieces == 5 then decorations[frame] = pieces
    else setPieces(pieces, false) end
end

local function discover()
    if not enabled or not current() then return end
    if combat() then pending = true; return end
    pending = false
    if tableOK(CHAT_FRAMES) then
        for _, name in ipairs(CHAT_FRAMES) do
            if readable(name) and type(name) == "string" and name:match("^ChatFrame%d+$") then
                decorate(_G[name])
                decorate(_G[name .. "EditBox"], "edit")
                decorate(_G[name .. "Tab"], "tab")
            end
        end
    else
        decorate(_G.ChatFrame1)
        decorate(_G.ChatFrame1EditBox, "edit")
        decorate(_G.ChatFrame1Tab, "tab")
    end
end

function toolbox.getChatStyleEnabled()
    if not current() then return nil, "聊天样式不可用" end
    return enabled
end

function toolbox.setChatStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "聊天样式不可用" end
    if combat() then return false, "请在脱战后调整" end
    if value == enabled then return true end
    if not value then
        local success = true
        for _, pieces in pairs(decorations) do
            if not setPieces(pieces, false) then success = false end
        end
        if not success then
            for _, pieces in pairs(decorations) do setPieces(pieces, true) end
            return false, "聊天样式暂时无法恢复"
        end
    end
    character.chatStyle, enabled = value, value
    if value then discover() end
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED", "UPDATE_CHAT_WINDOWS"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if init() then discover() end
        if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then discover() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED" or event == "UPDATE_CHAT_WINDOWS" then
        discover()
    end
end)
-- Temporary chats can be created later without a dedicated common event.
driver:SetScript("OnUpdate", function(_, delta)
    if not enabled or not current() then return end
    elapsed = elapsed + delta
    if elapsed < 5 then return end
    elapsed = 0
    discover()
end)
