return {
    id = "runtime.error_string_parity",
    description = "Matches complete Neovim error strings for representative expression, function, command, and type failures.", -- luacheck: ignore 631

    run = function(ctx)
        local Assert = ctx.assert
        local result = Assert.eval_block(ctx.backend, "exact error strings", [=[
            local function capture(fn)
                local ok, err = pcall(fn)
                local message = tostring(err or "")
                return ok, message:match("E%d+:[^\n]*") or message
            end

            local cases = {
                function() vim.fn.eval("1 +") end,
                function() vim.cmd("call CcvimMissing()") end,
                function() vim.fn.hasmapto("x", "n", 0, 1) end,
                function() vim.cmd("augroup! ccvim_missing_probe") end,
                function() vim.cmd("2echo 1") end,
                function() vim.fn.eval("1 2") end,
                function() vim.cmd("echo 1.0 % 2") end,
                function() vim.cmd("let g:ccvim_probe=1 | let g:ccvim_probe.field=2") end,
            }
            local out = {}
            for i, fn in ipairs(cases) do
                local ok, message = capture(fn)
                out[i] = { ok, message }
            end
            return out
        ]=])

        local expected = {
            'E15: Invalid expression: "1 +"',
            "E117: Unknown function: CcvimMissing",
            "E118: Too many arguments for function: hasmapto",
            'E367: No such group: "ccvim_missing_probe"',
            "E481: No range allowed: 2echo 1",
            "E488: Trailing characters: 2",
            "E804: Cannot use '%' with Float",
            "E1203: Dot can only be used on a dictionary: g:ccvim_probe.field=2",
        }
        for i, message in ipairs(expected) do
            Assert.eq("case " .. i .. " fails", result[i][1], false)
            Assert.eq("case " .. i .. " exact message", result[i][2], message)
        end
    end,
}
