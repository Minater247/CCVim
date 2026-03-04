local MockEnv = require("vim.tests.test_mocks")

local sourced = {}
local mock = MockEnv.setup({
    ccvim_path = "vim",
    module_stubs = {
        ["lib.scriptsource"] = {
            source = function(path)
                sourced[#sourced + 1] = path
                return true
            end,
            source_runtime = function()
                return true
            end,
            CurrentContext = function()
                return nil
            end,
            PushContext = function() end,
            PopContext = function() end,
            wrap = function(_, cb)
                return cb
            end,
        },
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
            trigger_keys = function() end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
            on_lines_changed = function() end,
            getplaced = function() return {} end,
            jump = function() return -1 end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options

local buf = mock.create_buffer(1, "/tmp/test.txt", { "" })
local win = mock.create_window(1, buf, { tabpagenr = 1 })
_G.curwin = 1
_G.curtp = 1
_G.tabpages = { { tabnr = 1, windows = { win }, opts = {} } }

local Runtime = mock.loadModule("lib.excmd.runtime")

local ok1, err1 = Runtime.run(
    [[source $VIMRUNTIME/colors/vim.lua " Nvim: revert to Vim default color scheme]],
    { script_ctx = "/tmp/test_source_comment.vim" }
)
assert_eq("source with spaced comment succeeds", ok1, true)
if ok1 ~= true then
    error(tostring(err1))
end
assert_eq("source with spaced comment strips trailing comment", sourced[1], "$VIMRUNTIME/colors/vim.lua")

local ok2, err2 = Runtime.run(
    [[source $VIMRUNTIME/colors/vim.lua"comment]],
    { script_ctx = "/tmp/test_source_comment.vim" }
)
assert_eq("source with adjacent comment succeeds", ok2, true)
if ok2 ~= true then
    error(tostring(err2))
end
assert_eq("source with adjacent comment strips trailing comment", sourced[2], "$VIMRUNTIME/colors/vim.lua")

print("source trailing comment tests: OK")
