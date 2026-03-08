return {
    id = "api.vim_setreg",
    description = "Ports setreg() coverage through public register APIs and alternate-buffer state.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "setreg scenarios", [[
            local function unique_path(prefix, ext)
                ext = ext or ""
                local seed = tostring(os.time()) .. "-" .. tostring(math.floor((os.clock() or 0) * 1000000))
                return "/tmp/" .. prefix .. "-" .. seed .. ext
            end

            vim.cmd("enew!")

            local alt_path = unique_path("vim-setreg-alt", ".txt")
            local alt = vim.fn.bufadd(alt_path)

            local setreg_char = vim.fn.setreg("a", "hello")
            local reg_a_initial = vim.fn.getreg("a")
            local unnamed_initial = vim.fn.getreg('"')
            local reg_a_initial_list = vim.fn.getreg("a", 1, 1)

            local setreg_append = vim.fn.setreg("A", " world")
            local reg_a_appended = vim.fn.getreg("a")
            local unnamed_after_append = vim.fn.getreg('"')

            local setreg_line = vim.fn.setreg("b", { "one", "two" })
            local reg_b_text = vim.fn.getreg("b")
            local reg_b_list = vim.fn.getreg("b", 1, 1)
            local unnamed_after_line = vim.fn.getreg('"', 1, 1)

            local setreg_alt = vim.fn.setreg("#", alt)
            local alt_reg = vim.fn.bufnr("#")
            local alt_name = vim.fn.getreg("#")

            return {
                setreg_char,
                reg_a_initial,
                unnamed_initial,
                reg_a_initial_list,
                setreg_append,
                reg_a_appended,
                unnamed_after_append,
                setreg_line,
                reg_b_text,
                reg_b_list,
                unnamed_after_line,
                setreg_alt,
                alt,
                alt_reg,
                alt_name,
            }
        ]])

        Assert.eq("setreg charwise ok", result[1], 0)
        Assert.eq("setreg charwise stored", result[2], "hello")
        Assert.eq("setreg charwise does not touch unnamed", result[3], "")
        Assert.table_eq("setreg charwise list form", result[4], { "hello" })

        Assert.eq("setreg append ok", result[5], 0)
        Assert.eq("setreg append via uppercase merges", result[6], "hello world")
        Assert.eq("setreg append does not touch unnamed", result[7], "")

        Assert.eq("setreg linewise ok", result[8], 0)
        Assert.eq("setreg linewise text form", result[9], "one\ntwo\n")
        Assert.table_eq("setreg linewise list form", result[10], { "one", "two" })
        Assert.table_eq("setreg linewise does not touch unnamed", result[11], {})

        Assert.eq("setreg alt buffer ok", result[12], 0)
        Assert.eq("setreg alt buffer updates #", result[14], result[13])
        Assert.truthy("setreg alt buffer stores path", result[15]:find("/tmp/vim%-setreg%-alt%-", 1) ~= nil, result[15])
    end,
}
