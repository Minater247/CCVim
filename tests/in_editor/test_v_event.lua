-- Basic tests for v:event lifecycle.
-- Ensures v.event populated during autocmd and restored/cleared after.

local function ok(label, cond, extra)
  LOG_DEBUG((cond and 'OK ' or 'FAIL ') .. label .. (extra and (' -> '..extra) or ''))
end

-- Create group to isolate
local gid = vim.api.nvim_create_augroup('TestVEvent', { clear = true })
local captured = {}

vim.api.nvim_create_autocmd('DirChanged', {
  group = gid,
  pattern = '*',
  callback = function(info)
    -- deep copy of v.event
    local ev = {}
    for k,v in pairs(vim.v.event) do ev[k] = v end
    captured[#captured+1] = ev
  end,
})

-- Fire with synthetic data (engine-internal trigger not yet wired for directory changes here)
vim.api.nvim_exec_autocmds('DirChanged', { data = { scope = 'window', cwd = '/old', new_cwd = '/new', changed_window = true } })

ok('autocmd fired once', #captured == 1, tostring(#captured))
ok('v.event.scope', captured[1] and captured[1].scope == 'window', captured[1] and captured[1].scope)
ok('v.event.cwd choose new_cwd', captured[1] and captured[1].cwd == '/new', captured[1] and captured[1].cwd)

-- After event should be cleared/restored (empty table expected)
local post_empty = true
for k,_ in pairs(vim.v.event) do post_empty = false break end
ok('v.event cleared after run', post_empty)
