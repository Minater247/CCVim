-- Simple runnable tests for :call under Neovim. Run with :luafile % or dofile('...').

local vim = rawget(_G, 'vim')
if not vim then return end

local LOG_DEBUG = rawget(_G, 'LOG_DEBUG')

local function ok(label, cond, actualerr)
    LOG_DEBUG((cond and 'OK ' or 'FAIL ') .. label .. " ==> " .. actualerr)
end

local function run_cmd(cmd)
  local okc, luaerr = pcall(vim.cmd, cmd)
  local em = vim.v.errmsg
  return okc, em or '', luaerr
end

-- Reset buffer and cursor
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })

-- Define helpers in Vimscript
vim.cmd([[
  function! TestNoop(...) abort
    return a:0
  endfunction

  function! TestCaptureLines() abort
    if !exists('g:caps') | let g:caps = [] | endif
    call add(g:caps, getline('.'))
  endfunction

  function! RangeAware() abort
    let g:last_range = [a:firstline, a:lastline]
  endfunction

  let g:MyDict = {}
  function! g:MyDict.noop(...) dict abort
    let g:did_dict_noop = 1
  endfunction
]])

-- 1) Plain function and arg evaluation (getline)
do
  local ok1, em1 = run_cmd([[call TestNoop(getline('.'))]])
  ok('plain call with getline', ok1 and em1 == '', em1)
end

-- 2) Dict.func where dict is global dictionary
do
  local ok2, em2 = run_cmd([[call g:MyDict.noop(1,2,3)]])
  ok('dict.func exists (noop)', ok2 and em2 == '' and (vim.g.did_dict_noop == 1), em2)
end

-- 3) Range behavior (per-line) default
do
  vim.g.caps = nil
  local ok3, em3 = run_cmd([[1,3call TestCaptureLines()]])
  local caps = vim.g.caps or {}
  ok('range per-line', ok3 and em3 == '' and #caps == 3 and caps[1] == 'one' and caps[2] == 'two' and caps[3] == 'three', em3)
end

-- 4) v:lua.require sugar
do
  package.loaded['mymod'] = { cond = function() vim.g.lua_cond_called = 1 end }
  local ok4, em4 = run_cmd([[call v:lua.require'mymod'.cond()]])
  ok('v:lua.require sugar', ok4 and em4 == '' and (vim.g.lua_cond_called == 1), em4)
end

-- 5) winsaveview/winrestview round-trip
do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'aa', 'bbb', 'cccc' })
  vim.api.nvim_win_set_cursor(0, { 2, 1 })

  local view = vim.fn.winsaveview()
  local ok_shape = (type(view) == 'table') and (view.lnum == 2) and (view.col == 1)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.fn.winrestview(view)

  local pos = vim.api.nvim_win_get_cursor(0)
  ok('winsaveview/winrestview restore cursor', ok_shape and pos[1] == 2 and pos[2] == 1,
    'pos=' .. tostring(pos[1]) .. ',' .. tostring(pos[2]))
end

-- 6) stridx() basic behavior from docs
do
  local colon1 = vim.fn.stridx('a:b:c', ':')
  local colon2 = vim.fn.stridx('a:b:c', ':', colon1 + 1)
  local ok6 = (vim.fn.stridx('An Example', 'Example') == 3)
    and (vim.fn.stridx('Starting point', 'Start') == 0)
    and (vim.fn.stridx('Starting point', 'start') == -1)
    and (colon1 == 1)
    and (colon2 == 3)
  ok('stridx basic/start behavior', ok6, 'colon1=' .. tostring(colon1) .. ', colon2=' .. tostring(colon2))
end

-- 7) stridx() edge cases
do
  local ok7 = (vim.fn.stridx('abc', '', 1) == 1)
    and (vim.fn.stridx('abc', '', 3) == -1)
    and (vim.fn.stridx('abc', 'a', -1) == 0)
    and (vim.fn.stridx('', '') == 0)
    and (vim.fn.stridx('', '', 0) == -1)
  ok('stridx edge cases', ok7, 'edge checks')
end

-- 8) Error unknown function
do
  local ok5, em5 = run_cmd('call Does_Not_Exist()')
  ok('unknown function sets E117', (not ok5) and em5:match('E117'), em5 .. (ok5 and " -> true" or " -> false"))
end

-- 9) Too many args (E118)
do
  local ok6, em6 = run_cmd([[call strlen('a','b')]])
  ok('too many/invalid args E118', (not ok6) and em6:match('E118'), em6)
end

-- 10) stridx() too many args (E118)
do
  local ok7, em7 = run_cmd([[call stridx('a', 'a', 0, 0)]])
  ok('stridx too many args E118', (not ok7) and em7:match('E118'), em7)
end

-- 11) matchstr() docs behavior
do
  local v1 = vim.fn.matchstr('testing', 'ing')
  local v2 = vim.fn.matchstr('testing', 'ing', 2)
  local v3 = vim.fn.matchstr('testing', 'ing', 5)
  local v4 = vim.fn.matchstr('testing', '..', 0, 2)
  local ok11 = (v1 == 'ing')
    and (v2 == 'ing')
    and (v3 == '')
    and (v4 == 'es')
  ok('matchstr basic/start/count behavior', ok11,
    'v1=' .. tostring(v1) .. ', v2=' .. tostring(v2) .. ', v3=' .. tostring(v3) .. ', v4=' .. tostring(v4))
end

-- 12) matchstr() list behavior: return matching item with original type
do
  local l = { 1, '__x' }
  local n = vim.fn.matchstr(l, '\\d')
  local s = vim.fn.matchstr(l, '\\a')
  local ok12 = (n == 1) and (type(n) == 'number') and (s == '__x')
  ok('matchstr list returns original matching item', ok12,
    'n=' .. tostring(n) .. '/' .. type(n) .. ', s=' .. tostring(s))
end

-- 13) matchstr() too many args (E118)
do
  local ok13, em13 = run_cmd([[call matchstr('a', 'a', 0, 0, 0)]])
  ok('matchstr too many args E118', (not ok13) and em13:match('E118'), em13)
end

-- 14) match()/matchstr() list count uses matching items (Vim semantics)
do
  local m1 = vim.fn.match({ 'ab', 'c' }, '.', 0, 1)
  local m2 = vim.fn.match({ 'ab', 'c' }, '.', 0, 2)
  local s2 = vim.fn.matchstr({ 'ab', 'c' }, '.', 0, 2)
  local ok14 = (m1 == 0) and (m2 == 1) and (s2 == 'c')
  ok('match/list count semantics', ok14, 'm1=' .. tostring(m1) .. ', m2=' .. tostring(m2) .. ', s2=' .. tostring(s2))
end

-- 15) matchstrpos() docs behavior
do
  local a = vim.fn.matchstrpos('testing', 'ing')
  local b = vim.fn.matchstrpos('testing', 'ing', 5)
  local c = vim.fn.matchstrpos({ 1, '__x' }, [[\a]])
  local d = vim.fn.matchstrpos({ 'ab', 'c' }, '.', 0, 2)
  local ok15 = (a[1] == 'ing' and a[2] == 4 and a[3] == 7)
    and (b[1] == '' and b[2] == -1 and b[3] == -1)
    and (c[1] == 'x' and c[2] == 1 and c[3] == 2 and c[4] == 3)
    and (d[1] == 'c' and d[2] == 1 and d[3] == 0 and d[4] == 1)
  ok('matchstrpos basic/list/count behavior', ok15, vim.inspect({ a = a, b = b, c = c, d = d }))
end

-- 16) matchstrpos() too many args (E118)
do
  local ok16, em16 = run_cmd([[call matchstrpos('a', 'a', 0, 0, 0)]])
  ok('matchstrpos too many args E118', (not ok16) and em16:match('E118'), em16)
end

-- 17) split() behavior and regex variants
do
  local s1 = vim.fn.split('  aa  bb  ')
  local s2 = vim.fn.split('  aa  bb  ', '', 1)
  local s3 = vim.fn.split('a:b::', ':')
  local s4 = vim.fn.split('a:b::', ':', 1)
  local s5 = vim.fn.split('abc', [[\zs]])
  local s6 = vim.fn.split('abc:def:ghi', [[:\zs]])
  local ok17 = vim.deep_equal(s1, { 'aa', 'bb' })
    and vim.deep_equal(s2, { '', 'aa', 'bb', '' })
    and vim.deep_equal(s3, { 'a', 'b', '' })
    and vim.deep_equal(s4, { 'a', 'b', '', '' })
    and vim.deep_equal(s5, { 'a', 'b', 'c' })
    and vim.deep_equal(s6, { 'abc:', 'def:', 'ghi' })
  ok('split docs/keepempty/\\zs behavior', ok17, vim.inspect({ s1 = s1, s2 = s2, s3 = s3, s4 = s4, s5 = s5, s6 = s6 }))
end

-- 18) split() too many args (E118)
do
  local ok18, em18 = run_cmd([[call split('a:b', ':', 0, 0)]])
  ok('split too many args E118', (not ok18) and em18:match('E118'), em18)
end

-- 19) execute() basic string/list capture behavior
do
  local e1 = vim.fn.execute([[echon "foo"]], '')
  local e2 = vim.fn.execute({ [[echon "foo"]], [[echon "bar"]] }, '')
  local ok19 = (e1 == 'foo') and (e2 == 'foobar')
  ok('execute string/list capture', ok19, vim.inspect({ e1 = e1, e2 = e2 }))
end

-- 20) execute() default {silent} works
do
  local e = vim.fn.execute([[echon "x"]])
  ok('execute default silent arg', e == 'x', tostring(e))
end

-- 21) execute("...", "silent!") suppresses command errors
do
  local ok21, em21 = run_cmd([[call execute('NoSuchExCommand', 'silent!')]])
  ok('execute silent! suppresses errors', ok21 and em21 == '', em21)
end

-- 22) exists('$ENV') and $ENV expression use unified env backend
do
  vim.env.CCVIM_TEST_ENV = 'value-123'
  local ex1 = vim.fn.exists('$CCVIM_TEST_ENV')
  local ok22a, em22a = run_cmd([[let g:env_from_expr = $CCVIM_TEST_ENV]])
  local ok22 = (ex1 == 1) and ok22a and em22a == '' and vim.g.env_from_expr == 'value-123'

  vim.env.CCVIM_TEST_ENV = nil
  local ex2 = vim.fn.exists('$CCVIM_TEST_ENV')
  ok('exists/env backend bridge', ok22 and ex2 == 0, vim.inspect({ ex1 = ex1, ex2 = ex2, em22a = em22a, val = vim.g.env_from_expr }))
end

-- 23) vim.fs.normalize() path rules
do
  local old_home = vim.env.HOME
  vim.env.HOME = '/tmp/ccvim-home'
  vim.env.CCVIM_NORM_ENV = '/tmp/ccvim-env'

  local ok23 = (vim.fs.normalize('./foo/bar') == 'foo/bar')
    and (vim.fs.normalize('foo/../../../bar') == '../../bar')
    and (vim.fs.normalize('/home/jdoe/../../../bar') == '/bar')
    and (vim.fs.normalize('././') == '.')
    and (vim.fs.normalize('/../../') == '/')
    and (vim.fs.normalize('$CCVIM_NORM_ENV/nvim/init.lua') == '/tmp/ccvim-env/nvim/init.lua')
    and (vim.fs.normalize('$CCVIM_NORM_ENV/nvim/init.lua', { expand_env = false }) == '$CCVIM_NORM_ENV/nvim/init.lua')
    and (vim.fs.normalize('~/src/nvim/api/../tui/./tui.c') == '/tmp/ccvim-home/src/nvim/tui/tui.c')

  ok('vim.fs.normalize docs behavior', ok23, vim.inspect({
    a = vim.fs.normalize('./foo/bar'),
    b = vim.fs.normalize('foo/../../../bar'),
    c = vim.fs.normalize('/home/jdoe/../../../bar'),
    d = vim.fs.normalize('$CCVIM_NORM_ENV/nvim/init.lua'),
    e = vim.fs.normalize('~/src/nvim/api/../tui/./tui.c'),
  }))

  vim.env.CCVIM_NORM_ENV = nil
  vim.env.HOME = old_home
end
