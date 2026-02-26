local CmdRead = {}

local Highlight = loadModule("lib.highlight")
local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local ExMsg = loadModule("lib.excmd.exmsg")
local Runtime = loadModule("lib.excmd.runtime")
local scopes = loadModule("lib.luaapi.scopes")

local pendingcmd = {}
local active = false

local crref = Key:new(keys.enter)
local bkspref = Key:new(keys.backspace)
local tabref = Key:new(keys.tab)

local function endRead()
    pendingcmd = {}
    active = false
    table.remove(Command.override_emitter)
    table.remove(Command.emitter_names)
end

local function current_cmdline_string()
    return Key.seqtostr(pendingcmd)
end

local function handler(k)
        if k:emittable() then
            if k == crref then
            local str = current_cmdline_string()
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
            ExMsg.Finalize()
        else
            if k == bkspref then
                table.remove(pendingcmd)
                if #pendingcmd == 0 then
                    endRead()
                    ExMsg.exitRead()
                end
            elseif k == tabref then
                -- TODO: completion
                LOG_ERROR("Tab not handled in cmdread")
            else
                table.insert(pendingcmd, k)
            end
            what_redraw["commandline"] = true
            need_redraw = true
        end
    end
end

function CmdRead.read()
    table.insert(Command.override_emitter, handler)
    table.insert(Command.emitter_names, "CmdRead.handler")

    active = true
    pendingcmd = { Key:new(keys.semiColon, false, true) }

    what_redraw["commandline"] = true
    need_redraw = true
end

function CmdRead.is_active()
    return active
end

function CmdRead.drawCmdline()
    local cmdheight = options.get("cmdheight")

    local cmd = current_cmdline_string()

    -- TODO: wrap this around on cmdheight > 1
    if cmdheight == 1 then
        Highlight.SetFor("MsgArea")
        term.setCursorPos(1, screen.height)
        local start = math.max(#cmd - screen.width + 1, 1)
        term.write(cmd:sub(start))
    else
        error("UNHANDLED: MULTILINE CMDHEIGHT")
    end
end

function CmdRead.getline()
    return current_cmdline_string()
end

function CmdRead.getpos()
    return #pendingcmd + 1
end

function CmdRead.setline(str, pos)
    local seq = Key.strtoseq(tostring(str or ""))
    pendingcmd = seq
    if pos ~= nil then
        -- TODO: support explicit cmdline cursor position; currently ignored.
        local _ = tonumber(pos)
    end
    what_redraw["commandline"] = true
    need_redraw = true
    return 0
end

return CmdRead
