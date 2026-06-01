local ok_compare, Compare = pcall(require, "vim.tests.compare_highlighting")
if not ok_compare then
    Compare = require("tests.compare_highlighting")
end

local Benchmark = {}

local function shell_quote(s)
    local v = tostring(s or "")
    return "'" .. v:gsub("'", "'\\''") .. "'"
end

local function starts_with(s, prefix)
    return tostring(s or ""):sub(1, #prefix) == prefix
end

local function normalize_path(path)
    return Compare.normalize_path(path)
end

local function now()
    local pipe = io.popen("perl -MTime::HiRes=time -e 'printf \"%.6f\", time' 2>/dev/null", "r")
    if pipe then
        local value = tonumber(pipe:read("*a"))
        pipe:close()
        if value then
            return value
        end
    end
    return os.time()
end

local function discover_runtime_files(root)
    local files = {}
    local cmd = "find " .. shell_quote(root) .. " -type f | sort"
    local pipe = io.popen(cmd, "r")
    if not pipe then
        return files
    end
    for line in pipe:lines() do
        files[#files + 1] = normalize_path(line)
    end
    pipe:close()
    return files
end

local function relative_path(root, path)
    root = normalize_path(root)
    path = normalize_path(path)
    if starts_with(path, root .. "/") then
        return path:sub(#root + 2)
    end
    return path
end

local function is_skip_error(message)
    message = tostring(message or "")
    if message:find("Unable to determine filetype", 1, true) then
        return true, "no filetype"
    end
    local missing = message:match("missing syntax file: ([^\n]+)")
    if missing then
        return true, "missing syntax"
    end
    return false, nil
end

function Benchmark.run(opts)
    opts = opts or {}
    local root = normalize_path(opts.runtime_root or "runtime")
    local max_files = tonumber(opts.max_files or os.getenv("CCVIM_RUNTIME_HIGHLIGHT_LIMIT") or "")
    local start_index = tonumber(opts.start_index or os.getenv("CCVIM_RUNTIME_HIGHLIGHT_START") or 1) or 1
    local max_failures = tonumber(opts.max_failures or 20) or 20
    local batch_size = tonumber(opts.batch_size or os.getenv("CCVIM_RUNTIME_HIGHLIGHT_BATCH") or 64) or 64
    local progress = opts.progress or os.getenv("CCVIM_RUNTIME_HIGHLIGHT_PROGRESS") == "1"
    if batch_size < 1 then
        batch_size = 1
    end
    local files = discover_runtime_files(root)
    if start_index < 1 then
        start_index = 1
    end
    local limit = max_files and math.min(start_index + max_files - 1, #files) or #files

    local started = now()
    local result = {
        runtime_root = root,
        discovered = #files,
        start_index = start_index,
        visited = math.max(0, limit - start_index + 1),
        compared = 0,
        skipped = 0,
        failed = 0,
        mismatch_lines = 0,
        mismatch_cols = 0,
        total_cols = 0,
        failures = {},
        skips = {},
        elapsed_sec = 0,
    }

    local i = start_index
    while i <= limit do
        local chunk = {}
        local last = math.min(limit, i + batch_size - 1)
        for idx = i, last do
            chunk[#chunk + 1] = files[idx]
        end
        if progress then
            io.stderr:write(string.format(
                "runtime highlight parity: batch %d-%d/%d %s\n",
                i,
                last,
                #files,
                relative_path(root, files[i])
            ))
            io.stderr:flush()
        end

        local ok_batch, nvim_batch_or_err = pcall(Compare.collect_nvim_segments_many, chunk)
        if not ok_batch then
            for idx = 1, #chunk do
                result.failed = result.failed + 1
                if #result.failures < max_failures then
                    result.failures[#result.failures + 1] = {
                        file = relative_path(root, chunk[idx]),
                        error = tostring(nvim_batch_or_err),
                    }
                end
            end
            i = last + 1
            goto continue_batch
        end

        for idx = 1, #chunk do
            local path = chunk[idx]
            local ok, stats_or_err = pcall(Compare.compare_file, {
                file = path,
                nvim_data = nvim_batch_or_err[path],
                quiet = true,
                max_report = 8,
            })

            if not ok then
                local skip, reason = is_skip_error(stats_or_err)
                if skip then
                    result.skipped = result.skipped + 1
                    result.skips[reason] = (result.skips[reason] or 0) + 1
                else
                    result.failed = result.failed + 1
                    if #result.failures < max_failures then
                        result.failures[#result.failures + 1] = {
                            file = relative_path(root, path),
                            error = tostring(stats_or_err),
                        }
                    end
                end
            else
                local stats = stats_or_err
                result.compared = result.compared + 1
                result.mismatch_lines = result.mismatch_lines + stats.mismatch_lines
                result.mismatch_cols = result.mismatch_cols + stats.mismatch_cols
                result.total_cols = result.total_cols + stats.total_cols
                if stats.mismatch_lines > 0 then
                    result.failed = result.failed + 1
                    if #result.failures < max_failures then
                        result.failures[#result.failures + 1] = {
                            file = relative_path(root, path),
                            filetype = stats.filetype,
                            mismatch_lines = stats.mismatch_lines,
                            mismatch_cols = stats.mismatch_cols,
                            first_line = stats.reports[1] and stats.reports[1].line or nil,
                        }
                    end
                end
            end
        end
        i = last + 1
        ::continue_batch::
    end

    result.elapsed_sec = now() - started
    return result
end

function Benchmark.summary(result)
    local skips = {}
    for reason, count in pairs(result.skips or {}) do
        skips[#skips + 1] = reason .. "=" .. tostring(count)
    end
    table.sort(skips)
    if #skips == 0 then
        skips[1] = "none"
    end
    return string.format(
        "runtime highlight parity: discovered=%d visited=%d compared=%d skipped=%d failed=%d "
            .. "mismatch_lines=%d mismatch_cols=%d/%d elapsed=%.3fs skips={%s}",
        result.discovered,
        result.visited,
        result.compared,
        result.skipped,
        result.failed,
        result.mismatch_lines,
        result.mismatch_cols,
        result.total_cols,
        result.elapsed_sec,
        table.concat(skips, ", ")
    )
end

return Benchmark
