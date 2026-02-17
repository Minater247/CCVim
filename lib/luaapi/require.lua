local package = loadModule("vim.lib.luaapi.package")
local RuntimePath = loadModule("vim.lib.runtimepath")

local function join_path(base, sub)
    if base:sub(-1) == "/" then
        return base .. sub
    end
    return base .. "/" .. sub
end

local function find_module_path(dotpath)
    local modpath = dotpath:gsub("%.", "/")
    local rtp = RuntimePath.get_list()
    for _, base in ipairs(rtp) do
        local lua_base = join_path(base, "lua/" .. modpath)
        if fs.exists(lua_base .. ".lua") then
            return lua_base .. ".lua"
        end
        if fs.isDir(lua_base) then
            local init = lua_base .. "/init.lua"
            if fs.exists(init) then
                return init
            end
        end
    end
    return nil
end

return function(dotpath)
    -- Return cached/preloaded module if present (matches Lua's require behavior)
    if package.loaded[dotpath] ~= nil then
        return package.loaded[dotpath]
    end

    local LuaLoader = loadModule("vim.lib.lualoader")
    local realpath = find_module_path(dotpath)
    if not realpath then
        -- TODO: properly list out the files
        error("module '" .. dotpath .. "' not found: ")
    end

    local ok, loaded = pcall(LuaLoader.LoadFile, realpath)
    if not ok then
        error(loaded)
    end
    -- Cache the module; if module returns nil, store true per Lua convention
    if loaded == nil then loaded = true end
    package.loaded[dotpath] = loaded
    return loaded
end
