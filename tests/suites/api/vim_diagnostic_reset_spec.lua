return {
    id = "api.vim_diagnostic_reset",
    description = "Ports diagnostic.reset() namespace and buffer scoping coverage.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "diagnostic reset scenarios", [[
            local b1 = vim.api.nvim_create_buf(true, false)
            local b2 = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "one" })
            vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "two" })
            vim.api.nvim_set_current_buf(b1)

            local ns = vim.api.nvim_create_namespace("diag-reset-test")
            local ns_other = vim.api.nvim_create_namespace("diag-reset-other")

            local function put_diag(namespace, bufnr, msg)
                vim.diagnostic.set(namespace, bufnr, {
                    {
                        lnum = 0,
                        col = 0,
                        end_lnum = 0,
                        end_col = 1,
                        severity = vim.diagnostic.severity.ERROR,
                        message = msg,
                        source = "test",
                    },
                }, {
                    underline = false,
                    virtual_text = false,
                    signs = false,
                })
            end

            local function diag_count(bufnr, namespace)
                return #vim.diagnostic.get(bufnr, { namespace = namespace })
            end

            put_diag(ns, b1, "a")
            put_diag(ns, b2, "b")
            put_diag(ns_other, b1, "c")

            vim.diagnostic.reset(ns, b1)
            local after_target = {
                diag_count(b1, ns),
                diag_count(b2, ns),
                diag_count(b1, ns_other),
            }

            put_diag(ns, b1, "a2")
            vim.diagnostic.reset(ns, 0)
            local after_current = {
                diag_count(b1, ns),
                diag_count(b2, ns),
            }

            vim.diagnostic.reset(ns)
            local after_all = {
                diag_count(b2, ns),
                diag_count(b1, ns_other),
            }

            return {
                after_target,
                after_current,
                after_all,
            }
        ]])

        Assert.table_eq("reset(ns, bufnr) clears target/leaves others", result[1], { 0, 1, 1 })
        Assert.table_eq("reset(ns, 0) uses current buffer", result[2], { 0, 1 })
        Assert.table_eq("reset(ns) clears all buffers/leaves other namespaces", result[3], { 0, 1 })
    end,
}
