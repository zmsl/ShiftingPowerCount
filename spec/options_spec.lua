local F = dofile("spec/fake.lua")

local function start(o) local w = F.install(o); F.fire("PLAYER_LOGIN"); return w end
local function slash(msg) SlashCmdList.SHIFTINGPOWERCOUNT(msg) end

describe("options", function()
    it("applies defaults at login and registers the panel", function()
        local w = start({})
        local db = ShiftingPowerCountDB
        assert.same({ 1, 1, 0.35, true, false, 20 }, { db.mode, db.icon.scale, db.icon.iconAlpha, db.icon.zeroRed, db.locked, db.icon.fontSize })
        assert.equal(1, w.frame.scale)
        assert.equal(0.35, w.icon.alpha)
        assert.equal("Shifting Power Count", w.settings.category.name)
        for _, k in ipairs({ "mode", "scale", "iconAlpha", "locked", "fontSize", "font", "outline", "color", "textPos", "zeroRed" }) do
            assert.is_table(w.settings.controls[k], k)
        end
        assert.equal(1, #w.settings.buttons)
    end)
    it("keeps saved values over defaults", function()
        F.install({}); _G.ShiftingPowerCountDB = { scale = 2, locked = true }; F.fire("PLAYER_LOGIN")
        assert.equal(2, F.w.frame.scale)
        assert.equal(2, ShiftingPowerCountDB.icon.scale)
        assert.is_true(ShiftingPowerCountDB.locked)
    end)
    it("size scales the frame, from the panel and from the CLI, the same DB field", function()
        local w = start({})
        w.settings.settings.scale:SetValue(1.7)
        assert.same({ 1.7, 1.7 }, { ShiftingPowerCountDB.icon.scale, w.frame.scale })
        slash("size 2.5")
        assert.same({ 2.5, 2.5 }, { ShiftingPowerCountDB.icon.scale, w.frame.scale })
        assert.equal(2.5, w.settings.settings.scale:GetValue()) -- panel follows the CLI
        slash("size 9")
        assert.equal(3, ShiftingPowerCountDB.icon.scale) -- clamped
    end)
    it("number only clears the icon, icon mode restores the opacity", function()
        local w = start({})
        slash("mode text")
        assert.same({ 2, 0 }, { ShiftingPowerCountDB.mode, w.icon.alpha })
        w.settings.settings.mode:SetValue(1)
        assert.equal(0.35, w.icon.alpha)
        w.settings.settings.iconAlpha:SetValue(0.6)
        assert.equal(0.6, w.icon.alpha)
    end)
    it("font size, font and outline reach every label, including ones built later", function()
        local w = start({})
        slash("fontsize 33"); slash("outline thick"); slash("font arial narrow")
        assert.equal(31, #w.fs)
        for _, fs in ipairs(w.fs) do assert.same({ "Fonts\\ARIALN.TTF", 33, "THICKOUTLINE" }, fs.font) end
        w.settings.settings.fontSize:SetValue(12)
        for _, fs in ipairs(w.fs) do assert.equal(12, fs.font[2]) end
        F.fire("SPELLS_CHANGED") -- rebuild keeps the style
        assert.equal(12, w.fs[5].font[2])
    end)
    it("colours: 0 red by default, option off uses the text colour, position anchors every label", function()
        local w = start({})
        assert.same({ 1, 0.2, 0.2 }, w.fs[1].color)
        assert.same({ 1, 1, 1 }, w.fs[2].color) -- default white
        slash("color ffd100")
        assert.same({ 1, 209 / 255, 0 }, w.fs[2].color)
        assert.same({ 1, 0.2, 0.2 }, w.fs[1].color)
        assert.equal("ffffd100", ShiftingPowerCountDB.icon.color) -- the colour picker's hex string
        assert.equal("swatch", w.settings.controls.SPC_ICON_COLOR.kind)
        slash("zero off")
        assert.same({ 1, 209 / 255, 0 }, w.fs[1].color)
        slash("pos below")
        for _, fs in ipairs(w.fs) do assert.same({ "TOP", w.frame, "BOTTOM", 0, -2 }, fs.point) end
    end)
    it("lock and reset share the DB with the panel", function()
        local w = start({})
        slash("lock")
        assert.is_true(w.settings.settings.locked:GetValue())
        w.settings.settings.locked:SetValue(false)
        assert.is_false(ShiftingPowerCountDB.locked)
        ShiftingPowerCountDB.pos = { "TOP", "TOP", 1, 1 }
        w.settings.buttons[1].click()
        assert.is_nil(ShiftingPowerCountDB.pos)
        assert.same({ "CENTER", 0, -150 }, w.frame.point)
    end)
    it("plain /spcount prints status and opens the panel; bad input does not error", function()
        local w = start({})
        slash("")
        assert.equal(42, w.settings.opened)
        assert.matches("size 1", w.printed)
        assert.has_no.errors(function() slash("size abc"); slash("mode nope"); slash("what") end)
    end)
    it("changes are safe in combat and never SetShown", function()
        local w = start({})
        w.combat = true
        local before = #w.shown
        assert.has_no.errors(function() slash("size 2"); slash("fontsize 30"); slash("mode text") end)
        assert.equal(before, #w.shown)
    end)
end)

describe("bar on player frame", function()
    local function ticksOf(bar)
        local r = {}
        for _, t in ipairs(rawget(bar, "textures") or {}) do
            if rawget(t, "color4") and rawget(t, "size") and t.size[1] == 2 and not rawget(t, "hidden") then
                r[#r + 1] = t.point[4] + 1 -- core is anchored 1px left of the tick position (2px wide, centred)
            end
        end
        return r
    end

    it("mode bar parents and anchors to PlayerFrame one strata below, in the fourth row", function()
        local w = start({})
        slash("mode bar")
        assert.equal(w.playerFrame, w.bar.parent)
        assert.same({ "TOPLEFT", w.playerFrame, "TOPLEFT", 85, -73 }, w.bar.point)
        assert.same({ 124, 9 }, w.bar.size)
        assert.equal("BACKGROUND", w.bar.strata)
        assert.equal(3, ShiftingPowerCountDB.mode)
        assert.equal("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", w.bar.barTexture)
        assert.equal("UI-HUD-UnitFrame-Player-PortraitOn-ClassResource", w.bar.textures[1].atlas)
        assert.same({ "CENTER", w.playerFrame, "CENTER", 0, -1.5 }, w.bar.textures[1].point)
    end)
    it("the floating frame goes invisible and the labels move onto the bar", function()
        local w = start({})
        slash("mode bar")
        assert.equal(0, w.frame.alpha)
        for _, fs in ipairs(w.fs) do
            assert.equal(w.overlay, fs.parent) -- never the (masked, clipping) StatusBar
            assert.is_not.equal(w.bar, fs.parent)
            assert.same({ "CENTER", w.overlay, "CENTER", 0, 0 }, fs.point)
        end
        slash("mode icon")
        assert.equal(1, w.frame.alpha)
        assert.is_true(w.bar.hidden)
        assert.equal(w.frame, w.fs[1].parent)
    end)
    it("ticks sit at every multiple of the cost, 124 wide", function()
        local w = start({ cost = 400, max = 2000 })
        slash("mode bar")
        local got = ticksOf(w.bar) -- 400/2000 of 124 each, none at the far end
        assert.equal(4, #got)
        for i, want in ipairs({ 24.8, 49.6, 74.4, 99.2 }) do assert.is_true(math.abs(got[i] - want) < 1e-9) end
        slash("ticks off")
        assert.same({}, ticksOf(w.bar))
        slash("ticks on")
        assert.equal(4, #ticksOf(w.bar))
        assert.equal(2000, w.bar.max)
    end)
    it("SetValue receives the secret and the min/max the plain max", function()
        local w = start({ mana = F.SECRET })
        slash("mode bar")
        assert.has_no.errors(function() w.combat = true; F.tick() end)
        assert.equal(F.SECRET, w.bar.value)
        assert.same({ 0, 2000 }, { w.bar.min, w.bar.max })
    end)
    it("falls back to the floating bar, once in chat, when PlayerFrame is missing or hidden", function()
        local w = start({ noPlayerFrame = true })
        slash("mode bar")
        assert.is_nil(w.bar)
        assert.is_table(w.floatBar)
        assert.equal(0, w.frame.alpha) -- the icon frame is not the fallback any more
        assert.matches("floating bar", w.printed)
        w.printed = nil
        slash("mode bar")
        assert.is_nil(w.printed) -- said once
        local w2 = F.install({})
        F.fire("PLAYER_LOGIN")
        w2.pfShown = false
        slash("mode bar")
        assert.is_nil(w2.bar)
        assert.is_table(w2.floatBar)
    end)
    it("a mode switch in combat waits for PLAYER_REGEN_ENABLED, other options still apply live", function()
        local w = start({})
        w.combat = true
        slash("mode bar")
        assert.is_nil(w.bar)
        assert.is_not.equal(0, w.frame.alpha) -- still the floating frame
        assert.equal(3, ShiftingPowerCountDB.mode)
        slash("fontsize 30")
        assert.equal(30, w.fs[1].font[2])
        w.combat = false
        F.fire("PLAYER_REGEN_ENABLED")
        assert.equal(w.playerFrame, w.bar.parent)
        assert.equal(0, w.frame.alpha)
        assert.equal(14, w.fs[1].font[2]) -- capped at 14 on the bar
    end)
    it("bar colour: Mana keeps the unit frame's mana fill; a custom colour greys and tints it; count text; panel", function()
        local w = start({})
        slash("mode bar")
        local fill = w.bar:GetStatusBarTexture()
        assert.equal("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", w.bar.barTexture)
        assert.is_false(fill.desat)
        slash("barcolor ff8000")
        assert.same({ 2, "ffff8000" }, { ShiftingPowerCountDB.bar.barColor, ShiftingPowerCountDB.bar.barCustom })
        assert.equal("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", w.bar.barTexture) -- same art, greyed and tinted
        assert.is_true(fill.desat)
        assert.same({ 1, 128 / 255, 0 }, fill.vertex)
        slash("dark dark")
        assert.same({ 0.6, 128 / 255 * 0.6, 0 }, fill.vertex) -- Dark dims the custom colour too
        slash("dark normal"); slash("barcolor mana")
        assert.is_false(fill.desat)
        assert.same({ 1, 1, 1 }, fill.vertex)
        assert.equal("ffff8000", ShiftingPowerCountDB.bar.barCustom) -- kept for the next Custom
        slash("barcolor teal")
        assert.matches("RRGGBB", w.printed)
        slash("bartext off")
        assert.is_true(w.fs[1].hidden)
        w.settings.settings.barText:SetValue(true)
        assert.is_false(w.fs[1].hidden)
        for _, k in ipairs({ "barColor", "ticks", "barText" }) do assert.is_table(w.settings.controls[k], k) end
        assert.same({ "Mana", "Custom" }, { w.settings.controls.barColor.opts[1].label, w.settings.controls.barColor.opts[2].label })
        assert.equal("swatch", w.settings.controls.SPC_BAR_BARCUSTOM.kind)
        assert.equal(3, #w.settings.controls.mode.opts)
    end)
end)

describe("bar polish: dark mode, ticks, text overlay, Cat Form", function()
    local function parts(bar)
        local cores, edges = {}, {}
        for _, t in ipairs(rawget(bar, "textures") or {}) do
            if rawget(t, "size") and rawget(t, "color4") then
                if t.size[1] == 2 then cores[#cores + 1] = t elseif t.size[1] == 1 then edges[#edges + 1] = t end
            end
        end
        return cores, edges
    end

    it("ticks are plain 2px lines, full height, black by default, colour from a picker", function()
        local w = start({ cost = 400, max = 2000 })
        slash("mode bar")
        local cores, edges = parts(w.bar)
        assert.equal(4, #cores)
        assert.equal(0, #edges)
        assert.same({ 2, 9 }, cores[1].size)
        assert.same({ 0, 0, 0, 1 }, cores[1].color4)
        slash("tickcolor #FFE633")
        assert.same({ 1, 230 / 255, 51 / 255, 1 }, cores[1].color4)
        assert.equal("ffffe633", ShiftingPowerCountDB.bar.tickColor)
        assert.equal("swatch", w.settings.controls.tickColor.kind)
    end)
    it("the Frame tick colour is gone: tickcolor takes RRGGBB only", function()
        local w = start({ cost = 400, max = 2000 })
        slash("mode bar"); slash("tickcolor frame")
        assert.matches("RRGGBB", w.printed)
        assert.equal("ff000000", ShiftingPowerCountDB.bar.tickColor)
        for _, t in ipairs(w.bar.textures) do assert.is_nil(rawget(t, "texcoord") and rawget(t, "texture")) end
    end)
    it("dark mode tints only our own textures and shows the well", function()
        local w = start({})
        slash("mode bar")
        local art, bg = w.bar.textures[1], w.bar.textures[2]
        assert.is_true(bg.hidden)
        slash("dark dark")
        assert.is_false(bg.hidden)
        assert.same({ 0.45, 0.45, 0.45 }, art.vertex)
        assert.is_nil(rawget(w.playerFrame, "vertex")) -- PlayerFrame itself is never tinted
        assert.is_nil(rawget(w.playerFrame.PlayerFrameContainer, "vertex"))
        slash("dark off")
        assert.same({ 1, 1, 1 }, art.vertex)
        assert.is_true(bg.hidden)
        assert.is_table(w.settings.controls.barStyle)
    end)
    it("Bar style Match mirrors the visible frame art (DarkMode: desaturate + colour), follows later changes, never writes PlayerFrame", function()
        local w = start({ pfArt = true })
        local alt = w.playerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
        local frame = w.playerFrame.PlayerFrameContainer.FrameTexture
        frame:SetDesaturated(true); frame:SetVertexColor(0.2, 0.25, 0.3) -- what DarkMode does before we exist
        slash("mode bar")
        slash("dark match")
        local art, bg = w.bar.textures[1], w.bar.textures[2]
        assert.same({ 0.2, 0.25, 0.3 }, art.vertex) -- the visible FrameTexture, not the (white) hidden alternate one
        assert.is_true(art.desat)
        assert.same({ 0.2, 0.25, 0.3 }, bg.vertex)
        assert.is_false(bg.hidden)
        frame:SetVertexColor(0.5, 0.5, 0.6) -- a later recolour reaches us through the hook
        assert.same({ 0.5, 0.5, 0.6 }, art.vertex)
        frame:SetDesaturated(false); frame:SetVertexColor(1, 1, 1) -- unmodified frame: no well, colour back
        assert.is_false(art.desat)
        assert.is_true(bg.hidden)
        assert.same({ 1, 1, 1 }, art.vertex)
        slash("dark normal")
        frame:SetDesaturated(true); frame:SetVertexColor(0.1, 0.1, 0.1)
        assert.same({ 1, 1, 1 }, art.vertex) -- not matching any more
        assert.is_false(art.desat)
        assert.equal(4, rawget(frame, "vwrites")) -- only the writes this test made itself
        assert.equal(3, rawget(frame, "dwrites"))
        assert.is_nil(rawget(alt, "vwrites"))
        assert.is_nil(rawget(w.playerFrame, "vertex"))
    end)
    it("Match keeps the fill's own colour", function()
        local w = start({ pfArt = true })
        w.playerFrame.PlayerFrameContainer.AlternatePowerFrameTexture:SetVertexColor(0.2, 0.2, 0.2)
        slash("mode bar")
        slash("dark match")
        assert.is_true(w.bar.barTexture ~= nil)
        assert.is_nil(rawget(w.bar, "vertex"))
    end)
    it("old boolean dark migrates; DarkMode loaded defaults to Match; on|off are aliases", function()
        F.install({}); _G.ShiftingPowerCountDB = { dark = true }; F.fire("PLAYER_LOGIN")
        assert.same({ 3, nil }, { ShiftingPowerCountDB.bar.barStyle, ShiftingPowerCountDB.dark })
        F.install({}); _G.ShiftingPowerCountDB = { dark = false }; F.fire("PLAYER_LOGIN")
        assert.equal(1, ShiftingPowerCountDB.bar.barStyle)
        start({})
        assert.equal(1, ShiftingPowerCountDB.bar.barStyle)
        start({ darkMode = true })
        assert.equal(2, ShiftingPowerCountDB.bar.barStyle)
        F.install({ darkMode = true }); _G.ShiftingPowerCountDB = { barStyle = 1 }; F.fire("PLAYER_LOGIN")
        assert.equal(1, ShiftingPowerCountDB.bar.barStyle) -- a saved choice wins
        slash("dark on"); assert.equal(3, ShiftingPowerCountDB.bar.barStyle)
        slash("dark off"); assert.equal(1, ShiftingPowerCountDB.bar.barStyle)
        slash("dark match"); assert.equal(2, ShiftingPowerCountDB.bar.barStyle)
        assert.equal(3, #F.w.settings.controls.barStyle.opts)
    end)
    it("the overlay is a PlayerFrame child above the bar, not inside it", function()
        local w = start({})
        slash("mode bar")
        assert.equal(w.playerFrame, w.overlay.parent)
        assert.equal("LOW", w.overlay.strata)
        assert.equal("BACKGROUND", w.bar.strata)
    end)
    it("hides outside Cat Form in every mode and shows again on the form event", function()
        local w = start({})
        slash("mode bar")
        w.form = 5; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.same({ true, true, true }, { w.frame.hidden, w.bar.hidden, w.overlay.hidden })
        w.form = 1; F.fire("UPDATE_SHAPESHIFT_FORMS")
        assert.same({ false, false, false }, { w.frame.hidden, w.bar.hidden, w.overlay.hidden })
        slash("mode icon") -- the floating icon too
        w.form = nil; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.is_true(w.frame.hidden)
    end)
    it("form changes work in combat, with plain booleans only", function()
        local w = start({})
        slash("mode bar")
        w.combat = true
        w.form = 3; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.same({ true, true }, { w.bar.hidden, w.overlay.hidden })
        w.form = 1; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.same({ false, false }, { w.bar.hidden, w.overlay.hidden })
        for _, v in ipairs(w.shown) do assert.is_boolean(v) end
        F.tick() -- the next tick refreshes the value
        assert.is_not_nil(rawget(w.bar, "value"))
    end)
    it("catonly off shows everywhere; the setting and CLI share the field", function()
        local w = start({ form = 5 })
        assert.is_true(w.frame.hidden)
        slash("catonly off")
        assert.is_false(ShiftingPowerCountDB.catOnly)
        assert.is_false(w.frame.hidden)
        w.settings.settings.catOnly:SetValue(true)
        assert.is_true(w.frame.hidden)
        assert.is_table(w.settings.controls.catOnly)
    end)
end)

describe("number boxes", function()
    -- Mimics a pooled SettingsSliderControlTemplate row: the slider routes its value into the setting.
    local function row(w, key)
        local st = w.settings.settings[key]
        local frame = { SliderWithSteppers = { SetValue = function(_, v) st:SetValue(v) end } }
        local init = w.settings.controls[key].init
        init:InitFrame(frame)
        return frame, frame.SPCBox, init
    end
    local function type_(box, text) box:SetText(text); box.scripts.OnEnterPressed(box) end

    it("every numeric setting gets a box showing its value", function()
        local w = start({})
        for key, want in pairs({ scale = "1", iconAlpha = "0.35", fontSize = "20" }) do
            local _, box = row(w, key)
            assert.equal(want, box:GetText(), key)
        end
    end)
    it("commits a typed number and sends it through the slider", function()
        local w = start({})
        local _, box = row(w, "scale")
        type_(box, "2.2")
        assert.same({ 2.2, 2.2, "2.2" }, { ShiftingPowerCountDB.icon.scale, w.frame.scale, box:GetText() })
    end)
    it("commits on losing focus too", function()
        local w = start({})
        local _, box = row(w, "fontSize")
        box:SetText("31"); box.scripts.OnEditFocusLost(box)
        assert.same({ 31, 31 }, { ShiftingPowerCountDB.icon.fontSize, w.fs[1].font[2] })
    end)
    it("clamps to the slider range and rounds to its step", function()
        local w = start({})
        local _, scale = row(w, "scale")
        type_(scale, "9"); assert.equal(3, ShiftingPowerCountDB.icon.scale)
        type_(scale, "-4"); assert.equal(0.5, ShiftingPowerCountDB.icon.scale)
        type_(scale, "1.26"); assert.same({ 1.3, "1.3" }, { ShiftingPowerCountDB.icon.scale, scale:GetText() })
        local _, size = row(w, "fontSize")
        type_(size, "20.6"); assert.equal(21, ShiftingPowerCountDB.icon.fontSize)
        type_(size, "1000"); assert.equal(72, ShiftingPowerCountDB.icon.fontSize)
        local _, a = row(w, "iconAlpha")
        type_(a, "0.37"); assert.equal(0.35, ShiftingPowerCountDB.icon.iconAlpha)
    end)
    it("reverts invalid input and on Escape", function()
        local w = start({})
        local _, box = row(w, "scale")
        for _, bad in ipairs({ "abc", "", "nan", "inf", "1..2" }) do
            type_(box, bad)
            assert.same({ 1, "1" }, { ShiftingPowerCountDB.icon.scale, box:GetText() }, bad)
        end
        box:SetText("2.5"); box.scripts.OnEscapePressed(box)
        assert.same({ 1, "1" }, { ShiftingPowerCountDB.icon.scale, box:GetText() })
    end)
    it("slider and CLI changes update the box, both ways live", function()
        local w = start({})
        local frame, box = row(w, "scale")
        frame.SliderWithSteppers:SetValue(1.8) -- slider drag
        assert.equal("1.8", box:GetText())
        slash("size 2.4") -- CLI
        assert.equal("2.4", box:GetText())
        type_(box, "0.7") -- box
        assert.same({ 0.7, 0.7 }, { ShiftingPowerCountDB.icon.scale, w.frame.scale })
        slash("fontsize 40") -- another setting's box stays untouched
        assert.equal("0.7", box:GetText())
    end)
    it("a released row hides its box and stops following the setting", function()
        local w = start({})
        local frame, box, init = row(w, "scale")
        init:Resetter(frame)
        assert.is_true(box.hidden)
        slash("size 2")
        assert.equal("1", box:GetText())
    end)
end)

describe("ticks on the Personal Resource Display mana row", function()
    local function cores(host)
        local r = {}
        for _, t in ipairs(rawget(host, "textures") or {}) do
            if rawget(t, "size") and t.size[1] == 2 and not rawget(t, "hidden") then r[#r + 1] = t end
        end
        return r
    end
    local function xs(host) local r = {}; for i, t in ipairs(cores(host)) do r[i] = t.point[4] + 1 end; return r end

    it("a tick at every multiple of the cost across the row's width and height, in any display mode", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        assert.equal(w.prdBar, w.prdHost.parent) -- our own child frame of the PRD row, never the row's textures
        assert.same({ 40, 80, 120, 160 }, xs(w.prdHost))
        assert.same({ 2, 10 }, cores(w.prdHost)[1].size)
        assert.is_nil(rawget(w.prdBar, "textures"))
        slash("mode bar")
        assert.same({ 40, 80, 120, 160 }, xs(w.prdHost))
    end)
    it("follows an Edit Mode resize of the row", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        w.prdW, w.prdH = 100, 6
        w.prdHost.scripts.OnSizeChanged(w.prdHost, 100, 6)
        assert.same({ 20, 40, 60, 80 }, xs(w.prdHost))
        assert.same({ 2, 6 }, cores(w.prdHost)[1].size)
    end)
    it("prdticks off hides them, the panel has the checkbox; the bar's tick colour does not reach the PRD", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        slash("prdticks off")
        assert.same({}, xs(w.prdHost))
        slash("prdticks on")
        assert.equal(4, #xs(w.prdHost))
        assert.is_table(w.settings.controls.prdTicks)
        slash("tickcolor ffe633")
        assert.same({ 0, 0, 0, 1 }, cores(w.prdHost)[1].color4) -- still the PRD's own colour (black)
    end)
    it("hidden outside Cat Form with the rest of the display; no PRD, no error", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        w.form = 5
        F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.is_true(w.prdHost.hidden)
        local w2 = start({ cost = 400, max = 2000 })
        assert.is_nil(w2.prdHost)
    end)
end)

describe("General and Style page", function()
    local function shown(w, var) return w.settings.controls[var].init:IsShown() end
    local function rows(w, m) -- the Style controls of mode m (variable names SPC_<MODE>_*) that are shown
        local r = {}
        for var, c in pairs(w.settings.controls) do
            if var:find("^SPC_" .. m .. "_") and c.init:IsShown() then r[#r + 1] = var:sub(#m + 6) end
        end
        table.sort(r)
        return r
    end

    it("has General, Personal Resource Display, then one Style header per mode, each with a tooltip", function()
        local w = start({})
        local names = {}
        for i, h in ipairs(w.settings.headers) do names[i] = h.header; assert.is_true(#h.tooltip > 0) end
        assert.same({ "General", "Personal Resource Display", "Icon Style", "Number Style", "Bar Style" }, names)
        local function visible()
            local r = {}
            for _, h in ipairs(w.settings.headers) do if h:IsShown() then r[#r + 1] = h.header end end
            return r
        end
        assert.same({ "General", "Personal Resource Display", "Icon Style" }, visible())
        slash("mode text")
        assert.same({ "General", "Personal Resource Display", "Number Style" }, visible())
        slash("mode bar")
        assert.same({ "General", "Personal Resource Display", "Bar Style" }, visible())
    end)
    it("shows General rows in every mode", function()
        local w = start({})
        for _, mode in ipairs({ "icon", "text", "bar" }) do
            slash("mode " .. mode)
            for _, var in ipairs({ "SPC_MODE", "SPC_CATONLY", "SPC_PRDTICKS" }) do assert.is_true(shown(w, var), var) end
        end
        slash("mode icon")
        assert.is_true(shown(w, "SPC_LOCKED"))
        assert.is_true(w.settings.buttons[1]:IsShown())
    end)
    it("shows only the selected mode's Style rows", function()
        local w = start({})
        assert.same({ "COLOR", "FONT", "FONTSIZE", "ICONALPHA", "OUTLINE", "SCALE", "TEXTPOS", "ZERORED" }, rows(w, "ICON"))
        assert.same({}, rows(w, "TEXT")); assert.same({}, rows(w, "BAR"))
        local before = w.settings.repairs
        slash("mode text")
        assert.same({ "COLOR", "FONT", "FONTSIZE", "OUTLINE", "SCALE", "ZERORED" }, rows(w, "TEXT"))
        assert.same({}, rows(w, "ICON"))
        assert.is_true(w.settings.repairs > before)
        slash("mode bar")
        assert.same({ "BARCOLOR", "BARSTYLE", "BARTEXT", "COLOR", "FONT", "FONTSIZE", "OUTLINE", "PLACEMENT", "TICKCOLOR", "TICKS", "ZERORED" },
            rows(w, "BAR"))
    end)
    it("Number position belongs to Icon and number only", function()
        local w = start({})
        assert.is_table(w.settings.controls.SPC_ICON_TEXTPOS)
        assert.is_nil(w.settings.controls.SPC_TEXT_TEXTPOS)
        slash("mode text")
        assert.is_nil(ShiftingPowerCountDB.text.textPos)
    end)
    it("Bar rows follow Placement; the custom bar colour row shows only for Custom", function()
        local w = start({})
        slash("mode bar")
        assert.is_true(shown(w, "SPC_BAR_BARCOLOR") and shown(w, "SPC_BAR_BARSTYLE"))
        assert.is_false(shown(w, "SPC_BAR_BARCUSTOM"))
        local before = w.settings.repairs
        w.settings.settings.SPC_BAR_BARCOLOR:SetValue(2)
        assert.is_true(shown(w, "SPC_BAR_BARCUSTOM"))
        assert.is_true(w.settings.repairs > before) -- the open panel redraws
        w.settings.settings.SPC_BAR_PLACEMENT:SetValue(2)
        assert.is_false(shown(w, "SPC_BAR_BARSTYLE"))
        assert.is_true(shown(w, "SPC_BAR_BARCOLOR")) -- colours the floating fill too
        assert.is_true(shown(w, "SPC_BAR_WIDTH") and shown(w, "SPC_BAR_TEXTURE") and shown(w, "SPC_BAR_TEXTPOS"))
        assert.is_true(shown(w, "SPC_BAR_TICKCOLOR"))
        assert.is_true(shown(w, "SPC_BAR_TICKS")) -- shared by both placements
        w.settings.settings.SPC_BAR_PLACEMENT:SetValue(1)
        assert.is_true(shown(w, "SPC_BAR_BARSTYLE"))
        assert.is_false(shown(w, "SPC_BAR_WIDTH") or shown(w, "SPC_BAR_BORDER"))
    end)
    it("style commands act on the current mode only", function()
        local w = start({})
        slash("mode text"); slash("fontsize 18")
        assert.same({ 18, 20 }, { ShiftingPowerCountDB.text.fontSize, ShiftingPowerCountDB.icon.fontSize })
        assert.equal(18, w.settings.settings.SPC_TEXT_FONTSIZE:GetValue())
        assert.equal(20, w.settings.settings.SPC_ICON_FONTSIZE:GetValue())
    end)
    it("bar-only keys written while Display is icon or text land in the bar table", function()
        local w = start({})
        for _, mode in ipairs({ "icon", "text" }) do
            slash("mode " .. mode)
            slash("ticks off"); slash("bartext off"); slash("tickcolor ffffff"); slash("barcolor ff2626"); slash("dark dark")
            local bar = ShiftingPowerCountDB.bar
            assert.same({ false, false, "ffffffff", 2, "ffff2626", 3 },
                { bar.ticks, bar.barText, bar.tickColor, bar.barColor, bar.barCustom, bar.barStyle }, mode)
            w.settings.settings.SPC_BAR_TICKS:SetValue(true)
            assert.is_true(bar.ticks)
            assert.is_nil(ShiftingPowerCountDB[mode].ticks)
        end
    end)
    it("hides Reset and Lock position when nothing floats", function()
        local w = start({})
        slash("mode bar")
        assert.is_false(shown(w, "SPC_LOCKED") or w.settings.buttons[1]:IsShown())
        w.settings.settings.SPC_BAR_PLACEMENT:SetValue(2)
        assert.is_true(shown(w, "SPC_LOCKED") and w.settings.buttons[1]:IsShown())
        slash("mode text")
        assert.is_true(shown(w, "SPC_LOCKED"))
    end)
    it("lists LibSharedMedia fonts", function()
        local w = start({})
        local names = {}
        for _, o in ipairs(w.settings.controls.SPC_ICON_FONT.opts) do names[o.value] = true end
        assert.is_true(names["Arial Narrow"] and names["Friz Quadrata TT"])
    end)
    it("registers each setting with its true default, not the login value", function()
        local w = start({})
        slash("fontsize 33"); slash("mode text")
        F.fire("PLAYER_LOGIN") -- re-registers from the saved table
        assert.equal(20, w.settings.settings.SPC_ICON_FONTSIZE.default)
        assert.equal(1, w.settings.settings.SPC_MODE.default)
    end)
    it("keeps the font failure line short", function()
        local w = start({})
        slash("font nope")
        assert.is_true(#w.printed < 200)
        assert.is_truthy(w.printed:find("Arial Narrow", 1, true))
    end)

    it("font and texture dropdowns list a stored name LibSharedMedia does not know", function()
        local w = start({})
        ShiftingPowerCountDB.icon.font = "Gone Font"
        ShiftingPowerCountDB.bar.texture = "Gone Tex"
        local function has(v, name)
            for _, o in ipairs(w.settings.controls[v].optsFn()) do
                if o.value == name then return true end
            end
        end
        assert.is_true(has("SPC_ICON_FONT", "Gone Font"))
        assert.is_true(has("SPC_BAR_TEXTURE", "Gone Tex"))
        assert.is_true(has("SPC_ICON_FONT", "Arial Narrow")) -- the listed ones stay
    end)
end)

describe("Personal Resource Display ticks: shape, colour, width", function()
    local function shown(host)
        local r = {}
        for _, t in ipairs(rawget(host, "textures") or {}) do
            if rawget(t, "size") and not rawget(t, "hidden") then r[#r + 1] = t end
        end
        return r
    end
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    local function prd() return start({ cost = 400, max = 2000, prd = { 200, 10 } }) end

    it("defaults to a black 2px bar, centred on each multiple of the cost", function()
        local w = prd()
        local db = ShiftingPowerCountDB
        assert.same({ 1, "ff000000", 2 }, { db.prdTickShape, db.prdTickColor, db.prdTickWidth })
        local t = shown(w.prdHost)
        assert.equal(4, #t)
        assert.same({ 2, 10 }, t[1].size)
        assert.same({ 0, 0, 0, 1 }, t[1].color4)
        assert.equal(39, t[1].point[4]) -- tick at 40, 2px wide: left edge at 39
    end)
    it("bar width is configurable and stays centred", function()
        local w = prd()
        slash("prdtickwidth 5")
        local t = shown(w.prdHost)
        assert.same({ 5, 10 }, t[1].size)
        assert.equal(37.5, t[1].point[4])
        slash("prdtickwidth 20")
        assert.equal(8, ShiftingPowerCountDB.prdTickWidth) -- clamped to 1-8
    end)
    it("pip: Blizzard's Cooldown Manager pip at the row's height, greyed and tinted with the colour, centred", function()
        local w = prd()
        slash("prdtickshape pip"); slash("prdtickcolor #FF8000")
        local t = shown(w.prdHost)
        assert.equal(4, #t)
        assert.equal("UI-HUD-CoolDownManager-Bar-Pip", t[1].atlas)
        assert.is_true(t[1].desat)
        assert.same({ 1, 128 / 255, 0 }, t[1].vertex)
        assert.equal("ffff8000", ShiftingPowerCountDB.prdTickColor) -- stored as the swatch's hex string
        assert.is_true(near(t[1].size[1], 100 / 23) and t[1].size[2] == 10)
        assert.is_true(near(t[1].point[4], 40 - 50 / 23))
    end)
    it("colour applies to the bar shape; back from pip to bar is a plain line again", function()
        local w = prd()
        slash("prdtickshape pip"); slash("prdtickcolor ff0000"); slash("prdtickshape bar")
        local t = shown(w.prdHost)
        assert.same({ 1, 0, 0, 1 }, t[1].color4)
        assert.is_false(t[1].desat)
        assert.same({ 1, 1, 1 }, t[1].vertex)
        assert.same({ 2, 10 }, t[1].size)
    end)
    it("the CLI colour takes RRGGBB with or without #; anything else is refused and kept", function()
        prd()
        slash("prdtickcolor 12ab9F")
        assert.equal("ff12ab9f", ShiftingPowerCountDB.prdTickColor)
        slash("prdtickcolor cyan")
        assert.equal("ff12ab9f", ShiftingPowerCountDB.prdTickColor)
        assert.truthy(F.w.printed:find("RRGGBB"))
    end)
    it("a stored non-hex colour (the preset test build) renders the default (black) and is reset at login", function()
        local w = F.install({ cost = 400, max = 2000, prd = { 200, 10 } })
        _G.ShiftingPowerCountDB = { schema = 1, prdTickColor = 4 }
        F.fire("PLAYER_LOGIN")
        assert.equal("ff000000", ShiftingPowerCountDB.prdTickColor)
        assert.same({ 0, 0, 0, 1 }, shown(w.prdHost)[1].color4)
    end)
    it("panel: shape, colour and width rows; width shows only for the bar shape", function()
        local w = prd()
        local c = w.settings.controls
        for _, var in ipairs({ "SPC_PRDTICKS", "SPC_PRDTICKSHAPE", "SPC_PRDTICKCOLOR", "SPC_PRDTICKWIDTH" }) do
            assert.is_table(c[var], var)
        end
        assert.equal("swatch", c.SPC_PRDTICKCOLOR.kind) -- Blizzard's colour swatch, opening the colour picker
        w.settings.settings.SPC_PRDTICKCOLOR:SetValue("ff00ff00") -- what the picker writes
        local t = shown(w.prdHost)
        assert.same({ 0, 1, 0, 1 }, t[1].color4)
        assert.is_true(c.SPC_PRDTICKWIDTH.init:IsShown())
        local before = w.settings.repairs
        w.settings.settings.SPC_PRDTICKSHAPE:SetValue(2)
        assert.is_false(c.SPC_PRDTICKWIDTH.init:IsShown())
        assert.is_true(w.settings.repairs > before) -- the open panel redraws
    end)
end)
