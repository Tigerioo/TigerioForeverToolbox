local _, toolbox = ...
local window, button, pageText, notice
local candidates, page, valid = {}, 1, false
local interaction = {}
local canSecure = type(RegisterStateDriver) == "function"

-- Only slots with one unambiguous destination are eligible for one-click use.
local singleSlots = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10, INVTYPE_CLOAK = 15,
}

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function say(message)
    print("|cffffd100升级工具箱|r " .. message)
end

local function isReadable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function visibleInteraction()
    for _ in pairs(interaction) do return true end
    for _, name in ipairs({"MerchantFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame",
        "AuctionFrame", "TradeFrame", "MailFrame", "VoidStorageFrame", "ItemUpgradeFrame",
        "ItemInteractionFrame", "ProfessionsFrame"}) do
        local f = _G[name]
        if f and type(f.IsShown) == "function" and f:IsShown() then return true end
    end
    if C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType
        and Enum and type(Enum.PlayerInteractionType) == "table" then
        for _, kind in pairs(Enum.PlayerInteractionType) do
            if type(kind) == "number" then
                local ok, active = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, kind)
                if not ok or not isReadable(active) or active then return true end
            end
        end
    end
    return false
end

local function safeCandidate(item)
    if not valid or inCombat() then return false, "当前不能装备，请稍后重新检查。" end
    if not canSecure or type(SecureCmdItemParse) ~= "function" then return false, "无法确认安全装备接口，请手动装备。" end
    if not item or type(item.link) ~= "string" or type(item.itemID) ~= "number"
        or type(item.bag) ~= "number" or type(item.bagSlot) ~= "number"
        or type(item.inventorySlot) ~= "number" or singleSlots[item.equipLoc] ~= item.inventorySlot then
        return false, "该部位无法确定替换位置，请手动装备。"
    end
    if visibleInteraction() then return false, "请先关闭商人、银行或其他交互窗口。" end
    if (type(CursorHasItem) == "function" and CursorHasItem())
        or (type(SpellIsTargeting) == "function" and SpellIsTargeting()) then
        return false, "请先清空鼠标上的物品或取消法术目标。"
    end
    if not C_Container or type(C_Container.GetContainerItemInfo) ~= "function"
        or type(C_Container.GetContainerNumSlots) ~= "function" or not C_Item
        or type(C_Item.GetItemInfo) ~= "function" or type(C_Item.IsEquippableItem) ~= "function"
        or type(C_Item.IsUsableItem) ~= "function" or type(C_Item.IsEquippedItem) ~= "function"
        or type(C_Item.GetDetailedItemLevelInfo) ~= "function"
        or type(GetInventoryItemLink) ~= "function" or type(GetInventoryItemID) ~= "function" then
        return false, "物品接口不可用，请手动装备。"
    end
    local parseOK, parsed, bag, slot = pcall(SecureCmdItemParse, item.link)
    local itemString = item.link:match("|H(item:[^|]+)|h")
    if not parseOK or not isReadable(parsed) or not itemString or bag or slot
        or (parsed ~= item.link and parsed ~= itemString) then
        return false, "无法确认完整物品链接，请手动装备。"
    end
    local info = C_Container.GetContainerItemInfo(item.bag, item.bagSlot)
    if not info or info.itemID ~= item.itemID or info.hyperlink ~= item.link or info.isLocked then
        return false, "背包物品已变化，请等待重新检查。"
    end
    local equipped = GetInventoryItemLink("player", item.inventorySlot)
    if not equipped or equipped ~= item.originalLink then return false, "已穿装备发生变化，请等待重新检查。" end
    local name, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(item.link)
    if type(name) ~= "string" or equipLoc ~= item.equipLoc
        or not C_Item.IsEquippableItem(item.link) or not C_Item.IsUsableItem(item.link)
        or C_Item.IsEquippedItem(item.link) then
        return false, "无法确认物品可装备，请手动检查。"
    end
    local newLevel, oldLevel = C_Item.GetDetailedItemLevelInfo(item.link), C_Item.GetDetailedItemLevelInfo(equipped)
    if type(newLevel) ~= "number" or type(oldLevel) ~= "number" or newLevel <= oldLevel then
        return false, "装等资料已变化，请重新检查。"
    end

    -- EquipItemByName must not have another equally named or same-ID choice.
    local maxBag = math.max(NUM_BAG_SLOTS or 4, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0)
    for b = 0, maxBag do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local other = C_Container.GetContainerItemInfo(b, s)
            if other and (b ~= item.bag or s ~= item.bagSlot) then
                if not other.itemID then return false, "其他背包物品资料未加载，请手动检查。" end
                local otherName = C_Item.GetItemInfo(other.hyperlink or other.itemID)
                if type(otherName) ~= "string" then return false, "其他背包物品资料未加载，请手动检查。" end
                if other.itemID == item.itemID or otherName == name then return false, "存在同名或同编号物品，请手动选择。" end
            end
        end
    end
    for s = 1, 19 do
        local otherID = GetInventoryItemID("player", s)
        if otherID then
            local otherLink = GetInventoryItemLink("player", s)
            local otherName = otherLink and C_Item.GetItemInfo(otherLink)
            if type(otherName) ~= "string" then return false, "已穿装备资料未加载，请手动检查。" end
            if otherID == item.itemID or otherName == name then return false, "存在同名或同编号装备，请手动选择。" end
        end
    end
    return true
end

local function check(item)
    local ok, allowed, reason = pcall(safeCandidate, item)
    if not ok then return false, "无法安全核验物品，请手动装备。" end
    return allowed, reason
end

local function clearAction()
    if not button or not canSecure or inCombat() then return end
    button:SetAttribute("type1", nil)
    button:SetAttribute("item1", nil)
end

local function render()
    if not window or inCombat() then return end
    clearAction()
    local item = candidates[page]
    if not valid or not item then window:Hide(); return end
    button.item = item
    button.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.title:SetText(item.link or "未知物品")
    button.diff:SetText("装等 +" .. tostring(item.difference or "?") .. "  ·  请核对属性与效果")
    pageText:SetText(page .. " / " .. #candidates)
    local allowed, reason = check(item)
    if allowed then
        button:SetAttribute("item1", item.link)
        button:SetAttribute("type1", "item")
        notice:SetText("左键装备 · 悬停查看属性")
    else
        notice:SetText(reason or "请手动装备。")
    end
    if canSecure then window:SetAttribute("hasCandidates", true) end
    window:Show()
end

local function changePage(offset)
    if inCombat() or #candidates == 0 then return end
    page = ((page - 1 + offset) % #candidates) + 1
    render()
end

local function createWindow()
    local template = canSecure and "BackdropTemplate,SecureHandlerStateTemplate" or "BackdropTemplate"
    local f = CreateFrame("Frame", "TigerioForeverToolboxGearPopup", UIParent, template)
    f:SetSize(370, 140)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not inCombat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if not inCombat() then self:StopMovingOrSizing() end end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = {left = 6, right = 6, top = 6, bottom = 6},
    })
    f:SetBackdropColor(0.27, 0.22, 0.18, 0.98)
    f:SetBackdropBorderColor(1, 1, 1, 1)

    -- Decorative layers are built with the window, which is only created out of combat.
    local header = f:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 9, -7)
    header:SetPoint("TOPRIGHT", -9, -7)
    header:SetHeight(29)
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    header:SetVertexColor(0.7, 0.6, 0.48, 0.95)
    local divider = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    divider:SetPoint("TOPLEFT", 12, -30)
    divider:SetPoint("TOPRIGHT", -12, -30)
    divider:SetAtlas("Options_HorizontalDivider", false)
    divider:SetHeight(2)
    local iconBacking = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconBacking:SetPoint("TOPLEFT", 10, -37)
    iconBacking:SetSize(44, 44)
    iconBacking:SetColorTexture(0.32, 0.26, 0.17, 0.9)

    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetColorTexture(1, 0.69, 0.16, 0.5)
    glow:SetPoint("TOPLEFT", 2, -2)
    glow:SetPoint("TOPRIGHT", -2, -2)
    glow:SetHeight(2)
    local group = glow:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local animation = group:CreateAnimation("Alpha")
    animation:SetFromAlpha(0.2)
    animation:SetToAlpha(1)
    animation:SetDuration(0.8)
    group:Play()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("装备装等提示")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function()
        if not inCombat() then
            if canSecure then f:SetAttribute("hasCandidates", nil) end
            f:Hide()
        end
    end)

    local template = canSecure and "SecureActionButtonTemplate" or nil
    local action = CreateFrame("Button", nil, f, template)
    action:SetPoint("TOPLEFT", 12, -34)
    action:SetSize(345, 50)
    action:RegisterForClicks("LeftButtonUp")
    action.icon = action:CreateTexture(nil, "ARTWORK")
    action.icon:SetPoint("LEFT", 0, 0)
    action.icon:SetSize(40, 40)
    action.title = action:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    action.title:SetPoint("TOPLEFT", 48, -3)
    action.title:SetWidth(290)
    action.title:SetJustifyH("LEFT")
    action.diff = action:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    action.diff:SetPoint("TOPLEFT", 48, -26)
    action.diff:SetJustifyH("LEFT")
    action:SetScript("OnEnter", function(self)
        local item = self.item
        if item and valid and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetBagItem(item.bag, item.bagSlot)
            GameTooltip:Show()
        end
    end)
    action:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if canSecure then
        action:SetScript("PreClick", function(self)
            local allowed, reason = check(self.item)
            if not allowed then
                clearAction()
                notice:SetText(reason or "请手动装备。")
                say(reason or "请手动装备。")
            end
        end)
    end
    button = action

    notice = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notice:SetPoint("TOPLEFT", 12, -88)
    notice:SetWidth(345)
    notice:SetJustifyH("LEFT")
    local previous = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    previous:SetSize(48, 20)
    previous:SetPoint("BOTTOMLEFT", 12, 8)
    previous:SetText("上件")
    previous:SetScript("OnClick", function() changePage(-1) end)
    pageText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    local nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextButton:SetSize(48, 20)
    nextButton:SetPoint("BOTTOMRIGHT", -12, 8)
    nextButton:SetText("下件")
    nextButton:SetScript("OnClick", function() changePage(1) end)
    f:Hide()
    if canSecure then
        -- Clear the secure flag while entering combat, so the driver cannot
        -- reopen stale candidates on leaving combat before a fresh scan.
        f:SetAttribute("_onstate-combat", [[
            if newstate == "1" then
                self:SetAttribute("hasCandidates", nil)
                self:Hide()
            elseif self:GetAttribute("hasCandidates") then
                self:Show()
            else
                self:Hide()
            end
        ]])
        RegisterStateDriver(f, "combat", "[combat] 1; 0")
    end
    return f
end

function toolbox.invalidateGearCandidates()
    valid = false
    candidates = {}
    page = 1
    if inCombat() then return end
    clearAction()
    if window then
        if canSecure then window:SetAttribute("hasCandidates", nil) end
        window:Hide()
    end
end

function toolbox.updateGearCandidates(list)
    if inCombat() then return end
    toolbox.invalidateGearCandidates()
    if type(list) ~= "table" or #list == 0 then return end
    for _, candidate in ipairs(list) do
        if type(candidate) == "table" then
            local copy = {}
            for key, value in pairs(candidate) do copy[key] = value end
            if type(copy.inventorySlot) == "number" and type(GetInventoryItemLink) == "function" then
                copy.originalLink = GetInventoryItemLink("player", copy.inventorySlot)
            end
            candidates[#candidates + 1] = copy
        end
    end
    if #candidates == 0 then return end
    valid = true
    if not window then window = createWindow() end
    render()
end

local events = CreateFrame("Frame")
for _, event in ipairs({"BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, kind)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and kind then interaction[kind] = true end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and kind then interaction[kind] = nil end
    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        toolbox.invalidateGearCandidates()
    elseif not inCombat() and valid then
        render()
    end
end)
