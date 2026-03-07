local Assert = {}

local function fail(msg)
    error(msg, 2)
end

function Assert.eq(label, got, want)
    if got ~= want then
        fail(string.format("%s: expected %s, got %s", label, tostring(want), tostring(got)))
    end
end

function Assert.truthy(label, cond, detail)
    if not cond then
        fail(string.format("%s: %s", label, tostring(detail or "expected truthy")))
    end
end

function Assert.table_eq(label, got, want)
    Assert.eq(label .. " length", #got, #want)
    for i = 1, #want do
        Assert.eq(string.format("%s[%d]", label, i), got[i], want[i])
    end
end

function Assert.contains_pair(label, rows, key, value)
    for i = 1, #rows do
        local row = rows[i]
        if row[1] == key and row[2] == value then
            return
        end
    end
    fail(string.format("%s: missing pair (%s,%s)", label, tostring(key), tostring(value)))
end

function Assert.eval(backend, label, expr)
    local result, err = backend:eval_lua(expr)
    Assert.truthy(label, result ~= nil, err)
    return result
end

function Assert.eval_eq(backend, label, expr, expected)
    local result = Assert.eval(backend, "eval " .. label, expr)
    Assert.eq(label, result, expected)
end

function Assert.eval_block(backend, label, code)
    local result, err = backend:eval_block(code)
    Assert.eq(label .. " error", err, nil)
    return result
end

function Assert.expect_error(backend, label, expr, error_pattern)
    local code = string.format(
        "(function() local ok, err = pcall(function() return %s end); "
        .. "return {ok, err and tostring(err):find('%s') ~= nil or false} end)()",
        expr, error_pattern)
    local result = Assert.eval(backend, "eval " .. label, code)
    Assert.table_eq(label, result, {false, true})
end

function Assert.expect_error_block(backend, label, code, error_pattern)
    local wrapped = string.format(
        "local ok, err = pcall(function()\n%s\nend)\n"
        .. "return {ok, err and tostring(err):find(%q, 1, true) ~= nil or false}",
        code, error_pattern)
    local result = Assert.eval_block(backend, "eval " .. label, wrapped)
    Assert.table_eq(label, result, {false, true})
end

function Assert.eval_vim(backend, label, expr, opts)
    local result, err = backend:eval_vimscript(expr, opts)
    Assert.truthy(label, result ~= nil, err)
    return result
end

function Assert.eval_vim_eq(backend, label, expr, expected, opts)
    local result = Assert.eval_vim(backend, "eval_vimscript " .. label, expr, opts)
    Assert.eq(label, result, expected)
end

return Assert
