return {
    id = "api.vim_notify_once",
    description = "Ports vim.notify_once() deduplication behavior through the public Lua API.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.notify_once scenarios", [[
            local messages = {}
            local orig_notify = vim.notify
            vim.notify = function(msg, level, opts)
                messages[#messages + 1] = {
                    msg = tostring(msg),
                    level_state = (level == nil) and "nil" or tostring(level),
                    opts_state = (opts == nil) and "nil" or type(opts),
                    title_state = ((opts and opts.title) == nil) and "nil"
                        or ((opts.title == "") and "empty" or tostring(opts.title)),
                }
                return true
            end

            local chunk_1 = assert(load(
                "return vim.notify_once('gamma')",
                "=(notify_once_chunk_1)",
                "t",
                { vim = vim }
            ))
            local chunk_2 = assert(load(
                "return vim.notify_once('gamma')",
                "=(notify_once_chunk_2)",
                "t",
                { vim = vim }
            ))

            local out = {
                type(vim.notify_once),
                vim.notify_once("alpha", 2, { title = "one" }),
                vim.notify_once("alpha", 3, { title = "two" }),
                vim.notify_once("beta", 3, { title = "three" }),
                chunk_1(),
                chunk_2(),
                messages,
            }

            vim.notify = orig_notify
            return out
        ]])

        Assert.eq("vim.notify_once is exported", result[1], "function")
        Assert.eq("first notify_once call displays", result[2], true)
        Assert.eq("second identical notify_once call is suppressed", result[3], false)
        Assert.eq("different message displays", result[4], true)
        Assert.eq("first separate chunk call displays", result[5], true)
        Assert.eq("second separate chunk call is suppressed", result[6], false)
        Assert.eq("notify_once emits once per unique message", #result[7], 3)
        Assert.eq("first emitted notification message", result[7][1].msg, "alpha")
        Assert.eq("first emitted notification level", result[7][1].level_state, "2")
        Assert.eq("first emitted notification opts shape", result[7][1].opts_state, "table")
        Assert.eq("first emitted notification title", result[7][1].title_state, "one")
        Assert.eq("second emitted notification message", result[7][2].msg, "beta")
        Assert.eq("second emitted notification level", result[7][2].level_state, "3")
        Assert.eq("second emitted notification opts shape", result[7][2].opts_state, "table")
        Assert.eq("second emitted notification title", result[7][2].title_state, "three")
        Assert.eq("third emitted notification message", result[7][3].msg, "gamma")
        Assert.eq("third emitted notification level is nil", result[7][3].level_state, "nil")
        Assert.eq("third emitted notification opts is nil", result[7][3].opts_state, "nil")
        Assert.eq("third emitted notification title is nil", result[7][3].title_state, "nil")
    end,
}
