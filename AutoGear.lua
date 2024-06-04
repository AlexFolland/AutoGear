--AutoGear

-- to do:
-- implement classic direct % crit and direct % hit
-- Needing on meteor shard as a mage
--	In general, needing on one-handers that are near-worthless.  The plan is to only roll if it passes a minimum threshold.  That threshold should be 3x the highest weight among the 5 main stats.
-- Don't roll on loot I already have in my bag
-- Greeded in something within 5 levels that was an upgrade.  Specifically, Gauntlets of Divinity versus equipped Algae Fists.
-- Auto-equip bags if they're not BOP and you have an empty slot

-- accomodate for "no item link received"
-- identify bag rolls and roll need when appropriate
-- roll need on mounts that the character doesn't have
-- identify bag rolls and roll need when appropriate
-- fix guild repairs
-- make seperate stat weights for main and off hand
-- add a weight for weapon damage
-- fix weapons for rogues properly.  (dagger and any can equip dagger and shield, put slow in main hand for outlaw, etc)
-- remove the armor penetration weight
-- make gem weights have level tiers (70-79, 80-84, 85)
-- other non-gear it should let you roll
-- add a ui
-- add rolling on offset
-- factor in racial weapon bonuses
-- eye of arachnida slot nil error

---@type AutoGearAddon
local _, T = ...

---Current TOC version
---you should know how this versions works to compare.
---Example WoW Version to TOC Version:
--- - v1.2.0 -> 10200
--- - v3.4.3 -> 30403
--- - v9.7.2 -> 90702
--- - v10.0.1 -> 100001
---
---Start numbers for every expansion:
--- - Vanilla: 10000
--- - TBC: 20000
--- - WotLK: 30000
--- - Cata: 40000
--- - MoP: 50000
--- - WoD: 60000
--- - Legion: 70000
--- - BfA: 80000
--- - SL: 90000
--- - DF: 100000
local TOC_VERSION_CURRENT = select(4, GetBuildInfo())
local TOC_VERSION_TBC = 20000
local TOC_VERSION_WOTLK = 30000
local TOC_VERSION_CATA = 40000
local TOC_VERSION_MOP = 50000
local TOC_VERSION_WOD = 60000
local TOC_VERSION_LEGION = 70000
local TOC_VERSION_BFA = 80000
local TOC_VERSION_SL = 90000
local TOC_VERSION_DF = 100000

local _ --prevent taint when using throwaway variable
local next = next -- bind next locally for speed
--local lastlink
local futureAction = {}
local weapons
local tUpdate = 0
local dataAvailable = nil
local shouldPrintHelp = false
local maxPlayerLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or GetMaxLevelForExpansionLevel(GetExpansionLevel())
local L = T.Localization
local ContainerIDToInventoryID = ContainerIDToInventoryID or (C_Container and (C_Container.ContainerIDToInventoryID))
local GetContainerNumSlots = GetContainerNumSlots or (C_Container and (C_Container.GetContainerNumSlots))
local PickupContainerItem = PickupContainerItem or (C_Container and (C_Container.PickupContainerItem))
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or (C_Container and (C_Container.GetContainerNumFreeSlots))
AutoGearWouldRoll = "nil"
AutoGearIsItemDataMissing = nil
AutoGearFirstEquippableBagSlot = ContainerIDToInventoryID(1) or 20
AutoGearLastEquippableBagSlot = ContainerIDToInventoryID(NUM_BAG_SLOTS) or 23
AutoGearEquippableBagSlots = {}
--initialize equippable bag slots table
for i = BACKPACK_CONTAINER+1, NUM_BAG_SLOTS do
	table.insert(AutoGearEquippableBagSlots, AutoGearFirstEquippableBagSlot+i-1)
end

function AutoGearSerializeTable(val, name, skipnewlines, depth)
	skipnewlines = skipnewlines or false
	depth = depth or 0

	local tmp = string.rep(" ", depth)

	if name then tmp = tmp .. name .. " = " end

	if type(val) == "table" then
		tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

		for k, v in pairs(val) do
			tmp =  tmp .. AutoGearSerializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
		end

		tmp = tmp .. string.rep(" ", depth) .. "}"
	elseif type(val) == "number" then
		tmp = tmp .. tostring(val)
	elseif type(val) == "string" then
		tmp = tmp .. string.format("%q", val)
	elseif type(val) == "boolean" then
		tmp = tmp .. (val and "true" or "false")
	else
		tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
	end

	return tmp
end

function AutoGearStringHash(text)
	local counter = 1
	local len = string.len(text)
	for i = 1, len, 3 do
		counter = math.fmod(counter*8161, 4294967279) +  -- 2^32 - 17: Prime!
		(string.byte(text,i)*16776193) +
		((string.byte(text,i+1) or (len-i+256))*8372226) +
		((string.byte(text,i+2) or (len-i+256))*3932164)
	end
	return math.fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

--names of verbosity levels
local verbosityNames = {
	[0] = "errors",
	"info",
	"details",
	"debug",
}
-- set default value if key unknown
setmetatable(verbosityNames, {__index = function () return "funky" end})

function AutoGearGetAllowedVerbosityName(allowedverbosity)
	return verbosityNames[allowedverbosity]
end

--printing function to check allowed verbosity level
function AutoGearPrint(text, verbosity)
	if verbosity == nil then verbosity = 0 end
	if (AutoGearDB.AllowedVerbosity == nil) or (verbosity <= AutoGearDB.AllowedVerbosity) then
		print(text)
	end
end

--initialize table for storing saved variables
if (not AutoGearDB) then AutoGearDB = {} end

--initialize item info cache for quicker repeat lookups
-- AutoGearItemInfoCache = {}

--fill class lists for lookups later
AutoGearClassList = {}
local playerIsFemale = (C_PlayerInfo.GetSex(PlayerLocation:CreateFromUnit("player")) == 1)
FillLocalizedClassList(AutoGearClassList, playerIsFemale)
if not AutoGearClassList["DEATHKNIGHT"] then AutoGearClassList["DEATHKNIGHT"] = "Death Knight" end
if not AutoGearClassList["DEMONHUNTER"] then AutoGearClassList["DEMONHUNTER"] = "Demon Hunter" end
if not AutoGearClassList["EVOKER"] then AutoGearClassList["EVOKER"] = "Evoker" end
if not AutoGearClassList["MONK"] then AutoGearClassList["MONK"] = "Monk" end
AutoGearReverseClassList = {}
for k, v in pairs(AutoGearClassList) do
	AutoGearReverseClassList[v] = k
end

AutoGearClassIDList = {
	[1] = {
		fileName="WARRIOR",
		localizedName=AutoGearClassList["WARRIOR"]
	},
	[2] = {
		fileName="PALADIN",
		localizedName=AutoGearClassList["PALADIN"]
	},
	[3] = {
		fileName="HUNTER",
		localizedName=AutoGearClassList["HUNTER"]
	},
	[4] = {
		fileName="ROGUE",
		localizedName=AutoGearClassList["ROGUE"]
	},
	[5] = {
		fileName="PRIEST",
		localizedName=AutoGearClassList["PRIEST"]
	},
	[6] = {
		fileName="DEATHKNIGHT",
		localizedName=AutoGearClassList["DEATHKNIGHT"]
	},
	[7] = {
		fileName="SHAMAN",
		localizedName=AutoGearClassList["SHAMAN"]
	},
	[8] = {
		fileName="MAGE",
		localizedName=AutoGearClassList["MAGE"]
	},
	[9] = {
		fileName="WARLOCK",
		localizedName=AutoGearClassList["WARLOCK"]
	},
	[10] = {
		fileName="MONK",
		localizedName=AutoGearClassList["MONK"]
	},
	[11] = {
		fileName="DRUID",
		localizedName=AutoGearClassList["DRUID"]
	},
	[12] = {
		fileName="DEMONHUNTER",
		localizedName=AutoGearClassList["DEMONHUNTER"]
	},
	[13] = {
		fileName="EVOKER",
		localizedName=AutoGearClassList["EVOKER"]
	}
}
AutoGearReverseClassIDList = {}
for k, v in pairs(AutoGearClassIDList) do
	AutoGearReverseClassIDList[v.fileName] = {}
	AutoGearReverseClassIDList[v.fileName].id = k
	AutoGearReverseClassIDList[v.fileName].localizedName = v.localizedName
end

--initialize missing saved variables with default values; call only after PLAYER_ENTERING_WORLD
function AutoGearInitializeDB(defaults, reset)
	if AutoGearDB == nil or reset ~= nil then AutoGearDB = {} end
	for k,v in pairs(defaults) do
		if _G["AutoGearDB"][k] == nil then
			_G["AutoGearDB"][k] = v
		end
	end
end

-- Specializations appeared only in Mists Of Pandaria. We also have make changes to Cataclysm with preferred talent tree
-- later
if TOC_VERSION_CURRENT < TOC_VERSION_MOP then
	function AutoGearDetectSpec()
		-- GetSpecialization() doesn't exist until MoP
		-- Instead, this finds the talent tree where the most points are allocated.
		local highestSpec = nil
		local highestPointsSpent = nil
		local numTalentTabs = GetNumTalentTabs()
		if (not numTalentTabs) or (numTalentTabs < 2) then
			AutoGearPrint("AutoGear: numTalentTabs in AutoGearGetSpec() is "..tostring(numTalentTabs),0)
		end
		-- It needs a condition of being above 0 or else it will assign highestSpec to the first talent tree even if there are 0 points in it.
		local _, spec, _, _, pointsSpent = GetTalentTabInfo(1)
		if pointsSpent and pointsSpent >= 0 then
			highestPointsSpent = pointsSpent
			if pointsSpent > 0 then highestSpec = spec end
			for i = 2, numTalentTabs do
				local _, spec, _, _, pointsSpent = GetTalentTabInfo(i)
				if (pointsSpent > highestPointsSpent) then
					highestPointsSpent = pointsSpent
					highestSpec = spec
				end
			end
		else
			for i = 1, numTalentTabs do
				local spec, _, pointsSpent = GetTalentTabInfo(i)
				if (highestPointsSpent == nil or pointsSpent > highestPointsSpent) then
					highestPointsSpent = pointsSpent
					highestSpec = spec
				end
			end
		end
		if (highestPointsSpent == 0) then
			return "None"
		end

		-- If they're feral, determine if they're a tank and call it Guardian.
		if (highestSpec == "Feral" or highestSpec == "Feral Combat") then
			local tankiness = 0
			if TOC_VERSION_CURRENT < TOC_VERSION_WOTLK then
				tankiness = tankiness + select(5, GetTalentInfo(2, 3)) * 1.0 --Feral Instinct
				tankiness = tankiness + select(5, GetTalentInfo(2, 7)) * 5 --Feral Charge
				tankiness = tankiness + select(5, GetTalentInfo(2, 5)) * 0.5 --Thick Hide
				tankiness = tankiness + select(5, GetTalentInfo(2, 9)) * -100 --Improved Shred
				tankiness = tankiness + select(5, GetTalentInfo(2, 12)) * 100 --Primal Fury
			else
				tankiness = tankiness + select(5, GetTalentInfo(2, 15)) * 3 --Survival Instincts
				tankiness = tankiness + select(5, GetTalentInfo(2, 10)) * 1 --Feral Charge
				tankiness = tankiness + select(5, GetTalentInfo(2, 22)) * 1 --Primal Precision
				tankiness = tankiness + select(5, GetTalentInfo(2, 1)) * 1 --Thick Hide
				tankiness = tankiness + select(5, GetTalentInfo(2, 19)) * -100 --Predatory Instincts
				tankiness = tankiness + select(5, GetTalentInfo(2, 28)) * 100 --Protector of the Pack
			end
			if (tankiness >= 5) then return "Guardian" end
		end

		return highestSpec
	end
else
	function AutoGearDetectSpec()
		local currentSpec = GetSpecialization()
		local currentSpecName = currentSpec and select(2, GetSpecializationInfo(currentSpec)) or "None"
		if (currentSpec == 5) then
			return "None"
		else
			return currentSpecName
		end
	end
end

function AutoGearGetDefaultOverrideSpec()
	local className = UnitClass("player")
	local spec = AutoGearDetectSpec()
	if spec then
		return className..": "..spec
	end
end

function AutoGearGetDefaultLockedGearSlots()
	local lockedGearSlots = {}
	for gearSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
		if gearSlot <= INVSLOT_LAST_EQUIPPED or gearSlot >= AutoGearFirstEquippableBagSlot then
			lockedGearSlots[gearSlot] = {
				["label"] = tostring(gearSlot),
				["enabled"] = false
			}
		end
	end
	return lockedGearSlots
end

function AutoGearGetLockedGearSlots()
	if not AutoGearDB.LockedGearSlots then
		AutoGearDB.LockedGearSlots = AutoGearGetDefaultLockedGearSlots()
	end
	return AutoGearDB.LockedGearSlots
end

function AutoGearFixLockedGearSlots() -- finds missing slots and adds them, in case Blizzard changed them around
	if not AutoGearDB.LockedGearSlots then AutoGearDB.LockedGearSlots = AutoGearGetDefaultLockedGearSlots() return end
	for gearSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
		if gearSlot <= INVSLOT_LAST_EQUIPPED or gearSlot >= AutoGearFirstEquippableBagSlot then
			if not AutoGearDB.LockedGearSlots[gearSlot] then
				AutoGearDB.LockedGearSlots[gearSlot] = {
					["label"] = tostring(gearSlot),
					["enabled"] = false
				}
			end
		end
	end
end

--default values for variables saved between sessions
AutoGearDBDefaults = {
	Enabled = true,
	AutoLootRoll = true,
	AutoRollOnBoEBlues = false,
	AutoRollOnEpics = false,
	RollOnNonGearLoot = true,
	AutoConfirmBinding = true,
	AutoConfirmBindingBlues = false,
	AutoConfirmBindingEpics = false,
	AutoAcceptQuests = true,
	AutoCompleteItemQuests = true,
	AutoAcceptPartyInvitations = true,
	ScoreInTooltips = true,
	ReasonsInTooltips = false,
	AlwaysCompareGear = GetCVarBool("alwaysCompareItems"),
	AlwaysShowScoreComparisons = false,
	AutoSellGreys = true,
	AutoRepair = true,
	Override = false,
	OverrideSpec = AutoGearGetDefaultOverrideSpec(),
	UsePawn = true, --AutoGear built-in weights are deprecated.  We're using Pawn mainly now, so default true.
	OverridePawnScale = false,
	PawnScale = "",
	DebugInfoInTooltips = false,
	AllowedVerbosity = 1,
	LockGearSlots = true,
	LockedGearSlots = AutoGearGetDefaultLockedGearSlots()
}

--an invisible tooltip that AutoGear can scan for various information
local tooltipFrame = CreateFrame("GameTooltip", "AutoGearTooltip", UIParent, "GameTooltipTemplate")

--the main frame
AutoGearFrame = CreateFrame("Frame", nil, UIParent)
AutoGearFrame:SetWidth(1) AutoGearFrame:SetHeight(1)
AutoGearFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
AutoGearFrame:SetScript("OnUpdate", function()
	AutoGearMain()
end)

local E = 0.000001 --epsilon; non-zero value that's insignificantly different from 0, used here for the purpose of valuing gear that has higher stats that give the player "almost no benefit"
-- regex for finding 0 in this block to replace with E: (?<=[^ ] = )0(?=[^\.0-9])
if TOC_VERSION_CURRENT < TOC_VERSION_CATA then
	AutoGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.22, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.5,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.5, SpellPenetration = E, Haste = 0.5, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, SpellCrit = 0.9, Hit = 0.9, SpellHit = 0.9,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 1
			},
			["Balance"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = E, ArmorPenetration = E, Crit = 0.1, SpellCrit = 1, Hit = 0.1, SpellHit = 1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 1, Intellect = 0.1, Spirit = 0.2,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 0.05,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Feral Combat"] = { -- Classic spec name
				Strength = 0.3, Agility = 1.05, Stamina = 1, Intellect = 0.1, Spirit = 0.2,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 0.05,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 1.33,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.6, Spirit = 1.0,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 3,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.5, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["HUNTER"] = {
			["None"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, SpellCrit = E, Hit = 0.4, SpellHit = E,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = E, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Beast Mastery"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.9, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 2, SpellCrit = E, Hit = 1.4, SpellHit = E,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Marksmanship"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.61, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.66, SpellCrit = E, Hit = 3.49, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Survival"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.33, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.37, SpellCrit = E, Hit = 3.19, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.40, Spirit = 0.9,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = E, Agility = E, Stamina = 0.01, Intellect = 0.40, Spirit = 0.9,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1.1, SpellPenetration = 0.2, Haste = 0.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 10, YellowSockets = 8, BlueSockets = 7, MetaSockets = 20,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.9,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1.1, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 2.4, Hit = E, SpellHit = 1.75,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.40, Spirit = 0.8,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.3, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 0.3, SpellHit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, SpellCrit = 0.6, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.13333, Damage = 0.06667
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, SpellCrit = 0.98, Hit = 1.77, SpellHit = 0.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.1, Hit = E, SpellHit = 0.1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.1, Spirit = 0.3,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, Defense = 3,
				SpellPower = 0.05, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = 0.1, Crit = 0.25, SpellCrit = E, Hit = E,
				Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
				DPS = 1.33333, Damage = 0.66667
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = 0.1, Spirit = 0.3,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, SpellCrit = 0.1, Hit = 1.77, SpellHit = 0.1,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1, Damage = 1
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.75, SpellPenetration = E, Haste = 2, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.6, Hit = E, SpellHit = 1.95,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 0.26, Spirit = 1,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 1, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.25, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1.8,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.47, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.47, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1, Mp5 = 3,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1, Hit = E, SpellHit = 1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.3, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dagger and any",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger and any",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.6, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			}
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = E, Agility = 1, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, SpellCrit = 1.11, Hit = 2.7, SpellHit = 2.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Elemental"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, SpellCrit = 0.9, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.13333, Damage = 0.06667
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.95, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, SpellCrit = 1, Hit = 0.8, SpellHit = 0.8,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.75, SpellPenetration = E, Haste = 0.6, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, SpellCrit = 0.4, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.37, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.08, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 6, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = 0.5, Defense = 4,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, SpellCrit = E, Hit = 2, SpellHit = E,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, SpellCrit = E, Hit = 2, SpellHit = E,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Fury"] = {
				weapons = ((TOC_VERSION_CURRENT >= TOC_VERSION_WOTLK) and "2hDW" or "dual wield"),
				Strength = 2.98, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.37, Mp5 = E,
				AttackPower = 1.36, ArmorPenetration = E, Crit = 1.98, SpellCrit = E, Hit = 2.47, SpellHit = E,
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = 0.5, Stamina = 1.5, Intellect = E, Spirit = E,
				Armor = 0.13, Dodge = 1, Parry = 1.03, Block = 0.5, Defense = 4,
				SpellPower = E, SpellPenetration = E, Haste = E, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, SpellCrit = E, Hit = 0.02, SpellHit = E,
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			}
		}
	}
else
	AutoGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.22, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.5,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.5, SpellPenetration = E, Haste = 0.5, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = 0.9,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 1
			},
			["Balance"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = 0.05,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["EVOKER"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Devastation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Preservation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Augmentation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			}
		},
		["HUNTER"] = {
			["None"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, Hit = 0.4,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = E, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Beast Mastery"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.9, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 1.1, Hit = 0.4,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Marksmanship"] = {
				weapons = "ranged",
				Strength = E, Agility = 1.05, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.005, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.61, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.66, Hit = 3.49,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Survival"] = {
				Strength = E, Agility = 1.05, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.005, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.33, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.37, Hit = 3.19,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 5.16, Spirit = 0.05,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = E, ArmorPenetration = E, Crit = 1.34, Hit = 3.21,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = E, Agility = E, Stamina = 0.01, Intellect = 1, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.2, Haste = 0.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = 0.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.2, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.9, SpellPenetration = 0.3, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.8, Hit = 0.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, Hit = 1.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.8, Spirit = 0.9,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = E,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, SpellPower = 0.05,
				AttackPower = 0.4, Haste = 0.5, ArmorPenetration = 0.1,
				Crit = 0.25, Hit = E, Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
				DPS = 2
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, Hit = 1.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 2.75, SpellPenetration = E, Haste = 2, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.6, Hit = 1.95,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 1, Spirit = 1,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 1, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.25, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 1, SpellPenetration = E, Haste = 0.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.47, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = E, Crit = 1.1, Hit = 0.6,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			}
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = E, Agility = 1, Stamina = 0.05, Intellect = 1, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, Hit = 2.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Elemental"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.95, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, Hit = 0.8,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.65,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.75, SpellPenetration = E, Haste = 0.6, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.79, Hit = 2.78,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.79, Hit = 2.78,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.79, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.91, SpellPenetration = 0.05, Haste = 2.37, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.95, Hit = 3.74,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.3, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.62, SpellPenetration = 0.05, Haste = 2.08, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.4, Hit = 2.83,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, Hit = 2,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, Hit = 2,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Fury"] = {
				weapons = "2hDW",
				Strength = 2.98, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.37, Mp5 = E,
				AttackPower = 1.36, ArmorPenetration = E, Crit = 1.98, Hit = 2.47,
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = E, Stamina = 1.5, Intellect = E, Spirit = E,
				Armor = 0.16, Dodge = 1, Parry = 1.03, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = E, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = 0.02,
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		}
	}
end

AutoGearOverrideSpecs = {
	{
		["label"] = "Death Knight",
		["subLabels"] = {"None", "Blood", "Frost", "Unholy"}
	},
	{
		["label"] = "Demon Hunter",
		["subLabels"] = {"None", "Havoc", "Vengeance"}
	},
	{
		["label"] = "Druid",
		["subLabels"] = {"None", "Balance", "Feral", "Guardian", "Restoration"}
	},
	{
		["label"] = "Evoker",
		["subLabels"] = {"None", "Devastation", "Preservation", "Augmentation"}
	},
	{
		["label"] = "Hunter",
		["subLabels"] = {"None", "Beast Mastery", "Marksmanship", "Survival"}
	},
	{
		["label"] = "Mage",
		["subLabels"] = {"None", "Arcane", "Fire", "Frost"}
	},
	{
		["label"] = "Monk",
		["subLabels"] = {"None", "Brewmaster", "Mistweaver", "Windwalker"}
	},
	{
		["label"] = "Paladin",
		["subLabels"] = {"None", "Holy", "Protection", "Retribution"}
	},
	{
		["label"] = "Priest",
		["subLabels"] = {"None", "Discipline", "Holy", "Shadow"}
	},
	{
		["label"] = "Rogue",
		["subLabels"] = {"None", "Assassination", "Combat", "Outlaw", "Subtlety"}
	},
	{
		["label"] = "Shaman",
		["subLabels"] = {"None", "Enhancement", "Elemental", "Restoration"}
	},
	{
		["label"] = "Warlock",
		["subLabels"] = {"None", "Affliction", "Demonology", "Destruction"}
	},
	{
		["label"] = "Warrior",
		["subLabels"] = {"None", "Arms", "Fury", "Protection"}
	}
}

function AutoGearGetOverrideSpecs()
	local classOrder = {}
	for k in pairs(AutoGearDefaultWeights) do
		table.insert(classOrder, k)
	end
	table.sort(classOrder)

	for i = 1, #classOrder do (function()
		local className = classOrder[i]
		local localizedClassName = AutoGearClassList[className]
		if localizedClassName == nil then return end
		AutoGearOverrideSpecs[i] = {
			["label"] = localizedClassName,
			["subLabels"] = AutoGearOverrideSpecs[i]["subLabels"]
		}
		local specOrder = {}
		for l in pairs(AutoGearDefaultWeights[className]) do
			table.insert(specOrder, l)
		end
		table.sort(specOrder, function(a, b)
			if a == 'None' then
				return true
			elseif b == 'None' then
				return false
			else
				return a < b
			end
		end)
		for j = 1, #specOrder do
			local specName = specOrder[j]
			AutoGearOverrideSpecs[i]["subLabels"][j] = specName
		end
	end)() end
	return AutoGearOverrideSpecs
end

function AutoGearGetClassAndSpec()
	local localizedClass, class, spec, classID
	if (AutoGearDB.Override and AutoGearDB.OverrideSpec) then
		class, spec = string.match(AutoGearDB.OverrideSpec,"(.+): ?(.+)")
		localizedClass = string.gsub(class, "%s+", "")
		class = string.upper(localizedClass)
		classID = AutoGearReverseClassIDList[class].id
	end
	if ((localizedClass == nil) or (class == nil) or (spec == nil)) then
		localizedClass, class, spec, classID = AutoGearDetectClassAndSpec()
	end
	return localizedClass, class, spec, classID
end

function AutoGearDetectClassAndSpec()
	local localizedClass, class, spec, classID
	class, classID = UnitClassBase("player")
	localizedClass = AutoGearClassIDList[classID].localizedName
	spec = AutoGearDetectSpec()
	return localizedClass, class, spec, classID
end

function AutoGearSetStatWeights()
	local localizedClass, class, spec = AutoGearGetClassAndSpec()
	AutoGearCurrentWeighting = AutoGearDefaultWeights[class] and AutoGearDefaultWeights[class][spec] or nil
	weapons = AutoGearCurrentWeighting and (AutoGearCurrentWeighting.weapons or "any") or "any"
	if (not AutoGearCurrentWeighting) then
		if (not (AutoGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
			AutoGearPrint("AutoGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
		end
		return
	end
	if (TOC_VERSION_CURRENT >= TOC_VERSION_WOTLK) and (not (AutoGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
		AutoGearCurrentWeighting.Crit = math.max(AutoGearCurrentWeighting.Crit or 0, AutoGearCurrentWeighting.SpellCrit or 0)
	end
end

local function newCheckbox(dbname, label, description, onClick, optionsMenu)
	local check = CreateFrame("CheckButton", "AutoGear"..dbname.."CheckButton", optionsMenu, "InterfaceOptionsCheckButtonTemplate")
	check:SetScript("OnClick", function(self)
		local tick = self:GetChecked()
		onClick(self, tick and true or false)
		if tick then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
	end)
	check.label = _G[check:GetName().."Text"]
	check.label:SetText(label)
	check.tooltipText = label
	check.tooltipRequirement = description
	return check
end

local function optionsSetup(optionsMenu)
	local i = 0
	local frame = {}
	frame[i] = optionsMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame[i]:SetPoint("TOPLEFT", 8, -8)
	frame[i]:SetText("AutoGear")

	--loop through options table to build our options menu programmatically
	for _, v in ipairs(AutoGearOptions) do (function()
		if (not v["option"]) or ((v["shouldUse"] ~= nil) and (v["shouldUse"] == false)) then return end
		--manual iterator to be able to start from 0 and add another one outside the loop
		i = i + 1

		--function to run when toggling this option by clicking the checkbox
		_G["AutoGearSimpleToggle"..v["option"]] = function(self, value)
			if v["cvar"] then
				SetCVar(v["cvar"], value and 1 or 0)
			end
			AutoGearDB[v["option"]] = value
			AutoGearPrint("AutoGear: "..(AutoGearDB[v["option"]] and v["toggleDescriptionTrue"] or v["toggleDescriptionFalse"]), 3)
			AutoGearPrint("AutoGear: AutoGearDB."..v["option"].." is "..(AutoGearDB[v["option"]] and "true" or "false")..".",3)
		end

		--function to run when toggling this option via command-line interface
		_G["AutoGearToggle"..v["option"]] = function(force)
			if AutoGearDB[v["option"]] == nil then return end
			if force ~= nil then
				AutoGearDB[v["option"]] = force
			else
				AutoGearDB[v["option"]] = (not AutoGearDB[v["option"]])
			end
			if v["cvar"] then SetCVar(v["cvar"], force or (GetCVarBool(v["cvar"]) and 0 or 1)) end
			AutoGearPrint("AutoGear: "..(AutoGearDB[v["option"]] and v["toggleDescriptionTrue"] or v["toggleDescriptionFalse"]), 0)
			if _G["AutoGear"..v["option"].."CheckButton"] == nil then return end
			_G["AutoGear"..v["option"].."CheckButton"]:SetChecked(v["cvar"] and GetCVarBool(v["cvar"]) or AutoGearDB[v["option"]])
		end

		if v["togglePostHook"] then
			hooksecurefunc("AutoGearSimpleToggle"..v["option"], v["togglePostHook"])
			hooksecurefunc("AutoGearToggle"..v["option"], v["togglePostHook"])
		end

		--set description, and if this option is a cvar shortcut, add explanation of cvars to description
		local description = v["description"]..(v["cvar"] and "\n\nThis is a shortcut for the \""..v["cvar"].."\" CVar provided by Blizzard.  Toggling this will toggle that CVar." or "")

		--make a checkbox for this option
		frame[i] = newCheckbox(v["option"], v["label"], description, _G["AutoGearSimpleToggle"..v["option"]], optionsMenu)
		frame[i]:SetPoint("TOPLEFT", frame[i-1], "BOTTOMLEFT", 0, 0) --attach to previous element
		frame[i]:SetHitRectInsets(0, -280, 0, 0) --change click region to not be super wide
		frame[i]:SetChecked(AutoGearDB[v["option"]]) --set initial checked state based on db

		--if this has a child defined and it should be used, build its child
		if v["child"] and ((v["child"]["shouldUse"] == nil) or (v["child"]["shouldUse"] and (v["child"]["shouldUse"] ~= false))) then

			--if the child is a dropdown, build it that way
			if v["child"]["options"] then

				frame[i].dropDown = CreateFrame("FRAME", "AutoGear"..v["child"]["option"].."Dropdown", optionsMenu, "UIDropDownMenuTemplate")
				--newDropdown(v["child"]["option"], v["child"]["label"], v["child"]["description"], _G["AutoGearSelectFrom"..v["child"]["option"].."Dropdown"], v["child"]["options"], optionsMenu)
				local width = 250
				frame[i].dropDown:SetPoint("TOPLEFT", frame[i], "TOPRIGHT", width, 0) --attach to parent
				UIDropDownMenu_SetWidth(frame[i].dropDown, width)
				--frame[i].dropDown:SetHitRectInsets(0, -280, 0, 0) --change click region to not be super wide
				if type(AutoGearDB[v["child"]["option"]]) == 'string' then
					UIDropDownMenu_SetText(frame[i].dropDown, AutoGearDB[v["child"]["option"]])
				elseif type(AutoGearDB[v["child"]["option"]]) == 'table' then
					local label
					for _, l in pairs(v["child"]["options"]) do
						if l["enabled"] then
							if label then
								label = label..", "..l["label"]
							else
								label = l["label"]
							end
						end
					end
					UIDropDownMenu_SetText(_G["AutoGear"..v["child"]["option"].."Dropdown"], label)
				end

				--function to run when using this dropdown
				_G["AutoGear"..v["child"]["option"].."Dropdown"].SetValue = function(self, value)
					if type(AutoGearDB[v["child"]["option"]]) == 'string' then
						AutoGearDB[v["child"]["option"]] = value
						UIDropDownMenu_SetText(_G["AutoGear"..v["child"]["option"].."Dropdown"], AutoGearDB[v["child"]["option"]])
						CloseDropDownMenus()
					end
				end

				if v["child"]["dropdownPostHook"] then
					hooksecurefunc(_G["AutoGear"..v["child"]["option"].."Dropdown"], "SetValue", v["child"]["dropdownPostHook"])
				end

				UIDropDownMenu_Initialize(_G["AutoGear"..v["child"]["option"].."Dropdown"], function(self, level, menuList)
					local info = UIDropDownMenu_CreateInfo()
					if (level or 1) == 1 then
						--display the labels
						if type(AutoGearDB[v["child"]["option"]]) == 'string' then
							for _, j in ipairs(v["child"]["options"]) do
								info.text = j["label"]
								info.checked = (AutoGearDB[v["child"]["option"]] and (string.match(AutoGearDB[v["child"]["option"]], "^"..j["label"]..":") and true or false) or false)
								info.menuList = j
								info.hasArrow = (j["subLabels"] and true or false)
								UIDropDownMenu_AddButton(info)
							end
						elseif type(AutoGearDB[v["child"]["option"]]) == 'table' then
							for _, j in pairs(v["child"]["options"]) do
								info.text = j["label"]
								info.keepShownOnClick = true
								info.isNotRadio = true
								info.checked = j["enabled"]
								info.func = function(self) j["enabled"] = self.checked
									local label
									for _, l in pairs(v["child"]["options"]) do
										if l["enabled"] then
											if label then
												label = label..", "..l["label"]
											else
												label = l["label"]
											end
										end
									end
									UIDropDownMenu_SetText(_G["AutoGear"..v["child"]["option"].."Dropdown"], label)
								end
								info.menuList = j
								info.hasArrow = (j["subLabels"] and true or false)
								UIDropDownMenu_AddButton(info)
							end
						end
					else
						--display the subLabels
						info.func = self.SetValue
						if menuList["subLabels"] then
							for _, z in ipairs(menuList["subLabels"]) do
								info.text = z
								info.arg1 = menuList["label"]..": "..z
								info.checked = ((AutoGearDB[v["child"]["option"]] == info.arg1) or (AutoGearDB[v["child"]["option"]] == z))
								UIDropDownMenu_AddButton(info, level)
							end
						end
					end
				end)
			end
		end

		--if this is a cvar, hook Blizzard's SetCVar function to update our checkbox
		if v["cvar"] then
			hooksecurefunc("SetCVar",function(CVar, ...)
				if ((_G["AutoGear"..v["option"].."CheckButton"] ~= nil) and (CVar == v["cvar"])) then
					_G["AutoGear"..v["option"].."CheckButton"]:SetChecked(GetCVarBool(v["cvar"]))
				end
			end)
		end

		--if command-line interface commands are defined, add handling of those to the end of our cli command handling function
		if v["cliCommands"] then
			hooksecurefunc(SlashCmdList, "AutoGear", function(msg, ...)
				local command = nil
				local force = nil
				for _, w in ipairs(v["cliCommands"]) do
					if param1 == w then
						command = v["option"]
						shouldPrintHelp = false
						if not v["cliTrue"] then break end
						for _, x in ipairs(v["cliTrue"]) do
							if param2 == x then
								force = true
								break
							end
						end
						if force or (not v["cliFalse"]) then break end
						for _, x in ipairs(v["cliFalse"]) do
							if param2 == x then
								force = false
								break
							end
						end
						break
					end
				end
				if command then _G["AutoGearToggle"..command](force) end
			end)
		end
	end)() end
	hooksecurefunc(SlashCmdList, "AutoGear", function(msg, ...)
		if shouldPrintHelp then
			AutoGearPrintHelp()
			shouldPrintHelp = false
		end
	end)
	i = i + 1
	frame[i] = CreateFrame("Button", nil, optionsMenu, "UIPanelButtonTemplate")
	frame[i]:SetWidth(100)
	frame[i]:SetHeight(30)
	frame[i]:SetScript("OnClick", function() AutoGearScan() end)
	frame[i]:SetText("Scan")
	frame[i]:SetPoint("TOPLEFT", frame[i-1], "BOTTOMLEFT", 0, 0)
	frame[i]:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine("Click this button to force a scan, the same way that AutoGear scans for gear upgrades in your bags whenever new gear is looted.\n\nTip: By equipping your old item, you can use this to help determine how AutoGear decided an item was an upgrade.",nil,nil,nil,false)
		GameTooltip:Show()
	end)
	frame[i]:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local optionsMenu = CreateFrame("Frame", "AutoGearOptionsPanel", InterfaceOptionsFramePanelContainer)
optionsMenu.name = "AutoGear"
InterfaceOptions_AddCategory(optionsMenu)
if InterfaceAddOnsList_Update then InterfaceAddOnsList_Update() end

--handle PLAYER_ENTERING_WORLD events for initializing GUI options menu widget states at the right time
--UI reload doesn't seem to fire ADDON_LOADED
optionsMenu:RegisterEvent("PLAYER_ENTERING_WORLD")
optionsMenu:RegisterEvent("ADDON_LOADED")
optionsMenu:SetScript("OnEvent", function (self, event, arg1, ...)
	if event == "PLAYER_ENTERING_WORLD" then

		AutoGearInitializeDB(AutoGearDBDefaults)
		AutoGearFixLockedGearSlots()

		--initialize options menu variables
		AutoGearOptions = {
			{
				["option"] = "Enabled",
				["cliCommands"] = { "toggle", "gear", "equip" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically equip gear",
				["description"] = "Automatically equip gear upgrades, depending on internal stat weights.  These stat weights are currently only configurable by editing the values in the AutoGearDefaultWeights table in AutoGear.lua.  If this is disabled, AutoGear will still scan for gear when receiving new items and viewing loot rolls, but will never equip an item automatically.",
				["toggleDescriptionTrue"] = "Automatic gearing is now enabled.",
				["toggleDescriptionFalse"] = "Automatic gearing is now disabled.  You can still manually scan bags for upgrades with the options menu button or \"/ag scan\".",
				["togglePostHook"] = function() AutoGearUpdateBestItems() end
			},
			{
				["option"] = "AutoLootRoll",
				["cliCommands"] = { "roll", "loot", "rolling" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically roll on greens and BoP blues",
				["description"] = "Automatically roll on group loot of green rarity and blues which bind when picked up, depending on internal stat weights.  If this is disabled, AutoGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 ("..AutoGearGetAllowedVerbosityName(1)..") or higher.",
				["toggleDescriptionTrue"] = "Automatically rolling on loot of green rarity and blues which bind when picked up is now enabled.",
				["toggleDescriptionFalse"] = "Automatically rolling on loot of green rarity and blues which bind when picked up is now disabled.  AutoGear will still try to equip gear received through other means, but you will have to roll on this loot manually."
			},
			{
				["option"] = "AutoRollOnBoEBlues",
				["cliCommands"] = { "rollboeblues", "rollonboeblues", "lootboeblues" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically roll on BoE blues",
				["description"] = "Automatically roll on group loot of blue rarity which binds when equipped, depending on internal stat weights.  If this is disabled, AutoGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 ("..AutoGearGetAllowedVerbosityName(1)..") or higher.",
				["toggleDescriptionTrue"] = "Automatically rolling on group loot of blue rarity which binds when equipped is now enabled.",
				["toggleDescriptionFalse"] = "Automatically rolling on group loot of blue rarity which binds when equipped is now disabled.  AutoGear will still try to equip gear received through other means, but you will have to roll on this loot manually."
			},
			{
				["option"] = "AutoRollOnEpics",
				["cliCommands"] = { "rollepics", "rollonepics", "lootepics" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically roll on epics",
				["description"] = "Automatically roll on group loot of epic rarity, depending on internal stat weights.  If this is disabled, AutoGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 ("..AutoGearGetAllowedVerbosityName(1)..") or higher.",
				["toggleDescriptionTrue"] = "Automatically rolling on group loot of epic rarity is now enabled.",
				["toggleDescriptionFalse"] = "Automatically rolling on group loot of epic rarity is now disabled.  AutoGear will still try to equip gear received through other means, but you will have to roll on this loot manually."
			},
			{
				["option"] = "RollOnNonGearLoot",
				["cliCommands"] = { "nongear", "nongearloot", "allloot" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Roll on non-gear loot",
				["description"] = "Roll on all group loot, including loot that is not gear.  If this is enabled, AutoGear will roll GREED on non-gear, non-mount loot and NEED on mounts.",
				["toggleDescriptionTrue"] = "Rolling on non-gear loot is now enabled.  AutoGear will roll GREED on non-gear, non-mount loot and NEED on mounts.",
				["toggleDescriptionFalse"] = "Rolling on non-gear loot is now disabled."
			},
			{
				["option"] = "AutoConfirmBinding",
				["cliCommands"] = { "bind", "boe", "soulbinding" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically confirm soul-binding for non-blues/non-epics",
				["description"] = "Automatically confirm soul-binding when equipping an upgrade that does not have blue or epic rarity, causing it to become soulbound.  If this is disabled, AutoGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually.",
				["toggleDescriptionTrue"] = "Automatically confirming soul-binding for non-blues/non-epics is now enabled.",
				["toggleDescriptionFalse"] = "Automatically confirming soul-binding for non-blues/non-epics is now disabled.  AutoGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually."
			},
			{
				["option"] = "AutoConfirmBindingBlues",
				["cliCommands"] = { "blue", "blues", "bindblues", "autobindblues" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically confirm soul-binding for blues",
				["description"] = "Automatically confirm soul-binding when equipping an upgrade that has blue rarity, causing it to become soulbound.  If this is disabled, AutoGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually.",
				["toggleDescriptionTrue"] = "Automatically confirming soul-binding for blues is now enabled.",
				["toggleDescriptionFalse"] = "Automatically confirming soul-binding for blues is now disabled.  AutoGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually."
			},
			{
				["option"] = "AutoConfirmBindingEpics",
				["cliCommands"] = { "epic", "epics", "bindepics", "autobindepics" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically confirm soul-binding for epics",
				["description"] = "Automatically confirm soul-binding when equipping an upgrade that has epic rarity, causing it to become soulbound.  If this is disabled, AutoGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually.",
				["toggleDescriptionTrue"] = "Automatically confirming soul-binding for epics is now enabled.",
				["toggleDescriptionFalse"] = "Automatically confirming soul-binding for epics is now disabled.  AutoGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually."
			},
			{
				["option"] = "AutoAcceptQuests",
				["cliCommands"] = { "quest", "quests" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically accept all quests and complete quests which do not award items",
				["description"] = "Automatically accept all quests and complete quests which do not award items.  If this is disabled, AutoGear will not accept any quests and will only be able to complete quests which award items.",
				["toggleDescriptionTrue"] = "Automatically accepting all quests and completing quests which do not award items is now enabled.",
				["toggleDescriptionFalse"] = "Automatically accepting all quests and completing quests which do not award items is now disabled."
			},
			{
				["option"] = "AutoCompleteItemQuests",
				["cliCommands"] = { "completeitemquests", "questitems", "questloot", "questgear" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically complete quests which award items",
				["description"] = "Automatically evaluate quest item rewards and choose the best upgrade for your current spec, turning in the quest.  If no upgrade is found, AutoGear will choose the most valuable reward in vendor gold.  If this is disabled, AutoGear can still interact with quests, but will not complete quests which present item rewards to choose, and you can still view the total AutoGear score in item tooltips.",
				["toggleDescriptionTrue"] = "Automatically completing quests which award items is now enabled.",
				["toggleDescriptionFalse"] = "Automatically completing quests which award items is now disabled."
			},
			{
				["option"] = "AutoAcceptPartyInvitations",
				["cliCommands"] = { "party" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically accept party invitations",
				["description"] = "Automatically accept party invitations from any player.",
				["toggleDescriptionTrue"] = "Automatic acceptance of party invitations is now enabled.",
				["toggleDescriptionFalse"] = "Automatic acceptance of party invitations is now disabled."
			},
			{
				["option"] = "ScoreInTooltips",
				["cliCommands"] = { "score", "tooltip", "tooltips" },
				["cliTrue"] = { "show", "enable", "on", "start" },
				["cliFalse"] = { "hide", "disable", "off", "stop" },
				["label"] = "Show AutoGear score in item tooltips",
				["description"] = "Show total AutoGear item score from internal AutoGear stat weights in item tooltips.",
				["toggleDescriptionTrue"] = "Showing score in item tooltips is now enabled.",
				["toggleDescriptionFalse"] = "Showing score in item tooltips is now disabled."
			},
			{
				["option"] = "ReasonsInTooltips",
				["cliCommands"] = { "reason", "reasons" },
				["cliTrue"] = { "show", "enable", "on", "start" },
				["cliFalse"] = { "hide", "disable", "off", "stop" },
				["label"] = "Show won't-equip reasons in item tooltips",
				["description"] = "Show reasons AutoGear won't automatically equip items in item tooltips, except when the score is lower than the equipped item's score.",
				["toggleDescriptionTrue"] = "Showing won't-auto-equip reasons in item tooltips is now enabled.",
				["toggleDescriptionFalse"] = "Showing won't-auto-equip reasons in item tooltips is now disabled."
			},
			{
				["option"] = "AlwaysCompareGear",
				["cliCommands"] = { "compare", "alwayscompare", "alwayscomparegear" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["cvar"] = "alwaysCompareItems",
				["label"] = "Always show equipped gear comparison tooltips",
				["description"] = "Always show equipped gear comparison tooltips when viewing tooltips for gear that's not equipped.  If this is disabled, you can still show gear comparison tooltips while holding the Shift key.",
				["toggleDescriptionTrue"] = "Always showing gear comparison tooltips when viewing gear tooltips is now enabled.",
				["toggleDescriptionFalse"] = "Always showing gear comparison tooltips when viewing gear tooltips is now disabled.  You can still show gear comparison tooltips while holding the Shift key."
			},
			{
				["option"] = "AlwaysShowScoreComparisons",
				["cliCommands"] = { "scorecomparisons", "scorecomparisonsalways", "alwaysshowscorecomparisons" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Always show score comparisons in tooltips",
				["description"] = "Always show score comparisons in the item tooltip, even when also showing the comparison tooltip.  If this is enabled, only the score for the current item will be shown in the tooltip.",
				["toggleDescriptionTrue"] = "Always show score comparisons in gear tooltips is now enabled.",
				["toggleDescriptionFalse"] = "Always show score comparisons in gear tooltips is now disabled."
			},
			{
				["option"] = "AutoSellGreys",
				["cliCommands"] = { "sell", "sellgreys", "greys" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically sell greys",
				["description"] = "Automatically sell all grey items when interacting with a vendor.",
				["toggleDescriptionTrue"] = "Automatic selling of grey items is now enabled.",
				["toggleDescriptionFalse"] = "Automatic selling of grey items is now disabled."
			},
			{
				["option"] = "AutoRepair",
				["cliCommands"] = { "repair" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically repair",
				["description"] = "Automatically repair all gear when interacting with a repair-enabled vendor.  If you have a guild bank and guild bank repair funds, this will use guild bank repair funds first.",
				["toggleDescriptionTrue"] = "Automatic repairing is now enabled.",
				["toggleDescriptionFalse"] = "Automatic repairing is now disabled."
			},
			{
				["option"] = "Override",
				["cliCommands"] = { "override" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Override specialization",
				["description"] = "Override specialization with the specialization chosen in this dropdown.  If this is enabled, AutoGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the spec detected automatically.",
				["toggleDescriptionTrue"] = "Specialization overriding is now enabled.  AutoGear will use the specialization selected in the dropdown for evaluating gear.",
				["toggleDescriptionFalse"] = "Specialization overriding is now disabled.  AutoGear will use your class and its detected specialization for evaluating gear.  Type \"/ag spec\" to check what specialization AutoGear detects for your character.",
				["togglePostHook"] = function() AutoGearUpdateBestItems() end,
				["child"] = {
					["option"] = "OverrideSpec",
					["options"] = AutoGearGetOverrideSpecs(),
					["label"] = "Override specialization",
					["description"] = "Override specialization with the spec chosen in this dropdown.  If this is enabled, AutoGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the specialization detected automatically.",
					["dropdownPostHook"] = function() AutoGearSetStatWeights() end
				}
			},
			{
				["option"] = "UsePawn",
				["cliCommands"] = { "pawn", "usepawn" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Use Pawn to evaluate upgrades",
				["description"] = "If Pawn (gear evaluation addon) is installed and configured, use a Pawn scale instead of AutoGear's internal stat weights for evaluating gear upgrades.  AutoGear will use the Pawn scale with a name matching the \"[class]: [spec]\" format; example \"Paladin: Retribution\". If \"Override specialization\" is also enabled, that class and spec will be used for detecting which Pawn scale name to use instead. Visible scales (not hidden in Pawn's settings) will be prioritized when detecting which scale to use."..(((PawnIsReady ~= nil) and PawnIsReady()) and "" or "\n\n"..RED_FONT_COLOR_CODE.."Pawn is not running, so this option will do nothing."..FONT_COLOR_CODE_CLOSE),
				["toggleDescriptionTrue"] = "Using Pawn for evaluating gear upgrades is now enabled.",
				["toggleDescriptionFalse"] = "Using Pawn for evaluating gear upgrades is now disabled.",
				["togglePostHook"] = function() AutoGearUpdateBestItems() end
			},
			{
				["option"] = "OverridePawnScale",
				["shouldUse"] = ((PawnIsReady ~= nil) and PawnIsReady()),
				["cliCommands"] = { "scale", "overridepawn", "overridepawnscale" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Override Pawn scale",
				["description"] = "Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.\n\nThis override does nothing unless \"Use Pawn to evaluate upgrades\" is enabled.",
				["toggleDescriptionTrue"] = "Overriding Pawn scale with the selected scale is now enabled.",
				["toggleDescriptionFalse"] = "Overriding Pawn scale with the selected scale is now disabled.",
				["togglePostHook"] = function() AutoGearUpdateBestItems() end,
				["child"] = {
					["option"] = "PawnScale",
					["options"] = (function() if PawnIsReady and PawnIsReady() then return AutoGearGetPawnScales() end end)(),
					["label"] = "Pawn scale to use",
					["description"] = "Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.",
					["shouldUse"] = (PawnIsReady and PawnIsReady()),
					["dropdownPostHook"] = function(self, value)
						if AutoGearDB.PawnScale and string.len(AutoGearDB.PawnScale)>0 then
							local numMatches
							AutoGearDB.PawnScale, numMatches = string.gsub(AutoGearDB.PawnScale, "^Visible: ?", "", 1)
							if numMatches and numMatches == 0 then AutoGearDB.PawnScale = string.gsub(AutoGearDB.PawnScale, "^Hidden: ?", "", 1) end
							UIDropDownMenu_SetText(AutoGearPawnScaleDropdown, AutoGearDB.PawnScale)
						end
						AutoGearSetStatWeights()
					end
				}
			},
			{
				["option"] = "LockGearSlots",
				["cliCommands"] = { "lock", "lockslots", "lockgearslots" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Lock specified gear slots",
				["description"] = "Lock the specified gear slots, so AutoGear will not remove or equip items in those slots.  If this is enabled and any slots are locked, AutoGear will still evaluate scores for items in all slots, but will not remove or equip items in the locked slots.",
				["toggleDescriptionTrue"] = "Locking specified gear slots is now enabled.",
				["toggleDescriptionFalse"] = "Locking specified gear slots is now disabled.",
				["togglePostHook"] = function() AutoGearUpdateBestItems() end,
				["child"] = {
					["option"] = "LockedGearSlots",
					["options"] = AutoGearGetLockedGearSlots(),
					["label"] = "Gear slots to lock",
					["description"] = "Choose which gear slots to lock in this dropdown."
				}
			},
			{
				["option"] = "DebugInfoInTooltips",
				["cliCommands"] = { "debuginfo", "debuginfointooltips", "test", "testmode", "rolltestmode" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Show debug info in item tooltips (warning: "..RED_FONT_COLOR_CODE.."laggy"..FONT_COLOR_CODE_CLOSE.."!)",
				["description"] = "This is a test mode to show debug info in tooltips, such as the real roll outcome if the item viewed dropped as a loot roll.  This is to help the developers find and fix bugs in AutoGear.  You can use it to help too and report issues.  (warning: "..RED_FONT_COLOR_CODE.."laggy"..FONT_COLOR_CODE_CLOSE.."!)",
				["toggleDescriptionTrue"] = "Debug info in tooltips is now enabled. Info such as whether AutoGear would \""..GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.."\" or \""..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE.."\" on an item will be shown in item tooltips.  (warning: "..RED_FONT_COLOR_CODE.."laggy"..FONT_COLOR_CODE_CLOSE.."!)",
				["toggleDescriptionFalse"] = "Debug info in tooltips is now disabled."
			}
		}

		if AutoGearDB.OverrideSpec == nil then
			AutoGearDB.OverrideSpec = AutoGearGetDefaultOverrideSpec()
		end
		if (not AutoGearDB.LockedGearSlots) or (#AutoGearDB.LockedGearSlots == 0) then
			AutoGearDB.LockedGearSlots = AutoGearGetDefaultLockedGearSlots()
		end
		optionsSetup(optionsMenu)

		AutoGearUpdateBestItems()

		optionsMenu:UnregisterAllEvents()
		optionsMenu:SetScript("OnEvent", nil)
	end
end)

_G["SLASH_AutoGear1"] = "/AutoGear"
_G["SLASH_AutoGear2"] = "/autogear"
_G["SLASH_AutoGear3"] = "/ag"
SlashCmdList["AutoGear"] = function(msg)
	param1, param2, param3, param4, param5 = msg:match("([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*")
	if (not param1) then param1 = "" end
	if (not param2) then param2 = "" end
	if (not param3) then param3 = "" end
	if (not param4) then param4 = "" end
	if (not param5) then param5 = "" end
	if (param1 == "enable" or param1 == "on" or param1 == "start") then
		AutoGearToggleEnabled(true)
	elseif (param1 == "disable" or param1 == "off" or param1 == "stop") then
		AutoGearToggleEnabled(false)
	elseif (param1 == "scan") then
		AutoGearScan()
	elseif (param1 == "spec") then
		local localizedRealClass, realClass, realSpec, realClassID = AutoGearDetectClassAndSpec()
		local localizedOverrideClass, overrideClass, overrideSpec, overrideClassID = AutoGearGetClassAndSpec()
		local usingPawn = AutoGearDB.UsePawn and PawnIsReady and PawnIsReady()
		local pawnScaleName = ""
		local pawnScaleLocalizedName = ""
		if usingPawn then
			pawnScaleName, pawnScaleLocalizedName = AutoGearGetPawnScaleName()
		end
		AutoGearPrint("AutoGear: Looks like you are a"..(realSpec:find("^[AEIOUaeiou]") and "n " or " ")..RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realSpec.." "..localizedRealClass).."."..((usingPawn or (AutoGearDB.Override and ((realClassID ~= overrideClassID) or (realSpec ~= overrideSpec)))) and ("  However, AutoGear is using "..(usingPawn and ("Pawn scale \""..PawnGetScaleColor(pawnScaleName)..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"") or (RAID_CLASS_COLORS[overrideClass]:WrapTextInColorCode(overrideSpec.." "..localizedOverrideClass).." weights")).." for gear evaluation due to the \""..(usingPawn and "Use Pawn to evaluate upgrades" or "Override specialization").."\" option.") or ""), 0)
	elseif (param1 == "verbosity") or (param1 == "allowedverbosity") then
		AutoGearSetAllowedVerbosity(param2)
	elseif ((param1 == "setspec") or
	(param1 == "overridespec") or
	(param1 == "overridespecialization") or
	(param1 == "specoverride")) then
		local params = param2..(string.len(param3)>0 and " "..param3 or "")..(string.len(param4)>0 and " "..param4 or "")..(string.len(param5)>0 and " "..param5 or "")
		local localizedClassName, spec = string.match(params, "^\"?([^:\"]-): ([^:\"]+)\"?$")
		local class = AutoGearReverseClassList[localizedClassName]
		if class and AutoGearDefaultWeights[class][spec] then
			local overridespec = localizedClassName..": "..spec
			AutoGearDB.OverrideSpec = overridespec
			if AutoGearOverrideSpecDropdown then
				AutoGearOverrideSpecDropdown:SetValue(overridespec)
			end
			AutoGearPrint("AutoGear: "..(AutoGearDB.Override and "" or "While \"Override specialization\" is enabled, ").."AutoGear will now use "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(overridespec).." weights to evaluate gear.",0)
		else
			AutoGearPrint("AutoGear: Unrecognized command. Usage: \"/ag overridespec [class]: [spec]\" (example: \"/ag overridespec Hunter: Beast Mastery\")",0)
		end
	elseif ((param1 == "pawnscale") or
	(param1 == "setpawnscale") or
	(param1 == "setscale") or
	(param1 == "scaleoverride")) then
		-- AutoGearItemInfoCache = {}
		if PawnIsReady then
			if PawnIsReady() then
				local userPawnScaleName = param2..(string.len(param3)>0 and " "..param3 or "")..(string.len(param4)>0 and " "..param4 or "")..(string.len(param5)>0 and " "..param5 or "")
				if string.len(userPawnScaleName) == 0 then
					AutoGearPrint("AutoGear: Usage: \"/ag pawnscale [Pawn scale name]\" (example: \"/ag pawnscale Hunter: Beast Mastery\")",0)
					return
				end
				local truePawnScaleName, pawnScaleLocalizedName = AutoGearGetPawnScaleName(userPawnScaleName)
				if PawnDoesScaleExist(truePawnScaleName) then
					AutoGearDB.PawnScale = userPawnScaleName
					if AutoGearPawnScaleDropdown then
						UIDropDownMenu_SetText(AutoGearPawnScaleDropdown, AutoGearDB.PawnScale)
					end

					AutoGearPrint("AutoGear: "..(AutoGearDB.UsePawn and "" or "While using Pawn is enabled, ").."AutoGear will now use the \""..PawnGetScaleColor(truePawnScaleName)..(pawnScaleLocalizedName or truePawnScaleName)..FONT_COLOR_CODE_CLOSE.."\" Pawn scale to evaluate gear.",0)
				else
					AutoGearPrint("AutoGear: According to Pawn, a Pawn scale named \""..userPawnScaleName.."\" does not exist.",0)
				end
			else
				AutoGearPrint("AutoGear: Pawn is not ready yet.",0)
			end
		else
			AutoGearPrint("AutoGear: Pawn is not installed.",0)
		end
	elseif (param1 == "") then
		if not InterfaceAddOnsList_Update then
			InterfaceOptionsFrame_OpenToCategory(optionsMenu)
		end
		InterfaceOptionsFrame_OpenToCategory(optionsMenu)
	else
		shouldPrintHelp = true
	end
end

function AutoGearPrintHelp()
	AutoGearPrint("AutoGear: "..((param1 == "help") and "" or "Unrecognized command.  ").."Recognized commands:", 0)
	AutoGearPrint("AutoGear:    '/ag': options menu", 0)
	AutoGearPrint("AutoGear:    '/ag help': command line help", 0)
	AutoGearPrint("AutoGear:    '/ag scan': scan all bags for gear upgrades", 0)
	AutoGearPrint("AutoGear:    '/ag spec': get name of current talent specialization", 0)
	AutoGearPrint("AutoGear:    '/ag [gear/toggle]/[enable/on/start]/[disable/off/stop]': toggle automatic gearing", 0)
	AutoGearPrint("AutoGear:    '/ag roll [enable/on/start]/[disable/off/stop]': toggle automatic loot rolling", 0)
	AutoGearPrint("AutoGear:    '/ag bind [enable/on/start]/[disable/off/stop]': toggle automatic soul-binding confirmation", 0)
	AutoGearPrint("AutoGear:    '/ag quest [enable/on/start]/[disable/off/stop]': toggle automatic quest handling", 0)
	AutoGearPrint("AutoGear:    '/ag party [enable/on/start]/[disable/off/stop]': toggle automatic acceptance of party invitations", 0)
	AutoGearPrint("AutoGear:    '/ag tooltip [toggle/show/hide]': toggle showing score in item tooltips", 0)
	AutoGearPrint("AutoGear:    '/ag reasons [toggle/show/hide]': toggle showing won't-auto-equip reasons in item tooltips", 0)
	AutoGearPrint("AutoGear:    '/ag compare [enable/on/start]/[disable/off/stop]': toggle always comparing gear", 0)
	AutoGearPrint("AutoGear:    '/ag override [enable/on/start]/[disable/off/stop]': toggle specialization override", 0)
	AutoGearPrint("AutoGear:    '/ag overridespec [class]: [spec]': set override spec to \"[class]: [spec]\"",0)
	AutoGearPrint("AutoGear:    '/ag pawn [enable/on/start]/[disable/off/stop]': toggle using Pawn scales", 0)
	AutoGearPrint("AutoGear:    '/ag pawnscale [Pawn scale name]': set Pawn scale override to the specifed Pawn scale", 0)
	AutoGearPrint("AutoGear:    '/ag sell [enable/on/start]/[disable/off/stop]': toggle automatic selling of grey items", 0)
	AutoGearPrint("AutoGear:    '/ag repair [enable/on/start]/[disable/off/stop]': toggle automatic repairing", 0)
	AutoGearPrint("AutoGear:    '/ag verbosity [0/1/2/3]': set allowed verbosity level; valid levels are: 0 ("..AutoGearGetAllowedVerbosityName(0).."), 1 ("..AutoGearGetAllowedVerbosityName(1).."), 2 ("..AutoGearGetAllowedVerbosityName(2).."), 3 ("..AutoGearGetAllowedVerbosityName(3)..")", 0)
end

function AutoGearSetAllowedVerbosity(allowedverbosity)
	allowedverbosity = tonumber(allowedverbosity)
	if type(allowedverbosity) ~= "number" then
		AutoGearPrint("AutoGear: The current allowed verbosity level is "..tostring(AutoGearDB.AllowedVerbosity).." ("..AutoGearGetAllowedVerbosityName(AutoGearDB.AllowedVerbosity).."). Valid levels are: 0 ("..AutoGearGetAllowedVerbosityName(0).."), 1 ("..AutoGearGetAllowedVerbosityName(1).."), 2 ("..AutoGearGetAllowedVerbosityName(2).."), 3 ("..AutoGearGetAllowedVerbosityName(3)..").", 0)
		return
	end

	if allowedverbosity < 0 or allowedverbosity > 3 then
		AutoGearPrint("AutoGear: That is an invalid allowed verbosity level. Valid levels are: 0 ("..AutoGearGetAllowedVerbosityName(0).."), 1 ("..AutoGearGetAllowedVerbosityName(1).."), 2 ("..AutoGearGetAllowedVerbosityName(2).."), 3 ("..AutoGearGetAllowedVerbosityName(3)..").", 0)
		return
	else
		AutoGearDB.AllowedVerbosity = allowedverbosity
		AutoGearPrint("AutoGear: Allowed verbosity level is now: "..tostring(AutoGearDB.AllowedVerbosity).." ("..AutoGearGetAllowedVerbosityName(AutoGearDB.AllowedVerbosity)..").", 0)
	end
end

if TOC_VERSION_CURRENT >= TOC_VERSION_MOP then
	AutoGearFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	AutoGearFrame:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
end

if TOC_VERSION_CURRENT >= TOC_VERSION_CATA then
	-- "CONFIRM_DISENCHANT_ROLL" will be added to WoW Classic in a later phase of Cataclysm Classic. Source: https://youtube.com/watch?v=f8zWAPDUTkc&t=2498s
	-- AutoGearFrame:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
	AutoGearFrame:RegisterEvent("QUEST_POI_UPDATE")
end

function AutoGearGetContainerItemInfo(bagIndex, bagSlot)
	if GetContainerItemInfo then
		local _, count, locked, quality, _, _, link = GetContainerItemInfo(bagIndex, bagSlot)
		if (link) then
			return count, locked, link
		end
	elseif C_Container and C_Container.GetContainerItemInfo then
		local itemInfo = C_Container.GetContainerItemInfo(bagIndex, bagSlot)
		if itemInfo then
			return itemInfo.stackCount, itemInfo.isLocked, itemInfo.hyperlink
		end
	end
end

AutoGearFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
AutoGearFrame:RegisterEvent("PARTY_INVITE_REQUEST")
AutoGearFrame:RegisterEvent("START_LOOT_ROLL")
AutoGearFrame:RegisterEvent("CONFIRM_LOOT_ROLL")
AutoGearFrame:RegisterEvent("CHAT_MSG_LOOT")
AutoGearFrame:RegisterEvent("EQUIP_BIND_CONFIRM")
AutoGearFrame:RegisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM") --Fires when the player tries to equip a soulbound item that can still be traded to eligible players
AutoGearFrame:RegisterEvent("MERCHANT_SHOW")
AutoGearFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")     --Fires when equipment is equipped or unequipped from the player, excluding bags
AutoGearFrame:RegisterEvent("BAG_CONTAINER_UPDATE")         --Fires when bags are equipped or unequipped from the player
AutoGearFrame:RegisterEvent("QUEST_ACCEPTED")               --Fires when a new quest is added to the player's quest log (which is what happens after a player accepts a quest).
AutoGearFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")         --Fires when certain kinds of quests (e.g. NPC escort quests) are started by another member of the player's group
AutoGearFrame:RegisterEvent("QUEST_AUTOCOMPLETE")           --Fires when a quest is automatically completed (remote handin available)
AutoGearFrame:RegisterEvent("QUEST_COMPLETE")               --Fires when the player is looking at the "Complete" page for a quest, at a questgiver.
AutoGearFrame:RegisterEvent("QUEST_DETAIL")                 --Fires when details of an available quest are presented by a questgiver
AutoGearFrame:RegisterEvent("QUEST_FINISHED")               --Fires when the player ends interaction with a questgiver or ends a stage of the questgiver dialog
AutoGearFrame:RegisterEvent("QUEST_GREETING")               --Fires when a questgiver presents a greeting along with a list of active or available quests
AutoGearFrame:RegisterEvent("QUEST_ITEM_UPDATE")            --Fires when information about items in a questgiver dialog is updated
AutoGearFrame:RegisterEvent("QUEST_LOG_UPDATE")             --Fires when the game client receives updates relating to the player's quest log (this event is not just related to the quests inside it)
AutoGearFrame:RegisterEvent("QUEST_PROGRESS")               --Fires when interacting with a questgiver about an active quest
--AutoGearFrame:RegisterEvent("QUEST_QUERY_COMPLETE")       --Fires when quest completion information is available from the server; deprecated and registering returns an error as of 8.x
AutoGearFrame:RegisterEvent("QUEST_WATCH_UPDATE")           --Fires when the player's status regarding a quest's objectives changes, for instance picking up a required object or killing a mob for that quest. All forms of (quest objective) progress changes will trigger this event.
AutoGearFrame:RegisterEvent("GOSSIP_CLOSED")                --Fires when an NPC gossip interaction ends
AutoGearFrame:RegisterEvent("GOSSIP_CONFIRM")               --Fires when the player is requested to confirm a gossip choice
AutoGearFrame:RegisterEvent("GOSSIP_CONFIRM_CANCEL")        --Fires when an attempt to confirm a gossip choice is canceled
AutoGearFrame:RegisterEvent("GOSSIP_ENTER_CODE")            --Fires when the player attempts a gossip choice which requires entering a code
AutoGearFrame:RegisterEvent("GOSSIP_SHOW")                  --Fires when an NPC gossip interaction begins
AutoGearFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")       --Fires when a unit's quests change (accepted/objective progress/abandoned/completed)
AutoGearFrame:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, ...)

	if (AutoGearDB.AutoAcceptQuests) then
		if (event == "QUEST_ACCEPT_CONFIRM") then --another group member starts a quest (like an escort)
			ConfirmAcceptQuest()
		elseif (event == "QUEST_DETAIL") then
			QuestDetailAcceptButton_OnClick()
		elseif (event == "GOSSIP_SHOW") then
			--active quests
			for i = 1, C_GossipInfo.GetNumActiveQuests() do
				local quest = C_GossipInfo.GetActiveQuests()[i]
				if (quest["isComplete"]==true) then
					C_GossipInfo.SelectActiveQuest(quest.questID)
				end
			end
			--available quests
			for i = 1, C_GossipInfo.GetNumAvailableQuests() do
				local quest = C_GossipInfo.GetAvailableQuests()[i]
				if (quest["isTrivial"]==false) then
					C_GossipInfo.SelectAvailableQuest(quest.questID)
				end
			end
		elseif (event == "QUEST_GREETING") then
			--active quests
			for i = 1, GetNumActiveQuests() do
				local title, isComplete = GetActiveTitle(i)
				if (isComplete) then
					SelectActiveQuest(i)
				end
			end
			--available quests
			for i = 1, C_GossipInfo.GetNumAvailableQuests() do
				local quest = C_GossipInfo.GetAvailableQuests()[i]
				if (not quest.isTrivial) then
					C_GossipInfo.SelectAvailableQuest(quest.questID)
				end
			end
		elseif (event == "QUEST_PROGRESS") then
			if (IsQuestCompletable()) then
				CompleteQuest()
			end
		end
	end
	if (event == "QUEST_COMPLETE") then
		local rewards = GetNumQuestChoices()
		if ((not rewards or rewards == 0) and AutoGearDB.AutoAcceptQuests) then
			GetQuestReward()
		elseif (AutoGearDB.AutoCompleteItemQuests) then
			--choose a quest reward
			local questRewardIDs = {}
			local itemLinkMissing
			for i = 1, rewards do
				local itemLink = GetQuestItemLink("choice", i)
				if (not itemLink) then
					itemLinkMissing = 1
					AutoGearPrint("AutoGear: No item link received from the server. To automatically choose a reward, you can try reopening quest rewards menu.", 0)
				else
					local _, _, Color, Ltype, id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
					questRewardIDs[i] = id
				end
			end
			if not itemLinkMissing then
				GetQuestReward(AutoGearConsiderAllItems(nil, questRewardIDs))
			end
		end
	end

	if (AutoGearDB.AutoAcceptPartyInvitations) then
		if (event == "PARTY_INVITE_REQUEST") then
			AutoGearPrint("AutoGear: Automatically accepting party invite.", 1)
			AcceptGroup()
			AutoGearFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		elseif (event == "GROUP_ROSTER_UPDATE") then --for closing the invite window once I have joined the group
			StaticPopup_Hide("PARTY_INVITE")
			AutoGearFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
		end
	end

	if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player" then
		--make sure this doesn't happen as part of logon
		if dataAvailable then
			local localizedClass, class, spec = AutoGearGetClassAndSpec()
			AutoGearPrint("AutoGear: Talent specialization changed.  Considering all items for gear that's better suited for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 2)
			AutoGearConsiderAllItems()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_CONTAINER_UPDATE" then
		AutoGearUpdateBestItems()
	elseif event == "START_LOOT_ROLL" then
		local link = GetLootRollItemLink(arg1)
		AutoGearHandleLootRoll(link, arg1)
	elseif event == "CONFIRM_LOOT_ROLL" or event == "CONFIRM_DISENCHANT_ROLL" then
		ConfirmLootRoll(arg1, arg2)
	elseif event == "CHAT_MSG_LOOT" then --when receiving a new item
		local message, name, guid = arg1, arg5, arg12
		local pattern1 = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern2 = LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern3 = LOOT_ITEM_CREATED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern4 = LOOT_ITEM_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
		local pattern5 = LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
		local pattern6 = LOOT_ITEM_CREATED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")

		local uname, userver = UnitFullName("player")
		local fullName = uname .. "-" .. userver

		if (guid and guid ~= UnitGUID("player"))
		or ((name ~= uname) and (name ~= fullName)) then
			return
		end

		local link, quantity = message:match(pattern1)
		if not link then
			link, quantity = message:match(pattern2)
			if not link then
				link, quantity = message:match(pattern3)
				if not link then
					quantity, link = 1, message:match(pattern4)
					if not link then
						quantity, link = 1, message:match(pattern5)
						if not link then
							quantity, link = 1, message:match(pattern6)
						end
					end
				end
			end
		end

		-- if it's not gear, return early to avoid scanning for upgrades
		if link and (C_Item.GetItemInventoryTypeByID(link) == Enum.InventoryType.IndexNonEquipType) then return end

		--make sure a fishing pole isn't replaced while fishing
		if (not AutoGearIsMainHandAFishingPole()) then
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
	elseif (event == "EQUIP_BIND_CONFIRM") or
	(event == "EQUIP_BIND_REFUNDABLE_CONFIRM") or
	(event == "EQUIP_BIND_TRADEABLE_CONFIRM") then
		local rarity = Item:CreateFromItemLocation(C_Cursor.GetCursorItem()):GetItemQuality()
		if rarity == nil then return end
		if ((rarity ~= 3) and (rarity ~= 4) and (AutoGearDB.AutoConfirmBinding == true)) or
		((rarity == 3) and (AutoGearDB.AutoConfirmBindingBlues == true)) or
		((rarity == 4) and (AutoGearDB.AutoConfirmBindingEpics == true)) then
			EquipPendingItem(arg1)
		end
	elseif event == "MERCHANT_SHOW" then
		if (AutoGearDB.AutoSellGreys == true) then
			-- sell all grey items
			local soldSomething = nil
			local totalSellValue = 0
			for i = 0, NUM_BAG_SLOTS do
				local slotMax = GetContainerNumSlots(i)
				for j = 0, slotMax do
					local count, locked, link = AutoGearGetContainerItemInfo(i, j)
					if (link) then
						local name = select(3, string.find(link, "^.*%[(.*)%].*$"))
						if (string.find(link,"|cff9d9d9d") and not locked and not AutoGearIsQuestItem(i,j)) then
							totalSellValue = totalSellValue + select(11, GetItemInfo(link)) * count
							PickupContainerItem(i, j)
							PickupMerchantItem()
							soldSomething = 1
						end
					end
				end
			end
			if (soldSomething) then
				AutoGearPrint("AutoGear: Sold all grey items for "..AutoGearCashToString(totalSellValue)..".", 1)
			end
		end
		if (AutoGearDB.AutoRepair == true) then
			-- repair all gear
			local cashString = AutoGearCashToString(GetRepairAllCost())
			if TOC_VERSION_CURRENT >= TOC_VERSION_TBC then
				if (GetRepairAllCost() > 0) then
					if (CanGuildBankRepair()) then
						RepairAllItems(1) --guild repair
						--fix this.  it doesn't see 0 yet, even if it repaired
						if (GetRepairAllCost() == 0) then
							AutoGearPrint("AutoGear: Repaired all items for "..cashString.." using guild funds.", 1)
						end
					end
				end
			end
			if (GetRepairAllCost() > 0) then
				if (GetRepairAllCost() <= GetMoney()) then
					AutoGearPrint("AutoGear: Repaired all items for "..cashString..".", 1)
					RepairAllItems()
				elseif (GetRepairAllCost() > GetMoney()) then
					AutoGearPrint("AutoGear: Not enough money to repair all items ("..cashString..").", 0)
				end
			end
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if not dataAvailable then
			dataAvailable = 1
			AutoGearFrame:UnregisterEvent(event)
		end
	elseif event ~= "ADDON_LOADED" then
		AutoGearPrint("AutoGear: event fired: "..event, 3)
	end
end)

function AutoGearDecideRoll(link, lootRollID)
	if not AutoGearCurrentWeighting then AutoGearSetStatWeights() end
	if AutoGearCurrentWeighting then
		local rollDecision = nil
		local canNeed = lootRollID and select(6,GetLootRollItemInfo(lootRollID)) or 1
		local lootRollItemID = GetItemInfoInstant(link)
		local rollItemInfo = AutoGearReadItemInfo(nil, nil, nil, nil, nil, link)
		local reason = rollItemInfo.reason or "(no reason set)"
		local wouldNeed = AutoGearConsiderAllItems(lootRollItemID, nil, rollItemInfo, true)
		if (AutoGearDB.RollOnNonGearLoot == false)
		and (not rollItemInfo.isGear)
		and (not rollItemInfo.isMount) then
			AutoGearPrint("AutoGear: "..rollItemInfo.link.." is not gear and \"Roll on non-gear loot\" is disabled, so not rolling.", 3)
			--local rollDecision is nil, so no roll
		elseif wouldNeed and canNeed then
			if rollItemInfo.Within5levels or (rollItemInfo.isMount and (not rollItemInfo.alreadyKnown)) then
				local maxNumberOfCopiesAllowedToNeed = (rollItemInfo.unique or (rollItemInfo.isMount and (not rollItemInfo.alreadyKnown))) and 1 or #rollItemInfo.validGearSlots
				local numberOfCopiesOwned = GetItemCount(rollItemInfo.id, true)
				if numberOfCopiesOwned >= maxNumberOfCopiesAllowedToNeed then
					AutoGearPrint("AutoGear: "..rollItemInfo.link.." is "..(rollItemInfo.isMount and "a mount" or "an upgrade usable within 5 levels")..", but you already have "..tostring(numberOfCopiesOwned).." cop"..(numberOfCopiesOwned == 1 and "y" or "ies")..", so rolling "..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE..".",3)
					rollDecision = 2 --greed
				else
					rollDecision = 1 --need
				end
			else
				rollDecision = 1 --need
			end
		else
			rollDecision = 2 --greed
			if (wouldNeed and not canNeed) then
				AutoGearPrint("AutoGear: Would roll NEED, but NEED is not an option for "..rollItemInfo.link..".", 1)
			end
		end
		return rollDecision, rollItemInfo, reason
	else
		local localizedClass, class, spec = AutoGearGetClassAndSpec()
		AutoGearPrint("AutoGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
	end
end

function AutoGearHandleLootRoll(link, lootRollID)
	local item = Item:CreateFromItemLink(link)
	item:ContinueOnItemLoad(function()
		AutoGearHandleLootRollCallback(link, lootRollID)
	end)
end

function AutoGearHandleLootRollCallback(link, lootRollID)
		local rollDecision, rollItemInfo, reason = AutoGearDecideRoll(link, lootRollID)
		if rollItemInfo.unusable then AutoGearPrint("AutoGear: "..link.." will not be equipped.  "..reason, 1) end
		if rollDecision then
			local newAction = {}
			newAction.action = "roll"
			newAction.t = GetTime() --roll right away
			newAction.rollID = lootRollID
			newAction.rollType = rollDecision
			newAction.info = rollItemInfo
			table.insert(futureAction, newAction)
		end
end

-- from Attrition addon
function AutoGearCashToString(cash)
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

function AutoGearIsQuestItem(container, slot)
	return AutoGearItemContainsText(container, slot, "Quest Item")
end

function AutoGearItemContainsText(container, slot, search)
	AutoGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
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

function AutoGearUpdateEquippedItems()
	AutoGearSetStatWeights()
	-- AutoGearItemInfoCache = {}
	AutoGearEquippedItems = {}
	local info, score
	for invSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
		if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= AutoGearFirstEquippableBagSlot then
			info = AutoGearReadItemInfo(invSlot)
			score = AutoGearDetermineItemScore(info)
			AutoGearEquippedItems[invSlot] = {}
			AutoGearEquippedItems[invSlot].info = info
			AutoGearEquippedItems[invSlot].score = score
			AutoGearEquippedItems[invSlot].equipped = 1
		end
	end

	--pretend the tabard slot is a separate slot for 2-handers
	if (AutoGearEquippedItems[INVSLOT_MAINHAND] and
	AutoGearEquippedItems[INVSLOT_MAINHAND].info and
	AutoGearEquippedItems[INVSLOT_MAINHAND].info.is2hWeapon and
	(not ((weapons == "2hDW") and CanDualWield() and IsPlayerSpell(46917)))) then
		AutoGearEquippedItems[INVSLOT_TABARD] = AutoGearDeepCopy(AutoGearEquippedItems[INVSLOT_MAINHAND])
		AutoGearEquippedItems[INVSLOT_MAINHAND].info = { name = "nothing", empty = 1 }
		AutoGearEquippedItems[INVSLOT_MAINHAND].score = 0
		AutoGearEquippedItems[INVSLOT_MAINHAND].equipped = nil
	else
		AutoGearEquippedItems[INVSLOT_TABARD] = {}
		AutoGearEquippedItems[INVSLOT_TABARD].info = { name = "nothing", empty = 1 }
		AutoGearEquippedItems[INVSLOT_TABARD].score = 0
		AutoGearEquippedItems[INVSLOT_TABARD].equipped = nil
	end
end

function AutoGearDeepCopy(object)
    local object_type = type(object)
    local newObject
    if object_type == 'table' then
        newObject = {}
        for orig_key, orig_value in next, object, nil do
            newObject[AutoGearDeepCopy(orig_key)] = AutoGearDeepCopy(orig_value)
        end
        setmetatable(newObject, AutoGearDeepCopy(getmetatable(object)))
    else -- number, string, boolean, etc
        newObject = object
    end
    return newObject
end

function AutoGearUpdateBestItems()
	AutoGearUpdateEquippedItems()

	--set starting best scores from all equipped items
	AutoGearBestItems = AutoGearDeepCopy(AutoGearEquippedItems)

	local info

	-- table to track whether an item's been added
	AutoGearBestItemsAlreadyAdded = {}

	--consider all items in bags
	for bag = 0, NUM_BAG_SLOTS do
		local slotMax = GetContainerNumSlots(bag)
		for slot = 0, slotMax do
			info = AutoGearReadItemInfo(nil, nil, bag, slot)
			AutoGearConsiderItem(info, bag, slot, nil)
		end
	end
	--consider quest rewards (if any)
	for i = 1, GetNumQuestChoices() do
		info = AutoGearReadItemInfo(nil, nil, nil, nil, i)
		AutoGearConsiderItem(info, nil, nil, nil, i)
	end
end

function AutoGearConsiderAllItems(lootRollItemID, questRewardIDs, arbitraryItemInfo, noActions)
	if (arbitraryItemInfo and arbitraryItemInfo.isMount and (not arbitraryItemInfo.alreadyKnown)) then
		return 1
	end

	local anythingBetter = nil

	AutoGearUpdateBestItems()

	--consider item being rolled on (if any)
	if lootRollItemID and arbitraryItemInfo then
		AutoGearConsiderItem(arbitraryItemInfo, nil, nil, 1)
	end

	--create all future equip actions required (only if not rolling currently)
	if (not lootRollItemID and not questRewardIDs and not noActions) then
		for invSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
			if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= AutoGearFirstEquippableBagSlot then
				if invSlot == INVSLOT_MAINHAND or invSlot == INVSLOT_OFFHAND or invSlot == INVSLOT_TABARD then
					--skip weapons for now
				else
					local isSlotLocked = AutoGearDB.LockGearSlots and AutoGearDB.LockedGearSlots[invSlot].enabled
					local equippedInfo = AutoGearEquippedItems[invSlot].info
					local equippedScore = AutoGearEquippedItems[invSlot].score
					if (not AutoGearBestItems[invSlot].equipped) then
						anythingBetter = 1
						AutoGearPrint("AutoGear: "..(AutoGearBestItems[invSlot].info.link or AutoGearBestItems[invSlot].info.name).." ("..string.format("%.2f", AutoGearBestItems[invSlot].score)..") was determined to be better than "..(equippedInfo.link or equippedInfo.name).." ("..string.format("%.2f", equippedScore)..").  "..((AutoGearDB.Enabled == true) and (isSlotLocked and "Would equip, but slot "..tostring(invSlot or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						AutoGearPrintItem(AutoGearBestItems[invSlot].info)
						AutoGearPrintItem(equippedInfo)
						if not isSlotLocked then
							local newAction = {}
							newAction.action = "equip"
							newAction.t = GetTime()
							newAction.container = AutoGearBestItems[invSlot].bag
							newAction.slot = AutoGearBestItems[invSlot].slot
							newAction.replaceSlot = invSlot
							newAction.info = AutoGearBestItems[invSlot].info
							newAction.score = AutoGearBestItems[invSlot].score
							table.insert(futureAction, newAction)
						end
					end
				end
			end
		end
		--handle weapons
		local isMainHandSlotLocked = AutoGearDB.LockGearSlots and AutoGearDB.LockedGearSlots[INVSLOT_MAINHAND].enabled
		local isOffHandSlotLocked = AutoGearDB.LockGearSlots and AutoGearDB.LockedGearSlots[INVSLOT_OFFHAND].enabled
		if (AutoGearBestItems[INVSLOT_MAINHAND].score + AutoGearBestItems[INVSLOT_OFFHAND].score > AutoGearBestItems[INVSLOT_TABARD].score)
		or (AutoGearEquippedItems[INVSLOT_TABARD].info.unusable)
		or (((not AutoGearBestItems[INVSLOT_MAINHAND].info.empty)
		or (not AutoGearBestItems[INVSLOT_OFFHAND].info.empty))
		and AutoGearBestItems[INVSLOT_TABARD].info.empty) then
			local extraDelay = 0
			local mainSwap, offSwap
			--main hand
			if (not AutoGearBestItems[INVSLOT_MAINHAND].equipped) and (not AutoGearBestItems[INVSLOT_MAINHAND].info.empty) then
				mainSwap = 1
				if not isMainHandSlotLocked then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime()
					newAction.container = AutoGearBestItems[INVSLOT_MAINHAND].bag
					newAction.slot = AutoGearBestItems[INVSLOT_MAINHAND].slot
					newAction.replaceSlot = INVSLOT_MAINHAND
					newAction.info = AutoGearBestItems[INVSLOT_MAINHAND].info
					newAction.score = AutoGearBestItems[INVSLOT_MAINHAND].score
					table.insert(futureAction, newAction)
					extraDelay = 0.5
				end
			end
			--off-hand
			if (not AutoGearBestItems[INVSLOT_OFFHAND].equipped) and (not AutoGearBestItems[INVSLOT_OFFHAND].info.empty) then
				offSwap = 1
				if not isOffHandSlotLocked then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime() + extraDelay --do it after a longer delay
					newAction.container = AutoGearBestItems[INVSLOT_OFFHAND].bag
					newAction.slot = AutoGearBestItems[INVSLOT_OFFHAND].slot
					newAction.replaceSlot = INVSLOT_OFFHAND
					newAction.info = AutoGearBestItems[INVSLOT_OFFHAND].info
					newAction.score = AutoGearBestItems[INVSLOT_OFFHAND].score
					table.insert(futureAction, newAction)
				end
			end
			if (mainSwap or offSwap) then
				anythingBetter = 1
				if (mainSwap and offSwap) then
					if (AutoGearIsTwoHandEquipped()) then
						local equippedMain = AutoGearEquippedItems[INVSLOT_TABARD].info
						local mainScore = AutoGearEquippedItems[INVSLOT_TABARD].score
						AutoGearPrint("AutoGear: "..(AutoGearBestItems[INVSLOT_MAINHAND].info.link or AutoGearBestItems[INVSLOT_MAINHAND].info.name).." ("..string.format("%.2f", AutoGearBestItems[INVSLOT_MAINHAND].score)..") combined with "..(AutoGearBestItems[INVSLOT_OFFHAND].info.link or AutoGearBestItems[INVSLOT_OFFHAND].info.name).." ("..string.format("%.2f", AutoGearBestItems[INVSLOT_OFFHAND].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..").  "..((AutoGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						AutoGearPrintItem(AutoGearBestItems[INVSLOT_MAINHAND].info)
						AutoGearPrintItem(AutoGearBestItems[INVSLOT_OFFHAND].info)
						AutoGearPrintItem(equippedMain)
					else
						local equippedMain = AutoGearEquippedItems[INVSLOT_MAINHAND].info
						local mainScore = AutoGearEquippedItems[INVSLOT_MAINHAND].score
						local equippedOff = AutoGearEquippedItems[INVSLOT_OFFHAND].info
						local offScore = AutoGearEquippedItems[INVSLOT_OFFHAND].score
						AutoGearPrint("AutoGear: "..(AutoGearBestItems[INVSLOT_MAINHAND].info.link or AutoGearBestItems[INVSLOT_MAINHAND].info.name).." ("..string.format("%.2f", AutoGearBestItems[INVSLOT_MAINHAND].score)..") combined with "..(AutoGearBestItems[INVSLOT_OFFHAND].info.link or AutoGearBestItems[INVSLOT_OFFHAND].info.name).." ("..string.format("%.2f", AutoGearBestItems[INVSLOT_OFFHAND].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.link or equippedOff.name).." ("..string.format("%.2f", offScore)..").  "..((AutoGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						AutoGearPrintItem(AutoGearBestItems[INVSLOT_MAINHAND].info)
						AutoGearPrintItem(AutoGearBestItems[INVSLOT_OFFHAND].info)
						AutoGearPrintItem(equippedMain)
						AutoGearPrintItem(equippedOff)
					end
				else
					local invSlot = INVSLOT_MAINHAND
					if (offSwap) then invSlot = INVSLOT_OFFHAND end
					local equippedInfo = AutoGearEquippedItems[invSlot].info
					local equippedScore = AutoGearEquippedItems[invSlot].score
					AutoGearPrint("AutoGear: "..(AutoGearBestItems[invSlot].info.link or AutoGearBestItems[invSlot].info.name).." ("..string.format("%.2f", AutoGearBestItems[invSlot].score)..") was determined to be better than "..(equippedInfo.link or equippedInfo.name).." ("..string.format("%.2f", equippedScore)..").  "..((AutoGearDB.Enabled == true) and (((invSlot == INVSLOT_MAINHAND and isMainHandSlotLocked) or (invSlot == INVSLOT_OFFHAND and isOffHandSlotLocked)) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
					AutoGearPrintItem(AutoGearBestItems[invSlot].info)
					AutoGearPrintItem(equippedInfo)
				end
			end
		elseif (AutoGearBestItems[INVSLOT_TABARD].score > (AutoGearBestItems[INVSLOT_MAINHAND].score + AutoGearBestItems[INVSLOT_OFFHAND].score))
		or ((not AutoGearBestItems[INVSLOT_TABARD].info.empty)
		and ((AutoGearBestItems[INVSLOT_MAINHAND].info.empty)
		and (AutoGearBestItems[INVSLOT_OFFHAND].info.empty))) then
			if (not AutoGearBestItems[INVSLOT_TABARD].equipped) and (not AutoGearBestItems[INVSLOT_TABARD].info.empty) then
				anythingBetter = 1
				local showBothSlots = AutoGearIsTwoHandEquipped()
				local mainSlot = showBothSlots and INVSLOT_TABARD or INVSLOT_MAINHAND
				local equippedMain = AutoGearEquippedItems[mainSlot].info
				local mainScore = AutoGearEquippedItems[mainSlot].score
				local equippedOff = AutoGearEquippedItems[INVSLOT_OFFHAND].info
				local offScore = AutoGearEquippedItems[INVSLOT_OFFHAND].score
				AutoGearPrint("AutoGear: "..(AutoGearBestItems[INVSLOT_TABARD].info.link or AutoGearBestItems[INVSLOT_TABARD].info.name).." ("..string.format("%.2f", AutoGearBestItems[INVSLOT_TABARD].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..")"..(showBothSlots and ((" combined with "..(equippedOff.link or equippedOff.name).." ("..string.format("%.2f", offScore))..")") or "")..".  "..((AutoGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
				AutoGearPrintItem(AutoGearBestItems[INVSLOT_TABARD].info)
				AutoGearPrintItem(equippedMain)
				if showBothSlots then AutoGearPrintItem(equippedOff) end
				if (not isMainHandSlotLocked) and (not isOffHandSlotLocked) then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime() + 0.5 --do it after a short delay
					newAction.container = AutoGearBestItems[INVSLOT_TABARD].bag
					newAction.slot = AutoGearBestItems[INVSLOT_TABARD].slot
					newAction.replaceSlot = INVSLOT_MAINHAND
					newAction.info = AutoGearBestItems[INVSLOT_TABARD].info
					newAction.score = AutoGearBestItems[INVSLOT_TABARD].score
					table.insert(futureAction, newAction)
				end
			end
		end
	elseif (lootRollItemID) then
		--decide whether to roll on the item or not
		for invSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
			if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= AutoGearFirstEquippableBagSlot then
				if (AutoGearBestItems[invSlot].rollOn and
				(invSlot ~= INVSLOT_MAINHAND or invSlot ~= INVSLOT_OFFHAND or AutoGearIs1hWorthwhile(invSlot)) and
				(invSlot ~= INVSLOT_TABARD or AutoGearIsBest2hBetterThanBestMainAndOff())) then
					return 1
				end
			end
		end
		return nil
	elseif (questRewardIDs and not noActions) then
		--choose a quest reward
		--pick the reward with the biggest score improvement
		local bestRewardIndex
		local bestRewardScoreDelta
		for invSlot = INVSLOT_FIRST_EQUIPPED, AutoGearLastEquippableBagSlot do
			if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= AutoGearFirstEquippableBagSlot then
				if (AutoGearBestItems[invSlot].chooseReward and (invSlot ~= INVSLOT_TABARD or AutoGearIsBest2hBetterThanBestMainAndOff())) then
					local delta = AutoGearBestItems[invSlot].score - AutoGearEquippedItems[invSlot].score
					if (not bestRewardScoreDelta or delta > bestRewardScoreDelta) then
						bestRewardScoreDelta = delta
						bestRewardIndex = AutoGearBestItems[invSlot].chooseReward
					end
				end
			end
		end
		if (not bestRewardIndex) then
			--no gear upgrades, so choose the one with the highest sell value
			local bestRewardVendorPrice
			for i = 1, GetNumQuestChoices() do
				local vendorPrice = select(11,GetItemInfo(questRewardIDs[i]))
				if (not bestRewardVendorPrice) or (vendorPrice > bestRewardVendorPrice) then
					bestRewardIndex = i
					bestRewardVendorPrice = vendorPrice
				end
			end
		end
		return bestRewardIndex
	end
	return anythingBetter
end

function AutoGearIsBest2hBetterThanBestMainAndOff()
	return AutoGearBestItems[INVSLOT_TABARD].score > AutoGearBestItems[INVSLOT_MAINHAND].score + AutoGearBestItems[INVSLOT_OFFHAND].score
end

function AutoGearIs1hWorthwhile(i)
	-- 3x the highest weight among the 5 main stats
	local minScore = 3 * math.max(unpack({
		AutoGearCurrentWeighting.Strength or 0,
		AutoGearCurrentWeighting.Agility or 0,
		AutoGearCurrentWeighting.Stamina or 0,
		AutoGearCurrentWeighting.Intellect or 0,
		AutoGearCurrentWeighting.Spirit or 0}))
	return AutoGearBestItems[i].score > minScore and AutoGearBestItems[i].score > AutoGearBestItems[INVSLOT_TABARD].score * (i == INVSLOT_MAINHAND and 0.15 or 0.05)
end

--companion function to AutoGearConsiderAllItems
function AutoGearConsiderItem(info, bag, slot, rollOn, chooseReward)
	if info.empty
	or (info.link and AutoGearBestItemsAlreadyAdded[info.link])
	or (info.isAmmoBag
	and	AutoGearBestItems[INVSLOT_RANGED].info.isRangedWeapon)
	and (not AutoGearIsAmmoBagValidForRangedWeapon(info, AutoGearBestItems[INVSLOT_RANGED].info)) then
		return
	end
	if (info.isMount and (not info.alreadyKnown)) then return true end
	if (info.usable or (rollOn and info.Within5levels)) then
		local score = AutoGearDetermineItemScore(info)
		if info.isGear and info.validGearSlots then
			local firstValidGearSlot = info.validGearSlots[1]
			local lowestScoringValidGearSlot = firstValidGearSlot
			local lowestScoringValidGearSlotScore = AutoGearBestItems[firstValidGearSlot].score
			for _, gearSlot in pairs(info.validGearSlots) do
				local skipThisSlot = false
				for _, otherGearSlot in pairs(info.validGearSlots) do
					if gearSlot ~= otherGearSlot then
						if not AutoGearIsGearPairEquippableTogether(info, AutoGearBestItems[otherGearSlot].info) then
							skipThisSlot = true
						end
					end
				end
				if not skipThisSlot and
				((AutoGearBestItems[gearSlot].score < lowestScoringValidGearSlotScore)
				or AutoGearBestItems[gearSlot].info.empty) then
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = AutoGearBestItems[gearSlot].score
				end
			end

			if (
				((score > lowestScoringValidGearSlotScore) and (not info.isAmmoBag))
				or AutoGearBestItems[lowestScoringValidGearSlot].info.empty
				or AutoGearBestItems[lowestScoringValidGearSlot].info.unusable
				or (info.isAmmoBag
					and AutoGearIsAmmoBagValidForBestKnownRangedWeapon(info)
					and ((score > lowestScoringValidGearSlotScore)
					or (not AutoGearIsAmmoBagValidForBestKnownRangedWeapon(AutoGearBestItems[lowestScoringValidGearSlot].info)))
				)
			) then
				AutoGearBestItemsAlreadyAdded[info.link] = 1
				AutoGearBestItems[lowestScoringValidGearSlot].info = info
				AutoGearBestItems[lowestScoringValidGearSlot].score = score
				AutoGearBestItems[lowestScoringValidGearSlot].equipped = nil
				AutoGearBestItems[lowestScoringValidGearSlot].bag = bag
				AutoGearBestItems[lowestScoringValidGearSlot].slot = slot
				AutoGearBestItems[lowestScoringValidGearSlot].rollOn = rollOn
				AutoGearBestItems[lowestScoringValidGearSlot].chooseReward = chooseReward
				return true
			end
		end
	end
end

function AutoGearIsAmmoBagValidForBestKnownRangedWeapon(info)
	return AutoGearIsAmmoBagValidForRangedWeapon (
		info,
		(AutoGearBestItems and AutoGearBestItems[INVSLOT_RANGED])
		and AutoGearBestItems[INVSLOT_RANGED].info
		or AutoGearReadItemInfo(INVSLOT_RANGED)
	)
end

function AutoGearGetValidGearSlots(info)
	local gearSlotTable = {
		[Enum.InventoryType.IndexNonEquipType]       = nil,
		[Enum.InventoryType.IndexAmmoType]           = nil, -- ignore ammo because it's hard to match with weapon type
		[Enum.InventoryType.IndexHeadType]           = { INVSLOT_HEAD },
		[Enum.InventoryType.IndexNeckType]           = { INVSLOT_NECK },
		[Enum.InventoryType.IndexShoulderType]       = { INVSLOT_SHOULDER },
		[Enum.InventoryType.IndexBodyType]           = { INVSLOT_BODY },
		[Enum.InventoryType.IndexChestType]          = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexRobeType]           = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexWaistType]          = { INVSLOT_WAIST },
		[Enum.InventoryType.IndexLegsType]           = { INVSLOT_LEGS },
		[Enum.InventoryType.IndexFeetType]           = { INVSLOT_FEET },
		[Enum.InventoryType.IndexWristType]          = { INVSLOT_WRIST },
		[Enum.InventoryType.IndexHandType]           = { INVSLOT_HAND },
		[Enum.InventoryType.IndexFingerType]         = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
		[Enum.InventoryType.IndexTrinketType]        = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
		[Enum.InventoryType.IndexCloakType]          = { INVSLOT_BACK },
		[Enum.InventoryType.IndexWeaponType]         = ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and (CanDualWield()
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or { INVSLOT_MAINHAND })
		                                               or ((weapons == "weapon and shield")
		                                               and { INVSLOT_MAINHAND }
		                                               or nil),
		[Enum.InventoryType.IndexShieldType]         = ((weapons == "any")
		                                               or (weapons == "weapon and shield"))
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.Index2HweaponType]       = ((weapons == "2hDW")
		                                               and CanDualWield() and IsPlayerSpell(46917)
		                                               and (info.subclassID ~= Enum.ItemWeaponSubclass.Staff)
		                                               and ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
		                                               or (info.subclassID ~= Enum.ItemWeaponSubclass.Polearm)))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or (((weapons == "any")
		                                               or (weapons == "2h"))
		                                               and { INVSLOT_TABARD }
		                                               or nil),
		[Enum.InventoryType.IndexWeaponmainhandType] = ((weapons == "any")
		                                               or (weapons == "weapon and shield")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and { INVSLOT_MAINHAND }
		                                               or nil,
		[Enum.InventoryType.IndexWeaponoffhandType]  = (CanDualWield()
		                                               and ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917))))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexHoldableType]       = (weapons == "any")
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexRangedType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or { INVSLOT_MAINHAND },
		[Enum.InventoryType.IndexThrownType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or { INVSLOT_MAINHAND },
		[Enum.InventoryType.IndexRangedrightType]    = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or { INVSLOT_MAINHAND },
		[Enum.InventoryType.IndexRelicType]          = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or nil,
		[Enum.InventoryType.IndexTabardType]         = nil, -- INVSLOT_TABARD is used for evaluating 2h weapons
		[Enum.InventoryType.IndexBagType]            = AutoGearEquippableBagSlots,
		[Enum.InventoryType.IndexQuiverType]         = (weapons == "ranged")
		                                               and AutoGearEquippableBagSlots
                                                       or nil
	}

	return gearSlotTable[info.invType]
end

function AutoGearIsInvTypeWeapon(invType)
	if not invType then return nil end
	return AutoGearIsInvTypeTwoHanded(invType) or
	AutoGearIsInvTypeOneHanded(invType) or
	AutoGearIsInvTypeRangedOrRelic(invType)
end

function AutoGearIsInvTypeOneHanded(invType)
	if not invType then return nil end
	return (invType == Enum.InventoryType.IndexWeaponType) or
	(invType == Enum.InventoryType.IndexWeaponmainhandType) or
	(invType == Enum.InventoryType.IndexWeaponoffhandType) or
	(invType == Enum.InventoryType.IndexShieldType) or
	(invType == Enum.InventoryType.IndexHoldableType)
end

function AutoGearIsInvTypeTwoHanded(invType)
	if not invType then return nil end
	return (invType == Enum.InventoryType.Index2HweaponType) or (
		(TOC_VERSION_CURRENT >= TOC_VERSION_MOP) and (
			(invType == Enum.InventoryType.IndexRangedType) or (
				invType == Enum.InventoryType.IndexRangedrightType
			)
		)
	)
end

function AutoGearIsInvTypeRangedOrRelic(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		AutoGearIsInvTypeRanged(invType) or
		AutoGearIsInvTypeRelic(invType)
	)
end

function AutoGearIsInvTypeRanged(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		(invType == Enum.InventoryType.IndexRangedType) or
		(invType == Enum.InventoryType.IndexRangedrightType) or
		(invType == Enum.InventoryType.IndexThrownType)
	)
end

function AutoGearIsInvTypeRelic(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		invType == Enum.InventoryType.IndexRelicType
	)
end

function AutoGearIsAmmoBagAQuiverForArrows(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.isAmmoBag) and (info.subclassID == 2)
end

function AutoGearIsAmmoBagABulletPouch(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.isAmmoBag) and (info.subclassID == 3)
end

function AutoGearIsAmmoBagValidForRangedWeapon(ammoBag, rangedWeapon)
	if (not ammoBag.isAmmoBag)
	or (not rangedWeapon.isRangedWeapon)
	or (not rangedWeapon.classID)
	or (not rangedWeapon.subclassID) then
		return nil
	end
	return (AutoGearIsAmmoBagAQuiverForArrows(ammoBag) and
	(AutoGearIsRangedWeaponABowOrCrossbow(rangedWeapon))) or
	(AutoGearIsAmmoBagABulletPouch(ammoBag) and
	AutoGearIsRangedWeaponAGun(rangedWeapon))
end

function AutoGearIsRangedWeaponABowOrCrossbow(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.classID == Enum.ItemClass.Weapon) and
	((info.subclassID == Enum.ItemWeaponSubclass.Bows) or
	(info.subclassID == Enum.ItemWeaponSubclass.Crossbow))
end

function AutoGearIsRangedWeaponAGun(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return ((info.classID == Enum.ItemClass.Weapon) and
	(info.subclassID == Enum.ItemWeaponSubclass.Guns))
end

function AutoGearIsItemTwoHanded(itemID)
	if not itemID then return nil end
	return AutoGearIsInvTypeTwoHanded(C_Item.GetItemInventoryTypeByID(itemID))
end

function AutoGearIsTwoHandEquipped()
	return AutoGearIsItemTwoHanded(GetInventoryItemID("player", INVSLOT_MAINHAND))
end

function AutoGearIsMainHandAFishingPole()
	local mainHandID = GetInventoryItemID("player", INVSLOT_MAINHAND)
	if mainHandID then
		local itemClassID, itemSubClassID = select(6, GetItemInfoInstant(GetInventoryItemID("player", INVSLOT_MAINHAND)))
		return ((itemClassID == Enum.ItemClass.Weapon) and (itemSubClassID == Enum.ItemWeaponSubclass.Fishingpole))
	end
end

function AutoGearPrintItem(info)
	AutoGearPrint("AutoGear:     "..(info.link or info.name)..":", 2)
	if AutoGearDB.UsePawn and PawnIsReady and PawnIsReady() then
		local pawnScaleName, pawnScaleLocalizedName = AutoGearGetPawnScaleName()
		local pawnScaleColor = PawnGetScaleColor(pawnScaleName)
		local score = AutoGearDetermineItemScore(info)
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		AutoGearPrint("AutoGear:         "..(((pawnScaleLocalizedName or pawnScaleName) and pawnScaleColor) and ("Pawn \""..pawnScaleColor..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"") or "AutoGear").." score: "..(score or "nil"),2)
	elseif (not (AutoGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
		for k,v in pairs(info) do
			if (k ~= "Name" and AutoGearCurrentWeighting[k]) then
				AutoGearPrint("AutoGear:         "..k..": "..string.format("%.2f", v).." * "..AutoGearCurrentWeighting[k].." = "..string.format("%.2f", v * AutoGearCurrentWeighting[k]), 2)
			end
		end
	else
		AutoGearPrint("AutoGear:         (error: Stats aren't ready to be printed.)", 2)
	end
end

function AutoGearReadItemInfo(inventoryID, lootRollID, container, slot, questRewardIndex, link)
	AutoGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	AutoGearTooltip:ClearLines()

	local info = {}

	if container and slot then
		info.item = Item:CreateFromBagAndSlot(container, slot)
		if info.item:IsItemEmpty() then
			info.empty = 1
			info.name = "nothing"
			return info
		end
		info.link = info.item:GetItemLink()
		AutoGearTooltip:SetBagItem(container, slot)
	elseif inventoryID then
		info.item = Item:CreateFromEquipmentSlot(inventoryID)
		if info.item:IsItemEmpty() then
			info.empty = 1
			info.name = "nothing"
			return info
		end
		info.link = info.item:GetItemLink()
		AutoGearTooltip:SetInventoryItem("player", inventoryID)
	elseif lootRollID then
		info.link = GetLootRollItemLink(lootRollID)
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		AutoGearTooltip:SetLootRollItem(lootRollID)
	elseif questRewardIndex then
		info.link = GetQuestItemLink("choice", questRewardIndex)
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		AutoGearTooltip:SetQuestItem("choice", questRewardIndex)
	elseif link then
		info.link = link
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		AutoGearTooltip:SetHyperlink(info.link)
	else
		AutoGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; questRewardIndex: "..tostring(questRewardIndex or "nil")..
			"; link: "..tostring(link or "nil"),
			3
		)
	end

	info.id = info.item:GetItemID()
	if not info.id then
		AutoGearPrint("Error: "..tostring(info.name or "nil").." doesn't have an item ID",3)
		AutoGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; questRewardIndex: "..tostring(questRewardIndex or "nil")..
			"; link: "..tostring(info.link or "nil"),
			3
		)
		return info
	end
	info.classID, info.subclassID = select(6,GetItemInfoInstant(info.id))
	info.name = C_Item.GetItemNameByID(info.id)
	info.rarity = info.item:GetItemQuality()
	info.rarityColor = info.item:GetItemQualityColor()
	if info.link == nil then
		AutoGearPrint("Error: "..tostring(info.name or "nil").." doesn't have a link",3)
		AutoGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; questRewardIndex: "..tostring(questRewardIndex or "nil")..
			"; link: "..tostring(info.link or "nil"),
			3
		)
		return info
	end

	-- EF: this might actually be breaking it as I think it's caching empty tooltips before they're fully loaded
	-- caching did not show a performance benefit, so commented this and the below out
	-- info.linkHash = AutoGearStringHash(info.link)
	-- local cachediteminfo = AutoGearItemInfoCache[info.linkHash]
	-- if cachediteminfo then return cachediteminfo end

	info.invType = C_Item.GetItemInventoryTypeByID(info.id) or 0
	info.isGear = info.invType > 0

	if (info.classID == Enum.ItemClass.Miscellaneous) and
	(info.subclassID == Enum.ItemMiscellaneousSubclass.Mount) then
		info.isMount = 1
		if AutoGearIsMountItemAlreadyCollected(info.id) then
			info.alreadyKnown = 1
		end
	elseif not info.isGear then
		return info -- return early if the item isn't a mount or gear
	end

	info.RedSockets = 0
	info.YellowSockets = 0
	info.BlueSockets = 0
	info.MetaSockets = 0
	local localizedClass, class, spec = AutoGearGetClassAndSpec()

	if info.isGear then
		if AutoGearIsInvTypeWeapon(info.invType) then
			info.isWeaponOrOffHand = 1
		end
		if AutoGearIsInvTypeTwoHanded(info.invType) then
			info.is2hWeapon = 1
		elseif AutoGearIsInvTypeOneHanded(info.invType) then
			info.is1hWeaponOrOffHand = 1
		elseif AutoGearIsInvTypeRanged(info.invType) then
			info.isRangedWeapon = 1
		elseif AutoGearIsInvTypeRelic(info.invType) then
			info.isRelic = 1
		end
		if info.classID == Enum.ItemClass.Quiver then
			info.isAmmoBag = 1
		end
		info.validGearSlots = AutoGearGetValidGearSlots(info)
		info.numValidGearSlots = 0
		if not info.validGearSlots then
			info.unusable = 1
			info.reason = "(invalid item for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..")"
		else
			for _, slot in pairs(info.validGearSlots) do
				info.numValidGearSlots = info.numValidGearSlots + 1
			end
		end
	end

	local numLines = AutoGearTooltip:NumLines()

	for i = 1, numLines do
		local textLeft = getglobal("AutoGearTooltipTextLeft"..i)
		if textLeft then
			local r, g, b = textLeft:GetTextColor()
			local textLeftText = textLeft:GetText()
			local text = select(1,string.gsub(textLeftText:lower(),",",""))
			if i==1 then
				info.name = textLeft:GetText()
				if info.name == "Retrieving item information" or not info.item:IsItemDataCached() then
					if not AutoGearIsItemDataMissing then
						AutoGearPrint("AutoGear: An item was not yet ready on the client side when updating AutoGear's local item info, so updating AutoGear's table of equipped items again.",3)
						table.insert(futureAction, { action = "localupdate", t = GetTime() + 0.5 })
						AutoGearIsItemDataMissing = 1
					end
					info.unusable = 1
					info.reason = "(this item's tooltip is not yet available)"
				end
			end
			if (i==2 or i==3) then
				-- local currentItem = GameTooltip:GetItem()
				-- if currentItem and info.id == Item:CreateFromItemLink(currentItem):GetItemID() then AutoGearPrint(text,3) end
				if string.find(textLeftText, ITEM_BIND_ON_EQUIP) or
				string.find(textLeftText, ITEM_BIND_ON_USE) then
					info.boe = 1
				end
				if string.find(textLeftText, ITEM_SOULBOUND) or
				string.find(textLeftText, ITEM_BIND_ON_PICKUP) or
				string.find(textLeftText, ITEM_BIND_TO_ACCOUNT) or
				string.find(textLeftText, ITEM_BIND_TO_BNETACCOUNT) or
				string.find(textLeftText, ITEM_BIND_QUEST) then
					info.bop = 1
				end
			end
			if (i==numLines) and
			(not info.bop) then
				info.boe = 1
			end
			local multiplier = 1.0
			if string.find(text, "chance to") and not string.find(text, "improves") then multiplier = multiplier/3.0 end
			if string.find(text, "use:") then multiplier = multiplier/6.0 end
			-- don't count greyed out set bonus lines
			if r < 0.8 and g < 0.8 and b < 0.8 and string.find(text, "set:") then multiplier = 0 end
			-- note: these proc checks may not be correct for all cases
			if string.find(text, "deal damage") then multiplier = multiplier * (AutoGearCurrentWeighting.DamageProc or 0) end
			if string.find(text, "damage and healing") then multiplier = multiplier * math.max((AutoGearCurrentWeighting.HealingProc or 0), (AutoGearCurrentWeighting.DamageProc or 0))
			elseif string.find(text, "healing spells") then multiplier = multiplier * (AutoGearCurrentWeighting.HealingProc or 0)
			elseif string.find(text, "damage spells") then multiplier = multiplier * (AutoGearCurrentWeighting.DamageSpellProc or 0)
			end
			if string.find(text, "melee and ranged") then multiplier = multiplier * math.max((AutoGearCurrentWeighting.MeleeProc or 0), (AutoGearCurrentWeighting.RangedProc or 0))
			elseif string.find(text, "melee attacks") then multiplier = multiplier * (AutoGearCurrentWeighting.MeleeProc or 0)
			elseif string.find(text, "ranged attacks") then multiplier = multiplier * (AutoGearCurrentWeighting.RangedProc or 0)
			end
			local value = tonumber(string.match(text, "-?[0-9]+%.?[0-9]*")) or 0
			if value then
				value = value * multiplier
			else
				value = 0
			end
			if value > 0
			and (
				string.find(text, " bag") or
				string.find(text, " quiver") or
				string.find(text, " ammo pouch")
			) then
				info.numBagSlots = (info.numBagSlots or 0) + value
			end
			if value > 0
			and info.isAmmoBag
			and string.find(text, "ranged attack speed") then
				info.ammoBagRangedAttackSpeed = (info.ammoBagRangedAttackSpeed or 0) + value
			end
			if string.find(text, "unique") then
				info.unique = 1
			end
			if string.find(text, "already known") then
				info.alreadyKnown = 1
				info.unusable = 1
				info.reason = "(this item has been learned already)"
			end
			local isHealer = spec=="Holy" or spec=="Restoration" or spec=="Mistweaver" or spec=="Discipline"
			if string.find(text, L["strength"]) then info.Strength = (info.Strength or 0) + value end
			if string.find(text, L["agility"]) then info.Agility = (info.Agility or 0) + value end
			if string.find(text, L["intellect"]) then info.Intellect = (info.Intellect or 0) + value end
			if string.find(text, L["stamina"]) then info.Stamina = (info.Stamina or 0) + value end
			if string.find(text, L["spirit"]) then info.Spirit = (info.Spirit or 0) + value end
			if string.find(text, L["armor"]) and not string.find(text, "lowers their armor") then info.Armor = (info.Armor or 0) + value end
			if string.find(text, "attack power") and not string.find(text, "when fighting") and (not string.find(text, "forms only") or class=="DRUID") then info.AttackPower = (info.AttackPower or 0) + value end
			if ((string.find(text, "spell power") or string.find(text, "spell damage")) or
				string.find(text, "damage and healing") or
				(string.find(text, "frost spell damage") or string.find(text, "damage done by frost spells and effects")) and (spec=="Frost" or class=="MAGE" and spec=="None") or
				(string.find(text, "fire spell damage") or string.find(text, "damage done by fire spells and effects")) and (spec=="Fire" or class=="MAGE" and spec=="None") or
				(string.find(text, "arcane spell damage") or string.find(text, "damage done by arcane spells and effects")) and (spec=="Arcane" or class=="MAGE" and spec=="None") or
				(string.find(text, "shadow spell damage") or string.find(text, "damage done by shadow spells and effects")) and (class=="WARLOCK") or
				(string.find(text, "nature spell damage") or string.find(text, "damage done by nature spells and effects")) and (spec=="Balance" or class=="DRUID" and spec=="None") or
				(string.find(text, "healing") and isHealer) or
				(string.find(text, "increases healing done") and isHealer)) then info.SpellPower = (info.SpellPower or 0) + value
			end
			if TOC_VERSION_CURRENT < TOC_VERSION_WOTLK then
				if string.find(text, "critical strike with spells by") or string.find(text, "spell critical strike") or string.find(text, "spell critical rating") then info.SpellCrit = (info.SpellCrit or 0) + value end
				if string.find(text, "critical strike by") then info.Crit = (info.Crit or 0) + value end
				if string.find(text, "hit with spells by") or string.find(text, "spell hit rating by") then info.SpellHit = (info.SpellHit or 0) + value end
				if string.find(text, "critical strike by") then info.Crit = (info.Crit or 0) + value end
			else
				if string.find(text, "critical strike") then info.Crit = (info.Crit or 0) + value end
			end
			if TOC_VERSION_CURRENT < TOC_VERSION_WOD then
				if string.find(text, "hit by") or string.find(text, "improves hit rating by") or string.find(text, "your hit rating by") then info.Hit = (info.Hit or 0) + value end
			end
			if string.find(text, "haste") then info.Haste = (info.Haste or 0) + value end
			if string.find(text, "mana per 5") or string.find(text, "mana every 5") then info.Mp5 = (info.Mp5 or 0) + value end
			if string.find(text, "meta socket") then info.MetaSockets = info.MetaSockets + 1 end
			if string.find(text, "red socket") then info.RedSockets = info.RedSockets + 1 end
			if string.find(text, "yellow socket") then info.YellowSockets = info.YellowSockets + 1 end
			if string.find(text, "blue socket") then info.BlueSockets = info.BlueSockets + 1 end
			if string.find(text, "dodge") then info.Dodge = (info.Dodge or 0) + value end
			if string.find(text, "parry") then info.Parry = (info.Parry or 0) + value end
			if string.find(text, L["block"]) then info.Block = (info.Block or 0) + value end
			if string.find(text, "defense") then info.Defense = (info.Defense or 0) + value end
			if string.find(text, "mastery") then info.Mastery = (info.Mastery or 0) + value end
			if string.find(text, "multistrike") then info.Multistrike = (info.Multistrike or 0) + value end
			if string.find(text, "versatility") then info.Versatility = (info.Versatility or 0) + value end
			if string.find(text, "experience gained") then info.ExperienceGained = (info.ExperienceGained or 0) + value end
			if info.classID == Enum.ItemClass.Weapon then
				if string.find(text, "damage per second") then info.DPS = (info.DPS or 0) + value end
				local minDamage, maxDamage = string.match(text, "([0-9]+%.?[0-9]*) ?%- ?([0-9]+%.?[0-9]*) damage")
				if minDamage and maxDamage then
					info.Damage = (info.Damage or 0) + ((tonumber(minDamage) + tonumber(maxDamage))/2)
					minDamage, maxDamage = nil, nil
				end
			end
			--check for being a pattern or the like
			if string.find(text, "pattern:") then info.unusable = 1 end
			if string.find(text, "plans:") then info.unusable = 1 end

			--check for red text on the left
			if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and textLeftText) then --this is red text
				--if Within5levels was already set but we found another red text, clear it, because we really can't use this
				if info.Within5levels then info.Within5levels = nil end
				--if there's not already a reason we cannot use and this is just a required level, check if it's within 5 levels
				if (not info.unusable and string.find(text, "requires level") and value - UnitLevel("player") <= 5) then
					info.Within5levels = 1
				end
				info.reason = "(found red text: \""..textLeftText.."\")"
				info.unusable = 1
			end

			--check for red text on the right side
			local textRight = getglobal("AutoGearTooltipTextRight"..i)
			if textRight then
				local r, g, b = textRight:GetTextColor()
				local textRightText = textRight:GetText()
				if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and textRightText) then --this is red text
					info.reason = "(found red text: \""..textRightText.."\")"
					info.unusable = 1
				end
			end
		end
	end

	if info.RedSockets == 0 then info.RedSockets = nil end
	if info.YellowSockets == 0 then info.YellowSockets = nil end
	if info.BlueSockets == 0 then info.BlueSockets = nil end
	if info.MetaSockets == 0 then info.MetaSockets = nil end

	if info.isWeaponOrOffHand then
		if info.invType == Enum.InventoryType.IndexWeaponmainhandType then
			if ((weapons == "dagger")
			or (weapons == "dagger and any"))
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger main hand)"
			elseif weapons == "2h"
			or (weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917)) or
			((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a two-handed weapon)"
			end
		elseif info.invType == Enum.InventoryType.IndexShieldType then
			if (weapons ~= "weapon and shield") and (weapons ~= "any") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should not use a shield)"
			end
		elseif info.invType == Enum.InventoryType.Index2HweaponType then
			if weapons == "weapon and shield" then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a weapon and shield)"
			elseif weapons == "dual wield" and CanDualWield() and (not IsPlayerSpell(46917)) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield one-handers)"
			elseif weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917) then
				if info.subclassID == Enum.ItemWeaponSubclass.Staff then
					info.unusable = 1
					info.reason = "(Titan's Grip doesn't work with a staff)"
				elseif info.subclassID == Enum.ItemWeaponSubclass.Polearm and TOC_VERSION_CURRENT < TOC_VERSION_MOP then
					info.unusable = 1
					info.reason = "(Titan's Grip doesn't work with a polearm)"
				end
			elseif ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should use a ranged weapon)"
			end
		elseif info.invType == Enum.InventoryType.IndexHoldableType then
			if weapons == "2h"
			or (weapons == "dual wield" and CanDualWield())
			or weapons == "weapon and shield"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs the off-hand for a weapon or shield)"
			end
		elseif info.invType == Enum.InventoryType.IndexWeaponoffhandType then
			if weapons == "2h"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a two-handed weapon)"
			elseif weapons == "dagger"
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger in the off-hand)"
			elseif weapons == "weapon and shield"
			and (info.classID ~= Enum.ItemClass.Armor)
			and (info.subclassID ~= Enum.ItemArmorSubclass.Shield) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a shield in the off-hand)"
			elseif weapons == "dual wield"
			and CanDualWield()
			and (not IsPlayerSpell(46917))
			and (info.classID == Enum.ItemClass.Armor)
			and (info.subclassID == Enum.ItemArmorSubclass.Shield) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield and not use a shield)"
			end
		elseif info.invType == Enum.InventoryType.IndexWeaponType then
			if weapons == "2h"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and (weapons == "ranged")) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should use a two-handed weapon)"
			elseif (weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917)) then
				info.unusable = 1
				info.reason =  "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield two-handers)"
			elseif (weapons == "dagger"
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger in each hand)"
			end
		elseif (TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
		and (info.invType == Enum.InventoryType.IndexRangedType)
		and	(weapons ~= "ranged"
		and info.subclassID ~= Enum.ItemWeaponSubclass.Wand) then
			info.unusable = 1
			info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should not use a ranged 2h weapon)"
		end
	end

	info.equipped = not not inventoryID

	if info.isGear or info.isMount then
		info.shouldShowScoreInTooltip = 1
	end
	if (not info.unusable) and (info.isGear or info.isMount) then
		info.usable = 1
	elseif not (info.isGear or info.isMount) then
		info.unusable = 1
		info.reason = "(item can't be equipped. info.invType = '".. tostring(info.invType) .."')"
	end

	--caching did not show a performance benefit, so commented this out
	-- if not AutoGearIsItemDataMissing then
	-- 	AutoGearItemInfoCache[info.linkHash] = info
	-- end

	return info
end

function AutoGearGetPawnScales()
	AutoGearPawnScales = {
		{
			["label"] = "Visible",
			["subLabels"] = {}
		},
		{
			["label"] = "Hidden",
			["subLabels"] = {}
		}
	}
	AutoGearPawnScalesFromPawn = PawnGetAllScalesEx()
	for _, v in ipairs(AutoGearPawnScalesFromPawn) do
		if v["IsVisible"] then
			table.insert(AutoGearPawnScales[1]["subLabels"], v["LocalizedName"] or v["Name"])
		else
			table.insert(AutoGearPawnScales[2]["subLabels"], v["LocalizedName"] or v["Name"])
		end
	end
	return AutoGearPawnScales
end

function AutoGearGetPawnScaleName(scaleNameToFind)
	local realLocalizedClass, realClass, realSpec, realClassID = AutoGearDetectClassAndSpec()
	local overrideLocalizedClass, overrideClass, overrideSpec, overrideClassID = AutoGearGetClassAndSpec()

	-- Try to find the selected Pawn scale
	if AutoGearDB.OverridePawnScale and AutoGearDB.PawnScale then
		if not AutoGearPawnScales then AutoGearGetPawnScales() end
		scaleNameToFind = scaleNameToFind or AutoGearDB.PawnScale
		for trueScaleName, scale in pairs(PawnCommon.Scales) do
			if ((scaleNameToFind == trueScaleName)
			or (scale.LocalizedName
			and (scaleNameToFind == scale.LocalizedName)))
			and scale.Values
			and next(scale.Values) then
				return trueScaleName, scale.LocalizedName
			end
		end
	end

	if AutoGearDB.Override then

		-- Try to find a visible scale with name matching the full AutoGearDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and AutoGearDB.OverrideSpec
			and AutoGearDB.OverrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale with localized name matching the full AutoGearDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and AutoGearDB.OverrideSpec
			and AutoGearDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale with class ID matching the override class ID and override spec name found in the localized scale name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and AutoGearDB.OverrideSpec
			and overrideClassID == scale.ClassID
			and scale.LocalizedName
			and string.find(scale.LocalizedName, overrideSpec)
			and scale.Values and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale matching just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale with name matching just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideLocalizedClass == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale matching the full AutoGearDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if AutoGearDB.OverrideSpec
			and AutoGearDB.OverrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with localized name matching the full AutoGearDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if AutoGearDB.OverrideSpec
			and AutoGearDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with class ID matching the override class ID and name containing the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if scale.ClassID == overrideClassID
			and string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with class ID matching override class ID
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if overrideClassID == scale.ClassID
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideLocalizedClass)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override class name (example: "PALADIN")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideClass)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

	end

	local realClassAndSpec = realLocalizedClass..": "..realSpec

	-- Try to find a visible scale matching the real class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realClassAndSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale with matching real class ID and with localized name containing the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and scale.ClassID == realClassID
		and scale.LocalizedName
		and string.find(scale.LocalizedName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching just the real class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching the real class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching just the real localized class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching class with the matching real spec in the localized scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.LocalizedName
		and string.find(scale.LocalizedName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching class with the matching real spec in the scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and string.find(scaleName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching real class
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Use the first visible
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Just use the first one that has values
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		if Scale.Values and next(Scale.Values) then
			return ScaleName, Scale.LocalizedName
		end
	end
end

function AutoGearGetWeaponType(itemClassID, itemSubClassID)
	--ask WoW what type of weapon it is
	if (itemClassID == Enum.ItemClass.Weapon) or ((itemClassID == Enum.ItemClass.Armor) and (itemSubClassID == Enum.ItemArmorSubclass.Shield)) then
		return itemSubClassID
	end
end

function AutoGearDetermineItemScore(info)
	if info.empty then return 0 end
	if info.isMount and (not info.alreadyKnown) then
		return math.huge
	end
	if info.classID == Enum.ItemClass.Container then
		if info.subclassID == 0 then -- generic (typical) bag; there's no Enum.ItemContainerSubclass
			return info.numBagSlots
		else
			return info.numBagSlots * E -- specialized bags suck, so consider them only better than nothing
		end
	elseif info.isAmmoBag and info.numBagSlots and (UnitClassBase("player") == "HUNTER") then
		return info.numBagSlots + (info.ammoBagRangedAttackSpeed and info.ammoBagRangedAttackSpeed or 0)
	end

	if AutoGearDB.UsePawn and PawnIsReady and PawnIsReady() then
		local pawnItemData = PawnGetItemData(info.link)
		if pawnItemData then
			local score = PawnGetSingleValueFromItem(pawnItemData, AutoGearGetPawnScaleName())
			if score == 0 then
				return E
			else
				return score
			end
		end
	end

	-- This error trap sucks, but execution can reach here with no AutoGearCurrentWeighting and I don't know how
	if (not AutoGearCurrentWeighting) then
		AutoGearSetStatWeights()
		if (not AutoGearCurrentWeighting) then return 0 end
	end

	local score = (AutoGearCurrentWeighting.Strength or 0) * (info.Strength or 0) +
		(AutoGearCurrentWeighting.Agility or 0) * (info.Agility or 0) +
		(AutoGearCurrentWeighting.Stamina or 0) * (info.Stamina or 0) +
		(AutoGearCurrentWeighting.Intellect or 0) * (info.Intellect or 0) +
		(AutoGearCurrentWeighting.Spirit or 0) * (info.Spirit or 0) +
		(AutoGearCurrentWeighting.Armor or 0) * (info.Armor or 0) +
		(AutoGearCurrentWeighting.Dodge or 0) * (info.Dodge or 0) +
		(AutoGearCurrentWeighting.Parry or 0) * (info.Parry or 0) +
		(AutoGearCurrentWeighting.Block or 0) * (info.Block or 0) +
		(AutoGearCurrentWeighting.Defense or 0) * (info.Defense or 0) +
		(AutoGearCurrentWeighting.SpellPower or 0) * (info.SpellPower or 0) +
		(AutoGearCurrentWeighting.SpellPenetration or 0) * (info.SpellPenetration or 0) +
		(AutoGearCurrentWeighting.Haste or 0) * (info.Haste or 0) +
		(AutoGearCurrentWeighting.Mp5 or 0) * (info.Mp5 or 0) +
		(AutoGearCurrentWeighting.AttackPower or 0) * (info.AttackPower or 0) +
		(AutoGearCurrentWeighting.ArmorPenetration or 0) * (info.ArmorPenetration or 0) +
		(AutoGearCurrentWeighting.Crit or 0) * (info.Crit or 0) +
		(AutoGearCurrentWeighting.SpellCrit or 0) * (info.SpellCrit or 0) +
		(AutoGearCurrentWeighting.Hit or 0) * (info.Hit or 0) +
		(AutoGearCurrentWeighting.SpellHit or 0) * (info.SpellHit or 0) +
		(AutoGearCurrentWeighting.RedSockets or 0) * (info.RedSockets or 0) +
		(AutoGearCurrentWeighting.YellowSockets or 0) * (info.YellowSockets or 0) +
		(AutoGearCurrentWeighting.BlueSockets or 0) * (info.BlueSockets or 0) +
		(AutoGearCurrentWeighting.MetaSockets or 0) * (info.MetaSockets or 0) +
		(AutoGearCurrentWeighting.Mastery or 0) * (info.Mastery or 0) +
		(AutoGearCurrentWeighting.Multistrike or 0) * (info.Multistrike or 0) +
		(AutoGearCurrentWeighting.Versatility or 0) * (info.Versatility or 0) +
		(AutoGearCurrentWeighting.DPS or 0) * (info.DPS or 0) +
		(AutoGearCurrentWeighting.Damage or 0) * (info.Damage or 0) +
		((UnitLevel("player") < maxPlayerLevel and not (IsXPUserDisabled and IsXPUserDisabled())) and
		(AutoGearCurrentWeighting.ExperienceGained or 0) * (info.ExperienceGained or 0) or 0)
	if score == 0 then
		return E
	else
		return score
	end
end

function AutoGearIsMountItemAlreadyCollected(itemID)
	if GetItemCount(itemID, true) > 0 or
	IsSpellKnown(select(2,GetItemSpell(itemID))) or
	(C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountFromItem and
	select(11,C_MountJournal.GetMountInfoByID(C_MountJournal.GetMountFromItem(itemID)))) then
		return true
	elseif GetNumCompanions then
		local itemName = C_Item.GetItemNameByID(itemID)
		local numCollectedMounts = GetNumCompanions("MOUNT")
		for i = 1, numCollectedMounts do
			if select(2,GetCompanionInfo("MOUNT", i)) == itemName then
				return true
			end
		end
	end
end

function AutoGearGetAllBagsNumFreeSlots()
	local slotCount = 0
	for i = 0, NUM_BAG_SLOTS do
		local freeSlots, bagType = GetContainerNumFreeSlots(i)
		if (bagType == 0) then
			slotCount = slotCount + freeSlots
		end
	end
	return slotCount
end

function AutoGearPutItemInEmptyBagSlot()
	if GetContainerNumFreeSlots(BACKPACK_CONTAINER) > 0 then PutItemInBackpack() end
	for i = 1, NUM_BAG_SLOTS do
		local freeSlots, bagType = GetContainerNumFreeSlots(i)
		if (bagType == 0 and freeSlots > 0) then
			PutItemInBag(CONTAINER_BAG_OFFSET+i)
		end
	end
end

function AutoGearScan()
	AutoGearSetStatWeights()
	if (not AutoGearCurrentWeighting) then
		local localizedClass, class, spec = AutoGearGetClassAndSpec()
		AutoGearPrint("AutoGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
		return
	end
	AutoGearPrint("AutoGear: Scanning bags for upgrades.", 2)
	if (not AutoGearConsiderAllItems()) then
		AutoGearPrint("AutoGear: Nothing better was found", 1)
	end
end

--[[ AutoGearRecursivePrint(struct, [limit], [indent])   Recursively print arbitrary data.
	Set limit (default 100) to stanch infinite loops.
	Indents tables as [KEY] VALUE, nested tables as [KEY] [KEY]...[KEY] VALUE
	Set indent ("") to prefix each line:    Mytable [KEY] [KEY]...[KEY] VALUE
--]]
function AutoGearRecursivePrint(s, l, i) -- recursive Print (structure, limit, indent)
	l = (l) or 100; i = i or ""	-- default item limit, indent string
	if (l<1) then print "ERROR: Item limit reached."; return l-1 end;
	local ts = type(s);
	if (ts ~= "table") then print (i,ts,s); return l-1 end
	print (i,ts);           -- print "table"
	for k,v in pairs(s) do  -- print "[KEY] VALUE"
		l = AutoGearRecursivePrint(v, l, i.."["..tostring(k).."]");
		if (l < 0) then break end
	end
	return l
end

function AutoGearDump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..'] = ' .. AutoGearDump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function AutoGearGetTooltipScoreComparisonInfo(info, equipped)
	local lowestScoringValidGearSlot
	local lowestScoringValidGearSlotScore = AutoGearDetermineItemScore(info)
	local lowestScoringValidGearInfo = info
	if info.is2hWeapon and (not (CanDualWield() and IsPlayerSpell(46917))) then
		local mainHandInfo = AutoGearReadItemInfo(INVSLOT_MAINHAND)
		local mainHandScore = AutoGearDetermineItemScore(mainHandInfo)
		local offHandScore = AutoGearDetermineItemScore(AutoGearReadItemInfo(INVSLOT_OFFHAND))
		local oneHandedWeaponsScore = mainHandScore + offHandScore
		lowestScoringValidGearInfo = mainHandInfo
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		lowestScoringValidGearSlotScore = oneHandedWeaponsScore
	elseif info.is1hWeaponOrOffHand
	and AutoGearIsTwoHandEquipped() then
		lowestScoringValidGearInfo = AutoGearReadItemInfo(INVSLOT_MAINHAND)
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		lowestScoringValidGearSlotScore = AutoGearDetermineItemScore(lowestScoringValidGearInfo)
	else
		if info.validGearSlots then
			local firstValidGearSlot = info.validGearSlots[1]
			lowestScoringValidGearSlot = firstValidGearSlot
			lowestScoringValidGearSlotScore = AutoGearEquippedItems[firstValidGearSlot].score
			lowestScoringValidGearInfo = AutoGearEquippedItems[firstValidGearSlot].info
			for _, gearSlot in ipairs(info.validGearSlots) do
				local skipThisSlot = false
				for _, otherGearSlot in pairs(info.validGearSlots) do
					if gearSlot ~= otherGearSlot then
						if not AutoGearIsGearPairEquippableTogether(info, AutoGearEquippedItems[otherGearSlot].info) then
							skipThisSlot = true
						end
					end
				end
				if (not skipThisSlot)
				and ((AutoGearEquippedItems[gearSlot].score <= lowestScoringValidGearSlotScore)
				or AutoGearEquippedItems[gearSlot].info.empty) then
					lowestScoringValidGearInfo = AutoGearEquippedItems[gearSlot].info
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = AutoGearEquippedItems[gearSlot].score
				end
			end
		end
		if info.is1hWeaponOrOffHand and not equipped then
			lowestScoringValidGearSlotScore = AutoGearEquippedItems[INVSLOT_MAINHAND].score + AutoGearEquippedItems[INVSLOT_OFFHAND].score
		end
	end
	return lowestScoringValidGearInfo, lowestScoringValidGearSlotScore, lowestScoringValidGearSlot
end

function AutoGearGetOppositeHandSlot(invSlot)
	if (invSlot ~= INVSLOT_MAINHAND) and (invSlot ~= INVSLOT_OFFHAND) then return end
	return (invSlot == INVSLOT_MAINHAND and INVSLOT_OFFHAND or INVSLOT_MAINHAND)
end

function AutoGearIsGearPairEquippableTogether(a, b)
	if a.empty or b.empty then return 1 end
	if (not a.validGearSlots)
	or (not b.validGearSlots)
	or ((a.id == b.id)
	and ((GetItemCount(a.id, true) < 2)
	or (a.unique)))
	or (a.ammoBagRangedAttackSpeed and b.ammoBagRangedAttackSpeed)
	or ((a.is1hWeaponOrOffHand and b.is1hWeaponOrOffHand)
	and ((weapons == "dagger and any")
	and (a.subclassID ~= Enum.ItemWeaponSubclass.Dagger)
	and (b.subclassID ~= Enum.ItemWeaponSubclass.Dagger))
	or ((weapons == "weapon and shield")
	and (a.subclassID ~= Enum.ItemArmorSubclass.Shield)
	and (b.subclassID ~= Enum.ItemArmorSubclass.Shield))) then
		return
	end
	for _, firstSlot in pairs(a.validGearSlots) do
		for _, secondSlot in pairs(b.validGearSlots) do
			if (firstSlot ~= secondSlot)
			and (not (((firstSlot == INVSLOT_MAINHAND)
			or (firstSlot == INVSLOT_OFFHAND))
			and (secondSlot == INVSLOT_TABARD)))
			and (not ((firstSlot == INVSLOT_TABARD)
			and ((secondSlot == INVSLOT_MAINHAND)
			or (secondSlot == INVSLOT_OFFHAND))))
			then
				return 1
			end
		end
	end
end

function AutoGearGetBest1hPairing(info)
	local score = AutoGearDetermineItemScore(info)
	if info.is1hWeaponOrOffHand and info.validGearSlots then
		local totalScore = 0
		local bestScore = 0
		local bestScoreSlot
		for hand = INVSLOT_MAINHAND, INVSLOT_OFFHAND do
			if AutoGearIsGearPairEquippableTogether(info, AutoGearBestItems[hand].info) then
				totalScore = score + AutoGearBestItems[hand].score
				if totalScore > bestScore then
					bestScore = totalScore
					bestScoreSlot = hand
				end
			end
		end
		if bestScoreSlot then
			return AutoGearBestItems[bestScoreSlot], bestScore
		end
	end
	return { info = { name = "nothing", empty = 1 }, score = 0 }, score
end

function AutoGearTooltipHook(tooltip)
	if (not AutoGearDB.ScoreInTooltips) then return	end
	if (not AutoGearCurrentWeighting) then AutoGearSetStatWeights() end
	local name, link = tooltip:GetItem()
	local equipped = tooltip:IsEquippedItem()
	if not link then
		AutoGearPrint("AutoGear: No item link for "..(name or "(no name)").." on "..tooltip:GetName(),3)
		return
	end
	local tooltipItemInfo = AutoGearReadItemInfo(nil,nil,nil,nil,nil,link)
	local pawnScaleName
	local pawnScaleLocalizedName
	local pawnScaleColor
	if AutoGearDB.UsePawn and PawnIsReady and PawnIsReady() then
		pawnScaleName, pawnScaleLocalizedName = AutoGearGetPawnScaleName()
		pawnScaleColor = PawnGetScaleColor(pawnScaleName)
	end
	local lowestScoringEquippedItemInfo
	local lowestScoringEquippedItemScore
	local lowestScoringEquippedItemSlot
	local score
	local best1hPairing
	local scoreColor = HIGHLIGHT_FONT_COLOR
	local isAComparisonTooltip = tooltip:GetName() ~= "GameTooltip"
	if tooltipItemInfo.shouldShowScoreInTooltip then
		local shouldShowBest1hPairing = (tooltipItemInfo.is1hWeaponOrOffHand
		and (not equipped)
		and (not isAComparisonTooltip))
		if shouldShowBest1hPairing then
			best1hPairing, score = AutoGearGetBest1hPairing(tooltipItemInfo)
		else
			score = AutoGearDetermineItemScore(tooltipItemInfo)
		end
		lowestScoringEquippedItemInfo, lowestScoringEquippedItemScore, lowestScoringEquippedItemSlot = AutoGearGetTooltipScoreComparisonInfo(tooltipItemInfo, equipped)
		local isAnyComparisonTooltipVisible = ItemRefTooltip:IsVisible() or ShoppingTooltip1:IsVisible() or ShoppingTooltip2:IsVisible()
		local shouldShowComparisonLine = (not isAComparisonTooltip and (not isAnyComparisonTooltipVisible or AutoGearDB.AlwaysShowScoreComparisons)) and not equipped
		if (not equipped) and (not isAComparisonTooltip) then
			if (score > lowestScoringEquippedItemScore) then
				scoreColor = GREEN_FONT_COLOR
			elseif (score < lowestScoringEquippedItemScore) then
				scoreColor = RED_FONT_COLOR
			end
		end
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		local scoreLinePrefix = (((pawnScaleLocalizedName or pawnScaleName) and pawnScaleColor) and "AutoGear: Pawn \""..pawnScaleColor..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"" or "AutoGear")
		if shouldShowComparisonLine or shouldShowBest1hPairing then
			lowestScoringEquippedItemScore = math.floor(lowestScoringEquippedItemScore * 1000) / 1000
			tooltip:AddDoubleLine(scoreLinePrefix.." score".." (equipped"..(((not AutoGearIsTwoHandEquipped()) and tooltipItemInfo.isWeaponOrOffHand) and " pair" or "").."):",
			lowestScoringEquippedItemScore or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
		tooltip:AddDoubleLine(scoreLinePrefix.." score"..((shouldShowComparisonLine and not isAComparisonTooltip or shouldShowBest1hPairing) and " (this"..((shouldShowBest1hPairing and (not best1hPairing.info.empty)) and " and best pairing" or "")..")" or "")..":",
		(((tooltipItemInfo.unusable == 1) and (RED_FONT_COLOR_CODE.."(won't equip) "..FONT_COLOR_CODE_CLOSE) or "")..score) or "nil",
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		scoreColor.r, scoreColor.g, scoreColor.b)
		if (AutoGearDB.ReasonsInTooltips == true) and tooltipItemInfo.unusable then
			tooltip:AddDoubleLine("AutoGear: won't auto-equip",
			tooltipItemInfo.reason,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		end
		if shouldShowBest1hPairing and (not best1hPairing.info.empty) then
			local thisScore = math.floor(AutoGearDetermineItemScore(tooltipItemInfo) * 1000) / 1000
			local best1hPairingScore = math.floor(best1hPairing.score * 1000) / 1000
			tooltip:AddDoubleLine(scoreLinePrefix.." score (this; "..tooltipItemInfo.link.."):",
			tostring(thisScore or 0),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			tooltip:AddDoubleLine(scoreLinePrefix.." score (best pairing; "..(best1hPairing.info.link or best1hPairing.info.name).."):",
			tostring(best1hPairingScore or 0),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
	end
	if (AutoGearDB.DebugInfoInTooltips == true) then
		tooltip:AddDoubleLine(
			"AutoGear: item ID:",
			tostring(tooltipItemInfo.id or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: item level:",
			tostring(GetDetailedItemLevelInfo(tooltipItemInfo.link) or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: InventoryType:",
			tostring(tooltipItemInfo.invType or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		if PawnIsReady and PawnIsReady() then
			local pawnScaleName, pawnScaleLocalizedName = AutoGearGetPawnScaleName()
			tooltip:AddDoubleLine(
				"AutoGear: Pawn scale name:",
				(pawnScaleName or "nil"),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
			tooltip:AddDoubleLine(
				"AutoGear: Pawn scale localized name:",
				(pawnScaleLocalizedName or "nil"),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
			local pawnItemData = PawnGetItemData(tooltipItemInfo.link)
			tooltip:AddDoubleLine(
				"AutoGear: Pawn value:",
				tostring(
					tooltipItemInfo and (
						tooltipItemInfo.link and (
							PawnCanItemHaveStats(tooltipItemInfo.link) and (
								pawnItemData and (
									PawnGetSingleValueFromItem(
										pawnItemData,AutoGearGetPawnScaleName()
									) or "nil Pawn value"
								) or "nil Pawn item data"
							) or "Pawn says item can't have stats"
						) or "nil AG item link"
					) or "nil AG item info"
				),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
		end
		tooltip:AddDoubleLine(
			"AutoGear: info.is1hWeaponOrOffHand:",
			tostring(tooltipItemInfo.is1hWeaponOrOffHand or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: info.is2hWeapon:",
			tostring(tooltipItemInfo.is2hWeapon or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: item class ID:",
			tostring(tooltipItemInfo.classID or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: item subclass ID:",
			tostring(tooltipItemInfo.subclassID or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: valid gear slots:",
			table.concat(tooltipItemInfo.validGearSlots or {}, ", "),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: rarity:",
			tostring(tooltipItemInfo.rarity or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			tooltipItemInfo.rarityColor and tooltipItemInfo.rarityColor.r or HIGHLIGHT_FONT_COLOR.r,
			tooltipItemInfo.rarityColor and tooltipItemInfo.rarityColor.g or HIGHLIGHT_FONT_COLOR.g,
			tooltipItemInfo.rarityColor and tooltipItemInfo.rarityColor.b or HIGHLIGHT_FONT_COLOR.b
		)
		local soulbindingTable = {}
		soulbindingTable[1] = tooltipItemInfo.boe and "BoE" or tooltipItemInfo.bop and "BoP" or "none"
		if tooltipItemInfo.boe and tooltipItemInfo.bop then
			soulbindingTable[2] = "BoP"
		end
		tooltip:AddDoubleLine(
			"AutoGear: soulbinding:",
			table.concat(soulbindingTable,", "),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: lowest-scoring equipped item slot:",
			tostring(lowestScoringEquippedItemSlot or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: lowest-scoring equipped item:",
			lowestScoringEquippedItemInfo and lowestScoringEquippedItemInfo.link or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"AutoGear: lowest-scoring equipped item score:",
			lowestScoringEquippedItemScore or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		-- local rollDecision = AutoGearDecideRoll(tooltipItemInfo.link)
		-- tooltip:AddDoubleLine(
		-- 	"AutoGear: would roll:",
		-- 	(rollDecision == 1 and GREEN_FONT_COLOR_CODE.."NEED" or (rollDecision == 2 and RED_FONT_COLOR_CODE.."GREED" or HIGHLIGHT_FONT_COLOR_CODE.."no roll"))..FONT_COLOR_CODE_CLOSE,
		-- 	HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		-- 	HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		-- )
	end
end

GameTooltip:HookScript("OnTooltipSetItem", AutoGearTooltipHook)
ShoppingTooltip1:HookScript("OnTooltipSetItem", AutoGearTooltipHook)
ShoppingTooltip2:HookScript("OnTooltipSetItem", AutoGearTooltipHook)
ItemRefTooltip:HookScript("OnTooltipSetItem", AutoGearTooltipHook)


function AutoGearMain()
	if (GetTime() - tUpdate > 0.05) then
		tUpdate = GetTime()
		--future actions
		for i, curAction in ipairs(futureAction) do
			-- if there's any item data missing, don't do anything that matters and instead try updating again
			if AutoGearIsItemDataMissing then
				if curAction.action == "localupdate" and dataAvailable then
					if GetTime() > curAction.t then
						AutoGearIsItemDataMissing = nil
						AutoGearUpdateBestItems() -- this will set AutoGearIsItemDataMissing again if necessary
						table.remove(futureAction, i)
					end
				end
			else
				if curAction.action == "roll" then
					if GetTime() > curAction.t then
						if curAction.rollType == 1 then
							AutoGearPrint("AutoGear: "..((AutoGearDB.AutoLootRoll == true) and "Rolling " or "If automatic loot rolling was enabled, would roll ")..GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						elseif curAction.rollType == 2 then
							AutoGearPrint("AutoGear: "..((AutoGearDB.AutoLootRoll == true) and "Rolling " or "If automatic loot rolling was enabled, would roll ")..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						end
						local rarity = curAction.info.rarity
						if (((rarity < 3) or (rarity == 3 and not (curAction.info.boe))) and (AutoGearDB.AutoLootRoll == true)) or
						((rarity == 3) and curAction.info.boe and (AutoGearDB.AutoRollOnBoEBlues == true)) or
						((rarity == 4) and (AutoGearDB.AutoRollOnEpics == true)) then
								RollOnLoot(curAction.rollID, curAction.rollType)
						end
						table.remove(futureAction, i)
					end
				elseif (curAction.action == "equip" and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")) then
					if (GetTime() > curAction.t) then
						if ((AutoGearDB.Enabled ~= nil) and (AutoGearDB.Enabled == true)) then
							if (not curAction.messageAlready) then
								AutoGearPrint("AutoGear: Equipping "..(curAction.info.link or curAction.info.name)..".", 2)
								curAction.messageAlready = 1
							end
							if (curAction.removeMainHandFirst) then
								if (AutoGearGetAllBagsNumFreeSlots() > 0) then
									AutoGearPrint("AutoGear: Removing the two-hander to equip the off-hand", 1)
									PickupInventoryItem(INVSLOT_MAINHAND)
									AutoGearPutItemInEmptyBagSlot()
									curAction.removeMainHandFirst = nil
									curAction.waitingOnEmptyMainHand = 1
								else
									AutoGearPrint("AutoGear: Cannot equip the off-hand because bags are too full to remove the two-hander", 0)
									table.remove(futureAction, i)
								end
							elseif (curAction.waitingOnEmptyMainHand and not AutoGearEquippedItems[INVSLOT_MAINHAND].info.empty) then
							elseif (curAction.waitingOnEmptyMainHand and AutoGearEquippedItems[INVSLOT_MAINHAND].info.empty) then
								AutoGearPrint("AutoGear: Main hand detected to be clear.  Equipping now.", 1)
								curAction.waitingOnEmptyMainHand = nil
							elseif (curAction.ensuringEquipped) then
								-- AutoGearPrint("checking whether equipped: "..curAction.info.link,3)
								if (GetInventoryItemID("player", curAction.replaceSlot) == curAction.info.id) then
									curAction.ensuringEquipped = nil
									if (not futureAction[i+1]) or (not futureAction[i+1].ensuringEquipped) then
										AutoGearUpdateEquippedItems()
									end
									table.remove(futureAction, i)
								end
							else
								PickupContainerItem(curAction.container, curAction.slot)
								EquipCursorItem(curAction.replaceSlot)
								curAction.ensuringEquipped = 1
							end
						else
							table.remove(futureAction, i)
						end
					end
				elseif (curAction.action == "scan") then
					if (GetTime() > curAction.t) then
						AutoGearConsiderAllItems()
						table.remove(futureAction, i)
					end
				end
			end
		end
	end
end