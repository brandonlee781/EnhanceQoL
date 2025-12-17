local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local wipe = wipe
local serializer = LibStub("AceSerializer-3.0")
local deflate = LibStub("LibDeflate")
local PROFILE_EXPORT_KIND = "EQOL_PROFILE"

local cProfiles = addon.functions.SettingsCreateCategory(nil, L["Profiles"], nil, "Profiles")
addon.SettingsLayout.profilesCategory = cProfiles
local profileOrderActive, profileOrderGlobal, profileOrderCopy, profileOrderDelete = {}, {}, {}, {}

-- Build a sorted dropdown list, optionally keeping an empty entry pinned to the top
local function buildSortedProfileList(orderTarget, excludeFunc, includeEmpty)
	local list = {}
	local order = orderTarget or {}
	if orderTarget then wipe(orderTarget) end

	if includeEmpty then
		list[""] = ""
		table.insert(order, "")
	end

	local entries = {}
	for name in pairs(EnhanceQoLDB.profiles) do
		if not excludeFunc or not excludeFunc(name) then table.insert(entries, name) end
	end

	table.sort(entries, function(a, b)
		local la, lb = string.lower(a), string.lower(b)
		if la == lb then return a < b end
		return la < lb
	end)
	for _, name in ipairs(entries) do
		list[name] = name
		table.insert(order, name)
	end

	return list
end

local function getActiveProfileName()
	if not EnhanceQoLDB or not EnhanceQoLDB.profileKeys then return nil end
	local guid = UnitGUID("player")
	local profile = guid and EnhanceQoLDB.profileKeys[guid]
	if profile and profile ~= "" then return profile end
	if EnhanceQoLDB.profileGlobal and EnhanceQoLDB.profileGlobal ~= "" then return EnhanceQoLDB.profileGlobal end
	return nil
end

local EXPORT_BLACKLIST = {
	-- runtime/session or external data that should never be shared
	chatChannelHistory = true,
	chatChannelFilters = true,
	chatChannelFiltersEnable = true,
	chatIMFrameData = true,
}

local function sanitizeProfileData(source)
	if type(source) ~= "table" then return {} end
	local filtered = {}
	for key, value in pairs(source) do
		if not EXPORT_BLACKLIST[key] then filtered[key] = value end
	end
	return filtered
end

local function exportActiveProfile()
	if not serializer or not deflate then return nil, "NO_LIB" end
	local profileName = getActiveProfileName()
	if not profileName then return nil, "NO_ACTIVE" end
	local source = EnhanceQoLDB and EnhanceQoLDB.profiles and EnhanceQoLDB.profiles[profileName]
	if type(source) ~= "table" or not next(source) then return nil, "NO_DATA" end

	local payload = {
		meta = {
			addon = addonName,
			kind = PROFILE_EXPORT_KIND,
			version = tostring(C_AddOns.GetAddOnMetadata(addonName, "Version") or ""),
			profileVersion = 1,
			profile = profileName,
		},
		data = sanitizeProfileData(source),
	}

	local serialized = serializer:Serialize(payload)
	if not serialized or serialized == "" then return nil, "SERIALIZE" end
	local compressed = deflate:CompressDeflate(serialized)
	if not compressed then return nil, "COMPRESS" end
	return deflate:EncodeForPrint(compressed)
end

local function importActiveProfile(encoded)
	if not serializer or not deflate then return false, "NO_LIB" end
	encoded = tostring(encoded or "")
	encoded = encoded:gsub("^%s+", ""):gsub("%s+$", "")
	if encoded == "" then return false, "NO_INPUT" end

	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return false, "DECODE" end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return false, "DECOMPRESS" end
	local ok, payload = serializer:Deserialize(decompressed)
	if not ok or type(payload) ~= "table" then return false, "DESERIALIZE" end

	local meta = payload.meta
	local data = payload.data
	if type(meta) ~= "table" or meta.addon ~= addonName or meta.kind ~= PROFILE_EXPORT_KIND then return false, "INVALID" end
	if type(data) ~= "table" then return false, "NO_DATA" end

	local target = getActiveProfileName()
	if not target then return false, "NO_ACTIVE" end

	if not EnhanceQoLDB or type(EnhanceQoLDB.profiles) ~= "table" then return false, "NO_DB" end

	EnhanceQoLDB.profiles[target] = sanitizeProfileData(data)
	addon.db = EnhanceQoLDB.profiles[target]

	return true
end

local function exportErrorMessage(reason)
	if reason == "NO_ACTIVE" then return L["ProfileExportNoActive"] or "No active profile found." end
	if reason == "NO_DATA" then return L["ProfileExportEmpty"] or "Active profile has no saved settings to export." end
	return L["ProfileExportFailed"] or "Profile export failed."
end

local function importErrorMessage(reason)
	if reason == "NO_INPUT" then return L["ProfileImportEmpty"] or "Please paste a code to import." end
	if reason == "INVALID" or reason == "DECODE" or reason == "DECOMPRESS" or reason == "DESERIALIZE" then
		return L["ProfileImportInvalid"] or "The code could not be read."
	end
	if reason == "NO_ACTIVE" or reason == "NO_DB" then return L["ProfileExportNoActive"] or "No active profile found." end
	return L["ProfileImportFailed"] or "Profile import failed."
end

local data = {
	listFunc = function() return buildSortedProfileList(profileOrderActive) end,
	order = profileOrderActive,
	text = L["ProfileActive"],
	get = function() return EnhanceQoLDB.profileKeys[UnitGUID("player")] or EnhanceQoLDB.profileGlobal end,
	set = function(value)
		EnhanceQoLDB.profileKeys[UnitGUID("player")] = value
		addon.variables.requireReload = true
		addon.functions.checkReloadFrame()
	end,
	default = "",
	var = "profiledata",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

data = {
	listFunc = function() return buildSortedProfileList(profileOrderGlobal) end,
	order = profileOrderGlobal,
	text = L["ProfileUseGlobal"],
	get = function() return EnhanceQoLDB.profileGlobal end,
	set = function(value) EnhanceQoLDB.profileGlobal = value end,
	default = "",
	var = "profilefirststart",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)
addon.functions.SettingsCreateText(cProfiles, L["ProfileUseGlobalDesc"])

data = {
	listFunc = function()
		local currentProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
		return buildSortedProfileList(profileOrderCopy, function(name) return name == currentProfile end, true)
	end,
	order = profileOrderCopy,
	text = L["ProfileCopy"],
	get = function() return "" end,
	set = function(value)
		if value ~= "" then
			StaticPopupDialogs["EQOL_COPY_PROFILE"] = StaticPopupDialogs["EQOL_COPY_PROFILE"]
				or {
					text = "",
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
					OnAccept = function(self)
						local source = self.data
						if not source or source == "" then return end
						local target = EnhanceQoLDB.profileKeys[UnitGUID("player")]
						if not target then return end
						EnhanceQoLDB.profiles[target] = CopyTable(EnhanceQoLDB.profiles[source])
						C_UI.Reload()
					end,
				}
			StaticPopupDialogs["EQOL_COPY_PROFILE"].text = L["ProfileCopyDesc"]:format(value)
			StaticPopup_Show("EQOL_COPY_PROFILE", nil, nil, value)
		end
	end,
	default = "",
	var = "profilecopy",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

data = {
	listFunc = function()
		local currentProfile = EnhanceQoLDB.profileKeys[UnitGUID("player")]
		local globalProfile = EnhanceQoLDB.profileGlobal
		return buildSortedProfileList(profileOrderDelete, function(name) return name == currentProfile or name == globalProfile end, true)
	end,
	order = profileOrderDelete,
	text = L["ProfileDelete"],
	get = function() return "" end,
	set = function(value)
		if value ~= "" then
			StaticPopupDialogs["EQOL_DELETE_PROFILE"] = StaticPopupDialogs["EQOL_DELETE_PROFILE"]
				or {
					text = "",
					button1 = YES,
					button2 = CANCEL,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
					OnAccept = function(self)
						local profile = self.data
						if profile and profile ~= "" then EnhanceQoLDB.profiles[profile] = nil end
					end,
				}
			StaticPopupDialogs["EQOL_DELETE_PROFILE"].text = L["ProfileDeleteDesc"]:format(value)
			StaticPopup_Show("EQOL_DELETE_PROFILE", nil, nil, value)
		end
	end,
	desc = L["ProfileDeleteDesc2"],
	default = "",
	var = "profiledelete",
}

addon.functions.SettingsCreateDropdown(cProfiles, data)

data = {
var = "AddProfile",
text = L["ProfileName"],
func = function() StaticPopup_Show("EQOL_CREATE_PROFILE") end,
}
addon.functions.SettingsCreateButton(cProfiles, data)

addon.functions.SettingsCreateHeadline(cProfiles, L["ProfileShareHeader"] or "Export / Import")

addon.functions.SettingsCreateButton(cProfiles, {
	var = "profileExport",
	text = L["ProfileExport"] or (L["Export"] or "Export"),
	func = function()
		local code, reason = exportActiveProfile()
		if not code then
			print("|cff00ff98Enhance QoL|r: " .. tostring(exportErrorMessage(reason)))
			return
		end
		StaticPopupDialogs["EQOL_PROFILE_EXPORT"] = StaticPopupDialogs["EQOL_PROFILE_EXPORT"]
			or {
				text = L["ProfileExportTitle"] or "Export profile",
				button1 = CLOSE,
				hasEditBox = true,
				editBoxWidth = 320,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_PROFILE_EXPORT"].OnShow = function(self)
			self:SetFrameStrata("TOOLTIP")
			local editBox = self.editBox or self:GetEditBox()
			editBox:SetText(code)
			editBox:HighlightText()
			editBox:SetFocus()
		end
		StaticPopup_Show("EQOL_PROFILE_EXPORT")
	end,
})

addon.functions.SettingsCreateButton(cProfiles, {
	var = "profileImport",
	text = L["ProfileImport"] or (L["Import"] or "Import"),
	func = function()
		StaticPopupDialogs["EQOL_PROFILE_IMPORT"] = StaticPopupDialogs["EQOL_PROFILE_IMPORT"]
			or {
				text = L["ProfileImportConfirm"] or "Importing will overwrite your active profile and reload the UI.",
				button1 = OKAY,
				button2 = CANCEL,
				hasEditBox = true,
				editBoxWidth = 320,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_PROFILE_IMPORT"].text = L["ProfileImportConfirm"] or "Importing will overwrite your active profile and reload the UI."
		StaticPopupDialogs["EQOL_PROFILE_IMPORT"].OnShow = function(self)
			self:SetFrameStrata("TOOLTIP")
			local editBox = self.editBox or self:GetEditBox()
			editBox:SetText("")
			editBox:SetFocus()
		end
		StaticPopupDialogs["EQOL_PROFILE_IMPORT"].EditBoxOnEnterPressed = function(editBox)
			local parent = editBox:GetParent()
			if parent and parent.button1 then parent.button1:Click() end
			end
			StaticPopupDialogs["EQOL_PROFILE_IMPORT"].OnAccept = function(self)
				local editBox = self.editBox or self:GetEditBox()
				local input = editBox:GetText() or ""
				local ok, reason = importActiveProfile(input)
			if not ok then
				print("|cff00ff98Enhance QoL|r: " .. tostring(importErrorMessage(reason)))
				return
			end
			print("|cff00ff98Enhance QoL|r: " .. (L["ProfileImportSuccess"] or "Profile imported. Reloading UI..."))
			C_UI.Reload()
		end
		StaticPopup_Show("EQOL_PROFILE_IMPORT")
	end,
})

----- REGION END
function addon.functions.initProfile()
	StaticPopupDialogs["EQOL_CREATE_PROFILE"] = StaticPopupDialogs["EQOL_CREATE_PROFILE"]
		or {
			text = L["ProfileName"],
			hasEditBox = true,
			button1 = OKAY,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnShow = function(self, data)
				local editBox = self.editBox or self.GetEditBox and self:GetEditBox()
				if editBox then
					editBox:SetText(data or "")
					editBox:SetFocus()
					editBox:HighlightText()
				end
			end,
			OnAccept = function(self)
				local id = self:GetEditBox():GetText()
				if id and id ~= "" then
					if not EnhanceQoLDB.profiles[id] or type(EnhanceQoLDB.profiles[id]) ~= "table" then EnhanceQoLDB.profiles[id] = {} end
				end
			end,
		}
end
