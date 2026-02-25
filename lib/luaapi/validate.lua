local validate = {}

local function is_callable(v)
    if type(v) == "function" then
        return true
    end
    local mt = getmetatable(v)
    return mt ~= nil and type(mt.__call) == "function"
end

local function validate_one(name, value, validator, optional, message)
    if value == nil and optional == true then
        return
    end

    local function type_ok(expected)
        if expected == "callable" then
            return is_callable(value)
        end
        return type(value) == expected
    end

    local ok = false
    if type(validator) == "string" then
        ok = type_ok(validator)
    elseif type(validator) == "table" then
        for i = 1, #validator do
            local v = validator[i]
            if type(v) == "string" and type_ok(v) then
                ok = true
                break
            end
        end
    elseif type(validator) == "function" then
        local rv = validator(value)
        ok = rv and true or false
    end

    if not ok then
        local expected = message
        if not expected then
            if type(validator) == "table" then
                expected = table.concat(validator, "|")
            else
                expected = tostring(validator)
            end
        end
        error(("%s: expected %s, got %s"):format(tostring(name), tostring(expected), type(value)), 3)
    end
end

function validate.validate(name, value, validator, optional, message)
    if validator ~= nil then
        if type(optional) == "string" and message == nil then
            message = optional
            optional = false
        end
        validate_one(name, value, validator, optional, message)
        return
    end

    -- Minimal legacy form support: vim.validate({ key = {value, validator, optional_or_msg}, ... })
    if type(name) ~= "table" then
        error("invalid arguments", 2)
    end
    for k, spec in pairs(name) do
        if type(spec) ~= "table" then
            error(("invalid validation spec for %s"):format(tostring(k)), 2)
        end
        local v = spec[1]
        local vd = spec[2]
        local opt = spec[3]
        local msg = nil
        if type(opt) == "string" then
            msg = opt
            opt = false
        end
        validate_one(k, v, vd, opt, msg)
    end
end

return validate
