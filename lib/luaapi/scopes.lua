local Scopes = {}
local Error = loadModule("lib.error")

local LOCKED_VALUES = setmetatable({}, { __mode = "k" })
local LOCKED_TABLES = setmetatable({}, { __mode = "k" })

local function lock_value(value)
  if type(value) ~= "table" then return end
  local locked = LOCKED_TABLES[value]
  if locked then locked.refs = locked.refs + 1; return end
  local backing, original_mt = {}, getmetatable(value)
  for key, child in pairs(value) do backing[key] = child; rawset(value, key, nil); lock_value(child) end
  locked = { backing = backing, mt = original_mt, refs = 1 }
  LOCKED_TABLES[value] = locked
  local mt = {}
  if original_mt then for key, child in pairs(original_mt) do mt[key] = child end end
  mt.__index = backing
  mt.__newindex = function() error(Error(741, "const"), 2) end
  mt.__len = function() return #backing end
  mt.__pairs = function() return next, backing end
  setmetatable(value, mt)
end

local function unlock_value(value)
  local locked = type(value) == "table" and LOCKED_TABLES[value]
  if not locked then return end
  locked.refs = locked.refs - 1
  if locked.refs > 0 then return end
  LOCKED_TABLES[value] = nil
  setmetatable(value, locked.mt)
  for key, child in pairs(locked.backing) do rawset(value, key, child); unlock_value(child) end
end

local function lockable(tbl)
  if LOCKED_VALUES[tbl] then return end
  local values = {}
  LOCKED_VALUES[tbl] = values
  setmetatable(tbl, {
    __index = function(_, key)
      local entry = values[key]
      return entry and entry.value
    end,
    __newindex = function(self, key, value)
      if values[key] then
        if value ~= nil then error(Error(741, key), 2) end
        unlock_value(values[key].value)
        values[key] = nil
      else
        rawset(self, key, value)
      end
    end,
    __pairs = function(self)
      local merged = {}
      for key, value in next, self do merged[key] = value end
      for key, entry in pairs(values) do merged[key] = entry.value end
      return next, merged
    end,
  })
end

function Scopes.LockTable(tbl, key, value)
  if tbl[key] ~= nil then return Error(995) end
  lockable(tbl)
  lock_value(value)
  LOCKED_VALUES[tbl][key] = { value = value }
  return true
end

Scopes.MAXCOL = 2147483647

-- Backing stores
Scopes._g = {}
Scopes._v = {}
Scopes._v.errmsg = ""
Scopes._v.exception = ""
Scopes._v.throwpoint = ""
Scopes._v.event = {}
Scopes._v.completed_item = {}
Scopes._v.count = 0
Scopes._v.count1 = 1
Scopes._v.prevcount = 0
Scopes._v.stderr = 2
Scopes._v.maxcol = Scopes.MAXCOL
Scopes._v["true"] = true
Scopes._v["false"] = false
Scopes._v.t_number = 0
Scopes._v.t_string = 1
Scopes._v.t_func = 2
Scopes._v.t_list = 3
Scopes._v.t_dict = 4
Scopes._v.t_float = 5
Scopes._v.t_bool = 6
Scopes._v.t_none = 7
Scopes._b_by_buf = {}
Scopes._w_by_win = {}
Scopes._t_by_tab = {}

local function cur_bufnr()
  return windows[curwin].buffer.bufnr
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

function Scopes.Lock(scope, key, value)
  if scope == "b" then
    return Scopes.LockTable(ensure_scope_table(Scopes._b_by_buf, cur_bufnr()), key, value)
  elseif scope == "w" then
    return Scopes.LockTable(ensure_scope_table(Scopes._w_by_win, cur_winnr()), key, value)
  elseif scope == "t" then
    return Scopes.LockTable(ensure_scope_table(Scopes._t_by_tab, cur_tabnr()), key, value)
  end
  return Error(461, scope .. ":" .. key)
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
