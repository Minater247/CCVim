return {
    id = "api.require_bit",
    description = "Ports require('bit') preload behavior through public Lua require/package state.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "require bit scenarios", [[
            local bitmod = require("bit")
            local bitmod_again = require("bit")
            return {
                bitmod == package.loaded.bit,
                bitmod_again == bitmod,
                bitmod.band(6, 3),
                bitmod.bor(4, 1),
                bitmod.tohex(255),
            }
        ]])

        Assert.eq("require('bit') matches package.loaded.bit", result[1], true)
        Assert.eq("second require('bit') returns same table", result[2], true)
        Assert.eq("bit.band works", result[3], 2)
        Assert.eq("bit.bor works", result[4], 5)
        Assert.eq("bit.tohex works", result[5], "000000ff")
    end,
}
