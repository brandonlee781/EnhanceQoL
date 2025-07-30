-- CooldownNotify.lua - Notify when cooldowns are ready
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.CooldownNotify = addon.Aura.CooldownNotify or {}
local CN = addon.Aura.CooldownNotify
CN.functions = CN.functions or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")
local AceGUI = addon.AceGUI

local watching = {}
local cooldowns = {}
local animating = {}
local itemSpells = {}
local treeGroup
local anchors = {}

local DCP = CreateFrame("Frame", nil, UIParent)
DCP:SetPoint("CENTER")
DCP:SetSize(75, 75)
DCP:SetAlpha(0)
DCP:Hide()
DCP:SetScript("OnEvent", function(self, event, ...)
	if CN[event] then CN[event](CN, ...) end
end)

DCP.texture = DCP:CreateTexture(nil, "BACKGROUND")
DCP.texture:SetAllPoints(DCP)

DCP.text = DCP:CreateFontString(nil, "ARTWORK")
DCP.text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
DCP.text:SetShadowOffset(2, -2)
DCP.text:SetPoint("CENTER", DCP, "CENTER")
DCP.text:SetWidth(185)
DCP.text:SetJustifyH("CENTER")
DCP.text:SetTextColor(1, 1, 1)

local elapsed = 0
local runtimer = 0

local function IsAnimatingCooldownByName(name)
	for _, info in ipairs(animating) do
		if info[3] == name then return true end
	end
	return false
end

local function OnUpdate(_, update)
	elapsed = elapsed + update
	if elapsed > 0.05 then
		for id, v in pairs(watching) do
			if GetTime() >= v.start + 0.5 then
				local start, duration, enabled, texture, name, isPet
				if v.type == "spell" then
					local cd = C_Spell.GetSpellCooldown(v.spell)
					start = cd.startTime
					duration = cd.duration
					enabled = cd.isEnabled
					name = C_Spell.GetSpellName(v.spell)
					texture = C_Spell.GetSpellTexture(v.spell)
				elseif v.type == "item" then
					start, duration, enabled = C_Container.GetItemCooldown(id)
					name = GetItemInfo(id)
					texture = v.texture
				elseif v.type == "pet" then
					name, texture = GetPetActionInfo(v.index)
					start, duration, enabled = GetPetActionCooldown(v.index)
					isPet = true
				end
				if enabled ~= 0 and duration and duration > 2 and texture then
					cooldowns[id] = {
						start = start,
						duration = duration,
						texture = texture,
						name = name,
						isPet = isPet,
						catId = v.catId,
					}
				end
				watching[id] = nil
			end
		end
		for i, cd in pairs(cooldowns) do
			if cd.start then
				local remaining = cd.duration - (GetTime() - cd.start)
				local cat = addon.db.cooldownNotifyCategories[cd.catId] or {}
				local threshold = cat.remainingCooldownWhenNotified or 0
				if remaining <= threshold then
					if not IsAnimatingCooldownByName(cd.name) then table.insert(animating, { cd.texture, cd.isPet, cd.name, cd.catId }) end
					cooldowns[i] = nil
				end
			else
				cooldowns[i] = nil
			end
		end
		elapsed = 0
		if #animating == 0 and next(watching) == nil and next(cooldowns) == nil then
			DCP:SetScript("OnUpdate", nil)
			DCP:Hide()
			return
		end
	end

	if #animating > 0 then
		runtimer = runtimer + update
		local info = animating[1]
		local cat = addon.db.cooldownNotifyCategories[info[4]] or {}
		local fadeInTime = cat.fadeInTime or 0.3
		local fadeOutTime = cat.fadeOutTime or 0.7
		local maxAlpha = cat.maxAlpha or 0.7
		local animScale = cat.animScale or 1.5
		local iconSize = cat.iconSize or 75
		local holdTime = cat.holdTime or 0
		if runtimer > (fadeInTime + holdTime + fadeOutTime) then
			table.remove(animating, 1)
			runtimer = 0
			DCP.text:SetText(nil)
			DCP.texture:SetTexture(nil)
			DCP.texture:SetVertexColor(1, 1, 1)
		else
			if not DCP.texture:GetTexture() then
				if cat.showName and info[3] then
					local txt = info[3]
					if cat.customText and cat.customText ~= "" then txt = cat.customText end
					DCP.text:SetText(txt)
				end
				DCP.texture:SetTexture(info[1])
				if info[2] then DCP.texture:SetVertexColor(1, 1, 1) end
				local anch = cat.anchor or {}
				DCP:SetPoint(anch.point or "CENTER", UIParent, anch.point or "CENTER", anch.x or 0, anch.y or 0)
				DCP:SetSize(iconSize, iconSize)
				DCP:Show()
				if cat.soundReady and cat.soundKey then
					local file = addon.Aura.sounds[cat.soundKey]
					if file then PlaySoundFile(file, "Master") end
				end
			end
			local alpha = maxAlpha
			if runtimer < fadeInTime then
				alpha = maxAlpha * (runtimer / fadeInTime)
			elseif runtimer >= fadeInTime + holdTime then
				alpha = maxAlpha - (maxAlpha * ((runtimer - holdTime - fadeInTime) / fadeOutTime))
			end
			DCP:SetAlpha(alpha)
			local scale = iconSize + (iconSize * ((animScale - 1) * (runtimer / (fadeInTime + holdTime + fadeOutTime))))
			DCP:SetSize(scale, scale)
		end
	end
end

local function ensureAnchor(id)
	if anchors[id] then return anchors[id] end

	local cat = addon.db.cooldownNotifyCategories[id]
	if not cat then return nil end

	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }

	local anchor = CreateFrame("Frame", "EQOLCooldownNotifyAnchor" .. id, UIParent, "BackdropTemplate")
	anchor:SetSize(cat.iconSize or 75, cat.iconSize or 75)
	anchor:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
	anchor:SetBackdropColor(0, 0, 0, 0.6)
	anchor:SetMovable(true)
	anchor:EnableMouse(true)
	anchor:RegisterForDrag("LeftButton")

	anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	anchor.text:SetPoint("CENTER", anchor, "CENTER")
	anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. (cat.name or "") .. "|r"))

	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, xOfs, yOfs = self:GetPoint()
		cat.anchor.point = point
		cat.anchor.x = xOfs
		cat.anchor.y = yOfs
	end)

	anchor:SetScript("OnShow", function()
		if cat.anchor then
			anchor:ClearAllPoints()
			anchor:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)
		end
	end)

	if cat.anchor then
		anchor:ClearAllPoints()
		anchor:SetPoint(cat.anchor.point, UIParent, cat.anchor.point, cat.anchor.x, cat.anchor.y)
	end

	anchors[id] = anchor
	return anchor
end

local function applyLockState()
	for id, anchor in pairs(anchors) do
		if not addon.db.cooldownNotifyEnabled[id] then
			anchor:Hide()
		elseif addon.db.cooldownNotifyLocked[id] then
			anchor:RegisterForDrag()
			anchor:SetMovable(false)
			anchor:EnableMouse(false)
			anchor:SetScript("OnDragStart", nil)
			anchor:SetScript("OnDragStop", nil)
			anchor:SetBackdropColor(0, 0, 0, 0)
			if anchor.text then anchor.text:Hide() end
			anchor:Show()
		else
			anchor:RegisterForDrag("LeftButton")
			anchor:SetMovable(true)
			anchor:EnableMouse(true)
			anchor:SetScript("OnDragStart", anchor.StartMoving)
			anchor:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				local cat = addon.db.cooldownNotifyCategories[id]
				if cat and cat.anchor then
					local point, _, _, xOfs, yOfs = self:GetPoint()
					cat.anchor.point = point
					cat.anchor.x = xOfs
					cat.anchor.y = yOfs
				end
			end)
			anchor:SetBackdropColor(0, 0, 0, 0.6)
			if anchor.text then
				local cat = addon.db.cooldownNotifyCategories[id]
				anchor.text:SetText(L["DragToPosition"]:format("|cffffd700" .. ((cat and cat.name) or "") .. "|r"))
				anchor.text:Show()
			end
			anchor:Show()
		end
	end
end

function CN:SPELL_UPDATE_COOLDOWN()
	for _, cd in pairs(cooldowns) do
		-- noop: placeholder for future resets
	end
end

local function TrackItemSpell(itemID)
	local _, spellID = GetItemSpell(itemID)
	if spellID then
		itemSpells[spellID] = itemID
		return true
	end
	return false
end

function CN:UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
	if unit ~= "player" then return end
	for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
		if addon.db.cooldownNotifyEnabled[catId] then
			if cat.spells and cat.spells[spellID] then watching[spellID] = { start = GetTime(), type = "spell", spell = spellID, catId = catId } end
		end
	end
	local itemID = itemSpells[spellID]
	if itemID then
		local texture = select(10, GetItemInfo(itemID))
		for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
			if addon.db.cooldownNotifyEnabled[catId] and cat.items and cat.items[itemID] then watching[itemID] = { start = GetTime(), type = "item", texture = texture, catId = catId } end
		end
		itemSpells[spellID] = nil
	end
	if not DCP:GetScript("OnUpdate") then DCP:SetScript("OnUpdate", OnUpdate) end
end

function CN:COMBAT_LOG_EVENT_UNFILTERED()
	local _, event, _, _, _, sourceFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
	if event == "SPELL_CAST_SUCCESS" then
		if bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) == COMBATLOG_OBJECT_TYPE_PET and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) == COMBATLOG_OBJECT_AFFILIATION_MINE then
			local name = C_Spell.GetSpellName(spellID)
			local index = GetPetActionIndexByName(name)
			if index then
				for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
					if addon.db.cooldownNotifyEnabled[catId] and cat.pets and cat.pets[name] then
						watching[spellID] = { start = GetTime(), type = "pet", index = index, catId = catId }
						if not DCP:GetScript("OnUpdate") then DCP:SetScript("OnUpdate", OnUpdate) end
					end
				end
			end
		end
	end
end

hooksecurefunc("UseAction", function(slot)
	local actionType, itemID = GetActionInfo(slot)
	if actionType == "item" and not TrackItemSpell(itemID) then
		local texture = GetActionTexture(slot)
		for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
			if addon.db.cooldownNotifyEnabled[catId] and cat.items and cat.items[itemID] then watching[itemID] = { start = GetTime(), type = "item", texture = texture, catId = catId } end
		end
	end
end)

hooksecurefunc("UseInventoryItem", function(slot)
	local itemID = GetInventoryItemID("player", slot)
	if itemID and not TrackItemSpell(itemID) then
		local texture = GetInventoryItemTexture("player", slot)
		for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
			if addon.db.cooldownNotifyEnabled[catId] and cat.items and cat.items[itemID] then watching[itemID] = { start = GetTime(), type = "item", texture = texture, catId = catId } end
		end
	end
end)

hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
	local itemID = C_Container.GetContainerItemID(bag, slot)
	if itemID and not TrackItemSpell(itemID) then
		local texture = select(10, GetItemInfo(itemID))
		for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
			if addon.db.cooldownNotifyEnabled[catId] and cat.items and cat.items[itemID] then watching[itemID] = { start = GetTime(), type = "item", texture = texture, catId = catId } end
		end
	end
end)

CN.frame = DCP

local function getCategoryTree()
	local tree = {}
	for catId, cat in pairs(addon.db.cooldownNotifyCategories or {}) do
		local text = cat.name
		if addon.db.cooldownNotifyEnabled[catId] == false then text = "|cff808080" .. text .. "|r" end
		local node = { value = catId, text = text, children = {} }

		local spells = {}
		for id in pairs(cat.spells or {}) do
			table.insert(spells, id)
		end
		table.sort(spells)
		for _, spellId in ipairs(spells) do
			local info = C_Spell.GetSpellInfo(spellId)
			table.insert(node.children, {
				value = catId .. "\001" .. spellId,
				text = info and info.name or tostring(spellId),
				icon = info and info.iconID,
			})
		end
		table.insert(tree, node)
	end

	table.sort(tree, function(a, b) return a.value < b.value end)
	table.insert(tree, { value = "ADD_CATEGORY", text = "|cff00ff00+ " .. (L["Add Category"] or "Add Category") })
	table.insert(tree, { value = "IMPORT_CATEGORY", text = "|cff00ccff+ " .. (L["ImportCategory"] or "Import Category") })
	return tree
end

local function refreshTree(selectValue)
	if not treeGroup then return end
	treeGroup:SetTree(getCategoryTree())
	if selectValue then treeGroup:SelectByValue(tostring(selectValue)) end
end

local function buildCategoryOptions(container, catId)
	addon.db.cooldownNotifySelectedCategory = catId
	local cat = addon.db.cooldownNotifyCategories[catId]
	local group = addon.functions.createContainer("InlineGroup", "List")
	container:AddChild(group)
	group:SetFullHeight(true)

	local enableCB = addon.functions.createCheckboxAce(L["EnableCooldownNotify"]:format(cat.name), addon.db.cooldownNotifyEnabled[catId], function(_, _, val)
		addon.db.cooldownNotifyEnabled[catId] = val
		applyLockState()
	end)
	group:AddChild(enableCB)

	local lockCB = addon.functions.createCheckboxAce(L["buffTrackerLocked"], addon.db.cooldownNotifyLocked[catId], function(_, _, val)
		addon.db.cooldownNotifyLocked[catId] = val
		applyLockState()
	end)
	group:AddChild(lockCB)

	local showNameCB = addon.functions.createCheckboxAce(L["ShowCooldownName"], cat.showName, function(_, _, val) cat.showName = val end)
	group:AddChild(showNameCB)

	local customTextCB = addon.functions.createCheckboxAce(L["Show custom text"], cat.customTextEnabled, function(_, _, val) cat.customTextEnabled = val end)
	group:AddChild(customTextCB)

	local customTextEdit = addon.functions.createEditboxAce(L["Text"], cat.customText or "", function(_, _, text) cat.customText = text end)
	group:AddChild(customTextEdit)

	local soundList = {}
	for sname in pairs(addon.Aura.sounds or {}) do
		soundList[sname] = sname
	end
	local list, order = addon.functions.prepareListForDropdown(soundList)
	local soundDrop = addon.functions.createDropdownAce(L["SoundFile"], list, order, function(self, _, key)
		cat.soundKey = key
		self:SetValue(key)
		local file = addon.Aura.sounds[key]
		if file then PlaySoundFile(file, "Master") end
	end)
	soundDrop:SetValue(cat.soundKey)
	group:AddChild(soundDrop)

	local playSoundCB = addon.functions.createCheckboxAce(L["Play sound on ready"], cat.soundReady, function(_, _, val) cat.soundReady = val end)
	group:AddChild(playSoundCB)

	local fadeSlider = addon.functions.createSliderAce("Fade In", cat.fadeInTime or 0.3, 0, 2, 0.1, function(_, _, val) cat.fadeInTime = val end)
	group:AddChild(fadeSlider)
	local holdSlider = addon.functions.createSliderAce("Hold Time", cat.holdTime or 0, 0, 2, 0.1, function(_, _, val) cat.holdTime = val end)
	group:AddChild(holdSlider)
	local fadeOutSlider = addon.functions.createSliderAce("Fade Out", cat.fadeOutTime or 0.7, 0, 2, 0.1, function(_, _, val) cat.fadeOutTime = val end)
	group:AddChild(fadeOutSlider)
	local scaleSlider = addon.functions.createSliderAce("Scale", cat.animScale or 1.5, 0.5, 3, 0.1, function(_, _, val) cat.animScale = val end)
	group:AddChild(scaleSlider)
	local sizeSlider = addon.functions.createSliderAce("Icon Size", cat.iconSize or 75, 20, 200, 1, function(_, _, val) cat.iconSize = val end)
	group:AddChild(sizeSlider)

	local spellEdit = addon.functions.createEditboxAce(L["AddSpellID"], nil, function(self, _, text)
		local id = tonumber(text)
		if id then
			cat.spells[id] = true
			refreshTree(catId)
			container:ReleaseChildren()
			buildCategoryOptions(container, catId)
		end
		self:SetText("")
	end)
	spellEdit:SetRelativeWidth(0.6)
	group:AddChild(spellEdit)

	local exportBtn = addon.functions.createButtonAce(L["ExportCategory"], 150, function()
		local data = exportCategory(catId)
		if not data then return end
		StaticPopupDialogs["EQOL_EXPORT_CATEGORY"] = StaticPopupDialogs["EQOL_EXPORT_CATEGORY"]
			or {
				text = L["ExportCategory"],
				button1 = CLOSE,
				hasEditBox = true,
				editBoxWidth = 320,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_EXPORT_CATEGORY"].OnShow = function(self)
			self:SetFrameStrata("FULLSCREEN_DIALOG")
			self.editBox:SetText(data)
			self.editBox:HighlightText()
			self.editBox:SetFocus()
		end
		StaticPopup_Show("EQOL_EXPORT_CATEGORY")
	end)
	group:AddChild(exportBtn)

	local shareBtn = addon.functions.createButtonAce(L["ShareCategory"] or "Share Category", 150, function() ShareCategory(catId) end)
	group:AddChild(shareBtn)

	local delBtn = addon.functions.createButtonAce(L["DeleteCategory"], 150, function()
		local catName = addon.db.cooldownNotifyCategories[catId].name or ""
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"] = StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"]
			or {
				text = L["DeleteCategoryConfirm"],
				button1 = YES,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"].OnShow = function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end
		StaticPopupDialogs["EQOL_DELETE_CDN_CATEGORY"].OnAccept = function()
			addon.db.cooldownNotifyCategories[catId] = nil
			addon.db.cooldownNotifyEnabled[catId] = nil
			addon.db.cooldownNotifyLocked[catId] = nil
			addon.db.cooldownNotifyOrder[catId] = nil
			addon.db.cooldownNotifySounds[catId] = nil
			addon.db.cooldownNotifySoundsEnabled[catId] = nil
			if anchors[catId] then
				anchors[catId]:Hide()
				anchors[catId] = nil
			end
			addon.db.cooldownNotifySelectedCategory = next(addon.db.cooldownNotifyCategories)
			applyLockState()
			refreshTree(addon.db.cooldownNotifySelectedCategory)
			container:ReleaseChildren()
		end
		StaticPopup_Show("EQOL_DELETE_CDN_CATEGORY", catName)
	end)
	group:AddChild(delBtn)
end

local function buildSpellOptions(container, catId, spellId)
	local cat = addon.db.cooldownNotifyCategories[catId]
	if not (cat and cat.spells and cat.spells[spellId]) then return end

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullWidth(true)
	container:AddChild(wrapper)

	local info = C_Spell.GetSpellInfo(spellId)
	local name = info and info.name or tostring(spellId)
	local label = addon.functions.createLabelAce(name .. " (" .. spellId .. ")")
	wrapper:AddChild(label)

	local btn = addon.functions.createButtonAce(L["Remove"], 150, function()
		cat.spells[spellId] = nil
		refreshTree(catId)
		container:ReleaseChildren()
	end)
	wrapper:AddChild(btn)
	container:DoLayout()
end

function CN.functions.addCooldownNotifyOptions(container)
	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	local tree = getCategoryTree()

	treeGroup = AceGUI:Create("TreeGroup")
	treeGroup:SetTree(tree)
	treeGroup:SetCallback("OnGroupSelected", function(widget, _, value)
		if value == "ADD_CATEGORY" then
			local newId = 1
			for id in pairs(addon.db.cooldownNotifyCategories) do
				if id >= newId then newId = id + 1 end
			end
			addon.db.cooldownNotifyCategories[newId] = {
				name = L["NewCategoryName"] or "New",
				anchor = { point = "CENTER", x = 0, y = 0 },
				iconSize = 75,
				fadeInTime = 0.3,
				fadeOutTime = 0.7,
				holdTime = 0,
				animScale = 1.5,
				showName = true,
				spells = {},
				items = {},
				pets = {},
			}
			addon.db.cooldownNotifyEnabled[newId] = true
			addon.db.cooldownNotifyLocked[newId] = false
			ensureAnchor(newId)
			applyLockState()
			refreshTree(newId)
			return
		elseif value == "IMPORT_CATEGORY" then
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"] = StaticPopupDialogs["EQOL_IMPORT_CATEGORY"]
				or {
					text = L["ImportCategory"],
					button1 = ACCEPT,
					button2 = CANCEL,
					hasEditBox = true,
					editBoxWidth = 320,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].OnShow = function(self)
				self.editBox:SetText("")
				self.editBox:SetFocus()
				self.text:SetText(L["ImportCategory"])
			end
			StaticPopupDialogs["EQOL_IMPORT_CATEGORY"].OnAccept = function(self)
				local text = self.editBox:GetText()
				local id = importCategory(text)
				if id then
					refreshTree(id)
				else
					print(L["ImportCategoryError"] or "Invalid string")
				end
			end
			StaticPopup_Show("EQOL_IMPORT_CATEGORY")
			return
		end
		local catId, _, spellId = strsplit("\001", value)
		catId = tonumber(catId)
		widget:ReleaseChildren()

		local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		widget:AddChild(scroll)

		if spellId then
			buildSpellOptions(scroll, catId, tonumber(spellId))
		else
			buildCategoryOptions(scroll, catId)
		end
	end)
	wrapper:AddChild(treeGroup)
	treeGroup:SetFullHeight(true)
	treeGroup:SetFullWidth(true)
	treeGroup:SetTreeWidth(200, true)
	local ok = treeGroup:SelectByValue(tostring(addon.db.cooldownNotifySelectedCategory or 1))
	if not ok and tree[1] and tree[1].value then treeGroup:SelectByValue(tree[1].value) end
end

local ShareCategory -- forward declaration

function exportCategory(catId, encodeMode)
	local cat = addon.db.cooldownNotifyCategories and addon.db.cooldownNotifyCategories[catId]
	if not cat then return end
	local data = {
		category = cat,
		order = addon.db.cooldownNotifyOrder and addon.db.cooldownNotifyOrder[catId] or {},
		sounds = addon.db.cooldownNotifySounds and addon.db.cooldownNotifySounds[catId] or {},
		soundsEnabled = addon.db.cooldownNotifySoundsEnabled and addon.db.cooldownNotifySoundsEnabled[catId] or {},
		version = 1,
	}
	local serializer = LibStub("AceSerializer-3.0")
	local deflate = LibStub("LibDeflate")
	local serialized = serializer:Serialize(data)
	local compressed = deflate:CompressDeflate(serialized)
	if encodeMode == "chat" then
		return deflate:EncodeForWoWChatChannel(compressed)
	elseif encodeMode == "addon" then
		return deflate:EncodeForWoWAddonChannel(compressed)
	end
	return deflate:EncodeForPrint(compressed)
end

function importCategory(encoded)
	if type(encoded) ~= "string" or encoded == "" then return end
	local deflate = LibStub("LibDeflate")
	local serializer = LibStub("AceSerializer-3.0")
	local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
	if not decoded then return end
	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local ok, data = serializer:Deserialize(decompressed)
	if not ok or type(data) ~= "table" then return end
	local cat = data.category or data.cat or data
	if type(cat) ~= "table" then return end
	cat.anchor = cat.anchor or { point = "CENTER", x = 0, y = 0 }
	cat.iconSize = cat.iconSize or 75
	cat.fadeInTime = cat.fadeInTime or 0.3
	cat.fadeOutTime = cat.fadeOutTime or 0.7
	cat.animScale = cat.animScale or 1.5
	cat.holdTime = cat.holdTime or 0
	cat.showName = cat.showName ~= false
	cat.spells = cat.spells or {}
	cat.items = cat.items or {}
	cat.pets = cat.pets or {}
	local newId = 1
	for id in pairs(addon.db.cooldownNotifyCategories) do
		if id >= newId then newId = id + 1 end
	end
	addon.db.cooldownNotifyCategories[newId] = cat
	addon.db.cooldownNotifyEnabled[newId] = true
	addon.db.cooldownNotifyLocked[newId] = false
	addon.db.cooldownNotifyOrder[newId] = data.order or {}
	addon.db.cooldownNotifySounds[newId] = data.sounds or {}
	addon.db.cooldownNotifySoundsEnabled[newId] = data.soundsEnabled or {}
	ensureAnchor(newId)
	applyLockState()
	return newId
end

local COMM_PREFIX = "EQOLCDNSHARE"
local AceComm = LibStub("AceComm-3.0")
local incoming = {}
local pending = {}
local pendingSender = {}

function ShareCategory(catId, targetPlayer)
	local addonEncoded = exportCategory(catId, "addon")
	if not addonEncoded then return end
	local label = ("%s - %s"):format(UnitName("player"), (addon.db.cooldownNotifyCategories[catId] and addon.db.cooldownNotifyCategories[catId].name) or catId)
	local placeholder = ("[EQOLCDN: %s]"):format(label)
	ChatFrame_OpenChat(placeholder)
	local pktID = tostring(time() * 1000):gsub("%D", "")
	pending[label] = pktID
	local dist, target = "WHISPER", targetPlayer
	if not targetPlayer then
		if IsInRaid(LE_PARTY_CATEGORY_HOME) then
			dist = "RAID"
		elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			dist = "INSTANCE_CHAT"
		elseif IsInGroup() then
			dist = "PARTY"
		elseif IsInGuild() then
			dist = "GUILD"
		else
			target = UnitName("player")
		end
	end
	AceComm:SendCommMessage(COMM_PREFIX, ("<%s>%s"):format(pktID, addonEncoded), dist, target, "BULK")
end

local PATTERN = "%[EQOLCDN: ([^%]]+)%]"

local function EQOL_CDN_Filter(_, _, msg, sender, ...)
	local newMsg, hits = msg:gsub(PATTERN, function(label)
		local pktID = pendingSender[sender]
		if pktID then
			pending[label] = pktID
			pendingSender[sender] = nil
		end
		return ("|Hgarrmission:eqolcdn:%s|h|cff00ff88[%s]|h|r"):format(label, label)
	end)
	if hits > 0 then return false, newMsg, sender, ... end
end

for _, ev in ipairs({
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
}) do
	ChatFrame_AddMessageEventFilter(ev, EQOL_CDN_Filter)
end

local function HandleEQOLLink(link, text, button, frame)
	local label = link:match("^garrmission:eqolcdn:(.+)")
	if not label then return end
	local pktID = pending[label]
	if not (pktID and incoming[pktID]) then return end
	StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"] = StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"]
		or {
			text = L["ImportCategory"],
			button1 = ACCEPT,
			button2 = CANCEL,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function(_, data)
				local encoded = incoming[data]
				incoming[data] = nil
				pending[label] = nil
				local newId = importCategory(encoded)
				if newId and CN.functions.addCooldownNotifyOptions then CN.functions.addCooldownNotifyOptions(frame or UIParent) end
			end,
		}
	StaticPopupDialogs["EQOL_IMPORT_FROM_SHARE"].OnShow = function(self, data)
		local encoded = incoming[data]
		local name = ""
		if encoded then
			local deflate = LibStub("LibDeflate")
			local serializer = LibStub("AceSerializer-3.0")
			local decoded = deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWChatChannel(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
			if decoded then
				local decompressed = deflate:DecompressDeflate(decoded)
				if decompressed then
					local ok, data = serializer:Deserialize(decompressed)
					if ok and type(data) == "table" then
						local cat = data.category or data.cat or data
						name = cat and cat.name or name
					end
				end
			end
		end
		self.text:SetFormattedText("%s\n%s", L["ImportCategory"], name ~= "" and name or "")
	end
	StaticPopup_Show("EQOL_IMPORT_FROM_SHARE", nil, nil, pktID)
end

hooksecurefunc("SetItemRef", HandleEQOLLink)

local function OnComm(prefix, message, dist, sender)
	if prefix ~= COMM_PREFIX then return end
	local pktID, payload = message:match("^<(%d+)>(.+)")
	if not pktID then return end
	incoming[pktID] = payload
	pendingSender[sender] = pktID
end

AceComm:RegisterComm(COMM_PREFIX, OnComm)

-- register events
DCP:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
DCP:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
DCP:RegisterEvent("SPELL_UPDATE_COOLDOWN")

for id in pairs(addon.db.cooldownNotifyCategories or {}) do
	ensureAnchor(id)
end
applyLockState()
