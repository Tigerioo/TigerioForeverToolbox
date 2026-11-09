local _, toolbox = ...
local window

local function safeText(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function render()
    local entries, lines = toolbox.changelogEntries, {}
    if type(entries) == "table" then
        for _, group in ipairs(entries) do
            if type(group) == "table" and type(group.title) == "string" then
                if #lines > 0 then lines[#lines + 1] = "" end
                lines[#lines + 1] = "|cffffd27f" .. safeText(group.title) .. "|r"
                if type(group.lines) == "table" then
                    for _, line in ipairs(group.lines) do
                        if type(line) == "string" then lines[#lines + 1] = "• " .. safeText(line) end
                    end
                end
            end
        end
    end
    window.text:SetText(#lines > 0 and table.concat(lines, "\n") or "暂无更新日志")
    window.content:SetHeight(math.max(1, window.text:GetStringHeight() + 20))
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxChangelog", "Tigerio 的无限升级工具箱", 800, 540, "changelog")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 70, -42)
    title:SetText("更新日志")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 764, 417)
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxChangelogScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 34, -101)
    scroll:SetSize(716, 384)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(708, 1)
    scroll:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetWidth(700)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    f.text, f.content, f.scroll = text, content, scroll
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxChangelog"
    f:Hide()
    return f
end

function toolbox.toggleChangelog()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    render()
end
