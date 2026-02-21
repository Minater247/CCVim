-- Builds an index of files to pull from the repository during install.

local index = {"nvim.lua"}

local function indexPath(dir)
    local files = fs.list(shell.resolve(dir))
    
    for i = 1, #files do
        local path = dir .. "/" .. files[i]
        if fs.isDir(shell.resolve(path)) then
            indexPath(path)
        else
            table.insert(index, path)
        end
    end
end

indexPath("layout")
indexPath("lib")
indexPath("runtime")

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