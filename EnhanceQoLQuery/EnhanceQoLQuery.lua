local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

-- Event frame (no visible UI)
local eventFrame = CreateFrame("Frame")
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

addon.Query = addon.Query or {}
addon.Query.ui = addon.Query.ui or {}

local currentMode = "drink" -- one of: "drink", "potion", "auto"
-- No AH scan: keep only manual input
local lastProcessedBrowseCount = 0
local browseStallCount = 0
local executeSearch = false
local loadedResults = {}

-- No AH sharding/browse in this tool

local function setMode(mode)
	currentMode = mode
	local titleSuffix = (mode == "drink" and "Drinks") or (mode == "potion" and "Mana Potions") or "Auto"
	if addon.Query.ui and addon.Query.ui.window then addon.Query.ui.window:SetTitle("EnhanceQoLQuery - " .. titleSuffix) end
	if addon.Query.ui and addon.Query.ui.scanBtn then addon.Query.ui.scanBtn:SetText(mode == "potion" and "Scan Potions" or "Scan Drinks") end
end

local addedItems = {} -- known items already present in code lists
local inputAdded = {} -- items the user has added in the current input session
local addedResults = {}

local function seedKnownItems()
	wipe(addedItems)
	if addon and addon.Drinks and addon.Drinks.drinkList then
		for _, drink in ipairs(addon.Drinks.drinkList) do
			if drink and drink.id then addedItems[tostring(drink.id)] = true end
		end
	end
	if addon and addon.Drinks and addon.Drinks.manaPotions then
		for _, pot in ipairs(addon.Drinks.manaPotions) do
			if pot and pot.id then addedItems[tostring(pot.id)] = true end
		end
	end
end

local tooltip = CreateFrame("GameTooltip", "EnhanceQoLQueryTooltip", UIParent, "GameTooltipTemplate")

local function extractManaFromTooltip(itemLink)
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetHyperlink(itemLink)
	local mana = 0

	for i = 1, tooltip:NumLines() do
		local text = _G["EnhanceQoLQueryTooltipTextLeft" .. i]:GetText()
		if text and text:lower():find("mana") then
			-- Prefer explicit "million mana" match to avoid picking up unrelated "million" (e.g., health)
			local millionStr = text:lower():match("([%d%.,]+)%s*million%s*mana")
			if millionStr then
				local clean = (millionStr:gsub(",", "")) -- keep decimal dot for fractional millions
				local v = tonumber(clean) or 0
				mana = math.floor(v * 1000000 + 0.5)
				break
			end
			-- Fallback: plain numeric before "mana" (supports thousands separators)
			local plainStr = text:match("([%d%.,]+)%s*mana")
			if plainStr then
				local clean = plainStr:gsub("[,%.]", "")
				mana = tonumber(clean) or 0
				break
			end
		end
	end

	tooltip:Hide()
	return mana
end

local function extractWellFedFromTooltip(itemLink)
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetHyperlink(itemLink)
	local buffFood = "false"

	for i = 1, tooltip:NumLines() do
		local text = _G["EnhanceQoLQueryTooltipTextLeft" .. i]:GetText()
		if text and (text:match("well fed") or text:match("Well Fed")) then
			buffFood = "true"
			break
		end
	end

	tooltip:Hide()
	return buffFood
end

local function classifyItemByIDs(itemID)
	if not itemID then return nil end
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if classID == Enum.ItemClass.Consumable then
		if subClassID == Enum.ItemConsumableSubclass.Fooddrink then return "drink" end
		if subClassID == Enum.ItemConsumableSubclass.Potion then return "potion" end
	end
	if classID == Enum.ItemClass.Gem then return "gem" end
	return nil
end

local function sanitizeKey(name)
	local formatted = tostring(name or "")
	-- Remove quotes and collapse spaces to avoid invalid Lua string keys
	formatted = formatted:gsub('"', "")
	formatted = formatted:gsub("'", "")
	formatted = formatted:gsub("%s+", "")
	-- Fallback if empty after sanitization
	if formatted == "" then formatted = "item" end
	return formatted
end

local function trim(str)
	if not str then return "" end
	return (str:match("^%s*(.-)%s*$")) or ""
end

local function getCollectionType(enumKey, legacyKey)
	if Enum and Enum.TransmogCollectionType and Enum.TransmogCollectionType[enumKey] then
		return Enum.TransmogCollectionType[enumKey]
	end
	if legacyKey then
		local const = _G["LE_TRANSMOG_COLLECTION_TYPE_" .. legacyKey]
		if const then return const end
	end
	return nil
end

local transmogWeaponCategories = {
	{ id = getCollectionType("OneHAxe", "AXE_1H"), label = "Axt (1H)" },
	{ id = getCollectionType("TwoHAxe", "AXE_2H"), label = "Axt (2H)" },
	{ id = getCollectionType("OneHMace", "MACE_1H"), label = "Streitkolben (1H)" },
	{ id = getCollectionType("TwoHMace", "MACE_2H"), label = "Streitkolben (2H)" },
	{ id = getCollectionType("OneHSword", "SWORD_1H"), label = "Schwert (1H)" },
	{ id = getCollectionType("TwoHSword", "SWORD_2H"), label = "Schwert (2H)" },
	{ id = getCollectionType("Dagger", "DAGGER"), label = "Dolch" },
	{ id = getCollectionType("Fist", "FIST_WEAPON"), label = "Faustwaffe" },
	{ id = getCollectionType("Polearm", "POLEARM"), label = "Stangenwaffe" },
	{ id = getCollectionType("Staff", "STAFF"), label = "Stab" },
	{ id = getCollectionType("Bow", "BOW"), label = "Bogen" },
	{ id = getCollectionType("Crossbow", "CROSSBOW"), label = "Armbrust" },
	{ id = getCollectionType("Gun", "GUN"), label = "Schusswaffe" },
	{ id = getCollectionType("Wand", "WAND"), label = "Zauberstab" },
	{ id = getCollectionType("Warglaive", "WARGLAIVE"), label = "Kriegsgleve" },
	{ id = getCollectionType("FishingRod", "FISHING_ROD"), label = "Angel" },
}

-- Pretty text for item quality
local function qualityText(q)
	local n = tonumber(q) or 0
	local names = {
		[0] = "Poor",
		[1] = "Common",
		[2] = "Uncommon",
		[3] = "Rare",
		[4] = "Epic",
		[5] = "Legendary",
		[6] = "Artifact",
		[7] = "Heirloom",
		[8] = "WoWToken",
	}
	return string.format("%s (%d)", names[n] or tostring(n), n)
end

-- Public inspector function used by AceUI and Shift+Click when in inspector
function addon.Query.showItem(itemLink)
	local itemName, itemLink2, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expansionID, setID, isCraftingReagent =
		C_Item.GetItemInfo(itemLink)

	local function coinText(c)
		c = tonumber(c or 0) or 0
		if c <= 0 then return "0c (0)" end
		local g = math.floor(c / 10000)
		local s = math.floor((c % 10000) / 100)
		local k = c % 100
		local parts = {}
		if g > 0 then table.insert(parts, g .. "g") end
		if s > 0 then table.insert(parts, s .. "s") end
		if k > 0 then table.insert(parts, k .. "c") end
		return string.format("%s (%d)", table.concat(parts, " "), c)
	end

	local BIND_NAMES = { [0] = "None", [1] = "Bind on Pickup", [2] = "Bind on Equip", [3] = "Bind on Use", [4] = "Quest" }
	local function expansionFriendly(id)
		if id == nil then return nil end
		local key = "EXPANSION_NAME" .. tostring(id)
		local n = _G[key]
		return n and string.format("%s (%d)", n, id) or tostring(id)
	end

	local lines = {}
	local function add(key, val)
		if val ~= nil then table.insert(lines, string.format("%s: %s", key, tostring(val))) end
	end

	-- Basics
	add("itemName", itemName)
	add("itemLink", itemLink2)
	if itemQuality ~= nil then add("itemQuality", qualityText(itemQuality)) end
	add("itemLevel", itemLevel)
	add("itemMinLevel", itemMinLevel)
	add("itemType", itemType)
	add("itemSubType", itemSubType)
	add("itemStackCount", itemStackCount)

	-- Equip location in one line: token (localized)
	if itemEquipLoc ~= nil then
		local locName = _G[itemEquipLoc]
		if locName and locName ~= "" then
			add("itemEquipLoc", string.format("%s (%s)", itemEquipLoc, locName))
		else
			add("itemEquipLoc", itemEquipLoc)
		end
	end

	add("itemTexture", itemTexture)
	if sellPrice ~= nil then add("sellPrice", coinText(sellPrice)) end

	add("classID", classID)
	add("subclassID", subclassID)
	if bindType ~= nil then add("bindType", string.format("%s (%d)", BIND_NAMES[bindType] or tostring(bindType), bindType)) end
	if expansionID ~= nil then add("expansionID", expansionFriendly(expansionID)) end
	add("setID", setID)
	if isCraftingReagent ~= nil then add("isCraftingReagent", isCraftingReagent) end

	if addon.Query.ui and addon.Query.ui.inspectorOutput then addon.Query.ui.inspectorOutput:SetText(table.concat(lines, "\n")) end
end

local function formatDrinkString(name, itemID, minLevel, mana, isBuffFood)
	local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
	return string.format('{ key = "%s", id = %d, requiredLevel = %d, mana = %d, isBuffFood = %s }', formattedKey, itemID, minLevel or 1, mana or 0, tostring(isBuffFood))
end

local function formatGemDrinkString(name, itemID, minLevel, mana, isBuffFood)
	local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
	return string.format(
		'{ key = "%s", id = %d, requiredLevel = %d, mana = %d, isBuffFood = %s, isEarthenFood = true, earthenOnly = true }',
		formattedKey,
		itemID,
		minLevel or 1,
		mana or 0,
		tostring(isBuffFood)
	)
end

local function formatPotionString(name, itemID, minLevel, mana)
	local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
	return string.format('{ key = "%s", id = %d, requiredLevel = %d, mana = %d }', formattedKey, itemID, minLevel or 1, mana or 0)
end

local function updateItemInfo(itemLink)
	if not itemLink then return end
	local name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture = C_Item.GetItemInfo(itemLink)
	local mana = extractManaFromTooltip(itemLink)
	if name and type and subType and minLevel and mana > 0 then
		local itemID = tonumber(itemLink:match("item:(%d+)"))
		local kind = currentMode
		if kind == "auto" then kind = classifyItemByIDs(itemID) or "drink" end
		if kind == "potion" then
			return formatPotionString(name, itemID, minLevel, mana)
		else
			local buffFood = extractWellFedFromTooltip(itemLink)
			if type == "Gem" then
				return formatGemDrinkString(name, itemID, minLevel, mana, buffFood)
			else
				return formatDrinkString(name, itemID, minLevel, mana, buffFood)
			end
		end
	end
	return nil
end

-- Output helper + input processing (AceGUI path)
local function UI_SetOutput(text)
	if addon.Query.ui and addon.Query.ui.output then addon.Query.ui.output:SetText(text or "") end
end

local function processInputText(text)
	local itemLinks = { strsplit(" ", text or "") }
	local results = {}
	for _, itemLink in ipairs(itemLinks) do
		local itemID = itemLink:match("item:(%d+)")
		if itemID then
			local result = loadedResults[itemID]
			if result == nil then
				result = updateItemInfo(itemLink)
				loadedResults[itemID] = result
			end
			if result then table.insert(results, result) end
		end
	end
	UI_SetOutput(table.concat(results, ",\n        "))
end

-- (legacy editbox removed; AceGUI input handles text changes)

-- No AH result aggregator (manual input only)

local function runTransmogSetSearch(rawQuery)
	local query = trim(rawQuery)
	local outputLines = {}
	if not C_TransmogSets or not C_TransmogSets.GetAllSets then
		outputLines = { "Transmog set API is not available in this client build." }
	elseif query == "" then
		outputLines = { "Bitte einen Suchbegriff eingeben." }
	else
		local lowerQuery = query:lower()
		local allSets = C_TransmogSets.GetAllSets()
		if type(allSets) ~= "table" then
			outputLines = { "Keine Sets verfügbar." }
		else
			for _, setInfo in ipairs(allSets) do
				local name = setInfo.name
				if not name then
					local extra = C_TransmogSets.GetSetInfo(setInfo.setID)
					name = extra and extra.name
				end
				if name and name:lower():find(lowerQuery, 1, true) then
					table.insert(outputLines, string.format("[%d] %s", setInfo.setID, name))
				end
			end
			if #outputLines == 0 then outputLines = { string.format('Keine Ergebnisse für "%s".', query) } end
		end
	end

	local finalText = table.concat(outputLines, "\n")
	if addon.Query.ui and addon.Query.ui.setSearchOutput then addon.Query.ui.setSearchOutput:SetText(finalText) end
end

local function runTransmogSetLookup(rawIds)
	local text = trim(rawIds)
	local outputLines = {}
	if not C_TransmogSets or not C_TransmogSets.GetSetInfo then
		outputLines = { "Transmog set API is not available in this client build." }
	elseif text == "" then
		outputLines = { "Bitte eine oder mehrere IDs angeben." }
	else
		local seen = {}
		for entry in text:gmatch("[^,%s]+") do
			local id = tonumber(entry)
			if id and not seen[id] then
				seen[id] = true
				local info = C_TransmogSets.GetSetInfo(id)
				if info and info.name then
					table.insert(outputLines, string.format("[%d] %s", id, info.name))
				else
					table.insert(outputLines, string.format("[%d] Keine Daten gefunden.", id))
				end
			elseif not id then
				table.insert(outputLines, string.format('"%s" ist keine gültige Zahl.', entry))
			end
		end
		if #outputLines == 0 then outputLines = { "Keine gültigen IDs gefunden." } end
	end
	local finalText = table.concat(outputLines, "\n")
	if addon.Query.ui and addon.Query.ui.setIdOutput then addon.Query.ui.setIdOutput:SetText(finalText) end
end

local function runTransmogWeaponSearch(rawQuery, rawCategoryID)
	local query = trim(rawQuery)
	local outputLines = {}
	if not C_TransmogCollection or not C_TransmogCollection.GetCategoryAppearances then
		outputLines = { "Transmog Collections API nicht verfügbar." }
	elseif query == "" then
		outputLines = { "Bitte einen Suchbegriff eingeben." }
	else
		local categoryID = tonumber(rawCategoryID)
		if not categoryID then
			outputLines = { "Bitte eine gültige Kategorie auswählen." }
		else
			local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID) or {}
			local lowerQuery = query:lower()
			for _, appearance in ipairs(appearances) do
				local appearanceID = appearance and (appearance.appearanceID or appearance.visualID)
				if appearanceID then
					local sources = C_TransmogCollection.GetAppearanceSources(appearanceID, categoryID) or {}
					for _, source in ipairs(sources) do
						local name = source.name or ""
						if name ~= "" and name:lower():find(lowerQuery, 1, true) then
							local appID = appearanceID or 0
							local srcID = source.sourceID or 0
							table.insert(outputLines, string.format("app:%d src:%d %s", appID, srcID, name))
						end
					end
				end
			end
			if #outputLines == 0 then outputLines = { string.format('Keine Treffer für "%s".', query) } end
		end
	end
	local finalText = table.concat(outputLines, "\n")
	if addon.Query.ui and addon.Query.ui.weaponSearchOutput then addon.Query.ui.weaponSearchOutput:SetText(finalText) end
end

local function handleItemLink(text)
	local _, link = C_Item.GetItemInfo(text)
	local itemID = text and text:match("item:(%d+)") and tonumber(text:match("item:(%d+)")) or nil
	local classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	local kind = currentMode
	if kind == "auto" then kind = classifyItemByIDs(itemID) or "drink" end
	local isDrink = (classID == Enum.ItemClass.Consumable and subClassID == Enum.ItemConsumableSubclass.Fooddrink)
	local isPotion = (classID == Enum.ItemClass.Consumable and subClassID == Enum.ItemConsumableSubclass.Potion)
	local isGem = (classID == Enum.ItemClass.Gem)
	if (kind == "drink" and isDrink) or (kind == "potion" and isPotion) or (kind == "drink" and isGem) then
		local itemId = text:match("item:(%d+)")
		-- skip if already in master lists
		if addedItems[tostring(itemId)] then return end
		if not inputAdded[itemId] then
			inputAdded[itemId] = true
			if addon.Query.ui and addon.Query.ui.input then
				local currentText = addon.Query.ui.input:GetText() or ""
				addon.Query.ui.input:SetText((currentText ~= "" and (currentText .. " ") or "") .. text)
			end
		else
			print("Item is already in the list.")
		end
	else
		print("Item not matching mode or not supported.")
	end
end

local function BuildAceWindow()
	if not AceGUI then return end
	if addon.Query.ui and addon.Query.ui.window then return end
	local win = AceGUI:Create("Window")
	addon.Query.ui = addon.Query.ui or {}
	addon.Query.ui.window = win
	win:SetTitle("EnhanceQoLQuery - Drinks")
	win:SetWidth(700)
	win:SetHeight(520)
	win:SetLayout("Fill")

	local tree = AceGUI:Create("TreeGroup")
	addon.Query.ui.tree = tree
	tree:SetTree({
		{ value = "generator", text = "Generator" },
		{ value = "inspector", text = "GetItemInfo" },
		{ value = "transmog", text = "Transmog Sets" },
		{ value = "transmogId", text = "Transmog IDs" },
		{ value = "transmogWeapon", text = "Transmog Waffen" },
	})
	tree:SetLayout("Fill")
	win:AddChild(tree)

	local function buildGenerator(container)
		addon.Query.ui.activeGroup = "generator"
		container:ReleaseChildren()
		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("List")
		container:AddChild(outer)

		local row = AceGUI:Create("SimpleGroup")
		row:SetFullWidth(true)
		row:SetLayout("Flow")
		outer:AddChild(row)
		local lbl = AceGUI:Create("Label")
		lbl:SetText("Mode:")
		lbl:SetWidth(60)
		row:AddChild(lbl)
		local b1 = AceGUI:Create("Button")
		b1:SetText("Drinks")
		b1:SetWidth(100)
		b1:SetCallback("OnClick", function() setMode("drink") end)
		row:AddChild(b1)
		local b2 = AceGUI:Create("Button")
		b2:SetText("Mana Potions")
		b2:SetWidth(120)
		b2:SetCallback("OnClick", function() setMode("potion") end)
		row:AddChild(b2)
		local b3 = AceGUI:Create("Button")
		b3:SetText("Auto")
		b3:SetWidth(80)
		b3:SetCallback("OnClick", function() setMode("auto") end)
		row:AddChild(b3)

		local input = AceGUI:Create("MultiLineEditBox")
		input:SetLabel("Input (paste item links/IDs; Shift+Click adds here)")
		input:SetFullWidth(true)
		input:SetNumLines(3)
		input:DisableButton(true)
		input:SetCallback("OnTextChanged", function(_, _, t) processInputText(t) end)
		outer:AddChild(input)
		addon.Query.ui.input = input
		local output = AceGUI:Create("MultiLineEditBox")
		output:SetLabel("Generated table rows")
		output:SetFullWidth(true)
		output:SetNumLines(16)
		output:DisableButton(true)
		outer:AddChild(output)
		addon.Query.ui.output = output

		local bottom = AceGUI:Create("SimpleGroup")
		bottom:SetFullWidth(true)
		bottom:SetLayout("Flow")
		outer:AddChild(bottom)

		local clearBtn = AceGUI:Create("Button")
		clearBtn:SetText("Clear")
		clearBtn:SetWidth(120)
		clearBtn:SetCallback("OnClick", function()
			input:SetText("")
			output:SetText("")
			addedResults = {}
			resultsAHSearch = {}
			inputAdded = {}
			wipe(loadedResults)
		end)
		bottom:AddChild(clearBtn)
		local copyBtn = AceGUI:Create("Button")
		copyBtn:SetText("Copy")
		copyBtn:SetWidth(120)
		copyBtn:SetCallback("OnClick", function()
			output:SetFocus()
			output:HighlightText()
			C_Timer.After(0.8, function() output:ClearFocus() end)
		end)
		bottom:AddChild(copyBtn)
	end

	local function buildInspector(container)
		addon.Query.ui.activeGroup = "inspector"
		container:ReleaseChildren()
		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("List")
		container:AddChild(outer)
		local tip = AceGUI:Create("Label")
		tip:SetText("Shift+Click an item link or use the cursor button to inspect via GetItemInfo().")
		tip:SetFullWidth(true)
		outer:AddChild(tip)
		local pick = AceGUI:Create("Button")
		pick:SetText("Load item from cursor")
		pick:SetWidth(200)
		pick:SetCallback("OnClick", function()
			local t, _, link = GetCursorInfo()
			if t == "item" and link then
				addon.Query.showItem(link)
				ClearCursor()
			end
		end)
		outer:AddChild(pick)
		local output = AceGUI:Create("MultiLineEditBox")
		output:SetLabel("GetItemInfo")
		output:SetFullWidth(true)
		output:SetNumLines(18)
		output:DisableButton(true)
		outer:AddChild(output)
		addon.Query.ui.inspectorOutput = output
		local follow = AceGUI:Create("CheckBox")
		follow:SetLabel("Enable follow-up calls (experimental)")
		addon.functions.InitDBValue("queryFollowupEnabled", false)
		follow:SetValue(addon.db.queryFollowupEnabled)
		follow:SetCallback("OnValueChanged", function(_, _, v) addon.db.queryFollowupEnabled = v and true or false end)
		outer:AddChild(follow)
	end

	local function buildTransmog(container)
		addon.Query.ui.activeGroup = "transmog"
		container:ReleaseChildren()

		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("List")
		container:AddChild(outer)

		local tip = AceGUI:Create("Label")
		tip:SetText("Suche nach Transmog-Sets. Enter oder der Button starten die Suche.")
		tip:SetFullWidth(true)
		outer:AddChild(tip)

		local input = AceGUI:Create("EditBox")
		input:SetLabel("Suchbegriff")
		input:SetFullWidth(true)
		input:DisableButton(true)
		input:SetCallback("OnEnterPressed", function(widget, _, text)
			runTransmogSetSearch(text)
			widget:ClearFocus()
		end)
		outer:AddChild(input)
		addon.Query.ui.setSearchInput = input

		local searchBtn = AceGUI:Create("Button")
		searchBtn:SetText("Suchen")
		searchBtn:SetWidth(120)
		searchBtn:SetCallback("OnClick", function()
			runTransmogSetSearch(input:GetText())
		end)
		outer:AddChild(searchBtn)

		local output = AceGUI:Create("MultiLineEditBox")
		output:SetLabel("Ergebnisse")
		output:SetFullWidth(true)
		output:SetNumLines(14)
		output:DisableButton(true)
		outer:AddChild(output)
		addon.Query.ui.setSearchOutput = output
	end

	local function buildTransmogId(container)
		addon.Query.ui.activeGroup = "transmogId"
		container:ReleaseChildren()

		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("List")
		container:AddChild(outer)

		local tip = AceGUI:Create("Label")
		tip:SetText("Gib eine oder mehrere Set-IDs ein (getrennt durch Leerzeichen oder Komma).")
		tip:SetFullWidth(true)
		outer:AddChild(tip)

		local input = AceGUI:Create("EditBox")
		input:SetLabel("Set-ID(s)")
		input:SetFullWidth(true)
		input:DisableButton(true)
		input:SetCallback("OnEnterPressed", function(widget, _, text)
			runTransmogSetLookup(text)
			widget:ClearFocus()
		end)
		outer:AddChild(input)
		addon.Query.ui.setIdInput = input

		local searchBtn = AceGUI:Create("Button")
		searchBtn:SetText("Infos abrufen")
		searchBtn:SetWidth(140)
		searchBtn:SetCallback("OnClick", function()
			runTransmogSetLookup(input:GetText())
		end)
		outer:AddChild(searchBtn)

		local output = AceGUI:Create("MultiLineEditBox")
		output:SetLabel("Ergebnisse")
		output:SetFullWidth(true)
		output:SetNumLines(14)
		output:DisableButton(true)
		outer:AddChild(output)
		addon.Query.ui.setIdOutput = output
	end

	local function buildTransmogWeapon(container)
		addon.Query.ui.activeGroup = "transmogWeapon"
		container:ReleaseChildren()

		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("List")
		container:AddChild(outer)

		local tip = AceGUI:Create("Label")
		tip:SetText("Suche nach Waffen-Vorlagen. Kategorie wählen, Suchtext eingeben, Enter oder Button startet die Suche.")
		tip:SetFullWidth(true)
		outer:AddChild(tip)

		local availableOptions = {}
		local optionOrder = {}
		for _, info in ipairs(transmogWeaponCategories) do
			if info.id then
				local valueKey = tostring(info.id)
				availableOptions[valueKey] = info.label
				table.insert(optionOrder, valueKey)
			end
		end

		local dropdown = AceGUI:Create("Dropdown")
		dropdown:SetLabel("Kategorie")
		dropdown:SetFullWidth(true)
		if next(availableOptions) then
			dropdown:SetList(availableOptions, optionOrder)
			dropdown:SetValue(optionOrder[1])
			addon.Query.ui.weaponCategoryValue = optionOrder[1]
		else
			dropdown:SetDisabled(true)
		end
		outer:AddChild(dropdown)
		addon.Query.ui.weaponCategoryDropdown = dropdown

		local input = AceGUI:Create("EditBox")
		input:SetLabel("Suchbegriff")
		input:SetFullWidth(true)
		input:DisableButton(true)
		input:SetDisabled(not next(availableOptions))
		input:SetCallback("OnEnterPressed", function(widget, _, text)
			runTransmogWeaponSearch(text, dropdown:GetValue())
			widget:ClearFocus()
		end)
		outer:AddChild(input)
		addon.Query.ui.weaponSearchInput = input

		dropdown:SetCallback("OnValueChanged", function(_, _, key)
			addon.Query.ui.weaponCategoryValue = key
			if input and trim(input:GetText()) ~= "" then runTransmogWeaponSearch(input:GetText(), key) end
		end)

		local searchBtn = AceGUI:Create("Button")
		searchBtn:SetText("Suchen")
		searchBtn:SetWidth(120)
		searchBtn:SetDisabled(not next(availableOptions))
		searchBtn:SetCallback("OnClick", function()
			runTransmogWeaponSearch(input:GetText(), dropdown:GetValue())
		end)
		outer:AddChild(searchBtn)

		local output = AceGUI:Create("MultiLineEditBox")
		output:SetLabel("Ergebnisse")
		output:SetFullWidth(true)
		output:SetNumLines(14)
		output:DisableButton(true)
		outer:AddChild(output)
		addon.Query.ui.weaponSearchOutput = output

		if not next(availableOptions) then output:SetText("Keine Waffen-Kategorien verfügbar.") end
	end

	tree:SetCallback("OnGroupSelected", function(_, _, group)
		if group == "generator" then
			buildGenerator(tree)
		elseif group == "inspector" then
			buildInspector(tree)
		elseif group == "transmog" then
			buildTransmog(tree)
		elseif group == "transmogId" then
			buildTransmogId(tree)
		else
			buildTransmogWeapon(tree)
		end
	end)
	tree:SelectByValue("generator")
	setMode(currentMode)
end

local function onAddonLoaded(event, addonName)
	if addonName == "EnhanceQoLQuery" then
		-- Registriere den Slash-Command für /rq
		SLASH_EnhanceQoLQUERY1 = "/rq"
		SlashCmdList["EnhanceQoLQUERY"] = function(msg)
			if not (addon.Query.ui and addon.Query.ui.window) then BuildAceWindow() end
			if addon.Query.ui and addon.Query.ui.window then addon.Query.ui.window:Show() end
		end

		print("EnhanceQoLQuery command registered: /rq")
	end
end

local function onItemPush(bag, slot)
	if nil == bag or nil == slot then return end
	if bag < 0 or bag > 5 or slot < 1 or slot > C_Container.GetContainerNumSlots(bag) then return end
	local itemLink = C_Container.GetContainerItemLink(bag, slot)
	if itemLink then handleItemLink(itemLink) end
end

-- No AH event handling needed

-- No GET_ITEM_INFO_RECEIVED handler needed

local function onEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		-- Ensure slash command is registered as soon as the addon loads
		onAddonLoaded(event, ...)
		seedKnownItems()
	elseif event == "PLAYER_LOGIN" then
		-- Fallback: also register slash on login and seed known items
		onAddonLoaded(event, "EnhanceQoLQuery")
		seedKnownItems()
	elseif event == "ITEM_PUSH" and (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown()) then
		onItemPush(...)
		-- No AH scan handlers
	end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ITEM_PUSH")
-- No AH scan events registered
eventFrame:SetScript("OnEvent", onEvent)

-- Handling Shift+Click to add item link to the EditBox and clear previous item
hooksecurefunc("ChatEdit_InsertLink", function(itemLink)
	local shown = (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown())
	if itemLink and shown then
		if addon.Query.ui and addon.Query.ui.activeGroup == "inspector" and addon.Query.showItem then
			addon.Query.showItem(itemLink)
		else
			handleItemLink(itemLink)
		end
		return true
	end
end)

-- Legacy UI removed; AceGUI builds UI on demand via /rq
addon.Query.frame = eventFrame
