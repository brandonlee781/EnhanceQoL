local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.SharedMedia = addon.SharedMedia or {}
addon.SharedMedia.functions = addon.SharedMedia.functions or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_SharedMedia")
local LSM = LibStub("LibSharedMedia-3.0")

-- No explicit tree node; content is shown directly under "Media & Sound" in Core

addon.functions.InitDBValue("sharedMediaSounds", {})

local function RegisterEnabledSounds()
	for _, sound in ipairs(addon.SharedMedia.sounds or {}) do
		if addon.db.sharedMediaSounds[sound.key] then LSM:Register("sound", sound.label, sound.path) end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
	RegisterEnabledSounds()
	self:UnregisterEvent("PLAYER_LOGIN")
end)

function addon.SharedMedia.functions.UpdateSound(key, enabled)
	addon.db.sharedMediaSounds[key] = enabled
	local sound
	for _, s in ipairs(addon.SharedMedia.sounds or {}) do
		if s.key == key then
			sound = s
			break
		end
	end
	if not sound then return end
	if enabled then
		LSM:Register("sound", sound.label, sound.path)
	else
		if LSM.Unregister then
			local ok = pcall(LSM.Unregister, LSM, "sound", sound.label)
			if not ok then addon.variables.requireReload = true end
		else
			addon.variables.requireReload = true
		end
	end
end

-- Statusbars
LSM:Register("statusbar", "EQOL: Holy", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Holy.tga")
LSM:Register("statusbar", "EQOL: Thunder", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Thunder.tga")
LSM:Register("statusbar", "EQOL: Astral", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Astral.tga")
LSM:Register("statusbar", "EQOL: Rage", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Rage.tga")
LSM:Register("statusbar", "EQOL: Absorb", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Absorb.tga")
