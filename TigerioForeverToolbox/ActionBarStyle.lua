-- Style and fade only Blizzard's ordinary action bars; never alter their actions or visibility drivers.
local ADDON, toolbox = ...
local driver = CreateFrame("Frame")
local definitions = {
    {"MainActionBar", "ActionButton"},
    {"MultiBarBottomLeft", "MultiBarBottomLeftButton"},
    {"MultiBarBottomRight", "MultiBarBottomRightButton"},
    {"MultiBarRight", "MultiBarRightButton"},
    {"MultiBarLeft", "MultiBarLeftButton"},
    {"MultiBar5", "MultiBar5Button"},
    {"MultiBar6", "MultiBar6Button"},
    {"MultiBar7", "MultiBar7Button"},
}
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\SlotFrame.tga"
local managed, borders, hooked = {}, {}, {}
local character, active, initialized, scanElapsed, updateElapsed = nil, false, false, 0, 0
local layoutSuspended = false

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function safeCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    return value ~= nil and value ~= false
end

local function safeObject(object)
    if not object then return false end
    local ok, forbidden = pcall(function()
        if type(object.IsForbidden) == "function" then return object:IsForbidden() end
        return false
    end)
    return ok and readable(forbidden) and not forbidden
end

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and readable(guid) and type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function initialize()
    local db, guid = TigerioForeverToolboxDB, identity()
    if type(db) ~= "table" or not guid then return false end
    if db.actionBarStyle == nil then db.actionBarStyle = {version = 1, characters = {}} end
    local data = db.actionBarStyle
    if type(data) ~= "table" or data.version ~= 1 or type(data.characters) ~= "table" then return false end
    local entry = data.characters[guid]
    if entry == nil then entry = {enabled = true}; data.characters[guid] = entry end
    if type(entry) ~= "table" or type(entry.enabled) ~= "boolean"
        or (entry.hide ~= nil and type(entry.hide) ~= "boolean")
        or (entry.hover ~= nil and type(entry.hover) ~= "boolean") then return false end
    character, active, initialized = entry, entry.enabled, true
    return true
end

local function stillCurrent()
    local db, guid = TigerioForeverToolboxDB, identity()
    return initialized and character and guid and type(db) == "table"
        and type(db.actionBarStyle) == "table" and type(db.actionBarStyle.characters) == "table"
        and db.actionBarStyle.characters[guid] == character
end

-- Old version-1 records had only "enabled"; missing options retain the old behavior.
local function option(key)
    if not character then return nil end
    local value = character[key]
    if value == nil then return true end
    if readable(value) and type(value) == "boolean" then return value end
end

local function notify()
    if type(toolbox.onActionBarOptionsChanged) == "function" then
        pcall(toolbox.onActionBarOptionsChanged)
    end
end

function toolbox.getActionBarOptions()
    if not stillCurrent() then return nil, "动作条设置暂不可用" end
    local hide, hover = option("hide"), option("hover")
    if hide == nil or hover == nil then return nil, "动作条设置数据异常" end
    return {enabled = active, hide = hide, hover = hover}
end

local function getAlpha(bar)
    local ok, value = pcall(function() return bar:GetAlpha() end)
    if ok and readable(value) and type(value) == "number" and value >= 0 and value <= 1 then return value end
end

-- Stop controlling an alpha another owner has changed; never reset their value.
local function setManagedAlpha(state, alpha)
    if not state.owned then return false end
    local current = getAlpha(state.bar)
    if current == nil then return false end
    if state.last ~= nil and current ~= state.last then state.owned = false; return false end
    if current == alpha then state.last = alpha; return true end
    local ok = pcall(state.bar.SetAlpha, state.bar, alpha)
    if ok then state.last = alpha end
    return ok
end

local function editMode()
    local manager = EditModeManagerFrame
    if not safeObject(manager) then return false end
    local ok, value = pcall(function()
        if type(manager.IsEditModeActive) == "function" then return manager:IsEditModeActive() end
        if type(manager.IsShown) == "function" then return manager:IsShown() end
    end)
    return ok and readable(value) and not not value
end

local function hovered(state)
    local ok, value = pcall(state.bar.IsMouseOver, state.bar)
    if not ok or not readable(value) then return nil end
    if value then return true end
    for _, button in pairs(state.buttons) do
        if safeObject(button) and type(button.IsMouseOver) == "function" then
            local success, onButton = pcall(button.IsMouseOver, button)
            if success and readable(onButton) and onButton then return true end
        end
    end
    return false
end

local function refresh(state, editing)
    if not active or layoutSuspended or not state.owned or not safeObject(state.bar) then return end
    if editing then setManagedAlpha(state, state.original); return end
    local hide, hover = option("hide"), option("hover")
    if hide == nil or hover == nil or not hide then setManagedAlpha(state, state.original); return end
    if not hover then setManagedAlpha(state, 0); return end
    local over = hovered(state)
    -- If hover cannot be read, leave the bar usable rather than hiding it.
    setManagedAlpha(state, over == false and 0 or state.original)
end

local function hookHover(object, state)
    if hooked[object] or type(object.HookScript) ~= "function" then return end
    local ok = pcall(function()
        object:HookScript("OnEnter", function()
            if active and not layoutSuspended and (editMode() or option("hide") == false or option("hover") == true) then
                setManagedAlpha(state, state.original)
            end
        end)
    end)
    if ok then hooked[object] = true end
end

local function addBorder(button)
    local existing = borders[button]
    if existing then pcall(existing.Show, existing); return end
    local ok, texture = pcall(function()
        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetAllPoints(button)
        t:SetTexture(MEDIA)
        return t
    end)
    if ok and texture then borders[button] = texture end
end

local function discover()
    if not active or layoutSuspended or safeCombat() then return end
    local editing = editMode()
    for _, definition in ipairs(definitions) do
        local bar, prefix = _G[definition[1]], definition[2]
        if safeObject(bar) and type(bar.IsMouseOver) == "function" and type(bar.GetAlpha) == "function"
            and type(bar.SetAlpha) == "function" then
            local state = managed[bar]
            if not state then
                local alpha = getAlpha(bar)
                -- A non-default alpha may belong to the player or another addon.
                state = {bar = bar, original = alpha, last = alpha, owned = alpha == 1, buttons = {}}
                managed[bar] = state
                hookHover(bar, state)
            end
            for i = 1, 12 do
                local button = _G[prefix .. i]
                if safeObject(button) then
                    local ok, owner = pcall(function() return button.bar end)
                    if ok and readable(owner) and owner == bar then
                        state.buttons[i] = button
                        addBorder(button)
                        hookHover(button, state)
                    end
                end
            end
            refresh(state, editing)
        end
    end
end

local function deactivate()
    local failed = false
    for _, state in pairs(managed) do
        if state.owned and not setManagedAlpha(state, state.original) and state.owned then failed = true end
    end
    for _, texture in pairs(borders) do
        local ok = pcall(texture.Hide, texture)
        if not ok then failed = true end
    end
    return not failed
end

-- While the independent layout owns the native bars, stop fading them so that
-- a secure vehicle/override fallback can show the original system interface.
-- The character's explicit style and hover preferences remain untouched.
function toolbox.suspendNativeActionBarStyle(value)
    if type(value) ~= "boolean" or safeCombat() then return false end
    if value == layoutSuspended then return true end
    if value and active and not deactivate() then return false end
    layoutSuspended = value
    if not value and active then
        for _, state in pairs(managed) do
            local alpha = getAlpha(state.bar)
            state.original, state.last, state.owned = alpha, alpha, alpha == 1
        end
        discover()
    end
    return true
end

function toolbox.setActionBarOption(key, value)
    if key ~= "enabled" and key ~= "hide" and key ~= "hover" then return false, "设置无效" end
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not stillCurrent() then return false, "动作条设置暂不可用" end
    if option("hide") == nil or option("hover") == nil then return false, "动作条设置数据异常" end
    if safeCombat() then return false, "请在脱战后调整动作条" end
    if key == "enabled" then
        if active == value then return true end
        local restored = true
        if value then
            active, character.enabled = true, true
            -- Existing hooks remain valid; only reacquire the normal default alpha.
            for _, state in pairs(managed) do
                local alpha = getAlpha(state.bar)
                state.original, state.last, state.owned = alpha, alpha, alpha == 1
            end
            discover()
        else
            restored = deactivate()
            active, character.enabled = false, false
        end
        notify()
        return true, not restored and "部分动作条需重新加载界面" or nil
    end
    if option(key) ~= value then
        character[key] = value
        if active then
            local editing = editMode()
            for _, state in pairs(managed) do refresh(state, editing) end
        end
        notify()
    end
    return true
end

local function tell(message)
    if type(print) == "function" then print("|cffffd27f升级工具箱|r " .. message) end
end

SLASH_TIGERIOACTIONBARS1 = "/tftbars"
SlashCmdList.TIGERIOACTIONBARS = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command ~= "" and command ~= "on" and command ~= "off" then
        tell("用 /tftbars on 或 /tftbars off 切换动作条样式。")
        return
    end
    local enable = command == "on" or (command == "" and not active)
    local ok, message = toolbox.setActionBarOption("enabled", enable)
    if not ok then tell(message or "动作条设置暂不可用。"); return end
    if message then tell(message); return end
    tell(enable and "动作条样式已启用。" or "动作条样式已关闭。")
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        if initialize() and active then discover() end
        notify()
    elseif initialized and active and (event ~= "ADDON_LOADED" or name ~= ADDON) then
        discover()
    end
end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not active or layoutSuspended then return end
    if not stillCurrent() then
        -- Do not leave invisible bars behind if another component replaces our data.
        if not safeCombat() then deactivate(); active = false end
        return
    end
    updateElapsed, scanElapsed = updateElapsed + elapsed, scanElapsed + elapsed
    if updateElapsed >= 0.1 then
        updateElapsed = 0
        local editing = editMode()
        for _, state in pairs(managed) do refresh(state, editing) end
    end
    if scanElapsed >= 5 then
        scanElapsed = 0
        discover()
    end
end)
