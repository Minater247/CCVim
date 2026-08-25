-- Compatibility shim for the legacy installer.
local source
if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    source = info and info.source
end
local program = source and source:sub(1, 1) == "@" and source:sub(2) or ((arg and arg[0]) or "vim.lua")
local dir = (program:match("^(.*)/[^/]+$")) or "."
local argv = { ... }

local function load_local_chunk(path)
    local chunk, err = loadfile(path, "t", _ENV)
    if not chunk and setfenv then
        chunk, err = loadfile(path)
        if chunk then
            setfenv(chunk, _ENV)
        end
    end
    if not chunk then
        error(err)
    end
    return chunk
end

arg = { [0] = dir .. "/nvim.lua" }
for i = 1, #argv do
    arg[i] = argv[i]
end

return load_local_chunk(dir .. "/nvim.lua")()
