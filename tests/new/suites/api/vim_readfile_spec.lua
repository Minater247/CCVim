return {
    id = "api.vim_readfile",
    description = "Ports readfile() builtin coverage from old tests without fs stubs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "readfile scenarios", [[
            local function unique_path(prefix, ext)
                ext = ext or ""
                local seed = tostring(os.time()) .. "-" .. tostring(math.floor((os.clock() or 0) * 1000000))
                local n = 0
                while true do
                    local suffix = (n == 0) and "" or ("-" .. tostring(n))
                    local candidate = "/tmp/" .. prefix .. "-" .. seed .. suffix .. ext
                    if vim.fn.isdirectory(candidate) == 0 and vim.fn.filereadable(candidate) == 0 then
                        return candidate
                    end
                    n = n + 1
                end
            end

            local path = unique_path("vim-readfile-spec", ".txt")
            local missing = path .. ".missing"

            local function write_lines(file_path, lines)
                if fs and fs.open then
                    local h = assert(fs.open(file_path, "w"))
                    for i = 1, #lines do
                        h.writeLine(lines[i])
                    end
                    h.close()
                    return
                end
                vim.fn.writefile(lines, file_path)
            end

            write_lines(path, { "alpha", "beta", "mu", "nu" })

            local plain = vim.fn.readfile(path)
            local max2 = vim.fn.readfile(path, "", 2)
            local tail2 = vim.fn.readfile(path, "", -2)
            local zero = vim.fn.readfile(path, "", 0)
            local missing_ok, missing_err = pcall(vim.fn.readfile, missing)

            return { plain, max2, tail2, zero, missing_ok, tostring(missing_err or "") }
        ]])

        Assert.table_eq("readfile plain", result[1], { "alpha", "beta", "mu", "nu" })
        Assert.table_eq("readfile max positive", result[2], { "alpha", "beta" })
        Assert.table_eq("readfile max negative", result[3], { "mu", "nu" })
        Assert.table_eq("readfile max zero", result[4], {})
        Assert.eq("readfile missing raises", result[5], false)
        Assert.truthy("readfile missing uses E484", result[6]:find("E484", 1, true) ~= nil, result[6])
    end,
}
