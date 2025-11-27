local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local ActionBarLabels = addon.ActionBarLabels
local constants = addon.constants or {}

local NormalizeActionBarVisibilityConfig = addon.functions.NormalizeActionBarVisibilityConfig or function() end
local NormalizeUnitFrameVisibilityConfig = addon.functions.NormalizeUnitFrameVisibilityConfig or function() end
local UpdateActionBarMouseover = addon.functions.UpdateActionBarMouseover or function() end
local UpdateUnitFrameMouseover = addon.functions.UpdateUnitFrameMouseover or function() end
local RefreshAllActionBarAnchors = addon.functions.RefreshAllActionBarAnchors or function() end
local GetVisibilityRuleMetadata = addon.functions.GetVisibilityRuleMetadata or function() return {} end

local ACTION_BAR_FRAME_NAMES = constants.ACTION_BAR_FRAME_NAMES or {}
local ACTION_BAR_ANCHOR_ORDER = constants.ACTION_BAR_ANCHOR_ORDER or {}
local ACTION_BAR_ANCHOR_CONFIG = constants.ACTION_BAR_ANCHOR_CONFIG or {}

addon.db = addon.db or {}
addon.db.actionBarHiddenHotkeys = type(addon.db.actionBarHiddenHotkeys) == "table" and addon.db.actionBarHiddenHotkeys or {}

local function collectRuleOptions(kind)
	local options = {}
	for key, data in pairs(GetVisibilityRuleMetadata() or {}) do
		if data.appliesTo and data.appliesTo[kind] then table.insert(options, {
			value = key,
			text = data.label or key,
			order = data.order or 999,
		}) end
	end
	table.sort(options, function(a, b)
		if a.order == b.order then return a.text < b.text end
		return a.order < b.order
	end)
	return options
end

local ACTIONBAR_RULE_OPTIONS = collectRuleOptions("actionbar")
local function buildFontDropdown()
	local map = {
		[addon.variables.defaultFont] = L["actionBarFontDefault"] or "Blizzard Font",
	}
	local LSM = LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("font") or {}) do
			if type(path) == "string" and path ~= "" then map[path] = tostring(name) end
		end
	end
	local list, order = addon.functions.prepareListForDropdown(map)
	list._order = order
	return list
end

local function createActionBarVisibility(category)
	if #ACTIONBAR_RULE_OPTIONS == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["VisibilityHubName"] or ACTIONBARS_LABEL)
	if L["visibilityHubIntro"] then addon.functions.SettingsCreateText(category, L["visibilityHubIntro"]) end
	if L["ActionbarVisibilityExplain"] and _G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"] and _G["HUD_EDIT_MODE_MENU"] then
		addon.functions.SettingsCreateText(category, L["ActionbarVisibilityExplain"]:format(_G["HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS"], _G["HUD_EDIT_MODE_MENU"]))
	end

	local bars, seenVars = {}, {}
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		if info.var and not seenVars[info.var] then
			table.insert(bars, info)
			seenVars[info.var] = true
		end
	end

	table.sort(bars, function(a, b) return (a.text or a.name or "") < (b.text or b.name or "") end)

	for _, info in ipairs(bars) do
		if info.var and info.name then
			addon.functions.SettingsCreateMultiDropdown(category, {
				var = info.var .. "_visibility",
				text = info.text or info.name or info.var,
				options = ACTIONBAR_RULE_OPTIONS,
				isSelectedFunc = function(key)
					local cfg = NormalizeActionBarVisibilityConfig(info.var)
					return cfg and cfg[key] == true
				end,
				setSelectedFunc = function(key, shouldSelect)
					local working = addon.db[info.var]
					if type(working) ~= "table" then working = {} end
					if shouldSelect then
						working[key] = true
					else
						working[key] = nil
					end
					local normalized = NormalizeActionBarVisibilityConfig(info.var, working)
					UpdateActionBarMouseover(info.name, normalized, info.var)
				end,
			})
		end
	end
end

local function createAnchorControls(category)
	if #ACTION_BAR_FRAME_NAMES == 0 then return end

	addon.functions.SettingsCreateHeadline(category, L["actionBarAnchorSectionTitle"] or "Button growth")

	local anchorToggle = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarAnchorEnabled",
		text = L["actionBarAnchorEnable"] or "Modify Action Bar anchor",
		desc = L["actionBarAnchorEnableDesc"],
		func = function(value)
			addon.db["actionBarAnchorEnabled"] = value and true or false
			RefreshAllActionBarAnchors()
		end,
	})

	local anchorOptions = {
		TOPLEFT = L["topLeft"] or "Top Left",
		TOPRIGHT = L["topRight"] or "Top Right",
		BOTTOMLEFT = L["bottomLeft"] or "Bottom Left",
		BOTTOMRIGHT = L["bottomRight"] or "Bottom Right",
	}
	anchorOptions._order = ACTION_BAR_ANCHOR_ORDER

	for index = 1, #ACTION_BAR_FRAME_NAMES do
		local label
		if L["actionBarAnchorDropdown"] then
			label = L["actionBarAnchorDropdown"]:format(index)
		else
			label = string.format("Action Bar %d button anchor", index)
		end

		local dbKey = "actionBarAnchor" .. index
		local defaultKey = "actionBarAnchorDefault" .. index

		addon.functions.SettingsCreateDropdown(category, {
			var = dbKey,
			text = label,
			list = anchorOptions,
			default = addon.db[defaultKey] or ACTION_BAR_ANCHOR_ORDER[1],
			get = function()
				local current = addon.db[dbKey]
				if not current or not ACTION_BAR_ANCHOR_CONFIG[current] then current = addon.db[defaultKey] end
				if not current or not ACTION_BAR_ANCHOR_CONFIG[current] then current = ACTION_BAR_ANCHOR_ORDER[1] end
				return current
			end,
			set = function(key)
				if not ACTION_BAR_ANCHOR_CONFIG[key] then return end
				addon.db[dbKey] = key
				RefreshAllActionBarAnchors()
			end,
			parent = true,
			element = anchorToggle.element,
			parentCheck = function() return anchorToggle.setting and anchorToggle.setting:GetValue() == true end,
		})
	end
end

local function createLabelControls(category)
	addon.functions.SettingsCreateHeadline(category, L["actionBarLabelGroupTitle"] or "Button text")

	local outlineOptions = {
		NONE = L["fontOutlineNone"] or NONE,
		OUTLINE = L["fontOutlineThin"] or "Outline",
		THICKOUTLINE = L["fontOutlineThick"] or "Thick Outline",
		MONOCHROMEOUTLINE = L["fontOutlineMono"] or "Monochrome Outline",
		_order = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE" },
	}

	local hideMacro = addon.functions.SettingsCreateCheckbox(category, {
		var = "hideMacroNames",
		text = L["hideMacroNames"],
		desc = L["hideMacroNamesDesc"],
		func = function(value)
			addon.db["hideMacroNames"] = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
		end,
	})

	local macroOverride = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarMacroFontOverride",
		text = L["actionBarMacroFontOverride"] or "Change macro font",
		func = function(value)
			addon.db.actionBarMacroFontOverride = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hideMacro.element,
		parentCheck = function() return hideMacro.setting and hideMacro.setting:GetValue() ~= true end,
	})

	local function macroParentCheck() return macroOverride.setting and macroOverride.setting:GetValue() == true and hideMacro.setting and hideMacro.setting:GetValue() ~= true end

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarMacroFontFace",
		text = L["actionBarMacroFontLabel"] or "Macro name font",
		listFunc = buildFontDropdown,
		default = addon.variables.defaultFont,
		get = function()
			local current = addon.db.actionBarMacroFontFace or addon.variables.defaultFont
			local list = buildFontDropdown()
			if not list[current] then current = addon.variables.defaultFont end
			return current
		end,
		set = function(key)
			addon.db.actionBarMacroFontFace = key
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
	})

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarMacroFontOutline",
		text = L["actionBarFontOutlineLabel"] or "Font outline",
		list = outlineOptions,
		default = "OUTLINE",
		get = function() return addon.db.actionBarMacroFontOutline or "OUTLINE" end,
		set = function(key)
			addon.db.actionBarMacroFontOutline = key
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
	})

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarMacroFontSize",
		text = L["actionBarMacroFontSize"] or "Macro font size",
		min = 8,
		max = 24,
		step = 1,
		default = 12,
		get = function()
			local value = tonumber(addon.db.actionBarMacroFontSize) or 12
			if value < 8 then value = 8 end
			if value > 24 then value = 24 end
			return value
		end,
		set = function(val)
			val = math.floor(val + 0.5)
			if val < 8 then val = 8 end
			if val > 24 then val = 24 end
			addon.db.actionBarMacroFontSize = val
			if ActionBarLabels and ActionBarLabels.RefreshAllMacroNameVisibility then ActionBarLabels.RefreshAllMacroNameVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = macroOverride.element,
		parentCheck = macroParentCheck,
	})

	local hotkeyOverride = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarHotkeyFontOverride",
		text = L["actionBarHotkeyFontOverride"] or "Change keybind font",
		func = function(value)
			addon.db.actionBarHotkeyFontOverride = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
	})

	local function hotkeyParentCheck() return hotkeyOverride.setting and hotkeyOverride.setting:GetValue() == true end

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarHotkeyFontFace",
		text = L["actionBarHotkeyFontLabel"] or "Keybind font",
		listFunc = buildFontDropdown,
		default = addon.variables.defaultFont,
		get = function()
			local current = addon.db.actionBarHotkeyFontFace or addon.variables.defaultFont
			local list = buildFontDropdown()
			if not list[current] then current = addon.variables.defaultFont end
			return current
		end,
		set = function(key)
			addon.db.actionBarHotkeyFontFace = key
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
	})

	addon.functions.SettingsCreateDropdown(category, {
		var = "actionBarHotkeyFontOutline",
		text = L["actionBarFontOutlineLabel"] or "Font outline",
		list = outlineOptions,
		default = "OUTLINE",
		get = function() return addon.db.actionBarHotkeyFontOutline or "OUTLINE" end,
		set = function(key)
			addon.db.actionBarHotkeyFontOutline = key
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
	})

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarHotkeyFontSize",
		text = L["actionBarHotkeyFontSize"] or "Keybind font size",
		min = 8,
		max = 24,
		step = 1,
		default = 12,
		get = function()
			local value = tonumber(addon.db.actionBarHotkeyFontSize) or 12
			if value < 8 then value = 8 end
			if value > 24 then value = 24 end
			return value
		end,
		set = function(val)
			val = math.floor(val + 0.5)
			if val < 8 then val = 8 end
			if val > 24 then val = 24 end
			addon.db.actionBarHotkeyFontSize = val
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyVisibility then ActionBarLabels.RefreshAllHotkeyVisibility() end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		parent = true,
		element = hotkeyOverride.element,
		parentCheck = hotkeyParentCheck,
	})

	addon.functions.SettingsCreateHeadline(category, L["actionBarKeybindVisibilityHeader"] or "Keybind label visibility")

	local barOptions = {}
	for _, info in ipairs(addon.variables.actionBarNames or {}) do
		if info.name then table.insert(barOptions, { value = info.name, text = info.text or info.name }) end
	end
	table.sort(barOptions, function(a, b) return tostring(a.text) < tostring(b.text) end)

	addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarShortHotkeys",
		text = L["actionBarShortHotkeys"] or "Shorten keybind text",
		desc = L["actionBarShortHotkeysDesc"],
		func = function(value)
			addon.db.actionBarShortHotkeys = value and true or false
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
	})

	local rangeToggle = addon.functions.SettingsCreateCheckbox(category, {
		var = "actionBarFullRangeColoring",
		text = L["fullButtonRangeColoring"],
		desc = L["fullButtonRangeColoringDesc"],
		func = function(value)
			addon.db["actionBarFullRangeColoring"] = value
			if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		end,
	})

	addon.functions.SettingsCreateColorPicker(category, {
		var = "actionBarFullRangeColor",
		text = L["rangeOverlayColor"],
		callback = function()
			if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		end,
		parent = true,
		element = rangeToggle.element,
		parentCheck = function() return rangeToggle.setting and rangeToggle.setting:GetValue() == true end,
	})

	addon.functions.SettingsCreateSlider(category, {
		var = "actionBarFullRangeAlpha",
		text = L["rangeOverlayAlpha"],
		min = 1,
		max = 100,
		step = 1,
		default = 35,
		get = function()
			local val = addon.db["actionBarFullRangeAlpha"] or 0.35
			return math.floor((val * 100) + 0.5)
		end,
		set = function(val)
			addon.db["actionBarFullRangeAlpha"] = (val or 0) / 100
			if ActionBarLabels and ActionBarLabels.RefreshAllRangeOverlays then ActionBarLabels.RefreshAllRangeOverlays() end
		end,
		parent = true,
		element = rangeToggle.element,
		parentCheck = function() return rangeToggle.setting and rangeToggle.setting:GetValue() == true end,
	})

	addon.functions.SettingsCreateMultiDropdown(category, {
		var = "actionBarHiddenHotkeys",
		text = L["actionBarHideHotkeysGroup"] or "Hide keybinds per bar",
		options = barOptions,
		isSelectedFunc = function(key) return addon.db.actionBarHiddenHotkeys and addon.db.actionBarHiddenHotkeys[key] == true end,
		setSelectedFunc = function(key, shouldSelect)
			if type(addon.db.actionBarHiddenHotkeys) ~= "table" then addon.db.actionBarHiddenHotkeys = {} end
			if shouldSelect then
				addon.db.actionBarHiddenHotkeys[key] = true
			else
				addon.db.actionBarHiddenHotkeys[key] = nil
			end
			if ActionBarLabels and ActionBarLabels.RefreshAllHotkeyStyles then ActionBarLabels.RefreshAllHotkeyStyles() end
		end,
		desc = L["actionBarHideHotkeysDesc"],
	})
end

local function createActionBarCategory()
	local category = addon.functions.SettingsCreateCategory(nil, L["visibilityKindActionBars"] or ACTIONBARS_LABEL, nil, "ActionBar")
	addon.SettingsLayout.actionBarCategory = category

	createActionBarVisibility(category)
	createAnchorControls(category)
	createLabelControls(category)
end

local function setFrameRule(info, key, shouldSelect)
	if not info or not info.var then return end
	local working = addon.db[info.var]
	if type(working) ~= "table" then working = {} end

	if key == "ALWAYS_HIDDEN" and shouldSelect then
		working = { ALWAYS_HIDDEN = true }
	elseif shouldSelect then
		working[key] = true
		working.ALWAYS_HIDDEN = nil
	else
		working[key] = nil
	end

	NormalizeUnitFrameVisibilityConfig(info.var, working)
	UpdateUnitFrameMouseover(info.name, info)
end

local function getFrameRuleOptions(info)
	local options = {}
	for key, data in pairs(GetVisibilityRuleMetadata() or {}) do
		local allowed = data.appliesTo and data.appliesTo.frame
		if allowed and data.unitRequirement and data.unitRequirement ~= info.unitToken then allowed = false end
		if allowed then table.insert(options, { value = key, text = data.label or key, order = data.order or 999 }) end
	end
	table.sort(options, function(a, b)
		if a.order == b.order then return a.text < b.text end
		return a.order < b.order
	end)
	return options
end

local function createFrameCategory()
	local category = addon.functions.SettingsCreateCategory(nil, L["visibilityKindFrames"] or UNITFRAME_LABEL, nil, "Frames")
	addon.SettingsLayout.frameVisibilityCategory = category

	addon.functions.SettingsCreateHeadline(category, L["visibilityScenarioGroupTitle"] or (L["ActionBarVisibilityLabel"] or "Visibility"))
	if L["visibilityHubIntro"] then addon.functions.SettingsCreateText(category, L["visibilityHubIntro"]) end
	if L["visibilityFrameExplain"] then addon.functions.SettingsCreateText(category, L["visibilityFrameExplain"]) end
	if L["visibilityFrameExtrasNote"] then addon.functions.SettingsCreateText(category, L["visibilityFrameExtrasNote"]) end

	local frames = {}
	for _, info in ipairs(addon.variables.unitFrameNames or {}) do
		table.insert(frames, info)
	end
	table.sort(frames, function(a, b) return (a.text or a.name or "") < (b.text or b.name or "") end)

	for _, info in ipairs(frames) do
		if info.var and info.name then
			local options = getFrameRuleOptions(info)
			if #options > 0 then
				addon.functions.SettingsCreateMultiDropdown(category, {
					var = info.var .. "_visibility",
					text = info.text or info.name or info.var,
					options = options,
					isSelectedFunc = function(key)
						local cfg = NormalizeUnitFrameVisibilityConfig(info.var)
						return cfg and cfg[key] == true
					end,
					setSelectedFunc = function(key, shouldSelect) setFrameRule(info, key, shouldSelect) end,
				})
			end
		end
	end
end

createActionBarCategory()
createFrameCategory()
