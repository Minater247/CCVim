local Scopes = {}

-- Backing stores
Scopes._g = Scopes._g or {}
Scopes._v = Scopes._v or {}
Scopes._v.errmsg = Scopes._v.errmsg or ""
Scopes._v.event = Scopes._v.event or {}
Scopes._v["true"] = true
Scopes._v["false"] = false
Scopes._b_by_buf = Scopes._b_by_buf or {}
Scopes._w_by_win = Scopes._w_by_win or {}
Scopes._t_by_tab = Scopes._t_by_tab or {}

local function cur_bufnr()
  return (windows[curwin] and windows[curwin].buffer and windows[curwin].buffer.bufnr) or 0
end
local function cur_winnr()
  return curwin
end
local function cur_tabnr()
  return curtp
end

local function ensure_scope_table(store, id)
  local t = store[id]
  if not t then
    t = {}
    store[id] = t
  end
  return t
end

local function resolve_bufnr(bufnr, level)
  if bufnr == nil or bufnr == 0 then
    bufnr = cur_bufnr()
    if bufnr == 0 then
      return 0
    end
  end

  if type(bufnr) ~= "number" or bufnr ~= math.floor(bufnr) then
    error(("invalid buffer id: %s"):format(tostring(bufnr)), level or 2)
  end
  if bufnr ~= 0 and (not buffers or not buffers[bufnr]) then
    error(("invalid buffer id: %s"):format(tostring(bufnr)), level or 2)
  end
  return bufnr
end

local function resolve_winnr(winnr, level)
  if winnr == nil or winnr == 0 then
    winnr = cur_winnr()
  end

  if type(winnr) ~= "number" or winnr ~= math.floor(winnr) or not windows or not windows[winnr] then
    error(("invalid window id: %s"):format(tostring(winnr)), level or 2)
  end
  return winnr
end

local function resolve_tabnr(tabnr, level)
  if tabnr == nil or tabnr == 0 then
    tabnr = cur_tabnr()
  end

  if type(tabnr) ~= "number" or tabnr ~= math.floor(tabnr) or not tabpages or not tabpages[tabnr] then
    error(("invalid tabpage id: %s"):format(tostring(tabnr)), level or 2)
  end
  return tabnr
end

local function proxy_index(backing_get)
  return function(_, k)
    local tbl = backing_get()
    return tbl[k]
  end
end
local function proxy_newindex(backing_get)
  return function(_, k, v)
    local tbl = backing_get()
    tbl[k] = v
  end
end

-- g: global
Scopes.g = setmetatable({}, {
  __index = proxy_index(function() return Scopes._g end),
  __newindex = proxy_newindex(function() return Scopes._g end),
})

-- v: editor-wide (errmsg etc.)
Scopes.v = setmetatable({}, {
  __index = proxy_index(function() return Scopes._v end),
  __newindex = proxy_newindex(function() return Scopes._v end),
})

local function make_scoped_proxy(store, resolve_id, id_field)
  local cache = setmetatable({}, { __mode = "v" })
  local mt = {}

  mt.__index = function(self, k)
    if type(k) == "number" then
      local id = resolve_id(k, 2)
      local p = cache[id]
      if not p then
        p = setmetatable({ [id_field] = id }, mt)
        cache[id] = p
      end
      return p
    end

    local id = rawget(self, id_field)
    if id == nil then
      id = resolve_id(0, 2)
    end
    local tbl = ensure_scope_table(store, id)
    return tbl[k]
  end

  mt.__newindex = function(self, k, v)
    local id = rawget(self, id_field)
    if id == nil then
      id = resolve_id(0, 2)
    end

    local tbl = ensure_scope_table(store, id)
    tbl[k] = v
  end

  return setmetatable({}, mt)
end

Scopes.b = make_scoped_proxy(Scopes._b_by_buf, resolve_bufnr, "__bufnr")
Scopes.w = make_scoped_proxy(Scopes._w_by_win, resolve_winnr, "__winnr")
Scopes.t = make_scoped_proxy(Scopes._t_by_tab, resolve_tabnr, "__tabnr")

return Scopes
