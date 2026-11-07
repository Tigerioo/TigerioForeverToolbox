local ADDON = ...
local events = CreateFrame("Frame")
local currentCharacter, lastTick
local window, viewYear, viewMonth, selectedDate

local function dayKey(timestamp)
    return date("%Y-%m-%d", timestamp)
end

local function nextMidnight(timestamp)
    local parts = date("*t", timestamp)
    return time({year = parts.year, month = parts.month, day = parts.day + 1, hour = 0, min = 0, sec = 0})
end

local function dailyRecord(character, key)
    local days = character.days
    if type(days[key]) ~= "table" then days[key] = {seconds = 0, levels = {}} end
    local record = days[key]
    record.seconds = tonumber(record.seconds) or 0
    if type(record.levels) ~= "table" then record.levels = {} end
    return record
end

-- Account time against civil-day boundaries, including sessions crossing midnight.
local function accountTime(now)
    if not currentCharacter or not lastTick then return end
    if now <= lastTick then lastTick = now; return end
    while lastTick < now do
        local boundary = nextMidnight(lastTick)
        -- A system clock or calendar anomaly must not trap the event handler.
        if not boundary or boundary <= lastTick then lastTick = now; return end
        local finish = math.min(boundary, now)
        local record = dailyRecord(currentCharacter, dayKey(lastTick))
        record.seconds = record.seconds + finish - lastTick
        lastTick = finish
    end
end

local function duration(seconds)
    local minutes = math.floor((tonumber(seconds) or 0) / 60)
    return string.format("%d小时%02d分", math.floor(minutes / 60), minutes % 60)
end

local function text(parent, font, x, y, value)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, -y)
    label:SetJustifyH("LEFT")
    label:SetText(value or "")
    return label
end

local function button(parent, width, height, value, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, height)
    control:SetText(value)
    control:SetScript("OnClick", onClick)
    return control
end

local function namesForDay(key)
    local rows = {}
    for _, character in pairs(TigerioForeverToolboxDB.characters) do
        local record = type(character.days) == "table" and character.days[key]
        if type(record) == "table" then
            rows[#rows + 1] = {character = character, record = record}
        end
    end
    table.sort(rows, function(a, b)
        return (a.character.name or "") .. (a.character.realm or "") < (b.character.name or "") .. (b.character.realm or "")
    end)
    return rows
end

local function renderDetails()
    local rows = namesForDay(selectedDate)
    window.detailTitle:SetText(selectedDate .. " 角色记录")
    local lines = {}
    local total = 0
    for _, item in ipairs(rows) do
        local character, record = item.character, item.record
        local seconds = tonumber(record.seconds) or 0
        total = total + seconds
        lines[#lines + 1] = "|cffffd27f" .. (character.name or "未知角色") .. " - " .. (character.realm or "未知服务器") .. "|r"
        lines[#lines + 1] = "在线 " .. duration(seconds)
        if type(record.levels) == "table" then
            for _, level in ipairs(record.levels) do
                if type(level) == "table" and type(level.when) == "number" then
                    lines[#lines + 1] = date("%H:%M", level.when) .. "  升到 " .. tostring(level.level) .. " 级"
                end
            end
        end
        lines[#lines + 1] = ""
    end
    if #rows == 0 then lines[1] = "这一天还没有记录。" end
    window.detailSummary:SetText("当天合计在线 " .. duration(total))
    window.detailText:SetText(table.concat(lines, "\n"))
    window.detailContent:SetHeight(math.max(1, window.detailText:GetStringHeight() + 20))
    window.detailScroll:SetVerticalScroll(0)
end

local function renderCalendar()
    if not window then return end
    window.monthTitle:SetText(string.format("%d 年 %d 月", viewYear, viewMonth))
    local first = time({year = viewYear, month = viewMonth, day = 1, hour = 12, min = 0, sec = 0})
    local firstWeekday = date("*t", first).wday
    local last = time({year = viewYear, month = viewMonth + 1, day = 0, hour = 12, min = 0, sec = 0})
    local lastDay = date("*t", last).day
    for i, cell in ipairs(window.cells) do
        local day = i - firstWeekday + 1
        if day >= 1 and day <= lastDay then
            local key = string.format("%04d-%02d-%02d", viewYear, viewMonth, day)
            local rows = namesForDay(key)
            local levels = 0
            for _, item in ipairs(rows) do
                if type(item.record.levels) == "table" then levels = levels + #item.record.levels end
            end
            cell.dateKey = key
            cell:SetText(tostring(day) .. (levels > 0 and "  |cffffd100↑" .. levels .. "|r" or (#rows > 0 and "  |cff80c080·|r" or "")))
            cell:Show()
        else
            cell.dateKey = nil
            cell:Hide()
        end
    end
    renderDetails()
end

local function changeMonth(offset)
    local parts = date("*t", time({year = viewYear, month = viewMonth + offset, day = 1, hour = 12, min = 0, sec = 0}))
    viewYear, viewMonth = parts.year, parts.month
    selectedDate = string.format("%04d-%02d-01", viewYear, viewMonth)
    renderCalendar()
end

local function createWindow()
    local f = CreateFrame("Frame", "TigerioForeverToolboxFrame", UIParent, "BackdropTemplate")
    f:SetSize(770, 510)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.045, 0.043, 0.04, 0.98)
    f:SetBackdropBorderColor(0.48, 0.39, 0.26)
    text(f, "GameFontNormalLarge", 20, 18, "Tigerio 的无限升级工具箱")
    text(f, "GameFontHighlightSmall", 20, 45, "升级日历 · 本机日期 · 包含挂机时间")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() f:Hide() end)

    local previous = button(f, 65, 24, "上月", function() changeMonth(-1) end)
    previous:SetPoint("TOPLEFT", 20, -76)
    local nextButton = button(f, 65, 24, "下月", function() changeMonth(1) end)
    nextButton:SetPoint("TOPLEFT", 342, -76)
    f.monthTitle = text(f, "GameFontNormal", 156, 81, "")
    local weekdays = {"日", "一", "二", "三", "四", "五", "六"}
    for i, day in ipairs(weekdays) do text(f, "GameFontNormalSmall", 39 + (i - 1) * 56, 115, day) end
    f.cells = {}
    for i = 1, 42 do
        local cell = button(f, 52, 40, "", function(self)
            selectedDate = self.dateKey
            renderDetails()
        end)
        cell:SetPoint("TOPLEFT", 20 + ((i - 1) % 7) * 56, -136 - math.floor((i - 1) / 7) * 45)
        f.cells[i] = cell
    end
    text(f, "GameFontHighlightSmall", 20, 424, "↑ 升级次数    · 有在线记录")
    text(f, "GameFontHighlightSmall", 20, 449, "仅记录启用后的数据；角色需分别登录。")

    f.detailTitle = text(f, "GameFontNormal", 435, 80, "")
    f.detailSummary = text(f, "GameFontHighlightSmall", 435, 105, "")
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxDetailsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 435, -132)
    scroll:SetSize(290, 312)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(275, 1)
    scroll:SetScrollChild(content)
    f.detailText = text(content, "GameFontHighlightSmall", 0, 0, "")
    f.detailText:SetWidth(270)
    f.detailText:SetJustifyV("TOP")
    f.detailContent, f.detailScroll = content, scroll
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxFrame"
    f:Hide()
    return f
end

local function openCalendar()
    if not currentCharacter then return end
    accountTime(time())
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    local today = date("*t")
    viewYear, viewMonth = today.year, today.month
    selectedDate = dayKey(time())
    renderCalendar()
    window:Show()
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" and argument == ADDON then
        if type(TigerioForeverToolboxDB) ~= "table" then TigerioForeverToolboxDB = {} end
        if type(TigerioForeverToolboxDB.characters) ~= "table" then TigerioForeverToolboxDB.characters = {} end
    elseif event == "PLAYER_LOGIN" then
        if type(TigerioForeverToolboxDB) ~= "table" then return end
        local name = UnitName("player") or "未知角色"
        local realm = GetRealmName() or "未知服务器"
        local key = UnitGUID("player") or (realm .. "-" .. name)
        local characters = TigerioForeverToolboxDB.characters
        if type(characters[key]) ~= "table" then characters[key] = {} end
        currentCharacter = characters[key]
        currentCharacter.name, currentCharacter.realm = name, realm
        if type(currentCharacter.days) ~= "table" then currentCharacter.days = {} end
        lastTick = time()
    elseif event == "PLAYER_LEVEL_UP" and currentCharacter then
        local now = time()
        accountTime(now)
        local record = dailyRecord(currentCharacter, dayKey(now))
        record.levels[#record.levels + 1] = {level = argument, when = now}
        if window and window:IsShown() then renderCalendar() end
    elseif event == "PLAYER_LOGOUT" then
        accountTime(time())
    end
end)

local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
    if not currentCharacter then return end
    elapsed = elapsed + delta
    if elapsed >= 60 then
        elapsed = 0
        accountTime(time())
        if window and window:IsShown() then renderCalendar() end
    end
end)

SLASH_TIGERIOFOREVERTOOLBOX1 = "/tft"
SlashCmdList.TIGERIOFOREVERTOOLBOX = openCalendar
