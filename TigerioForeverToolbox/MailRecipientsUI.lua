-- Mail recipient picker.  The original mail input and send handlers remain in charge.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local panel, trigger, form, recipientBox, pending
local group, message, chosenText, originalColor = "characters", nil, nil, nil
local render

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function stringValue(value)
    return readable(value) and type(value) == "string" and value or nil
end

local function safeText(value)
    local text = stringValue(value)
    if not text or text == "" then return "未知" end
    return text:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, locked = pcall(InCombatLockdown)
    return not ok or not readable(locked) or (locked ~= nil and locked ~= false)
end

local function classColor(token)
    if not readable(token) or type(token) ~= "string" then return 1, 1, 1 end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    if not readable(colors) or type(colors) ~= "table" then return 1, 1, 1 end
    local ok, color = pcall(function() return colors[token] end)
    if not ok or not readable(color) or type(color) ~= "table" then return 1, 1, 1 end
    local checked, r, g, b = pcall(function() return color.r, color.g, color.b end)
    if not checked or not readable(r) or not readable(g) or not readable(b)
        or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return 1, 1, 1 end
    return r, g, b, true
end

local function classToken(value)
    value = stringValue(value)
    if not value then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    local upper = value:upper()
    local fallback = {WARRIOR="战士", PALADIN="圣骑士", HUNTER="猎人", ROGUE="潜行者",
        PRIEST="牧师", SHAMAN="萨满祭司", MAGE="法师", WARLOCK="术士", DRUID="德鲁伊",
        DEATHKNIGHT="死亡骑士", MONK="武僧", DEMONHUNTER="恶魔猎手", EVOKER="唤魔师"}
    if fallback[upper] then return upper end
    for _, names in ipairs({LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}, fallback}) do
        if readable(names) and type(names) == "table" then
            for key, name in pairs(names) do
                if readable(key) and readable(name) and type(key) == "string" and name == value then return key end
            end
        end
    end
    if value == "盗贼" then return "ROGUE" end
    if value == "萨满" then return "SHAMAN" end
    return false
end

local function label(parent, font, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, -y)
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    if type(text.SetWordWrap) == "function" then text:SetWordWrap(false) end
    if type(text.SetMaxLines) == "function" then text:SetMaxLines(1) end
    return text
end

local function button(parent, w, h, text)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(w, h)
    local bg = control:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.14, 0.105, 0.075, 0.98)
    local hover = control:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(); hover:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    local caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caption:SetPoint("CENTER"); caption:SetText(text or "")
    control.caption, control.background = caption, bg
    return control
end

local function input(parent, width, limit)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 24); edit:SetAutoFocus(false)
    if type(edit.SetMaxLetters) == "function" then edit:SetMaxLetters(limit or 77) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

local function records()
    if type(toolbox.getMailRecipients) ~= "function" then return nil, "收件人暂不可用" end
    local ok, value, reason = pcall(toolbox.getMailRecipients, group)
    if not ok or not readable(value) or type(value) ~= "table" then return nil, stringValue(reason) or "收件人暂不可用" end
    if type(canaccesstable) == "function" then
        local checked, available = pcall(canaccesstable, value)
        if not checked or not readable(available) or available ~= true then return nil, "收件人暂不可用" end
    end
    return value
end

local function restoreColor()
    chosenText = nil
    if recipientBox and originalColor and type(recipientBox.SetTextColor) == "function" then
        pcall(recipientBox.SetTextColor, recipientBox, originalColor[1], originalColor[2], originalColor[3])
    end
end

local function choose(entry)
    if combat() then message = "战斗中无法选择"; render(); return end
    local recipient = stringValue(entry.recipient)
    if entry.selectable ~= true or not recipient or recipient == "" or not recipientBox then
        message = "收件人信息待补"; render(); return
    end
    -- Never add color escapes to the recipient or call any send API.
    restoreColor()
    if not pcall(recipientBox.SetText, recipientBox, recipient) then
        message = "无法填写收件人"; render(); return
    end
    chosenText = recipient
    if originalColor and type(recipientBox.SetTextColor) == "function" then
        local r, g, b, known = classColor(entry.classToken)
        if known then pcall(recipientBox.SetTextColor, recipientBox, r, g, b) end
    end
    if type(AutoComplete_HideIfAttachedTo) == "function" then pcall(AutoComplete_HideIfAttachedTo, recipientBox) end
    panel:Hide()
end

local function createRow(parent, index)
    local row = button(parent, 276, 27, "")
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 29)
    row.name = label(row, "GameFontHighlightSmall", 7, 7, 160)
    row.level = label(row, "GameFontHighlightSmall", 170, 7, 75)
    row.remove = button(row, 20, 20, "×")
    row.remove:SetPoint("RIGHT", -3, 0)
    row.remove:SetScript("OnClick", function(self)
        if combat() then message = "战斗中无法调整"; render(); return end
        local entry = self:GetParent().entry
        local fn = toolbox.removeManualMailRecipient
        local ok, success, reason = false, nil, nil
        if entry and entry.manual == true and type(fn) == "function" then ok, success, reason = pcall(fn, entry.identity) end
        if ok and success == true then message = nil else message = stringValue(reason) or "无法移除" end
        render()
    end)
    row:SetScript("OnClick", function(self) if self.entry then choose(self.entry) end end)
    row:SetScript("OnEnter", function(self)
        if not self.entry or not GameTooltip then return end
        local entry = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(safeText(entry.name))
        local realm = stringValue(entry.realm)
        if realm and realm ~= "" then GameTooltip:AddLine(safeText(realm), 1, 1, 1) end
        if entry.selectable ~= true then GameTooltip:AddLine("收件人信息待补", 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function showManual(value)
    if value then
        panel.manual:Show()
        panel.manualStatus:SetText("")
        panel.manualName:SetText(""); panel.manualClass:SetText(""); panel.manualLevel:SetText("")
        panel.manualName:SetFocus()
    else
        panel.manualName:ClearFocus(); panel.manualClass:ClearFocus(); panel.manualLevel:ClearFocus()
        panel.manual:Hide()
    end
end

local function createPanel(parent, edit)
    local f = CreateFrame("Frame", "TigerioForeverToolboxMailRecipients", parent, "BackdropTemplate")
    f:SetSize(320, 330)
    f:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -4)
    f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true)
    if type(f.SetBackdrop) == "function" then
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
        f:SetBackdropColor(0.09, 0.065, 0.045, 0.98)
        f:SetBackdropBorderColor(0.62, 0.42, 0.18, 1)
    end
    f.characters = button(f, 112, 25, "我的角色")
    f.characters:SetPoint("TOPLEFT", 12, -10)
    f.friends = button(f, 90, 25, "好友")
    f.friends:SetPoint("TOPLEFT", 130, -10)
    f.characters:SetScript("OnClick", function() group = "characters"; message = nil; f.scroll:SetVerticalScroll(0); render() end)
    f.friends:SetScript("OnClick", function()
        group = "friends"; message = nil; f.scroll:SetVerticalScroll(0)
        if type(toolbox.requestMailFriendsRefresh) == "function" then pcall(toolbox.requestMailFriendsRefresh) end
        render()
    end)
    f.search = input(f, 270, 77)
    f.search:SetPoint("TOPLEFT", 18, -44)
    f.search:SetScript("OnTextChanged", function() if f:IsShown() then f.scroll:SetVerticalScroll(0); render() end end)
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxMailRecipientScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -78); scroll:SetSize(279, 194)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(276, 1); scroll:SetScrollChild(content)
    f.scroll, f.content, f.rows = scroll, content, {}
    f.empty = label(f, "GameFontHighlightSmall", 22, 90, 250)
    f.status = label(f, "GameFontHighlightSmall", 14, 306, 285)
    f.add = button(f, 102, 24, "+ 添加收件人")
    f.add:SetPoint("TOPLEFT", 14, -278)
    f.add:SetScript("OnClick", function() message = nil; showManual(true) end)
    local close = button(f, 58, 24, "关闭")
    close:SetPoint("TOPRIGHT", -12, -278); close:SetScript("OnClick", function() f:Hide() end)

    local manual = CreateFrame("Frame", nil, f, "BackdropTemplate")
    manual:SetAllPoints(f); manual:SetFrameLevel(f:GetFrameLevel() + 10); manual:EnableMouse(true)
    if type(manual.SetBackdrop) == "function" then
        manual:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
        manual:SetBackdropColor(0.09, 0.065, 0.045, 1); manual:SetBackdropBorderColor(0.62, 0.42, 0.18, 1)
    end
    local title = label(manual, "GameFontNormal", 18, 17, 260); title:SetText("添加收件人")
    local nameLabel = label(manual, "GameFontHighlightSmall", 18, 56, 80); nameLabel:SetText("姓名")
    f.manualName = input(manual, 190, 77); f.manualName:SetPoint("TOPLEFT", 95, -49)
    local classLabel = label(manual, "GameFontHighlightSmall", 18, 95, 80); classLabel:SetText("职业（可选）")
    f.manualClass = input(manual, 190, 32); f.manualClass:SetPoint("TOPLEFT", 95, -88)
    local levelLabel = label(manual, "GameFontHighlightSmall", 18, 134, 80); levelLabel:SetText("等级（可选）")
    f.manualLevel = input(manual, 90, 3); f.manualLevel:SetPoint("TOPLEFT", 95, -127)
    if type(f.manualLevel.SetNumeric) == "function" then f.manualLevel:SetNumeric(true) end
    f.manualStatus = label(manual, "GameFontHighlightSmall", 18, 177, 278)
    local save = button(manual, 82, 26, "添加")
    save:SetPoint("TOPLEFT", 18, -210)
    save:SetScript("OnClick", function()
        if combat() then f.manualStatus:SetText("战斗中无法调整"); return end
        local name = stringValue(f.manualName:GetText())
        local class = classToken(f.manualClass:GetText())
        local rawLevel = stringValue(f.manualLevel:GetText()) or ""
        local level = rawLevel ~= "" and tonumber(rawLevel) or nil
        if not name or not name:match("%S") then f.manualStatus:SetText("请输入姓名"); return end
        if class == false then f.manualStatus:SetText("职业名称无法识别"); return end
        if rawLevel ~= "" and (not level or level < 1 or level ~= math.floor(level)) then f.manualStatus:SetText("等级无效"); return end
        local fn = toolbox.addManualMailRecipient
        local ok, success, reason = false, nil, nil
        if type(fn) == "function" then ok, success, reason = pcall(fn, name, class, level) end
        if not ok or success ~= true then f.manualStatus:SetText(stringValue(reason) or "无法添加"); return end
        f.manualStatus:SetText(""); showManual(false); group = "characters"; message = nil; render()
    end)
    local cancel = button(manual, 82, 26, "取消")
    cancel:SetPoint("TOPLEFT", 110, -210); cancel:SetScript("OnClick", function() f.manualStatus:SetText(""); showManual(false) end)
    f.manual = manual; manual:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    f:SetScript("OnHide", function()
        f.search:ClearFocus(); f.manualName:ClearFocus(); f.manualClass:ClearFocus(); f.manualLevel:ClearFocus(); f.manual:Hide()
    end)
    f:Hide()
    return f
end

render = function()
    if not panel or not panel:IsShown() then return end
    local entries, reason = records()
    local query = stringValue(panel.search:GetText()) or ""
    query = query:lower():match("^%s*(.-)%s*$")
    local count = 0
    for _, entry in ipairs(entries or {}) do
        if readable(entry) and type(entry) == "table" then
            local name = safeText(entry.name)
            local realm = stringValue(entry.realm)
            local display = realm and realm ~= "" and (name .. " - " .. safeText(realm)) or name
            if display:lower():find(query, 1, true) then
                count = count + 1
                local row = panel.rows[count]
                if not row then row = createRow(panel.content, count); panel.rows[count] = row end
                row.entry = entry
                row.name:SetText(display)
                local r, g, b = classColor(entry.classToken)
                row.name:SetTextColor(r, g, b)
                local level = entry.level
                local levelText = readable(level) and type(level) == "number" and level > 0 and level < math.huge and tostring(math.floor(level)) .. "级" or "等级未知"
                if levelText ~= "等级未知" and entry.levelSource == "last" then levelText = levelText .. " · 上次" end
                row.level:SetText(levelText)
                if entry.manual == true then row.remove:Show() else row.remove:Hide() end
                row:Show()
            end
        end
    end
    for index = count + 1, #panel.rows do panel.rows[index].entry = nil; panel.rows[index]:Hide() end
    panel.content:SetHeight(math.max(1, count * 29))
    if not entries then panel.empty:SetText(safeText(reason))
    elseif count == 0 then panel.empty:SetText(query ~= "" and "没有匹配的收件人" or "暂无收件人")
    else panel.empty:SetText("") end
    panel.characters.background:SetColorTexture(group == "characters" and 0.35 or 0.14, group == "characters" and 0.25 or 0.105, group == "characters" and 0.11 or 0.075, 1)
    panel.friends.background:SetColorTexture(group == "friends" and 0.35 or 0.14, group == "friends" and 0.25 or 0.105, group == "friends" and 0.11 or 0.075, 1)
    panel.status:SetText(message or "")
end

function toolbox.onMailRecipientsChanged()
    if panel and panel:IsShown() then render() end
end

local function setup()
    if combat() then pending = true; return end
    local currentForm, edit = _G.SendMailFrame, _G.SendMailNameEditBox
    if not currentForm or not edit then return end
    if trigger and form == currentForm and recipientBox == edit then pending = false; return end
    if trigger then return end -- Do not reparent a control if another addon replaces the native frame.
    form, recipientBox = currentForm, edit
    if type(edit.GetTextColor) == "function" then
        local ok, r, g, b = pcall(edit.GetTextColor, edit)
        if ok and readable(r) and readable(g) and readable(b) and type(r) == "number" and type(g) == "number" and type(b) == "number" then originalColor = {r,g,b} end
    end
    if type(edit.HookScript) == "function" then
        edit:HookScript("OnTextChanged", function(self)
            if not chosenText then return end
            local ok, current = pcall(self.GetText, self)
            if not ok or not readable(current) or current ~= chosenText then restoreColor() end
        end)
    end
    -- Keep the trigger within the narrow gap before the native postage display.
    trigger = button(form, 18, 18, "▼")
    trigger:SetPoint("LEFT", edit, "RIGHT", 1, 0)
    panel = createPanel(form, edit)
    trigger:SetScript("OnClick", function()
        if combat() then return end
        if panel:IsShown() then panel:Hide(); return end
        group, message = "characters", nil
        panel.search:SetText(""); panel.scroll:SetVerticalScroll(0)
        if type(AutoComplete_HideIfAttachedTo) == "function" then pcall(AutoComplete_HideIfAttachedTo, recipientBox) end
        panel:Show(); render()
    end)
    if type(form.HookScript) == "function" then form:HookScript("OnHide", function() if panel then panel:Hide() end end) end
    pending = false
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_REGEN_ENABLED", "FRIENDLIST_UPDATE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "MAIL_CLOSED" then if panel then panel:Hide() end; return end
    if event == "FRIENDLIST_UPDATE" then if panel and panel:IsShown() then render() end; return end
    if event ~= "PLAYER_REGEN_ENABLED" or pending then setup() end
end)
