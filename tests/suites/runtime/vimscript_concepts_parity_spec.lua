-- luacheck: ignore 631
return {
    id = "runtime.vimscript_concepts_parity",
    description = "Compares representative legacy Vimscript values, expressions, scopes, flow control, functions, commands, and autocommands with Neovim.", -- luacheck: ignore 631
    supports = { lua_editor = false, headless_nvim = false, parity = true },

    run = function(ctx)
        return ctx.assert.eval_block(ctx.backend, "Vimscript concepts", [=[
            local expressions = {
                "123", "0b1111011", "0173", "0x7B", "123.0", "1.23e2",
                "1 + 2", "1 - 2", "- 1", "+ 1", "1 * 2", "1 / 2", "1 % 2",
                "v:true", "v:false", "1 == 1", "1 != 2", "2 > 1", "2 >= 2", "1 < 2", "2 <= 2",
                "'a' < 'B'", "'a' <? 'B'", "'a' <# 'B'",
                [['hi' =~ 'hello']], [['hi' =~# 'hello']], [['hi' =~? 'hello']],
                [['hi' !~ 'hello']], [['hi' !~# 'hello']], [['hi' !~? 'hello']],
                "v:true && v:false", "v:true || v:false", "!v:true", "v:true ? 'yes' : 'no'",
                [['Hello world\n']], [['Let''s go!']], [['Hello ' . 'world']], [['Hello ' .. 'world']],
                "'Hello'[1]", "'Hello'[1:3]", "'Hello'[1:-2]", "'Hello'[-2:]",
                "[1, 2] + [3, 4]", "[1, 2, 3, 4][-1]", "[1, 2, 3, 4][:-2]",
                "{'a': 1, 'b': 2}['a']", "{'a': 1, 'b': 2}.b",
                "call({x -> x * x}, [4])", "call(function('get'), [{'a': 1}, 'b', 3])",
                [['1' + 1]], [['1' .. 1]], [['0xA' + 1]], [['true' ? 1 : 0]],
                [==["Hello world\n"]==], [==[char2nr("Hellö"[4], 1)]==], [==["Hello"[:]]==],
                [==["Hello"[1:]]==], [==["Hello"[:2]]==],
                "[]", "[1, 2, 'Hello', ]", "[[1, 2], 'Hello']", "[1, 2, 3, 4][:]",
                "[1, 2, 3, 4][:2]", "[1, 2, 3, 4][2:]", "{}", "{'a': 1, 'b': 2, }",
                "type(function('type'))", "type({x -> x * x})", "call(function('substitute', ['hello']), ['l', 'L', 'g'])",
                "range(3, 0, -1)", "sort(keys({'pi': 3, 'e': 2}))", "sort(values({'pi': 3, 'e': 2}))",
                "type(1) == v:t_number", "type('x') == v:t_string", "type(function('type')) == v:t_func",
                "type([]) == v:t_list", "type({}) == v:t_dict", "type(1.0) == v:t_float",
                "type(v:true) == v:t_bool", "printf('%d in hexadecimal is %X', 123, 123)",
                "has('nvim')", "has('unix')", "has('win32')", "exists('&mouse')", "exists('*strftime')",
                "exists('##ColorScheme')",
                "type(1)", "type('x')", "type(function('type'))", "type([])", "type({})", "type(1.0)",
                "type(v:true)", "version", "v:version", "v:t_number", "v:t_string", "v:t_func", "v:t_list", "v:t_dict",
                "v:t_float", "v:t_bool",
            }
            local values = {}
            for i = 1, #expressions do
                values[i] = vim.fn.eval(expressions[i])
            end

            vim.cmd([==[
                let g:concept_values = []
                let b:concept_scope = 1
                let w:concept_scope = 2
                let t:concept_scope = 3
                let g:concept_scope = 4
                let s:concept_scope = 5
                let g:concept_script_scope = s:concept_scope
                let @a = 'register'
                let &l:textwidth = 79
                let &l:autoindent = '0'
                let &l:report = '2'
                const concept_constant = 10
                let [concept_x, concept_y] = [1, 2]
                let [concept_mother, concept_father; concept_children] = ['Alice', 'Bob', 'Carol', 'Dennis']
                if v:true
                    let g:concept_if = 'if'
                else
                    let g:concept_if = 'else'
                endif
                for concept_person in ['Alice', 'Bob']
                    call add(g:concept_values, concept_person)
                endfor
                for [concept_dx, concept_dy] in [[1, 0], [0, 1]]
                    call add(g:concept_values, concept_dx + concept_dy)
                endfor
                let concept_count = 0
                while concept_count < 2
                    let concept_count += 1
                endwhile
                try
                    throw 'concept-error'
                catch /concept-error/
                    let g:concept_caught = v:exception
                finally
                    let g:concept_finally = 1
                endtry
                function! ConceptAdd(x, y)
                    return a:x + a:y
                endfunction
                function! s:ConceptScriptFn()
                    return 1
                endfunction
                function! ConceptRange() range
                    let g:concept_range = [a:firstline, a:lastline]
                endfunction
                function! ConceptMakeAdder(x)
                    function! ConceptAdder(n) closure
                        return a:n + a:x
                    endfunction
                    return funcref('ConceptAdder')
                endfunction
                function! ConceptLen() dict
                    return len(self.data)
                endfunction
                let g:concept_dict = {'data': [0, 1, 2], 'len': function('ConceptLen')}
                let g:concept_inline_dict = {'data': [0, 1, 2, 3]}
                function! g:concept_inline_dict.len()
                    return len(self.data)
                endfunction
                let g:concept_add = ConceptAdd(2, 3)
                1,1call ConceptRange()
                let ConceptAddFive = ConceptMakeAdder(5)
                let g:concept_closure = ConceptAddFive(3)
                let g:concept_dict_len = g:concept_dict.len()
                let g:concept_inline_dict_len = g:concept_inline_dict.len()
                command! -nargs=1 ConceptCommand let g:concept_command = <q-args>
                ConceptCommand command-value
                augroup concept_group
                    autocmd!
                    autocmd User ConceptEvent let g:concept_autocmd = 1
                augroup END
                doautocmd User ConceptEvent
                let concept_execute = "let g:concept_executed = 1"
                execute concept_execute
            ]==])
            vim.cmd([==[
                let g:concept_multiline_string = " Hello
                    \ world "
                let g:concept_multiline_list = [1,
                    \ 2]
                let g:concept_multiline_dict = {
                    \ 'a': 1,
                    \ 'b': 2
                \}
            ]==])

            local function command_error(script)
                local ok, err = pcall(vim.cmd, script)
                return { ok, tostring(err):match(".*(E%d+)") }
            end
            local consts = {
                command_error("const g:concept_locked = 1 | let g:concept_locked = 2"),
                command_error("let g:concept_existing = 1 | const g:concept_existing = 2"),
                command_error("const g:concept_locked_list = [1] | call add(g:concept_locked_list, 2)"),
                command_error("const g:concept_locked_dict = {'a': 1} | let g:concept_locked_dict.a = 2"),
                command_error("echo funcref('type')"),
                command_error("echo function('ConceptMissing')"),
                command_error("let l:concept_illegal = 1"),
                command_error("let a:concept_illegal = 1"),
                command_error("echo concept_undefined == concept_other"),
            }
            vim.cmd("let g:concept_unlocked = [1] | const g:concept_unlock_alias = g:concept_unlocked"
                .. " | unlet g:concept_unlock_alias | call add(g:concept_unlocked, 2)")
            consts[#consts + 1] = vim.g.concept_unlocked
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "#!/bin", "body", "!#" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("/^#!/,/!#$/call ConceptRange()")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello", "two", "three", "four" })
            vim.cmd("substitute/hello/Hello/")
            vim.cmd("let concept_delete_line = 3 | execute concept_delete_line .. 'delete'")
            local execute_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
            vim.cmd("normal! ggddGp")
            local normal_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha beta" })
            vim.api.nvim_win_set_cursor(0, { 1, 7 })
            local expansions = { vim.fn.expand('%'), vim.fn.expand('%:p'), vim.fn.expand('<cword>') }
            local function printed(command)
                return string.format("%q", vim.api.nvim_exec2(command, { output = true }).output)
            end
            local printing = {
                printed("echo [1, 2, 'Hello']"), printed("echo {'a': [2, 'x']}"),
                printed("lua vim.print({ 1, 2, 'Hello' })"),
                printed("lua vim.print({ a = 1, b = { 2, 'x' } })"),
                printed([[lua vim.print(vim.fn.eval("[1, 2, 'Hello']"))]]),
                printed([[lua vim.print(vim.fn.eval("{'a': [2, 'x']}"))]]),
                printed([[lua print(1, "x", nil)]]),
                printed("echo []"), printed("echo {}"), printed("lua vim.print({})"),
            }

            return {
                expressions = values,
                scopes = {
                    vim.b.concept_scope, vim.w.concept_scope, vim.t.concept_scope, vim.g.concept_scope,
                    vim.g.concept_script_scope, vim.fn.getreg('a'), vim.bo.textwidth,
                    vim.bo.autoindent, vim.fn.eval("&l:report"),
                },
                unpacked = {
                    vim.fn.eval("concept_x"), vim.fn.eval("concept_y"), vim.fn.eval("concept_mother"),
                    vim.fn.eval("concept_father"), vim.fn.eval("concept_children"),
                },
                flow = {
                    vim.g.concept_if, vim.g.concept_values, vim.fn.eval("concept_count"),
                    vim.g.concept_caught, vim.g.concept_finally,
                },
                functions = {
                    vim.g.concept_add, vim.g.concept_range, vim.g.concept_closure, vim.g.concept_dict_len,
                    vim.g.concept_inline_dict_len,
                },
                commands = { vim.g.concept_command, vim.g.concept_autocmd, vim.g.concept_executed },
                exists = {
                    vim.fn.exists("#User"), vim.fn.exists("#User#ConceptEvent"),
                    vim.fn.exists("#concept_group"), vim.fn.exists(":ConceptCommand"),
                    vim.fn.exists('g:concept_dict["data"]'), vim.fn.exists("*ConceptAdd"),
                },
                consts = consts,
                multiline = {
                    vim.g.concept_multiline_string, vim.g.concept_multiline_list,
                    vim.g.concept_multiline_dict,
                },
                editing = { execute_lines, normal_lines, expansions },
                printing = printing,
            }
        ]=])
    end,
}
