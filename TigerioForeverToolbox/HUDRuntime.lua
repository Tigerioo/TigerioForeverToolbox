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
    for _, name in ipairs({"PlayerFrame", "TargetFrame"}) do
        local frame = _G[name]
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
            elseif not nativeDisowned[frame] and parent == UIParent then
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
        else
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
    local caption = font(bar, "GameFontHighlightSmall")
    caption:SetPoint(unit == "player" and "LEFT" or "RIGHT", bar, unit == "player" and "LEFT" or "RIGHT", unit == "player" and 8 or -8, 0)
    caption:SetWidth(96)
    caption:SetJustifyH(unit == "player" and "LEFT" or "RIGHT")
    if type(caption.SetWordWrap) == "function" then caption:SetWordWrap(false) end
    if type(caption.SetMaxLines) == "function" then caption:SetMaxLines(1) end
    caption:SetText(unit == "target" and "" or "—")
    caption:SetShadowColor(0, 0, 0, 1)
    caption:SetShadowOffset(1, -1)
    bar.nameLabel = caption
    bar.text = font(bar)
    bar.text:SetPoint(unit == "player" and "RIGHT" or "LEFT", bar,
        unit == "player" and "RIGHT" or "LEFT", unit == "player" and -10 or 10, 0)
    bar.text:SetText(unit == "target" and "" or "—")
    local level = font(bar, "GameFontNormalSmall")
    level:SetPoint(unit == "player" and "TOPLEFT" or "TOPRIGHT", bar,
        unit == "player" and "TOPLEFT" or "TOPRIGHT", unit == "player" and 5 or -5, -1)
    level:SetText("")
    level:SetShadowColor(0, 0, 0, 1)
    level:SetShadowOffset(1, -1)
    bar.levelLabel = level
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
    {slot = 1, x = -58, y = 58, color = {1, 0.45, 0.20}}, -- fire: front left
    {slot = 2, x = 58, y = 58, color = {0.75, 0.66, 0.48}}, -- earth: front right
    {slot = 4, x = -58, y = -58, color = {0.65, 0.75, 0.80}}, -- air: back left
    {slot = 3, x = 58, y = -58, color = {0.32, 0.65, 1}}, -- water: back right
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
        local glyph = tile:CreateTexture(nil, "BACKGROUND")
        glyph:SetAllPoints()
        glyph:SetTexture(MEDIA .. "TotemGlyphs.tga")
        -- Half-pixel inset prevents adjacent elements bleeding into the slot.
        glyph:SetTexCoord((index - 1) / 4 + 0.5 / 256, index / 4 - 0.5 / 256, 0, 1)
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
        local timer = font(tile, "GameFontHighlightSmall")
        timer:SetSize(40, 10)
        timer:SetPoint(position.y > 0 and "BOTTOM" or "TOP", tile,
            position.y > 0 and "TOP" or "BOTTOM", 0, position.y > 0 and -1 or 1)
        timer:SetTextColor(1, 0.85, 0.62, 1)
        timer:SetShadowColor(0, 0, 0, 1)
        timer:SetShadowOffset(1, -1)
        timer:SetText("")
        tile:Hide()
        slots[#slots + 1] = {index = position.slot, frame = tile, glyph = glyph, icon = icon,
            rim = rim, timer = timer, masked = masked, color = position.color}
    end
    return slots
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

local function updateTotems(frame)
    if not frame or not frame.totems then return end
    local _, class = call(UnitClass, "player")
    local isShaman = readable(class) and class == "SHAMAN"
    local available = isShaman and type(GetTotemInfo) == "function"
    for _, slot in ipairs(frame.totems) do
        local ok, exists, _, start, duration, icon
        if available then ok, exists, _, start, duration, icon = pcall(GetTotemInfo, slot.index) end
        if ok and readable(exists) and exists == true and readable(icon)
            and (type(icon) == "number" or type(icon) == "string") then
            if slot.masked then
                slot.icon:SetTexture(icon)
                slot.icon:Show()
                slot.glyph:SetVertexColor(1, 1, 1, 1)
            else
                slot.icon:Hide()
                slot.glyph:SetVertexColor(slot.color[1], slot.color[2], slot.color[3], 1)
            end
            slot.rim:SetVertexColor(1, 1, 1, 1)
            if finite(start) and finite(duration) and duration > 0 then
                local finish = start + duration
                slot.finish = finite(finish) and finish or nil
            else
                slot.finish = nil
            end
            slot.frame:Show()
        else
            slot.finish = nil
            slot.icon:Hide()
            if isShaman then
                slot.glyph:SetVertexColor(1, 1, 1, 1)
                slot.rim:SetVertexColor(0.8, 0.8, 0.8, 1)
                slot.frame:Show()
            else
                slot.frame:Hide()
            end
        end
    end
    updateTotemTimers(frame)
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

local function updateHealth(bar, unit)
    local present = call(UnitExists, unit)
    if not readable(present) or present ~= true then
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

local function refreshCooldown(slot, id)
    if not slot or not slot.cooldown then return end
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
        -- Include the outward bars and upper/lower totem layout when dragging.
        pcall(frame.SetClampRectInsets, frame, -15, 15, 7, -32)
    end
    -- Keep the totem satellites clear of both bars and their aligned skills.
    frame.player = healthBar(frame, "player", isShaman and -15 or 15)
    frame.target = healthBar(frame, "target", isShaman and 449 or 419)
    frame.primary = resource(frame, 305)
    frame.totems = createTotemMonitor(frame.primary)
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
        local index = i
        tile:SetScript("OnEnter", function(self)
            if not character or not character.slots[index] or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if type(GameTooltip.SetSpellByID) == "function" then GameTooltip:SetSpellByID(character.slots[index]) end
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.slots[i] = {button=tile, icon=icon, cooldown=cooldown, hotkey=hotkey, keyPressed=keyPressed}
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
            frame.tftTargetCast:SetPoint("TOPLEFT", frame, "TOPLEFT", 449, -116)
        end
    end
    if type(toolbox.attachHUDTargetState) == "function" then
        local ok, ready = pcall(toolbox.attachHUDTargetState, frame)
        targetOK = ok and ready == true
    end
    if type(toolbox.attachHUDCombo) == "function" then
        pcall(toolbox.attachHUDCombo, frame)
    end
    updateTotems(frame)
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
    updateTotems(hud); refreshVitals(); refreshCooldowns(); refreshUsabilityAll(); notify()
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

driver:SetScript("OnEvent", function(_, event, unit)
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
        updateTotems(hud); refreshVitals(); refreshCooldowns(); refreshUsabilityAll(); notify()
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
        refreshCooldowns(); refreshUsabilityAll()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        updateTotems(hud)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" or event == "ADDON_LOADED" then
        if event ~= "PLAYER_TARGET_CHANGED" then clearHUDKeys(); hudKeyMapDirty = true; installHUDKeyHooks() end
        local previousNotice = nativeFrameNotice
        if character and character.enabled and hud and hud:IsShown() then updateNativeFrames(true) end
        if previousNotice ~= nativeFrameNotice then notify() end
        updateTotems(hud); refreshVitals(); refreshUsabilityAll()
    elseif event:match("^UNIT_") then
        if readable(unit) and (unit == "player" or unit == "target") then refreshVitals() end
    else
        refreshVitals()
    end
end)

-- Skills configured here are not action slots.  Poll their client-provided
-- state lightly so range and stance changes update even without slot events.
local usabilityElapsed = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not hud then return end
    if not hud:IsShown() then
        if next(heldHUDKeys) then clearHUDKeys() end
        return
    end
    if next(heldHUDKeys) then
        local changed = false
        for token, held in pairs(heldHUDKeys) do
            held.age = held.age + elapsed
            if held.age >= 2 then heldHUDKeys[token] = nil; changed = true end
        end
        if changed then repaintHUDKeys() end
    end
    usabilityElapsed = usabilityElapsed + elapsed
    if usabilityElapsed < 0.25 then return end
    usabilityElapsed = 0
    if hudKeyMapDirty then refreshHUDKeys() end
    updateTotemTimers(hud)
    refreshUsabilityAll()
end)
