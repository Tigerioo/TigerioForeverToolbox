local _, toolbox = ...
local window, selectedID, pendingRefresh

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function text(value)
    if not readable(value) or type(value) ~= "string" or value == "" then return "未知" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function level(value)
    if not readable(value) or type(value) ~= "number" or value < 1 then return "未知" end
    return tostring(value) .. " 级"
end

local function timestamp(value)
    if not readable(value) or type(value) ~= "number" or value <= 0 then return "未知" end
    local ok, result = pcall(date, "%Y-%m-%d %H:%M", value)
    return ok and type(result) == "string" and result or "未知"
end

local function label(parent, font, x, y, value)
    local result = parent:CreateFontString(nil, "OVERLAY", font)
    result:SetPoint("TOPLEFT", x, -y)
    result:SetJustifyH("LEFT")
    result:SetText(value or "")
    return result
end

local function identity(entry)
    local id = entry.id
    if not readable(id) then return nil end
    if type(id) ~= "string" and type(id) ~= "number" then return nil end
    return type(id) .. ":" .. tostring(id)
end

local function displayName(entry)
    local name, realm = text(entry.name), text(entry.realm)
    if realm ~= "未知" then return name .. " - " .. realm end
    return name
end

-- The history stores localized class names, not class tokens.
local function classColor(entry)
    local name = entry.className
    if not readable(name) or type(name) ~= "string" or name == "" then return 1, 1, 1 end
    local token
    local fallback = {
        WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "潜行者",
        PRIEST = "牧师", DEATHKNIGHT = "死亡骑士", SHAMAN = "萨满祭司", MAGE = "法师",
        WARLOCK = "术士", MONK = "武僧", DRUID = "德鲁伊", DEMONHUNTER = "恶魔猎手", EVOKER = "唤魔师",
    }
    for _, names in ipairs({LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}, fallback}) do
        if readable(names) and type(names) == "table" then
            for key, value in pairs(names) do
                if readable(key) and type(key) == "string" and readable(value) and type(value) == "string" and value == name then
                    token = key
                    break
                end
            end
        end
        if token then break end
    end
    local colors = RAID_CLASS_COLORS
    if token and readable(colors) and type(colors) == "table" then
        local color = colors[token]
        if readable(color) and type(color) == "table" and readable(color.r) and readable(color.g) and readable(color.b)
            and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
            return color.r, color.g, color.b
        end
    end
    return 1, 1, 1
end

local function shortStatus(entry)
    local state = readable(entry.status) and entry.status or nil
    local source = readable(entry.statusSource) and entry.statusSource or nil
    if (source == "party" or source == "friend") and state == "online" then return "在线" end
    if (source == "party" or source == "friend") and state == "offline" then return "离线" end
    return "未知"
end

local function currentLevel(entry)
    if shortStatus(entry) == "在线" then return level(entry.currentLevel) end
    return "未知"
end

local function details(entry)
    local lines = {}
    if readable(entry.history) and type(entry.history) == "table" and #entry.history > 0 then
        for i = #entry.history, 1, -1 do
            local item = entry.history[i]
            if readable(item) and type(item) == "table" then
                if #lines > 0 then lines[#lines + 1] = "" end
                lines[#lines + 1] = "|cffffd27f" .. timestamp(item.time) .. "|r"
                lines[#lines + 1] = "当时  " .. level(item.level)
                lines[#lines + 1] = "我的位置  " .. text(item.location)
            end
        end
    end
    if #lines == 0 then
        lines = {"当时  " .. level(entry.lastLevel), "我的位置  " .. text(entry.lastLocation)}
    end
    return table.concat(lines, "\n")
end

local render

local function makeRow(index)
    local row = CreateFrame("Button", nil, window.listContent)
    row:SetSize(310, 60)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 63)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.07, 0.065, 0.055, 0.9)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.84, 0.62, 0.20, 0.16)
    local marker = row:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(0.84, 0.62, 0.20, 1)
    marker:SetPoint("TOPLEFT", 0, 0)
    marker:SetPoint("BOTTOMLEFT", 0, 0)
    marker:SetWidth(2)
    row.marker = marker
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetSize(7, 7)
    dot:SetPoint("TOPLEFT", 9, -11)
    row.dot = dot
    row.name = label(row, "GameFontNormalSmall", 22, 7, "")
    row.name:SetWidth(280)
    row.summary = label(row, "GameFontHighlightSmall", 22, 33, "")
    row.summary:SetWidth(280)
    for _, line in ipairs({row.name, row.summary}) do
        if type(line.SetWordWrap) == "function" then line:SetWordWrap(false) end
        if type(line.SetMaxLines) == "function" then line:SetMaxLines(1) end
    end
    row:SetScript("OnClick", function(self)
        selectedID = self.entryID
        render(true)
    end)
    return row
end

render = function(resetScroll)
    if not window then return end
    local entries, reason
    if type(toolbox.companionList) == "function" then
        local ok
        ok, entries, reason = pcall(toolbox.companionList)
        if not ok then entries, reason = nil, "记录暂不可用" end
    else
        reason = "记录模块暂不可用"
    end
    local available = type(entries) == "table"
    entries = available and entries or {}
    local filter = (window.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local filtered, selected = {}, nil
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local id = identity(entry)
            local haystack = (text(entry.name) .. " " .. text(entry.realm) .. " " .. text(entry.className)):lower()
            if id and haystack:find(filter, 1, true) then
                filtered[#filtered + 1] = entry
                if id == selectedID then selected = entry end
            end
        end
    end
    if not selected and filtered[1] then
        selected = filtered[1]
        selectedID = identity(selected)
    elseif not selected then
        selectedID = nil
    end
    for index, entry in ipairs(filtered) do
        local row = window.rows[index]
        if not row then
            row = makeRow(index)
            window.rows[index] = row
        end
        row.entryID = identity(entry)
        local state = shortStatus(entry)
        row.name:SetText(displayName(entry))
        row.name:SetTextColor(classColor(entry))
        row.summary:SetText(state .. "  ·  " .. currentLevel(entry) .. "  ·  " .. text(entry.className))
        if state == "在线" then row.dot:SetColorTexture(0.24, 0.80, 0.22, 1)
        elseif state == "离线" then row.dot:SetColorTexture(0.45, 0.45, 0.45, 1)
        else row.dot:SetColorTexture(0.80, 0.66, 0.37, 1) end
        if row.entryID == selectedID then row.marker:Show() else row.marker:Hide() end
        row:Show()
    end
    for index = #filtered + 1, #window.rows do window.rows[index]:Hide() end
    window.listContent:SetHeight(math.max(1, #filtered * 63))
    if not available then
        window.listEmpty:SetText(text(reason))
    elseif #entries == 0 then
        window.listEmpty:SetText("暂无同行记录")
    elseif #filtered == 0 then
        window.listEmpty:SetText("没有找到匹配的队友")
    else
        window.listEmpty:SetText("")
    end
    window.detailTitle:SetText(selected and displayName(selected) or "同行记录")
    if selected then window.detailTitle:SetTextColor(classColor(selected))
    else window.detailTitle:SetTextColor(1, 0.82, 0) end
    window.details:SetText(selected and details(selected) or (available and "暂无记录" or "记录暂不可用"))
    window.detailContent:SetHeight(math.max(1, window.details:GetStringHeight() + 20))
    if resetScroll then window.detailScroll:SetVerticalScroll(0) end
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxCompanionsFrame", "Tigerio 的无限升级工具箱", 800, 540, "companions")
    label(f, "GameFontNormalLarge", 70, 43, "同行记录")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 342, 417)
    toolbox.nativeSection(f, 368, 87, 414, 417)
    label(f, "GameFontNormalSmall", 30, 98, "搜索姓名或职业")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(312, 24)
    search:SetPoint("TOPLEFT", 32, -119)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search, f.rows = search, {}

    local listScroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxCompanionsListScroll", f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 28, -151)
    listScroll:SetSize(320, 332)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(310, 1)
    listScroll:SetScrollChild(listContent)
    f.listContent = listContent
    f.listEmpty = label(f, "GameFontHighlightSmall", 34, 158, "")
    f.listEmpty:SetWidth(292)
    f.listEmpty:SetJustifyV("TOP")
    search:SetScript("OnTextChanged", function() listScroll:SetVerticalScroll(0); render(true) end)

    f.detailTitle = label(f, "GameFontNormal", 382, 102, "同行记录")
    f.detailTitle:SetWidth(370)
    if type(f.detailTitle.SetWordWrap) == "function" then f.detailTitle:SetWordWrap(false) end
    if type(f.detailTitle.SetMaxLines) == "function" then f.detailTitle:SetMaxLines(1) end
    toolbox.nativeDivider(f, 382, 126, 374)
    local detailScroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxCompanionsDetailsScroll", f, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 382, -140)
    detailScroll:SetSize(370, 338)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(365, 1)
    detailScroll:SetScrollChild(detailContent)
    f.details = label(detailContent, "GameFontHighlightSmall", 0, 0, "")
    f.details:SetWidth(355)
    f.details:SetJustifyV("TOP")
    f.detailContent, f.detailScroll = detailContent, detailScroll
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxCompanionsFrame"
    f:Hide()
    return f
end

function toolbox.toggleCompanions()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    pendingRefresh = nil
    render(true)
end

function toolbox.onCompanionsChanged()
    if not window or not window:IsShown() then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        pendingRefresh = true
        return
    end
    render(false)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if pendingRefresh then
        pendingRefresh = nil
        if window and window:IsShown() then render(false) end
    end
end)

SLASH_TIGERIOCOMPANIONS1 = "/tftparty"
SlashCmdList.TIGERIOCOMPANIONS = toolbox.toggleCompanions
