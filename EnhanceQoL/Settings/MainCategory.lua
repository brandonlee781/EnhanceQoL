local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local SettingsLib = LibStub("LibEQOLSettingsMode-1.0")

local rootCategories = {
	{ id = "UI", label = _G["DISPLAY"] },
	{ id = "GENERAL", label = _G["GENERAL"] },
	{ id = "GAMEPLAY", label = _G["SETTING_GROUP_GAMEPLAY"] },
	{ id = "SOCIAL", label = _G["SOCIAL_LABEL"] },
	{ id = "ECONOMY", label = L["Economy"] or "Economy" },
	{ id = "SOUND", label = _G["SOUND"] },
	{ id = "PROFILES", label = L["Profiles"] },
}
for _, entry in ipairs(rootCategories) do
	addon.SettingsLayout["root" .. entry.id] = addon.functions.SettingsCreateCategory(nil, entry.label, nil, entry.id)
end
