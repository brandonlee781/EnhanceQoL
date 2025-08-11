local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
-- luacheck: globals GENERAL SlashCmdList
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.CombatMeter = {}
addon.CombatMeter.functions = {}
addon.LCombatMeter = {}

local AceGUI = addon.AceGUI
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_CombatMeter")

addon.variables.statusTable.groups["combatmeter"] = true
addon.functions.addToTree(nil, {
	value = "combatmeter",
	text = L["Combat Meter"],
	children = {
		{ value = "general", text = GENERAL },
	},
})

local function addGeneralFrame(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	container:AddChild(wrapper)

	local groupCore = addon.functions.createContainer("InlineGroup", "List")
	wrapper:AddChild(groupCore)

	local cbEnabled = addon.functions.createCheckboxAce(L["Enabled"], addon.db["combatMeterEnabled"], function(self, _, value)
		addon.db["combatMeterEnabled"] = value
		addon.CombatMeter.functions.toggle(value)
	end)
	groupCore:AddChild(cbEnabled)

	local cbAlwaysShow = addon.functions.createCheckboxAce(L["Always Show"], addon.db["combatMeterAlwaysShow"], function(self, _, value)
		addon.db["combatMeterAlwaysShow"] = value
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end)
	groupCore:AddChild(cbAlwaysShow)

	local sliderRate = addon.functions.createSliderAce(L["Update Rate"] .. ": " .. addon.db["combatMeterUpdateRate"], addon.db["combatMeterUpdateRate"], 0.05, 1, 0.05, function(self, _, val)
		addon.db["combatMeterUpdateRate"] = val
		addon.CombatMeter.functions.setUpdateRate(val)
		self:SetLabel(L["Update Rate"] .. ": " .. string.format("%.2f", val))
	end)
	groupCore:AddChild(sliderRate)

	local sliderFont = addon.functions.createSliderAce(L["Font Size"] .. ": " .. addon.db["combatMeterFontSize"], addon.db["combatMeterFontSize"], 8, 32, 1, function(self, _, val)
		addon.db["combatMeterFontSize"] = val
		if addon.CombatMeter.functions.setFontSize then addon.CombatMeter.functions.setFontSize(val) end
		self:SetLabel(L["Font Size"] .. ": " .. val)
	end)
	groupCore:AddChild(sliderFont)

	local btnReset = addon.functions.createButtonAce(L["Reset"], nil, function()
		if SlashCmdList and SlashCmdList["EQOLCM"] then SlashCmdList["EQOLCM"]("reset") end
		if addon.CombatMeter.functions.UpdateBars then addon.CombatMeter.functions.UpdateBars() end
	end)
	groupCore:AddChild(btnReset)
end

function addon.CombatMeter.functions.treeCallback(container, group)
	container:ReleaseChildren()
	if group == "combatmeter\001general" then addGeneralFrame(container) end
end

addon.functions.InitDBValue("combatMeterEnabled", false)
addon.functions.InitDBValue("combatMeterHistory", {})
addon.functions.InitDBValue("combatMeterAlwaysShow", false)
addon.functions.InitDBValue("combatMeterUpdateRate", 0.2)
addon.functions.InitDBValue("combatMeterFramePoint", "CENTER")
addon.functions.InitDBValue("combatMeterFrameX", 0)
addon.functions.InitDBValue("combatMeterFrameY", 0)
addon.functions.InitDBValue("combatMeterFontSize", 12)
