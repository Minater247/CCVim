return {
    id = "api.vim_bufadd",
    description = "Ports bufadd() coverage to real editor state.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "bufadd scenarios", [[
            local function unique_path(prefix, ext)
                ext = ext or ""
                local seed = tostring(os.time()) .. "-" .. tostring(math.floor((os.clock() or 0) * 1000000))
                return "/tmp/" .. prefix .. "-" .. seed .. ext
            end

            vim.cmd("enew!")

            local seen_bufadd = 0
            vim.api.nvim_create_autocmd("BufAdd", {
                callback = function()
                    seen_bufadd = seen_bufadd + 1
                end,
            })

            local a_path = unique_path("vim-bufadd-a", ".txt")
            local a = vim.fn.bufadd(a_path)
            local a2 = vim.fn.bufadd(a_path)
            local scratch = vim.fn.bufadd("")

            return {
                a,
                seen_bufadd,
                vim.fn.bufloaded(a),
                vim.fn.bufname(a),
                vim.fn.buflisted(a),
                a2,
                scratch,
                vim.fn.bufloaded(scratch),
                vim.fn.bufname(scratch),
                vim.fn.buflisted(scratch),
            }
        ]])

        Assert.truthy("bufadd created buffer", result[1] > 0, result[1])
        Assert.eq("bufadd does not fire BufAdd autocmd", result[2], 0)
        Assert.eq("bufadd creates unloaded buffer", result[3], 0)
        Assert.truthy("bufadd preserves name", result[4]:find("/tmp/vim%-bufadd%-a%-", 1) ~= nil, result[4])
        Assert.eq("bufadd creates unlisted buffer", result[5], 0)
        Assert.eq("bufadd existing name returns same bufnr", result[6], result[1])
        Assert.truthy("bufadd empty creates new buffer", result[7] ~= result[1], result[7])
        Assert.eq("bufadd empty is unloaded", result[8], 0)
        Assert.eq("bufadd empty has empty name", result[9], "")
        Assert.eq("bufadd empty is unlisted", result[10], 0)
    end,
}
