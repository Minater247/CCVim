return {
    id = "runtime.native_backend_color_semantics",
    description = "Checks that the native backend keeps RGB and terminal-color attrs on separate render paths.", -- luacheck: ignore 631

    run = function(ctx)
        local Assert = ctx.assert

        local function make_popen_output(map)
            return function(cmd, _mode)
                local out = map[cmd]
                if out == nil then
                    return nil
                end
                return {
                    read = function(_, fmt)
                        if fmt == "*l" then
                            return tostring(out):match("([^\n\r]*)")
                        end
                        return tostring(out)
                    end,
                    close = function() end,
                }
            end
        end

        local function render_case(opts)
            local writes = {}
            local env = setmetatable({
                io = {
                    write = function(s) writes[#writes + 1] = tostring(s) end,
                    flush = function() end,
                    popen = make_popen_output({
                        ["stty size 2>/dev/null"] = "24 80\n",
                        ["tput colors 2>/dev/null"] = tostring(opts.tput_colors) .. "\n",
                    }),
                },
                os = {
                    getenv = function(name)
                        if name == "COLORTERM" then
                            return opts.colorterm
                        end
                        if name == "TERM" then
                            return opts.term
                        end
                        return nil
                    end,
                    execute = function() return true end,
                    time = function() return 0 end,
                },
            }, { __index = _G })

            local Native = assert(loadfile("lib/backend/native.lua", "t", env))()
            Native.grid_resize(1, 4, 1)
            Native.default_colors_set(0xF0F0F0, 0x111111, nil, nil, nil)
            Native.hl_define(1, opts.attrs)
            Native.grid_line(1, 0, 0, { { "A", 1, 1 } }, false)
            Native.end_frame()
            return table.concat(writes), Native.color_depth()
        end

        local rgb_out, rgb_depth = render_case({
            colorterm = "truecolor",
            term = "xterm-256color",
            tput_colors = 256,
            attrs = {
                foreground = 0x112233,
                background = 0x000000,
            },
        })
        Assert.eq("truecolor depth", rgb_depth, "rgb")
        Assert.truthy("truecolor fg emits 24-bit sgr", rgb_out:find("38;2;17;34;51m", 1, true) ~= nil, rgb_out)
        Assert.truthy("truecolor bg emits 24-bit sgr", rgb_out:find("48;2;0;0;0m", 1, true) ~= nil, rgb_out)

        local rgb_only_out, rgb_only_depth = render_case({
            term = "xterm-256color",
            tput_colors = 256,
            attrs = {
                foreground = 0x112233,
                background = 0x000000,
            },
        })
        Assert.eq("256-color depth", rgb_only_depth, "256")
        Assert.truthy(
            "rgb-only attrs do not emit truecolor in 256-color mode",
            rgb_only_out:find("38;2;", 1, true) == nil,
            rgb_only_out
        )
        Assert.truthy(
            "rgb-only attrs do not fabricate 256-color sgr",
            rgb_only_out:find("38;5;", 1, true) == nil,
            rgb_only_out
        )

        local cterm_out = render_case({
            term = "xterm-256color",
            tput_colors = 256,
            attrs = {
                cterm_foreground = 196,
                cterm_background = 16,
            },
        })
        Assert.truthy("cterm fg emits 256-color sgr", cterm_out:find("38;5;196m", 1, true) ~= nil, cterm_out)
        Assert.truthy("cterm bg emits 256-color sgr", cterm_out:find("48;5;16m", 1, true) ~= nil, cterm_out)

        local mono_out, mono_depth = render_case({
            term = "vt100",
            tput_colors = 0,
            attrs = {
                cterm_foreground = 196,
                cterm_background = 16,
            },
        })
        Assert.eq("vt100 depth", mono_depth, "0")
        Assert.truthy("vt100 omits 24-bit sgr", mono_out:find("38;2;", 1, true) == nil, mono_out)
        Assert.truthy("vt100 omits 256-color sgr", mono_out:find("38;5;", 1, true) == nil, mono_out)
    end,
}
