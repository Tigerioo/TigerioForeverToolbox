local addonName, toolbox = ...

local function versionText()
    local function read(getMetadata)
        if type(getMetadata) ~= "function" then return nil end
        local ok, value = pcall(getMetadata, addonName, "Version")
        if not ok then return nil end
        if type(issecretvalue) == "function" then
            local checked, secret = pcall(issecretvalue, value)
            if not checked or secret then return nil end
        end
        if type(value) ~= "string" or value == "" then return nil end
        return value:gsub("|", "||"):gsub("[\r\n]", " ")
    end
    return read(C_AddOns and C_AddOns.GetAddOnMetadata) or read(GetAddOnMetadata)
end

-- Use the Forever client's own window and tab artwork. The addon supplies no
-- Questie textures or code, and each page retains its existing behavior.
local pages = {
    {key = "globalui", name = "全局界面", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", method = "toggleGlobalUI", frame = "TigerioForeverToolboxGlobalUI"},
    {key = "hud", name = "战斗 HUD", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", method = "toggleHUDSettings", frame = "TigerioForeverToolboxHUDSettings"},
    {key = "calendar", name = "升级日历", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", method = "toggleCalendar", frame = "TigerioForeverToolboxFrame"},
    {key = "dungeon", name = "副本任务", icon = "Interface\\Icons\\INV_Misc_Map_01", method = "toggleDungeonGuide", frame = "TigerioForeverToolboxDungeonGuide"},
    {key = "weapon", name = "武器大师", icon = "Interface\\Icons\\INV_Sword_04", method = "toggleWeaponMasters", frame = "TigerioForeverToolboxWeaponMasters"},
    {key = "luck", name = "奇珍图鉴", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_05", method = "toggleLuckCollection", frame = "TigerioForeverToolboxLuckFrame"},
    {key = "companions", name = "同行记录", icon = "Interface\\Icons\\INV_Misc_Book_09", method = "toggleCompanions", frame = "TigerioForeverToolboxCompanionsFrame"},
    {key = "changelog", name = "更新日志", icon = "Interface\\Icons\\INV_Misc_Note_01", method = "toggleChangelog", frame = "TigerioForeverToolboxChangelog"},
}

-- All pages share the same outer geometry and the last position chosen by the
-- player. Existing FrameMover records remain untouched.
local WINDOW_WIDTH, WINDOW_HEIGHT = 800, 540
local sharedPosition, lastVisible

local function rememberPosition(frame)
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    if point and relative ~= frame then
        sharedPosition = {point, relative or UIParent, relativePoint or point, x or 0, y or 0}
    end
end

local function applyPosition(frame)
    if not sharedPosition or sharedPosition[2] == frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(sharedPosition[1], sharedPosition[2], sharedPosition[3], sharedPosition[4], sharedPosition[5])
    if type(toolbox.markFramePositionApplied) == "function" then
        toolbox.markFramePositionApplied(frame:GetName())
    end
end

function toolbox.createNativeWindow(name, title, width, height, page)
    local f = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
    -- Hide before installing OnHide so construction cannot replace a position
    -- captured from the previously visible page.
    f:Hide()
    f:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        rememberPosition(self)
    end)
    f:HookScript("OnShow", function(self)
        if lastVisible and lastVisible ~= self and lastVisible:IsShown() then
            rememberPosition(lastVisible)
        end
        applyPosition(self)
        lastVisible = self
    end)
    f:HookScript("OnHide", function(self) rememberPosition(self) end)
    f:SetTitle(title)
    local version = versionText()
    -- The native title container is a higher-level child than the window.
    -- Keep credits above that artwork while allowing clicks through to the title.
    local titleParent = f.TitleContainer or f
    local creditsLayer = CreateFrame("Frame", nil, titleParent)
    creditsLayer:SetAllPoints(titleParent)
    creditsLayer:SetFrameLevel(titleParent:GetFrameLevel() + 1)
    creditsLayer:EnableMouse(false)
    local credits = creditsLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    credits:SetPoint("TOPLEFT", f, "TOPLEFT", 515, -12)
    credits:SetWidth(220)
    credits:SetJustifyH("LEFT")
    if type(credits.SetWordWrap) == "function" then credits:SetWordWrap(false) end
    if type(credits.SetMaxLines) == "function" then credits:SetMaxLines(1) end
    credits:SetText(version and ("v" .. version .. " · 陌上猛虎") or "陌上猛虎")
    if f.Bg then f.Bg:SetColorTexture(30 / 255, 23 / 255, 18 / 255, 0.94) end
    if type(f.SetPortraitTextureRaw) == "function" then
        f:SetPortraitTextureRaw("Interface\\Icons\\INV_Misc_Book_09")
    end
    for index, entry in ipairs(pages) do
        local key, method, frameName, label = entry.key, entry.method, entry.frame, entry.name
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(52, 52)
        tab:SetPoint("TOPLEFT", f, "TOPRIGHT", -2, -36 - (index - 1) * 51)
        local background = tab:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas("common-sidetab", false)
        background:SetAllPoints()
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetSize(34, 34)
        icon:SetPoint("CENTER", -2, 0)
        icon:SetTexture(entry.icon)
        if key ~= page then icon:SetAlpha(0.75) end
        if key == page then
            local selected = tab:CreateTexture(nil, "OVERLAY")
            selected:SetAtlas("common-sidetab-selected", false)
            selected:SetAllPoints()
        end
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAtlas("common-sidetab-hover", false)
        hover:SetAllPoints()
        tab:SetScript("OnClick", function()
            if key == page then return end
            local open = toolbox[method]
            if type(open) == "function" then
                local target = _G[frameName]
                if key == "luck" and type(InCombatLockdown) == "function" and InCombatLockdown()
                    and not (target and target:IsShown()) then return end
                rememberPosition(f)
                f:Hide()
                if target and target:IsShown() then
                    applyPosition(target)
                    lastVisible = target
                    target:Raise()
                else
                    open()
                end
            end
        end)
        tab:SetScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label); GameTooltip:Show() end
        end)
        tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return f
end

function toolbox.nativeSection(parent, x, y, width, height)
    local section = CreateFrame("Frame", nil, parent, "NineSlicePanelTemplate")
    section:SetPoint("TOPLEFT", x, -y)
    section:SetSize(width, height)
    section:SetFrameLevel(parent:GetFrameLevel())
    if NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function" then
        NineSliceUtil.ApplyLayoutByName(section, "TooltipGluesLayout")
    end
    section:SetAlpha(0.7)
    return section
end

function toolbox.nativeDivider(parent, x, y, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider", false)
    line:SetPoint("TOPLEFT", x, -y)
    line:SetSize(width, 8)
    return line
end
