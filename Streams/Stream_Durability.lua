-- luacheck: globals EnhanceQoL INVSLOT_HEAD INVSLOT_SHOULDER INVSLOT_CHEST INVSLOT_WAIST INVSLOT_LEGS INVSLOT_FEET INVSLOT_WRIST INVSLOT_HAND INVSLOT_BACK INVSLOT_MAINHAND INVSLOT_OFFHAND HEADSLOT SHOULDERSLOT CHESTSLOT WAISTSLOT LEGSLOT FEETSLOT WRISTSLOT HANDSSLOT BACKSLOT MAINHANDSLOT SECONDARYHANDSLOT
local floor = math.floor
local GetInventoryItemDurability = GetInventoryItemDurability

local slots = {
	[INVSLOT_HEAD] = HEADSLOT,
	[INVSLOT_SHOULDER] = SHOULDERSLOT,
	[INVSLOT_CHEST] = CHESTSLOT,
	[INVSLOT_WAIST] = WAISTSLOT,
	[INVSLOT_LEGS] = LEGSLOT,
	[INVSLOT_FEET] = FEETSLOT,
	[INVSLOT_WRIST] = WRISTSLOT,
	[INVSLOT_HAND] = HANDSSLOT,
	[INVSLOT_BACK] = BACKSLOT,
	[INVSLOT_MAINHAND] = MAINHANDSLOT,
	[INVSLOT_OFFHAND] = SECONDARYHANDSLOT,
}

local provider = {
	id = "durability",
	version = 1,
	title = "Durability",
	columns = {
		{ key = "slot", title = "Slot" },
		{ key = "percent", title = "Durability" },
	},
	poll = 30,
	collect = function(ctx)
		for slotId, name in pairs(slots) do
			local cur, max = GetInventoryItemDurability(slotId)
			if cur and max and max > 0 then
				local row = ctx.acquireRow()
				row.slot = name
				row.percent = floor((cur / max) * 100)
			end
		end
	end,
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
