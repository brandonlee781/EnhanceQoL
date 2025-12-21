local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_LayoutTools")
local db = addon.db["eqolLayoutTools"]

local function registerDefaults()
	addon.LayoutTools.functions.RegisterGroup("blizzard", L["Blizzard"] or "Blizzard", { expanded = true, order = 10 })
	addon.LayoutTools.functions.RegisterFrame({
		id = "SettingsPanel",
		label = SETTINGS or "Settings",
		group = "blizzard",
		names = { "SettingsPanel" },
		addon = "Blizzard_Settings",
		defaultEnabled = true,
	})
end

local function buildSettings()
	local categoryLabel = L["Layout Tools"] or L["Move"] or "Layout Tools"
	local cLayout = addon.functions.SettingsCreateCategory(nil, categoryLabel, nil, "LayoutTools")
	addon.SettingsLayout.layoutToolsCategory = cLayout

	local sectionGeneral = addon.functions.SettingsCreateExpandableSection(cLayout, {
		name = L["Global Settings"] or "General",
		expanded = true,
	})

	addon.functions.SettingsCreateCheckbox(cLayout, {
		var = "layoutToolsEnabled",
		text = L["Global Move Enabled"] or "Enable moving",
		default = true,
		get = function() return db.enabled end,
		set = function(value)
			db.enabled = value
			addon.LayoutTools.functions.ApplyAll()
		end,
		parentSection = sectionGeneral,
	})

	addon.functions.SettingsCreateCheckbox(cLayout, {
		var = "layoutToolsRequireModifier",
		text = L["Require Modifier For Move"] or "Require modifier to move",
		default = true,
		get = function() return db.requireModifier end,
		set = function(value) db.requireModifier = value end,
		parentSection = sectionGeneral,
	})

	addon.functions.SettingsCreateDropdown(cLayout, {
		var = "layoutToolsModifier",
		text = L["Move Modifier"] or (L["Scale Modifier"] or "Modifier"),
		list = { SHIFT = "SHIFT", CTRL = "CTRL", ALT = "ALT" },
		order = { "SHIFT", "CTRL", "ALT" },
		default = "SHIFT",
		get = function() return db.modifier or "SHIFT" end,
		set = function(value) db.modifier = value end,
		parentCheck = function() return db.requireModifier end,
		parentSection = sectionGeneral,
	})

	for _, group in ipairs(addon.LayoutTools.functions.GetGroups()) do
		local section = addon.functions.SettingsCreateExpandableSection(cLayout, {
			name = group.label or group.id,
			expanded = group.expanded,
		})

		for _, entry in ipairs(addon.LayoutTools.functions.GetEntriesForGroup(group.id)) do
			addon.functions.SettingsCreateCheckbox(cLayout, {
				var = entry.settingKey or entry.id,
				text = entry.label or entry.id,
				default = entry.defaultEnabled ~= false,
				get = function() return addon.LayoutTools.functions.IsFrameEnabled(entry) end,
				set = function(value)
					addon.LayoutTools.functions.SetFrameEnabled(entry, value)
					addon.LayoutTools.functions.RefreshEntry(entry)
				end,
				parentSection = section,
				parentCheck = function() return db.enabled end,
			})
		end
	end
end

registerDefaults()
buildSettings()

function addon.LayoutTools.functions.treeCallback(container, group)
	if addon.SettingsLayout.layoutToolsCategory then
		Settings.OpenToCategory(addon.SettingsLayout.layoutToolsCategory:GetID())
	end
end
