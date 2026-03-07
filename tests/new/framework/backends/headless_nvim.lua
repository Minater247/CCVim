local HeadlessNvimBackend = {}

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

function HeadlessNvimBackend.new()
    local backend = { name = "headless_nvim" }

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
        local marker = out:match("@@RESULT@@([^\n\r]+)")
        if not marker then
            return nil, "missing result marker: " .. out
        end
        return marker, nil
    end

    function backend:cleanup()
    end

    return backend
end

return HeadlessNvimBackend
