local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")

local UnitAffectingCombat = UnitAffectingCombat
local GetItemCooldown = GetItemCooldown
local GetTime = GetTime
local GetMacroInfo = GetMacroInfo
local EditMacro = EditMacro
local CreateMacro = CreateMacro

local healthMacroName = "EnhanceQoLHealthMacro"

-- DB defaults
addon.functions.InitDBValue("healthMacroEnabled", false)
addon.functions.InitDBValue("healthUseBoth", false)
addon.functions.InitDBValue("healthPreferStoneFirst", true)
addon.functions.InitDBValue("healthReset", "combat")
addon.functions.InitDBValue("healthAllowOther", false)
addon.functions.InitDBValue("healthReorderByCooldown", true)

local function createMacroIfMissing()
	if not addon.db.healthMacroEnabled then return end
	if GetMacroInfo(healthMacroName) == nil then CreateMacro(healthMacroName, "INV_Misc_QuestionMark") end
end

local function buildMacroString(item)
	if item == nil then return "#showtooltip" end
	return "#showtooltip\n/use " .. item
end

local lastItemPlaced
local lastMacroKey

local function isOffCooldown(itemID)
	local start, duration, enable = GetItemCooldown(itemID)
	if not start or start == 0 then return true end
	if duration == 0 then return true end
	local now = GetTime()
	return (start + duration) <= now
end

local function getBestAvailableByType(t)
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.type == t and v.getCount() > 0 then return v end
	end
	return nil
end

local function getBestAvailableAny()
	local list = addon.Health.filteredHealth
	if not list or #list == 0 then return nil end
	for _, v in ipairs(list) do
		if v.getCount() > 0 then return v end
	end
	return nil
end

local function buildResetToken()
	local r = addon.db.healthReset
	if type(r) == "number" then return tostring(r) end
	if r == "10" or r == "30" or r == "60" then return r end
	if r == "target" then return "target" end
	return "combat"
end

local function buildMacro()
	local useBoth = addon.db.healthUseBoth
	local preferStone = addon.db.healthPreferStoneFirst

	local stone = getBestAvailableByType("stone")
	local potion = getBestAvailableByType("potion")

	-- optionally include other healing items
	local other
	if addon.db.healthAllowOther then other = getBestAvailableByType("other") end

	local first, second

    if useBoth then
        -- decide order based on availability, cooldown, then healing amount unless explicitly preferring stone
        local stoneReady = stone and isOffCooldown(stone.id)
        local potionReady = potion and isOffCooldown(potion.id)

        -- fallback: if one is missing, try other
        if not stone and addon.db.healthAllowOther then stone = other end
        if not potion and addon.db.healthAllowOther then potion = other end

        if stone and potion then
            -- 1) cooldown-based reorder if enabled and readiness differs
            if addon.db.healthReorderByCooldown and (stoneReady ~= potionReady) then
                if stoneReady then
                    first, second = stone, potion
                else
                    first, second = potion, stone
                end
            else
                -- 2) explicit preference
                if preferStone then
                    first, second = stone, potion
                else
                    -- 3) highest healing first (default behavior)
                    local hS = stone.heal or 0
                    local hP = potion.heal or 0
                    if hS >= hP then
                        first, second = stone, potion
                    else
                        first, second = potion, stone
                    end
                end
            end
        else
            -- only one available
            first = stone or potion or other
        end
	else
		-- pick the single best by heal value among available
		local candidates = {}
		if stone then table.insert(candidates, stone) end
		if potion then table.insert(candidates, potion) end
		if addon.db.healthAllowOther and other then table.insert(candidates, other) end
		table.sort(candidates, function(a, b) return (a.heal or 0) > (b.heal or 0) end)
		first = candidates[1] or getBestAvailableAny()
	end

	local resetType = buildResetToken()

	local macroBody
	local key
	if first and second then
		-- castsequence; if stone is part of sequence, prefer demonic variant via cache
		local function toUse(v) return v and v.getId() or nil end
		local a = toUse(first)
		local b = toUse(second)
		macroBody = string.format("#showtooltip\n/castsequence reset=%s %s, %s", resetType, a, b)
		key = string.format("seq:%s|%s|%s", a, b, resetType)
	elseif first then
		-- single use: use the actual item found
		macroBody = buildMacroString(first.getId())
		key = string.format("single:%s", first.getId())
	else
		macroBody = buildMacroString(nil)
		key = "empty"
	end

	if key ~= lastMacroKey then
		EditMacro(healthMacroName, healthMacroName, nil, macroBody)
		lastMacroKey = key
	end
end

function addon.Health.functions.updateHealthMacro(ignoreCombat)
	if not addon.db.healthMacroEnabled then return end
	if UnitAffectingCombat("player") and ignoreCombat == false then return end
	createMacroIfMissing()
	addon.Health.functions.updateAllowedHealth()
	buildMacro()
end

-- Events + throttle similar to drinks
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

local pendingUpdate = false
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(true)
	elseif event == "BAG_UPDATE_DELAYED" then
		if not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.1, function()
				addon.Health.functions.updateHealthMacro(false)
				pendingUpdate = false
			end)
		end
	elseif event == "PLAYER_LEVEL_UP" then
		addon.Health.functions.updateAllowedHealth()
		if not UnitAffectingCombat("player") then addon.Health.functions.updateHealthMacro(true) end
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		if addon.Health and addon.Health.functions and addon.Health.functions.refreshTalentCache then addon.Health.functions.refreshTalentCache() end
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	elseif event == "UNIT_MAXHEALTH" then
		if arg1 == "player" then
			addon.Health.functions.updateAllowedHealth()
			addon.Health.functions.updateHealthMacro(false)
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		addon.Health.functions.updateAllowedHealth()
		addon.Health.functions.updateHealthMacro(false)
	end
end)

-- UI section for Health Macro (mounted under Drink Macro)
function addon.Health.functions.addHealthFrame(container)
    local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
    container:AddChild(wrapper)

    local group = addon.functions.createContainer("InlineGroup", "List")
    wrapper:AddChild(group)

    local cb = addon.functions.createCheckboxAce(L["Enable Health Macro"], addon.db["healthMacroEnabled"], function(_, _, value)
        addon.db["healthMacroEnabled"] = value
        addon.Health.functions.updateHealthMacro(false)
        container:ReleaseChildren()
        addon.Health.functions.addHealthFrame(container)
    end)
    group:AddChild(cb)

    -- If disabled, render nothing else
    if not addon.db["healthMacroEnabled"] then return end

    local cbBoth = addon.functions.createCheckboxAce(L["Use Healthstone and Potion"], addon.db["healthUseBoth"], function(_, _, value)
        addon.db["healthUseBoth"] = value
        addon.Health.functions.updateHealthMacro(false)
        container:ReleaseChildren()
        addon.Health.functions.addHealthFrame(container)
    end)
    group:AddChild(cbBoth)

    if addon.db["healthUseBoth"] then
        local cbPrefer = addon.functions.createCheckboxAce(L["Prefer Healthstone first"], addon.db["healthPreferStoneFirst"], function(_, _, value)
            addon.db["healthPreferStoneFirst"] = value
            addon.Health.functions.updateHealthMacro(false)
        end)
        group:AddChild(cbPrefer)
    end

	local cbOther = addon.functions.createCheckboxAce(L["Allow other healing items"], addon.db["healthAllowOther"], function(_, _, value)
		addon.db["healthAllowOther"] = value
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbOther)

	local cbReorder = addon.functions.createCheckboxAce(L["Reorder by cooldown on combat end"], addon.db["healthReorderByCooldown"], function(_, _, value)
		addon.db["healthReorderByCooldown"] = value
		addon.Health.functions.updateHealthMacro(false)
	end)
	group:AddChild(cbReorder)

	local resetList = { combat = L["Reset: Combat"], target = L["Reset: Target"], ["10"] = L["Reset: 10s"], ["30"] = L["Reset: 30s"], ["60"] = L["Reset: 60s"] }
	local order = { "combat", "target", "10", "30", "60" }
	local dropReset = addon.functions.createDropdownAce(L["Reset condition"], resetList, order, function(self, _, val)
		addon.db["healthReset"] = val
		self:SetValue(val)
		addon.Health.functions.updateHealthMacro(false)
	end)
	dropReset:SetValue(addon.db["healthReset"])
	group:AddChild(dropReset)

    local label = addon.functions.createLabelAce(healthMacroName .. " - place on your bar (updates outside combat)", nil, nil, 11)
    group:AddChild(label)

    group:AddChild(addon.functions.createSpacerAce())
    local gold = { r = 1, g = 0.843, b = 0 }
    local hint = addon.functions.createLabelAce(L["healthMacroBestFirst"], gold, nil, 11)
    group:AddChild(hint)
end
