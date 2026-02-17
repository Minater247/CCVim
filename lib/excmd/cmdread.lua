local CmdRead = {}

local Highlight = loadModule("vim.lib.highlight")
local Command = loadModule("vim.lib.command")
local Key = loadModule("vim.lib.key")
local ExMsg = loadModule("vim.lib.excmd.exmsg")
local Runtime = loadModule("vim.lib.excmd.runtime")
local scopes = loadModule("vim.lib.luaapi.scopes")

local pendingcmd = {}

local crref = Key:new(keys.enter)
local bkspref = Key:new(keys.backspace)
local tabref = Key:new(keys.tab)

local function endRead()
    pendingcmd = {}
    table.remove(Command.override_emitter)
    table.remove(Command.emitter_names)
end

local function handler(k)
    if k:emittable() then
        if k == crref then
            local str = Key.seqtostr(pendingcmd)
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

    pendingcmd = { Key:new(keys.semiColon, false, true) }

    what_redraw["commandline"] = true
    need_redraw = true
end

function CmdRead.drawCmdline()
    local cmdheight = options.get("cmdheight")

    local cmd = Key.seqtostr(pendingcmd)

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

return CmdRead
