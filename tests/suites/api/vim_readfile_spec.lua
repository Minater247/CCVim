return {
    id = "api.vim_readfile",
    description = "Ports readfile() builtin coverage from old tests without fs stubs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local path = Assert.temp_path(backend, "vim-readfile-spec", ".txt")
        local missing = path .. ".missing"
        local tutor_path = Assert.temp_path(backend, "vim-readfile-tutor-case", ".tutor")
        local metadata_path = tutor_path .. ".json"
        local bom = string.char(239, 187, 191)

        Assert.write_file(backend, path, bom .. "alpha\r\nbeta\nmu\0nu\n")
        Assert.write_file(backend, tutor_path, "")
        Assert.write_file(backend, metadata_path, "{\n  \"title\": \"Tutor\"\n}\n")

        local result = Assert.eval_block(backend, "readfile scenarios", string.format([=[
            local function same_list(a, b)
                if #a ~= #b then
                    return false
                end
                for i = 1, #a do
                    if a[i] ~= b[i] then
                        return false
                    end
                end
                return true
            end

            local plain = vim.fn.readfile(%q)
            local binary = vim.fn.readfile(%q, "b")
            local max2 = vim.fn.readfile(%q, "", 2)
            local tail2 = vim.fn.readfile(%q, "", -2)
            local zero = vim.fn.readfile(%q, "", 0)
            local missing_ok, missing_err = pcall(vim.fn.readfile, %q)

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.cmd("let b:tutor_metadata = json_decode(join(readfile(expand('%%').'.json'), \"\\n\"))")

            return {
                plain,
                binary,
                max2,
                tail2,
                zero,
                missing_ok,
                tostring(missing_err or ""),
                vim.b.tutor_metadata.title,
                same_list(plain, { "alpha", "beta", "mu", "nu" }),
                same_list(binary, { "%salpha\r", "beta", "mu", "nu", "" }),
                same_list(tail2, { "mu", "nu" }),
            }
        ]=], path, path, path, path, path, missing, tutor_path, bom))

        Assert.table_eq("readfile plain", result[1], { "alpha", "beta", "mu\nnu" })
        Assert.table_eq("readfile binary", result[2], { "<feff>alpha\r", "beta", "mu\nnu", "" })
        Assert.table_eq("readfile max positive", result[3], { "alpha", "beta" })
        Assert.table_eq("readfile max negative", result[4], { "beta", "mu\nnu" })
        Assert.table_eq("readfile max zero", result[5], {})
        Assert.eq("readfile missing raises", result[6], false)
        Assert.top_error_code("readfile missing uses E484", result[7], "E484")
        Assert.eq("readfile tutor metadata path works", result[8], "Tutor")
        Assert.eq("readfile plain is not the old split-on-NUL expectation", result[9], false)
        Assert.eq("readfile binary is not the old byte-splitting expectation", result[10], false)
        Assert.eq("readfile negative max is not the old tail expectation", result[11], false)
    end,
}
