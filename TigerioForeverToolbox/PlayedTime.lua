-- Server-provided character /played time. Do not intercept the normal chat output.
local _, Toolbox = ...
local driver = CreateFrame("Frame")
local snapshot, pending, completed
local trackedLevel, lastRequest, quarantined
local TIMEOUT, RETRY_INTERVAL = 15, 300

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function number(value)
    if readable(value) and type(value) == "number" and value >= 0 and value < math.huge then return value end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end

local function clock()
    return number(call(GetTime))
end

local function identity()
    local guid = call(UnitGUID, "player")
    if type(guid) == "string" and guid:match("^Player%-") then return guid end
end

local function level()
    local value = number(call(UnitLevel, "player"))
    if value and value > 0 and value == math.floor(value) then return value end
end

local function changed()
    if type(Toolbox.onPlayedTimeChanged) == "function" then pcall(Toolbox.onPlayedTimeChanged) end
end

local function delta(now, started)
    if not now or not started or now < started then return nil end
    return now - started
end

-- Project a confirmed snapshot only while this exact character remains logged in.
function Toolbox.playedTimeSnapshot()
    local now, guid = clock(), identity()
    if not snapshot or not guid or guid ~= snapshot.guid then return nil, nil end
    local elapsed = delta(now, snapshot.at)
    if not elapsed then return nil, nil end
    local current = level()
    local levelSeconds
    if current and current == snapshot.level and trackedLevel == snapshot.level then
        levelSeconds = snapshot.levelSeconds + elapsed
    end
    return snapshot.totalSeconds + elapsed, levelSeconds
end

local function elapsedForUpgrade(newLevel)
    if not snapshot or snapshot.used or not readable(newLevel) or type(newLevel) ~= "number"
        or newLevel ~= snapshot.level + 1 or identity() ~= snapshot.guid then return nil end
    local elapsed = delta(clock(), snapshot.at)
    if not elapsed then return nil end
    snapshot.used = true
    return snapshot.levelSeconds + elapsed
end

-- Called by the calendar during PLAYER_LEVEL_UP, independent of event order.
function Toolbox.consumePlayedLevelElapsed(newLevel)
    if completed and readable(newLevel) and completed.level == newLevel then
        local seconds = completed.seconds
        completed = nil
        return seconds
    end
    return elapsedForUpgrade(newLevel)
end

function Toolbox.requestPlayedTime(reason)
    local now, guid, current = clock(), identity(), level()
    if quarantined or pending or not now or not guid or not current or type(RequestTimePlayed) ~= "function" then return false end
    if trackedLevel and current ~= trackedLevel then return false end
    if not trackedLevel then trackedLevel = current end
    if reason == "open" and snapshot and snapshot.guid == guid and snapshot.level == current then return false end
    if reason ~= "level" and lastRequest and now - lastRequest < RETRY_INTERVAL then return false end
    pending = {at = now, guid = guid, level = current, invalid = false}
    lastRequest = now
    local ok = pcall(RequestTimePlayed)
    if not ok then pending = nil; return false end
    return true
end

local function scheduleLevelRequest()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(1, function() Toolbox.requestPlayedTime("level") end)
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("TIME_PLAYED_MSG")
driver:SetScript("OnEvent", function(_, event, first, second)
    if event == "PLAYER_LOGIN" then
        snapshot, pending, completed = nil, nil, nil
        trackedLevel, lastRequest, quarantined = level(), nil, false
        Toolbox.requestPlayedTime("login")
        changed()
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = number(first)
        completed = nil
        if newLevel then
            local seconds = elapsedForUpgrade(newLevel)
            if seconds then completed = {level = newLevel, seconds = seconds} end
            trackedLevel = newLevel
        else
            trackedLevel = nil
        end
        if pending then pending.invalid = true end
        changed()
        scheduleLevelRequest()
    elseif event == "TIME_PLAYED_MSG" then
        if not pending then return end
        local request = pending
        pending = nil
        local now, guid, current = clock(), identity(), level()
        local total, currentLevel = number(first), number(second)
        if not request.invalid and delta(now, request.at) and guid and guid == request.guid
            and current and current == request.level and trackedLevel == request.level
            and total and currentLevel and currentLevel <= total then
            snapshot = {at = now, guid = guid, level = current, totalSeconds = total, levelSeconds = currentLevel}
            changed()
        elseif request.invalid then
            scheduleLevelRequest()
        end
    elseif event == "PLAYER_LOGOUT" then
        snapshot, pending, completed = nil, nil, nil
    end
end)

driver:SetScript("OnUpdate", function()
    local now = clock()
    if pending and now and now - pending.at > TIMEOUT then
        -- A late reply has no request ID. Do not attribute it to a later request.
        pending, quarantined = nil, true
        changed()
    end
end)
