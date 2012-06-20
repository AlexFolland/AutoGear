--AutoGear

-- to do:
-- accomodate for unique-equipped
-- fix equipping right when receiving
-- for every slot, attempt to put only the best item on, rather than all of the better ones at once
-- choose quest loot rewards
-- save info between sessions
-- roll need on mounts that the character doesn't have
-- add weights for weapon speed and damage
-- make gem weights have level tiers

local reason
local futureAction = {}
local weighting --gear stat weighting
local tUpdate = 0

--an invisible tooltip that AutoGear can scan for various information
local tooltipFrame = CreateFrame("GameTooltip", "AutoGearTooltip", UIParent, "GameTooltipTemplate");

--the main frame
mainF = CreateFrame("Frame", nil, UIParent)
mainF:SetWidth(1); mainF:SetHeight(1)
mainF:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
mainF:SetScript("OnUpdate", function()
    main()
end)

function GetTicks() return GetTime() * 1000 end

mainF:RegisterEvent("ADDON_LOADED")
mainF:RegisterEvent("PARTY_INVITE_REQUEST")
mainF:RegisterEvent("START_LOOT_ROLL")
mainF:RegisterEvent("CONFIRM_LOOT_ROLL")
mainF:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
mainF:RegisterEvent("ITEM_PUSH")
mainF:RegisterEvent("EQUIP_BIND_CONFIRM")
mainF:RegisterEvent("MERCHANT_SHOW")
--mainF:RegisterEvent("LOOT_BIND_CONFIRM") --only from looting, not rolling on loot
mainF:RegisterEvent("QUEST_ACCEPTED")        --Fires when a new quest is added to the player's quest log (which is what happens after a player accepts a quest).
mainF:RegisterEvent("QUEST_ACCEPT_CONFIRM")    --Fires when certain kinds of quests (e.g. NPC escort quests) are started by another member of the player's group
mainF:RegisterEvent("QUEST_COMPLETE")        --Fires when the player is looking at the "Complete" page for a quest, at a questgiver.
mainF:RegisterEvent("QUEST_DETAIL")            --Fires when details of an available quest are presented by a questgiver
mainF:RegisterEvent("QUEST_FINISHED")        --Fires when the player ends interaction with a questgiver or ends a stage of the questgiver dialog
mainF:RegisterEvent("QUEST_GREETING")        --Fires when a questgiver presents a greeting along with a list of active or available quests
mainF:RegisterEvent("QUEST_ITEM_UPDATE")    --Fires when information about items in a questgiver dialog is updated
mainF:RegisterEvent("QUEST_LOG_UPDATE")        --Fires when the game client receives updates relating to the player's quest log (this event is not just related to the quests inside it)
mainF:RegisterEvent("QUEST_POI_UPDATE")        --This event is not yet documented
mainF:RegisterEvent("QUEST_PROGRESS")        --Fires when interacting with a questgiver about an active quest
mainF:RegisterEvent("QUEST_QUERY_COMPLETE")    --Fires when quest completion information is available from the server
mainF:RegisterEvent("QUEST_WATCH_UPDATE")    --Fires when the player's status regarding a quest's objectives changes, for instance picking up a required object or killing a mob for that quest. All forms of (quest objective) progress changes will trigger this event.
mainF:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, ...)
    if (event == "ADDON_LOADED" and arg1 == "AutoGear") then
        if (not AutoGearDB) then AutoGearDB = {} end
        -- create the stat weights
        -- supported stats are:
        --[[
            Strength, Agility, Stamina, Intellect, Spirit,
            Armor, DodgeRating, ParryRating, BlockRating,
            SpellPower, SpellPenetration, HasteRating, Mp5,
            AttackPower, ArmorPenetration, CritRating, HitRating, ExpertiseRating,
            RedSockets, YellowSockets, BlueSockets, MetaSockets,
            MasteryRating,
            HealingProc, DamageProc, DamageSpellProc, MeleeProc, RangedProc (multipliers)
            
            weighting = {Strength = 0, Agility = 0, Stamina = 0, Intellect = 0, Spirit = 0,
                         Armor = 0, DodgeRating = 0, ParryRating = 0, BlockRating = 0,
                         SpellPower = 0, SpellPenetration = 0, HasteRating = 0, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, CritRating = 0, HitRating = 0, ExpertiseRating = 0,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         MasteryRating = 0}
        ]]
        -- wait for player information
        while (not UnitClass("player")) do
        end
        -- create the stat weights
        SetStatWeights()
    elseif (event == "PARTY_INVITE_REQUEST") then
        print("AutoGear:  Automatically accepting party invite.")
        AcceptGroup()
        mainF:RegisterEvent("PARTY_MEMBERS_CHANGED")
    elseif (event == "PARTY_MEMBERS_CHANGED") then --for closing the invite window once I have joined the group
        StaticPopup_Hide("PARTY_INVITE")
        mainF:UnregisterEvent("PARTY_MEMBERS_CHANGED")
    elseif (event == "START_LOOT_ROLL") then
        if (not weighting) then SetStatWeights() end
        if (weighting) then
            local roll = nil
            reason = "(no reason set)"
            local rollItemInfo = ReadItemInfo(nil,arg1)
            local better, replaceSlot, rollItemScore, equippedItemScore = DetermineIfBetter(rollItemInfo, weighting)
            local _, _, _, _, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(arg1);
            if (better and canNeed) then roll = 1 else roll = 2 end
            if (better and not canNeed) then
                print("AutoGear:  I would roll NEED, but NEED is not an option for this item.")
            end
            if (rollItemScore) then print("AutoGear:  Roll item's score: "..rollItemScore) end
            if (equippedItemScore) then print("AutoGear:  Equipped item's score: "..equippedItemScore) end
            print("AutoGear:  Slot: "..(rollItemInfo.Slot or "none"))
            if (rollItemInfo.Usable) then print("AutoGear:  This item can be worn.") else print("AutoGear:  This item cannot be worn.  "..reason) end
            if (roll == 1) then
                print("AutoGear:  Rolling NEED on this item to replace "..(replaceSlot or "nil")..".")
            elseif (roll == 2) then
                local extra, extra2
                if (replaceItem) then extra = ", to not replace my "..replaceSlot else extra = "" end
                if (GetAllBagsNumFreeSlots() == 0) then extra2 = ", even though my bags are full" else extra2 = "" end
                print("AutoGear:  Rolling GREED on this item"..extra..extra2..".")
            else
                print("AutoGear:  I don't know what I would roll on this item.")
            end
            if (roll) then
                local newAction = {}
                newAction.action = "roll"
                if (roll == 1) then
                    newAction.t = GetTicks() + math.random(1500,2000)
                else
                    newAction.t = GetTicks() + math.random(1000,1500)
                end
                newAction.rollID = arg1
                newAction.rollType = roll
                table.insert(futureAction, newAction)
            end
        else
            print("AutoGear:  No weighting set for this class.")
        end
    elseif (event == "CONFIRM_LOOT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "CONFIRM_DISENCHANT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "ITEM_PUSH") then
        --print("AutoGear:  Received an item.  Checking for gear upgrades.")
        ScanBags()
    elseif (event == "EQUIP_BIND_CONFIRM") then
        EquipPendingItem(arg1)
    elseif (event == "MERCHANT_SHOW") then
        -- sell all grey items
        local soldSomething = nil
        local totalSellValue = 0
        for i = 0, NUM_BAG_SLOTS do
            slotMax = GetContainerNumSlots(i)
            for j = 0, slotMax do
                _, count, locked, quality, _, _, link = GetContainerItemInfo(i, j)
                if (link) then
                    local name = select(3, string.find(link, "^.*%[(.*)%].*$"))
                    if (string.find(link,"|cff9d9d9d") and not locked and not IsQuestItem(i,j)) then
                        totalSellValue = totalSellValue + select(11, GetItemInfo(link)) * count
                        PickupContainerItem(i, j)
                        PickupMerchantItem()
                        soldSomething = 1
                    end
                end
            end
        end
        if (soldSomething) then
            print("AutoGear:  Sold all grey items for "..CashToString(totalSellValue)..".")
        end
        if (GetRepairAllCost() > 0 and GetRepairAllCost() <= GetMoney()) then
            print("AutoGear:  Repaired all items for "..CashToString(GetRepairAllCost())..".")
            RepairAllItems()
        elseif (GetRepairAllCost() > GetMoney()) then
            print("AutoGear:  Not enough money to repair all items ("..CashToString(GetRepairAllCost())..").")
        end
    elseif (event == "QUEST_DETAIL") then
        AcceptQuest()
    elseif (not event == "ADDON_LOADED") then
        print("AutoGear:  "..event)
    end
end)

function SetStatWeights()
    local class
    _,class = UnitClass("player")
    if (class == "PALADIN") then
        weighting = {Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = -0.2,
                     Armor = 0.05, DodgeRating = 0.8, ParryRating = 0.75, BlockRating = 0.8, SpellPower = 0.05,
                     AttackPower = 0.4, HasteRating = 0.5, ArmorPenetration = 0.1,
                     CritRating = 0.25, HitRating = 0, ExpertiseRating = 0.2, MasteryRating = 0.05,
                     RedSockets = 40, YellowSockets = 35, BlueSockets = 40, MetaSockets = 50,
                     MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0}
    elseif (class == "PRIEST") then
        if (GetSpec() == "Discipline") then                
            weighting = {Intellect = 1, Spirit = 1,
                         Armor = 0.0001, SpellPower = 0.8,
                         HasteRating = 1,
                         CritRating = 0.25, MasteryRating = 0.5,
                         RedSockets = 30, YellowSockets = 30, BlueSockets = 30, MetaSockets = 40,
                         HealingProc = 1.0, DamageSpellProc = 0.5, DamageProc = 0.5}
        end
    elseif (class == "DRUID") then
        if (GetSpec() == "Balance") then        
            --slapped together; not necessarily completely accurate
            weighting = {Intellect = 1, Spirit = 0.1,
                         SpellPower = 0.8, SpellPenetration = 0.1, HasteRating = 0.8, Mp5 = 0.01,
                         CritRating = 0.4, HitRating = 0.05,
                         RedSockets = 30, YellowSockets = 30, BlueSockets = 25, MetaSockets = 40,
                         MasteryRating = 0.6,
                         DamageSpellProc = 1.0, DamageProc = 1.0}
        end
    else
        weighting = nil
    end
end

-- from Attrition addon
function CashToString(cash)
    if not cash then return "" end

    local gold   = floor(cash / (100 * 100))
    local silver = math.fmod(floor(cash / 100), 100)
    local copper = math.fmod(floor(cash), 100)
    gold         = gold   > 0 and "|cffeeeeee"..gold  .."|r|cffffd700g|r" or ""
    silver       = silver > 0 and "|cffeeeeee"..silver.."|r|cffc7c7cfs|r" or ""
    copper       = copper > 0 and "|cffeeeeee"..copper.."|r|cffeda55fc|r" or ""
    copper       = (silver ~= "" and copper ~= "") and " "..copper or copper
    silver       = (gold   ~= "" and silver ~= "") and " "..silver or silver

    return gold..silver..copper
end

function IsQuestItem(container, slot)
    return ItemContainsText(container, slot, "Quest Item")
end

function ItemContainsText(container, slot, search)
    AutoGearTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    AutoGearTooltip:ClearLines()
    AutoGearTooltip:SetBagItem(container, slot)
    for i=1, AutoGearTooltip:NumLines() do
        local mytext = getglobal("AutoGearTooltipTextLeft" .. i)
        if (mytext) then
            local text = mytext:GetText()
            if (text == search) then
                return 1
            end
        end
    end
    return nil
end


function ScanBags()
    if (not weighting) then
        return nil
    end
    local info
    local replaceInfo
    local anythingBetter = nil
    for bag = 0, NUM_BAG_SLOTS do
        local slotMax = GetContainerNumSlots(bag)
        for i = 0, slotMax do
            _,_,_,_,_,_, link = GetContainerItemInfo(bag, i)
            if (link) then
                info = ReadItemInfo(nil,nil,bag,i)
                local better, replaceSlot, newScore, oldScore = DetermineIfBetter(info, weighting)
                if (replaceSlot) then
                    replaceInfo = ReadItemInfo(GetInventorySlotInfo(replaceSlot))
                end
                if (replaceInfo and not replaceInfo.Name) then
                    replaceInfo.Name = "nothing"
                elseif (not replaceInfo) then
                    replaceInfo = {}
                    replaceInfo.Name = "nothing"
                    oldScore = 0
                end
                if (better) then
                    print("AutoGear:  "..info.Name.." ("..string.format("%.2f", newScore)..") was determined to be better than "..replaceInfo.Name.." ("..string.format("%.2f", oldScore)..").  Will equip it soon.")
                    PrintItem(replaceInfo)
                    PrintItem(info)
                    anythingBetter = 1
                    local newAction = {}
                    newAction.action = "equip"
                    newAction.t = GetTicks() + 0.5 --do it after a short delay
                    newAction.container = bag
                    newAction.slot = i
                    newAction.replaceSlot = replaceSlot
                    newAction.info = info
                    local id = GetInventoryItemID("player", GetInventorySlotInfo("MainHandSlot"))
                    local mainHandType, _
                    if (id) then
                        _, _, _, _, _, _, _, _, mainHandType = GetItemInfo(id)
                    end
                    if (info.Slot == "SecondaryHandSlot" and mainHandType and string.find(mainHandType:lower(), "2h")) then
                        newAction.removeMainHandFirst = 1
                    end
                    table.insert(futureAction, newAction)
                end
            end
        end
    end
    return anythingBetter
end

function PrintItem(info)
    print("AutoGear:      "..info.Name..":")
    for k,v in pairs(info) do
        if (k ~= "Name" and weighting[k]) then
            print("AutoGear:          "..k..": "..string.format("%.2f", v).." * "..weighting[k].." = "..string.format("%.2f", v * weighting[k]))
        end
    end
end

function ReadItemInfo(inventoryID, lootRollItemID, container, slot)
    local info = {}
    local cannotUse = nil
    AutoGearTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    AutoGearTooltip:ClearLines()
    if (inventoryID) then
        AutoGearTooltip:SetInventoryItem("player", inventoryID)
    elseif (lootRollItemID) then
        AutoGearTooltip:SetLootRollItem(lootRollItemID)
    elseif (container and slot) then
        AutoGearTooltip:SetBagItem(container, slot)
    end
    info.RedSockets = 0
    info.YellowSockets = 0
    info.BlueSockets = 0
    info.MetaSockets = 0
    spec = GetSpec()
    for i=1, AutoGearTooltip:NumLines() do
        local mytext = getglobal("AutoGearTooltipTextLeft"..i)
        if (mytext) then
            local r, g, b, a = mytext:GetTextColor()
            local text = mytext:GetText():lower()
            if (i==1) then info.Name = mytext:GetText() end
            local multiplier = 1.0
            if (string.find(text, "chance to")) then multiplier = multiplier/3.0 end
            if (string.find(text, "use:")) then multiplier = multiplier/6.0 end
            -- don't count greyed out set bonus lines
            if (r < 0.5 and g < 0.5 and b < 0.5 and string.find(text, "set:")) then multiplier = 0 end
            -- note: these proc checks may not be correct for all cases
            if (string.find(text, "deal damage")) then multiplier = multiplier * (weighting.DamageProc or 0) end
            if (string.find(text, "damage and healing")) then multiplier = multiplier * math.max((weighting.HealingProc or 0), (weighting.DamageProc or 0))
            elseif (string.find(text, "healing spells")) then multiplier = multiplier * (weighting.HealingProc or 0)
            elseif (string.find(text, "damage spells")) then multiplier = multiplier * (weighting.DamageSpellProc or 0)
            end
            if (string.find(text, "melee and ranged")) then multiplier = multiplier * math.max((weighting.MeleeProc or 0), (weighting.RangedProc or 0))
            elseif (string.find(text, "melee attacks")) then multiplier = multiplier * (weighting.MeleeProc or 0)
            elseif (string.find(text, "ranged attacks")) then multiplier = multiplier * (weighting.RangedProc or 0)
            end
            local value = 0
            _,_,value = string.find(text, "(%d+)")
            if (value) then
                value = value * multiplier
            else
                value = 0
            end
            if (string.find(text, "strength")) then info.Strength = (info.Strength or 0) + value end
            if (string.find(text, "agility")) then info.Agility = (info.Agility or 0) + value end
            if (string.find(text, "intellect")) then info.Intellect = (info.Intellect or 0) + value end
            if (string.find(text, "stamina")) then info.Stamina = (info.Stamina or 0) + value end
            if (string.find(text, "spirit")) then info.Spirit = (info.Spirit or 0) + value end
            if (string.find(text, "armor") and
               (not string.find(text, "penetration"))) then info.Armor = (info.Armor or 0) + value end
            if (string.find(text, "attack power")) then info.AttackPower = (info.AttackPower or 0) + value end
            if (string.find(text, "armor penetration")) then info.SpellPenetration = (info.SpellPenetration or 0) + value end
            if (string.find(text, "spell power") or 
                string.find(text, "frost spell damage") and spec=="Frost" or
                string.find(text, "fire spell damage") and spec=="Fire" or
                string.find(text, "arcane spell damage") and spec=="Arcane" or
                string.find(text, "nature spell damage") and spec=="Balance") then info.SpellPower = (info.SpellPower or 0) + value end
            if (string.find(text, "critical strike rating")) then info.CritRating = (info.CritRating or 0) + value end
            if (string.find(text, "hit rating")) then info.HitRating = (info.HitRating or 0) + value end
            if (string.find(text, "haste rating")) then info.HasteRating = (info.HasteRating or 0) + value end
            if (string.find(text, "mana per 5")) then info.Mp5 = (info.Mp5 or 0) + value end
            if (string.find(text, "meta socket")) then info.MetaSockets = info.MetaSockets + 1 end
            if (string.find(text, "red socket")) then info.RedSockets = info.RedSockets + 1 end
            if (string.find(text, "yellow socket")) then info.YellowSockets = info.YellowSockets + 1 end
            if (string.find(text, "blue socket")) then info.BlueSockets = info.BlueSockets + 1 end
            if (string.find(text, "dodge rating")) then info.DodgeRating = (info.DodgeRating or 0) + value end
            if (string.find(text, "parry rating")) then info.ParryRating = (info.ParryRating or 0) + value end
            if (string.find(text, "block rating")) then info.BlockRating = (info.BlockRating or 0) + value end
            if (string.find(text, "mastery rating")) then info.MasteryRating = (info.MasteryRating or 0) + value end
            if (string.find(text, "expertise rating")) then info.ExpertiseRating = (info.ExpertiseRating or 0) + value end
            
            if (text=="head") then info.Slot = "HeadSlot" end
            if (text=="neck") then info.Slot = "NeckSlot" end
            if (text=="shoulder") then info.Slot = "ShoulderSlot" end
            if (text=="back") then info.Slot = "BackSlot" end
            if (text=="chest") then info.Slot = "ChestSlot" end
            if (text=="shirt") then info.Slot = "ShirtSlot" end
            if (text=="tabard") then info.Slot = "TabardSlot" end
            if (text=="wrist") then info.Slot = "WristSlot" end
            if (text=="hands") then info.Slot = "HandsSlot" end
            if (text=="waist") then info.Slot = "WaistSlot" end
            if (text=="legs") then info.Slot = "LegsSlot" end
            if (text=="feet") then info.Slot = "FeetSlot" end
            if (text=="finger") then info.Slot = "Finger0Slot" end
            if (text=="trinket") then info.Slot = "Trinket0Slot" end
            if (text=="main hand") then info.Slot = "MainHandSlot" end
            if (text=="two-hand") then info.Slot = "MainHandSlot"; info.IncludeOffHand=1 end
            if (text=="held in off-hand") then info.Slot = "SecondaryHandSlot" end
            if (text=="off hand") then info.Slot = "SecondaryHandSlot" end
            if (text=="one-hand") then
                info.Slot = "MainHandSlot"
                if GetSpellInfo("Dual Wielding") then
                    info.Slot = "SecondaryHandSlot"
                    -- TO DO: add logic so this will work for either slot, maybe like this:
                    --info.Slot2 = "SecondaryHandSlot"
                end
            end
            if (text=="ranged" or text=="relic") then info.Slot = "RangedSlot" end
            
            --check for being a pattern or the like
            if (string.find(text, "pattern:")) then cannotUse = 1 end
            if (string.find(text, "plans:")) then cannotUse = 1 end
            
            --check for red text
            local r, g, b, a = mytext:GetTextColor()
            if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and mytext:GetText()) then --this is red text
                reason = "(found red text on the left.  color: "..string.format("%0.2f", r)..", "..string.format("%0.2f", g)..", "..string.format("%0.2f", b).."  text: ''"..(mytext:GetText() or "nil").."'')"
                cannotUse = 1
            end
        end
        
        --check for red text on the right side
        rightText = getglobal("AutoGearTooltipTextRight"..i)
        if (rightText) then
            local r, g, b, a = rightText:GetTextColor()
            if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and rightText:GetText()) then --this is red text
                reason = "(found red text on the right.  color: "..string.format("%0.2f", r)..", "..string.format("%0.2f", g)..", "..string.format("%0.2f", b).."  text: ''"..(rightText:GetText() or "nil").."'')"
                cannotUse = 1
            end
        end
    end
    if (info.RedSockets == 0) then info.RedSockets = nil end
    if (info.YellowSockets == 0) then info.YellowSockets = nil end
    if (info.BlueSockets == 0) then info.BlueSockets = nil end
    if (info.MetaSockets == 0) then info.MetaSockets = nil end
    if (not cannotUse and info.Slot) then
        info.Usable=1
    elseif (not info.Slot) then 
        reason = "(info.Slot was nil)"
    end
    return info
end

function DetermineIfBetter(newItemInfo, weighting)
    local newItemScore = DetermineItemScore(newItemInfo, weighting)
    local id = GetInventoryItemID("player", GetInventorySlotInfo("MainHandSlot"))
    local mainHandType, _
    if (id) then
        _, _, _, _, _, _, _, _, mainHandType = GetItemInfo(id)
    end
    local equippedItemScore
    if (newItemInfo.Usable) then
        if (string.find(newItemInfo.Slot:lower(), "trinket")) then
            local trinket0Score = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("Trinket0Slot")), weighting)
            local trinket1Score = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("Trinket1Slot")), weighting)
            if (trinket0Score < trinket1Score) then
                replaceSlot = "Trinket0Slot"
                equippedItemScore = trinket0Score
            else
                replaceSlot = "Trinket1Slot"
                equippedItemScore = trinket1Score
            end
        elseif (string.find(newItemInfo.Slot:lower(), "finger")) then
            local finger0Score = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("Finger0Slot")), weighting)
            local finger1Score = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("Finger1Slot")), weighting)
            if (finger0Score < finger1Score) then
                replaceSlot = "Finger0Slot"
                equippedItemScore = finger0Score
            else
                replaceSlot = "Finger1Slot"
                equippedItemScore = finger1Score
            end
        elseif (newItemInfo.IncludeOffHand) then
            local mainHandScore = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("MainHandSlot")), weighting)
            local offHandScore = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("SecondaryHandSlot")), weighting)
            equippedItemScore = mainHandScore + offHandScore
            replaceSlot = "MainHandSlot"
        -- check if the new item is an offhand and a 2-hander is equipped
        elseif (newItemInfo.Slot=="SecondaryHandSlot" and mainHandType and string.find(mainHandType:lower(), "2h")) then
            --take only half(?) of the 2-hander's score
            equippedItemScore = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo("MainHandSlot")), weighting) / 2
        elseif (newItemInfo.Slot) then
            equippedItemScore = DetermineItemScore(ReadItemInfo(GetInventorySlotInfo(newItemInfo.Slot)), weighting)
            replaceSlot = newItemInfo.Slot
        end
        if (newItemScore > equippedItemScore) then
            return 1, replaceSlot, newItemScore, equippedItemScore
        else
            return nil, nil, newItemScore, equippedItemScore
        end
    else
        return nil, nil, newItemScore, nil
    end
end

function DetermineItemScore(itemInfo, weighting)
    return (weighting.Strength or 0) * (itemInfo.Strength or 0) +
        (weighting.Agility or 0) * (itemInfo.Agility or 0) +
        (weighting.Stamina or 0) * (itemInfo.Stamina or 0) +
        (weighting.Intellect or 0) * (itemInfo.Intellect or 0) +
        (weighting.Spirit or 0) * (itemInfo.Spirit or 0) +
        (weighting.Armor or 0) * (itemInfo.Armor or 0) +
        (weighting.DodgeRating or 0) * (itemInfo.DodgeRating or 0) +
        (weighting.ParryRating or 0) * (itemInfo.ParryRating or 0) +
        (weighting.BlockRating or 0) * (itemInfo.BlockRating or 0) +
        (weighting.SpellPower or 0) * (itemInfo.SpellPower or 0) +
        (weighting.SpellPenetration or 0) * (itemInfo.SpellPenetration or 0) +
        (weighting.HasteRating or 0) * (itemInfo.HasteRating or 0) +
        (weighting.Mp5 or 0) * (itemInfo.Mp5 or 0) +
        (weighting.AttackPower or 0) * (itemInfo.AttackPower or 0) +
        (weighting.ArmorPenetration or 0) * (itemInfo.ArmorPenetration or 0) +
        (weighting.CritRating or 0) * (itemInfo.CritRating or 0) +
        (weighting.HitRating or 0) * (itemInfo.HitRating or 0) +
        (weighting.RedSockets or 0) * (itemInfo.RedSockets or 0) +
        (weighting.YellowSockets or 0) * (itemInfo.YellowSockets or 0) +
        (weighting.BlueSockets or 0) * (itemInfo.BlueSockets or 0) +
        (weighting.MetaSockets or 0) * (itemInfo.MetaSockets or 0) +
        (weighting.ExpertiseRating or 0) * (itemInfo.ExpertiseRating or 0) +
        (weighting.MasteryRating or 0) * (itemInfo.MasteryRating or 0)
end

function GetAllBagsNumFreeSlots()
    local slotCount = 0
    for i = 0, NUM_BAG_SLOTS do
        local freeSlots, bagType = GetContainerNumFreeSlots(i)
        if (bagType == 0) then
            slotCount = slotCount + freeSlots
        end
    end
    return slotCount
end

function GetSpec()
    local highestTalents = 0
    local spec = "Untalented"
    specNumbers = ""
    for i = 1, GetNumTalentTabs() do
        _, tabName, _, _, numTalents = GetTalentTabInfo(i)
        if (numTalents > highestTalents) then
            highestTalents = numTalents
            spec = tabName
        end
    end
    return spec
end

function PutItemInEmptyBagSlot()
    for i = 0, NUM_BAG_SLOTS do
        local freeSlots, bagType = GetContainerNumFreeSlots(i)
        if (bagType == 0 and freeSlots > 0) then
            if (i == 0) then
                PutItemInBackpack()
            else
                PutItemInBag(24-i)
            end
        end
    end
end

_G["SLASH_AutoGear1"] = "/AutoGear";
_G["SLASH_AutoGear2"] = "/autogear";
_G["SLASH_AutoGear3"] = "/ag";
SlashCmdList["AutoGear"] = function(msg)
    param1, param2, param3 = msg:match("([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*")
    if (not param1) then param1 = "(nil)" end
    if (not param2) then param2 = "(nil)" end
    if (not param3) then param3 = "(nil)" end
    if (param1 == "scan") then
        if (not weighting) then SetStatWeights() end
        if (not weighting) then
            print("AutoGear:  No weighting set for this class.")
            return
        end
        print("AutoGear:  Scanning bags for upgrades.")
        anythingBetter = ScanBags()
        if not anythingBetter then print ("AutoGear:  Nothing better was found.") end
    else
        print("AutoGear:  Unrecognized command.  Use '/ag scan' to scan all bags.")
    end
end

function main()
    if (GetTicks() - tUpdate > 50) then
        tUpdate = GetTicks()
    
        --future actions
        for i, curAction in ipairs(futureAction) do
            if (curAction.action == "roll") then
                if (GetTicks() > curAction.t) then
                    if (curAction.rollType == 1) then
                        print ("AutoGear:  Rolling NEED.")
                    elseif (curAction.rollType == 2) then
                        print ("AutoGear:  Rolling GREED.")
                    end
                    RollOnLoot(curAction.rollID, curAction.rollType)
                    table.remove(futureAction, i)
                end
            elseif (curAction.action == "equip" and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")) then
                if (GetTicks() > curAction.t) then
                    if (not curAction.messageAlready) then
                        print("AutoGear:  Attempting to equip "..curAction.info.Name..".")
                        curAction.messageAlready = 1
                    end
                    if (curAction.removeMainHandFirst) then
                        if (GetAllBagsNumFreeSlots() > 0) then
                            print("AutoGear:  Attempting to remove the 2-hander to equip the offhand")
                            PickupInventoryItem(GetInventorySlotInfo("MainHandSlot"))
                            PutItemInEmptyBagSlot()
                            curAction.removeMainHandFirst = nil
                            curAction.waitingOnEmptyMainHand = 1
                        else
                            print("AutoGear:  Cannot equip the offhand because bags are too full to remove the 2-hander")
                            table.remove(futureAction, i)
                        end
                    elseif (curAction.waitingOnEmptyMainHand and GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
                    elseif (curAction.waitingOnEmptyMainHand and not GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
                        print("AutoGear:  Mainhand detected to be clear.  Equipping now.")
                        curAction.waitingOnEmptyMainHand = nil
                    else
                        PickupContainerItem(curAction.container, curAction.slot)
                        EquipCursorItem(GetInventorySlotInfo(curAction.replaceSlot))
                        table.remove(futureAction, i)
                    end
                end
            end
        end
    end
end