local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local vimapi = ApiBuild.Build().vim

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail or "assertion failed")))
    end
end

assert_eq("joinpath docs example 1", vimapi.fs.joinpath("foo/", "/bar"), "foo/bar")
assert_eq("joinpath backslashes normalize to slashes", vimapi.fs.joinpath("a\\foo\\", "\\bar"), "a/foo/bar")
assert_eq("joinpath absolute first path", vimapi.fs.joinpath("/foo//", "///bar", "baz"), "/foo/bar/baz")
assert_eq("joinpath root first path", vimapi.fs.joinpath("/", "bar"), "/bar")
assert_eq("joinpath empty first path", vimapi.fs.joinpath("", "bar"), "bar")
assert_eq("joinpath no args", vimapi.fs.joinpath(), "")

local ok, err = pcall(vimapi.fs.joinpath, "foo", 12)
assert_true("joinpath type checks args", ok == false, tostring(err))

print("vim.fs.joinpath tests: OK")
