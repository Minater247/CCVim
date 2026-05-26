return {
    id = "runtime.runtime_highlight_parity_benchmark",
    description = "Benchmarks CCVim syntax highlighting parity against Neovim for comparable files under runtime/.",
    benchmark = true,
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local Benchmark = require("vim.tests.runtime_highlight_benchmark")

        local result = Benchmark.run({
            runtime_root = "runtime",
            max_failures = 20,
        })

        print(Benchmark.summary(result))

        if result.failed > 0 then
            local details = {}
            for i = 1, #result.failures do
                local failure = result.failures[i]
                if failure.error then
                    details[#details + 1] = string.format("%s: %s", failure.file, failure.error)
                else
                    details[#details + 1] = string.format(
                        "%s ft=%s mismatch_lines=%d mismatch_cols=%d first_line=%s",
                        failure.file,
                        tostring(failure.filetype),
                        failure.mismatch_lines,
                        failure.mismatch_cols,
                        tostring(failure.first_line)
                    )
                end
            end
            Assert.eq(
                "runtime highlight parity failures:\n" .. table.concat(details, "\n"),
                result.failed,
                0
            )
        end

        Assert.truthy("runtime highlight parity compared at least one file", result.compared > 0, Benchmark.summary(result))
    end,
}
