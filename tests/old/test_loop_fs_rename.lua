local MockEnv = require("vim.tests.test_mocks")

local paths = {
    ["/src.txt"] = { is_dir = false },
    ["/readonly.txt"] = { is_dir = false, read_only = true },
    ["/async.txt"] = { is_dir = false },
}

local function exists(path)
    return paths[path] ~= nil
end

local mock = MockEnv.setup({
    fs = {
        exists = exists,
        isDir = function(path)
            return paths[path] and paths[path].is_dir or false
        end,
        isReadOnly = function(path)
            return paths[path] and paths[path].read_only or false
        end,
        move = function(path, new_path)
            if not exists(path) then
                error(path .. ": No such file")
            end
            paths[new_path] = paths[path]
            paths[path] = nil
            return true
        end,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local Loop = mock.loadModule("lib.luaapi.loop")

local ok, err, errname = Loop.fs_rename("/src.txt", "/dst.txt")
assert_eq("sync rename ok", ok, true)
assert_eq("sync rename err nil", err, nil)
assert_eq("sync rename errname nil", errname, nil)
assert_eq("sync rename removed source", exists("/src.txt"), false)
assert_eq("sync rename created destination", exists("/dst.txt"), true)

local miss_ok, miss_err, miss_name = Loop.fs_rename("/missing.txt", "/new.txt")
assert_eq("sync missing ok nil", miss_ok, nil)
assert_true("sync missing err text", type(miss_err) == "string" and miss_err ~= "", miss_err)
assert_eq("sync missing errname", miss_name, "ENOENT")

local ro_ok, ro_err, ro_name = Loop.fs_rename("/readonly.txt", "/readonly-new.txt")
assert_eq("sync readonly ok nil", ro_ok, nil)
assert_true("sync readonly err text", type(ro_err) == "string" and ro_err ~= "", ro_err)
assert_eq("sync readonly errname", ro_name, "EACCES")

local async_called, async_err, async_success = false, "unset", "unset"
local req = Loop.fs_rename("/async.txt", "/async-new.txt", function(cb_err, success)
    async_called = true
    async_err = cb_err
    async_success = success
end)
assert_true("async request object returned", type(req) == "table", type(req))
assert_true("async callback called", async_called, async_called)
assert_eq("async err nil", async_err, nil)
assert_eq("async success true", async_success, true)
assert_eq("async removed source", exists("/async.txt"), false)
assert_eq("async created destination", exists("/async-new.txt"), true)

local async_miss_called, async_miss_err, async_miss_success = false, nil, "unset"
Loop.fs_rename("/missing-again.txt", "/somewhere.txt", function(cb_err, success)
    async_miss_called = true
    async_miss_err = cb_err
    async_miss_success = success
end)
assert_true("async missing callback called", async_miss_called, async_miss_called)
assert_true(
    "async missing err text",
    type(async_miss_err) == "string" and async_miss_err ~= "",
    async_miss_err
)
assert_eq("async missing success nil", async_miss_success, nil)

print("loop fs_rename tests: OK")
