-- Independent, per-character HUD. Secure buttons are only configured out of combat.
local ADDON, toolbox = ...
local driver = CreateFrame("Frame")
local hud, character, dataError, unlocked, pendingInit, dragging, pendingDragStop
local nativeHider, nativeOwned, nativeUncertain, nativeFrameNotice = nil, {}, {}, nil
local nativeDisowned, nativeSyncPending = {}, false
local nativeCastOwned, nativeCastDisowned, nativeCastWaiting = nil, nil, nil
local nativeCastOverlayHooked = false
local hudKeyHooks, heldHUDKeys, hudKeyMapDirty = {}, {}, true
local SLOT_COUNT = 16
-- Five top buttons span the same 286-unit panel as their health bar.
local TOP_SKILL_GAP = 3
local TOP_SKILL_SIZE = (286 - 4 * TOP_SKILL_GAP) / 5
local TOP_SKILL_STEP = TOP_SKILL_SIZE + TOP_SKILL_GAP
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    -- The client may return nil outside lockdown; truthy means locked.
    return not not value
end

local function notify()
    if type(toolbox.hudChanged) == "function" then pcall(toolbox.hudChanged) end
end

local function getIdentity()
    local guid = call(UnitGUID, "player")
    if readable(guid) and type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function validSlot(value)
    if not readable(value) then return false end
    return value == nil or (finite(value) and value > 0 and value == math.floor(value))
end

local function initData()
    character, dataError = nil, nil
    local db, guid = TigerioForeverToolboxDB, getIdentity()
    if type(db) ~= "table" or not guid then dataError = "角色数据暂不可用"; return end
    if db.hud == nil then db.hud = {version = 1, characters = {}} end
    if type(db.hud) ~= "table" or db.hud.version ~= 1 or type(db.hud.characters) ~= "table" then
        dataError = "HUD 数据版本不兼容"; return
    end
    local entry = db.hud.characters[guid]
    if entry == nil then
        entry = {enabled = false, slots = {}}
        db.hud.characters[guid] = entry
    end
    if type(entry) ~= "table" or type(entry.enabled) ~= "boolean" or type(entry.slots) ~= "table" then
        dataError = "HUD 数据不可用"; return
    end
    for i = 1, SLOT_COUNT do
        if not validSlot(entry.slots[i]) then dataError = "HUD 技能数据不可用"; return end
    end
    if (entry.x ~= nil and not finite(entry.x)) or (entry.y ~= nil and not finite(entry.y)) then
        dataError = "HUD 位置数据不可用"; return
    end
    character = entry
end

local function currentData()
    if not character then return nil, dataError or "角色数据暂不可用" end
    local db, guid = TigerioForeverToolboxDB, getIdentity()
    if type(db) ~= "table" or type(db.hud) ~= "table" or type(db.hud.characters) ~= "table"
        or not guid or db.hud.characters[guid] ~= character then return nil, "角色数据暂不可用" end
    return character
end

local function nativeCastParent(frame)
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok or not readable(parent) or not parent then return false end
    if parent == UIParent or parent == _G.PlayerFrame then return true end
    for _, name in ipairs({"BottomManagedFrameContainer", "PlayerBottomManagedFrameContainer"}) do
        local container = _G[name]
        if container then
            if parent == container then return true end
            local childOK, child = pcall(function() return container.BottomManagedLayoutContainer end)
            if childOK and readable(child) and child and parent == child then return true end
        end
    end
    return false
end

-- Use the same switch Blizzard uses for its own cast-bar replacement; it
-- preserves registered events and survives the managed container reparenting.
local function updateNativeCast(replace)
    if combat() then nativeSyncPending = true; return false end
    if not replace then
        local frame = nativeCastOwned
        if frame then
            local ok, current = pcall(function() return frame.showCastbar end)
            if not ok or not readable(current) then nativeSyncPending = true; return false end
            local overlay = _G.OverlayPlayerCastingBarFrame
            local overlayOK, overlayActive = pcall(function() return overlay and overlay.showCastbar end)
            if not overlayOK or not readable(overlayActive) then nativeSyncPending = true; return false end
            -- During Blizzard's temporary overlay the overlay itself restores
            -- the player bar when it ends; do not turn it on prematurely.
            if current == false and not overlayActive then
                if not nativeCastParent(frame) then
                    nativeCastOwned, nativeCastDisowned, nativeCastWaiting = nil, nil, nil
                    return true
                end
                local restored = pcall(frame.SetAndUpdateShowCastbar, frame, true)
                if not restored then nativeSyncPending = true; return false end
            end
        end
        nativeCastOwned, nativeCastDisowned, nativeCastWaiting = nil, nil, nil
        return true
    end
    local frame = _G.PlayerCastingBarFrame
    if not frame or not hud or not hud.tftCast then return true end
    local ok, forbidden, current = pcall(function()
        return type(frame.IsForbidden) == "function" and frame:IsForbidden(), frame.showCastbar
    end)
    if not ok or not readable(forbidden) or forbidden or not readable(current)
        or type(current) ~= "boolean" or type(frame.SetAndUpdateShowCastbar) ~= "function" then
        nativeSyncPending = true
        return false
    end
    if not nativeCastParent(frame) then
        if nativeCastOwned == frame then nativeCastOwned, nativeCastDisowned = nil, frame end
        nativeSyncPending = true
        return false
    end
    if nativeCastOwned == frame then
        -- If another owner turns it back on, do not take control again.
        if current then nativeCastOwned, nativeCastDisowned = nil, frame; return false end
        return true
    end
    if nativeCastDisowned == frame then return false end
    local overlay = _G.OverlayPlayerCastingBarFrame
    local overlayOK, overlayActive = pcall(function() return overlay and overlay.showCastbar end)
    if not overlayOK or not readable(overlayActive) then nativeSyncPending = true; return false end
    if not current then
        if overlayActive then nativeCastWaiting = frame end
        return true
    end
    if not pcall(frame.SetAndUpdateShowCastbar, frame, false) then
        nativeSyncPending = true
        return false
    end
    local verified, actual = pcall(function() return frame.showCastbar end)
    if verified and readable(actual) and actual == false then
        nativeCastOwned, nativeCastWaiting = frame, nil
        return true
    end
    nativeSyncPending = true
    return false
end

local function hookNativeCastOverlay()
    local overlay = _G.OverlayPlayerCastingBarFrame
    if nativeCastOverlayHooked or not overlay or type(hooksecurefunc) ~= "function"
        or type(overlay.EndReplacingPlayerBar) ~= "function" then return end
    local ok = pcall(hooksecurefunc, overlay, "EndReplacingPlayerBar", function()
        if not character or not character.enabled or not hud or not hud:IsShown() or not hud.tftCast then return end
        local frame = _G.PlayerCastingBarFrame
        if frame ~= nativeCastOwned and frame ~= nativeCastWaiting then return end
        if combat() then nativeCastOwned, nativeCastWaiting = nil, frame; nativeSyncPending = true; return end
        local currentOK, current = pcall(function() return frame.showCastbar end)
        if currentOK and readable(current) and current == true and nativeCastParent(frame) then
            if pcall(frame.SetAndUpdateShowCastbar, frame, false) then
                nativeCastOwned, nativeCastWaiting = frame, nil
            else nativeSyncPending = true end
        end
    end)
    nativeCastOverlayHooked = ok
end

-- Keep Blizzard's target/unit watches intact: changing their parent hides them
-- without changing their own shown state, drivers, or other addon settings.
local function updateNativeFrames(replace, keepCast)
    if combat() then nativeSyncPending = true; return false end
    if replace and hud and not hud.tftReplacementReady then
        local restored = updateNativeFrames(false, true)
        if restored then nativeFrameNotice = "HUD 信息不可用，已保留系统头像框" end
        return false
    end
    nativeSyncPending = false
    hookNativeCastOverlay()
    local castOK = updateNativeCast(replace or keepCast)
    if not replace then
        local failed = not castOK
        for _, frames in ipairs({nativeOwned, nativeUncertain}) do
            for frame, original in pairs(frames) do
                local ok, parent = pcall(frame.GetParent, frame)
                if not ok or not readable(parent) then
                    failed = true
                elseif parent == nativeHider then
                    local restored = pcall(frame.SetParent, frame, original)
                    local verified, actual = pcall(frame.GetParent, frame)
                    if restored and verified and readable(actual) and actual == original then frames[frame] = nil else failed = true end
                else
                    -- Another owner changed the frame; leave its parent untouched.
                    frames[frame] = nil
                end
            end
        end
        if not failed then nativeDisowned = {} else nativeSyncPending = true end
        nativeFrameNotice = failed and (castOK and "系统头像框恢复失败" or "系统施法条恢复失败") or nil
        return not failed
    end
    if not nativeHider then
        local ok, holder = pcall(CreateFrame, "Frame", nil, UIParent)
        if not ok or not holder then nativeSyncPending = true; nativeFrameNotice = "系统头像框未能全部隐藏"; return false end
        local hidden = pcall(holder.Hide, holder)
        if not hidden then nativeSyncPending = true; nativeFrameNotice = "系统头像框未能全部隐藏"; return false end
        nativeHider = holder
    end
    local complete = castOK
    local nativeFrames = {
        {name = "PlayerFrame", parent = UIParent},
        {name = "TargetFrame", parent = UIParent},
    }
    local _, class = call(UnitClass, "player")
    if readable(class) and class == "SHAMAN" then
        -- This is the native totem timer, not the secure MultiCast action bar.
        nativeFrames[#nativeFrames + 1] = {name = "TotemFrame", parent = _G.PlayerFrame, optional = true}
    end
    for _, definition in ipairs(nativeFrames) do
        local frame = _G[definition.name]
        if frame then
            local ok, parent, forbidden = pcall(function()
                return frame:GetParent(), type(frame.IsForbidden) == "function" and frame:IsForbidden()
            end)
            if not ok or not readable(parent) or not readable(forbidden) or forbidden then
                complete = false
            elseif nativeUncertain[frame] then
                if parent == nativeHider then nativeOwned[frame] = nativeUncertain[frame]
                else nativeDisowned[frame] = true; complete = false end
                nativeUncertain[frame] = nil
            elseif nativeOwned[frame] then
                if parent ~= nativeHider then
                    nativeOwned[frame] = nil
                    nativeDisowned[frame] = true
                    complete = false
                end
            elseif not nativeDisowned[frame] and definition.parent and parent == definition.parent then
                local changed = pcall(frame.SetParent, frame, nativeHider)
                local verified, actual = pcall(frame.GetParent, frame)
                if changed and verified and readable(actual) and actual == nativeHider then
                    nativeOwned[frame] = parent
                elseif changed and (not verified or not readable(actual)) then
                    -- Do not claim ownership until the new parent can be verified.
                    nativeUncertain[frame], complete = parent, false
                else
                    complete = false
                end
            else
                -- A third party controls this frame; do not change its parent.
                complete = false
            end
        elseif not definition.optional then
            complete = false
        end
    end
    nativeSyncPending = not complete
    nativeFrameNotice = not complete and (castOK and "系统头像框未能全部隐藏" or "系统施法条未能隐藏") or nil
    return complete
end

function toolbox.getHUDConfig()
    local config, err = currentData()
    if not config then return nil, err end
    local copy = {enabled = config.enabled, unlocked = not not unlocked, nativeFrameNotice = nativeFrameNotice, slots = {}}
    for i = 1, SLOT_COUNT do copy.slots[i] = config.slots[i] end
    return copy
end

local function font(parent, template)
    local value = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    value:SetJustifyH("CENTER")
    return value
end

local function background(parent, r, g, b, a)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function healthBar(parent, unit, x)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(286, 48)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -64)
    panel:EnableMouse(false)
    local back = panel:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetTexture(MEDIA .. "BarPanel.tga")
    local bar = CreateFrame("StatusBar", nil, panel)
    bar:SetSize(276, 40)
    bar:SetPoint(unit == "player" and "RIGHT" or "LEFT", panel, unit == "player" and "RIGHT" or "LEFT", unit == "player" and -5 or 5, 0)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(MEDIA .. "BarFill.tga")
    bar:SetStatusBarColor(1, 1, 1, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    -- The client can render protected healing values inside a StatusBar.
    -- Attach the prediction to the end of the real fill instead of calculating
    -- pixel widths from health values in Lua.
    local textLayer = bar
    if type(CreateUnitHealPredictionCalculator) == "function"
        and type(UnitGetDetailedHealPrediction) == "function"
        and Enum and Enum.UnitIncomingHealClampMode
        and type(Enum.UnitIncomingHealClampMode.MissingHealth) == "number" then
        local prediction, layer
        local ok = pcall(function()
            local calculator = CreateUnitHealPredictionCalculator()
            calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
            calculator:SetIncomingHealOverflowPercent(1)
            local filled = bar:GetStatusBarTexture()
            if not filled then error("health texture unavailable") end
            prediction = CreateFrame("StatusBar", nil, bar)
            prediction:EnableMouse(false)
            prediction:SetPoint("TOPLEFT", filled, "TOPRIGHT")
            prediction:SetPoint("BOTTOMLEFT", filled, "BOTTOMRIGHT")
            prediction:SetWidth(276)
            prediction:SetStatusBarTexture(MEDIA .. "BarFill.tga")
            prediction:SetStatusBarColor(0.35, 1, 0.55, 0.65)
            prediction:SetMinMaxValues(0, 1)
            prediction:SetValue(0)
            layer = CreateFrame("Frame", nil, bar)
            layer:EnableMouse(false)
            layer:SetAllPoints(bar)
            layer:SetFrameLevel(prediction:GetFrameLevel() + 1)
            bar.healPrediction, bar.healCalculator = prediction, calculator
        end)
        if ok then textLayer = layer
        elseif prediction then pcall(prediction.Hide, prediction) end
    end
    local caption = font(textLayer, "GameFontHighlightSmall")
    caption:SetPoint(unit == "player" and "LEFT" or "RIGHT", bar, unit == "player" and "LEFT" or "RIGHT", unit == "player" and 8 or -8, 0)
    caption:SetWidth(96)
    caption:SetJustifyH(unit == "player" and "LEFT" or "RIGHT")
    if type(caption.SetWordWrap) == "function" then caption:SetWordWrap(false) end
    if type(caption.SetMaxLines) == "function" then caption:SetMaxLines(1) end
    caption:SetText(unit == "target" and "" or "—")
    caption:SetShadowColor(0, 0, 0, 1)
    caption:SetShadowOffset(1, -1)
    bar.nameLabel = caption
    bar.text = font(textLayer)
    bar.text:SetPoint(unit == "player" and "RIGHT" or "LEFT", bar,
        unit == "player" and "RIGHT" or "LEFT", unit == "player" and -10 or 10, 0)
    bar.text:SetText(unit == "target" and "" or "—")
    local level = font(textLayer, "GameFontNormalSmall")
    level:SetPoint(unit == "player" and "TOPLEFT" or "TOPRIGHT", bar,
        unit == "player" and "TOPLEFT" or "TOPRIGHT", unit == "player" and 5 or -5, -1)
    level:SetText("")
    level:SetShadowColor(0, 0, 0, 1)
    level:SetShadowOffset(1, -1)
    bar.levelLabel = level
    if bar.healPrediction then
        local amount = font(textLayer, "GameFontHighlightSmall")
        amount:SetPoint("CENTER", bar, "CENTER", 0, 0)
        amount:SetWidth(80)
        amount:SetTextColor(0.72, 1, 0.75, 1)
        amount:SetShadowColor(0, 0, 0, 1)
        amount:SetShadowOffset(1, -1)
        amount:SetText("")
        bar.healAmount = amount
    end
    -- Keep targeting and the native unit menu in the secure click handler.
    local button = CreateFrame("Button", nil, panel, "SecureUnitButtonTemplate")
    button:SetAllPoints(panel)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:SetAttribute("unit", unit)
    -- Do not intercept clicks over the empty target panel.
    if unit == "target" then RegisterUnitWatch(button) end
    bar.clickButton = button
    return bar
end

local function resource(parent, x)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(110, 110)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -33)
    holder:EnableMouse(false)
    local empty = holder:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints()
    empty:SetTexture(MEDIA .. "OrbFill.tga")
    empty:SetVertexColor(0.18, 0.18, 0.18, 0.85)
    local fill = CreateFrame("StatusBar", nil, holder)
    fill:SetAllPoints(holder)
    fill:EnableMouse(false)
    fill:SetOrientation("VERTICAL")
    if type(fill.SetRotatesTexture) == "function" then fill:SetRotatesTexture(false) end
    fill:SetStatusBarTexture(MEDIA .. "OrbFill.tga")
    fill:SetStatusBarColor(1, 1, 1, 1)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    holder.fill = fill
    -- Keep the circular boundary fixed while the status bar changes height.
    local texture = fill:GetStatusBarTexture()
    if texture and type(holder.CreateMaskTexture) == "function" and type(texture.AddMaskTexture) == "function" then
        local mask = holder:CreateMaskTexture()
        mask:SetAllPoints(holder)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
        holder.mask = mask
    end
    -- Child frames draw above their parent's layers, so keep text/rim on a later child.
    local overlay = CreateFrame("Frame", nil, holder)
    overlay:SetAllPoints(holder)
    overlay:EnableMouse(false)
    if type(overlay.SetFrameLevel) == "function" and type(fill.GetFrameLevel) == "function" then
        overlay:SetFrameLevel(fill:GetFrameLevel() + 1)
    end
    local rim = overlay:CreateTexture(nil, "OVERLAY")
    rim:SetAllPoints()
    rim:SetTexture(MEDIA .. "OrbRing.tga")
    holder.value = font(overlay, "GameFontHighlight")
    if type(holder.value.GetFont) == "function" and type(holder.value.SetFont) == "function" then
        local path, size, flags = holder.value:GetFont()
        if readable(path) and type(path) == "string" and finite(size) then
            pcall(holder.value.SetFont, holder.value, path, (size + 4) * 1.5, flags)
        end
    end
    holder.value:SetPoint("CENTER")
    holder.value:SetText("—")
    return holder
end

-- Totem positions follow the character-facing Classic layout: fire/earth in
-- front and air/water behind. Unreadable client values are never guessed.
local TOTEM_POSITIONS = {
    {slot = 1, x = -58, y = 58, text = "火", color = {1, 0.45, 0.20}}, -- fire: front left
    {slot = 2, x = 58, y = 58, text = "土", color = {0.75, 0.66, 0.48}}, -- earth: front right
    {slot = 4, x = -58, y = -58, text = "风", color = {0.65, 0.75, 0.80}}, -- air: back left
    {slot = 3, x = 58, y = -58, text = "水", color = {0.32, 0.65, 1}}, -- water: back right
}

local function createTotemMonitor(ball)
    local slots = {}
    for index, position in ipairs(TOTEM_POSITIONS) do
        local tile = CreateFrame("Frame", nil, ball)
        tile:SetSize(56, 56)
        tile:SetPoint("CENTER", ball, "CENTER", position.x, position.y)
        tile:EnableMouse(false)
        if type(tile.SetFrameLevel) == "function" and type(ball.fill.GetFrameLevel) == "function" then
            tile:SetFrameLevel(ball.fill:GetFrameLevel() + 3)
        end
        local empty = tile:CreateTexture(nil, "BACKGROUND")
        empty:SetAllPoints()
        empty:SetTexture(MEDIA .. "OrbFill.tga")
        empty:SetVertexColor(0.16, 0.16, 0.16, 1)
        local glyph = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
        glyph:SetAllPoints()
        glyph:SetTexture(MEDIA .. "TotemGlyphs.tga")
        -- Half-pixel inset prevents adjacent elements bleeding into the slot.
        glyph:SetTexCoord((index - 1) / 4 + 0.5 / 256, index / 4 - 0.5 / 256, 0, 1)
        glyph:Hide()
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        -- Never expose square icon corners if the client's mask API is absent.
        local masked = false
        if type(tile.CreateMaskTexture) == "function" and type(icon.AddMaskTexture) == "function" then
            masked = pcall(function()
                local mask = tile:CreateMaskTexture()
                mask:SetAllPoints(icon)
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                icon:AddMaskTexture(mask)
                tile.mask = mask
            end)
        end
        icon:Hide()
        local rim = tile:CreateTexture(nil, "OVERLAY")
        rim:SetAllPoints(); rim:SetTexture(MEDIA .. "OrbRing.tga")
        local placeholder = font(tile, "GameFontNormalLarge")
        placeholder:SetPoint("CENTER")
        placeholder:SetText(position.text)
        placeholder:SetTextColor(0.72, 0.72, 0.72, 1)
        placeholder:SetShadowColor(0, 0, 0, 1)
        placeholder:SetShadowOffset(1, -1)
        local timer = font(tile, "GameFontHighlightSmall")
        timer:SetSize(40, 10)
        timer:SetPoint(position.y > 0 and "BOTTOM" or "TOP", tile,
            position.y > 0 and "TOP" or "BOTTOM", 0, position.y > 0 and -1 or 1)
        timer:SetTextColor(1, 0.85, 0.62, 1)
        timer:SetShadowColor(0, 0, 0, 1)
        timer:SetShadowOffset(1, -1)
        timer:SetText("")
        tile:Hide()
        slots[#slots + 1] = {index = position.slot, frame = tile, glyph = glyph, icon = icon, placeholder = placeholder,
            rim = rim, timer = timer, masked = masked, color = position.color}
    end
    return slots
end

-- Keep the secure hover targets separate from the visual totem tiles: those
-- tiles are refreshed in combat and must not acquire protected children.
local function createTotemFlyouts(ball)
    if type(GetMultiCastTotemSpells) ~= "function" then return nil end
    local flyouts = {}
    for _, position in ipairs(TOTEM_POSITIONS) do
        local handle = CreateFrame("Frame", nil, ball, "SecureHandlerEnterLeaveTemplate")
        handle:SetSize(56, 56)
        handle:SetPoint("CENTER", ball, "CENTER", position.x, position.y)
        -- The handles remain inert until all optional secure setup succeeds.
        handle:EnableMouse(false)
        handle:SetFrameLevel(ball.fill:GetFrameLevel() + 5)
        local popup = CreateFrame("Frame", nil, ball, "SecureHandlerBaseTemplate")
        popup:SetFrameLevel(handle:GetFrameLevel() + 1)
        popup:EnableMouse(true)
        popup:Hide()
        handle:SetFrameRef("totemFlyout", popup)
        handle:SetAttribute("_onenter", [[
            if self:GetAttribute("hasSpells") then
                local popup = self:GetFrameRef("totemFlyout")
                if popup then
                    popup:Show()
                    popup:RegisterAutoHide(0.35)
                    popup:AddToAutoHide(self)
                end
            end
        ]])
        flyouts[#flyouts + 1] = {slot = position.slot, upward = position.y > 0,
            handle = handle, popup = popup, buttons = {}}
    end
    return flyouts
end

local function packValues(...) return {n = select("#", ...), ...} end

local function refreshTotemFlyouts(frame)
    if not frame or not frame.totemFlyouts or combat() then return end
    local topFlyoutHeight = 0
    for _, flyout in ipairs(frame.totemFlyouts) do
        local result = packValues(pcall(GetMultiCastTotemSpells, flyout.slot))
        -- A secret or otherwise invalid value does not prove the element has
        -- no spells; keep the last secure configuration until it is readable.
        local known, spells = result[1], {}
        if known then
            for i = 2, result.n do
                local id = result[i]
                if finite(id) and id > 0 and id == math.floor(id) then
                    spells[#spells + 1] = id
                else
                    known = false
                    break
                end
            end
        end
        if known then
            flyout.popup:Hide()
            local size, gap, columns = 36, 2, math.min(2, math.max(1, #spells))
            local rows = math.max(1, math.ceil(#spells / columns))
            flyout.height = #spells > 0 and (rows * size + (rows - 1) * gap) or 0
            flyout.popup:SetSize(columns * size + (columns - 1) * gap, rows * size + (rows - 1) * gap)
            flyout.popup:ClearAllPoints()
            flyout.popup:SetPoint(flyout.upward and "BOTTOM" or "TOP", flyout.handle,
                flyout.upward and "TOP" or "BOTTOM", 0, 0)
            for i, id in ipairs(spells) do
                local button = flyout.buttons[i]
                if not button then
                    button = CreateFrame("Button", nil, flyout.popup, "SecureActionButtonTemplate")
                    button:SetSize(size, size)
                    button:RegisterForClicks("AnyUp", "AnyDown")
                    local background = button:CreateTexture(nil, "BACKGROUND")
                    background:SetAllPoints(); background:SetTexture(MEDIA .. "SlotEmpty.tga")
                    local icon = button:CreateTexture(nil, "ARTWORK")
                    icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
                    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
                    local rim = button:CreateTexture(nil, "OVERLAY")
                    rim:SetAllPoints(); rim:SetTexture(MEDIA .. "SlotFrame.tga")
                    local pushed = button:CreateTexture(nil, "ARTWORK", nil, 6)
                    pushed:SetAllPoints(icon); pushed:SetColorTexture(0, 0, 0, 0.42)
                    button:SetPushedTexture(pushed)
                    button.icon = icon
                    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                    cooldown:SetAllPoints(icon)
                    cooldown:SetDrawEdge(false)
                    cooldown:SetHideCountdownNumbers(false)
                    cooldown:EnableMouse(false)
                    button.cooldown = cooldown
                    button:SetScript("OnEnter", function(self)
                        if GameTooltip and self.spellID then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetSpellByID(self.spellID)
                            GameTooltip:Show()
                        end
                    end)
                    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                    flyout.buttons[i] = button
                end
                local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
                button:ClearAllPoints()
                button:SetPoint(flyout.upward and "BOTTOMLEFT" or "TOPLEFT", flyout.popup,
                    flyout.upward and "BOTTOMLEFT" or "TOPLEFT", col * (size + gap),
                    (flyout.upward and 1 or -1) * row * (size + gap))
                local texture = C_Spell and call(C_Spell.GetSpellTexture, id) or call(GetSpellTexture, id)
                if readable(texture) then button.icon:SetTexture(texture) end
                button.spellID = id
                button:SetAttribute("type1", "spell")
                button:SetAttribute("spell1", id)
                button:Show()
            end
            for i = #spells + 1, #flyout.buttons do
                local button = flyout.buttons[i]
                button:SetAttribute("type1", nil); button:SetAttribute("spell1", nil)
                button.spellID = nil; button:Hide()
            end
            flyout.handle:SetAttribute("hasSpells", #spells > 0)
        end
        if flyout.upward then topFlyoutHeight = math.max(topFlyoutHeight, flyout.height or 0) end
    end
    if frame.imbueWarning then
        -- Leave room above both top flyouts for the weapon imbue warning.
        frame.imbueWarning:ClearAllPoints()
        frame.imbueWarning:SetPoint("BOTTOM", frame, "TOP", 0, math.max(30, topFlyoutHeight + 4))
        if type(frame.SetClampRectInsets) == "function" then
            pcall(frame.SetClampRectInsets, frame, -15, 15, math.max(50, topFlyoutHeight + 26), -32)
        end
    end
end

local function safeRefreshTotemFlyouts(frame)
    if not frame or not frame.totemFlyouts or combat() then return end
    local ok = pcall(refreshTotemFlyouts, frame)
    for _, flyout in ipairs(frame.totemFlyouts) do
        pcall(flyout.handle.EnableMouse, flyout.handle, ok)
        if not ok then pcall(flyout.popup.Hide, flyout.popup) end
    end
end

local function updateTotemTimers(frame)
    if not frame or not frame.totems then return end
    local now = call(GetTime)
    for _, slot in ipairs(frame.totems) do
        if slot.finish and finite(now) then
            local remaining = math.max(0, slot.finish - now)
            local value
            if remaining >= 3600 then value = math.ceil(remaining / 3600) .. "h"
            elseif remaining >= 60 then value = math.ceil(remaining / 60) .. "m"
            else value = math.ceil(remaining) .. "s" end
            slot.timer:SetText(value)
        else
            slot.timer:SetText("")
        end
    end
end

-- The client can render secret totem state without revealing it to Lua.
-- Never branch on that state; both values go straight to supported widgets.
local function renderRestrictedTotem(slot, exists, icon, iconPlaceholder)
    local empty = iconPlaceholder and slot.glyph or slot.placeholder
    local other = iconPlaceholder and slot.placeholder or slot.glyph
    if not slot.masked or type(slot.icon.SetAlphaFromBoolean) ~= "function"
        or type(empty.SetAlphaFromBoolean) ~= "function" then return false end
    if readable(exists) and type(exists) ~= "boolean" then return false end
    if readable(icon) and type(icon) ~= "number" and type(icon) ~= "string" then return false end
    local ok, applied = pcall(slot.icon.SetTexture, slot.icon, icon)
    if not ok or (readable(applied) and applied == false) then return false end
    local iconOK = pcall(slot.icon.SetAlphaFromBoolean, slot.icon, exists, 1, 0)
    local labelOK = pcall(empty.SetAlphaFromBoolean, empty, exists, 0, 1)
    if not iconOK or not labelOK then return false end
    slot.finish = nil
    other:Hide()
    if iconPlaceholder then slot.glyph:SetVertexColor(1, 1, 1, 1) end
    slot.icon:Show()
    empty:Show()
    slot.rim:SetVertexColor(1, 1, 1, 1)
    slot.frame:Show()
    return true
end

local function updateTotems(frame)
    if not frame or not frame.totems then return end
    local _, class = call(UnitClass, "player")
    local isShaman = readable(class) and class == "SHAMAN"
    local available = isShaman and type(GetTotemInfo) == "function"
    local iconPlaceholder = character and character.totemPlaceholderStyle == "icon"
    for _, slot in ipairs(frame.totems) do
        local ok, exists, _, start, duration, icon
        if available then ok, exists, _, start, duration, icon = pcall(GetTotemInfo, slot.index) end
        local restricted = ok and (not readable(exists) or not readable(icon))
        if restricted and renderRestrictedTotem(slot, exists, icon, iconPlaceholder) then
            -- Visibility is controlled by the client, not by Lua.
        elseif ok and readable(exists) and exists == true and readable(icon)
            and (type(icon) == "number" or type(icon) == "string") then
            slot.icon:SetAlpha(1); slot.placeholder:SetAlpha(1); slot.glyph:SetAlpha(1)
            if slot.masked then
                slot.icon:SetTexture(icon)
                slot.icon:Show()
                slot.glyph:Hide()
            else
                slot.icon:Hide()
                slot.glyph:SetVertexColor(slot.color[1], slot.color[2], slot.color[3], 1)
                slot.glyph:Show()
            end
            slot.placeholder:Hide()
            slot.rim:SetVertexColor(1, 1, 1, 1)
            if finite(start) and finite(duration) and duration > 0 then
                local finish = start + duration
                slot.finish = finite(finish) and finish or nil
            else
                slot.finish = nil
            end
            slot.frame:Show()
        else
            slot.icon:SetAlpha(1); slot.placeholder:SetAlpha(1); slot.glyph:SetAlpha(1)
            slot.finish = nil
            slot.icon:Hide()
            if isShaman then
                if iconPlaceholder then
                    slot.glyph:SetVertexColor(1, 1, 1, 1)
                    slot.glyph:Show(); slot.placeholder:Hide()
                else
                    slot.glyph:Hide(); slot.placeholder:Show()
                end
                slot.rim:SetVertexColor(0.8, 0.8, 0.8, 1)
                slot.frame:Show()
            else
                slot.glyph:Hide(); slot.placeholder:Hide()
                slot.frame:Hide()
            end
        end
    end
    updateTotemTimers(frame)
end

-- Totem state may arrive after the event or spell success. Re-read only the
-- client's confirmed state, for a short window; never predict a totem icon.
local totemRetry, totemRetryTimes = nil, {0.05, 0.15, 0.35, 0.75, 1.5, 2.5}
local function scheduleTotemRefresh(frame)
    if not frame or not frame.totems or not frame:IsShown() then return end
    local _, class = call(UnitClass, "player")
    if not readable(class) or class ~= "SHAMAN" then return end
    updateTotems(frame)
    totemRetry = {frame = frame, elapsed = 0, next = 1}
end

local function advanceTotemRefresh(frame, elapsed)
    local retry = totemRetry
    if not retry then return end
    if retry.frame ~= frame or not frame:IsShown() then totemRetry = nil; return end
    retry.elapsed = retry.elapsed + elapsed
    if retry.elapsed < totemRetryTimes[retry.next] then return end
    updateTotems(frame)
    repeat retry.next = retry.next + 1
    until not totemRetryTimes[retry.next] or retry.elapsed < totemRetryTimes[retry.next]
    if not totemRetryTimes[retry.next] then totemRetry = nil end
end

local function isKnownTotemSpell(frame, spellID)
    if not frame or not frame.totemFlyouts or not finite(spellID) then return false end
    for _, flyout in ipairs(frame.totemFlyouts) do
        for _, button in ipairs(flyout.buttons) do
            if finite(button.spellID) and button.spellID == spellID then return true end
        end
    end
    return false
end

-- Forever keeps a shaman's imbue separately from other temporary enchants.
-- Treat missing, restricted or uncached client data as unknown, not missing.
local IMBUE_SPELLS = {
    8017, 8018, 8019, 10399, 16314, 16315, 16316, -- Rockbiter
    8024, 8027, 8030, 16339, 16341, 16342, -- Flametongue
    8033, 8038, 10456, 16355, 16356, -- Frostbrand
    8232, 8235, 10486, 16362, -- Windfury
}

local function imbueKnown()
    local lookup = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell or IsSpellKnown
    if type(lookup) ~= "function" then return false end
    for _, spellID in ipairs(IMBUE_SPELLS) do
        local ok, known = pcall(lookup, spellID)
        if ok and readable(known) and known == true then return true end
    end
    return false
end

local function equippedImbueWeapon(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if not ok or not readable(id) then return nil end
    if id == nil then return false end
    if type(id) ~= "number" or id <= 0 then return nil end
    local lookup = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(lookup) ~= "function" then return nil end
    local got, _, _, _, equipLoc, _, classID, subClassID = pcall(lookup, id)
    if not got or not readable(equipLoc) or not readable(classID) or not readable(subClassID)
        or type(equipLoc) ~= "string" or type(classID) ~= "number" or type(subClassID) ~= "number" then return nil end
    if classID ~= 2 or subClassID == 20 then return false end -- shields, held items and fishing poles
    if slot == 16 then
        return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON"
    end
    return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
end

local function hasShamanImbue(slot)
    local weaponSlots = Enum and Enum.WeaponSlot
    local enchantTypes = Enum and Enum.ItemEnchantType
    local slotKey = type(weaponSlots) == "table" and (slot == 16 and weaponSlots.MainHand or weaponSlots.OffHand)
    local imbueType = type(enchantTypes) == "table" and enchantTypes.Imbue
    local lookup = C_Item and C_Item.GetWeaponEnchantInfo
    if type(lookup) == "function" and type(slotKey) == "number" and type(imbueType) == "number" then
        local ok, list = pcall(lookup, slotKey)
        if not ok or not readable(list) or type(list) ~= "table" then return nil end
        if type(canaccesstable) == "function" then
            local checked, accessible = pcall(canaccesstable, list)
            if not checked or not readable(accessible) or accessible ~= true then return nil end
        end
        local scanned, result = pcall(function()
            local unknown = false
            for _, enchant in ipairs(list) do
                if not readable(enchant) or type(enchant) ~= "table" then
                    unknown = true
                else
                    local kind, active = enchant.enchantType, enchant.hasEnchant
                    if not readable(kind) or not readable(active) or type(kind) ~= "number" or type(active) ~= "boolean" then
                        unknown = true
                    elseif kind == imbueType and active then
                        return true
                    end
                end
            end
            if unknown then return nil end
            return false
        end)
        if scanned then return result end
        return nil
    end
    -- Older clients expose only an aggregate flag. A false flag proves there
    -- is no imbue; a true flag may be another temporary weapon effect.
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, main, _, _, _, off = pcall(GetWeaponEnchantInfo)
    local active
    if slot == 16 then active = main else active = off end
    if not ok or not readable(active) then return nil end
    if active == nil or active == false then return false end
    if active == true or active == 1 then return true end
    return nil
end

local function updateImbueWarning(frame)
    if not frame or not frame.imbueWarning then return end
    if not imbueKnown() then frame.imbueWarning:SetText(""); return end
    local main = equippedImbueWeapon(16) == true and hasShamanImbue(16) == false
    local off = equippedImbueWeapon(17) == true and hasShamanImbue(17) == false
    local text = main and off and "主手、副手武器未强化" or main and "主手武器未强化" or off and "副手武器未强化" or ""
    frame.imbueWarning:SetText(text)
end

local function percent(current, maximum)
    if not finite(current) or not finite(maximum) or maximum <= 0 then return "—" end
    return string.format("%d%%", math.max(0, math.min(100, math.floor(current / maximum * 100 + 0.5))))
end

-- Let the client format protected percentages without inspecting them in Lua.
local function healthPercentText(label, unit, current, maximum)
    local visible = percent(current, maximum)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if visible == "—" and curve and type(UnitHealthPercent) == "function" and type(label.SetFormattedText) == "function" then
        local ok = pcall(function() label:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve)) end)
        if ok then return end
    end
    label:SetText(visible)
end

local function powerPercentText(label, powerType, current, maximum)
    local visible = percent(current, maximum)
    if visible ~= "—" then visible = visible:sub(1, -2) end
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if visible == "—" and curve and type(UnitPowerPercent) == "function" and type(label.SetFormattedText) == "function" then
        local ok = pcall(function() label:SetFormattedText("%.0f", UnitPowerPercent("player", powerType, false, curve)) end)
        if ok then return end
    end
    label:SetText(visible)
end

local function validColor(r, g, b)
    return finite(r) and finite(g) and finite(b)
        and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1
end

-- Keep player health bars in their class color.
local fallbackClassColors = {
    WARRIOR = {0.78, 0.61, 0.43}, PALADIN = {0.96, 0.55, 0.73},
    HUNTER = {0.67, 0.83, 0.45}, ROGUE = {1.00, 0.96, 0.41},
    PRIEST = {1.00, 1.00, 1.00}, DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN = {0.00, 0.44, 0.87}, MAGE = {0.25, 0.78, 0.92},
    WARLOCK = {0.53, 0.53, 0.93}, MONK = {0.00, 1.00, 0.59},
    DRUID = {1.00, 0.49, 0.04}, DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER = {0.20, 0.58, 0.50},
}

local function classColor(unit)
    local isPlayer = call(UnitIsPlayer, unit)
    if not readable(isPlayer) or isPlayer ~= true then return 0.55, 0.55, 0.55 end
    local _, token = call(UnitClass, unit)
    if not readable(token) or type(token) ~= "string" then return 0.55, 0.55, 0.55 end
    local colors = readable(RAID_CLASS_COLORS) and RAID_CLASS_COLORS or nil
    if type(colors) == "table" then
        local ok, r, g, b = pcall(function()
            local color = colors[token]
            if color then return color.r, color.g, color.b end
        end)
        if ok and finite(r) and finite(g) and finite(b)
            and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then return r, g, b end
    end
    local color = fallbackClassColors[token]
    if color then return color[1], color[2], color[3] end
    return 0.55, 0.55, 0.55
end

local function applySelectionColor(bar, unit)
    -- The native target frame uses the client selection color for NPC reactions.
    if type(UnitSelectionColor) == "function" then
        local ok, r, g, b = pcall(UnitSelectionColor, unit)
        if ok and (not readable(r) or not readable(g) or not readable(b) or validColor(r, g, b)) then
            -- StatusBar can receive protected color components directly.
            if pcall(bar.SetStatusBarColor, bar, r, g, b, 1) then return true end
        end
    end
    local reaction = call(UnitReaction, unit, "player")
    local colors = FACTION_BAR_COLORS
    if not finite(reaction) or reaction ~= math.floor(reaction) or not readable(colors) or type(colors) ~= "table" then return false end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, colors)
        if not ok or not readable(accessible) or not accessible then return false end
    end
    local ok, r, g, b = pcall(function()
        local color = colors[reaction]
        if color then return color.r, color.g, color.b end
    end)
    if ok and validColor(r, g, b) then
        bar:SetStatusBarColor(r, g, b, 1)
        return true
    end
    return false
end

local function showOwnSurname()
    -- Forever's Nameplates > My Secondary Name setting uses this CVar.
    local getter = type(GetCVarBool) == "function" and GetCVarBool
        or (C_CVar and C_CVar.GetCVarBool)
    local value = call(getter, "UnitSurnameOwn")
    return readable(value) and value == true
end

local function updateUnitName(label, unit)
    -- Forever's second name component can be a surname rather than a realm.
    local name, second = call(UnitFullName, unit)
    if readable(name) and (type(name) ~= "string" or name == "") then
        name, second = call(UnitName, unit)
    end
    if unit == "player" and not showOwnSurname() then
        -- The client's helper also handles a name that already contains both parts.
        local getter = NameUtil and NameUtil.GetUnitFirstName
        if type(getter) == "function" then
            local ok, first = pcall(getter, unit)
            if ok and not readable(first) then
                label:SetText("未知")
                return
            elseif ok and type(first) == "string" and first ~= "" then
                label:SetText(first)
                return
            end
        end
        if not readable(name) or type(name) ~= "string" or name == "" then
            label:SetText("未知")
            return
        end
        local ok, separator = pcall(function()
            return Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
        end)
        if not ok or not readable(separator) or type(separator) ~= "string" or separator == "" then
            label:SetText("未知")
            return
        end
        local index = name:find(separator, 1, true)
        if index == 1 then label:SetText("未知"); return end
        if index then name = name:sub(1, index - 1) end
        label:SetText(name)
        return
    end
    if not readable(name) then
        -- FontString can accept protected text without exposing it to Lua.
        if not pcall(label.SetText, label, name) then label:SetText("未知") end
        return
    end
    if type(name) ~= "string" or name == "" then label:SetText("未知"); return end
    if (unit ~= "player" or showOwnSurname())
        and readable(second) and type(second) == "string" and second ~= "" then
        name = name .. " " .. second
    end
    label:SetText(name)
end

local function clearHealthPrediction(bar)
    if bar.healPrediction then pcall(bar.healPrediction.SetValue, bar.healPrediction, 0) end
    if bar.healAmount then bar.healAmount:SetText("") end
end

local function updateHealthPrediction(bar, unit)
    local prediction, calculator = bar.healPrediction, bar.healCalculator
    if not prediction or not calculator then return end
    local ok, own, maximum, raw = pcall(function()
        UnitGetDetailedHealPrediction(unit, "player", calculator)
        local _, fromPlayer = calculator:GetIncomingHeals()
        local raw
        if type(calculator.GetTotalIncomingHealsFromHealer) == "function" then
            raw = calculator:GetTotalIncomingHealsFromHealer()
        end
        return fromPlayer, calculator:GetMaximumHealth(), raw
    end)
    if not ok then clearHealthPrediction(bar); return end
    -- Values may be secret; only the native StatusBar consumes these directly.
    if not pcall(function() prediction:SetMinMaxValues(0, maximum); prediction:SetValue(own) end) then
        clearHealthPrediction(bar)
        return
    end
    if bar.healAmount then
        -- The number is optional when the client restricts its use in Lua.
        if finite(raw) and raw > 0 then bar.healAmount:SetText("+" .. tostring(math.floor(raw + 0.5)))
        else bar.healAmount:SetText("") end
    end
end

local function updateHealth(bar, unit)
    local present = call(UnitExists, unit)
    if not readable(present) or present ~= true then
        clearHealthPrediction(bar)
        bar:SetStatusBarColor(0.55, 0.55, 0.55, 1)
        bar:SetMinMaxValues(0, 1); bar:SetValue(0)
        if unit == "target" and readable(present) then
            bar.nameLabel:SetText("")
            bar.text:SetText("")
        else
            bar.nameLabel:SetText(not readable(present) and "未知" or "—")
            bar.text:SetText("—")
        end
        bar.levelLabel:SetText("")
        return
    end
    -- Use the client's effective cap, which includes the current ruleset.
    local cap = call(GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer)
    local level = call(UnitLevel, unit)
    if finite(cap) and cap > 0 and cap == math.floor(cap)
        and finite(level) and level > 0 and level == math.floor(level) and level < cap then
        bar.levelLabel:SetText(tostring(level))
    else
        bar.levelLabel:SetText("")
    end
    updateUnitName(bar.nameLabel, unit)
    local player = call(UnitIsPlayer, unit)
    if unit ~= "target" or (readable(player) and player == true) or not applySelectionColor(bar, unit) then
        local r, g, b = classColor(unit)
        bar:SetStatusBarColor(r, g, b, 1)
    end
    local current, maximum = call(UnitHealth, unit), call(UnitHealthMax, unit)
    -- Native status bars accept client-protected numeric values without Lua arithmetic.
    local ok = pcall(function() bar:SetMinMaxValues(0, maximum); bar:SetValue(current) end)
    if not ok then bar:SetMinMaxValues(0, 1); bar:SetValue(0) end
    healthPercentText(bar.text, unit, current, maximum)
    updateHealthPrediction(bar, unit)
end

-- Use the client's resource palette, not addon-defined per-resource colors.
local function paletteColor(key)
    local colors = PowerBarColor
    if not readable(key) or (type(key) ~= "string" and type(key) ~= "number")
        or not readable(colors) or type(colors) ~= "table" then return end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, colors)
        if not ok or not readable(accessible) or accessible ~= true then return end
    end
    local ok, r, g, b = pcall(function()
        local color = colors[key]
        if not readable(color) or type(color) ~= "table" then return end
        if type(canaccesstable) == "function" and not canaccesstable(color) then return end
        return color.r, color.g, color.b
    end)
    if ok and validColor(r, g, b) then return r, g, b end
end

local function defaultPowerColor(powerType, token, altR, altG, altB)
    local r, g, b = paletteColor(token)
    if r then return r, g, b end
    if validColor(altR, altG, altB) then return altR, altG, altB end
    r, g, b = paletteColor(powerType)
    if r then return r, g, b end
    return 1, 1, 1
end

local function updateResource(ball, powerType, token, altR, altG, altB)
    local r, g, b = defaultPowerColor(powerType, token, altR, altG, altB)
    ball.fill:SetStatusBarColor(r, g, b, 1)
    if not finite(powerType) then
        ball.fill:SetMinMaxValues(0, 1); ball.fill:SetValue(0)
        ball.value:SetText("—"); return
    end
    local current, maximum = call(UnitPower, "player", powerType), call(UnitPowerMax, "player", powerType)
    if (readable(current) and not finite(current)) or (readable(maximum) and (not finite(maximum) or maximum <= 0)) then
        ball.fill:SetMinMaxValues(0, 1); ball.fill:SetValue(0)
        ball.value:SetText("—"); return
    end
    -- StatusBar handles protected values natively; never inspect them in Lua.
    local ok = pcall(function() ball.fill:SetMinMaxValues(0, maximum); ball.fill:SetValue(current) end)
    if not ok then ball.fill:SetMinMaxValues(0, 1); ball.fill:SetValue(0) end
    powerPercentText(ball.value, powerType, current, maximum)
end

local function refreshVitals()
    if not hud or not hud:IsShown() then return end
    updateHealth(hud.player, "player")
    updateHealth(hud.target, "target")
    local ok, powerType, token, altR, altG, altB = pcall(function() return UnitPowerType("player") end)
    if not ok or not finite(powerType) then
        updateResource(hud.primary, nil); return
    end
    updateResource(hud.primary, powerType, token, altR, altG, altB)
end

-- Only mirror stance art when the client identifies the exact configured spell.
-- Never bind by a mutable stance index: it can change during combat.
local function stanceForSpell(id)
    if not id or type(GetNumShapeshiftForms) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then return end
    local count = call(GetNumShapeshiftForms)
    if not finite(count) or count < 1 or count > 100 then return end
    for i = 1, count do
        local ok, _, _, _, spellID = pcall(GetShapeshiftFormInfo, i)
        if ok and readable(spellID) and spellID == id then
            return i
        end
    end
end

local function refreshSlotIcon(slot, id)
    if not slot or not slot.icon or not id then return end
    local index = stanceForSpell(id)
    local ok, texture, _, _, spellID
    if index then ok, texture, _, _, spellID = pcall(GetShapeshiftFormInfo, index) end
    if not ok or not readable(spellID) or spellID ~= id then
        texture = call(C_Spell and C_Spell.GetSpellTexture, id)
    end
    if readable(texture) and (type(texture) == "number" or type(texture) == "string") then
        pcall(slot.icon.SetTexture, slot.icon, texture)
        pcall(slot.icon.Show, slot.icon)
    else
        pcall(slot.icon.Hide, slot.icon)
    end
end

-- Only track readable, independent spell cooldowns. Secret values cannot be
-- safely compared in Lua, so they do not produce a guessed ready flash.
local function trackReadyFlash(slot, id)
    if not slot or not slot.readyFlash then return end
    if slot.readySpell ~= id then
        slot.readySpell, slot.readyAt = id, nil
        slot.readyFlash:Stop()
    end
    if not id or type(GetTime) ~= "function" then return end
    local now = call(GetTime)
    if not finite(now) then return end
    local cd = call(C_Spell and C_Spell.GetSpellCooldown, id)
    if not readable(cd) or type(cd) ~= "table"
        or (type(canaccesstable) == "function" and call(canaccesstable, cd) ~= true) then return end
    local ok, start, duration, gcd = pcall(function() return cd.startTime, cd.duration, cd.isOnGCD end)
    if not ok or not finite(start) or not finite(duration) or not readable(gcd) then return end
    if start > 0 and duration > 1.6 and gcd ~= true and start + duration > now then
        slot.readyAt = start + duration
    elseif slot.readyAt then
        local finished = now >= slot.readyAt and now <= slot.readyAt + 1
        slot.readyAt = nil
        if finished and slot.button:IsShown() then slot.readyFlash:Play() end
    end
end

local function refreshCooldown(slot, id)
    if not slot or not slot.cooldown then return end
    trackReadyFlash(slot, id)
    if not id then pcall(slot.cooldown.Clear, slot.cooldown); return end
    local stanceIndex = stanceForSpell(id)
    if stanceIndex and type(GetShapeshiftFormCooldown) == "function" then
        local ok, start, duration = pcall(GetShapeshiftFormCooldown, stanceIndex)
        if ok and finite(start) and finite(duration) then
            pcall(slot.cooldown.SetCooldown, slot.cooldown, start, duration)
            return
        end
    end
    local getDuration = C_Spell and C_Spell.GetSpellCooldownDuration
    if type(getDuration) == "function" and type(slot.cooldown.SetCooldownFromDurationObject) == "function" then
        local duration = call(getDuration, id, true)
        if not readable(duration) then pcall(slot.cooldown.SetCooldownFromDurationObject, slot.cooldown, duration)
        elseif duration then pcall(slot.cooldown.SetCooldownFromDurationObject, slot.cooldown, duration)
        else pcall(slot.cooldown.Clear, slot.cooldown) end
        return
    end
    local cd = call(C_Spell and C_Spell.GetSpellCooldown, id)
    if type(cd) ~= "table" or not readable(cd) then pcall(slot.cooldown.Clear, slot.cooldown); return end
    if type(canaccesstable) == "function" and call(canaccesstable, cd) ~= true then pcall(slot.cooldown.Clear, slot.cooldown); return end
    local ok, start, duration = pcall(function() return cd.startTime, cd.duration end)
    if ok and finite(start) and finite(duration) then pcall(slot.cooldown.SetCooldown, slot.cooldown, start, duration)
    else pcall(slot.cooldown.Clear, slot.cooldown) end
end

local function refreshCooldowns()
    if not hud or not character then return end
    for i, slot in ipairs(hud.slots) do refreshCooldown(slot, character.slots[i]) end
    for _, flyout in ipairs(hud.totemFlyouts or {}) do
        for _, button in ipairs(flyout.buttons) do refreshCooldown(button, button.spellID) end
    end
end

-- The client distinguishes unavailable skills from insufficient power.  A
-- range result can be nil (no valid target), so only false means out of range.
local function refreshUsability(slot, id)
    if not slot or not slot.icon or not id then return end
    local stanceIndex = stanceForSpell(id)
    if stanceIndex then
        local ok, _, _, castable, spellID = pcall(GetShapeshiftFormInfo, stanceIndex)
        if ok and readable(spellID) and spellID == id and readable(castable) and type(castable) == "boolean" then
            local shade = castable and 1 or 0.4
            pcall(slot.icon.SetVertexColor, slot.icon, shade, shade, shade)
            return
        end
    end
    local r, g, b = 1, 1, 1
    local api = C_Spell
    local knownUnusable = false
    if api and type(api.IsSpellUsable) == "function" then
        local ok, usable, insufficient = pcall(api.IsSpellUsable, id)
        if ok and readable(usable) and type(usable) == "boolean" and not usable then
            knownUnusable = true
            if readable(insufficient) and insufficient == true then
                r, g, b = 0.5, 0.5, 1
            else
                r, g, b = 0.4, 0.4, 0.4
            end
        end
    end
    if not knownUnusable and api and type(api.IsSpellInRange) == "function" then
        local ok, inRange = pcall(api.IsSpellInRange, id, "target")
        if ok and readable(inRange) and inRange == false then r, g, b = 1, 0.25, 0.25 end
    end
    pcall(slot.icon.SetVertexColor, slot.icon, r, g, b)
end

local function refreshUsabilityAll()
    if not hud or not character or not hud:IsShown() then return end
    for i, slot in ipairs(hud.slots) do
        refreshSlotIcon(slot, character.slots[i])
        refreshUsability(slot, character.slots[i])
    end
    for _, flyout in ipairs(hud.totemFlyouts or {}) do
        for _, button in ipairs(flyout.buttons) do refreshUsability(button, button.spellID) end
    end
end

local function buttonPosition(i)
    local topY = 59 - TOP_SKILL_SIZE
    if i <= 4 then return 15 + (i - 1) * TOP_SKILL_STEP, topY, TOP_SKILL_SIZE end
    if i <= 8 then return 419 + (i - 5) * TOP_SKILL_STEP, topY, TOP_SKILL_SIZE end
    if i == 15 then return 15 + 4 * TOP_SKILL_STEP, topY, TOP_SKILL_SIZE end
    if i == 16 then return 419 + 4 * TOP_SKILL_STEP, topY, TOP_SKILL_SIZE end
    return 197 + (i - 9) * 55, 149
end

-- Read the system button that actually receives the existing binding. Never
-- create or change bindings, and never infer a spell from a macro or item.
local HUD_ACTION_BARS = {
    {nil, "ACTIONBUTTON"},
    {"MultiBarBottomLeft", "MULTIACTIONBAR1BUTTON"},
    {"MultiBarBottomRight", "MULTIACTIONBAR2BUTTON"},
    {"MultiBarRight", "MULTIACTIONBAR3BUTTON"},
    {"MultiBarLeft", "MULTIACTIONBAR4BUTTON"},
    {"MultiBar5", "MULTIACTIONBAR5BUTTON"},
    {"MultiBar6", "MULTIACTIONBAR6BUTTON"},
    {"MultiBar7", "MULTIACTIONBAR7BUTTON"},
}

local function hudNativeButton(row, index)
    if row == 1 then
        if type(GetActionButtonForID) == "function" then return call(GetActionButtonForID, index) end
        return _G["ActionButton" .. index]
    end
    local def = HUD_ACTION_BARS[row]
    if not def then return nil end
    local bar = _G[def[1]]
    if not readable(bar) or not bar then return nil end
    local ok, list = pcall(function() return bar.actionButtons end)
    if ok and readable(list) and type(list) == "table" then
        local found, button = pcall(function() return list[index] end)
        if found and readable(button) and button then return button end
    end
    -- Blizzard's multi-bar binding calls bar.actionButtons[index] directly;
    -- a similarly named global alone is not proof that the key reaches it.
    return nil
end

local function hudActionSpell(row, index)
    local button = hudNativeButton(row, index)
    if not readable(button) or not button then return nil end
    local ok, calculate = pcall(function() return button.CalculateAction end)
    if not ok or type(calculate) ~= "function" then return nil end
    local action = call(calculate, button, "LeftButton")
    if not finite(action) or action < 1 or action ~= math.floor(action) then return nil end
    local getInfo = type(GetActionInfo) == "function" and GetActionInfo or (C_ActionBar and C_ActionBar.GetActionInfo)
    local kind, spell = call(getInfo, action)
    if readable(kind) and kind == "spell" and finite(spell) and spell > 0 then return spell end
end

local function hudBindingKey(command)
    if type(GetBindingKey) ~= "function" or type(GetBindingAction) ~= "function" then return nil end
    local ok, first, second = pcall(GetBindingKey, command)
    if not ok then return nil end
    local function matches(key)
        if readable(key) and type(key) == "string" and key ~= "" then
            local actual = call(GetBindingAction, key, true)
            if readable(actual) and actual == command then return key end
        end
    end
    return matches(first) or matches(second)
end

local function hudKeyLabel(key)
    if not readable(key) or type(key) ~= "string" or key == "" then return "" end
    local localized = call(GetBindingText, key, 1)
    if not readable(localized) or type(localized) ~= "string" or localized == "" then localized = key end
    local prefix, rest = "", key
    local names = {SHIFT = "s-", CTRL = "c-", ALT = "a-", META = "m-"}
    while true do
        local modifier, tail = rest:match("^([A-Z]+)%-(.+)$")
        local short = modifier and names[modifier]
        if not short then break end
        prefix, rest = prefix .. short, tail
    end
    local special = {MOUSEWHEELUP = "MWU", MOUSEWHEELDOWN = "MWD", SPACE = "空格", TAB = "Tab",
        ENTER = "回车", PAGEUP = "Pg↑", PAGEDOWN = "Pg↓", UP = "↑", DOWN = "↓", LEFT = "←", RIGHT = "→"}
    local base = special[rest]
    if not base then
        local mouse, pad = rest:match("^BUTTON(%d+)$"), rest:match("^NUMPAD(%d)$")
        if mouse then base = "M" .. mouse elseif pad then base = "N" .. pad
        elseif rest:match("^[A-Z0-9]$") or rest:match("^F%d%d?$") or rest == "-" or rest == "=" then base = rest end
    end
    local result = (base and (prefix .. base) or localized):gsub("|", "||"):gsub("[\r\n]", " ")
    return result
end

local function refreshHUDKeys()
    if not hud or not character then return end
    local wanted, found = {}, {}
    -- slots can be sparse, so iterate the full configured range.
    for i = 1, SLOT_COUNT do local id = character.slots[i]; if validSlot(id) and id then wanted[id] = true end end
    for row, def in ipairs(HUD_ACTION_BARS) do
        for index = 1, 12 do
            local spell = hudActionSpell(row, index)
            if spell and wanted[spell] and not found[spell] then found[spell] = hudBindingKey(def[2] .. index) end
        end
    end
    for i, slot in ipairs(hud.slots) do
        local id = character.slots[i]
        slot.hotkey:SetText(hudKeyLabel(validSlot(id) and id and found[id] or nil))
    end
    hudKeyMapDirty = false
end

local function repaintHUDKeys()
    if not hud then return end
    local visible = {}
    for _, held in pairs(heldHUDKeys) do for _, slot in ipairs(held.slots) do visible[slot] = true end end
    for _, slot in ipairs(hud.slots) do
        if visible[slot] then slot.keyPressed:Show() else slot.keyPressed:Hide() end
    end
end

local function clearHUDKeys()
    heldHUDKeys = {}
    repaintHUDKeys()
end

local function markHUDKey(row, index, down)
    if not finite(index) or index < 1 or index > 12 or index ~= math.floor(index) then return end
    local token = row .. ":" .. index
    if not down then heldHUDKeys[token] = nil; repaintHUDKeys(); return end
    if not hud or not character or not hud:IsShown() then return end
    local spell = hudActionSpell(row, index)
    if not spell then return end
    local matches = {}
    for i, slot in ipairs(hud.slots) do
        local id = character.slots[i]
        if validSlot(id) and id == spell then matches[#matches + 1] = slot end
    end
    if #matches > 0 then heldHUDKeys[token] = {slots = matches, age = 0}; repaintHUDKeys() end
end

local function installHUDKeyHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local function hook(name, fn)
        if hudKeyHooks[name] or type(_G[name]) ~= "function" then return end
        if pcall(hooksecurefunc, name, fn) then hudKeyHooks[name] = true end
    end
    hook("ActionButtonDown", function(index) markHUDKey(1, index, true) end)
    hook("ActionButtonUp", function(index) markHUDKey(1, index, false) end)
    local function multi(barName, index, down)
        if not readable(barName) or type(barName) ~= "string" then return end
        for row = 2, #HUD_ACTION_BARS do
            if HUD_ACTION_BARS[row][1] == barName then markHUDKey(row, index, down); return end
        end
    end
    hook("MultiActionButtonDown", function(barName, index) multi(barName, index, true) end)
    hook("MultiActionButtonUp", function(barName, index) multi(barName, index, false) end)
end

local function setSlot(slot, id)
    slot.button:SetAttribute("type1", id and "spell" or nil)
    slot.button:SetAttribute("spell1", id)
    local icon = id and call(C_Spell and C_Spell.GetSpellTexture, id)
    if readable(icon) and (type(icon) == "number" or type(icon) == "string") then
        slot.icon:SetTexture(icon)
        slot.icon:Show()
    else
        slot.icon:Hide()
    end
    refreshSlotIcon(slot, id)
    refreshCooldown(slot, id)
    refreshUsability(slot, id)
    if id then slot.button:Show() else slot.button:Hide() end
end

local function finishDrag(frame)
    frame:StopMovingOrSizing()
    dragging, pendingDragStop = false, nil
    local x, y = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if character and finite(x) and finite(y) and finite(px) and finite(py) then character.x, character.y = x-px, y-py end
end

local function createHUD()
    local frame = CreateFrame("Frame", "TigerioForeverToolboxHUD", UIParent)
    frame:SetSize(720, 205)
    frame:SetPoint("CENTER", UIParent, "CENTER", character.x or 0, character.y or -200)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    local _, playerClass = call(UnitClass, "player")
    local isShaman = readable(playerClass) and playerClass == "SHAMAN"
    if isShaman and type(frame.SetClampRectInsets) == "function" then
        -- Include the warning above the orb and the lower totem layout.
        pcall(frame.SetClampRectInsets, frame, -15, 15, 50, -32)
    end
    -- Keep the totem satellites clear of both bars and their aligned skills.
    frame.player = healthBar(frame, "player", isShaman and -15 or 15)
    frame.target = healthBar(frame, "target", isShaman and 449 or 419)
    frame.primary = resource(frame, 305)
    frame.totems = createTotemMonitor(frame.primary)
    if isShaman then
        local ready, flyouts = pcall(createTotemFlyouts, frame.primary)
        if ready then frame.totemFlyouts = flyouts end
        local warning = font(frame, "GameFontNormal")
        warning:SetSize(220, 18)
        warning:SetPoint("BOTTOM", frame, "TOP", 0, 30)
        warning:SetTextColor(1, 0.72, 0.26, 1)
        warning:SetShadowColor(0, 0, 0, 1)
        warning:SetShadowOffset(1, -1)
        warning:SetText("")
        frame.imbueWarning = warning
        safeRefreshTotemFlyouts(frame)
    end
    frame.slots = {}
    for i = 1, SLOT_COUNT do
        local tile = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        local x, y, size = buttonPosition(i)
        if isShaman then
            if i <= 4 or i == 15 then x = x - 30
            elseif i <= 8 or i == 16 then x = x + 30
            else y = y + 36 end
        end
        tile:SetSize(size or 52, size or 52)
        tile:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
        -- The secure handler selects the active edge from ActionButtonUseKeyDown.
        tile:RegisterForClicks("AnyUp", "AnyDown")
        local empty = tile:CreateTexture(nil, "BACKGROUND")
        empty:SetAllPoints()
        empty:SetTexture(MEDIA .. "SlotEmpty.tga")
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        icon:Hide()
        local mousePressed = tile:CreateTexture(nil, "ARTWORK", nil, 6)
        mousePressed:SetAllPoints(icon); mousePressed:SetColorTexture(0, 0, 0, 0.42)
        tile:SetPushedTexture(mousePressed)
        local keyPressed = tile:CreateTexture(nil, "ARTWORK", nil, 7)
        keyPressed:SetAllPoints(icon); keyPressed:SetColorTexture(0, 0, 0, 0.42); keyPressed:Hide()
        local rim = tile:CreateTexture(nil, "OVERLAY")
        rim:SetAllPoints()
        rim:SetTexture(MEDIA .. "SlotFrame.tga")
        local hotkey = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        hotkey:SetPoint("TOPRIGHT", -4, -4); hotkey:SetSize((size or 52) - 8, 10)
        hotkey:SetJustifyH("RIGHT")
        if type(hotkey.SetWordWrap) == "function" then hotkey:SetWordWrap(false) end
        if type(hotkey.SetMaxLines) == "function" then hotkey:SetMaxLines(1) end
        local cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
        cooldown:SetAllPoints(icon)
        cooldown:SetDrawEdge(false)
        cooldown:SetHideCountdownNumbers(false)
        cooldown:EnableMouse(false)
        local readyFlash
        pcall(function()
            local flash = tile:CreateTexture(nil, "OVERLAY", nil, 7)
            flash:Hide()
            flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            flash:SetBlendMode("ADD")
            flash:SetVertexColor(1, 0.82, 0.34, 0.9)
            flash:SetSize((size or 52) * 1.3, (size or 52) * 1.3)
            flash:SetPoint("CENTER", tile, "CENTER")
            local group = flash:CreateAnimationGroup()
            local scale = group:CreateAnimation("Scale")
            scale:SetScaleFrom(0.7, 0.7); scale:SetScaleTo(1.4, 1.4); scale:SetDuration(0.36)
            local alpha = group:CreateAnimation("Alpha")
            alpha:SetFromAlpha(0.95); alpha:SetToAlpha(0); alpha:SetDuration(0.36)
            group:SetScript("OnPlay", function() flash:Show() end)
            group:SetScript("OnFinished", function() flash:Hide() end)
            group:SetScript("OnStop", function() flash:Hide() end)
            readyFlash = group
        end)
        local index = i
        tile:SetScript("OnEnter", function(self)
            if not character or not character.slots[index] or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if type(GameTooltip.SetSpellByID) == "function" then GameTooltip:SetSpellByID(character.slots[index]) end
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.slots[i] = {button=tile, icon=icon, cooldown=cooldown, hotkey=hotkey, keyPressed=keyPressed, readyFlash=readyFlash}
    end
    frame.handle = CreateFrame("Frame", nil, frame)
    frame.handle:SetSize(170, 22)
    frame.handle:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.handle:EnableMouse(true)
    frame.handle:RegisterForDrag("LeftButton")
    background(frame.handle, 0.12, 0.09, 0.06, 0.9)
    local title = font(frame.handle, "GameFontNormalSmall")
    title:SetAllPoints(); title:SetText("拖动 HUD")
    frame.handle:SetScript("OnDragStart", function()
        if not combat() and unlocked then frame:StartMoving(); dragging = true end
    end)
    frame.handle:SetScript("OnDragStop", function()
        if combat() then pendingDragStop = true; return end
        finishDrag(frame)
    end)
    frame.handle:Hide()
    for i, slot in ipairs(frame.slots) do setSlot(slot, character.slots[i]) end
    local castOK, targetOK = false, false
    if type(toolbox.attachHUDCast) == "function" then
        local ok, ready = pcall(toolbox.attachHUDCast, frame)
        castOK = ok and ready == true
    end
    if isShaman and castOK then
        -- Keep both casting bars directly below their respective health bars.
        if frame.tftCast then
            frame.tftCast:ClearAllPoints()
            frame.tftCast:SetPoint("TOPLEFT", frame, "TOPLEFT", -15, -116)
        end
        if frame.tftTargetCast then
            frame.tftTargetCast:ClearAllPoints()
            frame.tftTargetCast:SetPoint("TOPLEFT", frame, "TOPLEFT", 449, -136)
        end
    end
    if type(toolbox.attachHUDTargetState) == "function" then
        local ok, ready = pcall(toolbox.attachHUDTargetState, frame)
        targetOK = ok and ready == true
    end
    if type(toolbox.attachTargetOfTarget) == "function" then
        pcall(toolbox.attachTargetOfTarget, frame)
    end
    if type(toolbox.attachHUDCombo) == "function" then
        pcall(toolbox.attachHUDCombo, frame)
    end
    if type(toolbox.attachWarriorStance) == "function" then
        pcall(toolbox.attachWarriorStance, frame)
    end
    if type(toolbox.attachShamanBuffMonitor) == "function" then
        pcall(toolbox.attachShamanBuffMonitor, frame)
    end
    updateTotems(frame)
    updateImbueWarning(frame)
    frame.tftReplacementReady = castOK and targetOK and not frame.tftTargetCastUnavailable
    return frame
end

local function ensureHUD()
    if hud then return true end
    if combat() then pendingInit = true; return false, "战斗中无法调整 HUD" end
    if not currentData() then return false, dataError or "角色数据暂不可用" end
    local ok, result = pcall(createHUD)
    if not ok or not result then dataError = "HUD 初始化失败"; return false, dataError end
    hud, pendingInit = result, nil
    if not character.enabled then hud:Hide() end
    hudKeyMapDirty = true
    installHUDKeyHooks()
    refreshVitals(); refreshCooldowns(); refreshUsabilityAll()
    return true
end

function toolbox.getTotemPlaceholderStyle()
    local config, err = currentData()
    if not config then return nil, err end
    return config.totemPlaceholderStyle == "icon" and "icon" or "text"
end

function toolbox.setTotemPlaceholderStyle(value)
    if value ~= "text" and value ~= "icon" then return false, "设置无效" end
    local config, err = currentData()
    if not config then return false, err end
    config.totemPlaceholderStyle = value
    updateTotems(hud)
    notify()
    return true
end

function toolbox.setHUDSlot(index, spellID)
    if combat() then return false, "战斗中无法修改技能" end
    if not finite(index) or index ~= math.floor(index) or index < 1 or index > SLOT_COUNT or not validSlot(spellID) then return false, "技能无效" end
    local config, err = currentData()
    if not config then return false, err end
    local ok, why = ensureHUD()
    if not ok then return false, why end
    local applied = pcall(setSlot, hud.slots[index], spellID)
    if not applied then
        pcall(setSlot, hud.slots[index], config.slots[index])
        return false, "技能设置失败"
    end
    config.slots[index] = spellID
    hudKeyMapDirty = true
    notify()
    return true
end

function toolbox.setHUDEnabled(value)
    if combat() then return false, "战斗中无法切换 HUD" end
    if type(value) ~= "boolean" then return false, "设置无效" end
    local config, err = currentData()
    if not config then return false, err end
    local ok, why = ensureHUD()
    if not ok then return false, why end
    if value then hud:Show() else
        if dragging then finishDrag(hud) end
        clearHUDKeys()
        unlocked = false; hud.handle:Hide(); hud:Hide()
    end
    if value then hudKeyMapDirty = true; installHUDKeyHooks() end
    config.enabled = value
    if value then updateNativeFrames(hud:IsShown()) else updateNativeFrames(false) end
    if type(toolbox.syncPartyFrames) == "function" then pcall(toolbox.syncPartyFrames) end
    if type(toolbox.syncFocusFrame) == "function" then pcall(toolbox.syncFocusFrame) end
    updateTotems(hud); updateImbueWarning(hud); refreshVitals(); refreshCooldowns(); refreshUsabilityAll(); notify()
    return true
end

function toolbox.setHUDUnlocked(value)
    if combat() then return false, "战斗中无法移动 HUD" end
    if type(value) ~= "boolean" then return false, "设置无效" end
    local config, err = currentData()
    if not config then return false, err end
    if value and not config.enabled then return false, "请先启用 HUD" end
    local ok, why = ensureHUD()
    if not ok then return false, why end
    if not value and dragging then finishDrag(hud) end
    unlocked = value
    if unlocked then hud.handle:Show() else hud.handle:Hide() end
    notify()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED", "ADDON_LOADED",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_LEVEL", "PLAYER_LEVEL_UP", "PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL",
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "CVAR_UPDATE",
    "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR"}) do driver:RegisterEvent(event) end
pcall(driver.RegisterEvent, driver, "PLAYER_TOTEM_UPDATE")
pcall(driver.RegisterEvent, driver, "UPDATE_MULTI_CAST_ACTIONBAR")
pcall(driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED")
for _, event in ipairs({"UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"}) do
    pcall(driver.RegisterEvent, driver, event)
end
for _, event in ipairs({"PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "WEAPON_ENCHANT_CHANGED",
    "WEAPON_SLOT_CHANGED", "GET_ITEM_INFO_RECEIVED"}) do pcall(driver.RegisterEvent, driver, event) end

driver:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        initData()
        if character and character.enabled then
            local ready = ensureHUD()
            if ready and hud and hud:IsShown() then updateNativeFrames(true) end
        end
        notify()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingDragStop and hud then pcall(finishDrag, hud) end
        if pendingInit and character and character.enabled then ensureHUD() end
        if nativeSyncPending or (character and character.enabled and hud and hud:IsShown()) then
            updateNativeFrames(character and character.enabled and hud and hud:IsShown())
        end
        safeRefreshTotemFlyouts(hud)
        updateTotems(hud); updateImbueWarning(hud); refreshVitals(); refreshCooldowns(); refreshUsabilityAll(); notify()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if dragging then
            if not combat() then pcall(finishDrag, hud) else pendingDragStop = true end
        end
    elseif event == "CVAR_UPDATE" then
        if not readable(unit) or type(unit) ~= "string" or unit:lower() == "unitsurnameown" then refreshVitals() end
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
        clearHUDKeys(); hudKeyMapDirty = true
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELLS_CHANGED" or event == "UPDATE_SHAPESHIFT_FORMS" or event == "UPDATE_SHAPESHIFT_FORM" then
        if event ~= "SPELL_UPDATE_COOLDOWN" then clearHUDKeys(); hudKeyMapDirty = true end
        if event == "UPDATE_SHAPESHIFT_FORM" then updateTotems(hud) end
        if event == "SPELLS_CHANGED" then updateImbueWarning(hud); safeRefreshTotemFlyouts(hud) end
        refreshCooldowns(); refreshUsabilityAll()
    elseif event == "UPDATE_MULTI_CAST_ACTIONBAR" then
        safeRefreshTotemFlyouts(hud)
        refreshCooldowns(); refreshUsabilityAll()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        scheduleTotemRefresh(hud)
        -- The native frame can load after the HUD. Recheck only if no other
        -- owner has taken over; combat changes are deferred by the helper.
        local frame = _G.TotemFrame
        if frame and not nativeOwned[frame] and not nativeDisowned[frame]
            and character and character.enabled and hud and hud:IsShown() then
            updateNativeFrames(true)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if readable(unit) and unit == "player" and isKnownTotemSpell(hud, spellID) then
            scheduleTotemRefresh(hud)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "WEAPON_ENCHANT_CHANGED"
        or event == "WEAPON_SLOT_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
        updateImbueWarning(hud)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if readable(unit) and unit == "player" then updateImbueWarning(hud) end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" or event == "ADDON_LOADED" then
        if event ~= "PLAYER_TARGET_CHANGED" then clearHUDKeys(); hudKeyMapDirty = true; installHUDKeyHooks() end
        if event ~= "PLAYER_TARGET_CHANGED" then safeRefreshTotemFlyouts(hud) end
        local previousNotice = nativeFrameNotice
        if character and character.enabled and hud and hud:IsShown() then updateNativeFrames(true) end
        if previousNotice ~= nativeFrameNotice then notify() end
        updateTotems(hud); updateImbueWarning(hud); refreshVitals(); refreshUsabilityAll()
    elseif event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        if readable(unit) and type(unit) == "string" then
            local samePlayer = call(UnitIsUnit, unit, "player")
            local sameTarget = call(UnitIsUnit, unit, "target")
            if unit == "player" or unit == "target" or (readable(samePlayer) and samePlayer == true)
                or (readable(sameTarget) and sameTarget == true) then refreshVitals() end
        end
    elseif event:match("^UNIT_") then
        if readable(unit) and (unit == "player" or unit == "target") then refreshVitals() end
    else
        refreshVitals()
    end
end)

-- Skills configured here are not action slots.  Poll their client-provided
-- state lightly so range and stance changes update even without slot events.
local usabilityElapsed, imbueElapsed = 0, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not hud then return end
    if not hud:IsShown() then
        totemRetry = nil
        if next(heldHUDKeys) then clearHUDKeys() end
        return
    end
    advanceTotemRefresh(hud, elapsed)
    if next(heldHUDKeys) then
        local changed = false
        for token, held in pairs(heldHUDKeys) do
            held.age = held.age + elapsed
            if held.age >= 2 then heldHUDKeys[token] = nil; changed = true end
        end
        if changed then repaintHUDKeys() end
    end
    if hud.imbueWarning then
        imbueElapsed = imbueElapsed + elapsed
        if imbueElapsed >= 1 then imbueElapsed = 0; updateImbueWarning(hud) end
    end
    usabilityElapsed = usabilityElapsed + elapsed
    if usabilityElapsed < 0.25 then return end
    usabilityElapsed = 0
    if hudKeyMapDirty then refreshHUDKeys() end
    updateTotemTimers(hud)
    if character then
        for i, slot in ipairs(hud.slots) do trackReadyFlash(slot, character.slots[i]) end
    end
    refreshUsabilityAll()
end)
