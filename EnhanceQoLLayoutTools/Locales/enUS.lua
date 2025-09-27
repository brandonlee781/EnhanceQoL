local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end
local L = addon.LLayoutTools

L["Move"] = "Layout Tools"

L["uiScalerPlayerSpellsFrameMove"] = "Enable to move " .. PLAYERSPELLS_BUTTON
L["uiScalerPlayerSpellsFrameEnabled"] = "Enable to Scale the " .. PLAYERSPELLS_BUTTON

-- Slider label for scaling the Player Spells (Talents) frame
L["talentFrameUIScale"] = "Talent/Spells frame scale"


-- Deprecated/unused (kept only if reintroduced)
