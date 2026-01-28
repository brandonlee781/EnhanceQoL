local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.CooldownPanels = addon.Aura.CooldownPanels or {}
local CooldownPanels = addon.Aura.CooldownPanels
CooldownPanels.helper = CooldownPanels.helper or {}
local Helper = CooldownPanels.helper

Helper.PANEL_LAYOUT_DEFAULTS = {
	iconSize = 36,
	spacing = 2,
	direction = "RIGHT",
	wrapCount = 0,
	wrapDirection = "DOWN",
	growthPoint = "TOPLEFT",
	strata = "MEDIUM",
	rangeOverlayEnabled = false,
	rangeOverlayColor = { 1, 0.1, 0.1, 0.35 },
	checkPower = false,
	powerTintColor = { 0.5, 0.5, 1, 1 },
	unusableTintColor = { 0.6, 0.6, 0.6, 1 },
	opacityOutOfCombat = 1,
	opacityInCombat = 1,
	stackAnchor = "BOTTOMRIGHT",
	stackX = -1,
	stackY = 1,
	stackFontSize = 12,
	stackFontStyle = "OUTLINE",
	chargesAnchor = "TOP",
	chargesX = 0,
	chargesY = -1,
	chargesFontSize = 12,
	chargesFontStyle = "OUTLINE",
	keybindsEnabled = false,
	keybindsIgnoreItems = false,
	keybindAnchor = "TOPLEFT",
	keybindX = 2,
	keybindY = -2,
	keybindFontSize = 10,
	keybindFontStyle = "OUTLINE",
	cooldownDrawEdge = true,
	cooldownDrawBling = true,
	cooldownDrawSwipe = true,
	cooldownGcdDrawEdge = false,
	cooldownGcdDrawBling = false,
	cooldownGcdDrawSwipe = false,
	showChargesCooldown = false,
	showTooltips = false,
}

Helper.ENTRY_DEFAULTS = {
	alwaysShow = true,
	showCooldown = true,
	showCooldownText = true,
	showCharges = false,
	showStacks = false,
	showItemUses = false,
	showWhenEmpty = false,
	showWhenNoCooldown = false,
	glowReady = false,
	glowDuration = 0,
	soundReady = false,
	soundReadyFile = "None",
}

local function spellHasCharges(spellId)
	if not spellId then return false end
	if not (C_Spell and C_Spell.GetSpellCharges) then return false end
	local info = C_Spell.GetSpellCharges(spellId)
	if type(info) ~= "table" then return false end
	local issecretvalue = _G.issecretvalue
	if issecretvalue then
		if issecretvalue(info) then return false end
		if info.currentCharges ~= nil and issecretvalue(info.currentCharges) then return false end
		if info.maxCharges ~= nil and issecretvalue(info.maxCharges) then return false end
	end
	local maxCharges = info.maxCharges
	if type(maxCharges) ~= "number" then return false end
	return maxCharges > 1
end

function Helper.CopyTableShallow(source)
	local result = {}
	if source then
		for k, v in pairs(source) do
			result[k] = v
		end
	end
	return result
end

function Helper.NormalizeBool(value, fallback)
	if value == nil then return fallback end
	return value and true or false
end

function Helper.GetNextNumericId(map, start)
	local maxId = tonumber(start) or 0
	if map then
		for key in pairs(map) do
			local num = tonumber(key)
			if num and num > maxId then maxId = num end
		end
	end
	return maxId + 1
end

function Helper.CreateRoot()
	return {
		version = 1,
		panels = {},
		order = {},
		selectedPanel = nil,
		defaults = {
			layout = Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS),
			entry = Helper.CopyTableShallow(Helper.ENTRY_DEFAULTS),
		},
	}
end

function Helper.NormalizeRoot(root)
	if type(root) ~= "table" then return Helper.CreateRoot() end
	if type(root.version) ~= "number" then root.version = 1 end
	if type(root.panels) ~= "table" then root.panels = {} end
	if type(root.order) ~= "table" then root.order = {} end
	if type(root.defaults) ~= "table" then root.defaults = {} end
	if type(root.defaults.layout) ~= "table" then
		root.defaults.layout = Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	else
		for key, value in pairs(Helper.PANEL_LAYOUT_DEFAULTS) do
			if root.defaults.layout[key] == nil then root.defaults.layout[key] = value end
		end
	end
	if type(root.defaults.entry) ~= "table" then
		root.defaults.entry = Helper.CopyTableShallow(Helper.ENTRY_DEFAULTS)
	else
		for key, value in pairs(Helper.ENTRY_DEFAULTS) do
			if root.defaults.entry[key] == nil then root.defaults.entry[key] = value end
		end
	end
	root.defaults.entry.alwaysShow = Helper.ENTRY_DEFAULTS.alwaysShow
	root.defaults.entry.showCooldown = Helper.ENTRY_DEFAULTS.showCooldown
	root.defaults.entry.showCooldownText = Helper.ENTRY_DEFAULTS.showCooldownText
	root.defaults.entry.showCharges = Helper.ENTRY_DEFAULTS.showCharges
	root.defaults.entry.showStacks = Helper.ENTRY_DEFAULTS.showStacks
	root.defaults.entry.glowReady = Helper.ENTRY_DEFAULTS.glowReady
	root.defaults.entry.glowDuration = Helper.ENTRY_DEFAULTS.glowDuration
	root.defaults.entry.soundReady = Helper.ENTRY_DEFAULTS.soundReady
	root.defaults.entry.soundReadyFile = Helper.ENTRY_DEFAULTS.soundReadyFile
	return root
end

function Helper.NormalizePanel(panel, defaults)
	if type(panel) ~= "table" then return end
	defaults = defaults or {}
	local layoutDefaults = defaults.layout or Helper.PANEL_LAYOUT_DEFAULTS
	if type(panel.layout) ~= "table" then panel.layout = {} end
	local hadKeybindsEnabled = panel.layout.keybindsEnabled
	local hadChargesCooldown = panel.layout.showChargesCooldown
	for key, value in pairs(layoutDefaults) do
		if panel.layout[key] == nil then panel.layout[key] = value end
	end
	if type(panel.anchor) ~= "table" then panel.anchor = {} end
	local anchor = panel.anchor
	if anchor.point == nil then anchor.point = panel.point or "CENTER" end
	if anchor.relativePoint == nil then anchor.relativePoint = anchor.point end
	if anchor.x == nil then anchor.x = panel.x or 0 end
	if anchor.y == nil then anchor.y = panel.y or 0 end
	if not anchor.relativeFrame or anchor.relativeFrame == "" then anchor.relativeFrame = "UIParent" end
	if panel.point == nil then panel.point = "CENTER" end
	if panel.x == nil then panel.x = 0 end
	if panel.y == nil then panel.y = 0 end
	panel.point = anchor.point or panel.point
	panel.x = anchor.x or panel.x
	panel.y = anchor.y or panel.y
	if type(panel.entries) ~= "table" then panel.entries = {} end
	if type(panel.order) ~= "table" then panel.order = {} end
	if panel.enabled == nil then panel.enabled = true end
	if type(panel.name) ~= "string" or panel.name == "" then panel.name = "Cooldown Panel" end
	if hadKeybindsEnabled == nil or hadChargesCooldown == nil then
		for _, entry in pairs(panel.entries) do
			if entry then
				if hadKeybindsEnabled == nil and entry.showKeybinds == true then panel.layout.keybindsEnabled = true end
				if hadChargesCooldown == nil and entry.showChargesCooldown == true then panel.layout.showChargesCooldown = true end
				if (hadKeybindsEnabled ~= nil or panel.layout.keybindsEnabled == true) and (hadChargesCooldown ~= nil or panel.layout.showChargesCooldown == true) then break end
			end
		end
	end
end

function Helper.NormalizeEntry(entry, defaults)
	if type(entry) ~= "table" then return end
	local hadShowCharges = entry.showCharges ~= nil
	local hadShowStacks = entry.showStacks ~= nil
	defaults = defaults or {}
	local entryDefaults = defaults.entry or {}
	for key, value in pairs(entryDefaults) do
		if entry[key] == nil then entry[key] = value end
	end
	for key, value in pairs(Helper.ENTRY_DEFAULTS) do
		if entry[key] == nil then entry[key] = value end
	end
	if entry.alwaysShow == nil then entry.alwaysShow = true end
	if entry.showCooldown == nil then entry.showCooldown = true end
	if entry.type == "ITEM" and entry.showItemCount == nil then entry.showItemCount = true end
	if entry.type == "SPELL" then
		if not hadShowCharges then entry.showCharges = spellHasCharges(entry.spellID) end
		if not hadShowStacks then entry.showStacks = false end
	end
	local duration = tonumber(entry.glowDuration)
	if duration == nil then duration = defaults.entry and defaults.entry.glowDuration or Helper.ENTRY_DEFAULTS.glowDuration or 0 end
	if duration < 0 then duration = 0 end
	if duration > 30 then duration = 30 end
	entry.glowDuration = math.floor(duration + 0.5)
	if type(entry.soundReady) ~= "boolean" then entry.soundReady = Helper.ENTRY_DEFAULTS.soundReady end
	if type(entry.soundReadyFile) ~= "string" or entry.soundReadyFile == "" then entry.soundReadyFile = Helper.ENTRY_DEFAULTS.soundReadyFile end
end

function Helper.SyncOrder(order, map)
	if type(order) ~= "table" or type(map) ~= "table" then return end
	local cleaned = {}
	local seen = {}
	for _, id in ipairs(order) do
		if map[id] and not seen[id] then
			seen[id] = true
			cleaned[#cleaned + 1] = id
		end
	end
	for id in pairs(map) do
		if not seen[id] then cleaned[#cleaned + 1] = id end
	end
	for i = 1, #order do
		order[i] = nil
	end
	for i = 1, #cleaned do
		order[i] = cleaned[i]
	end
end

function Helper.CreatePanel(name, defaults)
	defaults = defaults or {}
	local layoutDefaults = defaults.layout or Helper.PANEL_LAYOUT_DEFAULTS
	return {
		name = (type(name) == "string" and name ~= "" and name) or "Cooldown Panel",
		enabled = true,
		point = "CENTER",
		x = 0,
		y = 0,
		anchor = {
			point = "CENTER",
			relativePoint = "CENTER",
			relativeFrame = "UIParent",
			x = 0,
			y = 0,
		},
		layout = Helper.CopyTableShallow(layoutDefaults),
		entries = {},
		order = {},
	}
end

function Helper.CreateEntry(entryType, idValue, defaults)
	defaults = defaults or {}
	local entryDefaults = defaults.entry or {}
	local entry = Helper.CopyTableShallow(entryDefaults)
	for key, value in pairs(Helper.ENTRY_DEFAULTS) do
		if entry[key] == nil then entry[key] = value end
	end
	entry.type = entryType
	if entryType == "SPELL" then
		entry.spellID = tonumber(idValue)
		entry.showCharges = spellHasCharges(entry.spellID)
		entry.showStacks = false
	elseif entryType == "ITEM" then
		entry.itemID = tonumber(idValue)
		if entry.showItemCount == nil then entry.showItemCount = true end
	elseif entryType == "SLOT" then
		entry.slotID = tonumber(idValue)
	end
	return entry
end

function Helper.GetEntryKey(panelId, entryId) return tostring(panelId) .. ":" .. tostring(entryId) end

function Helper.NormalizeDisplayCount(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return value end
	if value == "" then return nil end
	return value
end

function Helper.HasDisplayCount(value)
	if value == nil then return false end
	if issecretvalue and issecretvalue(value) then return true end
	return value ~= ""
end

Helper.Keybinds = Helper.Keybinds or {}
local Keybinds = Helper.Keybinds

local DEFAULT_ACTION_BUTTON_NAMES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarLeftButton",
	"MultiBarRightButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
}

local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local GetInventoryItemID = GetInventoryItemID
local GetActionDisplayCount = C_ActionBar and C_ActionBar.GetActionDisplayCount
local FindSpellActionButtons = C_ActionBar and C_ActionBar.FindSpellActionButtons
local issecretvalue = _G.issecretvalue

local function getEffectiveSpellId(spellId)
	local id = tonumber(spellId)
	if not id then return nil end
	if GetOverrideSpell then
		local overrideId = GetOverrideSpell(id)
		if type(overrideId) == "number" and overrideId > 0 then return overrideId end
	end
	return id
end

local function getRoot()
	if CooldownPanels and CooldownPanels.GetRoot then return CooldownPanels:GetRoot() end
	return nil
end

local function getRuntime(panelId)
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	local runtime = CooldownPanels.runtime[panelId]
	if not runtime then
		runtime = {}
		CooldownPanels.runtime[panelId] = runtime
	end
	return runtime
end

local function getActionSlotForSpell(spellId)
	if not spellId then return nil end
	if ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then
		local button = ActionButtonUtil.GetActionButtonBySpellID(spellId, false, false)
		if button and button.action then return button.action end
	end
	if FindSpellActionButtons then
		local slots = FindSpellActionButtons(spellId)
		if type(slots) == "table" and slots[1] then return slots[1] end
	end
	return nil
end

local function getActionDisplayCountForSpell(spellId)
	if not GetActionDisplayCount then return nil end
	local slot = getActionSlotForSpell(spellId)
	if not slot then return nil end
	return GetActionDisplayCount(slot)
end

function Helper.UpdateActionDisplayCountsForSpell(spellId, baseSpellId)
	if not GetActionDisplayCount then return false end
	local id = tonumber(spellId)
	local baseId = tonumber(baseSpellId)
	local runtime = CooldownPanels.runtime
	local index = runtime and runtime.spellIndex
	if not index then return false end

	local panels = {}
	if id and index[id] then
		for panelId in pairs(index[id]) do
			panels[panelId] = true
		end
	end
	if baseId and index[baseId] then
		for panelId in pairs(index[baseId]) do
			panels[panelId] = true
		end
	end
	if not next(panels) then return false end

	runtime.actionDisplayCounts = runtime.actionDisplayCounts or {}
	local cache = runtime.actionDisplayCounts

	for panelId in pairs(panels) do
		local panel = CooldownPanels:GetPanel(panelId)
		if panel and panel.entries then
			local runtimePanel = getRuntime(panelId)
			local entryToIcon = runtimePanel.entryToIcon
			local needsRefresh = false
			for entryId, entry in pairs(panel.entries) do
				if entry and entry.type == "SPELL" and entry.showStacks == true and entry.spellID then
					local entrySpellId = entry.spellID
					local effectiveId = getEffectiveSpellId(entrySpellId)
					local matches = (id and (entrySpellId == id or effectiveId == id)) or (baseId and (entrySpellId == baseId or effectiveId == baseId))
					if matches then
						local displayCount = getActionDisplayCountForSpell(effectiveId) or (effectiveId ~= entrySpellId and getActionDisplayCountForSpell(entrySpellId) or nil)
						displayCount = Helper.NormalizeDisplayCount(displayCount)
						cache[Helper.GetEntryKey(panelId, entryId)] = displayCount

						local icon = entryToIcon and entryToIcon[entryId]
						if icon then
							if displayCount ~= nil then
								icon.count:SetText(displayCount)
								icon.count:Show()
							else
								icon.count:Hide()
								needsRefresh = true
							end
						else
							if displayCount ~= nil then needsRefresh = true end
						end
					end
				end
			end
			if needsRefresh then
				if CooldownPanels:GetPanel(panelId) then CooldownPanels:RefreshPanel(panelId) end
			end
		end
	end
	return true
end

local function getActionButtonSlotMap()
	local runtime = CooldownPanels.runtime or {}
	if runtime._eqolActionButtonSlotMap then return runtime._eqolActionButtonSlotMap end
	local map = {}
	local buttonNames = (ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames) or DEFAULT_ACTION_BUTTON_NAMES
	local buttonCount = NUM_ACTIONBAR_BUTTONS or 12
	for _, prefix in ipairs(buttonNames) do
		for i = 1, buttonCount do
			local btn = _G[prefix .. i]
			local action = btn and btn.action
			if action and map[action] == nil then map[action] = btn end
		end
	end
	runtime._eqolActionButtonSlotMap = map
	CooldownPanels.runtime = runtime
	return map
end

local function getBindingTextForButton(button)
	if not button or not GetBindingKey then return nil end
	local key = nil
	if button.bindingAction then key = GetBindingKey(button.bindingAction) end
	if button:GetName() == "MultiBarBottomLeftButton6" then
	end
	if not key and button.GetName then key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton") end
	local text = key and GetBindingText and GetBindingText(key, 1)
	if text == "" then text = nil end
	return text
end

local function formatKeybindText(text)
	if type(text) ~= "string" or text == "" then return text end
	local labels = addon and addon.ActionBarLabels
	if labels and labels.ShortenHotkeyText then return labels.ShortenHotkeyText(text) end
	return text
end

local function getBindingTextForActionSlot(slot)
	if not slot then return nil end
	local map = getActionButtonSlotMap()
	local text = map and getBindingTextForButton(map[slot])
	if text then return text end
	if GetBindingKey then
		local buttons = NUM_ACTIONBAR_BUTTONS or 12
		local index = ((slot - 1) % buttons) + 1
		local key = GetBindingKey("ACTIONBUTTON" .. index)
		text = key and GetBindingText and GetBindingText(key, 1)
		if text == "" then text = nil end
		return text
	end
	return nil
end

local function buildKeybindLookup()
	local runtime = CooldownPanels.runtime or {}
	if runtime._eqolKeybindLookup then return runtime._eqolKeybindLookup end
	local lookup = {
		item = {},
	}
	local buttonNames = (ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames) or DEFAULT_ACTION_BUTTON_NAMES
	local buttonCount = NUM_ACTIONBAR_BUTTONS or 12
	local getMacroItem = GetMacroItem

	for _, prefix in ipairs(buttonNames) do
		for i = 1, buttonCount do
			local btn = _G[prefix .. i]
			local slot = btn and btn.action
			if slot then
				local keyText = getBindingTextForButton(btn)
				if not keyText and GetBindingKey then
					local buttons = NUM_ACTIONBAR_BUTTONS or 12
					local index = ((slot - 1) % buttons) + 1
					local key = GetBindingKey("ACTIONBUTTON" .. index)
					keyText = key and GetBindingText and GetBindingText(key, 1)
					if keyText == "" then keyText = nil end
				end
				if keyText and GetActionInfo then
					local actionType, actionId = GetActionInfo(slot)
					if actionType == "item" and actionId then
						if not lookup.item[actionId] then lookup.item[actionId] = keyText end
					elseif actionType == "macro" and actionId then
						if getMacroItem then
							local macroItem = getMacroItem(actionId)
							if macroItem then
								local itemId
								if type(macroItem) == "number" then
									itemId = macroItem
								elseif GetItemInfoInstantFn then
									itemId = GetItemInfoInstantFn(macroItem)
								end
								if itemId and not lookup.item[itemId] then lookup.item[itemId] = keyText end
							end
						end
					end
				end
			end
		end
	end

	runtime._eqolKeybindLookup = lookup
	CooldownPanels.runtime = runtime
	return lookup
end

function Keybinds.InvalidateCache()
	if not CooldownPanels.runtime then return end
	CooldownPanels.runtime._eqolActionButtonSlotMap = nil
	CooldownPanels.runtime._eqolKeybindLookup = nil
	CooldownPanels.runtime._eqolKeybindCache = nil
end

function Keybinds.MarkPanelsDirty()
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	CooldownPanels.runtime.keybindPanelsDirty = true
end

function Keybinds.RebuildPanels()
	local root = getRoot()
	if not root or not root.panels then return nil end
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	local runtime = CooldownPanels.runtime
	local panels = {}
	for panelId, panel in pairs(root.panels) do
		local layout = panel and panel.layout
		if panel and panel.enabled ~= false and layout and layout.keybindsEnabled == true then panels[panelId] = true end
	end
	runtime.keybindPanels = panels
	runtime.keybindPanelsDirty = nil
	return panels
end

function Keybinds.HasPanels()
	local runtime = CooldownPanels.runtime
	if not runtime then return false end
	local panels = (runtime.keybindPanelsDirty or runtime.keybindPanels == nil) and Keybinds.RebuildPanels() or runtime.keybindPanels
	return panels ~= nil and next(panels) ~= nil
end

function Keybinds.RefreshPanels()
	local runtime = CooldownPanels.runtime
	if not runtime then return false end
	local panels = (runtime.keybindPanelsDirty or not runtime.keybindPanels) and Keybinds.RebuildPanels() or runtime.keybindPanels
	if not panels or not next(panels) then return false end
	for panelId in pairs(panels) do
		if CooldownPanels.GetPanel and CooldownPanels.RefreshPanel then
			if CooldownPanels:GetPanel(panelId) then CooldownPanels:RefreshPanel(panelId) end
		end
	end
	return true
end

function Keybinds.RequestRefresh(cause)
	local runtime = CooldownPanels.runtime
	if not runtime then return end
	if not Keybinds.HasPanels() then return end
	if cause then runtime.keybindRefreshCause = cause end
	if runtime.keybindRefreshPending then return end
	runtime.keybindRefreshPending = true
	C_Timer.After(0.1, function()
		runtime.keybindRefreshPending = nil
		if not Keybinds.HasPanels() then return end
		runtime.keybindRefreshCauseActive = runtime.keybindRefreshCause
		runtime.keybindRefreshCause = nil
		Keybinds.InvalidateCache()
		Keybinds.RefreshPanels()
		runtime.keybindRefreshCauseActive = nil
	end)
end

function Keybinds.GetEntryKeybindText(entry, layout)
	if not entry then return nil end
	if layout and layout.keybindsIgnoreItems == true and (entry.type == "ITEM" or entry.type == "SLOT") then return nil end
	local runtime = CooldownPanels.runtime or {}
	runtime._eqolKeybindCache = runtime._eqolKeybindCache or {}
	local slotItemId
	if entry.type == "SLOT" and entry.slotID then slotItemId = GetInventoryItemID and GetInventoryItemID("player", entry.slotID) end
	local effectiveSpellId = entry.type == "SPELL" and getEffectiveSpellId(entry.spellID) or nil
	local cacheKey = tostring(entry.type) .. ":" .. tostring(effectiveSpellId or entry.spellID or entry.itemID or entry.slotID or "") .. ":" .. tostring(slotItemId or "")
	local cached = runtime._eqolKeybindCache[cacheKey]
	if cached ~= nil then return cached or nil end

	local text = nil
	if entry.type == "SPELL" and entry.spellID then
		local spellId = effectiveSpellId or entry.spellID
		-- if C_ActionBar and C_ActionBar.FindSpellActionButtons then
		-- 	local slots = C_ActionBar.FindSpellActionButtons(spellId)
		-- 	if type(slots) == "table" then
		-- 		for _, slot in ipairs(slots) do
		-- 			text = getBindingTextForActionSlot(slot)
		-- 			if text then break end
		-- 		end
		-- 	end
		-- end
		if not text and ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then text = getBindingTextForButton(ActionButtonUtil.GetActionButtonBySpellID(spellId, false, false)) end
		if not text and effectiveSpellId and effectiveSpellId ~= entry.spellID then
			-- if C_ActionBar and C_ActionBar.FindSpellActionButtons then
			-- 	local slots = C_ActionBar.FindSpellActionButtons(entry.spellID)
			-- 	if type(slots) == "table" then
			-- 		for _, slot in ipairs(slots) do
			-- 			text = getBindingTextForActionSlot(slot)
			-- 			if text then break end
			-- 		end
			-- 	end
			-- end
			if not text and ActionButtonUtil and ActionButtonUtil.GetActionButtonBySpellID then
				text = getBindingTextForButton(ActionButtonUtil.GetActionButtonBySpellID(entry.spellID, false, false))
			end
		end
	elseif entry.type == "ITEM" and entry.itemID then
		local lookup = buildKeybindLookup()
		text = lookup.item and lookup.item[entry.itemID]
	elseif entry.type == "SLOT" and slotItemId then
		local lookup = buildKeybindLookup()
		text = lookup.item and lookup.item[slotItemId]
	end

	text = formatKeybindText(text)
	runtime._eqolKeybindCache[cacheKey] = text or false
	CooldownPanels.runtime = runtime
	return text
end

function CooldownPanels:RequestPanelRefresh(panelId)
	if not panelId then return end
	self.runtime = self.runtime or {}
	local rt = self.runtime

	rt._eqolPanelRefreshQueue = rt._eqolPanelRefreshQueue or {}
	rt._eqolPanelRefreshQueue[panelId] = true

	if rt._eqolPanelRefreshPending then return end
	rt._eqolPanelRefreshPending = true

	C_Timer.After(0, function()
		local runtime = CooldownPanels.runtime
		if not runtime then return end
		runtime._eqolPanelRefreshPending = nil

		local q = runtime._eqolPanelRefreshQueue
		if not q then return end

		for id in pairs(q) do
			q[id] = nil
			if CooldownPanels:GetPanel(id) then CooldownPanels:RefreshPanel(id) end
		end
	end)
end
