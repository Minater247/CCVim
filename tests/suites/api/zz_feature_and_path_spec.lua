return {
    id = "api.feature_and_path",
    description = "Validates generic Neovim feature-version comparisons and standard path coverage.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local mock = ctx.backend.mock
        local Fn = mock.loadModule("lib.luaapi.fn").fn

        local supported = {
            "nvim-0.7", "nvim-0.8.0", "nvim-0.11", "nvim-0.11.3",
        }
        for _, feature in ipairs(supported) do
            Assert.eq("supported " .. feature, Fn.has(feature), 1)
        end

        local unsupported = {
            "nvim-0.11.4", "nvim-0.12", "nvim-1.0.0", "nvim-0",
            "nvim-0.11.x", "nvim-0.11.3.1",
        }
        for _, feature in ipairs(unsupported) do
            Assert.eq("unsupported " .. feature, Fn.has(feature), 0)
        end

        Assert.eq("unrelated feature remains supported", Fn.has("syntax"), 1)
        Assert.eq("explicitly unavailable feature", Fn.has("win32"), 0)
        Assert.eq("unknown feature", Fn.has("not-a-real-feature"), 0)

        local root = mock.globals().ccvim_path
        Assert.eq("config path", Fn.stdpath("config"), root .. "/config")
        Assert.eq("data path", Fn.stdpath("data"), root .. "/data")
        Assert.eq("cache path", Fn.stdpath("cache"), root .. "/cache")
        Assert.eq("state path", Fn.stdpath("state"), root .. "/state")
        Assert.eq("log path", Fn.stdpath("log"), root .. "/log")
    end,
}
