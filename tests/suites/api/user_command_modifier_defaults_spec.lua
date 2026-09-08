return {
    id = "api.user_command_modifier_defaults",
    description = "Lua command callbacks expose the documented structured modifier defaults used by Oil.",
    run = function(ctx)
        local A = ctx.assert
        local result = A.eval_block(ctx.backend, "command modifiers", [=[
            local result
            vim.api.nvim_create_user_command('ModifierProbe', function(args)
                assert(args.smods.tab <= 0)
                result = args.smods
            end, {})
            vim.cmd('ModifierProbe')
            return result
        ]=])
        local expected = {
            silent = false, emsg_silent = false, unsilent = false,
            sandbox = false, noautocmd = false, browse = false,
            confirm = false, hide = false, horizontal = false,
            keepalt = false, keepjumps = false, keepmarks = false,
            keeppatterns = false, lockmarks = false, noswapfile = false,
            tab = -1, verbose = -1, vertical = false, split = "",
        }
        if ctx.backend.name ~= "headless_nvim" then
            expected.filter = {pattern = "", force = false}
        end
        A.deep_eq("structured defaults", result, expected)
    end,
}
