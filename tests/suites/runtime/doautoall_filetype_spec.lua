return {
    id = "runtime.doautoall_filetype",
    description = "Ports doautoall FileType behavior using real buffers and filetype matches.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "doautoall FileType scenarios", [[
            vim.cmd("enew!")
            vim.cmd("file /tmp/one.lua")
            vim.bo.filetype = "lua"
            local buf1 = vim.api.nvim_get_current_buf()

            vim.cmd("enew!")
            vim.cmd("file /tmp/two.py")
            vim.bo.filetype = "python"
            local buf2 = vim.api.nvim_get_current_buf()

            vim.g.doautoall_seen = {}
            vim.cmd([=[
augroup DoautoallFileTypeSpec
  autocmd!
  autocmd FileType * call add(g:doautoall_seen, printf('%d:%s', expand('<abuf>'), expand('<amatch>')))
augroup END
]=])

            vim.cmd("doautoall FileType")

            return {
                buf1,
                buf2,
                vim.g.doautoall_seen,
            }
        ]])

        Assert.table_eq("doautoall FileType emits buf1 filetype", result[3], {
            tostring(result[1]) .. ":lua",
            tostring(result[2]) .. ":python",
        })
    end,
}
