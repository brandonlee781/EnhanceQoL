-- luacheck: globals EnhanceQoL C_FriendList
local addonName, addon = ...

local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.friends = addon.db.datapanel.friends or {}
	db = addon.db.datapanel.friends
	db.fontSize = db.fontSize or 13
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
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	frame:AddChild(fontSize)

	frame.frame:Show()
end

local GetNumFriends = C_FriendList.GetNumFriends
local GetFriendInfoByIndex = C_FriendList.GetFriendInfoByIndex

local myGuid = UnitGUID("player")

local tooltipData = {}
local function getFriends(stream)
	local numFriendsOnline = 0
	wipe(tooltipData)
	local gMember = GetNumGuildMembers()
	if gMember then
		for i = 1, gMember do
			local name, _, _, level, _, _, _, _, isOnline, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
			if isOnline and guid ~= myGuid then
				numFriendsOnline = numFriendsOnline + 1
				local unit = { name = name, level = level, class = class }
				table.insert(tooltipData, unit)
			end
		end
	end

	local numBNetTotal, numBNetOnline = BNGetNumFriends()
	if numBNetOnline then
		for i = 1, numBNetTotal, 1 do
			local info = C_BattleNet.GetFriendAccountInfo(i)
			if info and info.gameAccountInfo then
				if info.gameAccountInfo.isOnline and info.gameAccountInfo.characterName and info.gameAccountInfo.characterLevel then
					numFriendsOnline = numFriendsOnline + 1
					local unit = { name = info.gameAccountInfo.characterName, level = info.gameAccountInfo.characterLevel, class = info.gameAccountInfo.className }
					table.insert(tooltipData, unit)
				end
			end
		end
	end
	for i = 1, C_FriendList.GetNumFriends() do
		local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
		if friendInfo.connected then
			numFriendsOnline = numFriendsOnline + 1
			local unit = { name = friendInfo.name, level = friendInfo.level, class = friendInfo.className }
			table.insert(tooltipData, unit)
		end
	end
	stream.snapshot.fontSize = db and db.fontSize or 13
	stream.snapshot.text = numFriendsOnline .. " " .. FRIENDS
end

local provider = {
	id = "friends",
	version = 1,
	title = FRIENDS,
	update = getFriends,
	events = {
		PLAYER_LOGIN = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BN_FRIEND_ACCOUNT_ONLINE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		BN_FRIEND_ACCOUNT_OFFLINE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		FRIENDLIST_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
	OnMouseEnter = function(b)
		local tip = GameTooltip
		tip:ClearLines()
		tip:SetOwner(b, "ANCHOR_TOPLEFT")
		for _, v in ipairs(tooltipData) do
			local level = v.level
			if v.class then level = v.class .. " (" .. level .. ")" end
			tip:AddDoubleLine(v.name, level)
		end
		tip:AddLine(L["Right-Click for options"])
		tip:Show()

		local name = tip:GetName()
		local left1 = _G[name .. "TextLeft1"]
		local right1 = _G[name .. "TextRight1"]
		local r, g, b = NORMAL_FONT_COLOR:GetRGB()
		if left1 then
			left1:SetFontObject(GameTooltipText)
			left1:SetTextColor(r, g, b)
		end
		if right1 then
			right1:SetFontObject(GameTooltipText)
			right1:SetTextColor(r, g, b)
		end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
