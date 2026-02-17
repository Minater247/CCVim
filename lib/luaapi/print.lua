local print = {}

local ExMsg = loadModule("vim.lib.excmd.exmsg")

do
    local function quote_string(s)
        s = s:gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("%c", function(c)
                local map = {
                    ["\a"] = "\\a",
                    ["\b"] = "\\b",
                    ["\f"] = "\\f",
                    ["\n"] = "\\n",
                    ["\r"] = "\\r",
                    ["\t"] = "\\t",
                    ["\v"] = "\\v"
                }
                return map[c] or string.format("\\%03d", c:byte())
            end)
        return '"' .. s .. '"'
    end

    local function is_identifier(str)
        return type(str) == "string" and str:match("^[%a_][%w_]*$")
    end

    local function seq_len(t)
        local n = 0
        for i = 1, math.huge do
            if rawget(t, i) == nil then return n end
            n = i
        end
    end

    local TYPE_ORDER = { number = 1, boolean = 2, string = 3, table = 4, ["function"] = 5, userdata = 6, thread = 7 }
    local function key_less(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb and (ta == "string" or ta == "number") then
            return a < b
        end
        local oa, ob = TYPE_ORDER[ta], TYPE_ORDER[tb]
        if oa and ob then return oa < ob end
        if oa then return true end
        if ob then return false end
        return ta < tb
    end

    local function collect_nonseq_keys(t)
        local n = seq_len(t)
        local keys = {}
        for k in pairs(t) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, key_less)
        return keys, n
    end

    local function count_appearances(args)
        local count = setmetatable({}, { __mode = "k" })
        local stack = setmetatable({}, { __mode = "k" })
        local function mark(x)
            count[x] = (count[x] or 0) + 1
        end
        local function visit(x)
            local tx = type(x)
            if tx == "table" or tx == "function" then
                mark(x)
            end
            if tx == "table" then
                if stack[x] then return end
                stack[x] = true
                for k, v in pairs(x) do
                    visit(k); visit(v)
                end
                local mt = getmetatable(x)
                if type(mt) == "table" then visit(mt) end
                stack[x] = nil
            end
        end
        for i = 1, #args do visit(args[i]) end
        return count
    end

    -- Internal: produce a list of line strings for the provided args (each arg its own line)
    local function format_args(args)
        local lines = {}

        local indent = 0
        local indent_cache = { [""] = "", [0] = "" }
        local function indent_str()
            local s = indent_cache[indent]
            if not s then
                s = string.rep("  ", indent)
                indent_cache[indent] = s
            end
            return s
        end

        local line_buf = {}
        local li = 0
        local function push(s)
            li = li + 1
            line_buf[li] = s
        end
        local function reset_line()
            for i = 1, li do line_buf[i] = nil end
            li = 0
        end
        local function flush_line()
            if li > 0 then
                lines[#lines + 1] = table.concat(line_buf, "")
                reset_line()
            end
        end

        local ids = {
            table = setmetatable({}, { __mode = "k" }),
            ["function"] = setmetatable({}, { __mode = "k" })
        }
        local next_id = { table = 1, ["function"] = 1 }
        local appearances = count_appearances(args)

        local write

        local function write_key(k)
            if is_identifier(k) then
                push(k)
            else
                push("["); write(k); push("]")
            end
        end

        local function write_table(t)
            if ids.table[t] then
                push("<table "); push(tostring(ids.table[t])); push(">")
                return
            end
            if (appearances[t] or 0) > 1 then
                ids.table[t] = next_id.table; next_id.table = next_id.table + 1
                push("<"); push(tostring(ids.table[t])); push(">")
            else
                ids.table[t] = next_id.table; next_id.table = next_id.table + 1
            end

            local nonkeys, n = collect_nonseq_keys(t)
            local mt = getmetatable(t)
            local has_mt_tbl = type(mt) == "table"

            push("{")
            if #nonkeys > 0 or has_mt_tbl then
                indent = indent + 1
                local count = 0

                for i = 1, n do
                    if count == 0 then push(" ") else push(", ") end
                    write(t[i])
                    count = count + 1
                end

                for _, k in ipairs(nonkeys) do
                    if count > 0 then push(",") end
                    flush_line(); push(indent_str())
                    write_key(k); push(" = "); write(t[k])
                    count = count + 1
                end

                if has_mt_tbl then
                    if count > 0 then push(",") end
                    flush_line(); push(indent_str())
                    push("<metatable> = "); write(mt)
                end

                indent = indent - 1
                flush_line(); push(indent_str()); push("}")
            else
                if n > 0 then push(" ") end
                for i = 1, n do
                    if i > 1 then push(", ") end
                    write(t[i])
                end
                if n > 0 then push(" ") end
                push("}")
            end
        end

        function write(v)
            local tv = type(v)
            if tv == "string" then
                push(quote_string(v))
            elseif tv == "number" or tv == "boolean" or tv == "nil" then
                push(tostring(v))
            elseif tv == "function" then
                local id = ids["function"][v]
                if not id then
                    id = next_id["function"]; next_id["function"] = id + 1
                    ids["function"][v] = id
                end
                push("<function "); push(tostring(id)); push(">")
            elseif tv == "table" then
                write_table(v)
            else
                push("<"); push(tv); push(">")
            end
        end

        for i = 1, #args do
            reset_line(); write(args[i]); flush_line()
        end

        return lines
    end

    -- vim.print implementation: print each argument representation and return them
    function print.print(...)
        local args = { ... }
        local lines = format_args(args)
        for i = 1, #lines do
            ExMsg.echo(lines[i])
        end
        return ...
    end

    -- vim.inspect implementation: returns a string representation (newline separated if multiple args)
    function print.inspect(...)
        local args = { ... }
        local lines = format_args(args)
        return table.concat(lines, "\n")
    end
end

return print
