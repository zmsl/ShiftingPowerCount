local F = dofile("spec/fake.lua")

local function start(o) local w = F.install(o); F.fire("PLAYER_LOGIN"); return w end
local function slash(msg) SlashCmdList.SHIFTINGPOWERCOUNT(msg) end

describe("options", function()
    it("applies defaults at login and registers the panel", function()
        local w = start({})
        local db = ShiftingPowerCountDB
        assert.same({ 1, 1, 0.35, true, false, 20 }, { db.mode, db.scale, db.iconAlpha, db.zeroRed, db.locked, db.fontSize })
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
        assert.is_true(ShiftingPowerCountDB.locked)
    end)
    it("size scales the frame, from the panel and from the CLI, the same DB field", function()
        local w = start({})
        w.settings.settings.scale:SetValue(1.7)
        assert.same({ 1.7, 1.7 }, { ShiftingPowerCountDB.scale, w.frame.scale })
        slash("size 2.5")
        assert.same({ 2.5, 2.5 }, { ShiftingPowerCountDB.scale, w.frame.scale })
        assert.equal(2.5, w.settings.settings.scale:GetValue()) -- panel follows the CLI
        slash("size 9")
        assert.equal(3, ShiftingPowerCountDB.scale) -- clamped
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
        slash("fontsize 33"); slash("outline thick"); slash("font arialn")
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
        assert.same({ 2.2, 2.2, "2.2" }, { ShiftingPowerCountDB.scale, w.frame.scale, box:GetText() })
    end)
    it("commits on losing focus too", function()
        local w = start({})
        local _, box = row(w, "fontSize")
        box:SetText("31"); box.scripts.OnEditFocusLost(box)
        assert.same({ 31, 31 }, { ShiftingPowerCountDB.fontSize, w.fs[1].font[2] })
    end)
    it("clamps to the slider range and rounds to its step", function()
        local w = start({})
        local _, scale = row(w, "scale")
        type_(scale, "9"); assert.equal(3, ShiftingPowerCountDB.scale)
        type_(scale, "-4"); assert.equal(0.5, ShiftingPowerCountDB.scale)
        type_(scale, "1.26"); assert.same({ 1.3, "1.3" }, { ShiftingPowerCountDB.scale, scale:GetText() })
        local _, size = row(w, "fontSize")
        type_(size, "20.6"); assert.equal(21, ShiftingPowerCountDB.fontSize)
        type_(size, "1000"); assert.equal(72, ShiftingPowerCountDB.fontSize)
        local _, a = row(w, "iconAlpha")
        type_(a, "0.37"); assert.equal(0.35, ShiftingPowerCountDB.iconAlpha)
    end)
    it("reverts invalid input and on Escape", function()
        local w = start({})
        local _, box = row(w, "scale")
        for _, bad in ipairs({ "abc", "", "nan", "inf", "1..2" }) do
            type_(box, bad)
            assert.same({ 1, "1" }, { ShiftingPowerCountDB.scale, box:GetText() }, bad)
        end
        box:SetText("2.5"); box.scripts.OnEscapePressed(box)
        assert.same({ 1, "1" }, { ShiftingPowerCountDB.scale, box:GetText() })
    end)
    it("slider and CLI changes update the box, both ways live", function()
        local w = start({})
        local frame, box = row(w, "scale")
        frame.SliderWithSteppers:SetValue(1.8) -- slider drag
        assert.equal("1.8", box:GetText())
        slash("size 2.4") -- CLI
        assert.equal("2.4", box:GetText())
        type_(box, "0.7") -- box
        assert.same({ 0.7, 0.7 }, { ShiftingPowerCountDB.scale, w.frame.scale })
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
