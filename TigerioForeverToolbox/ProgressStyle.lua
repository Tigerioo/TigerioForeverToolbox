-- Draw the player's experience at the top while preserving Blizzard's other
-- tracking bars and restoring the original experience bar when disabled.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, enabled, pending, elapsed = nil, false, false, 0
local managedArt, suppressedXP, disownedXP, managedDividers = {}, {}, {}, {}
local experience, xpKnown, nativeXP = nil, false, nil
local MEDIA = "Interface\\AddOns\\TigerioForeverToolbox\\Media\\HUD\\"

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, allowed = pcall(canaccesstable, value)
    return ok and readable(allowed) and allowed == true
end

local function field(value, key)
    if not readable(value) or not value then return nil, false end
    local ok, result = pcall(function() return value[key] end)
    if ok and readable(result) then return result, true end
    return nil, false
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, locked = pcall(InCombatLockdown)
    return not ok or not readable(locked) or (locked ~= nil and locked ~= false)
end

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and readable(guid) and type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function init()
    character = nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then return false end
    local data, ok = field(db, "globalUI")
    if not ok then return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.globalUI = data end) then return false end
    end
    local entries = field(data, "characters")
    if not tableOK(data) or field(data, "version") ~= 1 or not tableOK(entries) then return false end
    local entry, entryOK = field(entries, guid)
    if not entryOK then return false end
    if entry == nil then
        entry = {}
        if not pcall(function() entries[guid] = entry end) then return false end
    end
    local setting, settingOK = field(entry, "progressStyle")
    if not tableOK(entry) or not settingOK or (setting ~= nil and type(setting) ~= "boolean") then return false end
    character, enabled = entry, setting ~= false
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not character or not guid or not tableOK(db) then return false end
    local data = field(db, "globalUI")
    local entries = field(data, "characters")
    return tableOK(data) and field(data, "version") == 1 and tableOK(entries)
        and field(entries, guid) == character
end

local function safe(object)
    if not readable(object) or not object then return false end
    local ok, forbidden = pcall(function()
        return type(object.IsForbidden) == "function" and object:IsForbidden()
    end)
    return ok and readable(forbidden) and not forbidden
end

local function artState(texture)
    if not safe(texture) then return end
    local ok, atlas, alpha = pcall(function() return texture:GetAtlas(), texture:GetAlpha() end)
    if ok and readable(atlas) and type(atlas) == "string" and readable(alpha) and type(alpha) == "number" then
        return atlas:lower(), alpha
    end
end

local function suppressArt(texture, allowed)
    if not texture or managedArt[texture] ~= nil then return end
    local atlas, alpha = artState(texture)
    -- A non-default alpha or different atlas can be owned by another addon.
    if not atlas or not allowed[atlas] or alpha ~= 1 then return end
    if pcall(texture.SetAlpha, texture, 0) then managedArt[texture] = {alpha = alpha} end
end

local function restoreArt()
    local success = true
    for texture, old in pairs(managedArt) do
        local ok, alpha = pcall(texture.GetAlpha, texture)
        if not ok or not readable(alpha) or type(alpha) ~= "number" then
            success = false
        elseif alpha == 0 then
            if pcall(texture.SetAlpha, texture, old.alpha) then managedArt[texture] = nil
            else success = false end
        else
            managedArt[texture] = nil
        end
    end
    return success
end

local function restoreDivider(divider, original)
    local ok, alpha = pcall(divider.GetAlpha, divider)
    if not ok or not readable(alpha) or type(alpha) ~= "number" then return false end
    if alpha == 0 and not pcall(divider.SetAlpha, divider, original) then return false end
    managedDividers[divider] = nil
    return true
end

local function restoreDividers()
    local success = true
    for divider, state in pairs(managedDividers) do
        if not restoreDivider(divider, state.alpha) then success = false end
    end
    return success
end

-- Dividers are pooled siblings of the actual XP bar, not its children.
-- Control only the active dividers of a container currently displaying our
-- suppressed XP bar; never hide the container or its shared reputation UI.
local function syncDividers()
    local desired, uncertain = {}, {}
    local enum = field(field(StatusTrackingBarInfo, "BarsEnum"), "Experience") or 4
    for _, name in ipairs({"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer"}) do
        local container = _G[name]
        if safe(container) then
            local xp = field(field(container, "bars"), enum)
            local ok, shown = pcall(function() return container:GetShownBar() end)
            if not ok or not readable(shown) then
                uncertain[container] = true
            elseif xp and shown == xp and suppressedXP[xp] then
                local alphaOK, alpha = pcall(xp.GetAlpha, xp)
                if not alphaOK or not readable(alpha) then
                    uncertain[container] = true
                elseif alpha == 0 then
                    local pool = field(container, "HorizontalDividersPool")
                    if pool then
                        local got = pcall(function()
                            for divider in pool:EnumerateActive() do
                                if safe(divider) then desired[divider] = container end
                            end
                        end)
                        if not got then uncertain[container] = true end
                    end
                end
            end
        end
    end
    local success = true
    for divider, state in pairs(managedDividers) do
        if not desired[divider] and not uncertain[state.container] then
            if not restoreDivider(divider, state.alpha) then success = false end
        end
    end
    for divider, container in pairs(desired) do
        local state = managedDividers[divider]
        local ok, alpha = pcall(divider.GetAlpha, divider)
        if ok and readable(alpha) and type(alpha) == "number" then
            if state and alpha ~= 0 then
                -- The manager may reset pooled divider alpha during refresh.
                if not pcall(divider.SetAlpha, divider, 0) then success = false end
            elseif not state and alpha > 0 then
                if pcall(divider.SetAlpha, divider, 0) then
                    managedDividers[divider] = {alpha = alpha, container = container}
                else success = false end
            end
        else success = false end
    end
    if not success then pending = true end
    return success
end

local function restoreXP()
    local success = true
    for object, state in pairs(suppressedXP) do
        local restored = true
        local ok, alpha = pcall(object.GetAlpha, object)
        if not ok or not readable(alpha) then
            restored = false
        else
            if alpha == 0 and not pcall(object.SetAlpha, object, state.alpha) then restored = false end
            for child, wasEnabled in pairs(state.mouse) do
                local good, now = pcall(child.IsMouseEnabled, child)
                if good and readable(now) and now == false and wasEnabled then
                    if not pcall(child.EnableMouse, child, true) then restored = false end
                end
            end
        end
        if restored then suppressedXP[object] = nil else success = false end
    end
    return success
end

-- Only Blizzard's ExpStatusBarTemplate is controlled; reputation and other
-- tracking bars remain with the original manager and retain their interaction.
local function suppressXP(bar, parent)
    if not safe(bar) or field(bar, "isExpBar") ~= true or suppressedXP[bar] or disownedXP[bar] then return end
    local parentOK, actualParent = pcall(bar.GetParent, bar)
    if not parentOK or not readable(actualParent) or actualParent ~= parent then return end
    local ok, alpha = pcall(bar.GetAlpha, bar)
    if not ok or not readable(alpha) or type(alpha) ~= "number" then return end
    local state = {alpha = alpha, mouse = {}, parent = parent}
    local tick = field(bar, "ExhaustionTick")
    for _, object in ipairs({bar, tick}) do
        -- Mouse control is best effort; an unavailable tick must not leave
        -- the entire original XP bar visible beneath our replacement.
        if safe(object) and type(object.IsMouseEnabled) == "function" and type(object.EnableMouse) == "function" then
            local got, value = pcall(object.IsMouseEnabled, object)
            if got and readable(value) and value == true and pcall(object.EnableMouse, object, false) then
                state.mouse[object] = true
            end
        end
    end
    if pcall(bar.SetAlpha, bar, 0) then suppressedXP[bar] = state
    else for object in pairs(state.mouse) do pcall(object.EnableMouse, object, true) end end
end

local function createExperience()
    if experience then return true end
    local made
    local ok, result = pcall(function()
        local f = CreateFrame("Frame", nil, UIParent)
        made = f
        f:SetSize(520, 18)
        f:SetPoint("TOP", UIParent, "TOP", 0, -12)
        f:EnableMouse(true)
        local back = f:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.035, 0.027, 0.020, 0.92)
        local rest = CreateFrame("StatusBar", nil, f)
        rest:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        rest:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        rest:SetStatusBarTexture(MEDIA .. "BarFill.tga")
        rest:SetStatusBarColor(0.42, 0.44, 0.72, 0.65)
        rest:EnableMouse(false)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetAllPoints(rest)
        bar:SetStatusBarTexture(MEDIA .. "BarFill.tga")
        bar:SetStatusBarColor(0.60, 0.35, 0.78, 1)
        bar:EnableMouse(false)
        local overlay = CreateFrame("Frame", nil, f)
        overlay:SetAllPoints()
        overlay:EnableMouse(false)
        local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        for i = 1, 4 do
            local edge = overlay:CreateTexture(nil, "OVERLAY")
            edge:SetColorTexture(0.60, 0.43, 0.23, 0.95)
            if i == 1 then edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(1)
            elseif i == 2 then edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetHeight(1)
            elseif i == 3 then edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(1)
            else edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetWidth(1) end
        end
        f:SetScript("OnEnter", function(self)
            if not GameTooltip or not xpKnown then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("经验")
            GameTooltip:AddLine(self.xpText or "")
            if self.restText then GameTooltip:AddLine(self.restText) end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rest, f.bar, f.label = rest, bar, label
        f:Hide()
        return f
    end)
    if not ok or not result then
        if made then pcall(made.Hide, made) end
        return false
    end
    experience = result
    return true
end

local function xpValues(nativeBar)
    if nativeBar and type(nativeBar.GetLevelData) == "function" then
        local ok, value, maximum = pcall(nativeBar.GetLevelData, nativeBar)
        if ok then return value, maximum end
        return
    end
    if type(GameLimitedMode_IsBankedXPActive) == "function" then
        local ok, limited = pcall(GameLimitedMode_IsBankedXPActive)
        if not ok or not readable(limited) or limited then return end
    end
    if type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" then return end
    local ok, value, maximum = pcall(function() return UnitXP("player"), UnitXPMax("player") end)
    if ok then return value, maximum end
end

local function updateExperience(nativeBar)
    xpKnown = false
    if not experience then return false end
    if GameRulesUtil and type(GameRulesUtil.CanShowExperienceBar) == "function" then
        local ok, available = pcall(GameRulesUtil.CanShowExperienceBar)
        if not ok or not readable(available) or available ~= true then experience:Hide(); return false end
    end
    local value, maximum = xpValues(nativeBar)
    if not readable(value) or not readable(maximum) then
        -- StatusBar accepts protected values without exposing them to Lua.
        local ok = pcall(function() experience.bar:SetMinMaxValues(0, maximum); experience.bar:SetValue(value) end)
        if ok then
            experience.rest:SetMinMaxValues(0, 1); experience.rest:SetValue(0)
            experience.label:SetText("—")
            experience:Show()
            return true
        end
        experience:Hide()
        return false
    end
    if type(value) ~= "number" or type(maximum) ~= "number"
        or value ~= value or maximum ~= maximum or value < 0 or maximum <= 0
        or value >= 9007199254740992 or maximum >= 9007199254740992 then
        experience:Hide()
        return false
    end
    local current = math.max(0, math.min(value, maximum))
    experience.bar:SetMinMaxValues(0, maximum)
    experience.bar:SetValue(current)
    local rested = type(GetXPExhaustion) == "function" and select(2, pcall(GetXPExhaustion)) or nil
    if not readable(rested) or type(rested) ~= "number" or rested ~= rested or rested < 0 then rested = 0 end
    experience.rest:SetMinMaxValues(0, maximum)
    experience.rest:SetValue(math.min(maximum, current + rested))
    experience.label:SetText(string.format("%d / %d  ·  %.0f%%", current, maximum, current * 100 / maximum))
    experience.xpText = string.format("%d / %d", current, maximum)
    experience.restText = rested > 0 and string.format("休息经验：%d", rested) or nil
    experience:Show()
    xpKnown = true
    return true
end

local barAtlas = {["ui-hud-experiencebar-frame"] = true}
local leftAtlas = {["ui-hud-actionbar-gryphon-left"] = true, ["ui-hud-actionbar-wyvern-left"] = true}
local rightAtlas = {["ui-hud-actionbar-gryphon-right"] = true, ["ui-hud-actionbar-wyvern-right"] = true}

-- The shared frame can be reset by the client as the bar animates or changes.
-- Re-hide only the verified native atlas, and remember its original alpha.
local function suppressSharedFrame(texture)
    local atlas, alpha = artState(texture)
    if not atlas then pending = true; return end
    local state = managedArt[texture]
    if not barAtlas[atlas] then
        if state then
            if alpha ~= 0 or pcall(texture.SetAlpha, texture, state.alpha) then
                managedArt[texture] = nil
            else pending = true end
        end
        return
    end
    if state then
        if alpha ~= 0 and not pcall(texture.SetAlpha, texture, 0) then pending = true end
    elseif alpha > 0 then
        if pcall(texture.SetAlpha, texture, 0) then managedArt[texture] = {alpha = alpha}
        else pending = true end
    end
end

-- The frame texture is shared with reputation; restore it as soon as the
-- container switches away from the suppressed XP bar, including in combat.
local function syncSharedFrames()
    local enum = field(field(StatusTrackingBarInfo, "BarsEnum"), "Experience") or 4
    for _, name in ipairs({"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer"}) do
        local container = _G[name]
        if safe(container) then
            local texture = field(container, "BarFrameTexture")
            local xp = field(field(container, "bars"), enum)
            local ok, shown = pcall(function() return container:GetShownBar() end)
            if texture and ok and readable(shown) then
                local hidingXP = xp and shown == xp and suppressedXP[xp]
                if hidingXP then
                    local alphaOK, alpha = pcall(xp.GetAlpha, xp)
                    if alphaOK and readable(alpha) then hidingXP = alpha == 0 else hidingXP = nil end
                end
                if hidingXP then
                    suppressSharedFrame(texture)
                elseif managedArt[texture] then
                    local alphaOK, alpha = pcall(texture.GetAlpha, texture)
                    if alphaOK and readable(alpha) then
                        if alpha ~= 0 or pcall(texture.SetAlpha, texture, managedArt[texture].alpha) then
                            managedArt[texture] = nil
                        else pending = true end
                    else pending = true end
                end
            end
        end
    end
end

local function discover()
    if not enabled or not current() then return end
    if combat() then pending = true; syncSharedFrames(); syncDividers(); return end
    pending = false
    for bar, state in pairs(suppressedXP) do
        local parentOK, parent = pcall(bar.GetParent, bar)
        local alphaOK, alpha = pcall(bar.GetAlpha, bar)
        if parentOK and readable(parent) and alphaOK and readable(alpha) and parent ~= state.parent then
            if alpha == 0 then pcall(bar.SetAlpha, bar, state.alpha) end
            for object in pairs(state.mouse) do
                local ok, mouse = pcall(object.IsMouseEnabled, object)
                if ok and readable(mouse) and mouse == false then pcall(object.EnableMouse, object, true) end
            end
            suppressedXP[bar] = nil
            disownedXP[bar] = true
        elseif parentOK and readable(parent) and parent == state.parent and alphaOK and readable(alpha)
            and type(alpha) == "number" and alpha ~= 0 then
            -- Blizzard can reset the bar alpha while updating its display.
            -- Keep the replacement exclusive while this setting is enabled.
            if not pcall(bar.SetAlpha, bar, 0) then pending = true end
        end
    end
    local containers, selected = {}, nil
    local enum = field(field(StatusTrackingBarInfo, "BarsEnum"), "Experience") or 4
    for _, name in ipairs({"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer"}) do
        local frame = _G[name]
        if safe(frame) then
            local bar = field(field(frame, "bars"), enum)
            if safe(bar) and field(bar, "isExpBar") == true then
                local ok, shown = pcall(function() return frame:GetShownBar() end)
                if ok and readable(shown) and shown == bar then selected = bar end
                containers[#containers + 1] = {frame = frame, bar = bar, showing = ok and readable(shown) and shown == bar}
                nativeXP = selected or nativeXP or bar
            end
        end
    end
    if selected then nativeXP = selected end
    local ready = createExperience() and updateExperience(nativeXP)
    if ready then
        for _, info in ipairs(containers) do
            suppressXP(info.bar, info.frame)
        end
    else
        restoreXP()
    end
    syncSharedFrames()
    syncDividers()
    local caps = field(_G.MainActionBar, "EndCaps")
    suppressArt(field(field(caps, "LeftEndCap"), "Texture"), leftAtlas)
    suppressArt(field(field(caps, "RightEndCap"), "Texture"), rightAtlas)
end

function toolbox.getProgressStyleEnabled()
    if not current() then return nil, "进度条样式不可用" end
    return enabled
end

function toolbox.setProgressStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "进度条样式不可用" end
    if combat() then return false, "请在脱战后调整" end
    if value == enabled then return true end
    if not value then
        if experience then experience:Hide() end
        local success = restoreDividers()
        if not restoreXP() then success = false end
        if not restoreArt() then success = false end
        if not success then
            discover()
            return false, "进度条样式暂时无法恢复"
        end
        disownedXP = {}
    end
    if not pcall(function() character.progressStyle = value end) then
        if enabled then discover() end
        return false, "进度条样式无法保存"
    end
    enabled = value
    if value then discover() end
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED", "UPDATE_EXPANSION_LEVEL", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "UPDATE_FACTION"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if init() then discover() end
        if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then discover() end
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
        if enabled and current() then
            if not updateExperience(nativeXP) then
                if combat() then pending = true else discover() end
            end
        end
    else
        discover()
    end
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not enabled or not current() then return end
    elapsed = elapsed + delta
    if elapsed < 1 then return end
    elapsed = 0
    discover()
end)
