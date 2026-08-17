-- vim.lib.excmd.commands
local Commands = {}

local Error = loadModule("lib.error")

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local COMMAND_SPECS = {
    { name = "silent", min = 3, dispatch = true },
    { name = "unsilent", min = 3, dispatch = true },
    { name = "let", min = 3, comment_mode = "expr" },
    { name = "if", min = 2, comment_mode = "expr" },
    { name = "elseif", min = 5, comment_mode = "expr" },
    { name = "else", min = 2 },
    { name = "endif", min = 2 },
    { name = "while", min = 2, comment_mode = "expr" },
    { name = "endwhile", min = 4 },
    { name = "for", min = 3, comment_mode = "expr" },
    { name = "endfor", min = 5 },
    { name = "break", min = 4 },
    { name = "continue", min = 3 },
    { name = "try", min = 3 },
    { name = "catch", min = 3 },
    { name = "finally", min = 4 },
    { name = "endtry", min = 4 },
    { name = "throw", min = 2, comment_mode = "expr" },
    { name = "function", min = 2, comment_mode = "expr" },
    { name = "endfunction", min = 4 },
    { name = "return", min = 4, comment_mode = "expr" },
    { name = "finish", min = 2, dispatch = true },
    { name = "call", min = 3, comment_mode = "expr" },
    { name = "execute", min = 3, comment_mode = "expr" },
    { name = "unlet", min = 3 },
    { name = "command", min = 3, dispatch = true, no_bar_split = true },
    { name = "autocmd", min = 2, no_bar_split = true },
    { name = "syntax", min = 3, dispatch = true, no_bar_split = true },
    { name = "sign", min = 3, dispatch = true, no_bar_split = true },
    { name = "highlight", min = 2, dispatch = true },
    { name = "colorscheme", min = 4, dispatch = true },
    { name = "runtime", min = 2, dispatch = true },
    { name = "augroup", min = 3, dispatch = true },
    { name = "source", min = 2, dispatch = true },
    { name = "filetype", min = 5, dispatch = true },
    { name = "doautoall", min = 7, dispatch = true },
    { name = "set", min = 2 },
    { name = "packadd", min = 2, dispatch = true },
    { name = "verbose", min = 4 },
    { name = "echo", min = 2, dispatch = true, addr = "none" },
    { name = "echoerr", min = 5, dispatch = true, addr = "none" },
    { name = "echohl", min = 5, dispatch = true, addr = "none" },
    { name = "echomsg", min = 5, dispatch = true, addr = "none" },
    { name = "echon", min = 5, dispatch = true, addr = "none" },
    { name = "nnoremap", min = 2, dispatch = true,
        map = { action = "map", recursive = false, modes = "n", min_abbrev = 2 } },
    { name = "xnoremap", min = 2, dispatch = true,
        map = { action = "map", recursive = false, modes = "x", min_abbrev = 2 } },
    { name = "inoremap", min = 3, dispatch = true,
        map = { action = "map", recursive = false, modes = "i", min_abbrev = 3 } },
    { name = "onoremap", min = 3, dispatch = true,
        map = { action = "map", recursive = false, modes = "o", min_abbrev = 3 } },
    { name = "xmap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "x", min_abbrev = 2 } },
    { name = "nmap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "n", min_abbrev = 2 } },
    { name = "omap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "o", min_abbrev = 2 } },
    { name = "imap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "i", min_abbrev = 2 } },
    { name = "nunmap", min = 3, dispatch = true, map = { action = "unmap", modes = "n", min_abbrev = 3 } },
    { name = "xunmap", min = 2, dispatch = true, map = { action = "unmap", modes = "x", min_abbrev = 2 } },
    { name = "ounmap", min = 2, dispatch = true, map = { action = "unmap", modes = "o", min_abbrev = 2 } },
    { name = "defer", min = 4 },
    { name = "noautocmd", min = 3 },
    { name = "windo", min = 4, dispatch = true, no_bar_split = true },
    { name = "quit", min = 1, dispatch = true, addr = "none" },
    { name = "close", min = 3, dispatch = true, addr = "count" },
    { name = "wincmd", min = 4, dispatch = true, addr = "count" },
    { name = "setfiletype", min = 4, dispatch = true },
    { name = "setlocal", min = 4, dispatch = true },
    { name = "put", min = 2, dispatch = true },
    { name = "sort", min = 3, dispatch = true, addr = "line" },
    { name = "global", min = 1, dispatch = true, no_bar_split = true, addr = "line" },
    { name = "v", min = 1, dispatch = true, no_bar_split = true, addr = "line" },
    { name = "vglobal", min = 2, dispatch = true, no_bar_split = true, addr = "line" },
    { name = "substitute", min = 1, dispatch = true, addr = "line" },
    { name = "edit", min = 1, dispatch = true },
    { name = "file", min = 1, dispatch = true },
    { name = "delete", min = 1, dispatch = true, addr = "line" },
    { name = "mark", min = 2, dispatch = true },
    { name = "undo", min = 1, dispatch = true },
    { name = "redo", min = 3, dispatch = true },
    { name = "undojoin", min = 5, dispatch = true },

    { name = "map", min = 3, dispatch = true,
        map = { action = "map", recursive = true, modes = "", bang_modes = "ic", min_abbrev = 3 } },
    { name = "vmap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "vs", min_abbrev = 2 } },
    { name = "smap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "s", min_abbrev = 2 } },
    { name = "lmap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "l", min_abbrev = 2 } },
    { name = "cmap", min = 2, dispatch = true,
        map = { action = "map", recursive = true, modes = "c", min_abbrev = 2 } },
    { name = "tmap", min = 3, dispatch = true,
        map = { action = "map", recursive = true, modes = "t", min_abbrev = 3 } },
    { name = "noremap", min = 2, dispatch = true,
        map = { action = "map", recursive = false, modes = "", bang_modes = "ic", min_abbrev = 2 } },
    { name = "vnoremap", min = 2, dispatch = true,
        map = { action = "map", recursive = false, modes = "vs", min_abbrev = 2 } },
    { name = "snoremap", min = 4, dispatch = true,
        map = { action = "map", recursive = false, modes = "s", min_abbrev = 4 } },
    { name = "lnoremap", min = 2, dispatch = true,
        map = { action = "map", recursive = false, modes = "l", min_abbrev = 2 } },
    { name = "cnoremap", min = 3, dispatch = true,
        map = { action = "map", recursive = false, modes = "c", min_abbrev = 3 } },
    { name = "tnoremap", min = 3, dispatch = true,
        map = { action = "map", recursive = false, modes = "t", min_abbrev = 3 } },
    { name = "unmap", min = 3, dispatch = true,
        map = { action = "unmap", modes = "", bang_modes = "ic", min_abbrev = 3 } },
    { name = "vunmap", min = 2, dispatch = true, map = { action = "unmap", modes = "vs", min_abbrev = 2 } },
    { name = "sunmap", min = 4, dispatch = true, map = { action = "unmap", modes = "s", min_abbrev = 4 } },
    { name = "iunmap", min = 2, dispatch = true, map = { action = "unmap", modes = "i", min_abbrev = 2 } },
    { name = "lunmap", min = 2, dispatch = true, map = { action = "unmap", modes = "l", min_abbrev = 2 } },
    { name = "cunmap", min = 2, dispatch = true, map = { action = "unmap", modes = "c", min_abbrev = 2 } },
    { name = "tunmap", min = 5, dispatch = true, map = { action = "unmap", modes = "t", min_abbrev = 5 } },
    { name = "mapclear", min = 4, dispatch = true,
        map = { action = "clear", modes = "", bang_modes = "ic", min_abbrev = 4 } },
    { name = "nmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "n", min_abbrev = 5 } },
    { name = "vmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "vs", min_abbrev = 5 } },
    { name = "xmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "x", min_abbrev = 5 } },
    { name = "smapclear", min = 5, dispatch = true, map = { action = "clear", modes = "s", min_abbrev = 5 } },
    { name = "omapclear", min = 5, dispatch = true, map = { action = "clear", modes = "o", min_abbrev = 5 } },
    { name = "imapclear", min = 5, dispatch = true, map = { action = "clear", modes = "i", min_abbrev = 5 } },
    { name = "lmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "l", min_abbrev = 5 } },
    { name = "cmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "c", min_abbrev = 5 } },
    { name = "tmapclear", min = 5, dispatch = true, map = { action = "clear", modes = "t", min_abbrev = 5 } },

    { name = "menu", min = 2, dispatch = true, menu = { action = "define", modes = "nvo", recursive = true } },
    { name = "noremenu", min = 6, dispatch = true, menu = { action = "define", modes = "nvo", recursive = false } },
    { name = "unmenu", min = 4, dispatch = true, menu = { action = "remove", modes = "nvo" } },
    { name = "amenu", min = 2, dispatch = true, menu = { action = "define", modes = "a", recursive = true } },
    { name = "anoremenu", min = 2, dispatch = true, menu = { action = "define", modes = "a", recursive = false } },
    { name = "aunmenu", min = 3, dispatch = true, menu = { action = "remove", modes = "a" } },
    { name = "nmenu", min = 3, dispatch = true, menu = { action = "define", modes = "n", recursive = true } },
    { name = "nnoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "n", recursive = false } },
    { name = "nunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "n" } },
    { name = "vmenu", min = 3, dispatch = true, menu = { action = "define", modes = "vs", recursive = true } },
    { name = "vnoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "vs", recursive = false } },
    { name = "vunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "vs" } },
    { name = "xmenu", min = 3, dispatch = true, menu = { action = "define", modes = "x", recursive = true } },
    { name = "xnoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "x", recursive = false } },
    { name = "xunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "x" } },
    { name = "smenu", min = 3, dispatch = true, menu = { action = "define", modes = "s", recursive = true } },
    { name = "snoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "s", recursive = false } },
    { name = "sunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "s" } },
    { name = "omenu", min = 3, dispatch = true, menu = { action = "define", modes = "o", recursive = true } },
    { name = "onoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "o", recursive = false } },
    { name = "ounmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "o" } },
    { name = "imenu", min = 3, dispatch = true, menu = { action = "define", modes = "i", recursive = true } },
    { name = "inoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "i", recursive = false } },
    { name = "iunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "i" } },
    { name = "cmenu", min = 3, dispatch = true, menu = { action = "define", modes = "c", recursive = true } },
    { name = "cnoremenu", min = 7, dispatch = true, menu = { action = "define", modes = "c", recursive = false } },
    { name = "cunmenu", min = 5, dispatch = true, menu = { action = "remove", modes = "c" } },
    { name = "emenu", min = 2, dispatch = true, menu = { action = "execute", modes = "a" } },
    { name = "tmenu", min = 2, dispatch = true, menu = { action = "tooltip", modes = "t" } },
    { name = "tlmenu", min = 3, dispatch = true, menu = { action = "define", modes = "tl", recursive = true } },
    { name = "tlnoremenu", min = 3, dispatch = true, menu = { action = "define", modes = "tl", recursive = false } },
    { name = "tlunmenu", min = 3, dispatch = true, menu = { action = "remove", modes = "tl" } },
    { name = "tunmenu", min = 2, dispatch = true, menu = { action = "tooltip_remove", modes = "t" } },
    { name = "menutranslate", min = 5, dispatch = true, menu = { action = "translate", modes = "" } },

    { name = "keepjumps", min = 5, dispatch = true },
    { name = "keepalt", min = 5, dispatch = true },
    { name = "keeppatterns", min = 5, dispatch = true },
    { name = "leftabove", min = 5, dispatch = true },
    { name = "aboveleft", min = 3, dispatch = true },
    { name = "rightbelow", min = 6, dispatch = true },
    { name = "belowright", min = 3, dispatch = true },
    { name = "topleft", min = 2, dispatch = true },
    { name = "botright", min = 2, dispatch = true },
    { name = "vertical", min = 4, dispatch = true },
    { name = "horizontal", min = 3, dispatch = true },
    { name = "doautocmd", min = 4, dispatch = true },
    { name = "delcommand", min = 4, dispatch = true },
    { name = "delfunction", min = 4, dispatch = true },
    { name = "comclear", min = 4, dispatch = true },
    { name = "buffer", min = 2, dispatch = true, addr = "count" },
    { name = "enew", min = 3, dispatch = true },
    { name = "find", min = 2, dispatch = true },
    { name = "sfind", min = 3, dispatch = true },
    { name = "tabfind", min = 4, dispatch = true },
    { name = "tabnew", min = 4, dispatch = true },
    { name = "tabedit", min = 4, dispatch = true },
    { name = "tabnext", min = 4, dispatch = true },
    { name = "tabprevious", min = 7, dispatch = true },
    { name = "tabclose", min = 4, dispatch = true },
    { name = "drop", min = 2, dispatch = true },
    { name = "help", min = 1, dispatch = true },
    { name = "lcd", min = 2, dispatch = true },
    { name = "tcd", min = 2, dispatch = true },
    { name = "lua", min = 2, dispatch = true, no_bar_split = true },
    { name = "messages", min = 3, dispatch = true },
    { name = "redir", min = 4, dispatch = true },
    { name = "setglobal", min = 4, dispatch = true },
    { name = "normal", min = 4, dispatch = true, no_bar_split = true, addr = "line" },
    { name = "mode", min = 3, dispatch = true },
    { name = "redraw", min = 4, dispatch = true },
    { name = "redrawstatus", min = 7, dispatch = true },
    { name = "redrawtabline", min = 7, dispatch = true },
    { name = "resize", min = 3, dispatch = true, addr = "count", structured_addr = "none" },
    { name = "split", min = 2, dispatch = true, addr = "line" },
    { name = "vsplit", min = 2, dispatch = true, addr = "line" },
    { name = "write", min = 1, dispatch = true },
    { name = "wq", min = 2, dispatch = true },
    { name = "syntime", min = 4, dispatch = true },
    { name = "ownsyntax", min = 3, dispatch = true },
    { name = "match", min = 3, dispatch = true, no_bar_split = true },
    { name = "pwd", min = 2, dispatch = true },
    { name = "copy", min = 2, dispatch = true, addr = "line" },
    { name = "t", min = 1, dispatch = true, addr = "line" },
    { name = "move", min = 1, dispatch = true, addr = "line" },
}

local SPEC_BY_NAME = {}
local PARSE_REGISTRY_BY_FIRST = {}
local DISPATCH_MIN_ABBREV = {}
local DISPATCH_REGISTRY_BY_FIRST = {}
local MAP_COMMAND_SPECS = {}
local MENU_COMMAND_SPECS = {}
local EMPTY_REGISTRY = {}

local function add_registry(by_first, entry)
    local first = entry.name:sub(1, 1)
    local bucket = by_first[first]
    if not bucket then
        bucket = {}
        by_first[first] = bucket
    end
    bucket[#bucket + 1] = entry
end

local function normalize_prefix(raw)
    local prefix = tostring(raw):lower()
    local bang_end = #prefix
    while bang_end > 0 and prefix:byte(bang_end) == 33 do
        bang_end = bang_end - 1
    end
    if bang_end ~= #prefix then
        prefix = prefix:sub(1, bang_end)
    end
    return prefix
end

for _, spec in ipairs(COMMAND_SPECS) do
    SPEC_BY_NAME[spec.name] = spec
    if spec.min then
        add_registry(PARSE_REGISTRY_BY_FIRST, { name = spec.name, min = spec.min })
    end
    if spec.dispatch then
        DISPATCH_MIN_ABBREV[spec.name] = spec.min
        add_registry(DISPATCH_REGISTRY_BY_FIRST, { name = spec.name, min = spec.min })
    end
    if spec.map then
        MAP_COMMAND_SPECS[spec.name] = spec.map
    end
    if spec.menu then
        MENU_COMMAND_SPECS[spec.name] = spec.menu
    end
end

local function resolve_prefix(raw, by_first, exact_names, fallback_raw, sort_matches)
    if not raw or raw == "" then
        return nil
    end
    local prefix = normalize_prefix(raw)
    local prefix_len = #prefix
    if exact_names[prefix] then
        return prefix
    end
    local delete_name = "delete"
    if delete_name:find(prefix, 1, true) ~= 1 then
        local tail = prefix:sub(-1)
        if (tail == "l" or tail == "p") and prefix_len > 1 then
            local base = prefix:sub(1, -2)
            if delete_name:find(base, 1, true) == 1 then
                return delete_name
            end
        end
    end
    local registry = by_first[prefix:sub(1, 1)] or EMPTY_REGISTRY
    local first
    local matches
    local match_count = 0
    for i = 1, #registry do
        local e = registry[i]
        if prefix_len >= e.min and e.name:find(prefix, 1, true) == 1 then
            match_count = match_count + 1
            if match_count == 1 then
                first = e.name
            else
                if not matches then
                    matches = { first }
                end
                matches[#matches + 1] = e.name
            end
        end
    end
    if match_count == 1 then
        return first
    end
    if match_count == 0 then
        if fallback_raw then
            return trim(raw)
        end
        return nil
    end
    if sort_matches then
        table.sort(matches)
    end
    return nil, Error(464, prefix, table.concat(matches, ", "))
end

function Commands.resolve_parse_name(raw)
    return resolve_prefix(raw, PARSE_REGISTRY_BY_FIRST, SPEC_BY_NAME, true, false)
end

function Commands.resolve_dispatch_name(prefix)
    return resolve_prefix(prefix, DISPATCH_REGISTRY_BY_FIRST, DISPATCH_MIN_ABBREV, false, true)
end

function Commands.mode_and_bar(cmd_raw)
    if not cmd_raw or cmd_raw == "" then
        return "commentable", false
    end
    local spec = SPEC_BY_NAME[normalize_prefix(cmd_raw)]
    if not spec then
        local canonical = Commands.resolve_parse_name(cmd_raw)
        if type(canonical) ~= "string" or canonical == "" then
            return "commentable", false
        end
        spec = SPEC_BY_NAME[canonical]
        if not spec then
            return "raw", false
        end
    end
    local mode = spec.comment_mode or "raw"
    local no_bar = spec.no_bar_split == true
    return mode, no_bar
end

Commands.COMMAND_SPECS = COMMAND_SPECS
Commands.DISPATCH_MIN_ABBREV = DISPATCH_MIN_ABBREV
Commands.MAP_COMMAND_SPECS = MAP_COMMAND_SPECS
Commands.MENU_COMMAND_SPECS = MENU_COMMAND_SPECS

function Commands.get_spec(name)
    if type(name) ~= "string" then
        return nil
    end
    return SPEC_BY_NAME[name:lower()]
end

return Commands
