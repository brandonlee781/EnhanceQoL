local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

addon.Visibility = addon.Visibility or {}
addon.Visibility.helper = addon.Visibility.helper or {}
local Helper = addon.Visibility.helper

Helper.MODES = {
	SHOW = "SHOW",
	HIDE = "HIDE",
}

Helper.RULE_DEFINITIONS = {
	{ key = "IN_COMBAT", label = L["VisibilityCondInCombat"] or "In combat" },
	{ key = "OUT_OF_COMBAT", label = L["VisibilityCondOutOfCombat"] or "Out of combat" },
	{ key = "IN_GROUP", label = L["VisibilityCondInGroup"] or "In group" },
	{ key = "IN_PARTY", label = L["VisibilityCondInParty"] or "In party" },
	{ key = "IN_RAID", label = L["VisibilityCondInRaid"] or "In raid" },
	{ key = "SOLO", label = L["VisibilityCondSolo"] or "Solo" },
	{ key = "IN_INSTANCE", label = L["VisibilityCondInInstance"] or "In instance" },
	{ key = "INSTANCE_PARTY", label = L["VisibilityCondInstanceParty"] or "Instance: Party" },
	{ key = "INSTANCE_RAID", label = L["VisibilityCondInstanceRaid"] or "Instance: Raid" },
	{ key = "INSTANCE_PVP", label = L["VisibilityCondInstancePvp"] or "Instance: PvP" },
	{ key = "INSTANCE_ARENA", label = L["VisibilityCondInstanceArena"] or "Instance: Arena" },
	{ key = "INSTANCE_SCENARIO", label = L["VisibilityCondInstanceScenario"] or "Instance: Scenario" },
	{ key = "MOUNTED", label = L["VisibilityCondMounted"] or "Mounted" },
	{ key = "SKYRIDING", label = L["VisibilityCondSkyriding"] or "Skyriding" },
	{ key = "HAS_TARGET", label = L["VisibilityCondHasTarget"] or "Has target" },
	{ key = "CASTING", label = L["VisibilityCondCasting"] or "Casting" },
	{ key = "MOUSEOVER", label = L["VisibilityCondMouseover"] or "Mouseover" },
}

Helper.RULE_LABELS = Helper.RULE_LABELS or {}
for _, def in ipairs(Helper.RULE_DEFINITIONS) do
	Helper.RULE_LABELS[def.key] = def.label
end

Helper.CONFIG_DEFAULTS = {
	enabled = true,
	mode = Helper.MODES.SHOW,
	fadeAlpha = 0,
	name = L["VisibilityNewConfig"] or "New Visibility Config",
	frames = {},
	rules = { op = "AND", children = {} },
}

local DRUID_TRAVEL_FORM_SPELL_IDS = {
	[783] = true, -- Travel Form
	[1066] = true, -- Aquatic Form
	[33943] = true, -- Flight Form
	[40120] = true, -- Swift Flight Form
	[210053] = true, -- Mount Form (Stag)
}

function Helper.CopyTableShallow(source)
	local result = {}
	if source then
		for k, v in pairs(source) do
			result[k] = v
		end
	end
	return result
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
	for i = #order, 1, -1 do
		order[i] = nil
	end
	for i = 1, #cleaned do
		order[i] = cleaned[i]
	end
end

local function normalizeRuleNode(node)
	if type(node) ~= "table" then return nil end
	if node.key then
		if type(node.key) ~= "string" or node.key == "" then return nil end
		if node.negate == nil and node["not"] ~= nil then node.negate = node["not"] end
		node["not"] = nil
		local negate = node.negate and true or false
		if node.key == "NOT_MOUNTED" then
			node.key = "MOUNTED"
			negate = not negate
		elseif node.key == "NOT_SKYRIDING" then
			node.key = "SKYRIDING"
			negate = not negate
		end
		node.negate = negate
		return node
	end
	if type(node.op) ~= "string" then
		node.op = "AND"
	end
	if node.op ~= "AND" and node.op ~= "OR" then node.op = "AND" end
	if node.negate == nil and node["not"] ~= nil then node.negate = node["not"] end
	node["not"] = nil
	node.negate = node.negate and true or false
	if type(node.children) ~= "table" then node.children = {} end
	local cleaned = {}
	for _, child in ipairs(node.children) do
		local normalized = normalizeRuleNode(child)
		if normalized then cleaned[#cleaned + 1] = normalized end
	end
	node.children = cleaned
	return node
end

function Helper.NormalizeRules(node)
	if type(node) ~= "table" then
		return { op = "AND", children = {} }
	end
	if node.key or node.op then
		local normalized = normalizeRuleNode(node)
		if normalized then return normalized end
	end
	return { op = "AND", children = {} }
end

function Helper.NormalizeConfig(config, defaults)
	if type(config) ~= "table" then return end
	defaults = defaults or Helper.CONFIG_DEFAULTS
	if config.enabled == nil then config.enabled = defaults.enabled end
	if config.mode ~= Helper.MODES.SHOW and config.mode ~= Helper.MODES.HIDE then config.mode = defaults.mode end
	local alpha = tonumber(config.fadeAlpha)
	if alpha == nil then alpha = defaults.fadeAlpha end
	if alpha < 0 then alpha = 0 end
	if alpha > 1 then alpha = 1 end
	config.fadeAlpha = alpha
	if type(config.name) ~= "string" or config.name == "" then config.name = defaults.name end
	if type(config.frames) ~= "table" then config.frames = {} end
	config.rules = Helper.NormalizeRules(config.rules)
end

function Helper.CreateRoot()
	return {
		version = 1,
		configs = {},
		order = {},
		selectedConfig = nil,
		frameIndex = {},
		defaults = {
			config = Helper.CopyTableShallow(Helper.CONFIG_DEFAULTS),
		},
	}
end

function Helper.RebuildFrameIndex(root)
	if type(root) ~= "table" then return end
	root.frameIndex = {}
	for configId, config in pairs(root.configs or {}) do
		if type(config) == "table" and type(config.frames) == "table" then
			local unique = {}
			local cleaned = {}
			for _, name in ipairs(config.frames) do
				if type(name) == "string" and name ~= "" and not unique[name] then
					unique[name] = true
					if not root.frameIndex[name] then
						root.frameIndex[name] = configId
						cleaned[#cleaned + 1] = name
					end
				end
			end
			config.frames = cleaned
		end
	end
end

function Helper.NormalizeRoot(root)
	if type(root) ~= "table" then return Helper.CreateRoot() end
	if type(root.version) ~= "number" then root.version = 1 end
	if type(root.configs) ~= "table" then root.configs = {} end
	if type(root.order) ~= "table" then root.order = {} end
	if type(root.frameIndex) ~= "table" then root.frameIndex = {} end
	if type(root.defaults) ~= "table" then root.defaults = {} end
	if type(root.defaults.config) ~= "table" then root.defaults.config = Helper.CopyTableShallow(Helper.CONFIG_DEFAULTS) end

	for id, config in pairs(root.configs) do
		if type(config) == "table" then
			Helper.NormalizeConfig(config, root.defaults.config)
		else
			root.configs[id] = nil
		end
	end

	Helper.SyncOrder(root.order, root.configs)
	Helper.RebuildFrameIndex(root)
	if root.selectedConfig and not root.configs[root.selectedConfig] then root.selectedConfig = nil end
	return root
end

function Helper.HasRules(node)
	if type(node) ~= "table" then return false end
	if node.key then return true end
	local children = node.children or {}
	for _, child in ipairs(children) do
		if Helper.HasRules(child) then return true end
	end
	return false
end

function Helper.RuleUsesMouseover(node)
	if type(node) ~= "table" then return false end
	if node.key == "MOUSEOVER" then return true end
	local children = node.children or {}
	for _, child in ipairs(children) do
		if Helper.RuleUsesMouseover(child) then return true end
	end
	return false
end

function Helper.EvaluateRule(node, context)
	if type(node) ~= "table" then return nil end
	if node.key then
		local value = context and context[node.key]
		if value == nil then value = false end
		if node.negate then value = not value end
		return value
	end
	local children = node.children or {}
	local any = false
	local result
	if node.op == "OR" then
		result = false
		for _, child in ipairs(children) do
			local childResult = Helper.EvaluateRule(child, context)
			if childResult ~= nil then
				any = true
				if childResult then
					result = true
					break
				end
			end
		end
	else
		result = true
		for _, child in ipairs(children) do
			local childResult = Helper.EvaluateRule(child, context)
			if childResult ~= nil then
				any = true
				if not childResult then
					result = false
					break
				end
			end
		end
	end
	if not any then return nil end
	if node.negate then result = not result end
	return result
end

function Helper.ClampAlpha(value)
	local alpha = tonumber(value)
	if alpha == nil then return nil end
	if alpha < 0 then alpha = 0 end
	if alpha > 1 then alpha = 1 end
	return alpha
end

function Helper.IsInDruidTravelForm()
	local class = addon.variables and addon.variables.unitClass
	if not class and UnitClass then
		local _, eng = UnitClass("player")
		class = eng
	end
	if not class or class ~= "DRUID" then return false end
	if not GetShapeshiftForm then return false end
	local form = GetShapeshiftForm()
	if not form or form == 0 then return false end
	if GetShapeshiftFormID then
		local formID = GetShapeshiftFormID()
		if formID == DRUID_TRAVEL_FORM or formID == DRUID_ACQUATIC_FORM or formID == DRUID_FLIGHT_FORM or formID == 29 then return true end
	end
	local spellID = select(4, GetShapeshiftFormInfo(form))
	if spellID and DRUID_TRAVEL_FORM_SPELL_IDS[spellID] then return true end
	return form == 3
end

function Helper.BuildContext(runtime)
	local inCombat = false
	if InCombatLockdown and InCombatLockdown() then
		inCombat = true
	elseif UnitAffectingCombat then
		inCombat = UnitAffectingCombat("player") and true or false
	end

	local inGroup = IsInGroup and IsInGroup() and true or false
	local inRaid = IsInRaid and IsInRaid() and true or false
	local inParty = inGroup and not inRaid
	local solo = not inGroup
	local inInstance, instanceType = IsInInstance()
	local mounted = (IsMounted and IsMounted()) or Helper.IsInDruidTravelForm()
	local hasTarget = UnitExists and UnitExists("target") and true or false
	local casting = (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player"))
	local isCasting = casting and true or false
	local isSkyriding = runtime and runtime.isSkyriding and true or false

	return {
		IN_COMBAT = inCombat,
		OUT_OF_COMBAT = not inCombat,
		IN_GROUP = inGroup,
		IN_PARTY = inParty,
		IN_RAID = inRaid,
		SOLO = solo,
		IN_INSTANCE = inInstance and true or false,
		INSTANCE_PARTY = inInstance and instanceType == "party",
		INSTANCE_RAID = inInstance and instanceType == "raid",
		INSTANCE_PVP = inInstance and instanceType == "pvp",
		INSTANCE_ARENA = inInstance and instanceType == "arena",
		INSTANCE_SCENARIO = inInstance and instanceType == "scenario",
		MOUNTED = mounted and true or false,
		NOT_MOUNTED = not mounted,
		SKYRIDING = isSkyriding,
		NOT_SKYRIDING = not isSkyriding,
		HAS_TARGET = hasTarget,
		CASTING = isCasting,
		MOUSEOVER = false,
	}
end

function Helper.GetRuleLabel(key)
	return Helper.RULE_LABELS[key] or key or ""
end

function Helper.AddFrameToConfig(root, configId, frameName)
	if type(root) ~= "table" or type(frameName) ~= "string" or frameName == "" then return false, "invalid" end
	if root.frameIndex and root.frameIndex[frameName] and root.frameIndex[frameName] ~= configId then
		return false, "assigned"
	end
	local cfg = root.configs and root.configs[configId]
	if not cfg then return false, "missing" end
	cfg.frames = cfg.frames or {}
	for _, name in ipairs(cfg.frames) do
		if name == frameName then return false, "exists" end
	end
	cfg.frames[#cfg.frames + 1] = frameName
	root.frameIndex = root.frameIndex or {}
	root.frameIndex[frameName] = configId
	return true
end

function Helper.RemoveFrameFromConfig(root, configId, frameName)
	if type(root) ~= "table" or type(frameName) ~= "string" or frameName == "" then return false end
	local cfg = root.configs and root.configs[configId]
	if not cfg or type(cfg.frames) ~= "table" then return false end
	for i, name in ipairs(cfg.frames) do
		if name == frameName then
			table.remove(cfg.frames, i)
			break
		end
	end
	if root.frameIndex and root.frameIndex[frameName] == configId then root.frameIndex[frameName] = nil end
	return true
end
