local Syntax = {}

local function load_engine()
    if Syntax._syntax_engine_api then
        return Syntax._syntax_engine_api
    end

    local chunk, err = loadfile(ccvim_path .. "/lib/syntax_engine/api.lua", "t", _ENV)
    if not chunk then
        error("Failed to load syntax engine API: " .. tostring(err))
    end

    local mod = chunk()
    Syntax._syntax_engine_api = mod
    return mod
end

local Engine = load_engine()

function Syntax.ParseLinetypes(buffer, index)
    return Engine.invalidate_from_line(buffer, index)
end

function Syntax.LineToBlit(buffer, index, window)
    return Engine.line_to_blit(buffer, index, window)
end

function Syntax.LinesToBlit(buffer, first_line, last_line, window)
    return Engine.lines_to_blit(buffer, first_line, last_line, window)
end

function Syntax.OnSyntaxOptionSet(buffer, value)
    return Engine.on_syntax_option(buffer, value)
end

function Syntax.OnSynmaxcolOptionSet(buffer, value)
    return Engine.on_synmaxcol_option(buffer, value)
end

function Syntax.ClearBuffer(buffer)
    return Engine.clear_buffer(buffer)
end

function Syntax.OwnSyntax(window, name)
    return Engine.ownsyntax(window, name)
end

function Syntax.OnWindowBufferChanged(window)
    return Engine.on_window_buffer_changed(window)
end

function Syntax.SyntimeSet(window, enabled)
    return Engine.syntime_set(window, enabled)
end

function Syntax.SyntimeClear(window)
    return Engine.syntime_clear(window)
end

function Syntax.SyntimeReport(window)
    return Engine.syntime_report(window)
end

function Syntax.ExecuteCommand(window, raw_cmd)
    return Engine.syntax_command(window, raw_cmd)
end

function Syntax.MatchCommand(window, slot, raw_args)
    return Engine.match_command(window, slot, raw_args)
end

function Syntax.MatchSet(window, slot, group, pattern)
    return Engine.match_set(window, slot, group, pattern)
end

function Syntax.MatchClear(window, slot)
    return Engine.match_clear(window, slot)
end

function Syntax.MatchGet(window)
    return Engine.match_get(window)
end

function Syntax.Query(window, lnum, col)
    return Engine.syn_query(window, lnum, col)
end

return Syntax
