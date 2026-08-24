local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

return {
    id = "api.lsp_lua_large_file_parity",
    description = "Compares Lua LSP results from CCVim and real Neovim in the parity runner; single-engine backends are disabled because neither can perform the comparison alone.", -- luacheck: ignore 631
    supports = { lua_editor = false, headless_nvim = false, parity = true },

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/api/") or "."
        local server = root .. "/lib/luaapi/lsp_lua.lua"
        local fixtures = {
            { name = "runtime", source = root .. "/lib/excmd/runtime.lua", symbol = "eval_expr" },
            { name = "api", source = root .. "/lib/luaapi/api.lua", symbol = "api.nvim_buf_set_lines" },
        }

        local function probe(backend, label, path, symbol)
            return ctx.assert.eval_block(backend, label, string.format([[
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
                    return assert(client:request_sync(method, params, 1000, bufnr)).result
                end

                local symbols = request("textDocument/documentSymbol", {}) or {}
                local listed = {}
                for _, item in ipairs(symbols) do
                    listed[#listed + 1] = { item.name, item.detail or "", item.kind }
                end

                local line_count = vim.api.nvim_buf_line_count(bufnr)
                local completion_line = "local __ccvim_completion = to"
                local signature_line = %q .. "("
                local api_line = "vim.api.nvim_buf_"
                vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
                    completion_line, signature_line, api_line,
                })
                assert(vim.wait(1000, function()
                    return #(request("textDocument/documentSymbol", {}) or {}) >= #symbols
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
                        local item_label = item.filterText or item.label
                        if not seen[item_label] then
                            out[#out + 1] = item_label
                            seen[item_label] = true
                        end
                    end
                    table.sort(out)
                    return out
                end
                client:stop(true)
                return {
                    symbols = listed,
                    builtins = labels(completion),
                    api_builtins = labels(api_completion),
                    signature = signature and signature.signatures[1].label,
                }
            ]], path, server, symbol))
        end

        local results = {}
        for _, fixture in ipairs(fixtures) do
            local path = ctx.assert.temp_path(ctx.backend, "lsp-large-" .. fixture.name, ".lua")
            ctx.assert.write_file(ctx.backend, path, read(fixture.source))
            results[#results + 1] = probe(ctx.backend,
                ctx.backend.name .. " large Lua LSP " .. fixture.name, path, fixture.symbol)
        end
        return results
    end,
}
