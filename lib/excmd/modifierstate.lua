local M = {}
local Error = loadModule("lib.error")
local stack = {}
M.CANCELLED = {}

function M.get(key)
    for i = #stack, 1, -1 do
        if stack[i][key] ~= nil then return stack[i][key] end
    end
    return nil
end

function M.with(values, fn)
    stack[#stack + 1] = values
    local result = table.pack(pcall(fn))
    stack[#stack] = nil
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

function M.check()
    if M.get("sandbox") then error(Error(48)) end
end

local safe_commands = {
    echo = true, echomsg = true, echoerr = true, echon = true, let = true, const = true,
    unlet = true, call = true, execute = true, ["if"] = true, ["else"] = true,
    endif = true, ["for"] = true, endfor = true, ["while"] = true, endwhile = true,
    ["try"] = true, catch = true, finally = true, endtry = true, ["throw"] = true,
    ["return"] = true, ["break"] = true, ["continue"] = true, finish = true,
    ["function"] = true, endfunction = true, delfunction = true, set = true, setlocal = true,
    setglobal = true, silent = true, unsilent = true, verbose = true, sandbox = true,
    noautocmd = true, keepalt = true, keepjumps = true, keeppatterns = true, lockmarks = true,
    keepmarks = true, noswapfile = true, hide = true, confirm = true, browse = true,
    vertical = true, horizontal = true, aboveleft = true, belowright = true,
    leftabove = true, rightbelow = true, topleft = true, botright = true, tab = true,
}
safe_commands["elseif"] = true

function M.check_command(name)
    if M.get("sandbox") and not safe_commands[name] then M.check() end
end

local unsafe_functions = {
    system = true, systemlist = true, jobstart = true, termopen = true, jobstop = true,
    writefile = true, mkdir = true, delete = true, rename = true,
    bufadd = true, bufload = true, setline = true, append = true, deletebufline = true,
    setbufline = true, appendbufline = true, setbufvar = true, setwinvar = true, settabvar = true,
    win_execute = true, win_gotoid = true, feedkeys = true, input = true, confirm = true,
    execute = true, histadd = true, settabwinvar = true, timer_start = true,
    luaeval = true, libcall = true, libcallnr = true, chdir = true,
}
function M.check_function(name)
    if M.get("sandbox") and (unsafe_functions[name] or tostring(name):match("^v:lua%.")) then M.check() end
end

function M.adjust_marks(buf, start, removed, inserted)
    if M.get("lockmarks") then return end
    local preserve = M.get("filter") and (M.get("keepmarks")
        or not loadModule("lib.options").get("cpoptions"):find("R", 1, true))
    local function adjust(marks, global)
        for key, mark in pairs(marks or {}) do
            if (global or tostring(key):match("^[a-z]$")) and (not global or mark.bufnr == buf.bufnr) then
                if mark.lnum >= start + removed then
                    mark.lnum = mark.lnum + inserted - removed
                elseif mark.lnum >= start then
                    if preserve and mark.lnum < start + inserted then
                        mark.col = math.min(mark.col, #(buf.lines[mark.lnum] or "") + 1)
                    else
                        marks[key] = nil
                    end
                end
            end
        end
    end
    adjust(buf.marks)
    adjust(global_marks, true)
end

function M.check_assignment(text)
    if not M.get("sandbox") then return end
    local lhs = tostring(text or ""):match("^(.-)=") or text or ""
    for name in lhs:gmatch("v:([%w_]+)") do
        if name == "folddashes" or name == "foldend" or name == "foldlevel"
            or name == "foldstart" or name == "lnum" then error(Error(794)) end
    end
end

function M.wrap_functions(functions)
    for name in pairs(unsafe_functions) do
        local fn = functions[name]
        if type(fn) == "function" then
            functions[name] = function(...)
                M.check_function(name)
                return fn(...)
            end
        end
    end
end

function M.ask(message, choices, default)
    local ExMsg = loadModule("lib.excmd.exmsg")
    local Backend = loadModule("lib.backend")
    local Event = loadModule("lib.event")
    local labels = {}
    for i, choice in ipairs(choices) do labels[i] = choice.label end
    ExMsg.BeginQuestion(message .. "\n" .. table.concat(labels, ", ") .. ": ")
    if tabpages[curtp] then tabpages[curtp]:render() end
    local ok, selected = pcall(function()
        local choice
        while choice == nil do
            local event = table.pack(Backend.current().pull_event())
            if event[1] == "char" then
                local char = tostring(event[2]):lower()
                for i, item in ipairs(choices) do if char == item.key then choice = i; break end end
            elseif event[1] == "key" then
                if event[2] == keys.enter then choice = default or 0 end
                if event[2] == keys.escape or event[2] == keys.esc then choice = 0 end
            elseif event[1] == "terminate" then
                choice = 0
            elseif event[1] ~= "key_up" then
                Event.ProcessEvent(event)
                if (event[1] == "monitor_resize" or event[1] == "term_resize") and tabpages[curtp] then
                    tabpages[curtp]:render()
                end
            end
        end
        return choice
    end)
    ExMsg.EndQuestion()
    if not ok then error(selected, 0) end
    return selected
end

function M.confirm_buffer(buf)
    local decision = M.get("confirm_decision")
    if decision ~= "all" and decision ~= "discardall" then
        local result = M.ask('Save changes to "' .. (buf.name or "") .. '"?', {
            {key = "y", label = "[Y]es"}, {key = "n", label = "(N)o"},
            {key = "a", label = "(A)ll"}, {key = "d", label = "(D)iscard All"},
            {key = "c", label = "(C)ancel"},
        }, 1)
        if result == 0 or result == 5 then return false end
        decision = ({"yes", "no", "all", "discardall"})[result]
        if decision == "all" or decision == "discardall" then
            for i = #stack, 1, -1 do
                if stack[i].confirm then stack[i].confirm_decision = decision; break end
            end
        end
    end
    if decision == "yes" or decision == "all" then
        local result = buf:write(false)
        if result == M.CANCELLED then return false end
        return result
    end
    return true
end

return M
