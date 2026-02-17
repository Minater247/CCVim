local Pack = {}

local Options = loadModule("vim.lib.options")
local RuntimePath = loadModule("vim.lib.runtimepath")
local Error = loadModule("vim.lib.error")
local Scopes = loadModule("vim.lib.luaapi.scopes")
local VimFs = loadModule("vim.lib.luaapi.fs")
local ScriptSource

Pack.loaded = Pack.loaded or {}

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

local function packpath_list()
    local raw = Options.get("packpath", nil, nil, false, true)
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

local function list_dir_sorted(path)
    local entries = fs.list(path) or {}
    table.sort(entries)
    return entries
end

local function find_package_paths(name)
    local results, seen = {}, {}
    for _, root in ipairs(packpath_list()) do
        local packdir = root .. "/pack"
        if fs.isDir(packdir) then
            for _, group in ipairs(list_dir_sorted(packdir)) do
                local gpath = packdir .. "/" .. group
                if fs.isDir(gpath) then
                    local start = gpath .. "/start/" .. name
                    local opt = gpath .. "/opt/" .. name
                    if fs.isDir(start) then
                        if not seen[start] then
                            results[#results + 1] = { path = start, kind = "start" }
                            seen[start] = true
                        end
                    elseif fs.isDir(opt) then
                        if not seen[opt] then
                            results[#results + 1] = { path = opt, kind = "opt" }
                            seen[opt] = true
                        end
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
        local entries = fs.list(dir) or {}
        table.sort(entries)
        for _, name in ipairs(entries) do
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
    ScriptSource = ScriptSource or loadModule("vim.lib.scriptsource")
    for _, path in ipairs(paths) do
        local ok, err = ScriptSource.source(path)
        if not ok then
            return false, err
        end
    end
    return true
end

local function should_load_ftdetect()
    return Scopes.g.did_load_filetypes
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
        RuntimePath.add(pkg, { after = false })
        local after = pkg .. "/after"
        if fs.isDir(after) then
            RuntimePath.add(after, { after = true })
        end

        if not opts.no_load then
            if not Pack.loaded[pkg] then
                local ok, err = source_files(collect_scripts(pkg .. "/plugin", true))
                if not ok then
                    return false, err
                end

                local ok_after, err_after = source_files(collect_scripts(pkg .. "/after/plugin", true))
                if not ok_after then
                    return false, err_after
                end

                if match.kind == "opt" and should_load_ftdetect() then
                    local ok_ft, err_ft = source_files(collect_scripts(pkg .. "/ftdetect", false))
                    if not ok_ft then
                        return false, err_ft
                    end

                    local ok_ft_after, err_ft_after = source_files(collect_scripts(pkg .. "/after/ftdetect", false))
                    if not ok_ft_after then
                        return false, err_ft_after
                    end
                end

                Pack.loaded[pkg] = true
            end
        end
    end

    return true
end

function Pack.load_start()
    local packs = packpath_list()
    for _, root in ipairs(packs) do
        local packdir = root .. "/pack"
        if fs.isDir(packdir) then
            for _, group in ipairs(list_dir_sorted(packdir)) do
                local startdir = packdir .. "/" .. group .. "/start"
                if fs.isDir(startdir) then
                    for _, pkg in ipairs(list_dir_sorted(startdir)) do
                        local pkgpath = startdir .. "/" .. pkg
                        if fs.isDir(pkgpath) then
                            RuntimePath.add(pkgpath, { after = false })
                            local after = pkgpath .. "/after"
                            if fs.isDir(after) then
                                RuntimePath.add(after, { after = true })
                            end

                            if not Pack.loaded[pkgpath] then
                                local ok, err = source_files(collect_scripts(pkgpath .. "/plugin", true))
                                if not ok then
                                    return false, err
                                end
                                Pack.loaded[pkgpath] = true
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

return Pack
