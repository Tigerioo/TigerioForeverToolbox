-- Personal shaman buff reminders. Aura queries stay conservative when restricted.
local _, toolbox = ...
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"
local MAX_WATCH = 6
local monitor
local learnedCache = {}
local observedAuraIDs = {}
local durationFormatter

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

local function validID(id)
    return readable(id) and type(id) == "number" and id > 0 and id == math.floor(id)
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function getDurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    durationFormatter = false
    if not C_StringUtil or type(C_StringUtil.CreateNumericRuleFormatter) ~= "function" then return nil end
    local rounding = Enum and Enum.NumericRuleFormatRounding or {}
    local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not ok or not formatter then return nil end
    ok = pcall(formatter.SetBreakpoints, formatter, {
        {threshold = 0, format = ""},
        {threshold = 0.000001, step = 1, rounding = rounding.Up or 1, format = "%d"},
        {threshold = 60, step = 1, rounding = rounding.Up or 1, format = "%d:%02d",
            components = {{div = 60, step = 1, rounding = rounding.Down or 2},
                {mod = 60, step = 1, rounding = rounding.Down or 2}}},
        {threshold = 180.000001, format = ""},
    })
    if not ok then return nil end
    local checked, visible = pcall(formatter.FormatNumber, formatter, 180)
    local hiddenOK, hidden = pcall(formatter.FormatNumber, formatter, 181)
    if checked and visible == "3:00" and hiddenOK and hidden == "" then durationFormatter = formatter end
    return durationFormatter or nil
end

local function characterKey()
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or not readable(class) or class ~= "SHAMAN" then return nil, "仅萨满可使用" end
    local guid = call(UnitGUID, "player")
    if type(guid) ~= "string" or not guid:match("^Player%-") then return nil, "角色数据暂不可用" end
    return guid
end

local function watchData(create)
    local guid, err = characterKey()
    if not guid then return nil, err end
    local db = TigerioForeverToolboxDB
    if type(db) ~= "table" then return nil, "角色数据暂不可用" end
    local root = db.shamanBuffWatch
    if root == nil and not create then return {} end
    if root == nil then root = {version = 1, characters = {}}; db.shamanBuffWatch = root end
    if type(root) ~= "table" or root.version ~= 1 or type(root.characters) ~= "table" then
        return nil, "增益监控数据不可用"
    end
    local list = root.characters[guid]
    if list == nil and not create then return {} end
    if list == nil then list = {}; root.characters[guid] = list end
    if type(list) ~= "table" or #list > MAX_WATCH then return nil, "增益监控数据不可用" end
    for i = 1, #list do if not validID(list[i]) then return nil, "增益监控数据不可用" end end
    return list
end

local function spellInfo(id)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = call(C_Spell.GetSpellInfo, id)
        if type(info) == "table" then
            local ok, name, icon = pcall(function() return info.name, info.iconID end)
            if ok and readable(name) and type(name) == "string" and name ~= "" then
                return name, readable(icon) and icon or nil
            end
        end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok and readable(name) and type(name) == "string" and name ~= "" then
            return name, readable(icon) and icon or nil
        end
    end
end

-- A monitored aura can use a different ID from a spellbook rank. Compare the
-- localized name too; absence is actionable only when a learned source is known.
local function learnedSpell(id, name)
    if learnedCache[id] ~= nil then return learnedCache[id] end
    local book = C_SpellBook
    local known = type(book) == "table" and book.IsSpellKnown or IsPlayerSpell or IsSpellKnown
    if type(known) == "function" and call(known, id) == true then learnedCache[id] = true; return true end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if type(book) ~= "table" or bank == nil or spellType == nil or type(book.GetNumSpellBookSkillLines) ~= "function"
        or type(book.GetSpellBookSkillLineInfo) ~= "function" or type(book.GetSpellBookItemInfo) ~= "function" then
        return nil
    end
    local count = call(book.GetNumSpellBookSkillLines)
    if type(count) ~= "number" or count < 0 or count > 200 then return nil end
    for i = 1, count do
        local line = call(book.GetSpellBookSkillLineInfo, i)
        if type(line) ~= "table" then return nil end
        local ok, offset, amount = pcall(function() return line.itemIndexOffset, line.numSpellBookItems end)
        if not ok or not readable(offset) or not readable(amount) or type(offset) ~= "number"
            or type(amount) ~= "number" or offset < 0 or amount < 0 or amount > 1000 then return nil end
        for index = offset + 1, offset + amount do
            local item = call(book.GetSpellBookItemInfo, index, bank)
            if type(item) ~= "table" then return nil end
            local itemOK, itemName, kind, offSpec = pcall(function() return item.name, item.itemType, item.isOffSpec end)
            if not itemOK or not readable(itemName) or type(itemName) ~= "string"
                or not readable(kind) or not readable(offSpec) then return nil end
            if itemName == name and kind == spellType and offSpec == false then
                learnedCache[id] = true; return true
            end
        end
    end
    learnedCache[id] = false
    return false
end

-- General aura secrecy describes the broad context, not every spell. The
-- per-spell predicate can allow an exact-ID lookup even in a secret context.
local function generalAurasRestricted()
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
        local restricted = call(C_Secrets.ShouldAurasBeSecret)
        if type(restricted) == "boolean" then return restricted end
        return nil
    end
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, inCombat = pcall(InCombatLockdown)
    if not ok or not readable(inCombat) then return true end
    return inCombat ~= false and inCombat ~= nil
end

local function canQueryAura(identifier, generalRestricted)
    if C_Secrets and type(C_Secrets.ShouldSpellAuraBeSecret) == "function" then
        local restricted = call(C_Secrets.ShouldSpellAuraBeSecret, identifier)
        return type(restricted) == "boolean" and not restricted
    end
    return generalRestricted == false
end

-- true = present, false = definitely absent, nil = unavailable/unknown.
local function auraPresent(id, name)
    local generalRestricted = generalAurasRestricted()
    if not canQueryAura(id, generalRestricted) then return nil end
    if not C_UnitAuras or type(C_UnitAuras.GetPlayerAuraBySpellID) ~= "function" then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or not readable(aura) then return nil end
    if aura ~= nil then return true, aura end
    -- Spell ranks can share the same aura name; match the player's helpful aura.
    if not name or not canQueryAura(name, generalRestricted)
        or type(C_UnitAuras.GetAuraDataBySpellName) ~= "function" then return nil end
    local namedOK, named = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if not namedOK or not readable(named) then return nil end
    if named ~= nil then return true, named end
    -- Even non-secret name/ID lookups can return nil for an invisible unit.
    -- Require a confirmed visible player when the general context is secret;
    -- an unknown secrecy context or unreadable visibility stays unknown.
    if generalRestricted ~= false then
        if generalRestricted ~= true or type(UnitIsVisible) ~= "function" then return nil end
        local visible = call(UnitIsVisible, "player")
        if visible ~= true then return nil end
    end
    return false
end

local function auraField(aura, key)
    if not readable(aura) or type(aura) ~= "table" then return nil end
    local ok, value = pcall(function() return aura[key] end)
    if ok and readable(value) then return value end
end

-- Aura IDs may differ from the selected spell's rank. Retain IDs observed
-- outside combat and include learned ranks with the same localized name.
local function candidateIDs(id, name, aura)
    local ids = {[id] = true}
    local observed = observedAuraIDs[id] or {}
    local auraID = auraField(aura, "spellId")
    if validID(auraID) then observed[auraID] = true end
    observedAuraIDs[id] = observed
    for value in pairs(observed) do ids[value] = true end
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if name and type(book) == "table" and bank ~= nil and spellType ~= nil then
        local count = call(book.GetNumSpellBookSkillLines)
        if finite(count) and count >= 0 and count <= 200 then
            for lineIndex = 1, count do
                local line = call(book.GetSpellBookSkillLineInfo, lineIndex)
                local offset, amount = auraField(line, "itemIndexOffset"), auraField(line, "numSpellBookItems")
                if finite(offset) and offset >= 0 and finite(amount) and amount >= 0 and amount <= 1000 then
                    for index = offset + 1, offset + amount do
                        local item = call(book.GetSpellBookItemInfo, index, bank)
                        local itemID = auraField(item, "spellID")
                        if auraField(item, "name") == name and auraField(item, "itemType") == spellType
                            and auraField(item, "isOffSpec") == false and validID(itemID) then
                            ids[itemID] = true
                        end
                    end
                end
            end
        end
    end
    return ids
end

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local value = call(InCombatLockdown)
    return value ~= false
end

local function nativeSlot(tile, id, name, aura)
    if inCombat() then return tile.nativeID == id and tile.nativeReady == true end
    local ids = candidateIDs(id, name, aura)
    local sorted = {}
    for value in pairs(ids) do sorted[#sorted + 1] = value end
    table.sort(sorted)
    local signature = table.concat(sorted, ",")
    if tile.nativeReady then
        if tile.nativeID == id and tile.nativeSignature == signature then return true end
        local ok = pcall(tile.nativeContainer.SetAuraSlotCandidateFilters, tile.nativeContainer, "watch",
            {includeSpellIDs = ids})
        if ok then tile.nativeID, tile.nativeSignature = id, signature; return true end
        pcall(tile.nativeContainer.Hide, tile.nativeContainer)
        tile.nativeReady, tile.nativeID = false, nil
        return false
    end
    if tile.nativeAttempted then return false end
    tile.nativeAttempted = true
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function"
        and type(C_AddOns.LoadAddOn) == "function"
        and call(C_AddOns.IsAddOnLoaded, "Blizzard_AuraContainer") ~= true then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local container
    local ok = pcall(function()
        local host = CreateFrame("Frame", nil, tile, "DisableUntrustedLayoutScriptsTemplate")
        host:SetAllPoints(tile)
        host:EnableMouse(false)
        container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
        container:SetPoint("TOPLEFT", host, "TOPLEFT")
        assert(type(container.AddAuraSlot) == "function" and type(container.SetAuraSlotCandidateFilters) == "function")
        local button = container:AddAuraSlot("watch", "HELPFUL", {
            candidateFilters = {includeSpellIDs = ids},
            initializeFrame = function(frame)
                frame:SetAllPoints(host)
                if type(frame.SetMouseClickEnabled) == "function" then frame:SetMouseClickEnabled(false) end
                if type(frame.EnableMouseMotion) == "function" then frame:EnableMouseMotion(false) end
                local image = frame:CreateTexture(nil, "ARTWORK")
                image:SetPoint("TOPLEFT", 3, -3); image:SetPoint("BOTTOMRIGHT", -3, 3)
                image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                frame:SetIcon(image)
                local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
                cooldown:SetAllPoints(image); cooldown:EnableMouse(false)
                if type(cooldown.SetDrawSwipe) == "function" then cooldown:SetDrawSwipe(false) end
                if type(cooldown.SetDrawEdge) == "function" then cooldown:SetDrawEdge(false) end
                if type(cooldown.SetHideCountdownNumbers) == "function" then cooldown:SetHideCountdownNumbers(true) end
                frame:SetDurationCooldown(cooldown)
                local formatter = getDurationFormatter()
                if formatter and type(frame.SetDurationText) == "function" then
                    local duration = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    duration:SetPoint("BOTTOM", frame, "TOP", 0, 2)
                    duration:SetShadowColor(0, 0, 0, 1); duration:SetShadowOffset(1, -1)
                    if not pcall(frame.SetDurationText, frame, duration, {textFormatter = formatter}) then
                        duration:Hide()
                    end
                end
                local count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                count:SetPoint("CENTER")
                count:SetTextColor(1, 1, 1)
                count:SetShadowColor(0, 0, 0, 1); count:SetShadowOffset(1, -1)
                frame:SetApplicationCount(count, nil)
            end,
        })
        assert(button)
        container:SetUnit("player")
        container:SetEnabled(true)
        tile.nativeHost, tile.nativeContainer = host, container
    end)
    if not ok then
        if container then pcall(container.Hide, container) end
        return false
    end
    tile.nativeReady, tile.nativeID, tile.nativeSignature = true, id, signature
    return true
end

local function clearTime(tile)
    tile:SetScript("OnUpdate", nil)
    tile.expirationTime = nil
    tile.time:SetText("")
    local cooldown = tile.cooldown
    if not cooldown then return end
    if type(cooldown.Clear) == "function" then pcall(cooldown.Clear, cooldown)
    elseif type(cooldown.SetCooldown) == "function" then pcall(cooldown.SetCooldown, cooldown, 0, 0) end
    cooldown:Hide()
end

local function showTime(tile, aura)
    clearTime(tile)
    local duration, expires = auraField(aura, "duration"), auraField(aura, "expirationTime")
    if not finite(duration) or duration <= 0 or not finite(expires) or expires <= 0
        or type(GetTime) ~= "function" then return end
    tile.expirationTime = expires
    local elapsed = 1
    local function update(self, delta)
        elapsed = elapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        local now = call(GetTime)
        if not finite(now) then self.time:SetText(""); return end
        local remaining = self.expirationTime - now
        if remaining > 180 or remaining <= 0 then
            self.time:SetText("")
        else
            local seconds = math.ceil(remaining)
            if seconds >= 60 then self.time:SetText(string.format("%d:%02d", math.floor(seconds / 60), seconds % 60))
            else self.time:SetText(tostring(seconds)) end
        end
    end
    tile:SetScript("OnUpdate", update)
    update(tile, 0)
end

local function refresh()
    if not monitor then return end
    local list = watchData(false)
    local always = list and list.displayMode ~= "missing"
    local visible = 0
    for _, id in ipairs(list or {}) do
        local name, icon = spellInfo(id)
        local state, aura
        -- Cache learned ranks while unrestricted, so a later combat-time
        -- absence check does not depend on a restricted spellbook lookup.
        if name and generalAurasRestricted() == false then learnedSpell(id, name) end
        if name then state, aura = auraPresent(id, name) end
        if state == false and learnedSpell(id, name) ~= true then state = nil end
        if always or state == false then
            visible = visible + 1
            local tile = monitor.tiles[visible]
            local native = always and nativeSlot(tile, id, name, aura)
            if native then
                if not inCombat() then
                    tile.nativeHost:Show()
                    clearTime(tile)
                    tile.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    tile.icon:SetDesaturated(true)
                    tile.border:SetVertexColor(1, 1, 1, 1)
                    tile.status:SetText("")
                    tile:Show()
                end
            else
                if tile.nativeHost and not inCombat() then tile.nativeHost:Hide() end
                clearTime(tile)
                tile.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if state == false then
                    tile.icon:SetDesaturated(true)
                    tile.border:SetVertexColor(1, 0.25, 0.16, 1)
                    tile.status:SetText("补")
                    tile.status:SetTextColor(1, 0.36, 0.25)
                elseif state == true then
                    tile.icon:SetDesaturated(false)
                    tile.border:SetVertexColor(1, 1, 1, 1)
                    local stacks = auraField(aura, "applications")
                    tile.status:SetText(finite(stacks) and stacks >= 1 and tostring(stacks) or "")
                    tile.status:SetTextColor(1, 1, 1)
                    if always then showTime(tile, aura) end
                else
                    tile.icon:SetDesaturated(false)
                    tile.border:SetVertexColor(0.55, 0.55, 0.55, 1)
                    tile.status:SetText("?")
                    tile.status:SetTextColor(0.85, 0.85, 0.85)
                end
                tile:Show()
            end
        end
    end
    for index = visible + 1, #monitor.tiles do
        local tile = monitor.tiles[index]
        clearTime(tile)
        if tile.nativeHost and not inCombat() then tile.nativeHost:Hide() end
        tile:Hide()
    end
end

function toolbox.getShamanBuffDisplayMode()
    local list, err = watchData(false)
    if not list then return nil, err end
    return list.displayMode == "missing" and "missing" or "always"
end

function toolbox.setShamanBuffDisplayMode(mode)
    if mode ~= "missing" and mode ~= "always" then return false, "设置无效" end
    local list, err = watchData(true)
    if not list then return false, err end
    list.displayMode = mode
    refresh()
    return true
end

function toolbox.getShamanBuffWatchList()
    local list, err = watchData(false)
    if not list then return nil, err end
    local result = {}
    for i, id in ipairs(list) do result[i] = id end
    return result
end

function toolbox.addShamanBuffWatch(id)
    if not validID(id) then return false, "法术 ID 无效" end
    if not spellInfo(id) then return false, "未找到法术，请确认 ID" end
    local list, err = watchData(true)
    if not list then return false, err end
    for _, existing in ipairs(list) do if existing == id then return false, "已添加" end end
    if #list >= MAX_WATCH then return false, "最多监控 6 个增益" end
    list[#list + 1] = id
    refresh()
    return true
end

function toolbox.removeShamanBuffWatch(id)
    if not validID(id) then return false, "法术 ID 无效" end
    local list, err = watchData(false)
    if not list then return false, err end
    for index, existing in ipairs(list) do
        if existing == id then table.remove(list, index); refresh(); return true end
    end
    return false, "未找到监控项"
end

function toolbox.attachShamanBuffMonitor(hud)
    local guid = characterKey()
    if not guid then return false end
    if monitor then return true end
    if not hud or not hud.player then return false end
    local frame = CreateFrame("Frame", nil, hud)
    frame:SetSize(286, 40)
    frame:SetPoint("BOTTOMLEFT", hud.player, "TOPLEFT", 0, 95)
    frame:EnableMouse(false)
    frame.tiles = {}
    for index = 1, MAX_WATCH do
        local tile = CreateFrame("Frame", nil, frame)
        tile:SetSize(40, 40)
        tile:SetPoint("LEFT", frame, "LEFT", (index - 1) * 46, 0)
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = tile:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(); border:SetTexture(MEDIA .. "SlotFrame.tga")
        local status = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        status:SetPoint("CENTER")
        status:SetShadowColor(0, 0, 0, 1); status:SetShadowOffset(1, -1)
        local time = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        time:SetPoint("BOTTOM", tile, "TOP", 0, 2)
        time:SetShadowColor(0, 0, 0, 1); time:SetShadowOffset(1, -1)
        tile.icon, tile.border, tile.status, tile.time = icon, border, status, time
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, tile, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints(icon); cd:EnableMouse(false)
            if type(cd.SetDrawSwipe) == "function" then cd:SetDrawSwipe(false) end
            if type(cd.SetDrawEdge) == "function" then cd:SetDrawEdge(false) end
            if type(cd.SetHideCountdownNumbers) == "function" then cd:SetHideCountdownNumbers(false) end
            cd:Hide(); tile.cooldown = cd
        end
        tile:Hide()
        frame.tiles[index] = tile
    end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED"}) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" or (event == "SPELLS_CHANGED" and generalAurasRestricted() == false) then
            learnedCache = {}
        end
        if event ~= "UNIT_AURA" or (readable(unit) and unit == "player") then refresh() end
    end)
    monitor = frame
    refresh()
    return true
end
