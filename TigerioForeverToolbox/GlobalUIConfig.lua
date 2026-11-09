local _, toolbox = ...
local window, message

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, locked = pcall(InCombatLockdown)
    if not ok or not readable(locked) then return true end
    return locked ~= nil and locked ~= false
end

local function label(parent, template, x, y, value)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", x, -y)
    text:SetJustifyH("LEFT")
    text:SetText(value or "")
    return text
end

local definitions = {
    {key = "map", title = "小地图样式", get = "getMapStyleEnabled", set = "setMapStyleEnabled"},
    {key = "chat", title = "聊天框样式", get = "getChatStyleEnabled", set = "setChatStyleEnabled"},
    {key = "group", title = "小队与团队样式", get = "getGroupStyleEnabled", set = "setGroupStyleEnabled"},
    {key = "partyFrames", title = "小队框体替换", get = "getPartyFramesEnabled", set = "setPartyFramesEnabled"},
    {key = "progress", title = "顶部经验条与底部装饰", get = "getProgressStyleEnabled", set = "setProgressStyleEnabled"},
    {key = "micro", title = "系统菜单样式", get = "getMicroStyleEnabled", set = "setMicroStyleEnabled"},
    {key = "sellJunk", title = "自动出售灰色物品", get = "getMerchantOptions", set = "setMerchantOption", option = "sellJunk", x = 420, y = 142},
    {key = "autoRepair", title = "自动修理", get = "getMerchantOptions", set = "setMerchantOption", option = "autoRepair", x = 420, y = 186},
    {key = "actionLayout", title = "启用独立动作条", get = "getActionBarLayoutEnabled", set = "setActionBarLayoutEnabled", x = 420, y = 244},
}

local function readOption(entry)
    local fn = toolbox[entry.get]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if ok and entry.option then
        if not readable(value) or type(value) ~= "table" then return nil end
        if type(canaccesstable) == "function" then
            local accessOK, accessible = pcall(canaccesstable, value)
            if not accessOK or not readable(accessible) or accessible ~= true then return nil end
        end
        ok, value = pcall(function() return value[entry.option] end)
    end
    if ok and readable(value) and type(value) == "boolean" then return value end
end

local function readActionBarRows()
    if type(toolbox.getActionBarLayoutRows) ~= "function" then return nil end
    local ok, value = pcall(toolbox.getActionBarLayoutRows)
    if ok and readable(value) and type(value) == "number" and value >= 1 and value <= 4
        and value == math.floor(value) then return value end
end

local function render()
    if not window or not window:IsShown() then return end
    local locked = inCombat()
    local unavailable, actionLayoutEnabled = false, nil
    for _, entry in ipairs(definitions) do
        local current = readOption(entry)
        if entry.key == "actionLayout" then actionLayoutEnabled = current end
        local check = window.checks[entry.key]
        check:SetChecked(current == true)
        if current == nil then unavailable = true end
        if current ~= nil and not locked then check:Enable() else check:Disable() end
    end
    local rows = readActionBarRows()
    if rows == nil then unavailable = true end
    for index, button in ipairs(window.rowButtons) do
        if rows == index then button.background:SetColorTexture(0.35, 0.25, 0.11, 1)
        else button.background:SetColorTexture(0.14, 0.105, 0.075, 0.95) end
        if rows and actionLayoutEnabled and not locked then button:Enable() else button:Disable() end
    end
    window.status:SetText(message or (locked and "战斗中无法调整" or (unavailable and "部分设置暂不可用" or "")))
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxGlobalUI", "Tigerio 的无限升级工具箱", 800, 540, "globalui")
    label(f, "GameFontNormalLarge", 70, 42, "全局界面")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 764, 417)
    label(f, "GameFontNormal", 420, 110, "商店")
    f.checks = {}
    for index, entry in ipairs(definitions) do
        local setting = entry
        local x, y = setting.x or 32, setting.y or (110 + (index - 1) * 44)
        local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", x, -y)
        label(f, "GameFontHighlight", x + 30, y + 4, setting.title)
        check:SetScript("OnClick", function(self)
            if inCombat() then message = "战斗中无法调整"; render(); return end
            local value = self:GetChecked()
            if not readable(value) then message = "设置暂不可用"; render(); return end
            local setter = toolbox[setting.set]
            local ok, result, reason = false, nil, nil
            if type(setter) == "function" then
                local checked = value == true or value == 1
                if setting.option then ok, result, reason = pcall(setter, setting.option, checked)
                else ok, result, reason = pcall(setter, checked) end
            end
            if not ok or result ~= true then
                message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "设置暂不可用"
            else
                message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or nil
            end
            render()
        end)
        f.checks[setting.key] = check
    end
    label(f, "GameFontNormal", 420, 280, "动作条行数")
    f.rowButtons = {}
    for index = 1, 4 do
        local rowCount = index
        local button = CreateFrame("Button", nil, f)
        button:SetSize(62, 27)
        button:SetPoint("TOPLEFT", 420 + (index - 1) * 68, -305)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.14, 0.105, 0.075, 0.95)
        button.background = bg
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.9, 0.67, 0.25, 0.18)
        local caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        caption:SetPoint("CENTER")
        caption:SetText(index .. " 行")
        button.caption = caption
        button:SetScript("OnClick", function()
            if inCombat() then message = "战斗中无法调整"; render(); return end
            local setter = toolbox.setActionBarLayoutRows
            local ok, success, reason = false, nil, nil
            if type(setter) == "function" then ok, success, reason = pcall(setter, rowCount) end
            if not ok or success ~= true then
                message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "设置暂不可用"
            else
                message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or nil
            end
            render()
        end)
        f.rowButtons[index] = button
    end
    f.status = label(f, "GameFontHighlightSmall", 32, 380, "")
    f.status:SetWidth(700)
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxGlobalUI"
    f:Hide()
    return f
end

function toolbox.toggleGlobalUI()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    render()
end

function toolbox.onGlobalUIChanged()
    render()
end

function toolbox.onActionBarLayoutChanged()
    render()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if not inCombat() then message = nil end
    render()
end)

SLASH_TIGERIOGLOBALUI1 = "/tftui"
SlashCmdList.TIGERIOGLOBALUI = toolbox.toggleGlobalUI
