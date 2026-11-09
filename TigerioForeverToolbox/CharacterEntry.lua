-- Independent shortcut below the character window's native mode tabs.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local entry, character, tabs, anchored, pending, elapsed = nil, nil, nil, nil, false, 0
local ICON = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\ToolboxIcon.tga"
local pages = {"TigerioForeverToolboxFrame", "TigerioForeverToolboxDungeonGuide",
    "TigerioForeverToolboxWeaponMasters", "TigerioForeverToolboxLuckFrame",
    "TigerioForeverToolboxCompanionsFrame", "TigerioForeverToolboxHUDSettings",
    "TigerioForeverToolboxGlobalUI", "TigerioForeverToolboxChangelog"}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function field(object, key)
    if not readable(object) or not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok and readable(value) then return value end
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end

local function shown(frame)
    if not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, value = pcall(frame.IsShown, frame)
    return ok and readable(value) and value == true
end

local function openToolbox()
    -- Keep a single toolbox page visible if the shortcut is pressed twice or
    -- the player already has another toolbox page open.
    for _, name in ipairs(pages) do
        local page = _G[name]
        if shown(page) then
            if type(page.Raise) == "function" then pcall(page.Raise, page) end
            return
        end
    end
    if type(toolbox.toggleCalendar) == "function" then toolbox.toggleCalendar() end
end

-- Other addons sometimes add a sibling tab. Do not anchor to a frame whose
-- anchors already depend on our own entry, which would create a cycle.
local function dependsOnEntry(frame, seen, depth)
    if frame == entry then return true end
    if not frame or seen[frame] then return false end
    if depth > 16 then return true end
    seen[frame] = true
    if type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then return true end
    local ok, count = pcall(frame.GetNumPoints, frame)
    if not ok or not readable(count) or type(count) ~= "number" or count < 0 or count > 32 then return true end
    for index = 1, count do
        local got, _, relative = pcall(frame.GetPoint, frame, index)
        if not got or not readable(relative) then return true end
        if relative and dependsOnEntry(relative, seen, depth + 1) then return true end
    end
    return false
end

local function position(frame)
    if not frame then return end
    local ok, left, bottom, width, height = pcall(function()
        return frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    end)
    if ok and readable(left) and readable(bottom) and readable(width) and readable(height)
        and type(left) == "number" and type(bottom) == "number"
        and type(width) == "number" and type(height) == "number"
        and width >= 20 and width <= 100 and height >= 20 and height <= 100 then
        return left, bottom
    end
end

local function lastVisibleTab()
    local native = field(tabs, "Tabs")
    if type(native) ~= "table" then return nil end
    if type(canaccesstable) == "function" then
        local ok, allowed = pcall(canaccesstable, native)
        if not ok or not readable(allowed) or allowed ~= true then return nil end
    end
    local last
    for _, tab in ipairs(native) do
        if tab ~= entry and shown(tab) then last = tab end
    end
    if not last then return nil end
    local refLeft, bottom = position(last)
    if not refLeft or not bottom or type(tabs.GetChildren) ~= "function" then return last end
    local ok, children = pcall(function() return {tabs:GetChildren()} end)
    if not ok or type(children) ~= "table" then return last end
    for _, candidate in ipairs(children) do
        if candidate ~= entry and shown(candidate) then
            local left, candidateBottom = position(candidate)
            if left and candidateBottom and math.abs(left - refLeft) <= 12 and candidateBottom < bottom
                and not dependsOnEntry(candidate, {}, 0) then
                last, bottom = candidate, candidateBottom
            end
        end
    end
    return last
end

local function arrange()
    if not entry or not character or not tabs then return end
    if combat() then pending = true; return end
    local last = lastVisibleTab()
    if not last then pcall(entry.Hide, entry); anchored = nil; return end
    if last ~= anchored then
        local ok = pcall(function()
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
        end)
        if not ok then pending = true; return end
        anchored = last
    end
    pcall(entry.Show, entry)
    pending = false
end

local function initialize()
    local parent = _G.CharacterFrame
    local modeTabs = field(parent, "ModeTabs")
    if not parent or not modeTabs or type(field(modeTabs, "Tabs")) ~= "table" then return end
    if entry and (parent ~= character or modeTabs ~= tabs) then
        if combat() then pending = true; return end
        pcall(entry.Hide, entry)
        entry, anchored = nil, nil
    end
    character, tabs = parent, modeTabs
    if entry then arrange(); return end
    if combat() then pending = true; return end
    local candidate
    local ok, created = pcall(function()
        local tab = CreateFrame("Frame", nil, tabs, "LargeSideTabButtonTemplate")
        candidate = tab
        tab:Hide()
        tab:EnableMouse(true)
        tab.tooltipText = "升级工具箱"
        tab.Icon:SetTexture(ICON)
        tab:SetFillToInterior(true, 50)
        tab:SetChecked(false)
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside then openToolbox() end
        end)
        return tab
    end)
    if not ok or not created then
        if candidate then pcall(candidate.Hide, candidate) end
        pending = true
        return
    end
    entry = created
    if type(hooksecurefunc) == "function" and type(character.UpdateTabLayout) == "function" then
        pcall(hooksecurefunc, character, "UpdateTabLayout", arrange)
    end
    if type(character.HookScript) == "function" then
        pcall(character.HookScript, character, "OnShow", arrange)
    end
    arrange()
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then initialize() end
    else
        initialize()
    end
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not character or not shown(character) then return end
    elapsed = elapsed + delta
    if elapsed < 1 then return end
    elapsed = 0
    initialize()
end)
