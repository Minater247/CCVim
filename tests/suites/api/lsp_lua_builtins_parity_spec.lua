local function words(text)
    local out = {}
    for word in text:gmatch("%S+") do out[#out + 1] = word end
    return out
end

local expected = {
    [""] = words([[_G _VERSION arg assert bit collectgarbage coroutine debug dofile error gcinfo getfenv
        getmetatable io ipairs jit load loadfile loadstring lpeg math module newproxy next os package pairs
        pcall print rawequal rawget rawset require select setfenv setmetatable string table tonumber tostring
        type unpack vim xpcall]]),
    bit = words("arshift band bnot bor bswap bxor lshift rol ror rshift tobit tohex"),
    coroutine = words("create isyieldable resume running status wrap yield"),
    debug = words([[debug getfenv gethook getinfo getlocal getmetatable getregistry getupvalue setfenv
        sethook setlocal setmetatable setupvalue traceback upvalueid upvaluejoin]]),
    io = words("close flush input lines open output popen read stderr stdin stdout tmpfile type write"),
    jit = words("arch attach flush off on opt os security status version version_num"),
    ["jit.opt"] = words("start"),
    lpeg = words("B C Carg Cb Cc Cf Cg Cmt Cp Cs Ct P R S V locale match pcode ptree setmaxstack type utfR version"),
    math = words([[abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp huge ldexp log log10 max min
        modf pi pow rad random randomseed sin sinh sqrt tan tanh]]),
    os = words("clock date difftime execute exit getenv remove rename setlocale time tmpname"),
    package = words("config cpath loaded loaders loadlib path preload searchpath seeall"),
    string = words("byte char dump find format gmatch gsub len lower match rep reverse sub upper"),
    table = words("concat foreach foreachi getn insert maxn move remove sort"),
}

return {
    id = "api.lsp_lua_builtins_parity",
    description = "Lists every Lua global and standard-library member exposed by Neovim's LuaJIT runtime.",

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/api/") or "."
        local server = root .. "/lib/luaapi/lsp_lua.lua"
        local result = ctx.assert.eval_block(ctx.backend, "Lua builtin inventory", string.format([[
            vim.cmd("enew!")
            vim.bo.filetype = "lua"
            local bufnr = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_name(bufnr, "/tmp/lua-builtins.lua")
            local lua_lsp = vim.lsp.lua
            if not _G.loadModule then lua_lsp = assert(loadfile(%q))() end
            local id = lua_lsp.start({ bufnr = bufnr })
            assert(vim.wait(500, function()
                local client = vim.lsp.get_client_by_id(id)
                return client and client.initialized
            end, 5))
            local client = vim.lsp.get_client_by_id(id)
            local inventories = {}
            for _, owner in ipairs({ "", "bit", "coroutine", "debug", "io", "jit", "jit.opt", "lpeg",
                "math", "os", "package", "string", "table" }) do
                local line = owner == "" and "" or owner .. "."
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
                local response = assert(client:request_sync("textDocument/completion", {
                    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
                    position = { line = 0, character = #line },
                }, 500, bufnr)).result
                local labels, seen = {}, {}
                for _, item in ipairs(response.items or response) do
                    local label = item.filterText or item.label
                    if not seen[label] then
                        labels[#labels + 1] = label
                        seen[label] = true
                    end
                end
                table.sort(labels)
                inventories[owner] = labels
            end
            client:stop(true)
            return inventories
        ]], server))

        for owner, labels in pairs(expected) do
            table.sort(labels)
            ctx.assert.table_eq((owner == "" and "global" or owner) .. " Lua builtins", result[owner], labels)
        end
    end,
}
