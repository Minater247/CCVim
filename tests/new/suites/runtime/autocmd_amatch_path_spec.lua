return {
    id = "runtime.autocmd_amatch_path",
    description = "Ports <amatch> path normalization for BufEnter and FileType without backend-specific stubs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local base = Assert.temp_path(backend, "autocmd-amatch-path", "")
        local dir_path = base .. "/tests"
        local file_path = dir_path .. "/README.md"

        Assert.ensure_dir(backend, dir_path)
        Assert.write_file(backend, file_path, "readme\n")

        local result = Assert.eval_block(backend, "autocmd <amatch> path scenarios", string.format([==[
            local function trim_trailing_slash(path)
                return tostring(path or ""):gsub("/+$", "")
            end

            local function netrw_file(curdir, fname)
                fname = tostring(fname or "")
                if fname:sub(1, 1) == "/" then
                    return fname
                end
                return vim.fn.simplify(tostring(curdir) .. "/" .. fname)
            end

            local old_cwd = vim.fn.getcwd()

            vim.cmd("lcd " .. vim.fn.fnameescape(%q))
            vim.cmd([=[
augroup AutocmdAmatchPathSpec
  autocmd!
  autocmd BufEnter * let g:probe_amatch = expand('<amatch>')
  autocmd FileType * let g:probe_ft_amatch = expand('<amatch>')
augroup END
]=])

            vim.cmd("edit ./tests")

            local probe_amatch = trim_trailing_slash(vim.g.probe_amatch)
            local expected_amatch = trim_trailing_slash(vim.fn.fnamemodify("./tests", ":p"))
            local expected_file = trim_trailing_slash(vim.fn.fnamemodify("./tests/README.md", ":p"))

            vim.cmd("doautocmd FileType lua")
            local filetype_amatch = vim.g.probe_ft_amatch

            vim.cmd("doautocmd FileType netrw")
            local doauto_filetype_amatch = vim.g.probe_ft_amatch

            local legacy_match = vim.fn.glob("./tests/*", 0, 1, 1)[1]
            local fixed_match = vim.fn.glob(probe_amatch .. "/*", 0, 1, 1)[1]

            local legacy_path = netrw_file("./tests", legacy_match)
            local fixed_path = netrw_file(probe_amatch, fixed_match)

            vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))

            return {
                probe_amatch,
                expected_amatch,
                filetype_amatch,
                doauto_filetype_amatch,
                legacy_path,
                fixed_path,
                expected_file,
            }
        ]==], base))

        Assert.eq("BufEnter <amatch> is absolute path", result[1], result[2])
        Assert.eq("FileType <amatch> stays filetype", result[3], "lua")
        Assert.eq("doautocmd FileType keeps <amatch> as filetype", result[4], "netrw")
        Assert.eq("legacy relative curdir reproduces doubled path", result[5], "./tests/tests/README.md")
        Assert.eq("absolute curdir avoids doubled path", result[6], result[7])
    end,
}
