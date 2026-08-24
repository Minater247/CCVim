local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local report = os.getenv and os.getenv("CCVIM_LSP_REPORT") == "1"

return {
    id = "api.lsp_lua_large_file_parity",
    description = "Compares Lua symbols, signatures, and builtins on two large production files.",

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/api/") or "."
        local probe = io.open(root .. "/lib/luaapi/lsp_lua.lua", "rb")
        if probe then probe:close() else root = "." end
        local server = root .. "/lib/luaapi/lsp_lua.lua"
        local fixtures = {
            {
                name = "runtime",
                source = root .. "/lib/excmd/runtime.lua",
                symbol = "eval_expr",
                signature = "eval_expr(expr, state)",
                symbol_count = 1463,
                first_symbol = "Runtime",
                last_symbol = "err",
                builtins = {
                    "to", "to_bounds", "to_index", "to_number", "tok", "token",
                    "tokens", "tonumber", "top", "tostring", "total_subs",
                },
                api_builtins = { "nvim_buf_get_lines", "nvim_buf_get_name", "nvim_buf_set_lines", "nvim_buf_set_name" },
            },
            {
                name = "api",
                source = root .. "/lib/luaapi/api.lua",
                symbol = "api.nvim_buf_set_lines",
                signature = "api.nvim_buf_set_lines(buffer, start, end_, strict_indexing, replacement)",
                symbol_count = 549,
                first_symbol = "api",
                last_symbol = "out",
                builtins = { "tonumber", "tostring", "touched_window" },
                api_builtins = {
                    "nvim_buf_add_highlight", "nvim_buf_attach", "nvim_buf_call", "nvim_buf_clear_namespace",
                    "nvim_buf_del_extmark", "nvim_buf_del_keymap", "nvim_buf_del_var", "nvim_buf_delete",
                    "nvim_buf_detach", "nvim_buf_get_changedtick", "nvim_buf_get_extmark_by_id",
                    "nvim_buf_get_extmarks",
                    "nvim_buf_get_keymap", "nvim_buf_get_lines", "nvim_buf_get_name", "nvim_buf_get_option",
                    "nvim_buf_get_text", "nvim_buf_get_var",
                    "nvim_buf_is_loaded", "nvim_buf_is_valid", "nvim_buf_line_count", "nvim_buf_set_extmark",
                    "nvim_buf_set_keymap", "nvim_buf_set_lines", "nvim_buf_set_name", "nvim_buf_set_option",
                    "nvim_buf_set_text", "nvim_buf_set_var",
                },
            },
        }

        for _, fixture in ipairs(fixtures) do
            local path = ctx.assert.temp_path(ctx.backend, "lsp-large-" .. fixture.name, ".lua")
            ctx.assert.write_file(ctx.backend, path, read(fixture.source))
            local result = ctx.assert.eval_block(ctx.backend, "large Lua LSP " .. fixture.name, string.format([[
                vim.cmd("edit " .. vim.fn.fnameescape(%q))
                vim.bo.filetype = "lua"
                local bufnr = vim.api.nvim_get_current_buf()
                local lua_lsp = vim.lsp.lua
                if not _G.loadModule then lua_lsp = assert(loadfile(%q))() end
                local id = lua_lsp.start({ bufnr = bufnr })
                assert(vim.wait(1000, function()
                    local client = vim.lsp.get_client_by_id(id)
                    return client and client.initialized
                end, 5))
                local client = vim.lsp.get_client_by_id(id)
                local function request(method, params)
                    params.textDocument = { uri = vim.uri_from_bufnr(bufnr) }
                    local response = assert(client:request_sync(method, params, 1000, bufnr))
                    return response.result
                end

                local symbols = request("textDocument/documentSymbol", {}) or {}
                local details, names = {}, {}
                for _, symbol in ipairs(symbols) do
                    details[symbol.name] = symbol.detail or ""
                    names[#names + 1] = symbol.name
                end

                local line_count = vim.api.nvim_buf_line_count(bufnr)
                local completion_line = "local __ccvim_completion = to"
                local signature_line = %q .. "("
                local api_line = "vim.api.nvim_buf_"
                vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
                    completion_line, signature_line, api_line,
                })
                assert(vim.wait(1000, function()
                    local changed = request("textDocument/documentSymbol", {}) or {}
                    return #changed >= #symbols
                end, 5))
                local completion = request("textDocument/completion", {
                    position = { line = line_count, character = #completion_line },
                }) or {}
                local api_completion = request("textDocument/completion", {
                    position = { line = line_count + 2, character = #api_line },
                }) or {}
                local signature = request("textDocument/signatureHelp", {
                    position = { line = line_count + 1, character = #signature_line },
                })
                local function labels(response)
                    local out, seen = {}, {}
                    for _, item in ipairs(response.items or response) do
                        local label = item.filterText or item.label
                        if not seen[label] then
                            out[#out + 1] = label
                            seen[label] = true
                        end
                    end
                    table.sort(out)
                    return out
                end
                client:stop(true)
                return {
                    symbol_count = #symbols,
                    first_symbol = names[1],
                    last_symbol = names[#names],
                    detail = details[%q],
                    builtins = labels(completion),
                    api_builtins = labels(api_completion),
                    signature = signature and signature.signatures[1].label,
                }
            ]], path, server, fixture.symbol, fixture.symbol))

            if report then
                print(table.concat({
                    fixture.name,
                    tostring(result.symbol_count),
                    tostring(result.first_symbol),
                    tostring(result.last_symbol),
                    table.concat(result.builtins, ","),
                    table.concat(result.api_builtins, ","),
                }, "\t"))
            end

            ctx.assert.eq(fixture.name .. " symbol count", result.symbol_count, fixture.symbol_count)
            ctx.assert.eq(fixture.name .. " first symbol", result.first_symbol, fixture.first_symbol)
            ctx.assert.eq(fixture.name .. " last symbol", result.last_symbol, fixture.last_symbol)
            ctx.assert.eq(fixture.name .. " selected symbol detail", result.detail, fixture.signature)
            ctx.assert.eq(fixture.name .. " selected signature", result.signature, fixture.signature)
            ctx.assert.table_eq(fixture.name .. " builtin/object completion", result.builtins, fixture.builtins)
            ctx.assert.table_eq(fixture.name .. " vim.api object completion", result.api_builtins, fixture.api_builtins)
        end
    end,
}
