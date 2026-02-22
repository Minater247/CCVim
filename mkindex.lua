-- Builds an index of files to pull from the repository during install.

local index = {"nvim.lua"}

local function indexPath(dir, depth)
    local files = fs.list(shell.resolve(dir))

    depth = depth or 0
    
    for i = 1, #files do
        local path = dir .. "/" .. files[i]
        if fs.isDir(shell.resolve(path)) then
            table.insert(index, string.rep("\t", depth) .. files[i] .. "/")
            indexPath(path, depth + 1)
        else
            table.insert(index, string.rep("\t", depth) .. files[i])
        end
    end
end

local function indexRoot(root)
    table.insert(index, root .. "/")
    indexPath(root, 1)
end

indexRoot("layout")
indexRoot("lib")
indexRoot("runtime")

local indexfile = fs.open(shell.resolve("nvim.idx"), "w")
if not indexfile then
    print("Failed to write index: unable to open file!")
    return
end

for i = 1, #index do
    indexfile.write(index[i] .. "\n")
end

indexfile.close()

print("Index complete.")