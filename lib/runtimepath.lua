local RuntimePath = {}

local Options = loadModule("lib.options")
local VimFs = loadModule("lib.luaapi.fs")

local function split_csv(s)
    local t = {}
    for part in tostring(s or ""):gmatch("([^,]+)") do
        local p = part:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then
            t[#t + 1] = p
        end
    end
    return t
end

local function normalize(path)
    if not path or path == "" then
        return ""
    end
    local out = VimFs.abspath(path)
    if #out > 1 and out:sub(-1) == "/" then
        out = out:sub(1, -2)
    end
    return out
end

local function is_after(path)
    local n = normalize(path)
    return n:sub(-6) == "/after"
end

local function list_start_packages()
    local raw = Options.get("packpath", nil, nil, false, true)
    local roots = split_csv(raw)
    local out, seen = {}, {}
    for _, root in ipairs(roots) do
        local base = normalize(root)
        if base ~= "" then
            local packdir = base .. "/pack"
            if fs.isDir(packdir) then
                local groups = fs.list(packdir) or {}
                table.sort(groups)
                for _, group in ipairs(groups) do
                    local startdir = packdir .. "/" .. group .. "/start"
                    if fs.isDir(startdir) then
                        local pkgs = fs.list(startdir) or {}
                        table.sort(pkgs)
                        for _, pkg in ipairs(pkgs) do
                            local pkgpath = startdir .. "/" .. pkg
                            if fs.isDir(pkgpath) and not seen[pkgpath] then
                                out[#out + 1] = pkgpath
                                seen[pkgpath] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

function RuntimePath.split(s)
    return split_csv(s)
end

function RuntimePath.normalize(path)
    return normalize(path)
end

function RuntimePath.is_after(path)
    return is_after(path)
end

function RuntimePath.get_list()
    local raw = Options.get("runtimepath", nil, nil, false, true)
    local list = split_csv(raw)
    local out, seen = {}, {}
    for _, p in ipairs(list) do
        local n = normalize(p)
        if n ~= "" and not seen[n] then
            out[#out + 1] = n
            seen[n] = true
        end
    end
    return out
end

function RuntimePath.get_search_list()
    local out, seen = {}, {}
    local rtp = RuntimePath.get_list()
    for _, p in ipairs(rtp) do
        local n = normalize(p)
        if n ~= "" and not seen[n] then
            out[#out + 1] = n
            seen[n] = true
        end
    end

    local starts = list_start_packages()
    for _, p in ipairs(starts) do
        local n = normalize(p)
        if n ~= "" and not seen[n] then
            out[#out + 1] = n
            seen[n] = true
        end
    end

    return out
end

function RuntimePath.set_list(list)
    local out, seen = {}, {}
    for _, p in ipairs(list or {}) do
        local n = normalize(p)
        if n ~= "" and not seen[n] then
            out[#out + 1] = n
            seen[n] = true
        end
    end
    Options.set("runtimepath", table.concat(out, ","))
end

function RuntimePath.add(path, opts)
    opts = opts or {}
    local list = RuntimePath.get_list()
    local n = normalize(path)
    if n == "" then
        return false
    end
    for _, p in ipairs(list) do
        if normalize(p) == n then
            return false
        end
    end
    if opts.after then
        list[#list + 1] = n
    else
        local idx = #list + 1
        for i, p in ipairs(list) do
            if is_after(p) then
                idx = i
                break
            end
        end
        table.insert(list, idx, n)
    end
    RuntimePath.set_list(list)
    return true
end

return RuntimePath
