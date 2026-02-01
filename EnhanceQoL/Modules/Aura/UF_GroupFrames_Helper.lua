local parentAddonName = "EnhanceQoL"
local addon = _G[parentAddonName]
if not addon then return end

addon.Aura = addon.Aura or {}
addon.Aura.UF = addon.Aura.UF or {}
local UF = addon.Aura.UF
UF.GroupFramesHelper = UF.GroupFramesHelper or {}
local H = UF.GroupFramesHelper

local UnitSex = UnitSex
local GetNumClasses = GetNumClasses
local GetClassInfo = GetClassInfo
local GetSpecializationInfo = GetSpecializationInfo
local GetNumSpecializations = GetNumSpecializations
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = GetNumSpecializationsForClassID
local C_SpecializationInfo = C_SpecializationInfo
local C_CreatureInfo = C_CreatureInfo

function H.ClampNumber(value, minValue, maxValue, fallback)
	local v = tonumber(value)
	if v == nil then return fallback end
	if minValue ~= nil and v < minValue then v = minValue end
	if maxValue ~= nil and v > maxValue then v = maxValue end
	return v
end

function H.CopySelectionMap(selection)
	local copy = {}
	if type(selection) ~= "table" then return copy end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value ~= nil and (type(value) == "string" or type(value) == "number") then copy[value] = true end
		end
		return copy
	end
	for key, value in pairs(selection) do
		if value and (type(key) == "string" or type(key) == "number") then copy[key] = true end
	end
	return copy
end

H.roleOptions = {
	{ value = "TANK", label = TANK or "Tank" },
	{ value = "HEALER", label = HEALER or "Healer" },
	{ value = "DAMAGER", label = DAMAGER or "DPS" },
}

function H.DefaultRoleSelection()
	local sel = {}
	for _, opt in ipairs(H.roleOptions) do
		sel[opt.value] = true
	end
	return sel
end

local function getClassInfoById(classId)
	if GetClassInfo then return GetClassInfo(classId) end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classId)
		if info then return info.className, info.classFile, info.classID end
	end
	return nil
end

local function forEachSpec(callback)
	local getSpecCount = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
	if not getSpecCount or not GetSpecializationInfoForClassID or not GetNumClasses then return false end
	local sex = UnitSex and UnitSex("player") or nil
	local numClasses = GetNumClasses() or 0
	local found = false
	for classIndex = 1, numClasses do
		local className, classTag, classID = getClassInfoById(classIndex)
		if classID then
			local specCount = getSpecCount(classID) or 0
			for specIndex = 1, specCount do
				local specID, specName = GetSpecializationInfoForClassID(classID, specIndex, sex)
				if specID then
					found = true
					callback(specID, specName, className, classTag, classID)
				end
			end
		end
	end
	return found
end

function H.BuildSpecOptions()
	local opts = {}
	local entries = {}
	local found = forEachSpec(function(specId, specName, className, classTag)
		local label = specName or ("Spec " .. tostring(specId))
		local classLabel = className or classTag
		local classNameText = classLabel or ""
		if classLabel and classLabel ~= "" then label = label .. " (" .. classLabel .. ")" end
		entries[#entries + 1] = {
			value = specId,
			label = label,
			className = classNameText,
			specName = specName or "",
		}
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId, name = GetSpecializationInfo(i)
			if specId and name then entries[#entries + 1] = { value = specId, label = name, className = "", specName = name } end
		end
	end
	table.sort(entries, function(a, b)
		local ac = tostring(a.className or "")
		local bc = tostring(b.className or "")
		if ac ~= bc then return ac < bc end
		return tostring(a.specName or "") < tostring(b.specName or "")
	end)
	local allLabel = ALL or "All"
	opts[#opts + 1] = { value = "__ALL__", label = allLabel }
	for _, entry in ipairs(entries) do
		opts[#opts + 1] = { value = entry.value, label = entry.label }
	end
	return opts
end

function H.DefaultSpecSelection()
	local sel = {}
	local found = forEachSpec(function(specId)
		if specId then sel[specId] = true end
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId = GetSpecializationInfo(i)
			if specId then sel[specId] = true end
		end
	end
	return sel
end

H.auraAnchorOptions = {
	{ value = "TOPLEFT", label = "TOPLEFT", text = "TOPLEFT" },
	{ value = "TOP", label = "TOP", text = "TOP" },
	{ value = "TOPRIGHT", label = "TOPRIGHT", text = "TOPRIGHT" },
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
	{ value = "BOTTOMLEFT", label = "BOTTOMLEFT", text = "BOTTOMLEFT" },
	{ value = "BOTTOM", label = "BOTTOM", text = "BOTTOM" },
	{ value = "BOTTOMRIGHT", label = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
}

H.textAnchorOptions = {
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
}

H.anchorOptions9 = H.auraAnchorOptions

H.textModeOptions = {
	{ value = "PERCENT", label = "Percent", text = "Percent" },
	{ value = "CURMAX", label = "Current/Max", text = "Current/Max" },
	{ value = "CURRENT", label = "Current", text = "Current" },
	{ value = "MAX", label = "Max", text = "Max" },
	{ value = "CURPERCENT", label = "Current / Percent", text = "Current / Percent" },
	{ value = "CURMAXPERCENT", label = "Current/Max Percent", text = "Current/Max Percent" },
	{ value = "MAXPERCENT", label = "Max / Percent", text = "Max / Percent" },
	{ value = "PERCENTMAX", label = "Percent / Max", text = "Percent / Max" },
	{ value = "PERCENTCUR", label = "Percent / Current", text = "Percent / Current" },
	{ value = "PERCENTCURMAX", label = "Percent / Current / Max", text = "Percent / Current / Max" },
	{ value = "LEVELPERCENT", label = "Level / Percent", text = "Level / Percent" },
	{ value = "LEVELPERCENTMAX", label = "Level / Percent / Max", text = "Level / Percent / Max" },
	{ value = "LEVELPERCENTCUR", label = "Level / Percent / Current", text = "Level / Percent / Current" },
	{ value = "LEVELPERCENTCURMAX", label = "Level / Percent / Current / Max", text = "Level / Percent / Current / Max" },
	{ value = "NONE", label = "None", text = "None" },
}

H.healthTextModeOptions = {
	{ value = "PERCENT", label = "Percent", text = "Percent" },
	{ value = "CURMAX", label = "Current/Max", text = "Current/Max" },
	{ value = "CURRENT", label = "Current", text = "Current" },
	{ value = "MAX", label = "Max", text = "Max" },
	{ value = "DEFICIT", label = "Deficit", text = "Deficit" },
	{ value = "CURPERCENT", label = "Current / Percent", text = "Current / Percent" },
	{ value = "CURMAXPERCENT", label = "Current/Max Percent", text = "Current/Max Percent" },
	{ value = "MAXPERCENT", label = "Max / Percent", text = "Max / Percent" },
	{ value = "PERCENTMAX", label = "Percent / Max", text = "Percent / Max" },
	{ value = "PERCENTCUR", label = "Percent / Current", text = "Percent / Current" },
	{ value = "PERCENTCURMAX", label = "Percent / Current / Max", text = "Percent / Current / Max" },
	{ value = "NONE", label = "None", text = "None" },
}

H.delimiterOptions = {
	{ value = " ", label = "Space", text = "Space" },
	{ value = "  ", label = "Double space", text = "Double space" },
	{ value = "/", label = "/", text = "/" },
	{ value = ":", label = ":", text = ":" },
	{ value = "-", label = "-", text = "-" },
	{ value = "|", label = "|", text = "|" },
}

H.outlineOptions = {
	{ value = "NONE", label = "None", text = "None" },
	{ value = "OUTLINE", label = "Outline", text = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick Outline", text = "Thick Outline" },
	{ value = "MONOCHROMEOUTLINE", label = "Monochrome Outline", text = "Monochrome Outline" },
	{ value = "DROPSHADOW", label = "Drop shadow", text = "Drop shadow" },
}

H.auraGrowthXOptions = {
	{ value = "LEFT", label = "Left", text = "Left" },
	{ value = "RIGHT", label = "Right", text = "Right" },
}

H.auraGrowthYOptions = {
	{ value = "UP", label = "Up", text = "Up" },
	{ value = "DOWN", label = "Down", text = "Down" },
}

do
	local upLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or "Up"
	local downLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or "Down"
	local leftLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or "Left"
	local rightLabel = HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or "Right"
	local function growthLabel(first, second) return ("%s %s"):format(first, second) end
	H.auraGrowthOptions = {
		{ value = "UPRIGHT", label = growthLabel(upLabel, rightLabel), text = growthLabel(upLabel, rightLabel) },
		{ value = "UPLEFT", label = growthLabel(upLabel, leftLabel), text = growthLabel(upLabel, leftLabel) },
		{ value = "RIGHTUP", label = growthLabel(rightLabel, upLabel), text = growthLabel(rightLabel, upLabel) },
		{ value = "RIGHTDOWN", label = growthLabel(rightLabel, downLabel), text = growthLabel(rightLabel, downLabel) },
		{ value = "LEFTUP", label = growthLabel(leftLabel, upLabel), text = growthLabel(leftLabel, upLabel) },
		{ value = "LEFTDOWN", label = growthLabel(leftLabel, downLabel), text = growthLabel(leftLabel, downLabel) },
		{ value = "DOWNLEFT", label = growthLabel(downLabel, leftLabel), text = growthLabel(downLabel, leftLabel) },
		{ value = "DOWNRIGHT", label = growthLabel(downLabel, rightLabel), text = growthLabel(downLabel, rightLabel) },
	}
end

function H.TextureOptions(LSM)
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", "Default (Blizzard)")
	add("SOLID", "Solid")
	if not LSM then return list end
	local hash = LSM:HashTable("statusbar") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function H.FontOptions(LSM)
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	if not LSM then return list end
	local hash = LSM:HashTable("font") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function H.EnsureAuraConfig(cfg)
	cfg.auras = cfg.auras or {}
	cfg.auras.buff = cfg.auras.buff or {}
	cfg.auras.debuff = cfg.auras.debuff or {}
	cfg.auras.externals = cfg.auras.externals or {}
	return cfg.auras
end

function H.SyncAurasEnabled(cfg)
	local ac = H.EnsureAuraConfig(cfg)
	local enabled = false
	if ac.buff.enabled then enabled = true end
	if ac.debuff.enabled then enabled = true end
	if ac.externals.enabled then enabled = true end
	ac.enabled = enabled
end
