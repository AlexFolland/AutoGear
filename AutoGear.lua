--AutoGear

-- to do:
-- Classic 2019
-- Needing on meteor shard as a mage
--	In general, needing on one-handers that are near-worthless.  The plan is to only roll if it passes a minimum threshold.  That threshold should be 3x the highest weight among the 5 main stats.
-- Don't roll on loot I already have in my bag
-- Greeded in something within 5 levels that was an upgrade.  Specifically, Gauntlets of Divinity versus equipped Algae Fists.

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

local _ --prevent taint when using throwaway variable
local reason
local futureAction = {}
local weighting --gear stat weighting
local weapons
local tUpdate = 0
local dataAvailable = nil
local shouldPrintHelp = false
local maxPlayerLevel = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]

--initialize table for storing saved variables
if (not AutoGearDB) then AutoGearDB = {} end

--check whether it's WoW classic, for automatic compatibility
local IsClassic = WOW_PROJECT_ID and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

--initialize missing saved variables with default values
function InitializeAutoGearDB(defaults, reset)
    if AutoGearDB == nil or reset ~= nil then AutoGearDB = {} end
    for k,v in pairs(defaults) do
        if AutoGearDB[k] == nil then
            AutoGearDB[k] = defaults[k]
        end
    end
end

--printing function to check allowed verbosity level
function AutoGearPrint(text, verbosity)
    if verbosity == nil then verbosity = 0 end
    if (AutoGearDB.AllowedVerbosity == nil) or (verbosity <= AutoGearDB.AllowedVerbosity) then
        print(text)
    end
end

--names of verbosity levels
local function GetAllowedVerbosityName(allowedverbosity)
    if allowedverbosity == 0 then
        return "errors"
    elseif allowedverbosity == 1 then
        return "info"
    elseif allowedverbosity == 2 then
        return "details"
    elseif allowedverbosity == 3 then
    	return "debug"
    else
        return "funky"
    end
end

-- We run the IsClassic check before function definition to prevent poorer performance
if (IsClassic) then
	function AutoGearGetSpec()
		-- GetSpecialization() doesn't exist on Classic.
		-- Instead, this finds the talent tree where the most points are allocated.
		local highestSpec = nil
		local highestPointsSpent = nil
		local numTalentTabs = GetNumTalentTabs()
		if (not numTalentTabs) or (numTalentTabs < 2) then
			AutoGearPrint("AutoGear: numTalentTabs in AutoGearGetSpec() is "..tostring(numTalentTabs),0)
		end
		for i = 1, numTalentTabs do
			local spec, _, pointsSpent = GetTalentTabInfo(i)
			if (highestPointsSpent == nil or pointsSpent > highestPointsSpent) then
				highestPointsSpent = pointsSpent
				highestSpec = spec
			end
		end
		if (highestPointsSpent == 0) then
			return "None"
		end

		-- If they're feral, determine if they're a tank and call it Guardian.
		if (highestSpec == "Feral") then
			local tankiness = 0
			tankiness = tankiness + select(5, GetTalentInfo(2, 3)) * 1.0 --Feral Instinct
			tankiness = tankiness + select(5, GetTalentInfo(2, 7)) * 5 --Feral Charge
			tankiness = tankiness + select(5, GetTalentInfo(2, 5)) * 0.5 --Thick Hide
			tankiness = tankiness + select(5, GetTalentInfo(2, 9)) * -100 --Improved Shred
			tankiness = tankiness + select(5, GetTalentInfo(2, 12)) * 100 --Primal Fury
			if (tankiness >= 5) then return "Guardian" end
		end

		return highestSpec
	end
else
	function AutoGearGetSpec()
		local currentSpec = GetSpecialization()
		local currentSpecName = currentSpec and select(2, GetSpecializationInfo(currentSpec)) or "None"
		return currentSpecName
	end
end

function AutoGearGetDefaultOverrideSpec()
	className = UnitClass("player")
	spec = AutoGearGetSpec()
	if spec then
		return className..": "..spec
	end
end

--default values for variables saved between sessions
AutoGearDBDefaults = {
	Enabled = true,
	Override = false,
	OverrideSpec = AutoGearGetDefaultOverrideSpec(),
	AutoLootRoll = true,
	RollOnNonGearLoot = true,
	AutoConfirmBinding = true,
	AutoAcceptQuests = true,
	AutoAcceptPartyInvitations = true,
	ScoreInTooltips = true,
	ReasonsInTooltips = false,
	AlwaysCompareGear = GetCVarBool("alwaysCompareItems"),
	UsePawn = false,
	AutoSellGreys = true,
	AutoRepair = true,
	AllowedVerbosity = 2
}

InitializeAutoGearDB(AutoGearDBDefaults)

--an invisible tooltip that AutoGear can scan for various information
local tooltipFrame = CreateFrame("GameTooltip", "AutoGearTooltip", UIParent, "GameTooltipTemplate")

--the main frame
AutoGearFrame = CreateFrame("Frame", nil, UIParent)
AutoGearFrame:SetWidth(1); AutoGearFrame:SetHeight(1)
AutoGearFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
AutoGearFrame:SetScript("OnUpdate", function()
    AutoGearMain()
end)

-- supported stats are:
--[[
    weighting = {
		Strength = 0, Agility = 0, Stamina = 0, Intellect = 0, Spirit = 0,
		Armor = 0, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
		SpellPower = 0, SpellPenetration = 0, Haste = 0, Mp5 = 0,
		AttackPower = 0, ArmorPenetration = 0, Crit = 0, Hit = 0, 
		Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0, ExperienceGained = 0,
		RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
		HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
		DPS = 0
	}
]]
local E = 0.000001 --epsilon; non-zero value that's insignificantly different from 0, used here for the purpose of valuing gear that has higher stats that give the player "almost no benefit"
-- regex for finding 0 in this block to replace with E: (?<=[^ ] = )0(?=[^\.0-9])
if (IsClassic) then
	AutoGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.2, Damage = 0.8
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1, Damage = 1
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.22, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.2, Damage = 0.8
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.33333, Damage = 0.66667
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.5,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.5, SpellPenetration = 0, Haste = 0.5, Mp5 = 0.05,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.9, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 1
			},
			["Balance"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.05, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 1.33,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1.2,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 4,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["HUNTER"] = {
			["None"] = {
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, Hit = 0.4, 
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 0, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
				DPS = 2
			},
			["Beast Mastery"] = {
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.9, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 1.1, Hit = 0.4, 
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
				DPS = 2
			},
			["Marksmanship"] = {
				Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.005, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.61, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.66, Hit = 3.49, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Survival"] = {
				Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.005, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.33, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.37, Hit = 3.19, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 5.16, Spirit = 0.05,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.34, Hit = 3.21, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = 0, Agility = 0, Stamina = 0.01, Intellect = 1, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.6, SpellPenetration = 0.2, Haste = 0.5, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.8, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.2, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.9, SpellPenetration = 0.3, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.8, Hit = 0.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 1, Damage = 1
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 0.05,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.13333, Damage = 0.06667
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.33333, Damage = 0.66667
			},
			["Holy"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 0.8, Spirit = 0.9,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.7, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = 0,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, Defense = 3,
				SpellPower = 0.05, SpellPenetration = 0, Haste = 0.5, Mp5 = 0,
				AttackPower = 0.4, ArmorPenetration = 0.1, Crit = 0.25, Hit = 0,
				Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
				DPS = 1.33333, Damage = 0.66667
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1, Damage = 1
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.75, SpellPenetration = 0, Haste = 2, Mp5 = 4,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.6, Hit = 1.95, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = 0, Agility = 0, Stamina = 0, Intellect = 1, Spirit = 1,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.8, SpellPenetration = 0, Haste = 1, Mp5 = 4,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.25, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1.5,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.7, SpellPenetration = 0, Haste = 0.47, Mp5 = 4,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.47, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 1, SpellPenetration = 0, Haste = 1, Mp5 = 3,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0,
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0.3, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger and any",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.5, Mp5 = 0,
				AttackPower = 0.4, ArmorPenetration = 0, Crit = 1.1, Hit = 0.6, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			}		
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = 0, Agility = 1, Stamina = 0.05, Intellect = 1, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, Hit = 2.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.2, Damage = 0.8
			},
			["Elemental"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.13333, Damage = 0.06667
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.95, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, Hit = 0.8, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 1.2, Damage = 0.8
			},
			["Restoration"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.65,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.75, SpellPenetration = 0, Haste = 0.6, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.79, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.91, SpellPenetration = 0.05, Haste = 2.37, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.95, Hit = 3.74, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.3, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.62, SpellPenetration = 0.05, Haste = 2.08, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.4, Hit = 2.83, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0.5, Defense = 4,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.33333, Damage = 0.66667
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1, Damage = 1
			},
			["Fury"] = {
				weapons = "dual wield",
				Strength = 2.98, Agility = 0.5, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.37, Mp5 = 0,
				AttackPower = 1.36, ArmorPenetration = 0, Crit = 1.98, Hit = 2.47, 
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.2, Damage = 0.8
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = 0.5, Stamina = 1.5, Intellect = 0, Spirit = 0,
				Armor = 0.16, Dodge = 1, Parry = 1.03, Block = 0.5, Defense = 4,
				SpellPower = 0, SpellPenetration = 0, Haste = 0, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.02, 
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1.33333, Damage = 0.66667
			}
		}
	}
else
	AutoGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = 0, Stamina = 0.5, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.22, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.5,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0.5, SpellPenetration = 0, Haste = 0.5, Mp5 = 0.05,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.9, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 1
			},
			["Balance"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.05, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 0.05,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["HUNTER"] = {
			["None"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, Hit = 0.4, 
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 0, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
				DPS = 2
			},
			["Beast Mastery"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.9, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 1.1, Hit = 0.4, 
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1.0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 1,
				DPS = 2
			},
			["Marksmanship"] = {
				weapons = "ranged",
				Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.005, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.61, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.66, Hit = 3.49, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Survival"] = {
				Strength = 0, Agility = 1.05, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.005, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.33, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.37, Hit = 3.19, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 5.16, Spirit = 0.05,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.34, Hit = 3.21, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = 0, Agility = 0, Stamina = 0.01, Intellect = 1, Spirit = 0,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.6, SpellPenetration = 0.2, Haste = 0.5, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.8, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.2, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.9, SpellPenetration = 0.3, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.8, Hit = 0.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = 0, Agility = 1.05, Stamina = 1, Intellect = 0, Spirit = 0,
				Armor = 0.8, Dodge = 0.4, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 0.3, 
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.85, SpellPenetration = 0, Haste = 0.8, Mp5 = 0.05,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.6, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 1
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Holy"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 0.8, Spirit = 0.9,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0.7, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = 0,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, SpellPower = 0.05,
				AttackPower = 0.4, Haste = 0.5, ArmorPenetration = 0.1,
				Crit = 0.25, Hit = 0, Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
				DPS = 2
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.79, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 0.98, Hit = 1.77, 
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 2.75, SpellPenetration = 0, Haste = 2, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.6, Hit = 1.95, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = 0, Agility = 0, Stamina = 0, Intellect = 1, Spirit = 1,
				Armor = 0.0001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0.8, SpellPenetration = 0, Haste = 1, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.25, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 1, SpellPenetration = 0, Haste = 0.47, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.47, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 1, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 1, SpellPenetration = 0, Haste = 1, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1, Hit = 0,
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger and any",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.1, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.05, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0, Crit = 1.1, Hit = 1.75, 
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.5, Mp5 = 0,
				AttackPower = 0.4, ArmorPenetration = 0, Crit = 1.1, Hit = 0.6, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			}		
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = 0, Agility = 1, Stamina = 0.05, Intellect = 1, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, Hit = 2.7, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Elemental"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.9, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 1, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = 0, Agility = 1.05, Stamina = 0.1, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.95, Mp5 = 0,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, Hit = 0.8, 
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 1, DamageSpellProc = 0, MeleeProc = 1, RangedProc = 0,
				DPS = 2
			},
			["Restoration"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 1, Spirit = 0.65,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0.75, SpellPenetration = 0, Haste = 0.6, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.79, Hit = 2.78, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.79, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.91, SpellPenetration = 0.05, Haste = 2.37, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.95, Hit = 3.74, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = 0, Agility = 0, Stamina = 0.05, Intellect = 3.3, Spirit = 0.005,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 2.62, SpellPenetration = 0.05, Haste = 2.08, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 1.4, Hit = 2.83, 
				Expertise = 0, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0, Defense = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0.8, Mp5 = 0,
				AttackPower = 0.88, ArmorPenetration = 0, Crit = 1.34, Hit = 2, 
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Fury"] = {
				weapons = "2hDW", --Alitiwn: creating new weapons class for unique Fury handling
				Strength = 2.98, Agility = 0, Stamina = 0.05, Intellect = 0, Spirit = 0,
				Armor = 0.001, Dodge = 0, Parry = 0, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 1.37, Mp5 = 0,
				AttackPower = 1.36, ArmorPenetration = 0, Crit = 1.98, Hit = 2.47, 
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
				DPS = 2
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = 0, Stamina = 1.5, Intellect = 0, Spirit = 0,
				Armor = 0.16, Dodge = 1, Parry = 1.03, Block = 0,
				SpellPower = 0, SpellPenetration = 0, Haste = 0, Mp5 = 0,
				AttackPower = 0, ArmorPenetration = 0, Crit = 0.4, Hit = 0.02, 
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100, 
				RedSockets = 0, YellowSockets = 0, BlueSockets = 0, MetaSockets = 0,
				HealingProc = 0, DamageProc = 0, DamageSpellProc = 0, MeleeProc = 0, RangedProc = 0,
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
	local classList = {}
	FillLocalizedClassList(classList)
	local classOrder = {}
	for k in pairs(AutoGearDefaultWeights) do
		table.insert(classOrder, k)
	end
	table.sort(classOrder)

	for i = 1, #classOrder do (function()
		local className = classOrder[i]
		local localizedClassName = classList[className]
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
	local class, spec
	if (AutoGearDB.Override and AutoGearDB.OverrideSpec) then
		class, spec = string.match(AutoGearDB.OverrideSpec,"(.+): ?(.+)")
		class = string.upper(string.gsub(class, "%s+", ""))
	end
	if ((class == nil) or (spec == nil)) then
		_, class = UnitClass("player")
		spec = AutoGearGetSpec()
	end
	return class, spec
end

function AutoGearSetStatWeights()
    local class, spec = AutoGearGetClassAndSpec()
	weighting = AutoGearDefaultWeights[class][spec] or nil
	weapons = weighting.weapons or "any"
	AutoGearPrint("AutoGear: stat weights set for "..class..": "..spec, 3)
end

local function newCheckbox(dbname, label, description, onClick, optionsMenu)
	local check = CreateFrame("CheckButton", "AutoGear" .. dbname .. "CheckButton", optionsMenu, "InterfaceOptionsCheckButtonTemplate")
	check:SetScript("OnClick", function(self)
		local tick = self:GetChecked()
		onClick(self, tick and true or false)
		if tick then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
	end)
	check.label = _G[check:GetName() .. "Text"]
	check.label:SetText(label)
	check.tooltipText = label
	check.tooltipRequirement = description
	return check
end

local function OptionsSetup(optionsMenu)
	local i = 0
	local frame = {}
	frame[i] = optionsMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame[i]:SetPoint("TOPLEFT", 8, -8)
	frame[i]:SetText("AutoGear")

	--loop through options table to build our options menu programmatically
	for _, v in ipairs(AutoGearOptions) do (function()
		if not v["option"] then return end
		--manual iterator to be able to start from 0 and add another one outside the loop
		i = i + 1

		--function to run when toggling this option by clicking the checkbox
		_G["AutoGearSimpleToggle"..v["option"]] = function(self, value)
			if v["cvar"] then
				SetCVar(v["cvar"], value and 1 or 0)
			end
			AutoGearDB[v["option"]] = value
			AutoGearPrint("AutoGear: "..(AutoGearDB[v["option"]] and v["toggleDescriptionTrue"] or v["toggleDescriptionFalse"]), 3)
		end
		
		--function to run when toggling this option via command-line interface
		_G["AutoGearToggle"..v["option"]] = function(force)
			if AutoGearDB[v["option"]] == nil then return end
			AutoGearDB[v["option"]] = force or (not AutoGearDB[v["option"]])
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
		
		--if this has a child defined, build its child
		if v["child"] then
			
			--if the child is a dropdown, build it that way
			if v["child"]["options"] then

				frame[i].dropDown = CreateFrame("FRAME", "AutoGear"..v["child"]["option"].."Dropdown", optionsMenu, "UIDropDownMenuTemplate")
				--newDropdown(v["child"]["option"], v["child"]["label"], v["child"]["description"], _G["AutoGearSelectFrom"..v["child"]["option"].."Dropdown"], v["child"]["options"], optionsMenu)
				local width = 200
				frame[i].dropDown:SetPoint("TOPLEFT", frame[i], "TOPRIGHT", width, 0) --attach to parent
				UIDropDownMenu_SetWidth(frame[i].dropDown, width)
				--frame[i].dropDown:SetHitRectInsets(0, -280, 0, 0) --change click region to not be super wide
				UIDropDownMenu_SetText(frame[i].dropDown, AutoGearDB[v["child"]["option"]])

				--function to run when using this dropdown
				_G["AutoGear"..v["child"]["option"].."Dropdown"].SetValue = function(self, value)
					AutoGearDB[v["child"]["option"]] = value
					UIDropDownMenu_SetText(_G["AutoGear"..v["child"]["option"].."Dropdown"], AutoGearDB[v["child"]["option"]])
					CloseDropDownMenus()
				end
				
				if v["child"]["dropdownPostHook"] then
					hooksecurefunc(_G["AutoGear"..v["child"]["option"].."Dropdown"], "SetValue", v["child"]["dropdownPostHook"])
				end

				UIDropDownMenu_Initialize(_G["AutoGear"..v["child"]["option"].."Dropdown"], function(self, level, menuList)
					local info = UIDropDownMenu_CreateInfo()
					if (level or 1) == 1 then
						--display the labels
						for _, j in ipairs(v["child"]["options"]) do
							info.text = j["label"]
							info.checked = (string.match(AutoGearDB[v["child"]["option"]], "^"..j["label"]..":") and true or false)
							info.menuList = j
							info.hasArrow = (j["subLabels"] and true or false)
							UIDropDownMenu_AddButton(info)
						end
					else
						--display the subLabels
						info.func = self.SetValue
						for _, z in ipairs(menuList["subLabels"]) do
							info.text = z
							info.arg1 = menuList["label"]..": "..z
							info.checked = (AutoGearDB[v["child"]["option"]] == info.arg1)
							UIDropDownMenu_AddButton(info, level)
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

--handle PLAYER_ENTERING_WORLD events for initializing GUI options menu widget states at the right time
--UI reload doesn't seem to fire ADDON_LOADED
optionsMenu:RegisterEvent("PLAYER_ENTERING_WORLD")
optionsMenu:RegisterEvent("ADDON_LOADED")
optionsMenu:SetScript("OnEvent", function (self, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
		
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
				["toggleDescriptionFalse"] = "Automatic gearing is now disabled.  You can still manually scan bags for upgrades with the options menu button or \"/ag scan\"."
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
				["togglePostHook"] = function() AutoGearSetStatWeights() end,
				["child"] = {
					["option"] = "OverrideSpec",
					["options"] = AutoGearGetOverrideSpecs(),
					["label"] = "Override specialization",
					["description"] = "Override specialization with the spec chosen in this dropdown.  If this is enabled, AutoGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the specialization detected automatically.",
					["dropdownPostHook"] = function() AutoGearSetStatWeights() end
				}
			},
			{
				["option"] = "AutoLootRoll",
				["cliCommands"] = { "roll", "loot", "rolling" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically roll on loot",
				["description"] = "Automatically roll on group loot, depending on internal stat weights.  If this is disabled, AutoGear will still evaluate loot rolls and print its evaluation if verbosity is set to 1 ("..GetAllowedVerbosityName(1)..") or higher.",
				["toggleDescriptionTrue"] = "Automatically rolling on loot is now enabled.",
				["toggleDescriptionFalse"] = "Automatically rolling on loot is now disabled.  AutoGear will still try to equip gear received through other means, but you will have to roll on loot manually."
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
				["label"] = "Automatically confirm soul-binding",
				["description"] = "Automatically confirm soul-binding when equipping new gear, causing it to become soulbound.  If this is disabled, AutoGear will still try to equip binding gear, but you will have to confirm soul-binding manually.",
				["toggleDescriptionTrue"] = "Automatically confirming soul-binding is now enabled.",
				["toggleDescriptionFalse"] = "Automatically confirming soul-binding is now disabled.  AutoGear will still try to equip binding gear, but you will have to confirm soul-binding manually."
			},
			{
				["option"] = "AutoAcceptQuests",
				["cliCommands"] = { "quest", "quests" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Automatically handle quests",
				["description"] = "Automatically accept and complete quests, including choosing the best upgrade for your current spec.  If no upgrade is found, AutoGear will choose the most valuable reward in vendor gold.  If this is disabled, AutoGear will not interact with quest-givers in any way, but you can still view the total AutoGear score in item tooltips.",
				["toggleDescriptionTrue"] = "Automatic quest handling is now enabled.",
				["toggleDescriptionFalse"] = "Automatic quest handling is now disabled."
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
				["label"] = "Always compare gear",
				["description"] = "Always show gear comparison tooltips when viewing gear tooltips.  If this is disabled, you can still show gear comparison tooltips while holding the Shift key.",
				["toggleDescriptionTrue"] = "Always showing gear comparison tooltips when viewing gear tooltips is now enabled.",
				["toggleDescriptionFalse"] = "Always showing gear comparison tooltips when viewing gear tooltips is now disabled.  You can still show gear comparison tooltips while holding the Shift key."
			},
			{
				["option"] = "UsePawn",
				["cliCommands"] = { "pawn" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = "Use Pawn to evaluate upgrades",
				["description"] = "If Pawn (gear evaluation addon) is installed and configured, use Pawn's current scale instead of AutoGear's internal stat weights for evaluating gear upgrades.\n\nTip: If AutoGear's not using the scale you want it to use, to guarantee that AutoGear will use that Pawn scale, hide all scales in Pawn except that one.  Alternatively, name it \"[class]: [spec]\"; example \"Paladin: Retribution\".",
				["toggleDescriptionTrue"] = "Using Pawn for evaluating gear upgrades is now enabled.",
				["toggleDescriptionFalse"] = "Using Pawn for evaluating gear upgrades is now disabled."
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
			}
		}

		if AutoGearDB.OverrideSpec == nil then
			AutoGearDB.OverrideSpec = AutoGearGetDefaultOverrideSpec()
		end
		OptionsSetup(optionsMenu)

        optionsMenu:UnregisterAllEvents()
        optionsMenu:SetScript("OnEvent", nil)
    end
end)

_G["SLASH_AutoGear1"] = "/AutoGear"
_G["SLASH_AutoGear2"] = "/autogear"
_G["SLASH_AutoGear3"] = "/ag"
SlashCmdList["AutoGear"] = function(msg)
    param1, param2, param3 = msg:match("([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*")
    if (not param1) then param1 = "(nil)" end
    if (not param2) then param2 = "(nil)" end
    if (not param3) then param3 = "(nil)" end
    if (param1 == "enable" or param1 == "on" or param1 == "start") then
    	AutoGearToggleEnabled(true)
    elseif (param1 == "disable" or param1 == "off" or param1 == "stop") then
    	AutoGearToggleEnabled(false)
    elseif (param1 == "scan") then
        AutoGearScan()
    elseif (param1 == "spec") then
        AutoGearPrint("AutoGear: Looks like you are "..AutoGearGetSpec().."."..((AutoGearDB.UsePawn or AutoGearDB.Override) and ("  However, AutoGear is using "..(AutoGearDB.UsePawn and "Pawn" or "\""..AutoGearDB.OverrideSpec.."\"").." for gear evaluation due to the \""..(AutoGearDB.UsePawn and "use Pawn to evaluate upgrades" or "override specialization").."\" option.") or ""), 0)
    elseif (param1 == "verbosity") or (param1 == "allowedverbosity") then
        SetAllowedVerbosity(param2)
    elseif (param1 == "") then
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
	AutoGearPrint("AutoGear:    '/ag override [enable/on/start]/[disable/off/stop]': toggle specialization override", 0)
	AutoGearPrint("AutoGear:    '/ag roll [enable/on/start]/[disable/off/stop]': toggle automatic loot rolling", 0)
	AutoGearPrint("AutoGear:    '/ag bind [enable/on/start]/[disable/off/stop]': toggle automatic soul-binding confirmation", 0)
	AutoGearPrint("AutoGear:    '/ag quest [enable/on/start]/[disable/off/stop]': toggle automatic quest handling", 0)
	AutoGearPrint("AutoGear:    '/ag party [enable/on/start]/[disable/off/stop]': toggle automatic acceptance of party invitations", 0)
	AutoGearPrint("AutoGear:    '/ag tooltip [toggle/show/hide]': toggle showing score in item tooltips", 0)
	AutoGearPrint("AutoGear:    '/ag reasons [toggle/show/hide]': toggle showing won't-auto-equip reasons in item tooltips", 0)
	AutoGearPrint("AutoGear:    '/ag compare [enable/on/start]/[disable/off/stop]': toggle always comparing gear", 0)
	AutoGearPrint("AutoGear:    '/ag pawn [enable/on/start]/[disable/off/stop]': toggle using Pawn scales", 0)
	AutoGearPrint("AutoGear:    '/ag sell [enable/on/start]/[disable/off/stop]': toggle automatic selling of grey items", 0)
	AutoGearPrint("AutoGear:    '/ag repair [enable/on/start]/[disable/off/stop]': toggle automatic repairing", 0)
	AutoGearPrint("AutoGear:    '/ag verbosity [0/1/2/3]': set allowed verbosity level; valid levels are: 0 ("..GetAllowedVerbosityName(0).."), 1 ("..GetAllowedVerbosityName(1).."), 2 ("..GetAllowedVerbosityName(2).."), 3 ("..GetAllowedVerbosityName(3)..")", 0)
end

function SetAllowedVerbosity(allowedverbosity)
    allowedverbosity = tonumber(allowedverbosity)
    if type(allowedverbosity) ~= "number" then
        AutoGearPrint("AutoGear: The current allowed verbosity level is "..tostring(AutoGearDB.AllowedVerbosity).." ("..GetAllowedVerbosityName(AutoGearDB.AllowedVerbosity).."). Valid levels are: 0 ("..GetAllowedVerbosityName(0).."), 1 ("..GetAllowedVerbosityName(1).."), 2 ("..GetAllowedVerbosityName(2).."), 3 ("..GetAllowedVerbosityName(3)..").", 0)
        return
    end

    if allowedverbosity < 0 or allowedverbosity > 3 then
        AutoGearPrint("AutoGear: That is an invalid allowed verbosity level. Valid levels are: 0 ("..GetAllowedVerbosityName(0).."), 1 ("..GetAllowedVerbosityName(1).."), 2 ("..GetAllowedVerbosityName(2).."), 3 ("..GetAllowedVerbosityName(3)..").", 0)
        return
    else
        AutoGearDB.AllowedVerbosity = allowedverbosity
        AutoGearPrint("AutoGear: Allowed verbosity level is now: "..tostring(AutoGearDB.AllowedVerbosity).." ("..GetAllowedVerbosityName(AutoGearDB.AllowedVerbosity)..").", 0)
    end
end

if (not IsClassic) then 
	--These are events that don't exist in WoW classic
	AutoGearFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	AutoGearFrame:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
	AutoGearFrame:RegisterEvent("QUEST_POI_UPDATE")             --This event is not yet documented
end
AutoGearFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
AutoGearFrame:RegisterEvent("PARTY_INVITE_REQUEST")
AutoGearFrame:RegisterEvent("START_LOOT_ROLL")
AutoGearFrame:RegisterEvent("CONFIRM_LOOT_ROLL")
AutoGearFrame:RegisterEvent("ITEM_PUSH")
AutoGearFrame:RegisterEvent("EQUIP_BIND_CONFIRM")
AutoGearFrame:RegisterEvent("EQUIP_BIND_TRADEABLE_CONFIRM") --Fires when the player tries to equip a soulbound item that can still be traded to eligible players
AutoGearFrame:RegisterEvent("MERCHANT_SHOW")
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
AutoGearFrame:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, ...)
    --AutoGearPrint("AutoGear: "..event..(arg1 and " "..tostring(arg1) or "")..(arg2 and " "..tostring(arg2) or "")..(arg3 and " "..tostring(arg3) or "")..(arg4 and " "..tostring(arg4) or ""), 0)

    if (AutoGearDB.AutoAcceptQuests) then
        if (event == "QUEST_ACCEPT_CONFIRM") then --another group member starts a quest (like an escort)
            ConfirmAcceptQuest()
        elseif (event == "QUEST_DETAIL") then
            QuestDetailAcceptButton_OnClick()
        elseif (event == "GOSSIP_SHOW") then
            --active quests
            local quests = GetNumGossipActiveQuests()
            local info = {GetGossipActiveQuests()}
            for i = 1, quests do
                local name, level, isTrivial, isComplete, isLegendary = info[(i-1)*6+1], info[(i-1)*6+2], info[(i-1)*6+3], info[(i-1)*6+4], info[(i-1)*6+5]
                if (isComplete) then
                    SelectGossipActiveQuest(i)
                end
            end
            --available quests
            quests = GetNumGossipAvailableQuests()
            info = {GetGossipAvailableQuests()}
            for i = 1, quests do
                local name, level, isTrivial, frequency, isRepeatable = info[(i-1)*7+1], info[(i-1)*7+2], info[(i-1)*7+3], info[(i-1)*7+4], info[(i-1)*7+5]
                if (not isTrivial) then
                    SelectGossipAvailableQuest(i)
                end
            end
        elseif (event == "QUEST_GREETING") then
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
			if (not IsClassic) then 
				for i = 1, quests do
					local isTrivial, isDaily, isRepeatable = GetAvailableQuestInfo(i)
					if (not isTrivial) then
						SelectAvailableQuest(i)
					end
				end
			else
				for i = 1, quests do
					SelectAvailableQuest(i)
				end
			end
        elseif (event == "QUEST_PROGRESS") then
            if (IsQuestCompletable()) then
                CompleteQuest()
            end
        elseif (event == "QUEST_COMPLETE") then
            local rewards = GetNumQuestChoices()
            if (not rewards or rewards == 0) then
                GetQuestReward()
            else
                --choose a quest reward
                questRewardID = {}
                for i = 1, rewards do
                    local itemLink = GetQuestItemLink("choice", i)
                    if (not itemLink) then AutoGearPrint("AutoGear: No item link received from the server.", 0) end
                    local _, _, Color, Ltype, id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
                    questRewardID[i] = id
                end
                local choice = AutoGearScanBags(nil, nil, questRewardID)
                GetQuestReward(choice)
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

    if (event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player") then
		--make sure this doesn't happen as part of logon
        if (dataAvailable ~= nil) then
            --AutoGearPrint("AutoGear: event: \""..event.."\"; arg1: \""..arg1.."\"", 0)
            AutoGearPrint("AutoGear: Talent specialization changed.  Scanning bags for gear that's better suited for this spec.", 2)
            AutoGearScanBags()
        end
    elseif (event == "START_LOOT_ROLL") then
        AutoGearSetStatWeights()
        if (weighting) then
            local roll = nil
            reason = "(no reason set)"
            link = GetLootRollItemLink(arg1)
            local _, _, _, _, lootRollItemID, _, _, _, _, _, _, _, _, _ = string.find(link, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
			local wouldNeed = AutoGearScanBags(lootRollItemID, arg1)
            local rollItemInfo = ReadItemInfo(nil, arg1)
            local _, _, _, _, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(arg1);
			if ((AutoGearDB.RollOnNonGearLoot == false) and (not rollItemInfo.Slot)) then
				AutoGearPrint("AutoGear: This loot is not gear and \"Roll on non-gear loot\" is disabled, so not rolling.", 3)
				--local roll is nil, so no roll
            elseif (wouldNeed and canNeed) then
				roll = 1 --need
			else
				roll = 2 --greed
				if (wouldNeed and not canNeed) then
					AutoGearPrint("AutoGear: I would roll NEED, but NEED is not an option for this item.", 1)
				end
			end
            if (not rollItemInfo.Usable) then AutoGearPrint("AutoGear: This item cannot be worn.  "..reason, 1) end
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
            AutoGearPrint("AutoGear: No weighting set for this class.", 0)
        end
    elseif (event == "CONFIRM_LOOT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "CONFIRM_DISENCHANT_ROLL") then
        ConfirmLootRoll(arg1, arg2)
    elseif (event == "ITEM_PUSH") then
        --AutoGearPrint("AutoGear: Received an item.  Checking for gear upgrades.")
        --make sure a fishing pole isn't replaced while fishing
        if (GetMainHandType() ~= "Fishing Pole") then
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
		if (AutoGearDB.AutoConfirmBinding == true) then EquipPendingItem(arg1) end
    elseif (event == "EQUIP_BIND_TRADEABLE_CONFIRM") then
        if (AutoGearDB.AutoConfirmBinding == true) then EquipPendingItem(arg1) end
    elseif (event == "MERCHANT_SHOW") then
		if (AutoGearDB.AutoSellGreys == true) then
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
				AutoGearPrint("AutoGear: Sold all grey items for "..CashToString(totalSellValue)..".", 1)
			end
		end
		if (AutoGearDB.AutoRepair == true) then
			-- repair all gear
			local cashString = CashToString(GetRepairAllCost())
			if (not IsClassic) then
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
    elseif (event == "GET_ITEM_INFO_RECEIVED") then
        dataAvailable = 1
        AutoGearFrame:UnregisterEvent(event)
    elseif (event ~= "ADDON_LOADED") then
        AutoGearPrint("AutoGear: event fired: "..event, 3)
    end
end)

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

function AutoGearScanBags(lootRollItemID, lootRollID, questRewardID)
    AutoGearSetStatWeights()
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
    if (IsTwoHandEquipped() and spec ~= "Fury") then
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
                equippedInfo = ReadItemInfo(i)
                equippedScore = DetermineItemScore(equippedInfo, weighting)
                if ((not best[i].equipped) and best[i].score > equippedScore) then
                    AutoGearPrint("AutoGear: "..(best[i].info.Name or "nothing").." ("..string.format("%.2f", best[i].score)..") was determined to be better than "..(equippedInfo.Name or "nothing").." ("..string.format("%.2f", equippedScore)..").  "..((AutoGearDB.Enabled == true) and "Equipping." or "Would equip if automatic gear equipping was enabled."), 1)
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
            if (not best[16].equipped and best[16].info.Name ~= "nothing") then
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
                        AutoGearPrint("AutoGear: "..(best[16].info.Name or "nothing").." ("..string.format("%.2f", best[16].score)..") combined with "..(best[17].info.Name or "nothing").." ("..string.format("%.2f", best[17].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..").  "..((AutoGearDB.Enabled == true) and "Equipping." or "Would equip if automatic gear equipping was enabled."), 1)
                        PrintItem(best[16].info)
                        PrintItem(best[17].info)
                        PrintItem(equippedMain)
                    else
                        local equippedMain = ReadItemInfo(16)
                        local mainScore = DetermineItemScore(equippedMain, weighting)
                        local equippedOff = ReadItemInfo(17)
                        local offScore = DetermineItemScore(equippedOff, weighting)
                        AutoGearPrint("AutoGear: "..(best[16].info.Name or "nothing").." ("..string.format("%.2f", best[16].score)..") combined with "..(best[17].info.Name or "nothing").." ("..string.format("%.2f", best[17].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.Name or "nothing").." ("..string.format("%.2f", offScore)..").  "..((AutoGearDB.Enabled == true) and "Equipping." or "Would equip if automatic gear equipping was enabled."), 1)
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
                    AutoGearPrint("AutoGear: "..(best[i].info.Name or "nothing").." ("..string.format("%.2f", best[i].score)..") was determined to be better than "..(equippedInfo.Name or "nothing").." ("..string.format("%.2f", equippedScore)..").  "..((AutoGearDB.Enabled == true) and "Equipping." or "Would equip if automatic gear equipping was enabled."), 1)
                    PrintItem(best[i].info)
                    PrintItem(equippedInfo)
                end
            end
        elseif (best[19].score > best[16].score + best[17].score) then
            if (not best[19].equipped) then
                local equippedMain = ReadItemInfo(16)
                local mainScore = DetermineItemScore(equippedMain, weighting)
                local equippedOff = ReadItemInfo(17)
                local offScore = DetermineItemScore(equippedOff, weighting)
                AutoGearPrint("AutoGear: "..(best[19].info.Name or "nothing").." ("..string.format("%.2f", best[19].score)..") was determined to be better than "..(equippedMain.Name or "nothing").." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.Name or "nothing").." ("..string.format("%.2f", offScore)..").  "..((AutoGearDB.Enabled == true) and "Equipping." or "Would equip if automatic gear equipping was enabled."), 1)
                PrintItem(best[19].info)
                PrintItem(equippedMain)
                PrintItem(equippedOff)
                anythingBetter = 1
                local newAction = {}
                newAction.action = "equip"
                newAction.t = GetTime() + 0.5 --do it after a short delay
                newAction.container = best[19].bag
                newAction.slot = best[19].slot
                newAction.replaceSlot = 16
                newAction.info = best[19].info
                table.insert(futureAction, newAction)
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

--companion function to AutoGearScanBags
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
        string.find(mainHandType, "Fishing Pole") or
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
    if (info and info.Name) then AutoGearPrint("AutoGear:     "..info.Name..":", 2) end
    for k,v in pairs(info) do
        if (k ~= "Name" and weighting[k]) then
            AutoGearPrint("AutoGear:         "..k..": "..string.format("%.2f", v).." * "..weighting[k].." = "..string.format("%.2f", v * weighting[k]), 2)
        end
    end
end

function ReadItemInfo(inventoryID, lootRollID, container, slot, questRewardIndex, link)
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
	elseif (link) then
		AutoGearTooltip:SetHyperlink(link)
	end
	info.RedSockets = 0
	info.YellowSockets = 0
	info.BlueSockets = 0
	info.MetaSockets = 0
	local class, spec = AutoGearGetClassAndSpec()
	local weaponType = GetWeaponType()
	for i = 1, AutoGearTooltip:NumLines() do
		local mytext = getglobal("AutoGearTooltipTextLeft"..i)
		if (mytext) then
			local r, g, b, a = mytext:GetTextColor()
			local text = select(1,string.gsub(mytext:GetText():lower(),",",""))
			if (i==1) then
				info.Name = mytext:GetText()
				if (info.Name == "Retrieving item information") then
					cannotUse = 1
					reason = "(this item's tooltip is not yet available)"
					--AutoGearPrint("AutoGear: Item's name says \"Retrieving item information\"; cannotUse: "..tostring(cannotUse), 0)
				end
			end
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
			value = tonumber(string.match(text, "-?[0-9]+%.?[0-9]*"))
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
			if (string.find(text, "attack power")) and not string.find(text, "when fighting") then info.AttackPower = (info.AttackPower or 0) + value end
			if (string.find(text, "spell power") or 
				string.find(text, "damage and healing") or
				string.find(text, "frost spell damage") and (spec=="Frost" or class=="MAGE" and spec=="None") or
				string.find(text, "fire spell damage") and (spec=="Fire" or class=="MAGE" and spec=="None") or
				string.find(text, "arcane spell damage") and (spec=="Arcane" or class=="MAGE" and spec=="None") or
				string.find(text, "nature spell damage") and spec=="Balance" or
				string.find(text, "healing spells") or
				string.find(text, "increases healing done")) then info.SpellPower = (info.SpellPower or 0) + value end
			if (string.find(text, "critical strike")) then info.Crit = (info.Crit or 0) + value end
			if (string.find(text, "haste")) then info.Haste = (info.Haste or 0) + value end
			if (string.find(text, "mana per 5") or string.find(text, "mana every 5")) then info.Mp5 = (info.Mp5 or 0) + value end
			if (string.find(text, "meta socket")) then info.MetaSockets = info.MetaSockets + 1 end
			if (string.find(text, "red socket")) then info.RedSockets = info.RedSockets + 1 end
			if (string.find(text, "yellow socket")) then info.YellowSockets = info.YellowSockets + 1 end
			if (string.find(text, "blue socket")) then info.BlueSockets = info.BlueSockets + 1 end
			if (string.find(text, "dodge")) then info.Dodge = (info.Dodge or 0) + value end
			if (string.find(text, "parry")) then info.Parry = (info.Parry or 0) + value end
			if (string.find(text, "block")) then info.Block = (info.Block or 0) + value end
			if (string.find(text, "defense")) then info.Defense = (info.Defense or 0) + value end
			if (string.find(text, "mastery")) then info.Mastery = (info.Mastery or 0) + value end
			if (string.find(text, "multistrike")) then info.Multistrike = (info.Multistrike or 0) + value end
			if (string.find(text, "versatility")) then info.Versatility = (info.Versatility or 0) + value end
			if (string.find(text, "experience gained")) then
				if (UnitLevel("player") < maxPlayerLevel and not IsXPUserDisabled()) then
					info.ExperienceGained = (info.ExperienceGained or 0) + value
				end
			end
			
			if weaponType then
				if (string.find(text, "damage per second")) then info.DPS = (info.DPS or 0) + value end
				local minDamage, maxDamage = string.match(text, "([0-9]+%.?[0-9]*) ?%- ?([0-9]+%.?[0-9]*) damage")
				if (minDamage and maxDamage) then
					info.Damage = (info.Damage or 0) + ((tonumber(minDamage) + tonumber(maxDamage))/2)
					minDamage, maxDamage = nil
				end
			end

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
				if (weapons == "dagger and any" and weaponType ~= LE_ITEM_WEAPON_DAGGER) then
					cannotUse = 1
					reason = "(this spec needs a dagger main hand)"
				elseif (weapons == "2h" or weapons == "ranged" or weapons == "2hDW") then --Alitwin: adding 2hdw
					cannotUse = 1
					reason = "(this spec needs a two-hand weapon)"
				end
				info.Slot = "MainHandSlot"
			end
			if (text=="two-hand") then
				if (weapons == "weapon and shield") then
					cannotUse = 1
					reason = "(this spec needs weapon and shield)"
				elseif (weapons == "dual wield" and CanDualWield()) then
					cannotUse = 1
					reason = "(this spec should dual wield)"
				elseif (weapons == "ranged") then
					cannotUse = 1
					reason = "(this spec should use a ranged weapon)"
				end
				if (weapons == "2hDW") then	--Alitwin: adding 2hdw
					info.Slot = "MainHandSlot"
					info.Slot2 = "SecondaryHandSlot"
				else
					info.Slot = "MainHandSlot"; info.IncludeOffHand=1
				end
				info.Slot = "MainHandSlot"; info.IncludeOffHand=1
			end
			if (text=="held in off-hand") then
				if (weapons == "2h" or (weapons == "dual wield" and CanDualWield()) or weapons == "weapon and shield" or weapons == "ranged") then
					cannotUse = 1
					reason = "(this spec needs the off-hand for a weapon or shield)"
				end
				info.Slot = "SecondaryHandSlot"
			end
			if (text=="off hand") then
				if (weapons == "2h" or weapons == "ranged") then
					cannotUse = 1
					reason = "(this spec should use a two-hand weapon)"
				elseif (weapons == "weapon and shield" and weaponType ~= LE_ITEM_ARMOR_SHIELD) then
					cannotUse = 1
					reason = "(this spec needs a shield in the off-hand)"
				elseif (weapons == "dual wield" and CanDualWield() and weaponType == LE_ITEM_ARMOR_SHIELD) then
					cannotUse = 1
					reason = "(this spec should dual wield and not use a shield)"
				end
				info.Slot = "SecondaryHandSlot"
			end
			if (text=="one-hand") then
				if (weapons == "2h" or weapons == "ranged" or weapons == "2hDW") then --Alitwin: adding 2hdw
					cannotUse = 1
					reason = "(this spec should use a two-handed weapon or dual wield two-handers)"
				end
				if (weapons == "dagger and any" and weaponType ~= LE_ITEM_WEAPON_DAGGER) then
					info.Slot = "SecondaryHandSlot"
				elseif (((weapons == "dual wield") and CanDualWield()) or weapons == "dagger and any") then
					info.Slot = "MainHandSlot"
					info.Slot2 = "SecondaryHandSlot"
				else
					info.Slot = "MainHandSlot"
				end
			end
			if (IsClassic) then
				if (text=="wand" or
					text=="gun" or
					text=="ranged" or
					text=="crossbow" or
					text=="idol" or
					text=="libram" or
					text=="totem" or
					text=="sigil" or
					text=="relic") then
					info.Slot = "RangedSlot"
				end
			else
				if (text=="ranged") then
					info.Slot = "MainHandSlot"
					if (weapons ~= "ranged" and weaponType ~= LE_ITEM_WEAPON_WAND) then
						cannotUse = 1
						reason = "(this class or spec should not use a ranged 2h weapon)"
					end
				end
			end
			
			--check for being a pattern or the like
			if (string.find(text, "pattern:")) then cannotUse = 1 end
			if (string.find(text, "plans:")) then cannotUse = 1 end
			
			--check for red text
			local r, g, b, a = mytext:GetTextColor()
			if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and mytext:GetText()) then --this is red text
				--if Within5levels was already set but we found another red text, clear it, because we really can't use this
				if (info.Within5levels) then info.Within5levels = nil end
				--if there's not already a reason we cannot use and this is just a required level, check if it's within 5 levels
				if (not cannotUse and string.find(text, "requires level") and value - UnitLevel("player") <= 5) then
					info.Within5levels = 1
				end
				reason = "(found red text on the left.  color: "..string.format("%0.2f", r)..", "..string.format("%0.2f", g)..", "..string.format("%0.2f", b).."  text: \""..(mytext:GetText() or "nil").."\")"
				cannotUse = 1
			end
		end
		
		--check for red text on the right side
		rightText = getglobal("AutoGearTooltipTextRight"..i)
		if (rightText) then
			local r, g, b, a = rightText:GetTextColor()
			if ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and rightText:GetText()) then --this is red text
				reason = "(found red text on the right.  color: "..string.format("%0.2f", r)..", "..string.format("%0.2f", g)..", "..string.format("%0.2f", b).."  text: \""..(rightText:GetText() or "nil").."\")"
				cannotUse = 1
			end
		end
	end
	if (info.RedSockets == 0) then info.RedSockets = nil end
	if (info.YellowSockets == 0) then info.YellowSockets = nil end
	if (info.BlueSockets == 0) then info.BlueSockets = nil end
	if (info.MetaSockets == 0) then info.MetaSockets = nil end
	
	if (AutoGearDB.UsePawn == true) and (PawnIsReady ~= nil) and PawnIsReady() then
        if (not link) then _, link = AutoGearTooltip:GetItem() end
        local PawnItemData = PawnGetItemData(link)
        if PawnItemData then
			info.PawnScaleName = AutoGearGetPawnScaleName()
            info.PawnItemValue = PawnGetSingleValueFromItem(PawnItemData, info.PawnScaleName)
	    else
            AutoGearPrint("AutoGear: PawnItemData was nil in ReadItemInfo", 3)
        end
    end
	
	if (info.Slot or info.isMount) then info.shouldShowScoreInTooltip = 1 end
	if (not cannotUse and (info.Slot or info.isMount)) then
		info.Usable = 1
	elseif (not info.Slot) then
		cannotUse = 1
		reason = "(info.Slot was nil)"
	end

	--if (cannotUse) then AutoGearPrint("Cannot use "..(info.Name or (inventoryID and "inventoryID "..inventoryID or "(nil)")).." "..reason, 3) end
	info.reason = reason
	return info
end

function AutoGearGetPawnScaleName()
	local _, _, ClassID = UnitClass("player")

	local spec = AutoGearGetSpec()

	-- Try to find the matching class
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(ScaleName) and Scale.ClassID == ClassID and Scale.Provider ~= nil then
			return ScaleName
		end
	end

	-- Use the first visible
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(ScaleName) then
			return ScaleName
		end
	end

	-- Just use the first one
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		return ScaleName
	end
end

function GetWeaponType()
	--this function assumes the tooltip has already been set
	--ask WoW what type of weapon it is
	local name, link = AutoGearTooltip:GetItem()
	if link then
		local itemID, itemType, itemSubType, itemEquipLoc, icon, itemClassID, itemSubClassID = GetItemInfoInstant(link)
		if (itemClassID == LE_ITEM_CLASS_WEAPON) or ((itemClassID == LE_ITEM_CLASS_ARMOR) and (itemSubClassID == LE_ITEM_ARMOR_SHIELD)) then
			return itemSubClassID
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
	if itemInfo.PawnItemValue then return itemInfo.PawnItemValue end
	return (weighting.Strength or 0) * (itemInfo.Strength or 0) +
		(weighting.Agility or 0) * (itemInfo.Agility or 0) +
		(weighting.Stamina or 0) * (itemInfo.Stamina or 0) +
		(weighting.Intellect or 0) * (itemInfo.Intellect or 0) +
		(weighting.Spirit or 0) * (itemInfo.Spirit or 0) +
		(weighting.Armor or 0) * (itemInfo.Armor or 0) +
		(weighting.Dodge or 0) * (itemInfo.Dodge or 0) +
		(weighting.Parry or 0) * (itemInfo.Parry or 0) +
		(weighting.Block or 0) * (itemInfo.Block or 0) +
		(weighting.Defense or 0) * (itemInfo.Defense or 0) +
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
		(weighting.DPS or 0) * (itemInfo.DPS or 0) +
		(weighting.Damage or 0) * (itemInfo.Damage or 0)
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

function AutoGearScan()
    if (not weighting) then AutoGearSetStatWeights() end
    if (not weighting) then
        AutoGearPrint("AutoGear: No weighting set for this class.", 0)
        return
    end
    AutoGearPrint("AutoGear: Scanning bags for upgrades.", 2)
    if (not AutoGearScanBags()) then
        AutoGearPrint("AutoGear: Nothing better was found", 1)
    end
end

--[[ AutoGearRecursivePrint(struct, [limit], [indent])   Recursively print arbitrary data. 
	Set limit (default 100) to stanch infinite loops.
	Indents tables as [KEY] VALUE, nested tables as [KEY] [KEY]...[KEY] VALUE
	Set indent ("") to prefix each line:    Mytable [KEY] [KEY]...[KEY] VALUE
--]]
function AutoGearRecursivePrint(s, l, i) -- recursive Print (structure, limit, indent)
	l = (l) or 100; i = i or "";	-- default item limit, indent string
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

function AutoGearTooltipHook(tooltip)
	if (not AutoGearDB.ScoreInTooltips) then return end
	if (not weighting) then AutoGearSetStatWeights() end
	local name, link = tooltip:GetItem()
	if not link then
		AutoGearPrint("AutoGear: No item link for "..name.." on "..tooltip:GetName(),3)
		return
	end
	local tooltipItemInfo = ReadItemInfo(nil,nil,nil,nil,nil,link)
	local score = DetermineItemScore(tooltipItemInfo, weighting)
	if (tooltipItemInfo.shouldShowScoreInTooltip == 1) then
		local equippedItemInfo = ReadItemInfo(GetInventorySlotInfo(tooltipItemInfo.Slot))
		local equippedScore = DetermineItemScore(equippedItemInfo, weighting)
		local comparing = ((tooltip ~= ItemRefTooltip) and (ShoppingTooltip1:IsVisible() or tooltip:IsEquippedItem()));
		local scoreColor = HIGHLIGHT_FONT_COLOR
		if (score > equippedScore) then
			scoreColor = GREEN_FONT_COLOR
		elseif (score < equippedScore) then
			scoreColor = RED_FONT_COLOR
		end
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		if (not comparing) then
			equippedScore = math.floor(equippedScore * 1000) / 1000
			tooltip:AddDoubleLine((tooltipItemInfo.PawnScaleName and "AutoGear: Pawn \""..PawnGetScaleColor(tooltipItemInfo.PawnScaleName)..tooltipItemInfo.PawnScaleName..FONT_COLOR_CODE_CLOSE.."\"" or "AutoGear").." score".." (equipped):",
			equippedScore or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
		tooltip:AddDoubleLine((tooltipItemInfo.PawnScaleName and "AutoGear: Pawn \""..PawnGetScaleColor(tooltipItemInfo.PawnScaleName)..tooltipItemInfo.PawnScaleName..FONT_COLOR_CODE_CLOSE.."\"" or "AutoGear").." score"..(comparing and "" or " (this)")..":",
		(((tooltipItemInfo.Usable == 1) and "" or (RED_FONT_COLOR_CODE.."(won't equip) "..FONT_COLOR_CODE_CLOSE))..score) or "nil",
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		scoreColor.r, scoreColor.g, scoreColor.b)
		if (AutoGearDB.ReasonsInTooltips == true) and (not tooltipItemInfo.Usable) then
			tooltip:AddDoubleLine("won't auto-equip",
			tooltipItemInfo.reason,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		end
		--[[
		if AutoGearDB.AllowedVerbosity >= 3 then
			AutoGearPrint("AutoGear: The score of the item in the current tooltip is "..tostring(score),3)
			AutoGearPrint("AutoGear: Tooltip item info:",3)
			AutoGearRecursivePrint(tooltipItemInfo)
		end
		]]
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
            if (curAction.action == "roll") then
                if (GetTime() > curAction.t) then
					if (curAction.rollType == 1) then
						AutoGearPrint("AutoGear: "..((AutoGearDB.AutoLootRoll == true) and "Rolling " or "If automatic loot rolling was enabled, would roll ").."NEED on "..curAction.info.Name..".", 1)
					elseif (curAction.rollType == 2) then
						AutoGearPrint("AutoGear: "..((AutoGearDB.AutoLootRoll == true) and "Rolling " or "If automatic loot rolling was enabled, would roll ").."GREED on "..curAction.info.Name..".", 1)
					end
					if ((AutoGearDB.AutoLootRoll ~= nil) and (AutoGearDB.AutoLootRoll == true)) then
						RollOnLoot(curAction.rollID, curAction.rollType)
					end
					table.remove(futureAction, i)
                end
            elseif (curAction.action == "equip" and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")) then
				if (GetTime() > curAction.t) then
                    if ((AutoGearDB.Enabled ~= nil) and (AutoGearDB.Enabled == true)) then
						if (not curAction.messageAlready) then
							AutoGearPrint("AutoGear: Equipping "..curAction.info.Name..".", 2)
							curAction.messageAlready = 1
						end
						if (curAction.removeMainHandFirst) then
							if (GetAllBagsNumFreeSlots() > 0) then
								AutoGearPrint("AutoGear: Removing the two-hander to equip the off-hand", 1)
								PickupInventoryItem(GetInventorySlotInfo("MainHandSlot"))
								PutItemInEmptyBagSlot()
								curAction.removeMainHandFirst = nil
								curAction.waitingOnEmptyMainHand = 1
							else
								AutoGearPrint("AutoGear: Cannot equip the off-hand because bags are too full to remove the two-hander", 0)
								table.remove(futureAction, i)
							end
						elseif (curAction.waitingOnEmptyMainHand and GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
						elseif (curAction.waitingOnEmptyMainHand and not GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))) then
							AutoGearPrint("AutoGear: Main hand detected to be clear.  Equipping now.", 1)
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
					else
						table.remove(futureAction, i)
					end
                end
            elseif (curAction.action == "scan") then
                if (GetTime() > curAction.t) then
                    AutoGearScanBags()
                    table.remove(futureAction, i)
                end
            end
        end
    end
end
