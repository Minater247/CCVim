return {
    id = "api.treesitter.supported_lua",
    description = "Ports public Treesitter start/capture behavior for supported lua against Neovim reference semantics.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "treesitter supported lua parity", [[
            local function find_capture(items, wanted)
                for i = 1, #items do
                    if items[i].capture == wanted then
                        return true
                    end
                end
                return false
            end

            vim.o.swapfile = false

            local line = "local function foo(x) return x end"
            local foo_col = assert(string.find(line, "foo", 1, true)) - 1

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
            vim.bo.filetype = "lua"

            local parser = vim.treesitter.get_parser(0, "lua", { error = false })
            if parser then
                parser:parse(true)
            end

            local start_ok, start_result = pcall(function()
                return vim.treesitter.start(0, "lua")
            end)

            if parser then
                parser:parse(true)
            end

            local caps_local = vim.treesitter.get_captures_at_pos(0, 0, 0)
            local caps_foo = vim.treesitter.get_captures_at_pos(0, 0, foo_col)

            return {
                parser ~= nil,
                start_ok,
                start_result == nil,
                tostring(start_result or ""),
                find_capture(caps_local, "keyword"),
                find_capture(caps_foo, "function"),
            }
        ]])

        Assert.eq("lua parser exists", result[1], true)
        Assert.eq("lua start succeeds", result[2], true)
        Assert.eq("lua start returns nil", result[3], true)
        Assert.eq("lua start has no extra return value", result[4], "")
        Assert.eq("lua keyword capture found", result[5], true)
        Assert.eq("lua function capture found", result[6], true)
    end,
}
