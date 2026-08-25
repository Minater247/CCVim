local FsUtil = {}

function FsUtil.join(base, name)
    return base .. (base:sub(-1) == "/" and "" or "/") .. tostring(name)
end

function FsUtil.list_sorted(path)
    local entries = fs.list(path) or {}
    table.sort(entries)
    return entries
end

return FsUtil
