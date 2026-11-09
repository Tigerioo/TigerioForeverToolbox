-- Add unobtrusive borders to Blizzard's existing party and raid health bars.
-- Native frames continue to own unit updates, clicks, healing and layout.
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
    local ok, allowed = pcall(canaccesstable, value)
    return ok and readable(allowed) and allowed == true
end

local function field(value, key)
    if not readable(value) or not value then return nil, false end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result, true end
    return nil, false
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, locked = pcall(InCombatLockdown)
    if not ok or not readable(locked) then return true end
    return locked ~= nil and locked ~= false
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
    local data, dataOK = field(db, "globalUI")
    if not dataOK then return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.globalUI = data end) then return false end
    end
    local entries = field(data, "characters")
    if not tableOK(data) or field(data, "version") ~= 1 or not tableOK(entries) then return false end
    local entry, entryOK = field(entries, guid)
    if not entryOK then return false end
    if entry == nil then
        entry = {}
        if not pcall(function() entries[guid] = entry end) then return false end
    end
    local setting, settingOK = field(entry, "groupStyle")
    if not tableOK(entry) or not settingOK or (setting ~= nil and type(setting) ~= "boolean") then return false end
    character, enabled = entry, setting ~= false
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not character or not guid or not tableOK(db) then return false end
    local data = field(db, "globalUI")
    local entries = field(data, "characters")
    return tableOK(data) and field(data, "version") == 1 and tableOK(entries)
        and field(entries, guid) == character
end

local function usable(bar)
    if not readable(bar) or not bar then return false end
    local ok, safe = pcall(function()
        if type(bar.IsForbidden) == "function" and bar:IsForbidden() then return false end
        if type(bar.IsObjectType) == "function" and not bar:IsObjectType("StatusBar") then return false end
        return type(bar.CreateTexture) == "function"
    end)
    return ok and readable(safe) and safe == true
end

local function showPieces(pieces, show)
    local success = true
    for _, texture in ipairs(pieces) do
        local ok = pcall(show and texture.Show or texture.Hide, texture)
        if not ok then success = false end
    end
    return success
end

local function decorate(bar)
    if not usable(bar) then return end
    local existing = decorations[bar]
    if existing then showPieces(existing, true); return end
    local pieces = {}
    local ok = pcall(function()
        for index = 1, 4 do
            local edge = bar:CreateTexture(nil, "OVERLAY", nil, 7)
            pieces[#pieces + 1] = edge
            edge:SetColorTexture(0.60, 0.43, 0.23, 0.90)
            if index == 1 then
                edge:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                edge:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
                edge:SetHeight(1)
            elseif index == 2 then
                edge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                edge:SetHeight(1)
            elseif index == 3 then
                edge:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                edge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
                edge:SetWidth(1)
            else
                edge:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                edge:SetWidth(1)
            end
        end
    end)
    if ok and #pieces == 4 then decorations[bar] = pieces else showPieces(pieces, false) end
end

local function barOf(frame)
    local holder = field(frame, "HealthBarContainer")
    return field(holder, "HealthBar") or field(frame, "healthBar") or field(frame, "HealthBar")
end

local function applyMember(frame)
    if frame then decorate(barOf(frame)) end
end

local function applyArray(frames)
    if not tableOK(frames) then return end
    local ok = pcall(function()
        for _, frame in ipairs(frames) do applyMember(frame) end
    end)
    return ok
end

local function discover()
    if not enabled or not current() then return end
    if combat() then pending = true; return end
    pending = false
    local party = _G.PartyFrame
    for i = 1, 4 do
        local member = field(party, "MemberFrame" .. i) or _G["PartyMemberFrame" .. i]
        if not member and type(field(party, "GetPartyMemberFrame")) == "function" then
            local ok, value = pcall(party.GetPartyMemberFrame, party, i)
            if ok and readable(value) then member = value end
        end
        applyMember(member)
    end
    local compactParty = _G.CompactPartyFrame
    applyArray(field(compactParty, "memberUnitFrames"))
    for i = 1, 5 do applyMember(_G["CompactPartyFrameMember" .. i]) end
    for group = 1, 8 do
        local name = "CompactRaidGroup" .. group
        applyArray(field(_G[name], "memberUnitFrames"))
        for i = 1, 5 do applyMember(_G[name .. "Member" .. i]) end
    end
    -- The raid container creates these named buttons dynamically.
    local container = _G.CompactRaidFrameContainer
    local lists = field(container, "frameUpdateList")
    applyArray(field(lists, "normal"))
    for i = 1, 100 do applyMember(_G["CompactRaidFrame" .. i]) end
end

function toolbox.getGroupStyleEnabled()
    if not current() then return nil, "队伍样式不可用" end
    return enabled
end

function toolbox.setGroupStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "队伍样式不可用" end
    if combat() then return false, "请在脱战后调整" end
    if value == enabled then return true end
    if not value then
        local success = true
        for _, pieces in pairs(decorations) do
            if not showPieces(pieces, false) then success = false end
        end
        if not success then
            for _, pieces in pairs(decorations) do showPieces(pieces, true) end
            return false, "队伍样式暂时无法恢复"
        end
    end
    if not pcall(function() character.groupStyle = value end) then
        if enabled then for _, pieces in pairs(decorations) do showPieces(pieces, true) end end
        return false, "队伍样式无法保存"
    end
    enabled = value
    if value then discover() end
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED", "GROUP_ROSTER_UPDATE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if init() then discover() end
        if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then discover() end
    else
        discover()
    end
end)
-- Blizzard may create or recycle raid buttons after the roster event.
driver:SetScript("OnUpdate", function(_, delta)
    if not enabled or not current() then return end
    elapsed = elapsed + delta
    if elapsed < 5 then return end
    elapsed = 0
    discover()
end)
