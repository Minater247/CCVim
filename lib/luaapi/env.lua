local env = {}
local EnvVars = loadModule("lib.envvars")

setmetatable(env, {
    __index = function(_, idx)
        return EnvVars.get(idx)
    end,
    __newindex = function(_, idx, val)
        if val == nil then
            EnvVars.unset(idx)
        else
            EnvVars.set(idx, val)
        end
    end
})

return env
