-- BuffFrame owns only the player's helpful auras and their native controls.
-- Scale the frame rather than individual buttons so Blizzard's grid, duration
-- text and hit areas continue to use the same layout and update normally.
local BUFF_SCALE = 1.3
local scaledFrame

local function applyBuffScale()
    local frame = _G.BuffFrame
    if not frame or frame == scaledFrame or InCombatLockdown() then
        return
    end
    if type(frame.GetScale) ~= "function" or type(frame.SetScale) ~= "function" then
        return
    end

    local scale = frame:GetScale()
    if type(scale) ~= "number" or scale <= 0 then
        return
    end
    local success = pcall(frame.SetScale, frame, scale * BUFF_SCALE)
    if success then
        scaledFrame = frame
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addonName)
    if event ~= "ADDON_LOADED" or addonName == "Blizzard_BuffFrame" then
        applyBuffScale()
    end
end)
