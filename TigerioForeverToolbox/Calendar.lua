local ADDON, Toolbox = ...
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

-- The two addons record the same level-up independently, potentially on either
-- side of a clock second. Match only the same level within a short time window.
local function hasLevel(character, level, when)
    for _, record in pairs(character.days) do
        if type(record) == "table" and type(record.levels) == "table" then
            for _, existing in ipairs(record.levels) do
                if type(existing) == "table" and existing.level == level
                    and type(existing.when) == "number" and math.abs(existing.when - when) <= 5 then
                    return true
                end
            end
        end
    end
    return false
end

local function adventureJournalLoaded()
    local check = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return type(check) == "function" and check("AdventureJournal")
end

local function importAdventureJournal()
    if not currentCharacter or not adventureJournalLoaded()
        or type(AdventureJournalDB) ~= "table" or type(AdventureJournalDB.entries) ~= "table" then return end
    for _, entry in ipairs(AdventureJournalDB.entries) do
        if type(entry) == "table" and entry.kind == "level"
            and type(entry.level) == "number" and entry.level > 0 and entry.level < math.huge
            and entry.level == math.floor(entry.level)
            and type(entry.when) == "number" and entry.when > 0 and entry.when < math.huge
            and entry.when == math.floor(entry.when) then
            local valid, key = pcall(dayKey, entry.when)
            if valid and type(key) == "string" and key:match("^%d%d%d%d%-%d%d%-%d%d$")
                and not hasLevel(currentCharacter, entry.level, entry.when) then
                local record = dailyRecord(currentCharacter, key)
                record.levels[#record.levels + 1] = {level = entry.level, when = entry.when, source = "AdventureJournal"}
            end
        end
    end
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

local function text(parent, font, x, y, value)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, -y)
    label:SetJustifyH("LEFT")
    label:SetText(value or "")
    return label
end

-- Keep the native fonts, but soften the strong default gold to match the calendar.
local function tint(label, r, g, b)
    if type(label.SetTextColor) == "function" then label:SetTextColor(r, g, b) end
end

local function button(parent, width, height, value, onClick)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width, height)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.14, 0.105, 0.075, 0.9)
    local hover = control:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    local label = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(value)
    tint(label, 0.87, 0.78, 0.54)
    control:SetScript("OnClick", onClick)
    return control
end

local function markSelected(cell, selected)
    for _, edge in ipairs(cell.selection) do
        if selected then edge:Show() else edge:Hide() end
    end
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

local function renderDetails(resetScroll)
    local rows = namesForDay(selectedDate)
    window.detailTitle:SetText(selectedDate)
    local records, names, characterCount = {}, {}, 0
    for _, item in ipairs(rows) do
        local added = false
        if type(item.record.levels) == "table" then
            for _, level in ipairs(item.record.levels) do
                if type(level) == "table" and type(level.when) == "number" then
                    records[#records + 1] = {when = level.when, level = level.level, character = item.character}
                    added = true
                end
            end
        end
        if added then
            characterCount = characterCount + 1
            local name = item.character.name or "未知角色"
            names[name] = (names[name] or 0) + 1
        end
    end
    table.sort(records, function(a, b)
        if a.when ~= b.when then return a.when < b.when end
        local aName, bName = a.character.name or "", b.character.name or ""
        if aName ~= bName then return aName < bName end
        return (tonumber(a.level) or 0) < (tonumber(b.level) or 0)
    end)
    local lines = {}
    for _, entry in ipairs(records) do
        local character = ""
        if characterCount > 1 then
            local name = entry.character.name or "未知角色"
            if names[name] > 1 and entry.character.realm then name = name .. "-" .. entry.character.realm end
            character = "  " .. name
        end
        lines[#lines + 1] = "|cffaaaaaa" .. date("%H:%M", entry.when) .. "|r" .. character .. "  升到 " .. tostring(entry.level) .. " 级"
    end
    if #lines == 0 then lines[1] = "暂无记录" end
    window.detailText:SetText(table.concat(lines, "\n"))
    window.detailContent:SetHeight(math.max(1, window.detailText:GetStringHeight() + 20))
    if resetScroll then window.detailScroll:SetVerticalScroll(0) end
end

local function renderCalendar(resetScroll)
    if not window then return end
    window.monthTitle:SetText(string.format("%d 年 %d 月", viewYear, viewMonth))
    local today = dayKey(time())
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
            cell.dayLabel:SetText(tostring(day))
            cell.todayLabel:SetText(key == today and "今" or "")
            cell.recordLabel:SetText(levels > 0 and ("↑" .. (levels > 99 and "99+" or tostring(levels))) or "")
            markSelected(cell, key == selectedDate)
            cell:Show()
        else
            cell.dateKey = nil
            cell:Hide()
        end
    end
    renderDetails(resetScroll)
end

local function changeMonth(offset)
    local parts = date("*t", time({year = viewYear, month = viewMonth + offset, day = 1, hour = 12, min = 0, sec = 0}))
    viewYear, viewMonth = parts.year, parts.month
    selectedDate = string.format("%04d-%02d-01", viewYear, viewMonth)
    renderCalendar(true)
end

local function goToday()
    local now = time()
    local parts = date("*t", now)
    viewYear, viewMonth, selectedDate = parts.year, parts.month, dayKey(now)
    renderCalendar(true)
end

local function createWindow()
    local f = Toolbox.createNativeWindow("TigerioForeverToolboxFrame", "Tigerio 的无限升级工具箱", 770, 510, "calendar")
    Toolbox.nativeSection(f, 16, 68, 398, 349)
    Toolbox.nativeSection(f, 428, 68, 326, 393)
    Toolbox.nativeDivider(f, 20, 62, 730)
    Toolbox.nativeDivider(f, 435, 106, 290)
    tint(text(f, "GameFontNormalLarge", 70, 40, "升级日历"), 0.93, 0.81, 0.48)

    local previous = button(f, 54, 24, "< 上月", function() changeMonth(-1) end)
    previous:SetPoint("TOPLEFT", 20, -76)
    f.monthTitle = text(f, "GameFontNormal", 108, 81, "")
    tint(f.monthTitle, 0.89, 0.75, 0.41)
    local nextButton = button(f, 54, 24, "下月 >", function() changeMonth(1) end)
    nextButton:SetPoint("TOPLEFT", 257, -76)
    local today = button(f, 54, 24, "今天", goToday)
    today:SetPoint("TOPLEFT", 348, -76)
    local weekdays = {"日", "一", "二", "三", "四", "五", "六"}
    for i, day in ipairs(weekdays) do
        tint(text(f, "GameFontNormalSmall", 39 + (i - 1) * 56, 115, day), 0.85, 0.72, 0.37)
    end
    f.cells = {}
    for i = 1, 42 do
        local cell = CreateFrame("Button", nil, f)
        cell:SetSize(52, 40)
        cell:EnableMouse(true)
        cell:SetScript("OnClick", function(self)
            selectedDate = self.dateKey
            renderCalendar(true)
        end)
        cell:SetPoint("TOPLEFT", 20 + ((i - 1) % 7) * 56, -136 - math.floor((i - 1) / 7) * 45)
        local background = cell:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.14, 0.105, 0.075, 0.9)
        local hover = cell:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.9, 0.67, 0.25, 0.18)
        cell.dayLabel = text(cell, "GameFontHighlight", 7, 4, "")
        tint(cell.dayLabel, 0.93, 0.89, 0.79)
        cell.todayLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell.todayLabel:SetPoint("TOPRIGHT", -6, -4)
        tint(cell.todayLabel, 0.91, 0.79, 0.48)
        cell.recordLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell.recordLabel:SetPoint("BOTTOMRIGHT", -5, 4)
        tint(cell.recordLabel, 0.91, 0.79, 0.48)
        cell.selection = {}
        for edge = 1, 4 do
            local line = cell:CreateTexture(nil, "OVERLAY")
            line:SetColorTexture(0.95, 0.73, 0.29, 1)
            if edge == 1 then
                line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(2)
            elseif edge == 2 then
                line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(2)
            elseif edge == 3 then
                line:SetPoint("TOPLEFT"); line:SetPoint("BOTTOMLEFT"); line:SetWidth(2)
            else
                line:SetPoint("TOPRIGHT"); line:SetPoint("BOTTOMRIGHT"); line:SetWidth(2)
            end
            line:Hide()
            cell.selection[#cell.selection + 1] = line
        end
        f.cells[i] = cell
    end
    f.detailTitle = text(f, "GameFontNormal", 435, 80, "")
    tint(f.detailTitle, 0.90, 0.77, 0.47)
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxDetailsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 435, -116)
    scroll:SetSize(290, 328)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(275, 1)
    scroll:SetScrollChild(content)
    f.detailText = text(content, "GameFontHighlightSmall", 0, 0, "")
    f.detailText:SetWidth(270)
    f.detailText:SetJustifyV("TOP")
    if type(f.detailText.SetSpacing) == "function" then f.detailText:SetSpacing(4) end
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
    renderCalendar(true)
    window:Show()
end

Toolbox.toggleCalendar = openCalendar

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" and argument == ADDON then
        if type(TigerioForeverToolboxDB) ~= "table" then TigerioForeverToolboxDB = {} end
        if type(TigerioForeverToolboxDB.characters) ~= "table" then TigerioForeverToolboxDB.characters = {} end
    elseif event == "ADDON_LOADED" and argument == "AdventureJournal" and currentCharacter then
        importAdventureJournal()
        if window and window:IsShown() then renderCalendar() end
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
        importAdventureJournal()
    elseif event == "PLAYER_LEVEL_UP" and currentCharacter then
        local now = time()
        accountTime(now)
        if not hasLevel(currentCharacter, argument, now) then
            local record = dailyRecord(currentCharacter, dayKey(now))
            record.levels[#record.levels + 1] = {level = argument, when = now}
        end
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
SlashCmdList.TIGERIOFOREVERTOOLBOX = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "move" then
        Toolbox.toggleFrameMove()
    elseif command == "resetmove" then
        Toolbox.resetFrameMoves()
    elseif command == "dungeon" then
        Toolbox.toggleDungeonGuide()
    elseif command == "weapon" or command == "weapons" then
        Toolbox.toggleWeaponMasters()
    elseif command == "luck" then
        Toolbox.toggleLuckCollection()
    elseif command == "" then
        openCalendar()
    else
        print("|cffffd100升级工具箱|r /tft 打开日历；/tft dungeon 副本任务；/tft weapon 武器大师；/tft luck 奇珍图鉴；/tft move 移动框体；/tft resetmove 重置位置。")
    end
end
