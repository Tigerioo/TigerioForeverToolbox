-- A permanent, lightweight shortcut; it is not registered with LibDBIcon,
-- so the minimap's optional button collection does not hide it.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local button, attachedMap, pending
local ICON = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\ToolboxIcon.tga"
local pages = {
    "TigerioForeverToolboxFrame", "TigerioForeverToolboxDungeonGuide",
    "TigerioForeverToolboxWeaponMasters", "TigerioForeverToolboxLuckFrame",
    "TigerioForeverToolboxCompanionsFrame", "TigerioForeverToolboxHUDSettings",
    "TigerioForeverToolboxChangelog",
}

local function openConfig()
    if type(toolbox.toggleGlobalUI) ~= "function" then return end
    local config = _G.TigerioForeverToolboxGlobalUI
    if not config or not config:IsShown() then
        for _, name in ipairs(pages) do
            local page = _G[name]
            if page and page:IsShown() then page:Hide() end
        end
    end
    toolbox.toggleGlobalUI()
end

local function setup()
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then pending = true; return end
    local map = _G.Minimap
    if not map then pending = true; return end
    if button and attachedMap == map then return end
    local ok = pcall(function()
        if not button then
            local f = CreateFrame("Button", "TigerioForeverToolboxMinimapButton", map)
            button = f
            f:SetSize(31, 31)
            f:RegisterForClicks("LeftButtonUp")
            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("TOPLEFT", 7, -5)
            icon:SetTexture(ICON)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local border = f:CreateTexture(nil, "OVERLAY")
            border:SetSize(53, 53)
            border:SetPoint("TOPLEFT")
            border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            f:SetScript("OnClick", openConfig)
            f:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetText("升级工具箱")
                    GameTooltip:Show()
                end
            end)
            f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        else
            button:SetParent(map)
        end
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", -5, -3)
        button:SetFrameLevel(map:GetFrameLevel() + 10)
        button:Show()
    end)
    if ok then attachedMap, pending = map, false else pending = true end
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" or pending then setup() end
end)
