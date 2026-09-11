return {
    id = "api.extmark_splice_parity",
    description = "Checks line edit gravity, invalidation, and undo restoration for extmarks against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "extmark splice behavior", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "0", "1", "2", "3", "4", "5", "6" })
            vim.bo.undolevels = -1
            vim.bo.undolevels = 1000

            local ns = vim.api.nvim_create_namespace("extmark.splice.parity")
            for row = 0, 6 do
                vim.api.nvim_buf_set_extmark(0, ns, row, 0, { id = row + 1, invalidate = true })
            end

            vim.api.nvim_buf_set_lines(0, 1, 2, false, {})
            vim.api.nvim_buf_set_lines(0, 2, 4, false, {})

            local after_delete = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })

            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
            vim.bo.undolevels = -1
            vim.bo.undolevels = 1000
            local restored = vim.api.nvim_buf_set_extmark(0, ns, 1, 0, { invalidate = true })
            vim.api.nvim_buf_set_lines(0, 1, 2, false, {})
            local before_undo = vim.api.nvim_buf_get_extmark_by_id(0, ns, restored, { details = true })
            vim.cmd("undo")
            local after_undo = vim.api.nvim_buf_get_extmark_by_id(0, ns, restored, { details = true })
            vim.cmd("redo")
            local after_redo = vim.api.nvim_buf_get_extmark_by_id(0, ns, restored, { details = true })

            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
            local left = vim.api.nvim_buf_set_extmark(0, ns, 1, 0, { right_gravity = false })
            local right = vim.api.nvim_buf_set_extmark(0, ns, 1, 0, { right_gravity = true })
            vim.api.nvim_buf_set_lines(0, 1, 1, false, { "inserted" })
            local left_position = vim.api.nvim_buf_get_extmark_by_id(0, ns, left, {})
            local right_position = vim.api.nvim_buf_get_extmark_by_id(0, ns, right, {})

            local doomed = vim.api.nvim_buf_set_extmark(0, ns, 0, 0, {
                invalidate = true,
                undo_restore = false,
            })
            vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
            local doomed_position = vim.api.nvim_buf_get_extmark_by_id(0, ns, doomed, {})

            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
            local text_marks = {}
            for col = 0, 6 do
                text_marks[#text_marks + 1] = vim.api.nvim_buf_set_extmark(0, ns, 0, col, {
                    right_gravity = col % 2 == 0,
                    invalidate = true,
                })
            end
            vim.api.nvim_buf_set_text(0, 0, 2, 0, 4, { "XYZ" })
            local text_columns = {}
            for _, id in ipairs(text_marks) do
                text_columns[#text_columns + 1] = vim.api.nvim_buf_get_extmark_by_id(0, ns, id, {})[2]
            end

            local function positions(marks)
                local out = {}
                for _, mark in ipairs(marks) do
                    out[#out + 1] = { mark[1], mark[2], mark[4].invalid == true }
                end
                return out
            end

            return {
                positions(after_delete),
                { before_undo[1], before_undo[3].invalid == true },
                { after_undo[1], after_undo[3].invalid == true },
                { after_redo[1], after_redo[3].invalid == true },
                left_position,
                right_position,
                doomed_position,
                text_columns,
            }
        ]])

        ctx.assert.deep_eq("deleted line extmarks", result[1], {
            { 1, 0, false },
            { 2, 1, true },
            { 3, 1, false },
            { 4, 2, true },
            { 5, 2, true },
            { 6, 2, false },
            { 7, 3, false },
        })
        ctx.assert.deep_eq("deleted extmark is invalid", result[2], { 1, true })
        ctx.assert.deep_eq("undo restores extmark", result[3], { 1, false })
        ctx.assert.deep_eq("redo invalidates extmark", result[4], { 1, true })
        ctx.assert.deep_eq("left gravity insertion", result[5], { 1, 0 })
        ctx.assert.deep_eq("right gravity insertion", result[6], { 2, 0 })
        ctx.assert.deep_eq("non-restoring invalid extmark is deleted", result[7], {})
        ctx.assert.deep_eq("text edit gravity", result[8], { 0, 1, 5, 2, 5, 6, 7 })
    end,
}
