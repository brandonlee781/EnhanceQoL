local addonName, addon = ...

addon.functions = addon.functions or {}

local function cleanupCombatMeterProfile(profile)
	if type(profile) ~= "table" then return end
	for key in pairs(profile) do
		if type(key) == "string" and key:lower():find("^combatmeter") then profile[key] = nil end
	end

	local layouts = profile.editModeLayouts
	if type(layouts) ~= "table" then return end
	for layoutName, layout in pairs(layouts) do
		if type(layout) == "table" then
			for id in pairs(layout) do
				if type(id) == "string" and id:lower():find("^combatmeter") then layout[id] = nil end
			end
			if not next(layout) then layouts[layoutName] = nil end
		end
	end
end

local function cleanupBuffTrackerProfile(profile)
	if type(profile) ~= "table" then return end
	for key in pairs(profile) do
		if type(key) == "string" and key:lower():find("^bufftracker") then profile[key] = nil end
	end
end

function addon.functions.CleanupCombatMeterSettings()
	local db = _G.EnhanceQoLDB
	if type(db) == "table" and type(db.profiles) == "table" then
		for _, profile in pairs(db.profiles) do
			cleanupCombatMeterProfile(profile)
		end
	elseif addon.db then
		cleanupCombatMeterProfile(addon.db)
	end
end

function addon.functions.CleanupBuffTrackerSettings()
	local db = _G.EnhanceQoLDB
	if type(db) == "table" and type(db.profiles) == "table" then
		for _, profile in pairs(db.profiles) do
			cleanupBuffTrackerProfile(profile)
		end
	elseif addon.db then
		cleanupBuffTrackerProfile(addon.db)
	end
end

function addon.functions.CleanupOldStuff()
	addon.functions.CleanupCombatMeterSettings()
	addon.functions.CleanupBuffTrackerSettings()
end
