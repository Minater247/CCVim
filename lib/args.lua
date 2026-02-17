local Args = {}

local Buffer = loadModule("vim.layout.buffer")
local Window = loadModule("vim.layout.window")
local Tabpage = loadModule("vim.layout.tabpage")
local FrameTree = loadModule("vim.lib.frame")

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

  --startuptime <file>  Write startup timing messages to <file>]])
end

local function print_version(argv0)
    print("CCVim v" .. vimversion_str)
    print("LuaJIT " .. (jit and jit.version or "Unavailable"))
    print("Run \"" .. argv0 .. " -V1 -v\" for more info.")
end

function Args.parse(argv)
    local state = {
        files = {},
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
    for i = 1, #state.files do
        local buf = Buffer(true, false)
        buf.name = state.files[i]
        buf:Load(true)
        buf.opts.readonly = state.readonly
        buf.opts.modifiable = not state.nomodifiable
    end

    if state.mkwins == 0 then
        state.mkwins = #state.files
    end
    for i = 1, state.mkwins do
        Window(buffers[i])
    end

    local firsttp = Tabpage(windows[1])
    for i = 2, #windows do
        firsttp:WinSplit(windows[i-1].winnr, windows[i], state.win_split_type == 2)
    end
    assert(FrameTree.Equalize(firsttp.tree))
    
    if state.mktabs == 0 then
        state.mktabs = #state.files
    end
    for i = 2, state.mktabs do
        Tabpage()
    end

    return true
end

return Args
