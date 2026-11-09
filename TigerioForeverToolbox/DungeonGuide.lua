local _, toolbox = ...
local window, selected
local pending = 0

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

local function setStatus(message)
    if window then window.status:SetText(message or "") end
end

-- The handbook owns its data and its interface. Match a unique display name at
-- runtime, without importing its data or maintaining a copy of its identifiers.
local function findHandbookID(ns, name)
    local data = ns and ns.DungeonData
    if type(data) ~= "table" or type(data.dungeons) ~= "table" or type(name) ~= "string" then return nil end
    local result
    for _, dungeon in ipairs(data.dungeons) do
        if type(dungeon) == "table" and dungeon.name == name and type(dungeon.id) == "string" then
            if result then return nil end
            result = dungeon.id
        end
    end
    return result
end

local function openHandbook()
    pending = pending + 1
    local token = pending
    local open = type(SlashCmdList) == "table" and SlashCmdList.DUNGEONSFOREVER
    if type(open) ~= "function" then
        setStatus("请先安装并启用无限副本手册。")
        return
    end
    local ok = pcall(open, "fb")
    if not ok then
        setStatus("无法打开无限副本手册，请尝试输入 /df fb。")
        return
    end
    local ns = _G.DF_NS
    local id = findHandbookID(ns, selected and selected.name)
    if not id or type(ns.ShowDungeonDetail) ~= "function" then
        setStatus("已打开副本手册，请在手册中选择副本。")
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        setStatus("已打开副本手册，请在手册中选择副本。")
        return
    end
    local attempts = 0
    local function navigate()
        if token ~= pending then return end
        attempts = attempts + 1
        local ui = ns.DungeonUI
        local frame = ns.TalentSimFrame
        if frame and type(frame.IsShown) == "function" and not frame:IsShown() then return end
        if type(ui) == "table" and ui.built and ui.dungeonBuilt and frame then
            local detailOK = pcall(ns.ShowDungeonDetail, id)
            local current = ui.dungeonDetailCur
            if detailOK and type(current) == "table" and current.id == id and type(ui.SetDungeonTab) == "function" then
                local tabOK = pcall(ui.SetDungeonTab, ui, "quest")
                if tabOK then setStatus(""); return end
            end
            setStatus("已打开副本手册，请在手册中选择副本和任务。")
            return
        end
        if attempts < 30 then C_Timer.After(0.1, navigate)
        else setStatus("已打开副本手册，请在手册中选择副本和任务。") end
    end
    C_Timer.After(0.1, navigate)
end

local function renderDetails()
    if not window then return end
    window.detailTitle:SetText(selected and selected.name or "选择一个副本")
    setStatus("")
end

local function renderList()
    if not window then return end
    local filter = (window.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local count = 0
    local entries = type(toolbox.dungeonGuideData) == "table" and toolbox.dungeonGuideData or {}
    for _, entry in ipairs(entries) do
        if type(entry.name) == "string" and entry.name:lower():find(filter, 1, true) then
            count = count + 1
            local row = window.rows[count]
            if not row then
                row = CreateFrame("Button", nil, window.listContent, "UIPanelButtonTemplate")
                row:SetSize(210, 27)
                row:SetPoint("TOPLEFT", 0, -(count - 1) * 30)
                row.selectedMarker = selectedMarker(row)
                row:SetScript("OnClick", function(self)
                    pending = pending + 1
                    selected = self.entry
                    renderList()
                    renderDetails()
                end)
                window.rows[count] = row
            end
            row.entry = entry
            row:SetText((entry == selected and "|cffffd100" or "") .. entry.name .. (entry == selected and "|r" or ""))
            if entry == selected then row.selectedMarker:Show() else row.selectedMarker:Hide() end
            row:Show()
        end
    end
    for i = count + 1, #window.rows do window.rows[i]:Hide() end
    window.listContent:SetHeight(math.max(1, count * 30))
    window.listEmpty:SetText(count == 0 and "未找到匹配的副本。" or "")
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxDungeonGuide", "Tigerio 的无限升级工具箱", 800, 540, "dungeon")
    label(f, "GameFontNormalLarge", 28, 43, "副本任务")
    label(f, "GameFontHighlightSmall", 28, 70, "通过无限副本手册查询任务和前置链")
    toolbox.nativeDivider(f, 22, 90, 755)
    toolbox.nativeSection(f, 18, 102, 238, 402)
    toolbox.nativeSection(f, 264, 102, 518, 402)

    label(f, "GameFontNormalSmall", 29, 112, "搜索副本")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(200, 24)
    search:SetPoint("TOPLEFT", 31, -134)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search, f.rows = search, {}
    local listScroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxDungeonListScroll", f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 27, -169)
    listScroll:SetSize(218, 310)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(210, 1)
    listScroll:SetScrollChild(listContent)
    f.listContent = listContent
    f.listEmpty = label(f, "GameFontHighlightSmall", 31, 176, "")
    search:SetScript("OnTextChanged", function() listScroll:SetVerticalScroll(0); renderList() end)

    f.detailTitle = label(f, "GameFontNormal", 278, 114, "")
    toolbox.nativeDivider(f, 278, 137, 476)
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 28)
    open:SetPoint("TOPLEFT", 278, -155)
    open:SetText("打开副本手册")
    open:SetScript("OnClick", openHandbook)
    f.status = label(f, "GameFontHighlightSmall", 278, 195, "")
    f.status:SetWidth(460)
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxDungeonGuide"
    f:Hide()
    return f
end

function toolbox.toggleDungeonGuide()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    if not selected and type(toolbox.dungeonGuideData) == "table" then selected = toolbox.dungeonGuideData[1] end
    window:Show()
    renderList()
    renderDetails()
end
