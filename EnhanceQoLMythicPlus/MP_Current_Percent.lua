local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")

-- Ultra‑lightweight tracker for current pull percent in M+.
-- Design goals:
--  - Zero cost when MDT is not loaded or when not in/entering an M+ run
--  - Conditional event registration (add/remove COMBAT_LOG only while active)
--  - Early exits in hot paths (e.g., CL events) and GUID de‑duplication

local MPlus = {}
MPlus.active = false
MPlus.weights = {} -- [npcId] = forcesCount (or weight)
MPlus.inPullGUID = {} -- set: [guid] = true
MPlus.inPullByNPC = {} -- [npcId] = { guids = set, _count = int }
MPlus.pullForces = 0 -- absolute forces for current pull
MPlus.maxForces = 0 -- from MDT objective cap
MPlus.uiThrottle = 0
addon.MPlusData = MPlus

-- forward declarations for locals referenced earlier
local EnsureUILabel
local UpdateUILabel

local function NPCIDFromGUID(guid)
	-- guid: Creature-0-*-*-*-<npcId>-*
	local id = guid and select(6, strsplit("-", guid))
	return id and tonumber(id)
end

-- MDT Integration (built once per run/preset)
local function BuildWeightsFromMDT()
	wipe(MPlus.weights)
	if not MDT then return end
	-- Guard against MDT not fully initialized yet (e.g., db is nil)
	local okPreset, preset = pcall(function() return MDT.GetCurrentPreset and MDT:GetCurrentPreset() end)
	if not okPreset or not preset then return end
	local okIsTeeming, isTeeming = pcall(function() return MDT.IsPresetTeeming and MDT:IsPresetTeeming(preset) end)
	isTeeming = okIsTeeming and isTeeming or false

	local sData = C_ScenarioInfo.GetScenarioStepInfo()

	for criteriaIndex = 1, sData.numCriteria do
		local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
		if criteriaInfo and criteriaInfo.isWeightedProgress and criteriaInfo.totalQuantity then MPlus.maxForces = criteriaInfo.totalQuantity end
	end

	if MPlus.maxForces then
		local mapID = C_Map.GetBestMapForUnit("player")
		local mdtID = MDT.zoneIdToDungeonIdx[mapID]

		local enemies = MDT.dungeonEnemies and MDT.dungeonEnemies[mdtID]
		if type(enemies) == "table" then
			for _, entry in pairs(enemies) do
				if entry.id and entry.count then MPlus.weights[entry.id] = entry.count * 100 / MPlus.maxForces end
			end
		end
		if UpdateUILabel then UpdateUILabel() end
	end
end

local function ResetPull()
	wipe(MPlus.inPullGUID)
	wipe(MPlus.inPullByNPC)
	MPlus.pullForces = 0
	if UpdateUILabel then UpdateUILabel() end
end

local function RecomputePullForces()
	local sum = 0
	for npcId, data in pairs(MPlus.inPullByNPC) do
		local perMob = MPlus.weights[npcId]
		if perMob and data.guids then sum = sum + perMob * (data._count or 0) end
	end
	MPlus.pullForces = sum
	if UpdateUILabel then UpdateUILabel() end
end

local function AddGUIDToPull(guid)
	if MPlus.inPullGUID[guid] then return end -- already accounted
	local npcId = NPCIDFromGUID(guid)
	if not npcId then return end
	local perMob = MPlus.weights[npcId]
	if not perMob then return end -- ignorieren (kein Forces-Eintrag, Minion o.ä.)

	MPlus.inPullGUID[guid] = true
	local b = MPlus.inPullByNPC[npcId]
	if not b then
		b = { guids = {}, _count = 0 }
		MPlus.inPullByNPC[npcId] = b
	end
	b.guids[guid] = true
	b._count = b._count + 1
	RecomputePullForces()
end

local function RemoveGUIDFromPull(guid)
	if not MPlus.inPullGUID[guid] then return end
	MPlus.inPullGUID[guid] = nil
	local npcId = NPCIDFromGUID(guid)
	local b = npcId and MPlus.inPullByNPC[npcId]
	if b and b.guids[guid] then
		b.guids[guid] = nil
		b._count = math.max(0, (b._count or 1) - 1)
		if b._count == 0 then MPlus.inPullByNPC[npcId] = nil end
		RecomputePullForces()
	end
end

-- Prozent (optional)
local function GetPullPercent()
	if MPlus.maxForces and MPlus.maxForces > 0 then return 100 * (MPlus.pullForces / MPlus.maxForces) end
	return 0
end

-- === Lightweight UI label on Scenario tracker ===
function EnsureUILabel()
	if MPlus.uiFrame and MPlus.uiFrame.text then return end
	local frame = CreateFrame("Frame", "EnhanceQoL_CurrentPullLabel", ScenarioObjectiveTracker.ContentsFrame)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetSize(140, 20)

	frame:SetPoint("TOPLEFT", ScenarioObjectiveTracker.ContentsFrame, "BOTTOMLEFT", 0, 10)

	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")
	fs:SetText(L["CurrentPull"]:format("0"))

	frame.text = fs
	MPlus.uiFrame = frame
end

function UpdateUILabel()
	if not MDT or not MPlus.active or not (addon and addon.db and addon.db["mythicPlusCurrentPull"]) then
		if MPlus.uiFrame then MPlus.uiFrame:Hide() end
		return
	end
	EnsureUILabel()
	if not MPlus.uiFrame then return end

	-- apply font/position settings
	local fs = addon.db["mythicPlusCurrentPullFontSize"] or 14
	if addon.variables and addon.variables.defaultFont then
		MPlus.uiFrame.text:SetFont(addon.variables.defaultFont, fs, "OUTLINE")
	else
		MPlus.uiFrame.text:SetFont(GameFontNormal:GetFont(), fs, "OUTLINE")
	end

	if MPlus.maxForces and MPlus.maxForces > 0 then
		local text = L["CurrentPull"]:format(MPlus.pullForces)
		if text ~= MPlus._lastUILabel then
			MPlus.uiFrame.text:SetText(text)
			MPlus._lastUILabel = text
		end
		MPlus.uiFrame:Show()
	else
		local text = L["CurrentPull"]:format("0")
		if text ~= MPlus._lastUILabel then
			MPlus.uiFrame.text:SetText(text)
			MPlus._lastUILabel = text
		end
	end
end

-- === Events ===
local f = CreateFrame("Frame")

-- localize bit ops and masks for hot path
local band = bit.band
local MASK_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE
local MASK_NPC = COMBATLOG_OBJECT_TYPE_NPC
local function isHostileNPC(flags) return band(flags or 0, MASK_HOSTILE) ~= 0 and band(flags or 0, MASK_NPC) ~= 0 end

local allowedSub = {
	SWING_DAMAGE = true,
	SWING_MISSED = true,
	RANGE_DAMAGE = true,
	SPELL_DAMAGE = true,
	SPELL_MISSED = true,
	SPELL_PERIODIC_DAMAGE = true,
	SPELL_CAST_START = true,
	SPELL_CAST_SUCCESS = true,
	SPELL_AURA_APPLIED = true,
	SPELL_AURA_REFRESH = true,
	UNIT_DIED = true,
	UNIT_DESTROYED = true,
	UNIT_DISSIPATES = true,
}

local function SetCombatLogActive(active)
	if active then
		f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

local function IsInKeystoneRun()
	local inInstance, _ = IsInInstance()
	if not inInstance then return false end
	local difficultyID = select(3, GetInstanceInfo())
	return difficultyID == 8 -- Mythic Keystone
end

local function ActivateRun()
	if MPlus.active then return end
	MPlus.active = true
	ResetPull()
	BuildWeightsFromMDT()
	SetCombatLogActive(true)
	UpdateUILabel()
end

local function DeactivateRun()
	if not MPlus.active then return end
	MPlus.active = false
	ResetPull()
	SetCombatLogActive(false)
	UpdateUILabel()
end

local baseEventsRegistered = false
local mdtInitDone = false
local function EnsureBaseEvents()
	if baseEventsRegistered then return end
	f:RegisterEvent("CHALLENGE_MODE_START")
	f:RegisterEvent("CHALLENGE_MODE_RESET")
	f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	-- PLAYER_ENTERING_WORLD wird initial ohnehin registriert (s. unten)
	baseEventsRegistered = true
end

local function OnMDTReady()
	EnsureBaseEvents()
	-- Falls wir schon in einer aktiven Instanz sind, M+ ggf. sofort aktivieren/deaktivieren
	if IsInKeystoneRun() then
		ActivateRun()
	else
		DeactivateRun()
	end
end

f:SetScript("OnEvent", function(_, ev, arg1)
	-- Feature must be enabled explicitly in settings
	if not (addon and addon.db and addon.db["mythicPlusCurrentPull"]) then return end
	if ev == "ADDON_LOADED" then
		-- Lazy detect MDT when it loads after us
		if not MDT and _G.MDT then MDT = _G.MDT end
		if MDT and not mdtInitDone then
			mdtInitDone = true
			OnMDTReady()
		end
		return
	end

	if ev == "CHALLENGE_MODE_START" then
		if not MDT and _G.MDT then MDT = _G.MDT end
		if MDT then ActivateRun() end
		return
	end

	if ev == "CHALLENGE_MODE_RESET" or ev == "CHALLENGE_MODE_COMPLETED" then
		if not MDT and _G.MDT then MDT = _G.MDT end
		if MDT then DeactivateRun() end
		return
	end

	if ev == "PLAYER_ENTERING_WORLD" then
		-- Only a single initial pass per session. PEW fires on every loading screen.
		if mdtInitDone then return end
		-- Last-chance init: check for MDT once here at startup
		if not MDT and _G.MDT then MDT = _G.MDT end
		if MDT then
			mdtInitDone = true
			OnMDTReady()
		end
		return
	end

	if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not MDT or not MPlus.active then return end
		-- Late MDT init guard: try once more to build weights when first combat events arrive
		if (MPlus.maxForces or 0) == 0 or (next(MPlus.weights) == nil) then BuildWeightsFromMDT() end
		local _, sub, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags = CombatLogGetCurrentEventInfo()
		if not allowedSub[sub] then return end

		-- Source
		if srcGUID and not MPlus.inPullGUID[srcGUID] and isHostileNPC(srcFlags) then
			print("Added", "source")
			AddGUIDToPull(srcGUID)
		end
		-- Destination
		if dstGUID and isHostileNPC(dstFlags) then
			if not MPlus.inPullGUID[dstGUID] then AddGUIDToPull(dstGUID) end
			if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" or sub == "UNIT_DISSIPATES" then RemoveGUIDFromPull(dstGUID) end
		end
		return
	end
end)

-- Toggle registration from the MythicPlus UI
addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
function addon.MythicPlus.functions.ToggleCurrentPull(enabled)
	if enabled then
		f:RegisterEvent("ADDON_LOADED")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		-- If MDT is around already, initialize immediately
		if _G.MDT and not MDT then MDT = _G.MDT end
		if MDT and not mdtInitDone then
			mdtInitDone = true
			OnMDTReady()
		end
	else
		f:UnregisterEvent("ADDON_LOADED")
		f:UnregisterEvent("PLAYER_ENTERING_WORLD")
		f:UnregisterEvent("CHALLENGE_MODE_START")
		f:UnregisterEvent("CHALLENGE_MODE_RESET")
		f:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
		f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		DeactivateRun()
		baseEventsRegistered = false
	end
end

-- Apply initial state based on saved setting
if addon and addon.db and addon.db["mythicPlusCurrentPull"] then addon.MythicPlus.functions.ToggleCurrentPull(true) end
