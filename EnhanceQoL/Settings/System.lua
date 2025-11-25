local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local function setCVarValue(...)
	if addon.functions and addon.functions.setCVarValue then return addon.functions.setCVarValue(...) end
end

local cSystem = addon.functions.SettingsCreateCategory(nil, L["System"], nil, "System")
addon.SettingsLayout.systemCategory = cSystem

local data = {
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
}

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cSystem, data)

local categories = {}
for key, optionData in pairs(addon.variables.cvarOptions) do
	local categoryKey = optionData.category or "cvarCategoryMisc"
	if not categories[categoryKey] then categories[categoryKey] = {} end
	table.insert(categories[categoryKey], {
		var = key,
		text = optionData.description,
		func = function(value)
			local newValue
			if value then
				newValue = optionData.trueValue
			else
				newValue = optionData.falseValue
			end

			if optionData.persistent then
				addon.db.cvarOverrides = addon.db.cvarOverrides or {}
				addon.db.cvarOverrides[key] = newValue
			end
			setCVarValue(key, newValue)
		end,
		get = function()
			local v = C_CVar.GetCVar(key)
			if v == optionData.trueValue then
				return true
			else
				return false
			end
		end,
	})
end

for i, v in pairs(categories) do
	addon.functions.SettingsCreateHeadline(cSystem, L["" .. i] or i)
	addon.functions.SettingsCreateCheckboxes(cSystem, v)
end

-- table.sort(data, function(a, b) return a.text < b.text end)
-- addon.functions.SettingsCreateCheckboxes(cSystem, data)

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
