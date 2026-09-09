return {
    id = "api.nvim_float_close",
    description = "Checks floating-window close focus, WinClosed context, and tiled frame geometry against Neovim.",
    supports = { lua_editor = true, headless_nvim = true },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "floating window close semantics", [=[
            vim.o.equalalways = true
            vim.cmd("vsplit")
            vim.cmd("split")
            vim.cmd("vertical resize 20")
            vim.cmd("resize 5")

            local prior = vim.api.nvim_get_current_win()
            local tiled = vim.deepcopy(vim.fn.winlayout())
            local function dimensions(layout)
                local result = {}
                local function collect(node)
                    if node[1] == "leaf" then
                        result[node[2]] = {
                            vim.api.nvim_win_get_width(node[2]),
                            vim.api.nvim_win_get_height(node[2]),
                        }
                    else
                        for _, child in ipairs(node[2]) do collect(child) end
                    end
                end
                collect(layout)
                return result
            end
            local tiled_dimensions = dimensions(tiled)

            local closed = {}
            vim.api.nvim_create_autocmd("WinClosed", {
                callback = function(args)
                    closed[#closed + 1] = { args.match, args.file, args.buf }
                end,
            })

            local backdrop_buf = vim.api.nvim_create_buf(false, true)
            vim.bo[backdrop_buf].bufhidden = "wipe"
            local backdrop = vim.api.nvim_open_win(backdrop_buf, false, {
                relative = "editor",
                row = 0,
                col = 0,
                width = 30,
                height = 10,
                focusable = false,
            })
            local content_buf = vim.api.nvim_create_buf(false, true)
            vim.bo[content_buf].bufhidden = "wipe"
            local content = vim.api.nvim_open_win(content_buf, true, {
                relative = "editor",
                row = 1,
                col = 2,
                width = 20,
                height = 6,
            })

            local layout_after_open = vim.deepcopy(vim.fn.winlayout())
            local dimensions_after_open = dimensions(layout_after_open)

            vim.api.nvim_win_close(backdrop, true)
            local current_after_backdrop = vim.api.nvim_get_current_win()
            local layout_after_backdrop = vim.deepcopy(vim.fn.winlayout())
            vim.api.nvim_win_close(content, true)
            local current_after_content = vim.api.nvim_get_current_win()
            local layout_after_content = vim.deepcopy(vim.fn.winlayout())

            local geometry_valid = true
            if type(loadModule) == "function" then
                local tp = tabpages[curtp]
                local expected_height = screen.height - options.get("cmdheight")
                local showtabline = options.get("showtabline")
                if showtabline == 2 or (showtabline == 1 and tp:count_all() > 1) then
                    expected_height = expected_height - 1
                end
                if options.get("laststatus") == 3 then expected_height = expected_height - 1 end
                geometry_valid = tp.tree.width == screen.width and tp.tree.height == expected_height
                local function validate(node)
                    if not node.split_type then
                        geometry_valid = geometry_valid and node.window.frame == node
                        return
                    end
                    local a, b = node.children[1], node.children[2]
                    geometry_valid = geometry_valid and a.parent == node and b.parent == node
                    if node.split_type == "v" then
                        geometry_valid = geometry_valid
                            and a.height == node.height
                            and b.height == node.height
                            and a.width + b.width == node.width
                    else
                        geometry_valid = geometry_valid
                            and a.width == node.width
                            and b.width == node.width
                            and a.height + b.height == node.height
                    end
                    validate(a)
                    validate(b)
                end
                validate(tp.tree)
            end

            return {
                vim.deep_equal(tiled, layout_after_open),
                vim.deep_equal(tiled_dimensions, dimensions_after_open),
                current_after_backdrop == content,
                vim.deep_equal(tiled, layout_after_backdrop),
                current_after_content == prior,
                vim.deep_equal(tiled, layout_after_content),
                geometry_valid,
                closed,
                backdrop,
                backdrop_buf,
                content,
                content_buf,
            }
        ]=])

        Assert.eq("opening floats preserves tiled layout", result[1], true)
        Assert.eq("entering a float preserves tiled dimensions", result[2], true)
        Assert.eq("closing non-current backdrop preserves current float", result[3], true)
        Assert.eq("closing backdrop preserves tiled layout", result[4], true)
        Assert.eq("closing current float restores previous tiled window", result[5], true)
        Assert.eq("closing content preserves tiled layout", result[6], true)
        Assert.eq("tiled frame tree remains a valid screen partition", result[7], true)
        Assert.eq("two WinClosed events fire", #result[8], 2)
        Assert.table_eq("backdrop WinClosed context", result[8][1], {
            tostring(result[9]), tostring(result[9]), result[10],
        })
        Assert.table_eq("content WinClosed context", result[8][2], {
            tostring(result[11]), tostring(result[11]), result[12],
        })
    end,
}
