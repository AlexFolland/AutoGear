--AutoGear

-- to do:
-- accomodate for "no item link received"
-- identify bag rolls and roll need when appropriate
-- roll need on mounts that the character doesn't have
-- identify bag rolls and roll need when appropriate
-- fix guild repairs
-- handle dual wielding 2h using titan's grip
-- make seperate stat weights for main and off hand
-- add a weight for weapon damage
-- fix weapons for rogues properly.  (dagger and any can equip dagger and shield, put slow in main hand for combat, etc)
-- remove the armor penetration weight
-- make gem weights have level tiers (70-79, 80-84, 85)
-- other non-gear it should let you roll
-- add a ui
-- add rolling on offset
-- factor in racial weapon bonuses
-- eye of arachnida slot nil error

local reason
local futureAction = {}
local weighting --gear stat weighting
local tUpdate = 0
local dataAvailable = nil
AutoAcceptQuests = AutoAcceptQuests or true

--an invisible tooltip that AutoGear can scan for various information
local tooltipFrame = CreateFrame("GameTooltip", "AutoGearTooltip", UIParent, "GameTooltipTemplate");

local weaponTypes = {dagger=1, sword=1, mace=1, shield=1, thrown=1, axe=1, bow=1, gun=1, polearm=1, staff=1, ["fist weapon"]=1, ["fishing pole"]=1, wand=1}

--the main frame
AutoGearFrame = CreateFrame("Frame", nil, UIParent)
AutoGearFrame:SetWidth(1); AutoGearFrame:SetHeight(1)
AutoGearFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
AutoGearFrame:SetScript("OnUpdate", function()
    AutoGearMain()
end)

--options menu (original template from BlizzMove; custom checkbox)
local function createOptionPanel()
    optionPanel = CreateFrame("Frame", "AutoGearPanel", UIParent)
    local title = optionPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local version = GetAddOnMetadata("AutoGear","Version") or ""
    title:SetText("AutoGear")

    local questHelpText = optionPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    questHelpText:SetHeight(35)
    questHelpText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    questHelpText:SetPoint("RIGHT", optionPanel, -32, 0)
    questHelpText:SetNonSpaceWrap(true)
    questHelpText:SetJustifyH("LEFT")
    questHelpText:SetJustifyV("TOP")

    questHelpText:SetText("AutoGear can automatically accept and complete quests, including choosing the best upgrade for your current spec.  If no upgrade is found, AutoGear will choose the most valuable reward in vendor gold.  The following checkbox sets whether AutoGear handles quests and quest-giving NPC dialog.")

    local questCheckButton = CreateFrame("CheckButton", "AutoGearQuestCheckButton", optionPanel, "OptionsCheckButtonTemplate")
    questCheckButton:SetScript("OnShow", function() AutoGearQuestCheckButton:SetChecked(AutoAcceptQuests) end)
    questCheckButton:SetScript("OnClick", function() ToggleAutoAcceptQuests() end)
    _G[questCheckButton:GetName() .. "Text"]:SetText("Automatically handle quests")
    questCheckButton:SetHitRectInsets(0, -200, 0, 0)
    questCheckButton:SetPoint("TOPLEFT", questHelpText, "BOTTOMLEFT", 0, -8)

    local scanHelpText = optionPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scanHelpText:SetHeight(35)
    scanHelpText:SetPoint("TOPLEFT", questCheckButton, "BOTTOMLEFT", 0, -16)
    scanHelpText:SetPoint("RIGHT", optionPanel, -32, 0)
    scanHelpText:SetNonSpaceWrap(true)
    scanHelpText:SetJustifyH("LEFT")
    scanHelpText:SetJustifyV("TOP")

    scanHelpText:SetText("AutoGear scans all bags for gear upgrades every time you loot gear.  Click the button below to force a scan.  Tip: By equipping your old item, you can use this to help determine how AutoGear decided an item was an upgrade.")

    local scanButton = CreateFrame("Button", nil, optionPanel, "UIPanelButtonTemplate")
    scanButton:SetWidth(100)
    scanButton:SetHeight(30)
    scanButton:SetScript("OnClick", function() Scan() end)
    scanButton:SetText("Scan")
    scanButton:SetPoint("TOPLEFT", scanHelpText, "BOTTOMLEFT", 0, -8)

    optionPanel.name = "AutoGear"
    InterfaceOptions_AddCategory(optionPanel)
end

createOptionPanel()

AutoGearFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
AutoGearFrame:RegisterEvent("ADDON_LOADED")
AutoGearFrame:RegisterEvent("PARTY_INVITE_REQUEST")
AutoGearFrame:RegisterEvent("START_LOOT_ROLL")
AutoGearFrame:RegisterEvent("CONFIRM_LOOT_ROLL")
AutoGearFrame:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
AutoGearFrame:RegisterEvent("ITEM_PUSH")
AutoGearFrame:RegisterEvent("EQUIP_BIND_CONFIRM")
AutoGearFrame:RegisterEvent("MERCHANT_SHOW")
AutoGearFrame:RegisterEvent("PLAYER_ALIVE")             --Fired when the player releases from death to a graveyard or accepts a resurrect before releasing their spirit.    
AutoGearFrame:RegisterEvent("QUEST_ACCEPTED")           --Fires when a new quest is added to the player's quest log (which is what happens after a player accepts a quest).
AutoGearFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")     --Fires when certain kinds of quests (e.g. NPC escort quests) are started by another member of the player's group
AutoGearFrame:RegisterEvent("QUEST_AUTOCOMPLETE")       --Fires when a quest is automatically completed (remote handin available)
AutoGearFrame:RegisterEvent("QUEST_COMPLETE")           --Fires when the player is looking at the "Complete" page for a quest, at a questgiver.
AutoGearFrame:RegisterEvent("QUEST_DETAIL")             --Fires when details of an available quest are presented by a questgiver
AutoGearFrame:RegisterEvent("QUEST_FINISHED")           --Fires when the player ends interaction with a questgiver or ends a stage of the questgiver dialog
AutoGearFrame:RegisterEvent("QUEST_GREETING")           --Fires when a questgiver presents a greeting along with a list of active or available quests
AutoGearFrame:RegisterEvent("QUEST_ITEM_UPDATE")        --Fires when information about items in a questgiver dialog is updated
AutoGearFrame:RegisterEvent("QUEST_LOG_UPDATE")         --Fires when the game client receives updates relating to the player's quest log (this event is not just related to the quests inside it)
AutoGearFrame:RegisterEvent("QUEST_POI_UPDATE")         --This event is not yet documented
AutoGearFrame:RegisterEvent("QUEST_PROGRESS")           --Fires when interacting with a questgiver about an active quest
AutoGearFrame:RegisterEvent("QUEST_QUERY_COMPLETE")     --Fires when quest completion information is available from the server
AutoGearFrame:RegisterEvent("QUEST_WATCH_UPDATE")       --Fires when the player's status regarding a quest's objectives changes, for instance picking up a required object or killing a mob for that quest. All forms of (quest objective) progress changes will trigger this event.
AutoGearFrame:RegisterEvent("GOSSIP_CLOSED")            --Fires when an NPC gossip interaction ends
AutoGearFrame:RegisterEvent("GOSSIP_CONFIRM")           --Fires when the player is requested to confirm a gossip choice
AutoGearFrame:RegisterEvent("GOSSIP_CONFIRM_CANCEL")    --Fires when an attempt to confirm a gossip choice is canceled
AutoGearFrame:RegisterEvent("GOSSIP_ENTER_CODE")        --Fires when the player attempts a gossip choice which requires entering a code
AutoGearFrame:RegisterEvent("GOSSIP_SHOW")              --Fires when an NPC gossip interaction begins
AutoGearFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")   --Fires when a unit's quests change (accepted/objective progress/abandoned/completed)
AutoGearFrame:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, ...)
    -- print("AutoGear: "..event)
    if (event == "ACTIVE_TALENT_GROUP_CHANGED") then
        --make sure this doesn't happen as part of logon
        if (dataAvailable) then
            print("AutoGear: Talent specialization changed.  Scanning bags for gear that's better suited for this spec.")
            ScanBags()
        end
    elseif (event == "ADDON_LOADED" and arg1 == "AutoGear") then
        if (not AutoGearDB) then AutoGearDB = {} end
    elseif (event == "PARTY_INVITE_REQUEST") then
        print("AutoGear: Automatically accepting party invite.")
        AcceptGroup()
        AutoGearFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    elseif (event == "PARTY_MEMBERS_CHANGED") then --for closing the invite window once I have joined the group
        StaticPopup_Hide("PARTY_INVITE")
        AutoGearFrame:UnregisterEvent("PARTY_MEMBERS_CHANGED")
    elseif (event == "START_LOOT_ROLL") then
        SetStatWeights()
        if (weighting) then
            local roll = nil
            reason = "(no reason set)"
            link = GetLootRollItemLink(arg1)
            local _, _, _, _, lootRollItemID, _, _, _, _, _, _, _, _, _ = string.find(link, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
            local wouldNeed = ScanBags(lootRollItemID, arg1)
            local rollItemInfo = ReadItemInfo(nil, arg1)
            local _, _, _, _, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(arg1);
            if (wouldNeed and canNeed) then roll = 1 else roll = 2 end
            if (wouldNeed and not canNeed) then
                print("AutoGear: I would roll NEED, but NEED is not an option for this item.")
            end
            if (not rollItemInfo.Usable) then print("AutoGear: This item cannot be worn.  "..reason) end
            if (roll) then
                local newAction = {}
                newAction.action = "roll"
                newAction.t = GetTime() --roll right away
                newAction.rollID = arg1
                newAction.rollType = roll
                newAction.info = rollItemInfo
                table.insert(futureAction, newAction)
            end
        else
            print("AutoGear: No weighting set for this class.")
        end
    elseif (event == "CONFIRM_LOOT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "CONFIRM_DISENCHANT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "ITEM_PUSH") then
        --print("AutoGear: Received an item.  Checking for gear upgrades.")
        --make sure a fishing pole isn't replaced while fishing
        if (GetMainHandType() ~= "Fishing Poles") then
            --check if there's already a scan action in queue
            local scanFound = nil
            for i, curAction in ipairs(futureAction) do
                if (curAction.action == "scan") then
                    --push the time ahead until all the items have arrived
                    curAction.t = GetTime() + 1.0
                    scanFound = 1
                end
            end
            if (not scanFound) then
                --no scan found, so create a new one
                local newAction = {}
                newAction.action = "scan"
                --give the item some time to arrive
                newAction.t = GetTime() + 0.5
                table.insert(futureAction, newAction)
            end
        end
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
            print("AutoGear: Sold all grey items for "..CashToString(totalSellValue)..".")
        end
        local cashString = CashToString(GetRepairAllCost())
        if (GetRepairAllCost() > 0) then
            if (CanGuildBankRepair()) then
                RepairAllItems(1) --guild repair
                --fix this.  it doesn't see 0 yet, even if it repaired
                if (GetRepairAllCost() == 0) then
                    print("AutoGear: Repaired all items for "..cashString.." using guild funds.")
                end
            end
        end
        if (GetRepairAllCost() > 0) then
            if (GetRepairAllCost() <= GetMoney()) then
                print("AutoGear: Repaired all items for "..cashString..".")
                RepairAllItems()
            elseif (GetRepairAllCost() > GetMoney()) then
                print("AutoGear: Not enough money to repair all items ("..cashString..").")
            end
        end
    elseif (event == "PLAYER_ALIVE") then
        dataAvailable = 1
    elseif (event == "QUEST_ACCEPT_CONFIRM" and AutoAcceptQuests) then --another group member starts a quest (like an escort)
        ConfirmAcceptQuest()
    elseif (event == "QUEST_DETAIL" and AutoAcceptQuests) then
        QuestDetailAcceptButton_OnClick()
    elseif (event == "GOSSIP_SHOW" and AutoAcceptQuests) then
        --active quests
        local quests = GetNumGossipActiveQuests()
        local info = {GetGossipActiveQuests()}
        for i = 0, quests - 1 do
            local name, level, isTrivial, isComplete, isLegendary = info[i*5+1], info[i*5+2], info[i*5+3], info[i*5+4], info[i*5+5]
            if (isComplete) then
                SelectGossipActiveQuest(i+1)
            end
        end
        --available quests
        quests = GetNumGossipAvailableQuests()
        info = {GetGossipAvailableQuests()}
        for i = 0, quests - 1 do
            local name, level, isTrivial, isDaily, isRepeatable = info[i*5+1], info[i*5+2], info[i*5+3], info[i*5+4], info[i*5+5]
            if (not isTrivial) then
                SelectGossipAvailableQuest(i+1)
            end
        end
    elseif (event == "QUEST_GREETING" and AutoAcceptQuests) then
        --active quests
        local quests = GetNumActiveQuests()
        for i = 1, quests do
        	local title, isComplete = GetActiveTitle(i)
        	if (isComplete) then
        		SelectActiveQuest(i)
        	end
        end
        --available quests
        quests = GetNumAvailableQuests()
        for i = 1, quests do
            local isTrivial, isDaily, isRepeatable = GetAvailableQuestInfo(i)
            if (not isTrivial) then
                SelectAvailableQuest(i)
            end
        end
    elseif (event == "QUEST_PROGRESS" and AutoAcceptQuests) then
        if (IsQuestCompletable()) then
            CompleteQuest()
        end
    elseif (event == "QUEST_COMPLETE" and AutoAcceptQuests) then
        local rewards = GetNumQuestChoices()
        if (not rewards or rewards == 0) then
            GetQuestReward()
        else
            --choose a quest reward
            questRewardID = {}
            for i = 1, rewards do
                local itemLink = GetQuestItemLink("choice", i)
                if (not itemLink) then print("AutoGear: No item link received from the server.") end
                local _, _, Color, Ltype, id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
                questRewardID[i] = id
            end
            local choice = ScanBags(nil, nil, questRewardID)
            GetQuestReward(choice)
        end
    elseif (event ~= "ADDON_LOADED") then
        --print("AutoGear: "..event)
    end
end)

-- supported stats are:
--[[
    weighting = {Strength = 0, Agility = 0, Stamina = 0, Intellect = 0, Spirit = 0,
                 Armor = 0, Dodge = 0, Parry = 0, Block = 0,
                 SpellPower = 0, SpellPenetration = 0, Haste = 0, Mp5 = 0,

                 AttackPower = 0, ArmorPenetration = 0, Crit = 0, Hit = 0, 
                 Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0, ExperienceGained = 0,
                 RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,

                 HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                 
                 DPS = 0}
]]
function SetStatWeights()
    local class, spec
    _,class = UnitClass("player")
    spec = GetSpec()
    weapons = "any"
    if (class == "DEATHKNIGHT") then
        if (spec == "None") then
            weighting = {Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
                         Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
                         Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Blood") then
            weighting = {Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
                         Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
                         Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Frost") then
            weighting = {Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.22, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
                         Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Unholy") then
            weighting = {Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
                         Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        end
    elseif (class == "DRUID") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.5,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.5, SpellPenetration = 0, Haste = 0.5, Mp5 = 0.05,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.9, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
                         DPS = 1}
        elseif (spec == "Balance") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.05, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Feral") then
            weighting = {Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
                         Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
                         Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 0.8}
        elseif (spec == "Guardian") then
            weighting = {Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
                         Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
                         Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 0.8}
        elseif (spec == "Restoration") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 0.05,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        end
    elseif (class == "HUNTER") then
        weapons = "ranged"
        if (spec == "None") then
            weighting = {Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = -0.1, Spirit = -0.1,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, Hit = 0.4, 
                         Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 0, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
                         DPS = 2}
        elseif (spec == "Beast Mastery") then
            weighting = {Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = -0.1, Spirit = -0.1,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.9, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.8, Crit = 1.1, Hit = 0.4, 
                         Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
                         DPS = 2}
        elseif (spec == "Marksmanship") then
            weighting = {Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = -0.1, Spirit = -0.1,
                         Armor = 0.005, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.61, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.66, Hit = 3.49, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Survival") then
            weighting = {Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = -0.1, Spirit = -0.1,
                         Armor = 0.005, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.33, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.37, Hit = 3.19, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        end
    elseif (class == "MAGE") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 5.16, Spirit = 0.05,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.34, Hit = 3.21, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Arcane") then
            weighting = {Strength = -0.1, Agility = -0.1, Stamina = 0.01, Intellect = 1, Spirit = 0,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.6, SpellPenetration = 0.2, Haste = 0.5, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.7, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Fire") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.8, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.2, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Frost") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.9, SpellPenetration = 0.3, Haste = 0.8, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.8, Hit = 0.7, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        end
    elseif (class == "MONK") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
                         Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 3.075}
        elseif (spec == "Brewmaster") then
            weighting = {Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
                         Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
                         Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Windwalker") then
            weighting = {Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
                         Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 3.075}
        elseif (spec == "Mistweaver") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 0.05,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 1}
        end
    elseif (class == "PALADIN") then
        if (spec == "None") then
            weighting = {Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
                         Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Holy") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 0.8, Spirit = 0.9,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.7, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Protection") then
            weapons = "weapon and shield"
            weighting = {Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = -0.2,
                         Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, SpellPower = 0.05,
                         AttackPower = 0.4, Haste = 0.5, ArmorPenetration = 0.1,
                         Crit = 0.25, Hit = 0, Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
                         DPS = 2}
        elseif (spec == "Retribution") then
            weapons = "2h"
            weighting = {Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
                         Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        end
    elseif (class == "PRIEST") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.75, SpellPenetration = 0, Haste = 2, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.6, Hit = 1.95, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Discipline") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0, Intellect = 1, Spirit = 1,
                         Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.8, SpellPenetration = 0, Haste = 1, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.25, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Holy") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 1, SpellPenetration = 0, Haste = 0.47, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.47, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Shadow") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 1, SpellPenetration = 0, Haste = 1, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0,
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        end
    elseif (class == "ROGUE") then
        weapons = "dual wield"
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
                         Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 3.075}
        elseif (spec == "Assassination") then
            weighting = {Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
                         Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Combat") then
            weighting = {Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
                         Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 3.075}
        elseif (spec == "Subtlety") then
            weapons = "dagger and any"
            weighting = {Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.5, Mp5 = 0,
                         AttackPower = 0.4, ArmorPenetration = 0, Crit = 1.1, Hit = 0.6, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 2}
        end
    elseif (class == "SHAMAN") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 1, Stamina = 0.05, Intellect = 1, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, Hit = 2.7, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Elemental") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Enhancement") then
            weapons = "dual wield"
            weighting = {Strength = 0, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.95, Mp5 = 0,
                         AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, Hit = 0.8, 
                         Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Restoration") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.65,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0.75, SpellPenetration = 0, Haste = 0.6, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        end
    elseif (class == "WARLOCK") then
        if (spec == "None") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Affliction") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Demonology") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.79, Spirit = 0.005,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.91, SpellPenetration = 0.05, Haste = 2.37, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.95, Hit = 3.74, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        elseif (spec == "Destruction") then
            weighting = {Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.3, Spirit = 0.005,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 2.62, SpellPenetration = 0.05, Haste = 2.08, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 1.4, Hit = 2.83, 
                         Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 0.01}
        end
    elseif (class == "WARRIOR") then
        if (spec == "None") then
            weighting = {Strength = 2.02, Agility = 0.01, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
                         Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Arms") then
            weapons = "2h"
            weighting = {Strength = 2.02, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
                         AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
                         Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Fury") then
            weapons = "dual wield"
            weighting = {Strength = 2.98, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
                         Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 1.37, Mp5 = 0,
                         AttackPower = 1.36, ArmorPenetration = 0, Crit = 1.98, Hit = 2.47, 
                         Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
        elseif (spec == "Protection") then
            weapons = "weapon and shield"
            weighting = {Strength = 1.2, Agility = 0, Stamina = 1.5, Intellect = 0, Spirit = 0,
                         Armor = 0.16, Dodge = 1, Parry = 1.03, Block = 0,
                         SpellPower = 0, SpellPenetration = 0, Haste = 0, Mp5 = 0,
                         AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.02, 
                         Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
                         RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
                         HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
                         DPS = 2}
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

function ScanBags(lootRollItemID, lootRollID, questRewardID)
    SetStatWeights()
    if (not weighting) then
        return nil
    end
    local anythingBetter = nil
    --create the table for best items
    best = {}
    local info, score, i, bag, slot
    --look at all equipped items and set starting best scores
    for i = 1, 18 do
        info = ReadItemInfo(i)
        score = DetermineItemScore(info, weighting)
        best[i] = {}
        best[i].info = info
        best[i].score = score
        best[i].equippedScore = score
        best[i].equipped = 1
    end
    --pretend slot 19 is a separate slot for 2-handers
    best[19] = {}
    if (IsTwoHandEquipped()) then
        best[19].info = best[16].info
        best[19].score = best[16].score
        best[19].equippedScore = best[16].equippedScore
        best[19].equipped = 1
        best[16].info = {Name = "nothing"}
        best[16].score = 0
        best[16].equipped = nil
    else
        best[19].info = {Name = "nothing"}
        best[19].score = 0
        best[19].equippedScore = best[16].equippedScore + best[17].equippedScore
        best[19].equipped = nil
    end
    --look at all items in bags
    for bag = 0, NUM_BAG_SLOTS do
        local slotMax = GetContainerNumSlots(bag)
        for slot = 0, slotMax do
            local _,_,_,_,_,_, link = GetContainerItemInfo(bag, slot)
            if (link) then
                info = ReadItemInfo(nil, nil, bag, slot)
                LookAtItem(best, info, bag, slot, nil, GetContainerItemID(bag, slot))
            end
        end
    end
    --look at item being rolled on (if any)
    if (lootRollItemID) then
        info = ReadItemInfo(nil, lootRollID)
        LookAtItem(best, info, nil, nil, 1, lootRollItemID)
    end
    --look at quest rewards (if any)
    if (questRewardID) then
        for i = 1, GetNumQuestChoices() do
            info = ReadItemInfo(nil, nil, nil, nil, i)
            LookAtItem(best, info, nil, nil, nil, questRewardID[i], i)
        end
    end
    --create all future equip actions required (only if not rolling currently)
    if (not lootRollItemID and not questRewardID) then
        for i = 1, 18 do
            if i == 16 or i == 17 then
                --skip for now
            else
                if (not best[i].equipped) then
                    equippedInfo = ReadItemInfo(i)
                    equippedScore = DetermineItemScore(equippedInfo, weighting)
                    print("AutoGear: "..(best[i].info.Name or "nothing").." ("..string.format("%.2f", best[i].score)..") was determined to be better than "..(equippedInfo.Name or "nothing").." ("..string.format("%.2f", equippedScore)..").  Equipping.")
                    PrintItem(best[i].info)
                    PrintItem(equippedInfo)
                    anythingBetter = 1
                    local newAction = {}
                    newAction.action = "equip"
                    newAction.t = GetTime()
                    newAction.container = best[i].bag
                    newAction.slot = best[i].slot
                    newAction.replaceSlot = i
                    newAction.info = best[i].info
                    table.insert(futureAction, newAction)
                end
            end
        end
        --handle main and off-hand
        if (best[16].score + best[17].score > best[19].score) then
            local extraDelay = 0
            local mainSwap, offSwap
            --main hand
            if (not best[16].equipped) then
                mainSwap = 1
                local newAction = {}
                newAction.action = "equip"
                newAction.t = GetTime()
                newAction.container = best[16].bag
                newAction.slot = best[16].slot
                newAction.replaceSlot = 16
                newAction.info = best[16].info
                table.insert(futureAction, newAction)
                extraDelay = 0.5
            end
            --off-hand
            if (not best[17].equipped) then
                offSwap = 1
                local newAction = {}
                newAction.action = "equip"
                newAction.t = GetTime() + extraDelay --do it after a longer delay
                newAction.container = best[17].bag
                newAction.slot = best[17].slot
                newAction.replaceSlot = 17
                newAction.info = best[17].info
                table.insert(futureAction, newAction)
            end
            if (mainSwap or offSwap) then
                anythingBetter = 1
                if (mainSwap and offSwap) then
                    if (IsTwoHandEquipped()) then
                        local equippedMain = ReadItemInfo(16)
                        local mainScore = DetermineItemScore(equippedMain, weighting)
                        print("AutoGear: "..(best[16].info.Name or "nothing").." ("..string.format("%.2f", best[16].score)..") combined with "..(best[17].info.Name or "nothing").." ("..string.format("%.2f", best[17].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..").  Equipping.")
                        PrintItem(best[16].info)
                        PrintItem(best[17].info)
                        PrintItem(equippedMain)
                    else
                        local equippedMain = ReadItemInfo(16)
                        local mainScore = DetermineItemScore(equippedMain, weighting)
                        local equippedOff = ReadItemInfo(17)
                        local offScore = DetermineItemScore(equippedOff, weighting)
                        print("AutoGear: "..(best[16].info.Name or "nothing").." ("..string.format("%.2f", best[16].score)..") combined with "..(best[17].info.Name or "nothing").." ("..string.format("%.2f", best[17].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.Name or "nothing").." ("..string.format("%.2f", offScore)..").  Equipping.")
                        PrintItem(best[16].info)
                        PrintItem(best[17].info)
                        PrintItem(equippedMain)
                        PrintItem(equippedOff)
                    end
                else
                    local i = 16
                    if (offSwap) then i = 17 end
                    local equippedInfo = ReadItemInfo(i)
                    local equippedScore = DetermineItemScore(equippedInfo, weighting)
                    print("AutoGear: "..(best[i].info.Name or "nothing").." ("..string.format("%.2f", best[i].score)..") was determined to be better than "..(equippedInfo.Name or "nothing").." ("..string.format("%.2f", equippedScore)..").  Equipping.")
                    PrintItem(best[i].info)
                    PrintItem(equippedInfo)
                end
            end
        else
            if (not best[19].equipped) then
                anythingBetter = 1
                local newAction = {}
                newAction.action = "equip"
                newAction.t = GetTime() + 0.5 --do it after a short delay
                newAction.container = best[19].bag
                newAction.slot = best[19].slot
                newAction.replaceSlot = 16
                newAction.info = best[19].info
                table.insert(futureAction, newAction)
                local equippedMain = ReadItemInfo(16)
                local mainScore = DetermineItemScore(equippedMain, weighting)
                local equippedOff = ReadItemInfo(17)
                local offScore = DetermineItemScore(equippedOff, weighting)
                print("AutoGear: "..(best[19].info.Name or "nothing").." ("..string.format("%.2f", best[19].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.Name or "nothing").." ("..string.format("%.2f", offScore)..").  Equipping.")
                PrintItem(best[19].info)
                PrintItem(equippedMain)
                PrintItem(equippedOff)
            end
        end
    elseif (lootRollItemID) then
        --decide whether to roll on the item or not
        if info.isMount then return 1 end
        for i = 1, 19 do
            if (best[i].rollOn) then
                return 1
            end
        end
        return nil
    else
        --choose a quest reward
        --pick the reward with the biggest score improvement
        local bestRewardIndex
        local bestRewardScoreDelta
        for i = 1, 19 do
            if (best[i].chooseReward) then
                local delta = best[i].score - best[i].equippedScore
                if (not bestRewardScoreDelta or delta > bestRewardScoreDelta) then
                    bestRewardScoreDelta = delta
                    bestRewardIndex = best[i].chooseReward
                end
            end
        end
        if (not bestRewardIndex) then
            --no gear upgrades, so choose the one with the highest sell value
            local bestRewardVendorPrice
            for i = 1, GetNumQuestChoices() do
                local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(questRewardID[i])
                if (not bestRewardVendorPrice or vendorPrice > bestRewardVendorPrice) then
                    bestRewardIndex = i
                    bestRewardVendorPrice = vendorPrice
                end
            end
        end
        return bestRewardIndex
    end
    return anythingBetter
end

--companion function to ScanBags
function LookAtItem(best, info, bag, slot, rollOn, itemID, chooseReward)
    local score, i, i2
    if (info.Usable or (rollOn and info.Within5levels)) then
        score = DetermineItemScore(info, weighting)
        if info.Slot then
            i = GetInventorySlotInfo(info.Slot)
            if (info.Slot2) then i2 = GetInventorySlotInfo(info.Slot2) end
            --ignore it if it's a tabard
            if (i == 19) then return end
            --compare to the lowest score ring, trinket, or dual wield weapon
            if (i == 11 and best[12].score < best[11].score) then i = 12 end
            if (i == 13 and best[14].score < best[13].score) then i = 14 end
            if (i2 and i == 16 and i2 == 17 and best[17].score < best[16].score) then i = 17 end
            if (i == 16 and IsItemTwoHanded(itemID)) then i = 19 end
            if (score > best[i].score) then
                best[i].info = info
                best[i].score = score
                best[i].equipped = nil
                best[i].bag = bag
                best[i].slot = slot
                best[i].rollOn = rollOn
                best[i].chooseReward = chooseReward
            end
        end
    end
end

function IsItemTwoHanded(itemID)
    if (not itemID) then return nil end
    local mainHandType = select(7, GetItemInfo(itemID))
    return mainHandType and 
        (string.find(mainHandType, "Two") or
        string.find(mainHandType, "Staves") or
        string.find(mainHandType, "Fishing Poles") or
        string.find(mainHandType, "Polearms") or
        string.find(mainHandType, "Guns") or
        string.find(mainHandType, "Bows") or
        string.find(mainHandType, "Crossbows"))
end

function IsTwoHandEquipped()
    return IsItemTwoHanded(GetInventoryItemID("player", 16)) --16 = main hand
end

function GetMainHandType()
    local id = GetInventoryItemID("player", GetInventorySlotInfo("MainHandSlot"))
    local mainHandType, _
    if (id) then
        _, _, _, _, _, _, mainHandType = GetItemInfo(id)
    end
    if mainHandType then
        return mainHandType
    else
        return ""
    end
end

function PrintItem(info)
    if (info and info.Name) then print("AutoGear:     "..info.Name..":") end
    for k,v in pairs(info) do
        if (k ~= "Name" and weighting[k]) then
            print("AutoGear:         "..k..": "..string.format("%.2f", v).." * "..weighting[k].." = "..string.format("%.2f", v * weighting[k]))
        end
    end
end

function ReadItemInfo(inventoryID, lootRollID, container, slot, questRewardIndex)
    local info = {}
    local cannotUse = nil
    AutoGearTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    AutoGearTooltip:ClearLines()
    if (inventoryID) then
        AutoGearTooltip:SetInventoryItem("player", inventoryID)
    elseif (lootRollID) then
        AutoGearTooltip:SetLootRollItem(lootRollID)
    elseif (container and slot) then
        AutoGearTooltip:SetBagItem(container, slot)
    elseif (questRewardIndex) then
        AutoGearTooltip:SetQuestItem("choice", questRewardIndex)
    end
    info.RedSockets = 0
    info.YellowSockets = 0
    info.BlueSockets = 0
    info.MetaSockets = 0
    spec = GetSpec()
    for i = 1, AutoGearTooltip:NumLines() do
        local mytext = getglobal("AutoGearTooltipTextLeft"..i)
        if (mytext) then
            local r, g, b, a = mytext:GetTextColor()
            local text = select(1,string.gsub(mytext:GetText():lower(),",",""))
            if (i==1) then info.Name = mytext:GetText() end
            local multiplier = 1.0
            if (string.find(text, "chance to")) then multiplier = multiplier/3.0 end
            if (string.find(text, "use:")) then multiplier = multiplier/6.0 end
            -- don't count greyed out set bonus lines
            if (r < 0.8 and g < 0.8 and b < 0.8 and string.find(text, "set:")) then multiplier = 0 end
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
            if (string.find(text, "unique")) then
                if (PlayerIsWearingItem(info.Name)) then
                    cannotUse = 1
                    reason = "(this item is unique and you already have one)"
                end
            end
            if (string.find(text, "already known")) then
                if (PlayerIsWearingItem(info.Name)) then
                    cannotUse = 1
                    reason = "(this item has been learned already)"
                end
            end
            if (string.find(text, "strength")) then info.Strength = (info.Strength or 0) + value end
            if (string.find(text, "agility")) then info.Agility = (info.Agility or 0) + value end
            if (string.find(text, "intellect")) then info.Intellect = (info.Intellect or 0) + value end
            if (string.find(text, "stamina")) then info.Stamina = (info.Stamina or 0) + value end
            if (string.find(text, "spirit")) then info.Spirit = (info.Spirit or 0) + value end
            if (string.find(text, "armor") and not (string.find(text, "lowers their armor"))) then info.Armor = (info.Armor or 0) + value end
            if (string.find(text, "attack power")) then info.AttackPower = (info.AttackPower or 0) + value end
            if (string.find(text, "spell power") or 
                string.find(text, "frost spell damage") and spec=="Frost" or
                string.find(text, "fire spell damage") and spec=="Fire" or
                string.find(text, "arcane spell damage") and spec=="Arcane" or
                string.find(text, "nature spell damage") and spec=="Balance") then info.SpellPower = (info.SpellPower or 0) + value end
            if (string.find(text, "critical strike")) then info.Crit = (info.Crit or 0) + value end
            if (string.find(text, "haste")) then info.Haste = (info.Haste or 0) + value end
            if (string.find(text, "mana per 5")) then info.Mp5 = (info.Mp5 or 0) + value end
            if (string.find(text, "meta socket")) then info.MetaSockets = info.MetaSockets + 1 end
            if (string.find(text, "red socket")) then info.RedSockets = info.RedSockets + 1 end
            if (string.find(text, "yellow socket")) then info.YellowSockets = info.YellowSockets + 1 end
            if (string.find(text, "blue socket")) then info.BlueSockets = info.BlueSockets + 1 end
            if (string.find(text, "dodge")) then info.Dodge = (info.Dodge or 0) + value end
            if (string.find(text, "parry")) then info.Parry = (info.Parry or 0) + value end
            if (string.find(text, "block")) then info.Block = (info.Block or 0) + value end
            if (string.find(text, "mastery")) then info.Mastery = (info.Mastery or 0) + value end
            if (string.find(text, "multistrike")) then info.Multistrike = (info.Multistrike or 0) + value end
            if (string.find(text, "versatility")) then info.Versatility = (info.Versatility or 0) + value end
            if (string.find(text, "experience gained")) then
                if (UnitLevel("player") < 100 and not IsXPUserDisabled()) then
                    info.ExperienceGained = (info.ExperienceGained or 0) + value
                end
            end
            if (string.find(text, "damage per second")) then info.DPS = (info.DPS or 0) + value end
            
            if (text=="mount") then info.isMount = 1 end
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
            if (text=="main hand") then
                local weaponType = GetWeaponType()
                if (weapons == "dagger and any" and weaponType ~= "dagger") then
                    cannotUse = 1
                    reason = "(this spec needs a dagger main hand)"
                elseif (weapons == "2h" or weapon == "ranged") then
                    cannotUse = 1
                    reason = "(this spec needs a two-hand weapon)"
                end
                info.Slot = "MainHandSlot"
            end
            if (text=="two-hand") then
                if (weapons == "weapon and shield") then
                    cannotUse = 1
                    reason = "(this spec needs weapon and shield)"
                elseif (weapons == "dual wield") then
                    cannotUse = 1
                    reason = "(this spec should dual wield)"
                elseif (weapons == "ranged") then
                    cannotUse = 1
                    reason = "(this spec should use a ranged weapon)"
                end
                info.Slot = "MainHandSlot"; info.IncludeOffHand=1
            end
            if (text=="held in off-hand") then
                if (weapons == "2h" or weapons == "dual wield" or weapons == "weapon and shield" or weapons == "ranged") then
                    cannotUse = 1
                    reason = "(this spec needs the off-hand for a weapon or shield)"
                end
                info.Slot = "SecondaryHandSlot"
            end
            if (text=="off hand") then
                if (weapons == "2h" or weapons == "ranged") then
                    cannotUse = 1
                    reason = "(this spec should use a two-hand weapon)"
                elseif (weapons == "weapon and shield" and weaponType ~= "shield") then
                    cannotUse = 1
                    reason = "(this spec needs a shield in the off-hand)"
                elseif (weapons == "dual wield" and weaponType == "shield") then
                    cannotUse = 1
                    reason = "(this spec should dual wield and not use a shield)"
                end
                info.Slot = "SecondaryHandSlot"
            end
            if (text=="one-hand") then
                if (weapons == "2h" or weapons == "ranged") then
                    cannotUse = 1
                    reason = "(this spec should use a two-hand weapon)"
                end
                if (weapons == "dagger and any" and weaponType ~= "dagger") then
                    info.Slot = "SecondaryHandSlot"
                elseif (weapons == "dual wield" or weapons == "dagger and any") then
                    info.Slot = "MainHandSlot"
                    info.Slot2 = "SecondaryHandSlot"
                else
                    info.Slot = "MainHandSlot"
                end
            end
            local _, class = UnitClass("player")
            if (text=="ranged") then
                info.Slot = "MainHandSlot"
                if (weapons ~= "ranged" and weaponType ~= "wand") then
                    cannotUse = 1
                    reason = "(this class or spec should not use a ranged 2h weapon)"
                end
            end
            
            --check for being a pattern or the like
            if (string.find(text, "pattern:")) then cannotUse = 1 end
            if (string.find(text, "plans:")) then cannotUse = 1 end
            
            --check for red text
            local r, g, b, a = mytext:GetTextColor()
            if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and mytext:GetText()) then --this is red text
                if (string.find(text, "requires level") and value - UnitLevel("player") <= 5) then
                    info.Within5levels = 1
                end
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
    if (not cannotUse and (info.Slot or info.isMount)) then
        info.Usable = 1
    elseif (not info.Slot) then 
        reason = "(info.Slot was nil)"
    end
    return info
end

function GetWeaponType()
    --this function assumes the tooltip has already been set
    --search the right text for a recognized weapon type
    for i=1, AutoGearTooltip:NumLines() do
        rightText = getglobal("AutoGearTooltipTextRight"..i)
        if (rightText and rightText:GetText()) then
            local text = rightText:GetText():lower()
            if (weaponTypes[text]) then return text end
        end
    end
end

--used for unique
function PlayerIsWearingItem(name)
    --search all worn items and the 4 top-level bag slots
    for i = 0, 23 do
        local id = GetInventoryItemID("player", i)
        if (id) then
            if GetItemInfo(id) == name then return 1 end
        end
    end
    return nil
end

function DetermineItemScore(itemInfo, weighting)
    if itemInfo.isMount then return 999999 end
    return (weighting.Strength or 0) * (itemInfo.Strength or 0) +
        (weighting.Agility or 0) * (itemInfo.Agility or 0) +
        (weighting.Stamina or 0) * (itemInfo.Stamina or 0) +
        (weighting.Intellect or 0) * (itemInfo.Intellect or 0) +
        (weighting.Spirit or 0) * (itemInfo.Spirit or 0) +
        (weighting.Armor or 0) * (itemInfo.Armor or 0) +
        (weighting.Dodge or 0) * (itemInfo.Dodge or 0) +
        (weighting.Parry or 0) * (itemInfo.Parry or 0) +
        (weighting.Block or 0) * (itemInfo.Block or 0) +
        (weighting.SpellPower or 0) * (itemInfo.SpellPower or 0) +
        (weighting.SpellPenetration or 0) * (itemInfo.SpellPenetration or 0) +
        (weighting.Haste or 0) * (itemInfo.Haste or 0) +
        (weighting.Mp5 or 0) * (itemInfo.Mp5 or 0) +
        (weighting.AttackPower or 0) * (itemInfo.AttackPower or 0) +
        (weighting.ArmorPenetration or 0) * (itemInfo.ArmorPenetration or 0) +
        (weighting.Crit or 0) * (itemInfo.Crit or 0) +
        (weighting.RedSockets or 0) * (itemInfo.RedSockets or 0) +
        (weighting.YellowSockets or 0) * (itemInfo.YellowSockets or 0) +
        (weighting.BlueSockets or 0) * (itemInfo.BlueSockets or 0) +
        (weighting.MetaSockets or 0) * (itemInfo.MetaSockets or 0) +
        (weighting.Mastery or 0) * (itemInfo.Mastery or 0) +
        (weighting.Multistrike or 0) * (itemInfo.Multistrike or 0) +
        (weighting.Versatility or 0) * (itemInfo.Versatility or 0) +
        (weighting.ExperienceGained or 0) * (itemInfo.ExperienceGained or 0) +
        (weighting.DPS or 0) * (itemInfo.DPS or 0)
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
    local currentSpec = GetSpecialization()
    local currentSpecName = currentSpec and select(2, GetSpecializationInfo(currentSpec)) or "None"
    return currentSpecName
end

function PutItemInEmptyBagSlot()
    for i = 0, NUM_BAG_SLOTS do
        local freeSlots, bagType = GetContainerNumFreeSlots(i)
        if (bagType == 0 and freeSlots > 0) then
            if (i == 0) then
                PutItemInBackpack()
            else
                PutItemInBag(23-i)
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
    if (param1 == "quest") then
        ToggleAutoAcceptQuests()
    elseif (param1 == "scan") then
        Scan()
    elseif (param1 == "spec") then
        print("AutoGear: Looks like you are "..GetSpec()..".")
    elseif (param1 == "") then
        InterfaceOptionsFrame_OpenToCategory(optionPanel)
    else
        print("AutoGear: Unrecognized command.  Recognized commands:")
        print("AutoGear:    '/ag': options menu")
        print("AutoGear:    '/ag scan':  scan all bags")
        print("AutoGear:    '/ag quest': toggle automatic quest handling")
    end
end

function ToggleAutoAcceptQuests()
    if (AutoAcceptQuests == true) then
        AutoAcceptQuests = false
        print("AutoGear: Automatic quest handling is now disabled.")
    else
        AutoAcceptQuests = true
        print("AutoGear: Automatic quest handling is now enabled.")
    end
    AutoGearQuestCheckButton:SetChecked(AutoAcceptQuests)
end

function Scan()
    if (not weighting) then SetStatWeights() end
    if (not weighting) then
        print("AutoGear: No weighting set for this class.")
        return
    end
    print("AutoGear: Scanning bags for upgrades.")
    if (not ScanBags()) then
        print("AutoGear: Nothing better was found")
    end
end

function AutoGearMain()
    if (GetTime() - tUpdate > 0.05) then
        tUpdate = GetTime()
        --future actions
        for i, curAction in ipairs(futureAction) do
            if (curAction.action == "roll") then
                if (GetTime() > curAction.t) then
                    if (curAction.rollType == 1) then
                        print ("AutoGear: Rolling NEED on "..curAction.info.Name..".")
                    elseif (curAction.rollType == 2) then
                        print ("AutoGear: Rolling GREED on "..curAction.info.Name..".")
                    end
                    RollOnLoot(curAction.rollID, curAction.rollType)
                    table.remove(futureAction, i)
                end
            elseif (curAction.action == "equip" and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")) then
                if (GetTime() > curAction.t) then
                    if (not curAction.messageAlready) then
                        print("AutoGear: Equipping "..curAction.info.Name..".")
                        curAction.messageAlready = 1
                    end
                    if (curAction.removeMainHandFirst) then
                        if (GetAllBagsNumFreeSlots() > 0) then
                            print("AutoGear: Removing the two-hander to equip the off-hand")
                            PickupInventoryItem(GetInventorySlotInfo("MainHandSlot"))
                            PutItemInEmptyBagSlot()
                            curAction.removeMainHandFirst = nil
                            curAction.waitingOnEmptyMainHand = 1
                        else
                            print("AutoGear: Cannot equip the off-hand because bags are too full to remove the two-hander")
                            table.remove(futureAction, i)
                        end
                    elseif (curAction.waitingOnEmptyMainHand and GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
                    elseif (curAction.waitingOnEmptyMainHand and not GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
                        print("AutoGear: Main hand detected to be clear.  Equipping now.")
                        curAction.waitingOnEmptyMainHand = nil
                    elseif (curAction.ensuringEquipped) then
                        if (GetInventoryItemID("player", curAction.replaceSlot) == GetContainerItemID(curAction.container, curAction.slot)) then
                            curAction.ensuringEquipped = nil
                            table.remove(futureAction, i)
                        end
                    else
                        PickupContainerItem(curAction.container, curAction.slot)
                        EquipCursorItem(curAction.replaceSlot)
                        curAction.ensuringEquipped = 1
                    end
                end
            elseif (curAction.action == "scan") then
                if (GetTime() > curAction.t) then
                    ScanBags()
                    table.remove(futureAction, i)
                end
            end
        end
    end
end