local options = loadModule("vim.lib.options")

-- =========
-- wo
-- =========
local function resolve_window(winid)
    local win = windows[winid]
    if not win then
        error(("invalid window id: %s"):format(tostring(winid)), 3)
    end
    return win
end

local function resolve_window_buffer(winid, bufnr)
    local win = resolve_window(winid)
    local resolved = bufnr
    if bufnr == 0 then
        resolved = win.buffer.bufnr
    end
    local buf = buffers[resolved]
    if not buf then
        error(("invalid buffer id: %s"):format(tostring(resolved)), 3)
    end
    return buf
end

local wo_proxy_mt = {}
wo_proxy_mt.__index = function(self, opt)
    if type(opt) == "number" then
        local bufnr = opt
        return setmetatable({
            __winid = rawget(self, "__winid"),
            __bufnr = bufnr,
        }, wo_proxy_mt)
    end

    local winid = rawget(self, "__winid")
    local win = resolve_window(winid)
    local buf = nil
    local bufnr = rawget(self, "__bufnr")
    if bufnr ~= nil then
        buf = resolve_window_buffer(winid, bufnr)
    end
    return options.get(opt, win, buf, true)
end
wo_proxy_mt.__newindex = function(self, opt, val)
    local winid = rawget(self, "__winid")
    local win = resolve_window(winid)
    local buf = nil
    local bufnr = rawget(self, "__bufnr")
    if bufnr ~= nil then
        buf = resolve_window_buffer(winid, bufnr)
    end
    options.set(opt, val, true, win, buf)
end

local wo = {}
local wo_mt = {}
local wo_cache = setmetatable({}, { __mode = "v" })

wo_mt.__index = function(_, k)
    if type(k) == "number" then
        local winid = (k == 0) and curwin or k
        resolve_window(winid)
        local p = wo_cache[winid]
        if not p then
            p = setmetatable({ __winid = winid }, wo_proxy_mt)
            wo_cache[winid] = p
        end
        return p
    else
        -- your code path for current window reads
        return options.get(k, windows[curwin], nil, true)
    end
end

wo_mt.__newindex = function(_, k, v)
    options.set(k, v, true, windows[curwin])
end

setmetatable(wo, wo_mt)

-- =========
-- bo (buffer options) with its own cache
-- =========
local bo_proxy_mt = {}

-- proxy resolves the live buffer table each time using stored bufnr
bo_proxy_mt.__index = function(self, opt)
    local buf = buffers[self.__bufnr]
    if not buf then error(("invalid buffer id: %s"):format(tostring(self.__bufnr)), 2) end
    return options.get(opt, nil, buf, true)
end

bo_proxy_mt.__newindex = function(self, opt, val)
    local buf = buffers[self.__bufnr]
    if not buf then error(("invalid buffer id: %s"):format(tostring(self.__bufnr)), 2) end
    options.set(opt, val, true, nil, buf)
end

local bo = {}
local bo_mt = {}
local bo_cache = setmetatable({}, { __mode = "v" })

bo_mt.__index = function(_, k)
    if type(k) == "number" then
        local bufnr = (k == 0) and windows[curwin].buffer.bufnr or k -- support 0 as "current buffer"
        local buf = buffers[bufnr]
        if not buf then error(("invalid buffer id: %s"):format(tostring(bufnr)), 2) end
        local p = bo_cache[bufnr]
        if not p then
            -- store only the id to avoid keeping the buffer object alive
            p = setmetatable({ __bufnr = bufnr }, bo_proxy_mt)
            bo_cache[bufnr] = p
        end
        return p
    else
        -- read on current buffer
        return options.get(k, nil, windows[curwin].buffer, true)
    end
end

bo_mt.__newindex = function(_, k, v)
    options.set(k, v, true, nil, windows[curwin].buffer)
end

setmetatable(bo, bo_mt)

local go = {}
local go_mt = {}

go_mt.__index = function(_, k)
    return options.get(k, nil, nil, false, true)
end

go_mt.__newindex = function(_, k, v)
    options.set(k, v, false, nil, nil, true)
end

setmetatable(go, go_mt)

local o = {}
local o_mt = {}

o_mt.__index = function(_, k)
    return options.get(k, windows[curwin], windows[curwin].buffer)
end

o_mt.__newindex = function(_, k, v)
    options.set(k, v, false, windows[curwin], windows[curwin].buffer)
end

setmetatable(o, o_mt)

return {
    wo = wo,
    bo = bo,
    go = go,
    o = o,
}
