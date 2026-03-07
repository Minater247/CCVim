local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local vimapi = ApiBuild.Build().vim

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

assert_eq("joinpath docs example 1", vimapi.fs.joinpath("foo/", "/bar"), "foo/bar")
if vimapi.fn.has("win32") == 1 then
    assert_eq("joinpath backslashes normalize to slashes", vimapi.fs.joinpath("a\\foo\\", "\\bar"), "a/foo/bar")
else
    local expected = (table.concat({ "a\\foo\\", "\\bar" }, "/"):gsub("//+", "/"))
    assert_eq("joinpath backslashes preserved on non-windows", vimapi.fs.joinpath("a\\foo\\", "\\bar"), expected)
end
assert_eq("joinpath absolute first path", vimapi.fs.joinpath("/foo//", "///bar", "baz"), "/foo/bar/baz")
assert_eq("joinpath root first path", vimapi.fs.joinpath("/", "bar"), "/bar")
assert_eq("joinpath empty first path", vimapi.fs.joinpath("", "bar"), "/bar")
assert_eq("joinpath no args", vimapi.fs.joinpath(), "")

assert_eq("joinpath coerces numeric args", vimapi.fs.joinpath("foo", 12), "foo/12")

print("vim.fs.joinpath tests: OK")
