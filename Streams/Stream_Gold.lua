-- luacheck: globals EnhanceQoL
local floor = math.floor
local GetMoney = GetMoney

local COPPER_PER_GOLD = 10000

local provider = {
	id = "gold",
	version = 1,
	title = "Gold",
	columns = {
		{ key = "gold", title = "Gold" },
	},
	poll = 30,
	collect = function(ctx)
		local row = ctx.acquireRow()
		row.gold = floor(GetMoney() / COPPER_PER_GOLD)
	end,
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
