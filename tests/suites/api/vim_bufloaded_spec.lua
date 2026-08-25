return {
    id = "api.vim_bufloaded",
    description = "Ports bufloaded() coverage to real buffer state instead of mock tables.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "bufloaded scenarios", [[
            local function unique_path(prefix, ext)
                ext = ext or ""
                local seed = tostring(os.time()) .. "-" .. tostring(math.floor((os.clock() or 0) * 1000000))
                return "/tmp/" .. prefix .. "-" .. seed .. ext
            end

            local loaded_path = unique_path("vim-bufloaded-loaded", ".txt")
            local unloaded_path = unique_path("vim-bufloaded-unloaded", ".txt")
            local missing_path = unique_path("vim-bufloaded-missing", ".txt")

            local loaded = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_name(loaded, loaded_path)

            local unloaded = vim.fn.bufadd(unloaded_path)

            local number_loaded = vim.fn.bufloaded(loaded)
            local number_unloaded = vim.fn.bufloaded(unloaded)
            local number_missing = vim.fn.bufloaded(999999)

            local name_loaded = vim.fn.bufloaded(loaded_path)
            local name_unloaded = vim.fn.bufloaded(unloaded_path)
            local name_missing = vim.fn.bufloaded(missing_path)

            local alt_before = vim.fn.bufloaded(0)
            vim.cmd("buffer " .. tostring(unloaded))
            local number_loaded_after_switch = vim.fn.bufloaded(unloaded)
            local alt_after = vim.fn.bufloaded(0)

            local invalid_ok, invalid_value = pcall(vim.fn.bufloaded, {})

            return {
                number_loaded,
                number_unloaded,
                number_missing,
                name_loaded,
                name_unloaded,
                name_missing,
                alt_before,
                number_loaded_after_switch,
                alt_after,
                invalid_ok,
                invalid_value,
            }
        ]])

        Assert.eq("bufloaded number loaded", result[1], 1)
        Assert.eq("bufloaded number unloaded", result[2], 0)
        Assert.eq("bufloaded number missing", result[3], 0)
        Assert.eq("bufloaded name loaded", result[4], 1)
        Assert.eq("bufloaded name unloaded", result[5], 0)
        Assert.eq("bufloaded name missing", result[6], 0)
        Assert.eq("bufloaded alt before switch", result[7], 0)
        Assert.eq("bufloaded switched buffer becomes loaded", result[8], 1)
        Assert.eq("bufloaded alt after switch", result[9], 1)
        Assert.eq("bufloaded invalid arg does not error", result[10], true)
        Assert.eq("bufloaded invalid arg returns 0", result[11], 0)
    end,
}
