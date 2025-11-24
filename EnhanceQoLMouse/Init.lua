local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Mouse = {}
addon.Mouse.functions = {}
addon.Mouse.variables = {}
addon.LMouse = {} -- Locales for aura

addon.functions.InitDBValue("mouseRingEnabled", false)
addon.functions.InitDBValue("mouseTrailEnabled", false)
addon.functions.InitDBValue("mouseTrailDensity", 1)
addon.functions.InitDBValue("mouseRingSize", 70)
addon.functions.InitDBValue("mouseRingHideDot", false)
-- New options
addon.functions.InitDBValue("mouseRingOnlyInCombat", false)
addon.functions.InitDBValue("mouseTrailOnlyInCombat", false)
addon.functions.InitDBValue("mouseRingUseClassColor", false)
addon.functions.InitDBValue("mouseTrailUseClassColor", false)
