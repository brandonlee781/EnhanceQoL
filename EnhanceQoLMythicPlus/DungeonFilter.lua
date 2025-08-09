local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

addon.functions.InitDBValue("mythicPlusDungeonFilters", {})
if addon.db["mythicPlusDungeonFilters"][UnitGUID("player")] == nil then addon.db["mythicPlusDungeonFilters"][UnitGUID("player")] = {} end

local pDb = addon.db["mythicPlusDungeonFilters"][UnitGUID("player")]

local appliedLookup = {}

local ACTIVE_STATUS = {
	applied = true,
	invited = true,
	inviteaccepted = true,
	pending = true,
}

local function UpdateAppliedCache()
	wipe(appliedLookup)
	for _, appID in ipairs(C_LFGList.GetApplications()) do
		local resultID, status = C_LFGList.GetApplicationInfo(appID)
		if resultID and ACTIVE_STATUS[status] then appliedLookup[resultID] = true end
	end
end

local LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BR_CLASSES = { DRUID = true, WARLOCK = true, DEATHKNIGHT = true, PALADIN = true }

local SearchInfoCache = {}

local function CacheResultInfo(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)

	if not info then
		SearchInfoCache[resultID] = nil
		return
	end

	local cached = SearchInfoCache[resultID] or {}
	cached.searchResultID = resultID
	cached.numMembers = info.numMembers

	cached.extraCalculated = nil
	cached.groupTankCount = nil
	cached.groupHealerCount = nil
	cached.groupDPSCount = nil
	cached.hasLust = nil
	cached.hasBR = nil
	cached.hasSameSpec = nil

	SearchInfoCache[resultID] = cached
end

local function EnsureExtraInfo(resultID)
	local info = SearchInfoCache[resultID]
	if not info or info.extraCalculated then return info end

	local tank, healer, dps = 0, 0, 0
	local lust, br, sameSpec = false, false, false

	for i = 1, info.numMembers do
		local mData = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
		if mData then
			if mData.assignedRole == "TANK" then
				tank = tank + 1
			elseif mData.assignedRole == "HEALER" then
				healer = healer + 1
			elseif mData.assignedRole == "DAMAGER" then
				dps = dps + 1
			end
			if LUST_CLASSES[mData.classFilename] then
				lust = true
			elseif BR_CLASSES[mData.classFilename] then
				br = true
			end
			if mData.classFilename == addon.variables.unitClass and mData.specName == addon.variables.unitSpecName then
				sameSpec = true
			end
		end
	end

	info.groupTankCount = tank
	info.groupHealerCount = healer
	info.groupDPSCount = dps
	info.hasLust = lust
	info.hasBR = br
	info.hasSameSpec = sameSpec
	info.extraCalculated = true
	return info
end

local function PopulateInfoCache()
	wipe(SearchInfoCache)
	local panel = LFGListFrame.SearchPanel
	local dp = panel.ScrollBox and panel.ScrollBox:GetDataProvider()
	if not dp then return end
	for _, element in dp:EnumerateEntireRange() do
		local resultID = element.resultID or element.id
		if resultID then CacheResultInfo(resultID) end
	end
end

local playerIsLust = LUST_CLASSES[addon.variables.unitClass]
local playerIsBR = BR_CLASSES[addon.variables.unitClass]

local drop = LFGListFrame.SearchPanel.FilterButton
local originalSetupGen
local initialAllEntries = {}
local removedResults = {}

local titleScore1 = LFGListFrame:CreateFontString(nil, "OVERLAY")
titleScore1:SetFont(addon.variables.defaultFont, 13, "OUTLINE")
titleScore1:SetPoint("TOPRIGHT", PVEFrameLeftInset, "TOPRIGHT", -10, -5)
titleScore1:Hide()

drop:HookScript("OnHide", function()
	originalSetupGen = nil
	titleScore1:Hide()
	wipe(SearchInfoCache)
end)

local function EQOL_AddLFGEntries(owner, root, ctx)
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	local panel = LFGListFrame.SearchPanel
	if panel.categoryID ~= 2 then return end
	root:CreateTitle("")

	root:CreateTitle(addonName)
	root:CreateCheckbox(L["Partyfit"], function() return pDb["partyFit"] end, function() pDb["partyFit"] = not pDb["partyFit"] end)
	if not playerIsLust then root:CreateCheckbox(L["BloodlustAvailable"], function() return pDb["bloodlustAvailable"] end, function() pDb["bloodlustAvailable"] = not pDb["bloodlustAvailable"] end) end
	if not playerIsBR then root:CreateCheckbox(L["BattleResAvailable"], function() return pDb["battleResAvailable"] end, function() pDb["battleResAvailable"] = not pDb["battleResAvailable"] end) end
	if addon.variables.unitRole == "DAMAGER" then
		root:CreateCheckbox(
			(L["NoSameSpec"]):format(addon.variables.unitSpecName .. " " .. select(1, UnitClass("player"))),
			function() return pDb["NoSameSpec"] end,
			function() pDb["NoSameSpec"] = not pDb["NoSameSpec"] end
		)
	end
end

if Menu and Menu.ModifyMenu then Menu.ModifyMenu("MENU_LFG_FRAME_SEARCH_FILTER", EQOL_AddLFGEntries) end

local function MyCustomFilter(info)
	if appliedLookup[info.searchResultID] then return true end
	if info.numMembers == 5 then return false end

	info = EnsureExtraInfo(info.searchResultID) or info

	local groupTankCount = info.groupTankCount or 0
	local groupHealerCount = info.groupHealerCount or 0
	local groupDPSCount = info.groupDPSCount or 0
	local hasLust = info.hasLust or false
	local hasBR = info.hasBR or false
	local hasSameSpec = info.hasSameSpec or false

	if addon.variables.unitRole == "DAMAGER" and pDb["NoSameSpec"] and hasSameSpec then return false end

	if pDb["partyFit"] then
		-- Party-queue role availability check
		local needTanks, needHealers, needDPS = 0, 0, 0
		local partySize = GetNumGroupMembers()
		if partySize > 1 then
			-- Count roles in the player's party
			for i = 1, partySize do
				local unit = (i == 1) and "player" or ("party" .. (i - 1))
				local role = UnitGroupRolesAssigned(unit)
				if role == "TANK" then
					needTanks = needTanks + 1
				elseif role == "HEALER" then
					needHealers = needHealers + 1
				elseif role == "DAMAGER" then
					needDPS = needDPS + 1
				end
			end
		else
			-- solo or solo party also nur meine Rolle mit reinnehmen
			local role = addon.variables.unitRole
			if role == "TANK" then
				needTanks = needTanks + 1
			elseif role == "HEALER" then
				needHealers = needHealers + 1
			elseif role == "DAMAGER" then
				needDPS = needDPS + 1
			end
		end

		-- check for basic group requirement
		if needTanks > 1 then return false end
		if needHealers > 1 then return false end
		if needDPS > 3 then return false end

		if (1 - groupTankCount) < needTanks then return false end
		if (1 - groupHealerCount) < needHealers then return false end
		if (3 - groupDPSCount) < needDPS then return false end
		local freeSlots = 5 - info.numMembers
		if freeSlots < partySize then return false end
	end

	local partyHasLust, partyHasBR = false, false
	for i = 1, GetNumGroupMembers() do
		local unit = (i == 1) and "player" or ("party" .. (i - 1))
		local _, class = UnitClass(unit)
		if class and LUST_CLASSES[class] then partyHasLust = true end
		if class and BR_CLASSES[class] then partyHasBR = true end
	end

	local missingProviders = 0
	if pDb["bloodlustAvailable"] then
		if not hasLust and not partyHasLust then
			if groupTankCount == 0 then missingProviders = missingProviders + 1 end
			missingProviders = missingProviders + 1
		end
	end
	if pDb["battleResAvailable"] then
		if not hasBR and not partyHasBR then missingProviders = missingProviders + 1 end
	end

	local slotsAfterJoin = 5 - info.numMembers - 1
	if slotsAfterJoin < missingProviders then return false end
	return true
end

local _eqolFiltering = false

local function ApplyEQOLFilters(isInitial)
	if _eqolFiltering then return end
	_eqolFiltering = true

	-- Basic guards
	if not drop or not drop:IsVisible() then _eqolFiltering = false; return end
	if not addon.db["mythicPlusEnableDungeonFilter"] then _eqolFiltering = false; return end

	local panel = LFGListFrame and LFGListFrame.SearchPanel
	if not panel or panel.categoryID ~= 2 then
		titleScore1:Hide()
		_eqolFiltering = false
		return
	end
	local dp = panel.ScrollBox and panel.ScrollBox:GetDataProvider()
	if not dp then _eqolFiltering = false; return end

	-- Fast exit if nothing to filter (mirrors the old conditions)
	local needFilter = false
	if (pDb["bloodlustAvailable"] and not playerIsLust) then needFilter = true end
	if (pDb["battleResAvailable"] and not playerIsBR) then needFilter = true end
	if pDb["partyFit"] then needFilter = true end
	if (pDb["NoSameSpec"] and addon.variables.unitRole == "DAMAGER") then needFilter = true end
	if not needFilter then
		titleScore1:Hide()
		_eqolFiltering = false
		return
	end

	-- On initial call, record the current set of entries
	if isInitial or not next(initialAllEntries) then
		wipe(initialAllEntries)
		wipe(removedResults)
		for _, element in dp:EnumerateEntireRange() do
			local resultID = element.resultID or element.id
			if resultID then initialAllEntries[resultID] = true end
		end
	end

	-- Build removal list without mutating the provider during enumeration
	local toRemove = {}
	for _, element in dp:EnumerateEntireRange() do
		local resultID = element.resultID or element.id
		if resultID and not removedResults[resultID] then
			if not SearchInfoCache[resultID] then
				CacheResultInfo(resultID)
			end
			local info = SearchInfoCache[resultID]
			if info and not MyCustomFilter(info) then
				table.insert(toRemove, { elem = element, id = resultID })
			end
		end
	end

	for i = 1, #toRemove do
		local r = toRemove[i]
		dp:Remove(r.elem)
		initialAllEntries[r.id] = false
		removedResults[r.id] = true
	end

	local removedCount = 0
	for _, v in pairs(initialAllEntries) do
		if v == false then removedCount = removedCount + 1 end
	end

	if removedCount > 0 then
		titleScore1:SetFormattedText((L["filteredTextEntries"]):format(removedCount))
		titleScore1:Show()
	else
		titleScore1:Hide()
	end

	-- Refresh the scrollbox (be tolerant if constants differ)
	if panel.ScrollBox and panel.ScrollBox.FullUpdate then
		if ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately then
			panel.ScrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
		else
			panel.ScrollBox:FullUpdate()
		end
	end

	_eqolFiltering = false
end

local f

function addon.MythicPlus.functions.addDungeonFilter()
	if LFGListFrame.SearchPanel.FilterButton:IsShown() then
		LFGListFrame:Hide()
		LFGListFrame:Show()
	end
	f = CreateFrame("Frame")
	UpdateAppliedCache()
	f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	f:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
	f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	f:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
	f:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
	f:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
	f:RegisterEvent("LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS")
	f:SetScript("OnEvent", function(_, event, ...)
		if not drop:IsVisible() then return end
		if not addon.db["mythicPlusEnableDungeonFilter"] then return end
		if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
			PopulateInfoCache()
			ApplyEQOLFilters(true)
		elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
			local resultID = ...
			if resultID then CacheResultInfo(resultID) end
			ApplyEQOLFilters(false)
		elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
			PopulateInfoCache()
			ApplyEQOLFilters(true)
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			if drop then drop.eqolWrapped = nil end
		elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" or event == "LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS" then
			UpdateAppliedCache()
			ApplyEQOLFilters(false) -- <- direkt hinterher filtern
		end
	end)
end

function addon.MythicPlus.functions.removeDungeonFilter()
	if f then
		f:UnregisterAllEvents()
		f:Hide()
		f:SetScript("OnEvent", nil)
		f = nil
		wipe(SearchInfoCache)
		titleScore1:Hide()
		if LFGListFrame.SearchPanel.FilterButton:IsShown() then
			LFGListFrame:Hide()
			LFGListFrame:Show()
		end
	end
end

LFGListFrame.SearchPanel.FilterButton.ResetButton:HookScript("OnClick", function()
	if not addon.db["mythicPlusEnableDungeonFilter"] then return end
	if not addon.db["mythicPlusEnableDungeonFilterClearReset"] then return end
	pDb["bloodlustAvailable"] = false
	pDb["battleResAvailable"] = false
	pDb["partyFit"] = false
	pDb["NoSameSpec"] = false
end)
