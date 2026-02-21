local MockEnv = require("vim.tests.test_mocks")

local dirs = {
    ["/"] = true,
    ["/tmp"] = true,
}

local files = {
    ["/tmp/existing-file"] = true,
}

local function norm(path)
    local p = tostring(path or ""):gsub("//+", "/")
    if p ~= "/" then
        p = p:gsub("/+$", "")
    end
    if p == "" then
        p = "/"
    end
    return p
end

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            local p = norm(path)
            return dirs[p] == true or files[p] == true
        end,
        isDir = function(path)
            return dirs[norm(path)] == true
        end,
        list = function()
            return {}
        end,
        open = function()
            return nil
        end,
        isReadOnly = function()
            return false
        end,
        getSize = function(path)
            if files[norm(path)] then
                return 1
            end
            return 0
        end,
        makeDir = function(path)
            local p = norm(path)
            if files[p] then
                error("path is a file")
            end
            local cur = ""
            for seg in p:gmatch("[^/]+") do
                if cur == "" then
                    cur = "/" .. seg
                else
                    cur = cur .. "/" .. seg
                end
                if files[cur] then
                    error("parent is a file")
                end
                dirs[cur] = true
            end
        end,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Fn = mock.loadModule("lib.luaapi.fn")

assert_eq("mkdir -p creates nested path", Fn.mkdir("/tmp/a/b", "p", 448), 1)
assert_eq("mkdir -p made parent", dirs["/tmp/a"], true)
assert_eq("mkdir -p made child", dirs["/tmp/a/b"], true)

assert_eq("mkdir existing dir with -p succeeds", Fn.mkdir("/tmp/a/b", "p"), 1)
assert_eq("mkdir existing dir without -p fails", Fn.mkdir("/tmp/a/b"), 0)

assert_eq("mkdir without -p requires parent", Fn.mkdir("/tmp/no-parent/x"), 0)
assert_eq("mkdir without -p works with parent", Fn.mkdir("/tmp/a/c"), 1)
assert_eq("mkdir no -p created child", dirs["/tmp/a/c"], true)

assert_eq("mkdir path that is existing file fails", Fn.mkdir("/tmp/existing-file", "p"), 0)
assert_eq("mkdir with empty name fails", Fn.mkdir(""), 0)

print("mkdir builtin tests: OK")
