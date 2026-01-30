-- luacheck: globals RegisterStateDriver UnregisterStateDriver RegisterUnitWatch
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

--[[
	EQoL Group Unit Frames (Party/Raid) - SecureGroupHeaderTemplate scaffold

	Goal of this file:
	- Create secure party + raid headers
	- Provide a unit-button template hook (defined in UF_GroupFrames.xml)
	- Build a simple unit frame (health/power/name) on top of your existing UF style
	- Keep everything extendable (more widgets, auras, indicators, sorting, etc.)

	Notes about secure headers:
	- Changing header attributes (layout, filters, visibility) is forbidden in combat.
	- Frames are spawned by the header. You must use an XML template for the unit buttons.
	- Use RegisterStateDriver for visibility, and guard everything with InCombatLockdown().
--]]

addon.Aura = addon.Aura or {}
addon.Aura.UF = addon.Aura.UF or {}
local UF = addon.Aura.UF

UF.GroupFrames = UF.GroupFrames or {}
local GF = UF.GroupFrames

local UFHelper = addon.Aura.UFHelper
local AuraUtil = UF.AuraUtil
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local C_Timer = C_Timer
local GetTime = GetTime
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGroupRolesAssignedEnum = UnitGroupRolesAssignedEnum
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local GetNumClasses = GetNumClasses
local GetClassInfo = GetClassInfo
local GetSpecialization = GetSpecialization
local GetNumSpecializations = GetNumSpecializations
local GetSpecializationInfo = GetSpecializationInfo
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetNumSpecializationsForClassID = GetNumSpecializationsForClassID
local UnitSex = UnitSex
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local issecretvalue = _G.issecretvalue
local C_UnitAuras = C_UnitAuras
local Enum = Enum
local C_SpecializationInfo = C_SpecializationInfo
local C_CreatureInfo = C_CreatureInfo
local GetMicroIconForRole = GetMicroIconForRole

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor
local LSM = LibStub and LibStub("LibSharedMedia-3.0")

-- ----------------------------------------------------------------------------
-- Small subset of UF.lua helpers (kept local here)
-- ----------------------------------------------------------------------------

local max = math.max
local floor = math.floor
local hooksecurefunc = hooksecurefunc

local function ensureBorderFrame(frame)
	if not frame then return nil end
	local border = frame._ufBorder
	if not border then
		border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		border:EnableMouse(false)
		frame._ufBorder = border
	end
	border:SetFrameStrata(frame:GetFrameStrata())
	local baseLevel = frame:GetFrameLevel() or 0
	border:SetFrameLevel(baseLevel + 3)
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	return border
end

local function setBackdrop(frame, borderCfg)
	if not frame then return end
	if borderCfg and borderCfg.enabled then
		if frame.SetBackdrop then frame:SetBackdrop(nil) end
		local borderFrame = ensureBorderFrame(frame)
		if not borderFrame then return end
		local color = borderCfg.color or { 0, 0, 0, 0.8 }
		local insetVal = borderCfg.inset
		if insetVal == nil then insetVal = borderCfg.edgeSize or 1 end
		local edgeFile = (UFHelper and UFHelper.resolveBorderTexture and UFHelper.resolveBorderTexture(borderCfg.texture)) or "Interface\\Buttons\\WHITE8x8"
		borderFrame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = edgeFile,
			edgeSize = borderCfg.edgeSize or 1,
			insets = { left = insetVal, right = insetVal, top = insetVal, bottom = insetVal },
		})
		borderFrame:SetBackdropColor(0, 0, 0, 0)
		borderFrame:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
		borderFrame:Show()
	else
		if frame.SetBackdrop then frame:SetBackdrop(nil) end
		local borderFrame = frame._ufBorder
		if borderFrame then
			borderFrame:SetBackdrop(nil)
			borderFrame:Hide()
		end
	end
end

local function applyBarBackdrop(bar, cfg)
	if not bar or not bar.SetBackdrop then return end
	cfg = cfg or {}
	local bd = cfg.backdrop or {}
	if bd.enabled == false then
		bar:SetBackdrop(nil)
		return
	end
	local col = bd.color or { 0, 0, 0, 0.6 }
	bar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = nil,
		tile = false,
	})
	bar:SetBackdropColor(col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.6)
end

local function stabilizeStatusBarTexture(bar)
	if not (bar and bar.GetStatusBarTexture) then return end
	local t = bar:GetStatusBarTexture()
	if not t then return end
	if t.SetHorizTile then t:SetHorizTile(false) end
	if t.SetVertTile then t:SetVertTile(false) end
	if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
end

local function layoutTexts(bar, leftFS, centerFS, rightFS, cfg)
	if not bar then return end
	local leftCfg = (cfg and cfg.offsetLeft) or { x = 6, y = 0 }
	local centerCfg = (cfg and cfg.offsetCenter) or { x = 0, y = 0 }
	local rightCfg = (cfg and cfg.offsetRight) or { x = -6, y = 0 }
	if leftFS then
		leftFS:ClearAllPoints()
		leftFS:SetPoint("LEFT", bar, "LEFT", leftCfg.x or 0, leftCfg.y or 0)
		leftFS:SetJustifyH("LEFT")
	end
	if centerFS then
		centerFS:ClearAllPoints()
		centerFS:SetPoint("CENTER", bar, "CENTER", centerCfg.x or 0, centerCfg.y or 0)
		centerFS:SetJustifyH("CENTER")
	end
	if rightFS then
		rightFS:ClearAllPoints()
		rightFS:SetPoint("RIGHT", bar, "RIGHT", rightCfg.x or 0, rightCfg.y or 0)
		rightFS:SetJustifyH("RIGHT")
	end
end

local function setFrameLevelAbove(child, parent, offset)
	if not child or not parent then return end
	if child.SetFrameStrata and parent.GetFrameStrata then child:SetFrameStrata(parent:GetFrameStrata()) end
	if child.SetFrameLevel and parent.GetFrameLevel then child:SetFrameLevel((parent:GetFrameLevel() or 0) + (offset or 1)) end
end

local function syncTextFrameLevels(st)
	if not st then return end
	setFrameLevelAbove(st.healthTextLayer, st.health, 5)
	setFrameLevelAbove(st.powerTextLayer, st.power, 5)
end

local function hookTextFrameLevels(st)
	if not st or not hooksecurefunc then return end
	st._textLevelHooks = st._textLevelHooks or {}
	local function hookFrame(frame)
		if not frame or st._textLevelHooks[frame] then return end
		st._textLevelHooks[frame] = true
		if frame.SetFrameLevel then hooksecurefunc(frame, "SetFrameLevel", function() syncTextFrameLevels(st) end) end
		if frame.SetFrameStrata then hooksecurefunc(frame, "SetFrameStrata", function() syncTextFrameLevels(st) end) end
	end
	hookFrame(st.frame)
	hookFrame(st.barGroup)
	hookFrame(st.health)
	hookFrame(st.power)
	syncTextFrameLevels(st)
end

local function getClassColor(class)
	if not class then return nil end
	if addon.db and addon.db.ufUseCustomClassColors then
		local overrides = addon.db.ufClassColors
		local custom = overrides and overrides[class]
		if custom then
			if custom.r then return custom.r, custom.g, custom.b, custom.a or 1 end
			if custom[1] then return custom[1], custom[2], custom[3], custom[4] or 1 end
		end
	end
	local fallback = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if fallback then return fallback.r or fallback[1], fallback.g or fallback[2], fallback.b or fallback[3], fallback.a or fallback[4] or 1 end
	return nil
end

local function selectionHasAny(selection)
	if type(selection) ~= "table" then return false end
	for _, value in pairs(selection) do
		if value then return true end
	end
	return false
end

local function selectionContains(selection, key)
	if type(selection) ~= "table" or key == nil then return false end
	if selection[key] == true then return true end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value == key then return true end
		end
	end
	return false
end

local function unpackColor(color, fallback)
	if not color then color = fallback end
	if not color then return 1, 1, 1, 1 end
	if color.r then return color.r, color.g, color.b, color.a or 1 end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local function selectionMode(selection)
	if type(selection) ~= "table" then return "all" end
	if selectionHasAny(selection) then return "some" end
	return "none"
end

local function textModeUsesPercent(mode)
	return type(mode) == "string" and mode:find("PERCENT", 1, true) ~= nil
end

local function getHealthPercent(unit, cur, maxv)
	if issecretvalue and ((cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv))) then return nil end
	if addon.functions and addon.functions.GetHealthPercent then return addon.functions.GetHealthPercent(unit, cur, maxv, true) end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function getPowerPercent(unit, powerEnum, cur, maxv)
	if issecretvalue and ((cur and issecretvalue(cur)) or (maxv and issecretvalue(maxv))) then return nil end
	if addon.functions and addon.functions.GetPowerPercent then return addon.functions.GetPowerPercent(unit, powerEnum, cur, maxv, true) end
	if maxv and maxv > 0 then return (cur or 0) / maxv * 100 end
	return nil
end

local function getSafeLevelText(unit, hideClassText)
	if not unit then return "??" end
	if UnitLevel then
		local lvl = UnitLevel(unit)
		if issecretvalue and issecretvalue(lvl) then return "??" end
		if UFHelper and UFHelper.getUnitLevelText then return UFHelper.getUnitLevelText(unit, lvl, hideClassText) end
		lvl = tonumber(lvl) or 0
		if lvl > 0 then return tostring(lvl) end
	end
	if UFHelper and UFHelper.getUnitLevelText then return UFHelper.getUnitLevelText(unit, nil, hideClassText) end
	return "??"
end

local function getUnitRoleKey(unit)
	local roleEnum
	if UnitGroupRolesAssignedEnum then roleEnum = UnitGroupRolesAssignedEnum(unit) end
	if roleEnum and Enum and Enum.LFGRole then
		if roleEnum == Enum.LFGRole.Tank then return "TANK" end
		if roleEnum == Enum.LFGRole.Healer then return "HEALER" end
		if roleEnum == Enum.LFGRole.Damage then return "DAMAGER" end
	end
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
	return "NONE"
end

local function getPlayerSpecId()
	if not GetSpecialization then return nil end
	local specIndex = GetSpecialization()
	if not specIndex then return nil end
	if GetSpecializationInfo then
		local specId = GetSpecializationInfo(specIndex)
		return specId
	end
	return nil
end

local function shouldShowPowerForUnit(pcfg, unit)
	if not pcfg then return true end
	local roleMode = selectionMode(pcfg.showRoles)
	local specMode = selectionMode(pcfg.showSpecs)

	if roleMode == "some" then
		local roleKey = getUnitRoleKey(unit)
		return selectionContains(pcfg.showRoles, roleKey)
	end

	if roleMode == "none" then
		if specMode ~= "some" then return false end
		local specId = getPlayerSpecId()
		if not specId then return true end
		return selectionContains(pcfg.showSpecs, specId)
	end

	-- roleMode == "all"
	if specMode == "some" then
		local specId = getPlayerSpecId()
		if not specId then return true end
		return selectionContains(pcfg.showSpecs, specId)
	end
	if specMode == "none" then return false end
	return true
end

local function canShowPowerBySelection(pcfg)
	if not pcfg then return true end
	local roleMode = selectionMode(pcfg.showRoles)
	local specMode = selectionMode(pcfg.showSpecs)
	if roleMode == "some" then return true end
	if roleMode == "none" then return specMode == "some" end
	-- roleMode == "all"
	if specMode == "none" then return false end
	return true
end

local function isEditModeActive()
	local lib = addon.EditModeLib
	return lib and lib.IsInEditMode and lib:IsInEditMode()
end

-- -----------------------------------------------------------------------------
-- Defaults / DB helpers
-- -----------------------------------------------------------------------------

local DEFAULTS = {
	party = {
		enabled = false,
		showPlayer = false,
		showSolo = false,
		width = 140,
		height = 30,
		powerHeight = 6,
		spacing = 4,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		growth = "DOWN", -- DOWN or RIGHT
		border = {
			enabled = true,
			texture = "DEFAULT",
			color = { 0, 0, 0, 0.8 },
			edgeSize = 1,
			inset = 0,
		},
		highlight = {
			enabled = false,
			mouseover = true,
			aggro = false,
			texture = "DEFAULT",
			size = 2,
			color = { 1, 0, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			useCustomColor = false,
			useClassColor = false,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbEnabled = true,
			absorbUseCustomColor = false,
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbTexture = "SOLID",
			absorbReverseFill = false,
			useAbsorbGlow = true,
			healAbsorbEnabled = true,
			healAbsorbUseCustomColor = false,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "PERCENT",
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		power = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 10,
			fontOutline = "OUTLINE",
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "NONE",
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 6, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -6, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		text = {
			nameMaxChars = 18,
			showHealthPercent = true,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 12,
			fontOutline = "OUTLINE",
			nameOffset = { x = 6, y = 0 },
		},
		status = {
			nameColorMode = "CLASS", -- CLASS or CUSTOM
			nameColor = { 1, 1, 1, 1 },
			levelEnabled = true,
			hideLevelAtMax = false,
			levelColorMode = "CUSTOM", -- CUSTOM or CLASS
			levelColor = { 1, 0.85, 0, 1 },
			levelAnchor = "RIGHT",
			levelOffset = { x = -6, y = 0 },
			leaderIcon = {
				enabled = true,
				size = 12,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 2,
				y = -2,
			},
			assistIcon = {
				enabled = true,
				size = 12,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 18,
				y = -2,
			},
		},
		roleIcon = {
			enabled = true,
			size = 14,
			point = "LEFT",
			relativePoint = "LEFT",
			x = 2,
			y = 0,
			spacing = 2,
			style = "TINY",
			showRoles = { TANK = true, HEALER = true, DAMAGER = true },
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "TOPLEFT",
				x = 0,
				y = 4,
				showTooltip = true,
				showCooldown = true,
			},
			debuff = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "BOTTOMLEFT",
				x = 0,
				y = -4,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 16,
				perRow = 6,
				max = 4,
				spacing = 2,
				anchorPoint = "TOPRIGHT",
				x = 0,
				y = 4,
				showTooltip = true,
				showCooldown = true,
			},
		},
	},
	raid = {
		enabled = false,
		width = 100,
		height = 24,
		powerHeight = 5,
		spacing = 3,
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		relativeTo = "UIParent",
		x = 500,
		y = -300,
		groupBy = "GROUP",
		groupingOrder = "1,2,3,4,5,6,7,8",
		sortMethod = "INDEX",
		sortDir = "ASC",
		unitsPerColumn = 5,
		maxColumns = 8,
		growth = "RIGHT", -- RIGHT or DOWN
		columnSpacing = 8,
		border = {
			enabled = true,
			texture = "DEFAULT",
			color = { 0, 0, 0, 0.8 },
			edgeSize = 1,
			inset = 0,
		},
		highlight = {
			enabled = false,
			mouseover = true,
			aggro = false,
			texture = "DEFAULT",
			size = 2,
			color = { 1, 0, 0, 1 },
		},
		health = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 11,
			fontOutline = "OUTLINE",
			useCustomColor = false,
			useClassColor = false,
			color = { 0.0, 0.8, 0.0, 1 },
			absorbEnabled = true,
			absorbUseCustomColor = false,
			absorbColor = { 0.85, 0.95, 1.0, 0.7 },
			absorbTexture = "SOLID",
			absorbReverseFill = false,
			useAbsorbGlow = true,
			healAbsorbEnabled = true,
			healAbsorbUseCustomColor = false,
			healAbsorbColor = { 1.0, 0.3, 0.3, 0.7 },
			healAbsorbTexture = "SOLID",
			healAbsorbReverseFill = true,
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "NONE",
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -5, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		power = {
			texture = "DEFAULT",
			font = nil,
			fontSize = 9,
			fontOutline = "OUTLINE",
			textLeft = "NONE",
			textCenter = "NONE",
			textRight = "NONE",
			textDelimiter = " ",
			textDelimiterSecondary = " ",
			textDelimiterTertiary = " ",
			useShortNumbers = true,
			hidePercentSymbol = false,
			offsetLeft = { x = 5, y = 0 },
			offsetCenter = { x = 0, y = 0 },
			offsetRight = { x = -5, y = 0 },
			backdrop = { enabled = true, color = { 0, 0, 0, 0.6 } },
		},
		text = {
			nameMaxChars = 12,
			showHealthPercent = false,
			showPowerPercent = false,
			useClassColor = true,
			font = nil,
			fontSize = 10,
			fontOutline = "OUTLINE",
			nameOffset = { x = 5, y = 0 },
		},
		status = {
			nameColorMode = "CLASS",
			nameColor = { 1, 1, 1, 1 },
			levelEnabled = true,
			hideLevelAtMax = false,
			levelColorMode = "CUSTOM",
			levelColor = { 1, 0.85, 0, 1 },
			levelAnchor = "RIGHT",
			levelOffset = { x = -4, y = 0 },
			leaderIcon = {
				enabled = true,
				size = 10,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 1,
				y = -1,
			},
			assistIcon = {
				enabled = true,
				size = 10,
				point = "TOPLEFT",
				relativePoint = "TOPLEFT",
				x = 14,
				y = -1,
			},
		},
		roleIcon = {
			enabled = true,
			size = 12,
			point = "LEFT",
			relativePoint = "LEFT",
			x = 2,
			y = 0,
			spacing = 2,
			style = "TINY",
			showRoles = { TANK = true, HEALER = true, DAMAGER = true },
		},
		auras = {
			enabled = false,
			buff = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "TOPLEFT",
				x = 0,
				y = 3,
				showTooltip = true,
				showCooldown = true,
			},
			debuff = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 6,
				spacing = 2,
				anchorPoint = "BOTTOMLEFT",
				x = 0,
				y = -3,
				showTooltip = true,
				showCooldown = true,
			},
			externals = {
				enabled = false,
				size = 14,
				perRow = 6,
				max = 4,
				spacing = 2,
				anchorPoint = "TOPRIGHT",
				x = 0,
				y = 3,
				showTooltip = true,
				showCooldown = true,
			},
		},
	},
}

local DB

local function ensureDB()
	addon.db = addon.db or {}
	addon.db.ufGroupFrames = addon.db.ufGroupFrames or {}
	local db = addon.db.ufGroupFrames
	if db._eqolInited then
		DB = db
		return db
	end
	for kind, def in pairs(DEFAULTS) do
		db[kind] = db[kind] or {}
		local t = db[kind]
		for k, v in pairs(def) do
			if t[k] == nil then
				if type(v) == "table" then
					if addon.functions and addon.functions.copyTable then
						t[k] = addon.functions.copyTable(v)
					else
						t[k] = CopyTable(v)
					end
				else
					t[k] = v
				end
			end
		end
	end
	db._eqolInited = true
	DB = db
	return db
end

local function getCfg(kind)
	local db = DB or ensureDB()
	return db[kind] or DEFAULTS[kind]
end

local function isFeatureEnabled() return addon.db and addon.db.ufEnableGroupFrames == true end

-- Expose config for Settings / Edit Mode integration
function GF:GetConfig(kind) return getCfg(kind) end

function GF:IsFeatureEnabled() return isFeatureEnabled() end

function GF:EnsureDB() return ensureDB() end

-- -----------------------------------------------------------------------------
-- Internal state
-- -----------------------------------------------------------------------------

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}
GF._pendingRefresh = GF._pendingRefresh or false
GF._pendingDisable = GF._pendingDisable or false

local registerFeatureEvents
local unregisterFeatureEvents

local function getUnit(self)
	-- Secure headers set the "unit" attribute on the button.
	return (self and (self.unit or (self.GetAttribute and self:GetAttribute("unit"))))
end

local function getState(self)
	local st = self and self._eqolUFState
	if not st then
		st = { frame = self }
		self._eqolUFState = st
	end
	return st
end

local function updateButtonConfig(self, cfg)
	if not self then return end
	cfg = cfg or self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	self._eqolCfg = cfg
	local st = getState(self)
	if not (st and cfg) then return end

	local tc = cfg.text or {}
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	local ac = cfg.auras
	local scfg = cfg.status or {}

	st._wantsName = true
	st._wantsLevel = scfg.levelEnabled ~= false
	st._wantsAbsorb = (hc.absorbEnabled ~= false) or (hc.healAbsorbEnabled ~= false)

	local wantsPower = true
	local powerHeight = cfg.powerHeight
	if powerHeight ~= nil and tonumber(powerHeight) <= 0 then wantsPower = false end
	if wantsPower and not canShowPowerBySelection(pcfg) then wantsPower = false end
	st._wantsPower = wantsPower

	local wantsAuras = false
	if ac then
		if ac.enabled == true then
			wantsAuras = true
		elseif ac.enabled == false then
			wantsAuras = false
		else
			wantsAuras = (ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled) or false
		end
	end
	st._wantsAuras = wantsAuras
end

local auraUpdateQueue = {}
local auraUpdateScheduled = false

local function processAuraQueue()
	auraUpdateScheduled = false
	for btn, info in pairs(auraUpdateQueue) do
		auraUpdateQueue[btn] = nil
		if btn and btn._eqolUFState then
			local st = btn._eqolUFState
			local updateInfo = info or st._auraPendingInfo
			st._auraPendingInfo = nil
			GF:UpdateAuras(btn, updateInfo)
		end
	end
end

function GF:RequestAuraUpdate(self, updateInfo)
	local st = getState(self)
	if not st then return end
	if updateInfo ~= nil then st._auraPendingInfo = updateInfo end
	auraUpdateQueue[self] = st._auraPendingInfo
	if not auraUpdateScheduled then
		auraUpdateScheduled = true
		if C_Timer and C_Timer.After then
			C_Timer.After(0, processAuraQueue)
		else
			processAuraQueue()
		end
	end
end

function GF:CacheUnitStatic(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end

	local guid = UnitGUID and UnitGUID(unit)
	if st._guid == guid and st._unitToken == unit then return end
	st._guid = guid
	st._unitToken = unit

	if guid and UnitIsPlayer and UnitIsPlayer(unit) and UnitClass then
		local _, class = UnitClass(unit)
		st._class = class
		if class then
			st._classR, st._classG, st._classB, st._classA = getClassColor(class)
		else
			st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
		end
	else
		st._class = nil
		st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
	end
end

-- -----------------------------------------------------------------------------
-- Unit button construction
-- -----------------------------------------------------------------------------
function GF:BuildButton(self)
	if not self then return end
	local st = getState(self)

	local kind = self._eqolGroupKind or "party"
	local cfg = getCfg(kind)
	self._eqolCfg = cfg
	updateButtonConfig(self, cfg)
	GF:LayoutAuras(self)
	local hc = cfg.health or {}
	local pcfg = cfg.power or {}
	local tc = cfg.text or {}

	-- Basic secure click setup (safe even if header also sets it).
	if self.RegisterForClicks then self:RegisterForClicks("AnyUp") end
	-- Setting protected attributes is combat-locked. The header's initialConfigFunction
	-- already sets these, so we only do it out of combat as a safety net.
	if (not InCombatLockdown or not InCombatLockdown()) and self.SetAttribute then
		self:SetAttribute("*type1", "target")
		self:SetAttribute("*type2", "togglemenu")
	end

	-- Clique compatibility (your UF.lua already does this too).
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[self] = true

	-- Root visual group (mirrors your UF.lua structure)
	if not st.barGroup then
		st.barGroup = CreateFrame("Frame", nil, self, "BackdropTemplate")
		st.barGroup:EnableMouse(false)
	end
	st.barGroup:SetAllPoints(self)
	-- Border handling (same pattern as UF.lua: border lives on a dedicated child frame)
	setBackdrop(st.barGroup, cfg.border)

	-- Health bar
	if not st.health then
		st.health = CreateFrame("StatusBar", nil, st.barGroup, "BackdropTemplate")
		st.health:SetMinMaxValues(0, 1)
		st.health:SetValue(0)
		if st.health.SetStatusBarDesaturated then st.health:SetStatusBarDesaturated(true) end
	end
	if st.health.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
		st.health:SetStatusBarTexture(UFHelper.resolveTexture(hc.texture))
		if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.health, "HEALTH", hc.texture, hc) end
	end
	stabilizeStatusBarTexture(st.health)
	applyBarBackdrop(st.health, hc)

	-- Absorb overlays
	if not st.absorb then
		st.absorb = CreateFrame("StatusBar", nil, st.health, "BackdropTemplate")
		st.absorb:SetMinMaxValues(0, 1)
		st.absorb:SetValue(0)
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		st.absorb:Hide()
	end
	if not st.healAbsorb then
		st.healAbsorb = CreateFrame("StatusBar", nil, st.health, "BackdropTemplate")
		st.healAbsorb:SetMinMaxValues(0, 1)
		st.healAbsorb:SetValue(0)
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
		st.healAbsorb:Hide()
	end
	if not st.overAbsorbGlow then
		st.overAbsorbGlow = st.health:CreateTexture(nil, "ARTWORK", "OverAbsorbGlowTemplate")
		if not st.overAbsorbGlow then st.overAbsorbGlow = st.health:CreateTexture(nil, "ARTWORK") end
		if st.overAbsorbGlow then
			st.overAbsorbGlow:SetTexture(798066)
			st.overAbsorbGlow:SetBlendMode("ADD")
			st.overAbsorbGlow:SetAlpha(0.8)
			st.overAbsorbGlow:Hide()
		end
	end
	if st.absorb then st.absorb.overAbsorbGlow = st.overAbsorbGlow end

	-- Power bar
	if not st.power then
		st.power = CreateFrame("StatusBar", nil, st.barGroup, "BackdropTemplate")
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
	end
	if st.power.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then st.power:SetStatusBarTexture(UFHelper.resolveTexture(pcfg.texture)) end
	applyBarBackdrop(st.power, pcfg)
	if st.power.SetStatusBarDesaturated then st.power:SetStatusBarDesaturated(false) end

	-- Text layers (kept as separate frames so we can force proper frame levels)
	if not st.healthTextLayer then
		st.healthTextLayer = CreateFrame("Frame", nil, st.health)
		st.healthTextLayer:SetAllPoints(st.health)
	end
	if not st.powerTextLayer then
		st.powerTextLayer = CreateFrame("Frame", nil, st.power)
		st.powerTextLayer:SetAllPoints(st.power)
	end

	-- Mirror your UF.lua text triplets (Left/Center/Right) so you can expand easily.
	if not st.healthTextLeft then st.healthTextLeft = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextCenter then st.healthTextCenter = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.healthTextRight then st.healthTextRight = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextLeft then st.powerTextLeft = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextCenter then st.powerTextCenter = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	if not st.powerTextRight then st.powerTextRight = st.powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

	if not st.nameText then st.nameText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
	st.name = st.nameText
	if not st.levelText then st.levelText = st.healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

	local indicatorLayer = st.healthTextLayer
	if not st.leaderIcon then st.leaderIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if not st.assistIcon then st.assistIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
	if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
	if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
	if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end

	-- Apply fonts (uses your existing UFHelper logic + default font media)
	if UFHelper and UFHelper.applyFont then
		UFHelper.applyFont(st.healthTextLeft, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextCenter, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.healthTextRight, hc.font, hc.fontSize or 12, hc.fontOutline)
		UFHelper.applyFont(st.powerTextLeft, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextCenter, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.powerTextRight, pcfg.font, pcfg.fontSize or 10, pcfg.fontOutline)
		UFHelper.applyFont(st.nameText, tc.font or hc.font, tc.fontSize or hc.fontSize or 12, tc.fontOutline or hc.fontOutline)
	end

	-- Highlight style (same system as your UF.lua)
	st._highlightCfg = (UFHelper and UFHelper.buildHighlightConfig) and UFHelper.buildHighlightConfig(cfg, DEFAULTS[kind]) or nil
	if UFHelper and UFHelper.applyHighlightStyle then UFHelper.applyHighlightStyle(st, st._highlightCfg) end

	-- Layout updates on resize
	if not st._sizeHooked then
		st._sizeHooked = true
		self:HookScript("OnSizeChanged", function(btn) GF:LayoutButton(btn) end)
	end

	self:SetClampedToScreen(true)
	self:SetScript("OnMouseDown", nil) -- keep clean; secure click handles targeting.

	-- Menu function used by the secure "togglemenu" click.
	if not st._menuHooked then
		st._menuHooked = true
		self.menu = function(btn) GF:OpenUnitMenu(btn) end
	end

	hookTextFrameLevels(st)
	GF:LayoutButton(self)
end

function GF:LayoutButton(self)
	if not self then return end
	local st = getState(self)
	if not (st and st.barGroup and st.health and st.power) then return end

	local kind = self._eqolGroupKind -- set by header helper
	local cfg = self._eqolCfg or getCfg(kind or "party")
	local hc = cfg.health or {}
	local powerH = tonumber(cfg.powerHeight) or 5
	if st._powerHidden then powerH = 0 end
	local w, h = self:GetSize()
	if not w or not h then return end
	if powerH > h - 4 then powerH = math.max(3, h * 0.25) end

	st.barGroup:SetAllPoints(self)

	st.power:ClearAllPoints()
	st.power:SetPoint("BOTTOMLEFT", st.barGroup, "BOTTOMLEFT", 1, 1)
	st.power:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -1, 1)
	st.power:SetHeight(powerH)

	st.health:ClearAllPoints()
	st.health:SetPoint("TOPLEFT", st.barGroup, "TOPLEFT", 1, -1)
	st.health:SetPoint("BOTTOMRIGHT", st.barGroup, "BOTTOMRIGHT", -1, powerH + 1)

	-- Text layout (mirrors UF.lua positioning logic)
	layoutTexts(st.health, st.healthTextLeft, st.healthTextCenter, st.healthTextRight, cfg.health)
	layoutTexts(st.power, st.powerTextLeft, st.powerTextCenter, st.powerTextRight, cfg.power)

	-- Absorb overlays
	if st.absorb then
		local absorbTextureKey = hc.absorbTexture or hc.texture
		if st.absorb.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
			st.absorb:SetStatusBarTexture(UFHelper.resolveTexture(absorbTextureKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.absorb, "HEALTH", absorbTextureKey, hc) end
		end
		if st.absorb.SetStatusBarDesaturated then st.absorb:SetStatusBarDesaturated(false) end
		if UFHelper and UFHelper.applyStatusBarReverseFill then UFHelper.applyStatusBarReverseFill(st.absorb, hc.absorbReverseFill == true) end
		stabilizeStatusBarTexture(st.absorb)
		st.absorb:ClearAllPoints()
		st.absorb:SetAllPoints(st.health)
		setFrameLevelAbove(st.absorb, st.health, 1)
	end
	if st.healAbsorb then
		local healAbsorbTextureKey = hc.healAbsorbTexture or hc.texture
		if st.healAbsorb.SetStatusBarTexture and UFHelper and UFHelper.resolveTexture then
			st.healAbsorb:SetStatusBarTexture(UFHelper.resolveTexture(healAbsorbTextureKey))
			if UFHelper.configureSpecialTexture then UFHelper.configureSpecialTexture(st.healAbsorb, "HEALTH", healAbsorbTextureKey, hc) end
		end
		if st.healAbsorb.SetStatusBarDesaturated then st.healAbsorb:SetStatusBarDesaturated(false) end
		if UFHelper and UFHelper.applyStatusBarReverseFill then UFHelper.applyStatusBarReverseFill(st.healAbsorb, hc.healAbsorbReverseFill == true) end
		stabilizeStatusBarTexture(st.healAbsorb)
		st.healAbsorb:ClearAllPoints()
		st.healAbsorb:SetAllPoints(st.health)
		setFrameLevelAbove(st.healAbsorb, st.absorb or st.health, 1)
	end
	if st.overAbsorbGlow then
		st.overAbsorbGlow:ClearAllPoints()
		local glowAnchor = st.absorb or st.health
		st.overAbsorbGlow:SetPoint("TOPLEFT", glowAnchor, "TOPRIGHT", -7, 0)
		st.overAbsorbGlow:SetPoint("BOTTOMLEFT", glowAnchor, "BOTTOMRIGHT", -7, 0)
	end

	-- Name + role icon layout
	local tc = cfg.text or {}
	local rc = cfg.roleIcon or {}
	local sc = cfg.status or {}
	local rolePad = 0
	local roleEnabled = rc.enabled ~= false
	if roleEnabled and type(rc.showRoles) == "table" and not selectionHasAny(rc.showRoles) then
		roleEnabled = false
	end
	if roleEnabled then
		local indicatorLayer = st.healthTextLayer or st.health
		if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
		if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
		if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
		local size = rc.size or 14
		local point = rc.point or "LEFT"
		local relPoint = rc.relativePoint or "LEFT"
		local ox = rc.x or 2
		local oy = rc.y or 0
		st.roleIcon:ClearAllPoints()
		st.roleIcon:SetPoint(point, st.health, relPoint, ox, oy)
		st.roleIcon:SetSize(size, size)
		rolePad = size + (rc.spacing or 2)
	else
		if st.roleIcon then st.roleIcon:Hide() end
	end

	if st.nameText then
		if UFHelper and UFHelper.applyFont then
			local hc = cfg.health or {}
			UFHelper.applyFont(st.nameText, tc.font or hc.font, tc.fontSize or hc.fontSize or 12, tc.fontOutline or hc.fontOutline)
		end
		local nameOffset = tc.nameOffset or {}
		local baseOffset = (cfg.health and cfg.health.offsetLeft) or {}
		local nameX = (nameOffset.x ~= nil and nameOffset.x or baseOffset.x or 6) + rolePad
		local nameY = nameOffset.y ~= nil and nameOffset.y or baseOffset.y or 0
		local nameMaxChars = tonumber(tc.nameMaxChars) or 0
		st.nameText:ClearAllPoints()
		st.nameText:SetPoint("LEFT", st.health, "LEFT", nameX, nameY)
		if nameMaxChars <= 0 then
			st.nameText:SetPoint("RIGHT", st.health, "RIGHT", -4, nameY)
		end
		st.nameText:SetJustifyH("LEFT")
		if UFHelper and UFHelper.applyNameCharLimit then
			local nameCfg = st._nameLimitCfg or {}
			nameCfg.nameMaxChars = tc.nameMaxChars
			nameCfg.font = tc.font or hc.font
			nameCfg.fontSize = tc.fontSize or hc.fontSize or 12
			nameCfg.fontOutline = tc.fontOutline or hc.fontOutline
			st._nameLimitCfg = nameCfg
			UFHelper.applyNameCharLimit(st, nameCfg, nil)
		end
	end

	if st.levelText then
		if UFHelper and UFHelper.applyFont then
			local hc = cfg.health or {}
			local levelFont = sc.levelFont or tc.font or hc.font
			local levelFontSize = sc.levelFontSize or tc.fontSize or hc.fontSize or 12
			local levelOutline = sc.levelFontOutline or tc.fontOutline or hc.fontOutline
			UFHelper.applyFont(st.levelText, levelFont, levelFontSize, levelOutline)
		end
		local anchor = sc.levelAnchor or "RIGHT"
		local levelOffset = sc.levelOffset or {}
		st.levelText:ClearAllPoints()
		st.levelText:SetPoint(anchor, st.health, anchor, levelOffset.x or 0, levelOffset.y or 0)
		st.levelText:SetJustifyH(anchor == "LEFT" and "LEFT" or (anchor == "CENTER" and "CENTER" or "RIGHT"))
	end

	if st.leaderIcon then
		local lc = sc.leaderIcon or {}
		local indicatorLayer = st.healthTextLayer or st.health
		if st.leaderIcon.GetParent and st.leaderIcon:GetParent() ~= indicatorLayer then st.leaderIcon:SetParent(indicatorLayer) end
		if st.leaderIcon.SetDrawLayer then st.leaderIcon:SetDrawLayer("OVERLAY", 7) end
		if lc.enabled ~= false then
			local size = lc.size or 12
			st.leaderIcon:ClearAllPoints()
			st.leaderIcon:SetPoint(lc.point or "TOPLEFT", st.health, lc.relativePoint or "TOPLEFT", lc.x or 0, lc.y or 0)
			st.leaderIcon:SetSize(size, size)
		else
			st.leaderIcon:Hide()
		end
	end

	if st.assistIcon then
		local acfg = sc.assistIcon or {}
		local indicatorLayer = st.healthTextLayer or st.health
		if st.assistIcon.GetParent and st.assistIcon:GetParent() ~= indicatorLayer then st.assistIcon:SetParent(indicatorLayer) end
		if st.assistIcon.SetDrawLayer then st.assistIcon:SetDrawLayer("OVERLAY", 7) end
		if acfg.enabled ~= false then
			local size = acfg.size or 12
			st.assistIcon:ClearAllPoints()
			st.assistIcon:SetPoint(acfg.point or "TOPLEFT", st.health, acfg.relativePoint or "TOPLEFT", acfg.x or 0, acfg.y or 0)
			st.assistIcon:SetSize(size, size)
		else
			st.assistIcon:Hide()
		end
	end

	-- Keep text above bars
	local baseLevel = (st.barGroup:GetFrameLevel() or 0)
	st.health:SetFrameLevel(baseLevel + 1)
	st.power:SetFrameLevel(baseLevel + 1)
	syncTextFrameLevels(st)

	-- Pixel quantization caches (reset on layout changes)
	st._lastHealthPx = nil
	st._lastHealthBarW = nil
	st._lastPowerPx = nil
	st._lastPowerBarW = nil
end

-- -----------------------------------------------------------------------------
-- Updates
-- -----------------------------------------------------------------------------

local function resolveAuraGrowth(anchorPoint, growthX, growthY)
	local anchor = (anchorPoint or "TOPLEFT"):upper()
	if not growthX then
		if anchor:find("RIGHT", 1, true) then
			growthX = "LEFT"
		else
			growthX = "RIGHT"
		end
	end
	if not growthY then
		if anchor:find("BOTTOM", 1, true) then
			growthY = "UP"
		else
			growthY = "DOWN"
		end
	end
	return anchor, growthX, growthY
end

local function ensureAuraContainer(st, key)
	if not st then return nil end
	if not st[key] then
		st[key] = CreateFrame("Frame", nil, st.barGroup or st.frame)
		st[key]:EnableMouse(false)
	end
	return st[key]
end

local function hideAuraButtons(buttons, startIndex)
	if not buttons then return end
	for i = startIndex, #buttons do
		local btn = buttons[i]
		if btn then btn:Hide() end
	end
end

local function positionAuraButton(btn, container, anchorPoint, index, perRow, size, spacing, growthX, growthY)
	if not (btn and container) then return end
	perRow = perRow or 1
	if perRow < 1 then perRow = 1 end
	local col = (index - 1) % perRow
	local row = math.floor((index - 1) / perRow)
	local xSign = (growthX == "LEFT") and -1 or 1
	local ySign = (growthY == "UP") and 1 or -1
	local stepX = (size + spacing) * xSign
	local stepY = (size + spacing) * ySign
	btn:ClearAllPoints()
	btn:SetPoint(anchorPoint, container, anchorPoint, col * stepX, row * stepY)
end

local function resolveRoleAtlas(roleKey, style)
	if roleKey == "NONE" then return nil end
	if style == "CIRCLE" then
		if GetMicroIconForRole then
			return GetMicroIconForRole(roleKey)
		end
		if roleKey == "TANK" then return "UI-LFG-RoleIcon-Tank-Micro-GroupFinder" end
		if roleKey == "HEALER" then return "UI-LFG-RoleIcon-Healer-Micro-GroupFinder" end
		if roleKey == "DAMAGER" then return "UI-LFG-RoleIcon-DPS-Micro-GroupFinder" end
	end
	if roleKey == "TANK" then return "roleicon-tiny-tank" end
	if roleKey == "HEALER" then return "roleicon-tiny-healer" end
	if roleKey == "DAMAGER" then return "roleicon-tiny-dps" end
	return nil
end

function GF:UpdateRoleIcon(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local rc = cfg and cfg.roleIcon or {}
	if rc.enabled == false then
		if st.roleIcon then st.roleIcon:Hide() end
		return
	end
	local indicatorLayer = st.healthTextLayer or st.health or st.barGroup or st.frame
	if not st.roleIcon then st.roleIcon = indicatorLayer:CreateTexture(nil, "OVERLAY", nil, 7) end
	if st.roleIcon.GetParent and st.roleIcon:GetParent() ~= indicatorLayer then st.roleIcon:SetParent(indicatorLayer) end
	if st.roleIcon.SetDrawLayer then st.roleIcon:SetDrawLayer("OVERLAY", 7) end
	local roleKey = getUnitRoleKey(unit)
	if roleKey == "NONE" and isEditModeActive() then roleKey = "DAMAGER" end
	local selection = rc.showRoles
	if type(selection) == "table" then
		if not selectionHasAny(selection) then
			st._lastRoleAtlas = nil
			st.roleIcon:Hide()
			return
		end
		if roleKey == "NONE" or not selectionContains(selection, roleKey) then
			st._lastRoleAtlas = nil
			st.roleIcon:Hide()
			return
		end
	end
	local style = rc.style or "TINY"
	local atlas = resolveRoleAtlas(roleKey, style)
	if atlas then
		if st._lastRoleAtlas ~= atlas then
			st._lastRoleAtlas = atlas
			st.roleIcon:SetAtlas(atlas, true)
		end
		st.roleIcon:Show()
	else
		st._lastRoleAtlas = nil
		st.roleIcon:Hide()
	end
end

local function getUnitRaidRole(unit)
	if not (UnitInRaid and GetRaidRosterInfo and unit) then return nil end
	local raidID = UnitInRaid(unit)
	if not raidID then return nil end
	local role = select(10, GetRaidRosterInfo(raidID))
	return role
end

function GF:UpdateGroupIcons(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and st.leaderIcon and st.assistIcon) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local scfg = cfg and cfg.status or {}

	-- Leader icon
	local lc = scfg.leaderIcon or {}
	if lc.enabled == false then
		st.leaderIcon:Hide()
	else
		local showLeader = unit and UnitIsGroupLeader and UnitIsGroupLeader(unit)
		if not showLeader and isEditModeActive() then showLeader = true end
		if showLeader then
			st.leaderIcon:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon", true)
			st.leaderIcon:Show()
		else
			st.leaderIcon:Hide()
		end
	end

	-- Assist icon (group assistant or MAINASSIST raid role)
	local acfg = scfg.assistIcon or {}
	if acfg.enabled == false then
		st.assistIcon:Hide()
	else
		local showAssist = unit and UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
		if not showAssist then
			local raidRole = getUnitRaidRole(unit)
			showAssist = raidRole == "MAINASSIST"
		end
		if not showAssist and isEditModeActive() then showAssist = true end
		if showAssist then
			st.assistIcon:SetAtlas("RaidFrame-Icon-MainAssist", true)
			st.assistIcon:Show()
		else
			st.assistIcon:Hide()
		end
	end
end

local function externalAuraPredicate(aura, unit)
	if not (aura and aura.sourceUnit) then return false end
	if issecretvalue and (issecretvalue(aura.sourceUnit) or issecretvalue(unit)) then return false end
	return aura.sourceUnit ~= unit
end

local AURA_TYPE_META = {
	buff = {
		containerKey = "buffContainer",
		buttonsKey = "buffButtons",
		filter = "HELPFUL",
		isDebuff = false,
	},
	debuff = {
		containerKey = "debuffContainer",
		buttonsKey = "debuffButtons",
		filter = "HARMFUL",
		isDebuff = true,
	},
	externals = {
		containerKey = "externalContainer",
		buttonsKey = "externalButtons",
		filter = "HELPFUL",
		isDebuff = false,
		predicate = externalAuraPredicate,
	},
}

local SAMPLE_BUFF_ICONS = { 136243, 135940, 136085, 136097, 136116, 136048, 135932, 136108 }
local SAMPLE_DEBUFF_ICONS = { 136207, 136160, 136128, 135804, 136168, 132104, 136118, 136214 }
local SAMPLE_EXTERNAL_ICONS = { 135936, 136073, 135907, 135940, 136090, 135978 }
local SAMPLE_DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison" }

local function getSampleAuraData(kindKey, index, now)
	local duration
	if index % 3 == 0 then
		duration = 120
	elseif index % 3 == 1 then
		duration = 30
	else
		duration = 0
	end
	local expiration = duration > 0 and (now + duration) or nil
	local stacks
	if index % 5 == 0 then
		stacks = 5
	elseif index % 3 == 0 then
		stacks = 3
	end
	local iconList = SAMPLE_BUFF_ICONS
	if kindKey == "debuff" then
		iconList = SAMPLE_DEBUFF_ICONS
	elseif kindKey == "externals" then
		iconList = SAMPLE_EXTERNAL_ICONS
	end
	local icon = iconList[((index - 1) % #iconList) + 1]
	local dispelName = kindKey == "debuff" and SAMPLE_DISPEL_TYPES[((index - 1) % #SAMPLE_DISPEL_TYPES) + 1] or nil
	local canActivePlayerDispel = dispelName == "Magic"
	local base = (kindKey == "buff" and -100000) or (kindKey == "debuff" and -200000) or -300000
	local auraId = base - index
	return {
		auraInstanceID = auraId,
		icon = icon,
		isHelpful = kindKey ~= "debuff",
		isHarmful = kindKey == "debuff",
		applications = stacks,
		duration = duration,
		expirationTime = expiration,
		dispelName = dispelName,
		canActivePlayerDispel = canActivePlayerDispel,
		isSample = true,
	}
end

local function getSampleStyle(st, kindKey, style)
	st._auraSampleStyle = st._auraSampleStyle or {}
	local sample = st._auraSampleStyle[kindKey]
	if sample and sample._src == style then return sample end
	sample = {}
	for key, value in pairs(style or {}) do
		sample[key] = value
	end
	sample.showTooltip = false
	sample._src = style
	st._auraSampleStyle[kindKey] = sample
	return sample
end

function GF:LayoutAuras(self)
	local st = getState(self)
	if not st then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras
	if not ac or ac.enabled == false then return end

	st._auraLayout = st._auraLayout or {}
	st._auraLayoutKey = st._auraLayoutKey or {}
	st._auraStyle = st._auraStyle or {}

	local parent = st.barGroup or st.frame

	for kindKey, meta in pairs(AURA_TYPE_META) do
		local typeCfg = ac[kindKey] or {}
		if typeCfg.enabled == false then
			local container = st[meta.containerKey]
			if container then container:Hide() end
			hideAuraButtons(st[meta.buttonsKey], 1)
			st._auraLayout[kindKey] = nil
			st._auraLayoutKey[kindKey] = nil
		else
			local anchorPoint, growthX, growthY = resolveAuraGrowth(typeCfg.anchorPoint, typeCfg.growthX, typeCfg.growthY)
			local size = tonumber(typeCfg.size) or 16
			local spacing = tonumber(typeCfg.spacing) or 2
			local perRow = tonumber(typeCfg.perRow) or tonumber(typeCfg.max) or 6
			if perRow < 1 then perRow = 1 end
			local maxCount = tonumber(typeCfg.max) or perRow
			if maxCount < 0 then maxCount = 0 end
			local x = tonumber(typeCfg.x) or 0
			local y = tonumber(typeCfg.y) or 0

			local key = anchorPoint .. "|" .. growthX .. "|" .. growthY .. "|" .. size .. "|" .. spacing .. "|" .. perRow .. "|" .. maxCount .. "|" .. x .. "|" .. y
			local layout = st._auraLayout[kindKey] or {}
			layout.anchorPoint = anchorPoint
			layout.growthX = growthX
			layout.growthY = growthY
			layout.size = size
			layout.spacing = spacing
			layout.perRow = perRow
			layout.maxCount = maxCount
			layout.x = x
			layout.y = y
			layout.key = key
			st._auraLayout[kindKey] = layout

			if st._auraLayoutKey[kindKey] ~= key then
				st._auraLayoutKey[kindKey] = key
				local container = ensureAuraContainer(st, meta.containerKey)
				if container then
					container:ClearAllPoints()
					container:SetPoint(anchorPoint, parent, anchorPoint, x, y)
				end
				local buttons = st[meta.buttonsKey]
				if buttons and container then
					for i, btn in ipairs(buttons) do
						positionAuraButton(btn, container, anchorPoint, i, perRow, size, spacing, growthX, growthY)
						btn._auraLayoutKey = key
					end
				end
			end

			local style = st._auraStyle[kindKey] or {}
			style.size = size
			style.padding = spacing
			style.showTooltip = typeCfg.showTooltip ~= false
			style.showCooldown = typeCfg.showCooldown ~= false
			style.countFont = typeCfg.countFont
			style.countFontSize = typeCfg.countFontSize
			style.countFontOutline = typeCfg.countFontOutline
			style.cooldownFontSize = typeCfg.cooldownFontSize
			st._auraStyle[kindKey] = style
		end
	end
end

local function updateAuraType(self, unit, st, ac, kindKey)
	local meta = AURA_TYPE_META[kindKey]
	if not meta then return end
	local typeCfg = ac and ac[kindKey] or {}
	if typeCfg.enabled == false then
		local container = st[meta.containerKey]
		if container then container:Hide() end
		hideAuraButtons(st[meta.buttonsKey], 1)
		return
	end

	local layout = st._auraLayout and st._auraLayout[kindKey]
	local style = st._auraStyle and st._auraStyle[kindKey]
	if not (layout and style) then return end

	local container = ensureAuraContainer(st, meta.containerKey)
	if not container then return end
	container:Show()

	local buttons = st[meta.buttonsKey]
	if not buttons then
		buttons = {}
		st[meta.buttonsKey] = buttons
	end

	local filter = meta.filter
	local shown = 0
	local maxCount = layout.maxCount or 0
	local scanIndex = 1
	while shown < maxCount do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, scanIndex, filter)
		if not aura then break end
		scanIndex = scanIndex + 1
		if meta.predicate and not meta.predicate(aura, unit) then
			-- skip non-matching aura
		else
			shown = shown + 1
			local btn = AuraUtil.ensureAuraButton(container, buttons, shown, style)
			AuraUtil.applyAuraToButton(btn, aura, style, meta.isDebuff, unit)
			if btn._auraLayoutKey ~= layout.key then
				positionAuraButton(btn, container, layout.anchorPoint, shown, layout.perRow, layout.size, layout.spacing, layout.growthX, layout.growthY)
				btn._auraLayoutKey = layout.key
			end
			btn:Show()
		end
	end

	hideAuraButtons(buttons, shown + 1)
end

function GF:UpdateAuras(self, updateInfo)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local unit = getUnit(self)
	if isEditModeActive() then
		GF:UpdateSampleAuras(self)
		return
	end
	if not (unit and C_UnitAuras) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras or {}
	local wantsAuras = st._wantsAuras
	if wantsAuras == nil then wantsAuras = (ac and ac.enabled ~= false and ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled))) or false end
	if wantsAuras == false or ac.enabled == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		return
	end

	st._auraSampleActive = nil

	if not st._auraLayout then GF:LayoutAuras(self) end

	updateAuraType(self, unit, st, ac, "buff")
	updateAuraType(self, unit, st, ac, "debuff")
	updateAuraType(self, unit, st, ac, "externals")
end

function GF:UpdateSampleAuras(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and AuraUtil) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local ac = cfg and cfg.auras or {}
	local wantsAuras = st._wantsAuras
	if wantsAuras == nil then wantsAuras = (ac and ac.enabled ~= false and ((ac.buff and ac.buff.enabled) or (ac.debuff and ac.debuff.enabled) or (ac.externals and ac.externals.enabled))) or false end
	if wantsAuras == false or ac.enabled == false then
		if st.buffContainer then st.buffContainer:Hide() end
		if st.debuffContainer then st.debuffContainer:Hide() end
		if st.externalContainer then st.externalContainer:Hide() end
		hideAuraButtons(st.buffButtons, 1)
		hideAuraButtons(st.debuffButtons, 1)
		hideAuraButtons(st.externalButtons, 1)
		st._auraSampleActive = nil
		return
	end

	if not st._auraLayout then GF:LayoutAuras(self) end

	local function updateSampleType(kindKey)
		local meta = AURA_TYPE_META[kindKey]
		if not meta then return end
		local typeCfg = ac and ac[kindKey] or {}
		if typeCfg.enabled == false then
			local container = st[meta.containerKey]
			if container then container:Hide() end
			hideAuraButtons(st[meta.buttonsKey], 1)
			return
		end

		local layout = st._auraLayout and st._auraLayout[kindKey]
		local style = st._auraStyle and st._auraStyle[kindKey]
		if not (layout and style) then return end

		local container = ensureAuraContainer(st, meta.containerKey)
		if not container then return end
		container:Show()

		local buttons = st[meta.buttonsKey]
		if not buttons then
			buttons = {}
			st[meta.buttonsKey] = buttons
		end

		local iconList = SAMPLE_BUFF_ICONS
		if kindKey == "debuff" then
			iconList = SAMPLE_DEBUFF_ICONS
		elseif kindKey == "externals" then
			iconList = SAMPLE_EXTERNAL_ICONS
		end
		local maxCount = layout.maxCount or 0
		local shown = math.min(maxCount, #iconList)
		local now = GetTime and GetTime() or 0
		local sampleStyle = getSampleStyle(st, kindKey, style)
		local unitToken = unit or "player"
		for i = 1, shown do
			local aura = getSampleAuraData(kindKey, i, now)
			local btn = AuraUtil.ensureAuraButton(container, buttons, i, sampleStyle)
			AuraUtil.applyAuraToButton(btn, aura, sampleStyle, meta.isDebuff, unitToken)
			if btn._auraLayoutKey ~= layout.key then
				positionAuraButton(btn, container, layout.anchorPoint, i, layout.perRow, layout.size, layout.spacing, layout.growthX, layout.growthY)
				btn._auraLayoutKey = layout.key
			end
			btn:Show()
		end
		hideAuraButtons(buttons, shown + 1)
	end

	updateSampleType("buff")
	updateSampleType("debuff")
	updateSampleType("externals")
	st._auraSampleActive = true
end

function GF:UpdateName(self)
	local unit = getUnit(self)
	local st = getState(self)
	local fs = st and (st.nameText or st.name)
	if not (unit and st and fs) then return end
	if st._wantsName == false then return end
	if UnitExists and not UnitExists(unit) then
		fs:SetText("")
		return
	end
	local name = UnitName and UnitName(unit) or ""
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local tc = cfg and cfg.text or {}
	local sc = cfg and cfg.status or {}
	if UnitIsConnected and not UnitIsConnected(unit) then name = (name and name ~= "") and (name .. " |cffff6666DC|r") or "|cffff6666DC|r" end
	name = name or ""
	if st._lastName ~= name then
		fs:SetText(name)
		st._lastName = name
	end

	-- Name coloring (simple: class color for players, grey if offline)
	local r, g, b, a = 1, 1, 1, 1
	local nameMode = sc.nameColorMode
	if nameMode == nil then nameMode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM" end
	if nameMode == "CUSTOM" then
		r, g, b, a = unpackColor(sc.nameColor, { 1, 1, 1, 1 })
	elseif nameMode == "CLASS" and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	end
	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b, a = 0.7, 0.7, 0.7, 1
	end
	if st._lastNameR ~= r or st._lastNameG ~= g or st._lastNameB ~= b or st._lastNameA ~= a then
		st._lastNameR, st._lastNameG, st._lastNameB, st._lastNameA = r, g, b, a
		if fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
	end
end

local function shouldShowLevel(scfg, unit)
	if not scfg or scfg.levelEnabled == false then return false end
	if scfg.hideLevelAtMax and addon.variables and addon.variables.isMaxLevel and UnitLevel then
		local level = UnitLevel(unit)
		if issecretvalue and issecretvalue(level) then return true end
		level = tonumber(level) or 0
		if level > 0 and addon.variables.isMaxLevel[level] then return false end
	end
	return true
end

function GF:UpdateLevel(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (st and st.levelText) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local scfg = cfg and cfg.status or {}
	local show = unit and shouldShowLevel(scfg, unit)
	if not show and isEditModeActive() then show = true end
	st.levelText:SetShown(show)
	if not show then return end

	local levelText = "??"
	if unit and UnitExists and UnitExists(unit) then
		levelText = getSafeLevelText(unit, false)
	elseif isEditModeActive() then
		levelText = tostring(scfg.sampleLevel or 60)
	end
	st.levelText:SetText(levelText)

	local r, g, b, a = 1, 0.85, 0, 1
	if scfg.levelColorMode == "CUSTOM" then
		r, g, b, a = unpackColor(scfg.levelColor, { 1, 0.85, 0, 1 })
	elseif scfg.levelColorMode == "CLASS" and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	end
	if st._lastLevelR ~= r or st._lastLevelG ~= g or st._lastLevelB ~= b or st._lastLevelA ~= a then
		st._lastLevelR, st._lastLevelG, st._lastLevelB, st._lastLevelA = r, g, b, a
		st.levelText:SetTextColor(r, g, b, a)
	end
end

function GF:UpdateHealthValue(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.health) then return end
	if UnitExists and not UnitExists(unit) then
		st.health:SetMinMaxValues(0, 1)
		st.health:SetValue(0)
		if st.absorb then st.absorb:Hide() end
		if st.healAbsorb then st.healAbsorb:Hide() end
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
		return
	end
	local cur = UnitHealth and UnitHealth(unit)
	if cur == nil then cur = 0 end
	local maxv = UnitHealthMax and UnitHealthMax(unit)
	if maxv == nil then maxv = 1 end
	local maxForValue = 1
	if issecretvalue and issecretvalue(maxv) then
		maxForValue = maxv
	elseif maxv and maxv > 0 then
		maxForValue = maxv
	end
	local secretHealth = issecretvalue and (issecretvalue(cur) or issecretvalue(maxv))
	if secretHealth then
		st.health:SetMinMaxValues(0, maxForValue)
		st.health:SetValue(cur or 0)
	else
		if st._lastHealthMax ~= maxForValue then
			st.health:SetMinMaxValues(0, maxForValue)
			st._lastHealthMax = maxForValue
			st._lastHealthPx = nil
			st._lastHealthBarW = nil
		end
		local w = st.health:GetWidth()
		if w and w > 0 and maxForValue > 0 then
			local px = floor((cur * w) / maxForValue + 0.5)
			if st._lastHealthPx ~= px or st._lastHealthBarW ~= w then
				st._lastHealthPx = px
				st._lastHealthBarW = w
				st.health:SetValue((px / w) * maxForValue)
				st._lastHealthCur = cur
			end
		else
			if st._lastHealthCur ~= cur then
				st.health:SetValue(cur)
				st._lastHealthCur = cur
			end
		end
	end

	-- Absorb overlays
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	local kind = self._eqolGroupKind or "party"
	local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}
	local absorbEnabled = hc.absorbEnabled ~= false
	local healAbsorbEnabled = hc.healAbsorbEnabled ~= false
	local curSecret = issecretvalue and issecretvalue(cur)
	if absorbEnabled and st.absorb then
		local abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
		local absSecret = issecretvalue and issecretvalue(abs)
		if not absSecret then abs = tonumber(abs) or 0 end
		local canSampleAbsorb = isEditModeActive() and not absSecret and (not issecretvalue or not issecretvalue(maxForValue))
		if canSampleAbsorb and (not abs or abs == 0) then abs = (maxForValue or 1) * 0.6 end
		st.absorb:SetMinMaxValues(0, maxForValue or 1)
		st.absorb:SetValue(abs or 0)
		if absSecret then
			st.absorb:Show()
		elseif abs and abs > 0 then
			st.absorb:Show()
		else
			st.absorb:Hide()
		end
		local ar, ag, ab, aa
		if UFHelper and UFHelper.getAbsorbColor then
			ar, ag, ab, aa = UFHelper.getAbsorbColor(hc, defH)
		else
			ar, ag, ab, aa = 0.85, 0.95, 1, 0.7
		end
		if st._lastAbsorbR ~= ar or st._lastAbsorbG ~= ag or st._lastAbsorbB ~= ab or st._lastAbsorbA ~= aa then
			st._lastAbsorbR, st._lastAbsorbG, st._lastAbsorbB, st._lastAbsorbA = ar, ag, ab, aa
			st.absorb:SetStatusBarColor(ar or 0.85, ag or 0.95, ab or 1, aa or 0.7)
		end
		if st.overAbsorbGlow then
			local showGlow = hc.useAbsorbGlow ~= false and (not absSecret and abs and abs > 0)
			st.overAbsorbGlow:SetShown(showGlow)
		end
	elseif st.absorb then
		st.absorb:Hide()
		if st.overAbsorbGlow then st.overAbsorbGlow:Hide() end
	end

	if healAbsorbEnabled and st.healAbsorb then
		local healAbs = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
		local healSecret = issecretvalue and issecretvalue(healAbs)
		if not healSecret then healAbs = tonumber(healAbs) or 0 end
		local canSampleHeal = isEditModeActive() and not healSecret and (not issecretvalue or not issecretvalue(maxForValue))
		if canSampleHeal and (not healAbs or healAbs == 0) then healAbs = (maxForValue or 1) * 0.35 end
		st.healAbsorb:SetMinMaxValues(0, maxForValue or 1)
		if not healSecret and not curSecret then
			if (cur or 0) < (healAbs or 0) then healAbs = cur or 0 end
		end
		st.healAbsorb:SetValue(healAbs or 0)
		if healSecret then
			st.healAbsorb:Show()
		elseif healAbs and healAbs > 0 then
			st.healAbsorb:Show()
		else
			st.healAbsorb:Hide()
		end
		local har, hag, hab, haa
		if UFHelper and UFHelper.getHealAbsorbColor then
			har, hag, hab, haa = UFHelper.getHealAbsorbColor(hc, defH)
		else
			har, hag, hab, haa = 1, 0.3, 0.3, 0.7
		end
		if st._lastHealAbsorbR ~= har or st._lastHealAbsorbG ~= hag or st._lastHealAbsorbB ~= hab or st._lastHealAbsorbA ~= haa then
			st._lastHealAbsorbR, st._lastHealAbsorbG, st._lastHealAbsorbB, st._lastHealAbsorbA = har, hag, hab, haa
			st.healAbsorb:SetStatusBarColor(har or 1, hag or 0.3, hab or 0.3, haa or 0.7)
		end
	elseif st.healAbsorb then
		st.healAbsorb:Hide()
	end

	-- Health text slots (UF-like formatting, secret-safe)
	local leftMode = (hc.textLeft ~= nil) and hc.textLeft or defH.textLeft or "NONE"
	local centerMode = (hc.textCenter ~= nil) and hc.textCenter or defH.textCenter or "NONE"
	local rightMode = (hc.textRight ~= nil) and hc.textRight or defH.textRight or "NONE"
	local hasText = (leftMode ~= "NONE") or (centerMode ~= "NONE") or (rightMode ~= "NONE")
	if hasText and (st.healthTextLeft or st.healthTextCenter or st.healthTextRight) then
		if secretHealth then
			if st.healthTextLeft then st.healthTextLeft:SetText("") end
			if st.healthTextCenter then st.healthTextCenter:SetText("") end
			if st.healthTextRight then st.healthTextRight:SetText("") end
			st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
		else
			local delimiter = (UFHelper and UFHelper.getTextDelimiter and UFHelper.getTextDelimiter(hc, defH)) or (hc.textDelimiter or defH.textDelimiter or " ")
			local delimiter2 = (UFHelper and UFHelper.getTextDelimiterSecondary and UFHelper.getTextDelimiterSecondary(hc, defH, delimiter))
				or (hc.textDelimiterSecondary or defH.textDelimiterSecondary or delimiter)
			local delimiter3 = (UFHelper and UFHelper.getTextDelimiterTertiary and UFHelper.getTextDelimiterTertiary(hc, defH, delimiter, delimiter2))
				or (hc.textDelimiterTertiary or defH.textDelimiterTertiary or delimiter2)
			local useShort = hc.useShortNumbers ~= false
			local hidePercentSymbol = hc.hidePercentSymbol == true
			local percentVal
			if textModeUsesPercent(leftMode) or textModeUsesPercent(centerMode) or textModeUsesPercent(rightMode) then
				if addon.variables and addon.variables.isMidnight then
					percentVal = getHealthPercent(unit, cur, maxv)
				else
					percentVal = getHealthPercent(unit, cur, maxv)
				end
			end
			local levelText
			if UFHelper and UFHelper.textModeUsesLevel then
				if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then
					levelText = getSafeLevelText(unit, false)
				end
			end
			local function setHealthText(fs, cacheKey, mode)
				if not fs then return end
				if mode == "NONE" then
					if st[cacheKey] ~= "" then
						st[cacheKey] = ""
						fs:SetText("")
					end
					return
				end
				local text = ""
				if UFHelper and UFHelper.formatText then
					text = UFHelper.formatText(mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
				else
					text = tostring(cur or 0)
				end
				if st[cacheKey] ~= text then
					st[cacheKey] = text
					fs:SetText(text)
				end
			end
			setHealthText(st.healthTextLeft, "_lastHealthTextLeft", leftMode)
			setHealthText(st.healthTextCenter, "_lastHealthTextCenter", centerMode)
			setHealthText(st.healthTextRight, "_lastHealthTextRight", rightMode)
		end
	elseif st.healthTextLeft or st.healthTextCenter or st.healthTextRight then
		if st.healthTextLeft then st.healthTextLeft:SetText("") end
		if st.healthTextCenter then st.healthTextCenter:SetText("") end
		if st.healthTextRight then st.healthTextRight:SetText("") end
		st._lastHealthTextLeft, st._lastHealthTextCenter, st._lastHealthTextRight = nil, nil, nil
	end
end

function GF:UpdateHealthStyle(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.health) then return end
	if UnitExists and not UnitExists(unit) then return end

	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local hc = cfg and cfg.health or {}
	local kind = self._eqolGroupKind or "party"
	local defH = (DEFAULTS[kind] and DEFAULTS[kind].health) or {}

	if st.health and st.health.SetStatusBarDesaturated then
		if st._lastHealthDesat ~= true then
			st._lastHealthDesat = true
			st.health:SetStatusBarDesaturated(true)
		end
	end

	local r, g, b, a
	local useCustom = hc.useCustomColor == true
	if useCustom then
		r, g, b, a = unpackColor(hc.color, defH.color or { 0, 0.8, 0, 1 })
	elseif hc.useClassColor == true and st._classR then
		r, g, b, a = st._classR, st._classG, st._classB, st._classA or 1
	else
		r, g, b, a = unpackColor(hc.color, defH.color or { 0, 0.8, 0, 1 })
	end

	if UnitIsConnected and not UnitIsConnected(unit) then
		r, g, b, a = 0.5, 0.5, 0.5, 1
	end
	if st._lastHealthR ~= r or st._lastHealthG ~= g or st._lastHealthB ~= b or st._lastHealthA ~= a then
		st._lastHealthR, st._lastHealthG, st._lastHealthB, st._lastHealthA = r, g, b, a
		st.health:SetStatusBarColor(r, g, b, a or 1)
	end
end

function GF:UpdateHealth(self)
	GF:UpdateHealthStyle(self)
	GF:UpdateHealthValue(self)
end

function GF:UpdatePowerVisibility(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return false end
	local kind = self._eqolGroupKind or "party"
	local cfg = self._eqolCfg or getCfg(kind)
	local pcfg = cfg and cfg.power or {}
	if st._wantsPower == false then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		if st.power:IsShown() then st.power:Hide() end
		if not st._powerHidden then
			st._powerHidden = true
			GF:LayoutButton(self)
		end
		return false
	end
	local showPower = shouldShowPowerForUnit(pcfg, unit)
	if not showPower then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		if st.power:IsShown() then st.power:Hide() end
		if not st._powerHidden then
			st._powerHidden = true
			GF:LayoutButton(self)
		end
		return false
	end
	if st._powerHidden then
		st._powerHidden = nil
		GF:LayoutButton(self)
	end
	if not st.power:IsShown() then st.power:Show() end
	return true
end

function GF:UpdatePowerValue(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return end
	if st._wantsPower == false or st._powerHidden then return end
	if UnitExists and not UnitExists(unit) then
		st.power:SetMinMaxValues(0, 1)
		st.power:SetValue(0)
		return
	end
	local powerType = st._powerType
	if powerType == nil and UnitPowerType then
		powerType, st._powerToken = UnitPowerType(unit)
		st._powerType = powerType
	end
	local cur = UnitPower and UnitPower(unit, powerType)
	if cur == nil then cur = 0 end
	local maxv = UnitPowerMax and UnitPowerMax(unit, powerType)
	if maxv == nil then maxv = 1 end
	local maxForValue = 1
	if issecretvalue and issecretvalue(maxv) then
		maxForValue = maxv
	elseif maxv and maxv > 0 then
		maxForValue = maxv
	end
	local secretPower = issecretvalue and (issecretvalue(cur) or issecretvalue(maxv))
	if secretPower then
		st.power:SetMinMaxValues(0, maxForValue)
		st.power:SetValue(cur or 0)
	else
		if st._lastPowerMax ~= maxForValue then
			st.power:SetMinMaxValues(0, maxForValue)
			st._lastPowerMax = maxForValue
			st._lastPowerPx = nil
			st._lastPowerBarW = nil
		end
		local w = st.power:GetWidth()
		if w and w > 0 and maxForValue > 0 then
			local px = floor((cur * w) / maxForValue + 0.5)
			if st._lastPowerPx ~= px or st._lastPowerBarW ~= w then
				st._lastPowerPx = px
				st._lastPowerBarW = w
				st.power:SetValue((px / w) * maxForValue)
				st._lastPowerCur = cur
			end
		else
			if st._lastPowerCur ~= cur then
				st.power:SetValue(cur)
				st._lastPowerCur = cur
			end
		end
	end

	-- Power text slots (UF-like formatting, secret-safe)
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local kind = self._eqolGroupKind or "party"
	local pcfg = cfg and cfg.power or {}
	local defP = (DEFAULTS[kind] and DEFAULTS[kind].power) or {}
	local leftMode = (pcfg.textLeft ~= nil) and pcfg.textLeft or defP.textLeft or "NONE"
	local centerMode = (pcfg.textCenter ~= nil) and pcfg.textCenter or defP.textCenter or "NONE"
	local rightMode = (pcfg.textRight ~= nil) and pcfg.textRight or defP.textRight or "NONE"
	local hasText = (leftMode ~= "NONE") or (centerMode ~= "NONE") or (rightMode ~= "NONE")
	if hasText and (st.powerTextLeft or st.powerTextCenter or st.powerTextRight) then
		if secretPower then
			if st.powerTextLeft then st.powerTextLeft:SetText("") end
			if st.powerTextCenter then st.powerTextCenter:SetText("") end
			if st.powerTextRight then st.powerTextRight:SetText("") end
			st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
		else
			local maxZero = (maxv == 0)
			if maxZero then
				if st.powerTextLeft then st.powerTextLeft:SetText("") end
				if st.powerTextCenter then st.powerTextCenter:SetText("") end
				if st.powerTextRight then st.powerTextRight:SetText("") end
				st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
			else
				local delimiter = (UFHelper and UFHelper.getTextDelimiter and UFHelper.getTextDelimiter(pcfg, defP)) or (pcfg.textDelimiter or defP.textDelimiter or " ")
				local delimiter2 = (UFHelper and UFHelper.getTextDelimiterSecondary and UFHelper.getTextDelimiterSecondary(pcfg, defP, delimiter))
					or (pcfg.textDelimiterSecondary or defP.textDelimiterSecondary or delimiter)
				local delimiter3 = (UFHelper and UFHelper.getTextDelimiterTertiary and UFHelper.getTextDelimiterTertiary(pcfg, defP, delimiter, delimiter2))
					or (pcfg.textDelimiterTertiary or defP.textDelimiterTertiary or delimiter2)
				local useShort = pcfg.useShortNumbers ~= false
				local hidePercentSymbol = pcfg.hidePercentSymbol == true
				local percentVal
				if textModeUsesPercent(leftMode) or textModeUsesPercent(centerMode) or textModeUsesPercent(rightMode) then
					if addon.variables and addon.variables.isMidnight then
					percentVal = getPowerPercent(unit, powerType or 0, cur, maxv)
				else
					percentVal = getPowerPercent(unit, powerType or 0, cur, maxv)
				end
			end
				local levelText
				if UFHelper and UFHelper.textModeUsesLevel then
					if UFHelper.textModeUsesLevel(leftMode) or UFHelper.textModeUsesLevel(centerMode) or UFHelper.textModeUsesLevel(rightMode) then
						levelText = getSafeLevelText(unit, false)
					end
				end
				local function setPowerText(fs, cacheKey, mode)
					if not fs then return end
					if mode == "NONE" then
						if st[cacheKey] ~= "" then
							st[cacheKey] = ""
							fs:SetText("")
						end
						return
					end
					local text = ""
					if UFHelper and UFHelper.formatText then
						text = UFHelper.formatText(mode, cur, maxv, useShort, percentVal, delimiter, delimiter2, delimiter3, hidePercentSymbol, levelText)
					else
						text = tostring(cur or 0)
					end
					if st[cacheKey] ~= text then
						st[cacheKey] = text
						fs:SetText(text)
					end
				end
				setPowerText(st.powerTextLeft, "_lastPowerTextLeft", leftMode)
				setPowerText(st.powerTextCenter, "_lastPowerTextCenter", centerMode)
				setPowerText(st.powerTextRight, "_lastPowerTextRight", rightMode)
			end
		end
	elseif st.powerTextLeft or st.powerTextCenter or st.powerTextRight then
		if st.powerTextLeft then st.powerTextLeft:SetText("") end
		if st.powerTextCenter then st.powerTextCenter:SetText("") end
		if st.powerTextRight then st.powerTextRight:SetText("") end
		st._lastPowerTextLeft, st._lastPowerTextCenter, st._lastPowerTextRight = nil, nil, nil
	end
end

function GF:UpdatePowerStyle(self)
	local unit = getUnit(self)
	local st = getState(self)
	if not (unit and st and st.power) then return end
	if st._wantsPower == false or st._powerHidden then return end
	if not UnitPowerType then return end
	local powerType, powerToken = UnitPowerType(unit)
	st._powerType, st._powerToken = powerType, powerToken

	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	local pcfg = cfg and cfg.power or {}
	local powerKey = powerToken or powerType or "MANA"
	-- Apply special atlas textures for default texture keys (mirrors UF.lua behavior)
	if UFHelper and UFHelper.configureSpecialTexture then
		if st._lastPowerToken ~= powerKey or st._lastPowerTexture ~= pcfg.texture then
			UFHelper.configureSpecialTexture(st.power, powerKey, pcfg.texture, pcfg)
			st._lastPowerToken = powerKey
			st._lastPowerTexture = pcfg.texture
		end
	end
	stabilizeStatusBarTexture(st.power)
	if st.power.SetStatusBarDesaturated and UFHelper and UFHelper.isPowerDesaturated then
		local desat = UFHelper.isPowerDesaturated(powerKey)
		if st._lastPowerDesat ~= desat then
			st._lastPowerDesat = desat
			st.power:SetStatusBarDesaturated(desat)
		end
	end
	local pr, pg, pb, pa
	if UFHelper and UFHelper.getPowerColor then
		pr, pg, pb, pa = UFHelper.getPowerColor(powerKey)
	else
		local c = PowerBarColor and (PowerBarColor[powerKey] or PowerBarColor[powerType] or PowerBarColor["MANA"])
		if c then
			pr, pg, pb, pa = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 1, c.a or c[4] or 1
		end
	end
	if not pr then
		pr, pg, pb, pa = 0, 0.5, 1, 1
	end
	local alpha = pa or 1
	if st._lastPowerR ~= pr or st._lastPowerG ~= pg or st._lastPowerB ~= pb or st._lastPowerA ~= alpha then
		st._lastPowerR, st._lastPowerG, st._lastPowerB, st._lastPowerA = pr, pg, pb, alpha
		st.power:SetStatusBarColor(pr, pg, pb, pa or 1)
	end
end

function GF:UpdatePower(self)
	if not GF:UpdatePowerVisibility(self) then return end
	GF:UpdatePowerStyle(self)
	GF:UpdatePowerValue(self)
end

function GF:UpdateAll(self)
	GF:UpdateName(self)
	GF:UpdateLevel(self)
	GF:UpdateHealth(self)
	GF:UpdatePower(self)
	GF:UpdateRoleIcon(self)
	GF:UpdateGroupIcons(self)
	GF:UpdateAuras(self)
end

-- -----------------------------------------------------------------------------
-- Unit menu (right click)
-- -----------------------------------------------------------------------------

GF._dropdown = GF._dropdown or nil

local function ensureDropDown()
	if GF._dropdown and GF._dropdown.GetName then return GF._dropdown end
	GF._dropdown = CreateFrame("Frame", "EQOLUFGroupDropDown", UIParent, "UIDropDownMenuTemplate")
	return GF._dropdown
end

local function resolveMenuType(unit)
	-- Best-effort: Blizzard has multiple menu variants. These are the most common keys.
	if unit == "player" then return "SELF" end
	if UnitIsUnit and UnitIsUnit(unit, "player") then return "SELF" end
	if UnitInRaid and UnitInRaid(unit) then return "RAID_PLAYER" end
	if UnitInParty and UnitInParty(unit) then return "PARTY" end
	return "RAID_PLAYER"
end

function GF:OpenUnitMenu(self)
	local unit = getUnit(self)
	if not unit then return end

	-- Dragonflight+ has UnitPopup_OpenMenu, but it is not 100% consistent across versions.
	-- We fall back to UnitPopup_ShowMenu + a shared dropdown.
	if UnitPopup_OpenMenu then
		-- Try the modern API signature first.
		pcall(function() UnitPopup_OpenMenu(resolveMenuType(unit), { unit = unit }) end)
		return
	end

	if UnitPopup_ShowMenu then
		local dd = ensureDropDown()
		local which = resolveMenuType(unit)
		local name = (UnitName and UnitName(unit))
		UnitPopup_ShowMenu(dd, which, unit, name)
	end
end

-- -----------------------------------------------------------------------------
-- XML template script handlers
-- -----------------------------------------------------------------------------

function GF.UnitButton_OnLoad(self)
	-- Detect whether this button belongs to the party or raid header.
	-- (The secure header is the parent; we tag headers with _eqolKind.)
	local parent = self and self.GetParent and self:GetParent()
	if parent and parent._eqolKind then self._eqolGroupKind = parent._eqolKind end

	GF:BuildButton(self)

	-- The unit attribute may already exist when the button is created.
	local unit = getUnit(self)
	if unit then
		GF:UnitButton_SetUnit(self, unit)
	else
		-- Keep it blank until we get a unit.
		GF:UpdateAll(self)
	end
end

function GF:UnitButton_SetUnit(self, unit)
	if not self then return end
	self.unit = unit
	GF:CacheUnitStatic(self)

	GF:UnitButton_RegisterUnitEvents(self, unit)

	GF:UpdateAll(self)
end

function GF:UnitButton_ClearUnit(self)
	if not self then return end
	self.unit = nil
	auraUpdateQueue[self] = nil
	if self._eqolRegEv then
		for ev in pairs(self._eqolRegEv) do
			if self.UnregisterEvent then self:UnregisterEvent(ev) end
			self._eqolRegEv[ev] = nil
		end
	end
	local st = self._eqolUFState
	if st then
		st._guid = nil
		st._unitToken = nil
		st._class = nil
		st._powerType = nil
		st._powerToken = nil
		st._classR, st._classG, st._classB, st._classA = nil, nil, nil, nil
	end
end

function GF:UnitButton_RegisterUnitEvents(self, unit)
	if not (self and unit) then return end
	local cfg = self._eqolCfg or getCfg(self._eqolGroupKind or "party")
	updateButtonConfig(self, cfg)

	self._eqolRegEv = self._eqolRegEv or {}
	for ev in pairs(self._eqolRegEv) do
		if self.UnregisterEvent then self:UnregisterEvent(ev) end
		self._eqolRegEv[ev] = nil
	end

	local function reg(ev)
		self:RegisterUnitEvent(ev, unit)
		self._eqolRegEv[ev] = true
	end

	reg("UNIT_CONNECTION")
	reg("UNIT_HEALTH")
	reg("UNIT_MAXHEALTH")
	if self._eqolUFState and self._eqolUFState._wantsAbsorb then
		reg("UNIT_ABSORB_AMOUNT_CHANGED")
		reg("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
	end

	local powerH = cfg and cfg.powerHeight or 0
	local wantsPower = self._eqolUFState and self._eqolUFState._wantsPower
	if wantsPower == nil then wantsPower = true end
	if powerH and powerH > 0 and wantsPower then
		reg("UNIT_POWER_UPDATE")
		reg("UNIT_MAXPOWER")
		reg("UNIT_DISPLAYPOWER")
	end

	reg("UNIT_NAME_UPDATE")
	local wantsLevel = self._eqolUFState and self._eqolUFState._wantsLevel
	if not wantsLevel and UFHelper and UFHelper.textModeUsesLevel then
		local hc = cfg and cfg.health or {}
		local pcfg = cfg and cfg.power or {}
		if UFHelper.textModeUsesLevel(hc.textLeft) or UFHelper.textModeUsesLevel(hc.textCenter) or UFHelper.textModeUsesLevel(hc.textRight) then
			wantsLevel = true
		elseif UFHelper.textModeUsesLevel(pcfg.textLeft) or UFHelper.textModeUsesLevel(pcfg.textCenter) or UFHelper.textModeUsesLevel(pcfg.textRight) then
			wantsLevel = true
		end
	end
	if wantsLevel then reg("UNIT_LEVEL") end

	if self._eqolUFState and self._eqolUFState._wantsAuras then reg("UNIT_AURA") end
end

function GF.UnitButton_OnAttributeChanged(self, name, value)
	if name ~= "unit" then return end
	if value == nil or value == "" then
		-- Unit cleared
		GF:UnitButton_ClearUnit(self)
		GF:UpdateAll(self)
		return
	end
	if self.unit == value then return end
	GF:UnitButton_SetUnit(self, value)
end

local function dispatchUnitHealth(btn) GF:UpdateHealthValue(btn) end
local function dispatchUnitPower(btn) GF:UpdatePowerValue(btn) end
local function dispatchUnitDisplayPower(btn) GF:UpdatePower(btn) end
local function dispatchUnitName(btn)
	GF:CacheUnitStatic(btn)
	GF:UpdateName(btn)
	GF:UpdateHealthStyle(btn)
	GF:UpdateLevel(btn)
end
local function dispatchUnitLevel(btn)
	GF:UpdateLevel(btn)
	GF:UpdateHealthValue(btn)
	GF:UpdatePowerValue(btn)
end
local function dispatchUnitConnection(btn)
	GF:UpdateHealthStyle(btn)
	GF:UpdateHealthValue(btn)
	GF:UpdatePowerValue(btn)
	GF:UpdateName(btn)
	GF:UpdateLevel(btn)
end
local function dispatchUnitAura(btn, updateInfo) GF:RequestAuraUpdate(btn, updateInfo) end

local UNIT_DISPATCH = {
	UNIT_HEALTH = dispatchUnitHealth,
	UNIT_MAXHEALTH = dispatchUnitHealth,
	UNIT_ABSORB_AMOUNT_CHANGED = dispatchUnitHealth,
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = dispatchUnitHealth,
	UNIT_POWER_UPDATE = dispatchUnitPower,
	UNIT_MAXPOWER = dispatchUnitPower,
	UNIT_DISPLAYPOWER = dispatchUnitDisplayPower,
	UNIT_NAME_UPDATE = dispatchUnitName,
	UNIT_LEVEL = dispatchUnitLevel,
	UNIT_CONNECTION = dispatchUnitConnection,
	UNIT_AURA = dispatchUnitAura,
}

function GF.UnitButton_OnEvent(self, event, unit, ...)
	if not isFeatureEnabled() then return end
	local u = getUnit(self)
	if not u or (unit and unit ~= u) then return end

	local fn = UNIT_DISPATCH[event]
	if fn then fn(self, ...) end
end

function GF.UnitButton_OnEnter(self)
	local unit = getUnit(self)
	if not unit then return end
	local st = getState(self)
	if st then
		st._hovered = true
		if UFHelper and UFHelper.updateHighlight then UFHelper.updateHighlight(st, unit, "player") end
	end
	if not GameTooltip or GameTooltip:IsForbidden() then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetUnit(unit)
	GameTooltip:Show()
end

function GF.UnitButton_OnLeave(self)
	local unit = getUnit(self)
	local st = getState(self)
	if st then
		st._hovered = false
		if UFHelper and UFHelper.updateHighlight and unit then UFHelper.updateHighlight(st, unit, "player") end
	end
	if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

-- -----------------------------------------------------------------------------
-- Header creation / layout
-- -----------------------------------------------------------------------------

local function setPointFromCfg(frame, cfg)
	if not frame or not cfg then return end
	frame:ClearAllPoints()
	local rel = cfg.relativeTo and _G[cfg.relativeTo] or UIParent
	local p = cfg.point or "CENTER"
	local rp = cfg.relativePoint or p
	frame:SetPoint(p, rel, rp, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0)
end

-- -----------------------------------------------------------------------------
-- Anchor frames (Edit Mode)
-- -----------------------------------------------------------------------------
local function ensureAnchor(kind, parent)
	if not kind then return nil end
	GF.anchors = GF.anchors or {}
	local anchor = GF.anchors[kind]
	if anchor then return anchor end

	local name
	if kind == "party" then
		name = "EQOLUFPartyAnchor"
	elseif kind == "raid" then
		name = "EQOLUFRaidAnchor"
	end
	if not name then return nil end

	anchor = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
	anchor._eqolKind = kind
	anchor:EnableMouse(false)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetFrameLevel(1)

	-- A tiny backdrop so you can see the area while positioning in edit mode.
	-- The selection overlay will still be the primary indicator.
	if anchor.SetBackdrop then
		anchor:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			insets = { left = 0, right = 0, top = 0, bottom = 0 },
		})
		anchor:SetBackdropColor(0, 0, 0, 0.08)
		anchor:SetBackdropBorderColor(0, 0, 0, 0.6)
	end

	anchor:Hide()
	GF.anchors[kind] = anchor
	return anchor
end

function GF:UpdateAnchorSize(kind)
	local cfg = getCfg(kind)
	local anchor = GF.anchors and GF.anchors[kind]
	if not (cfg and anchor) then return end

	local w = floor((tonumber(cfg.width) or 100) + 0.5)
	local h = floor((tonumber(cfg.height) or 24) + 0.5)
	local spacing = tonumber(cfg.spacing) or 0
	local columnSpacing = tonumber(cfg.columnSpacing) or spacing
	local growth = (cfg.growth or "DOWN"):upper()

	local unitsPer = 5
	local columns = 1
	if kind == "raid" then
		unitsPer = max(1, floor((tonumber(cfg.unitsPerColumn) or 5) + 0.5))
		columns = max(1, floor((tonumber(cfg.maxColumns) or 8) + 0.5))
	end

	local totalW, totalH
	if growth == "RIGHT" then
		totalW = w * unitsPer + spacing * max(0, unitsPer - 1)
		totalH = h * columns + columnSpacing * max(0, columns - 1)
	else
		totalW = w * columns + columnSpacing * max(0, columns - 1)
		totalH = h * unitsPer + spacing * max(0, unitsPer - 1)
	end

	if totalW < w then totalW = w end
	if totalH < h then totalH = h end

	anchor:SetSize(totalW, totalH)
end

local function applyVisibility(header, kind, cfg)
	if not header or not cfg or not RegisterStateDriver then return end
	if InCombatLockdown and InCombatLockdown() then return end

	if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end

	local cond = "hide"
	if header._eqolForceShow then
		cond = "show"
	elseif cfg.enabled then
		if kind == "party" then
			if cfg.showSolo then
				cond = "[group:raid] hide; show"
			else
				cond = "[group:raid] hide; [group:party] show; hide"
			end
		elseif kind == "raid" then
			cond = "[group:raid] show; hide"
		end
	end

	RegisterStateDriver(header, "visibility", cond)
	header._eqolVisibilityCond = cond
end

local function forEachChild(header, fn)
	if not header or not fn then return end
	local children = { header:GetChildren() }
	for _, child in ipairs(children) do
		fn(child)
	end
end

function GF:RefreshRoleIcons()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateRoleIcon(child) end
		end)
	end
end

function GF:RefreshGroupIcons()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then GF:UpdateGroupIcons(child) end
		end)
	end
end

function GF:RefreshPowerVisibility()
	if not isFeatureEnabled() then return end
	for _, header in pairs(GF.headers or {}) do
		forEachChild(header, function(child)
			if child then
				updateButtonConfig(child, child._eqolCfg)
				if child.unit then GF:UnitButton_RegisterUnitEvents(child, child.unit) end
				GF:UpdatePower(child)
			end
		end)
	end
end

function GF:ApplyHeaderAttributes(kind)
	local cfg = getCfg(kind)
	local header = GF.headers[kind]
	if not header then return end
	if not isFeatureEnabled() then return end
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingRefresh = true
		return
	end

	local spacing = tonumber(cfg.spacing) or 0
	local growth = (cfg.growth or "DOWN"):upper()

	-- Core header settings
	if kind == "party" then
		header:SetAttribute("showParty", true)
		header:SetAttribute("showRaid", false)
		header:SetAttribute("showPlayer", cfg.showPlayer and true or false)
		header:SetAttribute("showSolo", cfg.showSolo and true or false)
		header:SetAttribute("sortMethod", "INDEX")
		header:SetAttribute("sortDir", "ASC")
		header:SetAttribute("maxColumns", 1)
		header:SetAttribute("unitsPerColumn", 5)
	elseif kind == "raid" then
		header:SetAttribute("showParty", false)
		header:SetAttribute("showRaid", true)
		header:SetAttribute("showPlayer", true) -- most raid layouts include player
		header:SetAttribute("showSolo", false)
		header:SetAttribute("groupBy", cfg.groupBy or "GROUP")
		header:SetAttribute("groupingOrder", cfg.groupingOrder or "1,2,3,4,5,6,7,8")
		header:SetAttribute("sortMethod", cfg.sortMethod or "INDEX")
		header:SetAttribute("sortDir", cfg.sortDir or "ASC")
		header:SetAttribute("unitsPerColumn", tonumber(cfg.unitsPerColumn) or 5)
		header:SetAttribute("maxColumns", tonumber(cfg.maxColumns) or 8)
	end

	-- Edit mode preview override: keep the header visible for positioning.
	if header._eqolForceShow then
		header:SetAttribute("showParty", true)
		header:SetAttribute("showRaid", true)
		header:SetAttribute("showPlayer", true)
		header:SetAttribute("showSolo", true)
	end

	-- Growth / spacing
	if growth == "RIGHT" then
		if kind == "party" then
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", spacing)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnSpacing", spacing)
			header:SetAttribute("columnAnchorPoint", "TOP")
		else
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", spacing)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnSpacing", tonumber(cfg.columnSpacing) or spacing)
			header:SetAttribute("columnAnchorPoint", "TOP")
		end
	else
		header:SetAttribute("point", "TOP")
		header:SetAttribute("xOffset", 0)
		header:SetAttribute("yOffset", -spacing)
		header:SetAttribute("columnSpacing", tonumber(cfg.columnSpacing) or spacing)
		header:SetAttribute("columnAnchorPoint", "LEFT")
	end

	-- Child template + secure per-button init
	-- NOTE: initialConfigFunction runs only when a button is created.
	-- If you change size later, also resize existing children (below).
	header:SetAttribute("template", "EQOLUFGroupUnitButtonTemplate")
	local w = tonumber(cfg.width) or 100
	local h = tonumber(cfg.height) or 24
	w = floor(w + 0.5)
	h = floor(h + 0.5)
	header:SetAttribute(
		"initialConfigFunction",
		string.format(
			[[
		self:SetWidth(%d)
		self:SetHeight(%d)
		self:SetAttribute('*type1','target')
		self:SetAttribute('*type2','togglemenu')
		RegisterUnitWatch(self)
	]],
			w,
			h
		)
	)

	-- Also apply size to existing children.
	forEachChild(header, function(child)
		child._eqolGroupKind = kind
		child._eqolCfg = cfg
		updateButtonConfig(child, cfg)
		GF:LayoutAuras(child)
		if child.unit then GF:UnitButton_RegisterUnitEvents(child, child.unit) end
		child:SetSize(w, h)
		if child._eqolUFState then
			GF:LayoutButton(child)
			GF:UpdateAll(child)
		end
	end)

	local anchor = GF.anchors and GF.anchors[kind]
	if anchor then
		setPointFromCfg(anchor, cfg)
		GF:UpdateAnchorSize(kind)
		header:ClearAllPoints()
		local p = cfg.point or "CENTER"
		header:SetPoint(p, anchor, p, 0, 0)
	else
		setPointFromCfg(header, cfg)
	end
	applyVisibility(header, kind, cfg)
end

function GF:EnsureHeaders()
	if not isFeatureEnabled() then return end
	if GF.headers.party and GF.headers.raid and GF.anchors.party and GF.anchors.raid then return end

	-- Parent to PetBattleFrameHider so frames disappear in pet battles
	local parent = _G.PetBattleFrameHider or UIParent

	-- Movers (for Edit Mode positioning)
	if not GF.anchors.party then ensureAnchor("party", parent) end
	if not GF.anchors.raid then ensureAnchor("raid", parent) end

	if not GF.headers.party then
		GF.headers.party = CreateFrame("Frame", "EQOLUFPartyHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.party._eqolKind = "party"
		GF.headers.party:Hide()
	end

	if not GF.headers.raid then
		GF.headers.raid = CreateFrame("Frame", "EQOLUFRaidHeader", parent, "SecureGroupHeaderTemplate")
		GF.headers.raid._eqolKind = "raid"
		GF.headers.raid:Hide()
	end

	-- Anchor headers to their movers (so we can drag the mover in edit mode)
	for kind, header in pairs(GF.headers) do
		local a = GF.anchors and GF.anchors[kind]
		if header and a then
			header:ClearAllPoints()
			local cfg = getCfg(kind)
			local p = cfg and (cfg.point or "CENTER") or "CENTER"
			header:SetPoint(p, a, p, 0, 0)
		end
	end

	-- Apply layout once
	GF:ApplyHeaderAttributes("party")
	GF:ApplyHeaderAttributes("raid")
end

-- -----------------------------------------------------------------------------
-- Public API (call these from Settings later)
-- -----------------------------------------------------------------------------

function GF:EnableFeature()
	addon.db = addon.db or {}
	addon.db.ufEnableGroupFrames = true
	registerFeatureEvents(GF._eventFrame)
	GF:EnsureHeaders()
	GF.Refresh()
	GF:EnsureEditMode()
end

function GF:DisableFeature()
	addon.db = addon.db or {}
	addon.db.ufEnableGroupFrames = false
	if InCombatLockdown and InCombatLockdown() then
		GF._pendingDisable = true
		return
	end
	GF._pendingDisable = nil
	unregisterFeatureEvents(GF._eventFrame)

	-- Unregister Edit Mode frames
	if EditMode and EditMode.UnregisterFrame then
		for _, id in pairs(EDITMODE_IDS) do
			pcall(EditMode.UnregisterFrame, EditMode, id)
		end
	end
	GF._editModeRegistered = nil

	-- Hide headers + anchors
	if GF.headers then
		for _, header in pairs(GF.headers) do
			if UnregisterStateDriver then UnregisterStateDriver(header, "visibility") end
			if RegisterStateDriver then RegisterStateDriver(header, "visibility", "hide") end
			if header.Hide then header:Hide() end
		end
	end
	if GF.anchors then
		for _, anchor in pairs(GF.anchors) do
			if anchor.Hide then anchor:Hide() end
		end
	end
end

function GF.Enable(kind)
	local cfg = getCfg(kind)
	cfg.enabled = true
	GF:EnsureHeaders()
	GF:ApplyHeaderAttributes(kind)
end

function GF.Disable(kind)
	local cfg = getCfg(kind)
	cfg.enabled = false
	GF:EnsureHeaders()
	GF:ApplyHeaderAttributes(kind)
end

function GF.Refresh(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	if kind then
		GF:ApplyHeaderAttributes(kind)
	else
		GF:ApplyHeaderAttributes("party")
		GF:ApplyHeaderAttributes("raid")
	end
end

-- -----------------------------------------------------------------------------
-- Edit Mode integration helpers
-- -----------------------------------------------------------------------------
local EDITMODE_IDS = {
	party = "EQOL_UF_GROUP_PARTY",
	raid = "EQOL_UF_GROUP_RAID",
}

local function anchorUsesUIParent(kind)
	local cfg = getCfg(kind)
	local rel = cfg and cfg.relativeTo
	return rel == nil or rel == "" or rel == "UIParent"
end

local function clampNumber(value, minValue, maxValue, fallback)
	local v = tonumber(value)
	if v == nil then return fallback end
	if minValue ~= nil and v < minValue then v = minValue end
	if maxValue ~= nil and v > maxValue then v = maxValue end
	return v
end

local function copySelectionMap(selection)
	local copy = {}
	if type(selection) ~= "table" then return copy end
	if #selection > 0 then
		for _, value in ipairs(selection) do
			if value ~= nil and (type(value) == "string" or type(value) == "number") then copy[value] = true end
		end
		return copy
	end
	for key, value in pairs(selection) do
		if value and (type(key) == "string" or type(key) == "number") then copy[key] = true end
	end
	return copy
end

local roleOptions = {
	{ value = "TANK", label = TANK or "Tank" },
	{ value = "HEALER", label = HEALER or "Healer" },
	{ value = "DAMAGER", label = DAMAGER or "DPS" },
}

local function defaultRoleSelection()
	local sel = {}
	for _, opt in ipairs(roleOptions) do
		sel[opt.value] = true
	end
	return sel
end

local function getClassInfoById(classId)
	if GetClassInfo then return GetClassInfo(classId) end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classId)
		if info then return info.className, info.classFile, info.classID end
	end
	return nil
end

local function forEachSpec(callback)
	local getSpecCount = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
	if not getSpecCount or not GetSpecializationInfoForClassID or not GetNumClasses then return false end
	local sex = UnitSex and UnitSex("player") or nil
	local numClasses = GetNumClasses() or 0
	local found = false
	for classIndex = 1, numClasses do
		local className, classTag, classID = getClassInfoById(classIndex)
		if classID then
			local specCount = getSpecCount(classID) or 0
			for specIndex = 1, specCount do
				local specID, specName = GetSpecializationInfoForClassID(classID, specIndex, sex)
				if specID then
					found = true
					callback(specID, specName, className, classTag, classID)
				end
			end
		end
	end
	return found
end

local function buildSpecOptions()
	local opts = {}
	local found = forEachSpec(function(specId, specName, className, classTag)
		local label = specName or ("Spec " .. tostring(specId))
		local classLabel = className or classTag
		if classLabel and classLabel ~= "" then label = label .. " (" .. classLabel .. ")" end
		opts[#opts + 1] = { value = specId, label = label }
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId, name = GetSpecializationInfo(i)
			if specId and name then opts[#opts + 1] = { value = specId, label = name } end
		end
	end
	return opts
end

local function defaultSpecSelection()
	local sel = {}
	local found = forEachSpec(function(specId)
		if specId then sel[specId] = true end
	end)
	if not found and GetNumSpecializations and GetSpecializationInfo then
		for i = 1, GetNumSpecializations() do
			local specId = GetSpecializationInfo(i)
			if specId then sel[specId] = true end
		end
	end
	return sel
end

local auraAnchorOptions = {
	{ value = "TOPLEFT", label = "TOPLEFT", text = "TOPLEFT" },
	{ value = "TOP", label = "TOP", text = "TOP" },
	{ value = "TOPRIGHT", label = "TOPRIGHT", text = "TOPRIGHT" },
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
	{ value = "BOTTOMLEFT", label = "BOTTOMLEFT", text = "BOTTOMLEFT" },
	{ value = "BOTTOM", label = "BOTTOM", text = "BOTTOM" },
	{ value = "BOTTOMRIGHT", label = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
}

local textAnchorOptions = {
	{ value = "LEFT", label = "LEFT", text = "LEFT" },
	{ value = "CENTER", label = "CENTER", text = "CENTER" },
	{ value = "RIGHT", label = "RIGHT", text = "RIGHT" },
}

local textModeOptions = {
	{ value = "PERCENT", label = "Percent", text = "Percent" },
	{ value = "CURMAX", label = "Current/Max", text = "Current/Max" },
	{ value = "CURRENT", label = "Current", text = "Current" },
	{ value = "MAX", label = "Max", text = "Max" },
	{ value = "CURPERCENT", label = "Current / Percent", text = "Current / Percent" },
	{ value = "CURMAXPERCENT", label = "Current/Max Percent", text = "Current/Max Percent" },
	{ value = "MAXPERCENT", label = "Max / Percent", text = "Max / Percent" },
	{ value = "PERCENTMAX", label = "Percent / Max", text = "Percent / Max" },
	{ value = "PERCENTCUR", label = "Percent / Current", text = "Percent / Current" },
	{ value = "PERCENTCURMAX", label = "Percent / Current / Max", text = "Percent / Current / Max" },
	{ value = "LEVELPERCENT", label = "Level / Percent", text = "Level / Percent" },
	{ value = "LEVELPERCENTMAX", label = "Level / Percent / Max", text = "Level / Percent / Max" },
	{ value = "LEVELPERCENTCUR", label = "Level / Percent / Current", text = "Level / Percent / Current" },
	{ value = "LEVELPERCENTCURMAX", label = "Level / Percent / Current / Max", text = "Level / Percent / Current / Max" },
	{ value = "NONE", label = "None", text = "None" },
}

local delimiterOptions = {
	{ value = " ", label = "Space", text = "Space" },
	{ value = "  ", label = "Double space", text = "Double space" },
	{ value = "/", label = "/", text = "/" },
	{ value = ":", label = ":", text = ":" },
	{ value = "-", label = "-", text = "-" },
	{ value = "|", label = "|", text = "|" },
}

local function textureOptions()
	local list = {}
	local seen = {}
	local function add(value, label)
		local lv = tostring(value or ""):lower()
		if lv == "" or seen[lv] then return end
		seen[lv] = true
		list[#list + 1] = { value = value, label = label }
	end
	add("DEFAULT", "Default (Blizzard)")
	add("SOLID", "Solid")
	if not LSM then return list end
	local hash = LSM:HashTable("statusbar") or {}
	for name, path in pairs(hash) do
		if type(path) == "string" and path ~= "" then add(name, tostring(name)) end
	end
	table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
	return list
end

local function ensureAuraConfig(cfg)
	cfg.auras = cfg.auras or {}
	cfg.auras.buff = cfg.auras.buff or {}
	cfg.auras.debuff = cfg.auras.debuff or {}
	cfg.auras.externals = cfg.auras.externals or {}
	return cfg.auras
end

local function syncAurasEnabled(cfg)
	local ac = ensureAuraConfig(cfg)
	local enabled = false
	if ac.buff.enabled then enabled = true end
	if ac.debuff.enabled then enabled = true end
	if ac.externals.enabled then enabled = true end
	ac.enabled = enabled
end

local function buildEditModeSettings(kind, editModeId)
	if not SettingType then return nil end

	local widthLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH or "Width"
	local heightLabel = HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT or "Height"
	local specOptions = buildSpecOptions()
	local settings = {
		{
			name = "Frame",
			kind = SettingType.Collapsible,
			id = "frame",
			defaultCollapsed = false,
		},
		{
			name = "Enabled",
			kind = SettingType.Checkbox,
			field = "enabled",
			default = (DEFAULTS[kind] and DEFAULTS[kind].enabled) or false,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "enabled", cfg.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = widthLabel,
			kind = SettingType.Slider,
			allowInput = true,
			field = "width",
			minValue = 40,
			maxValue = 600,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].width) or 100,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.width or (DEFAULTS[kind] and DEFAULTS[kind].width) or 100
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 40, 600, cfg.width or 100)
				cfg.width = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "width", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = heightLabel,
			kind = SettingType.Slider,
			allowInput = true,
			field = "height",
			minValue = 10,
			maxValue = 200,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].height) or 24,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.height or (DEFAULTS[kind] and DEFAULTS[kind].height) or 24
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 10, 200, cfg.height or 24)
				cfg.height = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "height", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Power height",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerHeight",
			minValue = 0,
			maxValue = 50,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6,
			parentId = "frame",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.powerHeight or (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 50, cfg.powerHeight or 6)
				cfg.powerHeight = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerHeight", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Layout",
			kind = SettingType.Collapsible,
			id = "layout",
			defaultCollapsed = false,
		},
		{
			name = "Spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "spacing",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0,
			parentId = "layout",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.spacing or (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 40, cfg.spacing or 0)
				cfg.spacing = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "spacing", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Growth",
			kind = SettingType.Dropdown,
			field = "growth",
			parentId = "layout",
			get = function()
				local cfg = getCfg(kind)
				return (cfg and cfg.growth) or (DEFAULTS[kind] and DEFAULTS[kind].growth) or "DOWN"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg or not value then return end
				cfg.growth = tostring(value):upper()
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "growth", cfg.growth, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				local options = {
					{ value = "DOWN", label = "Down" },
					{ value = "RIGHT", label = "Right" },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						return (cfg and cfg.growth) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.growth = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "growth", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Text",
			kind = SettingType.Collapsible,
			id = "text",
			defaultCollapsed = true,
		},
		{
			name = "Name class color",
			kind = SettingType.Checkbox,
			field = "nameClassColor",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				if sc.nameColorMode then return sc.nameColorMode == "CLASS" end
				local tc = cfg and cfg.text or {}
				return tc.useClassColor ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.status = cfg.status or {}
				cfg.text.useClassColor = value and true or false
				cfg.status.nameColorMode = value and "CLASS" or "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameClassColor", cfg.text.useClassColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Name color",
			kind = SettingType.Color,
			field = "nameColor",
			parentId = "text",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.nameColor) or { 1, 1, 1, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.nameColor) or { 1, 1, 1, 1 }
				local r, g, b, a = unpackColor(sc.nameColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.text = cfg.text or {}
				cfg.status.nameColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				cfg.status.nameColorMode = "CUSTOM"
				cfg.text.useClassColor = false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameColor", cfg.status.nameColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local mode = sc.nameColorMode
				if not mode then
					local tc = cfg and cfg.text or {}
					mode = (tc.useClassColor ~= false) and "CLASS" or "CUSTOM"
				end
				return mode == "CUSTOM"
			end,
		},
		{
			name = "Name max width",
			kind = SettingType.Slider,
			allowInput = true,
			field = "nameMaxChars",
			parentId = "text",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0,
			get = function()
				local cfg = getCfg(kind)
				local tc = cfg and cfg.text or {}
				return tc.nameMaxChars or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.text = cfg.text or {}
				cfg.text.nameMaxChars = clampNumber(value, 0, 40, cfg.text.nameMaxChars or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "nameMaxChars", cfg.text.nameMaxChars, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Health class color",
			kind = SettingType.Checkbox,
			field = "healthClassColor",
			parentId = "text",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useClassColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useClassColor = value and true or false
				if value then cfg.health.useCustomColor = false end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthClassColor", cfg.health.useClassColor, nil, true) end
				if EditMode and EditMode.SetValue and value then EditMode:SetValue(editModeId, "healthUseCustomColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Health",
			kind = SettingType.Collapsible,
			id = "health",
			defaultCollapsed = true,
		},
		{
			name = "Show absorb bar",
			kind = SettingType.Checkbox,
			field = "absorbEnabled",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbEnabled", cfg.health.absorbEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Absorb texture",
			kind = SettingType.Dropdown,
			field = "absorbTexture",
			parentId = "health",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbTexture or "SOLID"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbTexture = value or "SOLID"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbTexture", cfg.health.absorbTexture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.absorbTexture or "SOLID") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.absorbTexture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Absorb reverse fill",
			kind = SettingType.Checkbox,
			field = "absorbReverse",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbReverseFill == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbReverseFill = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbReverse", cfg.health.absorbReverseFill, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Custom absorb color",
			kind = SettingType.Checkbox,
			field = "absorbUseCustomColor",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbUseCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbUseCustomColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbUseCustomColor", cfg.health.absorbUseCustomColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false
			end,
		},
		{
			name = "Absorb color",
			kind = SettingType.Color,
			field = "absorbColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.absorbColor) or { 0.85, 0.95, 1, 0.7 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.absorbColor) or { 0.85, 0.95, 1, 0.7 }
				local r, g, b, a = unpackColor(hc.absorbColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.absorbColor = { value.r or 0.85, value.g or 0.95, value.b or 1, value.a or 0.7 }
				cfg.health.absorbUseCustomColor = true
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbColor", cfg.health.absorbColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbUseCustomColor", true, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.absorbEnabled ~= false and hc.absorbUseCustomColor == true
			end,
		},
		{
			name = "Show heal absorb bar",
			kind = SettingType.Checkbox,
			field = "healAbsorbEnabled",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbEnabled", cfg.health.healAbsorbEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Heal absorb texture",
			kind = SettingType.Dropdown,
			field = "healAbsorbTexture",
			parentId = "health",
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbTexture or "SOLID"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbTexture = value or "SOLID"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbTexture", cfg.health.healAbsorbTexture, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.healAbsorbTexture or "SOLID") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.healAbsorbTexture = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbTexture", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Heal absorb reverse fill",
			kind = SettingType.Checkbox,
			field = "healAbsorbReverse",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbReverseFill == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbReverseFill = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbReverse", cfg.health.healAbsorbReverseFill, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Custom heal absorb color",
			kind = SettingType.Checkbox,
			field = "healAbsorbUseCustomColor",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbUseCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbUseCustomColor = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbUseCustomColor", cfg.health.healAbsorbUseCustomColor, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false
			end,
		},
		{
			name = "Heal absorb color",
			kind = SettingType.Color,
			field = "healAbsorbColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 }
				local r, g, b, a = unpackColor(hc.healAbsorbColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.healAbsorbColor = { value.r or 1, value.g or 0.3, value.b or 0.3, value.a or 0.7 }
				cfg.health.healAbsorbUseCustomColor = true
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbColor", cfg.health.healAbsorbColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healAbsorbUseCustomColor", true, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.healAbsorbEnabled ~= false and hc.healAbsorbUseCustomColor == true
			end,
		},
		{
			name = "Absorb glow",
			kind = SettingType.Checkbox,
			field = "absorbGlow",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useAbsorbGlow ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useAbsorbGlow = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "absorbGlow", cfg.health.useAbsorbGlow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Use custom health color",
			kind = SettingType.Checkbox,
			field = "healthUseCustomColor",
			parentId = "health",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useCustomColor == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useCustomColor = value and true or false
				if value then cfg.health.useClassColor = false end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthUseCustomColor", cfg.health.useCustomColor, nil, true) end
				if EditMode and EditMode.SetValue and value then EditMode:SetValue(editModeId, "healthClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Health color",
			kind = SettingType.Color,
			field = "healthColor",
			parentId = "health",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 },
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 }
				local r, g, b, a = unpackColor(hc.color, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.health = cfg.health or {}
				cfg.health.color = { value.r or 0, value.g or 0.8, value.b or 0, value.a or 1 }
				cfg.health.useCustomColor = true
				cfg.health.useClassColor = false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthColor", cfg.health.color, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthUseCustomColor", true, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.useCustomColor == true
			end,
		},
		{
			name = "Health text",
			kind = SettingType.Collapsible,
			id = "healthtext",
			defaultCollapsed = true,
		},
		{
			name = "Health text left",
			kind = SettingType.Dropdown,
			field = "healthTextLeft",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textLeft = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextLeft", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textLeft = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextLeft", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health text center",
			kind = SettingType.Dropdown,
			field = "healthTextCenter",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textCenter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextCenter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textCenter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextCenter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health text right",
			kind = SettingType.Dropdown,
			field = "healthTextRight",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textRight or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textRight = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextRight", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textRight or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textRight = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthTextRight", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiter",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						return (hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " ") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health secondary delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiterSecondary",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
				return hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiterSecondary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterSecondary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
						return (hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiterSecondary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterSecondary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Health tertiary delimiter",
			kind = SettingType.Dropdown,
			field = "healthDelimiterTertiary",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
				local secondary = hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
				return hc.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary) or secondary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.textDelimiterTertiary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterTertiary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local hc = cfg and cfg.health or {}
						local primary = hc.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "
						local secondary = hc.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or primary
						return (hc.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary) or secondary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.health = cfg.health or {}
						cfg.health.textDelimiterTertiary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthDelimiterTertiary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Short numbers",
			kind = SettingType.Checkbox,
			field = "healthShortNumbers",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				if hc.useShortNumbers == nil then
					return (DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.useShortNumbers) ~= false
				end
				return hc.useShortNumbers ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.useShortNumbers = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthShortNumbers", cfg.health.useShortNumbers, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Hide percent symbol",
			kind = SettingType.Checkbox,
			field = "healthHidePercent",
			parentId = "healthtext",
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return hc.hidePercentSymbol == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.hidePercentSymbol = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthHidePercent", cfg.health.hidePercentSymbol, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Left text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthLeftX",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetLeft and hc.offsetLeft.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetLeft = cfg.health.offsetLeft or {}
				cfg.health.offsetLeft.x = clampNumber(value, -200, 200, (cfg.health.offsetLeft and cfg.health.offsetLeft.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthLeftX", cfg.health.offsetLeft.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Left text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthLeftY",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetLeft and hc.offsetLeft.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetLeft = cfg.health.offsetLeft or {}
				cfg.health.offsetLeft.y = clampNumber(value, -200, 200, (cfg.health.offsetLeft and cfg.health.offsetLeft.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthLeftY", cfg.health.offsetLeft.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Center text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthCenterX",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetCenter and hc.offsetCenter.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetCenter = cfg.health.offsetCenter or {}
				cfg.health.offsetCenter.x = clampNumber(value, -200, 200, (cfg.health.offsetCenter and cfg.health.offsetCenter.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthCenterX", cfg.health.offsetCenter.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Center text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthCenterY",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetCenter and hc.offsetCenter.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetCenter = cfg.health.offsetCenter or {}
				cfg.health.offsetCenter.y = clampNumber(value, -200, 200, (cfg.health.offsetCenter and cfg.health.offsetCenter.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthCenterY", cfg.health.offsetCenter.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Right text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthRightX",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetRight and hc.offsetRight.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetRight = cfg.health.offsetRight or {}
				cfg.health.offsetRight.x = clampNumber(value, -200, 200, (cfg.health.offsetRight and cfg.health.offsetRight.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthRightX", cfg.health.offsetRight.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Right text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "healthRightY",
			parentId = "healthtext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local hc = cfg and cfg.health or {}
				return (hc.offsetRight and hc.offsetRight.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.health = cfg.health or {}
				cfg.health.offsetRight = cfg.health.offsetRight or {}
				cfg.health.offsetRight.y = clampNumber(value, -200, 200, (cfg.health.offsetRight and cfg.health.offsetRight.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "healthRightY", cfg.health.offsetRight.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Level",
			kind = SettingType.Collapsible,
			id = "level",
			defaultCollapsed = true,
		},
		{
			name = "Show level",
			kind = SettingType.Checkbox,
			field = "levelEnabled",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelEnabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelEnabled", cfg.status.levelEnabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Hide level at max",
			kind = SettingType.Checkbox,
			field = "hideLevelAtMax",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.hideLevelAtMax == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.hideLevelAtMax = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "hideLevelAtMax", cfg.status.hideLevelAtMax, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level class color",
			kind = SettingType.Checkbox,
			field = "levelClassColor",
			parentId = "level",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelColorMode or "CUSTOM") == "CLASS"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelColorMode = value and "CLASS" or "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelClassColor", value and true or false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level color",
			kind = SettingType.Color,
			field = "levelColor",
			parentId = "level",
			hasOpacity = true,
			default = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.levelColor) or { 1, 0.85, 0, 1 },
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local def = (DEFAULTS[kind] and DEFAULTS[kind].status and DEFAULTS[kind].status.levelColor) or { 1, 0.85, 0, 1 }
				local r, g, b, a = unpackColor(sc.levelColor, def)
				return { r = r, g = g, b = b, a = a }
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not (cfg and value) then return end
				cfg.status = cfg.status or {}
				cfg.status.levelColor = { value.r or 1, value.g or 1, value.b or 1, value.a or 1 }
				cfg.status.levelColorMode = "CUSTOM"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelColor", cfg.status.levelColor, nil, true) end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelClassColor", false, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false and (sc.levelColorMode or "CUSTOM") == "CUSTOM"
			end,
		},
		{
			name = "Level anchor",
			kind = SettingType.Dropdown,
			field = "levelAnchor",
			parentId = "level",
			values = textAnchorOptions,
			height = 120,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelAnchor or "RIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelAnchor = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "levelOffsetX",
			parentId = "level",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelOffset and sc.levelOffset.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelOffset = cfg.status.levelOffset or {}
				cfg.status.levelOffset.x = clampNumber(value, -200, 200, (cfg.status.levelOffset and cfg.status.levelOffset.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelOffsetX", cfg.status.levelOffset.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Level offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "levelOffsetY",
			parentId = "level",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return (sc.levelOffset and sc.levelOffset.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.levelOffset = cfg.status.levelOffset or {}
				cfg.status.levelOffset.y = clampNumber(value, -200, 200, (cfg.status.levelOffset and cfg.status.levelOffset.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "levelOffsetY", cfg.status.levelOffset.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				return sc.levelEnabled ~= false
			end,
		},
		{
			name = "Group icons",
			kind = SettingType.Collapsible,
			id = "groupicons",
			defaultCollapsed = true,
		},
		{
			name = "Show leader icon",
			kind = SettingType.Checkbox,
			field = "leaderIconEnabled",
			parentId = "groupicons",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconEnabled", cfg.status.leaderIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Leader icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconSize",
			parentId = "groupicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.size or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.size = clampNumber(value, 8, 40, cfg.status.leaderIcon.size or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconSize", cfg.status.leaderIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon anchor",
			kind = SettingType.Dropdown,
			field = "leaderIconPoint",
			parentId = "groupicons",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.point or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.point = value
				cfg.status.leaderIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconOffsetX",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.x = clampNumber(value, -200, 200, cfg.status.leaderIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconOffsetX", cfg.status.leaderIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Leader icon offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "leaderIconOffsetY",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.leaderIcon = cfg.status.leaderIcon or {}
				cfg.status.leaderIcon.y = clampNumber(value, -200, 200, cfg.status.leaderIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "leaderIconOffsetY", cfg.status.leaderIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local lc = sc.leaderIcon or {}
				return lc.enabled ~= false
			end,
		},
		{
			name = "Show assist icon",
			kind = SettingType.Checkbox,
			field = "assistIconEnabled",
			parentId = "groupicons",
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconEnabled", cfg.status.assistIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Assist icon size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconSize",
			parentId = "groupicons",
			minValue = 8,
			maxValue = 40,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.size or 12
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.size = clampNumber(value, 8, 40, cfg.status.assistIcon.size or 12)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconSize", cfg.status.assistIcon.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
		},
		{
			name = "Assist icon anchor",
			kind = SettingType.Dropdown,
			field = "assistIconPoint",
			parentId = "groupicons",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.point or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.point = value
				cfg.status.assistIcon.relativePoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconPoint", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
		},
		{
			name = "Assist icon offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconOffsetX",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.x = clampNumber(value, -200, 200, cfg.status.assistIcon.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconOffsetX", cfg.status.assistIcon.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
		},
		{
			name = "Assist icon offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "assistIconOffsetY",
			parentId = "groupicons",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.status = cfg.status or {}
				cfg.status.assistIcon = cfg.status.assistIcon or {}
				cfg.status.assistIcon.y = clampNumber(value, -200, 200, cfg.status.assistIcon.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "assistIconOffsetY", cfg.status.assistIcon.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local sc = cfg and cfg.status or {}
				local acfg = sc.assistIcon or {}
				return acfg.enabled ~= false
			end,
		},
		{
			name = "Role icons",
			kind = SettingType.Collapsible,
			id = "roleicons",
			defaultCollapsed = true,
		},
		{
			name = "Enable role icons",
			kind = SettingType.Checkbox,
			field = "roleIconEnabled",
			parentId = "roleicons",
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.enabled = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconEnabled", cfg.roleIcon.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Role icon style",
			kind = SettingType.Dropdown,
			field = "roleIconStyle",
			parentId = "roleicons",
			get = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.style or "TINY"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				cfg.roleIcon.style = value or "TINY"
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconStyle", cfg.roleIcon.style, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				local options = {
					{ value = "TINY", label = "Icon" },
					{ value = "CIRCLE", label = "Icon + Circle" },
				}
				for _, option in ipairs(options) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local rc = cfg and cfg.roleIcon or {}
						return (rc.style or "TINY") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.roleIcon = cfg.roleIcon or {}
						cfg.roleIcon.style = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconStyle", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Show role icons for roles",
			kind = SettingType.MultiDropdown,
			field = "roleIconRoles",
			height = 120,
			values = roleOptions,
			parentId = "roleicons",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				local selection = rc.showRoles
				if type(selection) ~= "table" then return true end
				return selectionContains(selection, value)
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.roleIcon = cfg.roleIcon or {}
				local selection = cfg.roleIcon.showRoles
				if type(selection) ~= "table" then
					selection = defaultRoleSelection()
					cfg.roleIcon.showRoles = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "roleIconRoles", copySelectionMap(selection), nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			isEnabled = function()
				local cfg = getCfg(kind)
				local rc = cfg and cfg.roleIcon or {}
				return rc.enabled ~= false
			end,
		},
		{
			name = "Power",
			kind = SettingType.Collapsible,
			id = "power",
			defaultCollapsed = true,
		},
		{
			name = "Show power for roles",
			kind = SettingType.MultiDropdown,
			field = "powerRoles",
			height = 140,
			values = roleOptions,
			parentId = "power",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local selection = pcfg.showRoles
				if type(selection) ~= "table" then return true end
				return selectionContains(selection, value)
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				local selection = cfg.power.showRoles
				if type(selection) ~= "table" then
					selection = defaultRoleSelection()
					cfg.power.showRoles = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRoles", copySelectionMap(selection), nil, true) end
				GF:RefreshPowerVisibility()
			end,
		},
		{
			name = "Show power for specs",
			kind = SettingType.MultiDropdown,
			field = "powerSpecs",
			height = 240,
			values = specOptions,
			parentId = "power",
			isSelected = function(_, value)
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local selection = pcfg.showSpecs
				if type(selection) ~= "table" then return true end
				return selectionContains(selection, value)
			end,
			setSelected = function(_, value, state)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				local selection = cfg.power.showSpecs
				if type(selection) ~= "table" then
					selection = defaultSpecSelection()
					cfg.power.showSpecs = selection
				end
				if state then
					selection[value] = true
				else
					selection[value] = nil
				end
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerSpecs", copySelectionMap(selection), nil, true) end
				GF:RefreshPowerVisibility()
			end,
		},
		{
			name = "Power text",
			kind = SettingType.Collapsible,
			id = "powertext",
			defaultCollapsed = true,
		},
		{
			name = "Power text left",
			kind = SettingType.Dropdown,
			field = "powerTextLeft",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textLeft = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextLeft", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textLeft or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textLeft = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextLeft", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power text center",
			kind = SettingType.Dropdown,
			field = "powerTextCenter",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textCenter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextCenter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textCenter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textCenter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextCenter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power text right",
			kind = SettingType.Dropdown,
			field = "powerTextRight",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textRight or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textRight = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextRight", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(textModeOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textRight or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textRight = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerTextRight", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiter",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiter = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiter", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						return (pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " ") == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiter = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiter", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power secondary delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiterSecondary",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
				return pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiterSecondary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterSecondary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
						return (pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiterSecondary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterSecondary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Power tertiary delimiter",
			kind = SettingType.Dropdown,
			field = "powerDelimiterTertiary",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
				local secondary = pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
				return pcfg.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or secondary
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.textDelimiterTertiary = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterTertiary", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
			generator = function(_, root)
				for _, option in ipairs(delimiterOptions) do
					root:CreateRadio(option.label, function()
						local cfg = getCfg(kind)
						local pcfg = cfg and cfg.power or {}
						local primary = pcfg.textDelimiter or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "
						local secondary = pcfg.textDelimiterSecondary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or primary
						return (pcfg.textDelimiterTertiary or (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or secondary) == option.value
					end, function()
						local cfg = getCfg(kind)
						if not cfg then return end
						cfg.power = cfg.power or {}
						cfg.power.textDelimiterTertiary = option.value
						if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerDelimiterTertiary", option.value, nil, true) end
						GF:ApplyHeaderAttributes(kind)
					end)
				end
			end,
		},
		{
			name = "Short numbers",
			kind = SettingType.Checkbox,
			field = "powerShortNumbers",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				if pcfg.useShortNumbers == nil then
					return (DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.useShortNumbers) ~= false
				end
				return pcfg.useShortNumbers ~= false
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.useShortNumbers = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerShortNumbers", cfg.power.useShortNumbers, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Hide percent symbol",
			kind = SettingType.Checkbox,
			field = "powerHidePercent",
			parentId = "powertext",
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return pcfg.hidePercentSymbol == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.hidePercentSymbol = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerHidePercent", cfg.power.hidePercentSymbol, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Left text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerLeftX",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetLeft and pcfg.offsetLeft.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetLeft = cfg.power.offsetLeft or {}
				cfg.power.offsetLeft.x = clampNumber(value, -200, 200, (cfg.power.offsetLeft and cfg.power.offsetLeft.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerLeftX", cfg.power.offsetLeft.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Left text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerLeftY",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetLeft and pcfg.offsetLeft.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetLeft = cfg.power.offsetLeft or {}
				cfg.power.offsetLeft.y = clampNumber(value, -200, 200, (cfg.power.offsetLeft and cfg.power.offsetLeft.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerLeftY", cfg.power.offsetLeft.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Center text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerCenterX",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetCenter and pcfg.offsetCenter.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetCenter = cfg.power.offsetCenter or {}
				cfg.power.offsetCenter.x = clampNumber(value, -200, 200, (cfg.power.offsetCenter and cfg.power.offsetCenter.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerCenterX", cfg.power.offsetCenter.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Center text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerCenterY",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetCenter and pcfg.offsetCenter.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetCenter = cfg.power.offsetCenter or {}
				cfg.power.offsetCenter.y = clampNumber(value, -200, 200, (cfg.power.offsetCenter and cfg.power.offsetCenter.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerCenterY", cfg.power.offsetCenter.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Right text offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerRightX",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetRight and pcfg.offsetRight.x) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetRight = cfg.power.offsetRight or {}
				cfg.power.offsetRight.x = clampNumber(value, -200, 200, (cfg.power.offsetRight and cfg.power.offsetRight.x) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRightX", cfg.power.offsetRight.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Right text offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "powerRightY",
			parentId = "powertext",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local pcfg = cfg and cfg.power or {}
				return (pcfg.offsetRight and pcfg.offsetRight.y) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.power = cfg.power or {}
				cfg.power.offsetRight = cfg.power.offsetRight or {}
				cfg.power.offsetRight.y = clampNumber(value, -200, 200, (cfg.power.offsetRight and cfg.power.offsetRight.y) or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "powerRightY", cfg.power.offsetRight.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buffs",
			kind = SettingType.Collapsible,
			id = "buffs",
			defaultCollapsed = true,
		},
		{
			name = "Enable buffs",
			kind = SettingType.Checkbox,
			field = "buffsEnabled",
			parentId = "buffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffsEnabled", ac.buff.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff anchor",
			kind = SettingType.Dropdown,
			field = "buffAnchor",
			parentId = "buffs",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.anchorPoint or "TOPLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffOffsetX",
			parentId = "buffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.x = clampNumber(value, -200, 200, ac.buff.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffOffsetX", ac.buff.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffOffsetY",
			parentId = "buffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.y = clampNumber(value, -200, 200, ac.buff.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffOffsetY", ac.buff.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffSize",
			parentId = "buffs",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.size = clampNumber(value, 8, 60, ac.buff.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffSize", ac.buff.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffPerRow",
			parentId = "buffs",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.perRow = clampNumber(value, 1, 12, ac.buff.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffPerRow", ac.buff.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffMax",
			parentId = "buffs",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.max or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.max = clampNumber(value, 0, 20, ac.buff.max or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffMax", ac.buff.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Buff spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "buffSpacing",
			parentId = "buffs",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.buff.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.buff.spacing = clampNumber(value, 0, 10, ac.buff.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "buffSpacing", ac.buff.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuffs",
			kind = SettingType.Collapsible,
			id = "debuffs",
			defaultCollapsed = true,
		},
		{
			name = "Enable debuffs",
			kind = SettingType.Checkbox,
			field = "debuffsEnabled",
			parentId = "debuffs",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffsEnabled", ac.debuff.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff anchor",
			kind = SettingType.Dropdown,
			field = "debuffAnchor",
			parentId = "debuffs",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.anchorPoint or "BOTTOMLEFT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffOffsetX",
			parentId = "debuffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.x = clampNumber(value, -200, 200, ac.debuff.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffOffsetX", ac.debuff.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffOffsetY",
			parentId = "debuffs",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.y = clampNumber(value, -200, 200, ac.debuff.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffOffsetY", ac.debuff.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffSize",
			parentId = "debuffs",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.size = clampNumber(value, 8, 60, ac.debuff.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffSize", ac.debuff.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffPerRow",
			parentId = "debuffs",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.perRow = clampNumber(value, 1, 12, ac.debuff.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffPerRow", ac.debuff.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffMax",
			parentId = "debuffs",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.max or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.max = clampNumber(value, 0, 20, ac.debuff.max or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffMax", ac.debuff.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Debuff spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "debuffSpacing",
			parentId = "debuffs",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.debuff.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.debuff.spacing = clampNumber(value, 0, 10, ac.debuff.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "debuffSpacing", ac.debuff.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "Externals",
			kind = SettingType.Collapsible,
			id = "externals",
			defaultCollapsed = true,
		},
		{
			name = "Enable externals",
			kind = SettingType.Checkbox,
			field = "externalsEnabled",
			parentId = "externals",
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.enabled == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.enabled = value and true or false
				syncAurasEnabled(cfg)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalsEnabled", ac.externals.enabled, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External anchor",
			kind = SettingType.Dropdown,
			field = "externalAnchor",
			parentId = "externals",
			values = auraAnchorOptions,
			height = 180,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.anchorPoint or "TOPRIGHT"
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.anchorPoint = value
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalAnchor", value, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External offset X",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalOffsetX",
			parentId = "externals",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.x or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.x = clampNumber(value, -200, 200, ac.externals.x or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalOffsetX", ac.externals.x, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External offset Y",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalOffsetY",
			parentId = "externals",
			minValue = -200,
			maxValue = 200,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.y or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.y = clampNumber(value, -200, 200, ac.externals.y or 0)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalOffsetY", ac.externals.y, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External size",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalSize",
			parentId = "externals",
			minValue = 8,
			maxValue = 60,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.size or 16
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.size = clampNumber(value, 8, 60, ac.externals.size or 16)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalSize", ac.externals.size, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External per row",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalPerRow",
			parentId = "externals",
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.perRow or 6
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.perRow = clampNumber(value, 1, 12, ac.externals.perRow or 6)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalPerRow", ac.externals.perRow, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External max",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalMax",
			parentId = "externals",
			minValue = 0,
			maxValue = 20,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.max or 4
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.max = clampNumber(value, 0, 20, ac.externals.max or 4)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalMax", ac.externals.max, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
		{
			name = "External spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "externalSpacing",
			parentId = "externals",
			minValue = 0,
			maxValue = 10,
			valueStep = 1,
			get = function()
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				return ac.externals.spacing or 2
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				local ac = ensureAuraConfig(cfg)
				ac.externals.spacing = clampNumber(value, 0, 10, ac.externals.spacing or 2)
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "externalSpacing", ac.externals.spacing, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		},
	}

	if kind == "party" then
		settings[#settings + 1] = {
			name = "Party",
			kind = SettingType.Collapsible,
			id = "party",
			defaultCollapsed = false,
		}
		settings[#settings + 1] = {
			name = "Show player",
			kind = SettingType.Checkbox,
			field = "showPlayer",
			default = (DEFAULTS.party and DEFAULTS.party.showPlayer) or false,
			parentId = "party",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.showPlayer == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.showPlayer = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "showPlayer", cfg.showPlayer, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Show solo",
			kind = SettingType.Checkbox,
			field = "showSolo",
			default = (DEFAULTS.party and DEFAULTS.party.showSolo) or false,
			parentId = "party",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.showSolo == true
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				cfg.showSolo = value and true or false
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "showSolo", cfg.showSolo, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
	elseif kind == "raid" then
		settings[#settings + 1] = {
			name = "Raid",
			kind = SettingType.Collapsible,
			id = "raid",
			defaultCollapsed = false,
		}
		settings[#settings + 1] = {
			name = "Units per column",
			kind = SettingType.Slider,
			allowInput = true,
			field = "unitsPerColumn",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.unitsPerColumn or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 1, 10, cfg.unitsPerColumn or 5)
				v = floor(v + 0.5)
				cfg.unitsPerColumn = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "unitsPerColumn", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Max columns",
			kind = SettingType.Slider,
			allowInput = true,
			field = "maxColumns",
			minValue = 1,
			maxValue = 10,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.maxColumns or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 1, 10, cfg.maxColumns or 8)
				v = floor(v + 0.5)
				cfg.maxColumns = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "maxColumns", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
		settings[#settings + 1] = {
			name = "Column spacing",
			kind = SettingType.Slider,
			allowInput = true,
			field = "columnSpacing",
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			default = (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
			parentId = "raid",
			get = function()
				local cfg = getCfg(kind)
				return cfg and cfg.columnSpacing or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0
			end,
			set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				local v = clampNumber(value, 0, 40, cfg.columnSpacing or 0)
				cfg.columnSpacing = v
				if EditMode and EditMode.SetValue then EditMode:SetValue(editModeId, "columnSpacing", v, nil, true) end
				GF:ApplyHeaderAttributes(kind)
			end,
		}
	end

	return settings
end

local function applyEditModeData(kind, data)
	if not data then return end
	local cfg = getCfg(kind)
	if not cfg then return end

	if data.point then
		cfg.point = data.point
		cfg.relativePoint = data.relativePoint or data.point
		cfg.x = data.x or 0
		cfg.y = data.y or 0
		if not cfg.relativeTo or cfg.relativeTo == "" then cfg.relativeTo = "UIParent" end
	end

	if data.width ~= nil then cfg.width = clampNumber(data.width, 40, 600, cfg.width or 100) end
	if data.height ~= nil then cfg.height = clampNumber(data.height, 10, 200, cfg.height or 24) end
	if data.powerHeight ~= nil then cfg.powerHeight = clampNumber(data.powerHeight, 0, 50, cfg.powerHeight or 6) end
	if data.spacing ~= nil then cfg.spacing = clampNumber(data.spacing, 0, 40, cfg.spacing or 0) end
	if data.growth then cfg.growth = tostring(data.growth):upper() end
	if data.enabled ~= nil then cfg.enabled = data.enabled and true or false end
	if data.nameClassColor ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.useClassColor = data.nameClassColor and true or false
		cfg.status = cfg.status or {}
		cfg.status.nameColorMode = data.nameClassColor and "CLASS" or "CUSTOM"
	end
	if data.nameMaxChars ~= nil then
		cfg.text = cfg.text or {}
		cfg.text.nameMaxChars = clampNumber(data.nameMaxChars, 0, 40, cfg.text.nameMaxChars or 0)
	end
	if data.healthClassColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useClassColor = data.healthClassColor and true or false
		if data.healthClassColor then cfg.health.useCustomColor = false end
	end
	if data.healthUseCustomColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useCustomColor = data.healthUseCustomColor and true or false
		if data.healthUseCustomColor then cfg.health.useClassColor = false end
	end
	if data.healthColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.color = data.healthColor
		cfg.health.useCustomColor = true
		cfg.health.useClassColor = false
	end
	if data.healthTextLeft ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textLeft = data.healthTextLeft
	end
	if data.healthTextCenter ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textCenter = data.healthTextCenter
	end
	if data.healthTextRight ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textRight = data.healthTextRight
	end
	if data.healthDelimiter ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiter = data.healthDelimiter
	end
	if data.healthDelimiterSecondary ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiterSecondary = data.healthDelimiterSecondary
	end
	if data.healthDelimiterTertiary ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.textDelimiterTertiary = data.healthDelimiterTertiary
	end
	if data.healthShortNumbers ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useShortNumbers = data.healthShortNumbers and true or false
	end
	if data.healthHidePercent ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.hidePercentSymbol = data.healthHidePercent and true or false
	end
	if data.healthLeftX ~= nil or data.healthLeftY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetLeft = cfg.health.offsetLeft or {}
		if data.healthLeftX ~= nil then cfg.health.offsetLeft.x = data.healthLeftX end
		if data.healthLeftY ~= nil then cfg.health.offsetLeft.y = data.healthLeftY end
	end
	if data.healthCenterX ~= nil or data.healthCenterY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetCenter = cfg.health.offsetCenter or {}
		if data.healthCenterX ~= nil then cfg.health.offsetCenter.x = data.healthCenterX end
		if data.healthCenterY ~= nil then cfg.health.offsetCenter.y = data.healthCenterY end
	end
	if data.healthRightX ~= nil or data.healthRightY ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.offsetRight = cfg.health.offsetRight or {}
		if data.healthRightX ~= nil then cfg.health.offsetRight.x = data.healthRightX end
		if data.healthRightY ~= nil then cfg.health.offsetRight.y = data.healthRightY end
	end
	if data.absorbEnabled ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbEnabled = data.absorbEnabled and true or false
	end
	if data.absorbTexture ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbTexture = data.absorbTexture
	end
	if data.absorbReverse ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbReverseFill = data.absorbReverse and true or false
	end
	if data.absorbUseCustomColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbUseCustomColor = data.absorbUseCustomColor and true or false
	end
	if data.absorbColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.absorbColor = data.absorbColor
	end
	if data.healAbsorbEnabled ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbEnabled = data.healAbsorbEnabled and true or false
	end
	if data.healAbsorbTexture ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbTexture = data.healAbsorbTexture
	end
	if data.healAbsorbReverse ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbReverseFill = data.healAbsorbReverse and true or false
	end
	if data.healAbsorbUseCustomColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbUseCustomColor = data.healAbsorbUseCustomColor and true or false
	end
	if data.healAbsorbColor ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.healAbsorbColor = data.healAbsorbColor
	end
	if data.absorbGlow ~= nil then
		cfg.health = cfg.health or {}
		cfg.health.useAbsorbGlow = data.absorbGlow and true or false
	end
	if data.nameColorMode ~= nil or data.nameColor ~= nil or data.levelEnabled ~= nil or data.levelColorMode ~= nil or data.levelColor ~= nil or data.hideLevelAtMax ~= nil or data.levelClassColor ~= nil then
		cfg.status = cfg.status or {}
	end
	if data.nameColorMode ~= nil then
		cfg.status.nameColorMode = data.nameColorMode
		cfg.text = cfg.text or {}
		cfg.text.useClassColor = data.nameColorMode == "CLASS"
	end
	if data.nameColor ~= nil then
		cfg.status.nameColor = data.nameColor
	end
	if data.levelEnabled ~= nil then
		cfg.status.levelEnabled = data.levelEnabled and true or false
	end
	if data.hideLevelAtMax ~= nil then
		cfg.status.hideLevelAtMax = data.hideLevelAtMax and true or false
	end
	if data.levelClassColor ~= nil then
		cfg.status.levelColorMode = data.levelClassColor and "CLASS" or "CUSTOM"
	end
	if data.levelColorMode ~= nil then
		cfg.status.levelColorMode = data.levelColorMode
	end
	if data.levelColor ~= nil then
		cfg.status.levelColor = data.levelColor
	end
	if data.levelAnchor ~= nil then
		cfg.status.levelAnchor = data.levelAnchor
	end
	if data.levelOffsetX ~= nil or data.levelOffsetY ~= nil then
		cfg.status.levelOffset = cfg.status.levelOffset or {}
		if data.levelOffsetX ~= nil then cfg.status.levelOffset.x = data.levelOffsetX end
		if data.levelOffsetY ~= nil then cfg.status.levelOffset.y = data.levelOffsetY end
	end
	if data.leaderIconEnabled ~= nil or data.leaderIconSize ~= nil or data.leaderIconPoint ~= nil or data.leaderIconOffsetX ~= nil or data.leaderIconOffsetY ~= nil then
		cfg.status.leaderIcon = cfg.status.leaderIcon or {}
		if data.leaderIconEnabled ~= nil then cfg.status.leaderIcon.enabled = data.leaderIconEnabled and true or false end
		if data.leaderIconSize ~= nil then cfg.status.leaderIcon.size = data.leaderIconSize end
		if data.leaderIconPoint ~= nil then
			cfg.status.leaderIcon.point = data.leaderIconPoint
			cfg.status.leaderIcon.relativePoint = data.leaderIconPoint
		end
		if data.leaderIconOffsetX ~= nil then cfg.status.leaderIcon.x = data.leaderIconOffsetX end
		if data.leaderIconOffsetY ~= nil then cfg.status.leaderIcon.y = data.leaderIconOffsetY end
	end
	if data.assistIconEnabled ~= nil or data.assistIconSize ~= nil or data.assistIconPoint ~= nil or data.assistIconOffsetX ~= nil or data.assistIconOffsetY ~= nil then
		cfg.status.assistIcon = cfg.status.assistIcon or {}
		if data.assistIconEnabled ~= nil then cfg.status.assistIcon.enabled = data.assistIconEnabled and true or false end
		if data.assistIconSize ~= nil then cfg.status.assistIcon.size = data.assistIconSize end
		if data.assistIconPoint ~= nil then
			cfg.status.assistIcon.point = data.assistIconPoint
			cfg.status.assistIcon.relativePoint = data.assistIconPoint
		end
		if data.assistIconOffsetX ~= nil then cfg.status.assistIcon.x = data.assistIconOffsetX end
		if data.assistIconOffsetY ~= nil then cfg.status.assistIcon.y = data.assistIconOffsetY end
	end
	if data.roleIconEnabled ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.enabled = data.roleIconEnabled and true or false
	end
	if data.roleIconStyle ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.style = data.roleIconStyle
	end
	if data.roleIconRoles ~= nil then
		cfg.roleIcon = cfg.roleIcon or {}
		cfg.roleIcon.showRoles = copySelectionMap(data.roleIconRoles)
	end
	if data.powerRoles ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showRoles = copySelectionMap(data.powerRoles)
	end
	if data.powerSpecs ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.showSpecs = copySelectionMap(data.powerSpecs)
	end
	if data.powerTextLeft ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textLeft = data.powerTextLeft
	end
	if data.powerTextCenter ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textCenter = data.powerTextCenter
	end
	if data.powerTextRight ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textRight = data.powerTextRight
	end
	if data.powerDelimiter ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiter = data.powerDelimiter
	end
	if data.powerDelimiterSecondary ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiterSecondary = data.powerDelimiterSecondary
	end
	if data.powerDelimiterTertiary ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.textDelimiterTertiary = data.powerDelimiterTertiary
	end
	if data.powerShortNumbers ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.useShortNumbers = data.powerShortNumbers and true or false
	end
	if data.powerHidePercent ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.hidePercentSymbol = data.powerHidePercent and true or false
	end
	if data.powerLeftX ~= nil or data.powerLeftY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetLeft = cfg.power.offsetLeft or {}
		if data.powerLeftX ~= nil then cfg.power.offsetLeft.x = data.powerLeftX end
		if data.powerLeftY ~= nil then cfg.power.offsetLeft.y = data.powerLeftY end
	end
	if data.powerCenterX ~= nil or data.powerCenterY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetCenter = cfg.power.offsetCenter or {}
		if data.powerCenterX ~= nil then cfg.power.offsetCenter.x = data.powerCenterX end
		if data.powerCenterY ~= nil then cfg.power.offsetCenter.y = data.powerCenterY end
	end
	if data.powerRightX ~= nil or data.powerRightY ~= nil then
		cfg.power = cfg.power or {}
		cfg.power.offsetRight = cfg.power.offsetRight or {}
		if data.powerRightX ~= nil then cfg.power.offsetRight.x = data.powerRightX end
		if data.powerRightY ~= nil then cfg.power.offsetRight.y = data.powerRightY end
	end

	local ac = ensureAuraConfig(cfg)
	if data.buffsEnabled ~= nil then ac.buff.enabled = data.buffsEnabled and true or false end
	if data.buffAnchor ~= nil then ac.buff.anchorPoint = data.buffAnchor end
	if data.buffOffsetX ~= nil then ac.buff.x = data.buffOffsetX end
	if data.buffOffsetY ~= nil then ac.buff.y = data.buffOffsetY end
	if data.buffSize ~= nil then ac.buff.size = data.buffSize end
	if data.buffPerRow ~= nil then ac.buff.perRow = data.buffPerRow end
	if data.buffMax ~= nil then ac.buff.max = data.buffMax end
	if data.buffSpacing ~= nil then ac.buff.spacing = data.buffSpacing end

	if data.debuffsEnabled ~= nil then ac.debuff.enabled = data.debuffsEnabled and true or false end
	if data.debuffAnchor ~= nil then ac.debuff.anchorPoint = data.debuffAnchor end
	if data.debuffOffsetX ~= nil then ac.debuff.x = data.debuffOffsetX end
	if data.debuffOffsetY ~= nil then ac.debuff.y = data.debuffOffsetY end
	if data.debuffSize ~= nil then ac.debuff.size = data.debuffSize end
	if data.debuffPerRow ~= nil then ac.debuff.perRow = data.debuffPerRow end
	if data.debuffMax ~= nil then ac.debuff.max = data.debuffMax end
	if data.debuffSpacing ~= nil then ac.debuff.spacing = data.debuffSpacing end

	if data.externalsEnabled ~= nil then ac.externals.enabled = data.externalsEnabled and true or false end
	if data.externalAnchor ~= nil then ac.externals.anchorPoint = data.externalAnchor end
	if data.externalOffsetX ~= nil then ac.externals.x = data.externalOffsetX end
	if data.externalOffsetY ~= nil then ac.externals.y = data.externalOffsetY end
	if data.externalSize ~= nil then ac.externals.size = data.externalSize end
	if data.externalPerRow ~= nil then ac.externals.perRow = data.externalPerRow end
	if data.externalMax ~= nil then ac.externals.max = data.externalMax end
	if data.externalSpacing ~= nil then ac.externals.spacing = data.externalSpacing end
	syncAurasEnabled(cfg)

	if kind == "party" then
		if data.showPlayer ~= nil then cfg.showPlayer = data.showPlayer and true or false end
		if data.showSolo ~= nil then cfg.showSolo = data.showSolo and true or false end
	elseif kind == "raid" then
		if data.unitsPerColumn ~= nil then
			local v = clampNumber(data.unitsPerColumn, 1, 10, cfg.unitsPerColumn or 5)
			cfg.unitsPerColumn = floor(v + 0.5)
		end
		if data.maxColumns ~= nil then
			local v = clampNumber(data.maxColumns, 1, 10, cfg.maxColumns or 8)
			cfg.maxColumns = floor(v + 0.5)
		end
		if data.columnSpacing ~= nil then cfg.columnSpacing = clampNumber(data.columnSpacing, 0, 40, cfg.columnSpacing or 0) end
	end

	GF:ApplyHeaderAttributes(kind)
end

function GF:EnsureEditMode()
	if GF._editModeRegistered then return end
	if not isFeatureEnabled() then return end
	if not (EditMode and EditMode.RegisterFrame and EditMode.IsAvailable and EditMode:IsAvailable()) then return end

	GF:EnsureHeaders()

	for _, kind in ipairs({ "party", "raid" }) do
		local anchor = GF.anchors and GF.anchors[kind]
		if anchor then
			GF:UpdateAnchorSize(kind)
			local cfg = getCfg(kind)
			local ac = ensureAuraConfig(cfg)
			local pcfg = cfg.power or {}
			local rc = cfg.roleIcon or {}
			local sc = cfg.status or {}
			local lc = sc.leaderIcon or {}
			local acfg = sc.assistIcon or {}
			local defaults = {
				point = cfg.point or "CENTER",
				relativePoint = cfg.relativePoint or cfg.point or "CENTER",
				x = cfg.x or 0,
				y = cfg.y or 0,
				width = cfg.width or (DEFAULTS[kind] and DEFAULTS[kind].width) or 100,
				height = cfg.height or (DEFAULTS[kind] and DEFAULTS[kind].height) or 24,
				powerHeight = cfg.powerHeight or (DEFAULTS[kind] and DEFAULTS[kind].powerHeight) or 6,
				spacing = cfg.spacing or (DEFAULTS[kind] and DEFAULTS[kind].spacing) or 0,
				growth = cfg.growth or (DEFAULTS[kind] and DEFAULTS[kind].growth) or "DOWN",
				enabled = cfg.enabled == true,
				showPlayer = cfg.showPlayer == true,
				showSolo = cfg.showSolo == true,
				unitsPerColumn = cfg.unitsPerColumn or (DEFAULTS.raid and DEFAULTS.raid.unitsPerColumn) or 5,
				maxColumns = cfg.maxColumns or (DEFAULTS.raid and DEFAULTS.raid.maxColumns) or 8,
				columnSpacing = cfg.columnSpacing or (DEFAULTS.raid and DEFAULTS.raid.columnSpacing) or 0,
				nameClassColor = (cfg.text and cfg.text.useClassColor) ~= false,
				nameMaxChars = (cfg.text and cfg.text.nameMaxChars) or (DEFAULTS[kind] and DEFAULTS[kind].text and DEFAULTS[kind].text.nameMaxChars) or 0,
				healthClassColor = (cfg.health and cfg.health.useClassColor) == true,
				healthUseCustomColor = (cfg.health and cfg.health.useCustomColor) == true,
				healthColor = (cfg.health and cfg.health.color) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.color) or { 0, 0.8, 0, 1 }),
				healthTextLeft = (cfg.health and cfg.health.textLeft) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textLeft) or "NONE"),
				healthTextCenter = (cfg.health and cfg.health.textCenter) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textCenter) or "NONE"),
				healthTextRight = (cfg.health and cfg.health.textRight) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textRight) or "NONE"),
				healthDelimiter = (cfg.health and cfg.health.textDelimiter) or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiter) or " "),
				healthDelimiterSecondary = (cfg.health and cfg.health.textDelimiterSecondary)
					or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterSecondary) or ((cfg.health and cfg.health.textDelimiter) or " ")),
				healthDelimiterTertiary = (cfg.health and cfg.health.textDelimiterTertiary)
					or ((DEFAULTS[kind] and DEFAULTS[kind].health and DEFAULTS[kind].health.textDelimiterTertiary) or ((cfg.health and cfg.health.textDelimiterSecondary) or (cfg.health and cfg.health.textDelimiter) or " ")),
				healthShortNumbers = (cfg.health and cfg.health.useShortNumbers) ~= false,
				healthHidePercent = (cfg.health and cfg.health.hidePercentSymbol) == true,
				healthLeftX = (cfg.health and cfg.health.offsetLeft and cfg.health.offsetLeft.x) or 0,
				healthLeftY = (cfg.health and cfg.health.offsetLeft and cfg.health.offsetLeft.y) or 0,
				healthCenterX = (cfg.health and cfg.health.offsetCenter and cfg.health.offsetCenter.x) or 0,
				healthCenterY = (cfg.health and cfg.health.offsetCenter and cfg.health.offsetCenter.y) or 0,
				healthRightX = (cfg.health and cfg.health.offsetRight and cfg.health.offsetRight.x) or 0,
				healthRightY = (cfg.health and cfg.health.offsetRight and cfg.health.offsetRight.y) or 0,
				absorbEnabled = (cfg.health and cfg.health.absorbEnabled) ~= false,
				absorbTexture = (cfg.health and cfg.health.absorbTexture) or "SOLID",
				absorbReverse = (cfg.health and cfg.health.absorbReverseFill) == true,
				absorbUseCustomColor = (cfg.health and cfg.health.absorbUseCustomColor) == true,
				absorbColor = (cfg.health and cfg.health.absorbColor) or { 0.85, 0.95, 1, 0.7 },
				healAbsorbEnabled = (cfg.health and cfg.health.healAbsorbEnabled) ~= false,
				healAbsorbTexture = (cfg.health and cfg.health.healAbsorbTexture) or "SOLID",
				healAbsorbReverse = (cfg.health and cfg.health.healAbsorbReverseFill) == true,
				healAbsorbUseCustomColor = (cfg.health and cfg.health.healAbsorbUseCustomColor) == true,
				healAbsorbColor = (cfg.health and cfg.health.healAbsorbColor) or { 1, 0.3, 0.3, 0.7 },
				absorbGlow = (cfg.health and cfg.health.useAbsorbGlow) ~= false,
				nameColorMode = sc.nameColorMode or "CLASS",
				nameColor = sc.nameColor or { 1, 1, 1, 1 },
				levelEnabled = sc.levelEnabled ~= false,
				hideLevelAtMax = sc.hideLevelAtMax == true,
				levelClassColor = (sc.levelColorMode or "CUSTOM") == "CLASS",
				levelColorMode = sc.levelColorMode or "CUSTOM",
				levelColor = sc.levelColor or { 1, 0.85, 0, 1 },
				levelAnchor = sc.levelAnchor or "RIGHT",
				levelOffsetX = (sc.levelOffset and sc.levelOffset.x) or 0,
				levelOffsetY = (sc.levelOffset and sc.levelOffset.y) or 0,
				leaderIconEnabled = lc.enabled ~= false,
				leaderIconSize = lc.size or 12,
				leaderIconPoint = lc.point or "TOPLEFT",
				leaderIconOffsetX = lc.x or 0,
				leaderIconOffsetY = lc.y or 0,
				assistIconEnabled = acfg.enabled ~= false,
				assistIconSize = acfg.size or 12,
				assistIconPoint = acfg.point or "TOPLEFT",
				assistIconOffsetX = acfg.x or 0,
				assistIconOffsetY = acfg.y or 0,
				roleIconEnabled = rc.enabled ~= false,
				roleIconStyle = rc.style or "TINY",
				roleIconRoles = (type(rc.showRoles) == "table") and copySelectionMap(rc.showRoles) or defaultRoleSelection(),
				powerRoles = (type(pcfg.showRoles) == "table") and copySelectionMap(pcfg.showRoles) or defaultRoleSelection(),
				powerSpecs = (type(pcfg.showSpecs) == "table") and copySelectionMap(pcfg.showSpecs) or defaultSpecSelection(),
				powerTextLeft = (pcfg.textLeft) or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textLeft) or "NONE"),
				powerTextCenter = (pcfg.textCenter) or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textCenter) or "NONE"),
				powerTextRight = (pcfg.textRight) or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textRight) or "NONE"),
				powerDelimiter = (pcfg.textDelimiter) or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiter) or " "),
				powerDelimiterSecondary = (pcfg.textDelimiterSecondary)
					or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterSecondary) or (pcfg.textDelimiter or " ")),
				powerDelimiterTertiary = (pcfg.textDelimiterTertiary)
					or ((DEFAULTS[kind] and DEFAULTS[kind].power and DEFAULTS[kind].power.textDelimiterTertiary) or (pcfg.textDelimiterSecondary or pcfg.textDelimiter or " ")),
				powerShortNumbers = pcfg.useShortNumbers ~= false,
				powerHidePercent = pcfg.hidePercentSymbol == true,
				powerLeftX = (pcfg.offsetLeft and pcfg.offsetLeft.x) or 0,
				powerLeftY = (pcfg.offsetLeft and pcfg.offsetLeft.y) or 0,
				powerCenterX = (pcfg.offsetCenter and pcfg.offsetCenter.x) or 0,
				powerCenterY = (pcfg.offsetCenter and pcfg.offsetCenter.y) or 0,
				powerRightX = (pcfg.offsetRight and pcfg.offsetRight.x) or 0,
				powerRightY = (pcfg.offsetRight and pcfg.offsetRight.y) or 0,
				buffsEnabled = ac.buff.enabled == true,
				buffAnchor = ac.buff.anchorPoint or "TOPLEFT",
				buffOffsetX = ac.buff.x or 0,
				buffOffsetY = ac.buff.y or 0,
				buffSize = ac.buff.size or 16,
				buffPerRow = ac.buff.perRow or 6,
				buffMax = ac.buff.max or 6,
				buffSpacing = ac.buff.spacing or 2,
				debuffsEnabled = ac.debuff.enabled == true,
				debuffAnchor = ac.debuff.anchorPoint or "BOTTOMLEFT",
				debuffOffsetX = ac.debuff.x or 0,
				debuffOffsetY = ac.debuff.y or 0,
				debuffSize = ac.debuff.size or 16,
				debuffPerRow = ac.debuff.perRow or 6,
				debuffMax = ac.debuff.max or 6,
				debuffSpacing = ac.debuff.spacing or 2,
				externalsEnabled = ac.externals.enabled == true,
				externalAnchor = ac.externals.anchorPoint or "TOPRIGHT",
				externalOffsetX = ac.externals.x or 0,
				externalOffsetY = ac.externals.y or 0,
				externalSize = ac.externals.size or 16,
				externalPerRow = ac.externals.perRow or 6,
				externalMax = ac.externals.max or 4,
				externalSpacing = ac.externals.spacing or 2,
			}

			EditMode:RegisterFrame(EDITMODE_IDS[kind], {
				frame = anchor,
				title = (kind == "party") and (PARTY or "Party") or (RAID or "Raid"),
				layoutDefaults = defaults,
				settings = buildEditModeSettings(kind, EDITMODE_IDS[kind]),
				onApply = function(_, _, data) applyEditModeData(kind, data) end,
				onPositionChanged = function(_, _, data) applyEditModeData(kind, data) end,
				onEnter = function() GF:OnEnterEditMode(kind) end,
				onExit = function() GF:OnExitEditMode(kind) end,
				isEnabled = function() return true end,
				allowDrag = function() return anchorUsesUIParent(kind) end,
				showOutsideEditMode = false,
				showReset = false,
				showSettingsReset = false,
				enableOverlayToggle = true,
				settingsMaxHeight = 900,
			})

			if addon.EditModeLib and addon.EditModeLib.SetFrameResetVisible then addon.EditModeLib:SetFrameResetVisible(anchor, false) end
		end
	end

	GF._editModeRegistered = true
	if addon.EditModeLib and addon.EditModeLib.internal and addon.EditModeLib.internal.RefreshSettingValues then addon.EditModeLib.internal:RefreshSettingValues() end
end

function GF:OnEnterEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	header._eqolForceShow = true
	GF:ApplyHeaderAttributes(kind)
end

function GF:OnExitEditMode(kind)
	if not isFeatureEnabled() then return end
	GF:EnsureHeaders()
	local header = GF.headers and GF.headers[kind]
	if not header then return end
	header._eqolForceShow = nil
	GF:ApplyHeaderAttributes(kind)
end

-- -----------------------------------------------------------------------------
-- Bootstrap
-- -----------------------------------------------------------------------------

registerFeatureEvents = function(frame)
	if not frame then return end
	if frame.RegisterEvent then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("PARTY_LEADER_CHANGED")
		frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	end
end

unregisterFeatureEvents = function(frame)
	if not frame then return end
	if frame.UnregisterEvent then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
		frame:UnregisterEvent("PARTY_LEADER_CHANGED")
		frame:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
		frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	end
end

do
	local f = CreateFrame("Frame")
	GF._eventFrame = f
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			if isFeatureEnabled() then
				registerFeatureEvents(f)
				GF:EnsureHeaders()
				GF.Refresh()
				GF:EnsureEditMode()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if GF._pendingDisable then
				GF._pendingDisable = nil
				GF:DisableFeature()
			elseif GF._pendingRefresh then
				GF._pendingRefresh = false
				GF.Refresh()
			end
		elseif not isFeatureEnabled() then
			return
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED" then
			GF:RefreshRoleIcons()
			GF:RefreshGroupIcons()
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			GF:RefreshPowerVisibility()
		end
	end)
end
