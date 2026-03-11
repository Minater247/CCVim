local State = {}

function State.new_context(opts)
    return {
        syntax = opts.syntax,
        synmaxcol = math.max(opts.synmaxcol, 0),
        generation = 0,
        dirty_from = 1,
        checkpoints = {},
        span_cache = {},
        syntax_commands = {},
        syntax_ir = nil,
        syntax_ir_dirty = false,
        profile = {
            enabled = false,
            counters = {},
        },
    }
end

function State.ensure_context(buffer, syntax_name, synmaxcol)
    local ctx = buffer.syntax_ctx
    if ctx then return ctx end

    ctx = State.new_context({
        syntax = syntax_name,
        synmaxcol = synmaxcol,
    })
    buffer.syntax_ctx = ctx
    return ctx
end

function State.mark_dirty(ctx, line)
    local ln = math.max(line, 1)
    if ln < ctx.dirty_from then
        ctx.dirty_from = ln
    end
    ctx.generation = ctx.generation + 1
    return true
end

function State.set_syntax(ctx, syntax_name)
    ctx.syntax = syntax_name
    ctx.checkpoints = {}
    ctx.span_cache = {}
    ctx.syntax_commands = {}
    ctx.syntax_ir = nil
    ctx.syntax_ir_dirty = false
    return State.mark_dirty(ctx, 1)
end

function State.set_synmaxcol(ctx, value)
    ctx.synmaxcol = math.max(value, 0)
    ctx.checkpoints = {}
    ctx.span_cache = {}
    return State.mark_dirty(ctx, 1)
end

function State.clear(ctx)
    ctx.checkpoints = {}
    ctx.span_cache = {}
    return State.mark_dirty(ctx, 1)
end

return State
