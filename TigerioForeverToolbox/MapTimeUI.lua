local _, toolbox = ...
local window, refreshElapsed

local function label(parent, font, x, y, width)
    local value = parent:CreateFontString(nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, -y)
    value:SetJustifyH("LEFT")
    if width then value:SetWidth(width) end
    return value
end

local function safeText(value)
    if type(value) ~= "string" or value == "" then return "未知" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function duration(seconds)
    local value = math.floor(seconds)
    local hours, minutes = math.floor(value / 3600), math.floor(value / 60) % 60
    if hours > 0 then return string.format("%d 小时 %02d 分", hours, minutes) end
    if minutes > 0 then return string.format("%d 分 %02d 秒", minutes, value % 60) end
    return string.format("%d 秒", value)
end

local function render()
    if not window or not window:IsShown() then return end
    local ok, data = pcall(toolbox.getMapTimeStats)
    if not ok or type(data) ~= "table" then
        window.summary:SetText("地图统计暂不可用")
        window.text:SetText("")
        return
    end
    local rows, total = {}, 0
    for _, map in ipairs(data.maps) do
        total = total + map.seconds
        rows[#rows + 1] = safeText(map.name) .. (map.id == data.currentMapID and "  ·  当前" or "")
            .. "    " .. duration(map.seconds)
    end
    window.summary:SetText("当前角色  ·  已记录约 " .. duration(total))
    window.text:SetText(#rows > 0 and table.concat(rows, "\n") or "暂无地图记录")
    window.content:SetHeight(math.max(1, window.text:GetStringHeight() + 20))
    window.status:SetText(data.loading and "正在切换地图，暂停计时"
        or (not data.currentMapID and "当前地图暂不可识别，暂停计时"
        or "启用后在线停留估算；加载与未知地图不计，登出或重载时保存"))
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxMapTime", "Tigerio 的无限升级工具箱", 800, 540, "maptime")
    label(f, "GameFontNormalLarge", 70, 42, 300):SetText("地图停留时间")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 764, 417)
    f.summary = label(f, "GameFontHighlight", 38, 105, 690)
    label(f, "GameFontNormalSmall", 38, 145, 500):SetText("地图  /  累计停留时间")
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxMapTimeScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 38, -170); scroll:SetSize(700, 284)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(685, 1); scroll:SetScrollChild(content)
    f.text = label(content, "GameFontHighlight", 0, 0, 680)
    f.text:SetJustifyV("TOP")
    if type(f.text.SetSpacing) == "function" then f.text:SetSpacing(7) end
    f.content = content
    f.status = label(f, "GameFontHighlightSmall", 38, 478, 700)
    f:SetScript("OnUpdate", function(_, delta)
        refreshElapsed = (refreshElapsed or 0) + delta
        if refreshElapsed >= 5 then refreshElapsed = 0; render() end
    end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    f:Hide()
    return f
end

function toolbox.toggleMapTime()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    refreshElapsed = 0
    render()
end
