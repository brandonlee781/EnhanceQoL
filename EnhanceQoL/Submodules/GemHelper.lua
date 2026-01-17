local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

local NumSockets = C_ItemSocketInfo and C_ItemSocketInfo.GetNumSockets or GetNumSockets
local TypeSockets = C_ItemSocketInfo and C_ItemSocketInfo.GetSocketTypes or GetSocketTypes
local wipe = wipe
local tinsert = table.insert
local tremove = table.remove

local TRACKED_SOCKET_SLOTS = {
	[1] = true, -- Head
	[2] = true, -- Neck
	[6] = true, -- Waist
	[9] = true, -- Wrist
	[11] = true, -- Finger 1
	[12] = true, -- Finger 2
}

local TRACKED_GEM_TYPES = {
	{ key = "Blasphemite", icon = 630620 },
	{ key = "Amber", icon = 5931396 },
	{ key = "Onyx", icon = 5931393 },
	{ key = "Sapphire", icon = 5931403 },
	{ key = "Emerald", icon = 5931390 },
	{ key = "Ruby", icon = 5931400 },
}

local TRACKER_ICON_SIZE = 32
local TRACKER_ICON_PAD = 4
local TRACKER_LABEL_HEIGHT = 12
local TRACKER_LABEL_SPACING = 2
local TRACKER_LABEL_MAX = 6
local TRACKER_ANCHOR_X = -2
local TRACKER_ANCHOR_Y = -(40 + TRACKER_LABEL_HEIGHT + TRACKER_LABEL_SPACING)
local TRACKER_UPDATE_DELAY = 1.0

local TRACKED_GEM_BY_KEY = {}
for _, entry in ipairs(TRACKED_GEM_TYPES) do
	TRACKED_GEM_BY_KEY[entry.key] = entry
end

local GEM_TYPE_INFO = {}
GEM_TYPE_INFO["Yellow"] = 9
GEM_TYPE_INFO["Red"] = 9
GEM_TYPE_INFO["Blue"] = 9
GEM_TYPE_INFO["Hydraulic"] = 9
GEM_TYPE_INFO["Cogwheel"] = 9
GEM_TYPE_INFO["Meta"] = 9
GEM_TYPE_INFO["Prismatic"] = { [9] = true, [10] = true }
GEM_TYPE_INFO["SingingThunder"] = 9
GEM_TYPE_INFO["SingingWind"] = 9
GEM_TYPE_INFO["SingingSea"] = 9
GEM_TYPE_INFO["Fiber"] = 9

local specialGems = {}
specialGems[238042] = "Fiber"
specialGems[238044] = "Fiber"
specialGems[238045] = "Fiber"
specialGems[238046] = "Fiber"

specialGems[217113] = "Prismatic" -- Cubic Blasphemia
specialGems[217114] = "Prismatic" -- Cubic Blasphemia
specialGems[217115] = "Prismatic" -- Cubic Blasphemia

specialGems[213741] = "Prismatic" -- Culminating Blasphemite
specialGems[213742] = "Prismatic" -- Culminating Blasphemite
specialGems[213743] = "Prismatic" -- Culminating Blasphemite

specialGems[213744] = "Prismatic" -- Elusive Blasphemite
specialGems[213745] = "Prismatic" -- Elusive Blasphemite
specialGems[213746] = "Prismatic" -- Elusive Blasphemite

specialGems[213738] = "Prismatic" -- Insightful Blasphemite
specialGems[213739] = "Prismatic" -- Insightful Blasphemite
specialGems[213740] = "Prismatic" -- Insightful Blasphemite

specialGems[213747] = "Prismatic" -- Enduring Bloodstone
specialGems[213748] = "Prismatic" -- Cognitive Bloodstone
specialGems[213749] = "Prismatic" -- Determined Bloodstone

local frame = CreateFrame("Frame")

local gemButtons = {}
local gemButtonPool = {}
local gemLayoutQueued = false
local gemTrackerButtons = {}
local gemTrackerQueued = false
local gemTrackerHooked = false
local gemSocketHooked = false
-- helper to refresh / clear buttons
local function clearGemButtons()
	if not gemButtons then return end
	for _, btn in ipairs(gemButtons) do
		btn:ClearAllPoints()
		btn:Hide()
		btn.itemLink = nil
		btn.bag = nil
		btn.slot = nil
		btn.itemName = nil
		btn:SetParent(UIParent)
		tinsert(gemButtonPool, btn)
	end
	wipe(gemButtons)
end

local function getGemTracker()
	return _G.EnhanceQoLGemTracker
end

local function ensureGemTracker()
	local tracker = getGemTracker()
	if tracker then return tracker end
	if not PaperDollFrame then return nil end
	tracker = CreateFrame("Frame", "EnhanceQoLGemTracker", PaperDollFrame)
	tracker:SetFrameStrata("HIGH")
	tracker:SetSize((#TRACKED_GEM_TYPES * TRACKER_ICON_SIZE) + ((#TRACKED_GEM_TYPES - 1) * TRACKER_ICON_PAD), TRACKER_ICON_SIZE + TRACKER_LABEL_HEIGHT + TRACKER_LABEL_SPACING)
	tracker:SetPoint("TOPRIGHT", PaperDollFrame, "BOTTOMRIGHT", 0, 0)

	for index, info in ipairs(TRACKED_GEM_TYPES) do
		local btn = CreateFrame("Frame", nil, tracker)
		btn:SetSize(TRACKER_ICON_SIZE, TRACKER_ICON_SIZE + TRACKER_LABEL_HEIGHT + TRACKER_LABEL_SPACING)
		btn:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -((index - 1) * (TRACKER_ICON_SIZE + TRACKER_ICON_PAD)), 0)

		local iconFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		iconFrame:SetSize(TRACKER_ICON_SIZE, TRACKER_ICON_SIZE)
		iconFrame:SetPoint("TOP", btn, "TOP", 0, 0)

		iconFrame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
			insets = { left = 0, right = 0, top = 0, bottom = 0 },
		})
		iconFrame:SetBackdropColor(0, 0, 0, 0.25)
		iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

		local icon = iconFrame:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(info.icon)
		btn.icon = icon

		local glow = iconFrame:CreateTexture(nil, "OVERLAY")
		glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0.6)
		glow:SetAllPoints(iconFrame)
		glow:Hide()
		btn.glow = glow

		local count = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		count:SetPoint("BOTTOMRIGHT", -1, 1)
		btn.count = count

		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOP", iconFrame, "BOTTOM", 0, -TRACKER_LABEL_SPACING)
		label:SetJustifyH("CENTER")
		local labelText = info.key
		if labelText and #labelText > TRACKER_LABEL_MAX then labelText = labelText:sub(1, TRACKER_LABEL_MAX) end
		label:SetText(labelText or "")
		btn.label = label

		gemTrackerButtons[info.key] = btn
	end

	_G.EnhanceQoLGemTracker = tracker
	return tracker
end

local function parseGemType(gemName)
	if not gemName then return nil, nil end
	local prefix, gemType = gemName:match("^([^%s]+)%s+([^%s]+)")
	if gemType and TRACKED_GEM_BY_KEY[gemType] then return prefix, gemType end
	for key in pairs(TRACKED_GEM_BY_KEY) do
		if gemName:find(key, 1, true) then return nil, key end
	end
	return nil, nil
end

local updateGemTracker

local function queueGemTrackerUpdate(delay)
	if gemTrackerQueued or not C_Timer then return end
	gemTrackerQueued = true
	C_Timer.After(delay or 0.2, function()
		gemTrackerQueued = false
		if addon.db and addon.db["enableGemHelper"] then
			if updateGemTracker then updateGemTracker() end
		end
	end)
end

local function markGemTrackerDirty(delay)
	local useDelay = delay
	if useDelay == nil then useDelay = TRACKER_UPDATE_DELAY end
	if PaperDollFrame and PaperDollFrame:IsShown() then queueGemTrackerUpdate(useDelay) end
end

local function hookSocketingFrame()
	if gemSocketHooked or not ItemSocketingFrame then return end
	gemSocketHooked = true
	ItemSocketingFrame:HookScript("OnHide", function()
		if addon.db and addon.db["enableGemHelper"] then markGemTrackerDirty() end
	end)
end

updateGemTracker = function()
	if not addon.db or not addon.db["enableGemHelper"] then
		local tracker = getGemTracker()
		if tracker then tracker:Hide() end
		return
	end
	if not PaperDollFrame or not PaperDollFrame:IsShown() then return end
	if ItemSocketingFrame and ItemSocketingFrame:IsShown() then hookSocketingFrame() end

	local tracker = ensureGemTracker()
	if not tracker then return end
	tracker:Show()

	local gemsByType = {}
	local needsRetry = false
	for slotID in pairs(TRACKED_SOCKET_SLOTS) do
		local itemLink = GetInventoryItemLink("player", slotID)
		if itemLink then
			local numSockets = C_Item.GetItemNumSockets(itemLink) or 0
			for i = 1, numSockets do
				local gemID = C_Item.GetItemGemID(itemLink, i)
				if gemID then
					local gemName = C_Item.GetItemNameByID(gemID)
					if not gemName then
						needsRetry = true
					else
						local _, gemType = parseGemType(gemName)
						if gemType then
							local entry = gemsByType[gemType]
							if not entry then
								entry = { count = 0, icon = C_Item.GetItemIconByID(gemID) }
								gemsByType[gemType] = entry
							end
							entry.count = entry.count + 1
						end
					end
				end
			end
		end
	end

	for _, info in ipairs(TRACKED_GEM_TYPES) do
		local btn = gemTrackerButtons[info.key]
		if btn then
			local data = gemsByType[info.key]
			if data then
				btn.icon:SetTexture(data.icon or info.icon)
				btn.icon:SetDesaturated(false)
				btn.glow:Hide()
				btn.count:SetText(data.count and data.count > 1 and tostring(data.count) or "")
			else
				btn.icon:SetTexture(info.icon)
				btn.icon:SetDesaturated(true)
				btn.glow:Show()
				btn.count:SetText("")
			end
		end
	end

	if needsRetry then queueGemTrackerUpdate() end
end

local function hookGemTracker()
	if gemTrackerHooked or not PaperDollFrame then return end
	gemTrackerHooked = true
	PaperDollFrame:HookScript("OnShow", function()
		if addon.db and addon.db["enableGemHelper"] then updateGemTracker() end
	end)
end

local function createGemHelper()
	if EnhanceQoLGemHelper then return end
	-- backdrop anchor so we get the nice border you already had
	local frameAnchor = CreateFrame("Frame", "EnhanceQoLGemHelper", ItemSocketingFrame, "BackdropTemplate")
	frameAnchor:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frameAnchor:SetBackdropColor(0, 0, 0, 0.8)
	frameAnchor:SetPoint("TOPLEFT", ItemSocketingFrame, "BOTTOMLEFT", 0, -2)
	local width, height = ItemSocketingFrame:GetSize()
	frameAnchor:SetSize(width, 100)
end

local function createButton(parent, itemTexture, itemLink, bag, slot, locked)
	local button = tremove(gemButtonPool)
	if not button then
		button = CreateFrame("Button", nil, parent)
		button:SetSize(32, 32) -- position will be applied later in layoutButtons()

		local bg = button:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(button)
		bg:SetColorTexture(0, 0, 0, 0.8)
		button.bg = bg

		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(button)
		button.icon = icon

		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetScript("OnClick", function(self)
			if not self.bag or not self.slot then return end
			ClearCursor()
			C_Container.PickupContainerItem(self.bag, self.slot)

			self.icon:SetDesaturated(true)
			self.icon:SetAlpha(0.5)
			self:EnableMouse(false)
		end)
	else
		button:SetParent(parent)
	end

	button:SetSize(32, 32)
	button.itemLink = itemLink
	button.bag = bag
	button.slot = slot
	button.icon:SetTexture(itemTexture)

	if locked then
		button.icon:SetDesaturated(true)
		button.icon:SetAlpha(0.5)
		button:EnableMouse(false)
	else
		button.icon:SetDesaturated(false)
		button.icon:SetAlpha(1)
		button:EnableMouse(true)
	end

	if not addon.variables.isMidnight then
		button:SetScript("OnEnter", function(self)
			if not self.itemLink then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.itemLink)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	else
		button:SetScript("OnEnter", nil)
		button:SetScript("OnLeave", nil)
	end

	return button
end

local function layoutButtons()
	if not EnhanceQoLGemHelper then return end
	local PAD = 4 -- spacing between icons
	local BW, BH = 32, 32 -- button width / height
	local maxW = (EnhanceQoLGemHelper:GetWidth() or 220) - PAD

	local x, y = PAD, -PAD -- start offsets (negative y for TOPLEFT anchoring)

	table.sort(gemButtons, function(a, b)
		if a.itemName and b.itemName then
			return a.itemName < b.itemName
		elseif a.itemName then
			return true
		elseif b.itemName then
			return false
		else
			return false
		end
	end)
	local usedRows = 1
	for _, btn in ipairs(gemButtons) do
		btn:ClearAllPoints()

		-- new row if the next button would overflow
		if x + BW > maxW then
			x = PAD
			y = y - BH - PAD
			usedRows = usedRows + 1
		end

		btn:SetPoint("TOPLEFT", EnhanceQoLGemHelper, "TOPLEFT", x, y)
		btn:Show()

		x = x + BW + PAD
	end

	local neededHeight = usedRows * (BH + PAD) + PAD
	if neededHeight > EnhanceQoLGemHelper:GetHeight() then EnhanceQoLGemHelper:SetHeight(neededHeight) end
end

local function queueLayoutButtons()
	if gemLayoutQueued or not C_Timer then return end
	gemLayoutQueued = true
	C_Timer.After(0, function()
		gemLayoutQueued = false
		layoutButtons()
	end)
end

local function checkGems()
	clearGemButtons()

	local aSockets = {}
	local aSocketColors = {}
	local numSockets = NumSockets()
	for i = 1, numSockets do
		local gemColor = TypeSockets(i)
		aSocketColors[gemColor] = true
		if GEM_TYPE_INFO[gemColor] then
			if type(GEM_TYPE_INFO[gemColor]) == "table" then
				for i in pairs(GEM_TYPE_INFO[gemColor]) do
					aSockets[i] = true
				end
			else
				aSockets[GEM_TYPE_INFO[gemColor]] = true
			end
		end
	end

	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
			if containerInfo then
				local eItem = Item:CreateFromBagAndSlot(bag, slot)
				if eItem and not eItem:IsItemEmpty() then
					eItem:ContinueOnItemLoad(function()
						local itemLink = eItem:GetItemLink()
						if not itemLink then return end
						local itemID = eItem:GetItemID()

						if specialGems[itemID] and not aSocketColors[specialGems[itemID]] then return end

						local itemName, _, _, _, _, _, _, _, _, icon, _, classID, subClassID = C_Item.GetItemInfo(itemID)
						if classID ~= 3 then return end

						if nil == aSockets[subClassID] then return end

						local locked = false
						if C_Item.IsLocked(eItem:GetItemLocation()) then locked = true end

						local btn = createButton(EnhanceQoLGemHelper, icon, itemLink, bag, slot, locked)
						btn.itemName = itemName
						tinsert(gemButtons, btn)
						queueLayoutButtons()
					end)
				end
			end
		end
	end
	layoutButtons()
end

local function eventHandler(self, event, unit, arg1, arg2, ...)
	if event == "ADDON_LOADED" then
		local loadedAddon = unit
		if loadedAddon == "Blizzard_CharacterUI" then hookGemTracker() end
		return
	end

	if not addon.db or not addon.db["enableGemHelper"] then
		if EnhanceQoLGemHelper then EnhanceQoLGemHelper:Hide() end
		local tracker = getGemTracker()
		if tracker then tracker:Hide() end
		return
	end

	if event == "SOCKET_INFO_UPDATE" then
		if ItemSocketingFrame then
			hookSocketingFrame()
			createGemHelper()
			checkGems()
		end
	elseif event == "CURSOR_CHANGED" then
		if ItemSocketingFrame and ItemSocketingFrame:IsShown() and arg2 == 1 then checkGems() end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		markGemTrackerDirty()
	elseif event == "SOCKET_INFO_ACCEPT" then
		markGemTrackerDirty()
	end
end

frame:RegisterEvent("SOCKET_INFO_UPDATE")
frame:RegisterEvent("CURSOR_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("SOCKET_INFO_ACCEPT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", eventHandler)
frame:Hide()

hookGemTracker()
