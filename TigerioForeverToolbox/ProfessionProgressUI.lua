-- Compact profession progress page. Data and reminders are managed separately.
local _, toolbox = ...
local window, message

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function numberText(value)
    if not readable(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return "未知" end
    return tostring(math.floor(value))
end

local function safeText(value)
    if not readable(value) or type(value) ~= "string" or value == "" then return "未知" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function label(parent, template, x, y, value, width)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", x, -y)
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    text:SetText(value or "")
    return text
end

local function getProgress()
    if type(toolbox.getProfessionProgress) ~= "function" then return nil end
    local ok, value = pcall(toolbox.getProfessionProgress)
    if ok and readable(value) and type(value) == "table" then return value end
end

local render

local function createRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(720, 46)
    row:SetPoint("TOPLEFT", 38, -(178 + (index - 1) * 49))
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.09, 0.065, 0.8)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30); icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    row.name = label(row, "GameFontNormal", 48, 14, "", 145)
    row.skill = label(row, "GameFontHighlight", 225, 14, "", 128)
    row.reference = label(row, "GameFontHighlight", 390, 14, "", 100)
    row.advancement = label(row, "GameFontHighlight", 525, 14, "", 180)
    row:Hide()
    return row
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxProfessionProgress", "Tigerio 的无限升级工具箱", 800, 540, "profession")
    label(f, "GameFontNormalLarge", 70, 42, "专业技能")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 764, 417)
    f.summary = label(f, "GameFontHighlight", 38, 105, "")
    f.status = label(f, "GameFontHighlightSmall", 38, 488, "", 700)
    f.reminders = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.reminders:SetSize(24, 24)
    f.reminders:SetPoint("TOPLEFT", 565, -99)
    label(f, "GameFontHighlight", 592, 104, "专业提醒")
    f.reminders:SetScript("OnClick", function(self)
        local value = self:GetChecked()
        if not readable(value) then message = "设置暂不可用"; render(); return end
        local setter = toolbox.setProfessionRemindersEnabled
        local ok, result, reason = false, nil, nil
        if type(setter) == "function" then ok, result, reason = pcall(setter, value == true or value == 1) end
        if not ok or result ~= true then
            message = readable(reason) and type(reason) == "string" and reason ~= "" and reason or "设置暂不可用"
        else message = nil end
        render()
    end)
    toolbox.nativeDivider(f, 38, 140, 720)
    label(f, "GameFontNormalSmall", 86, 154, "专业")
    label(f, "GameFontNormalSmall", 263, 154, "技能 / 上限")
    label(f, "GameFontNormalSmall", 428, 154, "参考进度")
    label(f, "GameFontNormalSmall", 563, 154, "升阶")
    f.rows = {}
    for index = 1, 6 do f.rows[index] = createRow(f, index) end
    f.empty = label(f, "GameFontHighlight", 46, 190, "")
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    f:Hide()
    return f
end

render = function()
    if not window or not window:IsShown() then return end
    local data = getProgress()
    local valid = type(data) == "table"
    local level = valid and numberText(data.level) or "未知"
    local reference = valid and numberText(data.reference) or "未知"
    window.summary:SetText("角色等级 " .. level .. "   ·   参考进度 = 等级 × 5")
    local enabled = valid and data.remindersEnabled
    window.reminders:SetChecked(enabled == true)
    if type(enabled) == "boolean" and type(toolbox.setProfessionRemindersEnabled) == "function" then
        window.reminders:Enable()
    else window.reminders:Disable() end
    local entries = valid and data.professions
    if not readable(entries) or type(entries) ~= "table" then entries = {} end
    for index, row in ipairs(window.rows) do
        local entry = entries[index]
        if readable(entry) and type(entry) == "table" then
            row.name:SetText(safeText(entry.name))
            row.skill:SetText(numberText(entry.skill) .. " / " .. numberText(entry.max))
            row.reference:SetText(reference)
            local state = readable(entry.advancement) and entry.advancement or nil
            row.advancement:SetText((state == "已达上限" or state == "接近上限" or state == "查看升阶条件") and state or "—")
            local icon = readable(entry.icon) and entry.icon or nil
            if type(icon) == "number" or type(icon) == "string" then row.icon:SetTexture(icon); row.icon:Show()
            else row.icon:Hide() end
            row:Show()
        else row:Hide() end
    end
    local unavailable = not valid or data.available ~= true
    if #entries == 0 then
        window.empty:SetText(unavailable and "专业数据暂不可用" or "尚未学习专业")
    else window.empty:SetText("") end
    window.status:SetText(message or (unavailable and #entries > 0 and "部分专业数据暂不可用" or ""))
end

function toolbox.toggleProfessionProgress()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    message = nil
    window:Show()
    render()
end

function toolbox.onProfessionProgressChanged()
    render()
end
