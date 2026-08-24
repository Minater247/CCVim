return {
    id = "runtime.qall_command",
    description = "Ports :qa as the :qall abbreviation, including modified-buffer refusal and forced editor-loop termination.", -- luacheck: ignore 631

    run = function(ctx)
        local refusal = ctx.assert.eval_block(ctx.backend, ":qa modified-buffer parity", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "modified" })
            local ok, err = pcall(vim.cmd, "qa")
            return { ok, tostring(err or ""), vim.bo.modified }
        ]])
        ctx.assert.eq(":qa refuses a modified buffer", refusal[1], false)
        ctx.assert.top_error_code(":qa refusal uses E37", refusal[2], "E37")
        ctx.assert.eq(":qa refusal preserves the modified buffer", refusal[3], true)

        if ctx.backend.name == "lua_editor" then
            local forced = ctx.assert.eval_block(ctx.backend, ":qa! terminates the editor loop", [[
                local events = {}
                vim.api.nvim_create_autocmd("QuitPre", {
                    callback = function(args) events[#events + 1] = args.event end,
                })
                vim.cmd("qa!")
                return events
            ]])
            ctx.assert.deep_eq(":qa! fires QuitPre and terminates", forced, { "QuitPre" })
        end
    end,
}
