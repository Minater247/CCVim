return {
    id = 'runtime.message_idle_redraw',
    description = 'Unchanged message overlays do not repaint on unrelated event finalization.',
    supports = {headless_nvim = false},
    run = function(ctx)
        local A, b = ctx.assert, ctx.backend
        local ExMsg = b.mock.loadModule('lib.excmd.exmsg')
        local Event = b.mock.loadModule('lib.event')
        local globals = b.mock.globals()
        local original_grid_line = globals.screen.grid_line
        local writes = 0
        globals.screen.grid_line = function(...)
            writes = writes + 1
            return original_grid_line(...)
        end

        ExMsg.BeginQuestion('Question?\n[Y]es, (N)o: ')
        local question_writes = writes
        Event.ProcessEvent({'timer', -1})
        A.eq('idle question timer writes no rows', writes, question_writes)
        ExMsg.echomsg('changed')
        Event.ProcessEvent({'timer', -1})
        A.truthy('changed question content redraws', writes > question_writes)
        local changed_question_writes = writes
        Event.ProcessEvent({'timer', -1})
        A.eq('settled question timer writes no rows', writes, changed_question_writes)
        ExMsg.EndQuestion()

        ExMsg.echomsg('one')
        ExMsg.echomsg('two')
        ExMsg.Finalize()
        local press_enter_writes = writes
        Event.ProcessEvent({'timer', -1})
        A.eq('idle hit-enter timer writes no rows', writes, press_enter_writes)
        ExMsg.exitRead()

        for i = 1, globals.screen.height do ExMsg.echomsg(tostring(i)) end
        ExMsg.Finalize()
        local more_writes = writes
        Event.ProcessEvent({'timer', -1})
        A.eq('idle pager timer writes no rows', writes, more_writes)
        ExMsg.exitRead()

        globals.screen.grid_line = original_grid_line
    end,
}
