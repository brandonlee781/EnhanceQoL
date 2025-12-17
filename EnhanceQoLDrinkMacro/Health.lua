local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local UnitLevel = UnitLevel
local UnitHealthMax = UnitHealthMax
local newItem = addon.functions.newItem
local insert = table.insert
local sort = table.sort
local wipe = table.wipe
local abs = math.abs

-- Cache for O(1) checks
addon.Health.cache = addon.Health.cache or {}
addon.Health.cache.isWarlock = (addon.variables and addon.variables.unitClass == "WARLOCK") or false
addon.Health.cache.hasDemonicTalent = false

local function checkForTalent(spellID)
	-- Be defensive: during login/loads the trait config may not be ready yet
	if not C_ClassTalents or not C_Traits or not C_Traits.GetConfigInfo then return false end

	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return false end

	local cfg = C_Traits.GetConfigInfo(configID)
	if not cfg or not cfg.treeIDs or not cfg.treeIDs[1] then return false end
	local treeID = cfg.treeIDs[1]

	local nodes = C_Traits.GetTreeNodes(treeID) or {}
	for _, nodeID in ipairs(nodes) do
		local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
		if nodeInfo and nodeInfo.activeEntry and (nodeInfo.ranksPurchased or 0) > 0 then
			local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
			if entryInfo and entryInfo.definitionID then
				local def = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
				if def and def.spellID == spellID then return true end
			end
		end
	end
	return false
end

local function GetPotionHeal(totalHealth)
	local raw = totalHealth * 0.25
	local heal = raw - (raw % 50)
	return heal
end

local function GetStoneHeal(totalHealth) return (totalHealth or 0) * 0.25 end

-- Health items master list. Each entry has:
-- key, id, requiredLevel, heal (relative ranking), type: "stone"|"potion"|"other"
addon.Health.healthList = {
	-- Healthstones (Warlock)
	{ key = "Healthstone", id = 5512, requiredLevel = 5, healFunc = function(maxHP) return GetStoneHeal(maxHP) end, type = "stone" },
	{ key = "DemonicHealthstone", id = 224464, requiredLevel = 5, healFunc = function(maxHP) return GetStoneHeal(maxHP) end, type = "stone" },

	-- Midnight
	{ key = "SilvermoonHealingPotion", id = 241305, requiredLevel = 81, heal = 205956, type = "potion" },
	{ key = "SilvermoonHealingPotion", id = 241304, requiredLevel = 81, heal = 241303, type = "potion" },

	-- The War Within: Cavedweller's Delight (Qualities 1-3)
	{ key = "CavedwellerDelight1", id = 212242, requiredLevel = 71, heal = 2574750, type = "potion", isCombatPotion = true },
	{ key = "CavedwellerDelight2", id = 212243, requiredLevel = 71, heal = 2685000, type = "potion", isCombatPotion = true },
	{ key = "CavedwellerDelight3", id = 212244, requiredLevel = 71, heal = 2799950, type = "potion", isCombatPotion = true },

	-- The War Within: Invigorating Healing Potion (Qualities 1-3)
	{ key = "InvigoratingHealingPotion1", id = 244835, requiredLevel = 71, heal = 5100000, type = "potion" },
	{ key = "InvigoratingHealingPotion2", id = 244838, requiredLevel = 71, heal = 5300000, type = "potion" },
	{ key = "InvigoratingHealingPotion3", id = 244839, requiredLevel = 71, heal = 6400000, type = "potion" },

	-- Khaz Algar: Algari Healing Potion (Qualities 1-3)
	{ key = "AlgariHealingPotion1", id = 211878, requiredLevel = 71, heal = 3500000, type = "potion" },
	{ key = "AlgariHealingPotion2", id = 211879, requiredLevel = 71, heal = 3600000, type = "potion" },
	{ key = "AlgariHealingPotion3", id = 211880, requiredLevel = 71, heal = 3800000, type = "potion" },

	-- Dragonflight: Refreshing Healing Potion (Qualities 1-3) - kept for completeness
	{ key = "RefreshingHealingPotion1", id = 207023, requiredLevel = 70, heal = 159194, type = "potion" },
	{ key = "RefreshingHealingPotion2", id = 207022, requiredLevel = 70, heal = 136368, type = "potion" },
	{ key = "RefreshingHealingPotion3", id = 207021, requiredLevel = 70, heal = 116788, type = "potion" },

	-- Dragonflight: Refreshing Healing Potion (Qualities 1-3) - kept for completeness
	{ key = "RefreshingHealingPotion1", id = 191378, requiredLevel = 61, heal = 118950, type = "potion" },
	{ key = "RefreshingHealingPotion2", id = 191379, requiredLevel = 61, heal = 139050, type = "potion" },
	{ key = "RefreshingHealingPotion3", id = 191380, requiredLevel = 61, heal = 162500, type = "potion" },

	-- Shadowlands
	{ key = "SpiritualHealingPotion", id = 171267, requiredLevel = 51, heal = 36000, type = "potion" },

	-- Battle for Azeroth
	{ key = "CoastalHealingPotion", id = 152615, requiredLevel = 40, heal = 8000, type = "potion" },
	{ key = "AbyssalHealingPotion", id = 169451, requiredLevel = 40, heal = 16000, type = "potion" },

	-- Legion
	{ key = "AncientHealingPotion", id = 127834, requiredLevel = 40, heal = 6000, type = "potion" },
	{ key = "AgedHealingPotion", id = 136569, requiredLevel = 40, heal = 6000, type = "potion" },

	-- Warlords of Draenor
	{ key = "HealingTonic", id = 109223, requiredLevel = 35, heal = 3400, type = "potion" },
	{ key = "MasterHealingPotion", id = 76097, requiredLevel = 32, heal = 2200, type = "potion" },
	{ key = "MysticalHealingPotion", id = 57191, requiredLevel = 30, heal = 1000, type = "potion" },

	-- Wrath of the Lich King
	{ key = "RunicHealingPotion", id = 33447, requiredLevel = 27, heal = 1200, type = "potion" },

	{ key = "SurvivalistsHealingPotion", id = 224021, requiredLevel = 5, type = "potion", healFunc = function(maxHP) return GetPotionHeal(maxHP or 0) end },

	-- Other healing items (examples; toggleable)
	-- Add additional healing clickies here if desired
}

addon.Health._combatPotionByID = addon.Health._combatPotionByID or {}
do
	local map = addon.Health._combatPotionByID
	if wipe then
		wipe(map)
	else
		for k in pairs(map) do
			map[k] = nil
		end
	end
	for _, e in ipairs(addon.Health.healthList) do
		if e.id then map[e.id] = e.isCombatPotion == true end
	end
end

-- Prepared lists and best-of per type
addon.Health.filteredHealth = {}
addon.Health.bestStone = nil
addon.Health.bestPotion = nil
addon.Health.bestOther = nil

addon.Health._lastPlayerLevel = addon.Health._lastPlayerLevel or nil
addon.Health._lastMaxHP = addon.Health._lastMaxHP or nil
local MAXHP_RECALC_DELTA = 0.05

addon.Health._wrapped = addon.Health._wrapped or {}
local function wrapItem(entry, maxHP)
	local obj = addon.Health._wrapped[entry.id]
	if not obj then
		obj = newItem(entry.id, nil, false)
		addon.Health._wrapped[entry.id] = obj
	end
	obj.requiredLevel = entry.requiredLevel or 1
	obj.type = entry.type or "potion"
	obj.key = entry.key
	if entry.healFunc then
		obj.heal = entry.healFunc(maxHP)
	else
		obj.heal = entry.heal or 0
	end
	return obj
end

function addon.Health.functions.updateAllowedHealth(force)
	local playerLevel = UnitLevel("player")
	local maxHP = UnitHealthMax("player") or 0

	if not force then
		local lastLevel = addon.Health._lastPlayerLevel
		local lastMaxHP = addon.Health._lastMaxHP

		local levelChanged = playerLevel ~= lastLevel
		local hpChanged = false

		if not lastMaxHP or lastMaxHP == 0 then
			hpChanged = true
		else
			local delta = abs(maxHP - lastMaxHP) / lastMaxHP
			hpChanged = delta >= MAXHP_RECALC_DELTA
		end

		if not levelChanged and not hpChanged then return end
	end

	addon.Health._lastPlayerLevel = playerLevel
	addon.Health._lastMaxHP = maxHP

	local filtered = {}
	local bestStone, bestPotion, bestOther
	local function isBetter(newItem, current)
		if not current then return true end
		local newLevel = newItem.requiredLevel or 0
		local curLevel = current.requiredLevel or 0
		if newLevel ~= curLevel then return newLevel > curLevel end
		-- If same level, prefer higher heal, then earlier entries (list order = freshness)
		local newHeal = newItem.heal or 0
		local curHeal = current.heal or 0
		if newHeal ~= curHeal then return newHeal > curHeal end
		local newOrder = newItem._order or math.huge
		local curOrder = current._order or math.huge
		return newOrder < curOrder
	end

	for i = 1, #addon.Health.healthList do
		local e = addon.Health.healthList[i]
		if (e.requiredLevel or 1) <= playerLevel then
			local w = wrapItem(e, maxHP)
			w._order = i
			insert(filtered, w)
			if w.type == "stone" then
				if isBetter(w, bestStone) then bestStone = w end
			elseif w.type == "potion" then
				if isBetter(w, bestPotion) then bestPotion = w end
			else
				if isBetter(w, bestOther) then bestOther = w end
			end
		end
	end

	if #filtered > 1 then
		sort(filtered, function(a, b)
			local aLevel, bLevel = a.requiredLevel or 0, b.requiredLevel or 0
			if aLevel ~= bLevel then return aLevel > bLevel end
			local aHeal, bHeal = a.heal or 0, b.heal or 0
			if aHeal ~= bHeal then return aHeal > bHeal end
			local aOrder, bOrder = a._order or math.huge, b._order or math.huge
			return aOrder < bOrder
		end)
	end

	addon.Health.filteredHealth = filtered
	addon.Health.bestStone = bestStone
	addon.Health.bestPotion = bestPotion
	addon.Health.bestOther = bestOther
end

-- Refresh cached availability flags for talents/classes once per event
function addon.Health.functions.refreshTalentCache()
	local c = addon.Health.cache
	c.isWarlock = addon.variables and addon.variables.unitClass == "WARLOCK" or false
	c.hasDemonicTalent = c.isWarlock and checkForTalent(386689) or false
end

function addon.Health.functions.isDemonicAvailable() return addon.Health.cache.hasDemonicTalent end
