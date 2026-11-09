-- Experimental only. This file is deliberately absent from the addon TOC.
-- It does not hide or move Blizzard bars, change bindings, or write saved data.
-- Not a replacement: original bars can overlap/intercept clicks; secure paging,
-- combat, protected values, cooldowns, drag/drop, override and vehicle behavior
-- require validation on the actual Forever client before any integration.
local _, toolbox = ...
local root, rows, driver, running = nil, {}, nil, false
local requestedRows = 1
local SLOT_SIZE, GAP, BOTTOM = 38, 3, 18
local TEX = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\SlotFrame.tga"
-- Main bar is dynamic; the other rows use the standard multibar pages.
local pages = {nil, 6, 5, 3}

local function locked()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, result = pcall(InCombatLockdown)
    return not ok or (result ~= nil and result ~= false)
end

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function slotID(button)
    local id = call(button.GetAttribute, button, "action")
    if readable(id) and type(id) == "number" and id > 0 then return id end
end

local function refreshButton(button)
    local action = slotID(button)
    if not action then return end
    local api = C_ActionBar
    local texture = call(api and api.GetActionTexture or GetActionTexture, action)
    if readable(texture) and (type(texture) == "number" or type(texture) == "string") then
        button.icon:SetTexture(texture)
        button.icon:Show()
    else
        button.icon:Hide()
    end
    local usable, noPower = call(api and api.IsUsableAction or IsUsableAction, action)
    if readable(usable) and readable(noPower) and usable == false then
        if noPower then button.icon:SetVertexColor(0.4, 0.4, 1)
        else button.icon:SetVertexColor(0.4, 0.4, 0.4) end
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
    local duration = call(api and api.GetActionCooldownDuration, action)
    if readable(duration) and duration and type(button.cooldown.SetCooldownFromDurationObject) == "function" then
        pcall(button.cooldown.SetCooldownFromDurationObject, button.cooldown, duration)
    else
        local start, length = call(api and api.GetActionCooldown or GetActionCooldown, action)
        if readable(start) and type(start) == "table" then
            local ok, beginTime, span = pcall(function() return start.startTime, start.duration end)
            if ok then start, length = beginTime, span else start, length = nil, nil end
        end
        if readable(start) and readable(length) and type(start) == "number" and type(length) == "number" then
            pcall(button.cooldown.SetCooldown, button.cooldown, start, length)
        else
            pcall(button.cooldown.Clear, button.cooldown)
        end
    end
end

local function refresh()
    if not running then return end
    for _, row in ipairs(rows) do
        for _, button in ipairs(row.buttons) do refreshButton(button) end
    end
end

local function moveAllowed()
    if locked() then return false end
    if Settings and type(Settings.GetValue) == "function" then
        local value = call(Settings.GetValue, "lockActionBars")
        if value == true then return type(IsModifiedClick) == "function" and IsModifiedClick("PICKUPACTION") end
        return value == false
    end
    -- When the lock state cannot be read, only allow the explicit pickup modifier.
    return type(IsModifiedClick) == "function" and IsModifiedClick("PICKUPACTION") == true
end

local function makeButton(row, index)
    local button = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    button:SetID(0) -- SecureActionButtonMixin resolves the explicit action attribute.
    button:SetSize(SLOT_SIZE, SLOT_SIZE)
    button:SetPoint("LEFT", row, "LEFT", (index - 1) * (SLOT_SIZE + GAP), 0)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "action")
    button:SetAttribute("checkselfcast", true)
    button:SetAttribute("checkfocuscast", true)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(button)
    border:SetTexture(TEX)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    button.icon, button.cooldown = icon, cooldown
    button:SetScript("OnEnter", function(self)
        local action = slotID(self)
        if action and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetAction(action)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function(self)
        local action = slotID(self)
        if action and moveAllowed() and type(PickupAction) == "function" then pcall(PickupAction, action) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        local action = slotID(self)
        if action and not locked() and type(PlaceAction) == "function" then pcall(PlaceAction, action) end
    end)
    return button
end

local function build()
    if root then return true end
    if locked() or type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then return false end
    local panel = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    panel:Hide()
    panel:SetSize(SLOT_SIZE * 12 + GAP * 11, SLOT_SIZE)
    panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM)
    for r = 1, 4 do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(SLOT_SIZE * 12 + GAP * 11, SLOT_SIZE)
        row:SetPoint("BOTTOM", panel, "BOTTOM", 0, (r - 1) * (SLOT_SIZE + GAP))
        row.buttons = {}
        for i = 1, 12 do
            local button = makeButton(row, i)
            button:SetAttribute("action", ((pages[r] or 1) - 1) * 12 + i)
            row.buttons[i] = button
            if r == 1 then panel:SetFrameRef("button" .. i, button) end
        end
        rows[r] = row
    end
    panel:SetAttribute("_onstate-page", [[
        local page = tonumber(newstate) or 1
        for i = 1, 12 do
            local button = self:GetFrameRef("button" .. i)
            if button then button:SetAttribute("action", (page - 1) * 12 + i) end
        end
    ]])
    RegisterStateDriver(panel, "page", "[bonusbar:5] 11; [bonusbar:4] 10; [bonusbar:3] 9; [bonusbar:2] 8; [bonusbar:1] 7; [bar:6] 6; [bar:5] 5; [bar:4] 4; [bar:3] 3; [bar:2] 2; 1")
    root = panel
    return true
end

function toolbox.getActionBarLayoutRows()
    return requestedRows
end

function toolbox.setActionBarLayoutRows(value)
    if type(value) ~= "number" or value < 1 or value > 4 or value ~= math.floor(value) then return false, "行数无效" end
    if locked() then return false, "请在脱战后调整动作条" end
    requestedRows = value
    if root then for i, row in ipairs(rows) do if running and i <= value then row:Show() else row:Hide() end end end
    if type(toolbox.onActionBarLayoutChanged) == "function" then pcall(toolbox.onActionBarLayoutChanged) end
    refresh()
    return true
end

-- Explicit opt-in only. The native bars remain visible and retain all bindings.
function toolbox.startActionBarRowsPrototype()
    if locked() then return false, "请在脱战后调整动作条" end
    local ok, success = pcall(build)
    if not ok or not success then return false, "动作条原型无法创建" end
    running = true
    root:Show()
    -- Hide only our prototype when the client switches to a special action UI.
    local registered = pcall(RegisterStateDriver, root, "visibility", "[vehicleui][overridebar][possessbar][petbattle] hide; show")
    if not registered then running = false; root:Hide(); return false, "动作条原型无法创建" end
    toolbox.setActionBarLayoutRows(requestedRows)
    refresh()
    return true
end

function toolbox.stopActionBarRowsPrototype()
    if locked() then return false, "请在脱战后调整动作条" end
    running = false
    if root then UnregisterStateDriver(root, "visibility"); root:Hide() end
    return true
end

driver = CreateFrame("Frame")
for _, event in ipairs({"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "PLAYER_ENTERING_WORLD"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", refresh)
local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    if not running then return end
    elapsed = elapsed + delta
    if elapsed >= 0.25 then elapsed = 0; refresh() end
end)
