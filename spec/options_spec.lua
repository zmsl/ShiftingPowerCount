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
        slash("color yellow")
        assert.same({ 1, 0.82, 0 }, w.fs[2].color)
        assert.same({ 1, 0.2, 0.2 }, w.fs[1].color)
        slash("zero off")
        assert.same({ 1, 0.82, 0 }, w.fs[1].color)
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
    it("bar colour, count text and settings panel entries", function()
        local w = start({})
        slash("mode bar"); slash("barcolor energy")
        assert.equal("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy", w.bar.barTexture)
        slash("bartext off")
        assert.is_true(w.fs[1].hidden)
        w.settings.settings.barText:SetValue(true)
        assert.is_false(w.fs[1].hidden)
        for _, k in ipairs({ "barColor", "ticks", "barText" }) do assert.is_table(w.settings.controls[k], k) end
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

    it("ticks are plain 2px lines, full height, in the chosen colour, no edges; the colour is a preset", function()
        local w = start({ cost = 400, max = 2000 })
        slash("mode bar")
        local cores, edges = parts(w.bar)
        assert.equal(4, #cores)
        assert.equal(0, #edges)
        assert.same({ 2, 9 }, cores[1].size)
        assert.same({ 1, 1, 1, 0.9 }, cores[1].color4)
        slash("tickcolor yellow")
        assert.same({ 1, 0.9, 0.2, 0.9 }, cores[1].color4)
        slash("tickcolor black")
        assert.same({ 0, 0, 0, 0.9 }, cores[1].color4) -- just black: no light outline
        assert.equal(0, #select(2, parts(w.bar)))
        assert.is_table(w.settings.controls.tickColor)
    end)
    it("tick colour Frame cuts the frame art's border slice, mirrors DarkMode, follows hooks, white restores", function()
        local w = start({ pfArt = true })
        local frame = w.playerFrame.PlayerFrameContainer.FrameTexture
        frame:SetDesaturated(true); frame:SetVertexColor(0.2, 0.25, 0.3)
        slash("mode bar")
        slash("tickcolor frame") -- Bar style stays Normal: the mirroring does not depend on it
        local ticks = {}
        for _, t in ipairs(w.bar.textures) do if rawget(t, "texcoord") and t.texture == 4631591 then ticks[#ticks + 1] = t end end
        assert.equal(4, #ticks)
        local tc = ticks[1].texcoord
        assert.near(1000 / 1024, tc[1], 1e-9); assert.near(1002 / 1024, tc[2], 1e-9)
        assert.near(59.5 / 512, tc[3], 1e-9); assert.near(68.5 / 512, tc[4], 1e-9)
        assert.same({ 2, 9 }, ticks[1].size)
        assert.is_true(ticks[1].desat)
        assert.same({ 0.2, 0.25, 0.3 }, ticks[1].vertex)
        for _, t in ipairs(w.bar.textures) do if rawget(t, "size") and t.size[1] == 1 then assert.is_true(t.hidden) end end -- no edges
        frame:SetVertexColor(0.5, 0.5, 0.6)
        assert.same({ 0.5, 0.5, 0.6 }, ticks[1].vertex)
        frame:SetDesaturated(false)
        assert.is_false(ticks[3].desat)
        slash("tickcolor white")
        assert.same({ 1, 1, 1, 0.9 }, ticks[1].color4)
        assert.same({ 1, 1, 1 }, ticks[1].vertex)
        assert.is_false(ticks[1].desat)
        assert.same({ 0, 1, 0, 1 }, ticks[1].texcoord)
        assert.is_false(ticks[1].hidden)
        assert.equal(0, #select(2, parts(w.bar))) -- white is a plain line: no edges come back
        assert.equal(2, rawget(frame, "vwrites")) -- only this test's own writes
        assert.is_nil(rawget(w.playerFrame, "vertex"))
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
        slash("tickcolor yellow")
        assert.equal(6704514, cores(w.prdHost)[1].texture) -- still the PRD tick style's Border slice
        assert.is_nil(rawget(cores(w.prdHost)[1], "color4"))
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

    it("has a General then a Style header, each with a tooltip", function()
        local w = start({})
        assert.same({ "General", "Style" }, { w.settings.headers[1].header, w.settings.headers[2].header })
        assert.equal(2, #w.settings.headers)
        for _, h in ipairs(w.settings.headers) do assert.is_true(#h.tooltip > 0) end
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
    it("Bar rows follow Placement; Frame tick colour only on the player frame", function()
        local w = start({})
        slash("mode bar")
        assert.is_true(shown(w, "SPC_BAR_BARCOLOR") and shown(w, "SPC_BAR_BARSTYLE"))
        local opts = w.settings.controls.SPC_BAR_TICKCOLOR.optsFn
        assert.equal(4, #opts())
        w.settings.settings.SPC_BAR_PLACEMENT:SetValue(2)
        assert.is_false(shown(w, "SPC_BAR_BARSTYLE"))
        assert.is_true(shown(w, "SPC_BAR_BARCOLOR")) -- colours the floating fill too
        assert.is_true(shown(w, "SPC_BAR_WIDTH") and shown(w, "SPC_BAR_TEXTURE") and shown(w, "SPC_BAR_TEXTPOS"))
        assert.equal(3, #opts())
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
            slash("ticks off"); slash("bartext off"); slash("tickcolor black"); slash("barcolor rage"); slash("dark dark")
            local bar = ShiftingPowerCountDB.bar
            assert.same({ false, false, 2, 3, 3 }, { bar.ticks, bar.barText, bar.tickColor, bar.barColor, bar.barStyle }, mode)
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

describe("Personal Resource Display tick style", function()
    local function shown(host)
        local r = {}
        for _, t in ipairs(rawget(host, "textures") or {}) do
            if rawget(t, "size") and not rawget(t, "hidden") and (rawget(t, "texture") or rawget(t, "atlas") or rawget(t, "color4")) then
                r[#r + 1] = t
            end
        end
        return r
    end
    local function near(a, b) return math.abs(a - b) < 1e-9 end

    it("defaults to Border: a 2px slice of the PRD bar's border art at the row's height, no edges", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        assert.equal(4, ShiftingPowerCountDB.prdTickStyle)
        local t = shown(w.prdHost)
        assert.equal(4, #t) -- cores only: the 1px edges stay hidden
        assert.equal(6704514, t[1].texture)
        assert.same({ 2, 10 }, t[1].size)
        local c = t[1].texcoord -- atlas columns 0..2 of 132, rows 3..12 of 19
        for i, want in ipairs({ 0.1, 0.102, 0.03, 0.12 }) do assert.is_true(near(c[i], want), "texcoord " .. i) end
    end)
    it("Pip uses Blizzard's Cooldown Manager pip at the row's height", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        slash("prdtickstyle pip")
        local t = shown(w.prdHost)
        assert.equal(4, #t)
        assert.equal("UI-HUD-CoolDownManager-Bar-Pip", t[1].atlas)
        assert.is_true(near(t[1].size[1], 100 / 23) and t[1].size[2] == 10)
    end)
    it("colour styles are plain 2px lines, no edges; the bar's tick colour no longer drives the PRD", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        slash("prdtickstyle black")
        slash("mode bar"); slash("tickcolor yellow")
        local t = shown(w.prdHost)
        assert.equal(4, #t) -- one line per tick, nothing beside it
        assert.same({ 2, 10 }, t[1].size)
        assert.same({ 0, 0, 0, 0.9 }, t[1].color4)
        assert.equal(4, #rawget(w.prdHost, "textures")) -- no edge textures exist at all
        assert.is_table(w.settings.controls.SPC_PRDTICKSTYLE)
    end)
    it("switching back from Pip to Border clears the atlas look", function()
        local w = start({ cost = 400, max = 2000, prd = { 200, 10 } })
        slash("prdtickstyle pip"); slash("prdtickstyle border")
        local t = shown(w.prdHost)
        assert.equal(6704514, t[1].texture)
        assert.same({ 2, 10 }, t[1].size)
    end)
end)
