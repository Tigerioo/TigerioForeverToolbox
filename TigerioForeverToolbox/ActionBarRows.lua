-- Independent action buttons. Never modify permanent key bindings or action slots.
local addonID, toolbox = ...
local driver = CreateFrame("Frame")
local character, controller, nativeHolder, panel, rows
local active, elapsed, pendingStart = false, 0, false
local owned = {}
local unsupportedFlyouts = {}
local pressTextures, pressed, pressHooks = {}, {}, {}
local REPLACEMENT_BLOCKED = false
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\SlotFrame.tga"
local SIZE, GAP, BOTTOM, BOTTOM_WITH_ACCESSORIES = 38, 3, 8, 64
local definitions = {
    {"MainActionBar", "ACTIONBUTTON", 1},
    {"MultiBarBottomLeft", "MULTIACTIONBAR1BUTTON", 6},
    {"MultiBarBottomRight", "MULTIACTIONBAR2BUTTON", 5},
    {"MultiBarRight", "MULTIACTIONBAR3BUTTON", 3},
    {"MultiBarLeft", "MULTIACTIONBAR4BUTTON", 4},
    {"MultiBar5", "MULTIACTIONBAR5BUTTON", 13},
    {"MultiBar6", "MULTIACTIONBAR6BUTTON", 14},
    {"MultiBar7", "MULTIACTIONBAR7BUTTON", 15},
}

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

local function locked()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end

local function identity()
    local value = call(UnitGUID, "player")
    if readable(value) and type(value) == "string" and value:match("^Player%-") then return value end
end

local function initialize()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not readable(db) or type(db) ~= "table" or not guid then return false end
    if db.actionBarRows == nil then db.actionBarRows = {version = 1, characters = {}} end
    local data = db.actionBarRows
    if not readable(data) or type(data) ~= "table" or data.version ~= 1 or type(data.characters) ~= "table" then return false end
    local entry = data.characters[guid]
    if entry == nil then entry = {enabled = true, rows = 1}; data.characters[guid] = entry end
    if type(entry) ~= "table" or type(entry.enabled) ~= "boolean" or type(entry.rows) ~= "number"
        or entry.rows < 1 or entry.rows > 4 or entry.rows ~= math.floor(entry.rows) then return false end
    character = entry
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    return character and guid and type(db) == "table" and type(db.actionBarRows) == "table"
        and type(db.actionBarRows.characters) == "table" and db.actionBarRows.characters[guid] == character
end

local function notify()
    if type(toolbox.onActionBarLayoutChanged) == "function" then pcall(toolbox.onActionBarLayoutChanged) end
end

local function moveAllowed()
    if locked() then return false end
    local lock
    if Settings and type(Settings.GetValue) == "function" then lock = call(Settings.GetValue, "lockActionBars") end
    if lock == false then return true end
    return type(IsModifiedClick) == "function" and call(IsModifiedClick, "PICKUPACTION") == true
end

local function actionID(button)
    local id = call(button.GetAttribute, button, "action")
    if readable(id) and type(id) == "number" and id > 0 then return id end
end

-- Key bindings continue through Blizzard's original action buttons. Observe
-- those functions after they run and animate only our own texture regions.
local function clearPressed()
    for texture in pairs(pressed) do
        pcall(texture.Hide, texture)
        pressed[texture] = nil
    end
end

local function markPressed(rowIndex, index, down)
    if not readable(index) or type(index) ~= "number" or index < 1 or index > 12 or index ~= math.floor(index) then return end
    local row = rows and rows[rowIndex]
    local button = row and row.buttons[index]
    local texture = button and pressTextures[button]
    if not texture then return end
    if not down then
        pcall(texture.Hide, texture)
        pressed[texture] = nil
        return
    end
    if not active or not character or rowIndex > character.rows or not panel or type(panel.IsVisible) ~= "function" then return end
    local ok, visible = pcall(panel.IsVisible, panel)
    if not ok or not readable(visible) or visible ~= true then return end
    if pcall(texture.Show, texture) then pressed[texture] = 0 end
end

local function installPressHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local function hook(name, handler)
        if pressHooks[name] or type(_G[name]) ~= "function" then return end
        if pcall(hooksecurefunc, name, handler) then pressHooks[name] = true end
    end
    hook("ActionButtonDown", function(index) markPressed(1, index, true) end)
    hook("ActionButtonUp", function(index) markPressed(1, index, false) end)
    local function multi(barName, index, down)
        if not readable(barName) or type(barName) ~= "string" then return end
        for i = 2, #definitions do
            if definitions[i][1] == barName then markPressed(i, index, down); return end
        end
    end
    hook("MultiActionButtonDown", function(barName, index) multi(barName, index, true) end)
    hook("MultiActionButtonUp", function(barName, index) multi(barName, index, false) end)
end

-- Blizzard uses GetBindingText(key, 1) for localized action-button labels.
-- Compact common physical keys further so modifier combinations fit a slot.
local function bindingLabel(key)
    if not readable(key) or type(key) ~= "string" or key == "" then return "" end
    local localized = call(GetBindingText, key, 1)
    if not readable(localized) or type(localized) ~= "string" or localized == "" then localized = key end

    local modifiers, rest = "", key
    local modifierNames = {SHIFT = "s-", CTRL = "c-", ALT = "a-", META = "m-"}
    while true do
        local modifier, nextKey = rest:match("^([A-Z]+)%-(.+)$")
        local short = modifier and modifierNames[modifier]
        if not short then break end
        modifiers, rest = modifiers .. short, nextKey
    end

    local names = {
        MOUSEWHEELUP = "MWU", MOUSEWHEELDOWN = "MWD",
        SPACE = "空格", TAB = "Tab", ENTER = "回车", BACKSPACE = "退格",
        PAGEUP = "Pg↑", PAGEDOWN = "Pg↓", INSERT = "Ins", DELETE = "Del",
        HOME = "Home", END = "End", UP = "↑", DOWN = "↓", LEFT = "←", RIGHT = "→",
        NUMPADDECIMAL = "N.", NUMPADDIVIDE = "N/", NUMPADMULTIPLY = "N*",
        NUMPADMINUS = "N-", NUMPADPLUS = "N+", NUMPADENTER = "N↵",
    }
    local compact = names[rest]
    if not compact then
        local mouse = rest:match("^BUTTON(%d+)$")
        local numpad = rest:match("^NUMPAD(%d)$")
        if mouse then compact = "M" .. mouse
        elseif numpad then compact = "N" .. numpad
        elseif rest:match("^[A-Z0-9]$") or rest:match("^F%d%d?$") or rest == "-" or rest == "=" then compact = rest end
    end
    -- Preserve localized text for keys not covered above; do not truncate UTF-8.
    local result = compact and (modifiers .. compact) or localized
    return (result:gsub("|", "||"):gsub("[\r\n]", " "))
end

local function refreshButton(button)
    local action = actionID(button)
    if not action then return end
    local api = C_ActionBar
    local texture = call(api and api.GetActionTexture or GetActionTexture, action)
    if not readable(texture) then
        -- Texture objects accept protected values even when Lua cannot inspect them.
        if pcall(button.icon.SetTexture, button.icon, texture) then button.icon:Show() end
    elseif (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
        button.icon:SetTexture(texture); button.icon:Show()
    else
        button.icon:Hide()
    end
    -- A popup field assigned from addon Lua taints the protected action path.
    -- Until a secure flyout setup is verified, identify unsupported flyouts.
    local kind = call(api and api.GetActionInfo or GetActionInfo, action)
    local unsupported = readable(kind) and kind == "flyout"
    unsupportedFlyouts[button] = unsupported
    button.unavailableText:SetText(unsupported and "禁用" or "")
    if button.Arrow then button.Arrow:Hide() end
    local usable, noPower = call(api and api.IsUsableAction or IsUsableAction, action)
    if readable(usable) and readable(noPower) and usable == false then
        if noPower then button.icon:SetVertexColor(0.4, 0.4, 1) else button.icon:SetVertexColor(0.4, 0.4, 0.4) end
    else
        local inRange = call(api and api.IsActionInRange or IsActionInRange, action)
        if readable(inRange) and (inRange == false or inRange == 0) then
            button.icon:SetVertexColor(0.8, 0.15, 0.15)
        else button.icon:SetVertexColor(1, 1, 1) end
    end
    if unsupported then button.icon:SetVertexColor(0.4, 0.4, 0.4) end
    local duration = call(api and api.GetActionCooldownDuration, action)
    if (not readable(duration) or duration ~= nil) and type(button.cooldown.SetCooldownFromDurationObject) == "function"
        and pcall(button.cooldown.SetCooldownFromDurationObject, button.cooldown, duration) then
        -- Duration objects also support restricted cooldowns.
    else
        local start, length = call(api and api.GetActionCooldown or GetActionCooldown, action)
        if readable(start) and type(start) == "table" then
            local ok, a, b = pcall(function() return start.startTime, start.duration end)
            if ok then start, length = a, b else start, length = nil, nil end
        end
        if readable(start) and readable(length) and type(start) == "number" and type(length) == "number" then
            pcall(button.cooldown.SetCooldown, button.cooldown, start, length)
        else pcall(button.cooldown.Clear, button.cooldown) end
    end
    local count = call(api and api.GetActionCount or GetActionCount, action)
    if readable(count) and type(count) == "number" and count > 1 then button.count:SetText(tostring(count))
    else button.count:SetText("") end
end

local function refresh()
    if not active or not rows then return end
    for i, row in ipairs(rows) do
        if i <= character.rows then for _, button in ipairs(row.buttons) do refreshButton(button) end end
    end
end

local function makeButton(row, rowIndex, index)
    local name = "TigerioForeverActionBar" .. rowIndex .. "Button" .. index
    -- Flyout template must come first: the secure template supplies OnClick.
    local button = CreateFrame("Button", name, row, "FlyoutButtonTemplate,SecureActionButtonTemplate")
    button:SetID(0)
    button:SetSize(SIZE, SIZE)
    button:SetPoint("LEFT", row, "LEFT", (index - 1) * (SIZE + GAP), 0)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "action")
    button:SetAttribute("checkselfcast", true)
    button:SetAttribute("checkfocuscast", true)
    if not SpellFlyout or type(button.SetPopupDirection) ~= "function" then
        error("system flyout unavailable")
    end
    -- Do not set button.popup from addon Lua. The client reads it from the
    -- secure action path even for ordinary skills; A/B testing confirmed taint.
    button:SetPopupDirection("UP")
    if button.Arrow then button.Arrow:Hide() end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- The mouse uses the native button state; keyboard feedback is a separate
    -- region because the original system button receives the actual key.
    local mousePressed = button:CreateTexture(nil, "ARTWORK", nil, 6)
    mousePressed:SetAllPoints(icon)
    mousePressed:SetColorTexture(0, 0, 0, 0.42)
    button:SetPushedTexture(mousePressed)
    local keyPressed = button:CreateTexture(nil, "ARTWORK", nil, 7)
    keyPressed:SetAllPoints(icon)
    keyPressed:SetColorTexture(0, 0, 0, 0.42)
    keyPressed:Hide()
    pressTextures[button] = keyPressed
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(button); border:SetTexture(MEDIA)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    hotkey:SetPoint("TOPRIGHT", -4, -4)
    hotkey:SetSize(SIZE - 8, 10)
    if type(hotkey.SetJustifyH) == "function" then hotkey:SetJustifyH("RIGHT") end
    if type(hotkey.SetJustifyV) == "function" then hotkey:SetJustifyV("MIDDLE") end
    if type(hotkey.SetWordWrap) == "function" then hotkey:SetWordWrap(false) end
    if type(hotkey.SetMaxLines) == "function" then hotkey:SetMaxLines(1) end
    if type(hotkey.SetNonSpaceWrap) == "function" then hotkey:SetNonSpaceWrap(false) end
    local unavailableText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unavailableText:SetPoint("CENTER")
    unavailableText:SetText("")
    button.icon, button.cooldown, button.count, button.hotkey, button.unavailableText = icon, cooldown, count, hotkey, unavailableText
    button:SetScript("OnEnter", function(self)
        local action = actionID(self)
        if action and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetAction(action)
            if unsupportedFlyouts[self] and type(GameTooltip.AddLine) == "function" then
                GameTooltip:AddLine("该技能菜单暂不可用", 1, 0.35, 0.25, true)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function(self)
        local action = actionID(self)
        if action and moveAllowed() and type(PickupAction) == "function" then pcall(PickupAction, action) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        local action = actionID(self)
        if action and not locked() and type(PlaceAction) == "function" then pcall(PlaceAction, action) end
    end)
    return button
end

local function build()
    if controller then return true end
    if locked() or type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then return false end
    local control = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetAllPoints(UIParent); holder:Hide()
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(SIZE * 12 + GAP * 11, SIZE)
    -- Keep the old clearance until the menu and bag bar have been hidden.
    root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM_WITH_ACCESSORIES)
    root:Hide()
    local madeRows = {}
    for r, def in ipairs(definitions) do
        local row = CreateFrame("Frame", nil, root)
        row:SetSize(SIZE * 12 + GAP * 11, SIZE)
        row:SetPoint("BOTTOM", root, "BOTTOM", 0, (r - 1) * (SIZE + GAP))
        row.buttons = {}
        local native = _G[def[1]]
        local page = native and call(native.GetAttribute, native, "actionpage") or nil
        if not readable(page) or type(page) ~= "number" or page < 1 then page = def[3] end
        for i = 1, 12 do
            local button = makeButton(row, r, i)
            button:SetAttribute("action", (page - 1) * 12 + i)
            row.buttons[i] = button
            if r == 1 then control:SetFrameRef("main" .. i, button) end
        end
        madeRows[r] = row
    end
    control:SetFrameRef("holder", holder); control:SetFrameRef("panel", root)
    control:SetAttribute("_onstate-mode", [[
        self:SetAttribute("layoutMode", newstate)
        local holder, panel = self:GetFrameRef("holder"), self:GetFrameRef("panel")
        if newstate == "normal" then holder:Hide(); panel:Show()
        else panel:Hide(); holder:Show() end
    ]])
    control:SetAttribute("_onstate-page", [[
        local page = tonumber(newstate) or 1
        for i = 1, 12 do
            local button = self:GetFrameRef("main"..i)
            if button then button:SetAttribute("action", (page - 1) * 12 + i) end
        end
    ]])
    controller, nativeHolder, panel, rows = control, holder, root, madeRows
    return true
end

local function restoreNative()
    local complete = true
    for frame, previous in pairs(owned) do
        local parent = call(frame.GetParent, frame)
        if parent == nativeHolder or not readable(parent) or parent == nil then
            local ok = pcall(frame.SetParent, frame, previous)
            if ok and call(frame.GetParent, frame) == previous then owned[frame] = nil else complete = false end
        elseif readable(parent) and parent ~= nil then
            -- Another addon took ownership; leave its choice untouched.
            owned[frame] = nil
        else complete = false end
    end
    return complete
end

local function hideNative()
    if not _G.MainActionBar then return false end
    for _, def in ipairs(definitions) do
        local frame = _G[def[1]]
        if frame then
            local parent = call(frame.GetParent, frame)
            local forbidden = type(frame.IsForbidden) == "function" and call(frame.IsForbidden, frame)
            if not readable(parent) or parent ~= UIParent or not readable(forbidden) or forbidden then
                restoreNative(); return false
            end
            -- Record before mutation so even an unreadable post-check is recoverable.
            owned[frame] = parent
            local ok = pcall(frame.SetParent, frame, nativeHolder)
            local newParent = call(frame.GetParent, frame)
            if not ok or newParent ~= nativeHolder then
                pcall(frame.SetParent, frame, parent)
                restoreNative(); return false
            end
        end
    end
    return true
end

-- Keep the menu and bag bar in the same secure visibility holder as the
-- native action bars: they return in vehicle/override modes and on stop.
-- Never reparent their shared container, which can own other protected UI.
local function hideAccessories()
    -- In the Forever client MicroMenu belongs to MicroMenuContainer, not
    -- UIParent. Keep that relationship intact so Blizzard can update it.
    local menu, menuContainer, bags = _G.MicroMenu, _G.MicroMenuContainer, _G.BagsBar
    if not menu or not menuContainer or not bags or menuContainer == bags
        or call(menu.GetParent, menu) ~= menuContainer then return false, true end
    local moved = {}
    local function rollback()
        for movedFrame, oldParent in pairs(moved) do
            if call(movedFrame.GetParent, movedFrame) == oldParent
                or (pcall(movedFrame.SetParent, movedFrame, oldParent) and call(movedFrame.GetParent, movedFrame) == oldParent) then
                owned[movedFrame] = nil
            end
        end
        for movedFrame in pairs(moved) do if owned[movedFrame] then return false, false end end
        return false, true
    end
    for _, frame in ipairs({menuContainer, bags}) do
        local parent = call(frame.GetParent, frame)
        local forbidden = type(frame.IsForbidden) == "function" and call(frame.IsForbidden, frame)
        if not readable(parent) or parent ~= UIParent or not readable(forbidden) or forbidden or owned[frame] then
            return rollback()
        end
        owned[frame], moved[frame] = parent, parent
        if not pcall(frame.SetParent, frame, nativeHolder) or call(frame.GetParent, frame) ~= nativeHolder then
            return rollback()
        end
    end
    return true, true
end

local function updateRows()
    if not rows then return end
    clearPressed()
    for r, row in ipairs(rows) do
        local show = r <= character.rows
        -- Invisible rows must not intercept mouse input.
        row:SetAlpha(show and 1 or 0)
        for _, button in ipairs(row.buttons) do button:EnableMouse(show) end
    end
end

local function updateBindings()
    if not rows then return end
    for r, def in ipairs(definitions) do
        for i = 1, 12 do
            local command, button = def[2] .. i, rows[r].buttons[i]
            local key = call(GetBindingKey, command)
            button.hotkey:SetText(bindingLabel(key))
        end
    end
end

local function stop()
    if not controller then return true end
    clearPressed()
    local modeOK = pcall(UnregisterStateDriver, controller, "mode")
    local pageOK = pcall(UnregisterStateDriver, controller, "page")
    local panelOK = pcall(panel.Hide, panel)
    local ok = restoreNative()
    if ok and type(toolbox.suspendNativeActionBarStyle) == "function" then
        ok = toolbox.suspendNativeActionBarStyle(false)
    end
    if ok then active = false end
    return ok and modeOK and pageOK and panelOK
end

local function start(diagnostic)
    -- The safety gate can prevent takeover without altering saved preferences.
    if REPLACEMENT_BLOCKED and diagnostic ~= true then return false, "独立动作条暂不可用" end
    if locked() then return false, "请在脱战后调整动作条" end
    local ok, made = pcall(build)
    if not ok or not made then return false, "独立动作条暂不可用" end
    if next(owned) and not restoreNative() then return false, "系统动作条恢复失败，请重新加载界面" end
    if type(toolbox.suspendNativeActionBarStyle) ~= "function"
        or not toolbox.suspendNativeActionBarStyle(true) then return false, "系统动作条无法安全接管" end
    if not hideNative() then
        toolbox.suspendNativeActionBarStyle(false)
        return false, next(owned) and "系统动作条恢复失败，请重新加载界面" or "系统动作条无法安全接管"
    end
    local accessoriesHidden, accessoriesRestored = hideAccessories()
    if not accessoriesRestored then
        pcall(stop)
        return false, "系统菜单恢复失败，请重新加载界面"
    end
    local success = pcall(function()
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, accessoriesHidden and BOTTOM or BOTTOM_WITH_ACCESSORIES)
        updateRows()
        RegisterStateDriver(controller, "page", "[bonusbar:5,bar:1] 11; [bonusbar:4,bar:1] 10; [bonusbar:3,bar:1] 9; [bonusbar:2,bar:1] 8; [bonusbar:1,bar:1] 7; [bar:6] 6; [bar:5] 5; [bar:4] 4; [bar:3] 3; [bar:2] 2; 1")
        RegisterStateDriver(controller, "mode", "[vehicleui][overridebar][possessbar][petbattle] special; normal")
        active = true
        installPressHooks()
        updateBindings()
        refresh()
    end)
    if not success then
        pcall(stop)
        return false, "独立动作条初始化失败"
    end
    return true
end

-- A manual, one-shot probe only. The normal startup and settings paths remain
-- blocked, and the existing saved preference is not touched.
local diagnosticAttempted, diagnosticCaptured, diagnosticListener = false, false, nil
local function diagnosticPrint(message)
    if type(print) == "function" then print("|cffffd27f升级工具箱诊断|r " .. message) end
end

SLASH_TFTBARPROBE1 = "/tftbarprobe"
SlashCmdList.TFTBARPROBE = function()
    if diagnosticAttempted then
        diagnosticPrint("本次诊断已启动，请输入 /reload 恢复。")
        return
    end
    if locked() then
        diagnosticPrint("请先脱离战斗，再输入 /tftbarprobe。")
        return
    end
    if not current() then
        diagnosticPrint("角色设置暂不可用，请输入 /reload 后重试。")
        return
    end
    diagnosticAttempted = true
    local listener = CreateFrame("Frame")
    local ok1, result1 = pcall(listener.RegisterEvent, listener, "ADDON_ACTION_BLOCKED")
    local ok2, result2 = pcall(listener.RegisterEvent, listener, "ADDON_ACTION_FORBIDDEN")
    if not ok1 or result1 == false or not ok2 or result2 == false then
        if type(listener.UnregisterAllEvents) == "function" then pcall(listener.UnregisterAllEvents, listener) end
        diagnosticPrint("无法监听受保护操作，请输入 /reload 恢复。")
        return
    end
    diagnosticListener = listener
    listener:SetScript("OnEvent", function(self, event, addonName, functionName)
        if not readable(addonName) or type(addonName) ~= "string" or addonName ~= addonID then return end
        local name = "未知"
        if readable(functionName) and type(functionName) == "string" and functionName ~= "" then
            name = functionName:gsub("[\r\n|]", " "):sub(1, 160)
        end
        diagnosticCaptured = true
        diagnosticPrint(event .. "：" .. name .. "。请记录此行，然后输入 /reload 恢复。")
        if type(self.UnregisterAllEvents) == "function" then self:UnregisterAllEvents() end
    end)
    diagnosticPrint("正在启动一次性诊断，可能再次弹窗；输入 /reload 可恢复。")
    local success, started, reason = pcall(start, true)
    if not success or not started then
        -- A failure can occur part-way through takeover. Try to restore, but
        -- leave reload as the final recovery path if a protected call fails.
        local cleanupOK, restored = pcall(stop)
        local message = readable(reason) and type(reason) == "string" and reason or "诊断动作条无法启动"
        if not cleanupOK or not restored then message = message .. "，系统动作条恢复未完成" end
        diagnosticPrint(message .. "；请输入 /reload 恢复。")
        return
    end
    if not diagnosticCaptured then
        diagnosticPrint("请点击一次底部动作条；可能再次弹窗。记录诊断内容后输入 /reload 恢复。")
    end
end

-- Isolated comparison: no native bar is moved, no action is fired by Lua,
-- and no override binding is used. The sole difference is SetPopup.
local abPanel, abButtons, abListener, abSlot, abKind, abActionID, abMode
local function abPrint(message)
    if type(print) == "function" then print("|cffffd27f动作条对照|r " .. message) end
end

local function abActionUsable(slot)
    local info = type(GetActionInfo) == "function" and GetActionInfo or (C_ActionBar and C_ActionBar.GetActionInfo)
    local kind, id = call(info, slot)
    local usable = call(C_ActionBar and C_ActionBar.IsUsableAction or IsUsableAction, slot)
    if not readable(kind) or not readable(id) or not readable(usable) then return false end
    return kind == "spell" and type(id) == "number" and id > 0 and usable == true, kind, id
end

local function abFindAction()
    for slot = 1, 12 do
        local usable, kind, id = abActionUsable(slot)
        if usable then return slot, kind, id end
    end
end

local function abCreate(slot, kind, id)
    if not SpellFlyout then return false end
    local listener = CreateFrame("Frame")
    local ok1, result1 = pcall(listener.RegisterEvent, listener, "ADDON_ACTION_BLOCKED")
    local ok2, result2 = pcall(listener.RegisterEvent, listener, "ADDON_ACTION_FORBIDDEN")
    if not ok1 or result1 == false or not ok2 or result2 == false then
        if type(listener.UnregisterAllEvents) == "function" then pcall(listener.UnregisterAllEvents, listener) end
        return false
    end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(180, 90)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:Hide()
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", panel, "TOP", 0, -3)
    local buttons = {}
    for _, mode in ipairs({"a", "b"}) do
        local button = CreateFrame("Button", nil, panel, "FlyoutButtonTemplate,SecureActionButtonTemplate")
        button:SetID(0)
        button:SetSize(48, 48)
        button:SetPoint("BOTTOM", panel, "BOTTOM", 0, 5)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "action")
        button:SetAttribute("checkselfcast", true)
        button:SetAttribute("checkfocuscast", true)
        button:SetAttribute("action", slot)
        if type(button.SetPopup) ~= "function" or type(button.SetPopupDirection) ~= "function" then error("flyout unavailable") end
        button:SetPopupDirection("UP")
        if mode == "b" then button:SetPopup(SpellFlyout) end
        if button.Arrow then button.Arrow:Hide() end
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        local texture = call(C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture, slot)
        if not readable(texture) or texture ~= nil then pcall(icon.SetTexture, icon, texture) end
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(button)
        border:SetTexture(MEDIA)
        button:SetScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetAction(slot); GameTooltip:Show() end
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        button:Hide()
        buttons[mode] = button
    end
    listener:SetScript("OnEvent", function(_, event, addonName, functionName)
        if not readable(addonName) or type(addonName) ~= "string" or addonName ~= addonID then return end
        local value = "未知"
        if readable(functionName) and type(functionName) == "string" and functionName ~= "" then
            value = functionName:gsub("[\r\n|]", " "):sub(1, 160)
        end
        abPrint("测试 " .. (abMode or "未知") .. "：" .. event .. "：" .. value)
    end)
    abPanel, abButtons, abListener, abSlot, abKind, abActionID = panel, buttons, listener, slot, kind, id
    abPanel.label = label
    return true
end

SLASH_TFTBARAB1 = "/tftbarab"
SlashCmdList.TFTBARAB = function(message)
    if locked() then abPrint("请脱离战斗后再测试。") return end
    if type(GetCursorInfo) ~= "function" then abPrint("鼠标状态不可用，无法安全测试。") return end
    local cursorOK, cursor = pcall(GetCursorInfo)
    if not cursorOK or not readable(cursor) or cursor ~= nil then
        abPrint("请先放下鼠标上的物品或技能。") return
    end
    local mode = type(message) == "string" and message:match("^%s*([aAbB])%s*$")
    if not mode then abPrint("输入 /tftbarab a 或 /tftbarab b；/reload 退出。") return end
    mode = mode:lower()
    if not abPanel then
        local slot, kind, id = abFindAction()
        if not slot then abPrint("主动作条前 12 格没有可用的普通技能。") return end
        local ok, made = pcall(abCreate, slot, kind, id)
        if not ok or not made then abPrint("对照按钮创建失败；请输入 /reload。") return end
    else
        local usable, kind, id = abActionUsable(abSlot)
        if not usable or kind ~= abKind or id ~= abActionID then
            abPanel:Hide()
            abPrint("测试动作已变化或不可用；请输入 /reload 后重试。")
            return
        end
    end
    abButtons.a:Hide(); abButtons.b:Hide()
    abMode = mode:upper()
    abPanel.label:SetText("动作测试 " .. abMode)
    abPanel:Show(); abButtons[mode]:Show()
    local secure = "未知"
    if type(issecurevariable) == "function" then
        local ok, value = pcall(issecurevariable, abButtons[mode], "popup")
        if ok and readable(value) and type(value) == "boolean" then secure = value and "安全" or "不安全" end
    end
    abPrint("测试 " .. abMode .. "：popup " .. secure .. "；点击中央技能一次，记录是否弹窗；/reload 退出。")
end

-- Manual comparison of Blizzard's native action-button flyout handling.
-- It never touches the original bars, saved settings or keyboard bindings.
local flyoutProbePanel, flyoutProbeButtons, flyoutProbeListener, flyoutProbeMode
local flyoutProbeSlots, flyoutProbeIDs, flyoutProbeUsed = {}, {}, false
local function flyoutProbePrint(message)
    if type(print) == "function" then print("|cffffd27f飞出菜单诊断|r " .. message) end
end

local function flyoutProbeInfo(slot)
    local getter = type(GetActionInfo) == "function" and GetActionInfo or (C_ActionBar and C_ActionBar.GetActionInfo)
    if type(getter) ~= "function" then return nil, nil, false end
    local ok, kind, id = pcall(getter, slot)
    if not ok or not readable(kind) or not readable(id) then return nil, nil, false end
    if kind ~= nil and type(kind) ~= "string" then return nil, nil, false end
    return kind, id, true
end

local function flyoutProbeCreate()
    -- The native template's OnLoad reads slot 1 before attributes are set.
    -- Never construct it when that could write a flyout popup insecurely.
    local first, _, known = flyoutProbeInfo(1)
    if not known or first == "flyout" then return false, "请先将主动作条第 1 格留空或放普通技能。" end
    local normal, flyout
    for slot = 1, 12 do
        local kind, id, ok = flyoutProbeInfo(slot)
        if not ok then return false, "动作条数据暂不可读取。" end
        local usable = kind == "spell" and call(C_ActionBar and C_ActionBar.IsUsableAction or IsUsableAction, slot)
        if kind == "spell" and type(id) == "number" and id > 0 and readable(usable) and usable == true and not normal then normal = slot end
        if kind == "flyout" and type(id) == "number" and id > 0 and not flyout then flyout = slot end
    end
    if not normal or not flyout then return false, "请在主动作条前 12 格各放一个可用的普通技能和飞出技能。" end
    if not SpellFlyout or type(issecurevariable) ~= "function" then return false, "客户端诊断接口不可用。" end

    local listener, panel
    local ok, reason = pcall(function()
        listener = CreateFrame("Frame")
        for _, event in ipairs({"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"}) do
            local registered, value = pcall(listener.RegisterEvent, listener, event)
            if not registered or value == false then error("event unavailable") end
        end
        panel = CreateFrame("Frame", nil, UIParent)
        panel:SetSize(180, 90); panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0); panel:Hide()
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOP", panel, "TOP", 0, -3)
        local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        if type(header.Execute) ~= "function" then error("secure handler unavailable") end
        local buttons = {}
        for _, mode in ipairs({"a", "b"}) do
            local slot = mode == "a" and normal or flyout
            local button = CreateFrame("CheckButton", "TigerioForeverFlyoutProbe" .. mode:upper(), panel,
                "ActionButtonTemplate,SecureActionButtonTemplate")
            button:SetID(0); button:SetSize(48, 48)
            button:SetPoint("BOTTOM", panel, "BOTTOM", 0, 5)
            button:RegisterForClicks("AnyUp", "AnyDown")
            button:Hide()
            header:SetFrameRef("test", button)
            header:Execute(("local b = self:GetFrameRef('test'); b:SetAttribute('type','none'); b:SetAttribute('action',%d); b:SetAttribute('flyoutDirection','UP'); b:SetAttribute('type','action')"):format(slot))
            if call(button.GetAttribute, button, "type") ~= "action"
                or call(button.GetAttribute, button, "action") ~= slot
                or call(button.GetAttribute, button, "flyoutDirection") ~= "UP" then
                error("secure action initialization incomplete")
            end
            local secureOK, secure = pcall(issecurevariable, button, "popup")
            if not secureOK or not readable(secure) or secure ~= true then error("popup is not secure") end
            local popupOK, popup = pcall(function() return button.popup end)
            if not popupOK or not readable(popup) or (mode == "b" and popup ~= SpellFlyout)
                or (mode == "a" and popup ~= nil) then error("unexpected flyout popup") end
            local texture = call(C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture, slot)
            if button.icon and (not readable(texture) or texture ~= nil) then pcall(button.icon.SetTexture, button.icon, texture) end
            buttons[mode] = button
            local _, id = flyoutProbeInfo(slot)
            flyoutProbeSlots[mode], flyoutProbeIDs[mode] = slot, id
        end
        listener:SetScript("OnEvent", function(_, event, addonName, functionName)
            if not readable(addonName) or type(addonName) ~= "string" or addonName ~= addonID then return end
            local name = "未知"
            if readable(functionName) and type(functionName) == "string" and functionName ~= "" then
                name = functionName:gsub("[\r\n|]", " "):sub(1, 160)
            end
            flyoutProbePrint("测试 " .. (flyoutProbeMode or "未知") .. "：" .. event .. "：" .. name)
        end)
        flyoutProbePanel, flyoutProbeButtons, flyoutProbeListener = panel, buttons, listener
        flyoutProbePanel.label = label
    end)
    if not ok then
        if listener and type(listener.UnregisterAllEvents) == "function" then pcall(listener.UnregisterAllEvents, listener) end
        if panel then pcall(panel.Hide, panel) end
        return false, "飞出按钮未通过安全检查，请 /reload。"
    end
    return true
end

SLASH_TFTFLYOUTPROBE1 = "/tftflyoutprobe"
SlashCmdList.TFTFLYOUTPROBE = function(message)
    if locked() then flyoutProbePrint("请脱离战斗后再测试。"); return end
    if type(GetCursorInfo) ~= "function" then flyoutProbePrint("鼠标状态不可用。"); return end
    local cursorOK, cursor = pcall(GetCursorInfo)
    if not cursorOK or not readable(cursor) or cursor ~= nil then flyoutProbePrint("请先放下鼠标上的物品或技能。"); return end
    local mode = type(message) == "string" and message:match("^%s*([aAbB])%s*$")
    if not mode then flyoutProbePrint("输入 /tftflyoutprobe a 或 /tftflyoutprobe b；/reload 退出。"); return end
    mode = mode:lower()
    if not flyoutProbePanel then
        if flyoutProbeUsed then flyoutProbePrint("请先输入 /reload。"); return end
        flyoutProbeUsed = true
        local ok, why = flyoutProbeCreate()
        if not ok then flyoutProbePrint(why); return end
    end
    local kind, id, known = flyoutProbeInfo(flyoutProbeSlots[mode])
    if not known or id ~= flyoutProbeIDs[mode] or kind ~= (mode == "a" and "spell" or "flyout") then
        flyoutProbePanel:Hide(); flyoutProbePrint("测试动作已变化，请 /reload 后重试。"); return
    end
    flyoutProbeButtons.a:Hide(); flyoutProbeButtons.b:Hide()
    flyoutProbeMode = mode:upper()
    flyoutProbePanel.label:SetText(mode == "a" and "普通技能测试" or "飞出菜单测试")
    flyoutProbePanel:Show(); flyoutProbeButtons[mode]:Show()
    flyoutProbePrint("测试 " .. flyoutProbeMode .. "：popup 安全；点击中央按钮，完成后 /reload。")
end

function toolbox.getActionBarLayoutEnabled()
    if not current() then return nil, "动作条设置暂不可用" end
    return active
end

function toolbox.getActionBarLayoutRows()
    if not current() then return nil, "动作条设置暂不可用" end
    return character.rows
end

function toolbox.setActionBarLayoutEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "动作条设置暂不可用" end
    if REPLACEMENT_BLOCKED then return false, "独立动作条暂不可用" end
    if locked() then return false, "请在脱战后调整动作条" end
    if value == active then character.enabled = value; return true end
    local success, ok, why
    if value then success, ok, why = pcall(start)
    else success, ok = pcall(stop); why = "系统动作条恢复失败，请重新加载界面" end
    if not success then ok, why = false, "独立动作条暂不可用，请重新加载界面" end
    if not ok then notify(); return false, why end
    character.enabled = value
    notify()
    return true
end

function toolbox.setActionBarLayoutRows(value)
    if type(value) ~= "number" or value < 1 or value > 4 or value ~= math.floor(value) then return false, "行数无效" end
    if not current() then return false, "动作条设置暂不可用" end
    if REPLACEMENT_BLOCKED then return false, "独立动作条暂不可用" end
    if locked() then return false, "请在脱战后调整动作条" end
    character.rows = value
    if rows then updateRows() end
    refresh()
    notify()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if initialize() and character.enabled then
            if locked() then pendingStart = true
            else
                local ok, why = start()
                if not ok and type(print) == "function" then print("|cffffd27f升级工具箱|r " .. (why or "独立动作条不可用")) end
            end
        end
        notify()
    elseif event == "UPDATE_BINDINGS" then
        clearPressed()
        if active then installPressHooks(); updateBindings() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingStart then
            pendingStart = false
            if character and character.enabled and not active then
                local ok, why = start()
                if not ok and type(print) == "function" then print("|cffffd27f升级工具箱|r " .. (why or "独立动作条不可用")) end
                notify()
            end
        end
        refresh()
    else
        if event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
            clearPressed()
            if active then installPressHooks() end
        end
        refresh()
    end
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not active then return end
    if next(pressed) and panel and type(panel.IsVisible) == "function" then
        local ok, visible = pcall(panel.IsVisible, panel)
        if not ok or not readable(visible) or visible ~= true then clearPressed() end
    end
    -- A lost key-up (for example after switching windows) must not leave a
    -- visual stuck indefinitely. This affects only the highlight, not input.
    for texture, age in pairs(pressed) do
        age = age + delta
        if age >= 2 then pcall(texture.Hide, texture); pressed[texture] = nil
        else pressed[texture] = age end
    end
    if not current() then if not locked() then stop(); notify() end; return end
    elapsed = elapsed + delta
    if elapsed >= 0.25 then elapsed = 0; refresh() end
end)
