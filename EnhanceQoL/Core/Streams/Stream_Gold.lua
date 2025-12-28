-- luacheck: globals EnhanceQoL
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function getOptionsHint()
	if addon.DataPanel and addon.DataPanel.GetOptionsHintText then
		local text = addon.DataPanel.GetOptionsHintText()
		if text ~= nil then return text end
		return nil
	end
	return L["Right-Click for options"]
end

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.gold = addon.db.datapanel.gold or {}
	db = addon.db.datapanel.gold
	db.fontSize = db.fontSize or 14
	db.displayMode = db.displayMode or "character"
end
local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(300)
	frame:SetHeight(200)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel(FONT_SIZE)
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	frame.frame:Show()
end

local floor = math.floor
local GetMoney = GetMoney

local COPPER_PER_GOLD = 10000

local function formatGoldString(copper)
	local g = floor(copper / COPPER_PER_GOLD)
	local s = floor((copper % COPPER_PER_GOLD) / 100)
	local c = copper % 100
	local gText = (BreakUpLargeNumbers and BreakUpLargeNumbers(g)) or tostring(g)
	return gText, s, c
end

local function getAccountTotalMoney()
	local total, hasEntry = 0, false
	if addon.db and type(addon.db.moneyTracker) == "table" then
		for _, info in pairs(addon.db.moneyTracker) do
			if type(info) == "table" and type(info.money) == "number" then
				total = total + info.money
				hasEntry = true
			end
		end
	end
	local warband = addon.db and tonumber(addon.db.warbandGold)
	if warband and warband > 0 then
		total = total + warband
		hasEntry = true
	end
	if hasEntry then return total end
	return nil
end

local function getDisplayLabel()
	if db and db.displayMode == "account" then return L["goldPanelDisplayAccount"] or "Account total" end
	return L["goldPanelDisplayCharacter"] or "Character"
end

local function toggleDisplayMode()
	ensureDB()
	if db.displayMode == "account" then
		db.displayMode = "character"
	else
		db.displayMode = "account"
	end
	addon.DataHub:RequestUpdate(stream)
end

local function checkMoney(stream)
	ensureDB()
	local money = GetMoney() or 0
	if db.displayMode == "account" then
		local total = getAccountTotalMoney()
		if total ~= nil then money = total end
	end
	local gText, s, c = formatGoldString(money)
	local size = db and db.fontSize or 12
	stream.snapshot.fontSize = size
	stream.snapshot.text = ("|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t %s"):format(size, size, gText)
	local clickHint = L["goldPanelClickHint"] or "Left-click to toggle account/character gold"
	local modeHint = (L["goldPanelDisplay"] or "Gold display") .. ": " .. getDisplayLabel()
	local hint = getOptionsHint()
	if hint then
		stream.snapshot.tooltip = clickHint .. "\n" .. modeHint .. "\n" .. hint
	else
		stream.snapshot.tooltip = clickHint .. "\n" .. modeHint
	end
end

local provider = {
	id = "gold",
	version = 1,
	title = WORLD_QUEST_REWARD_FILTERS_GOLD,
	update = checkMoney,
	events = {
		PLAYER_MONEY = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		ACCOUNT_MONEY = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "LeftButton" then
			toggleDisplayMode()
		elseif btn == "RightButton" then
			createAceWindow()
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
