local _, toolbox = ...
local window, message

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    return type(canaccesstable) ~= "function" or call(canaccesstable, value) == true
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result end
end

local function safeText(value)
    if not readable(value) or type(value) ~= "string" then return "" end
    return value:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, locked = pcall(InCombatLockdown)
    return not ok or not readable(locked) or not not locked
end

local function label(parent, x, y, text, font)
    local result = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    result:SetPoint("TOPLEFT", x, -y)
    result:SetJustifyH("LEFT")
    result:SetText(text or "")
    return result
end

local function button(parent, width, height, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.14, 0.105, 0.075, 0.95)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.9, 0.67, 0.25, 0.18)
    local caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caption:SetPoint("CENTER")
    caption:SetText(text or "")
    b.caption, b.background = caption, background
    return b
end

local function editBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function spellInfo(id)
    local info = C_Spell and call(C_Spell.GetSpellInfo, id)
    if tableOK(info) then return safeText(field(info, "name")), field(info, "iconID") end
    return "", nil
end

-- The book is authoritative for what this character can currently select.
-- A spell book does not identify every spell that grants an aura, so the
-- list is labelled as learned spells rather than claiming all are buffs.
local function spellBook()
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if type(book) ~= "table" or bank == nil or spellType == nil then return nil end
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
                        local id, kind = field(info, "spellID"), field(info, "itemType")
                        local passive, offspec = field(info, "isPassive"), field(info, "isOffSpec")
                        if kind == spellType and passive == false and offspec == false
                            and type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] then
                            local name, icon = safeText(field(info, "name")), field(info, "iconID")
                            if name ~= "" then
                                result[#result + 1] = {id = id, name = name, icon = icon}
                                seen[id] = true
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
    return result
end

local render
local function perform(method, id)
    if inCombat() then message = "战斗中无法配置"; render(); return end
    if type(method) ~= "function" then message = "增益监控不可用"; render(); return end
    local ok, success, reason = pcall(method, id)
    if not ok or success ~= true then
        message = safeText(reason)
        if message == "" then message = "操作失败" end
    else message = nil end
    render()
end

local function createWindow()
    local f = CreateFrame("Frame", "TigerioForeverToolboxShamanBuffConfig", UIParent, "PortraitFrameTemplate")
    f:SetSize(720, 490)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetTitle("增益监控")
    if type(f.SetPortraitTextureRaw) == "function" then f:SetPortraitTextureRaw("Interface\\Icons\\Spell_Nature_LightningShield") end
    if f.Bg then f.Bg:SetColorTexture(30 / 255, 23 / 255, 18 / 255, 0.97) end
    label(f, 28, 48, "已学技能", "GameFontNormal")
    label(f, 390, 48, "监控列表", "GameFontNormal")
    label(f, 28, 75, "搜索")
    f.search = editBox(f, 235)
    f.search:SetPoint("TOPLEFT", 75, -68)
    f.search:SetScript("OnTextChanged", function() if f:IsShown() then render() end end)
    local scroll = CreateFrame("ScrollFrame", "TigerioForeverToolboxShamanBuffScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 28, -102); scroll:SetSize(314, 306)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(306, 1); scroll:SetScrollChild(content)
    f.scroll, f.content, f.spells, f.watches = scroll, content, {}, {}
    label(f, 390, 299, "法术 ID")
    f.idBox = editBox(f, 120)
    f.idBox:SetPoint("TOPLEFT", 458, -292)
    f.idBox:SetNumeric(true)
    local add = button(f, 68, 24, "添加")
    add:SetPoint("TOPLEFT", 594, -292)
    add:SetScript("OnClick", function()
        local value = f.idBox:GetText()
        if not readable(value) or type(value) ~= "string" then message = "请输入法术 ID"; render(); return end
        local id = tonumber(value)
        if not id or id <= 0 or id ~= math.floor(id) then message = "请输入法术 ID"; render(); return end
        perform(toolbox.addShamanBuffWatch, id)
    end)
    f.idBox:SetScript("OnEnterPressed", function() add:Click() end)
    f.status = label(f, 390, 340, "")
    f.status:SetWidth(290)
    label(f, 390, 370, "常用增益", "GameFontNormal")
    f.suggestions = {}
    for i, id in ipairs({324, 408510, 131, 546}) do
        local suggestion = button(f, 67, 24, "")
        suggestion:SetPoint("TOPLEFT", 390 + (i - 1) * 70, -391)
        suggestion.caption = suggestion:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        suggestion.caption:SetPoint("CENTER")
        suggestion.caption:SetWidth(65)
        suggestion.spellID = id
        suggestion:SetScript("OnClick", function(self) perform(toolbox.addShamanBuffWatch, self.spellID) end)
        f.suggestions[i] = suggestion
    end
    label(f, 390, 431, "显示模式", "GameFontNormal")
    f.modeButtons = {}
    for index, choice in ipairs({{"missing", "仅缺失"}, {"always", "总是显示"}}) do
        local selectedMode = choice[1]
        local modeButton = button(f, 84, 24, choice[2])
        modeButton:SetPoint("TOPLEFT", 462 + (index - 1) * 90, -423)
        modeButton:SetScript("OnClick", function()
            perform(toolbox.setShamanBuffDisplayMode, selectedMode)
        end)
        f.modeButtons[selectedMode] = modeButton
    end
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    f:Hide()
    return f
end

render = function()
    if not window then return end
    local watches = call(toolbox.getShamanBuffWatchList)
    if not tableOK(watches) then watches = {} end
    local selected = {}
    for _, id in ipairs(watches) do if type(id) == "number" then selected[id] = true end end
    local query = window.search:GetText()
    if not readable(query) or type(query) ~= "string" then query = "" end
    query = query:lower():match("^%s*(.-)%s*$")
    local spells, count = spellBook(), 0
    for _, entry in ipairs(spells or {}) do
        if entry.name:lower():find(query, 1, true) or tostring(entry.id):find(query, 1, true) then
            count = count + 1
            local row = window.spells[count]
            if not row then
                row = button(window.content, 300, 26, "")
                row:SetPoint("TOPLEFT", 0, -(count - 1) * 29)
                row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 3, 0)
                row.text = label(row, 30, 5, ""); row.text:SetWidth(265)
                row:SetScript("OnClick", function(self) perform(toolbox.addShamanBuffWatch, self.spellID) end)
                window.spells[count] = row
            end
            row.spellID = entry.id
            row.text:SetText(entry.name .. "  " .. entry.id .. (selected[entry.id] and "  ✓" or ""))
            if type(entry.icon) == "string" or type(entry.icon) == "number" then row.icon:SetTexture(entry.icon); row.icon:Show() else row.icon:Hide() end
            row:Show()
        end
    end
    for i = count + 1, #window.spells do window.spells[i]:Hide() end
    window.content:SetHeight(math.max(1, count * 29))
    for i = 1, 6 do
        local row = window.watches[i]
        if not row then
            row = button(window, 278, 29, "")
            row:SetPoint("TOPLEFT", 390, -80 - (i - 1) * 34)
            row.text = label(row, 8, 6, ""); row.text:SetWidth(235)
            row:SetScript("OnClick", function(self) if self.spellID then perform(toolbox.removeShamanBuffWatch, self.spellID) end end)
            window.watches[i] = row
        end
        local id = watches[i]
        if type(id) == "number" then
            local name = spellInfo(id)
            row.spellID = id
            row.text:SetText((name ~= "" and name or "未知") .. "  " .. id .. "   ×")
            row:Show()
        else row.spellID = nil; row:Hide() end
    end
    for _, suggestion in ipairs(window.suggestions) do
        local name = spellInfo(suggestion.spellID)
        if name ~= "" then suggestion.caption:SetText(name); suggestion:Show() else suggestion:Hide() end
    end
    local mode = call(toolbox.getShamanBuffDisplayMode)
    for name, modeButton in pairs(window.modeButtons) do
        if mode == name then
            modeButton.caption:SetTextColor(1, 0.82, 0)
            modeButton.background:SetColorTexture(0.35, 0.25, 0.11, 1)
        else
            modeButton.caption:SetTextColor(0.8, 0.8, 0.8)
            modeButton.background:SetColorTexture(0.14, 0.105, 0.075, 0.95)
        end
        if (mode == "missing" or mode == "always") and not inCombat()
            and type(toolbox.setShamanBuffDisplayMode) == "function" then
            modeButton:Enable()
        else
            modeButton:Disable()
        end
    end
    window.status:SetText(message or (not spells and "技能列表不可用" or ""))
end

function toolbox.openShamanBuffConfig()
    if inCombat() then return false, "战斗中无法配置" end
    if not window then window = createWindow() end
    message = nil
    window:Show(); window:Raise(); render()
    return true
end
