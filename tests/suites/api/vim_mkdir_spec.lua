return {
    id = "api.vim_mkdir",
    description = "Ports mkdir() builtin coverage from old tests without fs stubs.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "mkdir scenarios", [[
            local function unique_path(prefix)
                local seed = tostring(os.time()) .. "-" .. tostring(math.floor((os.clock() or 0) * 1000000))
                local n = 0
                while true do
                    local suffix = (n == 0) and "" or ("-" .. tostring(n))
                    local candidate = "/tmp/" .. prefix .. "-" .. seed .. suffix
                    if vim.fn.isdirectory(candidate) == 0 and vim.fn.filereadable(candidate) == 0 then
                        return candidate
                    end
                    n = n + 1
                end
            end

            local base = unique_path("vim-mkdir-spec")
            local nested = base .. "/a/b"

            local function call(fn, ...)
                local ok, rv = pcall(fn, ...)
                if ok then
                    return { ok = true, value = rv }
                end
                if type(rv) == "table" and type(rv.toString) == "function" then
                    return { ok = false, err = rv:toString() }
                end
                return { ok = false, err = tostring(rv) }
            end

            local r1 = call(vim.fn.mkdir, nested, "p", 448)
            local has_parent = vim.fn.isdirectory(base .. "/a")
            local has_child = vim.fn.isdirectory(nested)

            local r2 = call(vim.fn.mkdir, nested, "p")
            local r3 = call(vim.fn.mkdir, nested)

            local r4 = call(vim.fn.mkdir, base .. "/no-parent/x")
            local r5 = call(vim.fn.mkdir, base .. "/a/c")
            local has_sibling = vim.fn.isdirectory(base .. "/a/c")

            local file_path = base .. "/existing-file"
            vim.fn.writefile({ "x" }, file_path)
            local r6 = call(vim.fn.mkdir, file_path, "p")
            local r7 = call(vim.fn.mkdir, "")

            return { r1, has_parent, has_child, r2, r3, r4, r5, has_sibling, r6, r7 }
        ]])

        Assert.eq("mkdir -p ok", result[1].ok, true)
        Assert.eq("mkdir -p returns 1", result[1].value, 1)
        Assert.eq("mkdir -p made parent", result[2], 1)
        Assert.eq("mkdir -p made child", result[3], 1)
        Assert.eq("mkdir existing dir with -p ok", result[4].ok, true)
        Assert.eq("mkdir existing dir with -p returns 1", result[4].value, 1)

        Assert.eq("mkdir existing dir without -p fails", result[5].ok, false)
        Assert.top_error_code("mkdir existing dir uses E739", result[5].err, "E739")

        Assert.eq("mkdir without -p parent missing fails", result[6].ok, false)
        Assert.top_error_code("mkdir parent missing uses E739", result[6].err, "E739")

        Assert.eq("mkdir without -p with parent ok", result[7].ok, true)
        Assert.eq("mkdir without -p returns 1", result[7].value, 1)
        Assert.eq("mkdir without -p made child", result[8], 1)

        Assert.eq("mkdir file path fails", result[9].ok, false)
        Assert.top_error_code("mkdir file path uses E739", result[9].err, "E739")
        Assert.eq("mkdir empty path call succeeds", result[10].ok, true)
        Assert.eq("mkdir empty path returns 0", result[10].value, 0)
    end,
}
