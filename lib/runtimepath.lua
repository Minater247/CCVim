local RuntimePath = {}

local Options = loadModule("lib.options")
local VimFs = loadModule("lib.luaapi.fs")
local FsUtil = loadModule("lib.fsutil")

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

function RuntimePath.is_after(path)
    local n = normalize(path)
    return n:sub(-6) == "/after"
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

function RuntimePath.list_packages(kind)
    local out, seen = {}, {}
    for _, root in ipairs(RuntimePath.get_pack_list()) do
        local packdir = root .. "/pack"
        if fs.isDir(packdir) then
            for _, group in ipairs(FsUtil.list_sorted(packdir)) do
                local kinddir = packdir .. "/" .. group .. "/" .. kind
                if fs.isDir(kinddir) then
                    for _, pkg in ipairs(FsUtil.list_sorted(kinddir)) do
                        local pkgpath = kinddir .. "/" .. pkg
                        if fs.isDir(pkgpath) and not seen[pkgpath] then
                            out[#out + 1] = pkgpath
                            seen[pkgpath] = true
                        end
                    end
                end
            end
        end
    end
    return out
end

function RuntimePath.get_list()
    local raw = Options.get("runtimepath", nil, nil, false, true)
    return dedup_normalize(split_csv(raw))
end

function RuntimePath.get_pack_list()
    local raw = Options.get("packpath", nil, nil, false, true)
    return dedup_normalize(split_csv(raw))
end

function RuntimePath.get_search_list()
    local out, seen = dedup_normalize(RuntimePath.get_list())
    dedup_normalize(RuntimePath.list_packages("start"), out, seen)
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
            if RuntimePath.is_after(p) then
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
