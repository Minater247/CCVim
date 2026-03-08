return {
    id = "runtime.oil_directory_hijack",
    description = "Ports directory-hijack autocmd behavior through public APIs and real backend filesystem state.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "oil-directory-hijack", "")
        local dir_path = root .. "/dir"
        local start_path = root .. "/start"

        Assert.ensure_dir(backend, root)
        Assert.ensure_dir(backend, dir_path)
        Assert.write_file(backend, start_path, "start\n")

        local result = Assert.eval_block(backend, "oil directory hijack runtime", string.format([==[
            local root = %q
            local dir_path = %q
            local start_path = %q
            local seen = {
                bufadd = 0,
                readcmd = 0,
                buflocal = 0,
                acwrite = 0,
            }

            local function normalize(path)
                path = tostring(path or "")
                if path == "" then
                    return path
                end
                local ok_abs, abs = pcall(vim.fn.fnamemodify, path, ":p")
                if ok_abs and type(abs) == "string" and abs ~= "" then
                    path = abs
                end
                local ok_resolve, resolved = pcall(vim.fn.resolve, path)
                if ok_resolve and type(resolved) == "string" and resolved ~= "" then
                    path = resolved
                end
                return path:gsub("/+$", "")
            end

            vim.cmd("edit " .. vim.fn.fnameescape(start_path))
            local start_buf = vim.api.nvim_get_current_buf()

            vim.api.nvim_create_autocmd("BufAdd", {
                pattern = "*",
                callback = function(params)
                    seen.bufadd = seen.bufadd + 1
                    if normalize(params.file) == normalize(dir_path) then
                        vim.api.nvim_buf_set_name(params.buf, "oil:///")
                    end
                end,
            })

            vim.api.nvim_create_autocmd("BufReadCmd", {
                pattern = "oil://*,oil-ssh://*",
                callback = function()
                    seen.readcmd = seen.readcmd + 1
                end,
            })

            local readcmd_au = vim.api.nvim_get_autocmds({ event = "BufReadCmd" })
            local saw_oil_pattern = false
            for _, au in ipairs(readcmd_au) do
                if au.pattern == "oil://*" or au.pattern == "oil-ssh://*" then
                    saw_oil_pattern = true
                end
            end

            local tmp_au_id = vim.api.nvim_create_autocmd("User", {
                pattern = "TmpOilProbe",
                callback = function() end,
            })
            vim.api.nvim_del_autocmd(tmp_au_id)

            vim.api.nvim_create_autocmd("BufEnter", {
                buffer = start_buf,
                callback = function()
                    seen.buflocal = seen.buflocal + 1
                end,
            })

            vim.api.nvim_exec_autocmds("BufEnter", { buffer = start_buf, modeline = false })
            local other_buf = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_name(other_buf, dir_path .. "/other.txt")
            vim.api.nvim_exec_autocmds("BufEnter", { buffer = other_buf, modeline = false })

            local edit_ok, edit_err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(dir_path))
            local current_name_after_edit = vim.api.nvim_buf_get_name(0)
            local readcmd_hits_after_edit = seen.readcmd
            local uv_stat = vim.uv.fs_stat("oil:///")

            vim.api.nvim_win_set_var(0, "oil_probe", 7)
            local win_probe = vim.api.nvim_win_get_var(0, "oil_probe")
            vim.api.nvim_win_del_var(0, "oil_probe")
            local ok_win_missing, win_missing = pcall(vim.api.nvim_win_get_var, 0, "oil_probe")

            vim.api.nvim_buf_set_var(0, "oil_buf_probe", 9)
            local buf_probe = vim.api.nvim_buf_get_var(0, "oil_buf_probe")
            vim.api.nvim_buf_del_var(0, "oil_buf_probe")
            local ok_buf_missing, buf_missing = pcall(vim.api.nvim_buf_get_var, 0, "oil_buf_probe")

            local doomed = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_name(doomed, root .. "/doomed")
            vim.api.nvim_buf_set_lines(doomed, 0, -1, false, { "x" })
            vim.api.nvim_set_current_buf(doomed)
            vim.api.nvim_buf_delete(doomed, { force = true })

            local unloadbuf = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_name(unloadbuf, root .. "/unload")
            vim.api.nvim_buf_set_lines(unloadbuf, 0, -1, false, { "x" })
            vim.api.nvim_buf_delete(unloadbuf, { force = true, unload = true })

            vim.api.nvim_create_autocmd("BufWriteCmd", {
                pattern = "acwrite://*",
                callback = function()
                    seen.acwrite = seen.acwrite + 1
                end,
            })

            local acwrite_buf = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(acwrite_buf)
            vim.api.nvim_buf_set_name(acwrite_buf, "acwrite:///probe")
            vim.bo[acwrite_buf].buftype = "acwrite"
            vim.api.nvim_buf_set_lines(acwrite_buf, 0, -1, false, { "x" })
            local acwrite_ok, acwrite_err = pcall(vim.cmd, "write")

            local acwrite_missing = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(acwrite_missing)
            vim.api.nvim_buf_set_name(acwrite_missing, "acwrite-miss:///probe")
            vim.bo[acwrite_missing].buftype = "acwrite"
            vim.api.nvim_buf_set_lines(acwrite_missing, 0, -1, false, { "x" })
            local acwrite_missing_ok, acwrite_missing_err = pcall(vim.cmd, "write")

            return {
                saw_oil_pattern = saw_oil_pattern,
                tmp_autocmd_removed = #vim.api.nvim_get_autocmds({ event = "User", pattern = "TmpOilProbe" }) == 0,
                buflocal_hits = seen.buflocal,
                edit_ok = edit_ok,
                edit_err = tostring(edit_err or ""),
                bufadd_hits = seen.bufadd,
                readcmd_hits_after_edit = readcmd_hits_after_edit,
                current_name_after_edit = current_name_after_edit,
                uv_stat = uv_stat,
                win_probe = win_probe,
                ok_win_missing = ok_win_missing,
                win_missing = tostring(win_missing or ""),
                buf_probe = buf_probe,
                ok_buf_missing = ok_buf_missing,
                buf_missing = tostring(buf_missing or ""),
                doomed_valid = vim.api.nvim_buf_is_valid(doomed),
                current_after_delete = vim.api.nvim_get_current_buf(),
                unload_valid = vim.api.nvim_buf_is_valid(unloadbuf),
                unload_lines = vim.api.nvim_buf_get_lines(unloadbuf, 0, -1, false),
                unload_loaded = vim.fn.bufloaded(unloadbuf),
                endswith = vim.endswith("oil:///", "/"),
                acwrite_ok = acwrite_ok,
                acwrite_err = tostring(acwrite_err or ""),
                acwrite_hits = seen.acwrite,
                acwrite_missing_ok = acwrite_missing_ok,
                acwrite_missing_err = tostring(acwrite_missing_err or ""),
            }
        ]==], root, dir_path, start_path))

        Assert.eq("nvim_get_autocmds reports split comma patterns", result.saw_oil_pattern, true)
        Assert.eq("nvim_del_autocmd removed command", result.tmp_autocmd_removed, true)
        Assert.eq("buffer-local autocmd only runs on target buffer", result.buflocal_hits, 1)
        Assert.eq("edit directory succeeds", result.edit_ok, true)
        Assert.truthy("BufAdd fired on edit new buffer", result.bufadd_hits >= 1, result.bufadd_hits)
        Assert.eq("BufReadCmd comma pattern matches oil scheme", result.readcmd_hits_after_edit, 1)
        Assert.eq("directory buffer renamed by BufAdd callback", result.current_name_after_edit, "oil:///")
        Assert.eq("uv.fs_stat returns nil for uri-like paths", result.uv_stat, nil)
        Assert.eq("nvim_win_get_var retrieves window var", result.win_probe, 7)
        Assert.eq("nvim_win_del_var removes value", result.ok_win_missing, false)
        Assert.eq("nvim_buf_get_var retrieves buffer var", result.buf_probe, 9)
        Assert.eq("nvim_buf_del_var removes value", result.ok_buf_missing, false)
        Assert.eq("nvim_buf_delete removes buffer", result.doomed_valid, false)
        Assert.truthy(
            "nvim_buf_delete switches window away from deleted buffer",
            type(result.current_after_delete) == "number" and result.current_after_delete > 0,
            result.current_after_delete
        )
        Assert.eq("nvim_buf_delete unload keeps buffer entry", result.unload_valid, true)
        Assert.eq("nvim_buf_delete unload clears lines", #result.unload_lines, 0)
        Assert.eq("nvim_buf_delete unload marks buffer unloaded", result.unload_loaded, 0)
        Assert.eq("vim.endswith is exposed", result.endswith, true)
        Assert.eq("acwrite dispatches BufWriteCmd", result.acwrite_ok, true)
        Assert.eq("acwrite BufWriteCmd callback fired", result.acwrite_hits, 1)
        Assert.eq("acwrite missing callback returns error", result.acwrite_missing_ok, false)
        Assert.top_error_code("acwrite missing callback uses E676", result.acwrite_missing_err, "E676")
    end,
}
