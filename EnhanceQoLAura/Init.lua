local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = {}
addon.Aura.functions = {}
addon.Aura.variables = {}
addon.Aura.sounds = {}
addon.LAura = {} -- Locales for aura

-- Default defensive abilities tracked on unit frames
addon.Aura.defaults = {}
-- IDs here are placeholders and should be replaced with actual spell IDs
addon.Aura.defaults.defensiveSpellIDs = {
	-- Warrior
	[999001] = "Shield Wall",
	-- Paladin
	[999002] = "Divine Shield",
	-- Death Knight
	[999003] = "Icebound Fortitude",
	-- Druid
	[999004] = "Barkskin",
	-- Demon Hunter
	[999005] = "Blur",
	-- Evoker
	[999006] = "Obsidian Scales",
	-- Hunter
	[999007] = "Survival of the Fittest",
	-- Mage
	[999008] = "Ice Block",
	-- Monk
	[999009] = "Fortifying Brew",
	-- Priest
	[999010] = "Dispersion",
	-- Rogue
	[999011] = "Evasion",
	-- Shaman
	[999012] = "Astral Shift",
	-- Warlock
	[999013] = "Unending Resolve",
}

addon.functions.InitDBValue("AuraCooldownTrackerBarHeight", 30)
addon.functions.InitDBValue("AuraSafedZones", {})
addon.functions.InitDBValue("personalResourceBarHealth", {})
addon.functions.InitDBValue("personalResourceBarHealthWidth", 100)
addon.functions.InitDBValue("personalResourceBarHealthHeight", 25)
addon.functions.InitDBValue("personalResourceBarManaWidth", 100)
addon.functions.InitDBValue("personalResourceBarManaHeight", 25)
addon.functions.InitDBValue("buffTrackerCategories", {
	[1] = {
		name = "Example",
		point = "CENTER",
		x = 0,
		y = 0,
		size = 36,
		direction = "RIGHT",
		buffs = {},
	},
})
addon.functions.InitDBValue("buffTrackerEnabled", {})
addon.functions.InitDBValue("buffTrackerLocked", {})
addon.functions.InitDBValue("buffTrackerHidden", {})
addon.functions.InitDBValue("buffTrackerSelectedCategory", 1)
addon.functions.InitDBValue("buffTrackerOrder", {})
addon.functions.InitDBValue("buffTrackerSounds", {})
addon.functions.InitDBValue("buffTrackerSoundsEnabled", {})
addon.functions.InitDBValue("buffTrackerShowStacks", false)
addon.functions.InitDBValue("buffTrackerShowTimerText", true)
addon.functions.InitDBValue("unitFrameAuraIDs", {})
addon.functions.InitDBValue("unitFrameAuraAnchor", "CENTER")
addon.functions.InitDBValue("unitFrameAuraDirection", "RIGHT")
addon.functions.InitDBValue("unitFrameAuraIconSize", 20)
addon.functions.InitDBValue("unitFrameAuraShowTime", false)

if type(addon.db["buffTrackerSelectedCategory"]) ~= "number" then addon.db["buffTrackerSelectedCategory"] = 1 end

for _, cat in pairs(addon.db["buffTrackerCategories"]) do
	for _, buff in pairs(cat.buffs or {}) do
		if not buff.altIDs then buff.altIDs = {} end
		if buff.showAlways == nil then buff.showAlways = false end
		if buff.glow == nil then buff.glow = false end
		if not buff.trackType then buff.trackType = "BUFF" end
		if not buff.conditions then
			buff.conditions = { join = "AND", conditions = {} }
			if buff.showWhenMissing then table.insert(buff.conditions.conditions, { type = "missing", operator = "==", value = true }) end
			if buff.stackOp and buff.stackVal then table.insert(buff.conditions.conditions, { type = "stack", operator = buff.stackOp, value = buff.stackVal }) end
			if buff.timeOp and buff.timeVal then table.insert(buff.conditions.conditions, { type = "time", operator = buff.timeOp, value = buff.timeVal }) end
		end
		buff.showWhenMissing = nil
		buff.stackOp = nil
		buff.stackVal = nil
		buff.timeOp = nil
		buff.timeVal = nil
		if not buff.allowedSpecs then buff.allowedSpecs = {} end
		if not buff.allowedClasses then buff.allowedClasses = {} end
		if not buff.allowedRoles then buff.allowedRoles = {} end
		if buff.showStacks == nil then
			buff.showStacks = addon.db["buffTrackerShowStacks"]
			if buff.showStacks == nil then buff.showStacks = true end
		end
		if buff.showTimerText == nil then
			buff.showTimerText = addon.db["buffTrackerShowTimerText"]
			if buff.showTimerText == nil then buff.showTimerText = true end
		end
	end
end
