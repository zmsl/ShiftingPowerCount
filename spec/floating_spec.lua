local F = dofile("spec/fake.lua")

local function start(o) local w = F.install(o); F.fire("PLAYER_LOGIN"); return w end
local function slash(msg) SlashCmdList.SHIFTINGPOWERCOUNT(msg) end
local function floating(o) local w = start(o or {}); slash("mode bar"); slash("placement floating"); return w end

-- The 2px tick cores of a host: x of the tick centre, and the core's size.
local function ticksOf(host)
    local xs, sizes = {}, {}
    for _, t in ipairs(rawget(host, "textures") or {}) do
        if rawget(t, "color4") and rawget(t, "size") and t.size[1] == 2 and not rawget(t, "hidden") then
            xs[#xs + 1] = t.point[4] + 1
            sizes[#sizes + 1] = t.size
        end
    end
    return xs, sizes
end

describe("floating bar", function()
    it("placement floating shows a bar of width x height with ticks per cost", function()
        local w = floating({ cost = 400, max = 2000, mana = F.SECRET })
        assert.is_true(w.bar.hidden) -- the player-frame row is not shown
        assert.same({ 150, 12 }, w.floatBar.size)
        assert.same({ 0, 2000 }, { w.floatBar.min, w.floatBar.max })
        local xs, sizes = ticksOf(w.floatBar)
        assert.same({ 30, 60, 90, 120 }, xs)
        assert.same({ 2, 12 }, sizes[1])
        w.combat = true; F.tick()
        assert.equal(F.SECRET, w.floatBar.value)
        assert.equal(0, w.frame.alpha)
        for _, fs in ipairs(w.fs) do assert.equal(w.overlay, fs.parent) end
        assert.equal(w.floatBar, w.overlay.parent)
        assert.same({ 0, 0.55, 1 }, w.floatBar.statusColor)
    end)
    it("width and height apply live from the CLI and the panel", function()
        local w = floating()
        slash("width 200"); slash("height 20")
        assert.same({ 200, 20 }, w.floatBar.size)
        assert.same({ 40, 80, 120, 160 }, (ticksOf(w.floatBar)))
        w.settings.settings.SPC_BAR_WIDTH:SetValue(100)
        assert.equal(100, ShiftingPowerCountDB.bar.width)
    end)
    it("placement player with no PlayerFrame falls back to the floating bar", function()
        local w = start({ noPlayerFrame = true })
        slash("mode bar")
        assert.is_nil(w.bar)
        assert.is_table(w.floatBar)
        assert.is_false(w.floatBar.hidden)
        assert.matches("floating bar", w.printed)
        assert.equal(0, w.frame.alpha)
        for _, fs in ipairs(w.fs) do assert.equal(w.overlay, fs.parent) end
        assert.is_true(w.settings.buttons[1]:IsShown()) -- something floats: Reset is offered
    end)
    it("placement change in combat waits for combat end", function()
        local w = start({})
        slash("mode bar")
        w.combat = true
        slash("placement floating")
        assert.is_nil(w.floatBar)
        assert.is_false(w.bar.hidden)
        w.combat = false
        F.fire("PLAYER_REGEN_ENABLED")
        assert.is_false(w.floatBar.hidden)
        assert.is_true(w.bar.hidden)
    end)
    it("going back to the player frame hides the floating bar", function()
        local w = floating()
        slash("placement player")
        assert.is_true(w.floatBar.hidden)
        assert.is_false(w.bar.hidden)
        assert.equal(w.playerFrame, w.overlay.parent)
    end)
    it("with unknown max shows empty, no ticks", function()
        local w = floating({ max = 0 })
        assert.same({ 0, 1 }, { w.floatBar.min, w.floatBar.max })
        assert.same({}, (ticksOf(w.floatBar)))
        assert.has_no.errors(function() F.tick() end)
    end)
    it("hides outside Cat Form with the overlay", function()
        local w = floating()
        w.form = 5; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.same({ true, true }, { w.floatBar.hidden, w.overlay.hidden })
        w.form = 1; F.fire("UPDATE_SHAPESHIFT_FORM")
        assert.same({ false, false }, { w.floatBar.hidden, w.overlay.hidden })
    end)
    it("texture, background, border and count position apply", function()
        local w = floating()
        assert.equal("Interface\\TargetingFrame\\UI-StatusBar", w.floatBar.barTexture)
        slash("texture nothing here") -- unknown name: refused
        assert.equal("Blizzard", ShiftingPowerCountDB.bar.texture)
        ShiftingPowerCountDB.bar.texture = "Gone"; slash("bgalpha 0.2") -- name kept, default path rendered
        assert.equal("Gone", ShiftingPowerCountDB.bar.texture)
        assert.equal("Interface\\TargetingFrame\\UI-StatusBar", w.floatBar.barTexture)
        assert.equal(0.2, w.floatBar.textures[1].color4[4])
        local function hidden() local r = {}; for i = 2, 5 do r[#r + 1] = w.floatBar.textures[i].hidden end; return r end
        assert.same({ false, false, false, false }, hidden())
        slash("border off")
        assert.same({ true, true, true, true }, hidden())
        slash("pos left")
        for _, fs in ipairs(w.fs) do assert.same({ "LEFT", w.overlay, "LEFT", 2, 0 }, fs.point) end
        slash("pos below")
        assert.same({ "TOP", w.overlay, "BOTTOM", 0, -2 }, w.fs[1].point)
        slash("barcolor energy")
        assert.same({ 1, 0.85, 0.1 }, w.floatBar.statusColor)
    end)
    it("drag saves barPos; reset puts the floating bar back; lock stops dragging", function()
        local w = floating()
        local fb = w.floatBar
        function fb.StartMoving(s) s.moving = (rawget(s, "moving") or 0) + 1 end
        fb.scripts.OnDragStart(fb)
        assert.equal(1, fb.moving)
        fb.scripts.OnDragStop(fb)
        assert.same({ "CENTER", "CENTER", 0, 0 }, ShiftingPowerCountDB.barPos)
        slash("lock")
        fb.scripts.OnDragStart(fb)
        assert.equal(1, fb.moving)
        slash("reset")
        assert.is_nil(ShiftingPowerCountDB.barPos)
        assert.same({ "CENTER", UIParent, "CENTER", 0, -190 }, fb.point)
    end)
    it("Frame tick colour is White on the floating bar", function()
        local w = start({})
        slash("mode bar"); slash("tickcolor frame")
        assert.equal(4, ShiftingPowerCountDB.bar.tickColor)
        slash("placement floating")
        assert.equal(1, ShiftingPowerCountDB.bar.tickColor) -- the dropdown never shows blank
        ShiftingPowerCountDB.bar.tickColor = 4 -- a stored 4 still renders white
        slash("ticks on")
        local core
        for _, x in ipairs(w.floatBar.textures) do if rawget(x, "color4") and rawget(x, "size") and x.size[1] == 2 then core = x end end
        assert.same({ 1, 1, 1, 0.9 }, core.color4)
    end)
    it("a style write to another mode says which", function()
        local w = start({})
        slash("mode text"); slash("pos below")
        assert.matches("bar display", w.printed)
        w.printed = nil
        slash("fontsize 18")
        assert.is_nil(w.printed)
    end)
    it("old v1.0.0 textPos does not leak into the bar count position", function()
        F.install({}); _G.ShiftingPowerCountDB = { textPos = 3 }; F.fire("PLAYER_LOGIN")
        assert.same({ 3, 1 }, { ShiftingPowerCountDB.icon.textPos, ShiftingPowerCountDB.bar.textPos })
    end)

    it("the Display option is labelled Bar and its tooltip names Placement", function()
        local w = start({})
        local c = w.settings.controls.SPC_MODE
        assert.equal("Bar", c.opts[3].label)
        assert.is_nil(c.tip:find("Bar on player frame", 1, true))
        assert.matches("Placement", c.tip)
    end)
    it("in the fallback the floating bar's style rows are shown, not the player-frame-only ones", function()
        local w = start({ noPlayerFrame = true })
        slash("mode bar")
        local function shown(v) return w.settings.controls[v].init:IsShown() end
        assert.equal(1, ShiftingPowerCountDB.bar.placement)
        for _, v in ipairs({ "SPC_BAR_WIDTH", "SPC_BAR_HEIGHT", "SPC_BAR_TEXTURE", "SPC_BAR_BGALPHA", "SPC_BAR_BORDER", "SPC_BAR_TEXTPOS" }) do
            assert.is_true(shown(v), v)
        end
        assert.is_false(shown("SPC_BAR_BARSTYLE"))
    end)
    it("a locked floating bar does not capture the mouse; unlocked does", function()
        local w = floating()
        slash("lock")
        assert.is_false(w.floatBar.mouse)
        slash("unlock")
        assert.is_true(w.floatBar.mouse)
        slash("lock")
        local w2 = start({}); slash("lock"); slash("mode bar"); slash("placement floating")
        assert.is_false(w2.floatBar.mouse) -- created after the lock
    end)
    it("tickcolor frame is refused on Floating with a reason", function()
        local w = floating()
        slash("tickcolor frame")
        assert.matches("player frame", w.printed)
        assert.equal(1, ShiftingPowerCountDB.bar.tickColor)
        slash("tickcolor black")
        assert.equal(2, ShiftingPowerCountDB.bar.tickColor)
    end)
    it("reset with the player-frame row shown says there is nothing to move", function()
        local w = start({})
        slash("mode bar")
        ShiftingPowerCountDB.pos = { "TOP", "TOP", 5, 5 }
        slash("reset")
        assert.matches("nothing to move", w.printed)
        assert.is_table(ShiftingPowerCountDB.pos)
    end)
end)
