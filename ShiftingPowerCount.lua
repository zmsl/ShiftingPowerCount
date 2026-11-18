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

local LSM = LibStub("LibSharedMedia-3.0")

-- Options live in ShiftingPowerCountDB (defaults filled at login): General keys at the top level, each display mode's
-- look in its own table (MODE_KEY[mode]). Choice options store an index into CHOICES; fonts are LibSharedMedia names.
local DEFAULTS = { mode = 1, locked = false, catOnly = true, prdTicks = true } -- General
local MODE_KEY = { "icon", "text", "bar" }
local FONT = "Friz Quadrata TT"
local MODE_DEFAULTS = {
    { scale = 1, iconAlpha = 0.35, fontSize = 20, font = FONT, outline = 1, color = 1, textPos = 1, zeroRed = true },
    { scale = 1, fontSize = 20, font = FONT, outline = 1, color = 1, zeroRed = true },
    { placement = 1, ticks = true, tickColor = 1, barText = true, fontSize = 20, font = FONT, outline = 1, color = 1,
        zeroRed = true, barColor = 1, barStyle = 1, width = 150, height = 12, texture = "Blizzard", bgAlpha = 0.5,
        border = true, textPos = 1 }, -- width .. textPos: the floating bar only
}
local V1_FONT = { "Friz Quadrata TT", "Arial Narrow", "Morpheus", "Skurri" } -- v1.0.0 stored an index into these
local SCHEMA = 1
local CAT_FORM = 1 -- GetShapeshiftFormID() of Cat Form (Blizzard DRUID_CAT_FORM = 1)
local BAR_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-" -- + Mana / Energy / Rage / Focus / RunicPower (verified Forever)
local CHOICES = { -- DB key -> { CLI name, panel label, value (font path / outline flag / rgb) }
    mode = { { "icon", "Icon and number" }, { "text", "Number only" }, { "bar", "Bar on player frame" } },
    tickColor = { { "white", "White", { 1, 1, 1, 0.9 } }, { "black", "Black", { 0, 0, 0, 0.9 } },
        { "yellow", "Yellow", { 1, 0.9, 0.2, 0.9 } }, { "frame", "Frame", "frame" } },
    barColor = { { "mana", "Mana", BAR_ATLAS .. "Mana", { 0, 0.55, 1 } }, { "energy", "Energy", BAR_ATLAS .. "Energy", { 1, 0.85, 0.1 } },
        { "rage", "Rage", BAR_ATLAS .. "Rage", { 1, 0.15, 0.15 } }, { "focus", "Focus", BAR_ATLAS .. "Focus", { 1, 0.5, 0.25 } },
        { "runic", "Runic power", BAR_ATLAS .. "RunicPower", { 0, 0.82, 1 } } }, -- [3] atlas (player frame), [4] RGB (floating)
    outline = { { "none", "None", "" }, { "outline", "Outline", "OUTLINE" }, { "thick", "Thick outline", "THICKOUTLINE" } },
    color = { { "white", "White", { 1, 1, 1 } }, { "yellow", "Yellow", { 1, 0.82, 0 } }, { "green", "Green", { 0.2, 1, 0.2 } },
        { "cyan", "Cyan", { 0.3, 0.9, 1 } }, { "orange", "Orange", { 1, 0.5, 0.1 } } },
    barStyle = { { "normal", "Normal" }, { "match", "Match player frame" }, { "dark", "Dark" } },
    placement = { { "player", "On player frame" }, { "floating", "Floating" } },
    textPos = { { "center", "Center" }, { "below", "Below the icon" }, { "above", "Above the icon" } },
    barTextPos = { { "center", "Center" }, { "left", "Left" }, { "right", "Right" }, { "above", "Above" }, { "below", "Below" } },
}
local CLI_KEY = { mode = "mode", outline = "outline", color = "color", pos = "textPos", barcolor = "barColor",
    tickcolor = "tickColor", dark = "barStyle", placement = "placement" }
local CLI_BOOL = { zero = "zeroRed", ticks = "ticks", bartext = "barText", catonly = "catOnly", prdticks = "prdTicks",
    border = "border" }
local CLI_NUM = { size = { "scale", 0.5, 3 }, fontsize = { "fontSize", 8, 72 }, alpha = { "iconAlpha", 0, 1 },
    width = { "width", 50, 400 }, height = { "height", 4, 40 }, bgalpha = { "bgAlpha", 0, 1 } }
local settingObjs, category = {}, nil
local InitSettings

local function Opt(k)
    local db = ShiftingPowerCountDB
    local v = db and db[k]
    if v == nil then return DEFAULTS[k] end
    return v
end

local function CurMode() local m = Opt("mode"); return MODE_DEFAULTS[m] and m or 1 end
-- Style value of k in mode m's table (m: 1 icon, 2 text, 3 bar; default the current mode); nil when it has no such key.
local function S(k, m)
    m = m or CurMode()
    local db = ShiftingPowerCountDB
    local t = db and db[MODE_KEY[m]]
    local v = t and t[k]
    if v == nil then return MODE_DEFAULTS[m][k] end
    return v
end
local function Choice(k) return CHOICES[k][Opt(k)] or CHOICES[k][1] end
-- The bar's count position has its own list (five places), under the same DB key as the icon's.
local function List(k, m) return k == "textPos" and m == 3 and CHOICES.barTextPos or CHOICES[k] end
local function SChoice(k, m) m = m or CurMode(); local l = List(k, m); return l[S(k, m)] or l[1] end
-- LibSharedMedia returns its default font for a name that is not registered (the stored name is kept).
local function Scale() return S("scale") or S("scale", 1) end
local function FontPath() return LSM:Fetch("font", S("font")) end
local function TexturePath() return LSM:Fetch("statusbar", S("texture", 3)) end

-- Which mode's table the CLI writes style key k into: the current mode's if it has the key, else bar's (the bar-only
-- keys), else icon's; nil for a General key (top level).
local function Where(k)
    if DEFAULTS[k] ~= nil then return nil end
    local m = CurMode()
    if MODE_DEFAULTS[m][k] == nil then m = MODE_DEFAULTS[3][k] ~= nil and 3 or 1 end
    return m
end
-- Settings variable name: SPC_<KEY> for General, SPC_<MODEKEY>_<KEY> per mode.
local function Var(k, m) return "SPC_" .. (m and MODE_KEY[m]:upper() .. "_" or "") .. k:upper() end

-- v1.0.0 flat keys -> per-mode tables, once (schema absent). Pure: the table in, the table out.
local function Migrate(db)
    if db.schema then return db end
    for m, key in ipairs(MODE_KEY) do
        local t = type(db[key]) == "table" and db[key] or {}
        db[key] = t
        for k in pairs(MODE_DEFAULTS[m]) do
            local v = db[k]
            if k == "font" and type(v) == "number" then v = V1_FONT[v] end
            if k == "textPos" and m == 3 then v = nil end -- v1.0.0's textPos was the icon's list
            if v ~= nil and t[k] == nil then t[k] = v end
        end
    end
    for _, defaults in ipairs(MODE_DEFAULTS) do
        for k in pairs(defaults) do db[k] = nil end
    end
    db.schema = SCHEMA
    return db
end

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

-- Bar mode: a StatusBar child of PlayerFrame, one strata below it, in the fourth row of the unit frame. Geometry is
-- Blizzard's own alternate power bar row (Blizzard_UnitFrame PlayerFrame.xml / AlternatePowerBarBase.xml, Forever):
-- 124x9 at TOPLEFT (85,-73) of PlayerFrame, mask atlas anchored (-2,3), and the extended frame art
-- "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource" centred at (0,-1.5) (what PlayerFrame shows for that fourth row).
-- Our copy of that art sits below PlayerFrame's own art, so the ring tucks over its left end.
local BAR_W, BAR_H, BAR_X, BAR_Y = 124, 9, 85, -73
local BAR_FONT_MAX = 14 -- the digits may overflow the 9px row (own overlay frame, never clipped), but not by more
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
-- Frame tick colour: a slice of the frame's own border art. Nobody has seen it in game: TUNE IN GAME.
-- Source: atlas ui-hud-unitframe-player-portraiton-classresource (wow_atlas_search, forever) = sheet 4631591
-- (interface/hud/uiunitframe.blp, SetTexture(4631591) per wow_file_search), pixels left=808 right=1006 top=1 bottom=75,
-- so the art is 198x74. Sheet size 1024x512: not stated anywhere in Blizzard code; inferred from the atlases on that
-- sheet (max right 1023, max bottom 506; the 2x sheet reaches 2047/1021), power-of-two. Blizzard's layout
-- (PlayerFrame.xml): PlayerFrame 232x100, AlternatePowerFrameTexture CENTER (0,-1.5), our bar at (85,-73) 124x9.
-- Art left in the frame = 116-99 = 17, art top = 51.5-37 = 14.5. The bar ends at x=209 in the frame = column 192 of
-- the art, rows 58.5..67.5; the right border column starts there. In the sheet: x = 808+192 = 1000, y = 1+58.5 = 59.5.
-- TICK_FRAME_X is that column's offset in the atlas (192); it is the one number to nudge (+/- a few px) if the slice
-- shows the bar's end or the outside of the frame instead of the border. 2px wide, like the colour core.
local TICK_FRAME_X, TICK_FRAME_W, TICK_FRAME_Y = 192, 2, 58.5
local SHEET_W, SHEET_H, SHEET_ID, ATLAS_L, ATLAS_T = 1024, 512, 4631591, 808, 1
local bar, ticks = nil, {}
-- Personal Resource Display: on Forever its AlternatePowerBar is the mana row whenever the main bar is not mana (Cat and
-- Bear Form; Blizzard_PersonalResourceDisplay Camelot override). Our ticks live on our own child frame of that row.
local prdBar, prdHost, prdTicks = nil, nil, {}
local barAtlas
local overlay, barArt, barBg -- overlay: label host above the bar (outside the masked fill); art/bg: our own textures
local barOn = false -- the display actually realised (mode asked for AND PlayerFrame usable)
local floatOn = false -- the floating bar is the realised display (Placement Floating, or the fallback)
local floatBar, floatTicks, floatBg, floatEdges, floatTex = nil, {}, nil, {}, nil
local pendingLayout, warned, isKnown = false, false, false
local catOk, lastCatOnly = true, DEFAULTS.catOnly -- catOk: Cat Form (or the restriction is off)
local DARK_ART, DARK_FILL = 0.45, 0.6 -- Dark style brightness of our art copy / our fill
local STYLE_NORMAL, STYLE_MATCH, STYLE_DARK = 1, 2, 3
local frameDesat = false
local frameRGB = { 1, 1, 1 } -- vertex colour last read off PlayerFrame's frame art (DarkMode or any recolouring addon)
local hookedTex = {}

local FLOAT_TEXT = { { "CENTER", "CENTER", 0, 0 }, { "LEFT", "LEFT", 2, 0 }, { "RIGHT", "RIGHT", -2, 0 },
    { "BOTTOM", "TOP", 0, 2 }, { "TOP", "BOTTOM", 0, -2 } } -- bar.textPos: point on the label, point on the bar, offset
local function Style(fs, k) -- every label gets the same font, outline and anchor; only the colour of "0" can differ
    local size = S("fontSize")
    if barOn then size = math.min(size, BAR_FONT_MAX) end
    fs:SetFont(FontPath(), size, SChoice("outline")[3])
    local c = (k == 0 and S("zeroRed")) and { 1, 0.2, 0.2 } or SChoice("color")[3]
    fs:SetTextColor(c[1], c[2], c[3])
    local pos = CurMode() == 1 and S("textPos", 1) or 1 -- only the icon mode has a position
    fs:SetParent((barOn or floatOn) and overlay or f)
    fs:ClearAllPoints()
    if barOn or floatOn then
        local at = barOn and 1 or S("textPos", 3) -- the player-frame row has no count position
        local a = FLOAT_TEXT[at] or FLOAT_TEXT[1]
        fs:SetPoint(a[1], overlay, a[2], a[3], a[4])
        if S("barText", 3) then fs:Show() else fs:Hide() end
    else
        fs:Show()
        if pos == 2 then fs:SetPoint("TOP", f, "BOTTOM", 0, -2)
        elseif pos == 3 then fs:SetPoint("BOTTOM", f, "TOP", 0, 2)
        else fs:SetPoint("CENTER") end
    end
end

local function TickLook(t, h, frameArt) -- colour ticks, or the frame-art slice mirroring PlayerFrame's desaturation and colour
    local c = SChoice("tickColor", 3)[3]
    if c == "frame" and not frameArt then c = CHOICES.tickColor[1][3] end -- the PRD has no border art to cut: white
    if c == "frame" then
        local x0 = ATLAS_L + TICK_FRAME_X
        local y0 = ATLAS_T + TICK_FRAME_Y
        t.core:SetTexture(SHEET_ID)
        t.core:SetTexCoord(x0 / SHEET_W, (x0 + TICK_FRAME_W) / SHEET_W, y0 / SHEET_H, (y0 + BAR_H) / SHEET_H)
        t.core:SetSize(TICK_FRAME_W, BAR_H)
        t.core:SetDesaturated(frameDesat)
        t.core:SetVertexColor(frameRGB[1], frameRGB[2], frameRGB[3])
        t.l:Hide(); t.r:Hide()
        return false
    end
    local edge = c[1] == 0 and 1 or 0 -- black ticks get light edges, the others dark ones
    t.core:SetColorTexture(c[1], c[2], c[3], c[4])
    t.core:SetTexCoord(0, 1, 0, 1)
    t.core:SetDesaturated(false)
    t.core:SetVertexColor(1, 1, 1)
    t.core:SetSize(2, h)
    t.l:SetSize(1, h)
    t.r:SetSize(1, h)
    t.l:SetColorTexture(edge, edge, edge, 0.8)
    t.r:SetColorTexture(edge, edge, edge, 0.8)
    return true
end

-- One tick per Shifting Power cost on a host w x h: the segments are casts. Plain out-of-combat numbers.
local function PlaceTicks(host, list, show, w, h, frameArt)
    for i = 1, MAX_LABELS do
        local x = show and (i * cost / maxMana * w) -- only divides when show (maxMana > 0)
        local t = list[i]
        if x and x < w - 0.5 then
            if not t then -- a 2px core with a 1px edge on each side, full row height
                t = { core = host:CreateTexture(nil, "OVERLAY", nil, 2), l = host:CreateTexture(nil, "OVERLAY", nil, 1),
                    r = host:CreateTexture(nil, "OVERLAY", nil, 1) }
                list[i] = t
            end
            local edges = TickLook(t, h, frameArt)
            t.core:ClearAllPoints(); t.core:SetPoint("LEFT", host, "LEFT", x - 1, 0)
            t.l:ClearAllPoints(); t.l:SetPoint("RIGHT", t.core, "LEFT", 0, 0)
            t.r:ClearAllPoints(); t.r:SetPoint("LEFT", t.core, "RIGHT", 0, 0)
            t.core:Show()
            if edges then t.l:Show(); t.r:Show() end
        elseif t then
            t.core:Hide(); t.l:Hide(); t.r:Hide()
        end
    end
end

local function LayoutTicks()
    local ok = cost > 0 and maxMana > 0
    if bar then PlaceTicks(bar, ticks, S("ticks", 3) and ok, BAR_W, BAR_H, true) end
    if floatBar then PlaceTicks(floatBar, floatTicks, S("ticks", 3) and ok, S("width", 3), S("height", 3), false) end
    if prdHost then
        local w, h = prdBar:GetWidth(), prdBar:GetHeight()
        if isSecret(w) or isSecret(h) or type(w) ~= "number" or type(h) ~= "number" or w <= 0 then w, h, ok = 0, 0, false end
        PlaceTicks(prdHost, prdTicks, Opt("prdTicks") and ok, w, h, false)
    end
end

local function HookPRD() -- once: our tick frame on the PRD mana row; it hides and scales with the row
    local prd = _G.PersonalResourceDisplayFrame
    if prdHost or not (prd and prd.AlternatePowerBar) then return end
    prdBar = prd.AlternatePowerBar
    prdHost = CreateFrame("Frame", "ShiftingPowerCountPRDTicks", prdBar)
    prdHost:SetAllPoints(prdBar)
    prdHost:SetScript("OnSizeChanged", LayoutTicks) -- Edit Mode width/height
end

-- Match style: read (never write) what PlayerFrame's art carries. DarkMode (D4KiR) greys a texture with
-- SetDesaturated(true) (its Desaturate option) and then multiplies its colour in with SetVertexColor, so both are
-- mirrored. The visible texture is sampled first: the alternate one is hidden on Forever and may stay uncoloured.
local FRAME_ART = { "FrameTexture", "AlternatePowerFrameTexture" }
local function PlayerArt()
    return _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
end
local function SampleFrameColor()
    local c = PlayerArt()
    for _, key in ipairs(FRAME_ART) do
        local t = c and c[key]
        if t and t.GetVertexColor and (key ~= "FrameTexture" or not t.IsShown or t:IsShown()) then
            local d = t.IsDesaturated and t:IsDesaturated()
            frameDesat = d == true and not isSecret(d)
            local r, g, b = t:GetVertexColor()
            if type(r) == "number" and type(g) == "number" and type(b) == "number"
                and not (isSecret(r) or isSecret(g) or isSecret(b)) then
                frameRGB = { r, g, b }
                return
            end
        end
    end
    frameRGB, frameDesat = { 1, 1, 1 }, false
end

-- Our own art copy and well only; PlayerFrame's textures are never written.
local function ArtVisuals()
    local style = S("barStyle", 3)
    barArt:SetDesaturated(style == STYLE_MATCH and frameDesat)
    barBg:SetDesaturated(style == STYLE_MATCH and frameDesat)
    if style == STYLE_MATCH then
        barArt:SetVertexColor(frameRGB[1], frameRGB[2], frameRGB[3])
        barBg:SetVertexColor(frameRGB[1], frameRGB[2], frameRGB[3])
        -- the well only where something recoloured the frame (plain white = unmodified frame, no well)
        local plain = not frameDesat and frameRGB[1] == 1 and frameRGB[2] == 1 and frameRGB[3] == 1
        if plain then barBg:Hide() else barBg:Show() end
    else
        local dark = style == STYLE_DARK
        barArt:SetVertexColor(dark and DARK_ART or 1, dark and DARK_ART or 1, dark and DARK_ART or 1)
        barBg:SetVertexColor(1, 1, 1)
        if dark then barBg:Show() else barBg:Hide() end
    end
end

local function HookFrameArt() -- once per texture: a later recolour of PlayerFrame's art reaches our copy
    local c = PlayerArt()
    for _, key in ipairs(FRAME_ART) do
        local t = c and c[key]
        if t and t.SetVertexColor and not hookedTex[t] then
            hookedTex[t] = true
            local function resample()
                SampleFrameColor()
                if barArt and S("barStyle", 3) == STYLE_MATCH then ArtVisuals() end
                if barArt and SChoice("tickColor", 3)[3] == "frame" then LayoutTicks() end -- regardless of Bar style
            end
            hooksecurefunc(t, "SetVertexColor", resample)
            if t.SetDesaturated then hooksecurefunc(t, "SetDesaturated", resample) end
        end
    end
end

local function BarVisuals()
    local atlas = SChoice("barColor", 3)[3]
    if atlas ~= barAtlas then barAtlas = atlas; bar:SetStatusBarTexture(atlas) end -- once per change: keeps the mask
    local dark = S("barStyle", 3) == STYLE_DARK
    local fill = bar:GetStatusBarTexture() -- our own fill keeps its colour in Match; PlayerFrame's textures are never touched
    if fill then fill:SetVertexColor(dark and DARK_FILL or 1, dark and DARK_FILL or 1, dark and DARK_FILL or 1) end
    HookFrameArt()
    SampleFrameColor()
    ArtVisuals()
    LayoutTicks()
end

local function MakeBar(pf)
    bar = CreateFrame("StatusBar", "ShiftingPowerCountBar", pf)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOPLEFT", pf, "TOPLEFT", BAR_X, BAR_Y)
    bar:SetMinMaxValues(0, math.max(maxMana, 1))
    bar:SetValue(0)
    barArt = bar:CreateTexture(nil, "BACKGROUND") -- the frame art with the extra row, under PlayerFrame's own art
    barArt:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-ClassResource", true)
    barArt:SetPoint("CENTER", pf, "CENTER", 0, -1.5)
    barBg = bar:CreateTexture(nil, "BACKGROUND", nil, 1) -- dark mode well, behind the fill, above the art
    barBg:SetColorTexture(0.02, 0.02, 0.02, 0.9)
    barBg:SetAllPoints(bar)
    -- Labels live here, not on the bar: the bar and its mask would clip them. Same strata as PlayerFrame, above the bar.
    BarVisuals()
    local tex, mask = bar:GetStatusBarTexture(), bar:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", true)
    mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
    if tex then tex:SetTexelSnappingBias(0); tex:SetSnapToPixelGrid(false); tex:AddMaskTexture(mask) end
end

-- The label host: one frame, moved onto whichever bar is the realised display (out of combat only).
local function Overlay(parent, host)
    if overlay then overlay:SetParent(parent)
    else
        overlay = CreateFrame("Frame", "ShiftingPowerCountOverlay", parent)
        overlay:SetClipsChildren(false)
    end
    overlay:SetAllPoints(host)
end

local BAR_POS = { "CENTER", "CENTER", 0, -190 }
local function PlaceFloat(pos)
    pos = pos or BAR_POS
    floatBar:ClearAllPoints()
    floatBar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

-- Plain values on our own frame, live in combat: size, texture, fill colour, background and border.
local function FloatVisuals()
    local w, h = S("width", 3), S("height", 3)
    floatBar:SetSize(w, h)
    local path = TexturePath() -- an unregistered name renders LibSharedMedia's default; the stored name is kept
    if path ~= floatTex then floatTex = path; floatBar:SetStatusBarTexture(path) end
    local c = SChoice("barColor", 3)[4]
    floatBar:SetStatusBarColor(c[1], c[2], c[3])
    floatBg:SetColorTexture(0, 0, 0, S("bgAlpha", 3))
    for _, e in ipairs(floatEdges) do e:SetShown(S("border", 3)) end
    LayoutTicks()
end

local function MakeFloat()
    floatBar = CreateFrame("StatusBar", "ShiftingPowerCountFloatingBar", UIParent)
    floatBar:SetMovable(true)
    floatBar:EnableMouse(true)
    floatBar:RegisterForDrag("LeftButton")
    floatBar:SetClampedToScreen(true)
    floatBar:SetMinMaxValues(0, math.max(maxMana, 1)) -- unknown max: empty until the first out-of-combat rebuild
    floatBar:SetValue(0)
    floatBg = floatBar:CreateTexture(nil, "BACKGROUND")
    floatBg:SetAllPoints(floatBar)
    -- 1px black edges outside the bar: { point on the edge, point on the bar } x2, then the thin side
    for i, g in ipairs({ { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", -1, 1, "h" },
        { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", -1, 1, "h" },
        { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0, "w" },
        { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, "w" } }) do
        local e = floatBar:CreateTexture(nil, "BORDER")
        e:SetColorTexture(0, 0, 0, 1)
        e:SetPoint(g[1], floatBar, g[2], g[5], 0)
        e:SetPoint(g[3], floatBar, g[4], g[6], 0)
        if g[7] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        floatEdges[i] = e
    end
    floatBar:SetScript("OnDragStart", function(self)
        if not ShiftingPowerCountDB.locked then self:StartMoving() end
    end)
    floatBar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ShiftingPowerCountDB.barPos = { p, rp, x, y }
    end)
    PlaceFloat(ShiftingPowerCountDB.barPos)
    FloatVisuals()
end

local function PlayerFrameUsable()
    local pf = _G.PlayerFrame
    return pf ~= nil and pf.PlayerFrameContainer ~= nil and pf:IsShown() and pf or nil
end

local function Restyle() for k, fs in pairs(labels) do Style(fs, k) end end

-- Plain booleans on our own frames: fine in combat. The floating frame stays "shown" (alpha 0) in bar mode so its
-- OnUpdate keeps ticking; hiding it with the rest stops the updates, and the next tick after showing refreshes.
local function ApplyVisibility()
    local show = isKnown and catOk
    f:SetShown(show)
    if prdHost then prdHost:SetShown(show) end
    if barOn then
        bar:SetShown(show)
        overlay:SetShown(show)
    elseif floatOn then
        floatBar:SetShown(show)
        overlay:SetShown(show)
    end
end

-- Cat Form gate (all modes). GetShapeshiftFormID is plain on Forever; a secret or a missing API keeps the last state.
local function UpdateForm()
    local ok = true
    if Opt("catOnly") then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        if isSecret(form) then return end
        ok = form == CAT_FORM
    end
    if ok ~= catOk then
        catOk = ok
        ApplyVisibility()
    end
end

-- Which display Bar mode asks for: the player-frame row (Placement 1 and PlayerFrame usable) or else the floating bar.
local function Want()
    if Opt("mode") ~= 3 then return false, false end
    local pf = S("placement", 3) == 1 and PlayerFrameUsable() or nil
    return pf ~= nil, pf == nil
end

-- Out of combat only (anchor, parent and strata): realise the display mode. The floating bar is also the fallback when
-- Placement is On player frame but PlayerFrame is hidden or replaced (another unit-frame addon): say so once.
local function Layout()
    local want, wantFloat = Want()
    if wantFloat and S("placement", 3) == 1 and not warned then
        warned = true
        print("Shifting Power Count: PlayerFrame is not available (hidden or replaced), showing the floating bar instead.")
    end
    barOn, floatOn = want, wantFloat
    if bar and not barOn then bar:Hide() end
    if floatBar and not floatOn then floatBar:Hide() end
    if barOn then
        local pf = PlayerFrameUsable()
        if not bar then MakeBar(pf) end
        Overlay(pf, bar)
        local at = 2
        for i, s in ipairs(STRATA) do if s == pf:GetFrameStrata() then at = i end end
        bar:SetFrameStrata(STRATA[math.max(1, at - 1)]) -- one below PlayerFrame
        overlay:SetFrameStrata(pf:GetFrameStrata()) -- PlayerFrame's strata: above the bar
        f:SetAlpha(0) -- labels live on the overlay
        f:EnableMouse(false)
    elseif floatOn then
        if not floatBar then MakeFloat() end
        Overlay(floatBar, floatBar)
        floatBar:SetFrameStrata("MEDIUM")
        overlay:SetFrameStrata("MEDIUM")
        f:SetAlpha(0)
        f:EnableMouse(false)
    else
        if overlay then overlay:Hide() end
        f:SetAlpha(1)
        f:EnableMouse(true)
    end
    Restyle()
    if barOn or floatOn then ApplyVisibility() end
end

-- Safe in combat: plain values on our own non-secure frames. Only a mode switch (anchor/strata/parent) waits for
-- PLAYER_REGEN_ENABLED.
local function Apply()
    local db = ShiftingPowerCountDB
    if S("placement", 3) == 2 and S("tickColor", 3) == 4 and db and db.bar then db.bar.tickColor = 1 end -- Frame needs the player frame
    f:SetScale(Scale())
    icon:SetAlpha(Opt("mode") == 1 and S("iconAlpha") or 0)
    if bar then BarVisuals() end
    if floatBar then FloatVisuals() end
    if Opt("catOnly") ~= lastCatOnly then lastCatOnly = Opt("catOnly"); UpdateForm() end
    local want, wantFloat = Want()
    if want ~= barOn or wantFloat ~= floatOn then
        if InCombatLockdown() then
            if not pendingLayout then print("Shifting Power Count: the display mode changes when combat ends.") end
            pendingLayout = true
        else
            Layout()
        end
    end
    Restyle() -- font, colour, text visibility: live even while a mode switch is pending
    LayoutTicks()
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
    isKnown = known
    ApplyVisibility()
    if not known then return end
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL)) -- first, so the frame is never an invisible box

    local c = 0
    for _, info in ipairs(C_Spell.GetSpellPowerCost(SPELL) or {}) do
        if info.type == MANA and not isSecret(info.cost) then c = info.cost end
    end
    local m = UnitPowerMax("player", MANA)
    if isSecret(m) or c <= 0 or m <= 0 then return end -- guard every divisor

    cost, maxMana = c, m
    if bar then bar:SetMinMaxValues(0, m) end
    if floatBar then floatBar:SetMinMaxValues(0, m) end
    LayoutTicks()
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
    if barOn then bar:SetValue(UnitPower("player", MANA)) end -- SetValue takes the secret; no arithmetic on it
    if floatOn then floatBar:SetValue(UnitPower("player", MANA)) end
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

local function ResetPos() -- the frame the current display shows
    if floatOn then
        ShiftingPowerCountDB.barPos = nil
        PlaceFloat()
        return
    end
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

-- Options > AddOns panel (Settings API, verified on Forever). Each setting is registered against the table that holds
-- it (General: the top level; Style: its mode's table), so the panel and the CLI write the same field; the value
-- callback applies the change live. Style rows of every mode exist; shown predicates keep only the selected mode's.
local function Repair() -- the open panel re-evaluates the shown predicates
    if SettingsInbound and SettingsInbound.RepairDisplay then SettingsInbound.RepairDisplay() end
end
local function ModeShown(m) return function() return CurMode() == m end end
local function PlacementShown(p) return function() return S("placement", 3) == p end end
local function Floats() return not barOn end -- something to move or lock: everything but the player-frame row

InitSettings = function()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end -- no panel: CLI only
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Shifting Power Count")
    -- m: the mode whose table holds the setting (nil: General). Each helper returns the row's initializer.
    local function add(m, key, vtype, name)
        local db = ShiftingPowerCountDB
        local var = Var(key, m)
        local st = Settings.RegisterAddOnSetting(category, var, key, m and db[MODE_KEY[m]] or db, vtype, name,
            (m and MODE_DEFAULTS[m] or DEFAULTS)[key])
        st:SetValueChangedCallback(function(_, v)
            Apply()
            if key == "mode" or key == "placement" then Repair() end
            if boxes[var] and type(v) == "number" then boxes[var]:SetText(Fmt(v)) end -- slider/CLI -> box
        end)
        settingObjs[var] = st
        return st
    end
    local function check(m, key, name, tip)
        return Settings.CreateCheckbox(category, add(m, key, Settings.VarType.Boolean, name), tip)
    end
    local function choice(m, key, name, tip, list) -- list: optional function giving the CHOICES entries to offer
        local function opts()
            local c = Settings.CreateControlTextContainer()
            for i, e in ipairs(list and list() or CHOICES[key]) do c:Add(i, e[2]) end
            return c:GetData()
        end
        return Settings.CreateDropdown(category, add(m, key, Settings.VarType.Number, name), opts, tip)
    end
    local function mediaChoice(m, key, name, kind) -- fonts and textures: values are LibSharedMedia names
        local function opts()
            local c = Settings.CreateControlTextContainer()
            for _, media in ipairs(LSM:List(kind)) do c:Add(media, media) end
            return c:GetData()
        end
        return Settings.CreateDropdown(category, add(m, key, Settings.VarType.String, name), opts)
    end
    local function slider(m, key, name, lo, hi, step, tip)
        local st = add(m, key, Settings.VarType.Number, name)
        -- no right-hand value label: the number box takes its place
        local init = Settings.CreateSlider(category, st, Settings.CreateSliderOptions(lo, hi, step), tip)
        AttachBox(init, st, Var(key, m), lo, hi, step)
        return init
    end
    -- Tick colour: the Frame choice cuts the player frame's border art, so only On player frame offers it.
    local function tickChoices() return S("placement", 3) == 1 and CHOICES.tickColor or { unpack(CHOICES.tickColor, 1, 3) } end

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General",
        "What the addon shows. These apply to every display mode."))
    choice(nil, "mode", "Display", "Bar on player frame adds a fourth row under the player unit frame's bars, one strata "
        .. "below it. It matches the unit frame, so Size and the lock/position settings do not apply to it. If the "
        .. "player frame is hidden or replaced, the floating frame is used instead. Changes in combat wait until combat ends.")
    check(nil, "catOnly", "Show only in Cat Form", "Hide the display (every mode) outside Cat Form.")
    check(nil, "prdTicks", "Personal Resource Display: cast ticks", "A tick at every multiple of the Shifting Power cost "
        .. "on the Personal Resource Display's mana row (Cat and Bear Form), in every display mode. Uses the tick colour.")
    check(nil, "locked", "Lock position"):AddShownPredicate(Floats)
    local reset = CreateSettingsButtonInitializer("Position", "Reset position", ResetPos,
        "Put the frame back at its default spot", true)
    reset:AddShownPredicate(Floats)
    layout:AddInitializer(reset)

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Style",
        "How the selected display looks. Switch Display above to style another mode."))
    for m = 1, 3 do
        local function row(init, p) -- shown only for mode m (and bar placement p)
            init:AddShownPredicate(ModeShown(m))
            if p then init:AddShownPredicate(PlacementShown(p)) end
        end
        if m == 3 then
            row(choice(m, "placement", "Placement", "On player frame: a fourth row under the player unit frame's bars. "
                .. "Floating: a separate bar you can move."))
        end
        if m ~= 3 then
            row(slider(m, "scale", "Size", 0.5, 3, 0.1, "Scales the floating frame (icon and number together)."))
        end
        if m == 1 then row(slider(m, "iconAlpha", "Icon opacity", 0, 1, 0.05)) end
        if m == 3 then
            row(check(m, "ticks", "Show cast ticks", "A tick at every multiple of the Shifting Power cost, so each segment is one cast."))
            row(choice(m, "tickColor", "Tick colour", "Tick colour. White, black and yellow ticks have a 1px edge on both sides. "
                .. "Frame (On player frame only): a slice of the player frame's own border art, greyed and tinted like it "
                .. "(for example by DarkMode), no edges; white on the Personal Resource Display.", tickChoices))
            row(check(m, "barText", "Show count", "Show the number of casts on the bar."))
        end
        row(slider(m, "fontSize", "Number size", 8, 72, 1))
        row(mediaChoice(m, "font", "Number font", "font"))
        row(choice(m, "outline", "Number outline"))
        row(choice(m, "color", "Number colour"))
        if m == 1 then row(choice(m, "textPos", "Number position")) end
        row(check(m, "zeroRed", "Show 0 in red"))
        if m == 3 then
            row(choice(m, "barColor", "Bar colour", "Fill of the bar. On the player frame it is the unit frame's own bar art."))
            row(choice(m, "barStyle", "Bar style", "Normal: the plain frame art. Match player frame: the new row's frame art "
                .. "and well take the colour the player frame has (for example from the DarkMode addon). Dark: a fixed "
                .. "near-black well, a dimmer fill and a darker copy of the frame art."), 1)
            row(slider(m, "width", "Width", 50, 400, 1), 2)
            row(slider(m, "height", "Height", 4, 40, 1), 2)
            row(mediaChoice(m, "texture", "Texture", "statusbar"), 2)
            row(slider(m, "bgAlpha", "Background opacity", 0, 1, 0.05), 2)
            row(check(m, "border", "Border", "A 1px black edge around the bar."), 2)
            row(choice(m, "textPos", "Count position", "Where the number sits on the floating bar.",
                function() return CHOICES.barTextPos end), 2)
        end
    end
    Settings.RegisterAddOnCategory(category)
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ShiftingPowerCountDB = ShiftingPowerCountDB or {}
        local db = ShiftingPowerCountDB
        if not db.schema and db.barStyle == nil then -- migrate the old boolean "dark"; a fresh install matches when DarkMode is loaded
            if type(db.dark) == "boolean" then db.barStyle = db.dark and STYLE_DARK or STYLE_NORMAL
            elseif C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DarkMode") then db.barStyle = STYLE_MATCH end
        end
        db.dark = nil
        Migrate(db)
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        for m, key in ipairs(MODE_KEY) do
            if type(db[key]) ~= "table" then db[key] = {} end
            for k, v in pairs(MODE_DEFAULTS[m]) do
                if db[key][k] == nil then db[key][k] = v end
            end
        end
        HookPRD()
        local pos = ShiftingPowerCountDB.pos
        f:ClearAllPoints()
        if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER", 0, -150) end
        Apply()
        UpdateForm()
        InitSettings()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
        if ShiftingPowerCountDB then UpdateForm() end
        return
    elseif event == "PLAYER_ENTERING_WORLD" and ShiftingPowerCountDB then
        HookPRD()
        Apply() -- PlayerFrame is up now
        UpdateForm()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingLayout then
        pendingLayout = false
        Layout()
        Repair() -- Lock and Reset position follow what is realised
    end
    Rebuild()
end)

local function Set(key, v)
    local m = Where(key)
    if m and m ~= CurMode() then
        print(("Shifting Power Count: %s is a %s display setting (Display is %s)"):format(key, MODE_KEY[m], MODE_KEY[CurMode()]))
    end
    local st = settingObjs[Var(key, m)]
    if st then return st:SetValue(v) end -- the panel's setting writes the field and applies (keeps an open panel in step)
    local db = ShiftingPowerCountDB
    local t = m and db[MODE_KEY[m]] or db
    t[key] = v
    Apply()
end

local USAGE = "(style commands act on the current Display mode) /spcount size <0.5-3> | mode icon|text|bar | fontsize <8-72> | font <name> | texture <name> | width <50-400> | height <4-40> | bgalpha <0-1> | border on|off | outline | color | pos | alpha <0-1>"
    .. " | barcolor | tickcolor | dark normal|match|dark | placement player|floating | catonly on|off | ticks on|off | bartext on|off | prdticks on|off | zero on|off | lock | unlock | reset"

SLASH_SHIFTINGPOWERCOUNT1 = "/spcount"
SlashCmdList.SHIFTINGPOWERCOUNT = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "dark" then arg = ({ on = "dark", off = "normal" })[arg] or arg end -- old on|off aliases
    if cmd == "lock" or cmd == "unlock" then
        Set("locked", cmd == "lock")
        print("Shifting Power Count: " .. cmd .. "ed")
    elseif cmd == "reset" then
        ResetPos()
    elseif CLI_BOOL[cmd] and (arg == "on" or arg == "off") then
        Set(CLI_BOOL[cmd], arg == "on")
    elseif CLI_NUM[cmd] then
        local key, lo, hi = unpack(CLI_NUM[cmd])
        local v = tonumber(arg)
        if not v then return print(("Shifting Power Count: %s needs a number %s-%s"):format(cmd, lo, hi)) end
        Set(key, math.max(lo, math.min(hi, v)))
    elseif cmd == "font" or cmd == "texture" then
        local kind = cmd == "font" and "font" or "statusbar"
        local all = LSM:List(kind)
        for _, name in ipairs(all) do
            if name:lower() == arg then return Set(cmd, name) end
        end
        print(("Shifting Power Count: %s is a LibSharedMedia name, %d installed (%s ...); the panel lists them all")
            :format(cmd, #all, table.concat(all, ", ", 1, math.min(3, #all))))
    elseif CLI_KEY[cmd] then
        local key = CLI_KEY[cmd]
        local names = {}
        for i, e in ipairs(List(key, Where(key))) do
            if e[1] == arg then return Set(key, i) end
            names[#names + 1] = e[1]
        end
        print("Shifting Power Count: " .. cmd .. " is one of " .. table.concat(names, ", "))
    elseif cmd == "" then
        Rebuild()
        print(("Shifting Power Count: cost %s, max mana %s, %d casts at full, size %s, mode %s, %s")
            :format(tostring(cost), tostring(maxMana), n, tostring(Scale()), Choice("mode")[1],
                Opt("locked") and "locked" or "unlocked"))
        if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
    else
        print("Shifting Power Count: " .. USAGE)
    end
end
