local Profile = {}

function Profile.set_enabled(ctx, enabled)
    ctx.profile.enabled = enabled
    return true
end

function Profile.clear(ctx)
    ctx.profile.counters = {}
    return true
end

function Profile.report(ctx)
    local status = ctx.profile.enabled and "on" or "off"
    local lines = { ("syntime: %s"):format(status) }
    local counters = ctx.profile.counters or {}
    local rows = {}
    local total_calls = 0
    local total_matches = 0
    local total_time = 0

    for _, entry in pairs(counters) do
        rows[#rows + 1] = entry
        total_calls = total_calls + (entry.calls or 0)
        total_matches = total_matches + (entry.matches or 0)
        total_time = total_time + (entry.time or 0)
    end

    table.sort(rows, function(a, b)
        local at = a.time or 0
        local bt = b.time or 0
        if at == bt then
            return (a.key or "") < (b.key or "")
        end
        return at > bt
    end)

    lines[#lines + 1] = ("total: calls=%d matches=%d time=%.3fms"):format(
        total_calls,
        total_matches,
        total_time * 1000
    )
    lines[#lines + 1] = "TOTAL(ms)  COUNT  MATCH  SLOWEST(ms)  AVERAGE(ms)  NAME  PATTERN"

    for i = 1, #rows do
        local row = rows[i]
        local calls = row.calls or 0
        local avg = calls > 0 and (row.time or 0) / calls or 0
        lines[#lines + 1] = ("%.3f  %5d  %5d  %11.3f  %11.3f  %s  %s"):format(
            (row.time or 0) * 1000,
            row.calls or 0,
            row.matches or 0,
            (row.slowest or 0) * 1000,
            avg * 1000,
            row.name or "",
            row.pattern or row.key or ""
        )
    end

    return lines
end

return Profile
