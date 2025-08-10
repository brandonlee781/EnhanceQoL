-- luacheck: globals EnhanceQoL
local floor = math.floor
local GetNumFactions = GetNumFactions
local GetFactionInfo = GetFactionInfo
local _G = _G

local provider = {
	id = "reputation",
	version = 1,
	title = "Reputation",
	columns = {
		{ key = "faction", title = "Faction" },
		{ key = "standing", title = "Standing" },
		{ key = "percent", title = "%" },
	},
	poll = 60,
	collect = function(ctx)
		for i = 1, GetNumFactions() do
			local name, _, standingID, barMin, barMax, barValue, _, _, isHeader = GetFactionInfo(i)
			if name and not isHeader then
				local row = ctx.acquireRow()
				row.faction = name
				row.standing = _G["FACTION_STANDING_LABEL" .. standingID]
				local pct = 0
				if barMax > barMin then pct = floor((barValue - barMin) / (barMax - barMin) * 100) end
				row.percent = pct
			end
		end
	end,
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
