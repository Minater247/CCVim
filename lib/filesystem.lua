local Filesystem = {}

local Error = loadModule("lib.error")
local ScriptSource = loadModule("lib.scriptsource")
local Scopes = loadModule("lib.luaapi.scopes")
local Runtime = loadModule("lib.excmd.runtime")
local VimFs = loadModule("lib.luaapi.fs")

local function _is_scheme(path)
    return type(path) == "string" and path:match("^%a[%w+.-]*://") ~= nil
end

local function _normalize_autocmd_path(path)
    if type(path) ~= "string" or path == "" then return path or "" end
    if _is_scheme(path) then return path end
    return VimFs.editor_abspath(path)
end

local function _expand_sid()
    local sid = tonumber(Runtime.CurrentScriptSid())

    -- Fallback: if only script context is available, derive SID from canonicalization.
    if not sid then
        local ctx = ScriptSource.CurrentContext()
        if type(ctx) == "string" and ctx ~= "" then
            local canon = Runtime.CanonicalFunctionName("s:_sid_probe", { script_ctx = ctx })
            sid = tonumber(tostring(canon or ""):match("^<SNR>(%d+)_"))
        end
    end

    if sid then
        return "<SNR>" .. tostring(sid) .. "_"
    end
    return Error(81)
end

function Filesystem.ExpandWildcards(path)
    -- Expand Unix-style wildcards (* and ?) in a filesystem path.
    -- Returns a list (table) of absolute paths matching the pattern.
    -- Examples:
    --   ExpandWildcards("/foo/*.vim") -> {"/foo/a.vim", "/foo/b.vim", ...}
    --   ExpandWildcards("foo/bar?.lua") -> matches under cwd
    -- Notes:
    --   - Supports '*', '?', '[...]', and '**' (zero-or-more directories).
    --   - Supports simple/nested brace expansion: "{a,b}".
    --   - Intermediate path segments may contain wildcards.
    --   - Non-matching segments yield an empty list.
    local function has_glob(s)
        return s:find("[%*%?%[]") ~= nil
    end

    local function find_brace_span(s)
        local depth = 0
        local open_at = nil
        for i = 1, #s do
            local ch = s:sub(i, i)
            if ch == "{" then
                if depth == 0 then
                    open_at = i
                end
                depth = depth + 1
            elseif ch == "}" and depth > 0 then
                depth = depth - 1
                if depth == 0 then
                    return open_at, i
                end
            end
        end
        return nil, nil
    end

    local function split_brace_parts(s)
        local out = {}
        local depth = 0
        local start = 1
        for i = 1, #s do
            local ch = s:sub(i, i)
            if ch == "{" then
                depth = depth + 1
            elseif ch == "}" and depth > 0 then
                depth = depth - 1
            elseif ch == "," and depth == 0 then
                out[#out + 1] = s:sub(start, i - 1)
                start = i + 1
            end
        end
        out[#out + 1] = s:sub(start)
        return out
    end

    local function expand_braces(s)
        local open_at, close_at = find_brace_span(s)
        if not open_at then
            return { s }
        end

        local inner = s:sub(open_at + 1, close_at - 1)
        if not inner:find(",", 1, true) then
            return { s }
        end

        local prefix = s:sub(1, open_at - 1)
        local suffix = s:sub(close_at + 1)
        local out = {}
        local parts = split_brace_parts(inner)
        for i = 1, #parts do
            local expanded = expand_braces(prefix .. parts[i] .. suffix)
            for j = 1, #expanded do
                out[#out + 1] = expanded[j]
            end
        end
        return out
    end

    local function to_lua_pattern(glob)
        local function esc(ch)
            if ch == "^" or ch == "$" or ch == "(" or ch == ")" or ch == "%" or ch == "." or ch == "[" or ch == "]"
                or ch == "+" or ch == "-" then
                return "%" .. ch
            end
            return ch
        end

        local out = { "^" }
        local i = 1
        local n = #glob
        while i <= n do
            local ch = glob:sub(i, i)
            if ch == "*" then
                out[#out + 1] = ".*"
                i = i + 1
            elseif ch == "?" then
                out[#out + 1] = "."
                i = i + 1
            elseif ch == "[" then
                local j = i + 1
                while j <= n and glob:sub(j, j) ~= "]" do
                    j = j + 1
                end

                if j > n then
                    out[#out + 1] = "%["
                    i = i + 1
                else
                    local cls = glob:sub(i + 1, j - 1)
                    local neg = false
                    if cls:sub(1, 1) == "!" or cls:sub(1, 1) == "^" then
                        neg = true
                        cls = cls:sub(2)
                    end

                    cls = cls:gsub("%%", "%%%%")
                    cls = cls:gsub("%]", "%%]")

                    if neg then
                        out[#out + 1] = "[^" .. cls .. "]"
                    else
                        out[#out + 1] = "[" .. cls .. "]"
                    end
                    i = j + 1
                end
            else
                out[#out + 1] = esc(ch)
                i = i + 1
            end
        end
        out[#out + 1] = "$"
        return table.concat(out)
    end

    local function join(parent, child)
        if parent == "/" then return "/" .. child end
        if parent:sub(-1) == "/" then return parent .. child end
        return parent .. "/" .. child
    end

    local function list_sorted(dir)
        local dirs, files = {}, {}
        local entries = fs.list(dir) or {}
        for i = 1, #entries do
            local name = entries[i]
            local child = join(dir, name)
            if fs.isDir(child) then
                dirs[#dirs + 1] = name
            else
                files[#files + 1] = name
            end
        end
        table.sort(dirs)
        table.sort(files)
        for i = 1, #files do
            dirs[#dirs + 1] = files[i]
        end
        return dirs
    end

    local function glob_matches_dotfiles(seg)
        return seg:sub(1, 1) == "."
    end

    -- Resolve to an absolute path first so expansion is deterministic
    local abs = VimFs.editor_abspath(path)

    local results = {}

    local expanded_inputs = expand_braces(abs)
    for _, expanded_path in ipairs(expanded_inputs) do
        -- Split into segments, skipping any empty parts (leading slash)
        local segs = {}
        for seg in expanded_path:gmatch("[^/]+") do segs[#segs + 1] = seg end

        local function expand_from(base, idx)
            if idx > #segs then
                results[#results + 1] = base
                return
            end

            local seg = segs[idx]
            local is_last = (idx == #segs)

            if seg == "**" then
                -- Match zero directory segments
                expand_from(base, idx + 1)
                -- Match one or more directory segments
                if fs.isDir(base) then
                    for _, name in ipairs(list_sorted(base)) do
                        local child = join(base, name)
                        if fs.isDir(child) then
                            expand_from(child, idx)
                        end
                    end
                end
                return
            end

            if has_glob(seg) then
                local patt = to_lua_pattern(seg)
                if fs.isDir(base) then
                    local names = list_sorted(base)
                    if glob_matches_dotfiles(seg) then
                        table.insert(names, 1, "..")
                        table.insert(names, 1, ".")
                    end
                    for _, name in ipairs(names) do
                        if (name:sub(1, 1) ~= "." or glob_matches_dotfiles(seg)) and name:match(patt) then
                            local child = join(base, name)
                            if is_last or fs.isDir(child) then
                                expand_from(child, idx + 1)
                            end
                        end
                    end
                end
            else
                local child = join(base, seg)
                if fs.exists(child) then
                    if is_last or fs.isDir(child) then
                        expand_from(child, idx + 1)
                    end
                end
            end
        end

        expand_from("/", 1)
    end

    if #results == 0 then
        return {}
    end

    local out, seen = {}, {}
    for _, p in ipairs(results) do
        if not seen[p] then
            out[#out + 1] = p
            seen[p] = true
        end
    end

    return out
end

function Filesystem.Expand(str)
    local expansions = {}

    if str:sub(1, 1) == "%" then
        str = str:sub(2)
        local name = windows[curwin].buffer.name or ""
        if name == nil then name = "" end
        expansions = { name }
    elseif str:sub(1, 1) == "<" then
        local brack, rest = str:match("^<([^>]+)>(.*)$")
        local brack_l = tostring(brack or ""):lower()

        if brack_l == "sfile" then
            expansions = { ScriptSource.CurrentContext() }
            str = rest
        elseif brack_l == "amatch" or brack_l == "afile" or brack_l == "abuf" then
            local ve = Scopes._v and Scopes._v.event or {}
            if brack_l == "amatch" then
                local v = ve.match
                if v == nil or v == "" then
                    v = ve.file or windows[curwin].buffer.name or ""
                end
                local ev = tostring(ve.event or "")
                local is_path_event = ev:match("^Buf") ~= nil or (ev:match("^File") ~= nil and ev ~= "FileType")
                if is_path_event and ve.match ~= nil and ve.file ~= nil and tostring(ve.match) == tostring(ve.file) then
                    v = _normalize_autocmd_path(v)
                end
                expansions = { tostring(v) }
            elseif brack_l == "afile" then
                local v = ve.file or windows[curwin].buffer.name or ""
                expansions = { _normalize_autocmd_path(v) }
            else -- abuf
                local v = ve.buf or windows[curwin].buffer.bufnr
                expansions = { tostring(v) }
            end
            str = rest
        elseif brack_l == "sid" then
            local sid = _expand_sid()
            if Error.IsError(sid) then
                return sid
            end
            expansions = { sid }
            str = rest
        else
            error("UNHANDLED: expand(\"<" .. brack .. ">\"): " .. str)
        end
    elseif str:sub(1, 1) == "#" then
        error("UNHANDLED: expand(\"#...\"): " .. str)
    else
        local out = str:match("^([^:]*)") or ""
        str = str:sub(#out + 1)
        expansions = { out }
    end

    -- suffixes

    while #str > 0 do
        local c = str:sub(1, 1)
        if c == ":" then
            c = str:sub(2, 2)
            if c == "t" then
                for i = 1, #expansions do
                    local name = expansions[i]:match("([^/]+)/*$") or expansions[i]
                    expansions[i] = name
                end
            elseif c == "h" then
                -- Head: remove the last path component
                for i = 1, #expansions do
                    local p = expansions[i]
                    -- strip trailing slashes (but keep root '/')
                    p = p:gsub("/+$", "")
                    if p == "" then p = "/" end
                    if p == "/" then
                        expansions[i] = "/"
                    else
                        local head = p:match("^(.*)/[^/]*$")
                        if not head or head == "" then
                            expansions[i] = "."
                        else
                            expansions[i] = head
                        end
                    end
                end
            elseif c == "p" then
                for i = 1, #expansions do
                    local v = expansions[i]
                    if v == "" then
                        expansions[i] = ""
                    else
                        expansions[i] = VimFs.abspath(v)
                    end
                end
            elseif c == "r" then
                -- Root: remove one file extension from the last path component
                for i = 1, #expansions do
                    local p = expansions[i]
                    -- remove trailing slashes for processing
                    local s = p:gsub("/+$", "")
                    if s == "" then s = "/" end
                    if s == "/" then
                        -- root stays root
                        expansions[i] = s
                    else
                        local dir, base = s:match("^(.*)/([^/]*)$")
                        if not dir then dir, base = "", s end
                        -- find last '.' not at position 1
                        local last
                        for idx = 2, #base do
                            if base:sub(idx, idx) == "." then last = idx end
                        end
                        local newbase = base
                        if last then newbase = base:sub(1, last - 1) end
                        if dir == "" then
                            expansions[i] = newbase
                        else
                            expansions[i] = dir .. "/" .. newbase
                        end
                    end
                end
            elseif c == "e" then
                -- Extension only: keep only the extension (after last '.' in tail)
                for i = 1, #expansions do
                    local p = expansions[i]
                    local s = p:gsub("/+$", "")
                    if s == "" or s == "/" then
                        expansions[i] = ""
                    else
                        local base = s:match("([^/]+)$") or s
                        -- find last '.' not at position 1
                        local last
                        for idx = 2, #base do
                            if base:sub(idx, idx) == "." then last = idx end
                        end
                        if last then
                            expansions[i] = base:sub(last + 1)
                        else
                            expansions[i] = ""
                        end
                    end
                end
            else
                error("expand(): unknown ':' char: " .. c .. "(full string " .. str .. ")")
            end
            str = str:sub(3)
        else
            break
        end
    end

    for i, v in ipairs(expansions) do
        expansions[i] = v .. str
    end

    if #expansions == 1 then
        expansions = expansions[1]
    end

    return expansions
end

return Filesystem
