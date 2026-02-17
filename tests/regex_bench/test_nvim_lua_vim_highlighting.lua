local function make_colors()
    local order = {
        "white", "orange", "magenta", "lightBlue",
        "yellow", "lime", "pink", "gray",
        "lightGray", "cyan", "purple", "blue",
        "brown", "green", "red", "black",
    }
    local t = {}
    local map = {}
    for i = 1, #order do
        local bit = 2 ^ (i - 1)
        t[order[i]] = bit
        map[bit] = string.format("%x", i - 1)
    end

    function t.toBlit(bit)
        return map[bit] or "0"
    end

    function t.packRGB(r, g, b)
        return { r, g, b }
    end

    function t.unpackRGB(rgb)
        if type(rgb) == "table" then
            return rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
        end
        return 0, 0, 0
    end

    return t
end

_G.colors = make_colors()
_G.term = {
    getPaletteColor = function(_)
        return 0, 0, 0
    end,
    setTextColor = function(_) end,
    setBackgroundColor = function(_) end,
}

_G.LOG_ERROR = function(...) end
_G.LOG_DEBUG = function(...) end
_G.LOG_INTERNAL = function(...) end

local MODULE_CACHE = {}
function _G.loadModule(name)
    if MODULE_CACHE[name] then
        return MODULE_CACHE[name]
    end

    local path = name:gsub("%.", "/") .. ".lua"
    local env = setmetatable({
        _V = nil,
        loadModule = _G.loadModule,
    }, { __index = _G })

    local chunk, err = loadfile(path, "t", env)
    if not chunk then
        error(("loadModule failed for %s (%s)"):format(name, tostring(err)))
    end

    local mod = chunk()
    MODULE_CACHE[name] = mod
    return mod
end

local Runtime = loadModule("vim.lib.syntax_engine.runtime")
local Parser = loadModule("vim.lib.syntax_engine.command_parser")
local Compiler = loadModule("vim.lib.syntax_engine.compiler")
local State = loadModule("vim.lib.syntax_engine.state")
local Highlight = loadModule("vim.lib.highlight")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local function mk_ctx(commands)
    local parsed = {}
    for i = 1, #commands do
        parsed[i] = Parser.parse(commands[i])
    end

    local ctx = State.new_context({
        syntax = "test",
        synmaxcol = 3000,
    })
    ctx.syntax_commands = parsed
    ctx.syntax_ir = Compiler.compile(parsed)
    ctx.syntax_ir_dirty = false
    return ctx
end

local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    return lines
end

local function find_luaapi_in_nvim(lines)
    local needle = 'loadModule("vim.lib.luaapi.scopes")'
    for i = 1, #lines do
        if lines[i]:find(needle, 1, true) then
            local s, e = lines[i]:find("luaapi", 1, true)
            if s and e then
                return i, s, e
            end
        end
    end
    error("FAIL could not locate luaapi token in vim/nvim.lua")
end

local function assert_fg_range(label, blit, s, e, want)
    for col = s, e do
        assert_eq(label .. " col " .. tostring(col), blit.fg:sub(col, col), want)
    end
end

local source_lines = read_lines("vim/nvim.lua")
local target_line, token_start, token_end = find_luaapi_in_nvim(source_lines)
local buf = { lines = source_lines }
local error_fg = colors.toBlit(Highlight.For("Error")[1])

-- Lua-style form: contains=TOP,Group should add Group, not subtract it.
do
    local ctx = mk_ctx({
        "match Error /luaapi/ contained",
        "region Comment start=/\\(/ end=/\\)/ contains=TOP,Error",
    })
    local blit = Runtime.line_to_blit(ctx, buf, target_line)
    assert_true("TOP+group nvim.lua blit exists", blit ~= nil)
    assert_fg_range("TOP+group highlights contained token", blit, token_start, token_end, error_fg)
end

-- Vimscript-style form: clusters using contains=TOP,Group must also add Group.
do
    local ctx = mk_ctx({
        "match Error /luaapi/ contained",
        "cluster LegacyTop contains=TOP,Error",
        "region Comment start=/\\(/ end=/\\)/ contains=@LegacyTop",
    })
    local blit = Runtime.line_to_blit(ctx, buf, target_line)
    assert_true("cluster TOP+group nvim.lua blit exists", blit ~= nil)
    assert_fg_range("cluster TOP+group highlights contained token", blit, token_start, token_end, error_fg)
end

-- contains=CONTAINED,Group should include the listed top-level group.
do
    local ctx = mk_ctx({
        "match Error /luaapi/",
        "region Comment start=/\\(/ end=/\\)/ contains=CONTAINED,Error",
    })
    local blit = Runtime.line_to_blit(ctx, buf, target_line)
    assert_true("CONTAINED+group nvim.lua blit exists", blit ~= nil)
    assert_fg_range("CONTAINED+group highlights top-level token", blit, token_start, token_end, error_fg)
end

print("nvim.lua syntax contains/cluster tests: OK")
