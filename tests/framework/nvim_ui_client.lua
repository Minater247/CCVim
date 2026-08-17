local uv = require("luv")
local string_pack = assert(rawget(string, "pack"))
local string_unpack = assert(rawget(string, "unpack"))

local Client = {}
local EMPTY_ARRAY = {}

local function rpc_error_message(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    return tostring(value.message or value[2] or value[1] or "Neovim RPC error")
end

local function is_array(value)
    if value == EMPTY_ARRAY then
        return true
    end
    local count = 0
    local highest = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > highest then
            highest = key
        end
    end
    return count == highest and count > 0
end

local function pack(value)
    local kind = type(value)
    if value == nil then
        return "\192"
    elseif kind == "boolean" then
        return value and "\195" or "\194"
    elseif kind == "number" then
        if value % 1 ~= 0 then
            return "\203" .. string_pack(">d", value)
        elseif value >= 0 and value < 128 then
            return string.char(value)
        elseif value >= -32 and value < 0 then
            return string.char(value + 256)
        elseif value >= 0 and value < 256 then
            return "\204" .. string.char(value)
        elseif value >= 0 and value < 65536 then
            return "\205" .. string_pack(">I2", value)
        elseif value >= 0 and value < 4294967296 then
            return "\206" .. string_pack(">I4", value)
        elseif value >= -128 and value < 128 then
            return "\208" .. string_pack(">i1", value)
        elseif value >= -32768 and value < 32768 then
            return "\209" .. string_pack(">i2", value)
        else
            return "\210" .. string_pack(">i4", value)
        end
    elseif kind == "string" then
        local length = #value
        if length < 32 then
            return string.char(160 + length) .. value
        elseif length < 256 then
            return "\217" .. string.char(length) .. value
        elseif length < 65536 then
            return "\218" .. string_pack(">I2", length) .. value
        end
        return "\219" .. string_pack(">I4", length) .. value
    elseif kind == "table" then
        local entries = {}
        if is_array(value) then
            for i = 1, #value do
                entries[#entries + 1] = pack(value[i])
            end
            local length = #value
            if length < 16 then
                return string.char(144 + length) .. table.concat(entries)
            end
            return "\220" .. string_pack(">I2", length) .. table.concat(entries)
        end
        for key, item in pairs(value) do
            entries[#entries + 1] = pack(key)
            entries[#entries + 1] = pack(item)
        end
        local length = #entries / 2
        if length < 16 then
            return string.char(128 + length) .. table.concat(entries)
        end
        return "\222" .. string_pack(">I2", length) .. table.concat(entries)
    end
    error("cannot encode MessagePack " .. kind)
end

local function unpack_value(data, index)
    if index > #data then
        return nil, index, false
    end

    local prefix = data:byte(index)
    index = index + 1
    if prefix <= 127 then
        return prefix, index, true
    elseif prefix >= 224 then
        return prefix - 256, index, true
    elseif prefix >= 160 and prefix <= 191 then
        local finish = index + prefix - 160 - 1
        if finish > #data then return nil, index, false end
        return data:sub(index, finish), finish + 1, true
    elseif prefix >= 144 and prefix <= 159 then
        local values = {}
        for i = 1, prefix - 144 do
            local value, next_index, complete = unpack_value(data, index)
            if not complete then return nil, index, false end
            values[i] = value
            index = next_index
        end
        return values, index, true
    elseif prefix >= 128 and prefix <= 143 then
        local values = {}
        for _ = 1, prefix - 128 do
            local key, key_index, key_complete = unpack_value(data, index)
            if not key_complete then return nil, index, false end
            local value, value_index, value_complete = unpack_value(data, key_index)
            if not value_complete then return nil, index, false end
            values[key] = value
            index = value_index
        end
        return values, index, true
    elseif prefix == 192 then
        return nil, index, true
    elseif prefix == 194 then
        return false, index, true
    elseif prefix == 195 then
        return true, index, true
    end

    local fixed_extension_lengths = {
        [212] = 1,
        [213] = 2,
        [214] = 4,
        [215] = 8,
        [216] = 16,
    }
    local fixed_extension_length = fixed_extension_lengths[prefix]
    if fixed_extension_length then
        if index + fixed_extension_length > #data then return nil, index, false end
        return "<extension>", index + fixed_extension_length + 1, true
    end

    local widths = {
        [196] = 1, [197] = 2, [198] = 4,
        [204] = 1, [205] = 2, [206] = 4, [207] = 8,
        [208] = 1, [209] = 2, [210] = 4, [211] = 8,
        [202] = 4, [203] = 8,
        [217] = 1, [218] = 2, [219] = 4,
        [220] = 2, [221] = 4, [222] = 2, [223] = 4,
        [199] = 1, [200] = 2, [201] = 4,
    }
    local width = widths[prefix]
    if not width or index + width - 1 > #data then
        return nil, index, false
    end

    if prefix == 220 or prefix == 221 then
        local count = prefix == 220 and string_unpack(">I2", data, index)
            or string_unpack(">I4", data, index)
        index = index + width
        local values = {}
        for i = 1, count do
            local value, next_index, complete = unpack_value(data, index)
            if not complete then return nil, index, false end
            values[i] = value
            index = next_index
        end
        return values, index, true
    end
    if prefix == 222 or prefix == 223 then
        local count = prefix == 222 and string_unpack(">I2", data, index)
            or string_unpack(">I4", data, index)
        index = index + width
        local values = {}
        for _ = 1, count do
            local key, key_index, key_complete = unpack_value(data, index)
            if not key_complete then return nil, index, false end
            local value, value_index, value_complete = unpack_value(data, key_index)
            if not value_complete then return nil, index, false end
            values[key] = value
            index = value_index
        end
        return values, index, true
    end

    local payload_length
    if prefix == 196 or prefix == 199 or prefix == 217 then
        payload_length = data:byte(index)
    elseif prefix == 197 or prefix == 200 or prefix == 218 then
        payload_length = string_unpack(">I2", data, index)
    elseif prefix == 198 or prefix == 201 or prefix == 219 then
        payload_length = string_unpack(">I4", data, index)
    end
    if payload_length then
        index = index + width
        if index + payload_length - 1 > #data then return nil, index, false end
        if prefix >= 217 and prefix <= 219 then
            return data:sub(index, index + payload_length - 1), index + payload_length, true
        end
        if prefix >= 196 and prefix <= 198 then
            return data:sub(index, index + payload_length - 1), index + payload_length, true
        end
        if index + payload_length > #data then return nil, index, false end
        return "<extension>", index + payload_length + 1, true
    end

    if prefix == 204 then return data:byte(index), index + 1, true end
    if prefix == 205 then return string_unpack(">I2", data, index), index + 2, true end
    if prefix == 206 then return string_unpack(">I4", data, index), index + 4, true end
    if prefix == 208 then return string_unpack(">i1", data, index), index + 1, true end
    if prefix == 209 then return string_unpack(">i2", data, index), index + 2, true end
    if prefix == 210 then return string_unpack(">i4", data, index), index + 4, true end
    if prefix == 202 then return string_unpack(">f", data, index), index + 4, true end
    if prefix == 203 then return string_unpack(">d", data, index), index + 8, true end
    return nil, index, false
end

function Client.eval(setup, query)
    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local output = ""
    local errors = ""
    local closed = false
    local handle, spawn_err = uv.spawn("nvim", {
        args = { "--embed", "-u", "NONE", "-n" },
        stdio = { stdin, stdout, stderr },
    }, function()
        closed = true
    end)
    if not handle then
        return nil, spawn_err
    end

    stdout:read_start(function(err, data)
        if err then errors = errors .. err end
        if data then output = output .. data end
    end)
    stderr:read_start(function(err, data)
        if err then errors = errors .. err end
        if data then errors = errors .. data end
    end)

    local next_request_id = 1
    local function request(method, args)
        local request_id = next_request_id
        next_request_id = next_request_id + 1
        uv.write(stdin, pack({ 0, request_id, method, args }))
        local deadline = uv.now() + 5000
        while uv.now() < deadline and not closed do
            uv.run("nowait")
            local message, next_index, complete = unpack_value(output, 1)
            if complete then
                output = output:sub(next_index)
                if message[1] == 1 and message[2] == request_id then
                    if message[3] ~= nil then
                        return nil, rpc_error_message(message[3])
                    end
                    return message[4], nil
                end
            end
            uv.sleep(1)
        end
        return nil, errors ~= "" and errors or "timed out waiting for Neovim RPC response"
    end

    local _, attach_err = request("nvim_ui_attach", { 80, 24, {} })
    if attach_err then
        handle:close()
        return nil, attach_err
    end
    local _, setup_err = request("nvim_exec_lua", { setup, EMPTY_ARRAY })
    if setup_err then
        handle:close()
        return nil, setup_err
    end
    local _, redraw_err = request("nvim_command", { "redraw" })
    if redraw_err then
        handle:close()
        return nil, redraw_err
    end
    local result, query_err = request("nvim_exec_lua", { query, EMPTY_ARRAY })
    request("nvim_command", { "qa!" })
    handle:close()
    return result, query_err
end

return Client
