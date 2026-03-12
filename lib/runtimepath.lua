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

local function list_dir_sorted(path)
    local entries = fs.list(path) or {}
    table.sort(entries)
    return entries
end

local function dedup_normalize(list, out, seen)
    out = out or {}
    seen = seen or {}
    for _, p in ipairs(list) do
        local n = normalize(p)
        if n ~= "" and not seen[n] then
            out[#out + 1] = n
            seen[n] = true
        end
    end
    return out, seen
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
                for _, group in ipairs(list_dir_sorted(packdir)) do
                    local startdir = packdir .. "/" .. group .. "/start"
                    if fs.isDir(startdir) then
                        for _, pkg in ipairs(list_dir_sorted(startdir)) do
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

local function list_opt_packages()
    local raw = Options.get("packpath", nil, nil, false, true)
    local roots = split_csv(raw)
    local out, seen = {}, {}
    for _, root in ipairs(roots) do
        local base = normalize(root)
        if base ~= "" then
            local packdir = base .. "/pack"
            if fs.isDir(packdir) then
                for _, group in ipairs(list_dir_sorted(packdir)) do
                    local optdir = packdir .. "/" .. group .. "/opt"
                    if fs.isDir(optdir) then
                        for _, pkg in ipairs(list_dir_sorted(optdir)) do
                            local pkgpath = optdir .. "/" .. pkg
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

RuntimePath.split = split_csv
RuntimePath.normalize = normalize
RuntimePath.is_after = is_after
RuntimePath.get_start_package_list = list_start_packages
RuntimePath.get_opt_package_list = list_opt_packages

function RuntimePath.get_list()
    local raw = Options.get("runtimepath", nil, nil, false, true)
    return (dedup_normalize(split_csv(raw)))
end

function RuntimePath.get_search_list()
    local out, seen = dedup_normalize(RuntimePath.get_list())
    dedup_normalize(list_start_packages(), out, seen)
    return out
end

function RuntimePath.set_list(list)
    local out = dedup_normalize(list or {})
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
