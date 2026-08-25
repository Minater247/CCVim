return {
    id = "api.lsp_lua_client_parity",
    description = "Runs CCVim's Lua LSP server through each editor's real LSP client and buffer lifecycle.",

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/api/") or "."
        local server = root .. "/lib/luaapi/lsp_lua.lua"
        local result = ctx.assert.eval_block(ctx.backend, "Lua LSP client", string.format([[
            vim.cmd("enew!")
            vim.bo.filetype = "lua"
            local bufnr = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_name(0, "/tmp/ccvim-lsp.lua")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "local function combine(left, right)",
                "  return left .. right",
                "end",
                "local apple = 1",
                "local result = app",
                "print(apple)",
                "combine(apple, result)",
                "local builtin = tab",
                "local member = table.in",
                "table.insert({}, 1, 'x')",
            })

            local lua_lsp = vim.lsp.lua
            if not _G.loadModule then
                lua_lsp = assert(loadfile(%q))()
            end
            local id = lua_lsp.start({ bufnr = bufnr })
            local initialized = vim.wait(500, function()
                local client = vim.lsp.get_client_by_id(id)
                return client and client.initialized
            end, 5)
            local client = vim.lsp.get_client_by_id(id)
            local response, request_err = client:request_sync("textDocument/completion", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 4, character = 18 },
            }, 500, bufnr)
            local labels = {}
            for _, item in ipairs(response and response.result and response.result.items or {}) do
                labels[#labels + 1] = item.label
            end
            local definition = client:request_sync("textDocument/definition", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 5, character = 8 },
            }, 500, bufnr)
            local hover = client:request_sync("textDocument/hover", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 5, character = 1 },
            }, 500, bufnr)
            local signature = client:request_sync("textDocument/signatureHelp", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 6, character = 18 },
            }, 500, bufnr)
            local builtin_completion = client:request_sync("textDocument/completion", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 7, character = 19 },
            }, 500, bufnr)
            local member_completion = client:request_sync("textDocument/completion", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 8, character = 23 },
            }, 500, bufnr)
            local table_signature = client:request_sync("textDocument/signatureHelp", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 9, character = 18 },
            }, 500, bufnr)
            local function completion_labels(response)
                local out = {}
                for _, item in ipairs(response and response.result and response.result.items or {}) do
                    out[#out + 1] = item.label
                end
                return out
            end
            local symbols = client:request_sync("textDocument/documentSymbol", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
            }, 500, bufnr)

            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "local banana = 1",
                "local result = ban",
            })
            local changed = client:request_sync("textDocument/completion", {
                textDocument = { uri = vim.uri_from_bufnr(0) },
                position = { line = 1, character = 18 },
            }, 500, bufnr)
            local changed_labels = {}
            for _, item in ipairs(changed and changed.result and changed.result.items or {}) do
                changed_labels[#changed_labels + 1] = item.label
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local =" })
            vim.wait(500, function() return #vim.diagnostic.get(0) > 0 end, 5)
            local diagnostics = vim.diagnostic.get(0)
            local attached = vim.lsp.buf_is_attached(0, id)
            local location = definition and definition.result
            location = location and (location.range and location or location[1])
            client:stop(true)
            return {
                initialized = initialized,
                attached = attached,
                request_err = request_err,
                labels = labels,
                changed_labels = changed_labels,
                name = client.name,
                encoding = client.offset_encoding,
                definition_line = location and location.range.start.line,
                hover = hover and hover.result and hover.result.contents.value,
                signature = signature and signature.result and signature.result.signatures[1].label,
                active_parameter = signature and signature.result and signature.result.activeParameter,
                builtin_labels = completion_labels(builtin_completion),
                member_labels = completion_labels(member_completion),
                table_signature = table_signature and table_signature.result
                    and table_signature.result.signatures[1].label,
                table_signature_2 = table_signature and table_signature.result
                    and table_signature.result.signatures[2].label,
                table_active_parameter = table_signature and table_signature.result
                    and table_signature.result.activeParameter,
                symbol_count = symbols and symbols.result and #symbols.result,
                diagnostic_count = #diagnostics,
                diagnostic_source = diagnostics[1] and diagnostics[1].source,
                diagnostic_severity = diagnostics[1] and diagnostics[1].severity,
            }
        ]], server))

        ctx.assert.eq("Lua LSP initializes", result.initialized, true)
        ctx.assert.eq("Lua LSP attaches", result.attached, true)
        ctx.assert.eq("Lua LSP completion request error", result.request_err, nil)
        ctx.assert.table_eq("Lua local completion", result.labels, { "apple" })
        ctx.assert.table_eq("Lua buffer synchronization", result.changed_labels, { "banana" })
        ctx.assert.eq("Lua LSP client name", result.name, "lua_ls")
        ctx.assert.eq("Lua LSP position encoding", result.encoding, "utf-8")
        ctx.assert.eq("Lua definition line", result.definition_line, 3)
        ctx.assert.eq("Lua builtin hover", result.hover, "`print(...)`\n\nPrint values")
        ctx.assert.eq("Lua function signature", result.signature, "combine(left, right)")
        ctx.assert.eq("Lua active parameter", result.active_parameter, 1)
        ctx.assert.table_eq("Lua builtin table completion", result.builtin_labels, { "table" })
        ctx.assert.table_eq("Lua table member completion", result.member_labels, {
            "insert(list, pos, value)", "insert(list, value)",
        })
        ctx.assert.eq("Lua table.insert signature", result.table_signature, "table.insert(list, pos, value)")
        ctx.assert.eq("Lua table.insert overload", result.table_signature_2, "table.insert(list, value)")
        ctx.assert.eq("Lua table.insert active parameter", result.table_active_parameter, 1)
        ctx.assert.eq("Lua document symbols", result.symbol_count, 5)
        ctx.assert.eq("Lua syntax diagnostic count", result.diagnostic_count, 1)
        ctx.assert.eq("Lua syntax diagnostic source", result.diagnostic_source, "lua_ls")
        ctx.assert.eq("Lua syntax diagnostic severity", result.diagnostic_severity, 1)
    end,
}
