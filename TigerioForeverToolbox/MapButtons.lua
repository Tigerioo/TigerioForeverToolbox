-- Collect low-frequency minimap buttons without moving or reparenting them.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local active, elapsed = false, 0
local managed = {}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function locked()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end

local function allowed(frame)
    if not frame or not readable(frame) then return false end
    local ok, usable = pcall(function()
        return type(frame.GetAlpha) == "function" and type(frame.SetAlpha) == "function"
            and not (type(frame.IsForbidden) == "function" and frame:IsForbidden())
    end)
    return ok and readable(usable) and usable
end

local function alpha(frame)
    local ok, value = pcall(frame.GetAlpha, frame)
    if ok and readable(value) and type(value) == "number" then return value end
end

local function restore(frame, state)
    local value = alpha(frame)
    if value == 0 and state.owned then
        pcall(frame.SetAlpha, frame, state.original)
    end
    state.owned = false
end

local function collect()
    local found = {}
    local function add(frame)
        if allowed(frame) then found[frame] = true end
    end
    add(_G.ExpansionLandingPageMinimapButton)
    local backdrop = _G.MinimapBackdrop
    if backdrop and readable(backdrop) then
        local ok, frame = pcall(function() return backdrop.ExternalEventURLButton end)
        if ok then add(frame) end
    end
    local stub = _G.LibStub
    if stub then
        local ok, lib = pcall(function() return stub("LibDBIcon-1.0", true) end)
        if ok and lib then
            local listed, names = pcall(function() return lib:GetButtonList() end)
            if listed and type(names) == "table" and readable(names) then
                for _, name in ipairs(names) do
                    local got, button = pcall(function() return lib:GetMinimapButton(name) end)
                    if got and button and readable(button) then
                        -- LibDBIcon already owns these buttons' mouseover fade.
                        local canRead, ownFade = pcall(function() return button.showOnMouseover end)
                        if canRead and readable(ownFade) and not ownFade then add(button) end
                    end
                end
            end
        end
    end
    return found
end

local function mouseOver(frame)
    if not frame or not readable(frame) then return false end
    local ok, result = pcall(function()
        return type(frame.IsMouseOver) == "function" and frame:IsMouseOver()
    end)
    return ok and readable(result) and result == true
end

local function update()
    if locked() then return end
    local found = collect()
    for frame, state in pairs(managed) do
        if not found[frame] then restore(frame, state); managed[frame] = nil end
    end
    -- Pointer may move from the map onto a button just outside its bounds.
    local hover = mouseOver(_G.Minimap) or mouseOver(_G.MinimapCluster)
    if not hover then
        for frame in pairs(found) do
            if mouseOver(frame) then hover = true; break end
        end
    end
    for frame in pairs(found) do
        local state = managed[frame]
        local value = alpha(frame)
        if value then
            if hover then
                if state then restore(frame, state); managed[frame] = nil end
            elseif value ~= 0 then
                -- A newer third-party alpha takes precedence over the saved value.
                state = state or {}
                state.original, state.owned = value, true
                managed[frame] = state
                if not pcall(frame.SetAlpha, frame, 0) then managed[frame] = nil end
            end
        end
    end
end

function toolbox.setMapButtonsCollapsed(value)
    if type(value) ~= "boolean" or locked() then return false end
    active = value
    if active then
        elapsed = 0
        driver:Show()
        update()
    else
        for frame, state in pairs(managed) do restore(frame, state) end
        managed = {}
        driver:Hide()
    end
    return true
end

driver:SetScript("OnUpdate", function(_, delta)
    if not active then return end
    elapsed = elapsed + delta
    if elapsed >= 0.15 then elapsed = 0; update() end
end)
driver:Hide()
