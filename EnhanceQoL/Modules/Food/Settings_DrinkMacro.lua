local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")
local LCore = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local wipe = wipe

local function isCheckboxEnabled(var)
	local entry = addon.SettingsLayout.elements and addon.SettingsLayout.elements[var]
	return entry and entry.setting and entry.setting:GetValue() == true
end

local function refreshDrinks()
	if addon.functions.updateAllowedDrinks then addon.functions.updateAllowedDrinks() end
	if addon.functions.updateAvailableDrinks then addon.functions.updateAvailableDrinks(false) end
end

local function refreshHealthMacro()
	if addon.Health and addon.Health.functions and addon.Health.functions.syncEventRegistration then addon.Health.functions.syncEventRegistration() end
	if addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then addon.Health.functions.updateHealthMacro(false) end
end

local function buildDrinkMacroSettings()
	local cDrink = addon.SettingsLayout.rootGAMEPLAY
	if not cDrink then return end

	local convenienceSection = addon.SettingsLayout.gameplayConvenienceSection
	if not convenienceSection then
		convenienceSection = addon.functions.SettingsCreateExpandableSection(cDrink, {
			name = (LCore and LCore["MacrosAndConsumables"]) or "Macros & Consumables",
			expanded = false,
			colorizeTitle = false,
		})
		addon.SettingsLayout.gameplayConvenienceSection = convenienceSection
	end

	addon.SettingsLayout.drinkMacroCategory = cDrink

	addon.functions.SettingsCreateHeadline(cDrink, L["Drinks & Food"], { parentSection = convenienceSection })

	addon.functions.SettingsCreateHeadline(cDrink, L["Drink Macro"], { parentSection = convenienceSection })

	local drinkData = {
		{
			var = "drinkMacroEnabled",
			text = L["Enable Drink Macro"],
			func = function(value)
				addon.db.drinkMacroEnabled = value and true or false
				refreshDrinks()
			end,
			default = false,
			children = {
				{
					var = "preferMageFood",
					text = L["Prefer mage food"],
					func = function(value)
						addon.db.preferMageFood = value and true or false
						refreshDrinks()
					end,
					parentCheck = function() return isCheckboxEnabled("drinkMacroEnabled") end,
					parent = true,
					default = true,
					type = Settings.VarType.Boolean,
					sType = "checkbox",
				},
				{
					var = "allowRecuperate",
					text = L["allowRecuperate"],
					func = function(value)
						addon.db.allowRecuperate = value and true or false
						refreshDrinks()
					end,
					desc = L["allowRecuperateDesc"],
					parentCheck = function() return isCheckboxEnabled("drinkMacroEnabled") end,
					parent = true,
					default = true,
					type = Settings.VarType.Boolean,
					sType = "checkbox",
				},
				{
					var = "useManaPotionInCombat",
					text = L["useManaPotionInCombat"],
					func = function(value)
						addon.db.useManaPotionInCombat = value and true or false
						if addon.functions.updateAvailableDrinks then addon.functions.updateAvailableDrinks(false) end
					end,
					desc = L["useManaPotionInCombatDesc"],
					parentCheck = function() return isCheckboxEnabled("drinkMacroEnabled") end,
					parent = true,
					default = false,
					type = Settings.VarType.Boolean,
					sType = "checkbox",
				},
				{
					var = "minManaFoodValue",
					text = L["Minimum mana restore for food"],
					get = function() return addon.db.minManaFoodValue or 50 end,
					set = function(value)
						value = tonumber(value) or 50
						if value < 0 then value = 0 end
						if value > 100 then value = 100 end
						addon.db.minManaFoodValue = value
						refreshDrinks()
					end,
					min = 0,
					max = 100,
					step = 1,
					parentCheck = function() return isCheckboxEnabled("drinkMacroEnabled") end,
					parent = true,
					default = 50,
					sType = "slider",
				},
			},
		},
	}
	local function applyParentSection(entry)
		entry.parentSection = convenienceSection
		if entry.children then
			for _, child in pairs(entry.children) do
				applyParentSection(child)
			end
		end
	end
	for _, entry in ipairs(drinkData) do
		applyParentSection(entry)
	end
	addon.functions.SettingsCreateCheckboxes(cDrink, drinkData)

	addon.functions.SettingsCreateHeadline(cDrink, L["MageFoodReminderHeadline"] or "Mage food reminder for Healer", { parentSection = convenienceSection })
	addon.functions.SettingsCreateCheckbox(cDrink, {
		var = "mageFoodReminder",
		text = L["mageFoodReminder"],
		desc = L["mageFoodReminderDesc2"],
		func = function(value)
			addon.db.mageFoodReminder = value and true or false
			if addon.Drinks and addon.Drinks.functions and addon.Drinks.functions.updateRole then addon.Drinks.functions.updateRole() end
		end,
		default = false,
		parentSection = convenienceSection,
	})
	addon.functions.SettingsCreateText(cDrink, L["mageFoodReminderEditModeHint"] or "Configure details in Edit Mode.", { parentSection = convenienceSection })

	addon.functions.SettingsCreateHeadline(cDrink, L["Health Macro"], { parentSection = convenienceSection })

	local function defaultPriority() return { "stone", "potion", addon.db.healthUseCombatPotions and "combatpotion" or "none", "none" } end

	local function ensureHealthPriority()
		if addon.Health and addon.Health.functions and addon.Health.functions.ensurePriorityOrder then addon.Health.functions.ensurePriorityOrder() end
	end

	local function notifyPriorityDropdowns()
		local vars = { "EQOL_healthPrioritySlot1", "EQOL_healthPrioritySlot2", "EQOL_healthPrioritySlot3", "EQOL_healthPrioritySlot4" }
		for _, var in ipairs(vars) do
			if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate(var) end
		end
	end

	local function setCombatPotionUsage(value)
		addon.db.healthUseCombatPotions = value and true or false
		addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or defaultPriority()
		if value then
			local exists = false
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "combatpotion" then
					exists = true
					break
				end
			end
			if not exists then
				for i = 1, 4 do
					if addon.db.healthPriorityOrder[i] == "none" then
						addon.db.healthPriorityOrder[i] = "combatpotion"
						break
					end
				end
			end
		else
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "combatpotion" then addon.db.healthPriorityOrder[i] = "none" end
			end
		end
		ensureHealthPriority()
		refreshHealthMacro()
		notifyPriorityDropdowns()
	end

	local function setCustomSpellsUsage(value)
		addon.db.healthUseCustomSpells = value and true or false
		addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or defaultPriority()
		if value then
			local exists = false
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "spell" then
					exists = true
					break
				end
			end
			if not exists then
				for i = 1, 4 do
					if addon.db.healthPriorityOrder[i] == "none" then
						addon.db.healthPriorityOrder[i] = "spell"
						break
					end
				end
			end
		else
			for i = 1, 4 do
				if addon.db.healthPriorityOrder[i] == "spell" then addon.db.healthPriorityOrder[i] = "none" end
			end
		end
		ensureHealthPriority()
		refreshHealthMacro()
		notifyPriorityDropdowns()
	end

	ensureHealthPriority()

	local healthEnable = addon.functions.SettingsCreateCheckbox(cDrink, {
		var = "healthMacroEnabled",
		text = L["Enable Health Macro"],
		func = function(value)
			addon.db.healthMacroEnabled = value and true or false
			refreshHealthMacro()
		end,
		default = false,
		notify = "healthUseCustomSpells",
		parentSection = convenienceSection,
	})

	local function healthParentCheck() return isCheckboxEnabled("healthMacroEnabled") end

	addon.functions.SettingsCreateCheckbox(cDrink, {
		var = "healthUseRecuperate",
		text = L["Use Recuperate out of combat"],
		func = function(value)
			addon.db.healthUseRecuperate = value and true or false
			refreshHealthMacro()
		end,
		parentCheck = healthParentCheck,
		parent = true,
		element = healthEnable.element,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = convenienceSection,
	})

	addon.functions.SettingsCreateCheckbox(cDrink, {
		var = "healthUseCombatPotions",
		text = L["Use Combat potions for health macro"],
		func = setCombatPotionUsage,
		parentCheck = healthParentCheck,
		parent = true,
		element = healthEnable.element,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = convenienceSection,
	})

	local priorityLabels = {
		spell = L["CategoryCustomSpells"] or (L["Custom Spells"] or "Custom Spells"),
		stone = L["CategoryHealthstones"] or (L["Prefer Healthstone first"] or "Healthstones"),
		potion = L["CategoryPotions"] or "Potions",
		combatpotion = L["CategoryCombatPotions"] or (L["Use Combat potions for health macro"] or "Combat potions"),
		none = NONE,
	}

	local basePriorityOrder = { "stone", "potion", "combatpotion", "spell" }
	local priorityOrders = { {}, {}, {}, {} }

	local function priorityOptions(slot)
		local used = {}
		for i = 1, slot - 1 do
			local current = addon.db.healthPriorityOrder and addon.db.healthPriorityOrder[i]
			if current and current ~= "none" then used[current] = true end
		end
		local list = {}
		local order = priorityOrders[slot] or {}
		wipe(order)
		priorityOrders[slot] = order
		for _, key in ipairs(basePriorityOrder) do
			if not used[key] then
				if key == "spell" and not addon.db.healthUseCustomSpells then
				elseif key == "combatpotion" and not addon.db.healthUseCombatPotions then
				else
					list[key] = priorityLabels[key]
					table.insert(order, key)
				end
			end
		end
		list["none"] = priorityLabels.none
		table.insert(order, "none")
		return list
	end

	for i = 1, 4 do
		local defaultOrder = defaultPriority()
		addon.functions.SettingsCreateDropdown(cDrink, {
			var = "healthPrioritySlot" .. i,
			text = (L["PrioritySlot"] or "Priority %d"):format(i),
			parentCheck = healthParentCheck,
			parent = true,
			element = healthEnable.element,
			listFunc = function() return priorityOptions(i) end,
			order = priorityOrders[i],
			default = defaultOrder[i] or "none",
			get = function()
				ensureHealthPriority()
				local cur = addon.db.healthPriorityOrder and addon.db.healthPriorityOrder[i] or "none"
				local list = priorityOptions(i)
				if not list[cur] then cur = "none" end
				return cur
			end,
			set = function(value)
				ensureHealthPriority()
				addon.db.healthPriorityOrder = addon.db.healthPriorityOrder or defaultPriority()
				addon.db.healthPriorityOrder[i] = value
				if value ~= "none" then
					for j = 1, 4 do
						if j ~= i and addon.db.healthPriorityOrder[j] == value then addon.db.healthPriorityOrder[j] = "none" end
					end
				end
				ensureHealthPriority()
				if addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then addon.Health.functions.updateHealthMacro(false) end
				notifyPriorityDropdowns()
			end,
			parentSection = convenienceSection,
		})
	end

	addon.functions.SettingsCreateDropdown(cDrink, {
		var = "healthReset",
		text = L["Reset condition"],
		parentCheck = healthParentCheck,
		parent = true,
		element = healthEnable.element,
		list = {
			combat = L["Reset: Combat"],
			target = L["Reset: Target"],
			["10"] = L["Reset: 10s"],
			["30"] = L["Reset: 30s"],
			["60"] = L["Reset: 60s"],
		},
		order = { "combat", "target", "10", "30", "60" },
		default = "combat",
		get = function() return addon.db.healthReset or "combat" end,
		set = function(value)
			addon.db.healthReset = value
			if addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then addon.Health.functions.updateHealthMacro(false) end
		end,
		parentSection = convenienceSection,
	})

	addon.functions.SettingsCreateCheckbox(cDrink, {
		var = "healthUseCustomSpells",
		text = L["Use custom spells"] or "Use custom spells",
		func = setCustomSpellsUsage,
		parentCheck = healthParentCheck,
		parent = true,
		element = healthEnable.element,
		default = false,
		type = Settings.VarType.Boolean,
		parentSection = convenienceSection,
	})

	local function customSpellsEnabled() return healthParentCheck() and addon.db.healthUseCustomSpells == true end
	local customSpellsParent = addon.SettingsLayout.elements["healthUseCustomSpells"] and addon.SettingsLayout.elements["healthUseCustomSpells"].element or healthEnable.element

	local customSpellOrder = {}

	StaticPopupDialogs["EQOL_ADD_HEALTH_SPELL"] = StaticPopupDialogs["EQOL_ADD_HEALTH_SPELL"]
		or {
			text = L["Add SpellID"] or "Add SpellID",
			button1 = OKAY,
			button2 = CANCEL,
			hasEditBox = true,
			maxLetters = 10,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function(self)
				local input = self.editBox or self.GetEditBox and self:GetEditBox()
				local text = input and input:GetText() or nil
				local sid = tonumber(text)
				if not sid then return end
				local info = C_Spell.GetSpellInfo(sid)
				if not info or not info.name then return end
				addon.db.healthCustomSpells = addon.db.healthCustomSpells or {}
				for _, v in ipairs(addon.db.healthCustomSpells) do
					if v == sid then return end
				end
				table.insert(addon.db.healthCustomSpells, sid)
				if addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then addon.Health.functions.updateHealthMacro(false) end
				if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("EQOL_healthCustomRemove") end
			end,
		}

	addon.functions.SettingsCreateButton(cDrink, {
		var = "healthCustomAdd",
		text = L["Add SpellID"] or "Add SpellID",
		func = function()
			if not customSpellsEnabled() then return end
			local dialog = StaticPopupDialogs["EQOL_ADD_HEALTH_SPELL"]
			if dialog and dialog.OnShow == nil then
				dialog.OnShow = function(self)
					local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
					if editBox then
						editBox:SetText("")
						editBox:SetFocus()
					end
				end
			end
			StaticPopup_Show("EQOL_ADD_HEALTH_SPELL")
		end,
		parent = true,
		element = customSpellsParent,
		parentCheck = customSpellsEnabled,
		parentSection = convenienceSection,
	})

	local function customSpellList()
		local list = { [""] = "" }
		wipe(customSpellOrder)
		table.insert(customSpellOrder, "")
		local spells = addon.db.healthCustomSpells or {}
		for _, sid in ipairs(spells) do
			local info = C_Spell.GetSpellInfo(sid)
			local name = info and info.name or tostring(sid)
			local key = tostring(sid)
			list[key] = string.format("%s (%s)", name, key)
			table.insert(customSpellOrder, key)
		end
		table.sort(customSpellOrder, function(a, b) return list[a] < list[b] end)
		return list
	end

	addon.functions.SettingsCreateDropdown(cDrink, {
		var = "healthCustomRemove",
		text = L["Custom Spells"] or "Custom Spells",
		parentCheck = customSpellsEnabled,
		parent = true,
		element = customSpellsParent,
		listFunc = customSpellList,
		order = customSpellOrder,
		default = "",
		get = function() return "" end,
		set = function(value)
			local sid = tonumber(value)
			if not sid or not addon.db.healthCustomSpells then return end
			for i, v in ipairs(addon.db.healthCustomSpells) do
				if v == sid then
					table.remove(addon.db.healthCustomSpells, i)
					if addon.Health and addon.Health.functions and addon.Health.functions.updateHealthMacro then addon.Health.functions.updateHealthMacro(false) end
					if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("EQOL_healthCustomRemove") end
					return
				end
			end
		end,
		parentSection = convenienceSection,
	})

	addon.functions.SettingsCreateText(
		cDrink,
		L["healthCustomSpellsHint"] or "Selecting a spell in the dropdown removes it (the field stays blank by design). The macro uses any custom spells you know.",
		{
			parent = customSpellsParent,
			parentCheck = customSpellsEnabled,
			parentSection = convenienceSection,
		}
	)

	addon.functions.SettingsCreateText(cDrink, string.format(L["healthMacroPlaceOnBar"], "EnhanceQoLHealthMacro"), { parentSection = convenienceSection })
	if addon.variables and addon.variables.unitClass == "WARLOCK" then addon.functions.SettingsCreateText(cDrink, L["healthMacroTipReset"], { parentSection = convenienceSection }) end
end

function addon.functions.initDrinkMacro()
	if addon.SettingsLayout and addon.SettingsLayout.drinkMacroSettingsReady then return end
	if not (addon.functions and addon.functions.SettingsCreateCategory) then return end
	if not (addon.SettingsLayout and addon.SettingsLayout.rootGAMEPLAY) then return end
	buildDrinkMacroSettings()
	addon.SettingsLayout.drinkMacroSettingsReady = true
end
