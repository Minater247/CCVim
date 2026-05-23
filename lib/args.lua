local Args = {}

local Buffer = loadModule("layout.buffer")
local Window = loadModule("layout.window")
local Tabpage = loadModule("layout.tabpage")
local FrameTree = loadModule("lib.frame")
local pending_file_bufnrs
local pending_window_bufnrs

local function print_help(argv0)
  print("Usage:")
  print("  " .. argv0 .. " [options] [file ...]")
    print([[Options:
  --                    Only file names after this

  -h, --help            Print this help message
  -o[N]                 Open N windows (default: one per file)
  -O[N]                 Open N vertical windows (default: one per file)
  -p[N]                 Open N tab pages (default: one per file)
  -R                    Read-only (view) mode
  -v, --version         Print version information
  -V[N][file]           Verbose [level][file]

  --no-cache            Recompile sourced .vim sidecar caches
  --startuptime <file>  Write startup timing messages to <file>]])
end

local function print_version(argv0)
    print("CCVim v" .. ccvimversion_str)
    print("LuaJIT " .. (jit and jit.version or "Unavailable"))
    print("Run \"" .. argv0 .. " -V1 -v\" for more info.")
end

function Args.parse(argv)
    local state = {
        files = {},
        file_bufnrs = {},
        window_bufnrs = {},
        nomodifiable = false,
        readonly = false,

        win_split_type = 0, -- 0=none, 1=horizontal, 2=vertical
        mktabs = 1,
        mkwins = 1,
    }

    local argsdone = false
    local should_continue = true
    local i = 1
    while i <= #argv do
        local v = argv[i]
        if (not argsdone) and v:sub(1, 1) == "-" then
            local c = v:sub(2, 2)
            if c == "-" then
                -- '--' arg
                c = v:sub(3)
                if c == "help" then
                    print_help(argv[0])
                    should_continue = false
                elseif c == "" then
                    argsdone = true
                elseif c == "version" then
                    print_version(argv[0])
                    should_continue = false
                elseif c == "no-cache" then
                    no_cache = true
                elseif c == "startuptime" then
                    startuptime = argv[i + 1]
                    i = i + 1
                else
                    print(argv[0] .. ": Unknown option argument: \"" .. v .. "\"")
                    print("More info with \"" .. argv[0] .. " -h\"")
                    return false
                end
            else
                -- single-line arguments
                local j = 2
                while j <= #v do
                    c = v:sub(j, j)
                    if c == "h" then
                        print_help(argv[0])
                        should_continue = false
                    elseif c == "m" then
                        options.set("write", false)
                    elseif c == "M" then
                        options.set("write", false)
                        state.nomodifiable = true
                    elseif c == "R" then
                        options.set("updatecount", 10000)
                        state.readonly = true
                    elseif c == "O" then
                        c = v:sub(j+1, j+1)
                        local cnt = 0
                        while tonumber(c) do
                            j = j + 1
                            cnt = cnt * 10 + tonumber(c)
                            c = v:sub(j+1, j+1)
                        end
                        state.win_split_type = 2
                        state.mkwins = cnt
                    elseif c == "o" then
                        c = v:sub(j+1, j+1)
                        local cnt = 0
                        while tonumber(c) do
                            j = j + 1
                            cnt = cnt * 10 + tonumber(c)
                            c = v:sub(j+1, j+1)
                        end
                        state.win_split_type = 1
                        state.mkwins = cnt
                    elseif c == "p" then
                        c = v:sub(j+1, j+1)
                        local cnt = 0
                        while tonumber(c) do
                            j = j + 1
                            cnt = cnt * 10 + tonumber(c)
                            c = v:sub(j+1, j+1)
                        end
                        state.mktabs = cnt > 0 and cnt or 1
                    elseif c == "?" then
                        print_help(argv[0])
                        should_continue = false
                    elseif c == "v" then
                        print_version(argv[0])
                        should_continue = false
                    else
                        print(argv[0] .. ": Unknown option argument: \"" .. v .. "\"")
                        print("More info with \"" .. argv[0] .. " -h\"")
                        return false
                    end
                    j = j + 1
                end
            end
        else
            state.files[#state.files + 1] = v
        end
        i = i + 1
    end

    if not should_continue then
        return false
    end

    -- Step 1: Make the buffers
    for idx = 1, #state.files do
        local buf = Buffer(true, false, false)
        buf.name = state.files[idx]
        buf.opts.readonly = state.readonly
        buf.opts.modifiable = not state.nomodifiable
        state.file_bufnrs[#state.file_bufnrs + 1] = buf.bufnr
    end

    if state.mkwins == 0 then
        state.mkwins = #state.files
    end

    local startup_window_buffer
    if #state.files > 0 then
        startup_window_buffer = Buffer(true, false)
    end

    for idx = 1, state.mkwins do
        if startup_window_buffer then
            Window(startup_window_buffer)
        else
            Window(buffers[idx])
        end
    end

    local firsttp = Tabpage(windows[1])
    for idx = 2, #windows do
        firsttp:WinSplit(windows[idx-1].winnr, windows[idx], state.win_split_type == 2)
    end
    assert(FrameTree.Equalize(firsttp.tree))
    
    if state.mktabs == 0 then
        state.mktabs = #state.files
    end
    for _ = 2, state.mktabs do
        Tabpage()
    end

    local visible_count = math.min(#state.file_bufnrs, state.mkwins)
    for idx = 1, visible_count do
        state.window_bufnrs[idx] = state.file_bufnrs[idx]
    end

    pending_file_bufnrs = state.file_bufnrs
    pending_window_bufnrs = state.window_bufnrs

    return true
end

function Args.load_pending_files()
    if not pending_file_bufnrs then
        return true
    end

    if pending_window_bufnrs then
        for i = 1, #pending_window_bufnrs do
            local win = windows[i]
            local newbuf = buffers[pending_window_bufnrs[i]]
            if win and newbuf and win.buffer ~= newbuf then
                if win.buffer then
                    win.buffer.refcount = math.max(0, (win.buffer.refcount or 0) - 1)
                end
                win.buffer = newbuf
                newbuf.refcount = (newbuf.refcount or 0) + 1
            end
        end
    end

    for i = 1, #pending_file_bufnrs do
        local buf = buffers[pending_file_bufnrs[i]]
        if not buf.loaded then
            buf:Load(true)
        end
    end

    pending_window_bufnrs = nil
    pending_file_bufnrs = nil

    return true
end

return Args
