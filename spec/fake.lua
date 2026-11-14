-- Minimal fake WoW client for ShiftingPowerCount. A secret is a table: any arithmetic or comparison on it errors.
local F = {}
F.SECRET = setmetatable({}, { __index = function() error("indexed a secret") end })

function F.install(o)
    local w = { mana = o.mana or 0, max = o.max or 2000, cost = o.cost or 400,
        combat = false, known = o.known ~= false, shown = {}, fs = {} }
    F.w = w
    local function obj()
        local t = { scripts = {} }
        function t.SetAlpha(s, a) s.alpha = a end
        function t.SetScript(s, n, fn) s.scripts[n] = fn end
        function t.SetText(s, x) s.text = x end
        function t.GetText(s) return s.text end
        function t.Show(s) s.hidden = false end
        function t.Hide(s) s.hidden = true end
        function t.SetScale(s, x) s.scale = x end
        function t.SetFont(s, path, size, flags) s.font = { path, size, flags } end
        function t.SetTextColor(s, r, g, b) s.color = { r, g, b } end
        function t.ClearAllPoints(s) s.point = nil end
        function t.SetPoint(s, ...) s.point = { ... } end
        function t.SetTexture(s, x) s.texture = x; w.texture = x end
        function t.SetShown(s, v) s.shown = v; s.hidden = not v; w.shown[#w.shown + 1] = v end
        function t.SetVertexColor(s, r, g, b) s.vertex = { r, g, b }; s.vwrites = (rawget(s, "vwrites") or 0) + 1 end
        function t.GetVertexColor(s) local v = rawget(s, "vertex") or { 1, 1, 1 }; return v[1], v[2], v[3], 1 end
        function t.SetDesaturated(s, d) s.desat = d and true or false; s.dwrites = (rawget(s, "dwrites") or 0) + 1 end
        function t.IsDesaturated(s) return rawget(s, "desat") == true end
        function t.IsShown(s) return not rawget(s, "hidden") end
        function t.CreateFontString() local fs = obj(); w.fs[#w.fs + 1] = fs; return fs end
        function t.CreateTexture(s)
            local tx = obj()
            w.icon = w.icon or tx -- the floating frame's icon is the first texture created
            if not rawget(s, "textures") then s.textures = {} end
            s.textures[#s.textures + 1] = tx
            return tx
        end
        function t.SetColorTexture(s, ...) s.color4 = { ... } end
        function t.SetSize(s, a, b) s.size = { a, b } end
        function t.CreateMaskTexture() return obj() end
        function t.SetAtlas(s, name) s.atlas = name end
        function t.SetStatusBarTexture(s, x) s.barTexture = x end
        function t.SetMinMaxValues(s, a, b) s.min, s.max = a, b end
        function t.SetValue(s, v) s.value = v; s.values = (rawget(s, "values") or 0) + 1 end
        function t.SetFrameStrata(s, x) s.strata = x end
        function t.GetFrameStrata(s) return rawget(s, "strata") or "LOW" end
        function t.SetParent(s, p) s.parent = p end
        function t.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
        return setmetatable(t, { __index = function() return function() end end }) -- other widget methods: no-ops
    end
    w.boxes = {}
    w.form = o.form or 1 -- GetShapeshiftFormID: 1 = Cat Form
    _G.GetShapeshiftFormID = function() return w.form end
    _G.CreateFrame = function(kind, name, parent)
        local fr = obj()
        fr.parent = parent
        if kind == "EditBox" then w.boxes[#w.boxes + 1] = fr
        elseif kind == "StatusBar" then w.bar = fr
        elseif name == "ShiftingPowerCountOverlay" then w.overlay = fr
        else w.frame = fr end
        return fr
    end
    -- Stub of Blizzard's PlayerFrame: a shown Button in strata LOW with its container child.
    if o.noPlayerFrame then
        _G.PlayerFrame = nil
    else
        local pf = obj()
        pf.PlayerFrameContainer = {}
        if o.pfArt then pf.PlayerFrameContainer.AlternatePowerFrameTexture = obj(); pf.PlayerFrameContainer.FrameTexture = obj() end
        pf.strata = "LOW"
        function pf.IsShown() return w.pfShown ~= false end
        _G.PlayerFrame = pf
        w.playerFrame = pf
    end
    _G.UIParent = {}
    _G.hooksecurefunc = function(t, name, fn) -- post-hook: runs after the original, like the client's
        local orig = t[name]
        t[name] = function(...) local a, b = orig(...); fn(...); return a, b end
    end
    _G.C_AddOns = { IsAddOnLoaded = function(n) return n == "DarkMode" and o.darkMode == true end }
    -- Fake Settings API: records registrations; an addon setting writes its table and calls the callback on SetValue.
    local reg = { settings = {}, controls = {}, buttons = {} }
    w.settings = reg
    local setting = {}
    setting.__index = setting
    function setting:SetValueChangedCallback(fn) self.cb = fn end
    function setting:GetValue() return self.tbl[self.key] end
    function setting:SetValue(v) self.tbl[self.key] = v; if self.cb then self.cb(self, v) end end
    local category = { GetID = function() return 42 end }
    _G.Settings = {
        VarType = { Number = "Number", Boolean = "Boolean" }, Default = { True = true, False = false },
        RegisterVerticalLayoutCategory = function(name)
            category.name = name
            return category, { AddInitializer = function(_, i) reg.buttons[#reg.buttons + 1] = i end }
        end,
        RegisterAddOnCategory = function(c) reg.category = c end,
        RegisterAddOnSetting = function(_, var, key, tbl, vtype, name, default)
            if tbl[key] == nil then tbl[key] = default end
            local st = setmetatable({ var = var, key = key, tbl = tbl, name = name, vtype = vtype }, setting)
            reg.settings[key] = st
            return st
        end,
        CreateSliderOptions = function(lo, hi, step) return { lo = lo, hi = hi, step = step, SetLabelFormatter = function() end } end,
        CreateControlTextContainer = function()
            local c = { data = {} }
            function c:Add(v, label) self.data[#self.data + 1] = { value = v, label = label } end
            function c:GetData() return self.data end
            return c
        end,
        CreateSlider = function(_, st, o)
            local init = { InitFrame = function() end, Resetter = function() end } -- Blizzard's mixin defaults, overridden per instance
            reg.controls[st.key] = { kind = "slider", opts = o, init = init }
            return init
        end,
        CreateDropdown = function(_, st, fn) reg.controls[st.key] = { kind = "dropdown", opts = fn() } end,
        CreateCheckbox = function(_, st) reg.controls[st.key] = { kind = "checkbox" } end,
        OpenToCategory = function(id) reg.opened = id end,
    }
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
    _G.CreateSettingsButtonInitializer = function(name, text, click) return { name = name, text = text, click = click } end
    _G.Enum = { LuaCurveType = { Step = "Step" } }
    _G.C_CurveUtil = { CreateCurve = function()
        local c = { pts = {} }
        function c:SetType() end
        function c:ClearPoints() self.pts = {} end
        function c:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y }; table.sort(self.pts, function(a, b) return a[1] < b[1] end) end
        function c:Eval(x) local y = 0; for _, p in ipairs(self.pts) do if p[1] <= x then y = p[2] end end; return y end
        return c
    end }
    _G.UnitPower = function() return w.mana end
    _G.UnitPowerMax = function() return w.max end
    _G.UnitPowerPercent = function(_, _, _, curve)
        if w.mana == F.SECRET or w.max == F.SECRET then return curve and 0 or F.SECRET end -- client evaluates secrets itself
        if not curve then return F.SECRET end -- the real client: a plain percent read is secret even out of combat
        return curve:Eval(w.max == 0 and 0 or w.mana / w.max) -- input 0..1 (Blizzard CurveConstants.ScaleTo100)
    end
    _G.C_Spell = { GetSpellPowerCost = function() return { { type = 0, cost = w.cost } } end, GetSpellTexture = function() return 1 end }
    _G.C_SpellBook = { IsSpellKnown = function() return w.known end }
    _G.InCombatLockdown = function() return w.combat end
    _G.issecretvalue = function(v) return v == F.SECRET end
    _G.SlashCmdList = {}
    _G.print = function(...) w.printed = table.concat({ ... }, " ") end
    _G.ShiftingPowerCountDB = nil
    dofile("ShiftingPowerCount.lua")
    return w
end

function F.fire(ev) local f = F.w.frame; f.scripts.OnEvent(f, ev) end
function F.tick() local f = F.w.frame; f.scripts.OnUpdate(f, 1) end
function F.at(mana) F.w.mana = mana; F.tick(); return F.visible() end
function F.visible() local r = {}; for _, fs in ipairs(F.w.fs) do if fs.alpha == 1 then r[#r + 1] = fs.text end end; return r end
return F
