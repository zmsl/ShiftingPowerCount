local F = dofile("spec/fake.lua")

local function start(o) local w = F.install(o); F.fire("PLAYER_LOGIN"); return w end

for _, scale in ipairs({ 1, 100 }) do
    describe("scale " .. scale, function()
        it("shows exactly one label per mana value", function()
            local w = start({ cost = 400, max = 2000, scale = scale })
            for mana, want in pairs({ [0] = 0, [399] = 0, [400] = 1, [799] = 1, [800] = 2, [1999] = 4, [2000] = 5 }) do
                assert.same({ want }, F.at(mana), "mana " .. mana)
            end
            assert.equal(31, #F.w.fs) -- labels 0..30 exist; bands above n are flat 0
        end)
        it("learns the scale out of combat even at ~1% mana", function()
            local w = start({ mana = 20, scale = scale, cost = 400, max = 2000 })
            assert.same({ 0 }, F.at(20))
            assert.same({ 1 }, F.at(400))
        end)
    end)
end

describe("rules", function()
    it("skips rebuild in combat", function()
        local w = start({})
        w.combat = true; w.cost = 100
        F.fire("SPELLS_CHANGED")
        assert.same({ 1 }, F.at(400)) -- still the cost-400 bands
    end)
    it("hides the frame with a plain boolean when the spell is unknown", function()
        local w = start({ known = false })
        assert.same({ false }, w.shown)
    end)
    it("does not error on cost<=0, max 0, or secret reads", function()
        for _, o in ipairs({ { cost = 0 }, { cost = -5 }, { max = 0 }, { mana = F.SECRET }, { max = F.SECRET } }) do
            assert.has_no.errors(function() local w = start(o); F.fire("SPELLS_CHANGED"); w.combat = true; F.tick() end)
        end
    end)
    it("keeps the last good scale when cur is 0 or secret", function()
        local w = start({ mana = 1000, scale = 100 })
        w.mana = 0; F.fire("SPELLS_CHANGED")
        w.mana = F.SECRET; F.fire("SPELLS_CHANGED")
        assert.same({ 1 }, F.at(400))
    end)
end)
