local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local EditMode = addon.EditMode

local ResourceBars = addon.Aura and addon.Aura.ResourceBars
if not ResourceBars then return end

local function ensureSpecCfg(specIndex)
	local class = addon.variables.unitClass
	if not class or not specIndex then return end
	addon.db.personalResourceBarSettings = addon.db.personalResourceBarSettings or {}
	addon.db.personalResourceBarSettings[class] = addon.db.personalResourceBarSettings[class] or {}
	addon.db.personalResourceBarSettings[class][specIndex] = addon.db.personalResourceBarSettings[class][specIndex] or {}
	return addon.db.personalResourceBarSettings[class][specIndex]
end

local function setBarEnabled(specIndex, barType, enabled)
	local specCfg = ensureSpecCfg(specIndex)
	if not specCfg then return end
	specCfg[barType] = specCfg[barType] or {}
	specCfg[barType].enabled = enabled and true or false
	if barType == "HEALTH" then
		if enabled then
			ResourceBars.SetHealthBarSize(specCfg[barType].width or ResourceBars.DEFAULT_HEALTH_WIDTH or 200, specCfg[barType].height or ResourceBars.DEFAULT_HEALTH_HEIGHT or 20)
		else
			ResourceBars.DetachAnchorsFrom("HEALTH", specIndex)
		end
	else
		if enabled then
			ResourceBars.SetPowerBarSize(specCfg[barType].width or ResourceBars.DEFAULT_POWER_WIDTH or 200, specCfg[barType].height or ResourceBars.DEFAULT_POWER_HEIGHT or 20, barType)
		else
			ResourceBars.DetachAnchorsFrom(barType, specIndex)
		end
	end
	if ResourceBars.QueueRefresh then ResourceBars.QueueRefresh(specIndex) end
	if ResourceBars.MaybeRefreshActive then ResourceBars.MaybeRefreshActive(specIndex) end
end

local function registerEditModeBars()
	if not EditMode or not EditMode.RegisterFrame then return end

	local function registerBar(idSuffix, frameName, barType, widthDefault, heightDefault)
		local frame = _G[frameName]
		if not frame then return end
		local cfg = ResourceBars and ResourceBars.getBarSettings and ResourceBars.getBarSettings(barType) or ResourceBars and ResourceBars.GetBarSettings and ResourceBars.GetBarSettings(barType)
		local anchor = ResourceBars and ResourceBars.getAnchor and ResourceBars.getAnchor(barType, addon.variables.unitSpec)
		EditMode:RegisterFrame("resourceBar_" .. idSuffix, {
			frame = frame,
			title = L["Resource Bars"],
			layoutDefaults = {
				point = anchor and anchor.point or "CENTER",
				relativePoint = anchor and anchor.relativePoint or "CENTER",
				x = anchor and anchor.x or 0,
				y = anchor and anchor.y or 0,
				width = cfg and cfg.width or widthDefault or frame:GetWidth() or 200,
				height = cfg and cfg.height or heightDefault or frame:GetHeight() or 20,
			},
			onApply = function(_, _, data)
				local spec = addon.variables.unitSpec
				local specCfg = ensureSpecCfg(spec)
				if not specCfg then return end
				specCfg[barType] = specCfg[barType] or {}
				local bcfg = specCfg[barType]
				bcfg.anchor = bcfg.anchor or {}
				if data.point then
					bcfg.anchor.point = data.point
					bcfg.anchor.relativePoint = data.relativePoint or data.point
					bcfg.anchor.x = data.x or 0
					bcfg.anchor.y = data.y or 0
					bcfg.anchor.relativeFrame = "UIParent"
				end
				bcfg.width = data.width or bcfg.width
				bcfg.height = data.height or bcfg.height
				if barType == "HEALTH" then
					ResourceBars.SetHealthBarSize(bcfg.width, bcfg.height)
				else
					ResourceBars.SetPowerBarSize(bcfg.width, bcfg.height, barType)
				end
				if ResourceBars.ReanchorAll then ResourceBars.ReanchorAll() end
				if ResourceBars.Refresh then ResourceBars.Refresh() end
			end,
			settings = EditMode.lib and EditMode.lib.SettingType and {
				{
					name = L["Width"] or WIDTH,
					kind = EditMode.lib.SettingType.Slider,
					field = "width",
					minValue = 50,
					maxValue = 600,
					valueStep = 1,
					default = cfg and cfg.width or widthDefault or 200,
				},
				{
					name = L["Height"] or HEIGHT,
					kind = EditMode.lib.SettingType.Slider,
					field = "height",
					minValue = 6,
					maxValue = 80,
					valueStep = 1,
					default = cfg and cfg.height or heightDefault or 20,
				},
			} or nil,
			showOutsideEditMode = true,
		})
	end

	registerBar("HEALTH", "EQOLHealthBar", "HEALTH", ResourceBars.DEFAULT_HEALTH_WIDTH, ResourceBars.DEFAULT_HEALTH_HEIGHT)
	for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
		local frameName = "EQOL" .. pType .. "Bar"
		registerBar(pType, frameName, pType, ResourceBars.DEFAULT_POWER_WIDTH, ResourceBars.DEFAULT_POWER_HEIGHT)
	end
end

local function buildSpecToggles(parent, specIndex, specName, available)
	addon.functions.SettingsCreateHeadline(parent, specName)

	local specCfg = ensureSpecCfg(specIndex)
	if not specCfg then return end

	-- Health toggle
	local hCfg = specCfg.HEALTH or {}
	addon.functions.SettingsCreateCheckbox(parent, {
		var = ("rb_health_%s"):format(specIndex),
		text = HEALTH,
		get = function() return hCfg.enabled == true end,
		func = function(val)
			hCfg.enabled = val and true or false
			setBarEnabled(specIndex, "HEALTH", val)
		end,
	})
	print(("rb_health_%s"):format(specIndex))

	for _, pType in ipairs(ResourceBars.classPowerTypes or {}) do
		if available[pType] then
			specCfg[pType] = specCfg[pType] or {}
			local cfg = specCfg[pType]
			local label = _G["POWER_TYPE_" .. pType] or _G[pType] or pType
			addon.functions.SettingsCreateCheckbox(parent, {
				var = ("rb_%s_%s"):format(pType, specIndex),
				text = label,
				get = function() return cfg.enabled == true end,
				func = function(val)
					cfg.enabled = val and true or false
					setBarEnabled(specIndex, pType, val)
				end,
			})
		end
	end
end

local function buildSettings()
	local cat = addon.functions.SettingsCreateCategory(nil, L["Resource Bars"], nil, "ResourceBars")
	if not cat then return end

	local data = {
		{
			var = "enableResourceFrame",
			text = L["Resource Bars"],
			desc = L["Resource Bars"],
			get = function() return addon.db["enableResourceFrame"] end,
			func = function(val)
				addon.db["enableResourceFrame"] = val and true or false
				if val and ResourceBars.EnableResourceBars then
					ResourceBars.EnableResourceBars()
				elseif ResourceBars.DisableResourceBars then
					ResourceBars.DisableResourceBars()
				end
			end,
			default = false,
			children = {
				{
					var = "resourceBarsHideOutOfCombat",
					text = L["Hide out of combat"],
					get = function() return addon.db["resourceBarsHideOutOfCombat"] end,
					func = function(val)
						addon.db["resourceBarsHideOutOfCombat"] = val and true or false
						if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
					end,
					parent = true,
					parentCheck = function()
						return addon.SettingsLayout.elements["enableResourceFrame"]
							and addon.SettingsLayout.elements["enableResourceFrame"].setting
							and addon.SettingsLayout.elements["enableResourceFrame"].setting:GetValue() == true
					end,
					default = false,
					sType = "checkbox",
				},
			},
		},
	}

	addon.functions.SettingsCreateCheckboxes(cat, data)

	addon.functions.SettingsCreateCheckbox(cat, {
		var = "resourceBarsHideMounted",
		text = L["Hide when mounted"],
		get = function() return addon.db["resourceBarsHideMounted"] end,
		func = function(val)
			addon.db["resourceBarsHideMounted"] = val and true or false
			if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
		end,
	})
	addon.functions.SettingsCreateCheckbox(cat, {
		var = "resourceBarsHideVehicle",
		text = L["Hide in vehicles"],
		get = function() return addon.db["resourceBarsHideVehicle"] end,
		func = function(val)
			addon.db["resourceBarsHideVehicle"] = val and true or false
			if ResourceBars.ApplyVisibilityPreference then ResourceBars.ApplyVisibilityPreference("settings") end
		end,
	})

	local class = addon.variables.unitClassID
	if class and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[addon.variables.unitClass] then
		for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(class) do
			local specID, specName = GetSpecializationInfoForClassID(class, specIndex)
			local available = ResourceBars.powertypeClasses[addon.variables.unitClass][specIndex] or {}
			if specID and specName then buildSpecToggles(cat, specIndex, specName, available) end
		end
	end

	do -- Profile export/import
		local classKey = addon.variables.unitClass or "UNKNOWN"
		addon.db.resourceBarsProfileScope = addon.db.resourceBarsProfileScope or {}
		local function getScope()
			local cur = addon.db.resourceBarsProfileScope[classKey]
			if not cur then cur = "ALL" end
			return cur
		end
		local function setScope(val) addon.db.resourceBarsProfileScope[classKey] = val end

		local scopeList, scopeOrder = { ALL = L["All specs"] or "All specs" }, { "ALL" }
		if class and ResourceBars.powertypeClasses and ResourceBars.powertypeClasses[addon.variables.unitClass] then
			for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(class) do
				local _, specName = GetSpecializationInfoForClassID(class, specIndex)
				if specName then
					scopeList[tostring(specIndex)] = specName
					scopeOrder[#scopeOrder + 1] = tostring(specIndex)
				end
			end
		end

		addon.functions.SettingsCreateHeadline(cat, L["Profiles"] or PROFILES_LABEL or "Profiles")
		addon.functions.SettingsCreateDropdown(cat, {
			var = "resourceBarsProfileScope",
			text = L["ProfileScope"] or (L["Apply to"] or "Apply to"),
			list = scopeList,
			get = getScope,
			set = setScope,
			default = "ALL",
		})

		addon.functions.SettingsCreateButton(cat, {
			var = "resourceBarsExport",
			text = L["Export"] or EXPORT,
			func = function()
				local scopeKey = getScope() or "ALL"
				local code, reason = ResourceBars.ExportProfile and ResourceBars.ExportProfile(scopeKey)
				if not code then
					local msg = ResourceBars.ExportErrorMessage and ResourceBars.ExportErrorMessage(reason) or (L["ExportProfileFailed"] or "Export failed.")
					print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
					return
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"] = StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"]
					or {
						text = L["ExportProfileTitle"] or "Export Resource Bars",
						button1 = CLOSE,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_RESOURCEBAR_EXPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText(code)
					editBox:HighlightText()
					editBox:SetFocus()
				end
				StaticPopup_Show("EQOL_RESOURCEBAR_EXPORT_SETTINGS")
			end,
		})

		addon.functions.SettingsCreateButton(cat, {
			var = "resourceBarsImport",
			text = L["Import"] or IMPORT,
			func = function()
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"] = StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"]
					or {
						text = L["ImportProfileTitle"] or "Import Resource Bars",
						button1 = OKAY,
						button2 = CANCEL,
						hasEditBox = true,
						editBoxWidth = 320,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						preferredIndex = 3,
					}
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].OnShow = function(self)
					self:SetFrameStrata("TOOLTIP")
					local editBox = self.editBox or self:GetEditBox()
					editBox:SetText("")
					editBox:SetFocus()
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].EditBoxOnEnterPressed = function(editBox)
					local parent = editBox:GetParent()
					if parent and parent.button1 then parent.button1:Click() end
				end
				StaticPopupDialogs["EQOL_RESOURCEBAR_IMPORT_SETTINGS"].OnAccept = function(self)
					local editBox = self.editBox or self:GetEditBox()
					local input = editBox:GetText() or ""
					local scopeKey = getScope() or "ALL"
					local ok, applied, enableState = addon.Aura.functions.importResourceProfile(input, scopeKey)
					if not ok then
						local msg = ResourceBars.ImportErrorMessage and ResourceBars.ImportErrorMessage(applied, enableState) or (L["ImportProfileFailed"] or "Import failed.")
						print("|cff00ff98Enhance QoL|r: " .. tostring(msg))
						return
					end
					if enableState ~= nil and scopeKey == "ALL" then
						local prev = addon.db["enableResourceFrame"]
						addon.db["enableResourceFrame"] = enableState and true or false
						if enableState and prev ~= true and addon.Aura.ResourceBars and addon.Aura.ResourceBars.EnableResourceBars then
							addon.Aura.ResourceBars.EnableResourceBars()
						elseif not enableState and prev ~= false and addon.Aura.ResourceBars and addon.Aura.ResourceBars.DisableResourceBars then
							addon.Aura.ResourceBars.DisableResourceBars()
						end
					end
					if applied then
						for _, specIndex in ipairs(applied) do
							addon.Aura.functions.requestActiveRefresh(specIndex)
						end
					end
					if applied and #applied > 0 then
						local specNames = {}
						for _, specIndex in ipairs(applied) do
							specNames[#specNames + 1] = ResourceBars.SpecNameByIndex and ResourceBars.SpecNameByIndex(specIndex) or tostring(specIndex)
						end
						local msg = (L["ImportProfileSuccess"] or "Resource Bars updated for: %s"):format(table.concat(specNames, ", "))
						print("|cff00ff98Enhance QoL|r: " .. msg)
					else
						local msg = L["ImportProfileSuccessGeneric"] or "Resource Bars profile imported."
						print("|cff00ff98Enhance QoL|r: " .. msg)
					end
					Settings.NotifyUpdate("EQOL_" .. "enableResourceFrame")
				end
				StaticPopup_Show("EQOL_RESOURCEBAR_IMPORT_SETTINGS")
			end,
		})
	end

	registerEditModeBars()
end

buildSettings()
