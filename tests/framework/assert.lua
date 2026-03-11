local Assert = {}

local function fail(msg)
    error(msg, 2)
end

local function extract_top_error_code(err)
    if type(err) ~= "string" then
        return nil
    end
    return err:match("(E%d+)")
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
        .. "local msg = (type(err) == 'table' and type(err.toString) == 'function') and err:toString() or tostring(err or ''); "
        .. "return {ok, err and msg:find('%s') ~= nil or false} end)()",
        expr, error_pattern)
    local result = Assert.eval(backend, "eval " .. label, code)
    Assert.table_eq(label, result, {false, true})
end

function Assert.expect_error_block(backend, label, code, error_pattern)
    local wrapped = string.format(
        "local ok, err = pcall(function()\n%s\nend)\n"
        .. "local msg = (type(err) == 'table' and type(err.toString) == 'function') and err:toString() or tostring(err or '')\n"
        .. "return {ok, err and msg:find(%q, 1, true) ~= nil or false}",
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

function Assert.expect_error_vim(backend, label, expr, error_pattern, opts)
    local result, err = backend:eval_vimscript(expr, opts)
    Assert.eq(label .. " result", result, nil)
    Assert.truthy(
        label .. " error",
        type(err) == "string" and err:find(error_pattern, 1, true) ~= nil,
        err
    )
end

function Assert.top_error_code(label, err, expected)
    local actual = extract_top_error_code(err)
    Assert.eq(label, actual, expected)
end

function Assert.expect_error_code(backend, label, expr, expected_code)
    local code = string.format(
        "(function() local ok, err = pcall(function() return %s end); "
        .. "local msg = (type(err) == 'table' and type(err.toString) == 'function') and err:toString() or tostring(err or ''); "
        .. "return {ok, msg} end)()",
        expr)
    local result = Assert.eval(backend, "eval " .. label, code)
    Assert.eq(label .. " result", result[1], false)
    Assert.top_error_code(label .. " top error", result[2], expected_code)
end

function Assert.expect_error_code_block(backend, label, code, expected_code)
    local wrapped = string.format(
        "local ok, err = pcall(function()\n%s\nend)\n"
        .. "local msg = (type(err) == 'table' and type(err.toString) == 'function') and err:toString() or tostring(err or '')\n"
        .. "return {ok, msg}",
        code)
    local result = Assert.eval_block(backend, "eval " .. label, wrapped)
    Assert.eq(label .. " result", result[1], false)
    Assert.top_error_code(label .. " top error", result[2], expected_code)
end

function Assert.expect_error_code_vim(backend, label, expr, expected_code, opts)
    local result, err = backend:eval_vimscript(expr, opts)
    Assert.eq(label .. " result", result, nil)
    Assert.top_error_code(label .. " top error", err, expected_code)
end

function Assert.temp_path(backend, prefix, suffix)
    if type(backend.make_temp_path) ~= "function" then
        fail("backend is missing make_temp_path()")
    end
    return backend:make_temp_path(prefix, suffix)
end

function Assert.ensure_dir(backend, path)
    if type(backend.ensure_dir) ~= "function" then
        fail("backend is missing ensure_dir()")
    end
    local ok, err = backend:ensure_dir(path)
    Assert.eq("ensure_dir " .. tostring(path) .. " error", err, nil)
    Assert.eq("ensure_dir " .. tostring(path), ok, true)
end

function Assert.write_file(backend, path, content)
    if type(backend.write_file) ~= "function" then
        fail("backend is missing write_file()")
    end
    local ok, err = backend:write_file(path, content)
    Assert.eq("write_file " .. tostring(path) .. " error", err, nil)
    Assert.eq("write_file " .. tostring(path), ok, true)
end

function Assert.remove_path(backend, path)
    if type(backend.remove_path) ~= "function" then
        fail("backend is missing remove_path()")
    end
    local ok, err = backend:remove_path(path)
    Assert.eq("remove_path " .. tostring(path) .. " error", err, nil)
    Assert.eq("remove_path " .. tostring(path), ok, true)
end

return Assert
