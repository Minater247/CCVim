local HelpTags = {}
local Error = loadModule("lib.error")

local function join(left, right)
    if left:sub(-1) == "/" then return left .. right end
    return left .. "/" .. right
end

local function collect_files(root, rel, out)
    local dir = rel == "" and root or join(root, rel)
    for _, name in ipairs(fs.list(dir)) do
        local child_rel = rel == "" and name or join(rel, name)
        local path = join(root, child_rel)
        if fs.isDir(path) then
            collect_files(root, child_rel, out)
        elseif name:match("%.txt$") or name:match("%.[%a][%a]x$") then
            out[#out + 1] = child_rel
        end
    end
end

local function escaped_pattern(tag)
    return "/*" .. tag:gsub("\\", "\\\\"):gsub("/", "\\/") .. "*"
end

local function line_tags(line)
    local tags, cursor = {}, 1
    while true do
        local open = line:find("*", cursor, true)
        if not open then return tags end
        local close = line:find("*", open + 1, true)
        if not close then return tags end
        local tag = line:sub(open + 1, close - 1)
        local after = line:sub(close + 1, close + 1)
        if line:sub(open - 1, open - 1) ~= "*"
            and (after == "" or after:match("%s"))
            and tag ~= "" and not tag:find("[%s|]")
        then
            tags[#tags + 1] = tag
        end
        cursor = close + 1
    end
end

function HelpTags.generate(root, force_help_tag)
    if not fs.isDir(root) then error(Error(150, root), 0) end
    local files = {}
    collect_files(root, "", files)
    table.sort(files)

    local groups = {}
    for _, rel in ipairs(files) do
        local language = rel:match("%.([%a][%a])x$")
        local output = language and ("tags-" .. language:lower()) or "tags"
        local group = groups[output]
        if not group then
            group = { rows = {}, seen = {} }
            groups[output] = group
        end
        local handle = assert(fs.open(join(root, rel), "r"))
        while true do
            local line = handle.readLine()
            if line == nil then break end
            for _, tag in ipairs(line_tags(line)) do
                if group.seen[tag] then error(Error(154, tag), 0) end
                group.seen[tag] = true
                group.rows[#group.rows + 1] = tag .. "\t" .. rel .. "\t" .. escaped_pattern(tag)
            end
        end
        handle.close()
    end

    if force_help_tag then
        if not groups.tags then groups.tags = { rows = {}, seen = {} } end
        for output, group in pairs(groups) do
            if group.seen["help-tags"] then error(Error(154, "help-tags"), 0) end
            group.rows[#group.rows + 1] = "help-tags\t" .. output .. "\t1"
        end
    end

    for output, group in pairs(groups) do
        table.sort(group.rows)
        local handle = assert(fs.open(join(root, output), "w"))
        handle.write(table.concat(group.rows, "\n") .. (#group.rows > 0 and "\n" or ""))
        handle.close()
    end
end

return HelpTags
