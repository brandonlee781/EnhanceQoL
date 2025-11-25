local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

local cTeleports = addon.functions.SettingsCreateCategory(nil, L["Teleports"], nil, "Teleports")
addon.SettingsLayout.teleportsCategory = cTeleports

local data = {
	{
		var = "teleportFrame",
		text = L["teleportEnabled"],
		desc = L["teleportEnabledDesc"],
		func = function(v)
			addon.db["teleportFrame"] = v
			addon.MythicPlus.functions.toggleFrame()
		end,
	},
	{
		var = "teleportsWorldMapEnabled",
		text = L["teleportsWorldMapEnabled"],
		desc = L["teleportsWorldMapEnabledDesc"],
		func = function(v) addon.db["teleportsWorldMapEnabled"] = v end,
		children = {
			{
				text = "|cffffd700" .. L["teleportsWorldMapHelp"] .. "|r",
				sType = "hint",
			},
		},
	},
	{
		var = "teleportsWorldMapShowSeason",
		text = L["teleportsWorldMapShowSeason"],
		desc = L["teleportsWorldMapShowSeasonDesc"],
		func = function(v) addon.db["teleportsWorldMapShowSeason"] = v end,
	},
	{
		var = "portalHideMissing",
		text = L["portalHideMissing"],
		func = function(v) addon.db["portalHideMissing"] = v end,
	},
}
-- TODO bug in tooltip in midnight beta - remove for now
if not addon.variables.isMidnight then table.insert(data, {
	text = L["portalShowTooltip"],
	var = "portalShowTooltip",
	func = function(value) addon.db["portalShowTooltip"] = value end,
}) end
table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cTeleports, data)

----- REGION END

function addon.functions.initTeleports() end

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
