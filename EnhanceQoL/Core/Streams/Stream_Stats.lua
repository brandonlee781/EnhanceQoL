-- luacheck: globals EnhanceQoL GAMEMENU_OPTIONS STAT_HASTE STAT_MASTERY STAT_VERSATILITY STAT_CRITICAL_STRIKE CR_HASTE_MELEE CR_MASTERY CR_VERSATILITY_DAMAGE_DONE CR_VERSATILITY_DAMAGE_TAKEN CR_CRIT_MELEE
local addonName, addon = ...
local L = addon.L

local AceGUI = addon.AceGUI
local db
local stream

local idx

local function ensureDB()
	addon.db.datapanel = addon.db.datapanel or {}
	addon.db.datapanel.stats = addon.db.datapanel.stats or {}
	db = addon.db.datapanel.stats
	db.fontSize = db.fontSize or 14
	db.vertical = db.vertical or false
	db.haste = db.haste or { enabled = true, rating = false }
	db.mastery = db.mastery or { enabled = true, rating = false }
	db.versatility = db.versatility or { enabled = true, rating = false }
	db.crit = db.crit or { enabled = true, rating = false }
	db.haste.color = db.haste.color or { r = 1, g = 1, b = 1 }
	db.mastery.color = db.mastery.color or { r = 1, g = 1, b = 1 }
	db.versatility.color = db.versatility.color or { r = 1, g = 1, b = 1 }
	db.crit.color = db.crit.color or { r = 1, g = 1, b = 1 }
end

local function RestorePosition(frame)
	if db.point and db.x and db.y then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	end
end

local aceWindow
local function addStatOptions(frame, key, label)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(label)
	group:SetFullWidth(true)
	group:SetLayout("List")

	local show = AceGUI:Create("CheckBox")
	show:SetLabel("Show")
	show:SetValue(db[key].enabled)
	show:SetCallback("OnValueChanged", function(_, _, val)
		db[key].enabled = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	group:AddChild(show)

	local rating = AceGUI:Create("CheckBox")
	rating:SetLabel("Use rating")
	rating:SetValue(db[key].rating)
	rating:SetCallback("OnValueChanged", function(_, _, val)
		db[key].rating = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	group:AddChild(rating)

	local color = AceGUI:Create("ColorPicker")
	color:SetLabel("Color")
	local c = db[key].color
	color:SetColor(c.r, c.g, c.b)
	color:SetCallback("OnValueChanged", function(_, _, r, g, b)
		db[key].color = { r = r, g = g, b = b }
		addon.DataHub:RequestUpdate(stream)
	end)
	group:AddChild(color)

	frame:AddChild(group)
end

local function createAceWindow()
	if aceWindow then
		aceWindow:Show()
		return
	end
	ensureDB()
	local frame = AceGUI:Create("Window")
	aceWindow = frame.frame
	frame:SetTitle(GAMEMENU_OPTIONS)
	frame:SetWidth(330)
	frame:SetHeight(500)
	frame:SetLayout("List")

	frame.frame:SetScript("OnShow", function(self) RestorePosition(self) end)
	frame.frame:SetScript("OnHide", function(self)
		local point, _, _, xOfs, yOfs = self:GetPoint()
		db.point = point
		db.x = xOfs
		db.y = yOfs
	end)

	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	frame:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetLabel("Font size")
	fontSize:SetSliderValues(8, 32, 1)
	fontSize:SetValue(db.fontSize)
	fontSize:SetCallback("OnValueChanged", function(_, _, val)
		db.fontSize = val
		addon.DataHub:RequestUpdate(stream)
	end)
	groupCore:AddChild(fontSize)

	local vertical = AceGUI:Create("CheckBox")
	vertical:SetLabel("Display vertically")
	vertical:SetValue(db.vertical)
	vertical:SetCallback("OnValueChanged", function(_, _, val)
		db.vertical = val and true or false
		addon.DataHub:RequestUpdate(stream)
	end)
	groupCore:AddChild(vertical)

	addStatOptions(groupCore, "haste", STAT_HASTE or "Haste")
	addStatOptions(groupCore, "mastery", STAT_MASTERY or "Mastery")
	addStatOptions(groupCore, "versatility", STAT_VERSATILITY or "Versatility")
	addStatOptions(groupCore, "crit", STAT_CRITICAL_STRIKE or "Crit")

	frame.frame:Show()
	scroll:DoLayout()
end

local STR = LE_UNIT_STAT_STRENGTH
local AGI = LE_UNIT_STAT_AGILITY
local INT = LE_UNIT_STAT_INTELLECT

local NAMES = {
	[STR] = ITEM_MOD_STRENGTH_SHORT, -- "Strength" (lokalisiert)
	[AGI] = ITEM_MOD_AGILITY_SHORT, -- "Agility"
	[INT] = ITEM_MOD_INTELLECT_SHORT, -- "Intellect"
}

local function GetPlayerPrimaryStatIndex()
	local spec = C_SpecializationInfo.GetSpecialization()
	if spec then
		-- 7. Rückgabewert ist der Primary-Stat (Index, passt direkt in UnitStat)
		local _, _, _, _, _, _, primaryStat = C_SpecializationInfo.GetSpecializationInfo(spec)
		if primaryStat == STR or primaryStat == AGI or primaryStat == INT then return primaryStat end
	end
	-- Fallback: nimm den höchsten von STR/AGI/INT auf dem Spieler
	local _, sSTR = UnitStat("player", STR)
	local _, sAGI = UnitStat("player", AGI)
	local _, sINT = UnitStat("player", INT)
	if sSTR >= sAGI and sSTR >= sINT then
		return STR
	elseif sAGI >= sINT then
		return AGI
	else
		return INT
	end
end

local function GetPlayerPrimaryStat()
	if not idx then idx = GetPlayerPrimaryStatIndex() end
	local base, effective = UnitStat("player", idx) -- effective enthält Buffs
	return (effective or base), idx, (NAMES[idx] or "Primary")
end

local function formatStat(label, rating, percent)
	if rating then
		return ("%s: %d"):format(label, rating)
	else
		return ("%s: %.2f%%"):format(label, percent)
	end
end

local function colorize(text, color)
	if color and color.r and color.g and color.b then return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text) end
	return text
end

local function checkStats(stream)
	ensureDB()
	local texts = {}
	local sep = db.vertical and "\n" or " "
	local size = db.fontSize or 14
	stream.snapshot.fontSize = size
	stream.snapshot.tooltip = L["Right-Click for options"]

	local primaryValue, primaryId, primaryName = GetPlayerPrimaryStat()
	texts[#texts + 1] = ("%s: %d"):format(primaryName, primaryValue)

	if db.haste.enabled then
		local text
		if db.haste.rating then
			text = formatStat(STAT_HASTE or "Haste", GetCombatRating(CR_HASTE_MELEE), nil)
		else
			text = formatStat(STAT_HASTE or "Haste", nil, GetHaste())
		end
		texts[#texts + 1] = colorize(text, db.haste.color)
	end

	if db.mastery.enabled then
		local text
		if db.mastery.rating then
			text = formatStat(STAT_MASTERY or "Mastery", GetCombatRating(CR_MASTERY), nil)
		else
			text = formatStat(STAT_MASTERY or "Mastery", nil, GetMastery())
		end
		texts[#texts + 1] = colorize(text, db.mastery.color)
	end

	if db.versatility.enabled then
		local text
		if db.versatility.rating then
			text = formatStat(STAT_VERSATILITY or "Vers", GetCombatRating(CR_VERSATILITY_DAMAGE_DONE), nil)
		else
			local dmg = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
			local red = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)
			text = ("%s %.2f%%/%.2f%%"):format(STAT_VERSATILITY or "Vers", dmg, red)
		end
		texts[#texts + 1] = colorize(text, db.versatility.color)
	end

	if db.crit.enabled then
		local text
		if db.crit.rating then
			text = formatStat(STAT_CRITICAL_STRIKE or "Crit", GetCombatRating(CR_CRIT_MELEE), nil)
		else
			text = formatStat(STAT_CRITICAL_STRIKE or "Crit", nil, GetCritChance())
		end
		texts[#texts + 1] = colorize(text, db.crit.color)
	end

	stream.snapshot.text = table.concat(texts, sep)
end

local provider = {
	id = "stats",
	version = 1,
	title = "Stats",
	update = checkStats,
	events = {
		UNIT_SPELL_HASTE = function(stream, _, unit)
			if unit == "player" then addon.DataHub:RequestUpdate(stream) end
		end,
		UNIT_ATTACK_SPEED = function(stream, _, unit)
			if unit == "player" then addon.DataHub:RequestUpdate(stream) end
		end,
		UNIT_STATS = function(stream, _, unit)
			if unit == "player" then addon.DataHub:RequestUpdate(stream) end
		end,
		UNIT_AURA = function(stream, _, unit)
			if unit == "player" then addon.DataHub:RequestUpdate(stream) end
		end,
		COMBAT_RATING_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		MASTERY_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_EQUIPMENT_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_TALENT_UPDATE = function(stream) addon.DataHub:RequestUpdate(stream) end,
		ACTIVE_TALENT_GROUP_CHANGED = function(stream) addon.DataHub:RequestUpdate(stream) end,
		UPDATE_SHAPESHIFT_FORM = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_ENTERING_WORLD = function(stream) addon.DataHub:RequestUpdate(stream) end,
		PLAYER_LOGIN = function(stream)
			C_Timer.After(1, function()
				idx = GetPlayerPrimaryStatIndex()
				addon.DataHub:RequestUpdate(stream)
			end)
		end,
		ACTIVE_PLAYER_SPECIALIZATION_CHANGED = function(stream)
			C_Timer.After(1, function()
				idx = GetPlayerPrimaryStatIndex()
				addon.DataHub:RequestUpdate(stream)
			end)
		end,
	},
	OnClick = function(_, btn)
		if btn == "RightButton" then createAceWindow() end
	end,
}

stream = EnhanceQoL.DataHub.RegisterStream(provider)

return provider
