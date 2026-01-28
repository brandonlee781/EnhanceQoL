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

CooldownPanels.AnchorHelper = CooldownPanels.AnchorHelper or {}
local AnchorHelper = CooldownPanels.AnchorHelper

local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

AnchorHelper.providers = AnchorHelper.providers or {}
AnchorHelper.runtime = AnchorHelper.runtime or {}

local function isProviderLoaded(provider)
	if not provider then return false end
	if provider.addonName and IsAddOnLoaded and not IsAddOnLoaded(provider.addonName) then return false end
	if provider.isLoaded and provider.isLoaded() == false then return false end
	return true
end

local function providerHasAnchor(provider, value)
	if type(value) ~= "string" or value == "" then return false end
	if provider.isAnchorKey and provider.isAnchorKey(value) then return true end
	if provider.anchorLabelByKey and provider.anchorLabelByKey[value] then return true end
	if provider.anchors then
		for _, entry in ipairs(provider.anchors) do
			if entry.key == value then return true end
		end
	end
	return false
end

local function getRoot()
	if CooldownPanels and CooldownPanels.GetRoot then return CooldownPanels:GetRoot() end
	return nil
end

local function getProvidersInUse()
	local root = getRoot()
	if not root or not root.panels then return nil end
	local used = {}
	for _, panel in pairs(root.panels) do
		local anchor = panel.anchor
		local key = anchor and anchor.relativeFrame
		if key then
			for _, provider in pairs(AnchorHelper.providers) do
				if providerHasAnchor(provider, key) then
					used[provider.key] = provider
					break
				end
			end
		end
	end
	local list = {}
	for _, provider in pairs(used) do
		list[#list + 1] = provider
	end
	if #list == 0 then return nil end
	return list
end

local function providersReady(providers)
	for _, provider in ipairs(providers) do
		if not isProviderLoaded(provider) then return false end
		if provider.framesAvailable and not provider.framesAvailable() then return false end
	end
	return true
end

local function reapplyAnchors(providers)
	local root = getRoot()
	if not root or not root.panels then return end
	if not (CooldownPanels and CooldownPanels.ApplyPanelPosition) then return end
	for panelId, panel in pairs(root.panels) do
		local anchor = panel.anchor
		local key = anchor and anchor.relativeFrame
		if key then
			for _, provider in ipairs(providers) do
				if providerHasAnchor(provider, key) then
					CooldownPanels:ApplyPanelPosition(panelId)
					break
				end
			end
		end
	end
end

function AnchorHelper:RegisterProvider(key, provider)
	if type(key) ~= "string" or key == "" then return end
	if type(provider) ~= "table" then return end
	provider.key = key
	provider.anchorLabelByKey = provider.anchorLabelByKey or {}
	if provider.anchors then
		for _, entry in ipairs(provider.anchors) do
			if entry.key and provider.anchorLabelByKey[entry.key] == nil then provider.anchorLabelByKey[entry.key] = entry.label end
		end
	end
	if provider.anchorLabels then
		for anchorKey, label in pairs(provider.anchorLabels) do
			if provider.anchorLabelByKey[anchorKey] == nil then provider.anchorLabelByKey[anchorKey] = label end
		end
	end
	AnchorHelper.providers[key] = provider
end

function AnchorHelper:IsExternalAnchorKey(value)
	for _, provider in pairs(self.providers) do
		if providerHasAnchor(provider, value) then return true end
	end
	return false
end

function AnchorHelper:GetAnchorLabel(value)
	for _, provider in pairs(self.providers) do
		if provider.anchorLabelByKey and provider.anchorLabelByKey[value] then return provider.anchorLabelByKey[value] end
	end
	return nil
end

function AnchorHelper:CollectAnchorEntries(entries, seen)
	if type(entries) ~= "table" then return end
	if type(seen) ~= "table" then seen = {} end
	for _, provider in pairs(self.providers) do
		if isProviderLoaded(provider) and provider.anchors then
			for _, entry in ipairs(provider.anchors) do
				local key = entry.key
				if key and not seen[key] then
					entries[#entries + 1] = { key = key, label = entry.label or (provider.anchorLabelByKey and provider.anchorLabelByKey[key]) or key }
					seen[key] = true
				end
			end
		end
	end
end

function AnchorHelper:ResolveExternalFrame(relativeName)
	if type(relativeName) ~= "string" or relativeName == "" then return nil end
	for _, provider in pairs(self.providers) do
		if isProviderLoaded(provider) and providerHasAnchor(provider, relativeName) then
			if provider.resolveFrame then
				local frame = provider.resolveFrame(relativeName)
				if frame then return frame end
			end
			if provider.anchorFrames and provider.anchorFrames[relativeName] then
				local frame = _G[provider.anchorFrames[relativeName]]
				if frame then return frame end
			end
			local frame = _G[relativeName]
			if frame then return frame end
		end
	end
	return nil
end

function AnchorHelper:MaybeScheduleRefresh(anchorKey)
	if self:IsExternalAnchorKey(anchorKey) then self:ScheduleRefresh() end
end

function AnchorHelper:ScheduleRefresh()
	local providers = getProvidersInUse()
	if not providers then return end
	local active = {}
	for _, provider in ipairs(providers) do
		if isProviderLoaded(provider) then active[#active + 1] = provider end
	end
	if #active == 0 then return end
	if providersReady(active) then
		reapplyAnchors(active)
		if CooldownPanels and CooldownPanels.RefreshAllPanels then CooldownPanels:RefreshAllPanels() end
		return
	end
	if not (C_Timer and C_Timer.NewTicker) then return end
	if self.runtime.refreshTicker then return end
	local tries = 0
	self.runtime.refreshTicker = C_Timer.NewTicker(0.2, function()
		tries = tries + 1
		if providersReady(active) then
			self.runtime.refreshTicker:Cancel()
			self.runtime.refreshTicker = nil
			reapplyAnchors(active)
			if CooldownPanels and CooldownPanels.RefreshAllPanels then CooldownPanels:RefreshAllPanels() end
		elseif tries >= 25 then
			self.runtime.refreshTicker:Cancel()
			self.runtime.refreshTicker = nil
		end
	end)
end

function AnchorHelper:HandleAddonLoaded(addonName)
	if type(addonName) ~= "string" or addonName == "" then return end
	for _, provider in pairs(self.providers) do
		if provider.addonName == addonName then
			self:ScheduleRefresh()
			return
		end
	end
end

function AnchorHelper:HandlePlayerLogin() self:ScheduleRefresh() end

AnchorHelper:RegisterProvider("msuf", {
	addonName = "MidnightSimpleUnitFrames",
	anchors = {
		{ key = "MSUF_player", label = "MSUF: Player Frame" },
		{ key = "MSUF_target", label = "MSUF: Target Frame" },
		{ key = "MSUF_targettarget", label = "MSUF: Target of Target" },
		{ key = "MSUF_focus", label = "MSUF: Focus Frame" },
		{ key = "MSUF_pet", label = "MSUF: Pet Frame" },
		{ key = "MSUF_boss1", label = "MSUF: Boss Frame 1" },
		{ key = "MSUF_boss2", label = "MSUF: Boss Frame 2" },
		{ key = "MSUF_boss3", label = "MSUF: Boss Frame 3" },
		{ key = "MSUF_boss4", label = "MSUF: Boss Frame 4" },
		{ key = "MSUF_boss5", label = "MSUF: Boss Frame 5" },
	},
	framesAvailable = function()
		local frames = _G and _G.MSUF_UnitFrames
		if frames and (frames.player or frames.target or frames.targettarget or frames.focus or frames.pet or frames.boss1) then return true end
		return _G and (_G.MSUF_player or _G.MSUF_target or _G.MSUF_targettarget or _G.MSUF_focus or _G.MSUF_pet or _G.MSUF_boss1) and true or false
	end,
	resolveFrame = function(relativeName) return _G[relativeName] end,
})

AnchorHelper:RegisterProvider("uuf", {
	addonName = "UnhaltedUnitFrames",
	anchors = {
		{ key = "UUF_Player", label = "UUF: Player Frame" },
		{ key = "UUF_Target", label = "UUF: Target Frame" },
		{ key = "UUF_TargetTarget", label = "UUF: Target of Target" },
		{ key = "UUF_Focus", label = "UUF: Focus Frame" },
		{ key = "UUF_FocusTarget", label = "UUF: Focus Target" },
		{ key = "UUF_Pet", label = "UUF: Pet Frame" },
		{ key = "UUF_Boss1", label = "UUF: Boss Frame 1" },
		{ key = "UUF_Boss2", label = "UUF: Boss Frame 2" },
		{ key = "UUF_Boss3", label = "UUF: Boss Frame 3" },
		{ key = "UUF_Boss4", label = "UUF: Boss Frame 4" },
		{ key = "UUF_Boss5", label = "UUF: Boss Frame 5" },
		{ key = "UUF_Boss6", label = "UUF: Boss Frame 6" },
		{ key = "UUF_Boss7", label = "UUF: Boss Frame 7" },
		{ key = "UUF_Boss8", label = "UUF: Boss Frame 8" },
		{ key = "UUF_Boss9", label = "UUF: Boss Frame 9" },
		{ key = "UUF_Boss10", label = "UUF: Boss Frame 10" },
	},
	framesAvailable = function()
		local g = _G
		if not g then return false end
		if g.UUF_Player or g.UUF_Target or g.UUF_TargetTarget or g.UUF_Focus or g.UUF_FocusTarget or g.UUF_Pet then return true end
		return g.UUF_Boss1 and true or false
	end,
	resolveFrame = function(relativeName) return _G[relativeName] end,
})

AnchorHelper:RegisterProvider("elvui", {
	addonName = "ElvUI",
	anchors = {
		{ key = "ElvUF_Player", label = "ElvUI: Player Frame" },
		{ key = "ElvUF_Target", label = "ElvUI: Target Frame" },
		{ key = "ElvUF_TargetTarget", label = "ElvUI: Target of Target" },
		{ key = "ElvUF_Focus", label = "ElvUI: Focus Frame" },
		{ key = "ElvUF_FocusTarget", label = "ElvUI: Focus Target" },
		{ key = "ElvUF_Pet", label = "ElvUI: Pet Frame" },
		{ key = "ElvUF_Boss1", label = "ElvUI: Boss Frame 1" },
		{ key = "ElvUF_Boss2", label = "ElvUI: Boss Frame 2" },
		{ key = "ElvUF_Boss3", label = "ElvUI: Boss Frame 3" },
		{ key = "ElvUF_Boss4", label = "ElvUI: Boss Frame 4" },
		{ key = "ElvUF_Boss5", label = "ElvUI: Boss Frame 5" },
		{ key = "ElvUF_Arena1", label = "ElvUI: Arena Frame 1" },
		{ key = "ElvUF_Arena2", label = "ElvUI: Arena Frame 2" },
		{ key = "ElvUF_Arena3", label = "ElvUI: Arena Frame 3" },
		{ key = "ElvUF_Arena4", label = "ElvUI: Arena Frame 4" },
		{ key = "ElvUF_Arena5", label = "ElvUI: Arena Frame 5" },
	},
	framesAvailable = function()
		local g = _G
		if not g then return false end
		if g.ElvUF_Player or g.ElvUF_Target or g.ElvUF_TargetTarget or g.ElvUF_Focus or g.ElvUF_FocusTarget or g.ElvUF_Pet then return true end
		if g.ElvUF_Boss1 or g.ElvUF_Arena1 then return true end
		return false
	end,
	resolveFrame = function(relativeName) return _G[relativeName] end,
})
