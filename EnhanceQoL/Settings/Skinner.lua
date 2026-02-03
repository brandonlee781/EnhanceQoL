local addonName, addon = ...

local function buildSkinnerSettings()
	if addon.Skinner and addon.Skinner.functions and addon.Skinner.functions.InitSettings then
		addon.Skinner.functions.InitSettings()
	end
end

if addon.Mover and addon.Mover.variables and addon.Mover.variables.settingsBuilt then
	buildSkinnerSettings()
elseif addon.Mover and addon.Mover.functions and addon.Mover.functions.InitSettings then
	hooksecurefunc(addon.Mover.functions, "InitSettings", buildSkinnerSettings)
else
	buildSkinnerSettings()
end
