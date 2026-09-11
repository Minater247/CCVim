local CmdRead = {}

local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local ExMsg = loadModule("lib.excmd.exmsg")
local Runtime = loadModule("lib.excmd.runtime")
local ScreenDraw = loadModule("lib.screendraw")
local scopes = loadModule("lib.luaapi.scopes")
local Completion = loadModule("lib.excmd.completion")
local PopupMenu = loadModule("lib.popupmenu")
local Backend = loadModule("lib.backend")
local Fn
local Autocmd

local pendingcmd = {}
local active = false
local cmdtype = ":"
local submit_handler
local change_handler
local cancel_handler

local crref = Key:new(keys.enter)
local bkspref = Key:new(keys.backspace)
local tabref = Key:new(keys.tab)

local function run_cmdline_event(event, abort)
    Autocmd = Autocmd or loadModule("lib.autocmd")
    Autocmd.Run(event, {
        pattern = cmdtype,
        data = {
            abort = abort == true,
            cmdlevel = 1,
            cmdtype = cmdtype,
        },
    })
end

local function endRead()
    pendingcmd = {}
    active = false
    cmdtype = ":"
    submit_handler = nil
    change_handler = nil
    cancel_handler = nil
    table.remove(Command.override_emitter)
    table.remove(Command.emitter_names)
end

local function current_cmdline_string()
    return Key.seqtostr(pendingcmd)
end

local function handler(k)
    local printable = k:printable()
    local cc_cancel = printable == "<C-Tab>" and Backend.current().kind == "cc"
    if printable == "<C-[>" or printable == "<Esc>" or cc_cancel then
        local handler_fn = cancel_handler
        run_cmdline_event("CmdlineLeave", true)
        endRead()
        if handler_fn then handler_fn() end
        ExMsg.exitRead()
        what_redraw.commandline = true
        need_redraw = true
        return
    end
    if k:emittable() then
        if k == crref then
            local str = current_cmdline_string()
            local handler_fn = submit_handler
            if handler_fn then
                handler_fn(str:sub(2))
                run_cmdline_event("CmdlineLeave", false)
                endRead()
            else
                run_cmdline_event("CmdlineLeave", false)
                endRead()
                local state = {
                    g = scopes._g,
                    s = {},
                    v = scopes._v,
                    funcs = Runtime._FUNCS,
                }
                local ok, err = Runtime.run(str, {
                    state = state,
                    origin = {
                        kind = "user-cmdline",
                    },
                })
                if not ok and err and err.toString then
                    ExMsg.echoerr(err:toString())
                end
            end
            ExMsg.Finalize()
        else
            if k == bkspref then
                table.remove(pendingcmd)
                if #pendingcmd == 0 then
                    local handler_fn = cancel_handler
                    run_cmdline_event("CmdlineLeave", true)
                    endRead()
                    if handler_fn then handler_fn() end
                    ExMsg.exitRead()
                end
            elseif k == tabref and cmdtype == ":" then
                local line = current_cmdline_string()
                Fn = Fn or loadModule("lib.luaapi.fn")
                local items, start = Completion.get(line, Runtime._USER_COMMANDS, {
                    call_function = Fn._call,
                })
                PopupMenu.cmdline(items, function(item)
                    if not item then return end
                    local next_line = line:sub(1, start - 1) .. item.word
                    pendingcmd = Key.strtoseq(next_line)
                    if change_handler then change_handler(CmdRead.getline()) end
                    run_cmdline_event("CmdlineChanged", false)
                    what_redraw.commandline = true
                    need_redraw = true
                end)
            else
                table.insert(pendingcmd, k)
            end
            if active and change_handler then
                change_handler(CmdRead.getline())
            end
            if active then run_cmdline_event("CmdlineChanged", false) end
            what_redraw["commandline"] = true
            need_redraw = true
        end
    end
end

function CmdRead.read(prefix, on_submit, on_change, on_cancel)
    table.insert(Command.override_emitter, handler)
    table.insert(Command.emitter_names, "CmdRead.handler")

    active = true
    cmdtype = prefix or ":"
    submit_handler = on_submit
    change_handler = on_change
    cancel_handler = on_cancel
    pendingcmd = Key.strtoseq(cmdtype)

    what_redraw["commandline"] = true
    need_redraw = true
    run_cmdline_event("CmdlineEnter", false)
end

function CmdRead.is_active()
    return active
end

function CmdRead.drawCmdline()
    local cmdheight = options.get("cmdheight")

    local cmd = current_cmdline_string()

    -- TODO: wrap this around on cmdheight > 1
    if cmdheight == 1 then
        local start = math.max(#cmd - screen.width + 1, 1)
        ScreenDraw.put_text(screen.height - 1, 0, cmd:sub(start), "MsgArea")
    else
        error("UNHANDLED: MULTILINE CMDHEIGHT")
    end
end

function CmdRead.getline()
    return current_cmdline_string():sub(2)
end

function CmdRead.getpos()
    return #pendingcmd
end

function CmdRead.gettype()
    return active and cmdtype or ""
end

function CmdRead.setline(str, pos)
    local seq = Key.strtoseq(tostring(str or ""))
    pendingcmd = Key.strtoseq(cmdtype)
    for i = 1, #seq do pendingcmd[#pendingcmd + 1] = seq[i] end
    if pos ~= nil then
        -- TODO: support explicit cmdline cursor position; currently ignored.
        local _ = tonumber(pos)
    end
    if change_handler then change_handler(CmdRead.getline()) end
    run_cmdline_event("CmdlineChanged", false)
    what_redraw["commandline"] = true
    need_redraw = true
    return 0
end

return CmdRead
