local _, toolbox = ...
local driver = CreateFrame("Frame")
local handle = CreateFrame("Button", "TigerioForeverToolboxMoveHandle", UIParent, "UIPanelButtonTemplate")
handle:SetSize(160, 24)
handle:SetFrameStrata("TOOLTIP")
handle:SetClampedToScreen(true)
handle:RegisterForDrag("LeftButton")
handle:Hide()

local moving, selected, characterKey, positions
local enabled, ready, elapsed = false, false, 0
local applied = {}

-- A toolbox page positioned by its shared navigation should not later be
-- displaced by that page's older, independently saved position.
function toolbox.markFramePositionApplied(name)
    if type(name) == "string" then applied[name] = true end
end

local function say(message)
    print("|cffffd100升级工具箱|r " .. message)
end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

-- Never touch forbidden/secure frames, including objects encountered while
-- walking from the focused child to its root.
local function safe(frame)
    if not frame or frame == UIParent or frame == handle then return false end
    local ok, result = pcall(function()
        if not frame.IsObjectType or not frame:IsObjectType("Frame") then return false end
        if frame.IsForbidden and frame:IsForbidden() then return false end
        if frame.IsProtected and frame:IsProtected() then return false end
        return true
    end)
    return ok and result
end

local function topLevel(frame)
    while frame and frame ~= UIParent do
        if not safe(frame) then return nil end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok then return nil end
        if parent == UIParent then
            local success, name, visible = pcall(function() return frame:GetName(), frame:IsVisible() end)
            if success and type(name) == "string" and _G[name] == frame and visible then return frame end
            return nil
        end
        frame = parent
    end
end

local function position(frame)
    local x, y = frame:GetCenter()
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not x or not y or not scale or not parentScale or parentScale == 0 then return end
    return x * scale / parentScale, y * scale / parentScale
end

local function restore(name, pos)
    local frame = _G[name]
    if not safe(frame) or topLevel(frame) ~= frame or inCombat() then return false end
    if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number"
        or pos.x ~= pos.x or pos.y ~= pos.y or math.abs(pos.x) == math.huge or math.abs(pos.y) == math.huge then return false end
    local ok = pcall(function()
        local factor = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local halfWidth, halfHeight = frame:GetWidth() * factor / 2, frame:GetHeight() * factor / 2
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local x = math.max(math.min(halfWidth, width / 2), math.min(pos.x, width - halfWidth))
        local y = math.max(math.min(halfHeight, height / 2), math.min(pos.y, height - halfHeight))
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / factor, y / factor)
    end)
    return ok
end

local function restorePositions()
    if not ready or inCombat() or not positions then return end
    for name, pos in pairs(positions) do
        if not applied[name] and type(name) == "string" and restore(name, pos) then applied[name] = true end
    end
end

local function finishMove()
    if not moving then return end
    local state = moving
    moving = nil
    local frame = state.frame
    local ok = pcall(function()
        frame:StopMovingOrSizing()
        local x, y = position(frame)
        if x and y and positions then
            -- Store the screen position in UIParent coordinates, not the original
            -- relative frame, so late-loaded frames can be restored independently.
            positions[state.name] = {x = x, y = y}
            applied[state.name] = true
        end
        if frame.SetUserPlaced and state.userPlaced ~= nil then frame:SetUserPlaced(state.userPlaced) end
        if frame.SetMovable and state.movable == false then frame:SetMovable(false) end
    end)
    if not ok then say("框体停止移动失败；请退出战斗后重载界面。") end
end

handle:SetScript("OnDragStart", function()
    if not enabled or inCombat() or not selected or topLevel(selected) ~= selected then return end
    local frame = selected
    local ok, state = pcall(function()
        local userPlaced
        if frame.IsUserPlaced then userPlaced = frame:IsUserPlaced() end
        return {frame = frame, movable = frame:IsMovable(),
            userPlaced = userPlaced, name = frame:GetName()}
    end)
    if not ok then say("该框体无法移动。") return end
    local started = pcall(function() frame:SetMovable(true); frame:StartMoving() end)
    if started then
        moving = state
    else
        if state.movable == false then pcall(frame.SetMovable, frame, false) end
        say("该框体无法移动。")
    end
end)
handle:SetScript("OnDragStop", finishMove)
handle:SetScript("OnHide", finishMove)

local function selectFrame(frame)
    if not frame or frame == selected then return end
    selected = frame
    handle:ClearAllPoints()
    local top = frame:GetTop()
    local factor = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if top and top * factor + 26 > UIParent:GetHeight() then
        handle:SetPoint("TOP", frame, "TOP", 0, -2)
    else
        handle:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    end
    handle:SetText("拖动：" .. frame:GetName())
    handle:Show()
end

function toolbox.toggleFrameMove()
    if inCombat() then say("战斗中不能调整框体位置。") return end
    enabled = not enabled
    if enabled then
        say("框体移动已开启：鼠标移到窗口，再拖动其上方的手柄；再次输入命令退出。")
    else
        finishMove()
        selected = nil
        handle:Hide()
        say("框体移动已关闭。")
    end
end

function toolbox.resetFrameMoves()
    if inCombat() then say("战斗中不能重置框体位置。") return end
    if not ready then say("角色数据尚未就绪。") return end
    finishMove()
    TigerioForeverToolboxDB.framePositions[characterKey] = {}
    positions = TigerioForeverToolboxDB.framePositions[characterKey]
    applied = {}
    say("已清除当前角色由工具箱保存的位置；输入 /reload 应用系统和各插件自己的布局。")
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if type(TigerioForeverToolboxDB) ~= "table" then return end
        characterKey = UnitGUID("player") or ((GetRealmName() or "") .. "-" .. (UnitName("player") or ""))
        if type(TigerioForeverToolboxDB.framePositions) ~= "table" then TigerioForeverToolboxDB.framePositions = {} end
        if type(TigerioForeverToolboxDB.framePositions[characterKey]) ~= "table" then TigerioForeverToolboxDB.framePositions[characterKey] = {} end
        positions = TigerioForeverToolboxDB.framePositions[characterKey]
        ready = true
        restorePositions()
    elseif event == "PLAYER_REGEN_DISABLED" then
        finishMove()
        handle:Hide()
        selected = nil
    elseif event == "ADDON_LOADED" or event == "PLAYER_REGEN_ENABLED" then
        restorePositions()
    end
end)

driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    restorePositions()
    if not enabled or inCombat() or moving then return end
    if selected and (not safe(selected) or not selected:IsVisible()) then selected = nil; handle:Hide() end
    local focus
    if type(GetMouseFoci) == "function" then
        local list = GetMouseFoci()
        focus = type(list) == "table" and list[1]
    elseif type(GetMouseFocus) == "function" then
        focus = GetMouseFocus()
    end
    if focus ~= handle then selectFrame(topLevel(focus)) end
end)
