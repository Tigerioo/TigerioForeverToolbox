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
    {key = "questPlateColor", title = "任务怪姓名条着色", get = "getQuestPlateColorEnabled", set = "setQuestPlateColorEnabled"},
    {key = "sellJunk", title = "自动出售灰色物品", get = "getMerchantOptions", set = "setMerchantOption", option = "sellJunk", x = 420, y = 142},
    {key = "autoRepair", title = "自动修理", get = "getMerchantOptions", set = "setMerchantOption", option = "autoRepair", x = 420, y = 186},
    {key = "actionLayout", title = "启用独立动作条", get = "getActionBarLayoutEnabled", set = "setActionBarLayoutEnabled", x = 420, y = 244},
    {key = "actionHoverAll", title = "动作条鼠标悬停时显示", get = "getActionBarHoverAll", set = "setActionBarHoverAll", x = 420, y = 342},
    {key = "focusFrame", title = "焦点框体替换", get = "getFocusFrameOptions", set = "setFocusFrameEnabled", valueField = "enabled", x = 420, y = 390},
    {key = "bagCooldown", title = "背包物品冷却栏", get = "getBagCooldownEnabled", set = "setBagCooldownEnabled", x = 32, y = 418},
}

local function readOption(entry)
    local fn = toolbox[entry.get]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    local valueField = entry.option or entry.valueField
    if ok and valueField then
        if not readable(value) or type(value) ~= "table" then return nil end
        if type(canaccesstable) == "function" then
            local accessOK, accessible = pcall(canaccesstable, value)
            if not accessOK or not readable(accessible) or accessible ~= true then return nil end
        end
        ok, value = pcall(function() return value[valueField] end)
    end
    if ok and readable(value) and type(value) == "boolean" then return value end
end

local function readActionBarRows()
    if type(toolbox.getActionBarLayoutRows) ~= "function" then return nil end
    local ok, value = pcall(toolbox.getActionBarLayoutRows)
    if ok and readable(value) and type(value) == "number" and value >= 1 and value <= 5
        and value == math.floor(value) then return value end
end

local function render()
    if not window or not window:IsShown() then return end
    local locked = inCombat()
    local unavailable, actionLayoutEnabled, partyFramesEnabled, focusFrameEnabled, bagCooldownEnabled = false, nil, nil, nil, nil
    for _, entry in ipairs(definitions) do
        local current = readOption(entry)
        if entry.key == "actionLayout" then actionLayoutEnabled = current end
        if entry.key == "partyFrames" then partyFramesEnabled = current end
        if entry.key == "focusFrame" then focusFrameEnabled = current end
        if entry.key == "bagCooldown" then bagCooldownEnabled = current end
        local check = window.checks[entry.key]
        check:SetChecked(current == true)
        if current == nil then unavailable = true end
        if current ~= nil and not locked and (entry.key ~= "actionHoverAll" or actionLayoutEnabled) then check:Enable() else check:Disable() end
    end
    local rows = readActionBarRows()
    if rows == nil then unavailable = true end
    for index, button in ipairs(window.rowButtons) do
        if rows == index then button.background:SetColorTexture(0.35, 0.25, 0.11, 1)
        else button.background:SetColorTexture(0.14, 0.105, 0.075, 0.95) end
        if rows and actionLayoutEnabled and not locked then button:Enable() else button:Disable() end
    end
    local unlocked = readOption({get = "getPartyFramesUnlocked"})
    window.partyMove.caption:SetText(unlocked and "锁定小队" or "移动小队")
    if unlocked ~= nil and partyFramesEnabled and not locked
        and type(toolbox.setPartyFramesUnlocked) == "function" then
        window.partyMove:Enable()
    else
        window.partyMove:Disable()
    end
    local focusUnlocked = readOption({get = "getFocusFrameOptions", valueField = "unlocked"})
    window.focusMove.caption:SetText(focusUnlocked and "锁定焦点" or "移动焦点")
    if focusUnlocked ~= nil and focusFrameEnabled and not locked
        and type(toolbox.setFocusFrameUnlocked) == "function" then
        window.focusMove:Enable()
    else
        window.focusMove:Disable()
    end
    local bagUnlocked = readOption({get = "getBagCooldownUnlocked"})
    window.bagCooldownMove.caption:SetText(bagUnlocked and "锁定冷却栏" or "移动冷却栏")
    if bagUnlocked ~= nil and bagCooldownEnabled and not locked
        and type(toolbox.setBagCooldownUnlocked) == "function" then
        window.bagCooldownMove:Enable()
    else
        window.bagCooldownMove:Disable()
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
    f.partyMove = CreateFrame("Button", nil, f)
    f.partyMove:SetSize(94, 24)
    f.partyMove:SetPoint("TOPLEFT", 240, -238)
    local moveBackground = f.partyMove:CreateTexture(nil, "BACKGROUND")
    moveBackground:SetAllPoints()
    moveBackground:SetColorTexture(0.14, 0.105, 0.075, 0.95)
    local moveHighlight = f.partyMove:CreateTexture(nil, "HIGHLIGHT")
    moveHighlight:SetAllPoints()
    moveHighlight:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    f.partyMove.caption = f.partyMove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.partyMove.caption:SetPoint("CENTER")
    f.partyMove:SetScript("OnClick", function()
        if inCombat() then message = "战斗中无法调整"; render(); return end
        local unlocked = readOption({get = "getPartyFramesUnlocked"})
        local setter = toolbox.setPartyFramesUnlocked
        local ok, success, reason = false, nil, nil
        if unlocked ~= nil and type(setter) == "function" then ok, success, reason = pcall(setter, not unlocked) end
        if not ok or success ~= true then
            message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "小队框体暂不可用"
        else
            message = nil
        end
        render()
    end)
    f.focusMove = CreateFrame("Button", nil, f)
    f.focusMove:SetSize(94, 24)
    f.focusMove:SetPoint("TOPLEFT", 630, -386)
    local focusBackground = f.focusMove:CreateTexture(nil, "BACKGROUND")
    focusBackground:SetAllPoints()
    focusBackground:SetColorTexture(0.14, 0.105, 0.075, 0.95)
    local focusHighlight = f.focusMove:CreateTexture(nil, "HIGHLIGHT")
    focusHighlight:SetAllPoints()
    focusHighlight:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    f.focusMove.caption = f.focusMove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.focusMove.caption:SetPoint("CENTER")
    f.focusMove:SetScript("OnClick", function()
        if inCombat() then message = "战斗中无法调整"; render(); return end
        local unlocked = readOption({get = "getFocusFrameOptions", valueField = "unlocked"})
        local setter = toolbox.setFocusFrameUnlocked
        local ok, success, reason = false, nil, nil
        if unlocked ~= nil and type(setter) == "function" then ok, success, reason = pcall(setter, not unlocked) end
        if not ok or success ~= true then
            message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "焦点框体暂不可用"
        else
            message = nil
        end
        render()
    end)
    f.bagCooldownMove = CreateFrame("Button", nil, f)
    f.bagCooldownMove:SetSize(94, 24)
    f.bagCooldownMove:SetPoint("TOPLEFT", 240, -418)
    local bagBackground = f.bagCooldownMove:CreateTexture(nil, "BACKGROUND")
    bagBackground:SetAllPoints()
    bagBackground:SetColorTexture(0.14, 0.105, 0.075, 0.95)
    local bagHighlight = f.bagCooldownMove:CreateTexture(nil, "HIGHLIGHT")
    bagHighlight:SetAllPoints()
    bagHighlight:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    f.bagCooldownMove.caption = f.bagCooldownMove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.bagCooldownMove.caption:SetPoint("CENTER")
    f.bagCooldownMove:SetScript("OnClick", function()
        if inCombat() then message = "战斗中无法调整"; render(); return end
        local unlocked = readOption({get = "getBagCooldownUnlocked"})
        local setter = toolbox.setBagCooldownUnlocked
        local ok, success, reason = false, nil, nil
        if unlocked ~= nil and type(setter) == "function" then ok, success, reason = pcall(setter, not unlocked) end
        if not ok or success ~= true then
            message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "冷却栏暂不可用"
        else
            message = nil
        end
        render()
    end)
    label(f, "GameFontNormal", 420, 280, "动作条行数")
    f.rowButtons = {}
    for index = 1, 5 do
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
    f.status = label(f, "GameFontHighlightSmall", 32, 450, "")
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
