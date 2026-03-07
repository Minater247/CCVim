local HeadlessNvimBackend = {}

-- Metatable marker for empty dictionaries
local EMPTY_DICT_MT = {}

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(cmd)
    local p = io.popen(cmd .. " 2>&1", "r")
    if not p then
        return false, "failed to launch command"
    end
    local out = p:read("*a") or ""
    local ok = p:close()
    if ok == true or ok == 0 then
        return true, out
    end
    return false, out
end

local function json_decode_raw(json_str)
    if type(json_str) ~= "string" then
        return nil, "json_decode expects a string"
    end

    local pos = 1
    local len = #json_str

    local function skip_whitespace()
        while pos <= len and json_str:sub(pos, pos):match("[%s]") do
            pos = pos + 1
        end
    end

    local function decode_value()
        skip_whitespace()
        if pos > len then
            return nil, "unexpected end of JSON"
        end

        local char = json_str:sub(pos, pos)

        if char == '"' then
            pos = pos + 1
            local result = {}
            while pos <= len do
                local c = json_str:sub(pos, pos)
                if c == '"' then
                    pos = pos + 1
                    return table.concat(result)
                elseif c == "\\" then
                    pos = pos + 1
                    local esc = json_str:sub(pos, pos)
                    if esc == 'n' then
                        result[#result + 1] = "\n"
                    elseif esc == 't' then
                        result[#result + 1] = "\t"
                    elseif esc == 'r' then
                        result[#result + 1] = "\r"
                    elseif esc == 'b' then
                        result[#result + 1] = "\b"
                    elseif esc == 'f' then
                        result[#result + 1] = "\f"
                    elseif esc == '\\' then
                        result[#result + 1] = "\\"
                    elseif esc == '"' then
                        result[#result + 1] = '"'
                    elseif esc == '/' then
                        result[#result + 1] = '/'
                    else
                        result[#result + 1] = esc
                    end
                    pos = pos + 1
                else
                    result[#result + 1] = c
                    pos = pos + 1
                end
            end
            return nil, "unterminated string"
        elseif char == '[' then
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if pos <= len and json_str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                local val, err = decode_value()
                if err then
                    return nil, err
                end
                arr[#arr + 1] = val
                skip_whitespace()
                if pos > len then
                    return nil, "unterminated array"
                end
                local next_char = json_str:sub(pos, pos)
                if next_char == ']' then
                    pos = pos + 1
                    return arr
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    return nil, "expected ',' or ']' in array"
                end
            end
        elseif char == '{' then
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if pos <= len and json_str:sub(pos, pos) == '}' then
                pos = pos + 1
                return setmetatable({}, EMPTY_DICT_MT)
            end
            while true do
                skip_whitespace()
                if pos > len or json_str:sub(pos, pos) ~= '"' then
                    return nil, "expected string key in object"
                end
                local key, err = decode_value()
                if err then
                    return nil, err
                end
                skip_whitespace()
                if pos > len or json_str:sub(pos, pos) ~= ':' then
                    return nil, "expected ':' after object key"
                end
                pos = pos + 1
                local val, err2 = decode_value()
                if err2 then
                    return nil, err2
                end
                obj[key] = val
                skip_whitespace()
                if pos > len then
                    return nil, "unterminated object"
                end
                local next_char = json_str:sub(pos, pos)
                if next_char == '}' then
                    pos = pos + 1
                    return obj
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    return nil, "expected ',' or '}' in object"
                end
            end
        elseif char == 't' then
            if json_str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
            return nil, "invalid JSON value"
        elseif char == 'f' then
            if json_str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
            return nil, "invalid JSON value"
        elseif char == 'n' then
            if json_str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
            return nil, "invalid JSON value"
        elseif char:match("[-0-9]") then
            local num_start = pos
            if char == '-' then
                pos = pos + 1
            end
            while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
            if pos <= len and json_str:sub(pos, pos) == '.' then
                pos = pos + 1
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            if pos <= len and json_str:sub(pos, pos):match("[eE]") then
                pos = pos + 1
                if pos <= len and json_str:sub(pos, pos):match("[+-]") then
                    pos = pos + 1
                end
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            local num_str = json_str:sub(num_start, pos - 1)
            return tonumber(num_str)
        else
            return nil, "unexpected character: " .. char
        end
    end

    local result, err = decode_value()
    if err then
        return nil, err
    end
    skip_whitespace()
    if pos <= len then
        return nil, "trailing garbage after JSON"
    end
    return result, nil
end

-- Decode JSON with support for reference preservation
local function json_decode(json_str)
    local decoded, err = json_decode_raw(json_str)
    if err then
        return nil, err
    end

    -- Check if this is a reference-encoded structure
    if type(decoded) ~= "table" or not decoded.refs or not decoded.root then
        -- Not reference-encoded, just restore empty dicts
        local function simple_restore(val)
            if type(val) ~= "table" then
                return val
            end
            local count = 0
            for _ in pairs(val) do
                count = count + 1
            end
            if count == 0 then
                return setmetatable({}, EMPTY_DICT_MT)
            end
            local tbl = {}
            for k, v in pairs(val) do
                tbl[k] = simple_restore(v)
            end
            return tbl
        end
        return simple_restore(decoded)
    end

    -- Restore table references
    local ref_data = decoded.refs
    local materialized = {}  -- Map from ref ID to actual table

    local function restore_refs(val)
        if type(val) ~= "table" then
            return val
        end

        -- Check for reference marker
        local ref_id = val.__ref
        if ref_id then
            -- Check if already materialized
            if materialized[ref_id] then
                return materialized[ref_id]
            end
            
            -- Get the ref data (refs is an array with 1-based indexing)
            local data = ref_data[ref_id]
            if not data then
                return nil, "invalid reference ID: " .. tostring(ref_id)
            end
            
            -- Check for special markers or empty tables
            local is_empty_dict_marker = data.__vim_empty_dict
            
            -- Create the table first
            local tbl
            if is_empty_dict_marker then
                -- Explicitly marked as empty dict
                tbl = setmetatable({}, EMPTY_DICT_MT)
            else
                local count = 0
                for _ in pairs(data) do
                    count = count + 1
                end
                
                if count == 0 then
                    -- Empty table - check if it's an empty dict (has EMPTY_DICT_MT)
                    -- or empty array (no metatable from JSON [])
                    if getmetatable(data) == EMPTY_DICT_MT then
                        tbl = setmetatable({}, EMPTY_DICT_MT)
                    else
                        -- Empty array from JSON []
                        tbl = {}
                    end
                else
                    tbl = {}
                end
            end
            materialized[ref_id] = tbl
            
            -- Now populate it
            for k, v in pairs(data) do
                if k ~= "__vim_empty_dict" then
                    tbl[k] = restore_refs(v)
                end
            end
            
            return tbl
        end

        -- Regular non-ref table, restore recursively
        local tbl = {}
        for k, v in pairs(val) do
            tbl[k] = restore_refs(v)
        end
        return tbl
    end

    return restore_refs(decoded.root)
end

function HeadlessNvimBackend.new()
    local backend = {
        name = "headless_nvim",
        EMPTY_DICT_MT = EMPTY_DICT_MT,
    }

    function backend:eval_lua(lua_expr)
        local tmp = string.format("/tmp/nvim-test-eval-%d.lua", os.time())
        local f = assert(io.open(tmp, "w"))
        -- Write the encoder function
        f:write([[
local function serialize_with_refs(value)
  local refs = {}      -- Map from table to ref ID
  local ref_data = {}  -- Map from ref ID to encoded data
  local next_id = 1
  
  -- Capture vim.empty_dict()'s metatable for detection
  local empty_dict_mt = getmetatable(vim.empty_dict())
  
  -- First pass: assign IDs to all tables and track references
  local function assign_ids(val)
    if type(val) == "table" then
      if not refs[val] then
        local id = next_id
        next_id = next_id + 1
        refs[val] = id
        
        -- Recurse into table contents
        for k, v in pairs(val) do
          assign_ids(k)
          assign_ids(v)
        end
      end
    end
  end
  
  assign_ids(value)
  
  -- Second pass: encode each unique table
  local function encode(val)
    local t = type(val)
    if t == "table" then
      local id = refs[val]
      if ref_data[id] then
        -- Already encoded, return reference
        return {__ref = id}
      end
      
      -- Check if this is an empty_dict
      local is_empty_dict = (getmetatable(val) == empty_dict_mt)
      
      -- Encode this table
      local is_list = vim.islist and vim.islist(val) or vim.tbl_islist(val)
      local encoded
      
      if is_list then
        encoded = {}
        for i, v in ipairs(val) do
          encoded[i] = encode(v)
        end
      elseif is_empty_dict then
        -- Mark as empty dict with special flag
        encoded = {__vim_empty_dict = true}
      else
        encoded = {}
        for k, v in pairs(val) do
          encoded[k] = encode(v)
        end
      end
      
      ref_data[id] = encoded
      return {__ref = id}
    else
      return val
    end
  end
  
  local root = encode(value)
  return {refs = ref_data, root = root}
end

]])
        f:write("local ok, rv = pcall(function() return ", lua_expr, " end)\n")
        f:write("if not ok then\n")
        f:write("  io.stderr:write('E:' .. tostring(rv) .. '\\n')\n")
        f:write("  vim.cmd('cq')\n")
        f:write("  return\n")
        f:write("end\n")
        f:write("print('@@RESULT@@' .. vim.json.encode(serialize_with_refs(rv)))\n")
        f:write("vim.cmd('qa!')\n")
        f:close()

        local cmd = "nvim --headless -u NONE -n -l " .. shell_quote(tmp)
        local ok, out = run(cmd)
        os.remove(tmp)
        if not ok then
            return nil, out
        end
        local json_result = out:match("@@RESULT@@([^\n\r]+)")
        if not json_result then
            return nil, "missing result marker: " .. out
        end
        return json_decode(json_result)
    end

    function backend:eval_vimscript(vimscript_expr)
        if type(vimscript_expr) ~= "string" then
            return nil, "eval_vimscript expects a string expression"
        end
        return self:eval_lua(string.format("vim.fn.eval(%q)", vimscript_expr))
    end

    function backend:eval_block(code)
        if type(code) ~= "string" then
            return nil, "eval_block expects a string containing Lua code"
        end
        
        local tmp = string.format("/tmp/nvim-test-eval-%d.lua", os.time())
        local f = assert(io.open(tmp, "w"))
        -- Write the encoder function
        f:write([[
local function serialize_with_refs(value)
  local refs = {}      -- Map from table to ref ID
  local ref_data = {}  -- Map from ref ID to encoded data
  local next_id = 1
  
  -- Capture vim.empty_dict()'s metatable for detection
  local empty_dict_mt = getmetatable(vim.empty_dict())
  
  -- First pass: assign IDs to all tables and track references
  local function assign_ids(val)
    if type(val) == "table" then
      if not refs[val] then
        local id = next_id
        next_id = next_id + 1
        refs[val] = id
        
        -- Recurse into table contents
        for k, v in pairs(val) do
          assign_ids(k)
          assign_ids(v)
        end
      end
    end
  end
  
  assign_ids(value)
  
  -- Second pass: encode each unique table
  local function encode(val)
    local t = type(val)
    if t == "table" then
      local id = refs[val]
      if ref_data[id] then
        -- Already encoded, return reference
        return {__ref = id}
      end
      
      -- Check if this is an empty_dict
      local is_empty_dict = (getmetatable(val) == empty_dict_mt)
      
      -- Encode this table
      local is_list = vim.islist and vim.islist(val) or vim.tbl_islist(val)
      local encoded
      
      if is_list then
        encoded = {}
        for i, v in ipairs(val) do
          encoded[i] = encode(v)
        end
      elseif is_empty_dict then
        -- Mark as empty dict with special flag
        encoded = {__vim_empty_dict = true}
      else
        encoded = {}
        for k, v in pairs(val) do
          encoded[k] = encode(v)
        end
      end
      
      ref_data[id] = encoded
      return {__ref = id}
    else
      return val
    end
  end
  
  local root = encode(value)
  return {refs = ref_data, root = root}
end

]])
        f:write("local ok, rv = pcall(function()\n")
        f:write(code)
        f:write("\nend)\n")
        f:write("if not ok then\n")
        f:write("  io.stderr:write('E:' .. tostring(rv) .. '\\n')\n")
        f:write("  vim.cmd('cq')\n")
        f:write("  return\n")
        f:write("end\n")
        f:write("if rv ~= nil then\n")
        f:write("  print('@@RESULT@@' .. vim.json.encode(serialize_with_refs(rv)))\n")
        f:write("end\n")
        f:write("vim.cmd('qa!')\n")
        f:close()

        local cmd = "nvim --headless -u NONE -n -l " .. shell_quote(tmp)
        local ok, out = run(cmd)
        os.remove(tmp)
        if not ok then
            return nil, out
        end
        local json_result = out:match("@@RESULT@@([^\n\r]+)")
        if not json_result then
            return nil, nil
        end
        return json_decode(json_result)
    end

    function backend:is_empty_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        return getmetatable(tbl) == EMPTY_DICT_MT
    end

    function backend:is_list(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_empty_dict(tbl) then
            return false
        end
        local n = 0
        for k, _ in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                return false
            end
            if k > n then
                n = k
            end
        end
        for i = 1, n do
            if tbl[i] == nil then
                return false
            end
        end
        return true
    end

    function backend:is_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_empty_dict(tbl) then
            return true
        end
        return not self:is_list(tbl)
    end

    function backend:cleanup()
    end

    return backend
end

return HeadlessNvimBackend
