return {
    id = "runtime.enew_redir",
    description = "Ports enew and redir behavior through real Ex execution and editor-visible files.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local current_name = Assert.temp_path(backend, "enew-current", ".txt")
        local redir_file = Assert.temp_path(backend, "redir-file", ".txt")
        Assert.write_file(backend, redir_file, "old\n")

        local result = Assert.eval_block(backend, "enew and redir scenarios", string.format([[
            vim.o.hidden = false
            vim.o.autowriteall = false

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.bo.modified = true
            local enew_ok, enew_err = pcall(vim.cmd, "enew")

            vim.o.fileformats = "dos,unix"
            vim.cmd("enew!")
            local bang_name = vim.fn.bufname("%%")
            local bang_ff = vim.bo.fileformat

            vim.o.fileformats = ""
            vim.bo.fileformat = "mac"
            vim.cmd("enew!")
            local empty_ff = vim.bo.fileformat

            vim.g.redir_var = nil
            vim.cmd([=[
redir => g:redir_var
echo "alpha"
echon "beta"
redir END
]=])

            vim.g.redir_one = nil
            vim.g.redir_two = nil
            vim.cmd([=[
redir => g:redir_one
echo "one"
redir => g:redir_two
echo "two"
redir END
]=])

            local file_ok, file_err = pcall(vim.cmd, "redir > " .. vim.fn.fnameescape(%q))

            vim.cmd("redir! > " .. vim.fn.fnameescape(%q))
            vim.cmd("echo 'fresh'")
            vim.cmd("redir END")
            local file_lines = vim.fn.readfile(%q)

            vim.cmd([=[
redir @a
echo "x"
redir END
redir @A
echo "y"
redir END
]=])

            return {
                enew_ok,
                tostring(enew_err or ""),
                bang_name,
                bang_ff,
                empty_ff,
                vim.g.redir_var,
                vim.g.redir_one,
                vim.g.redir_two,
                file_ok,
                tostring(file_err or ""),
                file_lines,
                vim.fn.getreg("a"),
                vim.fn.getreg("a", 1, 1),
            }
        ]], current_name, redir_file, redir_file, redir_file))

        Assert.eq("enew without bang fails on modified named buffer", result[1], false)
        Assert.top_error_code("enew without bang uses E37", result[2], "E37")
        Assert.eq("enew! creates unnamed buffer", result[3], "")
        Assert.eq("enew! uses first fileformats entry", result[4], "dos")
        Assert.eq("enew! with empty fileformats falls back to Neovim default", result[5], "unix")
        Assert.eq("redir captures echo and echon", result[6], "\nalphabeta")
        Assert.eq("first redir target closes on retarget", result[7], "\none")
        Assert.eq("second redir target receives later output", result[8], "\ntwo")
        Assert.eq("redir > existing file fails", result[9], false)
        Assert.top_error_code("redir > existing file uses E189", result[10], "E189")
        Assert.table_eq("redir! overwrites file", result[11], { "", "fresh" })
        Assert.eq("redir register text appends", result[12], "\nx\ny")
        Assert.table_eq("redir register list appends", result[13], { "", "x", "y" })
    end,
}
