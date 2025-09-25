-- luacheck: globals TargetFrameHealthBarMixin TextStatusBar_UpdateTextStringWithValues
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
    addon = _G[parentAddonName]
else
    error(parentAddonName .. " is not loaded")
end

local BossFrames = addon.BossFrames or {}
addon.BossFrames = BossFrames

BossFrames.enabled = BossFrames.enabled or false
BossFrames.mode = BossFrames.mode or "OFF" -- OFF, PERCENT, ABS, BOTH
BossFrames.frame = BossFrames.frame or CreateFrame("Frame")
BossFrames.hooked = BossFrames.hooked or {}

local function isStatusTextEnabled()
    return tonumber(GetCVar("statusText") or "0") == 1
end

local function abbr(n)
    n = tonumber(n) or 0
    if n >= 1000000000 then
        local s = string.format("%.1fb", n / 1000000000)
        s = s:gsub("%.0b", "b")
        return s
    elseif n >= 1000000 then
        local s = string.format("%.1fm", n / 1000000)
        s = s:gsub("%.0m", "m")
        return s
    elseif n >= 1000 then
        local s = string.format("%.1fk", n / 1000)
        s = s:gsub("%.0k", "k")
        return s
    else
        return tostring(n)
    end
end

local function fmt(mode, cur, max)
    cur = cur or 0
    if mode == "ABS" then
        return abbr(cur)
    end
    local pct = 0
    if (max or 0) > 0 then pct = math.floor((cur / max) * 100 + 0.5) end
    if mode == "PERCENT" then
        return string.format("%d%%", pct)
    elseif mode == "BOTH" then
        return string.format("%d%% (%s)", pct, abbr(cur))
    else
        return ""
    end
end

local function getBossHB(i)
    local f = _G[("Boss%dTargetFrame"):format(i)]
    if not f or not f.TargetFrameContent then return end
    local main = f.TargetFrameContent.TargetFrameContentMain
    local hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
    return hb, f
end

local function applyText(hb, text)
    if not hb or not text then return end
    local t = hb.TextString or hb.HealthBarText
    if not t then return end
    if hb.LeftText then hb.LeftText:Hide() end
    if hb.RightText then hb.RightText:Hide() end
    t:SetText(text)
    t:Show()
end

function BossFrames:UpdateBossIndex(i)
    if not self.enabled or self.mode == "OFF" or isStatusTextEnabled() then return end
    local unit = ("boss%d"):format(i)
    if not UnitExists(unit) then return end
    local hb = getBossHB(i)
    if not hb then return end
    applyText(hb, fmt(self.mode, UnitHealth(unit), UnitHealthMax(unit)))
end

function BossFrames:UpdateAll()
    if not self.enabled or self.mode == "OFF" or isStatusTextEnabled() then return end
    local n = _G.MAX_BOSS_FRAMES or 5
    for i = 1, n do
        self:UpdateBossIndex(i)
    end
end

function BossFrames:HideAll()
    if isStatusTextEnabled() then return end
    local n = _G.MAX_BOSS_FRAMES or 5
    for i = 1, n do
        local hb = getBossHB(i)
        if hb then
            local t = hb.TextString or hb.HealthBarText
            if t then t:Hide() end
            if hb.LeftText then hb.LeftText:Hide() end
            if hb.RightText then hb.RightText:Hide() end
        end
    end
end

function BossFrames:HookBars()
    local n = _G.MAX_BOSS_FRAMES or 5
    for i = 1, n do
        local hb = getBossHB(i)
        if hb and not self.hooked[hb] then
            self.hooked[hb] = true
            local idx = i -- fix in closure

            if hb.UpdateTextStringWithValues then
                hooksecurefunc(hb, "UpdateTextStringWithValues", function(bar, textString, value, min, max)
                    if not addon or not addon.BossFrames then return end
                    if not addon.BossFrames.enabled or addon.BossFrames.mode == "OFF" or isStatusTextEnabled() then return end
                    if not textString or not UnitExists(("boss%d"):format(idx)) then return end
                    textString:SetText(fmt(addon.BossFrames.mode, UnitHealth(("boss%d"):format(idx)), UnitHealthMax(("boss%d"):format(idx))))
                    textString:Show()
                    if bar.LeftText then bar.LeftText:Hide() end
                    if bar.RightText then bar.RightText:Hide() end
                end)
            else
                hooksecurefunc("TextStatusBar_UpdateTextStringWithValues", function(statusBar, textString, value, min, max)
                    if statusBar ~= hb or not textString then return end
                    if not addon or not addon.BossFrames then return end
                    if not addon.BossFrames.enabled or addon.BossFrames.mode == "OFF" or isStatusTextEnabled() then return end
                    if not UnitExists(("boss%d"):format(idx)) then return end
                    textString:SetText(fmt(addon.BossFrames.mode, UnitHealth(("boss%d"):format(idx)), UnitHealthMax(("boss%d"):format(idx))))
                    textString:Show()
                    if statusBar.LeftText then statusBar.LeftText:Hide() end
                    if statusBar.RightText then statusBar.RightText:Hide() end
                end)
            end
        end
    end

    -- Post-hook: ensure our text after default updates
    if not self._valueHooked then
        hooksecurefunc(TargetFrameHealthBarMixin, "OnValueChanged", function(bar)
            if not addon or not addon.BossFrames then return end
            if not addon.BossFrames.enabled or addon.BossFrames.mode == "OFF" or isStatusTextEnabled() then return end
            local p = bar
            for _ = 1, 6 do
                if not p then return end
                if p.isBossFrame then break end
                p = p:GetParent()
            end
            if not (p and p.isBossFrame) then return end
            local name = p:GetName()
            local i = name and tonumber(name:match("^Boss(%d)TargetFrame$"))
            if i then addon.BossFrames:UpdateBossIndex(i) end
        end)
        self._valueHooked = true
    end
end

function BossFrames:SetEnabled(flag)
    if flag and isStatusTextEnabled() then flag = false end
    if self.enabled == flag then return end
    self.enabled = flag and true or false
    if self.enabled then
        self.frame:RegisterEvent("PLAYER_LOGIN")
        self.frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        self.frame:RegisterEvent("UNIT_HEALTH")
        self.frame:RegisterEvent("UNIT_MAXHEALTH")
        self.frame:RegisterEvent("CVAR_UPDATE")
        self:HookBars()
        self:UpdateAll()
    else
        self.frame:UnregisterEvent("PLAYER_LOGIN")
        self.frame:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        self.frame:UnregisterEvent("UNIT_HEALTH")
        self.frame:UnregisterEvent("UNIT_MAXHEALTH")
        self.frame:UnregisterEvent("CVAR_UPDATE")
        self:HideAll()
    end
end

function BossFrames:SetMode(mode)
    self.mode = mode or "OFF"
    local enable = (self.mode ~= "OFF") and not isStatusTextEnabled()
    self:SetEnabled(enable)
end

BossFrames.frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not addon or not addon.BossFrames then return end
    if not addon.BossFrames.enabled or addon.BossFrames.mode == "OFF" then return end
    if isStatusTextEnabled() then addon.BossFrames:SetEnabled(false) return end

    if event == "PLAYER_LOGIN" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        addon.BossFrames:HookBars()
        addon.BossFrames:UpdateAll()
    elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 and arg1:match("^boss%d$") then
        local i = tonumber(arg1:match("^boss(%d)$"))
        if i then addon.BossFrames:UpdateBossIndex(i) end
    elseif event == "CVAR_UPDATE" then
        local name = tostring(arg1 or "")
        if name:lower() == "statustext" then
            if isStatusTextEnabled() then
                addon.BossFrames:SetEnabled(false)
            else
                if addon.db and addon.db["bossHealthMode"] and addon.db["bossHealthMode"] ~= "OFF" then
                    addon.BossFrames:SetEnabled(true)
                end
            end
        end
    end
end)

-- Initialize from DB after file load
if addon and addon.db and addon.db["bossHealthMode"] then
    BossFrames:SetMode(addon.db["bossHealthMode"]) -- respects statusText CVar
end
