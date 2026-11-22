local _, toolbox = ...
local window, keyword

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function safeText(value, fallback)
    if not readable(value) or type(value) ~= "string" then return fallback end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function updateKeyword(text)
    local value = text:match("^%s*(.-)%s*$"):lower()
    if value == keyword then return end
    keyword = value
    window.messages:Clear()
    window.status:SetText(value == "" and "输入关键词，开始过滤新频道消息。" or "正在过滤新频道消息；记录仅保留到重载界面。")
end

local function createWindow()
    local f = CreateFrame("Frame", "TigerioForeverToolboxChatFilter", UIParent, "PortraitFrameTemplate")
    f:Hide()
    f:SetSize(600, 420)
    f:SetPoint("CENTER")
    f:SetTitle("聊天频道过滤")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.Bg then f.Bg:SetColorTexture(30 / 255, 23 / 255, 18 / 255, 0.94) end

    local caption = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    caption:SetPoint("TOPLEFT", 30, -58)
    caption:SetText("关键词")
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(290, 24)
    input:SetPoint("TOPLEFT", 90, -53)
    input:SetAutoFocus(false)
    input:SetMaxLetters(100)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f:SetScript("OnHide", function() input:ClearFocus() end)

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(100, 26)
    clear:SetPoint("TOPRIGHT", -25, -52)
    clear:SetText("清空结果")
    clear:SetScript("OnClick", function() f.messages:Clear() end)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 30, -88)
    f.status:SetText("输入关键词，开始过滤新频道消息。")
    toolbox.nativeSection(f, 20, 110, 560, 285)
    local messages = CreateFrame("ScrollingMessageFrame", nil, f)
    messages:SetPoint("TOPLEFT", 32, -120)
    messages:SetPoint("BOTTOMRIGHT", -32, 38)
    messages:SetFontObject(GameFontHighlight)
    messages:SetJustifyH("LEFT")
    messages:SetFading(false)
    messages:SetMaxLines(300)
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    messages:SetHyperlinksEnabled(true)
    messages:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if type(SetItemRef) == "function" then SetItemRef(link, text, button, self) end
    end)
    f.messages = messages
    input:SetScript("OnTextChanged", function(self) updateKeyword(self:GetText()) end)
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxChatFilter"
    return f
end

function toolbox.toggleChatFilter()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_CHANNEL")
events:SetScript("OnEvent", function(_, _, message, sender, _, channel)
    if not window or not keyword or keyword == "" then return end
    if not readable(message) or type(message) ~= "string" then
        window.status:SetText("当前频道消息无法读取，暂不能过滤。")
        return
    end
    window.status:SetText("正在过滤新频道消息；记录仅保留到重载界面。")
    -- Search the visible label of linked items, not their hidden identifiers.
    local visible = message:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if not visible:lower():find(keyword, 1, true) then return end
    local channelName = safeText(channel, "频道")
    local senderName = safeText(sender, "未知玩家")
    window.messages:AddMessage("[" .. channelName .. "] [" .. senderName .. "]: " .. message, 1, 1, 1)
end)

SLASH_TIGERIOCHATFILTER1 = "/tftchat"
SlashCmdList.TIGERIOCHATFILTER = toolbox.toggleChatFilter
