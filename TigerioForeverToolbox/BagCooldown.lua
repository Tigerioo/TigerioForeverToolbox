-- Passive bag cooldown monitor. It never uses an item or changes protected actions.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\SlotFrame.tga"
local SIZE, GAP, COLUMNS = 38, 4, 12
local character, bar, handle, unlocked, elapsed = nil, nil, nil, false, 0
local icons, shown, previous = {}, 0, {}
local completing = {}
local FLASH_TIME = 0.45

local function readable(v)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, v)
    return ok and not secret
end
local function finite(v)
    return readable(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end
local function tableOK(v)
    if not readable(v) or type(v) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, allowed = pcall(canaccesstable, v)
    return ok and readable(allowed) and allowed == true
end
local function get(t, key)
    if not tableOK(t) then return nil, false end
    local ok, value = pcall(function() return t[key] end)
    if ok and readable(value) then return value, true end
    return nil, false
end
local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, id = pcall(UnitGUID, "player")
    if ok and readable(id) and type(id) == "string" and id:match("^Player%-") then return id end
end
local function initialize()
    character = nil
    local db, id = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not id then return false end
    local data, ok = get(db, "bagCooldown")
    if not ok then return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.bagCooldown = data end) then return false end
    end
    local entries = get(data, "characters")
    if not tableOK(data) or get(data, "version") ~= 1 or not tableOK(entries) then return false end
    local entry, valid = get(entries, id)
    if not valid then return false end
    if entry == nil then
        entry = {}
        if not pcall(function() entries[id] = entry end) then return false end
    end
    if not tableOK(entry) then return false end
    local enabled, enabledOK = get(entry, "enabled")
    if not enabledOK or (enabled ~= nil and type(enabled) ~= "boolean") then return false end
    character = entry
    return true
end
local function current()
    local db, id = TigerioForeverToolboxDB, identity()
    local data = get(db, "bagCooldown")
    local entries = get(data, "characters")
    return character and id and tableOK(data) and get(data, "version") == 1
        and tableOK(entries) and get(entries, id) == character
end
local function enabled()
    if not current() then return nil end
    local value, ok = get(character, "enabled")
    if not ok or (value ~= nil and type(value) ~= "boolean") then return nil end
    return value ~= false
end
local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end
local function position(frame)
    local x, y = 0.5, 0.72
    local stored = get(character, "position")
    if tableOK(stored) then
        local sx, sy = get(stored, "x"), get(stored, "y")
        if finite(sx) and finite(sy) and sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1 then x, y = sx, sy end
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not finite(width) or width <= 0 or not finite(height) or height <= 0 then return false end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", width * x, -height * y)
    return true
end
local function createBar()
    if bar then return end
    bar = CreateFrame("Frame", "TigerioForeverBagCooldown", UIParent)
    bar:SetSize(SIZE, SIZE); bar:SetClampedToScreen(true)
    position(bar)
end
local function createIcon(index)
    local frame = CreateFrame("Frame", nil, bar)
    frame:SetSize(SIZE, SIZE)
    local x, y = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    frame:SetPoint("TOPLEFT", bar, "TOPLEFT", x * (SIZE + GAP), -y * (SIZE + GAP))
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 3, -3); texture:SetPoint("BOTTOMRIGHT", -3, 3)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(frame); border:SetTexture(MEDIA)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(texture); cooldown:EnableMouse(false)
    if type(cooldown.SetHideCountdownNumbers) == "function" then cooldown:SetHideCountdownNumbers(false) end
    local flash
    local ok = pcall(function()
        flash = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        flash:SetPoint("CENTER", frame, "CENTER"); flash:SetSize(SIZE * 1.4, SIZE * 1.4)
        flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        flash:SetBlendMode("ADD"); flash:Hide()
        local animation = flash:CreateAnimationGroup()
        animation:SetScript("OnPlay", function() flash:Show() end)
        animation:SetScript("OnFinished", function() flash:Hide() end)
        animation:SetScript("OnStop", function() flash:Hide() end)
        local alpha = animation:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.85); alpha:SetToAlpha(0); alpha:SetDuration(FLASH_TIME)
        local scale = animation:CreateAnimation("Scale")
        scale:SetScale(1.35, 1.35); scale:SetDuration(FLASH_TIME)
        frame.flashAnimation = animation
    end)
    if not ok and flash then pcall(flash.Hide, flash) end
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if GameTooltip and type(GameTooltip.SetBagItem) == "function" and self.bag and self.slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot); GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.texture, frame.cooldown = texture, cooldown
    icons[index] = frame
    return frame
end
local function refresh()
    if not bar or enabled() ~= true then
        if bar then bar:Hide() end
        for _, icon in ipairs(icons) do
            if icon.flashAnimation then pcall(icon.flashAnimation.Stop, icon.flashAnimation) end
            icon.flashKey = nil
        end
        previous, completing = {}, {}
        shown = 0; return
    end
    local api = C_Container
    if not api or type(api.GetContainerNumSlots) ~= "function"
        or type(api.GetContainerItemInfo) ~= "function" or type(api.GetContainerItemCooldown) ~= "function"
        or type(GetTime) ~= "function" then bar:Hide(); shown = 0; return end
    local now = GetTime()
    if not finite(now) then return end
    local maxBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    if not finite(maxBag) or maxBag < 0 or maxBag > 20 then maxBag = 4 end
    local records, seen, nextPrevious, nextCompleting = {}, {}, {}, {}
    for bag = 0, maxBag do
        local valid, slots = pcall(api.GetContainerNumSlots, bag)
        if valid and finite(slots) and slots >= 0 and slots <= 200 then
            for slot = 1, slots do
                local infoOK, info = pcall(api.GetContainerItemInfo, bag, slot)
                if infoOK and tableOK(info) then
                    local texture, itemID = get(info, "iconFileID"), get(info, "itemID")
                    local cdOK, start, duration, isEnabled = pcall(api.GetContainerItemCooldown, bag, slot)
                    local key = finite(itemID) and itemID or (bag .. ":" .. slot)
                    local known = cdOK and finite(start) and finite(duration) and readable(isEnabled)
                    local old = previous[key]
                    if not known and old and old.start + old.duration > now then
                        start, duration, isEnabled = old.start, old.duration, true
                        known = true
                    end
                    local textureOK = readable(texture) and ((type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= ""))
                    if known and start > 0 and duration > 0 and start + duration > now
                        and isEnabled ~= 0 and isEnabled ~= false and not seen[key] and textureOK then
                        seen[key] = true
                        local record = {key = key, bag = bag, slot = slot, texture = texture, start = start, duration = duration}
                        records[#records + 1] = record
                        nextPrevious[key] = record
                    elseif not seen[key] and textureOK and finite(itemID) and known then
                        -- Only a still-present item with readable cooldown data can
                        -- finish. Never infer completion from an empty bag slot.
                        local finished = completing[key]
                        if not finished and old and now >= old.start + old.duration
                            and now - (old.start + old.duration) <= 1 then
                            finished = {untilTime = now + FLASH_TIME, key = key}
                        end
                        if finished and now < finished.untilTime then
                            seen[key] = true
                            finished.bag, finished.slot, finished.texture = bag, slot, texture
                            nextCompleting[key] = finished
                            records[#records + 1] = finished
                        end
                    end
                end
            end
        end
    end
    previous, completing = nextPrevious, nextCompleting
    shown = #records
    for i, record in ipairs(records) do
        local icon = icons[i] or createIcon(i)
        if icon.flashKey ~= record.key or not record.untilTime then
            if icon.flashAnimation then pcall(icon.flashAnimation.Stop, icon.flashAnimation) end
            icon.flashKey = nil
        end
        icon.bag, icon.slot = record.bag, record.slot
        icon.texture:SetTexture(record.texture)
        icon:Show()
        if record.untilTime then
            icon.cooldown:Hide()
            if icon.flashKey ~= record.key then
                icon.flashKey = record.key
                if icon.flashAnimation then pcall(icon.flashAnimation.Play, icon.flashAnimation) end
            end
        else
            pcall(icon.cooldown.SetCooldown, icon.cooldown, record.start, record.duration)
            icon.cooldown:Show()
        end
    end
    for i = shown + 1, #icons do
        if icons[i].flashAnimation then pcall(icons[i].flashAnimation.Stop, icons[i].flashAnimation) end
        icons[i].flashKey = nil; icons[i]:Hide()
    end
    if shown > 0 then
        bar:SetSize(math.min(COLUMNS, shown) * (SIZE + GAP) - GAP, math.ceil(shown / COLUMNS) * (SIZE + GAP) - GAP)
        bar:Show()
    else bar:Hide() end
end
local function createHandle()
    if handle then return end
    handle = CreateFrame("Button", nil, UIParent)
    handle:SetSize(SIZE * 4 + GAP * 3, SIZE); handle:SetMovable(true); handle:SetClampedToScreen(true)
    handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
    local background = handle:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.12, 0.08, 0.04, 0.9)
    local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText("拖动冷却栏")
    handle:SetScript("OnDragStart", function(self) if unlocked and not inCombat() then self:StartMoving() end end)
    handle:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not unlocked or inCombat() or not current() then return end
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local left, top, uiLeft, uiTop = self:GetLeft(), self:GetTop(), UIParent:GetLeft(), UIParent:GetTop()
        if not finite(width) or width <= 0 or not finite(height) or height <= 0
            or not finite(left) or not finite(top) or not finite(uiLeft) or not finite(uiTop) then return end
        local x, y = (left - uiLeft) / width, (uiTop - top) / height
        if x < 0 or x > 1 or y < 0 or y > 1 then return end
        if pcall(function() character.position = {x = x, y = y} end) then position(bar) end
    end)
    handle:Hide()
end
function toolbox.getBagCooldownEnabled() return enabled() end
function toolbox.setBagCooldownEnabled(value)
    if type(value) ~= "boolean" or not current() then return false, "冷却栏设置不可用" end
    if not pcall(function() character.enabled = value end) then return false, "设置无法保存" end
    if not value and unlocked then unlocked = false; if handle then handle:Hide() end end
    refresh(); notify(); return true
end
function toolbox.getBagCooldownUnlocked() return unlocked end
function toolbox.setBagCooldownUnlocked(value)
    if type(value) ~= "boolean" or not current() then return false, "冷却栏设置不可用" end
    if value and inCombat() then return false, "请在脱战后调整" end
    if value and enabled() ~= true then return false, "请先启用物品冷却栏" end
    createBar(); createHandle()
    unlocked = value
    if value then position(handle); handle:Show() else handle:StopMovingOrSizing(); handle:Hide() end
    notify(); return true
end
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then initialize(); if current() then createBar() end; notify() end
    if not current() then return end
    if event == "PLAYER_REGEN_DISABLED" and unlocked then
        unlocked = false
        if handle then handle:StopMovingOrSizing(); handle:Hide() end
        notify()
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if bar then position(bar) end
        if handle and unlocked then position(handle) end
    end
    refresh()
end)
driver:SetScript("OnUpdate", function(_, dt)
    if shown == 0 then return end
    elapsed = elapsed + dt
    local interval = next(completing) and 0.05 or 0.35
    if elapsed >= interval then elapsed = 0; refresh() end
end)
