return {
    id = "runtime.highlight_list_render",
    description = "Renders :highlight and :syntax list entries with the group name unhighlighted and only the literal xxx segment highlighted; lua-editor-only because Neovim's public capture APIs do not expose message highlight segments.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local name_width = 14

        local result = Assert.eval_block(backend, "highlight list render segments", [[
            local ExMsg = loadModule("lib.excmd.exmsg")

            local function upvalue(fn, wanted)
                for i = 1, 20 do
                    local name, value = debug.getupvalue(fn, i)
                    if not name then
                        break
                    end
                    if name == wanted then
                        return value
                    end
                end
            end

            local displaymessages = upvalue(ExMsg.flush, "displaymessages")

            local function clear_messages()
                while #displaymessages > 0 do
                    table.remove(displaymessages)
                end
            end

            local function simplify(line)
                local out = {}
                for i = 1, #line do
                    out[i] = { line[i][1], line[i][2] }
                end
                return out
            end

            clear_messages()
            vim.cmd("highlight String")
            local hi_line = simplify(displaymessages[#displaymessages])

            clear_messages()
            vim.cmd("syntax clear")
            vim.cmd("syntax keyword TestSyn foo")
            vim.cmd("syntax list TestSyn")
            local syn_line = simplify(displaymessages[#displaymessages])

            return { hi_line, syn_line }
        ]])

        Assert.eq("highlight name uses normal text", result[1][1][1], "Normal")
        Assert.eq(
            "highlight name text includes separator space",
            result[1][1][2],
            string.format("%-" .. name_width .. "s ", "String")
        )
        Assert.eq("highlight xxx uses target group", result[1][2][1], "String")
        Assert.eq("highlight xxx text is separate", result[1][2][2], "xxx")
        Assert.eq("highlight suffix returns to normal", result[1][3][1], "Normal")
        Assert.eq("highlight suffix excludes xxx", result[1][3][2], " links to Constant")

        Assert.eq("syntax name uses normal text", result[2][1][1], "Normal")
        Assert.eq(
            "syntax name text includes separator space",
            result[2][1][2],
            string.format("%-" .. name_width .. "s ", "TestSyn")
        )
        Assert.eq("syntax xxx uses syntax group", result[2][2][1], "TestSyn")
        Assert.eq("syntax xxx text is separate", result[2][2][2], "xxx")
    end,
}
