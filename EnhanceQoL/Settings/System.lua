local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local getCVarOptionState = addon.functions.GetCVarOptionState or function() return false end
local setCVarOptionState = addon.functions.SetCVarOptionState or function() end

local function applyParentSection(entries, section)
	for _, entry in ipairs(entries or {}) do
		entry.parentSection = section
		if entry.children then applyParentSection(entry.children, section) end
	end
end

local cGeneral = addon.SettingsLayout.rootGENERAL
addon.SettingsLayout.systemCategory = cGeneral

local movementExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["cvarCategoryMovementInput"] or "Movement & Input",
	expanded = false,
	colorizeTitle = false,
})

local movementData = {
	{
		var = "autoDismount",
		text = L["autoDismount"],
		get = function() return getCVarOptionState("autoDismount") end,
		func = function(value) setCVarOptionState("autoDismount", value) end,
		default = false,
	},
	{
		var = "autoDismountFlying",
		text = L["autoDismountFlying"],
		get = function() return getCVarOptionState("autoDismountFlying") end,
		func = function(value) setCVarOptionState("autoDismountFlying", value) end,
		default = false,
	},
}

table.sort(movementData, function(a, b) return a.text < b.text end)
applyParentSection(movementData, movementExpandable)
addon.functions.SettingsCreateCheckboxes(cGeneral, movementData)

local systemExpandable = addon.functions.SettingsCreateExpandableSection(cGeneral, {
	name = L["System"] or _G.SYSTEM or "System",
	expanded = false,
	colorizeTitle = false,
})

local systemData = {
	{
		var = "cvarPersistenceEnabled",
		text = L["cvarPersistence"],
		desc = L["cvarPersistenceDesc"],
		func = function(key)
			addon.db["cvarPersistenceEnabled"] = key
			if addon.functions.initializePersistentCVars then addon.functions.initializePersistentCVars() end
		end,
		default = false,
	},
	{
		var = "scriptErrors",
		text = L["scriptErrors"],
		get = function() return getCVarOptionState("scriptErrors") end,
		func = function(value) setCVarOptionState("scriptErrors", value) end,
		default = false,
	},
	{
		var = "showTutorials",
		text = L["showTutorials"],
		get = function() return getCVarOptionState("showTutorials") end,
		func = function(value) setCVarOptionState("showTutorials", value) end,
		default = false,
	},
	{
		var = "UberTooltips",
		text = L["UberTooltips"],
		get = function() return getCVarOptionState("UberTooltips") end,
		func = function(value) setCVarOptionState("UberTooltips", value) end,
		default = false,
	},
}

applyParentSection(systemData, systemExpandable)
addon.functions.SettingsCreateCheckboxes(cGeneral, systemData)

----- REGION END

function addon.functions.initSystem() end

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
