return {
    id = "api.nvim_list_uis",
    description = "Checks builtin UI discovery and reserved stdio channel info for the local runtime.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_list_uis builtin tui metadata", [[
            local uis = vim.api.nvim_list_uis()
            local tty = nil
            for _, ui in ipairs(uis) do
                if ui.chan == 1 and ui.stdout_tty then
                    tty = ui
                    break
                end
            end

            local buf = vim.api.nvim_create_buf(false, true)
            local term_chan = vim.api.nvim_open_term(buf, {})

            return {
                uis = uis,
                tty = tty,
                width = screen.width,
                height = screen.height,
                depth = screen.color_depth(),
                stdio = vim.api.nvim_get_chan_info(1),
                current = vim.api.nvim_get_chan_info(0),
                stderr = vim.api.nvim_get_chan_info(vim.v.stderr),
                chans = vim.api.nvim_list_chans(),
                term_chan = term_chan,
                term_info = vim.api.nvim_get_chan_info(term_chan),
            }
        ]])

        Assert.eq("one builtin UI is exposed", #result.uis, 1)
        Assert.truthy("tty discovery loop finds builtin UI", result.tty ~= nil)
        Assert.eq("ui width tracks screen width", result.uis[1].width, result.width)
        Assert.eq("ui height tracks screen height", result.uis[1].height, result.height)
        Assert.eq("ui rgb mirrors color depth", result.uis[1].rgb, result.depth == "rgb")
        Assert.eq("ui chan is stdio", result.uis[1].chan, 1)
        Assert.eq("ui reports stdin tty", result.uis[1].stdin_tty, true)
        Assert.eq("ui reports stdout tty", result.uis[1].stdout_tty, true)

        Assert.eq("stdio channel id", result.stdio.id, 1)
        Assert.eq("stdio channel stream", result.stdio.stream, "stdio")
        Assert.eq("stdio channel mode", result.stdio.mode, "bytes")
        Assert.eq("stdio channel client name", result.stdio.client.name, "nvim-tui")
        Assert.eq("current channel resolves to stdio", result.current.id, 1)

        Assert.eq("v:stderr channel id", result.stderr.id, 2)
        Assert.eq("v:stderr stream", result.stderr.stream, "stderr")
        Assert.eq("v:stderr mode", result.stderr.mode, "bytes")

        Assert.truthy("term channel does not reuse stdio", result.term_chan > 2)
        Assert.eq("term channel id", result.term_info.id, result.term_chan)
        Assert.eq("term channel stream", result.term_info.stream, "job")
        Assert.eq("term channel mode", result.term_info.mode, "terminal")

        local chan_ids = {}
        for i = 1, #result.chans do
            chan_ids[result.chans[i].id] = true
        end
        Assert.eq("channel list includes stdio", chan_ids[1], true)
        Assert.eq("channel list includes stderr", chan_ids[2], true)
        Assert.eq("channel list includes term channel", chan_ids[result.term_chan], true)
    end,
}
