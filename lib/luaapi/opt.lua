local opt = {}

local opt_mt = {}

local print = loadModule("lib.luaapi.print")

opt_mt.__index = function(self, name)
    return {
        get = function()
            return options.get(name,
                windows[curwin],
                windows[curwin].buffer)
        end,
        append = function(_, toapp)
            local val = options.get(name, windows[curwin], windows[curwin].buffer)
            if type(val) == "string" then
                -- TODO: table handling is very weird here. Nvim-Tree seems nonstandard
                if type(toapp) == "table" then
                    toapp = toapp[1]
                end

                val = val .. toapp
            elseif type(val) == "table" then
                val[#val + 1] = toapp
            else
                error("Unhandled type for append(): " .. type(val) .. "[[" .. name .. "]]")
            end
            options.set(name, val, false, windows[curwin], windows[curwin].buffer)
        end
    }
end

opt_mt.__newindex = function(self, name, value)
    options.set(name, value, false, windows[curwin], windows[curwin].buffer)
end

setmetatable(opt, opt_mt)


return opt
