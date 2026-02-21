local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({ ccvim_path = "vim" })

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local ApiBuild = mock.loadModule("vim.lib.luaapi.apibuild")
local api = ApiBuild.Build()

do
    local out = api.vim.iter({ 1, 2, 3, 4 })
        :filter(function(v)
            return v % 2 == 0
        end)
        :map(function(v)
            return v * 10
        end)
        :totable()
    assert_eq("vim.iter list filter+map count", #out, 2)
    assert_eq("vim.iter list first", out[1], 20)
    assert_eq("vim.iter list second", out[2], 40)
end

do
    local extmarks = {
        { 1, 0, 0, { invalid = true } },
        { 2, 0, 0, { invalid = false } },
        { 3, 0, 0, {} },
    }
    local out = api.vim.iter(extmarks)
        :filter(function(extmark)
            return not extmark[4].invalid
        end)
        :totable()
    assert_eq("vim.iter tutor-style filter count", #out, 2)
    assert_eq("vim.iter tutor-style first id", out[1][1], 2)
    assert_eq("vim.iter tutor-style second id", out[2][1], 3)
end

do
    local out = api.vim.iter({ a = 1, b = 2 }):totable()
    assert_eq("vim.iter dict totable count", #out, 2)
    local found_a = false
    local found_b = false
    for i = 1, #out do
        if out[i][1] == "a" and out[i][2] == 1 then
            found_a = true
        elseif out[i][1] == "b" and out[i][2] == 2 then
            found_b = true
        end
    end
    assert_true("vim.iter dict contains a pair", found_a, tostring(out))
    assert_true("vim.iter dict contains b pair", found_b, tostring(out))
end

print("vim.iter tests: OK")
