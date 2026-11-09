-- Optional merchant conveniences. Only the current character's settings are stored.
local _, toolbox = ...
local driver = CreateFrame("Frame")
local character, merchantOpen, generation = nil, false, 0

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

local function identity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, "player")
    if ok and readable(value) and type(value) == "string" and value:match("^Player%-") then return value end
end

local function initialize()
    character = nil
    local db, guid = TigerioForeverToolboxDB, identity()
    if not tableOK(db) or not guid then return false end
    local data, ok = field(db, "merchant")
    if not ok then return false end
    if data == nil then
        data = {version = 1, characters = {}}
        if not pcall(function() db.merchant = data end) then return false end
    end
    if not tableOK(data) or field(data, "version") ~= 1 then return false end
    local entries = field(data, "characters")
    if not tableOK(entries) then return false end
    local entry, entryOK = field(entries, guid)
    if not entryOK then return false end
    if entry == nil then
        entry = {sellJunk = false, autoRepair = false}
        if not pcall(function() entries[guid] = entry end) then return false end
    end
    if not tableOK(entry) then return false end
    local sell, sellOK = field(entry, "sellJunk")
    local repair, repairOK = field(entry, "autoRepair")
    if not sellOK or not repairOK or (sell ~= nil and type(sell) ~= "boolean")
        or (repair ~= nil and type(repair) ~= "boolean") then return false end
    character = entry
    return true
end

local function current()
    local db, guid = TigerioForeverToolboxDB, identity()
    if not character or not guid or not tableOK(db) then return false end
    local data = field(db, "merchant")
    local entries = field(data, "characters")
    return tableOK(data) and field(data, "version") == 1 and tableOK(entries)
        and field(entries, guid) == character
end

local function notify()
    if type(toolbox.onGlobalUIChanged) == "function" then pcall(toolbox.onGlobalUIChanged) end
end

function toolbox.getMerchantOptions()
    if not current() then return nil, "商人设置不可用" end
    local sell, sellOK = field(character, "sellJunk")
    local repair, repairOK = field(character, "autoRepair")
    if not sellOK or not repairOK or (sell ~= nil and type(sell) ~= "boolean")
        or (repair ~= nil and type(repair) ~= "boolean") then return nil, "商人设置不可用" end
    return {sellJunk = sell == true, autoRepair = repair == true}
end

function toolbox.setMerchantOption(key, value)
    if (key ~= "sellJunk" and key ~= "autoRepair") or type(value) ~= "boolean" then return false, "设置无效" end
    if not current() then return false, "商人设置不可用" end
    if not pcall(function() character[key] = value end) then return false, "商人设置无法保存" end
    -- Disabling an option cancels any remaining queued sales immediately.
    if key == "sellJunk" and not value then generation = generation + 1 end
    notify()
    return true
end

local function available(session)
    if not merchantOpen or session ~= generation or not current() then return false end
    local frame = _G.MerchantFrame
    if not readable(frame) or not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and readable(shown) and shown == true
end

local function cursorClear()
    if type(GetCursorInfo) ~= "function" or type(SpellIsTargeting) ~= "function" then return false end
    local ok, cursor = pcall(GetCursorInfo)
    local spellOK, targeting = pcall(SpellIsTargeting)
    return ok and readable(cursor) and cursor == nil and spellOK and readable(targeting) and not targeting
end

local function bagAllowsJunk(bag)
    if not C_Container then return false end
    local ok, excluded
    if bag == 0 then
        if type(C_Container.GetBackpackSellJunkDisabled) ~= "function" then return false end
        ok, excluded = pcall(C_Container.GetBackpackSellJunkDisabled)
    else
        local flag = field(field(Enum, "BagSlotFlags"), "ExcludeJunkSell")
        if not readable(flag) or type(flag) ~= "number" or type(C_Container.GetBagSlotFlag) ~= "function" then return false end
        ok, excluded = pcall(C_Container.GetBagSlotFlag, bag, flag)
    end
    return ok and readable(excluded) and excluded == false
end

-- Every condition must be known: never infer junk from missing or protected data.
local function inspect(bag, slot)
    local container, item = C_Container, C_Item
    if not container or not item or not ItemLocation
        or type(container.GetContainerItemInfo) ~= "function"
        or type(container.GetContainerItemQuestInfo) ~= "function"
        or type(container.GetContainerItemEquipmentSetInfo) ~= "function"
        or type(container.IsBattlePayItem) ~= "function"
        or type(item.CanBeRefunded) ~= "function" or type(item.GetItemGUID) ~= "function"
        or type(ItemLocation.CreateFromBagAndSlot) ~= "function" then return end
    if not bagAllowsJunk(bag) then return end
    local ok, info = pcall(container.GetContainerItemInfo, bag, slot)
    if not ok or not tableOK(info) then return end
    local quality, qOK = field(info, "quality")
    local locked, lOK = field(info, "isLocked")
    local loot, lootOK = field(info, "hasLoot")
    local readableItem, readableOK = field(info, "isReadable")
    local noValue, vOK = field(info, "hasNoValue")
    local id, idOK = field(info, "itemID")
    local count, countOK = field(info, "stackCount")
    if not (qOK and idOK and countOK) or type(id) ~= "number" or id <= 0
        or type(count) ~= "number" or count <= 0 then return end
    local locOK, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if not locOK or not readable(location) or not location then return end
    local guidOK, guid = pcall(item.GetItemGUID, location)
    if not guidOK or not readable(guid) or type(guid) ~= "string" or guid == "" then return end
    local identity = {bag = bag, slot = slot, id = id, count = count, guid = guid}
    -- Missing quality can be an item cache miss. Only retry the exact same item.
    if quality == nil then return nil, identity end
    if not (lOK and lootOK and readableOK and vOK)
        or quality ~= 0 or locked ~= false or loot ~= false or readableItem ~= false
        or noValue ~= false then return end
    local questOK, quest = pcall(container.GetContainerItemQuestInfo, bag, slot)
    if not questOK or not tableOK(quest) then return end
    local isQuest, iqOK = field(quest, "isQuestItem")
    local questID, qidOK = field(quest, "questID")
    if not iqOK or not qidOK or isQuest ~= false or questID ~= nil then return end
    local setOK, inSet = pcall(container.GetContainerItemEquipmentSetInfo, bag, slot)
    if not setOK or not readable(inSet) or inSet ~= false then return end
    local battleOK, battleItem = pcall(container.IsBattlePayItem, bag, slot)
    if not battleOK or not readable(battleItem) or battleItem ~= false then return end
    local refundOK, refundable = pcall(item.CanBeRefunded, location)
    if not refundOK or not readable(refundable) or refundable ~= false then return end
    return identity
end

local function repair(session)
    if not available(session) or field(character, "autoRepair") ~= true then return end
    if type(CanMerchantRepair) ~= "function" or type(GetRepairAllCost) ~= "function"
        or type(GetMoney) ~= "function" or type(RepairAllItems) ~= "function" then return end
    local ok, can = pcall(CanMerchantRepair)
    if not ok or not readable(can) or can ~= true then return end
    local costOK, cost, canRepair = pcall(GetRepairAllCost)
    local moneyOK, money = pcall(GetMoney)
    if not costOK or not moneyOK or not readable(cost) or not readable(canRepair) or not readable(money)
        or canRepair ~= true or type(cost) ~= "number" or cost <= 0
        or type(money) ~= "number" or money < cost then return end
    -- false explicitly selects the player's gold, never guild funds.
    pcall(RepairAllItems, false)
end

local function beginSales(session)
    if not available(session) or field(character, "sellJunk") ~= true or not cursorClear() then return end
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.UseContainerItem) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function" then return end
    local lastBag = NUM_BAG_SLOTS
    if not readable(lastBag) or type(lastBag) ~= "number" or lastBag < 0 or lastBag > 10 then return end
    local queue = {}
    local bags = {}
    for bag = 0, lastBag do bags[#bags + 1] = bag end
    local reagent = field(field(Enum, "BagIndex"), "ReagentBag")
    if readable(reagent) and type(reagent) == "number" and reagent == math.floor(reagent)
        and reagent > lastBag and reagent <= 10 then
        bags[#bags + 1] = reagent
    end
    for _, bag in ipairs(bags) do
        local ok, size = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and readable(size) and type(size) == "number" and size >= 0 and size <= 200 then
            for slot = 1, size do
                local entry, pending = inspect(bag, slot)
                entry = entry or pending
                if entry then
                    entry.retries = 0
                    queue[#queue + 1] = entry
                    if pending and type(C_Item.RequestLoadItemDataByID) == "function" then
                        pcall(C_Item.RequestLoadItemDataByID, pending.id)
                    end
                end
            end
        end
    end
    local index = 1
    local function nextSale()
        if not available(session) or field(character, "sellJunk") ~= true or not cursorClear() then return end
        local old = queue[index]
        if not old then return end
        local now, pending = inspect(old.bag, old.slot)
        if now and now.guid == old.guid and now.id == old.id and now.count == old.count then
            if not pcall(C_Container.UseContainerItem, old.bag, old.slot) then
                generation = generation + 1
                return
            end
        elseif pending and pending.guid == old.guid and pending.id == old.id and pending.count == old.count
            and old.retries < 3 then
            old.retries = old.retries + 1
            if type(C_Item.RequestLoadItemDataByID) == "function" then
                pcall(C_Item.RequestLoadItemDataByID, pending.id)
            end
            C_Timer.After(0.3, nextSale)
            return
        end
        index = index + 1
        C_Timer.After(0.25, nextSale)
    end
    nextSale()
end

for _, event in ipairs({"PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", "USE_NO_REFUND_CONFIRM", "CONFIRM_BEFORE_USE"}) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        initialize()
        notify()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        generation = generation + 1
    elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" or event == "USE_NO_REFUND_CONFIRM"
        or event == "CONFIRM_BEFORE_USE" then
        -- Never acknowledge a confirmation or continue selling behind one.
        generation = generation + 1
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        generation = generation + 1
        local session = generation
        if current() and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if not available(session) then return end
                repair(session)
                beginSales(session)
            end)
        end
    end
end)
