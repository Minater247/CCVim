return {
    id = "runtime.foldexpr_option",
    description = "Ports foldexpr script-local evaluation through sourced Vimscript and public option evaluation.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local script_a = Assert.temp_path(backend, "foldexpr-script-a", ".vim")
        local script_b = Assert.temp_path(backend, "foldexpr-script-b", ".vim")

        Assert.write_file(backend, script_a, [[
let s:base = 40
function s:FoldExpr()
  return s:base + v:lnum
endfunction
setlocal foldmethod=expr
setlocal foldexpr=s:FoldExpr()
let s:base = 42
]])

        Assert.write_file(backend, script_b, [[
let s:tick = 0
function s:FoldExpr()
  let s:tick = s:tick + 1
  return s:tick
endfunction
setlocal foldmethod=expr
setlocal foldexpr=s:FoldExpr()
]])

        local result = Assert.eval_block(backend, "foldexpr option scenarios", string.format([=[
            vim.cmd("enew!")

            vim.cmd("source " .. vim.fn.fnameescape(%q))
            local expr_a = vim.wo.foldexpr
            vim.cmd("let v:lnum = 3 | let g:foldexpr_a_value = eval(&foldexpr)")

            vim.cmd("source " .. vim.fn.fnameescape(%q))
            local expr_b = vim.wo.foldexpr
            vim.cmd(table.concat({
                "let v:lnum = 1",
                "let g:foldexpr_b_value_1 = eval(&foldexpr)",
                "let g:foldexpr_b_value_2 = eval(&foldexpr)",
            }, " | "))

            return {
                expr_a:match("^<SNR>%%d+_FoldExpr%%(%%)$") ~= nil,
                expr_a,
                vim.g.foldexpr_a_value,
                expr_b:match("^<SNR>%%d+_FoldExpr%%(%%)$") ~= nil,
                expr_b,
                vim.g.foldexpr_b_value_1,
                vim.g.foldexpr_b_value_2,
            }
        ]=], script_a, script_b))

        Assert.truthy("foldexpr script A stored as script-local function ref", result[1], result[2])
        Assert.eq("foldexpr script A sees updated script-local state", result[3], 45)
        Assert.truthy("foldexpr script B stored as script-local function ref", result[4], result[5])
        Assert.eq("foldexpr script B eval #1 value", result[6], 1)
        Assert.eq("foldexpr script B keeps persistent script-local state", result[7], 2)
    end,
}
