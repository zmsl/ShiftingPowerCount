-- Lint for Shifting Power Count (WoW Forever, Lua 5.1).
std = "lua51"
max_line_length = false
codes = true

exclude_files = { ".lua/", ".release/", ".luacheckrc", "Libs/" }

ignore = {
    "11./SLASH_.*", -- slash command globals
    "212",          -- unused arguments (event and script handler signatures)
}

-- The addon's own globals (written and read).
globals = { "ShiftingPowerCountDB", "SlashCmdList" }

-- Game API, FrameXML and client Lua extensions the addon reads.
read_globals = {
    "LibStub", "issecretvalue", "CreateFrame", "UIParent", "InCombatLockdown", "hooksecurefunc",
    "GetShapeshiftFormID", "UnitPower", "UnitPowerMax", "UnitPowerPercent", "C_Spell", "C_SpellBook",
    "C_CurveUtil", "C_AddOns", "C_Texture", "Enum", "Settings", "CreateSettingsButtonInitializer", "CreateSettingsListSectionHeaderInitializer", "SettingsInbound",
}

-- The busted specs install a fake client as globals.
files["spec/"] = { std = "+busted", allow_defined_top = true, ignore = { "1..", "4.." } }
