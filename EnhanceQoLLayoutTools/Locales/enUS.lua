local L = LibStub("AceLocale-3.0"):NewLocale("EnhanceQoL_LayoutTools", "enUS", true)

-- Category
L["Move"] = "Layout Tools"
L["Layout Tools"] = "Layout Tools"
L["Blizzard"] = "Blizzard"

-- Global section
L["Global Settings"] = "Global Settings"
L["Global Move Enabled"] = "Enable moving"
L["Global Scale Enabled"] = "Enable scaling (all)"
L["Require Modifier For Move"] = "Require modifier to move"
L["Move Modifier"] = "Move modifier"

-- Wheel scaling
L["Wheel Scaling"] = "Wheel Scaling"
L["Scale Modifier"] = "Scale Modifier"
L["ScaleInstructions"] = "Use %s + Mouse Wheel to scale. Use %s + Right-Click to reset."

-- Frames list
L["Frames"] = "Frames"
L["Enable scaling for"] = "Enable scaling for"
L["Enable moving for"] = "Enable moving for"

-- Optional legacy keys (if old pages are ever used)
L["uiScalerPlayerSpellsFrameMove"] = "Enable to move " .. (PLAYERSPELLS_BUTTON or "Talents & Spells")
L["uiScalerPlayerSpellsFrameEnabled"] = "Enable to Scale the " .. (PLAYERSPELLS_BUTTON or "Talents & Spells")
L["talentFrameUIScale"] = "Talent/Spells frame scale"
L["uiScalerCharacterFrameEnabled"] = "Enable to Scale the " .. (CHARACTER_BUTTON or "Character")
L["uiScalerCharacterFrameMove"] = "Enable to move " .. (CHARACTER_BUTTON or "Character")
