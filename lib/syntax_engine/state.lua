local State = {}

local function clamp_line(line)
    if line < 1 then return 1 end
    return line
end

local function clamp_synmaxcol(value)
    if value < 0 then return 0 end
    return value
end

function State.new_context(opts)
    return {
        syntax = opts.syntax,
        synmaxcol = clamp_synmaxcol(opts.synmaxcol),
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
    local ln = clamp_line(line)
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
    ctx.synmaxcol = clamp_synmaxcol(value)
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
