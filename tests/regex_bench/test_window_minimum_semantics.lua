local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.layout.buffer"] = function()
            return {
                refcount = 0,
                opts = {},
                lines_ref = function()
                    return { "" }
                end,
                ensure_loaded = function() end,
                line_count = function()
                    return 1
                end,
                get_line = function()
                    return ""
                end,
            }
        end,
        ["vim.lib.highlight"] = {},
        ["vim.lib.frame"] = {},
        ["vim.lib.statusline"] = {},
        ["vim.lib.texren"] = {
            parse = function()
                return { "" }, { fg = { "" }, bg = { "" } }
            end,
            layout = function()
                return { "" }, {}, {}, { line = 1, column = 1 }
            end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
        },
        ["vim.lib.tab"] = {
            get_tab_config = function()
                return {}
            end,
            vcol_of_prefix = function(_, col1)
                return col1
            end,
        },
        ["vim.lib.listchars"] = {},
        ["vim.lib.error"] = function(code, ...)
            return { code = code, params = { ... } }
        end,
        ["vim.lib.autocmd"] = {},
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Window = mock.loadModule("vim.layout.window")

local win1 = setmetatable({ winnr = 1, opts = {}, style = nil }, Window)
local win2 = setmetatable({ winnr = 2, opts = {}, style = nil }, Window)
windows[1] = win1
windows[2] = win2
curwin = 1

Options.set("winminwidth", 3, false, nil, nil, true)
Options.set("winminheight", 2, false, nil, nil, true)
Options.set("winwidth", 20, false, nil, nil, true)
Options.set("winheight", 9, false, nil, nil, true)

Options.set("number", false, true, win1)
Options.set("relativenumber", false, true, win1)
Options.set("number", false, true, win2)
Options.set("relativenumber", false, true, win2)

assert_eq("current window minwidth uses winminwidth", win1:minwidth(), 3)
assert_eq("non-current window minwidth uses winminwidth", win2:minwidth(), 3)
assert_eq("current window minheight uses winminheight", win1:minheight(), 2)
assert_eq("non-current window minheight uses winminheight", win2:minheight(), 2)

Options.set("number", true, true, win2)
Options.set("numberwidth", 6, true, win2)
assert_eq("number column floor still applies", win2:minwidth(), 7)

print("window minimum semantics tests: OK")
