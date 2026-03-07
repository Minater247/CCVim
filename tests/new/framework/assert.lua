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

return Assert
