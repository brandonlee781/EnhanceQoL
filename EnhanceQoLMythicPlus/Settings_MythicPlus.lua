local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local LSM = LibStub("LibSharedMedia-3.0")

local cTeleports = addon.functions.SettingsCreateCategory(nil, L["Teleports"], nil, "Teleports")
addon.SettingsLayout.teleportsCategory = cTeleports

local data = {
	{
		var = "teleportFrame",
		text = L["teleportEnabled"],
		desc = L["teleportEnabledDesc"],
		func = function(v)
			addon.db["teleportFrame"] = v
			addon.MythicPlus.functions.toggleFrame()
		end,
	},
	{
		var = "teleportsWorldMapEnabled",
		text = L["teleportsWorldMapEnabled"],
		desc = L["teleportsWorldMapEnabledDesc"],
		func = function(v) addon.db["teleportsWorldMapEnabled"] = v end,
		children = {
			{
				text = "|cffffd700" .. L["teleportsWorldMapHelp"] .. "|r",
				sType = "hint",
			},
		},
	},
	{
		var = "teleportsWorldMapShowSeason",
		text = L["teleportsWorldMapShowSeason"],
		desc = L["teleportsWorldMapShowSeasonDesc"],
		func = function(v) addon.db["teleportsWorldMapShowSeason"] = v end,
	},
	{
		var = "portalHideMissing",
		text = L["portalHideMissing"],
		func = function(v) addon.db["portalHideMissing"] = v end,
	},
}
-- TODO bug in tooltip in midnight beta - remove for now
if not addon.variables.isMidnight then table.insert(data, {
	text = L["portalShowTooltip"],
	var = "portalShowTooltip",
	func = function(value) addon.db["portalShowTooltip"] = value end,
}) end
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTeleports, data)

-- Potion Tracker (Combat & Dungeon)
local cPotion = addon.SettingsLayout.characterInspectCategory
if cPotion then
	addon.functions.SettingsCreateHeadline(cPotion, L["Potion Tracker"])
	if L["potionTrackerMidnightWarning"] then addon.functions.SettingsCreateText(cPotion, L["potionTrackerMidnightWarning"]) end

	local potionEnable = addon.functions.SettingsCreateCheckbox(cPotion, {
		var = "potionTracker",
		text = L["potionTracker"],
		desc = L["potionTrackerHeadline"],
		func = function(v)
			addon.db["potionTracker"] = v
			if v then
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			else
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then addon.MythicPlus.functions.resetCooldownBars() end
				if addon.MythicPlus and addon.MythicPlus.anchorFrame and addon.MythicPlus.anchorFrame.Hide then addon.MythicPlus.anchorFrame:Hide() end
			end
		end,
	})

	local function isPotionEnabled() return potionEnable and potionEnable.setting and potionEnable.setting:GetValue() == true end

	local potionOptions = {
		{
			var = "potionTrackerUpwardsBar",
			text = L["potionTrackerUpwardsBar"],
			func = function(v)
				addon.db["potionTrackerUpwardsBar"] = v
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.updateBars then addon.MythicPlus.functions.updateBars() end
			end,
		},
		{
			var = "potionTrackerClassColor",
			text = L["potionTrackerClassColor"],
			func = function(v) addon.db["potionTrackerClassColor"] = v end,
		},
		{
			var = "potionTrackerDisableRaid",
			text = L["potionTrackerDisableRaid"],
			func = function(v)
				addon.db["potionTrackerDisableRaid"] = v
				if v == true and UnitInRaid("player") and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.resetCooldownBars then
					addon.MythicPlus.functions.resetCooldownBars()
				end
			end,
		},
		{
			var = "potionTrackerShowTooltip",
			text = L["potionTrackerShowTooltip"],
			func = function(v) addon.db["potionTrackerShowTooltip"] = v end,
		},
		{
			var = "potionTrackerHealingPotions",
			text = L["potionTrackerHealingPotions"],
			func = function(v) addon.db["potionTrackerHealingPotions"] = v end,
		},
		{
			var = "potionTrackerOffhealing",
			text = L["potionTrackerOffhealing"],
			func = function(v) addon.db["potionTrackerOffhealing"] = v end,
		},
	}

	for _, entry in ipairs(potionOptions) do
		entry.parent = true
		entry.element = potionEnable.element
		entry.parentCheck = isPotionEnabled
		addon.functions.SettingsCreateCheckbox(cPotion, entry)
	end

	local function buildPotionTextureOptions()
		local map = {
			["DEFAULT"] = DEFAULT,
			["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard: UI-StatusBar",
			["Interface\\Buttons\\WHITE8x8"] = "Flat (white, tintable)",
			["Interface\\Tooltips\\UI-Tooltip-Background"] = "Dark Flat (Tooltip bg)",
		}
		for name, path in pairs(LSM and LSM:HashTable("statusbar") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
		local noDefault = {}
		for k, v in pairs(map) do
			if k ~= "DEFAULT" then noDefault[k] = v end
		end
		local sorted, order = addon.functions.prepareListForDropdown(noDefault)
		sorted["DEFAULT"] = DEFAULT
		table.insert(order, 1, "DEFAULT")
		sorted._order = order
		return sorted
	end

	addon.functions.SettingsCreateDropdown(cPotion, {
		var = "potionTrackerBarTexture",
		text = L["Bar Texture"],
		default = "DEFAULT",
		listFunc = buildPotionTextureOptions,
		get = function()
			local cur = addon.db["potionTrackerBarTexture"] or "DEFAULT"
			local list = buildPotionTextureOptions()
			if not list[cur] then cur = "DEFAULT" end
			return cur
		end,
		set = function(key)
			addon.db["potionTrackerBarTexture"] = key
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.applyPotionBarTexture then addon.MythicPlus.functions.applyPotionBarTexture() end
		end,
		parent = true,
		element = potionEnable.element,
		parentCheck = isPotionEnabled,
	})

	addon.functions.SettingsCreateButton(cPotion, {
		var = "potionTrackerAnchor",
		text = L["Toggle Anchor"],
		func = function()
			local anchor = addon.MythicPlus and addon.MythicPlus.anchorFrame
			if not anchor then return end
			if anchor:IsShown() then
				anchor:Hide()
			else
				anchor:Show()
			end
		end,
		parent = true,
		element = potionEnable.element,
		parentCheck = isPotionEnabled,
	})
end

-- Mythic+ & Raid (Combat & Dungeon)
local cMythic = addon.SettingsLayout.characterInspectCategory
if cMythic then
	addon.functions.SettingsCreateHeadline(cMythic, PLAYER_DIFFICULTY_MYTHIC_PLUS .. " & " .. RAID)

	-- Keystone Helper
	local keystoneEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "enableKeystoneHelper",
		text = L["enableKeystoneHelper"],
		desc = L["enableKeystoneHelperDesc"],
		func = function(v)
			addon.db["enableKeystoneHelper"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
	})
	local function isKeystoneEnabled() return keystoneEnable and keystoneEnable.setting and keystoneEnable.setting:GetValue() == true end

	local keystoneChildren = {
		{ var = "autoInsertKeystone", text = L["Automatically insert keystone"], func = function(v) addon.db["autoInsertKeystone"] = v end },
		{ var = "closeBagsOnKeyInsert", text = L["Close all bags on keystone insert"], func = function(v) addon.db["closeBagsOnKeyInsert"] = v end },
		{ var = "autoKeyStart", text = L["autoKeyStart"], func = function(v) addon.db["autoKeyStart"] = v end },
		{
			var = "groupfinderShowPartyKeystone",
			text = L["groupfinderShowPartyKeystone"],
			desc = L["groupfinderShowPartyKeystoneDesc"],
			func = function(v)
				addon.db["groupfinderShowPartyKeystone"] = v
				if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.togglePartyKeystone then addon.MythicPlus.functions.togglePartyKeystone() end
			end,
		},
		{
			var = "mythicPlusShowChestTimers",
			text = L["mythicPlusShowChestTimers"],
			desc = L["mythicPlusShowChestTimersDesc"],
			func = function(v) addon.db["mythicPlusShowChestTimers"] = v end,
		},
	}
	for _, entry in ipairs(keystoneChildren) do
		entry.parent = true
		entry.element = keystoneEnable.element
		entry.parentCheck = isKeystoneEnabled
		addon.functions.SettingsCreateCheckbox(cMythic, entry)
	end

	local listPull, orderPull = addon.functions.prepareListForDropdown({
		[1] = L["None"],
		[2] = L["Blizzard Pull Timer"],
		[3] = L["DBM / BigWigs Pull Timer"],
		[4] = L["Both"],
	})
	listPull._order = orderPull
	addon.functions.SettingsCreateDropdown(cMythic, {
		var = "PullTimerType",
		text = L["PullTimer"],
		type = Settings.VarType.Number,
		default = 2,
		list = listPull,
		get = function() return addon.db["PullTimerType"] or 1 end,
		set = function(value) addon.db["PullTimerType"] = value end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "noChatOnPullTimer",
		text = L["noChatOnPullTimer"],
		func = function(v) addon.db["noChatOnPullTimer"] = v end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateSlider(cMythic, {
		var = "pullTimerLongTime",
		text = L["sliderLongTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 10,
		get = function() return addon.db["pullTimerLongTime"] or 10 end,
		set = function(val) addon.db["pullTimerLongTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	addon.functions.SettingsCreateSlider(cMythic, {
		var = "pullTimerShortTime",
		text = L["sliderShortTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 5,
		get = function() return addon.db["pullTimerShortTime"] or 5 end,
		set = function(val) addon.db["pullTimerShortTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
	})

	-- Objective Tracker
	local objEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableObjectiveTracker",
		text = L["mythicPlusEnableObjectiveTracker"],
		desc = L["mythicPlusEnableObjectiveTrackerDesc"],
		func = function(v)
			addon.db["mythicPlusEnableObjectiveTracker"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
	})
	local function isObjectiveEnabled() return objEnable and objEnable.setting and objEnable.setting:GetValue() == true end

	local listObj, orderObj = addon.functions.prepareListForDropdown({ [1] = L["HideTracker"], [2] = L["collapse"] })
	listObj._order = orderObj
	addon.functions.SettingsCreateDropdown(cMythic, {
		var = "mythicPlusObjectiveTrackerSetting",
		text = L["mythicPlusObjectiveTrackerSetting"],
		type = Settings.VarType.Number,
		default = addon.db["mythicPlusObjectiveTrackerSetting"] or 1,
		list = listObj,
		get = function() return addon.db["mythicPlusObjectiveTrackerSetting"] or 1 end,
		set = function(value)
			addon.db["mythicPlusObjectiveTrackerSetting"] = value
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parent = true,
		element = objEnable.element,
		parentCheck = isObjectiveEnabled,
	})

	-- Dungeon Score next to Group Finder
	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "groupfinderShowDungeonScoreFrame",
		text = L["groupfinderShowDungeonScoreFrame"]:format(DUNGEON_SCORE),
		func = function(v)
			addon.db["groupfinderShowDungeonScoreFrame"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
	})

	-- BR Tracker
	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusBRTrackerEnabled",
		text = L["mythicPlusBRTrackerEnabled"],
		desc = L["mythicPlusBRTrackerEditModeHint"],
		func = function(v)
			addon.db["mythicPlusBRTrackerEnabled"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.createBRFrame then
				addon.MythicPlus.functions.createBRFrame()
			elseif addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then
				addon.MythicPlus.functions.setObjectiveFrames()
			end
		end,
	})

	-- Dungeon Finder filters
	local filterEnable = addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableDungeonFilter",
		text = L["mythicPlusEnableDungeonFilter"],
		desc = L["mythicPlusEnableDungeonFilterDesc"]:format(REPORT_GROUP_FINDER_ADVERTISEMENT),
		func = function(v)
			addon.db["mythicPlusEnableDungeonFilter"] = v
			if addon.MythicPlus and addon.MythicPlus.functions then
				if v and addon.MythicPlus.functions.addDungeonFilter then
					addon.MythicPlus.functions.addDungeonFilter()
				elseif not v and addon.MythicPlus.functions.removeDungeonFilter then
					addon.MythicPlus.functions.removeDungeonFilter()
				end
			end
		end,
	})
	local function isFilterEnabled() return filterEnable and filterEnable.setting and filterEnable.setting:GetValue() == true end

	addon.functions.SettingsCreateCheckbox(cMythic, {
		var = "mythicPlusEnableDungeonFilterClearReset",
		text = L["mythicPlusEnableDungeonFilterClearReset"],
		func = function(v) addon.db["mythicPlusEnableDungeonFilterClearReset"] = v end,
		parent = true,
		element = filterEnable.element,
		parentCheck = isFilterEnabled,
	})
end

-- Auto Marker (Combat & Dungeon)
if addon.SettingsLayout.characterInspectCategory and not addon.variables.isMidnight then
	local cAuto = addon.SettingsLayout.characterInspectCategory
	addon.functions.SettingsCreateHeadline(cAuto, L["AutoMark"])
	if L["autoMarkMidnightWarning"] then addon.functions.SettingsCreateText(cAuto, L["autoMarkMidnightWarning"]) end
	if L["autoMarkTankExplanation"] then addon.functions.SettingsCreateText(cAuto, "|cffffd700" .. L["autoMarkTankExplanation"]:format(TANK, COMMUNITY_MEMBER_ROLE_NAME_LEADER, TANK) .. "|r") end

	local autoMarkTank = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkTankInDungeon",
		text = L["autoMarkTankInDungeon"]:format(TANK),
		func = function(v) addon.db["autoMarkTankInDungeon"] = v end,
	})
	local function isTankEnabled() return autoMarkTank and autoMarkTank.setting and autoMarkTank.setting:GetValue() == true end

	local raidIconList = {
		[1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:20|t",
		[2] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:20|t",
		[3] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:20|t",
		[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:20|t",
		[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:20|t",
		[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:20|t",
		[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:20|t",
		[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:20|t",
	}
	local iconOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }

	addon.functions.SettingsCreateDropdown(cAuto, {
		var = "autoMarkTankInDungeonMarker",
		text = L["autoMarkTankInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = addon.db["autoMarkTankInDungeonMarker"],
		get = function() return addon.db["autoMarkTankInDungeonMarker"] or 1 end,
		set = function(value)
			if value == addon.db["autoMarkHealerInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(HEALER))
				return
			end
			addon.db["autoMarkTankInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkTank.element,
		parentCheck = isTankEnabled,
	})

	local autoMarkHealer = addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "autoMarkHealerInDungeon",
		text = L["autoMarkHealerInDungeon"]:format(HEALER),
		func = function(v) addon.db["autoMarkHealerInDungeon"] = v end,
		notify = "autoMarkTankInDungeon",
	})
	local function isHealerEnabled() return autoMarkHealer and autoMarkHealer.setting and autoMarkHealer.setting:GetValue() == true end

	addon.functions.SettingsCreateDropdown(cAuto, {
		var = "autoMarkHealerInDungeonMarker",
		text = L["autoMarkHealerInDungeonMarker"],
		type = Settings.VarType.Number,
		list = raidIconList,
		listOrder = iconOrder,
		default = addon.db["autoMarkHealerInDungeonMarker"],
		get = function() return addon.db["autoMarkHealerInDungeonMarker"] or 8 end,
		set = function(value)
			if value == addon.db["autoMarkTankInDungeonMarker"] then
				print("|cff00ff98Enhance QoL|r: " .. L["markerAlreadyUsed"]:format(TANK))
				return
			end
			addon.db["autoMarkHealerInDungeonMarker"] = value
		end,
		parent = true,
		element = autoMarkHealer.element,
		parentCheck = isHealerEnabled,
	})

	addon.functions.SettingsCreateCheckbox(cAuto, {
		var = "mythicPlusNoHealerMark",
		text = L["mythicPlusNoHealerMark"],
		func = function(v) addon.db["mythicPlusNoHealerMark"] = v end,
	})

	local excludeOptions = {
		{ value = "normal", text = PLAYER_DIFFICULTY1, db = "mythicPlusIgnoreNormal" },
		{ value = "heroic", text = PLAYER_DIFFICULTY2, db = "mythicPlusIgnoreHeroic" },
		{ value = "mythic", text = PLAYER_DIFFICULTY6, db = "mythicPlusIgnoreMythic" },
		{ value = "timewalking", text = PLAYER_DIFFICULTY_TIMEWALKER, db = "mythicPlusIgnoreTimewalking" },
		{ value = "event", text = BATTLE_PET_SOURCE_7, db = "mythicPlusIgnoreEvent" },
	}

	addon.functions.SettingsCreateMultiDropdown(cAuto, {
		var = "autoMarkIgnoreDifficulties",
		text = L["Exclude"] or "Exclude",
		options = excludeOptions,
		isSelectedFunc = function(key)
			for _, opt in ipairs(excludeOptions) do
				if opt.value == key then return addon.db[opt.db] == true end
			end
			return false
		end,
		setSelectedFunc = function(key, shouldSelect)
			for _, opt in ipairs(excludeOptions) do
				if opt.value == key then
					addon.db[opt.db] = shouldSelect and true or false
					break
				end
			end
		end,
		parent = true,
		parentCheck = function()
			return addon.SettingsLayout.elements["autoMarkHealerInDungeon"]
					and addon.SettingsLayout.elements["autoMarkHealerInDungeon"].setting
					and addon.SettingsLayout.elements["autoMarkHealerInDungeon"].setting:GetValue() == true
				or addon.SettingsLayout.elements["autoMarkTankInDungeon"]
					and addon.SettingsLayout.elements["autoMarkTankInDungeon"].setting
					and addon.SettingsLayout.elements["autoMarkTankInDungeon"].setting:GetValue() == true
		end,
		element = addon.SettingsLayout.elements["autoMarkTankInDungeon"].element,
	})
end

----- REGION END

function addon.functions.initTeleports() end

local eventHandlers = {}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
