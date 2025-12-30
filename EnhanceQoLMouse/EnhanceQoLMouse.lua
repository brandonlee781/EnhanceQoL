local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Mouse")

-- Hotpath locals & constants
local GetCursorPosition = GetCursorPosition
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitClass = UnitClass
local GetClassColor = GetClassColor
local RING_FRAME_NAME = addonName .. "_MouseRingFrame"
local TEX_MOUSE = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Mouse.tga"
local TEX_DOT = "Interface\\AddOns\\" .. addonName .. "\\Icons\\Dot.tga"
addon.Mouse.variables.TEXT_DOT = TEX_DOT
local TEX_TRAIL = "Interface\\AddOns\\" .. addonName .. "\\Icons\\MouseTrail.tga"

local MaxActuationPoint = 1 -- Minimaler Bewegungsabstand für Trail-Elemente
local MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
local duration = 0.3 -- Lebensdauer der Trail-Elemente in Sekunden
local Density = 0.02 -- Zeitdichte für neue Elemente
local ElementCap = 28 -- Maximale Anzahl von Trail-Elementen
local PastCursorX, PastCursorY, PresentCursorX, PresentCursorY = nil, nil, nil, nil

local trailPool = {}
local activeCount = 0
local playerClass = UnitClass and select(2, UnitClass("player")) or nil
local classR, classG, classB
if playerClass and GetClassColor then
	classR, classG, classB = GetClassColor(playerClass)
end
local currentPreset = nil

local trailPresets = {
	[1] = { -- LOW
		MaxActuationPoint = 1.0,
		duration = 0.4,
		Density = 0.025,
		ElementCap = 20,
	},
	[2] = { -- MEDIUM
		MaxActuationPoint = 0.7,
		duration = 0.5,
		Density = 0.02,
		ElementCap = 40,
	},
	[3] = { -- HIGH (Sweet Spot)
		MaxActuationPoint = 0.5,
		duration = 0.7,
		Density = 0.012,
		ElementCap = 80,
	},
	[4] = { -- ULTRA
		MaxActuationPoint = 0.3,
		duration = 0.7,
		Density = 0.007,
		ElementCap = 120,
	},
	[5] = { -- ULTRA HIGH
		MaxActuationPoint = 0.2,
		duration = 0.8,
		Density = 0.005,
		ElementCap = 150,
	},
}

local function createTrailElement()
	local tex = UIParent:CreateTexture(nil)
	tex:SetTexture(TEX_TRAIL)
	tex:SetBlendMode("ADD")
	tex:SetSize(35, 35)

	local ag = tex:CreateAnimationGroup()
	ag:SetScript("OnFinished", function(self)
		local t = self:GetParent()
		t:Hide()
		trailPool[#trailPool + 1] = t
		activeCount = activeCount - 1
	end)
	local fade = ag:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)

	tex.anim = ag
	tex.fade = fade

	return tex
end

local function ensureTrailPool()
	local total = activeCount + #trailPool
	if total >= ElementCap then return end
	for _ = 1, (ElementCap - total) do
		local tex = createTrailElement()
		tex:Hide()
		trailPool[#trailPool + 1] = tex
	end
end

local function applyPreset(presetName)
	local preset = trailPresets[presetName]
	if not preset then return end
	MaxActuationPoint = preset.MaxActuationPoint
	MaxActuationPointSq = MaxActuationPoint * MaxActuationPoint
	duration = preset.duration
	Density = preset.Density
	ElementCap = preset.ElementCap
	currentPreset = presetName

	if addon.db and addon.db["mouseTrailEnabled"] then ensureTrailPool() end
end
addon.Mouse.functions.applyPreset = applyPreset

local timeAccumulator = 0

local function getTrailColor()
	if addon.db["mouseTrailUseClassColor"] then
		if not classR then
			local class = playerClass or (UnitClass and select(2, UnitClass("player")))
			if class then playerClass = class end
			if class and GetClassColor then
				classR, classG, classB = GetClassColor(class)
			end
		end
		if classR then return classR, classG, classB, 1 end
		return 1, 1, 1, 1
	end
	local c = addon.db["mouseTrailColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 1, 1, 1
end

local function getRingColor()
	if addon.db["mouseRingUseClassColor"] then
		if not classR then
			local class = playerClass or (UnitClass and select(2, UnitClass("player")))
			if class then playerClass = class end
			if class and GetClassColor then
				classR, classG, classB = GetClassColor(class)
			end
		end
		if classR then return classR, classG, classB, 1 end
		return 1, 1, 1, 1
	end
	local c = addon.db["mouseRingColor"]
	if c then return c.r, c.g, c.b, c.a or 1 end
	return 1, 1, 1, 1
end

local function UpdateMouseTrail(delta, cursorX, cursorY, effectiveScale)
	-- Delta = Zeit seit letztem Frame

	-- Ersten Maus-Frame sauber initialisieren
	if PresentCursorX == nil then
		PresentCursorX, PresentCursorY = cursorX, cursorY
		return -- Startposition gesetzt
	end

	-- Zeit hochzählen
	timeAccumulator = timeAccumulator + delta

	-- Aktuelle Mausposition holen, Distanz ermitteln
	PastCursorX, PastCursorY = PresentCursorX, PresentCursorY
	PresentCursorX, PresentCursorY = cursorX, cursorY

	local dx = PresentCursorX - PastCursorX
	local dy = PresentCursorY - PastCursorY
	local distanceSq = dx * dx + dy * dy

	-- Neues Trail-Element anlegen?
	if timeAccumulator >= Density and distanceSq >= MaxActuationPointSq then
		timeAccumulator = timeAccumulator - Density

		if activeCount < ElementCap and #trailPool > 0 then
			local element = trailPool[#trailPool]
			trailPool[#trailPool] = nil
			activeCount = activeCount + 1

			element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", PresentCursorX / effectiveScale, PresentCursorY / effectiveScale)

			local r, g, b, a = getTrailColor()
			element:SetVertexColor(r, g, b, a)

			element.fade:SetDuration(duration)
			element.anim:Stop()
			element.anim:Play()
			element:Show()
		end
	end
end

local function createMouseRing()
	if addon.mousePointer then
		addon.mousePointer:Show()
		return
	end

	local imageFrame = _G[RING_FRAME_NAME]
	if not imageFrame then
		imageFrame = CreateFrame("Frame", RING_FRAME_NAME, UIParent, "BackdropTemplate")
		imageFrame:SetSize(120, 120)
		imageFrame:SetBackdropColor(0, 0, 0, 0)
		imageFrame:SetFrameStrata("TOOLTIP")
	end

	local texture1 = imageFrame.texture1
	if not texture1 then
		texture1 = imageFrame:CreateTexture(nil, "BACKGROUND")
		texture1:SetTexture(TEX_MOUSE)
		texture1:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
		imageFrame.texture1 = texture1
	end
	texture1:SetSize(addon.db["mouseRingSize"], addon.db["mouseRingSize"])
	local rr, rg, rb, ra = getRingColor()
	texture1:SetVertexColor(rr, rg, rb, ra)

	if addon.db["mouseRingHideDot"] then
		if imageFrame.dot then imageFrame.dot:Hide() end
	else
		local dot = imageFrame.dot
		if not dot then
			dot = imageFrame:CreateTexture(nil, "BACKGROUND")
			dot:SetTexture(TEX_DOT)
			dot:SetSize(10, 10)
			dot:SetPoint("CENTER", imageFrame, "CENTER", 0, 0)
			imageFrame.dot = dot
		end
		dot:Show()
	end

	imageFrame:Show()
	addon.mousePointer = imageFrame
end
addon.Mouse.functions.createMouseRing = createMouseRing

local function removeMouseRing()
	if addon.mousePointer then addon.mousePointer:Hide() end
end
addon.Mouse.functions.removeMouseRing = removeMouseRing

if addon.db["mouseRingEnabled"] then createMouseRing() end

if addon.db["mouseTrailEnabled"] then applyPreset(addon.db["mouseTrailDensity"]) end

-- Manage visibility of the ring based on combat state
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- enter combat
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- leave combat
eventFrame:SetScript("OnEvent", function()
	if not addon.db["mouseRingEnabled"] then return end
	if addon.db["mouseRingOnlyInCombat"] then
		if UnitAffectingCombat("player") then
			if not addon.mousePointer then createMouseRing() end
			if addon.mousePointer then addon.mousePointer:Show() end
		else
			if addon.mousePointer then addon.mousePointer:Hide() end
		end
	else
		if not addon.mousePointer then createMouseRing() end
		if addon.mousePointer then addon.mousePointer:Show() end
	end
end)

-- Shared runner for ring + trail updates
if not addon.mouseTrailRunner then
	local runner = CreateFrame("Frame")
	local lastTrailWanted = false
	runner:SetScript("OnUpdate", function(self, delta)
		local db = addon.db
		if not db then return end
		local ringOnly = db["mouseRingOnlyInCombat"]
		local trailOnly = db["mouseTrailOnlyInCombat"]
		local inCombat
		if ringOnly or trailOnly then inCombat = UnitAffectingCombat and UnitAffectingCombat("player") end
		local ringWanted = db["mouseRingEnabled"] and (not ringOnly or inCombat)
		local trailWanted = db["mouseTrailEnabled"] and (not trailOnly or inCombat)
		if trailWanted and currentPreset ~= db["mouseTrailDensity"] then applyPreset(db["mouseTrailDensity"]) end
		if trailWanted and not lastTrailWanted then
			ensureTrailPool()
			PresentCursorX, PresentCursorY = nil, nil
			timeAccumulator = 0
		end
		lastTrailWanted = trailWanted
		if not ringWanted and not trailWanted then return end
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		if ringWanted and addon.mousePointer and addon.mousePointer:IsShown() then
			addon.mousePointer:ClearAllPoints()
			addon.mousePointer:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
		end
		if trailWanted then UpdateMouseTrail(delta, x, y, scale) end
	end)
	addon.mouseTrailRunner = runner
end
