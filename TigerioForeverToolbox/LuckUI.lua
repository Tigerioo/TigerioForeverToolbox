local _, toolbox = ...
local window, lastResult, pending

local tiers = {
    common = {name = "普通", color = "|cffd5d5d5"},
    rare = {name = "精良", color = "|cff5cafff"},
    epic = {name = "史诗", color = "|cffa870ff"},
    legendary = {name = "传说", color = "|cffffa137"},
}

local function combat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function label(parent, font, x, y, value, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, -y)
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    text:SetText(value or "")
    return text
end

local function button(parent, title, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 27)
    b:SetText(title)
    b:SetScript("OnClick", onClick)
    return b
end

local function snapshot()
    if type(toolbox.luckState) ~= "function" then return nil, "收藏数据尚未就绪。" end
    local ok, state, reason = pcall(toolbox.luckState)
    if ok and type(state) == "table" then return state end
    if ok and type(reason) == "string" and reason ~= "" then return nil, reason end
    return nil, "收藏数据不可用，请稍后重试。"
end

local function catalog()
    return type(toolbox.luckCatalog) == "table" and toolbox.luckCatalog or {}
end

local function itemName(item)
    return type(item.name) == "string" and item.name or ("收藏 #" .. tostring(item.id))
end

local function itemIcon(id)
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function findItem(id)
    for _, item in ipairs(catalog()) do
        if tostring(item.id) == tostring(id) then return item end
    end
end

local function render()
    if not window then return end
    if combat() then pending = true; return end
    local state, reason = snapshot()
    if not state then
        window.balance:SetText("收藏数据尚未就绪。")
        window.progress:SetText("")
        window.drawCount:SetText("")
        window.pity:SetText("")
        window.result:SetText(reason or "请稍后重试。")
        window.tracking:SetText("本人或宠物最后一击有 25% 几率获得 1–2 碎片；受客户端限制可能漏计。")
        window.roll:Disable()
        for _, row in ipairs(window.rows) do row:Hide() end
        window.content:SetHeight(1)
        return
    end
    local collection = type(state.collection) == "table" and state.collection or {}
    local items, owned = catalog(), 0
    for _, item in ipairs(items) do
        if (tonumber(collection[tostring(item.id)]) or 0) > 0 then owned = owned + 1 end
    end
    window.balance:SetText("碎片  " .. tostring(state.shards or 0) .. " / 20")
    window.progress:SetText("图鉴  " .. owned .. " / " .. #items)
    window.drawCount:SetText("累计抽取  " .. tostring(state.rolls or 0) .. " 次")
    if (tonumber(state.shards) or 0) >= 20 then window.roll:Enable() else window.roll:Disable() end
    window.pity:SetText("史诗保底进度  " .. tostring(state.epicDry or 0) .. " / 10\n传说保底进度  " .. tostring(state.legendaryDry or 0) .. " / 50")
    local trackingText = "本人或宠物最后一击：25% 几率获得 1–2 碎片；受客户端限制可能漏计。"
    if state.trackingAvailable == false then
        trackingText = trackingText .. "\n|cffffbf70击杀统计不可用：" ..
            (type(state.trackingIssue) == "string" and state.trackingIssue or "客户端接口受限") .. "|r"
    elseif state.trackingIssue then
        trackingText = trackingText .. "\n|cffffbf70部分击杀无法识别，可能漏计。|r"
    end
    window.tracking:SetText(trackingText)
    local result = lastResult or findItem(state.lastID)
    if result then
        local tier = tiers[result.tier] or tiers.common
        local suffix = lastResult and (lastResult.isNew and "  新收藏" or "  已有收藏") or ""
        window.result:SetText(tier.color .. itemName(result) .. "|r" .. suffix)
    else
        window.result:SetText("尚未抽取")
    end

    for i, item in ipairs(items) do
        local row = window.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, window.content)
            row:SetSize(425, 35)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 39)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", 2, 0)
            row.icon:SetSize(30, 30)
            row.name = label(row, "GameFontHighlightSmall", 40, 3, "", 285)
            row.status = label(row, "GameFontHighlightSmall", 40, 19, "", 345)
            window.rows[i] = row
        end
        local amount = tonumber(collection[tostring(item.id)]) or 0
        local tier = tiers[item.tier] or tiers.common
        row.icon:SetTexture(itemIcon(item.id))
        row.name:SetText(tier.color .. itemName(item) .. "|r")
        row.status:SetText(tier.name .. "  ·  " .. (amount > 0 and ("已收藏 ×" .. amount) or "未收藏"))
        row:Show()
    end
    for i = #items + 1, #window.rows do window.rows[i]:Hide() end
    window.content:SetHeight(math.max(1, #items * 39))
    pending = nil
end

local function draw()
    if combat() then return end
    if type(toolbox.luckDraw) ~= "function" then
        window.message:SetText("抽取功能尚未就绪。")
        return
    end
    local called, success, result = pcall(toolbox.luckDraw)
    if not called then
        window.message:SetText("抽取失败，请稍后重试。")
    elseif not success then
        window.message:SetText(type(result) == "string" and result or "碎片不足或抽取暂不可用。")
    elseif type(result) == "table" then
        lastResult = result
        window.message:SetText(result.isNew and "获得新收藏！" or "再次获得该收藏。")
    end
    render()
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxLuckFrame", "奇珍图鉴", 740, 510, "luck")
    toolbox.nativeSection(f, 17, 70, 231, 420)
    toolbox.nativeSection(f, 256, 70, 467, 350)
    toolbox.nativeDivider(f, 20, 62, 700)
    toolbox.nativeDivider(f, 264, 102, 451)
    label(f, "GameFontNormalLarge", 23, 40, "奇珍图鉴")
    label(f, "GameFontHighlightSmall", 130, 44, "击杀积攒碎片 · 抽取虚拟收藏")

    label(f, "GameFontHighlight", 25, 82, "旅途战利品")
    f.balance = label(f, "GameFontNormal", 25, 116, "", 200)
    f.progress = label(f, "GameFontHighlight", 25, 144, "", 200)
    f.drawCount = label(f, "GameFontHighlightSmall", 25, 171, "", 200)
    local roll = button(f, "消耗 20 碎片抽取", 196, draw)
    roll:SetPoint("TOPLEFT", 25, -201)
    f.roll = roll
    f.message = label(f, "GameFontHighlightSmall", 25, 238, "", 200)
    label(f, "GameFontNormalSmall", 25, 270, "上次抽取", 200)
    f.result = label(f, "GameFontHighlightSmall", 25, 292, "", 200)
    f.pity = label(f, "GameFontHighlightSmall", 25, 336, "", 200)
    label(f, "GameFontHighlightSmall", 25, 384, "普通 70% · 精良 25%\n史诗 4% · 传说 1%\n\n连续10次未出史诗及以上，\n第11次保底；连续50次未出\n传说，第51次保底传说。\n传说优先；史诗保底按 4:1。", 202)

    label(f, "GameFontHighlight", 264, 78, "收藏图鉴")
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxLuckScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 264, -112)
    scroll:SetSize(456, 305)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(425, 1)
    scroll:SetScrollChild(content)
    f.content, f.rows = content, {}
    f.tracking = label(f, "GameFontHighlightSmall", 264, 426, "", 450)
    label(f, "GameFontNormalSmall", 264, 478, "虚拟收藏，不产生游戏物品；稀有度为小游戏规则。", 450)
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxLuckFrame"
    f:Hide()
    return f
end

function toolbox.toggleLuckCollection()
    if combat() then return end
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window.message:SetText("")
    render()
    window:Show()
end

function toolbox.onLuckChanged()
    if combat() then pending = true; return end
    if window and window:IsShown() then render() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function()
    if not combat() and window and window:IsShown() then render() end
end)
