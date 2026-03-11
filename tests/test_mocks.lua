local MockEnv = {}

-- Capture real OS functions before mocking
local real_os_clock = os.clock
local real_os_getenv = os.getenv
local real_os_time = os.time
local real_os_date = os.date
local real_os_exit = os.exit
local real_os_remove = os.remove
local real_os_rename = os.rename
local real_loadfile = loadfile
local has_lfs, lfs = pcall(require, "lfs")
if not has_lfs then
    error("test_mocks.lua requires LuaFileSystem (lfs)")
end

local function now_ms()
    return math.floor(real_os_clock() * 1000)
end

local function default_pid()
    local env_pid = real_os_getenv("NVIM_TEST_PID")
    if env_pid and env_pid ~= "" then
        return tonumber(env_pid) or 0
    end
    return 0
end

local function lfs_attr(path)
    return lfs.attributes(path)
end

local function mkdir_p(path)
    local attr = lfs_attr(path)
    if attr then
        if attr.mode ~= "directory" then
            error("path exists and is not a directory")
        end
        return true
    end

    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and parent ~= path and not lfs_attr(parent) then
        mkdir_p(parent)
    end

    local ok, err = lfs.mkdir(path)
    if not ok and not lfs_attr(path) then
        error(err or "cannot create directory")
    end
    return true
end

local function remove_tree(path)
    local attr = lfs_attr(path)
    if not attr then
        return true
    end

    if attr.mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                local ok, err = remove_tree(path .. "/" .. name)
                if not ok then
                    return false, err
                end
            end
        end
        local ok, err = lfs.rmdir(path)
        return ok ~= nil, err
    end

    local ok, err = real_os_remove(path)
    return ok ~= nil, err
end

local function copy_file(src, dst)
    local in_f, in_err = io.open(src, "rb")
    if not in_f then
        return false, in_err
    end

    local out_f, out_err = io.open(dst, "wb")
    if not out_f then
        in_f:close()
        return false, out_err
    end

    while true do
        local chunk = in_f:read(64 * 1024)
        if not chunk then
            break
        end
        local ok, write_err = out_f:write(chunk)
        if not ok then
            in_f:close()
            out_f:close()
            return false, write_err
        end
    end

    in_f:close()
    out_f:close()
    return true
end

local function copy_tree(src, dst)
    local attr = lfs_attr(src)
    if not attr then
        return false, "source does not exist"
    end

    if attr.mode == "directory" then
        local ok, err = mkdir_p(dst)
        if not ok then
            return false, err
        end
        for name in lfs.dir(src) do
            if name ~= "." and name ~= ".." then
                local child_src = src .. "/" .. name
                local child_dst = dst .. "/" .. name
                local child_ok, child_err = copy_tree(child_src, child_dst)
                if not child_ok then
                    return false, child_err
                end
            end
        end
        return true
    end

    return copy_file(src, dst)
end

local function move_path(src, dst)
    local ok, err = real_os_rename(src, dst)
    if ok then
        return true
    end

    local copy_ok, copy_err = copy_tree(src, dst)
    if not copy_ok then
        return false, copy_err or err
    end

    local rm_ok, rm_err = remove_tree(src)
    if not rm_ok then
        return false, rm_err
    end
    return true
end

local function normalize_path(path)
    path = tostring(path or "")
    path = path:gsub("\\", "/")
    path = path:gsub("//+", "/")
    if path == "" then
        return "/"
    end

    local absolute = path:sub(1, 1) == "/"
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif not absolute then
                parts[#parts + 1] = ".."
            end
        elseif seg ~= "." then
            parts[#parts + 1] = seg
        end
    end

    local result = table.concat(parts, "/")
    if absolute then
        result = "/" .. result
    end
    result = result:gsub("//+", "/")
    if result == "" then
        return absolute and "/" or "."
    end
    return result
end

local function create_colors_api()
    local names = {
        "white",
        "orange",
        "magenta",
        "lightBlue",
        "yellow",
        "lime",
        "pink",
        "gray",
        "lightGray",
        "cyan",
        "purple",
        "blue",
        "brown",
        "green",
        "red",
        "black",
    }

    local colors = {}
    for i = 1, #names do
        colors[names[i]] = 2 ^ (i - 1)
    end
    colors.grey = colors.gray
    colors.lightGrey = colors.lightGray

    local blit = "0123456789abcdef"
    local map_to_blit = {}
    local map_from_blit = {}
    for i = 1, #blit do
        local ch = blit:sub(i, i)
        local mask = 2 ^ (i - 1)
        map_to_blit[mask] = ch
        map_from_blit[ch] = mask
    end

    function colors.combine(...)
        local n = 0
        for i = 1, select("#", ...) do
            local v = tonumber(select(i, ...)) or 0
            n = n | v
        end
        return n
    end

    function colors.subtract(c, ...)
        local n = tonumber(c) or 0
        for i = 1, select("#", ...) do
            local v = tonumber(select(i, ...)) or 0
            n = n & (~v)
        end
        return n
    end

    function colors.test(c, mask)
        c = tonumber(c) or 0
        mask = tonumber(mask) or 0
        return (c & mask) == mask
    end

    function colors.toBlit(mask)
        return map_to_blit[tonumber(mask) or 0]
    end

    function colors.fromBlit(ch)
        return map_from_blit[tostring(ch or ""):sub(1, 1):lower()]
    end

    function colors.packRGB(r, g, b)
        r = math.max(0, math.min(1, tonumber(r) or 0))
        g = math.max(0, math.min(1, tonumber(g) or 0))
        b = math.max(0, math.min(1, tonumber(b) or 0))
        return math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256 + math.floor(b * 255 + 0.5)
    end

    function colors.unpackRGB(rgb)
        rgb = tonumber(rgb) or 0
        local r = math.floor(rgb / 65536) % 256
        local g = math.floor(rgb / 256) % 256
        local b = rgb % 256
        return r / 255, g / 255, b / 255
    end

    function colors.rgb8(r, g, b)
        r = tonumber(r) or 0
        g = tonumber(g) or 0
        b = tonumber(b) or 0
        return colors.packRGB(r / 255, g / 255, b / 255)
    end

    return colors
end

local function create_term_api(state, colors)
    local function color_to_blit(c)
        local ch = colors.toBlit(c)
        if ch then
            return ch
        end
        return "0"
    end

    local term = {}

    local function reset_cells()
        state.term.cells = {}
        for y = 1, state.term.height do
            local row = {}
            for x = 1, state.term.width do
                row[x] = { ch = " ", fg = state.term.fg, bg = state.term.bg }
            end
            state.term.cells[y] = row
        end
    end

    local function write_cell(x, y, ch, fg, bg)
        if y < 1 or y > state.term.height or x < 1 or x > state.term.width then
            return
        end
        state.term.cells[y][x] = { ch = ch, fg = fg, bg = bg }
    end

    local function cursor_row()
        return state.term.cy
    end

    local function cursor_col()
        return state.term.cx
    end

    function term.getSize()
        return state.term.width, state.term.height
    end

    function term.setCursorPos(x, y)
        state.term.cx = math.max(1, math.floor(tonumber(x) or 1))
        state.term.cy = math.max(1, math.floor(tonumber(y) or 1))
    end

    function term.getCursorPos()
        return state.term.cx, state.term.cy
    end

    function term.setCursorBlink(v)
        state.term.blink = not not v
    end

    function term.getCursorBlink()
        return state.term.blink
    end

    function term.setTextColor(c)
        local b = color_to_blit(c)
        state.term.fg = b
    end

    term.setTextColour = term.setTextColor

    function term.getTextColor()
        local c = colors.fromBlit(state.term.fg)
        return c or colors.white
    end

    term.getTextColour = term.getTextColor

    function term.setBackgroundColor(c)
        local b = color_to_blit(c)
        state.term.bg = b
    end

    term.setBackgroundColour = term.setBackgroundColor

    function term.getBackgroundColor()
        local c = colors.fromBlit(state.term.bg)
        return c or colors.black
    end

    term.getBackgroundColour = term.getBackgroundColor

    function term.clear()
        reset_cells()
        state.term.cx = 1
        state.term.cy = 1
    end

    function term.clearLine()
        local y = cursor_row()
        if y < 1 or y > state.term.height then
            return
        end
        for x = 1, state.term.width do
            write_cell(x, y, " ", state.term.fg, state.term.bg)
        end
        state.term.cx = 1
    end

    function term.write(text)
        text = tostring(text or "")
        local x = cursor_col()
        local y = cursor_row()
        for i = 1, #text do
            local ch = text:sub(i, i)
            write_cell(x, y, ch, state.term.fg, state.term.bg)
            x = x + 1
            if x > state.term.width then
                break
            end
        end
        state.term.cx = math.min(x, state.term.width + 1)
    end

    function term.blit(text, fg, bg)
        text = tostring(text or "")
        fg = tostring(fg or "")
        bg = tostring(bg or "")
        if #fg < #text or #bg < #text then
            error("blit arguments must be same length", 2)
        end
        local x = cursor_col()
        local y = cursor_row()
        for i = 1, #text do
            local ch = text:sub(i, i)
            local f = fg:sub(i, i)
            local b = bg:sub(i, i)
            if not colors.fromBlit(f) or not colors.fromBlit(b) then
                error("blit color strings must be hex chars", 2)
            end
            write_cell(x, y, ch, f:lower(), b:lower())
            x = x + 1
            if x > state.term.width then
                break
            end
        end
        state.term.cx = math.min(x, state.term.width + 1)
    end

    function term.scroll(n)
        n = math.floor(tonumber(n) or 0)
        if n == 0 then
            return
        end
        local blank = {}
        for x = 1, state.term.width do
            blank[x] = { ch = " ", fg = state.term.fg, bg = state.term.bg }
        end
        if n > 0 then
            for y = 1, state.term.height do
                local src = y + n
                state.term.cells[y] = src <= state.term.height and state.term.cells[src] or blank
            end
        else
            local up = -n
            for y = state.term.height, 1, -1 do
                local src = y - up
                state.term.cells[y] = src >= 1 and state.term.cells[src] or blank
            end
        end
    end

    function term.isColor()
        return true
    end

    term.isColour = term.isColor

    function term.getPaletteColor(mask)
        local idx = colors.toBlit(mask)
        local rgb = state.term.palette[idx]
        if not rgb then
            return 0, 0, 0
        end
        return rgb[1], rgb[2], rgb[3]
    end

    term.getPaletteColour = term.getPaletteColor

    function term.setPaletteColor(mask, r, g, b)
        local idx = colors.toBlit(mask)
        if not idx then
            error("invalid palette color", 2)
        end
        if b == nil then
            local rr, gg, bb = colors.unpackRGB(r)
            state.term.palette[idx] = { rr, gg, bb }
            return
        end
        state.term.palette[idx] = {
            math.max(0, math.min(1, tonumber(r) or 0)),
            math.max(0, math.min(1, tonumber(g) or 0)),
            math.max(0, math.min(1, tonumber(b) or 0)),
        }
    end

    term.setPaletteColour = term.setPaletteColor

    function term.current()
        return term
    end

    function term.native()
        return term
    end

    function term.redirect(target)
        if type(target) ~= "table" then
            error("redirect target must be terminal object", 2)
        end
        local prev = state.term.redirect_target
        state.term.redirect_target = target
        return prev or term
    end

    term.reset = reset_cells
    state.term.reset = reset_cells
    return term
end

local function create_textutils_api()
    local textutils = {}

    local function serialize_impl(v, seen)
        local t = type(v)
        if t == "nil" then
            return "nil"
        end
        if t == "number" or t == "boolean" then
            return tostring(v)
        end
        if t == "string" then
            return string.format("%q", v)
        end
        if t ~= "table" then
            error("cannot serialize type " .. t)
        end
        if seen[v] then
            error("cannot serialize recursive table")
        end
        seen[v] = true
        local parts = { "{" }
        local first = true
        for k, val in pairs(v) do
            if not first then
                parts[#parts + 1] = ","
            end
            first = false
            parts[#parts + 1] = "[" .. serialize_impl(k, seen) .. "]=" .. serialize_impl(val, seen)
        end
        parts[#parts + 1] = "}"
        seen[v] = nil
        return table.concat(parts)
    end

    function textutils.serialize(v)
        return serialize_impl(v, {})
    end

    function textutils.unserialize(s)
        local f, err = load("return " .. tostring(s or ""), "textutils.unserialize", "t", {})
        if not f then
            return nil, err
        end
        local ok, rv = pcall(f)
        if not ok then
            return nil, rv
        end
        return rv
    end

    function textutils.unserializeJSON(s)
        s = tostring(s or "")
        local f, err = load("return " .. s:gsub("null", "nil"), "textutils.unserializeJSON", "t", {})
        if not f then
            return nil, err
        end
        local ok, rv = pcall(f)
        if not ok then
            return nil, rv
        end
        return rv
    end

    return textutils
end

local function create_shell_api(state)
    local shell = {
        _dir = "/",
        _path = "/",
        _aliases = {},
    }

    function shell.dir()
        return shell._dir
    end

    function shell.setDir(path)
        shell._dir = normalize_path(path)
    end

    function shell.path()
        return shell._path
    end

    function shell.setPath(path)
        shell._path = tostring(path or "")
    end

    function shell.resolve(path)
        path = tostring(path or "")
        if path:sub(1, 1) == "/" then
            return normalize_path(path)
        end
        return normalize_path(shell._dir .. "/" .. path)
    end

    function shell.resolveProgram(name)
        name = tostring(name or "")
        if name == "" then
            return nil
        end
        local direct = shell.resolve(name)
        if state.fs.exists(direct) then
            return direct
        end
        for part in shell._path:gmatch("[^:]+") do
            local p = normalize_path(part .. "/" .. name)
            if state.fs.exists(p) then
                return p
            end
        end
        return nil
    end

    function shell.setAlias(name, target)
        shell._aliases[tostring(name)] = tostring(target)
    end

    function shell.clearAlias(name)
        shell._aliases[tostring(name)] = nil
    end

    function shell.aliases()
        local out = {}
        for k, v in pairs(shell._aliases) do
            out[k] = v
        end
        return out
    end

    function shell.getAlias(name)
        return shell._aliases[tostring(name)]
    end

    function shell.programs(include_hidden)
        local out = {}
        for part in shell._path:gmatch("[^:]+") do
            local abs = normalize_path(part)
            if state.fs.isDir(abs) then
                local names = state.fs.list(abs)
                for i = 1, #names do
                    local n = names[i]
                    if include_hidden or n:sub(1, 1) ~= "." then
                        out[#out + 1] = n
                    end
                end
            end
        end
        table.sort(out)
        return out
    end

    function shell.run(prog, ...)
        local path = shell.resolveProgram(prog)
        if not path then
            return false
        end
        local chunk, err = loadfile(state.fs.abs_path(path), "t", _G)
        if not chunk then
            error(err)
        end
        local ok, rv = pcall(chunk, ...)
        if not ok then
            error(rv)
        end
        return rv ~= false
    end

    return shell
end

local function create_keys_api()
    local keys = {
        enter = 28,
        backspace = 14,
        tab = 15,
        space = 57,
        up = 200,
        down = 208,
        left = 203,
        right = 205,
        home = 199,
        ["end"] = 207,
        delete = 211,
        insert = 210,
        pageUp = 201,
        pageDown = 209,
        leftShift = 42,
        rightShift = 54,
        leftCtrl = 29,
        rightCtrl = 157,
        leftAlt = 56,
        rightAlt = 184,
        f1 = 59,
        f2 = 60,
        f3 = 61,
        f4 = 62,
        f5 = 63,
        f6 = 64,
        f7 = 65,
        f8 = 66,
        f9 = 67,
        f10 = 68,
        f11 = 87,
        f12 = 88,
    }

    local names = {}
    local next_code = 1000
    for k, v in pairs(keys) do
        names[v] = k
        if v >= next_code then
            next_code = v + 1
        end
    end

    setmetatable(keys, {
        __index = function(t, k)
            if type(k) ~= "string" then
                return nil
            end
            local code = next_code
            next_code = next_code + 1
            rawset(t, k, code)
            if not names[code] then
                names[code] = k
            end
            return code
        end,
    })

    function keys.getName(code)
        return names[tonumber(code)]
    end

    return keys
end

local function create_fs_api(state)
    local fs = {}

    local function rel(path)
        path = tostring(path or "")
        if path == "" then
            return "/"
        end
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        return normalize_path(path)
    end

    local function abs(path)
        return state.fs_root .. rel(path)
    end

    local function path_attr(path)
        return lfs_attr(path)
    end

    local function host_runtime_attr(path)
        path = tostring(path or "")
        local root = tostring(state.ccvim_root or "")
        if root == "" or path == "" or path:sub(1, 1) ~= "/" then
            return nil
        end
        if path == root or path:sub(1, #root + 1) == root .. "/" then
            return path_attr(path)
        end
        return nil
    end

    function fs.abs_path(path)
        return abs(path)
    end

    function fs.combine(a, b)
        a = tostring(a or "")
        b = tostring(b or "")
        if a == "" then
            return normalize_path(b)
        end
        if b == "" then
            return normalize_path(a)
        end
        return normalize_path(a .. "/" .. b)
    end

    function fs.getName(path)
        path = normalize_path(path)
        if path == "/" then
            return ""
        end
        return path:match("([^/]+)$") or ""
    end

    function fs.getDir(path)
        path = normalize_path(path)
        if path == "/" then
            return "/"
        end
        local d = path:match("^(.*)/[^/]*$")
        if not d or d == "" then
            return "/"
        end
        return d
    end

    function fs.exists(path)
        path = tostring(path or "")
        if path ~= "" and path:sub(1, 1) ~= "/" then
            if path_attr(path) ~= nil then
                return true
            end
        elseif host_runtime_attr(path) ~= nil then
            return true
        end
        return path_attr(abs(path)) ~= nil
    end

    function fs.isDir(path)
        path = tostring(path or "")
        if path ~= "" and path:sub(1, 1) ~= "/" then
            local attr = path_attr(path)
            if attr and attr.mode == "directory" then
                return true
            end
        else
            local attr = host_runtime_attr(path)
            if attr and attr.mode == "directory" then
                return true
            end
        end
        local attr = path_attr(abs(path))
        if attr and attr.mode == "directory" then
            return true
        end
        return false
    end

    function fs.isReadOnly(_)
        return false
    end

    function fs.makeDir(path)
        local ok, err = pcall(mkdir_p, abs(path))
        if not ok then
            error("cannot create directory: " .. tostring(err), 2)
        end
        return true
    end

    local function delete_abs(abs_path)
        local ok, err = remove_tree(abs_path)
        if not ok then
            error("cannot delete path: " .. tostring(err), 2)
        end
    end

    function fs.delete(path)
        local p = abs(path)
        if not fs.exists(path) then
            return
        end
        delete_abs(p)
    end

    function fs.list(path)
        local orig_path = tostring(path or "")
        path = rel(path)
        if not fs.exists(orig_path) then
            error("no such path", 2)
        end
        if not fs.isDir(orig_path) then
            error("not a directory", 2)
        end
        local target = abs(path)
        if orig_path ~= "" and orig_path:sub(1, 1) ~= "/" then
            local attr = path_attr(orig_path)
            if attr and attr.mode == "directory" then
                target = orig_path
            end
        else
            local attr = host_runtime_attr(orig_path)
            if attr and attr.mode == "directory" then
                target = orig_path
            end
        end

        local lines = {}
        for name in lfs.dir(target) do
            if name ~= "." and name ~= ".." then
                lines[#lines + 1] = name
            end
        end
        table.sort(lines)
        return lines
    end

    function fs.move(from, to)
        if not fs.exists(from) then
            error("source does not exist", 2)
        end
        local parent = fs.getDir(to)
        fs.makeDir(parent)
        local ok, err = move_path(abs(from), abs(to))
        if not ok then
            error("move failed: " .. tostring(err), 2)
        end
        return true
    end

    function fs.copy(from, to)
        if not fs.exists(from) then
            error("source does not exist", 2)
        end
        local parent = fs.getDir(to)
        fs.makeDir(parent)
        local ok, err = copy_tree(abs(from), abs(to))
        if not ok then
            error("copy failed: " .. tostring(err), 2)
        end
        return true
    end

    function fs.getSize(path)
        if not fs.exists(path) then
            error("no such file", 2)
        end
        if fs.isDir(path) then
            return 0
        end
        local f = io.open(abs(path), "rb")
        if not f then
            return 0
        end
        local cur = f:seek()
        local size = f:seek("end")
        f:seek("set", cur)
        f:close()
        return size or 0
    end

    function fs.attributes(path)
        if not fs.exists(path) then
            return nil, "no such file"
        end
        local out = {
            isDir = fs.isDir(path),
            isReadOnly = false,
            size = fs.getSize(path),
            modified = real_os_time(),
            modification = real_os_time(),
            created = real_os_time(),
        }
        return out
    end

    function fs.open(path, mode)
        local orig_path = tostring(path or "")
        path = rel(path)
        mode = tostring(mode or "r")

        -- Check if this is a real filesystem path (for vim runtime files)
        local use_real_path = false
        if orig_path ~= "" and orig_path:sub(1, 1) ~= "/" then
            local attr = path_attr(orig_path)
            if attr and attr.mode == "file" then
                use_real_path = true
            end
        else
            local attr = host_runtime_attr(orig_path)
            if attr and attr.mode == "file" then
                use_real_path = true
            end
        end

        local abs_path = use_real_path and orig_path or abs(path)

        local parent = fs.getDir(use_real_path and orig_path or path)
        if mode == "w" or mode == "a" or mode == "wb" or mode == "ab" then
            if not use_real_path then
                fs.makeDir(parent)
            end
        end

        local f, err = io.open(abs_path, mode)
        if not f then
            return nil, err
        end

        local handle = {}

        function handle.readLine(with_trailing)
            local line = f:read("*l")
            if line == nil then
                return nil
            end
            if with_trailing then
                return line .. "\n"
            end
            return line
        end

        function handle.readAll()
            return f:read("*a")
        end

        function handle.read(count)
            if count == nil then
                local b = f:read(1)
                if not b then
                    return nil
                end
                return string.byte(b)
            end
            count = tonumber(count) or 0
            if count <= 0 then
                return ""
            end
            return f:read(count)
        end

        function handle.write(s)
            f:write(tostring(s))
        end

        function handle.writeLine(s)
            f:write(tostring(s or ""), "\n")
        end

        function handle.flush()
            f:flush()
        end

        function handle.close()
            f:close()
        end

        return handle
    end

    local function glob_to_lua(pattern)
        pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
        pattern = pattern:gsub("%*", ".*")
        return "^" .. pattern .. "$"
    end

    function fs.find(pattern)
        pattern = tostring(pattern or "")
        local rx = glob_to_lua(pattern)
        local matches = {}

        local function walk(path)
            local items = fs.list(path)
            for i = 1, #items do
                local name = items[i]
                local relp = normalize_path(path .. "/" .. name)
                relp = relp:gsub("^/+", "")
                if relp:match(rx) then
                    matches[#matches + 1] = relp
                end
                if fs.isDir("/" .. relp) then
                    walk("/" .. relp)
                end
            end
        end

        walk("/")
        table.sort(matches)
        return matches
    end

    function fs.getDrive(_)
        return "hdd"
    end

    function fs.getFreeSpace(_)
        return 1024 * 1024 * 1024
    end

    function fs.getCapacity(_)
        return 1024 * 1024 * 1024
    end

    function fs.complete(partial, path, include_files, include_dirs)
        partial = tostring(partial or "")
        path = path or "/"
        include_files = include_files ~= false
        include_dirs = include_dirs ~= false
        local out = {}
        if not fs.isDir(path) then
            return out
        end
        for _, name in ipairs(fs.list(path)) do
            if name:sub(1, #partial) == partial then
                local p = fs.combine(path, name)
                if fs.isDir(p) then
                    if include_dirs then
                        out[#out + 1] = name .. "/"
                    end
                elseif include_files then
                    out[#out + 1] = name
                end
            end
        end
        table.sort(out)
        return out
    end

    return fs
end

local function create_os_api(state)
    local cc_os = {}

    function cc_os.queueEvent(name, ...)
        state.events[#state.events + 1] = { tostring(name), ... }
    end

    local function pump_timers()
        local now = real_os_clock()
        local ready = {}
        for id, deadline in pairs(state.timers) do
            if now >= deadline then
                ready[#ready + 1] = id
            end
        end
        for i = 1, #ready do
            local id = ready[i]
            state.timers[id] = nil
            cc_os.queueEvent("timer", id)
        end
    end

    local function next_event(filter, raw)
        if state.done then
            if not raw then
                error("Terminated", 0)
            end
            return "terminate"
        end

        -- Try up to 10 iterations to avoid infinite loops in tests
        local max_attempts = 10
        local attempts = 0
        while attempts < max_attempts do
            attempts = attempts + 1
            pump_timers()
            if #state.events > 0 then
                local ev = table.remove(state.events, 1)
                if (not filter) or ev[1] == filter then
                    if not raw and ev[1] == "terminate" then
                        error("Terminated", 0)
                    end
                    return table.unpack(ev)
                end
            else
                if state.on_pull_event then
                    local ev = state.on_pull_event(filter)
                    if ev and ev[1] then
                        if (not filter) or ev[1] == filter then
                            if not raw and ev[1] == "terminate" then
                                error("Terminated", 0)
                            end
                            return table.unpack(ev)
                        end
                    else
                        -- on_pull_event returned nothing, return a dummy event
                        return "test_idle"
                    end
                else
                    -- No event handler, return dummy event immediately
                    return "test_idle"
                end
            end
        end
        -- Exceeded max attempts, return dummy event to avoid hanging
        return "test_idle"
    end

    function cc_os.pullEvent(filter)
        return next_event(filter, false)
    end

    function cc_os.pullEventRaw(filter)
        return next_event(filter, true)
    end

    function cc_os.startTimer(timeout)
        timeout = tonumber(timeout) or 0
        state.next_timer_id = state.next_timer_id + 1
        local id = state.next_timer_id
        state.timers[id] = real_os_clock() + math.max(0, timeout)
        return id
    end

    function cc_os.cancelTimer(id)
        state.timers[id] = nil
    end

    function cc_os.sleep()
        -- Non-blocking sleep for tests - just return immediately
        return
    end

    function cc_os.clock()
        return real_os_clock()
    end

    function cc_os.time(locale)
        if locale == "utc" then
            return real_os_time(real_os_date("!*t"))
        end
        return real_os_time()
    end

    function cc_os.day(locale)
        local t = locale == "utc" and real_os_date("!*t") or real_os_date("*t")
        return math.floor((real_os_time(t) or 0) / 86400)
    end

    function cc_os.epoch(locale)
        if locale == "utc" then
            return now_ms()
        end
        return now_ms()
    end

    function cc_os.date(fmt, time)
        return real_os_date(fmt, time)
    end

    function cc_os.version()
        return "CraftOS 1.9 (Mock)"
    end

    function cc_os.run(env, prog, ...)
        local chunk, err = loadfile(prog, "t", env or _G)
        if not chunk then
            error(err, 2)
        end
        return chunk(...)
    end

    function cc_os.loadAPI(path)
        local chunk, err = loadfile(path, "t", _G)
        if not chunk then
            return false, err
        end
        local ok, rv = pcall(chunk)
        if not ok then
            return false, rv
        end
        return true, rv
    end

    function cc_os.unloadAPI(_)
        return true
    end

    function cc_os.getComputerID()
        return state.computer_id
    end

    function cc_os.getComputerLabel()
        return state.computer_label
    end

    function cc_os.setComputerLabel(label)
        state.computer_label = label and tostring(label) or nil
    end

    function cc_os.shutdown()
        error("shutdown called", 0)
    end

    function cc_os.reboot()
        error("reboot called", 0)
    end

    function cc_os.exit(code)
        real_os_exit(code or 0)
    end

    return cc_os
end

local function create_bit32_compat()
    if _G.bit32 then
        return _G.bit32
    end
    return {
        band = function(a, b) return (a or 0) & (b or 0) end,
        bor = function(a, b) return (a or 0) | (b or 0) end,
        bxor = function(a, b) return (a or 0) ~ (b or 0) end,
        bnot = function(a) return ~(a or 0) end,
        lshift = function(a, n) return (a or 0) << (n or 0) end,
        rshift = function(a, n) return (a or 0) >> (n or 0) end,
        arshift = function(a, n) return (a or 0) >> (n or 0) end,
    }
end

local function default_globals(state, colors)
    local textutils = create_textutils_api()
    local term = create_term_api(state, colors)
    local fs = create_fs_api(state)
    state.fs = fs
    local shell = create_shell_api(state)
    local keys = create_keys_api()
    local cc_os = create_os_api(state)
    local function resolve_loadfile_path(path)
        path = tostring(path or "")
        if path == "" then
            return path
        end
        if lfs_attr(path) ~= nil then
            return path
        end
        return state.fs.abs_path(path)
    end

    local g = {
        _HOST = "CraftOS-PC",
        _VERSION = "CraftOS 1.9",
        _CC_DEFAULT_SETTINGS = "",

        bit32 = create_bit32_compat(),
        colors = colors,
        colours = colors,
        term = term,
        fs = fs,
        shell = shell,
        os = cc_os,
        textutils = textutils,
        keys = keys,
        redstone = {
            getInput = function() return false end,
            setOutput = function() end,
            getOutput = function() return false end,
        },
        rs = nil,
        peripheral = {
            isPresent = function() return false end,
            getType = function() return nil end,
            call = function() error("no peripheral", 2) end,
        },
        settings = {
            define = function() end,
            set = function() end,
            get = function(_, default) return default end,
            unset = function() end,
            clear = function() end,
            save = function() return true end,
            load = function() return true end,
        },
        parallel = {
            waitForAny = function(...)
                local fns = { ... }
                for i = 1, #fns do
                    fns[i]()
                end
                return 1
            end,
            waitForAll = function(...)
                local fns = { ... }
                for i = 1, #fns do
                    fns[i]()
                end
                return true
            end,
        },
        window = {
            create = function(parent, x, y, w, h)
                local win = {
                    _parent = parent,
                    _x = x,
                    _y = y,
                    _w = w,
                    _h = h,
                    _visible = true,
                }
                for k, v in pairs(parent) do
                    if type(v) == "function" then
                        win[k] = function(_, ...)
                            return v(...)
                        end
                    end
                end
                function win.reposition(nx, ny, nw, nh)
                    win._x = math.floor(tonumber(nx) or win._x)
                    win._y = math.floor(tonumber(ny) or win._y)
                    win._w = math.floor(tonumber(nw) or win._w)
                    win._h = math.floor(tonumber(nh) or win._h)
                end
                function win.getPosition()
                    return win._x, win._y
                end
                function win.getSize()
                    return win._w, win._h
                end
                function win.setVisible(v)
                    win._visible = not not v
                end
                function win.isVisible()
                    return win._visible
                end
                return win
            end,
        },
        loadfile = function(path, mode, env)
            local resolved = resolve_loadfile_path(path)
            if mode == nil and env == nil then
                return real_loadfile(resolved)
            end
            if env == nil then
                return real_loadfile(resolved, mode)
            end
            return real_loadfile(resolved, mode, env)
        end,
        dofile = function(path)
            local chunk, err = real_loadfile(resolve_loadfile_path(path), "t", _G)
            if not chunk then
                error(err, 2)
            end
            return chunk()
        end,
    }
    g.rs = g.redstone

    return g
end

local function make_module_loader(root, globals, stubs)
    local loaded = {}

    local function module_to_path(name)
        return root .. "/" .. name:gsub("%.", "/") .. ".lua"
    end

    local function load_chunk(path, env)
        local chunk, err = loadfile(path, "t", env)
        if not chunk and setfenv then
            chunk, err = loadfile(path)
            if chunk then
                setfenv(chunk, env)
            end
        end
        if not chunk then
            error(err, 2)
        end
        return chunk
    end

    local function load_module(name, opts)
        opts = opts or {}

        local cached = loaded[name]
        if cached ~= nil then
            if type(cached) == "table" and cached.__ccvim_lazy_proxy and opts.immediate then
                return cached.__ccvim_materialize()
            end
            return cached
        end

        local stub = stubs[name]
        local chunk
        if stub == nil then
            local path = module_to_path(name)
            local env = setmetatable({}, {
                __index = function(_, k)
                    local v = globals[k]
                    if v ~= nil then
                        return v
                    end
                    return _G[k]
                end,
            })
            env._G = _G  -- Use real global environment so Lua base functions are available
            env.loadModule = load_module
            chunk = load_chunk(path, env)
        end

        local resolved = false
        local mod
        local function materialize()
            if not resolved then
                if stub ~= nil then
                    mod = type(stub) == "function" and stub() or stub
                else
                    mod = chunk()
                end
                if mod == nil then
                    mod = true
                end
                resolved = true
                loaded[name] = mod
            end
            return mod
        end

        if opts.immediate then
            return materialize()
        end

        local proxy = {
            __ccvim_lazy_proxy = true,
            __ccvim_materialize = materialize,
        }
        setmetatable(proxy, {
            __index = function(_, key)
                return materialize()[key]
            end,
            __newindex = function(_, key, value)
                materialize()[key] = value
            end,
            __call = function(_, ...)
                return materialize()(...)
            end,
            __len = function()
                return #materialize()
            end,
            __pairs = function()
                return pairs(materialize())
            end,
            __tostring = function()
                return tostring(materialize())
            end,
        })
        loaded[name] = proxy
        return proxy
    end

    return load_module, loaded
end

function MockEnv.setup(opts)
    opts = opts or {}

    local pid = default_pid()
    local fs_root = string.format("/tmp/nvim-test-%d-%d-%d", real_os_time(), pid, math.random(1000, 9999))
    remove_tree(fs_root)
    local ok, code = pcall(mkdir_p, fs_root)
    if not ok then
        error("failed to create fs root " .. fs_root .. " (code " .. tostring(code) .. ")")
    end

    local colors = create_colors_api()
    local state = {
        fs_root = fs_root,
        events = {},
        timers = {},
        done = false,
        next_timer_id = 0,
        computer_id = tonumber(opts.computer_id) or 1,
        computer_label = opts.computer_label,
        term = {
            width = tonumber(opts.term_width) or 80,
            height = tonumber(opts.term_height) or 25,
            cx = 1,
            cy = 1,
            fg = "0",
            bg = "f",
            blink = false,
            cells = {},
            palette = {
                ["0"] = { 1.0, 1.0, 1.0 },
                ["1"] = { 0.95, 0.7, 0.2 },
                ["2"] = { 0.9, 0.5, 0.85 },
                ["3"] = { 0.6, 0.7, 0.95 },
                ["4"] = { 0.87, 0.87, 0.42 },
                ["5"] = { 0.5, 0.8, 0.1 },
                ["6"] = { 0.95, 0.7, 0.8 },
                ["7"] = { 0.6, 0.6, 0.6 },
                ["8"] = { 0.3, 0.3, 0.3 },
                ["9"] = { 0.3, 0.6, 0.7 },
                ["a"] = { 0.7, 0.4, 0.9 },
                ["b"] = { 0.2, 0.4, 0.8 },
                ["c"] = { 0.5, 0.4, 0.3 },
                ["d"] = { 0.3, 0.5, 0.2 },
                ["e"] = { 0.8, 0.3, 0.3 },
                ["f"] = { 0.1, 0.1, 0.1 },
            },
        },
    }

    state.on_pull_event = opts.on_pull_event or function()
        if #state.events > 0 then
            return table.remove(state.events, 1)
        end
        return { "idle" }
    end

    local ccvim_root = opts.ccvim_path
    if not ccvim_root or ccvim_root == "" then
        ccvim_root = rawget(_G, "__CCVIM_TEST_ROOT") or "."
    end
    if ccvim_root:sub(1, 1) ~= "/" then
        ccvim_root = normalize_path((lfs.currentdir() or ".") .. "/" .. ccvim_root)
    else
        ccvim_root = normalize_path(ccvim_root)
    end
    state.ccvim_root = ccvim_root

    local globals = default_globals(state, colors)

    function math.clamp(value, min_value, max_value)
        if value < min_value then
            return min_value
        end
        if value > max_value then
            return max_value
        end
        return value
    end
    
    globals.ccvim_path = ccvim_root
    globals.screen = {
        width = state.term.width,
        height = state.term.height,
    }

    globals.windows = {}
    globals.tabpages = { { opts = {} } }
    globals.buffers = {}
    globals.curwin = 1
    globals.curtp = 1
    globals.need_redraw = false
    globals.what_redraw = {}
    globals.vimmode = "normal"
    globals.vimlog = {}
    globals.registers = {}
    globals.global_marks = {}
    globals.__ccvim_input_state = {
        feedkeys_typeahead_depth = 0,
    }

    globals.LOG_DEBUG = function() end
    globals.LOG_ERROR = function() end
    globals.LOG_INTERNAL_ENABLE = {
        autocmd = false,
        syntax = false,
        excmd_call = false,
        excmd_internal_parse = false,
        unimplemented = false,
        ignored = false,
        pcall = false,
        frametree = false,
        has = false,
        missing = false,
    }
    globals.LOG_INTERNAL = function() end

    globals.printError = function()
    end

    globals.write = function(s)
        globals.term.write(s)
    end

    local load_module, loaded = make_module_loader(ccvim_root, globals, opts.module_stubs or {})
    
    globals.loadModule = load_module
    _G.loadModule = load_module

    for k, v in pairs(globals) do
        _G[k] = v
    end

    _G.what_redraw = globals.what_redraw

    globals.options = load_module("lib.options")
    _G.options = globals.options

    globals.enterWindow = function(winnr)
        if winnr == nil or globals.windows[winnr] == nil then
            return
        end
        if globals.curwin == nil or globals.windows[globals.curwin] == nil then
            globals.curwin = winnr
            globals.curtp = globals.windows[winnr].tabpagenr or globals.curtp
            return
        end
        if winnr == globals.curwin then
            return
        end

        local AutoCmd = load_module("lib.autocmd")
        local new_curtp
        local new_curwin = winnr
        local oldwin = globals.windows[globals.curwin]
        local newwin = globals.windows[new_curwin]

        if newwin.tabpagenr ~= globals.curtp then
            new_curtp = newwin.tabpagenr
        end

        local oldbuf = oldwin.buffer
        local newbuf = newwin.buffer
        local buf_changed = oldbuf ~= newbuf

        if buf_changed then
            AutoCmd.Run("BufLeave", { bufnr = oldbuf.bufnr, bufname = oldbuf.name })
        end

        AutoCmd.Run("WinLeave")

        if new_curtp then
            AutoCmd.Run("TabLeave")
        end

        globals.curwin = new_curwin
        if new_curtp then
            globals.curtp = new_curtp
        end

        AutoCmd.Run("WinEnter")

        if new_curtp then
            AutoCmd.Run("TabEnter")
        end

        if buf_changed then
            AutoCmd.Run("BufEnter", { bufnr = newbuf.bufnr, bufname = newbuf.name })
        end

        load_module("lib.frame").RebalanceCurrentTab()
    end
    _G.enterWindow = globals.enterWindow

    globals.setMode = function(newmode, newx, newy)
        local oldmode = globals.vimmode
        local win = globals.windows[globals.curwin]
        local mode_changed = (newmode ~= oldmode)
        local buf_ctx = {
            bufnr = win.buffer.bufnr,
            bufname = win.buffer.name,
        }

        local AutoCmd = load_module("lib.autocmd")
        local PopupMenu = load_module("lib.popupmenu")

        if mode_changed and oldmode == "insert" and newmode ~= "insert" then
            win.buffer:undo_end(win)
            AutoCmd.Run("InsertLeavePre", buf_ctx)
        end

        globals.vimmode = newmode
        if newy then
            win:cursorSetY(newy)
        end
        if newx then
            win:cursorSetX(newx)
        end
        if newmode == "insert" then
            local lines = win.buffer:lines_ref(true)
            if #lines == 0 then
                lines[1] = ""
            end
        end
        if mode_changed then
            if oldmode == "insert" and newmode ~= "insert" then
                if PopupMenu.visible() then
                    PopupMenu.close("cancel")
                end
                AutoCmd.Run("InsertLeave", buf_ctx)
            elseif oldmode ~= "insert" and newmode == "insert" then
                AutoCmd.Run("InsertEnter", buf_ctx)
            end

            if oldmode == "cmdline" and newmode ~= "cmdline" then
                AutoCmd.Run("CmdlineLeave", buf_ctx)
            elseif oldmode ~= "cmdline" and newmode == "cmdline" then
                AutoCmd.Run("CmdlineEnter", buf_ctx)
            end

            AutoCmd.Run("ModeChanged", { old_mode = oldmode, new_mode = newmode })
        end
        globals.what_redraw["commandline"] = true
        win:cursorMove(0, 0, false)
        if newmode == "insert" then
            win.insert_curs_start = { win.cursorx, win.cursory }
            if mode_changed and oldmode ~= "insert" then
                win.buffer:undo_begin(win)
            end
        end
        globals.need_redraw = true
    end
    _G.setMode = globals.setMode

    -- Set COLORTERM to prevent runtime startup from emitting terminal capability probes.
    local EnvVars = load_module("lib.envvars")
    if EnvVars and EnvVars.get and EnvVars.set_default then
        if not EnvVars.get("COLORTERM") then
            EnvVars.set_default("COLORTERM", "truecolor")
        end
    end

    if opts.bootstrap_default_editor == false then
        -- Replicate nvim.lua startup: parse argv to initialize buffer/window/tabpage.
        local Args = load_module("lib.args")
        local ok_parse = Args.parse({ [0] = "nvim" })
        if not ok_parse then
            error("Mock bootstrap failed: Args.parse returned false")
        end
    end

    globals.term.reset()

    local mock = {}

    function mock.loadModule(name, options)
        return load_module(name, options)
    end

    function mock.cleanup()
        state.done = true
        state.timers = {}
        state.events = { { "terminate" } }
        remove_tree(fs_root)
    end

    function mock.finish()
        state.done = true
        state.timers = {}
        state.events[#state.events + 1] = { "terminate" }
    end

    function mock.create_buffer(bufnr, name, lines, opts_buf)
        local Buffer = load_module("layout.buffer")
        local buf = Buffer(true, false, true)
        if bufnr then
            buf.bufnr = bufnr
            globals.buffers[bufnr] = buf
        end
        buf.name = name or ("/tmp/buf-" .. tostring(buf.bufnr) .. ".txt")
        buf.lines = lines or { "" }
        if opts_buf then
            for k, v in pairs(opts_buf) do
                buf[k] = v
            end
        end
        return buf
    end

    function mock.create_window(winnr, buffer, opts_win)
        local Window = load_module("layout.window")
        local win = Window(buffer)
        if winnr then
            win.winnr = winnr
            globals.windows[winnr] = win
            if globals.curwin == nil then
                globals.curwin = winnr
            end
        end
        if opts_win then
            for k, v in pairs(opts_win) do
                win[k] = v
            end
        end
        return win
    end

    function mock.create_tabpage(tabnr, wins, opts_tab)
        local Tabpage = load_module("layout.tabpage")
        local first = wins and wins[1] or nil
        local tp = Tabpage(first)
        if tabnr then
            tp.tabnr = tabnr
            globals.tabpages[tabnr] = tp
            if globals.curtp == nil then
                globals.curtp = tabnr
            end
        end
        if wins and #wins > 0 then
            tp.windows = wins
            for i = 1, #wins do
                wins[i].tabpagenr = tp.tabnr
                globals.windows[wins[i].winnr] = wins[i]
            end
        end
        if opts_tab then
            for k, v in pairs(opts_tab) do
                tp[k] = v
            end
        end
        return tp
    end

    function mock.queueEvent(name, ...)
        globals.os.queueEvent(name, ...)
    end

    function mock.term_cells()
        return state.term.cells
    end

    function mock.tmp_root()
        return fs_root
    end

    function mock.globals()
        return globals
    end

    function mock.module_cache()
        return loaded
    end

    if opts.bootstrap_default_editor ~= false and not globals.windows[1] then
        local b = mock.create_buffer(1, "/tmp/current.txt", { "" }, { refcount = 1 })
        local w = mock.create_window(1, b, { cursorx = 1, cursory = 1 })
        mock.create_tabpage(1, { w }, {})
        globals.curwin = 1
        globals.curtp = 1
    end

    return mock
end

return MockEnv
