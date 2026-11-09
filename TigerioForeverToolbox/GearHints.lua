local _, toolbox = ...

-- Compare only known equipment locations. Ambiguous weapon setups are skipped.
local armorSlots = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10, INVTYPE_CLOAK = 15,
}
local pairedSlots = {INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}}
local weaponSlots = {
    INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_2HWEAPON = 16, INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18,
    INVTYPE_THROWN = 18, INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17,
}
local driver = CreateFrame("Frame")
local loggedIn, pending = false, nil

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

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

local function itemData(link)
    if type(C_Item.GetItemInfo) ~= "function" then return nil end
    local ok, name, _, _, _, _, _, _, _, equipLoc, icon, _, classID, subclassID = pcall(C_Item.GetItemInfo, link)
    if not ok or not readable(name) or not readable(equipLoc) or not readable(icon)
        or not readable(classID) or not readable(subclassID) or type(name) ~= "string"
        or type(equipLoc) ~= "string" then return nil end
    local level = call(C_Item.GetDetailedItemLevelInfo, link)
    if type(level) ~= "number" or level <= 0 then return nil end
    return {level = level, equipLoc = equipLoc, icon = icon, classID = classID, subclassID = subclassID}
end

local function definitelyNotUnique(link)
    if type(C_Item.GetItemUniquenessByID) ~= "function" then return false end
    local ok, unique, category, count, categoryID = pcall(C_Item.GetItemUniquenessByID, link)
    return ok and readable(unique) and readable(category) and readable(count) and readable(categoryID)
        and unique == false and (category == nil or category == "")
        and (count == nil or count == 0) and (categoryID == nil or categoryID == 0)
end

local function equippedData(slot)
    local link = call(GetInventoryItemLink, "player", slot)
    if type(link) ~= "string" then return nil end
    return itemData(link)
end

local function betterSlot(link, item)
    local loc = item.equipLoc
    local directSlot = armorSlots[loc]
    if directSlot then
        local current = equippedData(directSlot)
        if current and item.level > current.level then return directSlot, item.level - current.level end
        return nil
    end
    local pair = pairedSlots[loc]
    if pair then
        -- Unique-equipped restrictions and a vacant comparison slot are deliberately excluded.
        if not definitelyNotUnique(link) then return nil end
        local first, second = equippedData(pair[1]), equippedData(pair[2])
        if not first or not second then return nil end
        local slot, current = pair[1], first
        if second.level < first.level then slot, current = pair[2], second end
        if item.level > current.level then return slot, item.level - current.level end
        return nil
    end
    local slot = weaponSlots[loc]
    if not slot then return nil end
    if loc == "INVTYPE_2HWEAPON" then
        if type(GetInventoryItemID) ~= "function" then return nil end
        local ok, offhand = pcall(GetInventoryItemID, "player", 17)
        if not ok or not readable(offhand) or offhand ~= nil then return nil end
    end
    local current = equippedData(slot)
    if not current or type(item.classID) ~= "number" or type(item.subclassID) ~= "number"
        or current.classID ~= item.classID or current.subclassID ~= item.subclassID
        or current.equipLoc ~= loc then return nil end
    if item.level > current.level then return slot, item.level - current.level end
end

local function scan()
    if not loggedIn or inCombat() then return end
    local candidates = {}
    if not C_Container or not C_Item or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemInfo) ~= "function"
        or type(C_Item.GetDetailedItemLevelInfo) ~= "function"
        or type(C_Item.IsUsableItem) ~= "function" or type(C_Item.IsEquippableItem) ~= "function" then
        if type(toolbox.updateGearCandidates) == "function" then toolbox.updateGearCandidates(candidates) end
        return
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local size = call(C_Container.GetContainerNumSlots, bag)
        if type(size) == "number" then
            for bagSlot = 1, size do
                local info = call(C_Container.GetContainerItemInfo, bag, bagSlot)
                if type(info) == "table" and (not canaccesstable or canaccesstable(info)) then
                    local link, itemID = info.hyperlink, info.itemID
                    if readable(link) and readable(itemID) and type(link) == "string" and type(itemID) == "number"
                        and readable(info.isLocked) and not info.isLocked then
                        local item = itemData(link)
                        if not item then
                            if type(C_Item.RequestLoadItemDataByID) == "function" then pcall(C_Item.RequestLoadItemDataByID, itemID) end
                        elseif call(C_Item.IsEquippableItem, link) == true and call(C_Item.IsUsableItem, link) == true then
                            local slot, difference = betterSlot(link, item)
                            if slot then
                                local icon = readable(info.iconFileID) and info.iconFileID or item.icon
                                candidates[#candidates + 1] = {link = link, bag = bag, bagSlot = bagSlot,
                                    itemID = itemID, inventorySlot = slot, difference = difference,
                                    icon = icon, equipLoc = item.equipLoc}
                            end
                        end
                    elseif readable(itemID) and type(itemID) == "number" and type(C_Item.RequestLoadItemDataByID) == "function" then
                        pcall(C_Item.RequestLoadItemDataByID, itemID)
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.difference ~= b.difference then return a.difference > b.difference end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.bagSlot < b.bagSlot
    end)
    if type(toolbox.updateGearCandidates) == "function" then toolbox.updateGearCandidates(candidates) end
end

local function schedule()
    if not loggedIn then return end
    if not inCombat() and type(toolbox.invalidateGearCandidates) == "function" then
        toolbox.invalidateGearCandidates()
    end
    pending = 0.5
end

for _, event in ipairs({"PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_LOCK_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "ADDON_LOADED"}) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then loggedIn = true end
    schedule()
end)
driver:SetScript("OnUpdate", function(_, delta)
    if not pending or inCombat() then return end
    pending = pending - delta
    if pending <= 0 then pending = nil; scan() end
end)

-- Allows the candidate window to request fresh data when it is opened.
toolbox.refreshGearCandidates = schedule
