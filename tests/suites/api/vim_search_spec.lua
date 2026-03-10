return {
    id = "api.vim_search",
    description = "Ports search() behavior for flags, wrapping, stopline, skip, and error cases.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.fn.search scenarios", [[
            local function set_lines(lines)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            end

            local function set_pos(line, col1)
                vim.api.nvim_win_set_cursor(0, { line, col1 - 1 })
            end

            local function get_pos()
                local pos = vim.api.nvim_win_get_cursor(0)
                return { pos[1], pos[2] + 1 }
            end

            set_lines({ "alpha", "beta foo", "foo gamma", "omega" })

            set_pos(1, 1)
            local forward = vim.fn.search("foo")
            local pos_forward = get_pos()

            set_pos(1, 1)
            local no_move = vim.fn.search("foo", "n")
            local pos_no_move = get_pos()

            set_pos(2, 6)
            local skip_current = vim.fn.search("foo", "n")
            local keep_current = vim.fn.search("foo", "nc")

            set_pos(3, 1)
            local backward_no_wrap = vim.fn.search("foo", "bnW")

            set_pos(4, 1)
            local wrap_default = vim.fn.search("foo", "n")
            local wrap_disabled = vim.fn.search("foo", "nW")

            set_pos(1, 1)
            local stopline_before = vim.fn.search("foo", "n", 1)
            local stopline_match = vim.fn.search("foo", "n", 2)

            set_pos(1, 1)
            local end_match = vim.fn.search("foo", "e")
            local pos_end_match = get_pos()

            set_pos(4, 1)
            local nomagic_anchor = vim.fn.search("^\\Momega", "n")

            set_lines({ "one", "two", "three", "four", "five" })
            set_pos(2, 1)
            vim.cmd("normal! zt")
            pcall(vim.cmd, "redraw")
            set_pos(4, 1)
            local winline = vim.fn.winline()

            set_lines({ "alpha", "beta foo", "foo gamma", "omega" })

            set_pos(1, 1)
            local skip_fn = vim.fn.search("foo", "n", 0, 0, function()
                return vim.fn.line(".") == 2
            end)
            local pos_skip_fn = get_pos()

            set_pos(1, 1)
            local skip_err_ok, skip_err_msg = pcall(function()
                return vim.fn.search("foo", "n", 0, 0, function()
                    error("boom")
                end)
            end)

            local ok_extra, err_extra = pcall(function()
                return vim.fn.search("foo", "", 0, 0, nil, "extra")
            end)

            return {
                forward,
                pos_forward,
                no_move,
                pos_no_move,
                skip_current,
                keep_current,
                backward_no_wrap,
                wrap_default,
                wrap_disabled,
                stopline_before,
                stopline_match,
                end_match,
                pos_end_match,
                nomagic_anchor,
                winline,
                skip_fn,
                pos_skip_fn,
                skip_err_ok,
                tostring(skip_err_msg),
                ok_extra,
                tostring(err_extra),
            }
        ]])

        Assert.eq("forward finds first hit", result[1], 2)
        Assert.table_eq("forward moves cursor", result[2], { 2, 6 })
        Assert.eq("n flag returns match line", result[3], 2)
        Assert.table_eq("n flag keeps cursor", result[4], { 1, 1 })
        Assert.eq("without c skips current match", result[5], 3)
        Assert.eq("with c accepts current match", result[6], 2)
        Assert.eq("backward no-wrap finds previous", result[7], 2)
        Assert.eq("default wrap finds from top", result[8], 2)
        Assert.eq("W disables wrap", result[9], 0)
        Assert.eq("stopline limits forward search", result[10], 0)
        Assert.eq("stopline includes matching line", result[11], 2)
        Assert.eq("e flag moves to matching line", result[12], 2)
        Assert.table_eq("e flag moves to end of match", result[13], { 2, 8 })
        Assert.eq("search handles \\M mode marker", result[14], 4)
        Assert.eq("winline returns cursor row in window", result[15], 3)
        Assert.eq("skip function skips first hit", result[16], 3)
        Assert.table_eq("skip function keeps cursor with n", result[17], { 1, 1 })
        Assert.eq("skip callback error raises", result[18], false)
        Assert.truthy("skip callback error includes message", result[19]:find("boom", 1, true) ~= nil, result[19])
        Assert.eq("too many args throws", result[20], false)
        Assert.top_error_code("too many args throws E118", result[21], "E118")
    end,
}
