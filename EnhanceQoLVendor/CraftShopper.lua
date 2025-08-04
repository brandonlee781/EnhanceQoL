-- Example file

local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Vendor = addon.Vendor or {}
addon.Vendor.CraftShopper = addon.Vendor.CraftShopper or {}
addon.Vendor.CraftShopper.items = addon.Vendor.CraftShopper.items or {}

local RANK_TO_USE = 3 -- 1-3: gewünschter Qualitätsrang
local isRecraftTbl = { false, true } -- erst normale, dann Recrafts

local SCAN_DELAY = 0.3
local pendingScan
local scanRunning

local function isAHBuyable(itemID)
	if not itemID then return false end
	local data = C_TooltipInfo.GetItemByID(itemID)
	local canAHBuy = true
	if data and data.lines then
		for i, v in pairs(data.lines) do
			if v.type == 20 then
				canAHBuy = false
				if v.leftText == ITEM_BIND_ON_EQUIP then canAHBuy = false end
			elseif v.type == 0 and v.leftText == ITEM_CONJURED then
				canAHBuy = false
			end
		end
	end
	return canAHBuy
end

local function BuildShoppingList()
	local need = {} -- [itemID] = fehlende Menge

	for _, isRecraft in ipairs(isRecraftTbl) do
		for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft)) do
			local schem = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
			if schem and schem.reagentSlotSchematics then
				for _, slot in ipairs(schem.reagentSlotSchematics) do
					-- Nur Pflicht-Reagenzien, optional/finishing überspringen:
					if slot.reagentType == Enum.CraftingReagentType.Basic then
						local reqQty = slot.quantityRequired
						-- gewünschte Qualitäts-ID holen:
						local reagent = slot.reagents[RANK_TO_USE]
						local id
						if reagent and reagent.itemID ~= 0 then
							id = reagent.itemID
							need[id] = need[id] or {}
							need[id].qty = (need[id].qty or 0) + reqQty
						else
							-- Fallback: Basis-ItemID (Qualität egal)
							id = slot.reagents[1].itemID
							need[id] = need[id] or {}
							need[id].qty = (need[id].qty or 0) + reqQty
						end
						need[id].canAHBuy = isAHBuyable(id)
					end
				end
			end
		end
	end

	local items = {}
	for itemID, want in pairs(need) do
		local owned = C_Item.GetItemCount(itemID, true) -- inkl. Bank
		local missing = math.max(want.qty - owned, 0)
		if missing > 0 then table.insert(items, {
			itemID = itemID,
			qtyNeeded = want.qty,
			owned = owned,
			missing = missing,
			ahBuyable = want.canAHBuy,
			hidden = false,
		}) end
	end
	return items
end

local function Rescan()
	if scanRunning then return end
	scanRunning = true
	pendingScan = nil
	if not IsResting() then
		scanRunning = false
		return
	end
	addon.Vendor.CraftShopper.items = BuildShoppingList()
	scanRunning = false
end

local function ScheduleRescan()
	if pendingScan or scanRunning then return end
	pendingScan = C_Timer.NewTimer(SCAN_DELAY, Rescan)
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRACKED_RECIPE_UPDATE") -- parameter 1: ID of recipe - parameter 2: tracked true/false
f:RegisterEvent("BAG_UPDATE_DELAYED") -- verzögerter Scan, um Event-Flut zu vermeiden
f:RegisterEvent("CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE") -- arg1: error code, 0 on success

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "BAG_UPDATE_DELAYED" then
		ScheduleRescan()
	elseif event == "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE" then
		if arg1 == 0 and not scanRunning then Rescan() end
	else
		Rescan()
	end
end)

function addon.Vendor.functions.checkList()
	Rescan()
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable then
			local info = C_Item.GetItemInfo(item.itemID)
			print(("[%s]   fehlt: %d - Buy in AH"):format(info or ("ItemID " .. item.itemID), item.missing))
		end
	end
end
