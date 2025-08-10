local addonName, addon = ...
addon.DataPanel = addon.DataPanel or {}
local DataPanel = addon.DataPanel
local DataHub = addon.DataHub

local panels = {}

local function ensureSettings(id)
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local info = addon.db.dataPanels[id]
	if not info then
		info = { point = "CENTER", x = 0, y = 0, width = 200, height = 20, streams = {}, streamSet = {} }
		addon.db.dataPanels[id] = info
	else
		info.streams = info.streams or {}
		info.streamSet = info.streamSet or {}
	end

	for _, name in ipairs(info.streams) do
		info.streamSet[name] = true
	end

	return info
end

local function savePosition(frame, id)
	local info = ensureSettings(id)
	info.point, _, _, info.x, info.y = frame:GetPoint()
	info.width = frame:GetWidth()
	info.height = frame:GetHeight()
end

function DataPanel.Create(id)
	if panels[id] then return panels[id] end
	local info = ensureSettings(id)
	local frame = CreateFrame("Frame", addonName .. "DataPanel" .. id, UIParent, "BackdropTemplate")
	frame:SetSize(info.width, info.height)
	frame:SetPoint(info.point, info.x, info.y)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		savePosition(f, id)
	end)
	frame:SetScript("OnMouseDown", function(f, btn)
		if btn == "RightButton" then f:StartSizing("BOTTOMRIGHT") end
	end)
	frame:SetScript("OnMouseUp", function(f, btn)
		if btn == "RightButton" then
			f:StopMovingOrSizing()
			savePosition(f, id)
		end
	end)
	frame:SetScript("OnSizeChanged", function(f) savePosition(f, id) end)
	frame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.5)

	local panel = { frame = frame, id = id, streams = {}, order = {}, info = info }

	function panel:Refresh()
		local changed = false
		if not self.lastOrder or #self.lastOrder ~= #self.order then
			changed = true
		else
			for i, name in ipairs(self.order) do
				if self.lastOrder[i] ~= name or (self.lastWidths and self.lastWidths[name] ~= self.streams[name].lastWidth) then
					changed = true
					break
				end
			end
		end
		if not changed then return end

		local prev
		for _, name in ipairs(self.order) do
			local data = self.streams[name]
			local btn = data.button
			btn:ClearAllPoints()
			btn:SetWidth(data.lastWidth)
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", 5, 0)
			else
				btn:SetPoint("LEFT", self.frame, "LEFT", 5, 0)
			end
			prev = btn
		end

		self.lastOrder = {}
		self.lastWidths = {}
		for i, name in ipairs(self.order) do
			self.lastOrder[i] = name
			self.lastWidths[name] = self.streams[name].lastWidth
		end
	end

	function panel:AddStream(name)
		if self.streams[name] then return end
		local button = CreateFrame("Button", nil, self.frame)
		button:SetHeight(self.frame:GetHeight())
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		local data = { button = button, text = text, lastWidth = text:GetStringWidth(), lastText = "" }
		button.slot = data
		button:SetScript("OnEnter", function(b)
			local s = b.slot
			if s.tooltip then
				GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
				GameTooltip:SetText(s.tooltip)
				GameTooltip:Show()
			end
			if s.OnMouseEnter then s.OnMouseEnter(b) end
		end)
		button:SetScript("OnLeave", function(b)
			local s = b.slot
			if s.OnMouseLeave then s.OnMouseLeave(b) end
			GameTooltip:Hide()
		end)
		button:SetScript("OnClick", function(b, ...)
			local s = b.slot
			if s.OnClick then s.OnClick(b, ...) end
		end)

		self.order[#self.order + 1] = name

		local function cb(payload)
			payload = payload or {}
			local text = payload.text or ""
			if text ~= data.lastText then
				data.text:SetText(text)
				data.lastText = text
				local width = data.text:GetStringWidth()
				if width ~= data.lastWidth then
					data.lastWidth = width
					self:Refresh()
				end
			end
			data.tooltip = payload.tooltip
			data.OnMouseEnter = payload.OnMouseEnter
			data.OnMouseLeave = payload.OnMouseLeave
			data.OnClick = payload.OnClick
		end

		data.unsub = DataHub:Subscribe(name, cb)
		self.streams[name] = data

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if not streamSet[name] then
			streamSet[name] = true
			streams[#streams + 1] = name
		end
	end

	function panel:RemoveStream(name)
		local info = self.streams[name]
		if not info then return end
		if info.unsub then info.unsub() end
		info.button:Hide()
		info.button:SetParent(nil)
		self.streams[name] = nil
		for i, n in ipairs(self.order) do
			if n == name then
				table.remove(self.order, i)
				break
			end
		end
		self:Refresh()

		local streams = self.info.streams
		local streamSet = self.info.streamSet
		if streamSet[name] then
			streamSet[name] = nil
			for i, s in ipairs(streams) do
				if s == name then
					table.remove(streams, i)
					break
				end
			end
		end
	end

	panels[id] = panel

	if info.streams then
		for _, name in ipairs(info.streams) do
			panel:AddStream(name)
		end
	end

	return panel
end

function DataPanel.List()
	addon.db = addon.db or {}
	addon.db.dataPanels = addon.db.dataPanels or {}
	local result = {}
	for id, info in pairs(addon.db.dataPanels) do
		local entry = { list = {}, set = {} }
		result[id] = entry
		if info.streams then
			for _, stream in ipairs(info.streams) do
				if not entry.set[stream] then
					entry.set[stream] = true
					entry.list[#entry.list + 1] = stream
				end
			end
		end
	end
	for id, panel in pairs(panels) do
		local entry = result[id]
		if not entry then
			entry = { list = {}, set = {} }
			result[id] = entry
		end
		for _, stream in ipairs(panel.order) do
			if not entry.set[stream] then
				entry.set[stream] = true
				entry.list[#entry.list + 1] = stream
			end
		end
	end
	for id, info in pairs(result) do
		result[id] = info.list
	end
	return result
end

function DataPanel.Delete(id)
	local panel = panels[id]
	if panel then
		for i = #panel.order, 1, -1 do
			panel:RemoveStream(panel.order[i])
		end
		panel.frame:Hide()
		panel.frame:SetParent(nil)
		panels[id] = nil
	end
	if addon.db and addon.db.dataPanels then addon.db.dataPanels[id] = nil end
end

function DataPanel.SlashHandler(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	if cmd == "create" then
		local id, w, h = rest:match("^(%S+)%s*(%d*)%s*(%d*)")
		if id then
			local panel = DataPanel.Create(id)
			if w ~= "" and h ~= "" then panel.frame:SetSize(tonumber(w), tonumber(h)) end
		end
	elseif cmd == "add" then
		local id, stream = rest:match("^(%S+)%s+(%S+)$")
		if id and stream then
			local panel = DataPanel.Create(id)
			panel:AddStream(stream)
		end
	elseif cmd == "remove" then
		local id, stream = rest:match("^(%S+)%s+(%S+)$")
		if id and stream and panels[id] then panels[id]:RemoveStream(stream) end
	else
		print("/eqolpanel create <id> [width] [height]")
		print("/eqolpanel add <id> <stream>")
		print("/eqolpanel remove <id> <stream>")
	end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
	addon.db = addon.db or {}
	local panelsDB = addon.db.dataPanels or {}
	addon.db.dataPanels = panelsDB

	for id in pairs(panelsDB) do
		DataPanel.Create(id)
	end

	self:UnregisterEvent("PLAYER_LOGIN")
end)

return DataPanel
