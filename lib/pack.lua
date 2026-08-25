local Pack = {}

local RuntimePath = loadModule("lib.runtimepath")
local Error = loadModule("lib.error")
local Scopes = loadModule("lib.luaapi.scopes")
local ScriptSource = loadModule("lib.scriptsource")
local FsUtil = loadModule("lib.fsutil")

Pack.loaded = {}

local function find_package_paths(name)
    local results, seen = {}, {}
    for _, root in ipairs(RuntimePath.get_pack_list()) do
        local packdir = root .. "/pack"
        if fs.isDir(packdir) then
            for _, group in ipairs(FsUtil.list_sorted(packdir)) do
                local gpath = packdir .. "/" .. group
                if fs.isDir(gpath) then
                    local start = gpath .. "/start/" .. name
                    local opt = gpath .. "/opt/" .. name
                    if fs.isDir(start) and not seen[start] then
                        results[#results + 1] = { path = start, kind = "start" }
                        seen[start] = true
                    elseif fs.isDir(opt) and not seen[opt] then
                        results[#results + 1] = { path = opt, kind = "opt" }
                        seen[opt] = true
                    end
                end
            end
        end
    end
    return results
end

local function collect_scripts(root, recursive)
    local out = {}
    if not fs.isDir(root) then
        return out
    end

    local function walk(dir)
        for _, name in ipairs(FsUtil.list_sorted(dir)) do
            local path = dir .. "/" .. name
            if fs.isDir(path) then
                if recursive then
                    walk(path)
                end
            else
                local ext = path:match("%.([^.]+)$")
                if ext == "vim" or ext == "lua" then
                    local base = path:gsub("%.[^.]+$", "")
                    out[#out + 1] = { path = path, base = base, ext = ext }
                end
            end
        end
    end

    walk(root)
    table.sort(out, function(a, b)
        if a.base == b.base then
            if a.ext == b.ext then
                return a.path < b.path
            end
            if a.ext == "vim" then
                return true
            end
            if b.ext == "vim" then
                return false
            end
            return a.ext < b.ext
        end
        return a.base < b.base
    end)

    local paths = {}
    for _, item in ipairs(out) do
        paths[#paths + 1] = item.path
    end
    return paths
end

local function source_files(paths)
    for _, path in ipairs(paths) do
        local ok, err = ScriptSource.source(path)
        if not ok then
            return false, err
        end
    end
    return true
end

local function register_pkg(pkg)
    RuntimePath.add(pkg, { after = false })
    local after = pkg .. "/after"
    if fs.isDir(after) then
        RuntimePath.add(after, { after = true })
    end
end

local function load_pkg(pkg, after, ftdetect)
    if Pack.loaded[pkg] then return true end

    local ok, err = source_files(collect_scripts(pkg .. "/plugin", true))
    if not ok then return false, err end

    if after then
        ok, err = source_files(collect_scripts(pkg .. "/after/plugin", true))
        if not ok then return false, err end
    end
    if ftdetect and Scopes.g.did_load_filetypes then
        ok, err = source_files(collect_scripts(pkg .. "/ftdetect", false))
        if not ok then return false, err end
        ok, err = source_files(collect_scripts(pkg .. "/after/ftdetect", false))
        if not ok then return false, err end
    end

    Pack.loaded[pkg] = true
    return true
end

function Pack.add(name, opts)
    opts = opts or {}
    if not name or name == "" then
        return false, Error(471)
    end

    local matches = find_package_paths(name)
    if #matches == 0 then
        return false, Error(919, name)
    end

    for _, match in ipairs(matches) do
        local pkg = match.path
        register_pkg(pkg)

        if not opts.no_load then
            local ok, err = load_pkg(pkg, true, match.kind == "opt")
            if not ok then return false, err end
        end
    end

    return true
end

function Pack.load_start()
    for _, pkg in ipairs(RuntimePath.list_packages("start")) do
        register_pkg(pkg)
        local ok, err = load_pkg(pkg, true)
        if not ok then return false, err end
    end

    return true
end

return Pack
