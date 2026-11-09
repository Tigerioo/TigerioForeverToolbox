local _, toolbox = ...
local window, selected, message

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and readable(result) then return result end
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    return call(canaccesstable, value) == true
end

local function field(value, name)
    local ok, result = pcall(function() return value[name] end)
    if ok and readable(result) then return result end
end

local function safeText(value)
    if not readable(value) or type(value) ~= "string" or value == "" then return "未知" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    return value ~= nil and value ~= false
end

local function label(parent, font, x, y, value)
    local result = parent:CreateFontString(nil, "OVERLAY", font)
    result:SetPoint("TOPLEFT", x, -y)
    result:SetJustifyH("LEFT")
    result:SetText(value or "")
    return result
end

local function quietButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.14, 0.105, 0.075, 0.95)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    return button
end

-- Each spellbook entry remains distinct by spellID; never promote a chosen rank.
local function spellBook()
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if type(book) ~= "table" or bank == nil or spellType == nil
        or type(book.GetNumSpellBookSkillLines) ~= "function"
        or type(book.GetSpellBookSkillLineInfo) ~= "function"
        or type(book.GetSpellBookItemInfo) ~= "function" then return nil end
    local count = call(book.GetNumSpellBookSkillLines)
    if type(count) ~= "number" or count < 0 or count > 200 then return nil end
    local result, seen = {}, {}
    for i = 1, count do
        local line = call(book.GetSpellBookSkillLineInfo, i)
        if tableOK(line) then
            local offset, amount = field(line, "itemIndexOffset"), field(line, "numSpellBookItems")
            if type(offset) == "number" and offset >= 0 and offset == math.floor(offset)
                and type(amount) == "number" and amount >= 0 and amount <= 1000 and amount == math.floor(amount) then
                for index = offset + 1, offset + amount do
                    local info = call(book.GetSpellBookItemInfo, index, bank)
                    if tableOK(info) then
                        local kind, id = field(info, "itemType"), field(info, "spellID")
                        local passive, offspec = field(info, "isPassive"), field(info, "isOffSpec")
                        local name, rank, icon = field(info, "name"), field(info, "subName"), field(info, "iconID")
                        if kind == spellType and passive == false and offspec == false
                            and type(id) == "number" and id > 0 and id == math.floor(id)
                            and type(name) == "string" and name ~= "" and not seen[id] then
                            result[#result + 1] = {id = id, name = safeText(name), rank = safeText(rank), icon = icon}
                            seen[id] = true
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.id < b.id
    end)
    return result
end

local function config()
    if type(toolbox.getHUDConfig) ~= "function" then return nil, "HUD 不可用" end
    local ok, value, reason = pcall(toolbox.getHUDConfig)
    if not ok or not tableOK(value) then return nil, safeText(reason) end
    return value
end

local function actionBarOptions()
    if type(toolbox.getActionBarOptions) ~= "function" then return nil, "动作条设置不可用" end
    local ok, value = pcall(toolbox.getActionBarOptions)
    if not ok or not tableOK(value) then return nil, "动作条设置不可用" end
    local enabled, hide, hover = field(value, "enabled"), field(value, "hide"), field(value, "hover")
    if type(enabled) ~= "boolean" or type(hide) ~= "boolean" or type(hover) ~= "boolean" then
        return nil, "动作条设置不可用"
    end
    return {enabled = enabled, hide = hide, hover = hover}
end

local function perform(fn, ...)
    if inCombat() then message = "战斗中无法配置"; return false end
    if type(fn) ~= "function" then message = "HUD 不可用"; return false end
    local ok, success, reason = pcall(fn, ...)
    if not ok or success ~= true then message = safeText(reason); return false end
    message = readable(reason) and type(reason) == "string" and reason ~= "" and safeText(reason) or nil
    return true
end

local function textureFor(id)
    if type(id) ~= "number" or not C_Spell then return nil end
    local texture = call(C_Spell.GetSpellTexture, id)
    if type(texture) == "number" or type(texture) == "string" then return texture end
end

local render
local function choose(id)
    if not selected then return end
    -- Recheck against the current book before writing, including after spell changes.
    local book, found = spellBook(), false
    if book then for _, entry in ipairs(book) do if entry.id == id then found = true; break end end end
    if not found then message = "技能不可用"; render(); return end
    if perform(toolbox.setHUDSlot, selected, id) then selected = nil end
    render()
end

local function addSlot(f, index, x, y, size, displayNumber)
    local button = CreateFrame("Button", nil, f)
    size = size or 43
    button:SetSize(size, size)
    button:SetPoint("TOPLEFT", x, -y)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.11, 0.085, 0.06, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon = icon
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.84, 0.62, 0.20, 0.25)
    local mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("BOTTOMLEFT", 0, 0)
    mark:SetPoint("BOTTOMRIGHT", 0, 0)
    mark:SetHeight(2)
    mark:SetColorTexture(0.9, 0.7, 0.25, 1)
    button.marker = mark
    button.displayNumber = displayNumber or index
    button.number = label(button, "GameFontNormalSmall", 4, 3, tostring(button.displayNumber))
    button.unavailable = label(button, "GameFontHighlight", (size - 9) / 2, (size - 16) / 2, "?")
    button:SetScript("OnClick", function(_, mouse)
        if inCombat() then message = "战斗中无法配置"; render(); return end
        if mouse == "RightButton" then
            if perform(toolbox.setHUDSlot, index, nil) then selected = nil end
        else
            selected, message = index, nil
            if window.listScroll then window.listScroll:SetVerticalScroll(0) end
        end
        render()
    end)
    button:SetScript("OnReceiveDrag", function()
        if inCombat() then message = "战斗中无法配置"; render(); return end
        if type(GetCursorInfo) ~= "function" then return end
        local ok, kind, _, _, spellID = pcall(GetCursorInfo)
        if not ok or not readable(kind) or not readable(spellID) or kind ~= "spell" or type(spellID) ~= "number" then return end
        local book, found = spellBook(), false
        if book then for _, entry in ipairs(book) do if entry.id == spellID then found = true; break end end end
        if not found then message = "技能不可用"; render(); return end
        if perform(toolbox.setHUDSlot, index, spellID) and type(ClearCursor) == "function" then ClearCursor() end
        render()
    end)
    return button
end

local function updateSpells()
    if not window then return end
    local book = selected and spellBook() or nil
    local search = window.search:GetText() or ""
    if not readable(search) or type(search) ~= "string" then search = "" end
    search = search:lower():match("^%s*(.-)%s*$")
    local count = 0
    for _, entry in ipairs(book or {}) do
        local name = entry.name .. (entry.rank ~= "未知" and ("  " .. entry.rank) or "")
        if name:lower():find(search, 1, true) then
            count = count + 1
            local row = window.spellRows[count]
            if not row then
                row = quietButton(window.listContent, 296, 27)
                row:SetPoint("TOPLEFT", 0, -(count - 1) * 30)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetPoint("LEFT", 4, 0)
                row.icon:SetSize(21, 21)
                row.spellLabel = label(row, "GameFontHighlightSmall", 31, 6, "")
                row.spellLabel:SetWidth(255)
                row:SetScript("OnClick", function(self) choose(self.spellID) end)
                window.spellRows[count] = row
            end
            row.spellID = entry.id
            row.spellLabel:SetText(name)
            if type(entry.icon) == "number" or type(entry.icon) == "string" then
                row.icon:SetTexture(entry.icon)
                row.icon:Show()
            else row.icon:Hide() end
            row:Show()
        end
    end
    for i = count + 1, #window.spellRows do window.spellRows[i]:Hide() end
    window.listContent:SetHeight(math.max(1, count * 30))
    if not selected then window.listMessage:SetText("选择技能槽")
    elseif not book then window.listMessage:SetText("技能列表不可用")
    elseif count == 0 then window.listMessage:SetText("未找到技能")
    else window.listMessage:SetText("") end
    local selectedSlot = selected and window.slots[selected]
    window.listTitle:SetText(selectedSlot and ("选择技能 · " .. selectedSlot.displayNumber) or "技能")
end

render = function()
    if not window or not window:IsShown() then return end
    local data, reason = config()
    local slots = data and field(data, "slots")
    if not tableOK(slots) then slots = {} end
    for index, button in ipairs(window.slots) do
        local id = field(slots, index)
        local texture = textureFor(id)
        if texture then button.icon:SetTexture(texture); button.icon:Show() else button.icon:Hide() end
        if type(id) == "number" and not texture then button.unavailable:Show() else button.unavailable:Hide() end
        if selected == index then button.marker:Show() else button.marker:Hide() end
    end
    local enabled = data and field(data, "enabled") == true
    local unlocked = data and field(data, "unlocked") == true
    local notice = data and field(data, "nativeFrameNotice")
    window.enable.caption:SetText(enabled and "关闭 HUD" or "启用 HUD")
    window.lock.caption:SetText(unlocked and "锁定位置" or "移动位置")
    window.status:SetText(message or (not data and reason or (inCombat() and "战斗中无法配置" or (notice and safeText(notice) or ""))))
    local bars, barsError = actionBarOptions()
    local locked = inCombat()
    for _, key in ipairs({"enabled", "hide", "hover"}) do
        local check = window.actionBarChecks[key]
        check:SetChecked(bars and bars[key] or false)
        local available = bars and not locked and (key == "enabled" or bars.enabled)
            and (key ~= "hover" or bars.hide)
        if available then check:Enable() else check:Disable() end
    end
    window.actionBarStatus:SetText(barsError or (bars and not bars.enabled and "动作条样式已关闭" or ""))
    updateSpells()
end

local function createWindow()
    local f = toolbox.createNativeWindow("TigerioForeverToolboxHUDSettings", "Tigerio 的无限升级工具箱", 800, 540, "hud")
    label(f, "GameFontNormalLarge", 70, 42, "HUD 设置")
    toolbox.nativeDivider(f, 22, 76, 755)
    toolbox.nativeSection(f, 18, 87, 374, 417)
    toolbox.nativeSection(f, 402, 87, 380, 417)
    f.status = label(f, "GameFontHighlightSmall", 30, 108, "")
    f.status:SetWidth(350)
    f.enable = quietButton(f, 100, 24)
    f.enable:SetPoint("TOPLEFT", 30, -138)
    f.enable.caption = f.enable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.enable.caption:SetPoint("CENTER")
    f.enable:SetScript("OnClick", function()
        local data = config()
        if data then perform(toolbox.setHUDEnabled, field(data, "enabled") ~= true); render() end
    end)
    f.lock = quietButton(f, 100, 24)
    f.lock:SetPoint("TOPLEFT", 144, -138)
    f.lock.caption = f.lock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lock.caption:SetPoint("CENTER")
    f.lock:SetScript("OnClick", function()
        local data = config()
        if data then perform(toolbox.setHUDUnlocked, field(data, "unlocked") ~= true); render() end
    end)
    label(f, "GameFontNormal", 30, 185, "左侧 · 攻击")
    label(f, "GameFontNormal", 216, 185, "右侧 · 控制 / 保命")
    label(f, "GameFontNormal", 30, 285, "下方")
    f.slots = {}
    -- Preserve existing slot IDs while keeping the displayed numbering in visual order.
    for i = 1, 5 do
        local index = i == 5 and 15 or i
        f.slots[index] = addSlot(f, index, 30 + (i - 1) * 35, 209, 34, i)
    end
    for i = 1, 5 do
        local index = i == 5 and 16 or i + 4
        f.slots[index] = addSlot(f, index, 216 + (i - 1) * 35, 209, 34, i + 5)
    end
    for i = 1, 6 do f.slots[i + 8] = addSlot(f, i + 8, 30 + (i - 1) * 48, 309, 43, i + 10) end

    toolbox.nativeDivider(f, 30, 372, 344)
    label(f, "GameFontNormal", 30, 381, "系统动作条")
    f.actionBarChecks = {}
    local function actionBarCheck(key, x, y, title)
        local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", x, -y)
        label(f, "GameFontHighlightSmall", x + 26, y + 5, title)
        check:SetScript("OnClick", function(self)
            local value = self:GetChecked()
            if not readable(value) then render(); return end
            perform(toolbox.setActionBarOption, key, value == true or value == 1)
            render()
        end)
        f.actionBarChecks[key] = check
    end
    actionBarCheck("enabled", 28, 400, "动作条样式")
    actionBarCheck("hide", 28, 428, "默认隐藏")
    actionBarCheck("hover", 166, 428, "鼠标悬停显示")
    f.actionBarStatus = label(f, "GameFontHighlightSmall", 30, 463, "")
    f.actionBarStatus:SetWidth(340)

    f.listTitle = label(f, "GameFontNormal", 414, 100, "技能")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(315, 24)
    search:SetPoint("TOPLEFT", 416, -128)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxHUDSpellScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 414, -165)
    scroll:SetSize(310, 315)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(296, 1)
    scroll:SetScrollChild(content)
    f.listScroll, f.listContent, f.spellRows = scroll, content, {}
    f.listMessage = label(f, "GameFontHighlightSmall", 422, 172, "")
    f.listMessage:SetWidth(280)
    search:SetScript("OnTextChanged", function() scroll:SetVerticalScroll(0); updateSpells() end)
    UISpecialFrames[#UISpecialFrames + 1] = "TigerioForeverToolboxHUDSettings"
    f:Hide()
    return f
end

function toolbox.toggleHUDSettings()
    if not window then window = createWindow() end
    if window:IsShown() then window:Hide(); return end
    window:Show()
    render()
end

function toolbox.hudChanged()
    render()
end

function toolbox.onActionBarOptionsChanged()
    render()
end

local events = CreateFrame("Frame")
for _, event in ipairs({"SPELLS_CHANGED", "SPELL_TEXT_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then message = nil end
    render()
end)

SLASH_TIGERIOHUD1 = "/tfthud"
SlashCmdList.TIGERIOHUD = toolbox.toggleHUDSettings
