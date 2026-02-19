local MockEnv = require("vim.tests.test_mocks")
local mock = MockEnv.setup()

local Runtime = mock.loadModule("vim.lib.syntax_engine.runtime")
local Parser = mock.loadModule("vim.lib.syntax_engine.command_parser")
local Compiler = mock.loadModule("vim.lib.syntax_engine.compiler")
local State = mock.loadModule("vim.lib.syntax_engine.state")
local Buffer = mock.loadModule("vim.layout.buffer")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_lines(path)
    local out = {}
    for line in io.lines(path) do
        out[#out + 1] = line
    end
    return out
end

local function mk_buf(lines)
    local buf = Buffer(false, false, true)
    local copied = {}
    for i = 1, #lines do
        copied[i] = lines[i]
    end
    if #copied == 0 then
        copied[1] = ""
    end
    buf.lines = copied
    buf.loaded = true
    return buf
end

local function read_logical_lines(path)
    local out = {}
    local cur = nil

    for raw in io.lines(path) do
        if raw:match("^%s*\\") then
            if cur then
                local tail = raw:gsub("^%s*\\%s*", "")
                cur = cur .. " " .. tail
            end
        else
            if cur then out[#out + 1] = cur end
            cur = raw
        end
    end

    if cur then out[#out + 1] = cur end
    return out
end

local function collect_vim_syntax_commands()
    local parsed = {}
    local lines = read_logical_lines("vim/runtime/syntax/vim.vim")
    local vars = {}
    local cond_stack = {}

    local function is_active()
        for i = 1, #cond_stack do
            if not cond_stack[i].active then
                return false
            end
        end
        return true
    end

    local function parse_assignment(raw)
        local name, rhs = raw:match("^let!?%s+([%w_:]+)%s*=%s*(.+)$")
        if not name then
            return
        end

        local v = trim(rhs)
        local quote = v:sub(1, 1)
        if (quote == "'" or quote == "\"") and v:sub(-1) == quote then
            vars[name] = v:sub(2, -2)
            return
        end

        local num = tonumber(v)
        if num ~= nil then
            vars[name] = num
            return
        end

        if vars[v] ~= nil then
            vars[name] = vars[v]
        end
    end

    local function eval_condition(expr)
        local out = trim(expr)
        out = out:gsub("([=!<>]=)[#?]", "%1")
        out = out:gsub("!=", "~=")
        out = out:gsub("&&", " and ")
        out = out:gsub("%|%|", " or ")
        out = out:gsub("exists%s*%((['\"])(.-)%1%)", function(_, name)
            return ("exists(%q)"):format(name)
        end)
        out = out:gsub("([%a_][%w_]*:[%w_:#]+)", function(name)
            return ("var(%q)"):format(name)
        end)

        local chars = {}
        for i = 1, #out do
            local ch = out:sub(i, i)
            if ch == "!" then
                local nxt = out:sub(i + 1, i + 1)
                if nxt == "=" or nxt == "~" then
                    chars[#chars + 1] = ch
                else
                    chars[#chars + 1] = " not "
                end
            else
                chars[#chars + 1] = ch
            end
        end
        out = table.concat(chars)

        local env = setmetatable({
            exists = function(name)
                return vars[name] ~= nil
            end,
            var = function(name)
                return vars[name] or 0
            end,
            has = function(_)
                return false
            end,
        }, {
            __index = function(_, key)
                return vars[key] or 0
            end,
        })

        local chunk = load("return (" .. out .. ")", "cond", "t", env)
        if not chunk then
            return false
        end
        local ok, value = pcall(chunk)
        if not ok then
            return false
        end
        return not not value and value ~= 0 and value ~= ""
    end

    for i = 1, #lines do
        local src = lines[i]
        local cmd = trim(src)

        local expr = cmd:match("^if%s+(.+)$")
        if expr then
            local parent_active = is_active()
            local cond = parent_active and eval_condition(expr) or false
            cond_stack[#cond_stack + 1] = {
                parent_active = parent_active,
                branch_taken = cond,
                active = parent_active and cond,
            }
            goto continue
        end

        expr = cmd:match("^elseif%s+(.+)$")
        if expr then
            local top = cond_stack[#cond_stack]
            if top then
                if not top.parent_active then
                    top.active = false
                elseif top.branch_taken then
                    top.active = false
                else
                    local cond = eval_condition(expr)
                    top.active = cond
                    if cond then top.branch_taken = true end
                end
            end
            goto continue
        end

        if cmd == "else" then
            local top = cond_stack[#cond_stack]
            if top then
                if top.parent_active and not top.branch_taken then
                    top.active = true
                    top.branch_taken = true
                else
                    top.active = false
                end
            end
            goto continue
        end

        if cmd == "endif" then
            if #cond_stack > 0 then
                cond_stack[#cond_stack] = nil
            end
            goto continue
        end

        if not is_active() then
            goto continue
        end

        parse_assignment(cmd)

        if cmd ~= "" and cmd:sub(1, 1) ~= "\"" then
            if cmd:match("^VimL%s+") then
                cmd = cmd:gsub("^VimL%s+", "")
            elseif cmd:match("^Vim9%s+") then
                cmd = nil
            elseif cmd:match("^VimFold%a*%s+") then
                cmd = cmd:gsub("^VimFold%a*%s+", "")
            end

            if cmd then
                cmd = cmd:gsub("^syntax%s+", "")
                cmd = cmd:gsub("^syn%s+", "")
                if cmd ~= src and cmd ~= "" then
                    local p = Parser.parse(cmd)
                    if p and p.kind ~= "unknown" then
                        parsed[#parsed + 1] = p
                    end
                end
            end
        end
        ::continue::
    end

    return parsed
end

local function group_name_for_id(ir, group_id)
    if type(group_id) == "number" then
        local g = ir.groups and ir.groups[group_id]
        return (g and g.name) or ("#" .. tostring(group_id))
    end
    if type(group_id) == "string" and group_id ~= "" then
        return group_id
    end
    return "Normal"
end

local function painted_groups_for_line(ctx, buf, line_nr)
    Runtime.line_to_blit(ctx, buf, line_nr)
    local cache = ctx.span_cache[line_nr]
    local text = buf:get_line(line_nr, true) or ""
    local painted = {}

    for i = 1, #text do
        painted[i] = "Normal"
    end

    if not cache then
        return painted
    end

    for i = 1, #cache.spans do
        local span = cache.spans[i]
        local name = group_name_for_id(ctx.syntax_ir, span.group_id)
        local s = math.max(1, span.s or 1)
        local e = math.min(#text, span.e or #text)
        for col = s, e do
            painted[col] = name
        end
    end

    return painted
end

local syntax_cmds = collect_vim_syntax_commands()
local ctx = State.new_context({
    syntax = "vim",
    synmaxcol = 4000,
})
ctx.syntax_commands = syntax_cmds
ctx.syntax_ir = Compiler.compile(syntax_cmds)
ctx.syntax_ir_dirty = false

local buf = mk_buf(read_lines("vim/runtime/ftplugin.vim"))

do
    local g7 = painted_groups_for_line(ctx, buf, 7)
    assert_eq("line 7 if group", g7[1], "vimNotFunc")
    assert_eq("line 7 left paren group", g7[10], "vimParenSep")
    assert_eq("line 7 string starts at quote", g7[11], "vimString")
end

do
    local g16 = painted_groups_for_line(ctx, buf, 16)
    assert_eq("line 16 string content", g16[15], "vimString")
    assert_eq("line 16 closing paren", g16[32], "vimParenSep")
end

do
    local g21 = painted_groups_for_line(ctx, buf, 21)
    assert_eq("line 21 left paren", g21[19], "vimParenSep")
    assert_eq("line 21 string starts", g21[20], "vimString")
end

do
    local g23 = painted_groups_for_line(ctx, buf, 23)
    assert_eq("line 23 operator =~# col 15", g23[15], "vimOper")
    assert_eq("line 23 operator =~# col 16", g23[16], "vimOper")
    assert_eq("line 23 operator =~# col 17", g23[17], "vimOper")
    assert_eq("line 23 operator &&", g23[23], "vimOper")
end

do
    local g30 = painted_groups_for_line(ctx, buf, 30)
    assert_eq("line 30 line comment starts at quote", g30[7], "vimLineComment")
end

do
    local g31 = painted_groups_for_line(ctx, buf, 31)
    assert_eq("line 31 for keyword", g31[7], "vimCommand")
end

print("ftplugin.vim Vimscript highlighting regression tests: OK")
