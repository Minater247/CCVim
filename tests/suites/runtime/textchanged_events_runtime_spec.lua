return {
    id = "runtime.textchanged_events",
    description = "Ports the documented typeahead suppression for TextChanged and TextChangedI against public editor input.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "textchanged typeahead suppression", [[
            local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

            local function fresh(lines)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
                return vim.api.nvim_get_current_buf()
            end

            local function install_probe()
                local hits = { normal = 0, insert = 0, normal_buf = nil, insert_buf = nil }
                local group = vim.api.nvim_create_augroup("TextChangedTypeaheadSpec", { clear = true })
                vim.api.nvim_create_autocmd("TextChanged", {
                    group = group,
                    callback = function(info)
                        hits.normal = hits.normal + 1
                        hits.normal_buf = info.buf
                    end,
                })
                vim.api.nvim_create_autocmd("TextChangedI", {
                    group = group,
                    callback = function(info)
                        hits.insert = hits.insert + 1
                        hits.insert_buf = info.buf
                    end,
                })
                return hits
            end

            local normal_hits = install_probe()
            local normal_buf = fresh({ "x" })
            vim.api.nvim_feedkeys("x", "xt", false)
            vim.cmd("redraw")
            local normal_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            local insert_hits = install_probe()
            local insert_buf = fresh({ "x" })
            vim.api.nvim_feedkeys("a2" .. esc, "xt", false)
            vim.cmd("redraw")
            local insert_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            return {
                normal_hits,
                normal_buf,
                normal_lines,
                insert_hits,
                insert_buf,
                insert_lines,
            }
        ]])

        Assert.eq("typeahead normal path changes text", result[3][1], "")
        Assert.eq("TextChanged suppressed during typeahead", result[1].normal, 0)
        Assert.eq("TextChanged reports no bufnr when suppressed", result[1].normal_buf, nil)

        Assert.eq("typeahead insert path changes text", result[6][1], "x2")
        Assert.eq("TextChangedI suppressed during typeahead", result[4].insert, 0)
        Assert.eq("TextChangedI reports no bufnr when suppressed", result[4].insert_buf, nil)
    end,
}
