local HeadlessNvimBackend = {}

-- Metatable marker for empty dictionaries
local EMPTY_DICT_MT = {}

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(cmd)
    local p = io.popen(cmd .. " 2>&1", "r")
    if not p then
        return false, "failed to launch command"
    end
    local out = p:read("*a") or ""
    local ok = p:close()
    if ok == true or ok == 0 then
        return true, out
    end
    return false, out
end

local function json_decode(json_str)
    if type(json_str) ~= "string" then
        return nil, "json_decode expects a string"
    end

    local pos = 1
    local len = #json_str

    local function skip_whitespace()
        while pos <= len and json_str:sub(pos, pos):match("[%s]") do
            pos = pos + 1
        end
    end

    local function decode_value()
        skip_whitespace()
        if pos > len then
            return nil, "unexpected end of JSON"
        end

        local char = json_str:sub(pos, pos)

        if char == '"' then
            pos = pos + 1
            local result = {}
            while pos <= len do
                local c = json_str:sub(pos, pos)
                if c == '"' then
                    pos = pos + 1
                    return table.concat(result)
                elseif c == "\\" then
                    pos = pos + 1
                    local esc = json_str:sub(pos, pos)
                    if esc == 'n' then
                        result[#result + 1] = "\n"
                    elseif esc == 't' then
                        result[#result + 1] = "\t"
                    elseif esc == 'r' then
                        result[#result + 1] = "\r"
                    elseif esc == 'b' then
                        result[#result + 1] = "\b"
                    elseif esc == 'f' then
                        result[#result + 1] = "\f"
                    elseif esc == '\\' then
                        result[#result + 1] = "\\"
                    elseif esc == '"' then
                        result[#result + 1] = '"'
                    elseif esc == '/' then
                        result[#result + 1] = '/'
                    else
                        result[#result + 1] = esc
                    end
                    pos = pos + 1
                else
                    result[#result + 1] = c
                    pos = pos + 1
                end
            end
            return nil, "unterminated string"
        elseif char == '[' then
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if pos <= len and json_str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                local val, err = decode_value()
                if err then
                    return nil, err
                end
                arr[#arr + 1] = val
                skip_whitespace()
                if pos > len then
                    return nil, "unterminated array"
                end
                local next_char = json_str:sub(pos, pos)
                if next_char == ']' then
                    pos = pos + 1
                    return arr
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    return nil, "expected ',' or ']' in array"
                end
            end
        elseif char == '{' then
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if pos <= len and json_str:sub(pos, pos) == '}' then
                pos = pos + 1
                return setmetatable({}, EMPTY_DICT_MT)
            end
            while true do
                skip_whitespace()
                if pos > len or json_str:sub(pos, pos) ~= '"' then
                    return nil, "expected string key in object"
                end
                local key, err = decode_value()
                if err then
                    return nil, err
                end
                skip_whitespace()
                if pos > len or json_str:sub(pos, pos) ~= ':' then
                    return nil, "expected ':' after object key"
                end
                pos = pos + 1
                local val, err2 = decode_value()
                if err2 then
                    return nil, err2
                end
                obj[key] = val
                skip_whitespace()
                if pos > len then
                    return nil, "unterminated object"
                end
                local next_char = json_str:sub(pos, pos)
                if next_char == '}' then
                    pos = pos + 1
                    return obj
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    return nil, "expected ',' or '}' in object"
                end
            end
        elseif char == 't' then
            if json_str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
            return nil, "invalid JSON value"
        elseif char == 'f' then
            if json_str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
            return nil, "invalid JSON value"
        elseif char == 'n' then
            if json_str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
            return nil, "invalid JSON value"
        elseif char:match("[-0-9]") then
            local num_start = pos
            if char == '-' then
                pos = pos + 1
            end
            while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
            if pos <= len and json_str:sub(pos, pos) == '.' then
                pos = pos + 1
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            if pos <= len and json_str:sub(pos, pos):match("[eE]") then
                pos = pos + 1
                if pos <= len and json_str:sub(pos, pos):match("[+-]") then
                    pos = pos + 1
                end
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            local num_str = json_str:sub(num_start, pos - 1)
            return tonumber(num_str)
        else
            return nil, "unexpected character: " .. char
        end
    end

    local result, err = decode_value()
    if err then
        return nil, err
    end
    skip_whitespace()
    if pos <= len then
        return nil, "trailing garbage after JSON"
    end
    return result, nil
end

function HeadlessNvimBackend.new()
    local backend = {
        name = "headless_nvim",
        EMPTY_DICT_MT = EMPTY_DICT_MT,
    }

    function backend:eval_lua(lua_expr)
        local tmp = string.format("/tmp/nvim-test-eval-%d.lua", os.time())
        local f = assert(io.open(tmp, "w"))
        f:write("local ok, rv = pcall(function() return ", lua_expr, " end)\n")
        f:write("if not ok then\n")
        f:write("  io.stderr:write('E:' .. tostring(rv) .. '\\n')\n")
        f:write("  vim.cmd('cq')\n")
        f:write("  return\n")
        f:write("end\n")
        f:write("print('@@RESULT@@' .. vim.json.encode(rv))\n")
        f:write("vim.cmd('qa!')\n")
        f:close()

        local cmd = "nvim --headless -u NONE -n -l " .. shell_quote(tmp)
        local ok, out = run(cmd)
        os.remove(tmp)
        if not ok then
            return nil, out
        end
        local json_result = out:match("@@RESULT@@([^\n\r]+)")
        if not json_result then
            return nil, "missing result marker: " .. out
        end
        return json_decode(json_result)
    end

    function backend:eval_vimscript(vimscript_expr)
        if type(vimscript_expr) ~= "string" then
            return nil, "eval_vimscript expects a string expression"
        end
        return self:eval_lua(string.format("vim.fn.eval(%q)", vimscript_expr))
    end

    function backend:is_empty_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        return getmetatable(tbl) == EMPTY_DICT_MT
    end

    function backend:is_list(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_empty_dict(tbl) then
            return false
        end
        local n = 0
        for k, _ in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                return false
            end
            if k > n then
                n = k
            end
        end
        for i = 1, n do
            if tbl[i] == nil then
                return false
            end
        end
        return true
    end

    function backend:is_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_empty_dict(tbl) then
            return true
        end
        return not self:is_list(tbl)
    end

    function backend:cleanup()
    end

    return backend
end

return HeadlessNvimBackend
