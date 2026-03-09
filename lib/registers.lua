local RegisterUtil = {}

local Key = loadModule("lib.key")

function RegisterUtil.is_list(t)
    if type(t) ~= "table" then return false end
    local maxk = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
        if k > maxk then maxk = k end
        count = count + 1
    end
    return count == maxk
end

function RegisterUtil.storage_key(regname)
    if regname == '"' then
        return "unnamed"
    end
    if regname:match("^%a$") then
        return regname:lower()
    end
    if regname:match("^%d$") then
        return tonumber(regname)
    end
    return regname
end

function RegisterUtil.split_lines(text)
    if text == "" then
        return { "" }
    end
    local out = {}
    local start = 1
    while true do
        local idx = text:find("\n", start, true)
        if not idx then
            out[#out + 1] = text:sub(start)
            break
        end
        out[#out + 1] = text:sub(start, idx - 1)
        start = idx + 1
    end
    return out
end

local function copy_payload_list(src)
    local out = {}
    for i = 1, #src do
        out[#out + 1] = tostring(src[i] or "")
    end
    return out
end

function RegisterUtil.entry_to_text(entry)
    if entry == nil then
        return ""
    end
    if type(entry) ~= "table" then
        return tostring(entry)
    end

    local kind = entry[1]
    local payload = entry[2]
    if type(payload) == "table" then
        local parts = copy_payload_list(payload)
        if kind == "inline" then
            return table.concat(parts)
        end
        local text = table.concat(parts, "\n")
        if kind == "linewise" then
            return text .. "\n"
        end
        return text
    end
    return tostring(payload or "")
end

function RegisterUtil.entry_to_lines(entry)
    if entry == nil then
        return {}
    end
    if type(entry) ~= "table" then
        return RegisterUtil.split_lines(tostring(entry))
    end

    local kind = entry[1]
    local payload = entry[2]
    if type(payload) == "table" then
        return copy_payload_list(payload)
    end

    local text = tostring(payload or "")
    local out = RegisterUtil.split_lines(text)
    if kind == "linewise" and text:sub(-1) == "\n" and #out > 0 and out[#out] == "" then
        table.remove(out, #out)
    end
    return out
end

function RegisterUtil.mode_from_options(value, options)
    options = tostring(options or "")
    if options:find("[vc]") then
        return "charwise"
    end
    if options:find("[lV]") then
        return "linewise"
    end
    if options:find("b", 1, true) or options:find(string.char(22), 1, true) then
        return "blockwise"
    end

    if type(value) == "table" and RegisterUtil.is_list(value) then
        return "linewise"
    end
    if type(value) == "string" and value:sub(-1) == "\n" then
        return "linewise"
    end
    return "charwise"
end

function RegisterUtil.normalize_value(value, mode)
    if type(value) == "table" and (not RegisterUtil.is_list(value)) then
        local info = value
        if type(info.regcontents) == "table" then
            value = info.regcontents
        elseif type(info.regcontents) == "string" then
            value = info.regcontents
        end
        if type(info.regtype) == "string" and info.regtype ~= "" then
            local prefix = info.regtype:sub(1, 1)
            if prefix == "V" or prefix == "l" then
                mode = "linewise"
            elseif prefix == "b" or prefix == string.char(22) then
                mode = "blockwise"
            else
                mode = "charwise"
            end
        end
    end

    if mode == "linewise" then
        local lines = {}
        if type(value) == "table" and RegisterUtil.is_list(value) then
            for i = 1, #value do
                lines[#lines + 1] = tostring(value[i] or "")
            end
        else
            local text = tostring(value or "")
            lines = RegisterUtil.split_lines(text)
            if text:sub(-1) == "\n" and #lines > 0 and lines[#lines] == "" then
                table.remove(lines, #lines)
            end
        end
        return { "linewise", lines }
    end

    return { "charwise", tostring(value or "") }
end

function RegisterUtil.get_entry(regname)
    local reg = tostring(regname or "")
    if reg == "" or reg == "@" then
        reg = '"'
    end
    reg = reg:sub(1, 1)

    local key = RegisterUtil.storage_key(reg)
    local entry = registers[key]
    if entry == nil and reg == '"' then
        entry = registers.unnamed
    end
    return entry
end

function RegisterUtil.set_entry(regname, entry)
    local reg = tostring(regname or "")
    if reg == "" or reg == "@" then
        reg = '"'
    end
    reg = reg:sub(1, 1)

    local key = RegisterUtil.storage_key(reg)
    registers[key] = entry
    if reg == '"' then
        registers.unnamed = entry
    end
    return entry
end

function RegisterUtil.sequence_to_text(seq)
    local out = {}
    for i = 1, #(seq or {}) do
        out[#out + 1] = Key.to_termcode_string(seq[i], { force_keycode = false, from_expr = false })
    end
    return table.concat(out)
end

function RegisterUtil.sequence_to_entry(seq, mode)
    return { mode or "charwise", RegisterUtil.sequence_to_text(seq) }
end

function RegisterUtil.entry_to_sequence(entry)
    local text = RegisterUtil.entry_to_text(entry)
    if text == "" then
        return {}
    end
    return Key.strtoseq(text)
end

return RegisterUtil
