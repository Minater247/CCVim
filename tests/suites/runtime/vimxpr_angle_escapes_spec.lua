return {
    id = "runtime.vimxpr_angle_escapes",
    description = "Ports Vimscript angle-bracket escape decoding through expression evaluation.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local char_ff = Assert.eval_vim(backend, "char-hex", [["\<Char-0xff>"]])
        Assert.eq("char-hex chars", utf8.len(char_ff), 1)
        Assert.eq("char-hex byte1", string.byte(char_ff, 1), 195)
        Assert.eq("char-hex byte2", string.byte(char_ff, 2), 191)

        local char_01 = Assert.eval_vim(backend, "char-01", [["\<Char-0x01>"]])
        Assert.eq("char-01 len", #char_01, 1)
        Assert.eq("char-01 byte", string.byte(char_01), 1)

        local ctrl_v = Assert.eval_vim(backend, "ctrl-v", [["\<C-V>"]])
        Assert.eq("ctrl-v len", #ctrl_v, 1)
        Assert.eq("ctrl-v byte", string.byte(ctrl_v), 22)

        local unknown = Assert.eval_vim(backend, "unknown literal", [["\<NotAKey>"]])
        Assert.eq("unknown literal", unknown, "<NotAKey>")
    end,
}
