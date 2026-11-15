-- Profession progress is read from the current client; reference is guidance only.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, initialized, dirty, delay, pendingNotice = nil, false, false, 0, false
local lastNotice = {}

local categories = {
    [186] = "gathering", [182] = "gathering", [393] = "gathering",
    [171] = "crafting", [164] = "crafting", [333] = "crafting",
    [202] = "crafting", [165] = "crafting", [197] = "crafting",
    [185] = "secondary", [129] = "secondary", [356] = "secondary",
}

local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function knownString(value)
    return readable(value) and type(value) == "string" and value ~= "" and value or nil
end

local function inCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not readable(value) or (value ~= nil and value ~= false)
end

local function initialize()
    local db = TigerioForeverToolboxDB
    if type(db) ~= "table" or type(UnitGUID) ~= "function" then return false end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or not readable(guid) or type(guid) ~= "string" or not guid:match("^Player%-") then return false end
    if db.professionProgress == nil then db.professionProgress = {version = 1, characters = {}} end
    local root = db.professionProgress
    if type(root) ~= "table" or root.version ~= 1 or type(root.characters) ~= "table" then return false end
    if root.characters[guid] == nil then root.characters[guid] = {} end
    local current = root.characters[guid]
    if type(current) ~= "table" or (current.remindersEnabled ~= nil and type(current.remindersEnabled) ~= "boolean") then return false end
    character, initialized = current, true
    return true
end

local function remindersEnabled()
    if not initialized or not character then return nil end
    local value = character.remindersEnabled
    if value == nil then return true end
    if type(value) == "boolean" then return value end
end

local function professionData()
    local result = {available = false, professions = {}, remindersEnabled = remindersEnabled()}
    if type(UnitLevel) == "function" then
        local ok, level = pcall(UnitLevel, "player")
        if ok and finite(level) and level > 0 and level == math.floor(level) then
            result.level, result.reference = level, level * 5
        end
    end
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return result end
    -- The six values are sparse: e.g. only fishing can occupy a later slot.
    local values = {pcall(GetProfessions)}
    if values[1] ~= true then return result end
    local available = true
    for position = 2, 7 do
        local index = values[position]
        if not readable(index) then
            available = false
        elseif index ~= nil then
            if not finite(index) or index <= 0 or index ~= math.floor(index) then
                available = false
            else
                local ok, name, icon, skill, maximum, _, _, skillID, modifier = pcall(GetProfessionInfo, index)
                if not ok then
                    available = false
                else
                    local entry = {
                        name = knownString(name),
                        icon = readable(icon) and (type(icon) == "number" or type(icon) == "string") and icon or nil,
                        skill = finite(skill) and skill >= 0 and skill or nil,
                        max = finite(maximum) and maximum > 0 and maximum or nil,
                        skillID = finite(skillID) and skillID > 0 and skillID or nil,
                        modifier = finite(modifier) and modifier or nil,
                    }
                    entry.category = entry.skillID and categories[entry.skillID] or "unknown"
                    if not entry.category then entry.category = "unknown" end
                    if not entry.name or not entry.skill or not entry.max then available = false end
                    if entry.skill and entry.max then
                        if entry.skill >= entry.max then entry.advancement = "已达上限"
                        elseif entry.max - entry.skill <= 10 then entry.advancement = "接近上限"
                        else
                            -- These are reference thresholds, not proof that the
                            -- next rank is available (level, quests and trainer vary).
                            local threshold = ({[75] = 50, [150] = 125, [225] = 200})[entry.max]
                            if threshold and entry.skill >= threshold then entry.advancement = "查看升阶条件" end
                        end
                    end
                    result.professions[#result.professions + 1] = entry
                end
            end
        end
    end
    result.available = available
    return result
end

function toolbox.getProfessionProgress()
    return professionData()
end

function toolbox.setProfessionRemindersEnabled(value)
    if type(value) ~= "boolean" then return false, "设置无效" end
    if not initialized and not initialize() then return false, "角色数据暂不可用" end
    character.remindersEnabled = value
    if not value then lastNotice = {}; pendingNotice = false end
    if value then dirty, delay = true, 0 end
    if type(toolbox.onProfessionProgressChanged) == "function" then pcall(toolbox.onProfessionProgressChanged) end
    return true
end

local function report(data)
    if data.remindersEnabled ~= true then return end
    if inCombat() then pendingNotice = true; return end
    pendingNotice = false
    local current = {}
    for _, entry in ipairs(data.professions) do
        if (entry.category == "gathering" or entry.category == "crafting")
            and entry.skillID and entry.name and entry.skill and entry.max then
            local warning = entry.advancement ~= "查看升阶条件" and entry.advancement or nil
            if not warning and data.reference and entry.skill + 25 <= data.reference
                and entry.skill < data.reference * 0.75 then warning = "低于参考进度" end
            local key = tostring(entry.skillID)
            current[key] = warning
            if warning and lastNotice[key] ~= warning and type(print) == "function" then
                local name = entry.name:gsub("|", "||"):gsub("[\r\n]", " ")
                print("|cffffd100升级工具箱|r " .. name .. " " .. warning .. " " .. entry.skill .. "/" .. entry.max)
            end
        end
    end
    lastNotice = current
end

local function refresh()
    if not initialized then initialize() end
    local data = professionData()
    if data.available then report(data) end
    if type(toolbox.onProfessionProgressChanged) == "function" then pcall(toolbox.onProfessionProgressChanged) end
end

for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "SPELLS_CHANGED", "TRADE_SKILL_LIST_UPDATE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then initialize() end
    if event == "PLAYER_REGEN_ENABLED" and not pendingNotice then return end
    dirty, delay = true, 0
end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not dirty or not finite(elapsed) then return end
    delay = delay + elapsed
    if delay >= 0.25 then dirty, delay = false, 0; refresh() end
end)
