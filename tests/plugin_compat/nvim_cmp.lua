local lfs = require("lfs")
local nvim_cmp = (os.getenv and os.getenv("CCVIM_NVIM_CMP")) or "/tmp/ccvim-nvim-cmp"
local cmp_nvim_lsp = (os.getenv and os.getenv("CCVIM_CMP_NVIM_LSP")) or "/tmp/ccvim-cmp-nvim-lsp"

local function copy_tree(backend, source, target)
    for name in lfs.dir(source) do
        if name ~= "." and name ~= ".." then
            local from = source .. "/" .. name
            local to = target .. "/" .. name
            if lfs.attributes(from, "mode") == "directory" then
                copy_tree(backend, from, to)
            else
                local file = assert(io.open(from, "rb"))
                local contents = file:read("*a")
                file:close()
                assert(backend:write_file(to, contents))
            end
        end
    end
end

return {
    id = "plugin_compat.nvim_cmp",
    description = "Runs the real nvim-cmp LSP source against CCVim's Lua LSP client and server.",
    supports = { headless_nvim = false },

    run = function(ctx)
        assert(lfs.attributes(nvim_cmp .. "/lua", "mode") == "directory", "nvim-cmp checkout not found")
        assert(lfs.attributes(cmp_nvim_lsp .. "/lua", "mode") == "directory", "cmp-nvim-lsp checkout not found")
        copy_tree(ctx.backend, nvim_cmp .. "/lua", "/plugins/nvim-cmp/lua")
        copy_tree(ctx.backend, cmp_nvim_lsp .. "/lua", "/plugins/cmp-nvim-lsp/lua")

        local frontend_snippet = ctx.assert.eval_block(ctx.backend, "frontend snippet selection", [[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "table.insert(" })
            vim.api.nvim_win_set_cursor(0, { 1, 12 })
            local Event = loadModule("lib.event")
            Event.ProcessEvent({ "key", keys.a, false, false, false })
            vim.snippet.expand("${1:list}, ${2:pos}, ${3:value})$0")
            vim.wait(500)
            local line = vim.api.nvim_get_current_line()
            local mode = vim.fn.mode()
            vim.snippet.stop()
            return { line, mode }
        ]])
        ctx.assert.eq("frontend snippet selects without inserting control keys", frontend_snippet[1],
            "table.insert(list, pos, value)")
        ctx.assert.eq("frontend snippet enters Select mode", frontend_snippet[2], "s")

        local result = ctx.assert.eval_block(ctx.backend, "nvim-cmp Lua LSP source", [[
            vim.o.runtimepath = vim.o.runtimepath .. ",/plugins/nvim-cmp,/plugins/cmp-nvim-lsp"
            local bridge = require("cmp_nvim_lsp")
            bridge.setup()
            local capabilities = bridge.default_capabilities()
            local cmp = require("cmp")
            local Event = loadModule("lib.event")
            cmp.setup({
                mapping = cmp.mapping.preset.insert({
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                }),
                sources = { { name = "nvim_lsp" } },
                view = { entries = { name = "native" } },
            })

            vim.cmd("enew!")
            vim.bo.filetype = "lua"
            vim.api.nvim_buf_set_name(0, "/tmp/cmp.lua")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "local apple = 1",
                "local result = app",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 18 })

            local id = vim.lsp.lua.start({ bufnr = 0, capabilities = capabilities })
            assert(vim.wait(500, function()
                local client = vim.lsp.get_client_by_id(id)
                return client and client.initialized
            end, 5))

            Event.ProcessEvent({ "key", keys.i, false, false, false })
            assert(vim.wait(500, function() return vim.api.nvim_get_mode().mode == "i" end, 5))
            assert(vim.wait(500, function()
                for _, candidate in pairs(cmp.get_registered_sources()) do
                    if candidate.name == "nvim_lsp" then return true end
                end
                return false
            end, 5))
            local registered = cmp.get_registered_sources()
            local source, wrapped_source
            for _, candidate in pairs(registered) do
                if candidate.name == "nvim_lsp" then
                    source, wrapped_source = candidate.source, candidate
                end
            end
            assert(source and source:is_available())

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            for char in ("table.inser"):gmatch(".") do
                Event.ProcessEvent({ "key", char == "." and keys.period or keys[char], false, false, false })
            end
            assert(vim.wait(2000, function() return vim.fn.pumvisible() == 1 end, 5))
            Event.ProcessEvent({ "key", keys.down, false, false, false })
            assert(vim.wait(500, function() return vim.api.nvim_get_current_line() == "table.insert" end, 5))
            Event.ProcessEvent({ "key", keys.enter, false, false, false })
            vim.wait(1000)
            local first_ui_line = vim.api.nvim_get_current_line()
            local first_ui_mode = vim.fn.mode()
            local first_ui_render_ok, first_ui_render_error = pcall(function()
                tabpages[curtp]:render()
            end)

            vim.snippet.stop()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
            cmp.close()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "local apple = 1",
                "local result = app",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 18 })
            vim.api.nvim_feedkeys("i", "nx", false)

            local response
            source:complete({
                option = {},
                completion_context = { triggerKind = 1 },
            }, function(value) response = value end)
            assert(vim.wait(500, function() return response ~= nil end, 5))
            local labels = {}
            for _, item in ipairs(response.items or response) do labels[#labels + 1] = item.label end
            table.sort(labels)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "table.in" })
            vim.api.nvim_win_set_cursor(0, { 1, 8 })
            local member_response
            source:complete({
                option = {},
                completion_context = { triggerKind = 1 },
            }, function(value) member_response = value end)
            assert(vim.wait(500, function() return member_response ~= nil end, 5))
            local member_labels, member_filters, member_text, member_formats = {}, {}, {}, {}
            for _, item in ipairs(member_response.items or member_response) do
                member_labels[#member_labels + 1] = item.label
                member_filters[#member_filters + 1] = item.filterText
                member_text[#member_text + 1] = item.insertText
                member_formats[#member_formats + 1] = item.insertTextFormat
            end
            table.sort(member_labels)
            table.sort(member_text)
            vim.wait(100)
            local notices = {}
            local notify = vim.notify
            vim.notify = function(message) notices[#notices + 1] = tostring(message) end
            cmp.complete()
            local popup_info
            local visible = vim.wait(2000, function()
                popup_info = vim.fn.complete_info()
                return popup_info.mode == "eval" and #popup_info.items == 2
            end, 5)
            popup_info = popup_info or { mode = "", items = {} }
            vim.notify = notify
            local popup_items = {}
            local scores_positive = true
            for _, entry in ipairs(wrapped_source.entries or {}) do
                local item = entry:get_vim_item(wrapped_source.offset)
                popup_items[#popup_items + 1] = {
                    abbr = item.abbr,
                    kind = item.kind,
                    word = item.word,
                }
                scores_positive = scores_positive and entry.score > 0
            end
            table.sort(popup_items, function(a, b) return a.abbr < b.abbr end)

            local source_offset, request_offset = wrapped_source.offset, wrapped_source.request_offset
            local native_entry_count = #cmp.core.view.native_entries_view.entries
            local native_item_count = #cmp.core.view.native_entries_view.items
            local cursor_before = cmp.core.context.cursor_before_line
            local source_status = wrapped_source.status
            local filter_running = cmp.core.filter.running
            local context_aborted = cmp.core.context.aborted
            cmp.close()
            local rendered = {}
            local Entry = require("cmp.entry")
            for _, line in ipairs({
                "pri", "bit.toh", "coroutine.res", "debug.trace", "io.op", "jit.sta",
                "jit.opt.sta", "lpeg.mat", "math.sqr", "math.p", "os.dat", "package.sea",
                "string.gs", "table.in", "vim.not", "vim.api.nvim_buf_get_n",
            }) do
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
                vim.api.nvim_win_set_cursor(0, { 1, #line })
                local completion
                source:complete({ option = {}, completion_context = { triggerKind = 1 } },
                    function(value) completion = value end)
                assert(vim.wait(500, function() return completion ~= nil end, 5))
                local items = {}
                for _, completion_item in ipairs(completion.items or completion) do
                    local item = Entry.new(cmp.core.context, wrapped_source, completion_item)
                        :get_vim_item(wrapped_source.offset)
                    items[#items + 1] = item.abbr .. "|" .. item.kind
                end
                table.sort(items)
                rendered[line] = items
            end

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "table.inser" })
            vim.api.nvim_win_set_cursor(0, { 1, 11 })
            cmp.complete()
            assert(vim.wait(2000, function() return vim.fn.pumvisible() == 1 end, 5))
            local confirm_notices = {}
            vim.notify = function(message) confirm_notices[#confirm_notices + 1] = tostring(message) end
            vim.api.nvim_select_popupmenu_item(0, true, false, {})
            cmp.confirm({ select = true })
            vim.wait(500)
            vim.notify = notify
            local confirmed_line = vim.api.nvim_get_current_line()
            local confirm_mode = vim.fn.mode()
            vim.api.nvim_feedkeys("data", "mx", false)
            vim.wait(100)
            local replaced_parameter = vim.api.nvim_get_current_line()
            vim.snippet.jump(1)
            vim.wait(100)
            local second_parameter_mode = vim.fn.mode()
            vim.api.nvim_feedkeys("idx", "mx", false)
            vim.wait(100)
            vim.snippet.jump(1)
            vim.wait(100)
            local third_parameter_mode = vim.fn.mode()
            vim.api.nvim_feedkeys("item", "mx", false)
            vim.wait(100)
            local replaced_parameters = vim.api.nvim_get_current_line()

            vim.snippet.stop()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "table.sor" })
            vim.api.nvim_win_set_cursor(0, { 1, 9 })
            vim.api.nvim_feedkeys("a", "nx", false)
            cmp.complete()
            local sort_popup_visible = vim.wait(2000, function() return vim.fn.pumvisible() == 1 end, 5)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Down>", true, false, true), "mx", false)
            local sort_selected = vim.wait(500, function()
                return vim.api.nvim_get_current_line() == "table.sort"
            end, 5)
            local line_after_down = vim.api.nvim_get_current_line()
            vim.wait(500)
            for char in ('(\"hello\")'):gmatch(".") do
                vim.api.nvim_feedkeys(char, "mx", false)
                vim.wait(25)
            end
            local cursor_before_wait = vim.api.nvim_win_get_cursor(0)
            vim.wait(500)
            local typed_line = vim.api.nvim_get_current_line()
            local cursor_after_typing = vim.api.nvim_win_get_cursor(0)
            local mode_after_typing = vim.api.nvim_get_mode().mode
            local visible_after_typing = vim.fn.pumvisible()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
            vim.wait(500)
            local lines_after_return = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            vim.snippet.stop()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
            cmp.close()
            vim.cmd("syntax clear")
            vim.cmd("syntax keyword CmpIdentifier table insert list pos value")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            Event.ProcessEvent({ "key", keys.i, false, false, false })
            for char in ("table.inser"):gmatch(".") do
                Event.ProcessEvent({ "key", char == "." and keys.period or keys[char], false, false, false })
                vim.wait(25)
            end
            local mapped_typed_line = vim.api.nvim_get_current_line()
            local mapped_popup_visible = vim.wait(2000, function() return vim.fn.pumvisible() == 1 end, 5)
            Event.ProcessEvent({ "key", keys.down, false, false, false })
            local mapped_selected = vim.wait(500, function()
                return vim.api.nvim_get_current_line() == "table.insert"
            end, 5)
            local mapped_selected_line = vim.api.nvim_get_current_line()
            local mapped_confirm_notices = {}
            vim.notify = function(message) mapped_confirm_notices[#mapped_confirm_notices + 1] = tostring(message) end
            Event.ProcessEvent({ "key", keys.enter, false, false, false })
            vim.wait(1000)
            vim.notify = notify
            local mapped_confirm_line = vim.api.nvim_get_current_line()
            local mapped_confirm_mode = vim.fn.mode()
            local mapped_syntax = {}
            for _, col in ipairs({ 1, 6, 7, 12, 13, 14, 18 }) do
                mapped_syntax[#mapped_syntax + 1] = vim.fn.synIDattr(vim.fn.synID(1, col, 1), "name")
            end
            vim.lsp.get_client_by_id(id):stop(true)
            return {
                labels = labels,
                member_labels = member_labels,
                member_filters = member_filters,
                member_text = member_text,
                member_formats = member_formats,
                popup_items = popup_items,
                source = source:get_debug_name(),
                snippets = capabilities.textDocument.completion.completionItem.snippetSupport,
                visible = visible,
                popup_mode = popup_info.mode,
                popup_count = #popup_info.items,
                native_entry_count = native_entry_count,
                native_item_count = native_item_count,
                source_offset = source_offset,
                request_offset = request_offset,
                cursor_before = cursor_before,
                scores_positive = scores_positive,
                source_status = source_status,
                filter_running = filter_running,
                context_aborted = context_aborted,
                notices = notices,
                rendered = rendered,
                confirmed_line = confirmed_line,
                confirm_mode = confirm_mode,
                replaced_parameter = replaced_parameter,
                second_parameter_mode = second_parameter_mode,
                third_parameter_mode = third_parameter_mode,
                replaced_parameters = replaced_parameters,
                confirm_notices = confirm_notices,
                typed_line = typed_line,
                cursor_after_typing = cursor_after_typing,
                cursor_before_wait = cursor_before_wait,
                mode_after_typing = mode_after_typing,
                visible_after_typing = visible_after_typing,
                lines_after_return = lines_after_return,
                sort_popup_visible = sort_popup_visible,
                sort_selected = sort_selected,
                line_after_down = line_after_down,
                mapped_confirm_line = mapped_confirm_line,
                mapped_confirm_mode = mapped_confirm_mode,
                mapped_confirm_notices = mapped_confirm_notices,
                mapped_syntax = mapped_syntax,
                mapped_typed_line = mapped_typed_line,
                mapped_popup_visible = mapped_popup_visible,
                mapped_selected = mapped_selected,
                mapped_selected_line = mapped_selected_line,
                first_ui_line = first_ui_line,
                first_ui_mode = first_ui_mode,
                first_ui_render_ok = first_ui_render_ok,
                first_ui_render_error = first_ui_render_error,
            }
        ]])

        ctx.assert.eq("nvim-cmp first frontend confirmation", result.first_ui_line,
            "table.insert(list, pos, value)")
        ctx.assert.eq("nvim-cmp first frontend selection", result.first_ui_mode, "s")
        ctx.assert.eq("nvim-cmp renders Select-mode snippet", result.first_ui_render_ok, true)
        ctx.assert.eq("nvim-cmp Select-mode render error", result.first_ui_render_error, nil)
        ctx.assert.table_eq("nvim-cmp completion labels", result.labels, { "apple" })
        ctx.assert.table_eq("nvim-cmp table member labels", result.member_labels, {
            "insert(list, pos, value)", "insert(list, value)",
        })
        ctx.assert.table_eq("nvim-cmp table member filters", result.member_filters, { "insert", "insert" })
        ctx.assert.table_eq("nvim-cmp table member snippets", result.member_text, {
            "insert(${1:list}, ${2:pos}, ${3:value})$0",
            "insert(${1:list}, ${2:value})$0",
        })
        ctx.assert.table_eq("nvim-cmp table member formats", result.member_formats, { 2, 2 })
        ctx.assert.deep_eq("nvim-cmp rendered table members", result.popup_items, {
            { abbr = "insert(list, pos, value)~", kind = "Function", word = "insert" },
            { abbr = "insert(list, value)~", kind = "Function", word = "insert" },
        })
        ctx.assert.eq("nvim-cmp source offset", result.source_offset, 7)
        ctx.assert.eq("nvim-cmp request offset", result.request_offset, 7)
        ctx.assert.eq("nvim-cmp cursor text", result.cursor_before, "table.in")
        ctx.assert.eq("nvim-cmp entries match", result.scores_positive, true)
        ctx.assert.eq("nvim-cmp source status", result.source_status, 3)
        ctx.assert.eq("nvim-cmp filter complete", result.filter_running, false)
        ctx.assert.eq("nvim-cmp context active", result.context_aborted, false)
        ctx.assert.eq("nvim-cmp async error", result.notices[1], nil)
        ctx.assert.eq("nvim-cmp native popup visible", result.visible, true)
        ctx.assert.eq("nvim-cmp native popup mode", result.popup_mode, "eval")
        ctx.assert.eq("nvim-cmp native popup count", result.popup_count, 2)
        ctx.assert.eq("nvim-cmp native entry count", result.native_entry_count, 2)
        ctx.assert.eq("nvim-cmp native item count", result.native_item_count, 2)
        ctx.assert.deep_eq("nvim-cmp builtin rendering", result.rendered, {
            ["pri"] = { "print(...)~|Function" },
            ["bit.toh"] = { "tohex(value, digits?)~|Function" },
            ["coroutine.res"] = { "resume(coroutine, ...)~|Function" },
            ["debug.trace"] = { "traceback(thread?, message?, level?)~|Function" },
            ["io.op"] = { "open(filename, mode?)~|Function" },
            ["jit.sta"] = { "status()~|Function" },
            ["jit.opt.sta"] = { "start(...)~|Function" },
            ["lpeg.mat"] = { "match(pattern, subject, init?, ...)~|Function" },
            ["math.sqr"] = { "sqrt(value)~|Function" },
            ["math.p"] = { "pi|Constant", "pow(x, y)~|Function" },
            ["os.dat"] = { "date(format?, time?)~|Function" },
            ["package.sea"] = { "searchpath(name, path, separator?, replacement?)~|Function" },
            ["string.gs"] = { "gsub(string, pattern, replacement, count?)~|Function" },
            ["table.in"] = {
                "insert(list, pos, value)~|Function", "insert(list, value)~|Function",
            },
            ["vim.not"] = { "notify(message, level?, opts?)~|Function" },
            ["vim.api.nvim_buf_get_n"] = { "nvim_buf_get_name(buffer)~|Function" },
        })
        ctx.assert.eq("nvim-cmp source identity", result.source, "nvim_lsp:lua_ls")
        ctx.assert.eq("cmp-nvim-lsp capabilities", result.snippets, true)
        ctx.assert.eq("nvim-cmp confirm error", result.confirm_notices[1], nil)
        ctx.assert.eq("nvim-cmp confirms snippets", result.confirmed_line, "table.insert(list, pos, value)")
        ctx.assert.eq("nvim-cmp selects first parameter", result.confirm_mode, "s")
        ctx.assert.eq("nvim-cmp replaces selected parameter", result.replaced_parameter,
            "table.insert(data, pos, value)")
        ctx.assert.eq("nvim-cmp selects second parameter", result.second_parameter_mode, "s")
        ctx.assert.eq("nvim-cmp selects third parameter", result.third_parameter_mode, "s")
        ctx.assert.eq("nvim-cmp replaces function parameters", result.replaced_parameters,
            "table.insert(data, idx, item)")
        ctx.assert.eq("nvim-cmp sort popup visible", result.sort_popup_visible, true)
        ctx.assert.eq("nvim-cmp line after down", result.line_after_down, "table.sort")
        ctx.assert.eq("nvim-cmp down selects sort", result.sort_selected, true)
        ctx.assert.eq("nvim-cmp keeps typed call", result.typed_line, 'table.sort("hello")')
        ctx.assert.deep_eq("nvim-cmp cursor before async work", result.cursor_before_wait, { 1, 19 })
        ctx.assert.eq("nvim-cmp remains in insert mode", result.mode_after_typing, "i")
        ctx.assert.deep_eq("nvim-cmp cursor follows typed call", result.cursor_after_typing, { 1, 19 })
        ctx.assert.eq("nvim-cmp closes stale popup", result.visible_after_typing, 0)
        ctx.assert.table_eq("nvim-cmp return inserts newline", result.lines_after_return, {
            'table.sort("hello")', "",
        })
        ctx.assert.eq("nvim-cmp mapped confirm error", result.mapped_confirm_notices[1], nil)
        ctx.assert.eq("nvim-cmp mapped typed line", result.mapped_typed_line, "table.inser")
        ctx.assert.eq("nvim-cmp mapped popup visible", result.mapped_popup_visible, true)
        ctx.assert.eq("nvim-cmp mapped selected line", result.mapped_selected_line, "table.insert")
        ctx.assert.eq("nvim-cmp mapped item selected", result.mapped_selected, true)
        ctx.assert.eq("nvim-cmp mapped confirm line", result.mapped_confirm_line,
            "table.insert(list, pos, value)")
        ctx.assert.eq("nvim-cmp mapped confirm selects parameter", result.mapped_confirm_mode, "s")
        ctx.assert.eq("nvim-cmp mapped syntax", table.concat(result.mapped_syntax, "|"),
            "CmpIdentifier||CmpIdentifier|CmpIdentifier||CmpIdentifier|")
    end,
}
