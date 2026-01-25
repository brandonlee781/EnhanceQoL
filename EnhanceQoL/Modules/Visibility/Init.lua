local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Visibility = addon.Visibility or {}
addon.Visibility.functions = addon.Visibility.functions or {}

function addon.Visibility.functions.InitDB()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue
	local helper = addon.Visibility and addon.Visibility.helper
	local defaultRoot = helper and helper.CreateRoot and helper.CreateRoot()
	init("visibilityConfigs", defaultRoot or {})
	init("visibilityEditorPoint", "CENTER")
	init("visibilityEditorX", 0)
	init("visibilityEditorY", 0)
end
