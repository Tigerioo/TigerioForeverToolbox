local _, toolbox = ...
local window, selected
local bothFactions = false

local function label(parent, font, x, y, value)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, -y)
    text:SetJustifyH("LEFT")
    text:SetText(value or "")
    return text
end

local function selectedMarker(button)
    local marker = button:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(0.84, 0.62, 0.20, 1)
    marker:SetPoint("TOPLEFT", 3, -3)
    marker:SetPoint("BOTTOMLEFT", 3, 3)
    marker:SetWidth(3)
    return marker
end

local function currentFaction()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, faction = pcall(UnitFactionGroup, "player")
    if not ok then return nil end
    if type(issecretvalue) == "function" then
        local safe, secret = pcall(issecretvalue, faction)
        if not safe or secret then return nil end
    end
    if faction == "Alliance" or faction == "Horde" then return faction end
end

local function matches(master, weapon)
    if not weapon then return true end
    for _, name in ipairs(type(master.weapons) == "table" and master.weapons or {}) do
        if name == weapon then return true end
    end
    for _, name in ipairs(type(master.uncertainWeapons) == "table" and master.uncertainWeapons or {}) do
        if name == weapon then return true, true end
    end
    return false
end

local function renderDetails(resetScroll)
    if not window then return end
    local data = type(toolbox.weaponMastersData) == "table" and toolbox.weaponMastersData or {}
    local faction = currentFaction()
    local filter
    if not bothFactions then filter = faction end
    window.factionButton:SetText(filter and (filter == "Alliance" and "阵营：联盟" or "阵营：部落") or "阵营：双方")
    window.detailTitle:SetText(selected and ("武器：" .. selected) or "全部武器大师")
    local lines = {}
    local count = 0
    for _, master in ipairs(type(data.masters) == "table" and data.masters or {}) do
        local matched, uncertain = matches(master, selected)
        if (not filter or master.faction == filter) and matched then
            count = count + 1
            local factionLabel = master.faction == "Alliance" and "联盟" or master.faction == "Horde" and "部落" or "阵营未确认"
            lines[#lines + 1] = "|cffffd27f" .. (master.name or "武器大师") .. "|r  [" .. factionLabel .. "]"
            if master.city then lines[#lines + 1] = "城市：" .. master.city end
            if master.location then lines[#lines + 1] = "位置：" .. master.location end
            if not selected and type(master.weapons) == "table" and #master.weapons > 0 then
                lines[#lines + 1] = "教授：" .. table.concat(master.weapons, "、")
            end
            if uncertain then lines[#lines + 1] = "该教学信息有冲突，需实机核实。" end
            if not selected and type(master.uncertainWeapons) == "table" and #master.uncertainWeapons > 0 then
                lines[#lines + 1] = "待核实：" .. table.concat(master.uncertainWeapons, "、") .. "（资料有冲突）"
            end
            if master.note then lines[#lines + 1] = master.note end
            lines[#lines + 1] = ""
        end
    end
    if count == 0 then
        lines[#lines + 1] = "当前筛选下没有已收录的大师；不代表不存在。"
        lines[#lines + 1] = ""
    end
    if selected and type(data.weaponNotes) == "table" and data.weaponNotes[selected] then
        lines[#lines + 1] = data.weaponNotes[selected]
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "|cffffd27f使用说明|r"
    lines[#lines + 1] = "资料可能不完整；能否学习还取决于职业、等级及游戏中的实际条件。"
    if type(data.notes) == "table" then
        for _, note in ipairs(data.notes) do lines[#lines + 1] = note end
    end
    window.details:SetText(table.concat(lines, "\n"))
    window.detailContent:SetHeight(math.max(1, window.details:GetStringHeight() + 20))
    if resetScroll then window.detailScroll:SetVerticalScroll(0) end
end

local function renderList()
    if not window then return end
    if selected then window.all.selectedMarker:Hide() else window.all.selectedMarker:Show() end
    local data = type(toolbox.weaponMastersData) == "table" and toolbox.weaponMastersData or {}
    local filter = (window.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local count = 0
    for _, weapon in ipairs(type(data.weapons) == "table" and data.weapons or {}) do
        if type(weapon) == "string" and weapon:lower():find(filter, 1, true) then
            count = count + 1
            local row = window.rows[count]
            if not row then
                row = CreateFrame("Button", nil, window.listContent, "UIPanelButtonTemplate")
                row:SetSize(200, 27)
                row:SetPoint("TOPLEFT", 0, -(count - 1) * 30)
                row.selectedMarker = selectedMarker(row)
                row:SetScript("OnClick", function(self)
                    selected = self.weapon
                    renderList()
                    renderDetails(true)
                end)
                window.rows[count] = row
            end
            row.weapon = weapon
            row:SetText((weapon == selected and "|cffffd100" or "") .. weapon .. (weapon == selected and "|r" or ""))
            if weapon == selected then row.selectedMarker:Show() else row.selectedMarker:Hide() end
            row:Show()
        end
    end
    for i = count + 1, #window.rows do window.rows[i]:Hide() end
    window.listContent:SetHeight(math.max(1, count * 30))
    window.listEmpty:SetText(count == 0 and "未找到匹配的武器。" or "")
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxWeaponMasters", "Tigerio 的无限升级工具箱", 780, 530, "weapon")
    label(f, "GameFontNormalLarge", 28, 43, "武器大师")
    label(f, "GameFontHighlightSmall", 28, 70, "选择武器类别，查看大师的城市和位置")
    toolbox.nativeDivider(f, 22, 90, 735)
    toolbox.nativeSection(f, 18, 102, 223, 400)
    toolbox.nativeSection(f, 250, 102, 512, 400)

    label(f, "GameFontNormalSmall", 28, 112, "搜索武器类别")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(190, 24)
    search:SetPoint("TOPLEFT", 29, -134)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search, f.rows = search, {}

    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(200, 26)
    all:SetPoint("TOPLEFT", 27, -167)
    all:SetText("查看全部大师")
    all.selectedMarker = selectedMarker(all)
    f.all = all
    all:SetScript("OnClick", function() selected = nil; renderList(); renderDetails(true) end)

    local listScroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxWeaponsListScroll", f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 27, -200)
    listScroll:SetSize(205, 280)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(200, 1)
    listScroll:SetScrollChild(listContent)
    f.listContent = listContent
    f.listEmpty = label(f, "GameFontHighlightSmall", 31, 207, "")
    search:SetScript("OnTextChanged", function() listScroll:SetVerticalScroll(0); renderList() end)

    f.detailTitle = label(f, "GameFontNormal", 266, 114, "")
    local factionButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    factionButton:SetSize(100, 24)
    factionButton:SetPoint("TOPRIGHT", -29, -109)
    factionButton:SetScript("OnClick", function()
        if currentFaction() then bothFactions = not bothFactions else bothFactions = true end
        renderDetails(true)
    end)
    f.factionButton = factionButton
    local detailScroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxWeaponDetailsScroll", f, "UIPanelScrollFrameTemplate")
    toolbox.nativeDivider(f, 266, 137, 468)
    detailScroll:SetPoint("TOPLEFT", 266, -150)
    detailScroll:SetSize(465, 330)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(460, 1)
    detailScroll:SetScrollChild(detailContent)
    f.details = label(detailContent, "GameFontHighlightSmall", 0, 0, "")
    f.details:SetWidth(450)
    f.details:SetJustifyV("TOP")
    f.detailContent, f.detailScroll = detailContent, detailScroll
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxWeaponMasters"
    f:Hide()
    return f
end

function toolbox.toggleWeaponMasters()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    renderList()
    renderDetails(true)
end
