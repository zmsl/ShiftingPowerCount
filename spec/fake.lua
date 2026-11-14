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
        function t.SetTexture(s, x) s.texture = x; w.texture = x end
        function t.SetShown(s, v) s.shown = v; w.shown[#w.shown + 1] = v end
        function t.CreateFontString() local fs = obj(); w.fs[#w.fs + 1] = fs; return fs end
        function t.CreateTexture() return obj() end
        function t.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
        return setmetatable(t, { __index = function() return function() end end }) -- other widget methods: no-ops
    end
    _G.CreateFrame = function() w.frame = obj(); return w.frame end
    _G.UIParent = {}
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
    _G.print = function() end
    _G.ShiftingPowerCountDB = nil
    dofile("ShiftingPowerCount.lua")
    return w
end

function F.fire(ev) local f = F.w.frame; f.scripts.OnEvent(f, ev) end
function F.tick() local f = F.w.frame; f.scripts.OnUpdate(f, 1) end
function F.at(mana) F.w.mana = mana; F.tick(); return F.visible() end
function F.visible() local r = {}; for _, fs in ipairs(F.w.fs) do if fs.alpha == 1 then r[#r + 1] = fs.text end end; return r end
return F
