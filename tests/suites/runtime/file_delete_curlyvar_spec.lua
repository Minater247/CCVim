return {
    id = "runtime.file_delete_curlyvar",
    description = "Ports file, delete, curly-var, and drop behavior through real Ex execution.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local curly_script = Assert.temp_path(backend, "curly-var-probe", ".vim")
        local drop_target = Assert.temp_path(backend, "drop target", ".txt")

        Assert.write_file(backend, curly_script, [[
execute "let s:netrwmarkfilemtch_" .. bufnr('%') .. " = 'match'"
let g:curly_var_probe = exists("s:netrwmarkfilemtch_{bufnr('%')}") && s:netrwmarkfilemtch_{bufnr('%')} != ""
]])

        local code = [[
            local function set_lines(lines)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
            end

            set_lines({ "alpha", "beta", "gamma" })
            vim.cmd("file /tmp/original.txt")
            vim.cmd("file .")
            local file_dot = {
                vim.fn.bufname("%"),
                vim.fn.bufname("#"),
            }

            set_lines({ "line" })
            vim.cmd("file /tmp/original.txt")
            vim.cmd("0file")
            local file_zero = {
                vim.fn.bufname("%"),
                vim.fn.bufname("#"),
            }

            set_lines({})
            local longname = "/tmp/" .. string.rep("very_long_segment_", 8) .. ".txt"
            vim.cmd("file " .. vim.fn.fnameescape(longname))
            vim.o.shortmess = "t"
            vim.cmd("redir => g:file_status_short")
            vim.cmd("silent file")
            vim.cmd("redir END")
            vim.cmd("redir => g:file_status_full")
            vim.cmd("silent file!")
            vim.cmd("redir END")

            set_lines({ "one", "two", "three", "four" })
            vim.fn.setreg('"', { "kept" }, "l")
            vim.fn.setreg("1", { "old1" }, "l")
            vim.cmd("delete 2")
            local delete_count = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.fn.getreg('"', 1, 1),
                vim.fn.getreg("1", 1, 1),
            }

            set_lines({ "red", "blue", "green" })
            vim.fn.setreg("1", { "keep-numbered" }, "l")
            vim.cmd("delete a 2")
            local delete_named = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.fn.getreg("a", 1, 1),
                vim.fn.getreg("1", 1, 1),
            }

            set_lines({ "one", "two", "three" })
            vim.fn.setreg('"', { "kept" }, "l")
            vim.cmd([=[%d _]=])
            local delete_blackhole = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.fn.getreg('"', 1, 1),
            }

            set_lines({ "gone", "\ta" })
            vim.cmd("redir => g:delete_print")
            vim.cmd("silent dp")
            vim.cmd("redir END")
            local delete_print = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.g.delete_print,
            }

            set_lines({ "gone", "\ta" })
            vim.cmd("redir => g:delete_list")
            vim.cmd("silent dell")
            vim.cmd("redir END")
            local delete_list = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.g.delete_list,
            }

            set_lines({ "x" })
            vim.cmd("source " .. vim.fn.fnameescape(__CURLY_SCRIPT__))
            local curly_probe = vim.g.curly_var_probe

            set_lines({ "x" })
            vim.g.drop_target = __DROP_TARGET__
            vim.cmd("execute 'drop ' . fnameescape(g:drop_target)")
            local drop_name = vim.fn.bufname("%")

            return {
                file_dot,
                file_zero,
                vim.g.file_status_short,
                vim.g.file_status_full,
                longname,
                delete_count,
                delete_named,
                delete_blackhole,
                delete_print,
                delete_list,
                curly_probe,
                drop_name,
            }
        ]]
        code = code:gsub("__CURLY_SCRIPT__", string.format("%q", curly_script), 1)
        code = code:gsub("__DROP_TARGET__", string.format("%q", drop_target), 1)

        local result = Assert.eval_block(backend, "file/delete/curlyvar scenarios", code)

        Assert.table_eq("file . renames current buffer and keeps alternate", result[1], { ".", "/tmp/original.txt" })
        Assert.table_eq("0file clears current name and keeps alternate", result[2], { "", "/tmp/original.txt" })
        Assert.truthy("file status truncates with shortmess t", result[3]:find("<", 1, true) ~= nil, result[3])
        Assert.truthy("file! status shows full name", result[4]:find(result[5], 1, true) ~= nil, result[4])

        Assert.table_eq("delete count removes two lines from cursor", result[6][1], { "three", "four" })
        Assert.table_eq("delete count updates unnamed register", result[6][2], { "one", "two" })
        Assert.table_eq("delete count updates numbered register", result[6][3], { "one", "two" })

        Assert.table_eq("delete named register removes lines", result[7][1], { "green" })
        Assert.table_eq("delete named register stores text", result[7][2], { "red", "blue" })
        Assert.table_eq("delete named register also rotates numbered register", result[7][3], { "red", "blue" })

        Assert.table_eq("blackhole delete leaves one empty line", result[8][1], { "" })
        Assert.table_eq("blackhole delete preserves unnamed register", result[8][2], { "kept" })

        Assert.table_eq("dp deletes current line", result[9][1], { "\ta" })
        Assert.eq("dp prints resulting current line", result[9][2], "\n        a\n")

        Assert.table_eq("dell deletes current line", result[10][1], { "\ta" })
        Assert.eq("dell lists resulting current line", result[10][2], "\n>       a\n")

        Assert.eq("curly-var expression resolves script-local name", result[11], 1)
        Assert.eq("drop + fnameescape preserves full target", result[12], drop_target)
    end,
}
