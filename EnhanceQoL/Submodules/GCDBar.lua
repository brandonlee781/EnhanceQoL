local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.GCDBar = addon.GCDBar or {}
local GCDBar = addon.GCDBar

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local LSM = LibStub("LibSharedMedia-3.0", true)

local EDITMODE_ID = "gcdBar"
local GCD_SPELL_ID = 61304

GCDBar.defaults = GCDBar.defaults or {
	width = 200,
	height = 18,
	texture = "DEFAULT",
	color = { r = 1, g = 0.82, b = 0.2, a = 1 },
}

local defaults = GCDBar.defaults

local DB_ENABLED = "gcdBarEnabled"
local DB_WIDTH = "gcdBarWidth"
local DB_HEIGHT = "gcdBarHeight"
local DB_TEXTURE = "gcdBarTexture"
local DB_COLOR = "gcdBarColor"

local DEFAULT_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local function getValue(key, fallback)
	if not addon.db then return fallback end
	local value = addon.db[key]
	if value == nil then return fallback end
	return value
end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function normalizeColor(value)
	if type(value) == "table" then
		local r = value.r or value[1] or 1
		local g = value.g or value[2] or 1
		local b = value.b or value[3] or 1
		local a = value.a or value[4]
		return r, g, b, a
	elseif type(value) == "number" then
		return value, value, value
	end
	local d = defaults.color or {}
	return d.r or 1, d.g or 1, d.b or 1, d.a
end

local function resolveTexture(key)
	if key == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not key or key == "DEFAULT" then return DEFAULT_TEX end
	if LSM and LSM.Fetch then
		local tex = LSM:Fetch("statusbar", key, true)
		if tex then return tex end
	end
	return key
end

local function textureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", _G.DEFAULT)
	add("SOLID", "Solid")
	if LSM and LSM.HashTable then
		for name, path in pairs(LSM:HashTable("statusbar") or {}) do
			if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
		end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

function GCDBar:GetWidth() return clamp(getValue(DB_WIDTH, defaults.width), 50, 800) end

function GCDBar:GetHeight() return clamp(getValue(DB_HEIGHT, defaults.height), 6, 200) end

function GCDBar:GetTextureKey()
	local key = getValue(DB_TEXTURE, defaults.texture)
	if not key or key == "" then key = defaults.texture end
	return key
end

function GCDBar:GetColor() return normalizeColor(getValue(DB_COLOR, defaults.color)) end

function GCDBar:ApplyAppearance()
	if not self.frame then return end
	local texture = resolveTexture(self:GetTextureKey())
	self.frame:SetStatusBarTexture(texture)
	local r, g, b, a = self:GetColor()
	self.frame:SetStatusBarColor(r, g, b, a or 1)
end

function GCDBar:ApplySize()
	if not self.frame then return end
	self.frame:SetSize(self:GetWidth(), self:GetHeight())
	if self.frame.bg then self.frame.bg:SetAllPoints(self.frame) end
end

function GCDBar:EnsureFrame()
	if self.frame then return self.frame end

	local bar = CreateFrame("StatusBar", "EQOL_GCDBar", UIParent)
	bar:SetMinMaxValues(0, 1)
	bar:SetClampedToScreen(true)
	bar:Hide()

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bar)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)
	bg:Hide()
	bar.bg = bg

	local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(L["GCDBar"] or "GCD Bar")
	label:Hide()
	bar.label = label

	self.frame = bar
	self:ApplyAppearance()
	self:ApplySize()

	return bar
end

function GCDBar:ShowEditModeHint(show)
	if not self.frame then return end
	if show then
		self.frame.bg:Show()
		self.frame.label:Show()
		self.previewing = true
		self.frame:SetMinMaxValues(0, 1)
		self.frame:SetValue(1)
		self.frame:Show()
	else
		self.frame.bg:Hide()
		self.frame.label:Hide()
		self.previewing = nil
		self:UpdateGCD()
	end
end

function GCDBar:UpdateGCD()
	if self.previewing then return end
	if not self.frame or not self.frame.SetTimerDuration then return end

	local duration = C_Spell.GetSpellCooldownDuration(GCD_SPELL_ID)
	if not duration then return end
	self.frame:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
	self.frame:Show()
end

function GCDBar:OnEvent(event, spellID, baseSpellID)
	if event ~= "SPELL_UPDATE_COOLDOWN" then return end
	self:UpdateGCD()
end

function GCDBar:RegisterEvents()
	if self.eventsRegistered then return end
	local frame = self:EnsureFrame()
	frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	frame:SetScript("OnEvent", function(_, event, ...) GCDBar:OnEvent(event, ...) end)
	self.eventsRegistered = true
end

function GCDBar:UnregisterEvents()
	if not self.eventsRegistered or not self.frame then return end
	self.frame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
	self.frame:SetScript("OnEvent", nil)
	self.eventsRegistered = false
end

local editModeRegistered = false

function GCDBar:ApplyLayoutData(data)
	if not data or not addon.db then return end

	local width = clamp(data.width or defaults.width, 50, 800)
	local height = clamp(data.height or defaults.height, 6, 200)
	local texture = data.texture or defaults.texture
	local r, g, b, a = normalizeColor(data.color or defaults.color)

	addon.db[DB_WIDTH] = width
	addon.db[DB_HEIGHT] = height
	addon.db[DB_TEXTURE] = texture
	addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }

	self:ApplySize()
	self:ApplyAppearance()
end

local function applySetting(field, value)
	if not addon.db then return end

	if field == "width" then
		local width = clamp(value, 50, 800)
		addon.db[DB_WIDTH] = width
		value = width
	elseif field == "height" then
		local height = clamp(value, 6, 200)
		addon.db[DB_HEIGHT] = height
		value = height
	elseif field == "texture" then
		local tex = value or defaults.texture
		addon.db[DB_TEXTURE] = tex
		value = tex
	elseif field == "color" then
		local r, g, b, a = normalizeColor(value)
		addon.db[DB_COLOR] = { r = r, g = g, b = b, a = a }
		value = addon.db[DB_COLOR]
	end

	if EditMode and EditMode.SetValue then EditMode:SetValue(EDITMODE_ID, field, value, nil, true) end
	GCDBar:ApplySize()
	GCDBar:ApplyAppearance()
end

function GCDBar:RegisterEditMode()
	if editModeRegistered or not EditMode or not EditMode.RegisterFrame then return end

	local settings
	if SettingType then
		settings = {
			{
				name = L["gcdBarWidth"] or "Bar width",
				kind = SettingType.Slider,
				field = "width",
				default = defaults.width,
				minValue = 50,
				maxValue = 800,
				valueStep = 1,
				get = function() return GCDBar:GetWidth() end,
				set = function(_, value) applySetting("width", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["gcdBarHeight"] or "Bar height",
				kind = SettingType.Slider,
				field = "height",
				default = defaults.height,
				minValue = 6,
				maxValue = 200,
				valueStep = 1,
				get = function() return GCDBar:GetHeight() end,
				set = function(_, value) applySetting("height", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = L["gcdBarTexture"] or "Bar texture",
				kind = SettingType.Dropdown,
				field = "texture",
				height = 180,
				get = function() return GCDBar:GetTextureKey() end,
				set = function(_, value) applySetting("texture", value) end,
				generator = function(_, root)
					for _, option in ipairs(textureOptions()) do
						root:CreateRadio(option.label, function() return GCDBar:GetTextureKey() == option.value end, function() applySetting("texture", option.value) end)
					end
				end,
			},
			{
				name = L["gcdBarColor"] or "Bar color",
				kind = SettingType.Color,
				field = "color",
				default = defaults.color,
				hasOpacity = true,
				get = function()
					local r, g, b, a = GCDBar:GetColor()
					return { r = r, g = g, b = b, a = a }
				end,
				set = function(_, value) applySetting("color", value) end,
			},
		}
	end

	EditMode:RegisterFrame(EDITMODE_ID, {
		frame = self:EnsureFrame(),
		title = L["GCDBar"] or "GCD Bar",
		layoutDefaults = {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = -120,
			width = self:GetWidth(),
			height = self:GetHeight(),
			texture = self:GetTextureKey(),
			color = (function()
				local r, g, b, a = self:GetColor()
				return { r = r, g = g, b = b, a = a }
			end)(),
		},
		onApply = function(_, _, data) GCDBar:ApplyLayoutData(data) end,
		onEnter = function() GCDBar:ShowEditModeHint(true) end,
		onExit = function() GCDBar:ShowEditModeHint(false) end,
		isEnabled = function() return addon.db and addon.db[DB_ENABLED] end,
		settings = settings,
		showOutsideEditMode = false,
		showReset = false,
		showSettingsReset = false,
		enableOverlayToggle = true,
	})

	editModeRegistered = true
end

function GCDBar:OnSettingChanged(enabled)
	if enabled then
		self:EnsureFrame()
		self:RegisterEditMode()
		self:RegisterEvents()
		self:ApplySize()
		self:ApplyAppearance()
		self:UpdateGCD()
	else
		self:UnregisterEvents()
		if self.frame then self.frame:Hide() end
	end

	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
end

return GCDBar
