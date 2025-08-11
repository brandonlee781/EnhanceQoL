local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_CombatMeter")

local config = addon.db
local barHeight = 20
local specIcons = {}
local groupFrames = {}
local ticker

local metricNames = {
	damagePerFight = L["Damage Per Fight"],
	damageOverall = L["Damage Overall"],
	healingPerFight = L["Healing Per Fight"],
	healingOverall = L["Healing Overall"],
}

local function abbreviateName(name)
	name = name or ""
	name = name:match("^[^-]+") or name
	if #name > 12 then name = name:sub(1, 12) end
	return name
end

local function createGroupFrame(groupConfig)
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(220, barHeight)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame.bars = {}
	frame.metric = groupConfig.type
	frame.groupConfig = groupConfig

	local dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	dragHandle:SetHeight(16)
	dragHandle:SetPoint("TOPLEFT")
	dragHandle:SetPoint("TOPRIGHT")
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:SetScript("OnDragStart", function(self) self:GetParent():StartMoving() end)
	dragHandle:SetScript("OnDragStop", function(self)
		local parent = self:GetParent()
		parent:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = parent:GetPoint()
		groupConfig.point = point
		groupConfig.x = xOfs
		groupConfig.y = yOfs
	end)

	dragHandle.text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	dragHandle.text:SetPoint("CENTER")
	dragHandle.text:SetText(metricNames[groupConfig.type] or "Combat Meter")
	frame.dragHandle = dragHandle

	local function restorePosition()
		frame:ClearAllPoints()
		frame:SetPoint(groupConfig.point or "CENTER", UIParent, groupConfig.point or "CENTER", groupConfig.x or 0, groupConfig.y or 0)
	end
	restorePosition()

	local function getBar(index)
		local bar = frame.bars[index]
		if not bar then
			bar = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")
			bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
			bar:SetHeight(barHeight)
			bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(16 + (index - 1) * barHeight))
			bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(16 + (index - 1) * barHeight))

			bar.icon = bar:CreateTexture(nil, "ARTWORK")
			bar.icon:SetSize(barHeight, barHeight)
			bar.icon:SetPoint("LEFT", bar, "LEFT")

			bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.name:SetPoint("LEFT", bar.icon, "RIGHT", 2, 0)

			bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

			bar.name:SetTextColor(1, 1, 1)
			bar.value:SetTextColor(1, 1, 1)

			local size = config["combatMeterFontSize"]
			bar.name:SetFont(addon.variables.defaultFont, size, "OUTLINE")
			bar.value:SetFont(addon.variables.defaultFont, size, "OUTLINE")

			frame.bars[index] = bar
		end
		return bar
	end

	frame.getBar = getBar

	function frame:setFontSize(size)
		for _, bar in ipairs(self.bars) do
			bar.name:SetFont(addon.variables.defaultFont, size, "OUTLINE")
			bar.value:SetFont(addon.variables.defaultFont, size, "OUTLINE")
		end
	end

	function frame:Update(groupUnits)
		if not (addon.CombatMeter.inCombat or config["combatMeterAlwaysShow"] or self.metric == "damageOverall" or self.metric == "healingOverall") then
			self:Hide()
			return
		end
		self:Show()
		local list = {}
		local maxValue = 0
		if self.metric == "damageOverall" or self.metric == "healingOverall" then
			local stats = addon.CombatMeter.functions.getOverallStats()
			for guid, p in pairs(stats) do
				if groupUnits[guid] then
					local value = self.metric == "damageOverall" and p.dps or p.hps
					table.insert(list, { guid = guid, name = p.name, value = value })
					if value > maxValue then maxValue = value end
				end
			end
		else
			local duration
			if addon.CombatMeter.inCombat then
				duration = GetTime() - addon.CombatMeter.fightStartTime
			else
				duration = addon.CombatMeter.fightDuration
			end
			if duration <= 0 then duration = 1 end
			for guid, data in pairs(addon.CombatMeter.players) do
				if groupUnits[guid] then
					local value
					if self.metric == "damagePerFight" then
						value = data.damage / duration
					else
						value = data.healing / duration
					end
					table.insert(list, { guid = guid, name = data.name, value = value })
					if value > maxValue then maxValue = value end
				end
			end
		end

		if maxValue == 0 then maxValue = 1 end
		table.sort(list, function(a, b) return a.value > b.value end)

		for i, p in ipairs(list) do
			local bar = getBar(i)
			bar:Show()
			bar:SetMinMaxValues(0, maxValue)
			bar:SetValue(p.value)

			local _, _, class, _, _, classFile = GetPlayerInfoByGUID(p.guid)
			local color = RAID_CLASS_COLORS[classFile] or NORMAL_FONT_COLOR
			bar:SetStatusBarColor(color.r, color.g, color.b)

			local unit = groupUnits[p.guid]
			local icon = specIcons[p.guid]
			if not icon and unit then
				local specID = GetInspectSpecialization(unit)
				if specID and specID > 0 then
					icon = select(4, GetSpecializationInfoByID(specID))
					specIcons[p.guid] = icon
				end
			end
			bar.icon:SetTexture(icon)

			bar.name:SetText(abbreviateName(p.name))
			bar.value:SetText(BreakUpLargeNumbers(math.floor(p.value)))
		end

		for i = #list + 1, #self.bars do
			self.bars[i]:Hide()
		end

		self:SetHeight(16 + #list * barHeight)
	end

	return frame
end

local function setFontSize(size)
	for _, frame in ipairs(groupFrames) do
		frame:setFontSize(size)
	end
end
addon.CombatMeter.functions.setFontSize = setFontSize

local function buildGroupUnits()
	local groupUnits = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnits[guid] = unit end
		end
	else
		for i = 1, GetNumGroupMembers() do
			local unit = "party" .. i
			local guid = UnitGUID(unit)
			if guid then groupUnits[guid] = unit end
		end
		local playerGUID = UnitGUID("player")
		if playerGUID then groupUnits[playerGUID] = "player" end
	end
	return groupUnits
end

local function UpdateAllFrames()
	if #groupFrames == 0 then return end
	local groupUnits = buildGroupUnits()
	for _, frame in ipairs(groupFrames) do
		frame:Update(groupUnits)
	end
end
addon.CombatMeter.functions.UpdateBars = UpdateAllFrames

local controller = CreateFrame("Frame")
addon.CombatMeter.uiFrame = controller

controller:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
		if ticker then ticker:Cancel() end
		ticker = C_Timer.NewTicker(config["combatMeterUpdateRate"], UpdateAllFrames)
		addon.CombatMeter.ticker = ticker
		C_Timer.After(0, UpdateAllFrames)
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
			addon.CombatMeter.ticker = nil
		end
		C_Timer.After(0, UpdateAllFrames)
	end
end)

function addon.CombatMeter.functions.setUpdateRate(rate)
	if ticker then
		ticker:Cancel()
		ticker = C_Timer.NewTicker(rate, UpdateAllFrames)
		addon.CombatMeter.ticker = ticker
	end
end

local function rebuildGroups()
	for _, frame in ipairs(groupFrames) do
		frame:Hide()
	end
	wipe(groupFrames)
	for _, cfg in ipairs(config["combatMeterGroups"]) do
		local frame = createGroupFrame(cfg)
		table.insert(groupFrames, frame)
	end
	UpdateAllFrames()
end
addon.CombatMeter.functions.rebuildGroups = rebuildGroups

rebuildGroups()
addon.CombatMeter.functions.toggle(addon.db["combatMeterEnabled"])
