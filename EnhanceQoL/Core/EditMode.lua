local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
local EditMode = addon.EditMode

local LibEditMode = LibStub("LibEditMode", true)

local DEFAULT_LAYOUT = "_Global"

local function getSelection(lib, frame)
	if not lib or not lib.frameSelections then return nil end
	return lib.frameSelections[frame]
end

local function copyDefaults(target, defaults)
	if not defaults then return end
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = CopyTable(value)
			else
				target[key] = value
			end
		end
	end
end

EditMode.frames = EditMode.frames or {}
EditMode.lib = LibEditMode
EditMode.activeLayout = EditMode.activeLayout

function EditMode:IsAvailable()
	if not self.lib then self.lib = LibStub("LibEditMode", true) end
	return self.lib ~= nil
end

function EditMode:IsInEditMode()
	return self:IsAvailable() and self.lib:IsInEditMode()
end

function EditMode:_ensureDB()
	if not addon.db then return nil end
	addon.db.editModeLayouts = addon.db.editModeLayouts or {}
	return addon.db.editModeLayouts
end

function EditMode:GetActiveLayoutName()
	if self:IsAvailable() then
		local layoutName = self.lib:GetActiveLayoutName()
		if layoutName and layoutName ~= "" then
			self.activeLayout = layoutName
			return layoutName
		end
	end
	return self.activeLayout or DEFAULT_LAYOUT
end

function EditMode:_resolveLayoutName(layoutName)
	if layoutName and layoutName ~= "" then return layoutName end
	return self:GetActiveLayoutName()
end

local function isInCombat()
	return InCombatLockdown and InCombatLockdown()
end

function EditMode:_ensureCombatWatcher()
	if self.combatWatcher then return end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function()
		EditMode:_flushPendingVisibility()
	end)
	self.combatWatcher = watcher
end

function EditMode:_flushPendingVisibility()
	local pending = self.pendingVisibility
	if not pending then return end
	self.pendingVisibility = nil
	for entry, shouldShow in pairs(pending) do
		if entry then self:_setFrameShown(entry, shouldShow, true) end
	end
end

function EditMode:_setFrameShown(entry, shouldShow, immediate)
	local frame = entry.frame
	if not frame then return end

	local isProtected = frame.IsProtected and frame:IsProtected()
	if not immediate and isProtected and isInCombat() then
		self.pendingVisibility = self.pendingVisibility or {}
		self.pendingVisibility[entry] = shouldShow
		self:_ensureCombatWatcher()
		return
	end

	if self.pendingVisibility then self.pendingVisibility[entry] = nil end

	local currentlyShown = frame:IsShown()
	if shouldShow then
		if not currentlyShown then frame:Show() end
	else
		if currentlyShown then frame:Hide() end
	end
end

local function resolveRelativeFrame(entry)
	if not entry then return UIParent end
	local relative = entry.relativeTo
	if type(relative) == "function" then relative = relative() end
	return relative or UIParent
end

function EditMode:EnsureLayoutData(id, layoutName)
	local entry = self.frames[id]
	if not entry then return nil end

	local container = self:_ensureDB()
	if not container then
		entry._fallback = entry._fallback or {}
		local layoutKey = self:_resolveLayoutName(layoutName)
		local record = entry._fallback[layoutKey]
		if not record then
			record = {}
			entry._fallback[layoutKey] = record
		end
		copyDefaults(record, entry.defaults)
		return record
	end

	local layoutKey = self:_resolveLayoutName(layoutName)
	local layout = container[layoutKey]
	if not layout then
		layout = {}
		container[layoutKey] = layout
	end

	local record = layout[id]
	if not record then
		record = {}
		if entry.legacy then
			for field, key in pairs(entry.legacy) do
				local value = addon.db and addon.db[key]
				if value ~= nil then record[field] = value end
			end
		end
		copyDefaults(record, entry.defaults)
		layout[id] = record
	end

	return record
end

function EditMode:GetLayoutData(id, layoutName)
	return self:EnsureLayoutData(id, layoutName)
end

function EditMode:SetFramePosition(id, point, x, y, layoutName, skipApply)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	data.point = point
	data.relativePoint = point
	data.x = x
	data.y = y

	if not skipApply then self:ApplyLayout(id, layoutName) end
end

function EditMode:SetValue(id, field, value, layoutName, skipApply)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	data[field] = value
	if not skipApply then self:ApplyLayout(id, layoutName) end
end

function EditMode:GetValue(id, field, layoutName)
	local data = self:EnsureLayoutData(id, layoutName)
	return data and data[field]
end

function EditMode:_isEntryEnabled(entry)
	if entry.isEnabled then
		local ok, result = pcall(entry.isEnabled, entry.frame)
		if not ok then
			geterrorhandler()(result)
			return true
		end
		return not not result
	end
	return true
end

function EditMode:_applyVisibility(entry, layoutName, enabled)
	local frame = entry.frame
	local lib = self.lib
	if enabled == nil then enabled = self:_isEntryEnabled(entry) end
	entry._lastEnabled = enabled

	local selection = getSelection(lib, frame)
	local inEditMode = self:IsInEditMode()

	if frame then
		local shouldShow = enabled and (inEditMode or entry.showOutsideEditMode)
		self:_setFrameShown(entry, shouldShow)
	end

	if selection then
		if enabled and inEditMode then
			selection:Show()
		else
			selection:Hide()
			selection.isSelected = false
		end
	end

	return enabled
end

function EditMode:RefreshFrame(id, layoutName)
	local entry = self.frames[id]
	if not entry then return end
	layoutName = self:_resolveLayoutName(layoutName)
	self:ApplyLayout(id, layoutName)
end

function EditMode:ApplyLayout(id, layoutName)
	local entry = self.frames[id]
	if not entry or not entry.frame then return end

	layoutName = self:_resolveLayoutName(layoutName)
	local data = self:EnsureLayoutData(id, layoutName)
	if not data then return end

	if entry.managePosition ~= false then
		local point = data.point or entry.defaults.point or "CENTER"
		local relativePoint = data.relativePoint or entry.defaults.relativePoint or point
		local x = data.x or entry.defaults.x or 0
		local y = data.y or entry.defaults.y or 0
		local relative = resolveRelativeFrame(entry)

		entry.frame:ClearAllPoints()
		entry.frame:SetPoint(point, relative, relativePoint, x, y)
	end

	if entry.onApply then entry.onApply(entry.frame, layoutName, data) end

	self:_applyVisibility(entry, layoutName)
end

function EditMode:_registerCallbacks()
	if self.callbacksRegistered then return end
	if not self:IsAvailable() then return end
	self.callbacksRegistered = true

	self.lib:RegisterCallback("enter", function() self:OnEnterEditMode() end)
	self.lib:RegisterCallback("exit", function() self:OnExitEditMode() end)
	self.lib:RegisterCallback("layout", function(layoutName)
		if layoutName and layoutName ~= "" then self.activeLayout = layoutName end
		self:OnLayoutChanged(layoutName)
	end)
end

function EditMode:OnEnterEditMode()
	for _, entry in pairs(self.frames) do
		local layoutName = self:GetActiveLayoutName()
		local enabled = self:_applyVisibility(entry, layoutName)
		if enabled and entry.onEnter then entry.onEnter(entry.frame, layoutName, self:EnsureLayoutData(entry.id)) end
	end
end

function EditMode:OnExitEditMode()
	for _, entry in pairs(self.frames) do
		if entry.onExit and entry._lastEnabled then entry.onExit(entry.frame, self:GetActiveLayoutName(), self:EnsureLayoutData(entry.id)) end
		self:_applyVisibility(entry, self:GetActiveLayoutName())
	end
end

function EditMode:OnLayoutChanged(layoutName)
	for id in pairs(self.frames) do
		self:ApplyLayout(id, layoutName)
	end
end

function EditMode:_prepareSetting(id, setting)
	local copy = {}
	for key, value in pairs(setting) do
		if key ~= "field" and key ~= "onValueChanged" then copy[key] = value end
	end

	local field = setting.field
	local onChange = setting.onValueChanged

	local requiresField = not copy.generator and copy.kind ~= EditMode.lib.SettingType.Label

	if not copy.get and requiresField then
		assert(field, "setting.field required when getter is omitted")
		copy.get = function(layoutName)
			local data = self:EnsureLayoutData(id, layoutName)
			return data and data[field]
		end
	end

	if not copy.set and requiresField then
		assert(field, "setting.field required when setter is omitted")
		copy.set = function(layoutName, value)
			self:SetValue(id, field, value, layoutName, true)
			local data = self:EnsureLayoutData(id, layoutName)
			if onChange then onChange(layoutName, value, data) end
			self:ApplyLayout(id, layoutName)
		end
	end

	local entry = self.frames[id]
	if requiresField and copy.default == nil and entry and entry.defaults then copy.default = entry.defaults[field] end

	return copy
end

function EditMode:RegisterSettings(id, settings)
	if not settings or #settings == 0 then return end
	if not self:IsAvailable() then return end

	local entry = self.frames[id]
	if not entry or not entry.frame then return end

	local prepared = {}
	for index = 1, #settings do
		prepared[index] = self:_prepareSetting(id, settings[index])
	end

	self.lib:AddFrameSettings(entry.frame, prepared)
end

function EditMode:RegisterFrame(id, opts)
	assert(type(id) == "string" and id ~= "", "frame id must be a non-empty string")
	opts = opts or {}

	local frame = opts.frame
	if not frame and opts.createFrame then frame = opts.createFrame() end
	assert(frame, "EditMode:RegisterFrame requires a frame")

	local defaults = opts.layoutDefaults or {}
	defaults.point = defaults.point or "CENTER"
	defaults.relativePoint = defaults.relativePoint or defaults.point
	defaults.x = defaults.x or 0
	defaults.y = defaults.y or 0

	local entry = {
		id = id,
		frame = frame,
		defaults = defaults,
		legacy = opts.legacyKeys,
		isEnabled = opts.isEnabled,
		managePosition = opts.managePosition,
		relativeTo = opts.relativeTo,
		showOutsideEditMode = not not opts.showOutsideEditMode,
		onApply = opts.onApply,
		onEnter = opts.onEnter,
		onExit = opts.onExit,
	}

	self.frames[id] = entry

	if opts.title then frame.editModeName = opts.title end

	self:EnsureLayoutData(id, nil)

	if not entry.showOutsideEditMode then frame:Hide() end

	if self:IsAvailable() then
		self:_registerCallbacks()

		local defaultPosition = {
			point = self:GetValue(id, "point") or defaults.point,
			x = self:GetValue(id, "x") or defaults.x,
			y = self:GetValue(id, "y") or defaults.y,
		}

		self.lib:AddFrame(frame, function(_, layoutName, point, x, y)
			self:SetFramePosition(id, point, x, y, layoutName, true)
			if opts.onPositionChanged then opts.onPositionChanged(frame, layoutName, self:EnsureLayoutData(id, layoutName)) end
			self:ApplyLayout(id, layoutName)
		end, defaultPosition)

		if opts.settings then self:RegisterSettings(id, opts.settings) end
	end

	self:ApplyLayout(id, self:GetActiveLayoutName())

	return frame
end
