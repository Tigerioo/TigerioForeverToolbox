-- Style the original minimap while preserving other addons' changes.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, dataError, overlay, overlayMap, pending = nil, nil, nil, nil, false
local borders = {}
local square, hookedMaps, externalMasks = nil, {}, {}
local dragHandle, moving
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local DEFAULT_MASK = "ui-hud-minimap-frame-generic-mask"
local function squareShape() return "SQUARE" end

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function tableOK(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, accessible = pcall(canaccesstable, value)
    return ok and readable(accessible) and accessible == true
end

local function field(value, key)
    local ok, result = pcall(function() return value[key] end)
    if not ok or not readable(result) then return nil, false end
    return result, true
end

local function combat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    if not ok or not readable(value) then return true end
    return value ~= nil and value ~= false
end

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, "player")
    if ok and readable(value) and type(value) == "string" and value:match("^Player%-") then return value end
end

local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end

local function initialize()
    character, dataError = nil, nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then dataError = "角色数据暂不可用"; return false end
    local data, ok = field(db, "globalUI")
    if not ok then dataError = "界面设置数据不可用"; return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.globalUI = data end) then dataError = "界面设置数据不可用"; return false end
    end
    if not tableOK(data) then dataError = "界面设置数据不可用"; return false end
    local version, versionOK = field(data, "version")
    local characters, charactersOK = field(data, "characters")
    if not versionOK or version ~= 1 or not charactersOK or not tableOK(characters) then
        dataError = "界面设置数据不可用"; return false
    end
    local entry, entryOK = field(characters, guid)
    if not entryOK then dataError = "小地图设置数据不可用"; return false end
    if entry == nil then
        entry = {}
        if not pcall(function() characters[guid] = entry end) then dataError = "小地图设置数据不可用"; return false end
    end
    if not tableOK(entry) then dataError = "小地图设置数据不可用"; return false end
    local setting, settingOK = field(entry, "mapStyle")
    if not settingOK or (setting ~= nil and type(setting) ~= "boolean") then
        dataError = "小地图设置数据不可用"; return false
    end
    character = entry
    return true
end

local function currentData()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not character or not guid or not tableOK(db) then
        return nil, dataError or "小地图设置暂不可用"
    end
    local data, dataOK = field(db, "globalUI")
    if not dataOK or not tableOK(data) then return nil, "小地图设置暂不可用" end
    local version, versionOK = field(data, "version")
    local characters, charactersOK = field(data, "characters")
    if not versionOK or version ~= 1 or not charactersOK or not tableOK(characters) then
        return nil, "小地图设置暂不可用"
    end
    local entry, entryOK = field(characters, guid)
    if not entryOK or entry ~= character then return nil, "小地图设置暂不可用" end
    local setting, settingOK = field(entry, "mapStyle")
    if not settingOK or (setting ~= nil and type(setting) ~= "boolean") then
        return nil, "小地图设置数据不可用"
    end
    return entry
end

local function enabled(entry)
    return entry.mapStyle ~= false
end

local function mapUsable(map)
    if not readable(map) or not map then return false end
    local ok, usable = pcall(function()
        if type(map.IsForbidden) == "function" and map:IsForbidden() then return false end
        if type(map.IsObjectType) == "function" and not map:IsObjectType("Minimap") then return false end
        return type(map.GetFrameLevel) == "function"
    end)
    return ok and readable(usable) and usable == true
end

local function pointOf(frame)
    local ok, p, relative, rp, x, y = pcall(frame.GetPoint, frame, 1)
    if ok and readable(p) and readable(relative) and readable(rp) and readable(x) and readable(y)
        and type(p) == "string" and relative and type(rp) == "string"
        and type(x) == "number" and type(y) == "number" then return {p, relative, rp, x, y} end
end

local function samePoint(a, b)
    if not a or not b then return false end
    for i = 1, 5 do if a[i] ~= b[i] then return false end end
    return true
end

local function mapOffsets(map)
    local ok, right, top, ms, us, width, height = pcall(function()
        return map:GetRight(), map:GetTop(), map:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if not ok or not readable(right) or not readable(top) or not readable(ms) or not readable(us)
        or not readable(width) or not readable(height) or type(right) ~= "number" or type(top) ~= "number"
        or type(ms) ~= "number" or type(us) ~= "number" or us == 0
        or type(width) ~= "number" or type(height) ~= "number" then return end
    return right * ms / us - width, top * ms / us - height
end

-- MinimapCluster inherits Blizzard's screen clamp. Its requested anchor can
-- be accepted while the visible map still stops short of the screen edge.
local function verifyClusterPosition(state)
    local cluster, map = state.cluster, state.map
    local current = pointOf(cluster)
    if not current then return end
    if not samePoint(current, state.clusterOwned) then
        state.positionSkipped = true
        return
    end
    local right, top = mapOffsets(map)
    if not right or not top then return end
    local dx, dy = state.targetRight - right, state.targetTop - top
    if math.abs(dx) < 1 and math.abs(dy) < 1 then
        state.positionReady = true
        return
    end
    -- Screen coordinates may remain stale for a frame after SetPoint. Do not
    -- repeatedly apply the same correction while waiting for layout to settle.
    if state.mapAdjusted then return end
    local ok, clamped = pcall(cluster.IsClampedToScreen, cluster)
    if not ok or not readable(clamped) or clamped ~= true then return end
    local point = pointOf(map)
    if not samePoint(point, {state.point, state.relative, state.relativePoint, state.shiftedX, state.shiftedY}) then
        state.positionSkipped = true
        return
    end
    local scalesOK, ms, us = pcall(function() return map:GetEffectiveScale(), UIParent:GetEffectiveScale() end)
    if not scalesOK or not readable(ms) or not readable(us)
        or type(ms) ~= "number" or type(us) ~= "number" or ms == 0 then return end
    local nextX, nextY = state.shiftedX + dx * us / ms, state.shiftedY + dy * us / ms
    local moved = pcall(function()
        map:ClearAllPoints()
        map:SetPoint(state.point, state.relative, state.relativePoint, nextX, nextY)
    end)
    if moved then
        local actual = pointOf(map)
        if actual and actual[1] == state.point and actual[2] == state.relative and actual[3] == state.relativePoint then
            state.shiftedX, state.shiftedY = actual[4], actual[5]
            state.mapAdjusted = true
        else
            state.positionSkipped = true
        end
    else
        pcall(function()
            map:ClearAllPoints()
            map:SetPoint(state.point, state.relative, state.relativePoint, state.shiftedX, state.shiftedY)
        end)
    end
end

-- Move the native cluster as a unit so zone text and time follow the map.
-- Saved positions from the general frame mover take precedence over defaults.
local function positionCluster(state)
    if state.positionReady or state.positionSkipped or state.positionExhausted or moving then return end
    if state.clusterOwned then verifyClusterPosition(state); return end
    local cluster = _G.MinimapCluster
    if not cluster or type(cluster.GetNumPoints) ~= "function" or type(cluster.GetPoint) ~= "function"
        or type(cluster.GetEffectiveScale) ~= "function" or type(cluster.ClearAllPoints) ~= "function"
        or type(cluster.SetPoint) ~= "function" then return end
    local ok, count = pcall(cluster.GetNumPoints, cluster)
    local original = pointOf(cluster)
    if not ok or count ~= 1 or not original then return end
    if state.cluster and (state.cluster ~= cluster or not samePoint(state.clusterOriginal, original)) then
        -- An external layout change owns the position now.
        state.positionSkipped = true
        return
    end
    state.cluster, state.clusterOriginal = cluster, state.clusterOriginal or original
    local saved = character and character.squareMapPosition
    local old = TigerioForeverToolboxDB and TigerioForeverToolboxDB.framePositions
    local guid = identity()
    if saved == nil and type(old) == "table" and guid and type(old[guid]) == "table" and old[guid].MinimapCluster then
        state.positionSkipped = true
        return
    end
    local right, top = -8, -28
    if saved ~= nil then
        if type(saved) ~= "table" or type(saved.right) ~= "number" or type(saved.top) ~= "number"
            or saved.right ~= saved.right or saved.top ~= saved.top or math.abs(saved.right) == math.huge
            or math.abs(saved.top) == math.huge then state.positionSkipped = true; return end
        right, top = saved.right, saved.top
    end
    local currentRight, currentTop = mapOffsets(state.map)
    local scalesOK, cs, us = pcall(function() return cluster:GetEffectiveScale(), UIParent:GetEffectiveScale() end)
    if not currentRight or not currentTop or not scalesOK or not readable(cs) or not readable(us)
        or type(cs) ~= "number" or type(us) ~= "number" or cs == 0 then return end
    local x = original[4] + (right - currentRight) * us / cs
    local y = original[5] + (top - currentTop) * us / cs
    local wanted = {original[1], original[2], original[3], x, y}
    local moved = pcall(function() cluster:ClearAllPoints(); cluster:SetPoint(unpack(wanted)) end)
    local actual = pointOf(cluster)
    local clampOK, clamped = pcall(cluster.IsClampedToScreen, cluster)
    if moved and actual and (samePoint(actual, wanted) or (clampOK and readable(clamped) and clamped == true)) then
        state.clusterOwned, state.targetRight, state.targetTop = actual, right, top
    elseif not actual then
        pcall(function() cluster:ClearAllPoints(); cluster:SetPoint(unpack(original)) end)
    elseif not samePoint(actual, original) then
        state.positionSkipped = true
    end
end

-- The frame can exist before its on-screen bounds have been computed. Retry for
-- a short period, but never move it again after a successful or user-owned move.
local function schedulePositionRetry(state)
    if state.positionReady or state.positionSkipped or state.positionExhausted or state.retryScheduled then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end
    if (state.positionAttempts or 0) >= 30 then state.positionExhausted = true; return end
    state.retryScheduled = true
    local scheduled = pcall(C_Timer.After, 0.15, function()
        state.retryScheduled = false
        if square ~= state or not state.maskOwned or _G.GetMinimapShape ~= squareShape
            or state.positionReady or state.positionSkipped or state.positionExhausted then return end
        local entry = currentData()
        if not entry or not enabled(entry) then return end
        if combat() then pending = true; return end
        state.positionAttempts = (state.positionAttempts or 0) + 1
        positionCluster(state)
        schedulePositionRetry(state)
    end)
    if not scheduled then state.retryScheduled = false end
end

local function dragCursor()
    if type(GetCursorPosition) ~= "function" then return end
    local ok, x, y, scale = pcall(function()
        local px, py = GetCursorPosition()
        return px, py, UIParent:GetEffectiveScale()
    end)
    if ok and readable(x) and readable(y) and readable(scale)
        and type(x) == "number" and type(y) == "number" and type(scale) == "number" and scale > 0 then
        return x / scale, y / scale
    end
end

-- A clamped cluster may stop before its inset map reaches the screen edge.
-- Only compensate when the user actually drags beyond that stopped position.
local function finishEdgeDrag(move, right, top)
    local state, cluster, map = move.state, move.cluster, move.state.map
    if combat() or not right or not top or not move.cursorX or not move.cursorY
        or not move.mapRight or not move.mapTop then return right, top end
    local x, y = dragCursor()
    if not x or not y then return right, top end
    local ok, clamped, cr, ct, cs, ms, us, width, height = pcall(function()
        return cluster:IsClampedToScreen(), cluster:GetRight(), cluster:GetTop(), cluster:GetEffectiveScale(),
            map:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if not ok or not readable(clamped) or clamped ~= true or not readable(cr) or not readable(ct)
        or not readable(cs) or not readable(ms) or not readable(us) or not readable(width) or not readable(height)
        or type(cr) ~= "number" or type(ct) ~= "number" or type(cs) ~= "number" or type(ms) ~= "number"
        or type(us) ~= "number" or type(width) ~= "number" or type(height) ~= "number" or ms <= 0 or us <= 0 then
        return right, top
    end
    local dx, dy = 0, 0
    local wantedRight = math.min(0, move.mapRight + x - move.cursorX)
    local wantedTop = math.min(0, move.mapTop + y - move.cursorY)
    if cr * cs / us >= width - 1 and wantedRight > right + 1 then dx = wantedRight - right end
    if ct * cs / us >= height - 1 and wantedTop > top + 1 then dy = wantedTop - top end
    if dx == 0 and dy == 0 then return right, top end
    local point = pointOf(map)
    local owned = {state.point, state.relative, state.relativePoint, state.shiftedX, state.shiftedY}
    if not samePoint(point, owned) then return right, top end
    local wanted = {state.point, state.relative, state.relativePoint,
        state.shiftedX + dx * us / ms, state.shiftedY + dy * us / ms}
    local moved = pcall(function() map:ClearAllPoints(); map:SetPoint(unpack(wanted)) end)
    local actual = pointOf(map)
    if moved and samePoint(actual, wanted) then
        state.shiftedX, state.shiftedY = actual[4], actual[5]
        -- Geometry can update a frame later. Persist the known anchor delta.
        return right + dx, top + dy
    end
    if not actual then pcall(function() map:ClearAllPoints(); map:SetPoint(unpack(owned)) end) end
    return right, top
end

local function finishMove()
    local move = moving
    if not move then return end
    moving = nil
    local state, cluster = move.state, move.cluster
    local ok = pcall(cluster.StopMovingOrSizing, cluster)
    if ok and square == state then
        local right, top = mapOffsets(state.map)
        right, top = finishEdgeDrag(move, right, top)
        local entry = currentData()
        if entry and right and top then pcall(function() entry.squareMapPosition = {right = right, top = top} end) end
        state.clusterOwned = pointOf(cluster)
    end
    if move.userPlaced ~= nil and type(cluster.SetUserPlaced) == "function" then pcall(cluster.SetUserPlaced, cluster, move.userPlaced) end
    if move.movable == false and type(cluster.SetMovable) == "function" then pcall(cluster.SetMovable, cluster, false) end
end

local function setupDrag(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
    h:SetHeight(12)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function()
        local state = square
        local cluster = state and state.cluster
        if combat() or not cluster or type(cluster.SetMovable) ~= "function" or type(cluster.StartMoving) ~= "function" then return end
        local movable = type(cluster.IsMovable) == "function" and cluster:IsMovable()
        local userPlaced = type(cluster.IsUserPlaced) == "function" and cluster:IsUserPlaced()
        local cursorX, cursorY = dragCursor()
        local mapRight, mapTop = mapOffsets(state.map)
        local ok = pcall(function() cluster:SetMovable(true); cluster:StartMoving() end)
        if ok then
            moving = {state = state, cluster = cluster, movable = movable, userPlaced = userPlaced,
                cursorX = cursorX, cursorY = cursorY, mapRight = mapRight, mapTop = mapTop}
            state.positionSkipped = true -- Never override a manual drag with a pending retry.
        elseif movable == false then pcall(cluster.SetMovable, cluster, false) end
    end)
    h:SetScript("OnDragStop", finishMove)
    h:SetScript("OnHide", finishMove)
    h:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("拖动小地图"); GameTooltip:Show() end
    end)
    h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    dragHandle = h
end

-- Minimap has no mask getter. Only take over the usual native round map;
-- if another addon already provides a shape, leave it under that addon's control.
local function restoreSquare()
    local state = square
    if not state then return end
    finishMove()
    square = nil
    if _G.GetMinimapShape == squareShape then _G.GetMinimapShape = state.previousShape end
    if state.maskOwned then
        state.writing = true
        pcall(state.map.SetMaskTexture, state.map, DEFAULT_MASK)
        state.writing = false
    end
    local ok, width, height = pcall(state.map.GetSize, state.map)
    if ok and readable(width) and readable(height) and width == state.width and height == state.height then
        pcall(state.map.SetSize, state.map, state.originalWidth, state.originalHeight)
    end
    local pointOK, point, relative, relativePoint, x, y = pcall(state.map.GetPoint, state.map, 1)
    if pointOK and point == state.point and relative == state.relative and relativePoint == state.relativePoint
        and x == state.shiftedX and y == state.shiftedY then
        pcall(function()
            state.map:ClearAllPoints()
            state.map:SetPoint(state.point, state.relative, state.relativePoint, state.originalX, state.originalY)
        end)
    end
    if state.cluster and samePoint(pointOf(state.cluster), state.clusterOwned) and state.clusterOriginal then
        pcall(function()
            state.cluster:ClearAllPoints()
            state.cluster:SetPoint(unpack(state.clusterOriginal))
        end)
    end
end

local function applySquare(map)
    if square and square.map == map then
        if square.maskOwned and _G.GetMinimapShape == squareShape then
            positionCluster(square)
            schedulePositionRetry(square)
            return true
        end
        local nativeReset = externalMasks[map] == DEFAULT_MASK and _G.GetMinimapShape == nil
        restoreSquare()
        if not nativeReset then return false end
    end
    if square then restoreSquare() end
    if (externalMasks[map] and externalMasks[map] ~= DEFAULT_MASK)
        or _G.GetMinimapShape ~= nil or type(hooksecurefunc) ~= "function"
        or type(map.GetSize) ~= "function" or type(map.SetSize) ~= "function"
        or type(map.GetPoint) ~= "function" or type(map.GetNumPoints) ~= "function"
        or type(map.ClearAllPoints) ~= "function" or type(map.SetPoint) ~= "function"
        or type(map.SetMaskTexture) ~= "function" then return false end
    local gotSize, width, height = pcall(map.GetSize, map)
    if not gotSize or not readable(width) or not readable(height)
        or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0 or math.abs(width - height) > 1 then return false end
    local countOK, count = pcall(map.GetNumPoints, map)
    local pointOK, point, relative, relativePoint, x, y = pcall(map.GetPoint, map, 1)
    if not countOK or not readable(count) or count ~= 1 or not pointOK
        or not readable(point) or not readable(relative) or not readable(relativePoint)
        or not readable(x) or not readable(y) or type(point) ~= "string" or not relative
        or type(relativePoint) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return false end
    if not hookedMaps[map] then
        local hooked = pcall(hooksecurefunc, map, "SetMaskTexture", function(changed, mask)
            local state = square
            if state and state.map == changed and not state.writing then
                -- Do not undo a newer change from the client or another addon.
                externalMasks[changed] = mask
                state.maskOwned = false
                if _G.GetMinimapShape == squareShape then _G.GetMinimapShape = state.previousShape end
                pending = true
            end
        end)
        if not hooked then return false end
        hookedMaps[map] = true
    end
    local size = math.floor(math.max(width, height) * 1.3 + 0.5)
    local state = {map = map, originalWidth = width, originalHeight = height,
        width = size, height = size, previousShape = _G.GetMinimapShape, writing = true,
        point = point, relative = relative, relativePoint = relativePoint, originalX = x, originalY = y,
        shiftedX = x - (size - width) / 2, shiftedY = y - (size - height) / 2}
    square = state
    local ok = pcall(function()
        map:SetSize(size, size)
        map:ClearAllPoints()
        map:SetPoint(point, relative, relativePoint, state.shiftedX, state.shiftedY)
        state.maskOwned = true
        map:SetMaskTexture(SQUARE_MASK)
        _G.GetMinimapShape = squareShape
    end)
    state.writing = false
    if not ok then restoreSquare(); return false end
    positionCluster(state)
    schedulePositionRetry(state)
    return true
end

local function restoreBorders()
    for texture, original in pairs(borders) do
        local ok, alpha = pcall(texture.GetAlpha, texture)
        if ok and readable(alpha) and alpha == 0 then
            pcall(texture.SetAlpha, texture, original)
        end
        borders[texture] = nil
    end
end

local function hideBorders()
    for _, name in ipairs({"MinimapCompassTexture", "MinimapCompassTextureUnderlay"}) do
        local texture = _G[name]
        if texture then
            local ok, alpha = pcall(texture.GetAlpha, texture)
            if not ok or not readable(alpha) or type(alpha) ~= "number" then
                restoreBorders()
                return false
            end
            if alpha ~= 0 then
                borders[texture] = alpha
                if not pcall(texture.SetAlpha, texture, 0) then
                    restoreBorders()
                    return false
                end
            end
        end
    end
    return true
end

local function applyStyle(wantEnabled)
    if combat() then pending = true; return false, "脱战后生效" end
    if not wantEnabled then
        restoreSquare()
        restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        if overlay then
            local ok = pcall(overlay.Hide, overlay)
            if not ok then pending = true; return false, "小地图样式暂无法关闭" end
        end
        pending = false
        return true
    end
    local map = _G.Minimap
    if not mapUsable(map) then
        restoreSquare()
        if overlay then pcall(overlay.Hide, overlay) end
        restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        pending = true
        return false, "小地图暂不可用"
    end
    if overlay and overlayMap ~= map then
        restoreSquare()
        local ok = pcall(overlay.Hide, overlay)
        if not ok then pending = true; return false, "小地图样式暂不可用" end
        restoreBorders()
        overlay, overlayMap = nil, nil
    end
    if not overlay then
        local candidate
        local created, frame = pcall(function()
            local f = CreateFrame("Frame", nil, map)
            candidate = f
            f:Hide()
            f:EnableMouse(false)
            f:SetAllPoints(map)
            f:SetFrameLevel(map:GetFrameLevel() + 5)
            local function edge(point1, relative1, point2, relative2, x1, y1, x2, y2)
                local line = f:CreateTexture(nil, "OVERLAY")
                line:SetColorTexture(0.67, 0.43, 0.19, 1)
                line:SetPoint(point1, f, relative1, x1, y1)
                line:SetPoint(point2, f, relative2, x2, y2)
            end
            edge("TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", -3, 3, 3, 1)
            edge("TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", -3, -1, 3, -3)
            edge("TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", -3, 1, -1, -1)
            edge("TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, 1, 3, -1)
            setupDrag(f)
            return f
        end)
        if not created or not frame then
            if candidate then pcall(candidate.Hide, candidate) end
            pending = true
            return false, "小地图样式暂不可用"
        end
        overlay, overlayMap = frame, map
    end
    if not applySquare(map) then
        pcall(overlay.Hide, overlay)
        restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        pending = true
        return false, "小地图样式由其他界面管理或暂不可用"
    end
    if not hideBorders() then
        restoreSquare()
        pcall(overlay.Hide, overlay)
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        pending = true
        return false, "小地图边框暂不可用"
    end
    local ok = pcall(overlay.Show, overlay)
    if not ok then
        restoreSquare(); restoreBorders()
        if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(false) end
        pending = true
        return false, "小地图样式暂不可用"
    end
    if type(toolbox.setMapButtonsCollapsed) == "function" then toolbox.setMapButtonsCollapsed(true) end
    pending = false
    return true
end

function toolbox.getMapStyleEnabled()
    local entry, err = currentData()
    if not entry then return nil, err end
    return enabled(entry)
end

function toolbox.setMapStyleEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if combat() then return false, "请在脱战后调整小地图" end
    local entry, err = currentData()
    if not entry then return false, err end
    local ok, why = applyStyle(value)
    if not ok then return false, why end
    local saved = pcall(function() entry.mapStyle = value end)
    if not saved then
        applyStyle(enabled(entry))
        return false, "小地图设置暂不可保存"
    end
    notify()
    return true
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ADDON_LOADED", "CVAR_UPDATE"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        finishMove()
        if dragHandle then dragHandle:Hide() end
        return
    elseif event == "PLAYER_REGEN_ENABLED" and dragHandle then
        dragHandle:Show()
    end
    if event == "PLAYER_LOGIN" then
        if initialize() then applyStyle(enabled(character)) end
        notify()
    elseif character and (pending or event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED") then
        local entry = currentData()
        if entry then applyStyle(enabled(entry)) end
    end
end)
