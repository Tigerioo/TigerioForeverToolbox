-- Draw a custom menu on Blizzard's buttons; native clicks and alerts stay intact.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, enabled, pending, elapsed, lookElapsed = nil, false, false, 0, 0
local decorations = {}
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\SlotFrame.tga"
local ICONS = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\MicroIcons.tga"
local buttonNames = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "TalentMicroButton", "SpellbookMicroButton", "AchievementMicroButton",
    "LegacyMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
    "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

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
    if not readable(value) or not value then return nil, false end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result, true end
    return nil, false
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

local function initialize()
    character = nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then return false end
    local data, ok = field(db, "globalUI")
    if not ok then return false end
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
    local value, valueOK = field(entry, "microStyle")
    if not tableOK(entry) or not valueOK or (value ~= nil and type(value) ~= "boolean") then return false end
    character, enabled = entry, value ~= false
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

local function eligible(button, menu)
    if not readable(button) or not button or not readable(menu) or not menu then return false end
    local ok, allowed = pcall(function()
        if type(button.IsForbidden) == "function" and button:IsForbidden() then return false end
        if type(button.IsObjectType) == "function" and not button:IsObjectType("Button") then return false end
        return type(button.GetParent) == "function" and button:GetParent() == menu
            and type(button.CreateTexture) == "function"
    end)
    return ok and readable(allowed) and allowed == true
end

local function setShown(pieces, show)
    local success = true
    for _, texture in ipairs(pieces) do
        if not pcall(show and texture.Show or texture.Hide, texture) then success = false end
    end
    return success
end

local function updateButtonLook(button, pieces)
    local icon = pieces[2]
    if not icon or type(button.IsEnabled) ~= "function" then return end
    local ok, isEnabled = pcall(button.IsEnabled, button)
    if ok and readable(isEnabled) then
        pcall(icon.SetAlpha, icon, (isEnabled and isEnabled ~= 0) and 1 or 0.42)
    end
end

local function discover()
    if not enabled or not current() then return end
    if combat() then pending = true; return end
    pending = false
    local menu = _G.MicroMenu
    local found = {}
    for index, name in ipairs(buttonNames) do
        local button = _G[name]
        if eligible(button, menu) then
            found[button] = true
            local pieces = decorations[button]
            if pieces then
                setShown(pieces, true)
            else
                pieces = {}
                local ok = pcall(function()
                    -- Artwork overlays the native art, while its alert/notification
                    -- overlay and all native button scripts remain above or intact.
                    local background = button:CreateTexture(nil, "ARTWORK", nil, 6)
                    pieces[#pieces + 1] = background
                    background:SetAllPoints(button)
                    background:SetColorTexture(0.035, 0.027, 0.020, 1)
                    local icon = button:CreateTexture(nil, "ARTWORK", nil, 7)
                    pieces[#pieces + 1] = icon
                    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -8)
                    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 8)
                    icon:SetTexture(ICONS)
                    local x, y = (index - 1) % 4, math.floor((index - 1) / 4)
                    icon:SetTexCoord(x / 4 + 0.002, (x + 1) / 4 - 0.002, y / 4 + 0.002, (y + 1) / 4 - 0.002)
                    icon:SetVertexColor(0.91, 0.77, 0.53, 1)
                    local border = button:CreateTexture(nil, "OVERLAY", nil, 7)
                    pieces[#pieces + 1] = border
                    border:SetAllPoints(button)
                    border:SetTexture(MEDIA)
                end)
                if ok and #pieces == 3 then decorations[button] = pieces
                else setShown(pieces, false); pieces = nil end
            end
            if pieces then updateButtonLook(button, pieces) end
        end
    end
    -- If a different addon takes a button out of the Blizzard menu, stop
    -- decorating that button without changing its parent or its own settings.
    for button, pieces in pairs(decorations) do
        if not found[button] then setShown(pieces, false) end
    end
end

function toolbox.getMicroStyleEnabled()
    if not current() then return nil, "系统菜单样式不可用" end
    return enabled
end

function toolbox.setMicroStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "系统菜单样式不可用" end
    if combat() then return false, "请在脱战后调整" end
    if value == enabled then return true end
    if not value then
        local success = true
        for _, pieces in pairs(decorations) do
            if not setShown(pieces, false) then success = false end
        end
        if not success then
            discover()
            return false, "系统菜单样式暂时无法恢复"
        end
    end
    if not pcall(function() character.microStyle = value end) then
        if enabled then discover() end
        return false, "系统菜单样式无法保存"
    end
    enabled = value
    if value then discover() end
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if initialize() then discover() end
        if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then discover() end
    else
        discover()
    end
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not enabled or not current() then return end
    lookElapsed = lookElapsed + delta
    if lookElapsed >= 0.3 then
        lookElapsed = 0
        if not combat() then
            for button, pieces in pairs(decorations) do updateButtonLook(button, pieces) end
        end
    end
    elapsed = elapsed + delta
    if elapsed < 5 then return end
    elapsed = 0
    discover()
end)
