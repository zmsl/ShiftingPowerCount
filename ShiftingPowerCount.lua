-- Shifting Power Count: how many Shifting Powers (Forever Feral, spell 1322605) your mana pays for right now.
-- Mana is secret in combat, so the addon never reads it as a number. One label per count ("0", "1", ... "N") sits
-- on the same spot; each label's alpha is a step curve over your mana percent, 1 only inside its own band
-- [k*cost, (k+1)*cost). The client evaluates the curve on the secret value and SetAlpha accepts the secret result
-- (checked in game 2026-11-04: SetAlpha ok, SetShown errors). Cost and max mana are read out of combat, where
-- they are plain, and the bands are rebuilt whenever either changes.

local SPELL = 1322605 -- Shifting Power
local MANA = 0 -- Enum.PowerType.Mana
local MAX_LABELS = 30
local isSecret = issecretvalue or function() return false end

-- Options live in ShiftingPowerCountDB (defaults filled at login). Choice options store an index into CHOICES.
local DEFAULTS = { mode = 1, scale = 1, iconAlpha = 0.35, zeroRed = true, locked = false,
    fontSize = 20, font = 1, outline = 1, color = 1, textPos = 1 }
local CHOICES = { -- DB key -> { CLI name, panel label, value (font path / outline flag / rgb) }
    mode = { { "icon", "Icon and number" }, { "text", "Number only" } },
    font = { { "frizqt", "Friz Quadrata", "Fonts\\FRIZQT__.TTF" }, { "arialn", "Arial Narrow", "Fonts\\ARIALN.TTF" },
        { "morpheus", "Morpheus", "Fonts\\MORPHEUS.ttf" }, { "skurri", "Skurri", "Fonts\\skurri.ttf" } },
    outline = { { "none", "None", "" }, { "outline", "Outline", "OUTLINE" }, { "thick", "Thick outline", "THICKOUTLINE" } },
    color = { { "white", "White", { 1, 1, 1 } }, { "yellow", "Yellow", { 1, 0.82, 0 } }, { "green", "Green", { 0.2, 1, 0.2 } },
        { "cyan", "Cyan", { 0.3, 0.9, 1 } }, { "orange", "Orange", { 1, 0.5, 0.1 } } },
    textPos = { { "center", "Center" }, { "below", "Below the icon" }, { "above", "Above the icon" } },
}
local CLI_KEY = { mode = "mode", font = "font", outline = "outline", color = "color", pos = "textPos" }
local CLI_NUM = { size = { "scale", 0.5, 3 }, fontsize = { "fontSize", 8, 72 }, alpha = { "iconAlpha", 0, 1 } }
local settingObjs, category = {}, nil
local InitSettings

local function Opt(k)
    local db = ShiftingPowerCountDB
    local v = db and db[k]
    if v == nil then return DEFAULTS[k] end
    return v
end
local function Choice(k) return CHOICES[k][Opt(k)] or CHOICES[k][1] end

local f = CreateFrame("Frame", "ShiftingPowerCountFrame", UIParent)
f:SetSize(64, 64)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetClampedToScreen(true)

local icon = f:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints()

local labels, curves = {}, {}
local cost, maxMana, n = 0, 0, -1 -- UnitPowerPercent's input to the curve is 0..1 (Blizzard CurveConstants.ScaleTo100)

-- Every label gets the same font, outline and anchor; only the colour of "0" can differ.
local function Style(fs, k)
    fs:SetFont(Choice("font")[3], Opt("fontSize"), Choice("outline")[3])
    local c = (k == 0 and Opt("zeroRed")) and { 1, 0.2, 0.2 } or Choice("color")[3]
    fs:SetTextColor(c[1], c[2], c[3])
    local pos = Opt("textPos")
    fs:ClearAllPoints()
    if pos == 2 then fs:SetPoint("TOP", f, "BOTTOM", 0, -2)
    elseif pos == 3 then fs:SetPoint("BOTTOM", f, "TOP", 0, 2)
    else fs:SetPoint("CENTER") end
end

-- Safe in combat: plain values on our own non-secure frame (scale, alpha, font, anchors); no SetShown.
local function Apply()
    f:SetScale(Opt("scale"))
    icon:SetAlpha(Opt("mode") == 1 and Opt("iconAlpha") or 0)
    for k, fs in pairs(labels) do Style(fs, k) end
end

local function Label(k)
    local fs = labels[k]
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        Style(fs, k)
        fs:SetText(k)
        labels[k] = fs
        curves[k] = C_CurveUtil.CreateCurve()
        curves[k]:SetType(Enum.LuaCurveType.Step)
    end
    return fs
end

-- Out of combat only: read cost and max mana (plain there), then rebuild each label's band. The percent itself is
-- never read: UnitPowerPercent returns a secret even out of combat, so only the client evaluates it, via the curves.
local function Rebuild()
    if InCombatLockdown() then return end
    local known = C_SpellBook.IsSpellKnown(SPELL) == true
    f:SetShown(known)
    if not known then return end
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL)) -- first, so the frame is never an invisible box

    local c = 0
    for _, info in ipairs(C_Spell.GetSpellPowerCost(SPELL) or {}) do
        if info.type == MANA and not isSecret(info.cost) then c = info.cost end
    end
    local m = UnitPowerMax("player", MANA)
    if isSecret(m) or c <= 0 or m <= 0 then return end -- guard every divisor

    cost, maxMana = c, m
    n = math.min(math.floor(m / c), MAX_LABELS)
    for k = 0, MAX_LABELS do
        local fs = Label(k)
        local cv = curves[k]
        cv:ClearPoints()
        if k <= n then
            local lo, hi = k * c / m, (k + 1) * c / m
            cv:AddPoint(0, k == 0 and 1 or 0)
            if k > 0 then cv:AddPoint(lo, 1) end
            if k < n then cv:AddPoint(hi, 0) end
        else
            cv:AddPoint(0, 0)
        end
        fs:SetAlpha(0)
    end
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 or n < 0 then return end
    elapsed = 0
    for k = 0, n do
        labels[k]:SetAlpha(UnitPowerPercent("player", MANA, false, curves[k]))
    end
end)

f:SetScript("OnDragStart", function(self)
    if not ShiftingPowerCountDB.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ShiftingPowerCountDB.pos = { p, rp, x, y }
end)

local function ResetPos()
    ShiftingPowerCountDB.pos = nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", 0, -150)
end

-- Number box beside a slider (no XML): the slider initializer's InitFrame/Resetter are wrapped, so the row's pooled
-- frame gets an InputBoxTemplate EditBox on init and hides it on release. Typed text is clamped to the slider range,
-- rounded to its step, and sent through the slider, so slider, box, setting and CLI all see one value.
local boxes = {} -- DB key -> the edit box of the row currently showing that setting

local function Fmt(v) return (("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")) end

local function Snap(text, lo, hi, step) -- nil when the text is not a finite number
    local v = tonumber(text)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    v = lo + math.floor((math.max(lo, math.min(hi, v)) - lo) / step + 0.5) * step
    return tonumber(("%.4f"):format(math.min(hi, v)))
end

local function AttachBox(init, st, key, lo, hi, step)
    local origInit, origReset = init.InitFrame, init.Resetter
    init.InitFrame = function(self, frame)
        origInit(self, frame)
        local box = frame.SPCBox
        if not box then
            box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            box:SetSize(56, 20)
            box:SetAutoFocus(false)
            box:SetFontObject("GameFontHighlightSmall")
            box:SetPoint("LEFT", frame.SliderWithSteppers, "RIGHT", 14, 0)
            frame.SPCBox = box
        end
        local function show() box:SetText(Fmt(st:GetValue())) end
        local function commit()
            local v = Snap(box:GetText(), lo, hi, step)
            if v then (frame.SliderWithSteppers or st):SetValue(v) end
            show() -- invalid input reverts; valid input shows the snapped value
        end
        box:SetScript("OnEnterPressed", function(b) commit(); b:ClearFocus() end)
        box:SetScript("OnEditFocusLost", commit)
        box:SetScript("OnEscapePressed", function(b) show(); b:ClearFocus() end)
        boxes[key] = box
        show()
        box:Show()
    end
    init.Resetter = function(self, frame)
        origReset(self, frame)
        local box = frame.SPCBox
        if box then
            box:ClearFocus()
            box:Hide()
            if boxes[key] == box then boxes[key] = nil end
        end
    end
end

-- Options > AddOns panel (Settings API, verified on Forever). RegisterAddOnSetting writes into ShiftingPowerCountDB;
-- the value callback applies the change live.
InitSettings = function()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end -- no panel: CLI only
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Shifting Power Count")
    local function add(key, vtype, name)
        local st = Settings.RegisterAddOnSetting(category, "SPC_" .. key:upper(), key, ShiftingPowerCountDB, vtype, name, DEFAULTS[key])
        st:SetValueChangedCallback(function(_, v)
            ShiftingPowerCountDB[key] = v
            Apply()
            if boxes[key] and type(v) == "number" then boxes[key]:SetText(Fmt(v)) end -- slider/CLI -> box
        end)
        settingObjs[key] = st
        return st
    end
    local function choice(key, name)
        local function opts()
            local c = Settings.CreateControlTextContainer()
            for i, e in ipairs(CHOICES[key]) do c:Add(i, e[2]) end
            return c:GetData()
        end
        Settings.CreateDropdown(category, add(key, Settings.VarType.Number, name), opts)
    end
    local function slider(key, name, lo, hi, step)
        local st = add(key, Settings.VarType.Number, name)
        -- no right-hand value label: the number box takes its place
        AttachBox(Settings.CreateSlider(category, st, Settings.CreateSliderOptions(lo, hi, step)), st, key, lo, hi, step)
    end
    choice("mode", "Display")
    slider("scale", "Size", 0.5, 3, 0.1)
    slider("iconAlpha", "Icon opacity", 0, 1, 0.05)
    Settings.CreateCheckbox(category, add("locked", Settings.VarType.Boolean, "Lock position"))
    layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Reset position", ResetPos,
        "Put the frame back at its default spot", true))
    slider("fontSize", "Number size", 8, 72, 1)
    choice("font", "Number font")
    choice("outline", "Number outline")
    choice("color", "Number colour")
    choice("textPos", "Number position")
    Settings.CreateCheckbox(category, add("zeroRed", Settings.VarType.Boolean, "Show 0 in red"))
    Settings.RegisterAddOnCategory(category)
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ShiftingPowerCountDB = ShiftingPowerCountDB or {}
        for k, v in pairs(DEFAULTS) do
            if ShiftingPowerCountDB[k] == nil then ShiftingPowerCountDB[k] = v end
        end
        local pos = ShiftingPowerCountDB.pos
        f:ClearAllPoints()
        if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER", 0, -150) end
        Apply()
        InitSettings()
    end
    Rebuild()
end)

local function Set(key, v)
    if settingObjs[key] then settingObjs[key]:SetValue(v) end -- keeps an open panel in step
    ShiftingPowerCountDB[key] = v
    Apply()
end

local USAGE = "/spcount size <0.5-3> | mode icon|text | fontsize <8-72> | font | outline | color | pos | alpha <0-1>"
    .. " | zero on|off | lock | unlock | reset"

SLASH_SHIFTINGPOWERCOUNT1 = "/spcount"
SlashCmdList.SHIFTINGPOWERCOUNT = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "lock" or cmd == "unlock" then
        Set("locked", cmd == "lock")
        print("Shifting Power Count: " .. cmd .. "ed")
    elseif cmd == "reset" then
        ResetPos()
    elseif cmd == "zero" and (arg == "on" or arg == "off") then
        Set("zeroRed", arg == "on")
    elseif CLI_NUM[cmd] then
        local key, lo, hi = unpack(CLI_NUM[cmd])
        local v = tonumber(arg)
        if not v then return print(("Shifting Power Count: %s needs a number %s-%s"):format(cmd, lo, hi)) end
        Set(key, math.max(lo, math.min(hi, v)))
    elseif CLI_KEY[cmd] then
        local key = CLI_KEY[cmd]
        local names = {}
        for i, e in ipairs(CHOICES[key]) do
            if e[1] == arg then return Set(key, i) end
            names[#names + 1] = e[1]
        end
        print("Shifting Power Count: " .. cmd .. " is one of " .. table.concat(names, ", "))
    elseif cmd == "" then
        Rebuild()
        print(("Shifting Power Count: cost %s, max mana %s, %d casts at full, size %s, mode %s, %s")
            :format(tostring(cost), tostring(maxMana), n, tostring(Opt("scale")), Choice("mode")[1],
                Opt("locked") and "locked" or "unlocked"))
        if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
    else
        print("Shifting Power Count: " .. USAGE)
    end
end
