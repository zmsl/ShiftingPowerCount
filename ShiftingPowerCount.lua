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

local f = CreateFrame("Frame", "ShiftingPowerCountFrame", UIParent)
f:SetSize(64, 64)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetClampedToScreen(true)

local icon = f:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints()
icon:SetAlpha(0.35)

local labels, curves = {}, {}
local cost, maxMana, n = 0, 0, -1 -- UnitPowerPercent's input to the curve is 0..1 (Blizzard CurveConstants.ScaleTo100)

local function Label(k)
    local fs = labels[k]
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        fs:SetPoint("CENTER")
        fs:SetText(k)
        if k == 0 then fs:SetTextColor(1, 0.2, 0.2) else fs:SetTextColor(1, 1, 1) end
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
        local pos = ShiftingPowerCountDB.pos
        f:ClearAllPoints()
        if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER", 0, -150) end
    end
    Rebuild()
end)

SLASH_SHIFTINGPOWERCOUNT1 = "/spcount"
SlashCmdList.SHIFTINGPOWERCOUNT = function(msg)
    msg = (msg or ""):lower()
    if msg == "lock" or msg == "unlock" then
        ShiftingPowerCountDB.locked = msg == "lock"
        print("Shifting Power Count: " .. msg .. "ed")
    elseif msg == "reset" then
        ShiftingPowerCountDB.pos = nil
        f:ClearAllPoints()
        f:SetPoint("CENTER", 0, -150)
    else
        Rebuild()
        print(("Shifting Power Count: cost %s, max mana %s, %d casts at full. /spcount lock | unlock | reset")
            :format(tostring(cost), tostring(maxMana), n))
    end
end
