-- A passive warrior stance indicator. It never changes protected actions.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
-- Validate the form by spell ID rather than depending on the order of forms.
local WARRIOR_STANCES = {[2457] = true, [71] = true, [2458] = true}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function activeStanceTexture()
    if type(GetNumShapeshiftForms) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then return nil end
    local ok, count = pcall(GetNumShapeshiftForms)
    if not ok or not readable(count) or type(count) ~= "number"
        or count ~= math.floor(count) or count < 1 or count > 100 then return nil end
    local result, found = nil, false
    for index = 1, count do
        local valid, texture, active, _, spellID = pcall(GetShapeshiftFormInfo, index)
        if not valid or not readable(active) then return nil end
        if active == true or active == 1 then
            if found or not readable(spellID) or type(spellID) ~= "number" then return nil end
            found = true
            if WARRIOR_STANCES[spellID] and readable(texture)
                and ((type(texture) == "number" and texture > 0)
                    or (type(texture) == "string" and texture ~= "")) then
                result = texture
            end
        end
    end
    return result
end

function toolbox.attachWarriorStance(hud)
    if not hud or not hud.primary or type(UnitClass) ~= "function" then return false end
    if hud.warriorStance then return true end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or not readable(class) or class ~= "WARRIOR" then return false end

    local badge = CreateFrame("Frame", nil, hud.primary)
    badge:SetSize(80, 48)
    -- Sink the crest into the upper rim without covering the resource number.
    badge:SetPoint("CENTER", hud.primary, "TOP", 0, -4)
    badge:EnableMouse(false)
    if hud.primary.fill and type(hud.primary.fill.GetFrameLevel) == "function"
        and type(badge.SetFrameLevel) == "function" then
        badge:SetFrameLevel(hud.primary.fill:GetFrameLevel() + 2)
    end
    local crest = badge:CreateTexture(nil, "BACKGROUND")
    crest:SetAllPoints()
    crest:SetTexture(MEDIA .. "StanceCrest.tga")
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(31, 31)
    icon:SetPoint("CENTER", badge, "CENTER", 0, 2)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    -- Keep the native square icon inside the round crest. If the client
    -- cannot create the mask, leave the indicator hidden rather than expose
    -- square corners over the orb.
    local masked = false
    if type(badge.CreateMaskTexture) == "function" and type(icon.AddMaskTexture) == "function" then
        masked = pcall(function()
            local mask = badge:CreateMaskTexture()
            mask:SetAllPoints(icon)
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            icon:AddMaskTexture(mask)
            badge.mask = mask
        end)
    end
    badge.icon = icon
    badge:SetAlpha(0)
    hud.warriorStance = badge

    local function update()
        local texture = masked and activeStanceTexture()
        if texture and pcall(icon.SetTexture, icon, texture) then
            badge:SetAlpha(1)
        else
            badge:SetAlpha(0)
        end
    end

    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
        "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", update)
    if type(hud.HookScript) == "function" then hud:HookScript("OnShow", update) end
    badge.events = events
    update()
    return true
end
