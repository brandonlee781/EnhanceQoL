-- luacheck: globals EnhanceQoL C_FriendList
local GetNumFriends = C_FriendList.GetNumFriends
local GetFriendInfoByIndex = C_FriendList.GetFriendInfoByIndex

local provider = {
	id = "friends",
	version = 1,
	title = "Friends",
	columns = {
		{ key = "name", title = "Name" },
		{ key = "level", title = "Level" },
		{ key = "class", title = "Class" },
		{ key = "zone", title = "Zone" },
		{ key = "status", title = "Status" },
	},
	poll = 30,
	collect = function(ctx)
		for i = 1, GetNumFriends() do
			local info = GetFriendInfoByIndex(i)
			if info and info.name then
				local row = ctx.acquireRow()
				row.name = info.name
				row.level = info.level or 0
				row.class = info.className
				row.zone = info.area
				local status
				if info.dnd then
					status = "DND"
				elseif info.afk then
					status = "AFK"
				elseif info.connected then
					status = "Online"
				else
					status = "Offline"
				end
				row.status = status
			end
		end
	end,
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
